# ============================================================
# CISC 886 — EC2 Chatbot Server
# NetID: 25jdvr
# Model: Qwen2.5-1.5B-Instruct
# ============================================================

# ─────────────────────────────────────────────────────────────
# EC2 INSTANCE — Chatbot inference server
# WHY m5.xlarge:
#   - Has NVIDIA T4 GPU with 16GB VRAM
#   - Qwen2.5-1.5B Q4_K_M GGUF = ~1.1GB — fits easily
#   - GPU gives ~10x faster inference than CPU
#   - Cost: ~$0.526/hr (stop when not in use!)
#
# Budget alternative: c5.2xlarge (8 vCPUs, 16GB RAM, CPU only)
#   - Slower but cheaper ($0.34/hr)
#   - Use Q4_K_M quantization — runs fine on CPU
# ─────────────────────────────────────────────────────────────
resource "aws_instance" "chatbot_server" {
  ami                    = var.ec2_ami
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.ec2_chatbot.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # Root volume — 100GB for OS + Docker + model files
  # WHY 100GB: Qwen2.5-1.5B GGUF ~1.1GB + Docker images ~5GB
  #            + Ubuntu + packages. 100GB gives comfortable room.
  root_block_device {
    volume_type           = "gp3"   # better performance/price than gp2
    volume_size           = 100
    delete_on_termination = true
    encrypted             = true
  }

  # User data script — runs ONCE on first boot automatically
  # This installs everything so you don't have to SSH and do it manually
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    exec > /var/log/user-data.log 2>&1

    echo "=== 25jdvr Chatbot Server Setup ==="
    echo "Started at: $(date)"

    # Update system
    apt-get update -y
    apt-get upgrade -y

    # Install essential tools
    apt-get install -y \
      curl wget git unzip \
      docker.io \
      awscli \
      htop nvtop

    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu

    # Install NVIDIA drivers (for g4dn instances)
    apt-get install -y ubuntu-drivers-common
    ubuntu-drivers autoinstall || true  # 'true' so script continues even if no GPU

    # Install Ollama
    curl -fsSL https://ollama.ai/install.sh | sh
    systemctl enable ollama
    systemctl start ollama

    # Wait for Ollama to be ready
    sleep 10

    # Pull Qwen2.5-1.5B directly from Ollama (easiest path)
    # We will ALSO load the fine-tuned version later via Modelfile
    ollama pull qwen2.5:1.5b || true

    # Run OpenWebUI via Docker (auto-restarts on reboot)
    docker run -d \
      --name openwebui \
      --restart always \
      -p 3000:8080 \
      --add-host=host.docker.internal:host-gateway \
      -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
      ghcr.io/open-webui/open-webui:main

    echo "=== Setup complete at: $(date) ==="
    echo "OpenWebUI will be at: http://$(curl -s ifconfig.me):3000"
  EOF
  )

  tags = {
    Name    = "${var.netid}-chatbot-server"
    Purpose = "Qwen2.5 inference + OpenWebUI"
  }
}

# ─────────────────────────────────────────────────────────────
# ELASTIC IP for EC2
# WHY: By default, EC2 public IPs change every time you
#      stop/start the instance. An Elastic IP is a fixed
#      public IP that stays the same — so your URLs don't break.
# ─────────────────────────────────────────────────────────────
resource "aws_eip" "chatbot" {
  instance = aws_instance.chatbot_server.id
  domain   = "vpc"

  tags = {
    Name = "${var.netid}-chatbot-eip"
  }

  depends_on = [aws_internet_gateway.igw]
}
