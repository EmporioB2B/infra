#!/usr/bin/env bash
# Publica o logo estático referenciado pelos emails do Backend no R2 de staging.
# Não grava dados no PostgreSQL e não deve ser usado para produção.
set +x
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_LOGO="$ROOT/../Front_Angular/public/img/logo.png"
LOGO_FILE="${1:-$DEFAULT_LOGO}"
readonly OBJECT_KEY='img/email/logo.png'
readonly MEDIA_BASE_URL='https://media-staging.emporiob2b.com.br'

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
[[ $# -le 1 ]] || fail 'uso: scripts/publish-email-logo-staging.sh [caminho/logo.png]'
[[ -f "$LOGO_FILE" && -r "$LOGO_FILE" ]] || fail "arquivo PNG não encontrado ou não legível: $LOGO_FILE"
command -v aws >/dev/null 2>&1 || fail 'AWS CLI v2 não encontrado'
command -v curl >/dev/null 2>&1 || fail 'curl não encontrado'
command -v file >/dev/null 2>&1 || fail 'file não encontrado'
aws_version="$(aws --version 2>&1)"
[[ "$aws_version" == aws-cli/2.* ]] || fail 'é necessário AWS CLI v2'
[[ "$(file --brief --mime-type -- "$LOGO_FILE")" == image/png ]] || fail 'o arquivo informado não é PNG'

for variable in EMAIL_LOGO_R2_ENDPOINT EMAIL_LOGO_R2_BUCKET \
                EMAIL_LOGO_R2_ACCESS_KEY_ID EMAIL_LOGO_R2_SECRET_ACCESS_KEY; do
  [[ -n "${!variable:-}" && "${!variable}" != replace-with-* ]] \
    || fail "defina $variable usando uma credencial dedicada ao staging"
done

case "$EMAIL_LOGO_R2_ENDPOINT" in
  https://*.r2.cloudflarestorage.com) ;;
  *) fail 'EMAIL_LOGO_R2_ENDPOINT deve ser o endpoint HTTPS da conta R2 (sem path)' ;;
esac
[[ "$EMAIL_LOGO_R2_BUCKET" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] \
  || fail 'EMAIL_LOGO_R2_BUCKET tem formato inválido'

PUBLIC_URL="$MEDIA_BASE_URL/$OBJECT_KEY"
printf 'Arquivo: %s\nDestino: bucket público de staging, chave %s\nURL esperada: %s\n' \
  "$LOGO_FILE" "$OBJECT_KEY" "$PUBLIC_URL"
printf 'A operação sobrescreve o objeto nessa chave. Digite staging para confirmar: '
IFS= read -r confirmation
[[ "$confirmation" == staging ]] || fail 'confirmação incorreta; nenhum upload feito'

# O token deve ser dedicado e restrito a escrita no bucket público de staging.
# Credenciais são entregues ao processo AWS via ambiente; nunca vão em argv/log.
AWS_ACCESS_KEY_ID="$EMAIL_LOGO_R2_ACCESS_KEY_ID" \
AWS_SECRET_ACCESS_KEY="$EMAIL_LOGO_R2_SECRET_ACCESS_KEY" \
AWS_DEFAULT_REGION=auto AWS_EC2_METADATA_DISABLED=true AWS_PAGER='' \
  aws --endpoint-url "$EMAIL_LOGO_R2_ENDPOINT" s3 cp \
    "$LOGO_FILE" "s3://$EMAIL_LOGO_R2_BUCKET/$OBJECT_KEY" \
    --content-type image/png \
    --cache-control 'public, max-age=300' \
    --only-show-errors --no-cli-pager

# Faz GET público após o upload (query única para reduzir falso negativo por cache).
if ! response="$(curl --silent --show-error --location --fail --max-time 30 \
  --output /dev/null --write-out '%{http_code} %{content_type}' \
  "$PUBLIC_URL?publish-check=$(date +%s)")"; then
  fail 'upload concluído, mas a URL pública não respondeu com sucesso; não repita às cegas, verifique domínio/cache'
fi
case "$response" in
  '200 image/png'*) ;;
  *) fail "objeto enviado, mas verificação pública inesperada (HTTP/content-type: $response)" ;;
esac

printf 'Logo publicado e servido como PNG: %s\n' "$PUBLIC_URL"
