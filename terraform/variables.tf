variable "aws_region" {
  default     = "us-east-1"
  description = "AWS region to deploy resources"
}

variable "cluster_name" {
  default     = "voting-app-cluster"
  description = "Name of the Kubernetes cluster"
}