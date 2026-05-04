# ============================================================
# CISC 886 — Security Groups
# NetID: 25jdvr
# ============================================================

# ─────────────────────────────────────────────────────────────
# SECURITY GROUP: EC2 Chatbot Server
# WHY: Principle of least privilege — only open the exact ports
#      the chatbot needs. SSH locked to YOUR IP only (not 0.0.0.0/0)
#      to prevent brute-force attacks on your server.
# ─────────────────────────────────────────────────────────────
resource "aws_security_group" "ec2_chatbot" {
  name        = "${var.netid}-chatbot-sg"
  description = "Security group for 25jdvr chatbot EC2 instance"
  vpc_id      = aws_vpc.main.id

  # SSH — YOUR IP ONLY (not public!)
  # WHY: SSH with key is already secure but exposing it to 0.0.0.0/0
  #      still invites automated scanners. Restrict to your IP.
  ingress {
    description = "SSH from your machine only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  # OpenWebUI — port 3000 open to anyone
  # WHY: This is the chat interface your professor will demo.
  #      Must be publicly accessible.
  ingress {
    description = "OpenWebUI browser chat interface"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ollama API — port 11434 open to anyone
  # WHY: OpenWebUI running in Docker calls Ollama.
  #      Also needed if you want to test the API from your laptop.
  ingress {
    description = "Ollama inference API"
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic allowed
  # WHY: EC2 needs to pull Docker images, download packages,
  #      and communicate with S3.
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.netid}-chatbot-sg"
  }
}

# ─────────────────────────────────────────────────────────────
# SECURITY GROUP: EMR Master Node
# WHY: The master node needs SSH from you (to submit jobs)
#      and must communicate freely with its worker nodes.
# ─────────────────────────────────────────────────────────────
resource "aws_security_group" "emr_master" {
  name        = "${var.netid}-emr-master-sg"
  description = "Security group for 25jdvr EMR master node"
  vpc_id      = aws_vpc.main.id

  # SSH from your IP only
  ingress {
    description = "SSH to EMR master from your machine"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  # HTTPS (Spark UI) from your IP — for monitoring the job
  ingress {
    description = "Spark Web UI"
    from_port   = 18080
    to_port     = 18080
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  # All outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.netid}-emr-master-sg"
  }
}

# ─────────────────────────────────────────────────────────────
# SECURITY GROUP: EMR Worker (Core) Nodes
# WHY: Workers only need to talk to the master and each other.
#      No public access needed — they're in the private subnet.
# ─────────────────────────────────────────────────────────────
resource "aws_security_group" "emr_worker" {
  name        = "${var.netid}-emr-worker-sg"
  description = "Security group for 25jdvr EMR worker nodes"
  vpc_id      = aws_vpc.main.id

  # All inbound from within the VPC (master ↔ workers)
  ingress {
    description = "Internal VPC communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # All outbound (to reach S3 via VPC endpoint, pull packages)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.netid}-emr-worker-sg"
  }
}
