#!/usr/bin/env bash
# =====================================================================
#  master.sh — Initialise le control-plane sur le noeud master
#  Args : $1 = IP privée de l'API server (ex: 192.168.56.10)
# =====================================================================
set -euo pipefail

API_IP="${1:-192.168.56.10}"
POD_CIDR="192.168.0.0/16"     # CIDR par défaut de Calico

echo "==> kubeadm init (apiserver=${API_IP}, pod-cidr=${POD_CIDR})"
kubeadm init \
  --apiserver-advertise-address="${API_IP}" \
  --pod-network-cidr="${POD_CIDR}" \
  --node-name master

echo "==> Configuration de kubectl pour l'utilisateur vagrant ET root"
for USERHOME in /home/vagrant /root; do
  mkdir -p "${USERHOME}/.kube"
  cp -f /etc/kubernetes/admin.conf "${USERHOME}/.kube/config"
done
chown -R vagrant:vagrant /home/vagrant/.kube
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "==> Installation du CNI Calico"
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/calico.yaml

# SÉCURITÉ (lab uniquement) : les fichiers ci-dessous sont déposés dans le dossier
# partagé /vagrant pour le confort de la formation (join des workers + pilotage
# kubectl depuis l'hôte). 'admin.conf' donne des droits cluster-admin et la commande
# de join contient un token valide. NE JAMAIS reproduire ce partage en production :
# kubeconfig admin et tokens de join sont des secrets. Ici les VMs sont isolées.
echo "==> Génération de la commande de join pour les workers (dossier partagé /vagrant)"
kubeadm token create --print-join-command > /vagrant/join-command.sh
chmod +x /vagrant/join-command.sh

echo "==> Copie du kubeconfig dans /vagrant pour accès depuis l'hôte (optionnel, lab)"
cp -f /etc/kubernetes/admin.conf /vagrant/admin.conf || true

echo "==> master.sh terminé. Vérifiez avec : kubectl get nodes"
