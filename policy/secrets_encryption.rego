# DORA Article 9(2) — protection of data at rest, and 9(4)(d) — key management.
#
# The AWS-managed key works, but it cannot be scoped: any principal in the
# account with secretsmanager permissions can decrypt. A customer-managed key
# turns "who can read this secret" into something a key policy answers.
package main

import rego.v1

deny contains msg if {
	some name, secret in input.resource.aws_secretsmanager_secret
	not secret.kms_key_id
	msg := sprintf("aws_secretsmanager_secret.%s: kms_key_id must be a customer-managed key (DORA Art. 9(2))", [name])
}

# alias/aws/secretsmanager satisfies "kms_key_id is set" while being precisely
# the AWS-managed key the rule above exists to reject.
deny contains msg if {
	some name, secret in input.resource.aws_secretsmanager_secret
	startswith(secret.kms_key_id, "alias/aws/")
	msg := sprintf("aws_secretsmanager_secret.%s: kms_key_id is %s, an AWS-managed key (DORA Art. 9(2))", [name, secret.kms_key_id])
}
