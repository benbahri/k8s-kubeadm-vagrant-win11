# =====================================================================
#  Vagrantfile — Cluster Kubernetes kubeadm multi-noeuds (formation KUB-ORCH)
#  Topologie : 1 master + 2 workers · Ubuntu 22.04 · réseau 192.168.56.0/24
#  Provider testé : VirtualBox (hôte x86_64)
# =====================================================================

BOX        = "bento/ubuntu-22.04"
MASTER_IP  = "192.168.56.10"
WORKERS    = { "worker1" => "192.168.56.11", "worker2" => "192.168.56.12" }
CPUS       = 2
MEM_MASTER = 4096
MEM_WORKER = 4096

Vagrant.configure("2") do |config|
  config.vm.box = BOX
  # Désactive le dossier synchronisé par défaut si rsync pose souci (optionnel) :
  # config.vm.synced_folder ".", "/vagrant", disabled: false

  # ---------------- MASTER ----------------
  config.vm.define "master" do |m|
    m.vm.hostname = "master"
    m.vm.network "private_network", ip: MASTER_IP
    m.vm.provider "virtualbox" do |vb|
      vb.name   = "k8s-master"
      vb.cpus   = CPUS
      vb.memory = MEM_MASTER
    end
    m.vm.provision "common", type: "shell", path: "scripts/common.sh", args: [MASTER_IP]
    m.vm.provision "master", type: "shell", path: "scripts/master.sh", args: [MASTER_IP]
    # Le stockage s'installe APRÈS la jonction des workers :
    #   vagrant ssh master -c "sudo bash /vagrant/scripts/storage.sh #{MASTER_IP}"
  end

  # ---------------- WORKERS ----------------
  WORKERS.each do |name, ip|
    config.vm.define name do |w|
      w.vm.hostname = name
      w.vm.network "private_network", ip: ip
      w.vm.provider "virtualbox" do |vb|
        vb.name   = "k8s-#{name}"
        vb.cpus   = CPUS
        vb.memory = MEM_WORKER
      end
      w.vm.provision "common", type: "shell", path: "scripts/common.sh", args: [ip]
      w.vm.provision "worker", type: "shell", path: "scripts/worker.sh"
    end
  end

  # -------- DOCKERLAB (optionnelle, atelier 01 uniquement) --------
  # Cette VM évite Docker Desktop/WSL2 lorsque l'hôte Windows est lui-même une
  # VM. Elle n'est pas démarrée par `vagrant up` ni par bootstrap-windows.ps1.
  config.vm.define "dockerlab", autostart: false do |d|
    d.vm.hostname = "dockerlab"
    d.vm.network "private_network", ip: "192.168.56.20"
    d.vm.network "forwarded_port", guest: 8080, host: 8080, auto_correct: true
    d.vm.network "forwarded_port", guest: 8090, host: 8090, auto_correct: true
    d.vm.provider "virtualbox" do |vb|
      vb.name   = "dockerlab"
      vb.cpus   = 2
      vb.memory = 2048
    end
    d.vm.provision "dockerlab", type: "shell", path: "scripts/dockerlab.sh"
  end
end
