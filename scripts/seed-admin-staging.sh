#!/usr/bin/env bash
# Seed manual e idempotente do admin inicial no PostgreSQL do Compose staging.
# Nao faz parte do bootstrap/migration e nao deve ser usado em producao.
set -euo pipefail

readonly PROJECT='emporio-staging'
readonly SERVICE='postgres'
readonly ADMIN_EMAIL='admin@emporiob2b.com.br'
readonly ADMIN_NOME='Admin Emporio B2B'
readonly ADMIN_USER_ID='00000000-0000-4000-8000-0000000000aa'
readonly ADMIN_VINCULO_ID='00000000-0000-4000-8000-0000000000ab'
readonly ADMIN_PLATFORM_ID='00000000-0000-4000-8000-000000000001'

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

[[ "${1:-}" == '--confirm-staging' && $# == 1 ]] \
  || fail 'uso: scripts/seed-admin-staging.sh --confirm-staging (somente staging)'
command -v docker >/dev/null 2>&1 || fail 'docker nao encontrado'
docker info >/dev/null 2>&1 || fail 'daemon Docker inacessivel'

mapfile -t service_containers < <(docker ps \
  --filter "label=com.docker.compose.service=$SERVICE" \
  --format '{{.ID}}')
containers=()
for candidate in "${service_containers[@]}"; do
  project="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$candidate")"
  name="$(docker inspect --format '{{.Name}}' "$candidate")"
  name="${name#/}"
  # Dokploy pode acrescentar um sufixo ao projeto Compose (ex.: -elh12i).
  # Aceita o nome base ou esse formato gerado, mantendo serviço e DB verificados.
  if [[ "$project" == "$PROJECT" || "$project" == "$PROJECT-"* \
        || "$name" == "$PROJECT-"*"-postgres-1" ]]; then
    database="$(docker inspect --format '{{range .Config.Env}}{{if eq . "POSTGRES_DB=emporio"}}yes{{end}}{{end}}' "$candidate")"
    [[ "$database" == yes ]] && containers+=("$candidate")
  fi
done
[[ ${#containers[@]} -eq 1 ]] \
  || fail "esperava exatamente um container Postgres de staging ($PROJECT/$SERVICE ou nome Dokploy equivalente) healthy; encontrados: ${#containers[@]}"
container="${containers[0]}"
health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$container")"
[[ "$health" == healthy ]] || fail "Postgres de staging nao esta healthy (estado: $health)"

printf 'Destino: projeto Compose %s, servico %s.\n' "$PROJECT" "$SERVICE"
printf 'Esta operacao cria/atualiza %s com privilegios administrativos de PLATAFORMA.\n' "$ADMIN_EMAIL"
read -r -p 'Digite staging para confirmar: ' confirmation
[[ "$confirmation" == staging ]] || fail 'confirmacao nao corresponde; nenhuma alteracao feita'

read -r -s -p 'Senha inicial do admin: ' ADMIN_PASSWORD
printf '\n'
read -r -s -p 'Confirme a senha: ' ADMIN_PASSWORD_CONFIRM
printf '\n'
[[ -n "$ADMIN_PASSWORD" && "$ADMIN_PASSWORD" == "$ADMIN_PASSWORD_CONFIRM" ]] \
  || fail 'senhas vazias ou diferentes'
unset ADMIN_PASSWORD_CONFIRM

# O Backend usa BCrypt com custo 12. A senha nao e passada em argv nem impressa.
if command -v htpasswd >/dev/null 2>&1; then
  HASH="$(printf '%s\n' "$ADMIN_PASSWORD" | htpasswd -niBC 12 x \
    | cut -d: -f2 | tr -d '\r\n' | sed 's|^\$2y\$|\$2b\$|')"
elif python3 -c 'import bcrypt' >/dev/null 2>&1; then
  HASH="$(ADMIN_PASSWORD="$ADMIN_PASSWORD" python3 -c \
    'import os,bcrypt; print(bcrypt.hashpw(os.environ["ADMIN_PASSWORD"].encode(), bcrypt.gensalt(12)).decode())')"
else
  unset ADMIN_PASSWORD
  fail 'instale htpasswd ou python3 com o modulo bcrypt para gerar BCrypt custo 12'
fi
unset ADMIN_PASSWORD
[[ "$HASH" =~ ^\$2[aby]\$12\$[./A-Za-z0-9]{53}$ ]] || fail 'hash BCrypt gerado tem formato inesperado'

# PSQL recebe SQL por stdin para interpolar variaveis com quoting seguro.
# A senha administrativa do banco e lida dentro do container; nao e copiada
# para o host, argv, arquivo ou saida do script. Somente o hash trafega em argv.
cat <<'SQL' | docker exec -i "$container" sh -ec \
  'test -n "$POSTGRES_USER" && test -n "$POSTGRES_PASSWORD"; PGPASSWORD="$POSTGRES_PASSWORD" exec psql -X -v ON_ERROR_STOP=1 -v uid="$1" -v vid="$2" -v org="$3" -v hash="$4" -v email="$5" -v nome="$6" -h 127.0.0.1 -U "$POSTGRES_USER" -d emporio -f -' \
  seed-admin-staging "$ADMIN_USER_ID" "$ADMIN_VINCULO_ID" \
  "$ADMIN_PLATFORM_ID" "$HASH" "$ADMIN_EMAIL" "$ADMIN_NOME"
SET search_path = identidade, catalogo, mercadoria, comercial, infraestrutura, venda, pedidos, public;

SELECT count(*) = 1 AS platform_ready FROM organizacao
 WHERE id = :'org'::uuid AND nome = 'Emporio B2B' AND slug = 'emporio-b2b'
   AND tipo = 'PLATAFORMA' AND status = 'ATIVA';
\gset check_
\if :check_platform_ready
\else
\echo 'ERRO: organizacao PLATAFORMA nao encontrada; confirme que V1 foi aplicada'
\quit 1
\endif

SELECT to_regclass('identidade.usuario') IS NOT NULL
   AND to_regclass('identidade.vinculo') IS NOT NULL
   AND to_regclass('identidade.vinculo_papel') IS NOT NULL
   AND to_regclass('identidade.vinculo_capacidade') IS NOT NULL AS schema_ready;
\gset check_
\if :check_schema_ready
\else
\echo 'ERRO: schema de identidade incompleto; confirme que as migrations terminaram'
\quit 1
\endif

BEGIN;

INSERT INTO usuario (id, email, nome, senha_hash, status, email_verificado_em)
VALUES (:'uid'::uuid, :'email', :'nome', :'hash', 'ATIVO', now())
ON CONFLICT (email) DO UPDATE
   SET senha_hash = EXCLUDED.senha_hash,
       status = 'ATIVO',
       email_verificado_em = COALESCE(usuario.email_verificado_em, now()),
       updated_at = now()
 WHERE usuario.id = EXCLUDED.id;

INSERT INTO vinculo (id, usuario_id, organizacao_id, status, created_at, updated_at, ativado_em)
VALUES (:'vid'::uuid, :'uid'::uuid, :'org'::uuid, 'ATIVO', now(), now(), now())
ON CONFLICT (id) DO UPDATE
   SET status = 'ATIVO', ativado_em = COALESCE(vinculo.ativado_em, now()), updated_at = now()
 WHERE vinculo.usuario_id = EXCLUDED.usuario_id
   AND vinculo.organizacao_id = EXCLUDED.organizacao_id;

INSERT INTO vinculo_papel (id, vinculo_id, organizacao_id, papel, escopo, status, concedido_em)
SELECT gen_random_uuid(), v.id, v.organizacao_id, 'ADMIN_NEGOCIO', 'PLATAFORMA', 'ATIVO', now()
  FROM vinculo v
 WHERE v.id = :'vid'::uuid AND v.usuario_id = :'uid'::uuid AND v.organizacao_id = :'org'::uuid
   AND NOT EXISTS (
       SELECT 1 FROM vinculo_papel p
        WHERE p.vinculo_id = v.id AND p.organizacao_id = v.organizacao_id
          AND p.papel = 'ADMIN_NEGOCIO' AND p.status = 'ATIVO'
   );

WITH capacidades(codigo) AS (
    VALUES ('ADMIN_GERENCIAR_CADASTRO'), ('ADMIN_GERENCIAR_CATEGORIA'),
           ('ADMIN_GERENCIAR_CARACTERISTICA'), ('ADMIN_GERENCIAR_MARCA'),
           ('ADMIN_GERENCIAR_PRODUTO'), ('ADMIN_GERENCIAR_MERCADORIA'),
           ('ADMIN_GERENCIAR_OFERTA'), ('ADMIN_PUBLICAR_OFERTA'), ('GESTAO_ADMIN')
)
INSERT INTO vinculo_capacidade (id, vinculo_id, organizacao_id, capacidade_codigo, concedida_em)
SELECT gen_random_uuid(), v.id, v.organizacao_id, c.codigo, now()
  FROM vinculo v CROSS JOIN capacidades c
 WHERE v.id = :'vid'::uuid AND v.usuario_id = :'uid'::uuid AND v.organizacao_id = :'org'::uuid
   AND NOT EXISTS (
       SELECT 1 FROM vinculo_capacidade vc
        WHERE vc.vinculo_id = v.id AND vc.organizacao_id = v.organizacao_id
          AND vc.capacidade_codigo = c.codigo AND vc.revogada_em IS NULL
   );

SELECT count(*) = 1 AS user_ok FROM usuario WHERE id = :'uid'::uuid AND email = :'email';
\gset check_
\if :check_user_ok
\else
\echo 'ERRO: email ja associado a outra identidade; transacao revertida'
\quit 1
\endif

SELECT count(*) = 1 AS link_ok FROM vinculo
 WHERE id = :'vid'::uuid AND usuario_id = :'uid'::uuid
   AND organizacao_id = :'org'::uuid AND status = 'ATIVO';
\gset check_
\if :check_link_ok
\else
\echo 'ERRO: vinculo do admin nao corresponde a identidade esperada; transacao revertida'
\quit 1
\endif

SELECT count(*) = 1 AS role_ok FROM vinculo_papel
 WHERE vinculo_id = :'vid'::uuid AND organizacao_id = :'org'::uuid
   AND papel = 'ADMIN_NEGOCIO' AND escopo = 'PLATAFORMA' AND status = 'ATIVO';
\gset check_
\if :check_role_ok
\else
\echo 'ERRO: papel administrativo nao ficou ativo; transacao revertida'
\quit 1
\endif

SELECT count(*) = 9 AS capabilities_ok FROM vinculo_capacidade
 WHERE vinculo_id = :'vid'::uuid AND organizacao_id = :'org'::uuid
   AND revogada_em IS NULL AND capacidade_codigo IN (
       'ADMIN_GERENCIAR_CADASTRO', 'ADMIN_GERENCIAR_CATEGORIA',
       'ADMIN_GERENCIAR_CARACTERISTICA', 'ADMIN_GERENCIAR_MARCA',
       'ADMIN_GERENCIAR_PRODUTO', 'ADMIN_GERENCIAR_MERCADORIA',
       'ADMIN_GERENCIAR_OFERTA', 'ADMIN_PUBLICAR_OFERTA', 'GESTAO_ADMIN'
   );
\gset check_
\if :check_capabilities_ok
\else
\echo 'ERRO: capacidades administrativas incompletas; transacao revertida'
\quit 1
\endif

COMMIT;

SELECT u.email, u.status AS usuario_status, v.status AS vinculo_status,
       p.papel, p.escopo, p.status AS papel_status,
       count(DISTINCT vc.capacidade_codigo) AS capacidades_admin_ativas
  FROM usuario u
  JOIN vinculo v ON v.usuario_id = u.id
  JOIN vinculo_papel p ON p.vinculo_id = v.id AND p.organizacao_id = v.organizacao_id
  LEFT JOIN vinculo_capacidade vc ON vc.vinculo_id = v.id
                                 AND vc.organizacao_id = v.organizacao_id
                                 AND vc.revogada_em IS NULL
 WHERE u.id = :'uid'::uuid AND u.email = :'email'
 GROUP BY u.email, u.status, v.status, p.papel, p.escopo, p.status;
SQL

unset HASH
printf '\nAdmin de staging pronto: %s. A organizacao Emporio B2B/PLATAFORMA e criada pela migration V1.\n' "$ADMIN_EMAIL"
