##############################################
# Q2 - Static Website using EC2 + NGINX
# Author: Devank Gupta
##############################################

provider "aws" {
  region = "ap-south-1"
}

#############################################
# Create a simple VPC for this workload
#############################################

resource "aws_vpc" "web_vpc" {
  cidr_block = "10.10.0.0/16"
  tags = {
    Name = "Devank_Gupta_Web_VPC"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.web_vpc.id
  cidr_block              = "10.10.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-south-1a"

  tags = {
    Name = "Devank_Gupta_Public_Subnet"
  }
}

resource "aws_internet_gateway" "web_igw" {
  vpc_id = aws_vpc.web_vpc.id

  tags = {
    Name = "Devank_Gupta_IGW"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.web_vpc.id

  tags = {
    Name = "Devank_Gupta_Public_Route_Table"
  }
}

resource "aws_route" "public_internet_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.web_igw.id
}

resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

#############################################
# Security Group: HTTP allowed to everyone,
# SSH allowed only to YOUR IP
#############################################



resource "aws_security_group" "web_sg" {
  name   = "Devank_Gupta_Web_SG"
  vpc_id = aws_vpc.web_vpc.id

  # Allow HTTP from anywhere (for website)
  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH from anywhere (for this demo)
  # In production: restrict this to your IP only (x.x.x.x/32)
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound allowed
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Devank_Gupta_Web_SG"
  }
}


#############################################
# EC2 Instance + NGINX + Upload Resume
#############################################

# Use latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  owners = ["137112412989"] # Amazon
}

resource "aws_instance" "web_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
  key_name = null # No SSH key required here

  # Install and configure Nginx + deploy resume.html
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install nginx1 -y
    systemctl start nginx
    systemctl enable nginx
    echo "${file("resume.html")}" > /usr/share/nginx/html/index.html
  EOF

  tags = {
    Name = "Devank_Gupta_Resume_Server"
  }
}

#############################################
# Outputs
#############################################

output "website_url" {
  value = "http://${aws_instance.web_server.public_ip}"
}
