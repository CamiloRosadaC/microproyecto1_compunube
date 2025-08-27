# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  BOX              = "bento/ubuntu-22.04"
  NET              = "192.168.100"
  CONSUL_SERVER_IP = "#{NET}.2"
  SERVICE_NAME     = "web"
  REPLICAS         = 2
  PORTS            = "3000,3001"  # usa 2 puertos (réplicas) por VM web

  config.vm.box = BOX
  config.vm.boot_timeout = 600

  config.vm.provider "virtualbox" do |vb|
    vb.gui = false
    vb.check_guest_additions = false
  end

  # ---------- haproxy (Consul server + HAProxy) ----------
config.vm.define "haproxy" do |node|
  node.vm.hostname = "haproxy"
  node.vm.network "private_network", ip: "#{NET}.2"

  # Carpeta sincronizada para reportes y planes de Artillery
  node.vm.synced_folder "./tests", "/home/vagrant/tests", create: true

  node.vm.provision "shell", path: "scripts/common.sh"

  # ¡Debe existir y ser ejecutable!
  node.vm.provision "shell", path: "scripts/artillery_setup.sh"

  node.vm.provision "shell",
    path: "scripts/haproxy.sh",
    env: {
      "CONSUL_SERVER_IP" => CONSUL_SERVER_IP,
      "SERVICE_NAME"     => SERVICE_NAME,
      "PORTS"            => PORTS,
      "DISCOVERY_MODE"   => "consul"
    }

  end

# ---------- web nodes (Node + Consul client) ----------
  ["web1", "web2"].each_with_index do |name, idx|
    config.vm.define name do |node|
      node.vm.hostname = name
      node.vm.network "private_network", ip: "#{NET}.#{3 + idx}"

      node.vm.provider "virtualbox" do |vb|
        vb.name   = name
        vb.memory = 1024
        vb.cpus   = 1
      end

      node.vm.provision "shell", path: "scripts/common.sh"
      node.vm.provision "shell",
        path: "scripts/web.sh",
        env: {
          "CONSUL_SERVER_IP" => CONSUL_SERVER_IP,
          "SERVICE_NAME"     => SERVICE_NAME,
          "REPLICAS"         => REPLICAS.to_s,
          "PORTS"            => PORTS,
          # Opcional: si tu app expone /health en otra ruta
          # "HEALTH_PATH"    => "/health"
        }
    end
  end
end



