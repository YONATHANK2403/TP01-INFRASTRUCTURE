# TP 01 — Construction et automatisation de l'infrastructure réseau

Infrastructure segmentée **DMZ / LAN / Management** déployée avec Docker Compose, configurée par **Ansible** (connexion `docker exec`, sans SSH) et filtrée par **nftables**.

## Démarrage rapide (un seul bloc)

```bash
tar xzf TP01-INFRASTRUCTURE.tar.gz && cd TP01-INFRASTRUCTURE
./scripts/install-prereqs.sh   # une fois : Docker, Compose, Ansible, collection community.docker
./scripts/deploy.sh            # preflight → compose up → ansible → tests
```

Aucune commande n'est tapée dans un conteneur : tout passe par `docker compose` et `ansible-playbook`.

## Architecture

```
                 ┌──────────────────── router-fw (nftables) ────────────────────┐
                 │  172.20.1.1            172.20.2.1             172.20.3.1     │
                 └──────┬─────────────────────┬──────────────────────┬──────────┘
                        │                     │                      │
              DMZ 172.20.1.0/24       LAN 172.20.2.0/24      MGMT 172.20.3.0/24
                        │               │          │               │
                    web-dmz          dns-lan   client-lan      admin-mgmt
                 .10 Nginx          .10 dnsmasq .20 (test)     .10 (test)
```

| Conteneur | Zone | IP | Rôle |
|---|---|---|---|
| router-fw | DMZ/LAN/MGMT | .1 de chaque zone | Routage + pare-feu nftables |
| web-dmz | DMZ | 172.20.1.10 | Nginx (serveur Web + reverse proxy) |
| dns-lan | LAN | 172.20.2.10 | dnsmasq (zone `tp01.lab`) |
| client-lan | LAN | 172.20.2.20 | Client de test |
| admin-mgmt | MGMT | 172.20.3.10 | Poste d'administration de test |

Les 3 réseaux Docker sont `internal: true` : aucun trafic ne sort, et **tout flux inter-zones traverse router-fw**.

## Matrice de flux (politique : tout refusé par défaut)

| Source → Destination | Autorisé |
|---|---|
| LAN → web-dmz | TCP 80, ping DMZ |
| DMZ → dns-lan | DNS (TCP/UDP 53) uniquement |
| MGMT → DMZ, LAN | ping, TCP 22/53/80/443, UDP 53 vers dns-lan |
| DMZ → LAN (hors DNS), DMZ → MGMT, LAN → MGMT | **Bloqué** |

## Correspondance avec les étapes du TP

| Étape | Où |
|---|---|
| 1. Environnement (Docker, réseaux, Git, IP) | `scripts/install-prereqs.sh`, `docker-compose.yml`, section Git ci-dessous |
| 2. Trois zones | `networks:` de `docker-compose.yml` |
| 3. Services | `web-dmz`, `router-fw`, `dns-lan` dans `docker-compose.yml` + `Dockerfile` (cibles `web`, `router`, `dns`, `client`) |
| 4. Ansible | `ansible/roles/{firewall,dns,reverse-proxy}` ; configs Jinja2 dans `configs/` |
| 5. Tests | `tests/run_tests.sh` (curl, dig, règles, isolation, idempotence) |

## Fonctionnement

1. `docker compose up` crée les 5 conteneurs ; `entrypoint.sh` pose la route par défaut via router-fw et le DNS du LAN.
2. `site.yml` applique les 3 rôles. Chaque template est **validé avant écriture** (`nft -c`, `dnsmasq --test`, `nginx -t`).
3. Les playbooks sont **idempotents** : une 2ᵉ exécution doit afficher `changed=0`.

Commandes utiles :

```bash
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
ansible-playbook ansible/playbooks/site.yml              # re-appliquer les configs
docker exec router-fw nft list ruleset                   # lecture seule : voir les règles
docker exec client-lan curl -s http://web.tp01.lab/      # démo web par nom
docker exec client-lan dig @172.20.2.10 web.tp01.lab     # démo DNS
./tests/run_tests.sh                                     # tous les tests
./scripts/teardown.sh                                    # tout arrêter
```

## Git

```bash
cd TP01-INFRASTRUCTURE
git init -b main
git add . && git commit -m "feat(tp01): infrastructure réseau segmentée automatisée"
git remote add origin <URL_DU_DEPOT> && git push -u origin main
```

## Limites connues / dépannage

- **Conteneur redémarré** (`docker restart`) : les services lancés par Ansible ne repartent pas seuls → relancer `ansible-playbook ansible/playbooks/site.yml` (les règles nft sont aussi rechargées).
- **Conflit de noms/sous-réseaux** avec une autre stack (ex. un autre projet utilisant `172.20.x.x`, `web-dmz`, `router-fw`) : `./scripts/preflight.sh` le détecte ; arrêter l'autre stack avant.
- **Adresses dupliquées** : `docker-compose.yml` est la source de vérité, `ansible/inventory/group_vars/all.yml` en est le miroir — les modifier ensemble.
- `NET_ADMIN` est donné aux conteneurs pour poser la route par défaut ; en production, on utiliserait un vrai routeur/VLAN.
- Pas de TLS (443 non ouvert) : extension possible (certificat + `listen 443 ssl` + règle nft).
# TP01-INFRASTRUCTURE
