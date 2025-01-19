provider "aws" {
region = "us-east-1"
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create a Key Pair in AWS
resource "aws_key_pair" "my_key" {
  key_name   = "my-key-pair"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# Save the private key locally
resource "local_file" "private_key" {
  content  = tls_private_key.ssh_key.private_key_pem
  filename = "${path.module}/my-key-pair.pem"
}

resource "aws_iam_role" "ssm_role" {
  name = "ssm-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
      },
    ],
  })
}

# Attach SSM Managed Policy to the IAM Role
resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create an instance profile for the EC2 instance
resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "ssm-instance-profile"
  role = aws_iam_role.ssm_role.name
}

resource "aws_security_group" "postgres_sg" {
  name        = "postgres-sg"
  description = "Security group for PostgreSQL and SSH access"

  # Inbound Rules
  ingress {
    description = "Allow PostgreSQL traffic from replicas"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Replace with replica CIDR block
  }

  ingress {
    description = "Allow SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Replace with a specific IP range for better security
  }

  # Outbound Rules
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allows all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "PostgreSQL-Security-Group"
  }
}

resource "aws_instance" "primary" {
  ami           = "ami-059ca4d31bc22f6e4"
  instance_type = "t2.medium"
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  key_name = aws_key_pair.my_key.key_name
  vpc_security_group_ids = [
      aws_security_group.postgres_sg.id
  ]
  tags = {
    Name = "PostgreSQL-Primary"
  }
}

resource "aws_instance" "replica" {
    ami    = "ami-059ca4d31bc22f6e4"
    instance_type = "t2.medium"
  count = 2
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  key_name = aws_key_pair.my_key.key_name
  vpc_security_group_ids = [
    aws_security_group.postgres_sg.id
  ]
  tags = {
    Name = "PostgreSQL-Replica"
  }
}

output "primary_public_ip" {
  value = aws_instance.primary.*.public_ip
}

output "primary_private_ip" {
  value = aws_instance.primary.*.private_ip
}

output "replica_ips" {
  value = aws_instance.replica.*.public_ip
}