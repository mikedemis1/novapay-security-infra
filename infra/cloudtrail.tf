# D1 Secure Landing Zone - centralized log bucket + org-wide CloudTrail.
# Doesn't need the member accounts to exist yet: an organization trail
# automatically starts logging any account added to the org later.

resource "aws_s3_bucket" "cloudtrail_logs" {
  #checkov:skip=CKV_AWS_18:Access logging on this bucket would need a second bucket, which the same check then wants logged, and so on. The reads worth catching here are API calls, and CloudTrail data events record those against the bucket directly. Not adding a bucket to satisfy a check that would immediately fire on the new one.
  #checkov:skip=CKV_AWS_144:Cross-region replication doubles the storage bill of the bucket that grows fastest in this estate, against a failure mode (loss of an entire AWS region) that this lab does not otherwise design for. Versioning and MFA-less deletion protection cover the realistic case, which is a mistake rather than a region outage.
  #checkov:skip=CKV2_AWS_62:Event notifications need something to notify. Nothing consumes object-created events on this bucket; findings reach the Security account through GuardDuty and EventBridge, which is the path that is actually wired up and tested.
  bucket = "novapay-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"

  # The whole point of this resource is to survive mistakes, including mine.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning is on, so every overwritten object is kept forever unless
# something expires it. For a bucket that receives org-wide CloudTrail this is
# the difference between a fixed monthly cost and one that only goes up.
# Current versions are kept: they are the audit record. Non-current ones are
# an artefact of versioning, not evidence.
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    id     = "expire-noncurrent-and-incomplete"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.cloudtrail_logs]
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cloudtrail_logs.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# The trail's ARN is built from its known, predictable format rather than
# referenced from aws_cloudtrail.org_trail.arn - that resource attribute
# would create a circular dependency (bucket policy needs the trail ARN,
# but the trail needs the bucket policy to exist first).
locals {
  org_trail_name = "novapay-org-trail"
  org_trail_arn  = "arn:aws:cloudtrail:eu-west-1:${data.aws_caller_identity.current.account_id}:trail/${local.org_trail_name}"
}

data "aws_iam_policy_document" "cloudtrail_logs" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail_logs.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.org_trail_arn]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["s3:PutObject"]
    resources = [
      # Member-account log prefix (org-wide) and the management account's
      # own log prefix (account ID, not org ID) both need to be writable.
      "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${aws_organizations_organization.main.id}/*",
      "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.org_trail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_logs.json
}

resource "aws_cloudtrail" "org_trail" {
  name           = local.org_trail_name
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs.id

  is_organization_trail = true
  is_multi_region_trail = true
  #checkov:skip=CKV2_AWS_10:CloudWatch Logs delivery bills per GB ingested on top of the S3 copy already being written, and an org-wide trail is the highest-volume source here. The queries it would enable are served by Athena over the bucket instead, at storage cost only. Revisit if real-time metric filters become the alerting path; today that path is GuardDuty to EventBridge.
  #checkov:skip=CKV_AWS_252:The SNS topic on a trail notifies on log file delivery, not on anything security-relevant, and this estate already alerts on findings rather than on the fact that a log arrived. Wiring it would add noise to the one topic that currently only carries HIGH and CRITICAL.
  include_global_service_events = true
  enable_log_file_validation    = true

  # Without this the trail encrypts with SSE-S3 regardless of what the bucket
  # default says: CloudTrail sets the algorithm on its own PutObject, and the
  # per-object choice wins over the bucket default. That is how the 2026-08-08
  # "fix" silently did nothing for a month.
  kms_key_id = aws_kms_key.cloudtrail_logs.arn

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]

  # A destroy here stops the recording for every account at once.
  lifecycle {
    prevent_destroy = true
  }
}
