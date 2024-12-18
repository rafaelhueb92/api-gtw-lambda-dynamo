#!/bin/bash

# Define project directories
PROJECT_NAME="dashboard-project"
mkdir -p $PROJECT_NAME/{lambda,terraform,tests}
cd $PROJECT_NAME

# Create Terraform main.tf file
cat <<EOF > terraform/main.tf
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
  filename      = "\${path.module}/lambda_package.zip"

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
  target    = "integrations/\${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "get_route" {
  api_id    = aws_apigatewayv2_api.dashboard_api.id
  route_key = "GET /dashboard"
  target    = "integrations/\${aws_apigatewayv2_integration.lambda_integration.id}"
}
EOF

# Create Lambda app.py file
cat <<EOF > lambda/app.py
import os
import boto3
import json

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.getenv('DYNAMODB_TABLE'))

def lambda_handler(event, context):
    http_method = event.get("httpMethod")
    
    if http_method == "POST":
        try:
            body = json.loads(event["body"])
            item = {
                "id": f"{body['type']}#{body['nameDashboard']}",
                "values": body["values"]
            }
            table.put_item(Item=item)
            return {
                "statusCode": 201,
                "body": json.dumps({"message": "Item created successfully"})
            }
        except Exception as e:
            return {"statusCode": 400, "body": json.dumps({"error": str(e)})}
    
    elif http_method == "GET":
        type_prefix = event["queryStringParameters"].get("type", "")
        response = table.scan(
            FilterExpression="begins_with(id, :prefix)",
            ExpressionAttributeValues={":prefix": type_prefix}
        )
        return {"statusCode": 200, "body": json.dumps(response["Items"])}

    return {"statusCode": 400, "body": json.dumps({"message": "Invalid HTTP Method"})}
EOF

# Create OpenAPI Specification (Swagger Documentation)
cat <<EOF > openapi.yaml
openapi: 3.0.3
info:
  title: Dashboard API
  description: API for managing dashboards and retrieving data.
  version: 1.0.0
servers:
  - url: https://{api_gateway_url}
    description: Production server
    variables:
      api_gateway_url:
        default: "localhost:3000"

paths:
  /dashboard:
    post:
      summary: Create a new dashboard item
      description: Add a new item to the DynamoDB table.
      operationId: createDashboard
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required:
                - type
                - nameDashboard
                - values
              properties:
                type:
                  type: string
                  description: The type of the dashboard.
                nameDashboard:
                  type: string
                  description: The name of the dashboard.
                values:
                  type: string
                  description: Additional values for the dashboard.
      responses:
        '201':
          description: Item created successfully.
        '400':
          description: Invalid request body.
    get:
      summary: Retrieve dashboard items
      description: Get all dashboard items filtered by type.
      operationId: getDashboards
      parameters:
        - name: type
          in: query
          required: true
          description: The type prefix to filter dashboard items.
          schema:
            type: string
      responses:
        '200':
          description: Successfully retrieved items.
          content:
            application/json:
              schema:
                type: array
                items:
                  type: object
        '400':
          description: Invalid query parameters.
EOF

# Create Unit Tests
cat <<EOF > tests/test_app.py
import app

def test_create_dashboard():
    event = {
        "httpMethod": "POST",
        "body": '{"type": "dashboard", "nameDashboard": "Main", "values": "test data"}'
    }
    response = app.lambda_handler(event, None)
    assert response["statusCode"] == 201

def test_get_dashboards():
    event = {
        "httpMethod": "GET",
        "queryStringParameters": {"type": "dashboard"}
    }
    response = app.lambda_handler(event, None)
    assert response["statusCode"] == 200
EOF

# Zip Lambda package
cd lambda
zip ../lambda_package.zip app.py
cd ..

# Print Completion Message
echo "Project structure created successfully."
