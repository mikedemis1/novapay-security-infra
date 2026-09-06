# DORA Article 9(3)(b) — minimise the risk of unauthorised access.
#
# Every bucket in this estate holds either audit logs or Terraform state, and
# both are worth more to an attacker than to anyone else.
package main

import rego.v1

blocked_bucket contains bucket if {
	some _, block in input.resource.aws_s3_bucket_public_access_block
	bucket := block.bucket
}

deny contains msg if {
	some name, _ in input.resource.aws_s3_bucket
	ref := sprintf("${aws_s3_bucket.%s.id}", [name])
	not ref in blocked_bucket
	msg := sprintf("aws_s3_bucket.%s: needs a matching aws_s3_bucket_public_access_block (DORA Art. 9(3)(b))", [name])
}
