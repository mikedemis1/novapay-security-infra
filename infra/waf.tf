resource "aws_wafv2_web_acl" "novapay_waf" {
  name  = "novapay-waf"
  scope = "REGIONAL"

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "novapay-waf"
    sampled_requests_enabled   = true
  }

  default_action {
    allow {}
  }

  rule {
    name     = "novapay-waf-rule1"
    priority = 1

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "novapay-waf-rule1"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "novapay-waf-rule2"
    priority = 2

    action {
      count {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "novapay-waf-rule2"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "novapay-waf-rule3"
    priority = 3

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "novapay-waf-rule3"
      sampled_requests_enabled   = true
    }
  }
}