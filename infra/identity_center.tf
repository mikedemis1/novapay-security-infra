# D1 Secure Landing Zone — human access into the real member accounts.
# IAM Identity Center itself (the instance + directory) was enabled manually
# in the console (no Terraform API for that first step). Everything past
# that — permission sets, who gets them, on which accounts — is Terraform.

data "aws_ssoadmin_instances" "main" {}

locals {
  sso_instance_arn  = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]
}

data "aws_identitystore_user" "mike" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = "mike"
    }
  }
}

resource "aws_ssoadmin_permission_set" "admin" {
  name         = "AdministratorAccess"
  instance_arn = local.sso_instance_arn
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssoadmin_account_assignment" "admin_security" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  principal_id       = data.aws_identitystore_user.mike.user_id
  principal_type     = "USER"
  target_id          = aws_organizations_account.security.id
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "admin_workloads" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  principal_id       = data.aws_identitystore_user.mike.user_id
  principal_type     = "USER"
  target_id          = aws_organizations_account.workloads.id
  target_type        = "AWS_ACCOUNT"
}
