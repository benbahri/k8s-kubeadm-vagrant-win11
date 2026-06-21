# Mise en place d'un cluster Kubernetes (kubeadm, multi-noeuds)

Document de référence — formateur et candidats. Il décrit la création d'un cluster
Kubernetes **multi-noeuds** avec **kubeadm**, sur des machines virtuelles provisionnées
par **Vagrant**, ainsi qu'une **solution de stockage** permettant de réaliser
correctement les ateliers Volumes (PV/PVC, provisionnement dynamique).

Deux usages :

- **Voie automatisée** (section 3) : `vagrant up`, le cluster est prêt en ~10 min.
- **Voie manuelle** (section 6) : les mêmes étapes, commande par commande, pour
  comprendre ce que fait kubeadm (utile en démonstration et pour la certification).

---

## 1. Topologie cible

| Noeud   | Rôle           | IP privée       | vCPU | RAM     |
|---------|----------------|-----------------|------|---------|
| master  | control-plane  | 192.168.56.10   | 2    | 2560 Mo |
| worker1 | worker         | 192.168.56.11   | 2    | 2048 Mo |
| worker2 | worker         | 192.168.56.12   | 2    | 2048 Mo |

- Système : **Ubuntu 22.04 LTS**
- Kubernetes : **1.33** · Runtime : **containerd** · CNI : **Calico**
- Réseau Pods (CIDR) : `192.168.0.0/16`

> Remarque : le support historique installait Kubernetes sur **CentOS**. CentOS 7/8
> étant en fin de vie, cette procédure est portée sur **Ubuntu 22.04** et le dépôt
> APT officiel `pkgs.k8s.io` (le dépôt `apt.kubernetes.io` est déprécié).

---

## 2. Prérequis sur la machine hôte

| Outil | Rôle | Vérification |
|-------|------|--------------|
| VirtualBox (≥ 7.0) | hyperviseur | `VBoxManage --version` |
| Vagrant (≥ 2.4) | orchestration des VMs | `vagrant --version` |
| ~8 Go de RAM libre, ~20 Go disque | exécuter 3 VMs | — |

Installation rapide (macOS) :
```bash
brew install --cask virtualbox vagrant docker   # docker = Docker Desktop (atelier 01)
```

Installation automatisée (Windows 11, PowerShell) :
```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\bootstrap-windows.ps1
```

Le script [`bootstrap-windows.ps1`](bootstrap-windows.ps1) demande les droits
administrateur puis installe, si nécessaire, VirtualBox, Vagrant, Git/Git Bash,
Visual Studio Code, **Docker Desktop** et MSYS2. Il configure Git Bash comme
terminal VS Code par défaut, installe Zsh avec Oh My Zsh dans MSYS2, puis démarre
`master`, `worker1` et `worker2` séquentiellement. Utilisez `-NoVagrantUp` pour
installer les outils sans démarrer les VMs, `-SkipZsh` pour ne pas installer
l'environnement Zsh, ou `-SkipDocker` pour ne pas installer Docker Desktop.

> **Pourquoi Docker sur l'hôte ?** L'atelier 01 (rappel conteneurs) construit et
> lance des images en local : il a besoin de Docker **sur la machine hôte**. Le
> cluster, lui, tourne sous **containerd** dans les VMs — Docker n'y est
> volontairement pas installé (le `dockershim` a été retiré de Kubernetes en 1.24).
> Docker Desktop s'appuie sur WSL2 : un redémarrage et l'activation de WSL2 peuvent
> être nécessaires au premier lancement.

> Zsh n'est pas fourni par Git Bash : il est installé dans MSYS2 et se lance avec
> `C:\msys64\msys2_shell.cmd -defterm -here -no-start -msys -shell zsh`.
> Si Windows 11 s'exécute lui-même dans une VM,
> la virtualisation imbriquée doit être activée sur l'hyperviseur hôte. Un
> redémarrage de Windows peut être nécessaire après l'installation de VirtualBox.

En cas d'échec d'une installation `winget`, la fenêtre reste ouverte et le détail
est enregistré dans `%TEMP%\kubeadm-bootstrap-windows.log`.

> Apple Silicon (M1/M2/M3) : VirtualBox ne supporte pas les puces ARM. Options :
> remplacer le provider par **VMware Fusion** (`vagrant_vmware_desktop`) ou
> **Parallels** (`vagrant-parallels`) et utiliser une box ARM
> (ex. `bento/ubuntu-22.04-arm64`), ou bien provisionner 3 VMs UTM/Multipass à la
> main puis appliquer directement les scripts de `scripts/` (voie manuelle, section 6).
> L'hôte de cette formation est x86_64 : la voie VirtualBox standard s'applique.

---

## 3. Voie automatisée (Vagrant)

Depuis ce dossier (`00-cluster-kubeadm/`) :

```bash
# 1. Démarrer et provisionner les 3 VMs (commun -> master -> workers)
vagrant up

# 2. Installer le stockage dynamique (NFS + local-path), une fois les workers joints
vagrant ssh master -c "sudo bash /vagrant/scripts/storage.sh 192.168.56.10"

# 3. Se connecter au master et vérifier
vagrant ssh master
kubectl get nodes -o wide
kubectl get storageclass
```

Résultat attendu :
```
NAME      STATUS   ROLES           AGE   VERSION
master    Ready    control-plane   5m    v1.33.x
worker1   Ready    <none>          3m    v1.33.x
worker2   Ready    <none>          3m    v1.33.x

NAME                   PROVISIONER                                     ...
local-path             rancher.io/local-path                           ...
nfs-client (default)   cluster.local/nfs-provisioner-...               ...
```

### Piloter le cluster depuis l'hôte (optionnel)
Le `admin.conf` est copié dans le dossier partagé :
```bash
export KUBECONFIG="$PWD/admin.conf"
kubectl get nodes
```

---

## 4. Ce que font les scripts de provisionnement

| Script | Exécuté sur | Contenu |
|--------|-------------|---------|
| [`scripts/common.sh`](scripts/common.sh) | tous | swap off, modules noyau, sysctl, containerd (cgroup systemd), dépôt + paquets `kubelet/kubeadm/kubectl`, pull des images |
| [`scripts/master.sh`](scripts/master.sh) | master | `kubeadm init`, kubeconfig, CNI Calico, génération de la commande de join |
| [`scripts/worker.sh`](scripts/worker.sh) | workers | attend puis exécute la commande de join |
| [`scripts/storage.sh`](scripts/storage.sh) | master | serveur NFS, `local-path-provisioner`, `nfs-subdir-external-provisioner` (SC par défaut) |

---

## 5. Stockage : pourquoi deux StorageClass ?

Sur un cluster **multi-noeuds**, un Pod peut être planifié sur n'importe quel worker.
Le choix du backend de stockage est donc déterminant pour les ateliers Volumes :

| StorageClass | Provisioner | Portée | Usage en atelier |
|--------------|-------------|--------|------------------|
| `local-path` | rancher.io/local-path | un répertoire **sur le noeud** où tourne le Pod | démonstration simple, PVC mono-noeud |
| `nfs-client` (défaut) | NFS dynamique | partage NFS du master, **accessible de tous les noeuds** | PVC dynamique réaliste, Pod re-planifié sur un autre noeud sans perte de données |

C'est `nfs-client` qui permet à l'atelier **18 (PV/PVC/StorageClass)** d'illustrer un
vrai **provisionnement dynamique** fonctionnant quel que soit le noeud d'exécution.

> Pour l'atelier **11 (hostPath PV)**, on utilise volontairement `local-path` ou un
> `hostPath` manuel afin de montrer les limites du stockage local en multi-noeuds.

---

## 6. Voie manuelle (pour comprendre / démontrer)

À exécuter en tant que `root` (`sudo -i`). Identique sur tous les noeuds pour 6.1–6.4.

### 6.1 Désactiver le swap
```bash
swapoff -a
sed -i '/\bswap\b/s/^/#/' /etc/fstab
```

### 6.2 Modules noyau + sysctl
```bash
cat <<EOF >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay && modprobe br_netfilter

cat <<EOF >/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system
```

### 6.3 Runtime containerd + client NFS
```bash
# nfs-common est requis sur TOUS les noeuds : le montage d'un PVC NFS s'effectue
# sur le noeud qui exécute le Pod, pas seulement sur le serveur NFS.
apt-get update && apt-get install -y containerd nfs-common
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd && systemctl enable containerd
```

### 6.4 Paquets Kubernetes (dépôt officiel)
```bash
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
```

### 6.5 Initialiser le control-plane (master uniquement)
```bash
kubeadm init \
  --apiserver-advertise-address=192.168.56.10 \
  --pod-network-cidr=192.168.0.0/16 \
  --node-name master

# kubeconfig pour l'utilisateur courant
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

### 6.6 Installer le CNI Calico (master uniquement)
```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/calico.yaml
kubectl get pods -n kube-system -w   # attendre que tout passe Running
```

### 6.7 Joindre les workers (sur chaque worker)
Récupérer la commande sur le master :
```bash
kubeadm token create --print-join-command
```
Puis l'exécuter sur chaque worker (exemple) :
```bash
kubeadm join 192.168.56.10:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

### 6.8 Vérifier
```bash
kubectl get nodes -o wide      # 3 noeuds Ready
```

---

## 7. Test de fumée (smoke test)

```bash
kubectl create deployment hello --image=nginx:1.27-alpine --replicas=3
kubectl expose deployment hello --port=80 --type=NodePort
kubectl get pods -o wide        # répartis sur worker1/worker2
PORT=$(kubectl get svc hello -o jsonpath='{.spec.ports[0].nodePort}')
curl http://192.168.56.11:$PORT # page NGINX
kubectl delete deploy,svc hello
```

Test stockage dynamique :
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get pvc test-pvc     # STATUS Bound (provisionné automatiquement par nfs-client)
kubectl delete pvc test-pvc
```

---

## 8. Confort kubectl (à faire sur le master)

```bash
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
source ~/.bashrc
```

---

## 9. Dépannage

| Symptôme | Cause probable | Correctif |
|----------|----------------|-----------|
| Noeuds `NotReady` | CNI absent / KO | réappliquer Calico ; `kubectl get pods -n kube-system` |
| `kubeadm init` échoue sur le swap | swap actif | `swapoff -a` puis relancer |
| worker ne rejoint pas | token expiré | régénérer : `kubeadm token create --print-join-command` |
| PVC reste `Pending` | provisioner NFS KO | `kubectl get pods -n kube-system | grep nfs` + logs |
| cgroup driver mismatch | containerd ≠ systemd | `SystemdCgroup = true` dans `/etc/containerd/config.toml` |

---

## 10. Cycle de vie des VMs

```bash
vagrant halt        # éteindre
vagrant up          # rallumer
vagrant destroy -f  # supprimer entièrement
vagrant status      # état
```

> Astuce formateur : après un `vagrant up` complet et un `storage.sh`, faites un
> **snapshot** (`vagrant snapshot save base`) pour repartir d'un cluster propre
> entre deux sessions (`vagrant snapshot restore base`).
