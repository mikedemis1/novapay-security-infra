# Test IAM user for iterating on least-privilege policies (D2 ③) without touching
# the main admin account — a wrong policy here can't lock the real user out.
resource "aws_iam_user" "test" {
  provider = aws.workloads
  name     = "novapay-iam-test-user"

  tags = {
    Name = "novapay-iam-test-user"
  }
}

resource "aws_iam_access_key" "test" {
  provider = aws.workloads
  user     = aws_iam_user.test.name
}

# Explicit Deny guardrail based on the IAM threat model (state.md ③):
# 1) irreversible database loss, 2) removing the app's WAF protection,
# 3) IAM privilege escalation (create/attach-policy/backdoor patterns from
# https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/).
# Deny always overrides Allow in IAM evaluation, so this stays in effect no matter
# what Allow permissions get layered onto this user later.
data "aws_iam_policy_document" "deny_dangerous_actions" {
  statement {
    sid       = "DenyDatabaseDeletion"
    effect    = "Deny"
    actions   = ["rds:DeleteDBInstance", "rds:DeleteDBCluster"]
    resources = ["*"]
  }

  statement {
    sid       = "DenyWafRemoval"
    effect    = "Deny"
    actions   = ["wafv2:DeleteWebACL", "wafv2:DisassociateWebACL"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyIamPrivilegeEscalation"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
      "iam:UpdateLoginProfile",
      "iam:AttachUserPolicy",
      "iam:PutUserPolicy",
      "iam:AttachGroupPolicy",
      "iam:PutGroupPolicy",
      "iam:AttachRolePolicy",
      "iam:PutRolePolicy",
      "iam:AddUserToGroup",
      "iam:CreatePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:UpdateAssumeRolePolicy",
      "iam:PassRole",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "deny_dangerous_actions" {
  provider = aws.workloads
  name     = "novapay-deny-dangerous-actions"
  policy   = data.aws_iam_policy_document.deny_dangerous_actions.json
}

resource "aws_iam_user_policy_attachment" "test_deny_dangerous_actions" {
  provider   = aws.workloads
  user       = aws_iam_user.test.name
  policy_arn = aws_iam_policy.deny_dangerous_actions.arn
}

data "aws_caller_identity" "current" {}

# Scoped Allow: read-only visibility into the D2 resources already applied
# (networking, WAF, budget). Nothing here can create/modify/delete anything —
# proves least-privilege in practice (Allow) alongside the Deny guardrail above.
data "aws_iam_policy_document" "read_only_d2" {
  statement {
    sid    = "ReadOnlyNetworking"
    effect = "Allow"
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeRouteTables",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeNatGateways",
    ]
    # EC2 Describe* actions don't support resource-level permissions.
    resources = ["*"]
  }

  statement {
    sid       = "ReadOnlyWafList"
    effect    = "Allow"
    actions   = ["wafv2:ListWebACLs"]
    resources = ["*"]
  }

  statement {
    sid     = "ReadOnlyWafGet"
    effect  = "Allow"
    actions = ["wafv2:GetWebACL"]
    # Wildcard rather than a reference: the web ACL is defined in the workload
    # stack now, and a deny that only covers one ACL by ARN stops covering
    # anything the moment that ACL is recreated with a new id.
    resources = ["arn:aws:wafv2:eu-west-1:${aws_organizations_account.workloads.id}:regional/webacl/*"]
  }

  # ReadOnlyBudget statement removed 2026-08-08: this test user now lives in
  # the Workloads account (D2 migration, SECURITY_DECISIONS.md), but the
  # budget stays in Management to see org-wide consolidated cost. AWS Budgets
  # has no resource-based/cross-account policy — an identity policy in one
  # account can name another account's budget ARN, but AWS denies the call
  # at runtime regardless, so the statement would be a no-op if left in.

  # ReadOnlySecret statement removed 2026-07-17: the secret it referenced
  # (aws_secretsmanager_secret.db_credentials) was destroyed after evidence
  # capture. Re-add it, referencing the secret's ARN again, once Secrets
  # Manager is re-applied for real (see SECURITY_DECISIONS.md 2026-07-17).
}

resource "aws_iam_policy" "read_only_d2" {
  provider = aws.workloads
  name     = "novapay-read-only-d2"
  policy   = data.aws_iam_policy_document.read_only_d2.json
}

resource "aws_iam_user_policy_attachment" "test_read_only_d2" {
  provider   = aws.workloads
  user       = aws_iam_user.test.name
  policy_arn = aws_iam_policy.read_only_d2.arn
}

output "test_user_access_key_id" {
  value = aws_iam_access_key.test.id
}

output "test_user_secret_access_key" {
  value     = aws_iam_access_key.test.secret
  sensitive = true
}
