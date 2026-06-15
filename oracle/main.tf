# Generate a random token for K3s cluster
resource "random_password" "k3s_token" {
  length  = 64
  special = false
}

# Data source to get the list of availability domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Data source to get Oracle Linux 8 ARM image
data "oci_core_images" "oracle_linux_arm" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Virtual Cloud Network
resource "oci_core_vcn" "k3s_vcn" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "k3s-vcn"
  dns_label      = "k3svcn"
}

# Internet Gateway
resource "oci_core_internet_gateway" "k3s_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.k3s_vcn.id
  display_name   = "k3s-internet-gateway"
  enabled        = true
}

# Route Table
resource "oci_core_route_table" "k3s_route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.k3s_vcn.id
  display_name   = "k3s-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.k3s_igw.id
  }
}

# Security List
resource "oci_core_security_list" "k3s_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.k3s_vcn.id
  display_name   = "k3s-security-list"

  # Egress - Allow all outbound traffic
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  # Ingress - SSH
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    stateless   = false
    description = "SSH"

    tcp_options {
      min = 22
      max = 22
    }
  }

  # Ingress - Kubernetes API Server
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    stateless   = false
    description = "Kubernetes API"

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # Ingress - HTTP
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    stateless   = false
    description = "HTTP"

    tcp_options {
      min = 80
      max = 80
    }
  }

  # Ingress - HTTPS
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    stateless   = false
    description = "HTTPS"

    tcp_options {
      min = 443
      max = 443
    }
  }

  # Ingress - NodePort Services
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    stateless   = false
    description = "NodePort Services"

    tcp_options {
      min = 30000
      max = 32767
    }
  }

  # Ingress - K3s VXLAN (for flannel overlay network)
  ingress_security_rules {
    protocol    = "17" # UDP
    source      = var.subnet_cidr
    stateless   = false
    description = "K3s VXLAN"

    udp_options {
      min = 8472
      max = 8472
    }
  }

  # Ingress - Kubelet API
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.subnet_cidr
    stateless   = false
    description = "Kubelet API"

    tcp_options {
      min = 10250
      max = 10250
    }
  }

  # Ingress - Allow all traffic within the subnet for K3s inter-node communication
  ingress_security_rules {
    protocol    = "all"
    source      = var.subnet_cidr
    stateless   = false
    description = "K3s inter-node communication"
  }
}

# Public Subnet
resource "oci_core_subnet" "k3s_subnet" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.k3s_vcn.id
  cidr_block        = var.subnet_cidr
  display_name      = "k3s-public-subnet"
  dns_label         = "k3spublic"
  route_table_id    = oci_core_route_table.k3s_route_table.id
  security_list_ids = [oci_core_security_list.k3s_security_list.id]
}

# Control Plane Instance
resource "oci_core_instance" "k3s_control_plane" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain - 1].name
  compartment_id      = var.compartment_ocid
  display_name        = "k3s-control-plane"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.control_plane_ocpus
    memory_in_gbs = var.control_plane_memory_gb
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux_arm.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.k3s_subnet.id
    assign_public_ip = true
    display_name     = "k3s-control-plane-vnic"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init/k3s-server.yaml.tpl", {
      k3s_token = random_password.k3s_token.result
    }))
  }
}

# Worker Instance
resource "oci_core_instance" "k3s_worker" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain - 1].name
  compartment_id      = var.compartment_ocid
  display_name        = "k3s-worker"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.worker_ocpus
    memory_in_gbs = var.worker_memory_gb
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux_arm.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.k3s_subnet.id
    assign_public_ip = true
    display_name     = "k3s-worker-vnic"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init/k3s-agent.yaml.tpl", {
      k3s_url       = "https://${oci_core_instance.k3s_control_plane.private_ip}:6443"
      k3s_server_ip = oci_core_instance.k3s_control_plane.private_ip
      k3s_token     = random_password.k3s_token.result
    }))
  }

  depends_on = [oci_core_instance.k3s_control_plane]
}
