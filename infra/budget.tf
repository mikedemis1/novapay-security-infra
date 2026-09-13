# AWS Budgets: monitors monthly spend. Account billing currency is USD
# (confirmed via AWS API error), not EUR. Uses aws_budgets_budget (not
# CloudWatch billing alarms) — no us-east-1 provider alias needed, and it emails
# directly without an SNS topic in between.
#
# Retuned 2026-09-13 for the near-zero-spend model. The old shape was a 40 USD
# cap warning at 20 and 35, which under this model would never warn in time: by
# the time it spoke, a month of unwanted spend had already happened.
#
# Thresholds were chosen from a read-back, not a guess. On 2026-09-13
# describe-budget reported 3.66 USD month-to-date. An inventory of all three
# accounts on the same day found no Elastic IPs, no NAT gateways, no running
# instances, no customer-managed KMS keys and no secrets, and the two non-empty
# S3 buckets hold 68 MB and 10 MB — roughly a fifth of a cent a month. So that
# 3.66 is almost entirely the first six days of September, before the
# 2026-09-06 wind-down and the 2026-09-11 CMK removal. Steady-state cost from
# here is cents, which is what makes a 1 USD alarm meaningful rather than noise.
#
# Note that the first ACTUAL alert will fire as soon as this applies, because
# this month has already passed 1 USD. That is a true statement about September,
# not a misconfiguration.
#
# AWS Budgets updates on a lag and cannot stop spending. This is a bell, not a
# switch: a 1 USD alert does not make the account free.

resource "aws_budgets_budget" "monthly_cap" {
  name         = "novapay-monthly-budget"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Something is running that should not be.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 1
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  # Forecast, so a resource left running on a test day is caught in the morning
  # rather than in next month's bill. This is the one that earns its keep.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 5
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
