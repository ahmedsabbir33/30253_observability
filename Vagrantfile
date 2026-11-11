# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Primary Ubuntu 26.04 box (fallback: "bento/ubuntu-24.04" if needed)
  config.vm.box = "bento/ubuntu-26.04"
  config.vm.hostname = "ubuntu-observability"

  # Dedicated Host-Only private IP (used by MicroK8s Alloy -> Docker Compose Loki and host browser)
  config.vm.network "private_network", ip: "192.168.56.10"

  # Localhost-only port forwarding to host browser (enforces Task 02 endpoint privacy)
  config.vm.network "forwarded_port", guest: 3000, host: 3000, host_ip: "127.0.0.1", id: "grafana", auto_correct: true
  config.vm.network "forwarded_port", guest: 9090, host: 9090, host_ip: "127.0.0.1", id: "prometheus", auto_correct: true
  config.vm.network "forwarded_port", guest: 8000, host: 8000, host_ip: "127.0.0.1", id: "order-api", auto_correct: true
  config.vm.network "forwarded_port", guest: 3100, host: 3100, host_ip: "127.0.0.1", id: "loki", auto_correct: true
  config.vm.network "forwarded_port", guest: 8025, host: 8025, host_ip: "127.0.0.1", id: "mailpit", auto_correct: true

  # Sync the cloned Git repository root into /vagrant inside the VM
  config.vm.synced_folder ".", "/vagrant", disabled: false

  config.vm.provider "virtualbox" do |vb|
    vb.name = "30253-observability-vm"
    vb.memory = 6144
    vb.cpus = 4
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
  end

  config.vm.provision "shell", inline: <<-SHELL
    set -e
    export DEBIAN_FRONTEND=noninteractive

    echo "=== [1/5] Installing base utilities, Docker Engine & Docker Compose v2 ==="
    apt-get update -y
    apt-get install -y curl jq tree git zip rsync ca-certificates gnupg lsb-release docker.io docker-compose-v2
    systemctl enable --now docker
    usermod -aG docker vagrant

    echo "=== [2/5] Installing MicroK8s via Snap ==="
    if ! snap list microk8s >/dev/null 2>&1; then
      snap install microk8s --classic --channel=1.31/stable || snap install microk8s --classic
    fi
    usermod -aG microk8s vagrant
    mkdir -p /home/vagrant/.kube
    chown -R vagrant:vagrant /home/vagrant/.kube

    echo "=== [3/5] Enabling MicroK8s addons (dns, hostpath-storage, helm3) ==="
    microk8s status --wait-ready
    microk8s enable dns hostpath-storage helm3
    microk8s status --wait-ready

    echo "=== [4/5] Syncing repository from /vagrant to /home/vagrant/30253_observability ==="
    mkdir -p /home/vagrant/30253_observability
    rsync -a --exclude='.vagrant' --exclude='node_modules' --exclude='.git' /vagrant/ /home/vagrant/30253_observability/
    if [ ! -f /home/vagrant/30253_observability/.env ] && [ -f /home/vagrant/30253_observability/.env.example ]; then
      cp /home/vagrant/30253_observability/.env.example /home/vagrant/30253_observability/.env
    fi
    chmod +x /home/vagrant/30253_observability/scripts/*.sh || true
    chown -R vagrant:vagrant /home/vagrant/30253_observability

    echo "=== [5/5] Deploying Docker Compose + MicroK8s Observability Stack ==="
    if [ -f /home/vagrant/30253_observability/scripts/deploy-all.sh ]; then
      su - vagrant -c "cd /home/vagrant/30253_observability && ./scripts/deploy-all.sh"
    fi

    echo "=== Vagrant Provisioning & Stack Deployment Complete! ==="
  SHELL
end
