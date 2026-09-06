# DORA Article 9(4)(c) — least privilege, and 9(4)(d) — strong authentication.
#
# A static access key is a credential with no expiry that has to live
# somewhere. Terraform-created keys are worse than console-created ones,
# because the secret is written to state in plaintext and often to an output
# as well. This repo had exactly that until 2026-09-06.
package main

import rego.v1

deny contains msg if {
	some name, _ in input.resource.aws_iam_access_key
	msg := sprintf("aws_iam_access_key.%s: no long-lived access keys; use a role that is assumed (DORA Art. 9(4)(d))", [name])
}

deny contains msg if {
	some name, _ in input.resource.aws_iam_user
	msg := sprintf("aws_iam_user.%s: humans arrive through Identity Center and workloads use roles (DORA Art. 9(4)(c))", [name])
}
