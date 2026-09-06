# DORA Article 9(4)(d) — protection measures for cryptographic keys.
#
# A customer-managed key that never rotates means one key protects every
# object for the life of the system. Rotation is a single boolean here, which
# is exactly why it gets forgotten.
package main

import rego.v1

deny contains msg if {
	some name, key in input.resource.aws_kms_key
	not key.enable_key_rotation
	msg := sprintf("aws_kms_key.%s: enable_key_rotation must be true (DORA Art. 9(4)(d))", [name])
}
