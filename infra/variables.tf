variable "budget_alert_email" {
  description = "Email address that receives AWS Budgets threshold notifications"
  type        = string
}

# Real root-account emails and alert addresses were hardcoded directly in
# accounts.tf/alerting.tf until 2026-08-09 - moved to variables (same pattern
# as budget_alert_email above) before making the repo public, since a public
# root email on an account without MFA yet (Workloads) is a real phishing/
# password-reset attack surface, not just a cosmetic detail.

variable "security_account_root_email" {
  description = "Root email for the Security member account (real address, not committed)"
  type        = string
}

variable "workloads_account_root_email" {
  description = "Root email for the Workloads member account (real address, not committed)"
  type        = string
}

variable "security_alerts_email" {
  description = "Email address that receives HIGH/CRITICAL Security Hub finding alerts"
  type        = string
}

variable "security_contact_phone" {
  description = "Phone number for the AWS account security alternate contact (E.164, e.g. +302101234567)"
  type        = string
}
