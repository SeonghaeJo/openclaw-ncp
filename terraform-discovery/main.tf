data "ncloud_vpcs" "all" {}
data "ncloud_subnets" "all" {
  usage_type = "GEN"
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
