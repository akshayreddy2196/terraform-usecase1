variable "region" {
  default = "us-east-1"
}

variable "key_name" {
  description = "EC2 Key Pair name"
  type        = string
}

variable "instance_names" {
  default = ["Home", "Images", "Register"]
}

variable "paths" {
  default = ["/", "/images", "/register"]
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}
