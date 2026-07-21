# NovaPay — Reference Architecture (D2)

Diagram reflects infra state as of 2026-07-21. Renders natively on GitHub/Obsidian (Mermaid) — no build step, edit the code block below whenever the Terraform changes.

**Legend:** green = applied & live in AWS · gray dashed = planned, not yet provisioned (D3+) · orange = designed but currently destroyed (cost/scope decision, re-apply pending).

```mermaid
flowchart TB
    Client(["Client / Browser"])

    subgraph AWS["AWS Account — eu-west-1"]
        WAF["AWS WAF: novapay-waf<br/>AWSManagedRulesCommonRuleSet<br/>AWSManagedRulesAmazonIpReputationList<br/>Rate-limit: 2000 req / 5 min<br/>rules in COUNT mode — monitoring only, not blocking"]

        subgraph VPC["VPC 10.0.0.0/16"]
            IGW(["Internet Gateway"])

            subgraph PUB["Public subnets — 10.0.0.0/19, 10.0.32.0/19"]
                LB["Load Balancer — planned<br/>SG novapay-lb-sg: allow 443 from 0.0.0.0/0"]
            end

            subgraph APPSUB["Private app subnets — 10.0.64.0/19, 10.0.96.0/19"]
                APP["App servers — planned, D3/EKS<br/>SG novapay-app-sg: allow 8080 from lb-sg only"]
            end

            subgraph DBSUB["Private db subnets — 10.0.128.0/19, 10.0.160.0/19"]
                DB["Database — planned RDS<br/>SG novapay-db-sg: allow 5432 from app-sg only<br/>no IGW route, no egress rule"]
            end
        end

        KMS["KMS CMK: alias/novapay-transaction-key<br/>management-only policy<br/>zero usage grants yet — no consumer wired"]
        SM["Secrets Manager: novapay/db-credentials<br/>designed, currently destroyed<br/>re-apply blocked until 2026-07-24"]
        IAM["IAM: novapay-iam-test-user<br/>Deny: RDS delete, WAF removal, priv-esc chain<br/>Allow: read-only on D2 resources only"]
        S3["S3: novapay-tfstate-&lt;account-id&gt;<br/>Terraform state — versioned, AES-256 SSE<br/>public access blocked, native lockfile locking"]
    end

    Client -->|HTTPS 443| WAF
    WAF -.->|planned: web ACL association| LB
    IGW --- PUB
    LB -->|TCP 8080| APP
    APP -->|TCP 5432| DB
    DB -.->|planned: encrypt at rest| KMS
    APP -.->|planned: fetch credentials| SM
    IAM -.->|read-only visibility, no write access| AWS

    classDef live fill:#1b5e20,stroke:#4caf50,color:#fff
    classDef planned fill:#37474f,stroke:#90a4ae,color:#eee,stroke-dasharray: 5 5
    classDef pending fill:#7c4a03,stroke:#ffb300,color:#fff

    class WAF,IGW,KMS,IAM,S3 live
    class LB,APP,DB planned
    class SM pending
```
