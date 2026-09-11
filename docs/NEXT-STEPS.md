# Next steps

Written 2026-09-11 because a working session was found with the repository
checked out at a detached HEAD on the `pre-detection-move` tag — a month
behind `main`, missing this very file, `evidence/`, and everything from PR #2
onward. Any agent reasoning from that checkout was reasoning from a stale
snapshot and had no way to know it. This file exists so that never happens
silently again.

## Before reading anything else in this repository

```
git symbolic-ref HEAD
```

It must print `refs/heads/main`. If it errors ("not a symbolic ref"), you are
on a detached HEAD — most likely that tag, left over from someone following
`docs/runbooks/move-detection-to-security-account.md`'s own instruction to
check it out and never returning. Run `git checkout main` before trusting the
README, this file, or any control's stated status. The one exception is the
runbook step below that names the tag explicitly and says to return
immediately after.

## Current state, as the README's control table has it today

Read `README.md`'s "What is actually running" table directly; it is the
source of truth and this file does not duplicate it. As of this writing, the
rows still marked `written, never applied` are: the CloudTrail customer-managed
key, the base/security-service-protection/region-deny SCPs, GuardDuty and
Security Hub administered from the Security account, S3 and malware
protection via organisation configuration, and the account baseline
(public access block, password policy, Access Analyzer, EBS encryption,
security contact).

## What to do, in order

### 1. Delete the CloudTrail KMS key; keep the trail

Decided 2026-09-11 by a five-agent review (factual, senior engineer, hiring
manager, cost advocate, consistency reviewer; 4 of 5 for this outcome). The
key has never encrypted a single log object — `evidence/2026-09-06-landing-zone-baseline.txt`
shows the trail with no `KmsKeyId` and live objects as `AES256` — so it costs
roughly 1-2 USD a month for a control that does not run. The trail itself is
free and stays: it is the only detective control left on an organisation that
still has a leaked root email and one account without root MFA (see step 3).

- [x] `infra/cloudtrail.tf`: remove the `kms_key_id = aws_kms_key.cloudtrail_logs.arn`
      line from the trail resource; set the bucket's default encryption back
      to `AES256`. Done 2026-09-11.
- [x] `infra/kms.tf`: remove `prevent_destroy` from this key only. The trail's
      own `prevent_destroy` (`cloudtrail.tf`) is untouched — the trail is not
      being removed, only the key. Done 2026-09-11.
- [x] `terraform apply`, then `aws s3api head-object` on a fresh log to prove
      nothing references the key before scheduling its deletion. Done
      2026-09-11 — the trail's `kms_key_id` was already unset in live state
      (it was never actually applied), so the apply only touched the bucket
      encryption config and the key's own tags/policy. `head-object` confirmed
      `AES256`, no `SSEKMSKeyId`. Evidence:
      `evidence/2026-09-11-cloudtrail-kms-removal.txt`.
- [x] Schedule the key for deletion (7-day window; it will still show in
      billing for that week). Done 2026-09-11 via `terraform destroy -target`
      on the key and its alias. `aws kms describe-key` confirms
      `KeyState: PendingDeletion`, `DeletionDate: 2026-09-18`. Cancellable with
      `aws kms cancel-key-deletion` until then if needed.
- [x] Update the README row and supersede the two `SECURITY_DECISIONS.md`
      entries that argued for keeping the key, in the file's existing
      "Status: superseded" style. Done 2026-09-11 — see `README.md`'s control
      table and "What broke", and the two `Status: superseded`/`partially
      superseded` notes in `SECURITY_DECISIONS.md`, plus a new
      `## 2026-09-11 — The CloudTrail CMK is dropped instead of fixed` entry
      there recording the decision itself.

**Note for step 2 below:** the plan for step 2's SCPs and account baseline
targets was re-verified after step 1 and is unaffected by it — the key removal
touched only `aws_kms_key.cloudtrail_logs`, its alias, and the bucket
encryption config, none of which step 2's targets depend on.

### 2. Apply the account baseline and the SCPs — targeted, not a bare apply

**Verified 2026-09-11 with a real `terraform plan` against the live account
(credentials are configured in this environment; the plan is read-only and
safe to rerun any time).** A plain `terraform apply` here is 41 to add, 26 to
change, 2 to destroy, and it is not just the SCPs and the baseline. The same
apply would also recreate `aws_secretsmanager_secret.db_credentials` and
`aws_kms_key.app_data` — the two rows the README marks
`wound down 2026-09-06, and never re-encrypted` and `wound down 2026-09-06`.
Their Terraform was never removed, only their deployed instances were
destroyed, so an untargeted apply silently reverses that cost decision. As of
step 1 above, `aws_kms_key.cloudtrail_logs` and `aws_kms_alias.cloudtrail_logs`
are now in the same boat — their code also stays while their live instances
are gone, so a bare apply would recreate those too. Do not run a bare
`terraform apply` in this repository until every such resource has either been
removed from the code or is a deliberate choice made that day.

Test-day model: apply only the targets below, capture evidence into
`evidence/`, decide same day whether the row stays live or gets wound down
with the evidence kept as proof it ran.

- [ ] Do step 1 (the KMS key removal) first — the plan above still shows
      `aws_cloudtrail.org_trail` and `aws_kms_key.cloudtrail_logs` as
      in-place updates from the *old* code; applying this step before step 1
      would apply the key reference you are about to remove.
- [ ] SCPs (replaces `workloads_guardrails` with three narrower policies —
      expected, and named in the move-detection runbook's own destroy list):
      ```
      terraform apply \
        -target=aws_organizations_policy.base_guardrails \
        -target=aws_organizations_policy.protect_security_services \
        -target=aws_organizations_policy.region_deny \
        -target=aws_organizations_policy_attachment.base_guardrails_root \
        -target=aws_organizations_policy_attachment.protect_security_services_security \
        -target=aws_organizations_policy_attachment.protect_security_services_workloads \
        -target=aws_organizations_policy_attachment.region_deny_security \
        -target=aws_organizations_policy_attachment.region_deny_workloads
      ```
- [ ] Account baseline:
      ```
      terraform apply \
        -target=aws_s3_account_public_access_block.management \
        -target=aws_s3_account_public_access_block.security \
        -target=aws_s3_account_public_access_block.workloads \
        -target=aws_iam_account_password_policy.management \
        -target=aws_iam_account_password_policy.security \
        -target=aws_iam_account_password_policy.workloads \
        -target=aws_accessanalyzer_analyzer.org \
        -target=aws_ebs_encryption_by_default.workloads \
        -target=aws_account_alternate_contact.management_security \
        -target=aws_account_alternate_contact.security_security \
        -target=aws_account_alternate_contact.workloads_security
      ```
- [ ] Re-run a plain `terraform plan` after both, confirm the only remaining
      diff is the app-data KMS key, the Secrets Manager secret, and the
      GuardDuty/Security Hub move (step 3 below) — nothing else unexplained.

### 3. GuardDuty and Security Hub, administered from the Security account

This is the one step that genuinely needs the tag, and only for its destroy
half. Follow `docs/runbooks/move-detection-to-security-account.md` exactly;
its own step 0 through step 4 are authoritative. The shape, so it is not a
surprise mid-runbook:

- [ ] Phase A (destroy the old management-account resources):
      `git checkout pre-detection-move` — detached HEAD, deliberate, and
      temporary for this phase only.
- [ ] Phase B (apply the new code): `git checkout main` immediately after the
      destroy, before the apply. Confirm with `git symbolic-ref HEAD` again.
- [ ] Confirm the SNS subscription (check the inbox), then generate a sample
      GuardDuty finding and verify the alert email arrives.

**Do not use the tag for anything else.** The other runbook,
`docs/runbooks/wind-down-billable-resources.md`, explicitly corrects an
earlier draft of itself that said to check out the tag throughout — at that
tag the Kubernetes/Helm providers are still wired into `infra/`, which is the
exact "unplannable from a clean checkout" failure this repository spent a
week fixing. That runbook runs entirely from `main`.

### 4. Safeguards from the zero-spend decision (2026-09-11)

- [ ] Root MFA on all three accounts (one is currently missing).
- [ ] Delete the two console-created IAM users with long-lived access keys in
      the management account (one has no MFA).
- [ ] Check for a console-made CloudTrail trail in `eu-north-1` that may still
      bill per event outside this repository's Terraform.
- [ ] A budget alarm at 1 USD, so a forgotten test-day resource pages the
      next morning instead of the next bill.

### 5. Then, outside this repository

Landing zone Phase 5 (CloudWatch alarms and SNS), per
`studies/Career Planning/2026-09-11-market-research-and-8-week-plan.md` in
the parent `cyberjob` folder. After that, the new `cloud-detection-and-response`
work begins.

## Rule for any agent picking this repository up cold

Confirm `git symbolic-ref HEAD` prints `refs/heads/main` before trusting a
single file here, the one exception being the two-phase dance in step 3
above — and return to `main` the moment that destroy step finishes. Tick a
box in this file, with the evidence file it points at, before moving to the
next one; do not mark a step done from a plan output alone.
