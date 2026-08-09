# D1 Secure Landing Zone — threat detection.
# CloudTrail records what happened; GuardDuty flags what looks malicious
# (recon, credential compromise, C2 traffic) by analyzing CloudTrail, VPC
# Flow Logs, and DNS — no extra logging pipeline needed.
#
# TEMPORARY: no real Security account exists yet (see organizations.tf), so
# the delegated admin points at this Management account for now. Revisit
# once the real Security account is created.

resource "aws_guardduty_detector" "main" {
  enable = true
}

resource "aws_guardduty_detector_feature" "s3_data_events" {
  detector_id = aws_guardduty_detector.main.id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "ebs_malware_protection" {
  detector_id = aws_guardduty_detector.main.id
  name        = "EBS_MALWARE_PROTECTION"
  status      = "ENABLED"
}

resource "aws_guardduty_organization_admin_account" "main" {
  admin_account_id = data.aws_caller_identity.current.account_id
}

resource "aws_guardduty_organization_configuration" "main" {
  detector_id                      = aws_guardduty_detector.main.id
  auto_enable_organization_members = "ALL"

  # Without this, Terraform may call UpdateOrganizationConfiguration before
  # EnableOrganizationAdminAccount has finished propagating on AWS's side —
  # that's what threw "delegated administrator account has not been enabled".
  depends_on = [aws_guardduty_organization_admin_account.main]
}
