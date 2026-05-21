terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ==============================================================================
# VPC 1 - GitLab Host
# ==============================================================================

resource "aws_vpc" "gitlab_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "gitlab-vpc"
  }
}

resource "aws_subnet" "gitlab_private_subnet" {
  vpc_id            = aws_vpc.gitlab_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "gitlab-private-subnet"
  }
}

# Public subnet for NAT Gateway (GitLab needs outbound internet for package install)
resource "aws_subnet" "gitlab_nat_subnet" {
  vpc_id                  = aws_vpc.gitlab_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "gitlab-nat-subnet"
  }
}

resource "aws_internet_gateway" "gitlab_igw" {
  vpc_id = aws_vpc.gitlab_vpc.id

  tags = {
    Name = "gitlab-igw"
  }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "gitlab-nat-eip"
  }
}

resource "aws_nat_gateway" "gitlab_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.gitlab_nat_subnet.id

  depends_on = [aws_internet_gateway.gitlab_igw]

  tags = {
    Name = "gitlab-nat-gateway"
  }
}

resource "aws_route_table" "gitlab_nat_rt" {
  vpc_id = aws_vpc.gitlab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gitlab_igw.id
  }

  tags = {
    Name = "gitlab-nat-public-rt"
  }
}

resource "aws_route_table_association" "gitlab_nat_rta" {
  subnet_id      = aws_subnet.gitlab_nat_subnet.id
  route_table_id = aws_route_table.gitlab_nat_rt.id
}

resource "aws_route_table" "gitlab_private_rt" {
  vpc_id = aws_vpc.gitlab_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.gitlab_nat.id
  }

  route {
    cidr_block                = "10.1.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.gitlab_to_pipeline.id
  }

  tags = {
    Name = "gitlab-private-rt"
  }
}

resource "aws_route_table_association" "gitlab_private_rta" {
  subnet_id      = aws_subnet.gitlab_private_subnet.id
  route_table_id = aws_route_table.gitlab_private_rt.id
}


# ==============================================================================
# VPC 2 - CodePipeline
# ==============================================================================

resource "aws_vpc" "pipeline_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "pipeline-vpc"
  }
}

resource "aws_subnet" "pipeline_private_subnet" {
  vpc_id            = aws_vpc.pipeline_vpc.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "pipeline-private-subnet"
  }
}

resource "aws_route_table" "pipeline_rt" {
  vpc_id = aws_vpc.pipeline_vpc.id

  route {
    cidr_block                = "10.0.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.gitlab_to_pipeline.id
  }

  tags = {
    Name = "pipeline-rt"
  }
}

resource "aws_route_table_association" "pipeline_rta" {
  subnet_id      = aws_subnet.pipeline_private_subnet.id
  route_table_id = aws_route_table.pipeline_rt.id
}

# ==============================================================================
# VPC Peering Connection
# ==============================================================================

resource "aws_vpc_peering_connection" "gitlab_to_pipeline" {
  vpc_id      = aws_vpc.gitlab_vpc.id
  peer_vpc_id = aws_vpc.pipeline_vpc.id
  auto_accept = true

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  tags = {
    Name = "gitlab-to-pipeline-peering"
  }
}

# ==============================================================================
# Security Group for GitLab EC2
# ==============================================================================

resource "aws_security_group" "gitlab_sg" {
  name        = "gitlab-sg"
  description = "Security group for GitLab instance"
  vpc_id      = aws_vpc.gitlab_vpc.id

  ingress {
    description = "SSH from within VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "HTTP from within VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "HTTPS from within VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "HTTPS from Pipeline VPC via peering"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "gitlab-sg"
  }
}

# ==============================================================================
# Private CA & TLS Certificate for GitLab
# ==============================================================================

resource "aws_acmpca_certificate_authority" "gitlab_ca" {
  type = "ROOT"

  certificate_authority_configuration {
    key_algorithm     = "RSA_2048"
    signing_algorithm = "SHA256WITHRSA"

    subject {
      common_name  = "GitLab Internal CA"
      organization = "Internal"
    }
  }

  permanent_deletion_time_in_days = 7

  tags = {
    Name = "gitlab-private-ca"
  }
}

# Self-sign the root CA certificate
resource "aws_acmpca_certificate" "gitlab_ca_cert" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.gitlab_ca.arn
  certificate_signing_request = aws_acmpca_certificate_authority.gitlab_ca.certificate_signing_request
  signing_algorithm           = "SHA256WITHRSA"

  template_arn = "arn:aws:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = 10
  }
}

# Activate the CA by installing its own certificate
resource "aws_acmpca_certificate_authority_certificate" "gitlab_ca_cert" {
  certificate_authority_arn = aws_acmpca_certificate_authority.gitlab_ca.arn
  certificate              = aws_acmpca_certificate.gitlab_ca_cert.certificate
  certificate_chain        = aws_acmpca_certificate.gitlab_ca_cert.certificate_chain
}

# Issue a TLS certificate for GitLab signed by the private CA
resource "aws_acmpca_certificate" "gitlab_tls" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.gitlab_ca.arn
  certificate_signing_request = tls_cert_request.gitlab.cert_request_pem
  signing_algorithm           = "SHA256WITHRSA"

  template_arn = "arn:aws:acm-pca:::template/EndEntityCertificate/V1"

  validity {
    type  = "YEARS"
    value = 1
  }

  depends_on = [aws_acmpca_certificate_authority_certificate.gitlab_ca_cert]
}

# Generate a private key and CSR for GitLab TLS
resource "tls_private_key" "gitlab" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "gitlab" {
  private_key_pem = tls_private_key.gitlab.private_key_pem

  subject {
    common_name  = var.gitlab_private_ip
    organization = "Internal"
  }

  # SAN includes the static private IP assigned to GitLab
  ip_addresses = [var.gitlab_private_ip]
  dns_names    = ["gitlab.internal", "gitlab.local"]
}

# ==============================================================================
# EC2 Instance for GitLab
# ==============================================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "gitlab" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.gitlab_instance_type
  key_name               = "wilhou"
  subnet_id              = aws_subnet.gitlab_private_subnet.id
  private_ip             = var.gitlab_private_ip
  vpc_security_group_ids = [aws_security_group.gitlab_sg.id]

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/scripts/install_gitlab.sh", {
    gitlab_token_name  = var.gitlab_token_name
    gitlab_token_value = var.gitlab_personal_access_token
    gitlab_domain      = "gitlab.internal"
    tls_certificate    = aws_acmpca_certificate.gitlab_tls.certificate
    tls_private_key    = tls_private_key.gitlab.private_key_pem
    ca_certificate     = aws_acmpca_certificate.gitlab_ca_cert.certificate
  })

  tags = {
    Name = "gitlab-server"
  }
}

# ==============================================================================
# CodeStar Connections Host (VPC 2) - Connects to GitLab in VPC 1
# ==============================================================================

resource "aws_security_group" "codestar_sg" {
  name        = "codestar-connection-sg"
  description = "Security group for CodeStar connection to GitLab"
  vpc_id      = aws_vpc.pipeline_vpc.id

  egress {
    description = "HTTPS to GitLab VPC via peering"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "codestar-connection-sg"
  }
}

resource "aws_codestarconnections_host" "gitlab_host" {
  name              = "gitlab-self-managed-host"
  provider_endpoint = "https://${var.gitlab_private_ip}"
  provider_type     = "GitLabSelfManaged"

  vpc_configuration {
    vpc_id             = aws_vpc.pipeline_vpc.id
    subnet_ids         = [aws_subnet.pipeline_private_subnet.id]
    security_group_ids = [aws_security_group.codestar_sg.id]
    tls_certificate    = join("", [
      aws_acmpca_certificate.gitlab_tls.certificate,
      aws_acmpca_certificate.gitlab_ca_cert.certificate
    ])
  }
}

resource "aws_codestarconnections_connection" "gitlab_connection" {
  name     = "gitlab-pipeline-connection"
  host_arn = aws_codestarconnections_host.gitlab_host.arn

  tags = {
    Name = "gitlab-pipeline-connection"
  }
}
