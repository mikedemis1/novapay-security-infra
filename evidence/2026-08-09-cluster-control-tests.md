# Cluster control tests, 2026-08-09

Five controls, each tested by trying to violate it rather than by confirming it
existed. One of the five turned out not to be working at all, and it looked
identical to the four that were.

Terminal output rather than screenshots: none of this is visual, and the
cluster was destroyed the same day. Account identifiers are not present because
none of these messages carry them.

Verified with a deliberate violation or a real positive and negative test, not with "the Terraform applied cleanly":

1. **Pod Security Standards** — a throwaway `Pod` with `privileged: true` was rejected outright by the API server before Kyverno even saw it: `violates PodSecurity "restricted:latest": privileged (container "test" must not set securityContext.privileged=true), ...`. Confirmed blocking.
2. **Kyverno `restrict-image-registries`** — a pod using `docker.io/library/alpine` was denied: `admission webhook "validate.kyverno.svc-fail" denied the request: ... Images must come from an approved registry`. Confirmed blocking.
3. **Kyverno `require-requests-limits`** — a pod with no resource requests/limits was denied with the same webhook, citing the missing `/spec/containers/0/resources/limits/`. Confirmed blocking.
4. **IRSA** — a debug pod using the same `novapay-transaction-service` service account successfully read the exact D2 secret (`aws secretsmanager get-secret-value --secret-id novapay/db-credentials`), and was denied `secretsmanager:ListSecrets` and `s3:ListAllMyBuckets` with `AccessDeniedException` for the assumed role `novapay-transaction-service-irsa`. Confirmed both the positive (scoped access works) and negative (nothing beyond that scope) case.
5. **NetworkPolicy** — **failed on first attempt**: DNS resolved correctly but an outbound HTTPS request to `example.com` *succeeded* when it should have been blocked. Root cause: the default AWS VPC CNI addon does not enforce `NetworkPolicy` objects at all without `enableNetworkPolicy: "true"` set on the `vpc-cni` addon's configuration — the policies existed in the Kubernetes API and did nothing. Added an explicit `aws_eks_addon` block for `vpc-cni` with that config (`eks.tf`), which triggered the `aws-node` DaemonSet to redeploy with a second container (the network policy agent, confirmed via `kubectl get pods -n kube-system -l k8s-app=aws-node` going from 1/1 to 2/2). Re-tested after: DNS still resolved, HTTPS now timed out as expected. This is the kind of gap that only shows up by actually testing the control, not by reading the Terraform diff — worth remembering for any future NetworkPolicy work on this or other clusters.

**Trivy scan** (`evidence/d3-trivy-scan-nginx-unprivileged.txt`): `nginxinc/nginx-unprivileged:1.27-alpine` — **105 vulnerabilities** (2 CRITICAL, 31 HIGH, 46 MEDIUM, 26 LOW), mostly in the Alpine base (musl, zlib, libxml2, nghttp2, openssl). Real findings from a real scan, not fabricated. Accepted as-is for this placeholder/demo purpose (no real app exists yet, per the 2026-08-09 decision) — if this were a real workload, patching the base image or moving to a distroless/minimal image would be the next step, and D4's CI gate is where this scan becomes a blocking check on every future image, not a one-off.
