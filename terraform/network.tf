# IDs are exact lookups, never name-based adoption or create-on-lookup-failure.
data "ncloud_subnet" "existing" {
  count = var.subnet_mode == "reuse" && var.subnet_no != null ? 1 : 0
  id    = var.subnet_no
}
data "ncloud_vpc" "existing" {
  count = var.vpc_mode == "reuse" ? 1 : 0
  id    = var.vpc_no != null ? var.vpc_no : try(data.ncloud_subnet.existing[0].vpc_no, "invalid-missing-vpc-id")
}
locals {
  vpc_no            = var.vpc_mode == "create" ? ncloud_vpc.managed[0].id : data.ncloud_vpc.existing[0].id
  vpc_cidr          = var.vpc_mode == "create" ? var.vpc_cidr : data.ncloud_vpc.existing[0].ipv4_cidr_block
  subnet_no         = var.subnet_mode == "create" ? ncloud_subnet.managed[0].id : try(data.ncloud_subnet.existing[0].id, null)
  subnet_type       = var.subnet_mode == "create" ? var.subnet_type : try(data.ncloud_subnet.existing[0].subnet_type, null)
  zone              = var.subnet_mode == "create" ? var.zone : try(data.ncloud_subnet.existing[0].zone, null)
  network_acl_no    = var.subnet_mode == "create" ? (var.vpc_mode == "create" ? ncloud_vpc.managed[0].default_network_acl_no : data.ncloud_vpc.existing[0].default_network_acl_no) : try(data.ncloud_subnet.existing[0].network_acl_no, null)
  public_ip_enabled = var.allocate_public_ip != null ? var.allocate_public_ip : var.subnet_mode == "reuse"
  acg_ids           = length(var.access_control_group_no_list) > 0 ? var.access_control_group_no_list : [ncloud_access_control_group.managed[0].id]
  # Numeric IPv4 bounds permit containment checks without a live account.
  cidrs = { vpc = local.vpc_cidr, subnet = var.subnet_cidr }
  cidr_valid = { for k, c in local.cidrs : k => try(
    cidrnetmask(c) != "" && tonumber(split("/", c)[1]) >= 16 && tonumber(split("/", c)[1]) <= 28 &&
    split("/", c)[0] == cidrhost(c, 0) && (
      split(".", cidrhost(c, 0))[0] == "10" ||
      (split(".", cidrhost(c, 0))[0] == "172" && tonumber(split(".", cidrhost(c, 0))[1]) >= 16 && tonumber(split(".", cidrhost(c, 0))[1]) <= 31) ||
      (split(".", cidrhost(c, 0))[0] == "192" && split(".", cidrhost(c, 0))[1] == "168")
  ), false) }
  cidr_start = { for k, c in local.cidrs : k => try(sum([for i, octet in split(".", cidrhost(c, 0)) : tonumber(octet) * pow(256, 3 - i)]), -1) }
  cidr_end   = { for k, c in local.cidrs : k => try(sum([for i, octet in split(".", cidrhost(c, -1)) : tonumber(octet) * pow(256, 3 - i)]), -1) }
}
resource "terraform_data" "network_contract" {
  lifecycle {
    precondition {
      condition     = var.vpc_mode == "create" ? (var.vpc_no == null && var.vpc_cidr != null && var.subnet_mode == "create" && length(var.access_control_group_no_list) == 0) : (var.vpc_cidr == null && (var.vpc_no != null || var.subnet_no != null))
      error_message = "Create VPC requires CIDR, new subnet and dedicated ACG; no existing VPC ID. Reuse requires VPC ID (or legacy subnet ID) and no VPC CIDR."
    }
    precondition {
      condition     = var.subnet_mode == "create" ? (var.subnet_no == null && var.subnet_cidr != null && var.zone != null) : (var.subnet_no != null && var.subnet_cidr == null)
      error_message = "Create subnet requires CIDR and zone, no subnet ID; reuse requires subnet ID, no subnet CIDR."
    }
    precondition {
      condition     = var.subnet_mode != "create" || (local.cidr_valid.vpc && local.cidr_valid.subnet && local.cidr_start.subnet >= local.cidr_start.vpc && local.cidr_end.subnet <= local.cidr_end.vpc)
      error_message = "Use canonical RFC1918 IPv4 /16 through /28 CIDRs; subnet must fit entirely inside VPC."
    }
    precondition {
      condition     = var.subnet_mode != "reuse" || try(data.ncloud_subnet.existing[0].vpc_no == local.vpc_no && data.ncloud_subnet.existing[0].usage_type == "GEN" && (var.zone == null || var.zone == data.ncloud_subnet.existing[0].zone), false)
      error_message = "Reused subnet must be GEN, belong to the selected VPC and match zone if provided."
    }
    precondition {
      condition     = !local.public_ip_enabled || local.subnet_type == "PUBLIC"
      error_message = "Public IP requires a PUBLIC subnet; set allocate_public_ip=false for PRIVATE."
    }
    precondition {
      condition     = length(var.access_control_group_no_list) == 0 || length(var.ssh_source_cidrs) == 0
      error_message = "ssh_source_cidrs only configures a dedicated new ACG; existing ACG rules are never modified."
    }
  }
}
resource "ncloud_vpc" "managed" {
  count           = var.vpc_mode == "create" ? 1 : 0
  name            = "${var.name}-vpc"
  ipv4_cidr_block = var.vpc_cidr
  lifecycle {
    prevent_destroy = true
  }
}
resource "ncloud_subnet" "managed" {
  count          = var.subnet_mode == "create" ? 1 : 0
  name           = "${var.name}-subnet"
  vpc_no         = local.vpc_no
  subnet         = var.subnet_cidr
  zone           = var.zone
  network_acl_no = local.network_acl_no
  subnet_type    = var.subnet_type
  usage_type     = "GEN"
  lifecycle {
    prevent_destroy = true
  }
}
data "ncloud_access_control_group" "existing" {
  for_each = toset(var.access_control_group_no_list)
  id       = each.value
  lifecycle {
    postcondition {
      condition     = self.vpc_no == local.vpc_no
      error_message = "Existing ACG must belong to selected VPC."
    }
  }
}
resource "ncloud_access_control_group" "managed" {
  count  = length(var.access_control_group_no_list) == 0 ? 1 : 0
  name   = "${var.name}-acg"
  vpc_no = local.vpc_no
  lifecycle {
    prevent_destroy = true
  }
}
resource "ncloud_access_control_group_rule" "managed" {
  count                   = length(var.access_control_group_no_list) == 0 ? 1 : 0
  access_control_group_no = ncloud_access_control_group.managed[0].id
  inbound = [for cidr in var.ssh_source_cidrs : {
    protocol = "TCP", ip_block = cidr, port_range = "22", description = "Operator SSH", source_access_control_group_no = null
  }]
  outbound = [for rule in [{ protocol = "TCP", port = "80" }, { protocol = "TCP", port = "443" }, { protocol = "TCP", port = "53" }, { protocol = "UDP", port = "53" }, { protocol = "UDP", port = "123" }] : {
    protocol = rule.protocol, ip_block = "0.0.0.0/0", port_range = rule.port, description = "Bootstrap egress", source_access_control_group_no = null
  }]
}
