terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Create the IAM roles: Create the IAM roles that are required to allow the code pipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "${var.pipeline_name}-role"

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


#Create Policy for the role to have acccess
resource "aws_iam_role_policy_attachment" "pipeline_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipelineFullAccess"
  role       = aws_iam_role.codepipeline_role.name
}

resource "aws_iam_policy" "codebuild_policy" {
  name = "codebuild_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:PutObjectAcl"]
        Resource = ["arn:aws:s3:::my-bucket/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy_attachment" {
  policy_arn = aws_iam_policy.codebuild_policy.arn
  role       = aws_iam_role.codepipeline_role.name
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

#create code pipeline
resource "aws_codepipeline" "pipeline" {
  name     = var.pipeline_name
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = "pipeline-artifacts-${var.aws_region}"
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name     = "Source"
      category = "Source"
      owner    = "ThirdParty"
      provider = "GitHub"
      version  = "1"

      configuration = {
        Owner      = "<OWNER>"
        Repo       = var.github_repo_name
        Branch     = "master"
        OAuthToken = data.aws_secretsmanager_secret_version.github_token.secret_string
      }

      output_artifacts = ["SourceOutput"]
    }
  }

  stage {
    name = "Build"
    action {
      name     = "BuildAction"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"
      configuration = {
        ProjectName = aws_codebuild_project.build_project.name
      }
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
    }
  }
  stage {
    name = "Deploy"
    action {
      name     = "DeployAction"
      category = "Deploy"
      owner    = "AWS"
      provider = "ECR"
      version  = "1"
      configuration = {
        RepositoryName = aws_ecr_repository.ecr_repo.name
        ImageTag       = "latest"
      }
      input_artifacts = ["build_output"]
      run_order       = 1
      role_arn        = aws_iam_role.codepipeline_role.arn
      run_command = join("", [
        data.aws_ecr_get_login_command.ecr_login_command.execution_arn, " | sh"
      ])
    }
  }

  artifact_store {
    type       = "S3"
    location   = aws_s3_bucket.pipeline_artifacts.bucket
    encryption = true
  }
}




#create a repository
resource "aws_ecr_repository" "my_repository" {
  name = var.ecr_repository_name
}

# Build and push the Docker image to ECR
resource "aws_ecr_registry_image" "my_image" {
  image_name = "${aws_ecr_repository.my_repository.repository_url}:latest"
  build {
    context    = "."
    dockerfile = "Dockerfile"
  }
}
# Output the ECR repository URL
output "ecr_repository_url" {
  value = aws_ecr_repository.my_repository.repository_url
}

#Code build 
#define a build project
resource "aws_codebuild_project" "build_project" {
  name         = "${var.pipeline_name}-build"
  service_role = aws_iam_role.codepipeline_role.arn

  source {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/docker:1.12.1"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "DOCKERFILE_NAME"
      value = var.dockerfile_name
    }
  }

  build {
    commands = [
      "docker build -t myimage . -f $DOCKERFILE_NAME",
      "docker tag myimage:latest <AWS_ACCOUNT_ID>.dkr.ecr.${var.aws_region}.amazonaws.com/myimage:latest",
      "$(aws ecr get-login --region ${var.aws_region} --no-include-email)",
      # Tag the Docker image with the ECR repository URI
      "docker tag my-image ${ecr_repository_url}:latest",
      # Push the Docker image to the ECR repository
      "docker push ${ecr_repository_url}:latest"
      //"docker push <AWS_ACCOUNT_ID>.dkr.ecr.${var.aws_region}.amazonaws.com/myimage:latest"
    ]
  }
}



/*

resource "aws_ecr_repository" "group2_c1_ch_first_ecr_repo" {
  name = "group2-c1-ch-first-ecr-repo" # Naming my repository
}

resource "aws_ecs_cluster" "group2_c1_ch_cluster" {
  name = "group2-c1-ch-cluster" # Naming the cluster
}

resource "aws_ecs_task_definition" "group2_c1_ch_first_task" {
  family                   = "group2-c1-ch-first-task" # Naming our first task
  container_definitions    = <<DEFINITION
  [
    {
      "name": "group2-c1-ch-first-task",
      "image": "${aws_ecr_repository.group2_c1_ch_first_ecr_repo.repository_url}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 3000,
          "hostPort": 3000
        }
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"] # Stating that we are using ECS Fargate
  network_mode             = "awsvpc"    # Using awsvpc as our network mode as this is required for Fargate
  memory                   = 512         # Specifying the memory our container requires
  cpu                      = 256         # Specifying the CPU our container requires
  execution_role_arn       = "${aws_iam_role.group2_c1_ch_ecsTaskExecutionRole.arn}"
}

resource "aws_iam_role" "group2_c1_ch_ecsTaskExecutionRole" {
  name               = "group2_c1_ecsTaskExecutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.group2_c1_ch_assume_role_policy.json}"
}

data "aws_iam_policy_document" "group2_c1_ch_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "group2_c1_ch_ecsTaskExecutionRole_policy" {
  role       = "${aws_iam_role.group2_c1_ch_ecsTaskExecutionRole.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Providing a reference to our default VPC
resource "aws_default_vpc" "default_vpc" {
}

# Providing a reference to our default subnets
resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "us-west-2a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "us-west-2b"
}

resource "aws_default_subnet" "default_subnet_c" {
  availability_zone = "us-west-2c"
}




resource "aws_ecs_service" "group2_c1_ch_first_service" {
  name            = "group2-c1-ch-first-service"                             # Naming our first service
  cluster         = "${aws_ecs_cluster.group2_c1_ch_cluster.id}"             # Referencing our created Cluster
  task_definition = "${aws_ecs_task_definition.group2_c1_ch_first_task.arn}" # Referencing the task our service will spin up
  launch_type     = "FARGATE"
  desired_count   = 3 # Setting the number of containers we want deployed to 3
  load_balancer {
    target_group_arn = "${aws_lb_target_group.ch_target_group.arn}" # Referencing our target group
    container_name   = "${aws_ecs_task_definition.group2_c1_ch_first_task.family}"
    container_port   = 3000 # Specifying the container port
  }

  network_configuration {
    subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}", 
"${aws_default_subnet.default_subnet_c.id}"]
    assign_public_ip = true # Providing our containers with public IPs
    security_groups  = ["${aws_security_group.group2_c1_ch_service_security_group.id}"] # Setting the security group
  }
 }


                                                                                                                 
resource "aws_security_group" "group2_c1_ch_service_security_group" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = ["${aws_security_group.group2_c1_ch_load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0 # Allowing any incoming port
    to_port     = 0 # Allowing any outgoing port
    protocol    = "-1" # Allowing any outgoing protocol
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}

resource "aws_alb" "group2_c1_application_load_balancer" {
  name               = "group2-c1-ch-test-lb-tf" # Naming our load balancer
  load_balancer_type = "application"
  subnets = [ # Referencing the default subnets
    "${aws_default_subnet.default_subnet_a.id}",
    "${aws_default_subnet.default_subnet_b.id}",
    "${aws_default_subnet.default_subnet_c.id}"
  ]
  # Referencing the security group
  security_groups = ["${aws_security_group.group2_c1_ch_load_balancer_security_group.id}"]
}

# Creating a security group for the load balancer:
resource "aws_security_group" "group2_c1_ch_load_balancer_security_group" {
  ingress {
    from_port   = 80 # Allowing traffic in from port 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic in from all sources
  }

  egress {
    from_port   = 0 # Allowing any incoming port
    to_port     = 0 # Allowing any outgoing port
    protocol    = "-1" # Allowing any outgoing protocol
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}



resource "aws_lb_target_group" "ch_target_group" {
  name        = "group2-c1-ch-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "${aws_default_vpc.default_vpc.id}" # Referencing the default VPC
  health_check {
    matcher = "200,301,302"
    path = "/"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = "${aws_alb.group2_c1_application_load_balancer.arn}" # Referencing our load balancer
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.ch_target_group.arn}" # Referencing our tagrte group
  }
}
           
*/