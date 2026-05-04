# ============================================================
# CISC 886 — Cloud-based Chatbot Project
# NetID: 25jdvr
# Terraform: Main Infrastructure (VPC + Networking)
# ============================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "CISC886-Chatbot"
      NetID     = "25jdvr"
      ManagedBy = "Terraform"
    }
  }
}

# ─────────────────────────────────────────────────────────────
# VPC
# WHY: The project requires a custom VPC (not default AWS VPC).
#      A /16 CIDR gives us 65,536 IPs — plenty for all subnets,
#      EMR nodes, and EC2 instances we will create.
# ─────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr          # 10.0.0.0/16
  enable_dns_support   = true                  # needed for S3 endpoint & EMR
  enable_dns_hostnames = true                  # needed so EC2 gets public DNS

  tags = {
    Name = "${var.netid}-vpc"
  }
}

# ─────────────────────────────────────────────────────────────
# PUBLIC SUBNET — for EC2 chatbot server
# WHY: EC2 must be publicly accessible so users can reach
#      OpenWebUI on port 3000. A public subnet with an IGW
#      route gives the instance a routable public IP.
# ─────────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr   # 10.0.1.0/24
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true                     # auto-assign public IP to EC2

  tags = {
    Name = "${var.netid}-public-subnet"
    Tier = "Public"
  }
}

# ─────────────────────────────────────────────────────────────
# PRIVATE SUBNET — for EMR cluster nodes
# WHY: EMR workers should NOT be directly reachable from the
#      internet. They only need outbound access (to pull from
#      S3). Keeping them in a private subnet is a security
#      best practice and reduces attack surface.
# ─────────────────────────────────────────────────────────────
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr  # 10.0.2.0/24
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "${var.netid}-private-subnet"
    Tier = "Private"
  }
}

# ─────────────────────────────────────────────────────────────
# INTERNET GATEWAY
# WHY: Without an IGW, nothing in the VPC can reach the
#      internet. The IGW is the bridge between our VPC and
#      the public internet — required for the EC2 instance
#      to be reachable and for pulling Docker images.
# ─────────────────────────────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.netid}-igw"
  }
}

# ─────────────────────────────────────────────────────────────
# NAT GATEWAY — for private subnet outbound access
# WHY: EMR nodes in the private subnet need to download
#      packages and reach S3. They cannot use the IGW directly
#      (they have no public IPs). The NAT Gateway sits in the
#      public subnet and forwards their outbound traffic.
# ─────────────────────────────────────────────────────────────
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.netid}-nat-eip"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id  # NAT GW must live in PUBLIC subnet

  tags = {
    Name = "${var.netid}-nat-gw"
  }

  depends_on = [aws_internet_gateway.igw]
}

# ─────────────────────────────────────────────────────────────
# ROUTE TABLES
# ─────────────────────────────────────────────────────────────

# Public route table: 0.0.0.0/0 → IGW (all outbound → internet)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.netid}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private route table: 0.0.0.0/0 → NAT GW (outbound through NAT)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.netid}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ─────────────────────────────────────────────────────────────
# VPC ENDPOINT FOR S3
# WHY: Without this, traffic from EMR → S3 goes out to the
#      internet (costly and slow). A Gateway Endpoint keeps all
#      S3 traffic inside AWS's private network — free of charge
#      and significantly faster for large data transfers.
# ─────────────────────────────────────────────────────────────
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.public.id,
    aws_route_table.private.id
  ]

  tags = {
    Name = "${var.netid}-s3-endpoint"
  }
}
