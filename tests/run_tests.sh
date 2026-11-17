#!/usr/bin/env bash
# Étape 5 — Tests : web (curl), DNS (dig), pare-feu, isolation, playbooks Ansible.
# Chaque test d'isolation (blocage) est précédé d'un test « témoin » (flux autorisé) pour éviter les faux positifs.
set -uo pipefail
cd "$(dirname "$0")/.."
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"

PASS=0; FAIL=0
t() {  # t "description" 'commande évaluée par eval'
  local desc="$1" cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then echo "  [PASS] $desc"; PASS=$((PASS+1))
  else echo "  [FAIL] $desc"; FAIL=$((FAIL+1)); fi
}

echo "== 1. Conteneurs =="
for c in router-fw web-dmz dns-lan client-lan admin-mgmt; do
  t "$c est démarré" "[ \"\$(docker inspect -f '{{.State.Running}}' $c)\" = true ]"
done

echo "== 2. Serveur Web (curl) =="
t "client-lan -> http://172.20.1.10/ répond 200" \
  '[ "$(docker exec client-lan curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://172.20.1.10/)" = 200 ]'
t "client-lan -> http://web.tp01.lab/health (nom résolu par dns-lan)" \
  'docker exec client-lan curl -sf --max-time 5 http://web.tp01.lab/health | grep -q OK'
t "reverse proxy : /api/ atteint le backend interne" \
  'docker exec client-lan curl -sf --max-time 5 http://web.tp01.lab/api/ | grep -q tp01-backend'
t "admin-mgmt -> web-dmz répond 200" \
  '[ "$(docker exec admin-mgmt curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://172.20.1.10/)" = 200 ]'
t "version de Nginx masquée (server_tokens off)" \
  '! docker exec client-lan curl -sI --max-time 5 http://172.20.1.10/ | grep -Eqi "^server: nginx/"'

echo "== 3. DNS (dig) =="
t "web.tp01.lab -> 172.20.1.10 (depuis client-lan)" \
  '[ "$(docker exec client-lan dig +short +time=2 +tries=1 @172.20.2.10 web.tp01.lab)" = 172.20.1.10 ]'
t "dns.tp01.lab -> 172.20.2.10" \
  '[ "$(docker exec client-lan dig +short +time=2 +tries=1 @172.20.2.10 dns.tp01.lab)" = 172.20.2.10 ]'
t "admin-mgmt interroge dns-lan (flux MGMT -> LAN autorisé)" \
  '[ "$(docker exec admin-mgmt dig +short +time=2 +tries=1 @172.20.2.10 web.tp01.lab)" = 172.20.1.10 ]'
t "web-dmz interroge dns-lan (flux DMZ -> DNS autorisé)" \
  '[ "$(docker exec web-dmz dig +short +time=2 +tries=1 @172.20.2.10 dns.tp01.lab)" = 172.20.2.10 ]'
t "nom inconnu -> NXDOMAIN" \
  'docker exec client-lan dig +time=2 +tries=1 @172.20.2.10 inconnu.tp01.lab | grep -q NXDOMAIN'

echo "== 4. Pare-feu nftables =="
t "table inet tp01_filter chargée" 'docker exec router-fw nft list table inet tp01_filter'
t "chaîne forward en policy drop" \
  'docker exec router-fw nft list chain inet tp01_filter forward | grep -q "policy drop"'
t "chaîne input en policy drop" \
  'docker exec router-fw nft list chain inet tp01_filter input | grep -q "policy drop"'
t "routage IPv4 activé sur router-fw" '[ "$(docker exec router-fw cat /proc/sys/net/ipv4/ip_forward)" = 1 ]'

echo "== 5. Isolation des réseaux =="
# Témoins (doivent PASSER)
t "témoin : client-lan -> web-dmz ping (LAN->DMZ autorisé)" 'docker exec client-lan ping -c1 -W2 172.20.1.10'
t "témoin : admin-mgmt -> client-lan ping (MGMT->LAN autorisé)" 'docker exec admin-mgmt ping -c1 -W2 172.20.2.20'
t "témoin : admin-mgmt -> web-dmz ping (MGMT->DMZ autorisé)" 'docker exec admin-mgmt ping -c1 -W2 172.20.1.10'
# Blocages (doivent ÉCHOUER côté réseau)
t "DMZ -> LAN bloqué (web-dmz -/-> client-lan)" '! docker exec web-dmz ping -c1 -W2 172.20.2.20'
t "DMZ -> LAN bloqué hors DNS (web-dmz -/-> dns-lan ping)" '! docker exec web-dmz ping -c1 -W2 172.20.2.10'
t "DMZ -> MGMT bloqué (web-dmz -/-> admin-mgmt)" '! docker exec web-dmz ping -c1 -W2 172.20.3.10'
t "LAN -> MGMT bloqué (client-lan -/-> admin-mgmt)" '! docker exec client-lan ping -c1 -W2 172.20.3.10'
t "LAN -> DMZ port non autorisé bloqué (8080)" '! docker exec client-lan curl -s --max-time 3 http://172.20.1.10:8080/'
t "backend 8081 inaccessible directement depuis le LAN" '! docker exec client-lan curl -s --max-time 3 http://172.20.1.10:8081/'
t "compteur « default deny » > 0 (le pare-feu a bien bloqué du trafic)" \
  'docker exec router-fw nft list chain inet tp01_filter forward | grep "default deny" | grep -Eq "packets [1-9]"'

echo "== 6. Playbooks Ansible =="
t "syntaxe du playbook site.yml" 'ansible-playbook ansible/playbooks/site.yml --syntax-check'
t "ré-exécution idempotente (changed=0, failed=0)" \
  'out=$(ansible-playbook ansible/playbooks/site.yml 2>&1); echo "$out" | grep -q "failed=0" && ! echo "$out" | grep -Eq "changed=[1-9]|failed=[1-9]|unreachable=[1-9]"'

echo
echo "Résultat : $PASS réussi(s), $FAIL échec(s)"
[ "$FAIL" -eq 0 ]
