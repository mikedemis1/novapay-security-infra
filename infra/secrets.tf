# Placeholder DB credentials for NovaPay's future RDS instance (D2 ⑤). No RDS
# yet — secret exists ready-for-use, same pattern as the KMS key in kms.tf.
resource "random_password" "db_credentials" {
  length  = 32
  special = true
}

# Uses the AWS-managed key (aws/secretsmanager), not novapay-transaction-key:
# the CMK grants zero kms:Encrypt/Decrypt/GenerateDataKey to any principal by
# design (kms.tf), and widening it now just to unblock this secret would
# undercut that least-privilege decision for no real consumer yet. Revisit
# once a real app role needs both the CMK and this secret. See
# SECURITY_DECISIONS.md 2026-07-17.
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "novapay/db-credentials"
  recovery_window_in_days = 7

  tags = {
    Name = "novapay-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "novapay_app"
    password = random_password.db_credentials.result
  })
}
