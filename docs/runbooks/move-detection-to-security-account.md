# Runbook: move detection and alerting to the Security account

**Status:** required before the next `terraform apply` of the platform stack.
**Risk:** low. Nothing here stores data. The cost is one email confirmation click.

> ## Corrections, 2026-09-13
>
> This runbook was written in August and was followed on 2026-09-12. It failed,
> twice, before reaching its first destroy. Three things below were wrong. They
> are corrected in place; this note records what changed so the diff is not a
> mystery.
>
> **1. Step 1 aborts unless you add a provider back first.** The account
> baseline applied on 2026-09-11 created three resources through
> `provider = aws.security`. This tag predates that alias, so a detached
> checkout leaves them with no provider configuration and Terraform refuses to
> plan *anything*:
>
> ```
> Error: Provider configuration not present
> To work with aws_account_alternate_contact.security_security (orphan) its
> original provider configuration at provider["...aws"].security is required,
> but it has been removed.
> ```
>
> The other two orphans are `aws_s3_account_public_access_block.security` and
> `aws_iam_account_password_policy.security`. The fix is in step 1 below and is
> the one Terraform's own error message recommends.
>
> **2. "Expect seven resources" is wrong — there are five.** GuardDuty and
> Security Hub are not in state at all any more; they were wound down. Nothing
> is being *moved*. Five alerting resources are destroyed and the whole
> detection stack is then created fresh in the Security account.
>
> **3. Step 3 said a bare `terraform apply`. Do not.** Since the wind-downs and
> the 2026-09-11 CMK removal, several resources keep their code on purpose while
> their live instances are gone. A bare apply silently recreates
> `aws_secretsmanager_secret.db_credentials`, `aws_kms_key.app_data` and
> `aws_kms_key.cloudtrail_logs`, reversing three deliberate cost decisions.
>
> One consequence is good news: the "few minutes without alerting" this runbook
> used to warn about no longer applies. Detection is already off, so there is no
> window to lose.

## Why this is not just an apply

GuardDuty, Security Hub and the finding-alert pipeline were built in the management account before any member account existed, and stayed there after the Security account was created in August. AWS recommends against the management account being the delegated administrator, and the design document had always drawn these in the Security account.

Changing `provider = aws.security` on a resource does not move it. Terraform keeps the same state address, refreshes it through the new provider, and fails, because the Security account's role cannot read a management-account resource:

```
Error: reading SNS Topic (arn:aws:sns:eu-west-1:<mgmt>:novapay-security-alerts):
AuthorizationError: User: arn:aws:sts::<security>:assumed-role/OrganizationAccountAccessRole/...
is not authorized to perform: SNS:GetTopicAttributes
```

Left alone it would be worse than an error. Where the refresh does succeed, Terraform creates a second copy in the new account and forgets the original, which then keeps running, keeps emailing, and is managed by nothing. That is the same trap the D2 migration hit in August.

So the old resources are destroyed with the old code, and the new ones created with the new code. Two applies, in order.

## The part that is easy to miss

Moving the delegated administrator silently breaks alerting if the EventBridge rule does not move with it. Findings aggregate in the delegated administrator's account, and an EventBridge rule only matches events on its own account's bus. Leave the rule in the management account and it will keep existing, keep reporting healthy, and never fire again. That is why `alerting.tf` moves in the same change rather than later.

## Steps

**0. Note the starting state.** On the branch that contains this runbook, `terraform plan` fails. That is expected and is the problem this runbook exists to solve: the moved resources are refreshed through a role that cannot read them, so the plan errors before it can produce anything.

```
Error: reading SNS Topic (...): AuthorizationError
Error: reading Security Hub Organization Configuration (...): InvalidAccessException
```

**1. Confirm what is about to be destroyed.** Switch to the code as it was before the move, so the old addresses still match the state. That is the `pre-detection-move` tag, not `main`: the move was merged into `main` in PR #1, so checking out `main` here would hand you the *new* code and reproduce the step 0 error instead of avoiding it.

```
git checkout pre-detection-move    # detached HEAD, deliberately; annotated tag on 35c35cc
cd infra
terraform init
```

**Now add the `aws.security` provider back, temporarily.** Copy this block into
`providers.tf` on the detached checkout. Do not commit it; it is discarded at
the end of this phase. Without it every plan aborts with "Provider
configuration not present" — see the correction note at the top.

```hcl
provider "aws" {
  alias  = "security"
  region = "eu-west-1"

  assume_role {
    role_arn = "arn:aws:iam::${aws_organizations_account.security.id}:role/OrganizationAccountAccessRole"
  }
}
```

Then plan the destroy:

```
terraform plan -destroy \
  -target=aws_sns_topic_subscription.security_alerts_email \
  -target=aws_sns_topic_policy.security_alerts \
  -target=aws_cloudwatch_event_target.security_alerts \
  -target=aws_cloudwatch_event_rule.high_severity_findings \
  -target=aws_sns_topic.security_alerts
```

**Expect exactly five resources.** Confirm with `terraform state list` first if
you want to see why: the two GuardDuty/Security Hub organisation-configuration
addresses this runbook originally listed are no longer in state, so targeting
them is a no-op. If a sixth address appears, or one of the five is missing, stop
— the state is not what this runbook assumes.

**2. Destroy them.** Same command with `destroy` instead of `plan -destroy`.

Then discard the temporary provider block before leaving the tag:

```
git checkout -- providers.tf
git status --porcelain          # must print nothing
```

There is no alerting gap to worry about here any more. GuardDuty and Security
Hub are already off, so nothing is generating findings that could be missed.

**3. Apply the new code — targeted, never bare.**

```
git checkout main
git symbolic-ref HEAD           # must print refs/heads/main
terraform init
```

A bare `terraform apply` at this point recreates three resources that were
destroyed on purpose for cost, because their Terraform was deliberately kept.
Target the detection stack only:

```
terraform apply \
  -target=aws_guardduty_detector.management \
  -target=aws_guardduty_detector.security \
  -target=aws_guardduty_organization_admin_account.main \
  -target=aws_guardduty_organization_configuration.main \
  -target=aws_guardduty_organization_configuration_feature.s3_data_events \
  -target=aws_guardduty_organization_configuration_feature.ebs_malware_protection \
  -target=aws_securityhub_account.management \
  -target=aws_securityhub_account.security \
  -target=aws_securityhub_organization_admin_account.main \
  -target=aws_securityhub_organization_configuration.main \
  -target=aws_sns_topic.security_alerts \
  -target=aws_sns_topic_policy.security_alerts \
  -target=aws_sns_topic_subscription.security_alerts_email \
  -target=aws_cloudwatch_event_rule.high_severity_findings \
  -target=aws_cloudwatch_event_target.security_alerts
```

Run `terraform plan` with the same targets first and read the list. The refresh
error on the SNS topic that step 0 predicts is gone once the destroy in step 2
has removed it from state.

This designates the Security account as delegated administrator for both
services, creates its detector and hub, enables S3 and malware protection for
every member through the organisation configuration rather than on one detector,
and rebuilds the alert pipeline in the Security account.

**Cost note, added 2026-09-13.** GuardDuty and Security Hub each give a 30-day
free trial **per account per region**, and each member of an organisation gets
its own. The Security account has never had either enabled, so this runbook
costs nothing for 30 days. After that GuardDuty bills on analysed CloudTrail
volume and Security Hub bills $0.001 per check. Decide before you start whether
this is a trial window or a permanent control, and write the decision down.

This designates the Security account as delegated administrator for both services, creates its detector and hub, enables S3 and malware protection for every member through the organisation configuration rather than on one detector, and rebuilds the alert pipeline in the Security account.

**4. Confirm the subscription.** AWS sends a confirmation email to the alert address. Until it is clicked the topic has a pending subscription and delivers nothing.

## What the plan should destroy, and nothing else

**This section describes a bare `terraform apply`, which step 3 above no longer
tells you to run.** It is kept because the nine addresses below still sit in
state and will still be destroyed the day someone does run an untargeted apply.
Read it as a standing hazard list, not as the expected output of step 3 — the
targeted apply touches none of them.

Two of the nine, `aws_guardduty_detector_feature.*`, may already be gone: the
detectors were wound down after this was written. Confirm with
`terraform state list` rather than trusting the count.

An address here that is missing, or one present that is not here, means the
state is not what this runbook assumed.

| Address | Why it goes |
|---|---|
| `aws_organizations_policy.workloads_guardrails` | replaced by three policies with different content and a different attachment point; not a rename, so no `moved` block applies |
| `aws_organizations_policy_attachment.workloads_guardrails` | same |
| `aws_guardduty_detector_feature.s3_data_events` | protection plans move to the organisation configuration; on a single detector they covered the management account only |
| `aws_guardduty_detector_feature.ebs_malware_protection` | same |
| `aws_iam_user.test` | replaced by an assumed role |
| `aws_iam_access_key.test` | the long-lived key that role exists to remove |
| `aws_iam_user_policy_attachment.test_read_only_d2` | attached to the user above |
| `aws_iam_user_policy_attachment.test_deny_dangerous_actions` | attached to the user above |
| `aws_wafv2_web_acl.novapay_waf` | moved to the workload stack, which is a separate state file; the platform stack drops it and `infra/workload` recreates it |

The Web ACL is the only one that is an artefact of splitting the stacks rather
than a deliberate replacement. `moved` blocks cannot help: they operate inside
one state, and the two stacks keep separate state files. Destroying it costs
nothing, because it has no `aws_wafv2_web_acl_association` and therefore no
traffic passes through it. Moving it also puts it on the workload lifecycle, so
it is destroyed with the cluster instead of billing while nothing runs.

There is a gap of seconds between the old guardrail policy being detached and
the new ones attaching, during which the Workloads unit is governed by no
service control policy. In this account that is acceptable. It is written down
because noticing it after the fact is worse than deciding it in advance.

The Kubernetes and Helm resources are **not** in this list. The platform state
holds none: the cluster is destroyed after each test, and its objects went with
it. If `terraform state list` ever does show `kubernetes_*` or `helm_*` entries
in the platform stack, stop. Those providers were removed from `infra/` in the
split, and a plan will abort with "Provider configuration not present" before
it can do anything about them.

Confirm the assumption before you start:

```
terraform -chdir=infra state list | grep -E '^(kubernetes|helm|module\.eks)' && echo "STOP: read the paragraph above" || echo "clear"
```

## Verification

```
aws guardduty list-organization-admin-accounts --region eu-west-1
aws securityhub list-organization-admin-accounts --region eu-west-1
```

Both must return the Security account, not the management account.

```
aws sns list-subscriptions --region eu-west-1        # from the Security account role
```

`SubscriptionArn` must be a real ARN, not the string `PendingConfirmation`.

Then generate a finding and wait for the email:

```
aws guardduty create-sample-findings \
  --detector-id <security-account-detector-id> \
  --finding-types Backdoor:EC2/C\&CActivity.B!DNS \
  --region eu-west-1
```

Sample findings are free and arrive within a few minutes. If no email arrives, the rule and the topic are in different accounts, which is the failure this runbook exists to prevent. Keep the terminal output as evidence either way.

## Rolling back

Revert the commit and repeat the same two-phase sequence in the other direction. Nothing here holds state, so a rollback loses only the finding history accumulated in the Security account since the move.
