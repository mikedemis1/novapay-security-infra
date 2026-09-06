# D1 Secure Landing Zone — the organisation and its OU layout.
# Member accounts are created separately in accounts.tf, because creating a
# real AWS account is not cleanly reversible with terraform destroy.

resource "aws_organizations_organization" "main" {
  # ALL (not CONSOLIDATED_BILLING) is required for Service Control Policies —
  # the deny rules that stop a compromised Workloads account from disabling
  # its own logging/detection, regardless of its local IAM permissions.
  feature_set = "ALL"

  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "sso.amazonaws.com",
    # Organization-scope Access Analyzer (account_baseline.tf) needs trusted
    # access before the analyzer can see past a single account.
    "access-analyzer.amazonaws.com",
  ]

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
  ]
}

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.main.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.main.roots[0].id
}
