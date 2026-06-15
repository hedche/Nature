output "control_plane_public_ip" {
  description = "Public IP address of the K3s control plane"
  value       = oci_core_instance.k3s_control_plane.public_ip
}

output "control_plane_private_ip" {
  description = "Private IP address of the K3s control plane"
  value       = oci_core_instance.k3s_control_plane.private_ip
}

output "worker_public_ip" {
  description = "Public IP address of the K3s worker node"
  value       = oci_core_instance.k3s_worker.public_ip
}

output "worker_private_ip" {
  description = "Private IP address of the K3s worker node"
  value       = oci_core_instance.k3s_worker.private_ip
}

output "ssh_to_control_plane" {
  description = "SSH command to connect to control plane"
  value       = "ssh opc@${oci_core_instance.k3s_control_plane.public_ip}"
}

output "ssh_to_worker" {
  description = "SSH command to connect to worker"
  value       = "ssh opc@${oci_core_instance.k3s_worker.public_ip}"
}

output "get_kubeconfig" {
  description = "Command to retrieve kubeconfig from control plane"
  value       = "ssh opc@${oci_core_instance.k3s_control_plane.public_ip} 'sudo cat /etc/rancher/k3s/k3s.yaml'"
}

output "check_k3s_status" {
  description = "Command to check K3s service status on control plane"
  value       = "ssh opc@${oci_core_instance.k3s_control_plane.public_ip} 'sudo systemctl status k3s'"
}

output "get_nodes" {
  description = "Command to get cluster nodes"
  value       = "ssh opc@${oci_core_instance.k3s_control_plane.public_ip} 'sudo /usr/local/bin/kubectl get nodes'"
}

output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT

    Deployment complete! Here are your next steps:

    1. Wait 2-3 minutes for K3s installation to complete on both nodes

    2. Check K3s status on control plane:
       ssh opc@${oci_core_instance.k3s_control_plane.public_ip} 'sudo systemctl status k3s'

    3. Verify both nodes are ready:
       ssh opc@${oci_core_instance.k3s_control_plane.public_ip} 'sudo /usr/local/bin/kubectl get nodes'

    4. Get your kubeconfig:
       ssh opc@${oci_core_instance.k3s_control_plane.public_ip} 'sudo cat /etc/rancher/k3s/k3s.yaml' > kubeconfig.yaml

       Then edit kubeconfig.yaml and replace '127.0.0.1' with '${oci_core_instance.k3s_control_plane.public_ip}'

    5. Use kubectl with your cluster:
       export KUBECONFIG=./kubeconfig.yaml
       kubectl get nodes
       kubectl get pods -A

    6. Deploy a test application:
       kubectl create deployment nginx --image=nginx
       kubectl expose deployment nginx --port=80 --type=NodePort

    For troubleshooting, check cloud-init logs:
       ssh opc@${oci_core_instance.k3s_control_plane.public_ip} 'sudo cat /var/log/cloud-init-output.log'
  EOT
}
