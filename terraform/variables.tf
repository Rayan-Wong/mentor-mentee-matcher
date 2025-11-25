variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "aws_az" {
  type        = string
  default     = "ap-southeast-1a"
  description = "Default AZ for single AZ deploy"
}

variable "env" {
  type        = string
  description = "Deployment environment (dev, staging, prod)"
  default     = "prod"
}

variable "app_name" {
  type        = string
  description = "Application name"
  default     = "asp_proj"
}

variable "ecs_cluster_name" {

  type        = string
  description = "ECS Cluster Name"
  default     = "app-cluster"
}

variable "owner" {
  type        = string
  description = "Team or person responsible for this infra"
  default     = "e-scholars"
}

variable "app_port" {
  type        = number
  description = "Port app is listening at"
  default     = 5000
}

variable "certificate_arn" {
  type        = string
  description = "ACM Certificate ARN"
  default     = "arn:aws:acm:ap-southeast-1:368339042148:certificate/eb6d11e7-9664-49e9-a277-7780be53688a"
}

variable "ami_id" {
  type        = string
  description = "AMI ID"
  default     = "ami-0929b541f173e08bc"
}

variable "ec2_instance_type" {
  type        = string
  description = "EC2 Instance Type"
  default     = "t2.micro"
}

variable "ec2_iam_role" {
  type        = string
  description = "EC2 Instance Role name"
  default     = "ecsInstanceRole"
}

variable "execution_iam_role" {
  type        = string
  description = "ECS Execution Role ARN"
  default     = "arn:aws:iam::368339042148:role/ecsTaskExecutionRole"
}

variable "dns_zone_id" {
  type        = string
  description = "Cloudflare DNS Zone ID"
  default     = "1853f51ba6d3f5081e6477329ccd706c"
}

variable "root_cname" {
  type        = string
  description = "Root URL"
  default     = "mentor-mentee-matcher"
}

variable "use_localstack" {
  type        = bool
  description = "Use LocalStack for local dev or actual (DEFAULT IS FALSE)"
  default     = false
}

variable "mock_acm_arn" {
  type        = string
  description = "Mock ACM for LocalStack"
  default     = ""
}

variable "mock_ecsTaskExecutionRoleARN" {
  type        = string
  description = "Mock ARN for ecsTaskExecutionRole in LocalStack"
  default     = ""
}
