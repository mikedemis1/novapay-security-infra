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

State was last written by the code from before the detection move, so its
addresses match that code and not `main`. Everything below runs from the tag:

```
git checkout pre-detection-move
cd infra
terraform init -backend-config=backend.hcl
terraform state list
```

Every address in the steps below must appear in that listing. One that does not
means state is not what this runbook assumes. Stop and read it rather than
guessing.

## Step 1. The web ACL, which is most of the bill

```
terraform destroy -target=aws_wafv2_web_acl.novapay_waf
```

Roughly 7.75 USD a month, around 60 percent of the bill, attached to nothing. It
has no `aws_wafv2_web_acl_association`, so no traffic passes through it and
nothing depends on it going. If only one step here ever gets run, this is the
one.

## Step 2. Detection and alerting

Order matters: the organisation configuration has to go before the delegated
administrator, and the administrator before the detector, or the API refuses.
Terraform derives that from the dependency graph, so pass them in one command
and let it order them rather than running thirteen commands by hand.

```
terraform destroy \
  -target=aws_sns_topic_subscription.security_alerts_email \
  -target=aws_sns_topic_policy.security_alerts \
  -target=aws_cloudwatch_event_target.security_alerts \
  -target=aws_cloudwatch_event_rule.high_severity_findings \
  -target=aws_sns_topic.security_alerts \
  -target=aws_securityhub_organization_configuration.main \
  -target=aws_securityhub_organization_admin_account.main \
  -target=aws_securityhub_account.main \
  -target=aws_guardduty_organization_configuration.main \
  -target=aws_guardduty_organization_admin_account.main \
  -target=aws_guardduty_detector_feature.s3_data_events \
  -target=aws_guardduty_detector_feature.ebs_malware_protection \
  -target=aws_guardduty_detector.main
```

From here nothing watches the accounts. That is the intent, but note the date,
because "no findings" after this point is not the same claim as "no findings"
before it.

## Step 3. Empty the log bucket by hand

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

## Step 4. Trail, log bucket, secret and keys

```
terraform destroy \
  -target=aws_cloudtrail.org_trail \
  -target=aws_s3_bucket_policy.cloudtrail_logs \
  -target=aws_s3_bucket_public_access_block.cloudtrail_logs \
  -target=aws_s3_bucket_server_side_encryption_configuration.cloudtrail_logs \
  -target=aws_s3_bucket_versioning.cloudtrail_logs \
  -target=aws_s3_bucket.cloudtrail_logs \
  -target=aws_secretsmanager_secret_version.db_credentials \
  -target=aws_secretsmanager_secret.db_credentials \
  -target=aws_kms_alias.cloudtrail_logs \
  -target=aws_kms_key.cloudtrail_logs \
  -target=aws_kms_alias.app_data \
  -target=aws_kms_key.app_data
```

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
  without MFA. No scanner in this repository sees them, because none of them
  reads a live account.
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

The state bucket carries no `prevent_destroy`. Nothing but this sentence stops a
future untargeted `terraform destroy` from taking the state with it.

## After

Update the status table in `README.md` in the same change. A row still reading
`live` after this runbook has run is the one failure mode that matters here,
because the repository's opening claim is that it distinguishes what runs from
what does not.
