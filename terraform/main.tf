resource "ncloud_network_interface" "primary" {
  depends_on            = [terraform_data.network_contract, data.ncloud_access_control_group.existing, ncloud_access_control_group_rule.managed]
  name                  = "${var.name}-nic"
  subnet_no             = local.subnet_no
  access_control_groups = local.acg_ids
}
resource "ncloud_server" "openclaw" {
  subnet_no                 = local.subnet_no
  name                      = var.name
  server_image_number       = var.server_image_number
  server_spec_code          = var.server_spec_code
  server_image_product_code = var.server_image_product_code
  server_product_code       = var.server_product_code
  login_key_name            = var.login_key_name
  network_interface {
    network_interface_no = ncloud_network_interface.primary.id
    order                = 0
  }
  lifecycle {
    precondition {
      condition = (
        (var.server_image_number != null && var.server_spec_code != null && var.server_image_product_code == null && var.server_product_code == null) ||
        (var.hypervisor != "KVM" && var.server_image_number == null && var.server_spec_code == null && var.server_image_product_code != null && var.server_product_code != null)
      )
      error_message = "Choose an explicit image_number/spec pair (all hypervisors) OR product-code pair (XEN/RHV only); never mix. Verify the selected image's hypervisor in NCP."
    }
  }
}
moved {
  from = ncloud_public_ip.openclaw
  to   = ncloud_public_ip.openclaw[0]
}
resource "ncloud_public_ip" "openclaw" {
  count              = local.public_ip_enabled ? 1 : 0
  server_instance_no = ncloud_server.openclaw.id
  description        = "OpenClaw bootstrap SSH"
}
