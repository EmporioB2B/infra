#!/usr/bin/env bash
# Smoke do stack de desenvolvimento integrado (TASK-INFRA-001).
#
# Uso: scripts/smoke.sh   (assumes o stack já sobe por up-dev.sh)
#
# Verifica com evidência, sem alterar nada:
#   1. api actuator UP (127.0.0.1:8081);
#   2. front dev-server responde (127.0.0.1:4200);
#   3. UI do Mailpit responde (127.0.0.1:8025);
#   4. radar /health/ready (via exec — não tem porta no host);
#   5. backend alcança radar:8000 (rede radar-net);
#   6. health do RustFS + três buckets presentes (via one-shot rc);
#   7. bucket público lê anonimamente (fotos do navegador);
#   8. bucket privado/quarentena NEGAM leitura anônima (403);
#   9. preflight CORS permite o PUT directo do navegador (:4200 → :9000).
#
# Exit != 0 na primeira falha reportada (continua os demais checks para dar
# o panorama completo).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/compose/docker-compose.dev.yml"
ENV_FILE="$ROOT/env/.env.dev"
RC_IMAGE="rustfs/rc:v0.1.30"
NET="emporio-dev_default"

[[ -f "$ENV_FILE" ]] || { echo "ERRO: falta $ENV_FILE (scripts/up-dev.sh)" >&2; exit 1; }

compose() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

FAIL=0
ok()   { printf 'OK   %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*"; FAIL=1; }

# 1. api
if curl -fsS --max-time 5 http://127.0.0.1:8081/actuator/health | grep -q '"status":"UP"'; then
  ok "api: /actuator/health UP (127.0.0.1:8081)"
else
  bad "api: /actuator/health não respondeu UP"
fi

# 2. front
if curl -fsS --max-time 10 -o /dev/null http://127.0.0.1:4200/; then
  ok "front-dev: HTTP 200 em 127.0.0.1:4200"
else
  bad "front-dev: sem resposta em 127.0.0.1:4200"
fi

# 3. mailpit UI
if curl -fsS --max-time 5 -o /dev/null http://127.0.0.1:8025/; then
  ok "mailpit: UI 200 em 127.0.0.1:8025"
else
  bad "mailpit: UI sem resposta em 127.0.0.1:8025"
fi

# 4. radar via exec (sem porta publicada no host — é a regra)
if compose exec -T radar python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health/ready')" 2>/dev/null; then
  ok "radar: /health/ready (via exec, sem porta no host)"
else
  bad "radar: /health/ready falhou via exec"
fi

# 5. backend -> radar pela radar-net
if compose exec -T backend curl -fsS --max-time 5 http://radar:8000/health/live -o /dev/null; then
  ok "radar-net: backend alcança radar:8000/health/live"
else
  bad "radar-net: backend NÃO alcança radar:8000"
fi

# 6. buckets presentes + objeto-marcador no público (one-shot rc na rede
#    default; credenciais do env file). O marcador é usado no check 7 — não
#    dependemos de ListBucket anônimo, que é acessório da política "download"
#    e mudaria o motivo de uma falha.
BUCKETS="$(
  docker run --rm --network "$NET" \
    --env-file "$ENV_FILE" \
    --entrypoint /bin/sh "$RC_IMAGE" -ec '
      rc alias set --quiet --region "${RUSTFS_REGION:-us-east-1}" --bucket-lookup path local http://rustfs:9000 "$RUSTFS_ACCESS_KEY" "$RUSTFS_SECRET_KEY" >/dev/null
      rc ls local/quarantine-local >/dev/null 2>&1 && rc ls local/private-local >/dev/null 2>&1 && rc ls local/public-local >/dev/null 2>&1 || exit 1
      printf smoke > /tmp/marker
      rc cp --quiet /tmp/marker local/public-local/public/smoke-check.txt >/dev/null 2>&1 || exit 1
      echo present
    ' 2>/dev/null || true
)"
if [[ "$BUCKETS" == "present" ]]; then
  ok "rustfs: buckets presentes + marcador público enviado"
else
  bad "rustfs: verificação de buckets/marcador falhou"
fi

# 7. leitura anônima do OBJETO no público (o navegador não tem credencial S3)
if [[ "$(curl -fsS --max-time 5 "http://127.0.0.1:9000/public-local/public/smoke-check.txt" 2>/dev/null)" == "smoke" ]]; then
  ok "rustfs: objeto anônimo lê sem credencial no public-local (fotos do navegador OK)"
else
  bad "rustfs: leitura anônima do objeto em public-local falhou"
fi

# 8. privado e quarentena fechados para anônimo (espera HTTP 403)
for bucket in private-local quarantine-local; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:9000/$bucket/" || true)"
  if [[ "$code" == "403" ]]; then
    ok "rustfs: $bucket nega leitura anônima (403)"
  else
    bad "rustfs: $bucket respondeu HTTP '$code' (esperado 403)"
  fi
done

# 9. preflight CORS do direct-upload: navegador (origem :4200) -> rustfs:9000.
#    Simulado no host com --resolve (equivalente ao hosts local do navegador).
PREFLIGHT="$(curl -s -o /dev/null -D - --max-time 5 --resolve rustfs:9000:127.0.0.1 \
  -X OPTIONS 'http://rustfs:9000/quarantine-local/preflight-probe' \
  -H 'Origin: http://localhost:4200' \
  -H 'Access-Control-Request-Method: PUT' \
  -H 'Access-Control-Request-Headers: content-type,x-amz-checksum-sha256,if-none-match' \
  || true)"
if printf '%s' "$PREFLIGHT" | grep -qi '^access-control-allow-origin: *http://localhost:4200'; then
  ok "cors: preflight OPTIONS autoriza PUT da origem http://localhost:4200"
else
  bad "cors: preflight sem ACAO esperada (init aplicou o CORS XML?)"
fi

echo
if [[ "$FAIL" -ne 0 ]]; then
  echo "smoke: FALHOU" >&2
  exit 1
fi
echo "smoke: todos os checks passaram"
