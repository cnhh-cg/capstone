terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region     = "us-west-2"  
  access_key = ""
  secret_key = ""
}


// Create an IAM role for the pipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })
}

// Create an S3 bucket for storing the build artifacts
resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket = "my-codepipeline-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }
}

// Create an ECR repository for the Docker image
resource "aws_ecr_repository" "ecr_repo" {
  name = "my-ecr-repo"
}

#Create secrete manager to store 
resource "aws_secretsmanager_secret" "github_token_secret" {
  name = "github-token-secret"

  tags = {
    Environment = "production"
  }
}

# aws_secretsmanager_secret_version that retrieves the secret value from AWS Secrets Manager 
# using the secret_id specified in the var.github_token_secret_id variable.
# create secrete version 

resource "aws_secretsmanager_secret_version" "github_token_secret_version" {
  secret_id     = aws_secretsmanager_secret.github_token_secret.id
  secret_string = var.github_token
  # NOTE : This github_token need to be passing in as commandline when we run terraform
}

data "aws_secretsmanager_secret_version" "github_token" {
  secret_id = "github-token-secret-id"
}


// Create a CodeBuild project for building and pushing the Docker image
resource "aws_codebuild_project" "docker_build" {
  name = "my-docker-build"
  description = "Builds a Docker image from a GitHub repository and pushes it to ECR"
  service_role = aws_iam_role.codepipeline_role.arn
  artifacts {
    type = "NO_ARTIFACTS"
  }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:4.0"
    type         = "LINUX_CONTAINER"
    privileged_mode = true
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.aws_account_id
    }
    environment_variable {
      name  = "AWS_REGION"
      value = "us-west-2"
    }
  }
  source {
    type            = "GITHUB"
    location        = "https://github.com/my-user/my-repo"
    buildspec       = "buildspec.yml"
    git_clone_depth = 1
  }
}

// Create a CodePipeline for orchestrating the build and push process
resource "aws_codepipeline" "docker_pipeline" {
  name     = "my-docker-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name            = "SourceAction"
      category        = "Source"
      owner           = "ThirdParty"
      provider        = "GitHub"
      version         = "1"
      output_artifacts = ["source_output"]
      configuration   = {
        Owner             = "my-user"
        Repo              = "my-repo"
        Branch            = "main"
        OAuthToken        = data.aws_secretsmanager_secret_version.github_token.secret_string
        PollForSourceChanges = "true"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name            = "BuildAction"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version         = "1"
      configuration   = {
        ProjectName = aws_codebuild_project.docker_build.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "DeployAction"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECR"
      input_artifacts  = ["build_output"]
      version         = "1"
      configuration   = {
        RepositoryName  = aws_ecr_repository.ecr_repo.name
        ImageTag        = "latest"
      }
    }
  }
}
