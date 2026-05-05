# CISC 886 StackOverflow Qwen2.5 Chatbot on AWS

End-to-end project repository for building a StackOverflow-trained chatbot using AWS infrastructure, PySpark preprocessing on EMR, Qwen2.5-7B-Instruct fine-tuning, and deployment through Ollama/OpenWebUI on EC2.

**Model:** `Qwen/Qwen2.5-7B-Instruct`  
**AWS Region:** `us-east-1`  
**Primary Dataset:** `stackoverflow-Posts.7z`

---

## Repository Contents

Your repository should include all implementation files needed to reproduce the project.

```text
cisc886-chatbot/
├── README.md
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── security_groups.tf
│   ├── s3.tf
│   ├── ec2.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── terraform.tfvars              # local only; do not commit secrets
├── scripts/
│   ├── bootstrap.sh
│   └── preprocess.py                 # PySpark preprocessing script
├── notebooks/
│   └── fine_tuning.ipynb             # fine-tuning notebook
```

> Do not commit AWS credentials, private keys, `.pem` files, large datasets, model weights, or Terraform state files.

---

## Prerequisites

### Accounts

- AWS account with billing enabled.
- IAM user for project work, not the AWS root user.
- Hugging Face account or access to download `Qwen/Qwen2.5-7B-Instruct`, if required.

### Local Tools

Install the following tools on your laptop:

- Terraform `>= 1.6.0`
- AWS CLI v2
- Python 3.10+
- `pip`
- `7zip` or `p7zip`
- Git
- SSH client

### AWS Region

This project uses:

```bash
us-east-1
```

### AWS Services Used

- Amazon S3
- Amazon EC2
- Amazon EMR
- Amazon VPC
- IAM
- NAT Gateway
- Elastic IP
- Security Groups

---

## AWS Account Setup

### 1. Create an AWS Account

1. Go to AWS and create an account.
2. Use your university email if required.
3. Select **Basic Support – Free**.
4. Enable MFA immediately for the root user.

### 2. Create an IAM Admin User

Create a project IAM user, for example:

```text
25jdvr-admin
```

Attach this AWS managed policy:

```text
AdministratorAccess
```

Use this IAM user for all project work instead of the root account.

### 3. Create AWS Access Keys

In AWS Console:

```text
IAM → Users → 25jdvr-admin → Security credentials → Access keys → Create access key
```

Choose:

```text
Command Line Interface (CLI)
```

Download the `.csv` file containing the access key and secret key.

### 4. Configure AWS CLI

```bash
aws configure
```

Use:

```text
AWS Access Key ID:     <your-access-key>
AWS Secret Access Key: <your-secret-access-key>
Default region name:  us-east-1
Default output format: json
```

Verify:

```bash
aws sts get-caller-identity
```

---

## SSH Key Pair Setup

Create an EC2 key pair in AWS:

```text
EC2 → Key Pairs → Create key pair
```

Use:

```text
Name: 25jdvr-keypair
Type: RSA
Format: .pem
```

Move the key locally.

### macOS/Linux

```bash
mkdir -p ~/.ssh
mv ~/Downloads/25jdvr-keypair.pem ~/.ssh/
chmod 400 ~/.ssh/25jdvr-keypair.pem
```

### Windows PowerShell

```powershell
mkdir C:\Users\YourName\.ssh
Move-Item 25jdvr-keypair.pem C:\Users\YourName\.ssh\
```

---

## Dataset

The dataset file should already exist locally:

```text
stackoverflow-Posts.7z
```

Do **not** extract it locally. Upload the compressed `.7z` file directly to S3. The EMR bootstrap script extracts it in the cloud.

Find the dataset locally:

### macOS/Linux

```bash
find ~ -name "*.7z" 2>/dev/null
```

### Windows PowerShell

```powershell
Get-ChildItem -Path $HOME -Recurse -Filter "*.7z" -ErrorAction SilentlyContinue
```

---

## Terraform Infrastructure Setup

### 1. Clone the Repository

```bash
git clone <your-repository-url>
cd cisc886-chatbot
```

### 2. Enter the Terraform Directory

```bash
cd terraform
```

### 3. Create `terraform.tfvars`

```bash
cp terraform.tfvars.example terraform.tfvars
```

Find your public IP:

```bash
curl ifconfig.me
```

Edit `terraform.tfvars`:

```hcl
your_ip       = "203.15.42.88/32"
key_pair_name = "25jdvr-keypair"
```

Replace `203.15.42.88/32` with your real public IP followed by `/32`.

### 4. Initialize Terraform

```bash
terraform init
```

### 5. Preview Infrastructure

```bash
terraform plan
```

Expected resources include:

- VPC
- Public and private subnets
- Internet Gateway
- NAT Gateway
- Route tables
- VPC S3 endpoint
- Security groups
- S3 bucket
- EC2 inference instance
- Elastic IP
- IAM role, policy, and instance profile

### 6. Apply Terraform

```bash
terraform apply
```

Type:

```text
yes
```

Expected output:

```text
ec2_public_ip   = "54.82.xxx.xxx"
ec2_ssh_command = "ssh -i ~/.ssh/25jdvr-keypair.pem ubuntu@54.82.xxx.xxx"
openwebui_url   = "http://54.82.xxx.xxx:3000"
s3_bucket_name  = "25jdvr-chatbot-bucket"
```

Save these outputs because they are needed later.

---

## S3 Uploads

Set the bucket name:

```bash
export BUCKET_NAME=25jdvr-chatbot-bucket
```

For Windows PowerShell:

```powershell
$env:BUCKET_NAME="25jdvr-chatbot-bucket"
```

### 1. Upload the Raw Dataset

macOS/Linux:

```bash
aws s3 cp /path/to/stackoverflow-Posts.7z \
  s3://$BUCKET_NAME/raw/stackoverflow-Posts.7z \
  --region us-east-1
```

Windows PowerShell:

```powershell
aws s3 cp "C:\Users\yourname\Downloads\stackoverflow-Posts.7z" `
  s3://$env:BUCKET_NAME/raw/stackoverflow-Posts.7z `
  --region us-east-1
```

### 2. Create `scripts/bootstrap.sh`

```bash
#!/bin/bash
# EMR Bootstrap Action
# Extracts StackOverflow .7z dataset to Posts.xml and uploads it back to S3.

set -e
exec > /var/log/bootstrap.log 2>&1

echo "Bootstrap started at: $(date)"

sudo yum install -y p7zip

echo "Downloading .7z from S3..."
aws s3 cp s3://25jdvr-chatbot-bucket/raw/stackoverflow-Posts.7z /tmp/

echo "Extracting .7z..."
cd /tmp
7za x stackoverflow-Posts.7z

echo "Uploading Posts.xml to S3..."
aws s3 cp /tmp/Posts.xml s3://25jdvr-chatbot-bucket/raw/Posts.xml

echo "Bootstrap complete at: $(date)"
```

Upload it:

```bash
aws s3 cp scripts/bootstrap.sh s3://$BUCKET_NAME/scripts/bootstrap.sh
```

### 3. Upload the PySpark Script

```bash
aws s3 cp scripts/preprocess.py s3://$BUCKET_NAME/scripts/preprocess.py
```

### 4. Download and Upload the Base Model

Install Hugging Face CLI:

```bash
pip install huggingface_hub
```

Download Qwen2.5:

```bash
huggingface-cli download Qwen/Qwen2.5-7B-Instruct \
  --local-dir ./Qwen2.5-7B-instruct/ \
  --include "*.safetensors" "*.json" "tokenizer*"
```

Upload to S3:

```bash
aws s3 sync ./Qwen2.5-7B-instruct/ \
  s3://$BUCKET_NAME/model/qwen2.5-base/ \
  --region us-east-1
```

### 5. Verify Uploads

```bash
aws s3 ls s3://$BUCKET_NAME/raw/
aws s3 ls s3://$BUCKET_NAME/scripts/
aws s3 ls s3://$BUCKET_NAME/model/qwen2.5-base/
```

---

## PySpark Preprocessing on EMR

### 1. Create an EMR Cluster

In AWS Console:

```text
EMR → Create cluster
```

Use these settings:

```text
Cluster name:         25jdvr-spark-cluster
Release:              emr-6.15.0
Applications:         Spark 3.5
Master instance:      m5.xlarge
Core instance type:   m5.xlarge
Core instances:       2
Log URI:              s3://25jdvr-chatbot-bucket/logs/
EC2 key pair:         25jdvr-keypair
VPC:                  25jdvr-vpc
Subnet:               25jdvr-private-subnet
Master SG:            25jdvr-emr-master-sg
Core SG:              25jdvr-emr-worker-sg
```

Add bootstrap action:

```text
Name:   25jdvr-extract-dataset
Script: s3://25jdvr-chatbot-bucket/scripts/bootstrap.sh
```

Create the cluster and wait until the cluster status is:

```text
Waiting
```

### 2. Submit the Spark Step

In AWS Console:

```text
EMR → Cluster → Steps → Add step
```

Use:

```text
Type:                 Spark application
Name:                 25jdvr-preprocess
Deploy mode:          Cluster
Application location: s3://25jdvr-chatbot-bucket/scripts/preprocess.py
Spark-submit options: --packages com.databricks:spark-xml_2.12:0.17.0 --conf spark.executor.memory=6g
Action on failure:    Continue
```

The preprocessing job reads:

```text
s3://25jdvr-chatbot-bucket/raw/Posts.xml
```

and writes processed datasets to:

```text
s3://25jdvr-chatbot-bucket/processed/train/
s3://25jdvr-chatbot-bucket/processed/val/
s3://25jdvr-chatbot-bucket/processed/test/
s3://25jdvr-chatbot-bucket/processed/sample/sample_100.json
```

### 3. Terminate EMR Cluster

Terminate the EMR cluster immediately after preprocessing completes.

AWS CLI:

```bash
aws emr terminate-clusters --cluster-ids j-XXXXXXXXXX
```

---

## Verify Processed Data

List output folders:

```bash
aws s3 ls s3://$BUCKET_NAME/processed/train/ | head -20
aws s3 ls s3://$BUCKET_NAME/processed/val/
aws s3 ls s3://$BUCKET_NAME/processed/test/
```

Download the sample:

```bash
aws s3 cp s3://$BUCKET_NAME/processed/sample/sample_100.json ./sample_100.json
```

Inspect several examples:

```bash
python3 -c "
import json

with open('sample_100.json') as f:
    for i, line in enumerate(f):
        if i < 3:
            row = json.loads(line)
            print(f'INSTRUCTION: {row[\"instruction\"][:100]}')
            print(f'RESPONSE: {row[\"response\"][:200]}')
            print('---')
"
```

---

## Fine-Tuning

The fine-tuning notebook should be included in:

```text
notebooks/fine_tuning.ipynb
```

A typical workflow is:

1. Load processed train/validation data from S3.
2. Load `Qwen/Qwen2.5-7B-Instruct`.
3. Tokenize prompt-response records.
4. Fine-tune using the notebook.
5. Save the resulting model artifacts.
6. Upload model artifacts to S3.

Example upload command:

```bash
aws s3 sync ./fine_tuned_model/ \
  s3://$BUCKET_NAME/model/qwen2.5-finetuned/ \
  --region us-east-1
```

---

## EC2 Inference Server

After Terraform completes, use the SSH command from Terraform output:

```bash
ssh -i ~/.ssh/25jdvr-keypair.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Check setup logs:

```bash
cat /var/log/user-data.log
```

Confirm Ollama is running:

```bash
ollama list
```

Confirm OpenWebUI is running:

```bash
docker ps
```

If using a GPU instance such as `g4dn.xlarge`, verify GPU access:

```bash
nvidia-smi
```

Open OpenWebUI:

```text
http://YOUR_EC2_PUBLIC_IP:3000
```

Create an admin account and connect the deployed Ollama model.

---

## Optional: Stop EC2 to Reduce Cost

When not using the inference server:

```bash
aws ec2 stop-instances --instance-ids i-XXXXXXXXXX
```

Start it again later:

```bash
aws ec2 start-instances --instance-ids i-XXXXXXXXXX
```

---

## Cost Summary

Approximate AWS costs are shown below. Actual spend depends on runtime, region pricing changes, storage duration, data transfer, and whether resources are stopped or terminated.

| Service | Usage | Approximate Cost |
|---|---:|---:|
| EC2 `g4dn.xlarge` | Inference server | `$0.53/hour` |
| EMR `m5.xlarge x3` | Spark preprocessing cluster | `$0.57/hour` |
| S3 | Around 35 GB storage for compressed dataset and outputs | `~$0.80/month` |
| NAT Gateway | Network access for private subnet resources | `~$0.045/hour` |
| Data Transfer In | Upload 17 GB `.7z` dataset to S3 | `$0` |
| Total EMR Run | Around 3.5 hours including bootstrap | `~$2.00` |

> Important: NAT Gateway and EC2 can continue charging while running. Terminate the EMR cluster after preprocessing and stop EC2 when not in use.

---

## Cleanup

### Stop EC2

```bash
aws ec2 stop-instances --instance-ids i-XXXXXXXXXX
```

### Delete EMR Cluster

```bash
aws emr terminate-clusters --cluster-ids j-XXXXXXXXXX
```

### Destroy Terraform Infrastructure

From the `terraform/` directory:

```bash
terraform destroy
```

Type:

```text
yes
```

### Remove S3 Objects Manually if Needed

If Terraform cannot delete a non-empty S3 bucket:

```bash
aws s3 rm s3://$BUCKET_NAME --recursive
terraform destroy
```

---


