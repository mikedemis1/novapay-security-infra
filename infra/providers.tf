terraform {
  # use_lockfile below is a 1.10 feature; without this floor the backend
  # silently falls back to no locking on an older CLI.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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

locals {
  common_tags = {
    Project     = "novapay"
    ManagedBy   = "terraform"
    Environment = "lab"
  }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = local.common_tags
  }
}

# The Security account owns detection and log storage. Same
# OrganizationAccountAccessRole pattern as the Workloads alias below.
provider "aws" {
  alias  = "security"
  region = "eu-west-1"

  assume_role {
    role_arn = "arn:aws:iam::${aws_organizations_account.security.id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "security" {
  provider = aws.security
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

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "workloads" {
  provider = aws.workloads
}
