data "ncloud_vpcs" "all" {}
data "ncloud_subnets" "all" {
  usage_type = "GEN"
}

data "ncloud_zones" "available" {}

data "ncloud_server_image_numbers" "images" {
  filter {
    name   = "hypervisor_type"
    values = ["KVM"]
  }
  filter {
    name   = "os_type"
    values = ["UBUNTU"]
  }
  filter {
    name   = "cpu_architecture_type"
    values = ["x86_64"]
  }
}

data "ncloud_server_specs" "specs" {
  filter {
    name   = "hypervisor_type"
    values = ["KVM"]
  }
  filter {
    name   = "cpu_architecture_type"
    values = ["x86_64"]
  }
}

output "vpcs" {
  value = [for v in data.ncloud_vpcs.all.vpcs : {
    id = v.vpc_no, name = v.name, cidr = v.ipv4_cidr_block
  }]
}

output "subnets" {
  value = [for s in data.ncloud_subnets.all.subnets : {
    id   = s.subnet_no, vpc_id = s.vpc_no, name = s.name, cidr = s.subnet,
    zone = s.zone, type = s.subnet_type, usage = s.usage_type
  }]
}

output "zones" {
  value = [for z in data.ncloud_zones.available.zones : {
    code = z.zone_code, name = z.zone_name, description = z.zone_description
  }]
}

output "images" {
  value = [for image in data.ncloud_server_image_numbers.images.image_number_list : {
    number       = image.server_image_number, name = image.name,
    description  = image.description, hypervisor = image.hypervisor_type,
    architecture = image.cpu_architecture_type, os = image.os_type
  }]
}

output "specs" {
  value = [for spec in data.ncloud_server_specs.specs.server_spec_list : {
    code         = spec.server_spec_code, hypervisor = spec.hypervisor_type,
    architecture = spec.cpu_architecture_type, memory = spec.memory_size,
    cpu          = spec.cpu_count, description = spec.description
  }]
}
