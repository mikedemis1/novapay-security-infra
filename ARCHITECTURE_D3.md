# D3 — EKS Workload Security

## Design (lightweight, pre-build)

Placeholder "transaction service" (`nginxinc/nginx-unprivileged`, no real
app exists yet — same pattern as the D2 KMS key/Secrets Manager secret)
running on a single-node EKS cluster in the Workloads account, inside the
existing D2 VPC's private app subnets. Purpose: have something real to
attach security controls to, not to ship a working payment service.

- **EKS** (community `terraform-aws-modules/eks/aws` module) — 1× `t3.medium`
  managed node group, in `app_a`/`app_b` private subnets.
- **NAT Gateway** — temporary, test-day only. D2 deliberately has none; EKS
  nodes need outbound (image pulls, EKS API). Destroyed with everything else.
- **IRSA** — the app's pod gets an IAM role scoped to `secretsmanager:GetSecretValue`
  on exactly the D2 `novapay/db-credentials` secret, nothing else.
- **Kyverno** (Helm, single-replica) — 2 custom `ClusterPolicy` resources:
  require resource requests/limits, restrict image registries to an
  allowlist. Deliberately not duplicating what Pod Security Standards
  already covers (privileged/root/capabilities).
- **Pod Security Standards** — `restricted` enforced via namespace label
  (native to Kubernetes 1.23+, no extra install).
- **NetworkPolicy** — default-deny both directions in the namespace, one
  explicit allow for DNS egress. Same "explicit allow only" pattern as the
  D2 security group chain.
- **Trivy** — one-off scan of the placeholder image via `docker run`
  (no local install needed), evidence captured as a report file.

## Threat model (brief, per-deliverable not per-resource)

| Asset | Attacker / attack path | Mitigation here |
|---|---|---|
| Node / cluster | Privileged or root container escapes to node | Pod Security Standards (`restricted`) + pod-level `securityContext` |
| Container image | Known CVE in a vulnerable/malicious image | Trivy scan (evidence-only here, becomes a CI gate in D4) |
| IRSA credentials | Over-scoped IAM role lets a compromised pod read unrelated secrets/data | Role scoped to exactly one secret ARN, one action |
| Pod-to-pod / pod-to-internet | No network segmentation lets a compromised pod pivot or exfiltrate | Default-deny NetworkPolicy, DNS-only egress allowed |
| Supply chain | Pod pulls an image from an untrusted registry | Kyverno `restrict-image-registries` policy |

## Cost / blast radius

EKS control plane bills **hourly** (~0.10 USD/h) regardless of use — unlike
the WAF (flat existence cost), a forgotten cluster adds up fast: a week
left running ≈ 24 USD, a month ≈ 100 USD, blowing the 40 EUR/month cap on
its own. NAT Gateway adds ~0.045 USD/h + data processing — negligible for a
few hours, not for a month. **Both get destroyed the same day**, right
after evidence capture below. Nothing here is customer-facing or holds real
data — blast radius of getting a policy wrong is "the demo pod doesn't
start," not an outage.

## Test-day runbook (run in order; this is the verification, not the code review)

1. `terraform apply` — brings up NAT Gateway, EKS cluster + node group, IRSA
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

## Test-day results (2026-08-09, executed live)

All 5 controls were verified with a deliberate violation or a real positive/negative test, not just "the Terraform applied cleanly":

1. **Pod Security Standards** — a throwaway `Pod` with `privileged: true` was rejected outright by the API server before Kyverno even saw it: `violates PodSecurity "restricted:latest": privileged (container "test" must not set securityContext.privileged=true), ...`. Confirmed blocking.
2. **Kyverno `restrict-image-registries`** — a pod using `docker.io/library/alpine` was denied: `admission webhook "validate.kyverno.svc-fail" denied the request: ... Images must come from an approved registry`. Confirmed blocking.
3. **Kyverno `require-requests-limits`** — a pod with no resource requests/limits was denied with the same webhook, citing the missing `/spec/containers/0/resources/limits/`. Confirmed blocking.
4. **IRSA** — a debug pod using the same `novapay-transaction-service` service account successfully read the exact D2 secret (`aws secretsmanager get-secret-value --secret-id novapay/db-credentials`), and was denied `secretsmanager:ListSecrets` and `s3:ListAllMyBuckets` with `AccessDeniedException` for the assumed role `novapay-transaction-service-irsa`. Confirmed both the positive (scoped access works) and negative (nothing beyond that scope) case.
5. **NetworkPolicy** — **failed on first attempt**: DNS resolved correctly but an outbound HTTPS request to `example.com` *succeeded* when it should have been blocked. Root cause: the default AWS VPC CNI addon does not enforce `NetworkPolicy` objects at all without `enableNetworkPolicy: "true"` set on the `vpc-cni` addon's configuration — the policies existed in the Kubernetes API and did nothing. Added an explicit `aws_eks_addon` block for `vpc-cni` with that config (`eks.tf`), which triggered the `aws-node` DaemonSet to redeploy with a second container (the network policy agent, confirmed via `kubectl get pods -n kube-system -l k8s-app=aws-node` going from 1/1 to 2/2). Re-tested after: DNS still resolved, HTTPS now timed out as expected. This is the kind of gap that only shows up by actually testing the control, not by reading the Terraform diff — worth remembering for any future NetworkPolicy work on this or other clusters.

**Trivy scan** (`evidence/d3-trivy-scan-nginx-unprivileged.txt`): `nginxinc/nginx-unprivileged:1.27-alpine` — **105 vulnerabilities** (2 CRITICAL, 31 HIGH, 46 MEDIUM, 26 LOW), mostly in the Alpine base (musl, zlib, libxml2, nghttp2, openssl). Real findings from a real scan, not fabricated. Accepted as-is for this placeholder/demo purpose (no real app exists yet, per the 2026-08-09 decision) — if this were a real workload, patching the base image or moving to a distroless/minimal image would be the next step, and D4's CI gate is where this scan becomes a blocking check on every future image, not a one-off.

## What's deliberately out of scope here (say so honestly, don't hide it)

- No real transaction service — placeholder only, per 2026-08-09 decision.
- Kyverno policies aren't exhaustive (only 2, chosen to avoid duplicating
  Pod Security Standards) — a real production cluster would have more.
- Trivy is a one-off manual scan here, not a CI gate yet — that's D4's job.
- Single node, single replica everywhere — this is a lab, not HA prod.
