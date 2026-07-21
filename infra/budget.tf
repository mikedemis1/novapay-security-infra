# AWS Budgets: monitors monthly spend, emails at $20 and $35 before the $40 cap.
# Account billing currency is USD (confirmed via AWS API error), not EUR.
# Uses aws_budgets_budget (not CloudWatch billing alarms) — no us-east-1 provider
# alias needed, and it emails directly without an SNS topic in between.

resource "aws_budgets_budget" "monthly_cap" {
  name         = "novapay-monthly-budget"
  budget_type  = "COST"
  limit_amount = "40"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 20
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 35
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
