# Download the Debian 12 cloud image once into the image datastore. PVE 9.x uses
# the 'import' content type as the home for VM-importable disk images; `local`
# already has it enabled. overwrite = false keeps subsequent applies fast.
resource "proxmox_download_file" "debian12_cloud" {
  content_type = "import"
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node

  url       = var.cloud_image_url
  file_name = var.cloud_image_filename
  overwrite = false
}

# Merge each VM's per-entry overrides with vm_defaults.
locals {
  vms = {
    for name, v in var.vms : name => {
      vmid      = v.vmid
      ip        = v.ip_address
      gateway   = v.gateway
      cores     = coalesce(v.cores, var.vm_defaults.cores)
      memory_mb = coalesce(v.memory_mb, var.vm_defaults.memory_mb)
      disk_gb   = coalesce(v.disk_gb, var.vm_defaults.disk_gb)
      username  = coalesce(v.username, var.vm_defaults.username)
      tags      = v.tags
      data_disk_path = v.data_disk_path
    }
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.vms

  name      = each.key
  vm_id     = each.value.vmid
  node_name = var.proxmox_node
  tags      = each.value.tags

  cpu {
    cores = each.value.cores
    type  = "host" # i5-5250U has VT-x; host CPU type gives best perf for Linux guests
  }

  memory {
    dedicated = each.value.memory_mb
  }

  # The Debian genericcloud image does not run qemu-guest-agent by default;
  # enabling this makes apply wait forever for the agent. Leave disabled unless
  # you install/enable the agent via custom cloud-init user_data (needs snippets).
  agent {
    enabled = false
  }

  scsi_hardware = "virtio-scsi-single"

  # Boot disk imported from the downloaded cloud image, placed on local-lvm and
  # grown to disk_gb.
  disk {
    datastore_id = var.vm_disk_datastore
    import_from  = proxmox_download_file.debian12_cloud.id
    interface    = "scsi0"
    size         = each.value.disk_gb
    discard      = "on"
    ssd          = true
  }

  # Optional whole-disk passthrough (e.g. the USB 1TB HDD on pve). Empty
  # datastore_id + absolute path_in_datastore is the bpg provider's passthrough
  # form. Excluded from backups; a physical disk can't be snapshotted anyway.
  dynamic "disk" {
    for_each = each.value.data_disk_path != null ? [each.value.data_disk_path] : []
    content {
      datastore_id      = ""
      path_in_datastore = disk.value
      interface         = "scsi1"
      backup            = false
    }
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  serial_device {} # cloud images expect a serial console

  # Cloud-init via the bpg initialization block — covers user/keys/IP/DNS
  # without needing a snippets datastore.
  initialization {
    datastore_id = var.vm_disk_datastore

    user_account {
      username = each.value.username
      keys     = [trimspace(var.ssh_public_key)]
    }

    dns {
      servers = var.dns_servers
      domain  = var.dns_domain
    }

    ip_config {
      ipv4 {
        address = each.value.ip != null ? each.value.ip : "dhcp"
        gateway = each.value.ip != null ? each.value.gateway : null
      }
    }
  }
}
