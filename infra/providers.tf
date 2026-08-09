terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }

  # bucket intentionally omitted — real AWS account ID stays out of version
  # control. Supplied via `terraform init -backend-config=backend.hcl`
  # (backend.hcl is gitignored, see infra/backend.hcl.example for the format).
  backend "s3" {
    key          = "novapay/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "eu-west-1"
}

# D2 infra (VPC/SG/WAF/Secrets/test IAM user) lives in the real Workloads
# account instead of Management — the migration deferred at D1 (SECURITY_DECISIONS.md
# 2026-08-08). OrganizationAccountAccessRole is the role Organizations creates
# automatically in every member account, assumable from the Management account
# that created it — no extra IAM setup needed in Workloads.
provider "aws" {
  alias  = "workloads"
  region = "eu-west-1"

  assume_role {
    role_arn = "arn:aws:iam::${aws_organizations_account.workloads.id}:role/OrganizationAccountAccessRole"
  }
}

data "aws_caller_identity" "workloads" {
  provider = aws.workloads
}

# D3: kubernetes/helm providers authenticate to the novapay-eks cluster
# (Workloads account) using a short-lived token from the same assumed role
# used for every other Workloads resource.
data "aws_eks_cluster_auth" "this" {
  provider = aws.workloads
  name     = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
