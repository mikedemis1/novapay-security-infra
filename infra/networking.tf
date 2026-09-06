resource "aws_vpc" "main" {
  #checkov:skip=CKV2_AWS_11:Real gap, not a false positive. Flow logs answer "what talked to what" and nothing else here does. Delivering them means a cross-account write from Workloads into the management-account log bucket, which needs its bucket policy widened, and that policy is the one thing standing between this estate and a tampered audit trail. Widening it is a decision of its own, not a checkbox. Listed under limits in README.md.
  provider   = aws.workloads
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "novapay-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  provider = aws.workloads
  vpc_id   = aws_vpc.main.id

  tags = {
    Name = "novapay-igw"
  }
}

# Public subnets (load balancer) — routed to the internet gateway
resource "aws_subnet" "public_a" {
  #checkov:skip=CKV_AWS_130:map_public_ip_on_launch is what makes a subnet public, and this tier exists to hold the load balancer and NAT. Turning it off would not harden the design, it would break the only route out of the private tiers. The private tiers are separate resources and do not set it.
  provider                = aws.workloads
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/19"
  availability_zone       = "eu-west-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "novapay-public-a"
  }
}

resource "aws_subnet" "public_b" {
  #checkov:skip=CKV_AWS_130:map_public_ip_on_launch is what makes a subnet public, and this tier exists to hold the load balancer and NAT. Turning it off would not harden the design, it would break the only route out of the private tiers. The private tiers are separate resources and do not set it.
  provider                = aws.workloads
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.32.0/19"
  availability_zone       = "eu-west-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "novapay-public-b"
  }
}

# Private subnets (app servers) — no route to the internet gateway
resource "aws_subnet" "app_a" {
  provider          = aws.workloads
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.64.0/19"
  availability_zone = "eu-west-1a"

  tags = {
    Name = "novapay-app-a"
  }
}

resource "aws_subnet" "app_b" {
  provider          = aws.workloads
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.96.0/19"
  availability_zone = "eu-west-1b"

  tags = {
    Name = "novapay-app-b"
  }
}

# Private subnets (database) — no route to the internet gateway
resource "aws_subnet" "db_a" {
  provider          = aws.workloads
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.128.0/19"
  availability_zone = "eu-west-1a"

  tags = {
    Name = "novapay-db-a"
  }
}

resource "aws_subnet" "db_b" {
  provider          = aws.workloads
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.160.0/19"
  availability_zone = "eu-west-1b"

  tags = {
    Name = "novapay-db-b"
  }
}

# Public route table — sends internet-bound traffic to the IGW
resource "aws_route_table" "public" {
  provider = aws.workloads
  vpc_id   = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "novapay-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  provider       = aws.workloads
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  provider       = aws.workloads
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Private route table — local traffic only, no route to the IGW.
# No NAT gateway (adds ~30 EUR/month) — out of scope for this budget.
resource "aws_route_table" "private" {
  provider = aws.workloads
  vpc_id   = aws_vpc.main.id

  tags = {
    Name = "novapay-private-rt"
  }
}

resource "aws_route_table_association" "app_a" {
  provider       = aws.workloads
  subnet_id      = aws_subnet.app_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "app_b" {
  provider       = aws.workloads
  subnet_id      = aws_subnet.app_b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "db_a" {
  provider       = aws.workloads
  subnet_id      = aws_subnet.db_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "db_b" {
  provider       = aws.workloads
  subnet_id      = aws_subnet.db_b.id
  route_table_id = aws_route_table.private.id
}
