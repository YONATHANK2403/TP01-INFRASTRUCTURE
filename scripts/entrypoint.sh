#!/bin/sh
# Prépare le réseau du conteneur : route par défaut via router-fw + DNS du LAN.
set -eu

if [ -n "${DEFAULT_GW:-}" ]; then
  ip route replace default via "${DEFAULT_GW}"
fi

if [ -n "${DNS_SERVER:-}" ]; then
  {
    echo "nameserver ${DNS_SERVER}"
    if [ -n "${DNS_DOMAIN:-}" ]; then echo "search ${DNS_DOMAIN}"; fi
  } > /etc/resolv.conf || echo "WARN: /etc/resolv.conf non modifiable" >&2
fi

exec "$@"
