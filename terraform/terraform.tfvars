# ============================================================
# CISC 886 — Your personal variable values
# RENAME this file to: terraform.tfvars
# FILL IN: your_ip and key_pair_name before running terraform
# ============================================================

netid              = "25jdvr"
aws_region         = "us-east-1"
vpc_cidr           = "10.0.0.0/16"
public_subnet_cidr = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"

# YOUR public IP — find it at https://whatismyip.com
# Format: "x.x.x.x/32"  (the /32 means just your single IP)
your_ip = "15.161.33.93/32"

# The name of the key pair you created in AWS Console
# Example: "25jdvr-keypair"
key_pair_name = "25jdvr-keypair"


ec2_instance_type = "m5.xlarge"

# Ubuntu 22.04 LTS in us-east-1
ec2_ami = "ami-0c7217cdde317cfec"

# EMR cluster: 1 master + 2 workers
emr_instance_type = "m5.xlarge"
emr_worker_count  = 2
