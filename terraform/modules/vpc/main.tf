locals {
  base_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.tags
  )

  target_az_count = lookup(
    {
      dev   = 1
      stage = 2
      prod  = 3
    },
    var.environment,
    3
  )

  az_count = min(
    local.target_az_count,
    length(data.aws_availability_zones.available.names),
    length(var.public_subnet_cidrs),
    length(var.private_subnet_cidrs)
  )

  selected_public_subnet_cidrs  = slice(var.public_subnet_cidrs, 0, local.az_count)
  selected_private_subnet_cidrs = slice(var.private_subnet_cidrs, 0, local.az_count)

  nat_gateway_count = var.environment == "prod" ? local.az_count : 1
  nat_per_az        = var.environment == "prod"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  lifecycle {
    precondition {
      condition     = local.az_count == local.target_az_count
      error_message = "Insufficient AZs or subnet CIDRs for ${var.environment}. Provide at least ${local.target_az_count} public and private CIDRs in this region."
    }
  }

  tags = merge(local.base_tags, { Name = "mlops-${var.environment}-vpc" })
}

data "aws_availability_zones" "available" {}

# -------------------------
# Public Subnets
# -------------------------

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.selected_public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.base_tags, { Name = "mlops-${var.environment}-public-${count.index}" })
}

# -------------------------
# Private Subnets
# -------------------------

resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.selected_private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.base_tags, { Name = "mlops-${var.environment}-private-${count.index}" })
}

# -------------------------
# Internet Gateway
# -------------------------

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.base_tags, { Name = "mlops-${var.environment}-igw" })
}

# -------------------------
# NAT Gateway (single for dev/stage, per-AZ for prod)
# -------------------------

resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"
  tags   = merge(local.base_tags, { Name = "mlops-${var.environment}-nat-eip-${count.index}" })
}

resource "aws_nat_gateway" "nat" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[local.nat_per_az ? count.index : 0].id

  tags = merge(local.base_tags, { Name = "mlops-${var.environment}-nat-${count.index}" })
}

# -------------------------
# Public Route Table
# -------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.base_tags, { Name = "mlops-${var.environment}-public-rt" })
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -------------------------
# Private Route Table
# -------------------------

resource "aws_route_table" "private" {
  count  = local.nat_per_az ? local.az_count : 1
  vpc_id = aws_vpc.main.id

  tags = merge(local.base_tags, { Name = "mlops-${var.environment}-private-rt-${count.index}" })
}

resource "aws_route" "private_nat_access" {
  count = local.nat_gateway_count

  route_table_id         = aws_route_table.private[local.nat_per_az ? count.index : 0].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[count.index].id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[local.nat_per_az ? count.index : 0].id
}
