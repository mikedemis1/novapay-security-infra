# DORA Article 9(4)(d) — cryptographic protection, and Article 10(1) — prompt
# detection of anomalous activity, which depends on the record being both
# complete and trustworthy.
#
# Log file validation is what lets you show a log was not edited after the
# fact. This project shipped for a month believing a customer-managed key
# additionally stopped the log being readable by anyone who could read the
# bucket, because the bucket default said so, while the trail actually wrote
# SSE-S3 regardless (CloudTrail sets its own per-object encryption, which
# always beats the bucket default). See README.md "What broke" and
# SECURITY_DECISIONS.md 2026-09-06/2026-09-11.
#
# 2026-09-11: rather than fix the apply-order bug that kept the CMK from ever
# taking effect, the key was dropped (five-agent review, SECURITY_DECISIONS.md
# "The CloudTrail CMK is dropped instead of fixed") — it cost ~1-2 USD/month
# for a control that had never once run. SSE-S3 is accepted here as this
# trail's cryptographic protection under Art. 9(4)(d): every object is still
# encrypted at rest, log-file validation (checked below) is what this project
# relies on for Art. 10(1) integrity, and a CMK's extra value — restricting
# *who* can decrypt, beyond default SSE-S3 semantics — was deliberately traded
# for keeping a working, honestly-labelled control rather than a hard
# requirement that hid a silent no-op. If a real customer-managed key is
# wired in again, the ban on AWS-managed aliases below still applies.
package main

import rego.v1

deny contains msg if {
	some name, trail in input.resource.aws_cloudtrail
	not trail.enable_log_file_validation
	msg := sprintf("aws_cloudtrail.%s: enable_log_file_validation must be true (DORA Art. 10(1))", [name])
}

# Setting kms_key_id to alias/aws/s3 would pass a naive presence check and
# leave the trail exactly as readable as plain SSE-S3 while claiming more.
deny contains msg if {
	some name, trail in input.resource.aws_cloudtrail
	trail.kms_key_id
	startswith(trail.kms_key_id, "alias/aws/")
	msg := sprintf("aws_cloudtrail.%s: kms_key_id is %s, an AWS-managed key dressed up as a CMK (DORA Art. 9(4)(d))", [name, trail.kms_key_id])
}
