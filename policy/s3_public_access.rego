# DORA Article 9(3)(b) — minimise the risk of unauthorised access.
#
# Every bucket in this estate holds either audit logs or Terraform state, and
# both are worth more to an attacker than to anyone else.
#
# Ceiling worth knowing: Conftest evaluates one file at a time, so this rule
# only sees a bucket and a public access block if they are written in the same
# file. Splitting them would produce a false FAIL here, not a false pass, so
# the rule stays safe when the convention breaks; it just becomes wrong in the
# noisy direction. Every bucket in this repository keeps its block beside it,
# which is the convention this depends on.
#
# The cross-file case is covered by checkov's CKV2_AWS_6, a graph check that
# resolves references across a directory, and checkov blocks the merge. Making
# this rule match it would mean running the whole suite under --combine, which
# changes the input shape for all nine policies to fix a rule that already
# fails in the direction that gets noticed.
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
