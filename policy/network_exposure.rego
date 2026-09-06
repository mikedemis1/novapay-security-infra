# DORA Article 9(4)(c) — logical access on a least-privilege basis.
#
# Open ingress is the least-privilege failure that costs nothing to introduce
# and is hardest to notice later. 443 from anywhere is what a public service is
# for; anything else from anywhere is a mistake, or a decision that belongs in
# writing.
#
# The normalisation below is not decoration. The first version of this rule was
# written as "some rule in sg.ingress" and passed against a security group that
# allowed 22 from 0.0.0.0/0, because the HCL parser represents one ingress block
# as an object and several as a list. Iterating the object walked the field
# values, none of which have a cidr_blocks key, so the rule found nothing and
# reported success. It would have started working by accident the day someone
# added a second ingress block.
#
# The lesson is the one worth keeping: a policy that has only ever been run
# against compliant input has not been tested. This one is exercised against a
# deliberate violation in policy/fixtures.
package main

import rego.v1

# Always a list, whether the source had one block or many.
ingress_rules(sg) := sg.ingress if is_array(sg.ingress)

ingress_rules(sg) := [sg.ingress] if is_object(sg.ingress)

deny contains msg if {
	some name, sg in input.resource.aws_security_group
	some rule in ingress_rules(sg)
	"0.0.0.0/0" in rule.cidr_blocks
	rule.from_port != 443
	msg := sprintf("aws_security_group.%s: ingress from 0.0.0.0/0 on port %v; only 443 may be world-reachable (DORA Art. 9(4)(c))", [name, rule.from_port])
}
