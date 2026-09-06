# GuardDuty and Security Hub existed for a month with no path to a human:
# findings landed in a dashboard nobody had a reason to open. This sends
# HIGH and CRITICAL Security Hub findings to an email address. Security Hub
# already aggregates GuardDuty, so one rule covers both.
#
# Lives in the Security account because that is the delegated administrator,
# and an EventBridge rule only matches events on its own account bus. Run
# from the management account it would have matched that account only.

resource "aws_sns_topic" "security_alerts" {
  provider = aws.security
  name     = "novapay-security-alerts"

  # checkov:skip=CKV_AWS_26: not encrypted at rest, deliberately. EventBridge
  # cannot publish to a topic encrypted with the AWS-managed SNS key, so this
  # would need a customer-managed key at roughly a dollar a month to protect
  # finding metadata that Security Hub already holds unencrypted anyway.
  # Revisit if the topic ever carries finding detail rather than a pointer.
}

resource "aws_sns_topic_subscription" "security_alerts_email" {
  provider  = aws.security
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.security_alerts_email
}

resource "aws_cloudwatch_event_rule" "high_severity_findings" {
  provider = aws.security
  name     = "novapay-high-severity-findings"

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
  provider  = aws.security
  rule      = aws_cloudwatch_event_rule.high_severity_findings.name
  target_id = "security-alerts-sns"
  arn       = aws_sns_topic.security_alerts.arn
}

data "aws_iam_policy_document" "security_alerts_topic" {
  provider = aws.security

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
  provider = aws.security
  arn      = aws_sns_topic.security_alerts.arn
  policy   = data.aws_iam_policy_document.security_alerts_topic.json
}
