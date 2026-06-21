#!/usr/bin/env bash
# Docker Engine pour l'atelier 01, dans une VM Linux dédiée.
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installation de Docker Engine"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io
fi

systemctl enable --now docker
usermod -aG docker vagrant

echo "==> Dockerlab prêt. Reconnectez-vous avec 'vagrant ssh dockerlab'."
docker version --format 'Docker Engine {{.Server.Version}}' || true
