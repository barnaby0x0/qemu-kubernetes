variable "dns_servers" {
  type = list(string)
  default = ["8.8.8.8", "1.1.1.1"]
}

variable "kubernetes_version" {
  type = string
  default = "1.32.0-*"
}

variable "kubernetes_version_short" {
  type = string
  default = "1.32"
}

variable "calico_version" {
  type = string
  default = "3.29.3"
}

variable "k9s_version" {
  type = string
  default = "v0.50.6"
}

variable "helm_version" {
  type = string
  default = "v3.17.3"
}

variable "control_ip" {
  type = string
  default = "1.32"
}

variable "pod_cidr" {
  type = string
  default = "1.32"
}

variable "service_cidr" {
  type = string
  default = "1.32"
}

variable "etcd_version" {
  type = string
  default = "3.6.0"
}

source "vagrant" "k8s" {
  communicator = "ssh"
  source_path = "generic/debian12"
  provider = "libvirt"
  add_force = true
}

build {
  sources = ["source.vagrant.k8s"]
  
  provisioner "shell" {
    script = "./scripts/common.sh"
    environment_vars = [
      "DNS_SERVERS=${join(" ", var.dns_servers)}",
      "KUBERNETES_VERSION=${var.kubernetes_version}",
      "KUBERNETES_VERSION_SHORT=${var.kubernetes_version_short}",
      "ETCD_VERSION=${var.etcd_version}"
    ]
  }

}
