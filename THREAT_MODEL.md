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
| Elevation | Cluster API reachable from any address | `cluster_endpoint_public_access_cidrs`, now a required input | live |
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
| Repudiation | Member account stops or deletes its own trail | `DenyTrailTampering`: `cloudtrail:StopLogging`, `cloudtrail:DeleteTrail` | live on the Workloads unit only |
| Repudiation | Trail narrowed rather than deleted, so it stays green and records nothing | nothing denies `UpdateTrail` or `PutEventSelectors` | **gap: claimed live, never existed** |
| Tampering | Detection disabled in a member account | `DenyGuardDutyTampering`: `guardduty:DeleteDetector`, `guardduty:DisassociateFromMasterAccount` | live on Workloads only, GuardDuty only, and GuardDuty was wound down on 2026-09-06, so it now guards nothing |
| Elevation | Account leaves the organisation to escape the guardrails | `DenyLeavingOrganization`: `organizations:LeaveOrganization` | live on the Workloads unit; not at the root, and `CloseAccount` is not denied |
| Tampering | Resources created outside the EU | region deny | **gap: claimed live, never existed** |

**The Security account is governed by nothing.** `novapay-workloads-guardrails`
is attached to the Workloads unit alone; the Security unit carries only
`FullAWSAccess`. Every row above therefore stops at the boundary of one unit.
The account this design nominates to hold detection is the account with no
guardrails on it.

**The narrowing row is the one to read twice.** `ARCHITECTURE.md` argues, in the
guardrails section, that narrowing is the failure that matters, because a trail
updated to record almost nothing still exists and still reports healthy. The
policy that was supposed to answer that denies `StopLogging` and `DeleteTrail`
and says nothing about `UpdateTrail`. The document identified the attack
correctly and then marked the control live without checking it, for weeks.

Nothing in this repository could have caught any of it. Checkov and Conftest
read the Terraform that was written, and the policies here were written; they
were simply never applied, and no scanner reads an organisation. It took
`aws organizations describe-policy` against the live account, which is the whole
argument for periodic verification against a source that is not the code.

**What no policy on this boundary protects.** Service control policies do not apply to the management account. It holds the organisation, the log bucket, the log key and the Terraform state, and the only things standing in front of it are root MFA and its IAM configuration. Two administrator IAM users with long-lived keys exist there, one without MFA, created in the console and therefore invisible to every scanner in this repository. That is the single largest gap in the model and it is not fixable in Terraform.

### B3 and the audit trail

| STRIDE | Threat | Control | Status |
|---|---|---|---|
| Tampering | Log objects altered after the fact | log-file validation, S3 versioning | live |
| Information disclosure | Logs readable by anyone who can read the bucket | customer-managed key scoped to this trail by encryption context | live |
| Tampering | Log objects deleted | versioning only | **gap: no deny statement, no object lock** |
| Denial of service | Detection findings never reach a person | EventBridge to SNS | the rule and topic still exist, but detection was wound down on 2026-09-06, so nothing can generate a finding to deliver |

The deletion gap matters more than it looks: the design once claimed a bucket policy denying deletion from other accounts, and no such statement existed. The claim was removed rather than the gap being hidden.

### B4 to B6, network and cluster

Mapped to the OWASP Kubernetes Top 10.

| OWASP K8s | Threat | Control | Status |
|---|---|---|---|
| K01 insecure workload configuration | Privileged or root containers | Pod Security Standards `restricted`, Kyverno in enforce | live, tested by violation |
| K01 | Writable root filesystem | enforced read-only, with explicit volumes | live, tested |
| K03 overly permissive RBAC | Pod identity reaching more than it needs | IRSA scoped by both subject and audience, one secret | live |
| K04 lack of centralised policy enforcement | Policy applied by convention | Kyverno cluster policies | live |
| K06 broken authentication | Cluster API open to the internet | endpoint allow list now required | live |
| K07 missing network segmentation | Lateral movement between pods | default-deny plus DNS-only egress | live, and initially not working at all |
| K07 | DNS used as an exfiltration channel | egress scoped to CoreDNS rather than port 53 anywhere | live, never tested |
| K08 secrets management failures | Credential readable by the wrong pod | Secrets Manager, access only through Secrets Manager; the customer-managed key was never applied | wound down 2026-09-06 with the secret |
| K09 misconfigured logging | No record of cluster activity | control plane audit logs on | live, though inherited from a module default rather than chosen |

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
