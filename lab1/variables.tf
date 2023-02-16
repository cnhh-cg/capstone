variable "pipeline_name" {
  type    = string
  default = "room2_ch_github_pineline"
}

variable "github_repo_name" {
  type    = string
  default = "cnhh-cg/weather-app-indicator"
}

variable "dockerfile_name" {
  type    = string
  default = "Dockerfile"
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}
# AWS_ACCOUNT_ID
variable "aws_account_id" {
  type    = string
  default = "962804699607"
}


data "aws_secretsmanager_secret_version" "github_token" {
  secret_id = "github-token-secret-id"
}

variable "github_token" {
  default = "please provide you github token during terraform init"
}


variable "ecr_repository_name" {
  type    = string
  default = "ch-repository"
}

