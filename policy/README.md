# Policy as code

Seven Rego rules, run by Conftest on every pull request. They read Terraform source, not a plan, so the gate needs no AWS credentials and works on a fork's pull request. The cost of that choice is precision: a value that arrives from a variable or a data source is invisible to these rules. They check what is written down. Whether the running estate matches is Security Hub's job.

## What each rule evidences

| Rule | Checks | DORA article |
|---|---|---|
| `kms_key_rotation` | every customer-managed key rotates | Art. 9(4)(d), protection of cryptographic keys |
| `cloudtrail_integrity` | trails have log-file validation and a customer-managed key | Art. 9(4)(d) and Art. 10(1), detection depends on a trustworthy record |
| `s3_public_access` | every bucket has a matching public access block | Art. 9(3)(b), minimise the risk of unauthorised access |
| `network_exposure` | no ingress from `0.0.0.0/0` except port 443 | Art. 9(4)(c), least-privilege logical access |
| `secrets_encryption` | secrets use a customer-managed key, not the AWS-managed one | Art. 9(2), protection of data at rest |
| `no_static_credentials` | no IAM users and no long-lived access keys | Art. 9(4)(c) and 9(4)(d) |
| `cluster_exposure` | the cluster API endpoint is not open to the internet unrestricted | Art. 9(4)(c) |

## What this does not claim

DORA is an organisational regulation. A solo lab cannot comply with it, and nothing here should be read as saying otherwise. What these rules do is evidence a subset of the technical controls that Article 9 and Article 10 require, automatically, on every change.

Four articles are deliberately not cited anywhere in this repository, because claiming them would be false:

- **Article 11 and 12**, backup and restore. Article 12 requires restore procedures to be tested periodically. Nothing here has ever been restored, so there is nothing to claim.
- **Article 17**, incident management. Out of scope for this project.
- **Article 28**, ICT third-party risk. It concerns contractual arrangements with providers. Pinning a Terraform provider version is not that, and dressing it up as that is the kind of claim an auditor takes apart in one question.

Article 9(4)(e), change management, is arguably evidenced by this pipeline existing at all, since it is the mechanism that stops unreviewed infrastructure reaching the account. That is a claim about the process, not about any one rule, so it is stated here rather than annotated on a policy file.

## Testing the policies

`policy/fixtures/violations.tf.fixture` breaks every rule on purpose, because a policy suite that has only been run against compliant code has not been tested.

The pipeline counts the denials rather than checking that Conftest merely failed. A pass/fail check is satisfied by any one rule firing, so most of the suite could stop working behind a step that stays green. The expected count lives in `EXPECTED_FAILURES` in the workflow and moves whenever a rule or a fixture case is added.

The extension is not `.tf` so that Checkov, `terraform fmt` and `terraform validate` ignore it. Conftest reads it because the parser is passed explicitly.

Run both halves locally:

```
conftest test --parser hcl2 --policy policy --all-namespaces $(find infra -name '*.tf')
conftest test --parser hcl2 --policy policy --all-namespaces policy/fixtures/violations.tf.fixture
```

The first must pass. The second must fail with fourteen findings, one per row below.

## Rules that passed what they claimed to block

Five cases at the end of the fixture were added on 2026-09-06, after a review found four rules checking that a field was *present* rather than what it *contained*. Each of these was clean under the old rules:

| Input | Why it passed |
|---|---|
| `ingress` on port 22 from `::/0` | the rule read `cidr_blocks` and never `ipv6_cidr_blocks` |
| `ingress` from `0.0.0.0/0`, ports 443-65535 | only `from_port` was compared to 443, so the upper bound was free |
| EKS with `cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]` | the rule required the list to exist, not to restrict anything |
| Secret with `kms_key_id = "alias/aws/secretsmanager"` | presence of `kms_key_id` was read as "customer-managed" |
| Trail with `kms_key_id = "alias/aws/s3"` | the same presence check, on the resource the project had already been burned by |

The shape is the same every time, and it is the same shape as the CloudTrail bug in the repository root README: a check that confirms a setting was configured, not that it does anything. A rule that cannot fail on the input it was written to reject is documentation with a build step.

## The rule that did not work

`network_exposure` was written first as a straightforward loop over `sg.ingress`. It passed against a security group that allowed port 22 from anywhere.

The HCL parser represents a single `ingress` block as an object and several as a list. Iterating the object walked the field values, none of which have a `cidr_blocks` key, so the rule matched nothing and reported success. It would have started working by accident the day someone added a second ingress block to that resource.

It was caught by running the rule against input that should fail it, which is the only reason it was caught at all. The fixture exists because of this.

## On tfsec

The project brief asks for Checkov plus tfsec. tfsec entered maintenance mode in 2023 and its checks were absorbed into Trivy, which is what runs here as `trivy config`. Using the unmaintained tool to match the brief literally would have meant shipping a scanner that no longer receives new rules. The second opinion is still there, which was the point of naming two scanners.
