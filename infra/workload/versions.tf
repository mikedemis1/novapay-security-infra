# The workload stack: the cluster and everything running on it.
#
# Separate from the platform stack in infra/ because Kubernetes objects cannot
# be planned before the cluster API exists. The kubernetes_manifest resources
# in kyverno.tf validate against the live cluster's schema at plan time, and
# the provider itself is configured from the cluster endpoint, which is
# unknown until the cluster is created. Keeping both in one root module meant
# terraform plan failed outright whenever the cluster was down, which is most
# of the time here, since the cluster is torn down after each test to stay
# inside the budget.
#
# The split is also how the two things actually behave. The platform is
# long-lived and changes rarely. The cluster is created, tested and destroyed
# in a day. Giving them one state file tied the lifetime of the first to the
# availability of the second.
#
# Apply order: platform first, then this. It reads the platform's outputs, so
# it cannot be applied against an empty platform state.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

  # Same bucket as the platform stack, different key. Bucket name is supplied
  # by -backend-config so the account ID stays out of version control; see
  # ../backend.hcl.example.
  backend "s3" {
    key          = "novapay/workload.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}

data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    bucket = var.platform_state_bucket
    key    = "novapay/terraform.tfstate"
    region = "eu-west-1"
  }
}

variable "platform_state_bucket" {
  description = "S3 bucket holding the platform stack state (same value as the backend bucket)"
  type        = string
}

locals {
  app_subnet_ids    = data.terraform_remote_state.platform.outputs.app_subnet_ids
  public_subnet_ids = data.terraform_remote_state.platform.outputs.public_subnet_ids
}

# Unlike the platform stack, everything here lives in one account, so Workloads
# is the default provider rather than an alias.
provider "aws" {
  region = "eu-west-1"

  assume_role {
    role_arn = "arn:aws:iam::${data.terraform_remote_state.platform.outputs.workloads_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = {
      Project     = "novapay"
      ManagedBy   = "terraform"
      Environment = "lab"
    }
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
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
