output "server_instance_no" {
  value = ncloud_server.openclaw.id
}
output "public_ip" {
  value = ncloud_public_ip.openclaw.public_ip
}
