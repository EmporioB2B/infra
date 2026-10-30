#!/usr/bin/env bash
# Prova determinística e isolada de que o dashboard do Emporio auto-provisiona no
# Grafana, sem depender da senha persistida no volume grafana-data do dev (que
# diverge do env em boots reaproveitados e geraria 401 falso-positivo).
#
# Sobe UM container Grafana descartável com banco Vazio num bind temporário
# (/tmp/opencode/...), montando os MESMOS arquivos versionados de provisionamento
# e dashboards somente-leitura, e confirma via API (com credencial efêmera de
# teste) que /api/dashboards/uid/emporio-backend-dev responde 200 e é o nosso
# dashboard. Não cria volume nomeado; o container usa --rm e é removido no fim.
#
# Uso: scripts/check-grafana-provisioning.sh   (não requer o stack dev ligado)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="grafana/grafana:12.0.0"
NAME="emp-grafana-prov-check"
DATA="$(mktemp -d /tmp/opencode/grafana-prov-XXXXXX)"
PROV_USER="admin"
PROV_PASS="emporio-prov-dummy"   # credencial efêmera deste container descartável
UID_CHECK="emporio-backend-dev"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  # não usa rm -rf absoluto (interdito): deixa o temp em /tmp/opencode, que é
  # efêmero e pré-aprovado para trabalho temporário.
}
trap cleanup EXIT

chmod 0777 "$DATA"
echo "==> subindo Grafana descartável (banco vazio em $DATA)"
docker run -d --rm --name "$NAME" \
  -e GF_SECURITY_ADMIN_USER="$PROV_USER" \
  -e GF_SECURITY_ADMIN_PASSWORD="$PROV_PASS" \
  -e GF_SERVER_HTTP_ADDR=127.0.0.1 \
  -e GF_ANALYTICS_REPORTING_ENABLED=false \
  -v "$DATA":/var/lib/grafana:rw \
  -v "$ROOT/compose/grafana/provisioning":/etc/grafana/provisioning:ro \
  -v "$ROOT/compose/grafana/dashboards":/var/lib/grafana/dashboards:ro \
  "$IMAGE" >/dev/null

echo "==> aguardando /api/health"
healthy=0
for _ in $(seq 1 30); do
  if docker exec "$NAME" wget -q -O /dev/null http://127.0.0.1:3000/api/health 2>/dev/null; then
    healthy=1; break
  fi
  sleep 2
done
[[ "$healthy" -eq 1 ]] || { echo "ERRO: Grafana descartável não ficou saudável" >&2; exit 1; }

# aguarda o file provider (updateIntervalSeconds=30) registrar o dashboard
echo "==> aguardando file provider registrar o dashboard"
code=""
for _ in $(seq 1 20); do
  # shellcheck disable=SC2016
  code="$(docker exec "$NAME" sh -c \
    'auth=$(printf "%s:%s" "$GF_SECURITY_ADMIN_USER" "$GF_SECURITY_ADMIN_PASSWORD" | base64 | tr -d "\n"); wget -S -O /dev/null --header="Authorization: Basic $auth" "http://127.0.0.1:3000/api/dashboards/uid/'"$UID_CHECK"'" 2>&1 | grep -m1 -oE "HTTP/[0-9.]+ [0-9]{3}"' \
    | tr -d '\r' | grep -oE '[0-9]{3}$' || true)"
  [[ "$code" == "200" ]] && break
  sleep 3
done

if [[ "$code" != "200" ]]; then
  echo "ERRO: dashboard $UID_CHECK não provisionou (HTTP=${code:-sem resposta})" >&2
  echo "---- provisioning log ----" >&2
  docker logs "$NAME" 2>&1 | grep -iE 'provisioning.dashboard|failed to load dashboard' | tail -20 >&2 || true
  exit 1
fi

# shellcheck disable=SC2016
title="$(docker exec "$NAME" sh -c \
  'auth=$(printf "%s:%s" "$GF_SECURITY_ADMIN_USER" "$GF_SECURITY_ADMIN_PASSWORD" | base64 | tr -d "\n"); wget -q -O - --header="Authorization: Basic $auth" "http://127.0.0.1:3000/api/dashboards/uid/'"$UID_CHECK"'"' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["dashboard"]["title"])')"

echo "OK   grafana: dashboard provisionado automaticamente em banco limpo — title=\"${title}\" (HTTP 200)"
echo "check-grafana-provisioning: passaram"
