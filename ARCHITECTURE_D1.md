# NovaPay — Secure Landing Zone (D1)

**Status: design-only, nothing applied yet.** This diagram is drawn *before* the first `terraform apply` for D1 (senior-engineer standing rule #2 — design before build), and reflects the account structure we agreed on: **Option Γ — Management + Security/Audit + Workloads**.

**Legend:** gray dashed = planned/design, nothing live yet in AWS. Solid arrows = "communicates with / feeds into." Dotted arrows = "constrains / denies regardless of local IAM."

```mermaid
flowchart TB
    Client(["Client / Attacker — internet"])

    subgraph MGMT["Management Account"]
        ORG["AWS Organizations<br/>root of the org, owns OU structure"]
        SSO["IAM Identity Center<br/>human SSO, grants scoped roles into member accounts"]
        SCP["Service Control Policies<br/>attached to OUs — override local IAM, cannot be bypassed from inside a member account"]
    end

    subgraph SEC["Security / Audit Account"]
        LOGS3["S3: centralized log bucket<br/>bucket policy denies delete from any other account"]
        CT["CloudTrail (org trail, multi-region)<br/>log-file validation on"]
        GD["GuardDuty — delegated administrator<br/>aggregates findings org-wide"]
        SH["Security Hub<br/>aggregates GuardDuty + compliance checks, one dashboard"]
    end

    subgraph WL["Workloads Account — existing D2 infra"]
        VPC["VPC / WAF / App / DB (D2)<br/>internet-facing — largest attack surface"]
        GDMEM["GuardDuty member sensor"]
        CTMEM["CloudTrail org trail — member side"]
    end

    Client -->|HTTPS 443| VPC

    ORG -->|OU membership| WL
    ORG -->|OU membership| SEC
    SCP -.->|deny: StopLogging, DeleteDetector, LeaveOrganization| WL
    SSO -->|scoped role grants| WL
    SSO -->|scoped role grants| SEC

    CTMEM -->|delivers logs, no delete perm on target| LOGS3
    CT --> LOGS3
    GDMEM -->|findings| GD
    GD --> SH

    classDef planned fill:#37474f,stroke:#90a4ae,color:#eee,stroke-dasharray: 5 5
    class ORG,SSO,SCP,LOGS3,CT,GD,SH,VPC,GDMEM,CTMEM planned
```

## Τι αντιμετωπίζει ένας attacker, βήμα-βήμα

1. **Είσοδος** — στοχεύει το **Workloads account** (μεγαλύτερη επιφάνεια: WAF/app/DB εκτεθειμένα στο internet). Ας υποθέσουμε ότι πετυχαίνει αρχικό compromise (π.χ. leaked credential, app vulnerability).
2. **Κλιμάκωση δικαιωμάτων μέσα στο account** — μπλοκάρεται από το IAM least-privilege του D2 *και ανεξάρτητα* από τα SCPs του D1, που ισχύουν ό,τι κι αν λέει το τοπικό IAM.
3. **Προσπάθεια συγκάλυψης ιχνών** (σβήσιμο CloudTrail, απενεργοποίηση GuardDuty) — αποτυγχάνει διπλά:
   - Τα logs ζουν σε S3 bucket σε **άλλο account** (Security/Audit) — το Workloads account δεν έχει delete δικαίωμα εκεί, ό,τι κι αν καταφέρει τοπικά.
   - Το SCP απαγορεύει ρητά `cloudtrail:StopLogging` / `guardduty:DeleteDetector`, ανεξάρτητα από το αν το τοπικό IAM θα το επέτρεπε.
4. **Ανίχνευση** — το GuardDuty τρέχει σε account που ο attacker ποτέ δεν παραβίασε· σημαίνει ασυνήθιστη συμπεριφορά, το Security Hub το συγκεντρώνει σε μία οθόνη.
5. **Η μόνη «νίκη» που θα του απέμενε** — να παραβιάσει απευθείας το Management ή το Security account. Πολύ μικρότερη επιφάνεια: καμία δημόσια έκθεση, πρόσβαση μόνο μέσω IAM Identity Center SSO.
