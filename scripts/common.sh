#!/usr/bin/env bash
set -euxo pipefail

get_latest_release() {
  curl --silent "https://api.github.com/repos/$1/$2/releases/latest" \
    | grep '"tag_name":' \
    | sed -E 's/.*"([^"]+)".*/\1/'
}

# System upgrade
sudo apt-get update && apt-get upgrade -y
sudo apt-get install -y curl net-tools vim


## DNS Setting
if [ ! -d /etc/systemd/resolved.conf.d ]; then
	sudo mkdir /etc/systemd/resolved.conf.d/
fi
cat <<EOF | sudo tee /etc/systemd/resolved.conf.d/dns_servers.conf
[Resolve]
DNS=${DNS_SERVERS}
EOF

sudo systemctl restart systemd-resolved

## CONFIGURATION
# Turn off swap
sudo swapoff -a
# Disable swap completely
sudo sed -i -e '/swap/d' /etc/fstab

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe -a overlay br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system


## CONTAINERD

## Add Docker's official GPG key:
#sudo apt-get update
#sudo apt-get install -y ca-certificates curl
#sudo install -m 0755 -d /etc/apt/keyrings
#sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
#sudo chmod a+r /etc/apt/keyrings/docker.asc
#
## Add the repository to Apt sources:
#echo \
#  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
#  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
#  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
#sudo apt-get update
#sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
#
#sudo sh -c 'cat << EOF >  /etc/containerd/config.toml
#version = 2
#[plugins]
#  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
#    runtime_type = "io.containerd.runc.v2"
#    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
#      SystemdCgroup = true
#EOF'
#sudo systemctl restart containerd


# variables used to compose URLS (avoid vertical scrollbars)
CONTAINERD_VER=$(get_latest_release containerd containerd) # v1.7.17
PKG_ARCH="$(dpkg --print-architecture)"
CONTAINERD_PKG="containerd-${CONTAINERD_VER#v}-linux-$PKG_ARCH.tar.gz"
CONTAINERD_URL_PATH="releases/download/$CONTAINERD_VER/$CONTAINERD_PKG"
CONTAINERD_URL="https://github.com/containerd/containerd/$CONTAINERD_URL_PATH"
# download package
curl -fLo "$CONTAINERD_PKG" "$CONTAINERD_URL"
# Extract the binaries
sudo tar Cxzvf /usr/local "$CONTAINERD_PKG"
sudo mkdir -p /etc/containerd/
sudo sh -c 'cat << EOF >  /etc/containerd/config.toml
version = 2
[plugins]
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
    runtime_type = "io.containerd.runc.v2"
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
      SystemdCgroup = true
EOF'

sudo sh -c 'cat << EOF > /etc/systemd/system/containerd.service
# Copyright The containerd Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd

Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5

# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity

# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF'

cat > /etc/crictl.yaml << EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now containerd


## RUNC
RUNC_VER=$(get_latest_release opencontainers runc) # v1.1.12
PKG_ARCH="$(dpkg --print-architecture)"
RUNC_URL_PATH="releases/download/$RUNC_VER/runc.$PKG_ARCH"
RUNC_URL="https://github.com/opencontainers/runc/$RUNC_URL_PATH"

# download
curl -fSLo runc."$PKG_ARCH" "$RUNC_URL"

# install
# shellcheck disable=SC2086
sudo install -m 755 runc.$PKG_ARCH /usr/local/sbin/runc


## CNI PLUGINS
## CNI plugins
get_latest_release() {
  curl --silent "https://api.github.com/repos/$1/$2/releases/latest" \
    | grep '"tag_name":' \
    | sed -E 's/.*"([^"]+)".*/\1/'
}

CNI_VERS=$(get_latest_release containernetworking plugins) # v1.5.0
PKG_ARCH="$(dpkg --print-architecture)"
CNI_PKG="cni-plugins-linux-$PKG_ARCH-$CNI_VERS.tgz"
CNI_URL_PATH="releases/download/$CNI_VERS/$CNI_PKG"
CNI_URL="https://github.com/containernetworking/plugins/$CNI_URL_PATH"

# download
curl -fLo "$CNI_PKG" "$CNI_URL"

# install
sudo mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin "$CNI_PKG"


## KUBEADM
# Install prerequisite packages
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Determine version of Kubernetes (instructions may vary)
# This is tested with v1.30.
K8S_VERS="v1.30"

# variables to make code readible
K8S_GPG_KEY_PATH="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
K8S_APT_REPO_URI="https://pkgs.k8s.io/core:/stable:/$K8S_VERS/deb/"

# Download signing key
[[ -d /etc/apt/keyrings ]]  || sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/$K8S_VERS/deb/Release.key \
 | sudo gpg --no-tty --batch --yes --dearmor -o $K8S_GPG_KEY_PATH


# Add the appropriate Kubernetes apt repository

echo "deb [signed-by=$K8S_GPG_KEY_PATH] $K8S_APT_REPO_URI /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update the apt package index, install kubelet, kubeadm and kubectl, and pin their version
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Enable the kubelet service before running kubeadm (optional)
sudo systemctl enable --now kubelet

# Enable resolvconf service
sudo systemctl enable --now systemd-resolved

cat << EOF | tee -a /home/vagrant/.bashrc
alias k='kubectl '
EOF

#sudo apt-get update -y
#sudo apt-get install -y jq
#local_ip="$(ip --json a s | jq -r '.[] | if .ifname == "eth1" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"
#cat > /etc/default/kubelet << EOF
#KUBELET_EXTRA_ARGS=--node-ip=$local_ip
#${ENVIRONMENT}
#EOF
