# Runbook: move detection and alerting to the Security account

**Status:** required before the next `terraform apply` of the platform stack.
**Risk:** low. Nothing here stores data. The cost is a few minutes without alerting and one email confirmation click.

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

**1. Confirm what is about to be destroyed.** Switch to the code as it was before the move, so the old addresses still match the state:

```
git checkout main
cd infra
terraform plan -destroy \
  -target=aws_sns_topic_subscription.security_alerts_email \
  -target=aws_sns_topic_policy.security_alerts \
  -target=aws_cloudwatch_event_target.security_alerts \
  -target=aws_cloudwatch_event_rule.high_severity_findings \
  -target=aws_sns_topic.security_alerts \
  -target=aws_securityhub_organization_configuration.main \
  -target=aws_guardduty_organization_configuration.main
```

Expect seven resources and nothing else. If anything else appears, stop.

**2. Destroy them.** Same command with `destroy` instead of `plan -destroy`.

Between this step and step 3 there is no alerting. Detection keeps running; only the path to the inbox is down.

**3. Apply the new code.**

```
git checkout p1-hardening
terraform apply
```

The plan now completes, because nothing is left in state that has to be read through the wrong account.

This designates the Security account as delegated administrator for both services, creates its detector and hub, enables S3 and malware protection for every member through the organisation configuration rather than on one detector, and rebuilds the alert pipeline in the Security account.

**4. Confirm the subscription.** AWS sends a confirmation email to the alert address. Until it is clicked the topic has a pending subscription and delivers nothing.

## What the plan should destroy, and nothing else

The plan for this change removes nine addresses. Read them against this list
before typing yes. An address here that is missing, or one present that is not
here, means the state is not what this runbook assumed.

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
