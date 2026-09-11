# Threat model

Scope: the AWS estate in this repository and the workload running on it. It covers the infrastructure, the identities that can change it, and the path a transaction would take through it. It does not cover application logic, because the workload here is a placeholder.

Two catalogues are used. STRIDE frames the threats per trust boundary, because the interesting failures here are infrastructure failures and STRIDE is organised the way infrastructure fails. The OWASP Kubernetes Top 10 is used for the cluster, because it names the specific ways a cluster is lost. The OWASP Top 10 for web applications is deliberately not used: there is no application to apply it to, and mapping it to nginx would be decoration.

## Assets, in order of what an attacker would want

1. **Organisation control.** Whoever controls the management account controls every account, can create new ones, and is not restrained by any service control policy.
2. **The audit trail.** The record of what happened. Valuable because destroying or narrowing it is how everything else gets away with it.
3. **Transaction data.** Does not exist yet. The controls around it do, which is the point of building them first.
4. **The database credential.** Was in Secrets Manager, destroyed in the 2026-09-06 wind-down, and encrypted with the AWS-managed key throughout: the customer-managed key this model assumed was written but never applied. It also sat in Terraform state in plaintext, which is asset 6's problem.
5. **Cluster control.** The Kubernetes API, and through it every workload identity.
6. **Terraform state.** Describes the whole estate and has historically contained secrets in plaintext.

## Trust boundaries

| Boundary | Between | Enforced by |
|---|---|---|
| B1 | Internet and the AWS estate | IAM, MFA, the cluster endpoint allow list |
| B2 | Management account and member accounts | account separation, service control policies |
| B3 | Security account and Workloads account | account separation, cross-account roles |
| B4 | Public subnets and private tiers | route tables, security group chain |
| B5 | Cluster and AWS APIs | IRSA, scoped role trust |
| B6 | Pod and pod | network policies, Pod Security Standards, Kyverno |
| B7 | Developer laptop and the estate | pull request, compliance gate, review |

## Actors

- **External attacker with no access.** Starts from a phishing attempt, a leaked credential, or an exposed endpoint.
- **Attacker holding one set of member-account credentials.** The realistic breach: one role, one account, and an interest in staying invisible.
- **Insider or compromised operator.** Holds legitimate administrative access.
- **Compromised dependency.** A container image or Terraform module that is not what it claims to be.

## Threats by boundary

### B1, internet to estate

| STRIDE | Threat | Control | Status |
|---|---|---|---|
| Spoofing | Root account password reset using a known root email address | root MFA on every account | **partial: one account still lacks it** |
| Spoofing | Stolen static access key used from anywhere | humans through Identity Center, no IAM users in Terraform, no long-lived keys | partial: true of Terraform only since 2026-09-06, and two administrator IAM users still exist outside it |
| Elevation | Cluster API reachable from any address | `cluster_endpoint_public_access_cidrs`, now a required input | enforced when a cluster exists; none does |
| Information disclosure | Account root emails readable in public git history | branch deletion, which did not work; needs a garbage-collection request | **open** |

The first and last rows compound. A root email that is readable and an account without MFA are one finding, not two, and that is the highest-priority open item in the repository.

The second row was simply false until 2026-09-06. `aws_iam_user.test` and
`aws_iam_access_key.test` were in the Terraform and had been since August, so
"no IAM users in Terraform, no long-lived keys" described an intention rather
than the state. They were destroyed in the wind-down, which is the only reason
the row now reads the way it always claimed to.

### B2, management to member accounts

This table was rewritten on 2026-09-06 after its claims were read back from the
organisation rather than from the code. One row was accurate, two overstated
their scope, and two described policy that does not exist. The Status column now
distinguishes what is enforced from what is only written.

| STRIDE | Threat | Control | Status |
|---|---|---|---|
| Repudiation | Member account stops or deletes its own trail | `DenyTrailTampering`: `cloudtrail:StopLogging`, `cloudtrail:DeleteTrail` | live on both units since 2026-09-11 (`novapay-protect-security-services`, `p-znh6pzob`) |
| Repudiation | Trail narrowed rather than deleted, so it stays green and records nothing | `DenyTrailTampering` also denies `cloudtrail:UpdateTrail` and `cloudtrail:PutEventSelectors` | closed 2026-09-11; attached to both units, not tamper-tested (see below) |
| Tampering | Detection disabled in a member account | `DenyGuardDutyTampering`, `DenySecurityHubTampering`, `DenyConfigTampering` | policy live on both units since 2026-09-11, but GuardDuty and Security Hub were wound down on 2026-09-06, so it currently guards services that are not running |
| Elevation | Account leaves the organisation to escape the guardrails | `DenyLeavingOrganization`: `organizations:LeaveOrganization` and `account:CloseAccount` | live at the root since 2026-09-11 (`novapay-base-guardrails`, `p-8ryv7lhp`), so it covers every account in the organisation, and `CloseAccount` is now denied too |
| Tampering | Resources created outside the EU | region deny, `eu-west-1` only, global services excluded by `NotAction` | live on both units since 2026-09-11 (`novapay-region-deny`, `p-pyxqnvs4`) and **tested**: `ec2:DescribeVpcs` in `eu-central-1` refused from inside both member accounts with an explicit deny naming that policy id |

**The Security account was governed by nothing, until 2026-09-11.**
`novapay-workloads-guardrails` was attached to the Workloads unit alone; the
Security unit carried only `FullAWSAccess`. The account this design nominates to
hold detection was the account with no guardrails on it. It now carries
`novapay-region-deny` and `novapay-protect-security-services`, and
`novapay-base-guardrails` sits at the root, above both units. The old
single-unit policy is still attached as well, and is destroyed by
`docs/runbooks/move-detection-to-security-account.md` in the detection move.

**The narrowing row was the one to read twice.** `ARCHITECTURE.md` argues, in
the guardrails section, that narrowing is the failure that matters, because a
trail updated to record almost nothing still exists and still reports healthy.
The policy that was supposed to answer that denied `StopLogging` and
`DeleteTrail` and said nothing about `UpdateTrail`. The document identified the
attack correctly and then marked the control live without checking it, for
weeks. `novapay-protect-security-services` denies `UpdateTrail` and
`PutEventSelectors` as well, and it is applied.

Nothing in this repository could have caught any of it. Checkov and Conftest
read the Terraform that was written, and the policies here were written; they
were simply never applied, and no scanner reads an organisation. It took
`aws organizations describe-policy` against the live account, which is the whole
argument for periodic verification against a source that is not the code.

**What the 2026-09-11 verification does and does not prove.** The region deny
was tested the only way a deny can honestly be tested: by making the denied call
from inside each member account and reading the refusal, which names the policy
id. The trail, GuardDuty, Security Hub and Config denies in
`protect_security_services` were not tested that way, because the only real test
of a deny on `cloudtrail:StopLogging` is to call `StopLogging`, and a policy not
in force would then stop the organisation trail — the one detective control
still running. They share a mechanism with the deny that was tested, and they
are attached; that is weaker evidence than the region row has, and this
paragraph exists so the difference is not quietly rounded up. Read back in
`evidence/2026-09-11-scps-and-account-baseline.txt`.

**What no policy on this boundary protects.** Service control policies do not apply to the management account. It holds the organisation, the log bucket, the log key and the Terraform state, and the only things standing in front of it are root MFA and its IAM configuration. Two administrator IAM users with long-lived keys exist there, one without MFA, created in the console and therefore invisible to every scanner in this repository. That is the single largest gap in the model and it is not fixable in Terraform.

### B3 and the audit trail

| STRIDE | Threat | Control | Status |
|---|---|---|---|
| Tampering | Log objects altered after the fact | log-file validation, S3 versioning | live |
| Information disclosure | Logs readable by anyone who can read the bucket | SSE-S3 (no customer-managed key) | **accepted 2026-09-11: a CMK was tried, never actually encrypted a log object (per-object PutObject encryption always beat the bucket default), and was dropped rather than fixed since it was pure unused cost. Bucket-read now genuinely equals log-read, with no scoped-decrypt control on top of it — this is the honest residual risk, not the earlier false claim of one** |
| Tampering | Log objects deleted | versioning only | **gap: no deny statement, no object lock** |
| Denial of service | Detection findings never reach a person | EventBridge to SNS | the rule and topic still exist, but detection was wound down on 2026-09-06, so nothing can generate a finding to deliver |

**The encryption row, verified on 2026-09-06.** `get-bucket-encryption` returns
`aws:kms` with the customer-managed key. `head-object` on the log objects
returns `AES256` and no key id. CloudTrail sets encryption on its own
`PutObject` call and the per-object choice beats the bucket default, so every
object in this bucket is SSE-S3 and the key protects none of them. The August
decision log recorded this as fixed; only the bucket default had changed.

That has a consequence for the wind-down. The key was kept, at about a euro a
month, partly on the strength of this row. It is not encrypting the trail. What
still justifies keeping the trail is log-file validation, multi-region coverage
and organisation scope, all of which are real and were verified. The key is
carried along by `prevent_destroy` and is the weakest euro in the estate.

The deletion gap matters more than it looks: the design once claimed a bucket policy denying deletion from other accounts, and no such statement existed. The claim was removed rather than the gap being hidden.

### B4 to B6, network and cluster

Mapped to the OWASP Kubernetes Top 10.

**No cluster is running.** It is created for a test day and destroyed the same
day, because the control plane bills about 0.10 USD an hour. So `enforced` below
means the control was applied to a real cluster and, where noted, tested by
deliberate violation on 2026-08-09; it does not mean anything is running now.
The evidence is `evidence/2026-08-09-cluster-control-tests.md`. The permanent
part of this boundary is the code in `infra/workload/`, which the pipeline
checks on every pull request.

| OWASP K8s | Threat | Control | Status |
|---|---|---|---|
| K01 insecure workload configuration | Privileged or root containers | Pod Security Standards `restricted`, Kyverno in enforce | enforced, tested by violation |
| K01 | Writable root filesystem | enforced read-only, with explicit volumes | enforced, tested |
| K03 overly permissive RBAC | Pod identity reaching more than it needs | IRSA scoped by both subject and audience, one secret | enforced; the secret it scoped to was destroyed on 2026-09-06 |
| K04 lack of centralised policy enforcement | Policy applied by convention | Kyverno cluster policies | enforced |
| K06 broken authentication | Cluster API open to the internet | endpoint allow list now required | enforced |
| K07 missing network segmentation | Lateral movement between pods | default-deny plus DNS-only egress | enforced, and initially not working at all |
| K07 | DNS used as an exfiltration channel | egress scoped to CoreDNS rather than port 53 anywhere | enforced, never tested |
| K08 secrets management failures | Credential readable by the wrong pod | Secrets Manager, access only through Secrets Manager; the customer-managed key was never applied | wound down 2026-09-06 with the secret |
| K09 misconfigured logging | No record of cluster activity | control plane audit logs on | enforced, though inherited from a module default rather than chosen |

The K07 row is the honest one. Those policies existed and were enforced by nothing for the whole first attempt, because the VPC CNI does not act on NetworkPolicy objects unless told to. They were only found because the test tried to violate them instead of confirming they existed.

### B7, change pipeline

| STRIDE | Threat | Control | Status |
|---|---|---|---|
| Tampering | Non-conforming infrastructure reaching an account | Checkov, Trivy and seven policy rules on every pull request | live |
| Information disclosure | Credential committed | gitleaks over full history | live |
| Tampering | A policy that silently stops working | fixture that must fail, checked by the pipeline | live |
| Elevation | Compromised Terraform module | provider versions pinned, lock file committed | partial: module versions are pinned by range, not by digest |

## What this model does not cover

- Application logic. The workload is nginx.
- Denial of service against the edge. There is no edge.
- Physical and personnel security.
- Supply chain beyond version pinning. No image signing, no SBOM, no attestation.
- The data tier, which does not exist. When it does, encryption at rest, backup and a tested restore all enter this model, and the backup row is currently the largest thing missing.

## Open items, ranked

1. Root MFA on the account whose root email is publicly readable, then the garbage-collection request for the leaked commits.
2. The administrator IAM user with a long-lived key and no MFA in the management account.
3. Deletion protection on the log bucket, and moving it out of the management account.
4. AWS Config and a Security Hub standard, so that drift from this model is detected rather than reviewed by hand.
5. A tested restore, once there is anything to restore.
