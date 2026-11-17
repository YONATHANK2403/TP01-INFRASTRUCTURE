#!/usr/bin/env bash
# Étape 1 — Installe/vérifie Docker, Docker Compose et Ansible (+ collection community.docker).
set -euo pipefail
cd "$(dirname "$0")/.."

SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

if ! command -v docker >/dev/null 2>&1; then
  $SUDO apt-get update -y
  $SUDO apt-get install -y docker.io docker-compose-v2
  $SUDO usermod -aG docker "$USER"
  echo ">> Reconnectez-vous (groupe docker) puis relancez ce script."; exit 0
fi
docker --version
docker compose version

if ! command -v ansible-playbook >/dev/null 2>&1; then
  $SUDO apt-get update -y
  $SUDO apt-get install -y ansible
fi
ansible --version | head -n 1
ansible-galaxy collection install -r ansible/requirements.yml
echo "OK : prérequis en place."
