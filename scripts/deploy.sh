#!/usr/bin/env bash
# Déploiement complet, sans intervention manuelle dans les conteneurs :
# preflight → docker compose up → ansible (3 rôles) → tests.
set -euo pipefail
cd "$(dirname "$0")/.."
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"

./scripts/preflight.sh
docker compose up -d --build

echo ">> Attente du démarrage des 5 conteneurs..."
n=0
for _ in $(seq 1 30); do
  n=$(docker compose ps --status running -q | wc -l)
  [ "$n" -eq 5 ] && break
  sleep 1
done
[ "$n" -eq 5 ] || { echo "ERREUR : conteneurs non démarrés"; docker compose ps; exit 1; }

echo ">> Configuration via Ansible..."
ansible-playbook ansible/playbooks/site.yml

echo ">> Tests..."
./tests/run_tests.sh
