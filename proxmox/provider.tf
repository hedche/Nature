terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # bpg is pre-1.0; pin tightly — minor releases occasionally change schema.
      version = "~> 0.84"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true # PVE ships a self-signed cert; required or init/plan fail with x509 errors

  # SSH is only used for operations the API can't do over the token alone
  # (e.g. uploading cloud-init snippets). Not needed for the simple
  # initialization-block path, but configured so snippet-based user_data works later.
  ssh {
    agent    = true
    username = "root"
  }
}
