# ============================================================
# CISC 886 — Variables
# ============================================================

variable "netid" {
  description = "Queen's University NetID — used as prefix for all resource names"
  type        = string
  default     = "25jdvr"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. /16 gives 65,536 IPs"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for public subnet (EC2 chatbot server)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR for private subnet (EMR cluster)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "your_ip" {
  description = "YOUR local machine public IP in CIDR form (e.g. 203.0.113.5/32). Used to restrict SSH access."
  type        = string
  # Find your IP: https://whatismyip.com — then add /32
  # Example: default = "203.0.113.5/32"
}

variable "ec2_instance_type" {
  description = "EC2 instance type for chatbot server"
  type        = string
  default     = "m5.xlarge"   
  # Budget alternative (CPU only): "c5.2xlarge"
}

variable "ec2_ami" {
  description = "Ubuntu 22.04 LTS AMI for us-east-1"
  type        = string
  default     = "ami-0c7217cdde317cfec"   # Ubuntu 22.04 LTS, us-east-1 (2024)
}

variable "key_pair_name" {
  description = "Name of the AWS key pair for SSH access to EC2"
  type        = string
  # Create this in AWS Console → EC2 → Key Pairs → Create key pair
  # Then set: default = "25jdvr-keypair"
}

variable "emr_instance_type" {
  description = "EC2 instance type for EMR cluster nodes"
  type        = string
  default     = "m5.xlarge"  # 4 vCPUs, 16GB RAM — good Spark worker
}

variable "emr_worker_count" {
  description = "Number of EMR worker (core) nodes"
  type        = number
  default     = 2  # 1 master + 2 workers = 3 nodes total
}
