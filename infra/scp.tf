# D1 Secure Landing Zone — deny-list SCP for the Workloads OU.
# Deny-list, not allow-list: the Workloads account is still under active
# D3/D4 build-out, so a "deny everything except X" policy risks blocking
# legitimate work the moment we forget to list something. This only blocks
# the specific evidence-tampering / escape actions from ARCHITECTURE_D1.md.

resource "aws_organizations_policy" "workloads_guardrails" {
  name = "novapay-workloads-guardrails"
  type = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyTrailTampering"
        Effect = "Deny"
        Action = [
          "cloudtrail:StopLogging",
          "cloudtrail:DeleteTrail",
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyGuardDutyTampering"
        Effect = "Deny"
        Action = [
          "guardduty:DeleteDetector",
          "guardduty:DisassociateFromMasterAccount",
        ]
        Resource = "*"
      },
      {
        Sid      = "DenyLeavingOrganization"
        Effect   = "Deny"
        Action   = "organizations:LeaveOrganization"
        Resource = "*"
      },
    ]
  })
}

resource "aws_organizations_policy_attachment" "workloads_guardrails" {
  policy_id = aws_organizations_policy.workloads_guardrails.id
  target_id = aws_organizations_organizational_unit.workloads.id
}
