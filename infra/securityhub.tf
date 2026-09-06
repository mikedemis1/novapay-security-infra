# D1 Secure Landing Zone — central findings view.
# Aggregates GuardDuty and other findings into one place with a common
# severity scale, so there is one thing to look at rather than one per
# service.
#
# Administered from the Security account for the same reason as GuardDuty,
# and because that is where the findings then aggregate. The alerting rule in
# alerting.tf has to sit in the same account for that reason: an EventBridge
# rule only sees events on its own account's bus.

moved {
  from = aws_securityhub_account.main
  to   = aws_securityhub_account.management
}

resource "aws_securityhub_account" "management" {
  enable_default_standards = false
}

resource "aws_securityhub_account" "security" {
  provider                 = aws.security
  enable_default_standards = false
}

resource "aws_securityhub_organization_admin_account" "main" {
  admin_account_id = aws_organizations_account.security.id

  depends_on = [aws_securityhub_account.security]
}

resource "aws_securityhub_organization_configuration" "main" {
  provider = aws.security

  auto_enable = true
  # Standards are chosen explicitly below rather than inherited, so that
  # turning one on is a decision with a cost attached and not a default.
  auto_enable_standards = "NONE"

  depends_on = [aws_securityhub_organization_admin_account.main]
}
