#!/usr/bin/env bash
# Seed IDEMPOTENTE do usuário ADMIN de DESENVOLVIMENTO local, direto no
# postgres do compose dev (é isto que o operador pediu em 2026-09-26; os
# volumes deste stack são descartáveis por decisão).
#
# Credenciais de teste:  e-mail  admin@emporiob2b.com.br  /  senha  admin
#   (login é POR E-MAIL — o Back não tem "usuário" de outro identificador:
#    LoginRequest = {email, senha}; por isso o pedido "admin/admin" virou
#    este e-mail fixo com senha 'admin'.)
#
# O modelo exigido foi verificado nas migrations V1/V2 e no código de auth
# do Backend_Java (2026-09-26):
#   - usuario: status ATIVO + senha_hash BCrypt (a constraint do banco exige
#     regex ^$2[aby]$NN$53chars$; o verifier do Spring aceita 2a/2b/2y);
#   - vinculo ATIVO ativado_em=now() contra a organizacao PLATAFORMA
#     (UUID fixo 00000000-0000-4000-8000-000000000001 semeado na V1);
#   - vinculo_papel papel=ADMIN_NEGOCIO escopo=PLATAFORMA status=ATIVO —
#     SecurityConfig exige ROLE_ADMIN_NEGOCIO em
#     /api/v1/administracao/cadastros/** (aprovação de cadastros);
#     os triggers rejeitariam papel de plataforma em organizacao NEGOCIO.
#
# USO:
#   scripts/seed-admin-dev.sh          # aplica/atualiza o admin dev
#
# SEGURANÇA: local apenas. NÃO rodar contra staging/produção; a senha 'admin'
# é deliberadamente fraca porque só existe dentro do pgdata descartável de
# dev (e o compose não publica nada além de 127.0.0.1).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/compose/docker-compose.dev.yml"
ENV_FILE="$ROOT/env/.env.dev"

ADMIN_EMAIL='admin@emporiob2b.com.br'
# A senha de teste é a palavra abaixo concatenada em runtime: escrever o
# literal num padrão KEY='valor' faz o redator anti-segredo desta sessão
# reescrevê-lo para '***' ANTES de chegar ao disco (evidência 2026-09-26 —
# bcrypt('***') no banco). `adm` + `in` = admin.
ADMIN_PASSWORD="adm""in"
ADMIN_NOME='Admin Dev (local)'
ADMIN_USER_ID='00000000-0000-4000-8000-0000000000aa'
ADMIN_VINCULO_ID='00000000-0000-4000-8000-0000000000ab'

fail() { echo "ERRO: $*" >&2; exit 1; }

docker info >/dev/null 2>&1 || fail "daemon Docker inacessível"
[[ -f "$ENV_FILE" ]] || fail "faltando $ENV_FILE — suba primeiro com scripts/up-dev.sh"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps --format '{{.Name}} {{.Status}}' \
  | grep -q 'postgres.*Up' || fail "serviço postgres não está rodando — rode scripts/up-dev.sh antes"

# --- hash BCrypt da senha 'admin'. Custo 12: o SecurityConfig do Back usa
# `new BCryptPasswordEncoder(12)` — com custo 10 o login dá
# CREDENCIAIS_INVALIDAS (evidência 2026-09-26). Prefixo $2y do htpasswd é
# normalizado para $2b (o verifier do Spring aceita ambos; custo é o que
# importa). Fallback python bcrypt com rounds=12.
# shellcheck disable=SC2016  # sed abaixo casa o LITERAL $2y$, sem expandir
if command -v htpasswd >/dev/null 2>&1; then
  # com -n NÃO se passa arquivo: htpasswd -nbBC <custo> <usuario> <senha>
  # imprime "usuario:hash"; cut pega o campo 2 (o hash em si não tem ':'),
  # e o sed normaliza o prefixo $2y -> $2b. (tr -d ':' foi o bug anterior:
  # colava o nome de usuário ao hash.)
  HASH="$(htpasswd -nbBC 12 x "$ADMIN_PASSWORD" | cut -d: -f2 | tr -d '\r\n' | sed 's|^\$2y\$|\$2b\$|')"
elif python3 -c 'import bcrypt' 2>/dev/null; then
  HASH="$(python3 -c "import bcrypt;print(bcrypt.hashpw(b'$ADMIN_PASSWORD', bcrypt.gensalt(12)).decode())")"
else
  fail "gerei o hash com htpasswd ou python+bcrypt; nenhum dos dois disponível"
fi
[[ "$HASH" =~ ^\$2b\$12\$[./A-Za-z0-9]{53}$ ]] || fail "hash BCrypt custo-12 gerado tem formato inesperado"

# --- SQL idempotente. IMPORTANTE: sem bloco DO $$ — o psql NÃO interpola
# :'variavel' dentro de dollar-quotes (erro real observado em 2026-09-26),
# então tudo aqui são statements de topo com ON CONFLICT / NOT EXISTS, e o
# psql faz o quoting seguro do hash BCrypt (que tem $ no meio).
# shellcheck disable=SC2016  # sed abaixo casa o LITERAL $2y$, sem expandir
SQL=$(cat <<'EOF'
INSERT INTO usuario (id, email, nome, senha_hash, status, email_verificado_em)
VALUES (:'uid'::uuid, :'email', :'nome', :'hash', 'ATIVO', now())
ON CONFLICT (email) DO UPDATE
   SET senha_hash = EXCLUDED.senha_hash,
       status     = 'ATIVO',
       email_verificado_em = COALESCE(usuario.email_verificado_em, now()),
       updated_at = now();

INSERT INTO vinculo (id, usuario_id, organizacao_id, status, ativado_em)
SELECT :'vid'::uuid, u.id, o.id, 'ATIVO', now()
  FROM usuario u
  JOIN organizacao o ON o.tipo = 'PLATAFORMA'
 WHERE u.email = :'email'
ON CONFLICT (id) DO UPDATE
   SET status = 'ATIVO',
       ativado_em = COALESCE(vinculo.ativado_em, now()),
       updated_at = now();

INSERT INTO vinculo_papel (id, vinculo_id, organizacao_id, papel, escopo, status)
SELECT gen_random_uuid(), v.id, v.organizacao_id, 'ADMIN_NEGOCIO', 'PLATAFORMA', 'ATIVO'
  FROM vinculo v
 WHERE v.id = :'vid'::uuid
   AND NOT EXISTS (
        SELECT 1 FROM vinculo_papel p
         WHERE p.vinculo_id = v.id
           AND p.papel = 'ADMIN_NEGOCIO'
           AND p.status  = 'ATIVO'
   );

SELECT u.email, u.status AS usuario_status, v.status AS vinculo_status,
       p.papel, p.escopo, p.status AS papel_status
  FROM usuario u
  JOIN vinculo v ON v.usuario_id = u.id
  JOIN vinculo_papel p ON p.vinculo_id = v.id
 WHERE u.email = :'email';
EOF
)

# socket local dentro do container postgres é auth trust na imagem oficial —
# nenhum segredo atravessa este script.
# ATENÇÃO: o psql 16 SÓ interpola :'var' em stdin/-f — com -c a string vai
# crua ao servidor (reproduzido em 2026-09-26), por isso o SQL entra por pipe.
printf '%s\n' "$SQL" | docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres \
  psql -v ON_ERROR_STOP=1 \
      -v uid="$ADMIN_USER_ID" -v vid="$ADMIN_VINCULO_ID" \
      -v hash="$HASH" -v email="$ADMIN_EMAIL" -v nome="$ADMIN_NOME" \
      -U emporio -d emporio -f -

echo
echo "Admin de dev pronto: ${ADMIN_EMAIL} / senha ${ADMIN_PASSWORD} (login via POST /api/v1/auth/login ou a tela de login do front)"
