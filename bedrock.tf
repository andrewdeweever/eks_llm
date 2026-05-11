# variable "region" {
#   description = "AWS region"
#   type        = string
#   default     = "us-east-1"
# }

# # Security Group for Bedrock VPC Endpoint
# resource "aws_security_group" "bedrock_vpc_endpoint_sg" {
#   name        = "${var.project_name}-bedrock-vpc-endpoint-sg"
#   description = "Security group for Bedrock VPC Endpoint"
#   vpc_id      = module.vpc.vpc_id

#   ingress {
#     from_port   = 443
#     to_port     = 443
#     protocol    = "tcp"
#     cidr_blocks = module.vpc.private_subnets_cidr_blocks
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = {
#     Name = "${var.project_name}-bedrock-sg"
#   }
# }

# # VPC Endpoint for Bedrock Runtime
# resource "aws_vpc_endpoint" "bedrock_runtime" {
#   vpc_id              = module.vpc.vpc_id
#   service_name        = "com.amazonaws.${var.region}.bedrock-runtime"
#   vpc_endpoint_type   = "Interface"
#   subnet_ids          = module.vpc.private_subnets
#   security_group_ids  = [aws_security_group.bedrock_vpc_endpoint_sg.id]
#   private_dns_enabled = true
# }

# # IAM Role for API Gateway to invoke Bedrock
# resource "aws_iam_role" "apigw_bedrock_invoke_role" {
#   name = "${var.project_name}-apigw-invoke-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "apigateway.amazonaws.com"
#         }
#       }
#     ]
#   })
# }

# resource "aws_iam_policy" "apigw_bedrock_invoke_policy" {
#   name = "${var.project_name}-apigw-invoke-policy"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "bedrock:InvokeModel",
#           "bedrock:InvokeModelWithResponseStream"
#         ]
#         # Allow API Gateway to invoke any model since the OpenAI API payload passes the model name in the JSON body
#         Resource = "arn:aws:bedrock:${var.region}::foundation-model/*"
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "apigw_bedrock_invoke_attach" {
#   role       = aws_iam_role.apigw_bedrock_invoke_role.name
#   policy_arn = aws_iam_policy.apigw_bedrock_invoke_policy.arn
# }

# # API Gateway
# resource "aws_api_gateway_rest_api" "bedrock_api" {
#   name        = "${var.project_name}-inference-api"
#   description = "Public API Gateway for Bedrock endpoint (OpenAI Compatible)"

#   endpoint_configuration {
#     types = ["REGIONAL"]
#   }
# }

# # OpenAI Compatible Route Structure: /v1/chat/completions
# resource "aws_api_gateway_resource" "v1" {
#   rest_api_id = aws_api_gateway_rest_api.bedrock_api.id
#   parent_id   = aws_api_gateway_rest_api.bedrock_api.root_resource_id
#   path_part   = "v1"
# }

# resource "aws_api_gateway_resource" "chat" {
#   rest_api_id = aws_api_gateway_rest_api.bedrock_api.id
#   parent_id   = aws_api_gateway_resource.v1.id
#   path_part   = "chat"
# }

# resource "aws_api_gateway_resource" "completions" {
#   rest_api_id = aws_api_gateway_rest_api.bedrock_api.id
#   parent_id   = aws_api_gateway_resource.chat.id
#   path_part   = "completions"
# }

# resource "aws_api_gateway_method" "completions_method" {
#   rest_api_id   = aws_api_gateway_rest_api.bedrock_api.id
#   resource_id   = aws_api_gateway_resource.completions.id
#   http_method   = "POST"
#   authorization = "NONE" # Controlled via WAF + possible custom authorizers in future
# }

# resource "aws_api_gateway_integration" "bedrock_integration" {
#   rest_api_id             = aws_api_gateway_rest_api.bedrock_api.id
#   resource_id             = aws_api_gateway_resource.completions.id
#   http_method             = aws_api_gateway_method.completions_method.http_method
#   integration_http_method = "POST"
#   type                    = "AWS"
#   # Route requests directly to the Bedrock runtime's native OpenAI compatible endpoint
#   uri                     = "arn:aws:apigateway:${var.region}:bedrock-runtime:path/v1/chat/completions"
#   credentials             = aws_iam_role.apigw_bedrock_invoke_role.arn
# }

# resource "aws_api_gateway_method_response" "completions_response_200" {
#   rest_api_id = aws_api_gateway_rest_api.bedrock_api.id
#   resource_id = aws_api_gateway_resource.completions.id
#   http_method = aws_api_gateway_method.completions_method.http_method
#   status_code = "200"
# }

# resource "aws_api_gateway_integration_response" "bedrock_integration_response" {
#   rest_api_id = aws_api_gateway_rest_api.bedrock_api.id
#   resource_id = aws_api_gateway_resource.completions.id
#   http_method = aws_api_gateway_method.completions_method.http_method
#   status_code = aws_api_gateway_method_response.completions_response_200.status_code

#   depends_on = [
#     aws_api_gateway_integration.bedrock_integration
#   ]
# }

# resource "aws_api_gateway_deployment" "api_deployment" {
#   rest_api_id = aws_api_gateway_rest_api.bedrock_api.id

#   depends_on = [
#     aws_api_gateway_integration.bedrock_integration
#   ]

#   lifecycle {
#     create_before_destroy = true
#   }
# }

# # CloudWatch Log Group for API Gateway
# resource "aws_cloudwatch_log_group" "api_gw_logs" {
#   name              = "/aws/api_gw/${aws_api_gateway_rest_api.bedrock_api.name}"
#   retention_in_days = 14
# }

# # API Gateway Stage
# resource "aws_api_gateway_stage" "api_stage_prod" {
#   deployment_id = aws_api_gateway_deployment.api_deployment.id
#   rest_api_id   = aws_api_gateway_rest_api.bedrock_api.id
#   stage_name    = "prod"

#   access_log_settings {
#     destination_arn = aws_cloudwatch_log_group.api_gw_logs.arn
#     format          = jsonencode({
#       requestId      = "$context.requestId"
#       ip             = "$context.identity.sourceIp"
#       requestTime    = "$context.requestTime"
#       httpMethod     = "$context.httpMethod"
#       routeKey       = "$context.routeKey"
#       status         = "$context.status"
#       protocol       = "$context.protocol"
#       responseLength = "$context.responseLength"
#     })
#   }
# }

# # WAF for API Gateway
# resource "aws_wafv2_web_acl" "api_waf" {
#   name        = "${var.project_name}-api-waf"
#   description = "WAF for Bedrock API Gateway"
#   scope       = "REGIONAL"

#   default_action {
#     allow {}
#   }

#   rule {
#     name     = "AWSManagedRulesCommonRuleSet"
#     priority = 1

#     override_action {
#       none {}
#     }

#     statement {
#       managed_rule_group_statement {
#         name        = "AWSManagedRulesCommonRuleSet"
#         vendor_name = "AWS"
#       }
#     }

#     visibility_config {
#       cloudwatch_metrics_enabled = true
#       metric_name                = "AWSManagedRulesCommonRuleSetMetric"
#       sampled_requests_enabled   = true
#     }
#   }

#   rule {
#     name     = "RateLimit"
#     priority = 2

#     action {
#       block {}
#     }

#     statement {
#       rate_based_statement {
#         limit              = 100
#         aggregate_key_type = "IP"
#       }
#     }

#     visibility_config {
#       cloudwatch_metrics_enabled = true
#       metric_name                = "RateLimitMetric"
#       sampled_requests_enabled   = true
#     }
#   }

#   visibility_config {
#     cloudwatch_metrics_enabled = true
#     metric_name                = "${var.project_name}-api-waf-metric"
#     sampled_requests_enabled   = true
#   }
# }

# # Associate WAF with API Gateway
# resource "aws_wafv2_web_acl_association" "api_waf_assoc" {
#   resource_arn = aws_api_gateway_stage.api_stage_prod.arn
#   web_acl_arn  = aws_wafv2_web_acl.api_waf.arn
# }

# # Output
# output "public_invocation_url" {
#   description = "OpenAI-compatible public URL to invoke the Bedrock model via API Gateway"
#   value       = "${aws_api_gateway_stage.api_stage_prod.invoke_url}/v1/chat/completions"
# }
