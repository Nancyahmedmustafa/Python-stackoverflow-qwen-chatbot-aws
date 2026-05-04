#!/bin/bash
set -euxo pipefail

LOG=/tmp/bootstrap-debug.log
exec > >(tee -a "$LOG") 2>&1

trap 'aws s3 cp "$LOG" s3://25jdvr-chatbot-bucket/logs/bootstrap-debug-$(hostname)-$(date +%s).log || true' EXIT

echo "Bootstrap started at: $(date)"
hostname
df -h
aws --version

echo "Checking input file..."
aws s3 ls s3://25jdvr-chatbot-bucket/raw/stackoverflow-Posts.7z

echo "Enabling EPEL and installing 7zip..."
sudo amazon-linux-extras install epel -y
sudo yum clean all
sudo yum install -y p7zip p7zip-plugins

echo "Downloading archive..."
cd /mnt
aws s3 cp s3://25jdvr-chatbot-bucket/raw/stackoverflow-Posts.7z .

echo "Extracting..."
7za x stackoverflow-Posts.7z -o/mnt1

echo "Uploading extracted XML..."
aws s3 cp /mnt1/Posts.xml s3://25jdvr-chatbot-bucket/raw/Posts.xml

echo "Bootstrap complete at: $(date)"