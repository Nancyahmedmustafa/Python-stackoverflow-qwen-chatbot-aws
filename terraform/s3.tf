# ============================================================
# CISC 886 — S3 Bucket
# NetID: 25jdvr
# ============================================================

# ─────────────────────────────────────────────────────────────
# S3 BUCKET
# WHY: S3 is the central data store for the entire pipeline.
#      All data flows through it: raw dataset → Spark output →
#      fine-tuned model files. Using S3 instead of local storage
#      means any AWS service (EMR, EC2, Colab) can access it.
# ─────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "main" {
  bucket        = "${var.netid}-chat-bot-bucket"
  force_destroy = false  # safety: don't delete if bucket has files

  tags = {
    Name    = "${var.netid}-chat-bot-bucket"
    Purpose = "Central storage for chatbot pipeline"
  }
}

# Block all public access — S3 data is private, accessed via IAM
# WHY: Your model weights and training data should never be
#      publicly readable. All access is through AWS credentials.
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning
# WHY: If a Spark job overwrites your processed data with bad
#      output, versioning lets you recover the previous version.
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
# WHY: AWS best practice. Encrypts data at rest automatically.
#      Required for academic/research data handling.
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ─────────────────────────────────────────────────────────────
# S3 FOLDER STRUCTURE
# Creating placeholder objects to represent the folder layout.
# WHY: S3 has no real folders — it's flat. But tools like the
#      AWS Console and EMR treat keys with "/" as folders.
#      Creating these placeholders makes the structure visible.
# ─────────────────────────────────────────────────────────────

resource "aws_s3_object" "folder_raw" {
  bucket  = aws_s3_bucket.main.id
  key     = "raw/"
  content = ""
}

resource "aws_s3_object" "folder_processed_train" {
  bucket  = aws_s3_bucket.main.id
  key     = "processed/train/"
  content = ""
}

resource "aws_s3_object" "folder_processed_val" {
  bucket  = aws_s3_bucket.main.id
  key     = "processed/val/"
  content = ""
}

resource "aws_s3_object" "folder_processed_test" {
  bucket  = aws_s3_bucket.main.id
  key     = "processed/test/"
  content = ""
}

resource "aws_s3_object" "folder_model" {
  bucket  = aws_s3_bucket.main.id
  key     = "model/"
  content = ""
}

resource "aws_s3_object" "folder_scripts" {
  bucket  = aws_s3_bucket.main.id
  key     = "scripts/"
  content = ""
}

resource "aws_s3_object" "folder_logs" {
  bucket  = aws_s3_bucket.main.id
  key     = "logs/"
  content = ""
}

# ─────────────────────────────────────────────────────────────
# IAM ROLE FOR EC2 — allows EC2 to read/write S3
# WHY: Instead of hardcoding AWS keys on the EC2 instance
#      (a security risk), we attach an IAM role so the instance
#      automatically gets S3 access via instance metadata.
# ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "ec2_s3_role" {
  name = "${var.netid}-ec2-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ec2_s3_policy" {
  name = "${var.netid}-ec2-s3-policy"
  role = aws_iam_role.ec2_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.main.arn,
          "${aws_s3_bucket.main.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.netid}-ec2-instance-profile"
  role = aws_iam_role.ec2_s3_role.name
}
