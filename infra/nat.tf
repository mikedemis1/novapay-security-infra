# TEMPORARY, test-day only (D3 EKS). D2 deliberately has no NAT Gateway
# (SECURITY_DECISIONS.md 2026-07-04 — saves ~30 EUR/month, no outbound need
# existed until now). EKS worker nodes in the private app subnets need
# outbound internet to pull container images and reach the EKS API, so this
# exists only for the D3 test window — destroy it same-day along with the
# EKS cluster, don't leave it running (NAT Gateway bills hourly + per-GB
# regardless of whether it does hourly, this is-hours-not-months money, but
# a forgotten month would blow the 40 EUR/month cap on its own).
resource "aws_eip" "nat" {
  provider = aws.workloads
  domain   = "vpc"

  tags = {
    Name = "novapay-nat-eip-TEMP-d3"
  }
}

resource "aws_nat_gateway" "main" {
  provider      = aws.workloads
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id

  tags = {
    Name = "novapay-nat-TEMP-d3"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route" "private_nat" {
  provider               = aws.workloads
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}
