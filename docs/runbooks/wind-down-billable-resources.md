# Runbook: wind down the billable resources, keep the landing zone

**Status:** the current plan for this estate. Run this instead of the detection
move, not after it.
**Risk:** medium. This destroys real resources, none of them recoverable from
Terraform alone, and two steps have a seven-day tail.

## Why this is not `terraform destroy`

The obvious command is wrong here, for a reason worth stating rather than
discovering.

Most of what runs in this landing zone costs nothing. Organizations,
organisational units, service control policies, IAM Identity Center, the VPC
and its subnets, and the budget alarm are all free. The VPC is free
specifically because the NAT gateway lives in the workload stack, which is
already destroyed between tests. There is no saving to be had from removing any
of it.

Worse, `aws_organizations_account` on destroy does not close an account. It
removes it from the organisation, which requires that account to carry its own
payment method and support agreement, and leaves it standalone rather than
gone. The member account email addresses are then spent, because AWS will not
let the same address open another account. An untargeted destroy trades the most
substantial thing this repository demonstrates for no saving at all, and does it
irreversibly.

So this removes what bills and keeps what does not.

## Check the assumption first

```
cd infra
terraform state list
```

Every address named below must appear. One that does not means state is not
what this runbook assumes; stop and read it rather than guessing.

`terraform init` is not needed if the backend is already configured locally,
which `state list` returning anything proves. In PowerShell, quote the argument
if you do need it: `terraform init "-backend-config=backend.hcl"`, because
PowerShell mangles a native argument containing `=`.

## Which branch to run from

Not the tag, for everything. The first draft of this runbook said to check out
`pre-detection-move` throughout, by analogy with the detection-move runbook.
That is wrong here, and the reason is worth keeping.

At that tag the platform stack still contained the cluster, so `providers.tf`
configures the `kubernetes` and `helm` providers from
`module.eks.cluster_endpoint` and `data.aws_eks_cluster_auth.this`. The cluster
has since been destroyed and `module.eks` is no longer in state, which is
exactly the condition that used to make this repository unplannable. Running
the wind-down from the tag walks straight back into it. The tag also predates
`evidence/capture-after-apply.sh`, so checking it out removes the script that
produces the evidence.

`main` has no such providers in `infra/`: they moved to `infra/workload/` with
the cluster. So the question becomes which addresses `main` can refresh, and
the split turns out to be clean.

| Group | Refresh from `main` | Costs |
|---|---|---|
| Web ACL, both KMS keys, trail and log bucket, secret, both detectors, Security Hub account, the D2 test user | works | effectively the whole bill |
| SNS topic, its policy and subscription, the EventBridge rule and target, the two organisation *configurations* | fails: they carry `provider = aws.security`, and that role cannot read a management-account resource | nothing |

The first group is either absent from `main`'s configuration, so it is a plain
state-only destroy, or present under the default provider, so it refreshes
against the management account it actually lives in. The second group is the
one the detection-move runbook exists for, and every resource in it is free: an
SNS topic, two EventBridge objects and two settings.

So steps 1 to 4 run from `main`. Step 5 is optional and costs nothing.

## Step 0. Capture the evidence, from bash

Do this before anything else. It is the only step here that cannot be repeated,
because step 3 deletes the logs that most of it reads.

```
bash evidence/capture-after-apply.sh > evidence/$(date +%F)-pre-winddown.txt
wc -l evidence/*-pre-winddown.txt
```

**Run it through `bash`, from the repository root.** PowerShell does not execute
a `.sh` file, so `./evidence/capture-after-apply.sh > out.txt` there produces an
empty file and sends the error somewhere the redirect does not capture. A
zero-line capture looks exactly like a successful one until it is opened. Check
the line count before continuing.

## Step 1. The web ACL, and the two renames that come with it

The web ACL alone is roughly 7.75 USD a month, around 60 percent of the bill,
attached to nothing. It has no `aws_wafv2_web_acl_association`, so no traffic
passes through it and nothing depends on it going.

It cannot go alone, though, and the reason is worth understanding because it
governs every targeted command in this runbook.

`main` carries four `moved` blocks. Two of them, renaming `aws_kms_key.transactions`
to `aws_kms_key.cloudtrail_logs` and the matching alias, are already reflected in
state and are inert. The other two are not:

```
aws_guardduty_detector.main   ->  aws_guardduty_detector.management
aws_securityhub_account.main  ->  aws_securityhub_account.management
```

State still holds the old names, the configuration declares the new ones, and
Terraform refuses to build a targeted plan that leaves a pending move only
half covered:

```
Error: Moved resource instances excluded by targeting
```

That refusal is correct. A `moved` block is a promise about identity, and a plan
that honoured it for some instances and not others would produce a state that
matches neither. So both sides of both renames join this step. Both resources
are being destroyed anyway, GuardDuty and Security Hub being the usage-billed
half of detection, so nothing is lost by taking them here rather than in step 4.

```
terraform destroy \
  -target=aws_wafv2_web_acl.novapay_waf \
  -target=aws_guardduty_detector.main \
  -target=aws_guardduty_detector.management \
  -target=aws_securityhub_account.main \
  -target=aws_securityhub_account.management
```

Terraform will pull in further instances to respect dependencies, and the
GuardDuty detector features in state are the likely additions. **Read the plan
before answering.** Every line must be a destroy; a single create means the
targeting has caught something that was meant to stay.

## Step 2. The D2 test user and its long-lived access key

Free, and the most dangerous thing left once nothing is watching the accounts.

```
terraform destroy \
  -target=aws_iam_user_policy_attachment.test_read_only_d2 \
  -target=aws_iam_user_policy_attachment.test_deny_dangerous_actions \
  -target=aws_iam_access_key.test \
  -target=aws_iam_user.test \
  -target=aws_iam_policy.read_only_d2 \
  -target=aws_iam_policy.deny_dangerous_actions
```

This is a long-lived access key belonging to a user created to test D2
permissions. The detection-move runbook had it scheduled for removal, and that
runbook is no longer being run. Deleting detection while leaving standing
credentials behind is the wrong order to stop in.

## Step 3. Empty the log bucket by hand

**Not run on 2026-09-06, and deliberately so.** The trail, its bucket and its key
were kept, for the reason set out under the guards below, so there was nothing
to empty. The step is left here because it is correct for anyone who does decide
to remove them, and because the trap in it is real.

Note the ordering, which the first draft had backwards: destroy the trail
*before* emptying the bucket. A running organisation trail keeps writing, so a
bucket emptied while it is still enabled is not empty by the time step 4 reaches
it.

**This step exists because step 4 fails without it.** No bucket in this stack
sets `force_destroy`, and the log bucket is versioned, so Terraform cannot
remove it while objects remain. Deleting the current objects is not enough
either: versioning keeps a delete marker and every non-current version, and the
bucket stays non-empty as far as the API is concerned.

Take the evidence capture before this runs. Once the logs are gone, the trail's
own record of this estate goes with them.

```
BUCKET=<log bucket name>

aws s3api list-object-versions --bucket "$BUCKET" \
  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
  --output json > versions.json
aws s3api delete-objects --bucket "$BUCKET" --delete file://versions.json

aws s3api list-object-versions --bucket "$BUCKET" \
  --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
  --output json > markers.json
aws s3api delete-objects --bucket "$BUCKET" --delete file://markers.json
```

Both calls cap at 1000 keys per request, so repeat them until
`list-object-versions` comes back empty.

## Step 4. The secret and the application key

What was actually run, after the trail and its key were kept:

```
terraform destroy \
  -target=aws_secretsmanager_secret_version.db_credentials \
  -target=aws_secretsmanager_secret.db_credentials \
  -target=aws_kms_alias.app_data \
  -target=aws_kms_key.app_data
```

The wider version, taking the trail, the log bucket and its key as well, needs
their `prevent_destroy` blocks removed from `cloudtrail.tf` and `kms.tf` first,
and step 3 run in between. It saves about 1.20 USD a month. It was not run.

If the GuardDuty detector features are still in state after step 1, add
`-target=aws_guardduty_detector_feature.s3_data_events` and
`-target=aws_guardduty_detector_feature.ebs_malware_protection` here. Step 1
usually takes them as dependencies of the detector, so check
`terraform state list` rather than assuming either way.

From here nothing watches the accounts. That is the intent, but note the date:
"no findings" after this point is not the same claim as "no findings" before it.

## What actually happened, 2026-09-06

Two things went wrong in ways the plan did not predict, and both are ordering
problems rather than mistakes in the target lists.

**Delegated administrators must be dismantled before the services they
administer.** Step 1 destroyed the web ACL and the IAM policies, then failed:

```
BadRequestException: The request is rejected. You must first disassociate
your member accounts and delete invited member accounts.
InvalidInputException: Cannot disable Security Hub on the Security Hub administrator
```

The fix is to destroy `aws_guardduty_organization_admin_account.main` and
`aws_securityhub_organization_admin_account.main` first. A destroy plan pulls in
dependents rather than dependencies, so targeting the two administrator
registrations also picks up the two organisation configurations, which is what
you want. Afterwards the detector and the hub each deleted in under a second,
having previously spent five minutes failing.

That also settles the branch question above: the organisation configurations
carry `provider = aws.security` and were expected to need the tag. They did not.
A destroy does not need a successful refresh, so step 5 is largely redundant.

**One resource genuinely could not be destroyed through the provider.**
`aws_securityhub_organization_configuration.main` failed with:

```
InvalidAccessException: Account <security> is not an administrator for this organization
```

Destroying it is an `UpdateOrganizationConfiguration` call rather than a delete,
and the configured provider is the Security account, which is not the
administrator. It was dropped from state instead:

```
terraform state rm aws_securityhub_organization_configuration.main
```

That is worth naming as a decision rather than leaving in the shell history. A
`state rm` abandons a real object to no owner, which is normally how estates rot.
It is defensible here on two grounds: the object is an auto-enable setting that
ceases to exist once the hub is disabled, which happened minutes later, and this
stack is never applied again, so there is no future plan for the orphan to
surprise. Neither ground would hold on a stack still in use.

## Step 5, optional. The free remainder

Nothing here bills. Left alone it is state drift, not cost, so it is worth
doing but not worth fighting.

```
git checkout pre-detection-move
terraform destroy \
  -target=aws_sns_topic_subscription.security_alerts_email \
  -target=aws_sns_topic_policy.security_alerts \
  -target=aws_cloudwatch_event_target.security_alerts \
  -target=aws_cloudwatch_event_rule.high_severity_findings \
  -target=aws_sns_topic.security_alerts \
  -target=aws_securityhub_organization_configuration.main \
  -target=aws_securityhub_organization_admin_account.main \
  -target=aws_guardduty_organization_configuration.main \
  -target=aws_guardduty_organization_admin_account.main
git checkout main
```

This is the only step that needs the tag, so it is the only one that can hit
the `kubernetes` provider problem described above. If it does, the fallback is
to disable the two services in the console and drop the addresses with
`terraform state rm`. Losing them from state costs nothing once the resources
are gone and the repository is no longer being applied.

## The seven-day tail

Neither the keys nor the secret are gone when Terraform reports them destroyed.

| Resource | Setting | What actually happens |
|---|---|---|
| `aws_kms_key.cloudtrail_logs` | `deletion_window_in_days = 7` | scheduled, not deleted, and billed at 1 USD a month for seven more days |
| `aws_kms_key.app_data` | `deletion_window_in_days = 7` | the same |
| `aws_secretsmanager_secret.db_credentials` | `recovery_window_in_days = 7` | recoverable, and billed, for seven more days |

The bill therefore reaches roughly zero after a week, not tomorrow. The windows
are deliberate and worth keeping: they are the only thing between a mistyped
`-target` and an unrecoverable key. A key scheduled by mistake comes back with
`aws kms cancel-key-deletion --key-id <id>`.

## What Terraform will not touch

Three things outlive this runbook because Terraform never created them.

- **A second CloudTrail, `management-events`, in eu-north-1**, made in the
  console. It keeps billing after every step above, and once the organisation
  trail is gone it is the entire remaining bill. Delete it in the console, in
  that region.
- **Two IAM users in the management account with long-lived access keys**, one
  without MFA. These are the console-created pair, not the Terraform-managed
  `aws_iam_user.test` that step 2 removes. No scanner in this repository sees
  them, because none of them reads a live account.
- **Two commits carrying account root email addresses**, still served by SHA
  from GitHub's events API after the branches were deleted. Only a GitHub
  Support garbage-collection request removes those.

## What is deliberately left running

Every row here is free. Removing it would cost this repository its most
substantial claim and save nothing.

| Kept | Why |
|---|---|
| Organizations, two organisational units, three accounts | free, and destroying it burns the account email addresses permanently |
| Three service control policies and their attachments | free, and meaningless without the organisation |
| IAM Identity Center, permission set, account assignments | free |
| VPC, six subnets, route tables, internet gateway, three security groups | free; the NAT gateway is in the workload stack |
| Budget alarm | free, and the one control that should outlive every other one here |
| Terraform state bucket | pennies, and it holds the state that keeps all of the above reversible; it is `AES256`, not one of the keys destroyed above, so nothing here can lock you out of it |

The account baseline and Access Analyzer are absent from both tables on purpose.
They are free, but they were never applied, so there is nothing to keep or
remove. They stay `written` in the README either way.

An earlier draft of this runbook said the state bucket carried no
`prevent_destroy` and that nothing but a sentence protected it. That was wrong,
and wrong in the safe direction. `main` carries six guards, none of which
existed at the tag, because all six were added in PR #1:

| Guarded | File |
|---|---|
| `aws_organizations_account.security` | `accounts.tf` |
| `aws_organizations_account.workloads` | `accounts.tf` |
| `aws_s3_bucket.cloudtrail_logs` | `cloudtrail.tf` |
| `aws_cloudtrail.org_trail` | `cloudtrail.tf` |
| `aws_kms_key.cloudtrail_logs` | `kms.tf` |
| `aws_s3_bucket.tfstate` | `state_backend.tf` |

The mistake came from grepping the tag, which is the right ref for state
addresses and the wrong one for configuration. Two different questions, two
different refs.

The guards worked. Step 4 stopped on `Instance cannot be destroyed`, which
forced the question of whether the organisation trail was worth keeping instead
of letting it go by momentum. It costs about a euro a month and it is the one
control in this estate nobody would switch off, so it stayed, and with it the
log bucket and its key. Removing a `prevent_destroy` is a code change and a
review, which is exactly the gate it exists to be.

## After

Update the status table in `README.md` in the same change. A row still reading
`live` after this runbook has run is the one failure mode that matters here,
because the repository's opening claim is that it distinguishes what runs from
what does not.
