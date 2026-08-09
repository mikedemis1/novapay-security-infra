# D1 Secure Landing Zone — step 1: enable AWS Organizations and lay out the
# OU structure from ARCHITECTURE_D1.md (Option G). No member accounts yet —
# that's a deliberately separate, explicitly-approved step (real AWS accounts
# aren't cleanly reversible via `terraform destroy`).

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
