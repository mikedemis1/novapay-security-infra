# D1 gap-analysis finding #1 (2026-08-08): GuardDuty + Security Hub existed
# with no path to a human. Findings sat in a dashboard nobody would check.
# This wires HIGH/CRITICAL Security Hub findings (which already include
# every GuardDuty finding, since Security Hub aggregates it) to an email.

resource "aws_sns_topic" "security_alerts" {
  name = "novapay-security-alerts"
}

resource "aws_sns_topic_subscription" "security_alerts_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.security_alerts_email
}

resource "aws_cloudwatch_event_rule" "high_severity_findings" {
  name = "novapay-high-severity-findings"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["CRITICAL", "HIGH"]
        }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "security_alerts" {
  rule      = aws_cloudwatch_event_rule.high_severity_findings.name
  target_id = "security-alerts-sns"
  arn       = aws_sns_topic.security_alerts.arn
}

data "aws_iam_policy_document" "security_alerts_topic" {
  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.security_alerts.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.high_severity_findings.arn]
    }
  }
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn    = aws_sns_topic.security_alerts.arn
  policy = data.aws_iam_policy_document.security_alerts_topic.json
}
