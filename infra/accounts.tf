# D1 Secure Landing Zone — the real member accounts.
# Explicit go/no-go step (see ARCHITECTURE_D1.md): creating a real AWS
# account is harder to reverse than anything else in D1 so far — closing one
# takes ~90 days to finalize, it's not a same-session `terraform destroy`.
#
# Security account uses a separate real inbox (not +addressing on the same
# Gmail as Workloads) so a compromise of one inbox can't password-reset both
# accounts at once — the Security account holds the org's log trail.
#
# close_on_deletion = true so `terraform destroy` actually requests closure
# instead of just forgetting the account in Terraform state while it keeps
# existing in AWS (the provider's default behavior, which would leak it).

resource "aws_organizations_account" "security" {
  name              = "novapay-security"
  email             = var.security_account_root_email
  parent_id         = aws_organizations_organizational_unit.security.id
  close_on_deletion = true

  # close_on_deletion means a destroy asks AWS to close a real account, and
  # closing takes about 90 days to finalise. Not a same-day mistake to undo.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_organizations_account" "workloads" {
  name              = "novapay-workloads"
  email             = var.workloads_account_root_email
  parent_id         = aws_organizations_organizational_unit.workloads.id
  close_on_deletion = true

  # Same reason as the Security account above.
  lifecycle {
    prevent_destroy = true
  }
}
