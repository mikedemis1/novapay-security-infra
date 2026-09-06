# DORA Article 9(4)(c) — limit logical access to ICT assets.
#
# The Kubernetes API is the control plane for everything running on the
# cluster. Reachable from the whole internet it is guarded by authentication
# alone, and it was, purely because that is the module default rather than
# anything anyone chose.
package main

import rego.v1

deny contains msg if {
	some name, mod in input.module
	contains(mod.source, "terraform-aws-modules/eks")
	mod.cluster_endpoint_public_access == true
	not mod.cluster_endpoint_public_access_cidrs
	msg := sprintf("module.%s: public API endpoint with no cluster_endpoint_public_access_cidrs (DORA Art. 9(4)(c))", [name])
}
