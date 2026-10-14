#!/usr/bin/env bash
# Seed IDEMPOTENTE do usuário ADMIN de DESENVOLVIMENTO local, direto no
# postgres do compose dev (é isto que o operador pediu em 2026-09-26; os
# volumes deste stack são descartáveis por decisão).
#
# Identidade de teste: e-mail admin@emporiob2b.com.br. A senha vem de
# ADMIN_DEV_PASSWORD no ambiente local ignorado (ou de env/.env.dev), nunca
# fica versionada nem é impressa. Login é POR E-MAIL — o Back não tem
# "usuário" de outro identificador: LoginRequest = {email, senha}.
#
# O modelo exigido foi verificado nas migrations V1/V2 e no código de auth
# do Backend_Java (2026-10-10):
#   - usuario: status ATIVO + senha_hash BCrypt (a constraint do banco exige
#     regex ^$2[aby]$NN$53chars$; o verifier do Spring aceita 2a/2b/2y);
#   - vinculo ATIVO com created_at, updated_at e ativado_em explícitos contra a
#     organizacao PLATAFORMA
#     (UUID fixo 00000000-0000-4000-8000-000000000001 semeado na V1);
#   - vinculo_papel papel=ADMIN_NEGOCIO escopo=PLATAFORMA status=ATIVO e
#     concedido_em explícito —
#     SecurityConfig exige ROLE_ADMIN_NEGOCIO em
#     /api/v1/administracao/cadastros/** (aprovação de cadastros);
#     os triggers rejeitariam papel de plataforma em organizacao NEGOCIO.
#   - vinculo_capacidade: todas as capacidades administrativas de plataforma,
#     incluindo GESTAO_ADMIN, para que o admin zero seja superusuário de teste.
#
# USO:
#   scripts/seed-admin-dev.sh          # aplica/atualiza o admin dev
#
# SEGURANÇA: local apenas. NÃO rodar contra staging/produção; use uma senha
# exclusiva no ADMIN_DEV_PASSWORD do arquivo .env.dev ignorado (e o compose
# não publica nada além de 127.0.0.1).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/compose/docker-compose.dev.yml"
ENV_FILE="$ROOT/env/.env.dev"

ADMIN_EMAIL='admin@emporiob2b.com.br'
ADMIN_NOME='Admin Dev (local)'
ADMIN_USER_ID='00000000-0000-4000-8000-0000000000aa'
ADMIN_VINCULO_ID='00000000-0000-4000-8000-0000000000ab'
ADMIN_PLATFORM_ID='00000000-0000-4000-8000-000000000001'

fail() { echo "ERRO: $*" >&2; exit 1; }

docker info >/dev/null 2>&1 || fail "daemon Docker inacessível"
[[ -f "$ENV_FILE" ]] || fail "faltando $ENV_FILE — suba primeiro com scripts/up-dev.sh"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps --format '{{.Name}} {{.Status}}' \
  | grep -q 'postgres.*Up' || fail "serviço postgres não está rodando — rode scripts/up-dev.sh antes"

# A senha pode ser exportada pelo operador para uma execução pontual ou lida
# somente em runtime do arquivo local ignorado. O parser deliberadamente aceita
# apenas a forma simples KEY=valor usada pelo *.example; não imprime o valor.
ADMIN_PASSWORD="${ADMIN_DEV_PASSWORD:-}"
if [[ -z "$ADMIN_PASSWORD" ]]; then
  while IFS= read -r env_line; do
    case "$env_line" in
      ADMIN_DEV_PASSWORD=*) ADMIN_PASSWORD="${env_line#ADMIN_DEV_PASSWORD=}"; break ;;
    esac
  done < "$ENV_FILE"
fi
[[ -n "$ADMIN_PASSWORD" && "$ADMIN_PASSWORD" != replace-with-* ]] \
  || fail "defina ADMIN_DEV_PASSWORD no env/.env.dev local (valor ignorado pelo Git)"

# --- hash BCrypt da senha configurada. Custo 12: o SecurityConfig do Back usa
# `new BCryptPasswordEncoder(12)` — com custo 10 o login dá
# CREDENCIAIS_INVALIDAS (evidência 2026-09-26). Prefixo $2y do htpasswd é
# normalizado para $2b (o verifier do Spring aceita ambos; custo é o que
# importa). Fallback python bcrypt com rounds=12.
# shellcheck disable=SC2016  # sed abaixo casa o LITERAL $2y$, sem expandir
if command -v htpasswd >/dev/null 2>&1; then
  # -i lê a senha via stdin, evitando expô-la como argumento de processo.
  # htpasswd imprime "usuario:hash"; cut pega o campo 2 (o hash em si não
  # tem ':') e o sed normaliza o prefixo $2y -> $2b.
  HASH="$(printf '%s\n' "$ADMIN_PASSWORD" | htpasswd -niBC 12 x | cut -d: -f2 | tr -d '\r\n' | sed 's|^\$2y\$|\$2b\$|')"
elif python3 -c 'import bcrypt' 2>/dev/null; then
  HASH="$(ADMIN_PASSWORD="$ADMIN_PASSWORD" python3 -c \
    'import os,bcrypt; print(bcrypt.hashpw(os.environ["ADMIN_PASSWORD"].encode(), bcrypt.gensalt(12)).decode())')"
else
  fail "gerei o hash com htpasswd ou python+bcrypt; nenhum dos dois disponível"
fi
[[ "$HASH" =~ ^\$2b\$12\$[./A-Za-z0-9]{53}$ ]] || fail "hash BCrypt custo-12 gerado tem formato inesperado"

# --- SQL idempotente. IMPORTANTE: sem bloco DO $$ — o psql NÃO interpola
# :'variavel' dentro de dollar-quotes (erro real observado em 2026-09-26),
# então os dados usam statements de topo com ON CONFLICT / NOT EXISTS. A
# transação impede que uma falha deixe somente o usuario persistido. As
# diretivas \gset/\if abaixo validam a identidade canônica sem interpolar
# variáveis dentro de PL/pgSQL, e o psql faz o quoting seguro do hash BCrypt
# (que tem $ no meio).
# shellcheck disable=SC2016  # sed abaixo casa o LITERAL $2y$, sem expandir
SQL=$(cat <<'EOF'
BEGIN;

INSERT INTO usuario (id, email, nome, senha_hash, status, email_verificado_em)
VALUES (:'uid'::uuid, :'email', :'nome', :'hash', 'ATIVO', now())
ON CONFLICT (email) DO UPDATE
   SET senha_hash = EXCLUDED.senha_hash,
       status     = 'ATIVO',
       email_verificado_em = COALESCE(usuario.email_verificado_em, now()),
       updated_at = now()
 WHERE usuario.id = EXCLUDED.id;

INSERT INTO vinculo (
    id, usuario_id, organizacao_id, status, created_at, updated_at, ativado_em
)
VALUES (:'vid'::uuid, :'uid'::uuid, :'org'::uuid, 'ATIVO', now(), now(), now())
ON CONFLICT (id) DO UPDATE
   SET status = 'ATIVO',
       ativado_em = COALESCE(vinculo.ativado_em, now()),
       updated_at = now()
 WHERE vinculo.usuario_id = EXCLUDED.usuario_id
   AND vinculo.organizacao_id = EXCLUDED.organizacao_id;

INSERT INTO vinculo_papel (
    id, vinculo_id, organizacao_id, papel, escopo, status, concedido_em
)
SELECT gen_random_uuid(), v.id, v.organizacao_id, 'ADMIN_NEGOCIO', 'PLATAFORMA', 'ATIVO', now()
  FROM vinculo v
 WHERE v.id = :'vid'::uuid
   AND v.usuario_id = :'uid'::uuid
   AND v.organizacao_id = :'org'::uuid
   AND NOT EXISTS (
        SELECT 1 FROM vinculo_papel p
         WHERE p.vinculo_id = v.id
           AND p.organizacao_id = v.organizacao_id
           AND p.papel = 'ADMIN_NEGOCIO'
           AND p.status  = 'ATIVO'
   );

-- Todas as capacidades de plataforma catalogadas em V2. A linha de
-- vinculo_capacidade também exige concedida_em explícito e não tem default.
WITH capacidades(codigo) AS (
    VALUES
        ('ADMIN_GERENCIAR_CADASTRO'),
        ('ADMIN_GERENCIAR_CATEGORIA'),
        ('ADMIN_GERENCIAR_CARACTERISTICA'),
        ('ADMIN_GERENCIAR_MARCA'),
        ('ADMIN_GERENCIAR_PRODUTO'),
        ('ADMIN_GERENCIAR_MERCADORIA'),
        ('ADMIN_GERENCIAR_OFERTA'),
        ('ADMIN_PUBLICAR_OFERTA'),
        ('GESTAO_ADMIN')
)
INSERT INTO vinculo_capacidade (
    id, vinculo_id, organizacao_id, capacidade_codigo, concedida_em
)
SELECT gen_random_uuid(), v.id, v.organizacao_id, c.codigo, now()
  FROM vinculo v
 CROSS JOIN capacidades c
 WHERE v.id = :'vid'::uuid
   AND v.usuario_id = :'uid'::uuid
   AND v.organizacao_id = :'org'::uuid
   AND NOT EXISTS (
       SELECT 1
         FROM vinculo_capacidade vc
        WHERE vc.vinculo_id = v.id
          AND vc.organizacao_id = v.organizacao_id
          AND vc.capacidade_codigo = c.codigo
          AND vc.revogada_em IS NULL
   );

-- Não prossiga silenciosamente se o email ou algum ID fixo já representar
-- outra identidade. Em caso de falha, a conexão fecha sem COMMIT e a
-- transação é revertida.
SELECT count(*) = 1 AS admin_user_ok
  FROM usuario
 WHERE id = :'uid'::uuid
   AND email = :'email';
\gset check_
\if :check_admin_user_ok
\else
\echo 'ERRO: o email do admin já está associado a outro usuario'
\quit 1
\endif

SELECT count(*) = 1 AS admin_vinculo_ok
  FROM vinculo
 WHERE id = :'vid'::uuid
   AND usuario_id = :'uid'::uuid
   AND organizacao_id = :'org'::uuid
   AND status = 'ATIVO';
\gset check_
\if :check_admin_vinculo_ok
\else
\echo 'ERRO: o vínculo fixo do admin não representa a identidade esperada'
\quit 1
\endif

SELECT count(*) = 1 AS admin_papel_ok
  FROM vinculo_papel
 WHERE vinculo_id = :'vid'::uuid
   AND organizacao_id = :'org'::uuid
   AND papel = 'ADMIN_NEGOCIO'
   AND escopo = 'PLATAFORMA'
   AND status = 'ATIVO';
\gset check_
\if :check_admin_papel_ok
\else
\echo 'ERRO: o papel ADMIN_NEGOCIO do admin não ficou ativo'
\quit 1
\endif

SELECT count(*) = 9 AS admin_capacidades_ok
  FROM vinculo_capacidade
 WHERE vinculo_id = :'vid'::uuid
   AND organizacao_id = :'org'::uuid
   AND revogada_em IS NULL
   AND capacidade_codigo IN (
       'ADMIN_GERENCIAR_CADASTRO', 'ADMIN_GERENCIAR_CATEGORIA',
       'ADMIN_GERENCIAR_CARACTERISTICA', 'ADMIN_GERENCIAR_MARCA',
       'ADMIN_GERENCIAR_PRODUTO', 'ADMIN_GERENCIAR_MERCADORIA',
       'ADMIN_GERENCIAR_OFERTA', 'ADMIN_PUBLICAR_OFERTA', 'GESTAO_ADMIN'
   );
\gset check_
\if :check_admin_capacidades_ok
\else
\echo 'ERRO: o superusuário não possui as nove capacidades administrativas'
\quit 1
\endif

COMMIT;

SELECT u.email, u.status AS usuario_status, v.status AS vinculo_status,
       p.papel, p.escopo, p.status AS papel_status,
       count(DISTINCT vc.capacidade_codigo) AS capacidades_admin_ativas
  FROM usuario u
  JOIN vinculo v ON v.usuario_id = u.id
  JOIN vinculo_papel p ON p.vinculo_id = v.id
                       AND p.organizacao_id = v.organizacao_id
  LEFT JOIN vinculo_capacidade vc ON vc.vinculo_id = v.id
                                 AND vc.organizacao_id = v.organizacao_id
                                 AND vc.revogada_em IS NULL
 WHERE u.id = :'uid'::uuid
   AND u.email = :'email'
 GROUP BY u.email, u.status, v.status, p.papel, p.escopo, p.status;
EOF
)

# socket local dentro do container postgres é auth trust na imagem oficial —
# nenhum segredo atravessa este script.
# ATENÇÃO: o psql 16 SÓ interpola :'var' em stdin/-f — com -c a string vai
# crua ao servidor (reproduzido em 2026-09-26), por isso o SQL entra por pipe.
printf '%s\n' "$SQL" | docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres \
  psql -v ON_ERROR_STOP=1 \
      -v uid="$ADMIN_USER_ID" -v vid="$ADMIN_VINCULO_ID" \
      -v org="$ADMIN_PLATFORM_ID" \
      -v hash="$HASH" -v email="$ADMIN_EMAIL" -v nome="$ADMIN_NOME" \
      -U emporio -d emporio -f -

echo
echo "Admin de dev pronto: ${ADMIN_EMAIL} (senha local fornecida por ADMIN_DEV_PASSWORD; login via POST /api/v1/auth/login ou a tela de login do front)"
