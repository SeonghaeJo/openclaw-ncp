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
  type = string
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
variable "server_spec_code" {
  type    = string
  default = null
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
  type = list(string)
  validation {
    condition     = length(var.access_control_group_no_list) > 0 && length(var.access_control_group_no_list) <= 3
    error_message = "Supply one to three existing ACG IDs from the subnet VPC."
  }
}
