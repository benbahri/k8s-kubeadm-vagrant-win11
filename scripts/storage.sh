#!/usr/bin/env bash
# =====================================================================
#  storage.sh — Provisionne le stockage dynamique pour les ateliers Volumes
#  Exécuté sur le MASTER, après que les workers ont rejoint.
#
#  Deux StorageClass sont mises en place :
#   1) local-path  : provisioner Rancher (hostPath par noeud) — simple,
#                    parfait pour emptyDir-like et PVC mono-noeud.
#   2) nfs-client  : provisioner NFS dynamique — un PVC est satisfait
#                    par un partage NFS hébergé sur le master, donc
#                    accessible depuis N'IMPORTE QUEL noeud (vrai multi-noeuds).
#
#  La StorageClass par défaut est 'nfs-client' (adaptée au multi-noeuds).
# =====================================================================
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

NFS_DIR="/srv/nfs/kubedata"
NFS_IP="${1:-192.168.56.10}"

echo "==> [1/4] Serveur NFS sur le master ($NFS_DIR exporté vers 192.168.56.0/24)"
apt-get install -y -qq nfs-kernel-server
mkdir -p "$NFS_DIR"
chown nobody:nogroup "$NFS_DIR"
chmod 0777 "$NFS_DIR"
grep -q "$NFS_DIR" /etc/exports || \
  echo "$NFS_DIR 192.168.56.0/24(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
exportfs -ra
systemctl enable --now nfs-kernel-server

echo "==> [2/4] local-path-provisioner (StorageClass 'local-path')"
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml

echo "==> [3/4] nfs-subdir-external-provisioner via Helm (StorageClass 'nfs-client')"
if ! command -v helm >/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/ >/dev/null
helm repo update >/dev/null
helm install nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server="$NFS_IP" \
  --set nfs.path="$NFS_DIR" \
  --set storageClass.name=nfs-client \
  --namespace kube-system

echo "==> [4/4] Définir nfs-client comme StorageClass par défaut"
kubectl patch storageclass nfs-client \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "==> storage.sh terminé. Vérifiez : kubectl get storageclass"
