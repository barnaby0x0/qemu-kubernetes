require "yaml"
vagrant_root = File.dirname(File.expand_path(__FILE__))
settings = YAML.load_file "#{vagrant_root}/settings.yaml"

IP_SECTIONS = settings["network"]["control_ip"].match(/^([0-9.]+\.)([^.]+)$/)
# First 3 octets including the trailing dot:
IP_NW = IP_SECTIONS.captures[0]
# Last octet excluding all dots:
IP_START = Integer(IP_SECTIONS.captures[1])
NUM_WORKER_NODES = settings["nodes"]["workers"]["count"]

Vagrant.configure("2") do |config|
  #config.vm.provider :libvirt do |libvirt|
  #  libvirt.storage_pool_name = "local" # Don't forget to create the pool first via virsh
  #end

  config.vm.provision "shell", env: { "IP_NW" => IP_NW, "IP_START" => IP_START, "NUM_WORKER_NODES" => NUM_WORKER_NODES }, inline: <<-SHELL
    echo "$IP_NW$((IP_START)) controlplane" >> /etc/hosts
    for i in `seq 1 ${NUM_WORKER_NODES}`; do
      echo "$IP_NW$((IP_START+i)) node0${i}" >> /etc/hosts
    done
  SHELL

  config.vm.provision "shell",
    env: {
      "DNS_SERVERS" => settings["network"]["dns_servers"].join(" "),
      "ENVIRONMENT" => settings["environment"],
      "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
      "KUBERNETES_VERSION_SHORT" => settings["software"]["kubernetes"][0..3],
      "OS" => settings["software"]["os"]
    },
    path: "scripts/common.sh"

  config.ssh.insert_key = false

  config.vm.define "master" do |master|
    master.vm.box = settings["software"]["box"]
    master.vm.hostname = "master-node"
    master.vm.network "private_network", ip: settings["network"]["control_ip"]
    master.vm.network "forwarded_port", guest: 6443, host: 6443
    master.vm.provider "libvirt" do |libvirt|
      libvirt.memory = settings["nodes"]["control"]["memory"]
      libvirt.cpus = settings["nodes"]["control"]["cpu"]
    end

    master.vm.provision "shell",
      env: {
        "CALICO_VERSION" => settings["software"]["calico"],
        "CONTROL_IP" => settings["network"]["control_ip"],
        "POD_CIDR" => settings["network"]["pod_cidr"],
        "SERVICE_CIDR" => settings["network"]["service_cidr"]
      },
      path: "scripts/master.sh"
  end

  (1..NUM_WORKER_NODES).each do |i|
     config.vm.define "node0#{i}" do |node|
     node.vm.box = settings["software"]["box"]
     node.vm.hostname = "worker-node0#{i}"
     #node.vm.network "private_network", ip: "10.10.19.1#{i}"
     node.vm.network "private_network", ip: "#{IP_NW}#{i}"
     node.vm.provider "libvirt" do |libvirt|
       libvirt.memory = settings["nodes"]["workers"]["memory"]
       libvirt.cpus = settings["nodes"]["workers"]["cpu"]
     end
     node.vm.provision "shell", path: "scripts/node.sh"
    end
  end
end

