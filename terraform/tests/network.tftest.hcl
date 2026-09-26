mock_provider "ncloud" {
  mock_data "ncloud_vpc" {
    defaults = {
      id                     = "100"
      ipv4_cidr_block        = "10.20.0.0/16"
      default_network_acl_no = "300"
    }
  }
  mock_data "ncloud_subnet" {
    defaults = {
      id             = "200"
      vpc_no         = "100"
      subnet         = "10.20.1.0/24"
      zone           = "KR-2"
      subnet_type    = "PUBLIC"
      usage_type     = "GEN"
      network_acl_no = "300"
    }
  }
  mock_data "ncloud_access_control_group" {
    defaults = { vpc_no = "100" }
  }
}
variables {
  login_key_name      = "offline-test"
  server_image_number = "12345"
  server_spec_code    = "test-spec"
}
run "legacy_reuse" {
  command = plan
  variables {
    subnet_no                    = "200"
    access_control_group_no_list = ["400"]
  }
  assert {
    condition     = length(ncloud_vpc.managed) == 0 && length(ncloud_subnet.managed) == 0 && length(ncloud_access_control_group.managed) == 0 && length(ncloud_public_ip.openclaw) == 1
    error_message = "Legacy interface must reuse networking and retain public IP."
  }
  assert {
    condition     = ncloud_server.openclaw.subnet_no == "200" && ncloud_network_interface.primary.subnet_no == "200" && ncloud_network_interface.primary.access_control_groups == toset(["400"])
    error_message = "Server and primary NIC must use resolved subnet and ACG."
  }
}
run "existing_vpc_new_subnet" {
  command = plan
  variables {
    vpc_no      = "100"
    subnet_mode = "create"
    subnet_cidr = "10.20.2.0/24"
    zone        = "KR-2"
  }
  assert {
    condition     = length(ncloud_vpc.managed) == 0 && ncloud_subnet.managed[0].vpc_no == "100" && ncloud_subnet.managed[0].network_acl_no == "300" && length(ncloud_public_ip.openclaw) == 0
    error_message = "Reuse VPC/default ACL, create private subnet without public IP."
  }
}
run "new_vpc_new_subnet" {
  command = plan
  variables {
    vpc_mode    = "create"
    subnet_mode = "create"
    vpc_cidr    = "10.20.0.0/16"
    subnet_cidr = "10.20.1.0/24"
    zone        = "KR-2"
  }
  assert {
    condition     = length(ncloud_vpc.managed) == 1 && length(ncloud_subnet.managed) == 1 && length(ncloud_access_control_group.managed) == 1 && length(ncloud_access_control_group_rule.managed[0].inbound) == 0 && length(ncloud_public_ip.openclaw) == 0
    error_message = "Fresh default is private, dedicated ACG, no ingress/public IP."
  }
}

run "create_with_existing_vpc" {
  command = plan
  variables {
    vpc_mode    = "create"
    subnet_mode = "create"
    vpc_no      = "100"
    vpc_cidr    = "10.20.0.0/16"
    subnet_cidr = "10.20.1.0/24"
    zone        = "KR-2"
  }
  expect_failures = [terraform_data.network_contract]
}

run "create_vpc_reuse_subnet" {
  command = plan
  variables {
    vpc_mode  = "create"
    subnet_no = "200"
    vpc_cidr  = "10.20.0.0/16"
  }
  expect_failures = [terraform_data.network_contract]
}

run "subnet_outside_vpc" {
  command = plan
  variables {
    vpc_no      = "100"
    subnet_mode = "create"
    subnet_cidr = "10.21.0.0/24"
    zone        = "KR-2"
  }
  expect_failures = [terraform_data.network_contract]
}


run "public_cidr" {
  command = plan
  variables {
    vpc_mode    = "create"
    subnet_mode = "create"
    vpc_cidr    = "8.8.0.0/16"
    subnet_cidr = "8.8.1.0/24"
    zone        = "KR-2"
  }
  expect_failures = [terraform_data.network_contract]
}


run "private_public_ip" {
  command = plan
  variables {
    vpc_no             = "100"
    subnet_mode        = "create"
    subnet_cidr        = "10.20.1.0/24"
    zone               = "KR-2"
    allocate_public_ip = true
  }
  expect_failures = [terraform_data.network_contract]
}

run "zone_mismatch" {
  command = plan
  variables {
    subnet_no = "200"
    zone      = "KR-1"
  }
  expect_failures = [terraform_data.network_contract]
}

run "vpc_mismatch" {
  command = plan
  variables {
    subnet_no = "200"
    vpc_no    = "999"
  }
  expect_failures = [terraform_data.network_contract]
}

run "reuse_with_cidr" {
  command = plan
  variables {
    subnet_no   = "200"
    subnet_cidr = "10.20.1.0/24"
  }
  expect_failures = [terraform_data.network_contract]
}

run "missing_ids" {
  command = plan
  variables {
  }
  expect_failures = [terraform_data.network_contract]
}

run "world_ssh_rejected" {
  command = plan
  variables {
    subnet_no        = "200"
    ssh_source_cidrs = ["0.0.0.0/0"]
  }
  expect_failures = [var.ssh_source_cidrs]
}
run "acg_wrong_vpc" {
  command = plan
  variables {
    subnet_no                    = "200"
    access_control_group_no_list = ["400"]
  }
  override_data {
    target = data.ncloud_access_control_group.existing["400"]
    values = { vpc_no = "999" }
  }
  expect_failures = [data.ncloud_access_control_group.existing]
}
run "public_new_opt_in" {
  command = plan
  variables {
    vpc_mode           = "create"
    subnet_mode        = "create"
    vpc_cidr           = "10.20.0.0/16"
    subnet_cidr        = "10.20.1.0/24"
    zone               = "KR-2"
    subnet_type        = "PUBLIC"
    allocate_public_ip = true
    ssh_source_cidrs   = ["203.0.113.10/32"]
  }
  assert {
    condition     = length(ncloud_public_ip.openclaw) == 1 && alltrue([for rule in ncloud_access_control_group_rule.managed[0].inbound : rule.port_range == "22" && rule.ip_block == "203.0.113.10/32"])
    error_message = "Only explicit SSH source and public IP may be enabled."
  }
}
run "empty_id_rejected" {
  command = plan
  variables { subnet_no = "" }
  expect_failures = [var.subnet_no]
}
run "bad_mode" {
  command = plan
  variables {
    subnet_no = "200"
    vpc_mode  = "auto"
  }
  expect_failures = [var.vpc_mode]
}
