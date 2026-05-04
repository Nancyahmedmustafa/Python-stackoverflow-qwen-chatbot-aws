"""
============================================================
CISC 886 — StackOverflow Dataset Preprocessing
NetID  : 25jdvr
Model  : Qwen2.5-1.5B-Instruct
Engine : Apache Spark on AWS EMR
============================================================
"""

import re
import sys
import logging
from datetime import datetime

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import StringType, IntegerType

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
log = logging.getLogger("25jdvr-preprocess")

NETID          = "25jdvr"
BUCKET         = f"s3://{NETID}-chatbot-bucket"
S3_INPUT       = f"{BUCKET}/raw/Posts.xml"
S3_OUTPUT      = f"{BUCKET}/processed"
RANDOM_SEED    = 42
TRAIN_RATIO    = 0.80
VAL_RATIO      = 0.10
TEST_RATIO     = 0.10

MIN_QUESTION_LEN = 30
MAX_QUESTION_LEN = 2000
MIN_ANSWER_LEN   = 80
MAX_ANSWER_LEN   = 3000
MIN_ANSWER_SCORE = 1
MIN_QUESTION_SCORE = 0
PRIMARY_TAG = "python"


def create_spark_session() -> SparkSession:
    log.info("Creating Spark session...")

    spark = (
        SparkSession.builder
        .appName(f"{NETID}-stackoverflow-preprocess")
        # FIXED: was "6g" — m4.large YARN max is 6144MB total per container
        # 2g executor + 384MB overhead = 2432MB — fits safely
        .config("spark.executor.memory", "2g")
        # FIXED: was "3" — m4.large has 2 vCPUs, using 1 core per executor
        .config("spark.executor.cores", "1")
        .config("spark.executor.memoryOverhead", "384")
        .config("spark.sql.broadcastTimeout", "600")
        .config("spark.sql.autoBroadcastJoinThreshold", "52428800")
        # FIXED: was 200 — reduced for small 2-node cluster
        .config("spark.sql.shuffle.partitions", "20")
        .config("spark.speculation", "true")
        .getOrCreate()
    )

    spark.sparkContext.setLogLevel("WARN")
    log.info(f"Spark version: {spark.version}")
    log.info(f"Executors: {spark.sparkContext.defaultParallelism}")
    return spark


def clean_html(text: str) -> str:
    if text is None:
        return None
    text = re.sub(r'<br\s*/?>', '\n', text, flags=re.IGNORECASE)
    text = re.sub(r'</p>', '\n', text, flags=re.IGNORECASE)
    text = re.sub(r'<li>', '• ', text, flags=re.IGNORECASE)
    text = re.sub(r'<code>(.*?)</code>', r'`\1`', text, flags=re.IGNORECASE | re.DOTALL)
    text = re.sub(r'<pre>(.*?)</pre>',
                  lambda m: '\n```\n' + m.group(1).strip() + '\n```\n',
                  text, flags=re.IGNORECASE | re.DOTALL)
    text = re.sub(r'<[^>]+>', ' ', text)
    html_entities = {
        '&amp;': '&', '&lt;': '<', '&gt;': '>',
        '&quot;': '"', '&#39;': "'", '&nbsp;': ' ',
        '&apos;': "'", '&#x27;': "'", '&#x2F;': '/',
    }
    for entity, char in html_entities.items():
        text = text.replace(entity, char)
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = re.sub(r'[ \t]+', ' ', text)
    return text.strip()


def clean_tags(tags_str: str) -> str:
    if tags_str is None:
        return ""
    return re.sub(r'[<>]', ' ', tags_str).strip().replace('  ', ',').replace(' ', ',')


clean_html_udf  = F.udf(clean_html,  StringType())
clean_tags_udf  = F.udf(clean_tags,  StringType())


def row_count(df) -> int:
    return int(df.agg(F.count(F.lit(1)).alias("n")).first()["n"])


def load_raw_data(spark: SparkSession):
    log.info("Loading raw Posts.xml from S3...")
    log.info(f"Source: {S3_INPUT}")
    df = (
        spark.read
        .format("xml")
        .option("rowTag", "row")
        .option("inferSchema", "true")
        .option("mode", "DROPMALFORMED")
        .load(S3_INPUT)
    )
    total_rows = row_count(df)
    log.info(f"Raw rows loaded: {total_rows:,}")
    return df, total_rows


def separate_questions_answers(df):
    log.info("Separating questions and answers...")
    questions = (
        df
        .filter(F.col("_PostTypeId") == 1)
        .filter(F.col("_AcceptedAnswerId").isNotNull())
        .filter(F.lower(F.col("_Tags")).contains(f"<{PRIMARY_TAG}>"))
        .select(
            F.col("_Id").cast(IntegerType()).alias("q_id"),
            F.col("_AcceptedAnswerId").cast(IntegerType()).alias("accepted_id"),
            F.col("_Title").alias("title"),
            F.col("_Body").alias("q_body"),
            F.col("_Score").cast(IntegerType()).alias("q_score"),
            F.col("_Tags").alias("tags"),
            F.col("_AnswerCount").cast(IntegerType()).alias("answer_count"),
            F.col("_ViewCount").cast(IntegerType()).alias("view_count"),
        )
    )
    answers = (
        df
        .filter(F.col("_PostTypeId") == 2)
        .select(
            F.col("_Id").cast(IntegerType()).alias("a_id"),
            F.col("_Body").alias("a_body"),
            F.col("_Score").cast(IntegerType()).alias("a_score"),
        )
    )
    q_count = row_count(questions)
    log.info(f"Questions with accepted answers + <{PRIMARY_TAG}> tag: {q_count:,}")
    log.info("Answers dataframe prepared.")
    return questions, answers


def join_qa_pairs(questions, answers):
    log.info("Joining questions with accepted answers...")
    paired = questions.join(answers, questions.accepted_id == answers.a_id, how="inner")
    paired_count = row_count(paired)
    log.info(f"Matched Q&A pairs: {paired_count:,}")
    return paired


def clean_text_columns(df):
    log.info("Cleaning HTML from text columns...")
    df = df.withColumn("instruction", clean_html_udf(F.col("title")))
    df = df.withColumn("response",    clean_html_udf(F.col("a_body")))
    df = df.withColumn("tags_clean",  clean_tags_udf(F.col("tags")))
    return df


def apply_quality_filters(df):
    log.info("Applying quality filters...")
    count_before = row_count(df)
    log.info(f"Before filtering: {count_before:,} pairs")

    df = df.filter(F.col("instruction").isNotNull() & F.col("response").isNotNull())
    df = df.filter(
        ~F.col("instruction").contains("[closed]") &
        ~F.col("instruction").contains("[duplicate]") &
        ~F.col("instruction").contains("[on hold]")
    )
    df = df.filter(
        (F.length("instruction") >= MIN_QUESTION_LEN) &
        (F.length("instruction") <= MAX_QUESTION_LEN)
    )
    df = df.filter(
        (F.length("response") >= MIN_ANSWER_LEN) &
        (F.length("response") <= MAX_ANSWER_LEN)
    )
    df = df.filter(F.col("a_score") >= MIN_ANSWER_SCORE)
    df = df.filter(F.col("q_score") >= MIN_QUESTION_SCORE)
    df = df.filter(
        (F.length(F.regexp_replace("instruction", r'[^\x00-\x7F]', '')) /
         F.length("instruction")) >= 0.85
    )
    df = df.dropDuplicates(["instruction"])

    count_after = row_count(df)
    retention = (count_after / count_before) * 100
    log.info(f"Retention rate: {retention:.1f}%  ({count_after:,} / {count_before:,})")
    return df


def add_computed_columns(df):
    log.info("Adding computed columns...")
    df = df.withColumn("q_length", F.length("instruction"))
    df = df.withColumn("a_length", F.length("response"))

    SYSTEM_PROMPT = (
        "You are a helpful tech support assistant specializing in "
        "programming and software development. Provide clear, accurate, "
        "and concise answers with code examples when appropriate."
    )
    df = df.withColumn(
        "text",
        F.concat(
            F.lit("<|im_start|>system\n"),
            F.lit(SYSTEM_PROMPT),
            F.lit("<|im_end|>\n<|im_start|>user\n"),
            F.col("instruction"),
            F.lit("<|im_end|>\n<|im_start|>assistant\n"),
            F.col("response"),
            F.lit("<|im_end|>")
        )
    )
    return df


def print_eda_stats(df, label: str = ""):
    log.info(f"\n{'='*50}")
    log.info(f"EDA STATS {label}")
    log.info(f"{'='*50}")
    total = row_count(df)
    log.info(f"Total samples: {total:,}")
    log.info("\n--- Question Score Distribution ---")
    df.select(
        F.min("q_score").alias("min"),
        F.mean("q_score").alias("mean"),
        F.percentile_approx("q_score", 0.50).alias("median"),
        F.percentile_approx("q_score", 0.75).alias("p75"),
        F.percentile_approx("q_score", 0.90).alias("p90"),
        F.max("q_score").alias("max"),
    ).show()
    log.info("\n--- Answer Length Distribution (chars) ---")
    df.select(
        F.min("a_length").alias("min"),
        F.mean("a_length").alias("mean"),
        F.percentile_approx("a_length", 0.50).alias("median"),
        F.percentile_approx("a_length", 0.75).alias("p75"),
        F.percentile_approx("a_length", 0.90).alias("p90"),
        F.max("a_length").alias("max"),
    ).show()
    log.info("\n--- Top 20 Tags ---")
    df.select(F.explode(F.split("tags_clean", ",")).alias("tag")) \
      .filter(F.col("tag") != "") \
      .groupBy("tag").agg(F.count(F.lit(1)).alias("count")) \
      .orderBy(F.desc("count")).limit(20).show()
    log.info(f"{'='*50}\n")


def split_and_save(df, spark: SparkSession):
    log.info("Splitting dataset...")
    train, val, test = df.randomSplit([TRAIN_RATIO, VAL_RATIO, TEST_RATIO], seed=RANDOM_SEED)
    output_cols = ["instruction", "response", "tags_clean",
                   "q_score", "a_score", "q_length", "a_length", "text"]
    train = train.select(output_cols)
    val   = val.select(output_cols)
    test  = test.select(output_cols)
    split_with_label = (
        train.withColumn("split", F.lit("train"))
        .unionByName(val.withColumn("split", F.lit("val")))
        .unionByName(test.withColumn("split", F.lit("test")))
    )
    split_counts = {
        r["split"]: int(r["n"])
        for r in split_with_label.groupBy("split").agg(F.count(F.lit(1)).alias("n")).collect()
    }
    train_count = split_counts.get("train", 0)
    val_count = split_counts.get("val", 0)
    test_count = split_counts.get("test", 0)
    log.info(f"Split counts — Train: {train_count:,} | Val: {val_count:,} | Test: {test_count:,}")

    log.info("Saving train split to S3...")
    train.repartition(20).write.mode("overwrite").parquet(f"{S3_OUTPUT}/train/")
    log.info("Saving val split to S3...")
    val.repartition(5).write.mode("overwrite").parquet(f"{S3_OUTPUT}/val/")
    log.info("Saving test split to S3...")
    test.repartition(5).write.mode("overwrite").parquet(f"{S3_OUTPUT}/test/")
    log.info("Saving 100-row sample for inspection...")
    (
        train.limit(100).coalesce(1)
        .write.mode("overwrite")
        .json(f"{S3_OUTPUT}/sample/sample_100.json")
    )
    return train_count, val_count, test_count


def main():
    start_time = datetime.now()
    log.info("=" * 60)
    log.info("25jdvr StackOverflow Preprocessing Pipeline")
    log.info(f"Start: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")
    log.info("=" * 60)

    spark = create_spark_session()
    df, total_raw = load_raw_data(spark)
    questions, answers = separate_questions_answers(df)
    paired = join_qa_pairs(questions, answers)
    cleaned = clean_text_columns(paired)
    filtered = apply_quality_filters(cleaned)
    final = add_computed_columns(filtered)
    print_eda_stats(final, label="FINAL FILTERED DATASET")
    train_count, val_count, test_count = split_and_save(final, spark)

    end_time = datetime.now()
    duration = end_time - start_time
    log.info("\n" + "=" * 60)
    log.info("PIPELINE COMPLETE")
    log.info("=" * 60)
    log.info(f"Raw posts loaded    : {total_raw:>12,}")
    log.info(f"Train samples       : {train_count:>12,}")
    log.info(f"Val samples         : {val_count:>12,}")
    log.info(f"Test samples        : {test_count:>12,}")
    log.info(f"Total output        : {train_count+val_count+test_count:>12,}")
    log.info(f"Duration            : {str(duration).split('.')[0]}")
    log.info(f"Output S3 path      : {S3_OUTPUT}/")
    log.info("=" * 60)
    log.info(">>> TERMINATE THE EMR CLUSTER NOW! <<<")
    log.info("=" * 60)

    spark.stop()


if __name__ == "__main__":
    main()
