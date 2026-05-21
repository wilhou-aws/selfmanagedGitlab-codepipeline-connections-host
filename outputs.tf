output "gitlab_vpc_id" {
  description = "VPC ID for the GitLab VPC"
  value       = aws_vpc.gitlab_vpc.id
}

output "pipeline_vpc_id" {
  description = "VPC ID for the Pipeline VPC"
  value       = aws_vpc.pipeline_vpc.id
}

output "vpc_peering_connection_id" {
  description = "VPC Peering Connection ID"
  value       = aws_vpc_peering_connection.gitlab_to_pipeline.id
}

output "gitlab_instance_id" {
  description = "EC2 Instance ID for GitLab server"
  value       = aws_instance.gitlab.id
}

output "gitlab_private_ip" {
  description = "Private IP of the GitLab EC2 instance"
  value       = aws_instance.gitlab.private_ip
}

output "codestar_host_arn" {
  description = "ARN of the CodeStar Connections Host"
  value       = aws_codestarconnections_host.gitlab_host.arn
}

output "codestar_connection_arn" {
  description = "ARN of the CodeStar Connection to GitLab"
  value       = aws_codestarconnections_connection.gitlab_connection.arn
}

output "codestar_connection_status" {
  description = "Status of the CodeStar Connection"
  value       = aws_codestarconnections_connection.gitlab_connection.connection_status
}
