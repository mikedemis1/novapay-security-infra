# D3 EKS Workload Security. Test-day resource — EKS control plane bills
# ~0.10 USD/hour regardless of usage, so this gets destroyed same-day after
# evidence capture (same pattern as the WAF test-day, SECURITY_DECISIONS.md
# 2026-07-14, but here the billing is hourly not just "exists", so leaving
# it running is a faster way to blow the 40 EUR/month cap).
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  providers = {
    aws = aws.workloads
  }

  cluster_name = "novapay-eks"
  # 1.30 (the first guess) turned out to be past EKS standard AND extended
  # support already - `aws eks describe-cluster-versions` is ground truth,
  # not memory/assumption. As of 2026-08-09: 1.34-1.36 are STANDARD_SUPPORT,
  # 1.31-1.33 are EXTENDED_SUPPORT (extra hourly cost - avoid for a test-day
  # lab). 1.36 is AWS's current default. This will go stale again eventually
  # - re-run describe-cluster-versions before reusing this cluster later.
  cluster_version = "1.36"

  cluster_endpoint_public_access = true

  # Without this, the identity running `terraform apply` (the assumed
  # OrganizationAccountAccessRole) gets no RBAC access to the cluster it
  # just created — breaks both the Helm/kubernetes provider calls later in
  # this same apply, and any kubectl access afterwards using that identity.
  enable_cluster_creator_admin_permissions = true

  # Confirmed live (2026-08-09 test-day): NetworkPolicy objects exist in the
  # API but have ZERO effect without this - the default AWS VPC CNI doesn't
  # enforce them at all, so the default-deny + DNS-only egress policies in
  # app.tf were silently no-ops (an HTTPS request to an external site
  # succeeded when it should have been blocked). This turns on the VPC
  # CNI's built-in NetworkPolicy agent so the policies actually apply.
  cluster_addons = {
    vpc-cni = {
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
  }

  vpc_id = aws_vpc.main.id
  # Control plane ENIs span both tiers; worker nodes (below) stay in the
  # private app subnets only, matching the app-tier pattern from D2.
  subnet_ids = [
    aws_subnet.app_a.id,
    aws_subnet.app_b.id,
    aws_subnet.public_a.id,
    aws_subnet.public_b.id,
  ]

  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 1
      desired_size   = 1
      subnet_ids     = [aws_subnet.app_a.id, aws_subnet.app_b.id]
    }
  }

  tags = {
    Name = "novapay-eks"
  }

  depends_on = [aws_route.private_nat]
}

# IRSA: the placeholder transaction-service pod gets its own IAM role, scoped
# to read exactly one secret (the D2 db-credentials secret) and nothing
# else — ties D2 and D3 together instead of being a disconnected demo.
data "aws_iam_policy_document" "app_irsa_trust" {
  provider = aws.workloads

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:novapay-app:novapay-transaction-service"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_irsa" {
  provider           = aws.workloads
  name               = "novapay-transaction-service-irsa"
  assume_role_policy = data.aws_iam_policy_document.app_irsa_trust.json
}

data "aws_iam_policy_document" "app_secret_read" {
  provider = aws.workloads

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.db_credentials.arn]
  }
}

resource "aws_iam_policy" "app_secret_read" {
  provider = aws.workloads
  name     = "novapay-transaction-service-secret-read"
  policy   = data.aws_iam_policy_document.app_secret_read.json
}

resource "aws_iam_role_policy_attachment" "app_irsa_secret_read" {
  provider   = aws.workloads
  role       = aws_iam_role.app_irsa.name
  policy_arn = aws_iam_policy.app_secret_read.arn
}
