#cloud-config

# K3s Control Plane Installation Script
# This cloud-init script automatically installs and configures K3s server

package_update: true
package_upgrade: true

packages:
  - curl
  - vim
  - git

runcmd:
  # Disable firewalld to avoid conflicts with K3s
  - systemctl disable firewalld
  - systemctl stop firewalld

  # Set SELinux to permissive mode for K3s
  - setenforce 0
  - sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

  # Install K3s server with pre-shared token
  - |
    public_ip=$(curl -4fsS --retry 5 --retry-delay 2 https://api.ipify.org || true)
    k3s_args="server --write-kubeconfig-mode 644 --node-name k3s-control-plane"
    if [ -n "$public_ip" ]; then
      k3s_args="$k3s_args --tls-san $public_ip"
    fi
    curl -sfL https://get.k3s.io | K3S_TOKEN="${k3s_token}" sh -s - $k3s_args

  # Wait for K3s to be ready
  - |
    echo "Waiting for K3s to be ready..."
    until /usr/local/bin/kubectl get nodes &> /dev/null; do
      echo "K3s not ready yet, waiting..."
      sleep 5
    done
    echo "K3s control plane is ready!"

  # Display K3s status
  - systemctl status k3s --no-pager

  # Show initial cluster info
  - /usr/local/bin/kubectl get nodes
  - /usr/local/bin/kubectl get pods -A

write_files:
  - path: /etc/sysctl.d/k3s.conf
    content: |
      net.bridge.bridge-nf-call-iptables = 1
      net.ipv4.ip_forward = 1
      net.bridge.bridge-nf-call-ip6tables = 1

  - path: /etc/profile.d/k3s.sh
    content: |
      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
      alias k=kubectl

final_message: "K3s control plane installation complete! System ready after $UPTIME seconds"
