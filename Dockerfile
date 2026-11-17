# syntax=docker/dockerfile:1
# Une seule image de base, 4 cibles (une par rôle). Le rôle réel est appliqué par Ansible.
ARG ALPINE_VERSION=3.20

FROM alpine:${ALPINE_VERSION} AS base
# python3 est requis par Ansible (modules exécutés dans le conteneur via docker exec)
RUN apk add --no-cache tini python3 iproute2 iputils curl bind-tools
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]

FROM base AS router
RUN apk add --no-cache nftables

FROM base AS web
RUN apk add --no-cache nginx \
 && mkdir -p /var/log/nginx /usr/share/nginx/html

FROM base AS dns
RUN apk add --no-cache dnsmasq

FROM base AS client
