# Account-level controls that apply to every account regardless of what runs
# inside it. These are the CIS AWS Foundations items that cost nothing and
# were missing without ever being decided against, which is the part that
# mattered: an undocumented gap and a documented trade-off look identical in
# a repo until someone checks.
#
# Terraform has no way to loop a resource over providers, so each account is
# written out. That repetition is the honest cost of a three-account estate
# in a single root module.

# CIS 2.1.4 — the bucket-level block already exists on both buckets; this is
# the account-level backstop that also covers buckets nobody remembered.
resource "aws_s3_account_public_access_block" "management" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_account_public_access_block" "security" {
  provider                = aws.security
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_account_public_access_block" "workloads" {
  provider                = aws.workloads
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CIS 1.8 / 1.9. Applies to IAM users with console passwords. There are none
# by design, since humans arrive through Identity Center, so this is a guard
# against a future console user being created with a weak password rather
# than a control doing work today.
resource "aws_iam_account_password_policy" "management" {
  minimum_password_length        = 14
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
  max_password_age               = 90
}

resource "aws_iam_account_password_policy" "workloads" {
  provider                       = aws.workloads
  minimum_password_length        = 14
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
  max_password_age               = 90
}

# CIS 1.20. Organization scope means one analyzer in the management account
# covers all three, instead of one per account. It reports resources reachable
# from outside the organisation, so a bucket shared to a stranger surfaces
# here rather than in a bill.
resource "aws_accessanalyzer_analyzer" "org" {
  analyzer_name = "novapay-org-external-access"
  type          = "ORGANIZATION"
}

# CIS 2.2.1. Only Workloads runs EC2, and only when the cluster is up, but the
# setting is per-account-per-region and has to exist before the volume does.
resource "aws_ebs_encryption_by_default" "workloads" {
  provider = aws.workloads
  enabled  = true
}

# CIS 1.2. Without this, AWS sends account-compromise notices to the root
# inbox only, which is the inbox nobody watches.
resource "aws_account_alternate_contact" "management_security" {
  alternate_contact_type = "SECURITY"
  name                   = "NovaPay Security"
  title                  = "Security Contact"
  email_address          = var.security_alerts_email
  phone_number           = var.security_contact_phone
}

resource "aws_account_alternate_contact" "security_security" {
  provider               = aws.security
  alternate_contact_type = "SECURITY"
  name                   = "NovaPay Security"
  title                  = "Security Contact"
  email_address          = var.security_alerts_email
  phone_number           = var.security_contact_phone
}

resource "aws_account_alternate_contact" "workloads_security" {
  provider               = aws.workloads
  alternate_contact_type = "SECURITY"
  name                   = "NovaPay Security"
  title                  = "Security Contact"
  email_address          = var.security_alerts_email
  phone_number           = var.security_contact_phone
}
