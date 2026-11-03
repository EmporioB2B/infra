#!/usr/bin/env bash
# Smoke isolado de roles/credenciais. Sobe PostgreSQL descartável com tmpfs;
# não conecta ao Compose persistente nem a Supabase/prod.
# Uso: scripts/smoke-db-roles.sh [postgres:16-alpine|postgres:17-alpine]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_SQL="$ROOT/database/bootstrap/roles.sql"
IMAGE="${1:-postgres:16-alpine}"
case "$IMAGE" in
  postgres:16-alpine|postgres:17-alpine) ;;
  *) printf '%s\n' 'Uso: scripts/smoke-db-roles.sh [postgres:16-alpine|postgres:17-alpine]' >&2; exit 2 ;;
esac

command -v docker >/dev/null 2>&1 || { printf '%s\n' 'ERRO: docker não encontrado' >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { printf '%s\n' 'ERRO: openssl não encontrado' >&2; exit 1; }
docker info >/dev/null 2>&1 || { printf '%s\n' 'ERRO: daemon Docker inacessível' >&2; exit 1; }
[[ -r "$BOOTSTRAP_SQL" ]] || { printf '%s\n' 'ERRO: bootstrap SQL ausente' >&2; exit 1; }

NAME="emporio-db-roles-smoke-$$"
if docker container inspect "$NAME" >/dev/null 2>&1; then
  printf '%s\n' 'ERRO: nome de container temporário já está em uso' >&2
  exit 1
fi

POSTGRES_PASSWORD="$(openssl rand -hex 32)"
EMPORIO_APP_TEST_PASSWORD="$(openssl rand -hex 32)"
EMPORIO_MIGRATOR_TEST_PASSWORD="$(openssl rand -hex 32)"
HUMAN_READ_TEST_PASSWORD="$(openssl rand -hex 32)"
HUMAN_MAINT_TEST_PASSWORD="$(openssl rand -hex 32)"
WRONG_TEST_PASSWORD="$(openssl rand -hex 32)"
export POSTGRES_PASSWORD EMPORIO_APP_TEST_PASSWORD EMPORIO_MIGRATOR_TEST_PASSWORD
export HUMAN_READ_TEST_PASSWORD HUMAN_MAINT_TEST_PASSWORD WRONG_TEST_PASSWORD

credentials=(
  "$POSTGRES_PASSWORD" "$EMPORIO_APP_TEST_PASSWORD"
  "$EMPORIO_MIGRATOR_TEST_PASSWORD" "$HUMAN_READ_TEST_PASSWORD"
  "$HUMAN_MAINT_TEST_PASSWORD" "$WRONG_TEST_PASSWORD"
)
for ((i = 0; i < ${#credentials[@]}; i++)); do
  for ((j = i + 1; j < ${#credentials[@]}; j++)); do
    if [[ "${credentials[i]}" == "${credentials[j]}" ]]; then
      printf '%s\n' 'ERRO: gerador produziu credenciais repetidas' >&2
      exit 1
    fi
  done
done

cleanup() {
  if [[ -n "${HUMAN_SESSION_PID:-}" ]]; then
    kill "$HUMAN_SESSION_PID" >/dev/null 2>&1 || true
    wait "$HUMAN_SESSION_PID" >/dev/null 2>&1 || true
  fi
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --rm --name "$NAME" \
  --tmpfs /var/lib/postgresql/data:rw,noexec,nosuid,size=256m \
  -e POSTGRES_DB=emporio \
  -e POSTGRES_USER=infra_smoke_admin \
  -e POSTGRES_PASSWORD \
  -e POSTGRES_HOST_AUTH_METHOD=scram-sha-256 \
  "$IMAGE" >/dev/null

DB_HOST="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NAME")"
[[ -n "$DB_HOST" ]] || { printf '%s\n' 'ERRO: não foi possível obter IP do PostgreSQL descartável' >&2; exit 1; }

ready=0
for _ in $(seq 1 40); do
  if docker exec "$NAME" pg_isready -q -h "$DB_HOST" -U infra_smoke_admin -d emporio >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
[[ "$ready" == 1 ]] || { printf '%s\n' 'ERRO: PostgreSQL descartável não ficou pronto' >&2; exit 1; }

admin_psql() {
  PGPASSWORD="$POSTGRES_PASSWORD" docker exec -i -e PGPASSWORD "$NAME" \
    psql -X -q -v ON_ERROR_STOP=1 -h "$DB_HOST" -U infra_smoke_admin -d emporio "$@"
}

admin_psql_with_test_secrets() {
  PGPASSWORD="$POSTGRES_PASSWORD" docker exec -i \
    -e PGPASSWORD \
    -e EMPORIO_APP_TEST_PASSWORD \
    -e EMPORIO_MIGRATOR_TEST_PASSWORD \
    -e HUMAN_READ_TEST_PASSWORD \
    -e HUMAN_MAINT_TEST_PASSWORD \
    "$NAME" \
    psql -X -q -v ON_ERROR_STOP=1 -h "$DB_HOST" -U infra_smoke_admin -d emporio
}

role_psql() {
  local username="$1" password_var="$2"
  shift 2
  PGPASSWORD="${!password_var}" docker exec -i -e PGPASSWORD "$NAME" \
    psql -X -q -v ON_ERROR_STOP=1 -h "$DB_HOST" -U "$username" -d emporio "$@"
}

printf '==> PostgreSQL descartável (%s)\n' "$IMAGE"
printf '%s\n' '==> aplicando bootstrap e verificando reconciliação de membership'
admin_psql < "$BOOTSTRAP_SQL"
admin_psql -c 'REVOKE emporio_owner FROM emporio_migrador'
admin_psql -c 'GRANT emporio_owner TO emporio_migrador WITH ADMIN TRUE, INHERIT TRUE, SET TRUE'
admin_psql < "$BOOTSTRAP_SQL"
admin_psql < "$BOOTSTRAP_SQL"

if ! admin_psql_with_test_secrets >/dev/null 2>&1 <<'SQL'
\getenv app_password EMPORIO_APP_TEST_PASSWORD
\getenv migrator_password EMPORIO_MIGRATOR_TEST_PASSWORD
ALTER ROLE emporio_app PASSWORD :'app_password';
ALTER ROLE emporio_migrador PASSWORD :'migrator_password';
SQL
then
  printf '%s\n' 'ERRO: não foi possível preparar credenciais no banco descartável' >&2
  exit 1
fi

role_state="$(admin_psql -At -F '|' -c "
  SELECT owner.rolcanlogin = false
     AND migrator.rolcanlogin = true
     AND app.rolcanlogin = true
     AND owner.rolsuper = false AND migrator.rolsuper = false AND app.rolsuper = false
     AND owner.rolcreatedb = false AND migrator.rolcreatedb = false AND app.rolcreatedb = false
     AND owner.rolcreaterole = false AND migrator.rolcreaterole = false AND app.rolcreaterole = false
     AND pg_catalog.pg_has_role('emporio_migrador', 'emporio_owner', 'SET')
     AND NOT pg_catalog.pg_has_role('emporio_app', 'emporio_owner', 'SET')
  FROM pg_catalog.pg_roles owner
  CROSS JOIN pg_catalog.pg_roles migrator
  CROSS JOIN pg_catalog.pg_roles app
  WHERE owner.rolname = 'emporio_owner'
    AND migrator.rolname = 'emporio_migrador'
    AND app.rolname = 'emporio_app';")"
[[ "$role_state" == t ]] || { printf '%s\n' 'ERRO: atributos/membership das roles divergiram do contrato' >&2; exit 1; }

membership_state="$(admin_psql -At -c "
  SELECT set_option AND NOT inherit_option AND NOT admin_option
  FROM pg_catalog.pg_auth_members
  WHERE roleid = 'emporio_owner'::regrole
    AND member = 'emporio_migrador'::regrole;")"
[[ "$membership_state" == t ]] || { printf '%s\n' 'ERRO: membership migrador→owner incorreta' >&2; exit 1; }

for spec in 'emporio_app:EMPORIO_APP_TEST_PASSWORD' 'emporio_migrador:EMPORIO_MIGRATOR_TEST_PASSWORD'; do
  IFS=: read -r username password_var <<< "$spec"
  actual="$(role_psql "$username" "$password_var" -At -c 'SELECT current_user')"
  [[ "$actual" == "$username" ]] || { printf 'ERRO: login %s não autenticou como a role esperada\n' "$username" >&2; exit 1; }
  printf 'PASS login PostgreSQL: %s\n' "$username"
done

if role_psql emporio_app WRONG_TEST_PASSWORD -At -c 'SELECT 1' >/dev/null 2>&1; then
  printf '%s\n' 'ERRO: senha inválida autenticou em emporio_app' >&2
  exit 1
fi
printf '%s\n' 'PASS senha inválida rejeitada; valores de credencial não foram exibidos'

owner_identity="$(role_psql emporio_migrador EMPORIO_MIGRATOR_TEST_PASSWORD -At <<'SQL'
SET ROLE emporio_owner;
CREATE SCHEMA infra_owner_probe;
CREATE TABLE infra_owner_probe.migration_owner_probe (id integer PRIMARY KEY);
SELECT session_user = 'emporio_migrador' AND current_user = 'emporio_owner';
SQL
)"
[[ "$owner_identity" == t ]] || { printf '%s\n' 'ERRO: identidade efetiva do migrador/owner incorreta' >&2; exit 1; }

object_owner="$(admin_psql -At -c "
  SELECT r.rolname
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_catalog.pg_roles r ON r.oid = c.relowner
  WHERE n.nspname = 'infra_owner_probe'
    AND c.relname = 'migration_owner_probe';")"
[[ "$object_owner" == emporio_owner ]] || { printf '%s\n' 'ERRO: objeto de migration não pertence a emporio_owner' >&2; exit 1; }
printf '%s\n' 'PASS SET ROLE e ownership efetivo do objeto de migration'

if role_psql emporio_app EMPORIO_APP_TEST_PASSWORD -At -c 'SET ROLE emporio_owner' >/dev/null 2>&1; then
  printf '%s\n' 'ERRO: emporio_app conseguiu assumir emporio_owner' >&2
  exit 1
fi
if role_psql emporio_app EMPORIO_APP_TEST_PASSWORD -At -c 'CREATE TABLE public.infra_app_ddl_denied (id integer)' >/dev/null 2>&1; then
  printf '%s\n' 'ERRO: emporio_app conseguiu executar CREATE em public' >&2
  exit 1
fi
app_truncate="$(admin_psql -At -c "SELECT pg_catalog.has_table_privilege('emporio_app', 'infra_owner_probe.migration_owner_probe', 'TRUNCATE')")"
[[ "$app_truncate" == f ]] || { printf '%s\n' 'ERRO: emporio_app tem privilégio TRUNCATE' >&2; exit 1; }
printf '%s\n' 'PASS runtime sem SET ROLE owner, CREATE em public ou privilégio TRUNCATE'

# Fixtures humanas existem somente neste banco descartável. Elas não definem
# grants nem nomes de roles humanas de produção.
admin_psql <<'SQL'
CREATE ROLE infra_smoke_human_read NOLOGIN;
CREATE ROLE infra_smoke_human_maint NOLOGIN;
CREATE ROLE infra_smoke_reader LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE infra_smoke_maint LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE;
GRANT infra_smoke_human_read TO infra_smoke_reader WITH ADMIN FALSE, INHERIT TRUE, SET FALSE;
GRANT infra_smoke_human_maint TO infra_smoke_maint WITH ADMIN FALSE, INHERIT TRUE, SET FALSE;
SET ROLE emporio_owner;
CREATE TABLE infra_owner_probe.human_access_probe (value integer NOT NULL);
INSERT INTO infra_owner_probe.human_access_probe VALUES (1);
RESET ROLE;
GRANT USAGE ON SCHEMA infra_owner_probe TO infra_smoke_human_read, infra_smoke_human_maint;
GRANT SELECT ON infra_owner_probe.human_access_probe TO infra_smoke_human_read;
GRANT SELECT, UPDATE ON infra_owner_probe.human_access_probe TO infra_smoke_human_maint;
SQL

if ! admin_psql_with_test_secrets >/dev/null 2>&1 <<'SQL'
\getenv human_read_password HUMAN_READ_TEST_PASSWORD
\getenv human_maint_password HUMAN_MAINT_TEST_PASSWORD
ALTER ROLE infra_smoke_reader PASSWORD :'human_read_password';
ALTER ROLE infra_smoke_maint PASSWORD :'human_maint_password';
SQL
then
  printf '%s\n' 'ERRO: não foi possível preparar logins humanos descartáveis' >&2
  exit 1
fi

human_read="$(role_psql infra_smoke_reader HUMAN_READ_TEST_PASSWORD -At -c 'SELECT count(*) FROM infra_owner_probe.human_access_probe')"
[[ "$human_read" == 1 ]] || { printf '%s\n' 'ERRO: operador de leitura não leu a fixture' >&2; exit 1; }
if role_psql infra_smoke_reader HUMAN_READ_TEST_PASSWORD -At -c 'UPDATE infra_owner_probe.human_access_probe SET value = 2' >/dev/null 2>&1; then
  printf '%s\n' 'ERRO: operador de leitura conseguiu escrever' >&2
  exit 1
fi
maint_update="$(role_psql infra_smoke_maint HUMAN_MAINT_TEST_PASSWORD -At -c 'UPDATE infra_owner_probe.human_access_probe SET value = 2 RETURNING value')"
[[ "$maint_update" == 2 ]] || { printf '%s\n' 'ERRO: operador de manutenção não executou a ação sintética permitida' >&2; exit 1; }
printf '%s\n' 'PASS logins humanos efêmeros: leitura restrita e manutenção sintética separadas'

# Mantém uma sessão humana sintética para provar que o administrador do banco
# descartável consegue encerrá-la antes de desabilitar o login.
PGPASSWORD="$HUMAN_MAINT_TEST_PASSWORD" PGAPPNAME=infra-smoke-human-revoke \
  docker exec -e PGPASSWORD -e PGAPPNAME "$NAME" \
  psql -X -q -h "$DB_HOST" -U infra_smoke_maint -d emporio -c 'SELECT pg_sleep(30)' \
  >/dev/null 2>&1 &
HUMAN_SESSION_PID=$!
activity_pid=""
for _ in $(seq 1 20); do
  activity_pid="$(admin_psql -At -c "SELECT pid FROM pg_catalog.pg_stat_activity WHERE application_name = 'infra-smoke-human-revoke' AND usename = 'infra_smoke_maint' LIMIT 1")"
  [[ -n "$activity_pid" ]] && break
  sleep 0.25
done
[[ "$activity_pid" =~ ^[0-9]+$ ]] || { printf '%s\n' 'ERRO: sessão humana sintética não apareceu em pg_stat_activity' >&2; exit 1; }
terminated="$(admin_psql -At -c "SELECT pg_catalog.pg_terminate_backend($activity_pid)")"
[[ "$terminated" == t ]] || { printf '%s\n' 'ERRO: sessão humana sintética não foi terminada' >&2; exit 1; }
if wait "$HUMAN_SESSION_PID" >/dev/null 2>&1; then
  printf '%s\n' 'ERRO: sessão continuou após pg_terminate_backend' >&2
  exit 1
fi
HUMAN_SESSION_PID=""
admin_psql <<'SQL'
ALTER ROLE infra_smoke_reader NOLOGIN;
ALTER ROLE infra_smoke_maint NOLOGIN;
REVOKE infra_smoke_human_read FROM infra_smoke_reader;
REVOKE infra_smoke_human_maint FROM infra_smoke_maint;
SQL
for spec in 'infra_smoke_reader:HUMAN_READ_TEST_PASSWORD' 'infra_smoke_maint:HUMAN_MAINT_TEST_PASSWORD'; do
  IFS=: read -r username password_var <<< "$spec"
  if role_psql "$username" "$password_var" -At -c 'SELECT 1' >/dev/null 2>&1; then
    printf 'ERRO: login revogado ainda autentica: %s\n' "$username" >&2
    exit 1
  fi
done
printf '%s\n' 'PASS sessão humana terminada e logins efêmeros revogados'
printf '%s\n' 'smoke-db-roles: passou (somente banco descartável; nenhum segredo exibido)'
