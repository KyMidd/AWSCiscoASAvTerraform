# Notes
# Create AWS account by hand
# Have to subscribe to BYOL Cisco ASAv on Marketplace: https://aws.amazon.com/marketplace/pp/B00WRGASUC
# Created SSH key in AWS, easier than explaining how to do it locally
# Created IAM user by hand, generate IAM static creds, export into CLI
# export AWS_ACCESS_KEY_ID="AKIA2OUL6JU2K4HLYFNU"
# export AWS_SECRET_ACCESS_KEY="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"

# Require TF version to be same as or greater than 0.12.18
terraform {
  required_version = ">=0.12.18"
}

# Download any stable version in AWS provider of 2.36.0 or higher in 2.36 train
provider "aws" {
  region  = "us-east-1"
  version = "~> 2.36.0"
}

locals {
  cisco_asav_name       = "CiscoASAv"
  my_public_ip          = "75.166.188.136/32"
  asav_public_facing_ip = "172.16.20.10"
}

resource "aws_vpc" "aws_vpc" {
  cidr_block = "172.16.0.0/16"

  tags = {
    Name = "AwsVpc"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.aws_vpc.id

  tags = {
    Name = "AwsInternetGateway"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.aws_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "AwsPublicRouteTable"
  }
}

# Attach network subnet 1 to dia route table1
resource "aws_route_table_association" "dia_route_table1" {
  subnet_id      = aws_subnet.aws_public_subnet1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_subnet" "aws_private_subnet1" {
  vpc_id            = aws_vpc.aws_vpc.id
  cidr_block        = "172.16.10.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "AwsPrivateSubnet1"
  }
}

resource "aws_subnet" "aws_public_subnet1" {
  vpc_id            = aws_vpc.aws_vpc.id
  cidr_block        = "172.16.20.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "AwsPublicSubnet1"
  }
}

# Create security group for ASAv public interface
resource "aws_security_group" "cisco_asav_public" {
  name        = "CiscoASAvPublicSg"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.aws_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.my_public_ip]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_public_ip]
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [local.my_public_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "CiscoASAvPublicSg"
  }
}

# Create security group for ASAv private interface
resource "aws_security_group" "cisco_asav_private" {
  name        = "CiscoASAvPrivateSg"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.aws_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "CiscoASAvPrivateSg"
  }
}

resource "aws_network_interface" "asav_private_interface" {
  subnet_id         = aws_subnet.aws_private_subnet1.id
  private_ips       = ["172.16.10.10"]
  source_dest_check = false

  security_groups = [
    aws_security_group.cisco_asav_private.id
  ]

  tags = {
    Name = "${local.cisco_asav_name}PrivateInterface"
  }
}

resource "aws_network_interface" "asav_public_interface" {
  subnet_id         = aws_subnet.aws_public_subnet1.id
  private_ips       = [local.asav_public_facing_ip]
  source_dest_check = false

  security_groups = [
    aws_security_group.cisco_asav_public.id
  ]

  tags = {
    Name = "${local.cisco_asav_name}PublicInterface"
  }
}

resource "aws_eip" "cisco_asav_elastic_public_ip" {
  vpc                       = true
  network_interface         = aws_network_interface.asav_public_interface.id
  associate_with_private_ip = local.asav_public_facing_ip

  depends_on = [
    aws_internet_gateway.internet_gateway
  ]
}

# Build the ASAv
resource "aws_instance" "cisco_asav" {
  # This AMI is only valid in us-east-1 region, with this specific instance type
  ami           = "ami-01b0bfec54ba93d12"
  instance_type = "c4.large"
  key_name      = "cisco_asav_keypair"

  network_interface {
    network_interface_id = aws_network_interface.asav_private_interface.id
    device_index         = 0
  }

  network_interface {
    network_interface_id = aws_network_interface.asav_public_interface.id
    device_index         = 1
  }

  user_data = file("aws_cisco_asav_config.txt")

  tags = {
    Name = local.cisco_asav_name
  }
}

output "asav_public_ip" {
  value = aws_eip.cisco_asav_elastic_public_ip.public_ip
}
