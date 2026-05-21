variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "gitlab_instance_type" {
  description = "EC2 instance type for GitLab server"
  type        = string
  default     = "t3.large"
}

variable "ssh_public_key" {
  description = "SSH public key for GitLab EC2 instance access"
  type        = string
}



variable "gitlab_token_name" {
  description = "Name for the GitLab personal access token"
  type        = string
  default     = "pipeline-token"
}

variable "gitlab_personal_access_token" {
  description = "Value for the GitLab personal access token (pre-defined)"
  type        = string
  sensitive   = true
}
