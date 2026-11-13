variable "region" {
  description = "AWS region (use the same region as your Management Server)"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  type    = string
  default = "lms"
}

variable "instance_type" {
  description = "Instance type for app and DB servers"
  type        = string
  default     = "t3.micro"
}

variable "public_key_path" {
  description = "Public key generated on the Management Server (ssh-keygen)"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "private_key_path" {
  description = "Matching private key, written into the Ansible inventory"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
