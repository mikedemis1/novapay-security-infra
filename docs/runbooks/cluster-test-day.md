# Runbook: cluster test day

The cluster costs roughly 0.10 USD per hour for the control plane alone, plus a
NAT gateway, so it goes up, gets tested and comes down in one sitting. Applying
it and leaving it overnight is the single easiest way to overrun the budget.

Run the steps in order. Steps 3 to 6 are the point: they try to break each
control. A control that has only been observed to exist has not been tested,
which is how the network policies passed the first review while enforcing
nothing.

## Before

The platform stack must be applied first; this stack reads its outputs.

1. `terraform apply` in `infra/workload` — brings up NAT gateway, EKS cluster + node group, IRSA
   role, Kyverno, the placeholder namespace/deployment/service, Kyverno
   ClusterPolicies, NetworkPolicies. Expect 15-20 minutes for the EKS
   control plane and node to become ready.
2. `aws eks update-kubeconfig --name novapay-eks --region eu-west-1` (with
   the Workloads-account credentials/role) to point `kubectl` at the
   cluster.
3. **Verify Pod Security Standards blocks a privileged pod on purpose:**
   apply a throwaway Pod manifest with `privileged: true` in the
   `novapay-app` namespace — the API server must reject it outright
   (before Kyverno even sees it). Capture the rejection message.
4. **Verify Kyverno blocks on purpose:** apply a throwaway Pod with no
   resource requests/limits, and a separate one using an image from a
   registry not on the allowlist (e.g. `docker.io/library/alpine`) —
   Kyverno must deny both. Capture `kubectl describe` / the admission
   error for each.
5. **Verify IRSA actually works and is actually scoped:** `kubectl exec`
   into the running `novapay-transaction-service` pod and confirm it can
   `aws secretsmanager get-secret-value` the D2 secret using its pod
   identity (no static keys anywhere), and separately confirm it
   **cannot** access any other secret/resource — the negative test matters
   as much as the positive one.
6. **Verify NetworkPolicy actually blocks:** `kubectl exec` into the pod,
   confirm DNS resolution works (`nslookup kubernetes.default`) but an
   outbound HTTP request to an arbitrary external site times out/fails.
7. **Trivy scan** (no local install — uses Docker Desktop, already
   installed):
   ```
   docker run --rm aquasec/trivy image nginxinc/nginx-unprivileged:1.27-alpine \
     > evidence/d3-trivy-scan-nginx-unprivileged.txt
   ```
   Whatever it finds is real evidence, not fabricated — if it's clean,
   that's the finding; if it finds CVEs, that becomes a documented, honest
   descoping note (matches the project's existing "designed, not
   implemented" convention) rather than something to hide.
8. Screenshot / copy the key outputs above into `evidence/`, same
   convention as `evidence/secrets-manager-applied.jpg`.
9. `terraform destroy` — same day, don't let this run overnight.

## Note on step 1

The original version of this runbook described a single `terraform apply`. That
could never have worked: the Kyverno cluster policies are custom resources whose
definition is installed by the Helm release in the same run, and the manifests
are validated at plan time against a cluster that does not exist yet. The
sequence that actually worked used `-target`, and was never written down. The
stack split fixed the first half of that; the Kyverno policies still depend on
the Helm release, so apply the release first if a fresh cluster refuses.
