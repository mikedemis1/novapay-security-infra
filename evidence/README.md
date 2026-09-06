# Evidence

Proof that a control behaved as described, kept because most of this
infrastructure is destroyed the same day it is tested.

Terminal output is the normal form here. A screenshot is only worth taking for
something that is visual by nature, such as a console setting with no API that
returns it. Everything else is copied as text, which is searchable, diffable and
does not need cropping.

| File | Shows | Date |
|---|---|---|
| `2026-09-06-landing-zone-baseline.txt` | The organisation trail writing SSE-S3 objects a month after the decision log recorded it as moved to a customer-managed key, and both delegated administrators still pointing at the management account. The before half of those fixes. | 2026-09-06 |
| `2026-08-09-cluster-control-tests.md` | Five cluster controls tested by deliberate violation. Four blocked as intended; the network policies enforced nothing until the CNI was reconfigured. | 2026-08-09 |
| `2026-08-09-trivy-nginx-unprivileged.txt` | Image scan of the placeholder container: 105 findings, 2 critical, mostly in the Alpine base. Recorded rather than tidied up. | 2026-08-09 |
| `2026-07-secrets-manager-applied.jpg` | Secret created and encrypted, from the console. | 2026-07 |

Before adding anything: remove account identifiers, IAM user names and email
addresses. The captures here have been through that already.
