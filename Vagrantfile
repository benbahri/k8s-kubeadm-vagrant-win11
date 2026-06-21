# =====================================================================
#  Vagrantfile — Cluster Kubernetes kubeadm multi-noeuds (formation KUB-ORCH)
#  Topologie : 1 master + 2 workers · Ubuntu 22.04 · réseau 192.168.56.0/24
#  Provider testé : VirtualBox (hôte x86_64)
# =====================================================================

BOX        = "bento/ubuntu-22.04"
MASTER_IP  = "192.168.56.10"
WORKERS    = { "worker1" => "192.168.56.11", "worker2" => "192.168.56.12" }
CPUS       = 2
MEM_MASTER = 2560
MEM_WORKER = 2048

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
    m.vm.provision "common", type: "shell", path: "scripts/common.sh"
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
      w.vm.provision "common", type: "shell", path: "scripts/common.sh"
      w.vm.provision "worker", type: "shell", path: "scripts/worker.sh"
    end
  end
end
