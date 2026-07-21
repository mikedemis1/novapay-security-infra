# CMK for future NovaPay transaction data at rest (D2 ④). No S3/RDS yet —
# key exists ready-for-use; wire it to a real resource when one exists.
resource "aws_kms_key" "transactions" {
  description             = "novapay-transaction-key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_transactions.json
}

resource "aws_kms_alias" "transactions" {
  name          = "alias/novapay-transaction-key"
  target_key_id = aws_kms_key.transactions.key_id
}

# Admin (root) gets management actions only — no kms:Encrypt/Decrypt/GenerateDataKey.
# Usage actions go to an app role once real data exists (test-user has no business here).
data "aws_iam_policy_document" "kms_transactions" {
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
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:CreateAlias",
    ]
    resources = ["*"]
  }
}
