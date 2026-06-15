#cloud-config

# K3s Worker Node Installation Script
# This cloud-init script automatically installs and configures K3s agent

package_update: true
package_upgrade: true

packages:
  - curl
  - vim
  - git

# Oracle Linux 8 boots with cgroup v1, but the K3s kubelet (v1.34+) refuses to
# run on cgroup v1. Switch to the unified (v2) hierarchy on the very first boot
# and reboot before cloud-init reaches the K3s install below. bootcmd runs on
# every boot; the guard makes it a no-op once v2 is active.
bootcmd:
  - |
    if [ ! -f /sys/fs/cgroup/cgroup.controllers ]; then
      grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=1"
      reboot
    fi

runcmd:
  # Grow the root filesystem to fill the full boot volume. Oracle Linux images
  # do not auto-expand past the image default, so without this the extra space
  # on a larger boot_volume_size_in_gbs would be stranded.
  - /usr/libexec/oci-growfs -y

  # Disable firewalld to avoid conflicts with K3s
  - systemctl disable firewalld
  - systemctl stop firewalld

  # Set SELinux to permissive mode for K3s
  - setenforce 0
  - sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

  # Wait for K3s server to be ready (retry up to 10 minutes)
  - |
    echo "Waiting for K3s control plane to be ready at ${k3s_server_ip}:6443..."
    max_attempts=60
    attempt=0
    until curl -k -s https://${k3s_server_ip}:6443/ping &> /dev/null; do
      attempt=$((attempt + 1))
      if [ $attempt -ge $max_attempts ]; then
        echo "ERROR: K3s control plane did not become ready in time"
        exit 1
      fi
      echo "Attempt $attempt/$max_attempts: Control plane not ready yet, waiting 10 seconds..."
      sleep 10
    done
    echo "K3s control plane is ready!"

  # Install K3s agent with pre-shared token
  - |
    curl -sfL https://get.k3s.io | K3S_URL="${k3s_url}" K3S_TOKEN="${k3s_token}" sh -s - agent \
      --node-name k3s-worker

  # Wait for K3s agent to be ready
  - |
    echo "Waiting for K3s agent to start..."
    until systemctl is-active --quiet k3s-agent; do
      echo "K3s agent not active yet, waiting..."
      sleep 5
    done
    echo "K3s agent is running!"

  # Display K3s agent status
  - systemctl status k3s-agent --no-pager

write_files:
  - path: /etc/sysctl.d/k3s.conf
    content: |
      net.bridge.bridge-nf-call-iptables = 1
      net.ipv4.ip_forward = 1
      net.bridge.bridge-nf-call-ip6tables = 1

final_message: "K3s worker node installation complete! System ready after $UPTIME seconds"
