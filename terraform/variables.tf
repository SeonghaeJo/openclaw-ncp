variable "region" {
  type    = string
  default = "KR"
}
variable "site" {
  type    = string
  default = "public"
}
variable "name" {
  type    = string
  default = "openclaw"
}
variable "subnet_no" {
  type    = string
  default = null
  validation {
    condition     = var.subnet_no == null ? true : can(regex("^[0-9]+$", var.subnet_no))
    error_message = "Existing IDs must be nonempty numeric IDs, never names."
  }
}
variable "login_key_name" {
  type = string
}
variable "hypervisor" {
  type    = string
  default = "KVM"
  validation {
    condition     = contains(["KVM", "XEN", "RHV"], var.hypervisor)
    error_message = "Use KVM, XEN or RHV."
  }
}
variable "server_image_number" {
  type    = string
  default = null
}
variable "ubuntu_release" {
  description = "Ubuntu LTS release selector used when server_image_number is omitted."
  type        = string
  default     = "24.04"
  validation {
    condition     = can(regex("^[0-9]{2}\\.[04]4$", var.ubuntu_release))
    error_message = "ubuntu_release must be an Ubuntu LTS release such as 22.04 or 24.04."
  }
}
variable "server_spec_code" {
  type    = string
  default = null
}
variable "server_spec_min_memory_gb" {
  description = "Minimum memory for automatic x86_64/KVM spec selection."
  type        = number
  default     = 4
}
variable "server_image_product_code" {
  type    = string
  default = null
}
variable "server_product_code" {
  type    = string
  default = null
}
variable "access_control_group_no_list" {
  type     = list(string)
  default  = []
  nullable = false
  validation {
    condition     = length(var.access_control_group_no_list) <= 3 && alltrue([for id in var.access_control_group_no_list : can(regex("^[0-9]+$", id))])
    error_message = "Supply up to three existing ACG IDs from the subnet VPC; empty creates a dedicated ACG."
  }
}

variable "vpc_mode" {
  type     = string
  default  = "reuse"
  nullable = false
  validation {
    condition     = contains(["create", "reuse"], var.vpc_mode)
    error_message = "Mode must be create or reuse."
  }
}

variable "subnet_mode" {
  type     = string
  default  = "reuse"
  nullable = false
  validation {
    condition     = contains(["create", "reuse"], var.subnet_mode)
    error_message = "Mode must be create or reuse."
  }
}

variable "vpc_no" {
  type    = string
  default = null
  validation {
    condition     = var.vpc_no == null ? true : can(regex("^[0-9]+$", var.vpc_no))
    error_message = "Existing IDs must be nonempty numeric IDs, never names."
  }
}

variable "vpc_cidr" {
  type    = string
  default = null
}

variable "subnet_cidr" {
  type    = string
  default = null
}

variable "zone" {
  type    = string
  default = null
}

variable "subnet_type" {
  type     = string
  default  = "PRIVATE"
  nullable = false
  validation {
    condition     = contains(["PUBLIC", "PRIVATE"], var.subnet_type)
    error_message = "subnet_type must be PUBLIC or PRIVATE (creation only)."
  }
}
variable "allocate_public_ip" {
  description = "null preserves legacy public IP on reused subnets; new subnets default to no public IP."
  type        = bool
  default     = null
}
variable "ssh_source_cidrs" {
  description = "Dedicated ACG SSH sources, IPv4 /8 or narrower; empty means no ingress. Not used with reused ACGs."
  type        = set(string)
  default     = []
  nullable    = false
  validation {
    condition     = alltrue([for c in var.ssh_source_cidrs : try(cidrnetmask(c) != "" && tonumber(split("/", c)[1]) >= 8, false)])
    error_message = "SSH sources must be IPv4 CIDRs /8 or narrower; prefer operator /32."
  }
}
