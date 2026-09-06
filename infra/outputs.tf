# Consumed by the workload stack in infra/workload, which reads this state
# rather than duplicating lookups. Only what crosses the boundary is exported:
# an output here is a promise to another stack, so the list is kept short on
# purpose.

output "workloads_account_id" {
  description = "Account the workload stack deploys into"
  value       = aws_organizations_account.workloads.id
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "app_subnet_ids" {
  description = "Private app-tier subnets, in AZ order"
  value       = [aws_subnet.app_a.id, aws_subnet.app_b.id]
}

output "public_subnet_ids" {
  description = "Public subnets, in AZ order"
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "private_route_table_id" {
  description = "Private route table. The workload stack adds the NAT route to it for as long as the cluster exists, and removes it on teardown."
  value       = aws_route_table.private.id
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}

output "app_data_kms_key_arn" {
  description = "CMK the secret is encrypted with. The workload stack grants its pod role kms:Decrypt on it."
  value       = aws_kms_key.app_data.arn
}
