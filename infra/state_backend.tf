resource "aws_s3_bucket" "tfstate" {
  #checkov:skip=CKV_AWS_18:Same reasoning as the log bucket: logging this would require another bucket that the same check then flags.
  #checkov:skip=CKV_AWS_144:State is small and recreatable from the configuration plus the accounts themselves; replicating it across regions protects against the one failure this lab does not model.
  #checkov:skip=CKV2_AWS_62:Nothing consumes object events on the state bucket.
  #checkov:skip=CKV_AWS_145:The honest one. State holds the generated database password in clear text, so a customer-managed key here would be a real improvement, and it is deliberately not taken yet. A CMK on the state bucket is the one encryption change that can lock you out of your own state: the key policy is managed by the same Terraform that needs the key to read the state it is stored in, and getting that wrong is unrecoverable without an AWS support case. Doing it safely means creating the key, granting access, and verifying a read before switching the bucket default, which is a runbook rather than an attribute. Tracked under limits in README.md.
  bucket = "novapay-tfstate-${data.aws_caller_identity.current.account_id}"

  # Destroying the bucket that holds the state is how a project loses track
  # of everything it has built.
  lifecycle {
    prevent_destroy = true
  }
}

# Terraform writes a new state object on every apply, and versioning keeps
# each one. Those old versions are the rollback path, which is why versioning
# is on at all, but a year of them is not. Ninety days is well past the point
# where rolling back to a state file is still the right move.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-noncurrent-and-incomplete"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.tfstate]
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
