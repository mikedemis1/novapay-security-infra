# D1 Secure Landing Zone — threat detection.
# CloudTrail records what happened; GuardDuty flags what looks malicious
# (reconnaissance, credential compromise, command-and-control traffic) by
# reading CloudTrail, VPC flow logs and DNS internally. No logging pipeline
# of our own is needed for it.
#
# The administrator is the Security account, not this one. AWS recommends
# against making the management account the delegated administrator, for the
# same reason SCPs do not apply there: it is the most privileged account in
# the organisation and the one whose compromise you can least afford to
# widen. Until 2026-09-06 it was the administrator anyway, left over from
# when no member account existed.
#
# Every account still needs its own detector, including this one. Delegating
# administration moves who reads the findings, not where they are produced.

# Renamed when the Security account became the administrator: this detector
# is now one member among three, not "the" one.
moved {
  from = aws_guardduty_detector.main
  to   = aws_guardduty_detector.management
}

resource "aws_guardduty_detector" "management" {
  enable = true
}

resource "aws_guardduty_detector" "security" {
  provider = aws.security
  enable   = true
}

# Designating the administrator is one of the few things only the management
# account can do, so this resource stays on the default provider even though
# everything it configures lives elsewhere.
resource "aws_guardduty_organization_admin_account" "main" {
  admin_account_id = aws_organizations_account.security.id
}

resource "aws_guardduty_organization_configuration" "main" {
  provider                         = aws.security
  detector_id                      = aws_guardduty_detector.security.id
  auto_enable_organization_members = "ALL"

  # Without this, Terraform may call UpdateOrganizationConfiguration before
  # EnableOrganizationAdminAccount has finished propagating on AWS's side.
  # That is what threw "delegated administrator account has not been enabled".
  depends_on = [aws_guardduty_organization_admin_account.main]
}

# Protection plans are configured per feature at the organisation level, not
# by enabling them on one detector. Enabling them on the administrator's own
# detector protects the administrator and nothing else, which is what the
# earlier version did: S3 and malware protection were on in the management
# account, the one account with no application data and no EC2 instances.
resource "aws_guardduty_organization_configuration_feature" "s3_data_events" {
  provider    = aws.security
  detector_id = aws_guardduty_detector.security.id
  name        = "S3_DATA_EVENTS"
  auto_enable = "ALL"
}

resource "aws_guardduty_organization_configuration_feature" "ebs_malware_protection" {
  provider    = aws.security
  detector_id = aws_guardduty_detector.security.id
  name        = "EBS_MALWARE_PROTECTION"
  auto_enable = "ALL"
}

# Known limit, recorded rather than left implicit: this is eu-west-1 only,
# while the organisation trail is multi-region. Activity in another region is
# recorded but not analysed. The region-deny SCP (scp.tf) is what makes that
# a scope decision instead of a gap, since resources cannot legitimately
# appear elsewhere in the member accounts.
