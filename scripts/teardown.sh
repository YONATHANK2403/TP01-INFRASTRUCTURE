#!/usr/bin/env bash
# Arrête et supprime les conteneurs/réseaux du TP01 (aucun volume n'est utilisé).
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose down
