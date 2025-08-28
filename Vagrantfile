# -*- mode: ruby -*-
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-22.04"

  # ---------- VM: haproxy (también corre Consul server y DNS de Consul) ----------
  config.vm.define "haproxy" do |h|
    h.vm.hostname = "haproxy"
    h.vm.network "private_network", ip: "192.168.100.10"
    h.vm.network "forwarded_port", guest: 8500, host: 8500, auto_correct: true # UI Consul
    h.vm.network "forwarded_port", guest: 8080, host: 8080, auto_correct: true # HAProxy frontend
    h.vm.provider "virtualbox" do |vb| vb.memory = 1024; vb.cpus = 2; end
    h.vm.provision "shell", path: "provision/00-common.sh"
    h.vm.provision "shell", path: "provision/10-consul-install.sh"
    h.vm.provision "shell", path: "provision/20-consul-server.sh"
    h.vm.provision "shell", path: "provision/30-haproxy-install.sh"
    h.vm.provision "shell", path: "provision/31-haproxy-config.sh"
  end

  # ---------- VM: web1 ----------
  config.vm.define "web1" do |w|
    w.vm.hostname = "web1"
    w.vm.network "private_network", ip: "192.168.100.11"
    w.vm.provider "virtualbox" do |vb| vb.memory = 768; vb.cpus = 1; end
    w.vm.provision "shell", path: "provision/00-common.sh"
    w.vm.provision "shell", path: "provision/10-consul-install.sh"
    w.vm.provision "shell", path: "provision/21-consul-client.sh", args: ["192.168.100.10"]
    w.vm.provision "shell", path: "provision/40-node-install.sh"
    w.vm.provision "shell", path: "provision/41-node-service.sh", args: ["web1"]
  end

  # ---------- VM: web2 ----------
  config.vm.define "web2" do |w|
    w.vm.hostname = "web2"
    w.vm.network "private_network", ip: "192.168.100.12"
    w.vm.provider "virtualbox" do |vb| vb.memory = 768; vb.cpus = 1; end
    w.vm.provision "shell", path: "provision/00-common.sh"
    w.vm.provision "shell", path: "provision/10-consul-install.sh"
    w.vm.provision "shell", path: "provision/21-consul-client.sh", args: ["192.168.100.10"]
    w.vm.provision "shell", path: "provision/40-node-install.sh"
    w.vm.provision "shell", path: "provision/41-node-service.sh", args: ["web2"]
  end
end


