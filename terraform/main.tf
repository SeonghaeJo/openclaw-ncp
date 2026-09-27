resource "ncloud_network_interface" "primary" {
  depends_on            = [terraform_data.network_contract, data.ncloud_access_control_group.existing, ncloud_access_control_group_rule.managed]
  name                  = "${var.name}-nic"
  subnet_no             = local.subnet_no
  access_control_groups = local.acg_ids
}
data "ncloud_server_image_numbers" "ubuntu" {
  count = var.server_image_number == null ? 1 : 0
  filter {
    name   = "hypervisor_type"
    values = [var.hypervisor]
  }
  filter {
    name   = "os_type"
    values = ["UBUNTU"]
  }
  filter {
    name   = "cpu_architecture_type"
    regex  = true
    values = ["(?i)x86_64"]
  }
}

data "ncloud_server_specs" "compatible" {
  count = var.server_spec_code == null ? 1 : 0
  filter {
    name   = "hypervisor_type"
    values = [var.hypervisor]
  }
  filter {
    name   = "cpu_architecture_type"
    values = ["x86_64"]
  }
}

locals {
  discovered_image_numbers = var.server_image_number == null ? data.ncloud_server_image_numbers.ubuntu[0].image_number_list : []
  release_images           = [for image in local.discovered_image_numbers : image if var.ubuntu_release != null && can(regex("(?i).*ubuntu.*${replace(var.ubuntu_release, ".", "\\.")}.*", "${image.name} ${image.description}"))]
  # Release is selected semantically by the wrapper from provider metadata;
  # image number is only a deterministic tie-breaker within that release.
  selected_image_number = var.server_image_number != null ? var.server_image_number : try(tostring(max([for image in local.release_images : tonumber(image.server_image_number)])), null)
  selected_image        = try([for image in local.release_images : image if image.server_image_number == local.selected_image_number][0], null)
  compatible_specs      = var.server_spec_code == null ? [for spec in data.ncloud_server_specs.compatible[0].server_spec_list : spec if try(tonumber(spec.memory_size), 0) >= var.server_spec_min_memory_gb] : []
  selected_spec_code    = var.server_spec_code != null ? var.server_spec_code : try(sort([for spec in local.compatible_specs : spec.server_spec_code])[0], null)
  selected_spec         = try([for spec in local.compatible_specs : spec if spec.server_spec_code == local.selected_spec_code][0], null)
}

resource "ncloud_server" "openclaw" {
  subnet_no                 = local.subnet_no
  name                      = var.name
  server_image_number       = local.selected_image_number
  server_spec_code          = local.selected_spec_code
  zone                      = local.zone
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
        (local.selected_image_number != null && local.selected_spec_code != null && var.server_image_product_code == null && var.server_product_code == null) ||
        (var.hypervisor != "KVM" && var.server_image_number == null && var.server_spec_code == null && var.server_image_product_code != null && var.server_product_code != null)
      )
      error_message = "Choose an explicit image_number/spec pair (all hypervisors) OR product-code pair (XEN/RHV only); never mix. Verify the selected image's hypervisor in NCP."
    }
    precondition {
      condition     = var.server_image_number != null || var.ubuntu_release != null
      error_message = "An explicit Ubuntu LTS release is required when server_image_number is omitted; the lifecycle wrapper resolves it from live NCP metadata."
    }
    precondition {
      condition     = var.server_image_number != null || length(local.release_images) > 0
      error_message = "NCP returned no Ubuntu LTS image matching the requested release, hypervisor and x86_64 architecture. Override server_image_number after reviewing the live API result."
    }
    precondition {
      condition     = var.server_spec_code != null || length(local.compatible_specs) > 0
      error_message = "NCP returned no compatible x86_64 spec with the requested minimum memory. Override server_spec_code after reviewing the live API result."
    }
    precondition {
      condition     = var.server_image_number != null || try(local.selected_image.hypervisor_type == var.hypervisor && can(regex("(?i)x86_64", local.selected_image.cpu_architecture_type)), false)
      error_message = "The selected Ubuntu image is not compatible with the requested hypervisor/x86_64 architecture."
    }
    precondition {
      condition     = var.server_spec_code != null || try(local.selected_spec.hypervisor_type == var.hypervisor && can(regex("(?i)x86_64", local.selected_spec.cpu_architecture_type)), false)
      error_message = "The selected server spec is not compatible with the requested hypervisor/x86_64 architecture."
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
