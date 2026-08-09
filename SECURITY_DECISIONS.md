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

---

## 2026-08-08 — D2 infra stays in the Management account; migration to the real Workloads account deferred

**Context:** D1 created real `novapay-security` and `novapay-workloads` member accounts (see `ARCHITECTURE_D1.md`, Option Γ). All of D2 (VPC, WAF, KMS, Secrets Manager, IAM, state backend) was built earlier and still lives in the Management account — enabling AWS Organizations didn't move anything, it only added the org structure around the existing account.

**Decision:** D2 infra is **not** migrated into the real Workloads account as part of D1. It stays where it is, and this is documented as a known, deliberate gap rather than an oversight.

**Why:** There is no in-place "move" between AWS accounts — the only path is destroy the resources in the Management account and recreate them fresh in the Workloads account (new resource IDs, a new KMS key, re-running every D2 apply). That's a real rebuild cost for a change that doesn't alter any control's behavior, only which account it lives under — and there's no live workload or real data at stake yet that migration would actually protect. In a real company, keeping application infrastructure in the Management account long-term would be a genuine finding (the Management account should stay minimal — see `research/2026-07-28-senior-cloud-security-gap-analysis.md`); here it's accepted short-term so the cost of the rebuild is paid once, deliberately, later.

**Revisit:** planned as a standalone step after the rest of P1, done by hand (not by Claude) as a deliberate exercise in cross-account resource migration — a real skill, worth doing hands-on rather than delegating.

---

## 2026-08-08 — Combined Security/Audit account, not split Log Archive + Security Tooling; deferred

**Context:** A gap-analysis scan against the AWS Security Reference Architecture (see [[cybersecurity projects/Novapay project/research/2026-07-28-senior-cloud-security-gap-analysis|gap analysis]]) found that the SRA's gold-standard pattern splits log storage and security tooling into two separate accounts: a **Log Archive account** (immutable storage only) and a **Security Tooling account** (delegated admin for GuardDuty/Security Hub/CloudTrail management). NovaPay combined both into one `novapay-security` account.

**Decision:** Not split for D1. Documented as a deliberate, accepted simplification, same reasoning family as the D2-to-Workloads migration above.

**Why:** Splitting means a 4th real AWS account (another root email, another go/no-go, another OU placement) purely to separate two roles that, at this project's scale, are both operated by the same single person anyway — the SRA's benefit (compromising one account doesn't hand over both the log archive and the detection tooling) is real but scoped to orgs where different teams/humans actually hold those two accounts. Revisit if NovaPay ever needs to demonstrate that separation concretely (e.g., a second operator, or an audit requiring it) rather than doing it preemptively.

---

## 2026-08-08 — Root account MFA (all 3 accounts) deferred, not skipped

**Context:** The same gap-analysis (finding #2) found none of the 3 accounts (Management, Security, Workloads) has MFA enabled on its root user — CIS AWS Foundations control #1. Root can't be scoped by IAM/SCPs the way every other principal can, so it's the highest-value target of the three; compromising the email tied to an account's root user is currently the softest path to full control of that account.

**Decision:** Not implemented in this D1 session. Explicitly deferred, to be done by hand (root credential/MFA setup has no Terraform API — AWS deliberately keeps this console-only).

**Why:** Time-boxed session; doing it properly for 3 accounts (including first setting a root password on the 2 member accounts, which don't have one by default) is a real chunk of manual work on its own. Unlike #3 (an architecture trade-off that's arguably fine to leave permanently), this one has no "acceptable forever" version — it should get done soon, not treated as settled debt.

---

## 2026-08-08 — D2→Workloads migration implemented by Claude (reverses the "done by hand" plan above); KMS key split; provider-reassignment orphan trap caught in `terraform plan`

**Context:** The 2026-08-08 entry above planned this migration as a manual exercise, done by the user later. The user asked Claude to implement it instead, in this same session.

**Decision 1 — how D2 moves:** Added a second `aws` provider alias (`aws.workloads`) in `providers.tf`, assuming `OrganizationAccountAccessRole` in the real Workloads account (`277606037083`) — the role Organizations creates automatically in every member account, assumable from Management with no extra IAM setup. Every D2 resource that belongs to a workload (VPC + subnets + route tables, the 3 security groups, the WAF ACL, the Secrets Manager secret, the test IAM user + its policies) got `provider = aws.workloads` added. Org-level resources (Organizations, the 2 accounts, the SCP, the org CloudTrail trail, the budget) stay on the default provider in Management — AWS requires this, it isn't a choice.

**Decision 2 — KMS key split:** `novapay-transaction-key` was encrypting the CloudTrail bucket (fixed 2026-08-08, same day as the migration-deferral entry above) but was labeled/intended as a future app-data key. Moving it wholesale to Workloads would make a security landing zone's audit-log encryption depend on a key owned by the account being audited — a separation-of-duties violation the AWS SRA specifically warns against. **Chosen: split into two keys.** The existing key stays in Management, renamed in-state via a `moved` block (`aws_kms_key.transactions` → `aws_kms_key.cloudtrail_logs`, alias → `alias/novapay-cloudtrail-key`) — no destroy, no re-encryption, zero risk to the CloudTrail logs it already protects. A brand-new key (`aws_kms_key.app_data`, alias `alias/novapay-transaction-key`) is created fresh in the Workloads account for future transaction data. Cost delta: ~$1/month for the second CMK.

**Decision 3 (process correction) — `ReadOnlyBudget` IAM statement dropped:** The test user's read-only policy granted `budgets:ViewBudget` on the Management-account budget. AWS Budgets has no resource-based/cross-account policy mechanism, so once the test user moves to Workloads this permission would be a silent no-op (AWS denies the call regardless of the IAM policy). Removed with a comment rather than left as dead configuration.

**Critical finding — provider reassignment does not safely migrate live resources:** A dry-run `terraform plan` (before any apply) showed that simply adding `provider = aws.workloads` to an *already-applied* resource does not make Terraform destroy the old object and create a new one. Terraform refreshes the existing state entry using the **new** provider's credentials; for resources where a describe-by-ID against the wrong account returns "not found" rather than an auth error (VPC, subnets, security groups, WAF ACL, IAM user), Terraform concludes the object "has been deleted" and silently drops it from state — then plans a fresh `create` in Workloads. The real objects in the Management account are never actually deleted; they become orphaned, untracked, still billing, still present as attack surface. (Secrets Manager was the exception: cross-account `DescribeSecret` returns `AccessDeniedException`, which surfaced as a hard plan error instead of silent drift — that's what caught this before any apply ran.)

**Corrected procedure:** two separate Terraform runs, not one:
1. `git stash` (temporarily restore the old, single-provider config) → `terraform destroy -target=aws_vpc.main -target=aws_wafv2_web_acl.novapay_waf -target=aws_secretsmanager_secret.db_credentials -target=aws_iam_user.test -target=aws_iam_policy.deny_dangerous_actions -target=aws_iam_policy.read_only_d2` — cleanly deletes the real Management-account objects (dependents like subnets/SGs/route tables/the secret version/the access key cascade automatically as targets of `aws_vpc.main`/`aws_secretsmanager_secret.db_credentials`/`aws_iam_user.test`).
2. `git stash pop` (restore the `aws.workloads`-provider config) → `terraform apply` — creates all of it fresh in the Workloads account.

**Why this matters beyond this one migration:** this is the general trap in any "move a resource to a different provider/account/region" change in Terraform — it looks like a one-line diff (`provider = ...`) but is never a safe in-place operation, and whether it fails loudly or silently orphans depends on which AWS API the resource happens to use for reads. Worth remembering for D3/D4 if similar account moves come up again.

**Outcome:** executed successfully. `terraform destroy -target=...` (old, single-provider config) cleanly removed all 29 D2 resources from the Management account; `terraform apply` (new, `aws.workloads`-provider config) created all of them fresh in the Workloads account. Final `terraform plan` confirmed zero drift.

**Two more real findings surfaced only by running this against live AWS, not by review:**

1. **The `cloudtrail_logs` key's admin policy was missing `kms:DeleteAlias`.** This key's policy has no "Enable IAM User Permissions" delegation statement — it's fully explicit, so *every* management action the admin can take must be listed by name; IAM permissions on the calling user are irrelevant if the key's own policy doesn't also allow it. The original 2026-07-17 policy only anticipated `kms:CreateAlias` (aliases get created, not renamed) — renaming one needs `DeleteAlias` too. Added `kms:DeleteAlias`, `kms:UpdateKeyDescription`, `kms:UntagResource` to both this key's policy and the new `app_data` key's policy (added there pre-emptively, before hitting the same gap twice).

2. **The AWS provider updates `description` before `policy` within a single `aws_kms_key` resource update.** Changing both the key's description and its policy in the same `terraform apply` meant `UpdateKeyDescription` ran against the *old*, not-yet-applied policy and got denied — even after the fix in finding 1 landed in the Terraform config, because the config being valid doesn't matter if AWS hasn't received the new policy yet at the moment the provider makes that particular API call. Worked around by applying the policy-only change first (temporarily leaving the description unchanged), then applying the description change in a second, separate `terraform apply` — by then the already-live policy permitted it. Not a NovaPay-specific bug: any single Terraform apply that both grants a permission *and* immediately exercises it via a different API call on the same resource can hit this ordering issue, regardless of provider. If it recurs elsewhere, splitting into two applies (permission-grant first, dependent action second) is the fix.

**Open choice not yet made:** virtual MFA (authenticator app, free, immediate) vs. hardware MFA key (CIS v3.0's actual recommendation for root, but costs money and requires ordering hardware first). Decide this when actually doing the work.
