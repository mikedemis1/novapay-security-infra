# D3 EKS Workload Security. Test-day resource — EKS control plane bills
# ~0.10 USD/hour regardless of usage, so this gets destroyed same-day after
# evidence capture (same pattern as the WAF test-day, SECURITY_DECISIONS.md
# 2026-07-14, but here the billing is hourly not just "exists", so leaving
# it running is a faster way to blow the 40 EUR/month cap).
module "eks" {
  #checkov:skip=CKV_TF_1:A commit hash is how you pin a module fetched from git. This one comes from the Terraform registry, where the equivalent is a version constraint plus the recorded checksum in .terraform.lock.hcl, which is committed. Rewriting the source as a git URL to satisfy the check would drop the registry's own signature verification.
  source = "terraform-aws-modules/eks/aws"

  # Exact, not "~> 20.0". A floating constraint means the module can change
  # under a build that touched nothing, and the compliance baseline below is
  # keyed on the resolved commit, so a silent bump would expire it and fail
  # the gate for no reason anyone could see. Bumping this is now a commit,
  # which is where a dependency change belongs.
  version      = "20.37.2"
  cluster_name = "novapay-eks"
  # 1.30 (the first guess) turned out to be past EKS standard AND extended
  # support already - `aws eks describe-cluster-versions` is ground truth,
  # not memory/assumption. As of 2026-08-09: 1.34-1.36 are STANDARD_SUPPORT,
  # 1.31-1.33 are EXTENDED_SUPPORT (extra hourly cost - avoid for a test-day
  # lab). 1.36 is AWS's current default. This will go stale again eventually
  # - re-run describe-cluster-versions before reusing this cluster later.
  cluster_version = "1.36"

  # The API endpoint was reachable from any address on the internet. IAM and
  # RBAC still gated it, but "authentication is the only thing between the
  # internet and the control plane" is a choice, and it had never been made
  # explicitly: it is the module's default. Now it is a required input, so
  # applying without deciding is not possible.
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.operator_cidrs

  # On by default in the module, not by anything written here. Stated so that
  # the answer to "which of these did you choose?" is not a guess.
  cluster_endpoint_private_access = true

  # All five, not the three that were here. controllerManager and scheduler
  # are the two that show a workload being scheduled somewhere it should not
  # be, which is the half of a compromise the audit log does not cover.
  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

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

  vpc_id = data.terraform_remote_state.platform.outputs.vpc_id
  # Control plane ENIs span both tiers; worker nodes (below) stay in the
  # private app subnets only, matching the app-tier pattern from D2.
  subnet_ids = [
    local.app_subnet_ids[0],
    local.app_subnet_ids[1],
    local.public_subnet_ids[0],
    local.public_subnet_ids[1],
  ]

  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 1
      desired_size   = 1
      subnet_ids     = [local.app_subnet_ids[0], local.app_subnet_ids[1]]

      # The module defaults this to 2, which is one hop more than the node
      # itself needs and exactly the hop a container needs to reach the
      # instance metadata service and read the node role's credentials. That
      # is the standard escape from a compromised pod to the whole node.
      #
      # Safe to close here because enable_irsa is on: pods receive
      # credentials through the OIDC provider, not through metadata, so
      # nothing in this cluster depends on the extra hop. http_tokens is
      # already "required" in the module, so IMDSv1 was never available.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }
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
  name               = "novapay-transaction-service-irsa"
  assume_role_policy = data.aws_iam_policy_document.app_irsa_trust.json
}

data "aws_iam_policy_document" "app_secret_read" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [data.terraform_remote_state.platform.outputs.db_secret_arn]
  }

  # Reading a CMK-encrypted secret needs the key too. Scoping is handled by
  # the key policy's kms:ViaService condition (kms.tf).
  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [data.terraform_remote_state.platform.outputs.app_data_kms_key_arn]
  }
}

resource "aws_iam_policy" "app_secret_read" {
  name   = "novapay-transaction-service-secret-read"
  policy = data.aws_iam_policy_document.app_secret_read.json
}

resource "aws_iam_role_policy_attachment" "app_irsa_secret_read" {
  role       = aws_iam_role.app_irsa.name
  policy_arn = aws_iam_policy.app_secret_read.arn
}

variable "operator_cidrs" {
  description = "Source ranges allowed to reach the EKS public API endpoint, in CIDR form. Deliberately has no default: a wide-open control plane should be a written decision, not an inherited one."
  type        = list(string)
}
