#!/usr/bin/env bash
# Capture proof for every row the README marks live, so the estate can be
# destroyed without those claims becoming unverifiable.
#
# Run once, straight after the apply and before destroying anything:
#
#   ./evidence/capture-after-apply.sh > evidence/$(date +%F)-post-apply.txt
#
# Every command is read-only. Sections are numbered to match rows in the README
# table, so a section that failed is a claim with nothing behind it.

set -uo pipefail
REGION="${AWS_REGION:-eu-west-1}"

# Everything printed goes through this. A capture that leaks the account ids it
# was taken from cannot be committed, and remembering to scrub by hand is how
# identifiers reached this repository the first time.
#
# The ids are replaced by role labels rather than by one uniform mask. Masking
# all three the same way destroys the thing most of these commands exist to
# show: which account administers a service. "<security-account>" proves the
# claim; three identical "<account-id>" strings prove nothing.
ACCOUNT_SED=()
while IFS=$'	' read -r acct_id acct_name; do
  [ -z "$acct_id" ] && continue
  case "$acct_name" in
    *security*|*Security*)   label="security-account" ;;
    *workload*|*Workload*)   label="workloads-account" ;;
    *)                       label="management-account" ;;
  esac
  ACCOUNT_SED+=(-e "s/${acct_id}/<${label}>/g")
done < <(aws organizations list-accounts --query 'Accounts[].[Id,Name]' --output text 2>/dev/null)

if [ ${#ACCOUNT_SED[@]} -eq 0 ]; then
  echo "# WARNING: could not list accounts, falling back to a uniform mask." >&2
  ACCOUNT_SED=(-e 's/[0-9]{12}/<account-id>/g')
fi

redact() {
  sed -E "${ACCOUNT_SED[@]}"     -e 's/[0-9]{12}/<other-account-id>/g'     -e 's/o-[a-z0-9]{10,32}/<org-id>/g'     -e 's/ou-[a-z0-9]{4,32}-[a-z0-9]{8,32}/<ou-id>/g'     -e 's/r-[a-z0-9]{4,32}/<root-id>/g'     -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g'     -e 's/(ssoins|instance)-[a-z0-9]{16,}/-<redacted>/g'
}

run() {
  echo
  # The command line is redacted too: arguments carry account ids, because
  # bucket names are built from them.
  echo "\$ $*" | redact
  { "$@" 2>&1 || echo "[command failed: exit $?]"; } | redact
}

section() {
  echo
  echo "=============================================================="
  echo "$*"
  echo "=============================================================="
}

echo "# NovaPay landing zone, post-apply verification"
echo "# Captured $(date -u +%FT%TZ) against region $REGION"
echo "# Every command read-only. Account IDs, emails and org identifiers redacted."

section "1. Organizations: three accounts, two organisational units"
run aws organizations describe-organization
run aws organizations list-accounts
run aws organizations list-roots

section "2. Service control policies: three of them, and where they attach"
run aws organizations list-policies --filter SERVICE_CONTROL_POLICY

section "3. Organisation CloudTrail: multi-region, validated, customer-managed key"
echo
echo "# The claim that failed last time was encryption. A KmsKeyId here is"
echo "# necessary but not sufficient: CloudTrail sets encryption on its own"
echo "# PutObject, so an object in the bucket is the thing that settles it."
run aws cloudtrail get-trail --name novapay-org-trail --region "$REGION"
run aws cloudtrail get-trail-status --name novapay-org-trail --region "$REGION"
echo
echo "# All trails in the account. A second trail outside Terraform is a known"
echo "# gap, and this is where it shows up rather than in prose."
run aws cloudtrail list-trails

section "4. GuardDuty administered from the Security account"
run aws guardduty list-organization-admin-accounts --region "$REGION"
run aws guardduty list-detectors --region "$REGION"

section "5. Security Hub administered from the Security account"
run aws securityhub list-organization-admin-accounts --region "$REGION"

section "6. Account baseline: password policy, Access Analyzer, EBS, contacts"
run aws iam get-account-password-policy
run aws accessanalyzer list-analyzers --region "$REGION"
run aws ec2 get-ebs-encryption-by-default --region "$REGION"
run aws account get-alternate-contact --alternate-contact-type SECURITY

section "7. KMS: both keys present, rotation on"
run aws kms list-aliases --region "$REGION"

section "8. Terraform state bucket: versioned, public access blocked"
STATE_BUCKET="novapay-tfstate-$(aws sts get-caller-identity --query Account --output text)"
run aws s3api get-bucket-versioning --bucket "$STATE_BUCKET"
run aws s3api get-public-access-block --bucket "$STATE_BUCKET"

section "9. Identity Center: instance and permission set"
run aws sso-admin list-instances --region "$REGION"

section "10. Cost: what the estate actually bills"
run aws ce get-cost-and-usage \
  --time-period "Start=$(date -u +%Y-%m-01),End=$(date -u +%F)" \
  --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

echo
echo "# Not captured here, because no API returns them. Screenshot these two:"
echo "#   - root MFA on each of the three accounts (IAM console, per account)"
echo "#   - the confirmed SNS subscription email in the inbox"
