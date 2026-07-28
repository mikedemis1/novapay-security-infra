# Security Decisions — NovaPay P1 (novapay-secure-platform)

Running log of architecture/security decisions and why they were made. Written incrementally as the project progresses (not reconstructed from memory at the end). Part of D5 documentation, started early per playbook guidance.

---

## 2026-07-04 — VPC CIDR block: `10.0.0.0/16`

**Decision:** Use `10.0.0.0/16` as the VPC CIDR range.

**Why:** RFC 1918 private address space. `/16` is the maximum block size AWS allows for a VPC (range is `/16` to `/28`), giving the most room for future subnet growth. The `10.x` range is the standard convention for large/cloud networks (vs. `192.168.x` typically used for home networks).

---

## 2026-07-04 — Subnet sizing: 6× `/19` subnets

**Decision:** Split the VPC into 6 subnets of `/19` each (2 public, 2 app-private, 2 db-private), across 2 Availability Zones.

**Why:** 6 subnets needed → next power of 2 is 8 → 3 bits borrowed from `/16` → `/19` prefix, ~8,192 addresses per subnet. Leaves 2 spare subnet slots for future use. Two AZs for the standard 3-tier (public/app-private/db-private) high-availability pattern.

---

## 2026-07-04 — No NAT Gateway

**Decision:** Private subnets have no route to the internet (no NAT Gateway deployed).

**Why:** NAT Gateway costs ~$30+/month, which alone would exceed most of the project's $40/month budget cap. The app/db tiers don't currently need outbound internet access for this PoC scope. Documented as a deliberate cost trade-off, not an oversight — would be added if a real workload required outbound calls (e.g., third-party API integration).

---

## 2026-07-08 — Security groups: SG-to-SG references instead of CIDR blocks

**Decision:** `app-sg` allows inbound only from `lb-sg` (security-group reference); `db-sg` allows inbound only from `app-sg` — not CIDR ranges.

**Why:** SG-to-SG references are more secure and maintainable than hardcoded IP ranges: they automatically track any instance that gets attached to the referenced SG, don't require knowing/updating IP addresses, and make the trust chain (lb → app → db) explicit and self-documenting in the Terraform code itself.

**Note:** `app-sg` ingress port is `8080` — this is a placeholder assumption and needs to be confirmed against the real application's listening port before this goes further than PoC.

---

## 2026-07-08 — `db-sg` has no egress block at all (deny-all outbound)

**Decision:** `novapay-db-sg` defines zero egress rules (not even a permissive one).

**Why:** Terraform's inline `ingress`/`egress` blocks on `aws_security_group` are authoritative/exhaustive — omitting egress entirely actively removes AWS's default allow-all-outbound behavior, rather than leaving it in place. This makes the db tier a real deny-all-egress boundary: even if compromised, the database instance cannot make outbound connections (blocks data exfiltration). This is a second, independent layer of defense on top of the private route table already having no internet route.

(Newer HashiCorp guidance recommends separate `aws_vpc_security_group_egress_rule` resources, which are additive rather than exhaustive-replace — not adopted yet, noted here as future-reference only.)

---

## 2026-07-08 — AWS Budgets instead of CloudWatch billing alarm

**Decision:** Use `aws_budgets_budget` for the $40/month cost cap, not a CloudWatch billing alarm.

**Why:** CloudWatch billing alarms require a manual one-time "Receive Billing Alerts" console toggle, a `us-east-1` provider alias (billing metrics only exist there), and an SNS topic to deliver notifications. AWS Budgets sends email directly with none of that — simpler for a solo/PoC setup.

**Two-tier notification:** Alerts at $20 and $35 (not just at the $40 cap) — gives an early warning before the hard limit is reached.

---

## 2026-07-09 — Budget currency: USD (confirmed via AWS API, not console)

**Decision:** `limit_unit = "USD"` in `budget.tf` (originally assumed `EUR`).

**Why:** The account's billing currency is USD — discovered directly from the AWS API's rejection error (`InvalidParameterException: EUR is not in the supported unit set: [USD]`) after the IAM console path to check Payment Preferences was blocked by a root-only account setting ("IAM User and Role Access to Billing Information") that wasn't enabled. Using the API error as ground truth avoided a root-login detour.

---

## 2026-07-08 — Scope note: not everything in D2 will be fully implemented

**Decision:** Per the playbook's own scope guidance ("reference architecture + PoC of the highest-risk controls, not the whole bank, not a production rebuild"), some D2 items will be implemented in Terraform (applied to real AWS resources) and others will be documented as "designed, not implemented" where full implementation would be disproportionately costly or complex for a PoC (e.g., full multi-region DR with a tested live failover).

**Why:** Budget ($40/month) and timeline (6 weeks for the whole P1, not just D2) constraints make full implementation of every control impractical. The playbook explicitly permits this trade-off as long as it's labeled honestly rather than silently skipped.

---

## 2026-07-14 — WAF: code-complete in `infra/waf.tf`, not applied; rules in count mode

**Decision:** The WAF web ACL and its 3 rules (`AWSManagedRulesCommonRuleSet`, rate-based limit=2000/IP/5min, `AWSManagedRulesAmazonIpReputationList`) are written and pass `terraform validate`/`fmt`, but are not applied to real AWS resources yet. All 3 rules use `count` mode (monitor-only), not `block`.

**Why:** A WAF web ACL needs something to attach to (ALB/API Gateway/CloudFront) that doesn't exist yet in this project. Applying now would mean paying for an ALB (~$16/month) + WAF (~$5/month) before the rest of the reference architecture is ready to test against it, and before the rules have been observed against real traffic to confirm sane thresholds — both against the $40/month budget cap. Plan: apply everything together in a single test-day once enough of the architecture exists to exercise it, capture evidence (CloudWatch metrics/screenshots) with rules still in count mode, decide count→block per rule from what's actually observed, then destroy the same day.

**Note:** Rate-based rule limit (2000 req/IP/5min) is an unvalidated starting default (common AWS docs example value), not derived from NovaPay's actual traffic — to be confirmed or adjusted from CloudWatch data during the test-day before any block-mode decision.

---

## 2026-07-14 — Geo-blocking and Bot Control: out of scope for WAF (P1)

**Decision:** No country/geo-match rule and no AWS Bot Control managed rule group in `infra/waf.tf`.

**Why:** The playbook doesn't define a target market or a geographic restriction requirement for NovaPay — only the general DORA/EU regulatory context, which doesn't itself mandate geo-blocking. Adding a geo-restriction without a real business requirement behind it would be arbitrary and could block legitimate traffic. Bot Control was excluded separately because it bills per inspected request, an open-ended cost risk incompatible with the fixed $40/month cap.

**Trade-off:** Without geo-blocking, the WAF does not reduce traffic from countries outside any plausible customer base, even though a meaningful share of automated attack traffic often originates from outside a service's real user geography. Revisit if/when a real target market is defined for NovaPay.

---

## 2026-07-17 — KMS key policy: management-only, no usage actions granted yet

**Decision:** `novapay-transaction-key` (CMK, `aws_kms_key` with `deletion_window_in_days=7`, `enable_key_rotation=true`) + `aws_kms_alias` (`alias/novapay-transaction-key`) has a key policy with a single statement: principal = root account, actions limited to 11 management/read operations (`DescribeKey`, `GetKeyPolicy`, `PutKeyPolicy`, `EnableKeyRotation`, `DisableKeyRotation`, `ScheduleKeyDeletion`, `CancelKeyDeletion`, `TagResource`, `GetKeyRotationStatus`, `ListResourceTags`, `CreateAlias`). No usage actions (`Encrypt`, `Decrypt`, `GenerateDataKey`) are granted to any principal.

**Why:** As of this decision, no application role, EC2/EKS instance, or data resource exists yet that would actually need to encrypt/decrypt data with this key — D3 (EKS Workload Security) and the data tier haven't started. Granting `Encrypt`/`Decrypt`/`GenerateDataKey` now would be an unused permission with no consumer, violating least-privilege for no benefit. The key exists now (ahead of its consumers) so that Secrets Manager (D2 ⑤, which depends on both IAM and KMS) can reference it next.

**Note:** The test-user IAM principal used for live-testing D2 resources is deliberately excluded from the key policy — it has no business need to manage or use this key. Revisit the key policy to add scoped `Encrypt`/`Decrypt`/`GenerateDataKey` grants once a real principal (app role, Secrets Manager service integration) needs them — prefer condition-scoped grants over broad ones at that point.

---

## 2026-07-17 — Secrets Manager: AWS-managed key (`aws/secretsmanager`), not the CMK

**Decision:** `infra/secrets.tf` creates `aws_secretsmanager_secret.db_credentials` (placeholder DB credentials for the future RDS instance — no RDS yet) without a `kms_key_id`, so it encrypts with the AWS-managed key `aws/secretsmanager`, not `novapay-transaction-key`.

**Why:** The CMK's key policy grants zero `kms:Encrypt`/`Decrypt`/`GenerateDataKey` to any principal (previous decision, above). Secrets Manager needs those actions on whichever principal creates/reads the secret. Widening the CMK's policy now, with no real consumer, would contradict the least-privilege reasoning just documented for it — so this secret uses the AWS-managed key instead, which needs no policy change.

**Trade-off:** AWS-managed keys can't be scoped with a custom key policy or shared cross-account, and don't demonstrate CMK-based access control. Revisit and migrate this secret to `novapay-transaction-key` once a real app role exists that needs scoped `Decrypt`/`GenerateDataKey` — at that point the CMK policy gets a new statement for that specific role, not a blanket grant.

**IAM:** `novapay-read-only-d2` policy (`infra/iam.tf`) grants the test-user `secretsmanager:GetSecretValue` scoped to this one secret's ARN — same read-only least-privilege pattern as the other D2 grants.

**Applied, evidenced, and destroyed same day (2026-07-17):** secret created live in `eu-west-1`, confirmed in console (`evidence/secrets-manager-applied.jpg`), then destroyed via `terraform destroy -target`. Destroying the secret cascaded to destroy `aws_iam_policy.read_only_d2` and its user attachment too, since the policy document referenced the secret's ARN — a real dependency-graph lesson: `-target` destroy also removes anything that depends on the target, not just the target itself. The `ReadOnlySecret` statement was removed from `infra/iam.tf` and the other 4 read-only grants were re-applied on their own.

**Gotcha found:** AWS Secrets Manager enforces the `recovery_window_in_days` (7 here) on delete — a new secret with the same name (`novapay/db-credentials`) can't be created again until the window elapses (`InvalidRequestException: ... already scheduled for deletion`). `infra/secrets.tf` stays code-complete but won't successfully apply again until ~2026-07-24 unless recreated with a different name or force-deleted without recovery.

---

## 2026-07-18 — D2 ⑥ DR/backup scoped to Terraform state, not data tier

**Decision:** D2 ⑥ ("DR/backup") is implemented now as a remote Terraform state backend (`infra/state_backend.tf` + `backend "s3"` in `providers.tf`): S3 bucket `novapay-tfstate-771665904432` with versioning, `AES256` default encryption (AWS-managed key, not the CMK), and full public access block; state locking via S3 native `use_lockfile = true` (Terraform 1.10+ feature) instead of a separate DynamoDB lock table. Data-tier backup (AWS Backup plan for the future RDS instance) is deliberately **not** implemented yet — no data resource exists to protect (D3 hasn't started).

**Why:** Evaluated against what a real company/team would require, not PoC-minimal defaults (standing decision, see below). Local Terraform state is a live risk today — no versioning (no rollback if a bad `apply` corrupts it), no locking (concurrent applies would corrupt it in a team setting), and it can leak resource ARNs/IAM policy JSON in plaintext if accidentally committed. This isn't a deferrable "nice-to-have" like the WAF (which waited for an ALB to attach to) — the state backend needs no other resource to exist first, so there's no reason to delay it. An AWS Backup plan for RDS, by contrast, would protect nothing yet and cost money for no benefit — correctly deferred to D3, same reasoning already applied to the WAF and the CMK's usage grants.

**Architecture choice — S3 native locking (`use_lockfile`) over DynamoDB table:** both give correct locking; native locking removes one resource to manage/pay for and is what a team starting fresh today would pick, now that Terraform ≥1.10 supports it. DynamoDB locking remains valid (and is what most existing/legacy company setups use) but is legacy inertia, not a technical advantage, for a project starting from scratch.

**Standing scoping rule (2026-07-18):** going forward, NovaPay architecture decisions default to "what would a real company require," with budget/PoC-scope trade-offs noted as an explicit secondary constraint — not the default lens. Reflects that this is a portfolio project meant to demonstrate professional judgment, not just deliver a working PoC.

**Bootstrap sequence (chicken-and-egg):** the bucket must exist before `backend "s3"` can reference it. Real sequence hit an additional wrinkle beyond the one anticipated: Terraform validates the backend block *before* any command runs, not just at `init` — so `terraform apply` couldn't even start with the `backend "s3"` block present and the bucket not yet existing. Fix: temporarily commented out the `backend "s3"` block, ran `terraform init` (fell back to local backend, no data loss) + `terraform apply -target=...` (once per resource — chaining multiple `-target` flags in one PowerShell command truncated the resource address after the dot; single-target-per-command with the value quoted worked) to create the 4 bucket-related resources, then restored the `backend "s3"` block and ran `terraform init -migrate-state` (answered `yes` to copy local state into the bucket).

**Applied 2026-07-19:** all 4 resources live in `eu-west-1` (`aws_s3_bucket.tfstate`, `_versioning`, `_server_side_encryption_configuration`, `_public_access_block`), state successfully migrated to the S3 backend. Confirmed via `terraform plan`: 0 changes to existing infrastructure, only the already-known blocked Secrets Manager resources show as pending (unrelated, expected until ~2026-07-24). The `Releasing state lock` message in the plan output confirms `use_lockfile` native locking is functioning.

---

## 2026-07-29 — D2 checkov triage: 3 low-cost findings, all accepted-as-is or lightly hardened

**Context:** `checkov` installed and run against the full D2 Terraform (`infra/`): 79 passed / 24 failed. 21 of the 24 failures were triaged as either intentional (test IAM user, public LB subnets, unattached SGs pending D3 compute) or overkill for a solo PoC (cross-region replication, secret rotation, event notifications). The remaining 3 were revisited individually:

**1. `CKV_AWS_149` — Secrets Manager secret not encrypted with a CMK.** Kept as-is (AWS-managed key), consistent with the 2026-07-17 decision above — the CMK still has zero usage grants, and this secret still has no real consumer (no RDS, no app role) to scope a grant to. Added `#checkov:skip=CKV_AWS_149` inline in `infra/secrets.tf` referencing this decision. Note: on this machine's checkov 3.3.8 install, the skip annotation isn't actually suppressing the finding in local scans (confirmed via isolated repro — looks like a tool/environment quirk, not a syntax error); left in place since it should behave correctly in a standard Linux CI run (D4) and documents intent regardless.

**2. `CKV2_AWS_12` — default VPC security group not restricted.** Fixed: added `aws_default_security_group.main` in `infra/security_groups.tf` with zero ingress/egress rules. Unlike #1, there was no real trade-off here — lb/app/db already have dedicated SGs, so nothing depends on the default SG staying open; it only existed as a landmine for any future resource launched without an explicit SG. Checkov confirms PASSED.

**3. `CKV_AWS_192` — WAF doesn't prevent Log4j2/JNDI lookup (Log4Shell, CVE-2021-44228).** Added a 4th WAF rule (`AWSManagedRulesKnownBadInputsRuleSet`) in `infra/waf.tf`, in `count` mode — same as the existing 3 rules, per the D2 decision to keep the whole WAF in observe-only mode until rule behavior is validated against real traffic. Checkov still fails this check because it specifically requires blocking (`none {}`) action, not counting; confirmed by an isolated test swapping `count{}` for `none{}`, which passes. Added `#checkov:skip=CKV_AWS_192` with the same caveat as #1 about local suppression not taking effect. Will resolve naturally once the WAF as a whole moves from count to block mode — not before, to avoid making that call for one rule in isolation.
