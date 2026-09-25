terraform {
  required_version = ">= 1.6.0"

  required_providers {
    ncloud = {
      source  = "NaverCloudPlatform/ncloud"
      version = "= 4.0.7"
    }
  }
}

provider "ncloud" {
  region      = var.region
  site        = var.site
  support_vpc = true
}
