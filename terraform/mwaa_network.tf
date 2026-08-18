# -----------------------------------------------------------------
# mwaa_network.tf
# Dedicated VPC for the MWAA environment.
# -----------------------------------------------------------------

resource "aws_vpc" "mwaa_prod" {
  cidr_block           = "10.100.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "mwaa-dedicated-vpc"
  }
}

resource "aws_internet_gateway" "mwaa_prod" {
  vpc_id = aws_vpc.mwaa_prod.id
}

resource "aws_subnet" "mwaa_prod_public" {
  vpc_id                  = aws_vpc.mwaa_prod.id
  cidr_block              = "10.100.0.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "mwaa-prod-public"
  }
}

resource "aws_eip" "mwaa_prod_nat" {
  domain = "vpc"

  tags = {
    Name = "mwaa-prod-nat-eip"
  }
}

resource "aws_nat_gateway" "mwaa_prod" {
  allocation_id = aws_eip.mwaa_prod_nat.id
  subnet_id     = aws_subnet.mwaa_prod_public.id
  depends_on    = [aws_internet_gateway.mwaa_prod]

  tags = {
    Name = "mwaa-prod-nat"
  }
}

resource "aws_route_table" "mwaa_prod_public" {
  vpc_id = aws_vpc.mwaa_prod.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mwaa_prod.id
  }
}

resource "aws_route_table_association" "mwaa_prod_public" {
  subnet_id      = aws_subnet.mwaa_prod_public.id
  route_table_id = aws_route_table.mwaa_prod_public.id
}

resource "aws_subnet" "mwaa_prod_a" {
  vpc_id            = aws_vpc.mwaa_prod.id
  cidr_block        = "10.100.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "mwaa-prod-private-a"
  }
}

resource "aws_subnet" "mwaa_prod_b" {
  vpc_id            = aws_vpc.mwaa_prod.id
  cidr_block        = "10.100.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "mwaa-prod-private-b"
  }
}

resource "aws_route_table" "mwaa_prod_private" {
  vpc_id = aws_vpc.mwaa_prod.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.mwaa_prod.id
  }
}

resource "aws_route_table_association" "mwaa_prod_a" {
  subnet_id      = aws_subnet.mwaa_prod_a.id
  route_table_id = aws_route_table.mwaa_prod_private.id
}

resource "aws_route_table_association" "mwaa_prod_b" {
  subnet_id      = aws_subnet.mwaa_prod_b.id
  route_table_id = aws_route_table.mwaa_prod_private.id
}