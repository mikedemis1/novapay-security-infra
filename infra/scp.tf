# D1 Secure Landing Zone — service control policies.
#
# Deny lists rather than allow lists. An allow list would have blocked the
# cluster work the first time something unlisted was needed, and a guardrail
# that gets detached to unblock a Friday is not a guardrail.
#
# Three policies instead of one because they answer different questions and
# attach in different places: what nobody may ever do (root), what protects
# the security services (both OUs), and where data may live (both OUs).
# Splitting them also means a region change is not an edit to the same
# document that protects the audit trail.
#
# What none of them do: constrain the management account. SCPs never apply
# there. The management account holds the organisation, the log bucket, the
# log key and the Terraform state, and the only things protecting it are root
# MFA and its IAM configuration. That asymmetry is the reason detection and
# log storage belong in the Security account.

# Attached at the root, so it also covers any OU added later. AWS attaches an
# equivalent policy to new organisations by default; this one is explicit so
# the intent survives someone tidying up the console.
resource "aws_organizations_policy" "base_guardrails" {
  name        = "novapay-base-guardrails"
  description = "Actions no account in the organisation may take"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyLeavingOrganization"
        Effect = "Deny"
        Action = [
          "organizations:LeaveOrganization",
          "account:CloseAccount",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_organizations_policy_attachment" "base_guardrails_root" {
  policy_id = aws_organizations_policy.base_guardrails.id
  target_id = aws_organizations_organization.main.roots[0].id
}

# The evidence-tampering guardrail. Someone who lands in a member account
# should not be able to stop the recording, disconnect the account from the
# detection administrator, or quietly narrow what gets recorded.
#
# Narrowing matters as much as deleting. UpdateTrail and PutEventSelectors
# can turn a trail into one that records almost nothing while still existing
# and still looking healthy on a dashboard. DeleteTrail is the loud version
# of the same attack, and the loud version is not the one to worry about.
#
# Member accounts cannot stop or delete an organisation trail in the first
# place, so the CloudTrail half is defence in depth against a future
# account-local trail. It is not what protects the org trail.
resource "aws_organizations_policy" "protect_security_services" {
  name        = "novapay-protect-security-services"
  description = "Stop member accounts disabling or narrowing their own logging and detection"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyTrailTampering"
        Effect = "Deny"
        Action = [
          "cloudtrail:StopLogging",
          "cloudtrail:DeleteTrail",
          "cloudtrail:UpdateTrail",
          "cloudtrail:PutEventSelectors",
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyGuardDutyTampering"
        Effect = "Deny"
        Action = [
          "guardduty:DeleteDetector",
          "guardduty:UpdateDetector",
          "guardduty:DeleteMembers",
          "guardduty:DisassociateFromAdministratorAccount",
          # Retired name for the action above. Kept because an old SDK or an
          # open session can still send it, and a deny that covers only the
          # current spelling is a deny with a bypass.
          "guardduty:DisassociateFromMasterAccount",
        ]
        Resource = "*"
      },
      {
        Sid    = "DenySecurityHubTampering"
        Effect = "Deny"
        Action = [
          "securityhub:DisableSecurityHub",
          "securityhub:DisassociateFromAdministratorAccount",
          "securityhub:DeleteMembers",
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyConfigTampering"
        Effect = "Deny"
        Action = [
          "config:DeleteConfigurationRecorder",
          "config:StopConfigurationRecorder",
          "config:DeleteDeliveryChannel",
        ]
        Resource = "*"
      },
    ]
  })
}

locals {
  # Services with no regional endpoint, or whose endpoint is pinned to
  # us-east-1. Denying these by region makes an account unmanageable, and the
  # lockout cannot be undone from inside the account.
  global_service_actions = [
    "access-analyzer:*",
    "account:*",
    "acm:*",
    "aws-marketplace:*",
    "aws-portal:*",
    "budgets:*",
    "ce:*",
    "cloudfront:*",
    "cur:*",
    "globalaccelerator:*",
    "health:*",
    "iam:*",
    "kms:*",
    "license-manager:*",
    "organizations:*",
    "route53:*",
    "route53domains:*",
    "s3:GetAccountPublic*",
    "s3:ListAllMyBuckets",
    "s3:PutAccountPublic*",
    "shield:*",
    "sts:*",
    "support:*",
    "trustedadvisor:*",
    "waf-regional:*",
    "waf:*",
    "wafv2:*",
    "wellarchitected:*",
  ]
}

# Data residency. NovaPay is framed as an EU payments firm, so a resource
# outside eu-west-1 is a compliance problem before it is a security one.
#
# It also turns a gap into a decision: GuardDuty runs in eu-west-1 only, which
# is a hole if resources can appear anywhere and a defensible scope if they
# cannot.
resource "aws_organizations_policy" "region_deny" {
  name        = "novapay-region-deny"
  description = "Confine member accounts to eu-west-1, excluding global services"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyOutsideEuWest1"
        Effect    = "Deny"
        NotAction = local.global_service_actions
        Resource  = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = ["eu-west-1"]
          }
        }
      },
    ]
  })
}

# Both OUs, not only Workloads. The Security account holds the detection
# services, so someone who reaches it has more reason to disable them, not
# less. Leaving that OU on FullAWSAccess alone was an oversight.
resource "aws_organizations_policy_attachment" "protect_security_services_workloads" {
  policy_id = aws_organizations_policy.protect_security_services.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "protect_security_services_security" {
  policy_id = aws_organizations_policy.protect_security_services.id
  target_id = aws_organizations_organizational_unit.security.id
}

resource "aws_organizations_policy_attachment" "region_deny_workloads" {
  policy_id = aws_organizations_policy.region_deny.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "region_deny_security" {
  policy_id = aws_organizations_policy.region_deny.id
  target_id = aws_organizations_organizational_unit.security.id
}

# Left out on purpose: a deny on the member-account root user. It is standard
# advice, but Workloads still has no root MFA, and enabling that is a root
# console action. Denying root before the account can be secured would remove
# the only way to secure it. Root MFA first, then this policy.
