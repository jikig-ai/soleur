terraform {
  backend "s3" {
    bucket                      = "soleur-terraform-state"
    key                         = "web-platform/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
    use_lockfile                = false # R2 does not support S3 conditional writes
  }

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.6"
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cf_api_token
}

# Separate provider for zone-settings APIs (HSTS / security_header).
# The default cf_api_token lacks Zone Settings:Edit; rather than expanding
# its scope, this alias uses a narrow token that only grants Zone Settings
# on soleur.ai. See cloudflare-settings.tf and #2527.
provider "cloudflare" {
  alias     = "zone_settings"
  api_token = var.cf_api_token_zone_settings
}
