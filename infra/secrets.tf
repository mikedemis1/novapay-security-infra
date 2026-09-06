# Placeholder DB credentials for NovaPay's future RDS instance (D2 ⑤). No RDS
# yet — secret exists ready-for-use, same pattern as the KMS key in kms.tf.
resource "random_password" "db_credentials" {
  length  = 32
  special = true
}

# Encrypted with novapay-transaction-key rather than aws/secretsmanager. The
# CMK grants no usage actions to anyone directly; it allows the account's
# principals to use it only through Secrets Manager (kms:ViaService in
# kms.tf), so reading this secret is the one thing the key can do.
resource "aws_secretsmanager_secret" "db_credentials" {
  provider                = aws.workloads
  name                    = "novapay/db-credentials"
  recovery_window_in_days = 7
  kms_key_id              = aws_kms_key.app_data.arn

  # checkov:skip=CKV2_AWS_57: there is no database to rotate against yet, so a
  # rotation Lambda would rotate a value nothing reads. Revisit with the RDS
  # instance. Note the placement: checkov only reads skip comments inside the
  # resource block, which is why the earlier one above the block never applied.

  tags = {
    Name = "novapay-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  provider  = aws.workloads
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "novapay_app"
    password = random_password.db_credentials.result
  })
}
