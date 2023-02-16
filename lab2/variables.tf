#data "aws_caller_identity" "current" {}


variable "github_token" {
  default = "please provide you github token during terraform init"
}
variable "aws_account_id" {
  type    = string
  default = "962804699607"
}