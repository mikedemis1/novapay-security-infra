# Renamed in place (no destroy) when this key stopped being a generic
# "future transaction data" CMK and became the trail's key. The rename used a
# moved block so the already-encrypted log objects were never rewritten.
#
# Placement is a known compromise, not the target: the key sits in the same
# account as the trail it protects, and that account is itself audited by the
# trail and exempt from every SCP. The AWS SRA puts log keys in the Log
# Archive account for exactly that reason. Recorded rather than hidden.
moved {
  from = aws_kms_key.transactions
  to   = aws_kms_key.cloudtrail_logs
}

moved {
  from = aws_kms_alias.transactions
  to   = aws_kms_alias.cloudtrail_logs
}

# CMK dedicated to encrypting the org-wide CloudTrail trail (Management
# account). Kept out of Workloads on purpose — see the moved-block comment
# above.
resource "aws_kms_key" "cloudtrail_logs" {
  description             = "novapay-cloudtrail-key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_cloudtrail_logs.json

  # The whole point of this resource is to survive mistakes, including mine. Losing it makes
  # every log object already written unreadable.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "cloudtrail_logs" {
  name          = "alias/novapay-cloudtrail-key"
  target_key_id = aws_kms_key.cloudtrail_logs.key_id
}

# Admin (root) gets management actions only — no kms:Encrypt/Decrypt/GenerateDataKey
# for bulk application data. Usage actions go to an app role once real data
# exists (test-user has no business here).
#
# CloudTrail is this key's only consumer (D1 gap-analysis, 2026-08-08):
# its logs were encrypted with the AWS-managed SSE-S3 key, which can't be
# scoped to specific principals. The 3 statements below give this CMK exactly
# the two actions CloudTrail's own encryption flow needs, plus decrypt for
# the admin who'd actually investigate an incident — both scoped by
# encryption context to this one trail, not a blanket grant.
data "aws_iam_policy_document" "kms_cloudtrail_logs" {
  statement {
    sid    = "AdminManageKey"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions = [
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:PutKeyPolicy",
      "kms:EnableKeyRotation",
      "kms:DisableKeyRotation",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:UpdateKeyDescription",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudTrailToEncryptLogs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    # Decrypt is needed only because the bucket sets bucket_key_enabled:
    # CloudTrail has to read the bucket-level data key before it can write.
    # Both actions stay bound to this one trail by encryption context.
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = [local.org_trail_arn]
    }
  }

  statement {
    sid    = "AllowCloudTrailToDescribeKey"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["kms:DescribeKey"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowAdminToDecryptLogs"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:Decrypt", "kms:ReEncryptFrom"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = [local.org_trail_arn]
    }
  }
}

# CMK for future NovaPay transaction data at rest (D2 ④), now created fresh
# in the Workloads account instead of Management — no S3/RDS yet, key exists
# ready-for-use; wire it to a real resource when one exists.
# Named "app_data" (not "transactions") to avoid colliding with the `moved`
# block above, which already claims the "transactions" address for the
# renamed CloudTrail key.
resource "aws_kms_key" "app_data" {
  provider                = aws.workloads
  description             = "novapay-transaction-key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_app_data.json
}

resource "aws_kms_alias" "app_data" {
  provider      = aws.workloads
  name          = "alias/novapay-transaction-key"
  target_key_id = aws_kms_key.app_data.key_id
}

# Admin (root of the Workloads account) gets management actions only. Usage is
# delegated to IAM, but only through Secrets Manager, so a stolen role cannot
# call Decrypt against this key directly.
data "aws_iam_policy_document" "kms_app_data" {
  statement {
    sid    = "AdminManageKey"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.workloads.account_id}:root"]
    }
    actions = [
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:PutKeyPolicy",
      "kms:EnableKeyRotation",
      "kms:DisableKeyRotation",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:UpdateKeyDescription",
    ]
    resources = ["*"]
  }

  # The consumer is the IRSA role in eks.tf, which is granted
  # secretsmanager:GetSecretValue plus kms:Decrypt on this key. The condition
  # is what keeps that grant narrow: IAM decides who, this decides through
  # what. Repeating the condition on the role's own policy would add nothing,
  # since both policies must allow the call.
  statement {
    sid    = "AllowUseOnlyThroughSecretsManager"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.workloads.account_id}:root"]
    }
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.eu-west-1.amazonaws.com"]
    }
  }
}
