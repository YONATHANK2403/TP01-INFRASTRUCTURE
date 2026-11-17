#!/usr/bin/env bash
# Détecte les conflits avec d'autres stacks Docker (noms de conteneurs, sous-réseaux 172.20.x.x).
set -euo pipefail
conflict=0

for c in router-fw web-dmz dns-lan client-lan admin-mgmt; do
  if docker inspect "$c" >/dev/null 2>&1; then
    proj=$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$c" 2>/dev/null || true)
    if [ "$proj" != "tp01" ]; then
      echo "CONFLIT : le conteneur '$c' existe déjà (projet compose : '${proj:-aucun}')."
      conflict=1
    fi
  fi
done

while read -r name subnets; do
  case "$name" in tp01_*) continue ;; esac
  for s in $subnets; do
    case "$s" in
      172.20.*) echo "CONFLIT : le réseau '$name' utilise déjà $s (chevauchement possible avec 172.20.1-3.0/24)."; conflict=1 ;;
    esac
  done
done < <(docker network ls -q | xargs -r docker network inspect \
          -f '{{.Name}} {{range .IPAM.Config}}{{.Subnet}} {{end}}')

if [ "$conflict" -ne 0 ]; then
  echo ">> Arrêtez l'autre stack (docker compose down dans son dossier) puis relancez."
  exit 1
fi
echo "Preflight OK : aucun conflit détecté."
