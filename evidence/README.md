# Evidence

Proof that a control behaved as described, kept because most of this
infrastructure is destroyed the same day it is tested.

Terminal output is the normal form here. A screenshot is only worth taking for
something that is visual by nature, such as a console setting with no API that
returns it. Everything else is copied as text, which is searchable, diffable and
does not need cropping.

| File | Shows | Date |
|---|---|---|
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
email addresses. The captures here have been through that already.
