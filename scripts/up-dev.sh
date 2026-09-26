#!/usr/bin/env bash
# Subi o stack de desenvolvimento integrado (compose/docker-compose.dev.yml).
#
# Uso (a partir de qualquer diretório):
#   scripts/up-dev.sh [--no-build]
#
# Pré-checagens: daemon Docker, env/.env.dev presente (segredos locais de
# dev), .env local do Radar presente (credenciais do R2 de teste — o arquivo
# NÃO é lido nem copiado), repos irmãos vizinhos e `config --quiet` verde.
# Depois: build (opcional via --no-build) + up -d --wait, que só retorna com
# TODOS os serviços healthy (ou falha com código != 0).
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

echo "==> certificando TLS dev do Mailpit (idempotente)"
bash "$ROOT/scripts/gen-dev-certs.sh"

echo "==> validando compose (config --quiet)"
compose config --quiet

echo "==> up -d ${BUILD_FLAG[*]} com espera por todos healthy (--wait)"
# `up --wait` retorna somente quando todos os healthchecks ficam healthy.
# start_period do radar (90s, sincroniza SQLite do R2) + backend (Flyway)
# exigem timeout generoso.
compose up -d "${BUILD_FLAG[@]}" --wait --wait-timeout 600

echo "==> seed do admin de dev (idempotente)"
bash "$ROOT/scripts/seed-admin-dev.sh" | tail -3

echo
compose ps
echo
echo "Stack de dev pronto. Smoke: scripts/smoke.sh"
echo "Front: http://localhost:4200 | API: http://localhost:8080 (actuator 8081)"
echo "Mailpit (emails): http://localhost:8025 | RustFS console: http://localhost:9001"
