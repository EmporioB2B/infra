#!/usr/bin/env bash
# Integra bootstrap canônico + runner Flyway + datasource Java sem tocar no
# volume persistente do Compose. PostgreSQL usa tmpfs; container e rede são
# descartáveis. Uso:
# scripts/smoke-db-migration-runner.sh [imagem-backend] [postgres:16-alpine|postgres:17-alpine]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROLES_SQL="$ROOT/database/bootstrap/roles.sql"
IMAGE="${1:-emporio-backend:dev}"
PG_IMAGE="${2:-postgres:16-alpine}"
PG_NAME="emporio-db-runner-pg-$$"
RUNTIME_NAME="emporio-db-runner-app-$$"
NETWORK="emporio-db-runner-net-$$"

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || fail "docker não encontrado"
command -v openssl >/dev/null 2>&1 || fail "openssl não encontrado"
docker info >/dev/null 2>&1 || fail "daemon Docker inacessível"
[[ -r "$ROLES_SQL" ]] || fail "bootstrap canônico ausente"
docker image inspect "$IMAGE" >/dev/null 2>&1 || fail "imagem Backend local ausente: $IMAGE (construa o Backend antes do smoke)"
case "$PG_IMAGE" in
  postgres:16-alpine|postgres:17-alpine) ;;
  *) fail "PostgreSQL permitido: postgres:16-alpine ou postgres:17-alpine" ;;
esac

POSTGRES_ADMIN_PASSWORD="$(openssl rand -hex 32)"
EMPORIO_APP_PASSWORD="$(openssl rand -hex 32)"
EMPORIO_MIGRATOR_PASSWORD="$(openssl rand -hex 32)"
POSTGRES_PASSWORD="$POSTGRES_ADMIN_PASSWORD"
export POSTGRES_ADMIN_PASSWORD POSTGRES_PASSWORD EMPORIO_APP_PASSWORD EMPORIO_MIGRATOR_PASSWORD

cleanup() {
  docker rm -f "$RUNTIME_NAME" "$PG_NAME" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$NETWORK" >/dev/null
docker run -d --rm --name "$PG_NAME" --network "$NETWORK" \
  --network-alias postgres \
  --tmpfs /var/lib/postgresql/data:rw,noexec,nosuid,size=512m \
  -v "$ROLES_SQL:/bootstrap/roles.sql:ro" \
  -e POSTGRES_DB=emporio \
  -e POSTGRES_USER=phase2_admin \
  -e POSTGRES_PASSWORD \
  -e POSTGRES_HOST_AUTH_METHOD=scram-sha-256 \
  "$PG_IMAGE" >/dev/null

ready=0
for _ in $(seq 1 60); do
  if docker exec "$PG_NAME" pg_isready -q -h 127.0.0.1 -U phase2_admin -d emporio >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
[[ "$ready" == 1 ]] || fail "PostgreSQL descartável não ficou pronto"

admin_psql() {
  PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" docker exec -i \
    -e PGPASSWORD -e EMPORIO_APP_PASSWORD -e EMPORIO_MIGRATOR_PASSWORD \
    "$PG_NAME" psql -X -q -v ON_ERROR_STOP=1 -h 127.0.0.1 \
    -U phase2_admin -d emporio "$@"
}

printf '%s\n' '==> PostgreSQL descartável em tmpfs; aplicando roles canônicas'
admin_psql < "$ROLES_SQL"
if ! admin_psql >/dev/null 2>&1 <<'SQL'
\getenv app_password EMPORIO_APP_PASSWORD
\getenv migrator_password EMPORIO_MIGRATOR_PASSWORD
ALTER ROLE emporio_app PASSWORD :'app_password';
ALTER ROLE emporio_migrador PASSWORD :'migrator_password';
SQL
then
  fail "não foi possível configurar credenciais sintéticas"
fi

APP_URL='jdbc:postgresql://postgres:5432/emporio?currentSchema=public,identidade,catalogo,mercadoria,comercial,infraestrutura,venda,pedidos,financeiro,fiscal,relatorio'
SPRING_FLYWAY_URL="$APP_URL"
SPRING_FLYWAY_USER=emporio_migrador
SPRING_FLYWAY_PASSWORD="$EMPORIO_MIGRATOR_PASSWORD"
export SPRING_FLYWAY_URL SPRING_FLYWAY_USER SPRING_FLYWAY_PASSWORD
printf '%s\n' '==> executando runner Flyway one-shot'
docker run --rm --network "$NETWORK" --name "${PG_NAME}-migrate" \
  -e SPRING_FLYWAY_URL -e SPRING_FLYWAY_USER -e SPRING_FLYWAY_PASSWORD \
  "$IMAGE" migrate

v10="$(admin_psql -At -c "SELECT EXISTS (SELECT 1 FROM public.flyway_schema_history WHERE version='10' AND success)")"
[[ "$v10" == t ]] || fail "V10 não consta como aplicada com sucesso"
printf '%s\n' 'PASS migration: V1–V10 aplicadas; histórico Flyway registra V10'

runtime_network_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$PG_NAME")"
[[ -n "$runtime_network_ip" ]] || fail "IP do container PostgreSQL não disponível"
APP_JWT_SECRET="$(openssl rand -hex 32)"
SPRING_DATASOURCE_PASSWORD="$EMPORIO_APP_PASSWORD"
export APP_JWT_SECRET SPRING_DATASOURCE_PASSWORD

docker run -d --name "$RUNTIME_NAME" --network "container:$PG_NAME" \
  -e SPRING_PROFILES_ACTIVE=dev,container \
  -e 'SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/emporio?currentSchema=identidade,catalogo,mercadoria,comercial,infraestrutura,venda,pedidos' \
  -e SPRING_DATASOURCE_USERNAME=emporio_app \
  -e SPRING_DATASOURCE_PASSWORD \
  -e SPRING_FLYWAY_ENABLED=false \
  -e SPRING_FLYWAY_URL= \
  -e SPRING_FLYWAY_USER= \
  -e SPRING_FLYWAY_PASSWORD= \
  -e POSTGRES_ADMIN_PASSWORD= \
  -e APP_JWT_SECRET \
  -e APP_CORS_ALLOWED_ORIGINS=http://localhost:4200 \
  -e RADAR_BASE_URL=http://radar:8000 \
  -e MANAGEMENT_SERVER_ADDRESS="$runtime_network_ip" \
  -e APP_EMAIL_ENABLED=false \
  -e APP_EMAIL_HEALTH_ENABLED=false \
  -e APP_STORAGE_PROVIDER=DISABLED \
  "$IMAGE" >/dev/null

healthy=0
for _ in $(seq 1 60); do
  if docker exec "$RUNTIME_NAME" curl --fail --silent --show-error --max-time 2 \
    "http://$runtime_network_ip:8081/actuator/health" >/dev/null 2>&1; then
    healthy=1
    break
  fi
  sleep 1
done
[[ "$healthy" == 1 ]] || fail "Backend não ficou healthy como runtime"

runtime_identity="$(PGPASSWORD="$EMPORIO_APP_PASSWORD" docker exec -i -e PGPASSWORD \
  "$PG_NAME" psql -X -q -v ON_ERROR_STOP=1 -h 127.0.0.1 \
  -U emporio_app -d emporio -At -c "SELECT current_user || chr(58) || (SELECT count(*) FROM identidade.usuario)")"
[[ "$runtime_identity" == emporio_app:* ]] \
  || fail "conexão de prova não autenticou como emporio_app ou não acessou identidade.usuario"

runtime_session="$(admin_psql -At -c "SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_stat_activity WHERE datname=current_database() AND usename='emporio_app' AND pid <> pg_backend_pid())")"
[[ "$runtime_session" == t ]] || fail "não observada sessão PostgreSQL do Backend como emporio_app"

if PGPASSWORD="$EMPORIO_APP_PASSWORD" docker exec -i -e PGPASSWORD "$PG_NAME" \
  psql -X -q -v ON_ERROR_STOP=1 -h 127.0.0.1 -U emporio_app -d emporio \
  -c 'CREATE TABLE public.infra_phase2_runtime_ddl_probe (id integer)' >/dev/null 2>&1; then
  fail "emporio_app executou DDL inesperadamente"
fi

privileges="$(admin_psql -At -c "SELECT NOT pg_catalog.pg_has_role('emporio_app','emporio_owner','SET') AND NOT pg_catalog.has_table_privilege('emporio_app','identidade.usuario','TRUNCATE')")"
[[ "$privileges" == t ]] || fail "emporio_app tem membership owner ou privilégio TRUNCATE"

printf '%s\n' 'PASS runtime: API healthy, sessão Java em emporio_app e leitura de identidade.usuario'
printf '%s\n' 'PASS runtime: DDL, TRUNCATE e SET ROLE emporio_owner negados'
printf 'smoke-db-migration-runner: passou (%s tmpfs; segredos efêmeros; nenhum volume persistente)\n' "$PG_IMAGE"
