provider "aws" {
  region = local.region
  assume_role {
    role_arn = "TF_ROLE"
  }
}