output "server_instance_no" {
  value = ncloud_server.openclaw.id
}
output "public_ip" {
  value = try(ncloud_public_ip.openclaw[0].public_ip, null)
}

output "vpc_no" { value = local.vpc_no }
output "subnet_no" { value = local.subnet_no }
output "zone" { value = local.zone }
output "network_acl_no" { value = local.network_acl_no }
output "access_control_group_no_list" { value = local.acg_ids }
output "subnet_type" { value = local.subnet_type }
