# DORA Article 9(4)(c) — limit logical access to ICT assets.
#
# The Kubernetes API is the control plane for everything running on the
# cluster. Reachable from the whole internet it is guarded by authentication
# alone, and it was, purely because that is the module default rather than
# anything anyone chose.
package main

import rego.v1

# Requiring the list to merely exist was the bug: ["0.0.0.0/0"] is a CIDR
# list, satisfies the check, and is the exact state the rule exists to stop.
unrestricted(mod) if not mod.cluster_endpoint_public_access_cidrs

unrestricted(mod) if "0.0.0.0/0" in mod.cluster_endpoint_public_access_cidrs

deny contains msg if {
	some name, mod in input.module
	contains(mod.source, "terraform-aws-modules/eks")
	mod.cluster_endpoint_public_access == true
	unrestricted(mod)
	msg := sprintf("module.%s: public API endpoint not restricted to named CIDRs (DORA Art. 9(4)(c))", [name])
}
