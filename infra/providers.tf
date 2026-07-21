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
