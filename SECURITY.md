# Security

## What this repository is

A lab. It is applied against real AWS accounts and torn down between tests, and
it is not production. `README.md` separates what is running from what is only
written down, and the limits section says where it falls short.

No customer data, no real payment flows, no secrets in the tree. NovaPay is an
invented company.

## Reporting something

Open an issue, or use GitHub's private vulnerability reporting on this
repository if the finding should not be public first. Include the file and the
line if you can.

There is no bounty and no SLA. This is a personal project.

## What is already known

Reporting one of these is not needed, they are recorded on purpose:

- Service control policies do not apply to the management account. That account
  holds the organisation, the log bucket and the Terraform state, and is
  protected only by root MFA and its IAM configuration. See `ARCHITECTURE.md`.
- The organisation CloudTrail uses SSE-S3. Anyone who can read the bucket can
  read the logs. A customer-managed key was tried, never encrypted a single
  object, and was dropped on 2026-09-11 instead of fixed.
- There are no VPC flow logs, so there is no record of which address talked to
  which.
- `THREAT_MODEL.md` lists the controls that are attached but not tamper-tested,
  and says why testing some of them would break the only detective control
  running.

## Scanning

Every pull request runs Checkov, Trivy, gitleaks and an OPA policy suite, and
the policy suite is itself tested against a fixture that violates every rule.
Findings are triaged in the open. Where a check is skipped there is a dated
reason next to it in the Terraform.
