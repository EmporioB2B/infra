#!/usr/bin/env bash
# Testes disruptivos, somente para o ambiente dev:
#   - restart do Prometheus preserva readiness, configuração e volume;
#   - target do Backend vai a 0 durante indisponibilidade;
#   - target retorna a 1 após a recuperação do Backend.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/compose/docker-compose.dev.yml"
ENV_FILE="$ROOT/env/.env.dev"

[[ -f "$ENV_FILE" ]] || { echo "ERRO: falta $ENV_FILE" >&2; exit 1; }

compose() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

prometheus() {
  compose exec -T prometheus wget -q -O - "$1"
}

wait_ready() {
  local attempts=0
  until prometheus http://127.0.0.1:9090/-/ready >/dev/null; do
    attempts=$((attempts + 1))
    (( attempts < 24 )) || return 1
    sleep 5
  done
}

wait_target() {
  local expected="$1" attempts=0 payload
  until payload="$(prometheus 'http://127.0.0.1:9090/api/v1/query?query=up%7Bjob%3D%22emporio-backend%22%7D')" \
    && [[ "$payload" == *"\"$expected\""* ]]; do
    attempts=$((attempts + 1))
    (( attempts < 24 )) || return 1
    sleep 5
  done
}

restore_backend() {
  compose start backend >/dev/null 2>&1 || true
}
trap restore_backend EXIT

PROM_CONTAINER="$(compose ps -q prometheus)"
VOLUME_BEFORE="$(docker inspect "$PROM_CONTAINER" \
  --format '{{range .Mounts}}{{if eq .Destination "/prometheus"}}{{.Name}}{{end}}{{end}}')"
CONFIG_BEFORE="$(prometheus http://127.0.0.1:9090/api/v1/status/config | sha256sum | cut -d' ' -f1)"
wait_target 1
HISTORY_START="$(( $(date +%s) - 30 ))"
HISTORY_BEFORE="$(prometheus "http://127.0.0.1:9090/api/v1/query_range?query=process_start_time_seconds%7Bjob%3D%22emporio-backend%22%7D&start=${HISTORY_START}&end=$(date +%s)&step=15")"
[[ "$HISTORY_BEFORE" == *'"values":[['* ]] \
  || { echo "FAIL: não existe amostra histórica antes do restart" >&2; exit 1; }

compose restart prometheus >/dev/null
wait_ready

PROM_CONTAINER_AFTER="$(compose ps -q prometheus)"
VOLUME_AFTER="$(docker inspect "$PROM_CONTAINER_AFTER" \
  --format '{{range .Mounts}}{{if eq .Destination "/prometheus"}}{{.Name}}{{end}}{{end}}')"
CONFIG_AFTER="$(prometheus http://127.0.0.1:9090/api/v1/status/config | sha256sum | cut -d' ' -f1)"

[[ "$VOLUME_BEFORE" == "$VOLUME_AFTER" ]] \
  || { echo "FAIL: volume do Prometheus mudou no restart" >&2; exit 1; }
[[ "$CONFIG_BEFORE" == "$CONFIG_AFTER" ]] \
  || { echo "FAIL: configuração do Prometheus mudou no restart" >&2; exit 1; }
echo "OK   prometheus: restart preservou volume e configuração"

HISTORY_AFTER="$(prometheus "http://127.0.0.1:9090/api/v1/query_range?query=process_start_time_seconds%7Bjob%3D%22emporio-backend%22%7D&start=${HISTORY_START}&end=$(date +%s)&step=15")"
[[ "$HISTORY_AFTER" == *'"values":[['* ]] \
  || { echo "FAIL: amostra histórica não sobreviveu ao restart" >&2; exit 1; }
echo "OK   prometheus: amostra histórica preservada no restart"

compose stop backend >/dev/null
wait_target 0
echo "OK   prometheus: target Backend ficou DOWN durante a indisponibilidade"

compose start backend >/dev/null
wait_target 1
echo "OK   prometheus: target Backend voltou UP após recuperação"

trap - EXIT
echo "metrics-resilience: todos os checks passaram"
