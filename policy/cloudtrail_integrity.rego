# DORA Article 9(4)(d) — cryptographic protection, and Article 10(1) — prompt
# detection of anomalous activity, which depends on the record being both
# complete and trustworthy.
#
# Log file validation is what lets you show a log was not edited after the
# fact. A customer-managed key is what stops the log being readable by anyone
# who can read the bucket. This project shipped for a month believing it had
# the second one because the bucket default said so, while the trail wrote
# SSE-S3; the rule checks the trail, not the bucket.
package main

import rego.v1

deny contains msg if {
	some name, trail in input.resource.aws_cloudtrail
	not trail.enable_log_file_validation
	msg := sprintf("aws_cloudtrail.%s: enable_log_file_validation must be true (DORA Art. 10(1))", [name])
}

deny contains msg if {
	some name, trail in input.resource.aws_cloudtrail
	not trail.kms_key_id
	msg := sprintf("aws_cloudtrail.%s: kms_key_id must be set, or the trail writes SSE-S3 whatever the bucket default says (DORA Art. 9(4)(d))", [name])
}

# Setting kms_key_id to alias/aws/s3 passes the presence check above and
# leaves the trail exactly as readable as it was.
deny contains msg if {
	some name, trail in input.resource.aws_cloudtrail
	startswith(trail.kms_key_id, "alias/aws/")
	msg := sprintf("aws_cloudtrail.%s: kms_key_id is %s, an AWS-managed key (DORA Art. 9(4)(d))", [name, trail.kms_key_id])
}
