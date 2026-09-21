# Evidence

Proof that a control behaved as described, kept because most of this
infrastructure is destroyed the same day it is tested.

Terminal output is the normal form here. A screenshot is only worth taking for
something that is visual by nature, such as a console setting with no API that
returns it. Everything else is copied as text, which is searchable, diffable and
does not need cropping.

| File | Shows | Date |
|---|---|---|
| `2026-09-14-budget-alert-investigation.txt` | The first firing of the FORECASTED budget alert, answered rather than dismissed. Day-by-day and per-service charges read from CloudWatch billing metrics. The forecast of 7.09 USD is an extrapolation of a month whose spend was front-loaded before the 6 September wind-down; the current run rate is 0.008 USD a day. Also records that the 2026-09-13 audit missed WAF, which turned out to be the largest single line on the bill, and confirms none exist now. | 2026-09-14 |
| `2026-09-13-root-mfa.txt` | Root MFA turned on for all three accounts. The first attempt registered a device in the wrong account because the password reset used management's root email instead of workloads'; caught because the device name and the account it landed in disagreed. Read back after the fix: all three show `AccountMFAEnabled = 1`. | 2026-09-13 |
| `2026-09-13-iam-key-hygiene.txt` | IAM access key audit in the management account. Deactivated a `<secondary-iam-user>` key unused for two months, decided by last-used date rather than creation date. Access key IDs are truncated to four characters after the repository's own gitleaks gate correctly failed the first version of this file. Records what is still open: `<cli-iam-user>`'s active long-lived key and missing MFA, which cannot be removed until Identity Center access replaces it. | 2026-09-13 |
| `2026-09-13-cost-guardrail-scp.txt` | A fourth service control policy, `novapay-cost-guardrails`, applied and negative-tested. Argues a budget is a notification with a billing-data lag, not a brake, and an SCP refuses the API call at the moment it is made. | 2026-09-13 |
| `2026-09-13-cost-audit-and-budget-retune.txt` | Real spend read from AWS Budgets before choosing an alarm threshold, rather than guessing one. Actual spend was higher than earlier notes assumed, which is why the retuned budget uses both an ACTUAL and a FORECASTED threshold instead of one. | 2026-09-13 |
| `2026-09-11-scps-and-account-baseline.txt` | The three service control policies and the account baseline read back per account after the apply, not just planned. The region-deny policy tested from inside both member accounts, denying `ec2:DescribeVpcs` in `eu-central-1` with the denying policy id in the error. | 2026-09-11 |
| `2026-09-11-cloudtrail-kms-removal.txt` | The check that found the customer-managed key had never encrypted a single log object: CloudTrail sets its own per-object encryption, which beat the bucket default the whole time. The key was scheduled for deletion instead of chased further. | 2026-09-11 |
| `2026-09-06-post-winddown.txt` | The other half of the same day. Every row the README marks `wound down` read back as absent, and every row it still marks `live` read back as present and logging. Short on purpose: it answers the status table and nothing else. | 2026-09-06 |
| `2026-09-06-pre-winddown.txt` | The whole estate, ten sections, read back from AWS on the day it was wound down. This is the proof that everything the README marked `live` really did run. Two commands fail, both from the account baseline that was never applied, which is what `capture-after-apply.sh` is documented to do. Sections 4 and 5 are the interesting ones: the headings say the detection services are administered from the Security account and the output underneath returns `<management-account>`. The headings were written for the state after a migration that never happened. The file is kept exactly as captured, mismatch included, because a capture edited to agree with itself proves nothing. | 2026-09-06 |
| `2026-09-06-pipeline-first-github-run.txt` | The two check runs on the merge commit of PR #1, read back from the GitHub API. The pipeline had been written and run locally for weeks; this is the first proof it runs on GitHub, on a pull request, without AWS credentials. | 2026-09-06 |
| `2026-09-06-landing-zone-baseline.txt` | The organisation trail writing SSE-S3 objects a month after the decision log recorded it as moved to a customer-managed key, and both delegated administrators still pointing at the management account. The before half of those fixes. | 2026-09-06 |
| `2026-08-09-cluster-control-tests.md` | Five cluster controls tested by deliberate violation. Four blocked as intended; the network policies enforced nothing until the CNI was reconfigured. | 2026-08-09 |
| `2026-08-09-trivy-nginx-unprivileged.txt` | Image scan of the placeholder container: 105 findings, 2 critical, mostly in the Alpine base. Recorded rather than tidied up. | 2026-08-09 |
| `2026-07-secrets-manager-applied.jpg` | Secret created and encrypted, from the console. | 2026-07 |

## capture-after-apply.sh

One command that produces the "after" half for every row the README marks live.
Run it straight after the apply and before destroying anything:

```
./evidence/capture-after-apply.sh > evidence/$(date +%F)-post-apply.txt
```

Its sections are numbered to match the README table, so a section that failed is
a claim with nothing behind it. Run against the estate before the hardening
apply, exactly two commands fail, both from the account baseline that has not
been applied yet, which is the intended behaviour: the script is a test of the
claims, not a formality.

Redaction is built in, so the output can be committed as it comes. Account ids
become role labels rather than one uniform mask, because masking all three
identically would destroy the thing most of these commands exist to prove.
`<security-account>` next to a delegated administrator is evidence;
three identical `<account-id>` strings are not.

Before adding anything by hand: remove account identifiers, IAM user names and
email addresses. A follow-up review on 21 September 2026 found identifiers
in several manually added captures; those text files have been corrected.
Account roles, organisational units and distinct IAM users retain consistent
placeholder labels.
These edits redact identifiers only; they do not change test results or imply
that the historical calls were rerun. Earlier Git revisions are not covered
by this cleanup.
