variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint URL"
  type        = string
  default     = "https://10.30.1.55:8006/"
}

variable "proxmox_api_token" {
  description = "Proxmox API token in the form USER@REALM!TOKENID=UUID (see README for how to create it)"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Target Proxmox node name"
  type        = string
  default     = "pve"
}

variable "network_bridge" {
  description = "Bridge for VM NICs"
  type        = string
  default     = "vmbr0"
}

variable "vm_disk_datastore" {
  description = "Datastore for VM disks and the cloud-init drive (lvmthin)"
  type        = string
  default     = "local-lvm"
}

variable "image_datastore" {
  description = "Datastore that holds downloaded cloud images (must allow the 'import' content type)"
  type        = string
  default     = "local"
}

variable "ssh_public_key" {
  description = "SSH public key injected into the cloud-init default user"
  type        = string
}

variable "cloud_image_url" {
  description = "URL of the Ubuntu 24.04 (noble) cloud image (qcow2 format, .img extension)"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "cloud_image_filename" {
  description = "Filename to store the downloaded image under (the 'import' content type requires a .qcow2/.raw/.vmdk extension; the Ubuntu .img is qcow2)"
  type        = string
  default     = "noble-server-cloudimg-amd64.qcow2"
}

variable "dns_servers" {
  description = "DNS servers for cloud-init"
  type        = list(string)
  default     = ["10.30.1.1", "1.1.1.1"]
}

variable "dns_domain" {
  description = "Search domain for cloud-init"
  type        = string
  default     = "local"
}

# Default specs applied to every VM unless overridden per-VM in the vms map.
# Node has 4 threads / 15 GB RAM / ~56 GB local-lvm — keep these modest.
variable "vm_defaults" {
  description = "Default specs for VMs"
  type = object({
    cores     = number
    memory_mb = number
    disk_gb   = number
    username  = string
  })
  default = {
    cores     = 1
    memory_mb = 1024
    disk_gb   = 10
    username  = "ubuntu"
  }
}

# The user adds/removes VMs by editing this map. Per-VM fields fall back to
# vm_defaults via coalesce() in main.tf. Omit ip_address for DHCP.
# VMs live in 10.30.1.56-.59 (the node itself is .55; .50-.53 are the k8s nodes).
# Map the VMID to 100 + last octet (e.g. .56 -> vmid 156) for a mnemonic.
variable "vms" {
  description = "Map of VMs to create, keyed by VM name"
  type = map(object({
    vmid       = number
    ip_address = optional(string) # CIDR e.g. "10.30.1.110/24"; omit => DHCP
    gateway    = optional(string, "10.30.1.1")
    cores      = optional(number)
    memory_mb  = optional(number)
    disk_gb    = optional(number)
    username   = optional(string)
    tags       = optional(list(string), [])
    # Absolute /dev/disk/by-id/... path on the node to pass a whole physical
    # disk through to the VM as scsi1. The guest sees it as a raw block device.
    data_disk_path = optional(string)
  }))
  default = {}
}
