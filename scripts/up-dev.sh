#!/usr/bin/env bash
# Bootstrap RustFS e sobe o stack de desenvolvimento integrado
# (compose/docker-compose.dev.yml).
#
# Uso (a partir de qualquer diretório):
#   scripts/up-dev.sh [--no-build]
#
# Pré-checagens: daemon Docker, env/.env.dev presente (segredos locais de
# dev), .env local do Radar presente (credenciais do R2 de teste — o arquivo
# NÃO é lido nem copiado), repos irmãos vizinhos e `config --quiet` verde.
# Depois: aguarda Loki/Vector/Grafana e RustFS, corrige attachment ausente,
# então faz build (opcional via --no-build) + up -d --wait de toda a stack.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/compose/docker-compose.dev.yml"
ENV_FILE="$ROOT/env/.env.dev"
RADAR_ENV="$ROOT/../Radar_Middleware_Python/.env"

BUILD_FLAG=("--build")
if [[ "${1:-}" == "--no-build" ]]; then
  BUILD_FLAG=()
fi

fail() {
  echo "ERRO: $*" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || fail "docker não encontrado no PATH"
docker info >/dev/null 2>&1 || fail "daemon Docker inacessível (suba o Docker / verifique o socket)"

[[ -f "$ENV_FILE" ]] || fail "faltando $ENV_FILE — rode: cp env/.env.dev.example env/.env.dev e preencha os segredos de dev (openssl rand)"
[[ -f "$RADAR_ENV" ]] || fail "faltando $RADAR_ENV — o serviço radar usa o .env local do repo Radar (credenciais do R2 de teste). Nunca copie este arquivo para cá."

for sibling in Backend_Java Front_Angular Radar_Middleware_Python; do
  [[ -d "$ROOT/../$sibling" ]] || fail "repo irmão ausente: ../$sibling (convenção: todos vizinhos sob Emporio_git/)"
done

compose() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

rustfs_network_name() {
  local container_id project_name
  container_id="$(compose ps -q rustfs)"
  [[ -n "$container_id" ]] || return 1
  project_name="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$container_id")"
  [[ -n "$project_name" ]] || return 1
  printf '%s_default\n' "$project_name"
}

rustfs_has_expected_network() {
  local container_id network_name attached
  container_id="$(compose ps -q rustfs)"
  [[ -n "$container_id" ]] || return 1
  network_name="$(rustfs_network_name)" || return 1
  attached="$(docker inspect --format "{{if index .NetworkSettings.Networks \"$network_name\"}}yes{{else}}no{{end}}" "$container_id")"
  [[ "$attached" == "yes" ]]
}

ensure_rustfs_network() {
  local network_name
  network_name="$(rustfs_network_name)" || fail "não foi possível identificar o projeto Compose do serviço rustfs"

  if rustfs_has_expected_network; then
    echo "RustFS conectado à rede $network_name"
    return
  fi

  echo "AVISO: RustFS sem attachment em $network_name; recriando somente o container (o volume rustfs-data será preservado)." >&2
  compose up -d --no-deps --force-recreate --wait --wait-timeout 120 rustfs \
    || fail "não foi possível recriar/aguardar o serviço rustfs"
  rustfs_has_expected_network \
    || fail "rustfs continua sem attachment em $network_name após uma recriação"
  echo "RustFS reconectado à rede $network_name"
}

echo "==> certificando TLS dev do Mailpit (idempotente)"
bash "$ROOT/scripts/gen-dev-certs.sh"

echo "==> validando compose (config --quiet)"
compose config --quiet

echo "==> subindo e aguardando observabilidade local"
compose up -d --wait --wait-timeout 120 loki vector grafana

echo "==> subindo e aguardando RustFS antes do bootstrap dependente"
compose up -d "${BUILD_FLAG[@]}" --wait --wait-timeout 120 rustfs
ensure_rustfs_network

echo "==> up -d ${BUILD_FLAG[*]} com espera por todos healthy (--wait)"
# `up --wait` retorna somente quando todos os healthchecks ficam healthy.
# start_period do radar (90s, sincroniza SQLite do R2) + backend (Flyway)
# exigem timeout generoso.
if compose up -d "${BUILD_FLAG[@]}" --wait --wait-timeout 600; then
  :
else
  status=$?
  echo "ERRO: stack não ficou saudável; logs recentes do rustfs-init:" >&2
  compose logs --no-color --tail=100 rustfs-init >&2 || true
  exit "$status"
fi

echo "==> seed do admin de dev (idempotente)"
bash "$ROOT/scripts/seed-admin-dev.sh" | tail -3

echo
compose ps
echo
echo "Stack de dev pronto. Smoke: scripts/smoke.sh"
echo "Front: http://localhost:4200 | API: http://localhost:8080 (actuator 8081)"
MEDIA_GATEWAY_BIND="$(compose port media-gateway 80 2>/dev/null || true)"
echo "Media pública: http://${MEDIA_GATEWAY_BIND:-127.0.0.1:9002}/public/asset/"
echo "Mailpit (emails): http://localhost:8025 | RustFS console: http://localhost:9001"
echo "Grafana (logs): http://127.0.0.1:${GRAFANA_PORT:-3000}"
