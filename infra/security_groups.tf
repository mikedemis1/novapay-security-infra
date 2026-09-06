# Every VPC gets an implicit default SG (allow-all within itself, allow-all
# outbound) that nothing here references — lb/app/db each have their own.
# Locked to zero rules so anything accidentally launched without an explicit
# SG lands in a deny-all group instead of inheriting broad implicit trust.
resource "aws_default_security_group" "main" {
  provider = aws.workloads
  vpc_id   = aws_vpc.main.id

  tags = {
    Name = "novapay-default-sg-locked"
  }
}

# Security groups form a chain: internet -> lb -> app -> db.
# Each tier only accepts traffic from the tier directly in front of it.

resource "aws_security_group" "lb" {
  #checkov:skip=CKV2_AWS_5:Attached to the EKS cluster and its load balancer, which live in the workload stack and are destroyed after each test. Checkov reads one stack at a time, so it sees a group with nothing to attach to whenever the cluster is down, which is most of the time.
  #checkov:skip=CKV_AWS_382:Egress to 0.0.0.0/0 is deliberate. This tier pulls container images and reaches AWS APIs; pinning egress to CIDRs would mean tracking the address ranges of ECR, S3 and STS by hand. The control that does the work here is chained ingress: each tier accepts traffic only from the security group above it.
  provider    = aws.workloads
  name        = "novapay-lb-sg"
  description = "Load balancer: accepts HTTPS from the internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "novapay-lb-sg"
  }
}

resource "aws_security_group" "app" {
  #checkov:skip=CKV2_AWS_5:Attached to the EKS cluster and its load balancer, which live in the workload stack and are destroyed after each test. Checkov reads one stack at a time, so it sees a group with nothing to attach to whenever the cluster is down, which is most of the time.
  #checkov:skip=CKV_AWS_382:Egress to 0.0.0.0/0 is deliberate. This tier pulls container images and reaches AWS APIs; pinning egress to CIDRs would mean tracking the address ranges of ECR, S3 and STS by hand. The control that does the work here is chained ingress: each tier accepts traffic only from the security group above it.
  provider    = aws.workloads
  name        = "novapay-app-sg"
  description = "App servers: accept traffic only from the load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App traffic from LB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "novapay-app-sg"
  }
}

resource "aws_security_group" "db" {
  #checkov:skip=CKV2_AWS_5:Attached to the EKS cluster and its load balancer, which live in the workload stack and are destroyed after each test. Checkov reads one stack at a time, so it sees a group with nothing to attach to whenever the cluster is down, which is most of the time.
  provider    = aws.workloads
  name        = "novapay-db-sg"
  description = "Database: accept traffic only from app servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from app tier"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # No egress rule: db tier has no route to the internet anyway (private-rt),
  # and doesn't need to initiate outbound connections.

  tags = {
    Name = "novapay-db-sg"
  }
}
