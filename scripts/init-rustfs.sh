#!/bin/sh
# Bootstrap idempotente do RustFS local usado somente pelo Compose dev.
set -eu

validate_credential() {
  value="$1"
  case "$value" in
    ''|*[[:space:]]*|*'<'*|*'>'*|*'$'*|replace-with-*|replace_with_*|your-*|your_*|changeme|change-me|change_me|example|example-*|example_*|youraccesskey*|yoursecret*|replacewith*)
      exit 1
      ;;
  esac
}

case "$RUSTFS_ACCESS_KEY" in ''|*[!A-Za-z0-9]*) exit 1 ;; esac
case "$RUSTFS_READ_ONLY_ACCESS_KEY" in ''|*[!A-Za-z0-9]*) exit 1 ;; esac
[ "${#RUSTFS_ACCESS_KEY}" -ge 16 ] && [ "${#RUSTFS_ACCESS_KEY}" -le 128 ] || exit 1
[ "${#RUSTFS_READ_ONLY_ACCESS_KEY}" -ge 16 ] && [ "${#RUSTFS_READ_ONLY_ACCESS_KEY}" -le 128 ] || exit 1
validate_credential "$RUSTFS_ACCESS_KEY"
validate_credential "$RUSTFS_SECRET_KEY"
validate_credential "$RUSTFS_READ_ONLY_ACCESS_KEY"
validate_credential "$RUSTFS_READ_ONLY_SECRET_KEY"
if [ "$RUSTFS_ACCESS_KEY" = "$RUSTFS_READ_ONLY_ACCESS_KEY" ] || [ "$RUSTFS_SECRET_KEY" = "$RUSTFS_READ_ONLY_SECRET_KEY" ]; then
  exit 1
fi

# O alias set valida a conexão com o endpoint. A repetição limitada cobre a
# propagação transitória do DNS de serviço após o container saudável, sem
# escrever credenciais nos logs nem mascarar indisponibilidade persistente.
attempt=1
while :; do
  if rc alias set --quiet --region "${RUSTFS_REGION:-us-east-1}" --bucket-lookup path \
    local http://rustfs:9000 "$RUSTFS_ACCESS_KEY" "$RUSTFS_SECRET_KEY" >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -ge 15 ]; then
    printf '%s\n' 'ERRO: não foi possível conectar a rustfs:9000 após 15 tentativas.' >&2
    exit 1
  fi
  sleep 2
  attempt=$((attempt + 1))
done

rc mb --quiet --ignore-existing local/quarantine-local
rc mb --quiet --ignore-existing local/private-local
rc mb --quiet --ignore-existing local/public-local

printf '%s\n' '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject"],"Resource":["arn:aws:s3:::private-local/*","arn:aws:s3:::public-local/*"]}]}' > /tmp/emporio-storage-read-only.json
# Limpeza best-effort: os recursos podem ainda não existir e a imagem atual
# não anuncia policy-detach; serão recriados logo abaixo. Não poluir o log com
# falhas esperadas nem imprimir detalhes que possam conter dados de ambiente.
rc admin policy detach --quiet local emporio-storage-read-only --user "$RUSTFS_READ_ONLY_ACCESS_KEY" >/dev/null 2>&1 || true
rc admin user rm --quiet local "$RUSTFS_READ_ONLY_ACCESS_KEY" >/dev/null 2>&1 || true
rc admin policy rm --quiet local emporio-storage-read-only >/dev/null 2>&1 || true
rc admin policy create --quiet local emporio-storage-read-only /tmp/emporio-storage-read-only.json
rc admin user add --quiet local "$RUSTFS_READ_ONLY_ACCESS_KEY" "$RUSTFS_READ_ONLY_SECRET_KEY"
rc admin policy attach --quiet local emporio-storage-read-only --user "$RUSTFS_READ_ONLY_ACCESS_KEY"

# Desvio dev-only: o navegador não envia credencial S3; somente o bucket
# público permite leitura anônima. Quarentena e privado continuam fechados.
rc bucket anonymous set download local/public-local

# CORS dev-only para os PUTs pré-assinados feitos pelo navegador. Em produção
# o CORS mora na borda/bucket R2 e o upload usa o endpoint público real.
cat > /tmp/emporio-dev-cors.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<CORSConfiguration>
  <CORSRule>
    <AllowedOrigin>http://localhost:4200</AllowedOrigin>
    <AllowedOrigin>http://localhost:4000</AllowedOrigin>
    <AllowedOrigin>http://127.0.0.1:4200</AllowedOrigin>
    <AllowedMethod>PUT</AllowedMethod>
    <AllowedMethod>GET</AllowedMethod>
    <AllowedMethod>HEAD</AllowedMethod>
    <AllowedMethod>POST</AllowedMethod>
    <AllowedMethod>DELETE</AllowedMethod>
    <!-- `*` é o único wildcard que a spec S3 permite; `x-amz-*` NÃO é
         suportado pelo RustFS e derruba o preflight com 403 (evidência
         2026-09-26: ACRH com x-amz-checksum-sha256 -> 403; com `*` -> 200).
         A restrição relevante (origem) permanece explícita abaixo. -->
    <AllowedHeader>*</AllowedHeader>
    <ExposeHeader>ETag</ExposeHeader>
    <ExposeHeader>x-amz-checksum-crc32</ExposeHeader>
    <ExposeHeader>x-amz-checksum-crc32c</ExposeHeader>
    <ExposeHeader>x-amz-checksum-sha1</ExposeHeader>
    <ExposeHeader>x-amz-checksum-sha256</ExposeHeader>
    <ExposeHeader>x-amz-meta-content-type</ExposeHeader>
    <MaxAgeSeconds>3600</MaxAgeSeconds>
  </CORSRule>
</CORSConfiguration>
EOF

for bucket in quarantine-local private-local public-local; do
  rc bucket cors set "local/$bucket" --file /tmp/emporio-dev-cors.xml
done
