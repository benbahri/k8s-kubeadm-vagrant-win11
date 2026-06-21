#!/usr/bin/env bash
# =====================================================================
#  worker.sh — Joint un noeud worker au cluster
#  Utilise la commande de join générée par le master dans /vagrant
# =====================================================================
set -euo pipefail

echo "==> Attente de la commande de join (/vagrant/join-command.sh)"
for i in $(seq 1 30); do
  [ -f /vagrant/join-command.sh ] && break
  echo "    ...master pas encore prêt ($i/30)"; sleep 10
done

if [ ! -f /vagrant/join-command.sh ]; then
  echo "❌ join-command.sh introuvable. Le master a-t-il fini son provisioning ?"
  exit 1
fi

echo "==> Jonction au cluster"
bash /vagrant/join-command.sh
echo "==> worker.sh terminé."
