# ============================================================
# CISC 886 — Outputs
# These values print after `terraform apply` completes
# ============================================================

output "vpc_id" {
  description = "VPC ID — use this in your report architecture diagram"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Public subnet ID (EC2 lives here)"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet ID (EMR lives here)"
  value       = aws_subnet.private.id
}

output "s3_bucket_name" {
  description = "S3 bucket name — use this in all AWS CLI commands"
  value       = aws_s3_bucket.main.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.main.arn
}

output "ec2_public_ip" {
  description = "Elastic IP of chatbot server — open http://<this>:3000 for OpenWebUI"
  value       = aws_eip.chatbot.public_ip
}

output "ec2_ssh_command" {
  description = "SSH command to connect to your chatbot server"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ubuntu@${aws_eip.chatbot.public_ip}"
}

output "openwebui_url" {
  description = "URL to access the chatbot in your browser"
  value       = "http://${aws_eip.chatbot.public_ip}:3000"
}

output "chatbot_sg_id" {
  description = "Security group ID for EC2 — use in EMR launch if needed"
  value       = aws_security_group.ec2_chatbot.id
}

output "emr_master_sg_id" {
  description = "Security group ID for EMR master node"
  value       = aws_security_group.emr_master.id
}

output "emr_worker_sg_id" {
  description = "Security group ID for EMR worker nodes"
  value       = aws_security_group.emr_worker.id
}
