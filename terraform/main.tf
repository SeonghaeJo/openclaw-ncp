resource "ncloud_server" "openclaw" {
  subnet_no                 = var.subnet_no
  name                      = var.name
  server_image_product_code = var.server_image_product_code
  server_product_code       = var.server_product_code
  login_key_name            = var.login_key_name
}

resource "ncloud_public_ip" "openclaw" {
  server_instance_no = ncloud_server.openclaw.id
  description        = "OpenClaw bootstrap SSH"
}
