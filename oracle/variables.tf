variable "tenancy_ocid" {
  description = "The OCID of your tenancy"
  type        = string
}

variable "user_ocid" {
  description = "The OCID of the user"
  type        = string
}

variable "fingerprint" {
  description = "The fingerprint of the API key"
  type        = string
}

variable "private_key_path" {
  description = "The path to the private key file"
  type        = string
}

variable "region" {
  description = "The OCI region"
  type        = string
  default     = "us-ashburn-1"
}

variable "compartment_ocid" {
  description = "The OCID of the compartment"
  type        = string
}

variable "ssh_public_key" {
  description = "The SSH public key for accessing instances"
  type        = string
}

variable "availability_domain" {
  description = "The availability domain number (1, 2, or 3)"
  type        = number
  default     = 1
}

variable "vcn_cidr" {
  description = "CIDR block for the VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "control_plane_ocpus" {
  description = "Number of OCPUs for control plane instance"
  type        = number
  default     = 1
}

variable "control_plane_memory_gb" {
  description = "Memory in GB for control plane instance"
  type        = number
  default     = 6
}

variable "worker_ocpus" {
  description = "Number of OCPUs for worker instance"
  type        = number
  default     = 3
}

variable "worker_memory_gb" {
  description = "Memory in GB for worker instance"
  type        = number
  default     = 18
}

variable "shape_name" {
  description = "The shape name to check for availability (used by retry script)"
  type        = string
  default     = "VM.Standard.A1.Flex"
}
