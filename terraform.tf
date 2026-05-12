terraform {
  # Store the state file in the remote state bucket
  backend "s3" {
    bucket       = "cloudwatch-project-remote-state"
    key          = "cloudwatch-project-remote-state/terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
  }

  required_version = "~> 1.14.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}