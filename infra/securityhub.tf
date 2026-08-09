# D1 Secure Landing Zone — central findings dashboard.
# Aggregates GuardDuty (and future) findings into one view with severity
# scoring, instead of checking each detection service separately.
#
# Default compliance standards (CIS/AWS Foundational Security Best Practices)
# are left OFF: they bill per check evaluated across every resource, and we
# don't have a standard picked yet. Turn one on explicitly when we do.
#
# TEMPORARY: no real Security account exists yet (see organizations.tf), so
# the delegated admin points at this Management account for now. Revisit
# once the real Security account is created.

resource "aws_securityhub_account" "main" {
  enable_default_standards = false
}

resource "aws_securityhub_organization_admin_account" "main" {
  admin_account_id = data.aws_caller_identity.current.account_id
}

resource "aws_securityhub_organization_configuration" "main" {
  auto_enable           = true
  auto_enable_standards = "NONE"

  depends_on = [aws_securityhub_organization_admin_account.main]
}
