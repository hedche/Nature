output "vms" {
  description = "Created VMs with id and configured IP"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm : name => {
      vmid      = vm.vm_id
      ip_config = try(vm.initialization[0].ip_config[0].ipv4[0].address, "dhcp")
      # Live IPs reported by the guest agent — null unless agent { enabled = true }
      # and qemu-guest-agent is running in the guest.
      agent_ips = try(vm.ipv4_addresses, null)
    }
  }
}

output "ssh_commands" {
  description = "SSH command per VM (static-IP VMs only)"
  value = {
    for name, v in local.vms : name => (
      v.ip != null
      ? "ssh ${v.username}@${split("/", v.ip)[0]}"
      : "DHCP — find IP via the router's DHCP leases or 'ssh pve qm guest cmd ${v.vmid} network-get-interfaces'"
    )
  }
}
