terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.44.0"
    }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "us-east-1" # Adjust as needed
}

resource "aws_dynamodb_table" "dashboard_table" {
  name           = "dashboard_table"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_dashboard_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  inline_policy {
    name   = "lambda-dynamodb-policy"
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Effect   = "Allow",
          Action   = ["dynamodb:*"],
          Resource = "*"
        }
      ]
    })
  }
}

resource "aws_lambda_function" "dashboard_lambda" {
  function_name = "dashboard_lambda"
  runtime       = "python3.9"
  handler       = "app.lambda_handler"
  filename      = "${path.module}/lambda_package.zip"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.dashboard_table.name
    }
  }

  role = aws_iam_role.lambda_role.arn
}

resource "aws_apigatewayv2_api" "dashboard_api" {
  name          = "Dashboard API"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.dashboard_api.id
  name        = "prod"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.dashboard_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.dashboard_lambda.invoke_arn
}

resource "aws_apigatewayv2_route" "post_route" {
  api_id    = aws_apigatewayv2_api.dashboard_api.id
  route_key = "POST /dashboard"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "get_route" {
  api_id    = aws_apigatewayv2_api.dashboard_api.id
  route_key = "GET /dashboard"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}
