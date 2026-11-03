#!/usr/bin/env bash
# Valida a fonte do Backend, prepara sua imagem e sobe o stack integrado
# (Postgres → db-bootstrap → migrate → backend, além das dependências).
# (compose/docker-compose.dev.yml).
#
# Uso (a partir de qualquer diretório):
#   scripts/up-dev.sh [--no-build]
#   BACKEND_BUILD_CONTEXT=../Backend_Java_Cliente scripts/up-dev.sh
#
# Pré-checagens: daemon Docker, env/.env.dev presente (segredos locais de
# dev), .env local do Radar presente (credenciais do R2 de teste — o arquivo
# NÃO é lido nem copiado), contexto Backend disponível e `config --quiet` verde.
# Depois: aguarda Loki/Vector/Prometheus/Grafana e RustFS, corrige attachment ausente,
# então faz build de uma imagem Backend (opcional via --no-build) e up -d
# --wait de toda a stack.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/compose/docker-compose.dev.yml"
ENV_FILE="$ROOT/env/.env.dev"
RADAR_ENV="$ROOT/../Radar_Middleware_Python/.env"
DEFAULT_BACKEND_SOURCE="$(realpath -e "$ROOT/../Backend_Java" 2>/dev/null || true)"
BACKEND_SOURCE_INPUT="${BACKEND_BUILD_CONTEXT:-$ROOT/../Backend_Java}"
if [[ "$BACKEND_SOURCE_INPUT" != /* ]]; then
  BACKEND_SOURCE_INPUT="$ROOT/$BACKEND_SOURCE_INPUT"
fi
BACKEND_SOURCE="$(realpath -e "$BACKEND_SOURCE_INPUT" 2>/dev/null || true)"
BACKEND_DEV_IMAGE="emporio-backend:dev"

BUILD_FLAG=("--build")
if [[ "${1:-}" == "--no-build" ]]; then
  BUILD_FLAG=()
elif [[ -n "${1:-}" ]]; then
  printf 'ERRO: argumento desconhecido: %s (uso: scripts/up-dev.sh [--no-build])\n' "$1" >&2
  exit 2
fi

fail() {
  echo "ERRO: $*" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || fail "docker não encontrado no PATH"
command -v git >/dev/null 2>&1 || fail "git não encontrado no PATH (necessário para identificar a fonte do build)"
command -v realpath >/dev/null 2>&1 || fail "realpath não encontrado no PATH"
docker info >/dev/null 2>&1 || fail "daemon Docker inacessível (suba o Docker / verifique o socket)"

[[ -f "$ENV_FILE" ]] || fail "faltando $ENV_FILE — rode: cp env/.env.dev.example env/.env.dev e preencha os segredos de dev (openssl rand)"
[[ -f "$RADAR_ENV" ]] || fail "faltando $RADAR_ENV — o serviço radar usa o .env local do repo Radar (credenciais do R2 de teste). Nunca copie este arquivo para cá."
[[ -n "$BACKEND_SOURCE" && -f "$BACKEND_SOURCE/Dockerfile" ]] \
  || fail "contexto Backend inválido ou sem Dockerfile: ${BACKEND_SOURCE_INPUT}"
[[ -d "$BACKEND_SOURCE/.git" || -f "$BACKEND_SOURCE/.git" ]] \
  || fail "contexto Backend não parece um checkout Git: $BACKEND_SOURCE"

git -C "$BACKEND_SOURCE" rev-parse --show-toplevel >/dev/null 2>&1 \
  || fail "não foi possível identificar o checkout Git do Backend"
BACKEND_BRANCH="$(git -C "$BACKEND_SOURCE" branch --show-current 2>/dev/null)"
BACKEND_SHA="$(git -C "$BACKEND_SOURCE" rev-parse --verify HEAD 2>/dev/null)" \
  || fail "não foi possível identificar o commit do Backend"
BACKEND_STATUS="$(git -C "$BACKEND_SOURCE" status --porcelain --untracked-files=normal 2>/dev/null)" \
  || fail "não foi possível consultar o estado local do Backend"
if [[ -n "$BACKEND_STATUS" ]]; then
  BACKEND_DIRTY="dirty ($(printf '%s\n' "$BACKEND_STATUS" | wc -l | tr -d ' ') entradas)"
else
  BACKEND_DIRTY="clean"
fi

export BACKEND_BUILD_CONTEXT="$BACKEND_SOURCE"
export BACKEND_DEV_IMAGE

echo "Backend build source: $BACKEND_SOURCE"
echo "Backend ref: branch=${BACKEND_BRANCH:-detached} sha=${BACKEND_SHA:0:12} state=$BACKEND_DIRTY"
if [[ -n "$DEFAULT_BACKEND_SOURCE" && "$BACKEND_SOURCE" == "$DEFAULT_BACKEND_SOURCE" \
  && "$BACKEND_BRANCH" == "main" && "$BACKEND_DIRTY" == "clean" ]]; then
  echo "Backend build classification: canônico (clone ../Backend_Java em main limpo)"
else
  echo "AVISO: Backend build de trabalho — não é a fonte canônica integrada de main."
fi
echo "Backend image tag: $BACKEND_DEV_IMAGE (tag local mutável; sem SHA manual no dev diário)"

for sibling in Backend_Java Front_Angular Radar_Middleware_Python; do
  if [[ "$sibling" == Backend_Java ]]; then
    [[ -n "$BACKEND_SOURCE" ]] || fail "repo/contexto Backend ausente"
  else
    [[ -d "$ROOT/../$sibling" ]] || fail "repo irmão ausente: ../$sibling (convenção: todos vizinhos sob Emporio_git/)"
  fi
done

compose() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

wait_for_job() {
  local service="$1" timeout_seconds="$2" started="$SECONDS" container state
  while (( SECONDS - started < timeout_seconds )); do
    container="$(compose ps -aq "$service")"
    if [[ -n "$container" ]]; then
      state="$(docker inspect --format '{{.State.Status}} {{.State.ExitCode}}' "$container" 2>/dev/null || true)"
      case "$state" in
        "exited 0")
          echo "Job $service concluiu com exit 0"
          return 0
          ;;
        exited\ *)
          fail "job $service terminou com $state; logs não são impressos automaticamente por higiene de segredos"
          ;;
      esac
    fi
    sleep 2
  done
  fail "timeout aguardando o job $service; logs não são impressos automaticamente por higiene de segredos"
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

if [[ ${#BUILD_FLAG[@]} -gt 0 ]]; then
  echo "==> construindo uma única imagem backend para migrate + backend"
  compose build backend
else
  echo "==> --no-build: usando a imagem local existente $BACKEND_DEV_IMAGE"
  echo "AVISO: branch/SHA acima descrevem o checkout selecionado, não comprovam a origem da imagem reutilizada."
  docker image inspect "$BACKEND_DEV_IMAGE" >/dev/null 2>&1 \
    || fail "imagem local ausente: $BACKEND_DEV_IMAGE (remova --no-build para construí-la)"
fi

echo "==> subindo e aguardando observabilidade local"
compose up -d --wait --wait-timeout 120 loki vector prometheus grafana

echo "==> subindo e aguardando RustFS antes do bootstrap dependente"
compose up -d --wait --wait-timeout 120 rustfs
ensure_rustfs_network

# Começa explicitamente pela database; jobs one-shot são aguardados por exit
# code, não por `up --wait` (que trata um container concluído como não-running).
echo "==> iniciando Postgres e aguardando healthy"
compose up -d --wait --wait-timeout 120 postgres

# Remover containers parados dos jobs força execução nova (credenciais e/ou
# banco greenfield alterados), sem remover volumes nem dados.
echo "==> removendo somente containers one-shot anteriores"
compose rm -f db-bootstrap migrate rustfs-init >/dev/null 2>&1 || true

echo "==> iniciando stack; depends_on ordena bootstrap → migrate → backend"
compose up -d
wait_for_job db-bootstrap 120
wait_for_job migrate 600
wait_for_job rustfs-init 120

# `--no-deps` exclui os jobs one-shot já verificados. `--wait` agora se aplica
# apenas aos serviços long-lived com healthcheck.
compose up -d --no-deps --wait --wait-timeout 600 \
  postgres backend radar rustfs mailpit media-gateway loki vector prometheus grafana front-dev

echo "==> seed do admin de dev (idempotente)"
bash "$ROOT/scripts/seed-admin-dev.sh" | tail -3

echo
compose ps
echo
echo "Stack de dev pronto. Smoke: scripts/smoke.sh"
echo "Front: http://localhost:4200 | API: http://localhost:8080 (management 8081 somente na metrics-net)"
MEDIA_GATEWAY_BIND="$(compose port media-gateway 80 2>/dev/null || true)"
echo "Media pública: http://${MEDIA_GATEWAY_BIND:-127.0.0.1:9002}/public/asset/"
echo "Mailpit (emails): http://localhost:8025 | RustFS console: http://localhost:9001"
echo "Grafana (logs + métricas): http://127.0.0.1:${GRAFANA_PORT:-3000}"
