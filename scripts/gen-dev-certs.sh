#!/usr/bin/env bash
# Gera os materiais TLS usados SOMENTE pelo stack de dev local:
#
#   certs/dev/mailpit.crt / mailpit.key
#       certificado autoassinado com SAN=mailpit (o nome que o Back usa como
#       SMTP_HOST), servido pelo Mailpit em STARTTLS na porta 1025.
#   certs/dev/truststore.p12
#       truststore PKCS12 do JVM do backend contendo esse certificado, para
#       que `mail.smtp.starttls.required=true` +
#       `mail.smtp.ssl.checkserveridentity=true` (hard-coded no Back) passem
#       sem fragilizar nada: o profile de produção usa o cacerts padrão.
#
# Por que isto existe: o EmailConfiguration do Backend_Java REJEITA subir com
# APP_EMAIL_ENABLED=true sem STARTTLS obrigatório, auth e credenciais — SMTP
# plano do Mailpit não atende (verificado: EHLO sem STARTTLS/AUTH).
#
# Segurança: material EFEMERO de desenvolvimento, nunca versionado
# (.gitignore cobre *.crt/*.key/*.p12 em qualquer nível). A senha do
# truststore é pública e documentada de propósito — ela não autentica nada,
# só destrava o read do arquivo dentro do container de dev.
#
# Uso: scripts/gen-dev-certs.sh [--force]
# Idempotente: reutiliza se o certificado existir, casar o SAN e durar >7d.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/certs/dev"
CRT="$DIR/mailpit.crt"
KEY="$DIR/mailpit.key"
TS="$DIR/truststore.p12"
TS_PASS="emporio-dev-truststore"
FORCE="${1:-}"

valid_existing() {
  [[ -f "$CRT" && -f "$KEY" && -f "$TS" ]] || return 1
  openssl x509 -in "$CRT" -noout -checkend 604800 >/dev/null 2>&1 || return 1
  openssl x509 -in "$CRT" -noout -text | grep -q 'DNS:mailpit' || return 1
  keytool -list -keystore "$TS" -storepass "$TS_PASS" -alias mailpit-dev >/dev/null 2>&1
}

if [[ "$FORCE" == "--force" ]]; then
  : # regenera
elif valid_existing; then
  echo "certs/dev: material TLS de dev já é válido (>7 dias de validade, SAN=mailpit, truststore ok)"
  exit 0
fi

command -v openssl >/dev/null 2>&1 || { echo "ERRO: openssl não encontrado" >&2; exit 1; }
command -v keytool >/dev/null 2>&1 || { echo "ERRO: keytool (JDK) não encontrado no PATH" >&2; exit 1; }

mkdir -p "$DIR"
umask 077
openssl req -x509 -newkey rsa:2048 -sha256 -days 825 -nodes \
  -keyout "$KEY" -out "$CRT" \
  -subj "/CN=mailpit" \
  -addext "subjectAltName=DNS:mailpit,DNS:localhost" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth" >/dev/null 2>&1
chmod 644 "$CRT" "$KEY"

rm -f "$TS" 2>/dev/null || true
keytool -importcert -noprompt -trustcacerts \
  -alias mailpit-dev -file "$CRT" \
  -keystore "$TS" -storetype PKCS12 -storepass "$TS_PASS" >/dev/null 2>&1
chmod 644 "$TS"

echo "certs/dev: gerados mailpit.crt/key (SAN=mailpit, 825d) + truststore.p12 (alias mailpit-dev)"
echo "Atenção: arquivo local de dev; não commitar (gitignore já cobre *.crt/*.key/*.p12)."
