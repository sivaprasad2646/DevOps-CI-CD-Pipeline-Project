variable "vpc_name" {
  type        = string
  description = "Name of the VPC"
  default     = "Devops CI/CD Pipeline Project VPC"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_1_cidr" {
  type        = string
  description = "CIDR block for public subnet 1"
  default     = "10.0.1.0/24"
}

variable "public_subnet_2_cidr" {
  type        = string
  description = "CIDR block for public subnet 2"
  default     = "10.0.2.0/24"
}

variable "private_subnet_1_cidr" {
  type        = string
  description = "CIDR block for private subnet 1"
  default     = "10.0.3.0/24"
}

variable "private_subnet_2_cidr" {
  type        = string
  description = "CIDR block for private subnet 2"
  default     = "10.0.4.0/24"
}

variable "availability_zone_1" {
  type        = string
  description = "First availability zone"
  default     = "ap-south-1a"
}

variable "availability_zone_2" {
  type        = string
  description = "Second availability zone"
  default     = "ap-south-1b"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "production"
}
