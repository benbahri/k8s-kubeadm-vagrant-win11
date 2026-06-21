#!/usr/bin/env bash
# =====================================================================
#  common.sh — Préparation commune à TOUS les noeuds (master + workers)
#  Cible : Ubuntu 22.04 LTS · Kubernetes 1.30 · runtime containerd
# =====================================================================
set -euo pipefail

K8S_MINOR="v1.33"   # version maintenue (bumper ici pour changer toute la flotte)

echo "==> [1/7] Désactivation du swap (exigence kubelet)"
swapoff -a
sed -i '/\bswap\b/s/^/#/' /etc/fstab

echo "==> [2/7] Modules noyau pour le réseau conteneurs"
cat <<EOF >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

echo "==> [3/7] Paramètres sysctl (bridge + ip_forward)"
cat <<EOF >/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
# Ne charger que les paramètres Kubernetes. `sysctl --system` recharge aussi
# les valeurs Ubuntu de /usr/lib/sysctl.d ; certains hyperviseurs imbriqués
# refusent notamment accept_source_route et promote_secondaries, ce qui peut
# faire échouer le provisioning alors que ces clés sont inutiles à Kubernetes.
sysctl -p /etc/sysctl.d/k8s.conf >/dev/null

echo "==> [4/7] Installation de containerd + client NFS (requis sur TOUS les noeuds)"
apt-get update -qq
# nfs-common : indispensable sur chaque noeud pour monter les PVC NFS (mount.nfs
# s'exécute sur le noeud qui héberge le Pod, pas seulement sur le serveur NFS).
apt-get install -y -qq apt-transport-https ca-certificates curl gnupg containerd nfs-common
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
# Utiliser le cgroup driver systemd (aligné avec kubelet)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

echo "==> [5/7] Dépôt APT officiel Kubernetes ($K8S_MINOR)"
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

echo "==> [6/7] Installation de kubelet, kubeadm, kubectl"
apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl   # fige les versions

echo "==> [7/7] Pré-téléchargement des images du control-plane (accélère kubeadm init)"
kubeadm config images pull >/dev/null 2>&1 || true

echo "==> common.sh terminé."
