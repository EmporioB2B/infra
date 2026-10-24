#!/usr/bin/env bash
# Smoke do stack de desenvolvimento integrado (TASK-INFRA-001).
#
# Uso: scripts/smoke.sh   (assumes o stack já sobe por up-dev.sh)
#
# Verifica com evidência, sem alterar nada:
#   1. api actuator UP (127.0.0.1:8081);
#   2. front dev-server responde (127.0.0.1:4200);
#   3. UI do Mailpit responde (127.0.0.1:8025);
#   4. Grafana responde em loopback e Loki está pronto;
#   5. um label de container chega ao Loki via Vector;
#   6. media-gateway responde em loopback e publica somente /public/asset;
#   7. radar /health/ready (via exec — não tem porta no host);
#   8. backend alcança radar:8000 (rede radar-net);
#   9. health do RustFS + três buckets presentes (via one-shot rc);
#  10. bucket público lê anonimamente (fotos do navegador);
#  11. bucket privado/quarentena NEGAM leitura anônima (403);
#  12. media-gateway bloqueia buckets privados, listagem, escrita e paths fora
#      de /public/asset;
#  13. preflight CORS permite o PUT directo do navegador (:4200 → :9000);
#  14. CORS do bucket de quarentena mantém GET e HEAD nas origens dev;
#  15. credencial dedicada lê só o prefixo de quarentena e nega alterações,
#      listagem e leitura privada.
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

if ! compose config --quiet; then
  echo "ERRO: Compose inválido; confira env/.env.dev (incluindo GRAFANA_ADMIN_PASSWORD)." >&2
  exit 1
fi

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

# 4. Grafana e Loki.
GRAFANA_BIND="$(compose port grafana 3000 2>/dev/null || true)"
if [[ -n "$GRAFANA_BIND" ]] && curl -fsS --max-time 5 -o /dev/null "http://$GRAFANA_BIND/api/health"; then
  ok "grafana: API de health em http://$GRAFANA_BIND"
else
  bad "grafana: UI/API de health não respondeu"
fi

if compose exec -T grafana wget -q -O /dev/null http://loki:3100/ready 2>/dev/null; then
  ok "loki: /ready acessível pela rede de observabilidade"
else
  bad "loki: /ready falhou pela rede de observabilidade"
fi

# The single-quoted script is intentionally evaluated inside the Grafana
# container, not by this outer shell.
# shellcheck disable=SC2016
if compose exec -T grafana sh -c \
  'i=0; while [ "$i" -lt 12 ]; do values=$(wget -q -O - http://loki:3100/loki/api/v1/label/container/values || true); case "$values" in *backend*) exit 0;; esac; i=$((i+1)); sleep 2; done; exit 1' \
  2>/dev/null; then
  ok "logs: container backend chegou ao Loki via Vector"
else
  bad "logs: container backend não chegou ao Loki via Vector"
fi

# 5. media-gateway: a porta real vem do binding do Compose (default 9002).
MEDIA_GATEWAY_BIND="$(compose port media-gateway 80 2>/dev/null || true)"
if [[ -n "$MEDIA_GATEWAY_BIND" ]]; then
  MEDIA_GATEWAY_URL="http://$MEDIA_GATEWAY_BIND"
  if curl -fsS --max-time 5 -o /dev/null "$MEDIA_GATEWAY_URL/healthz"; then
    ok "media-gateway: health em $MEDIA_GATEWAY_URL"
  else
    bad "media-gateway: health sem resposta em $MEDIA_GATEWAY_URL"
  fi
else
  MEDIA_GATEWAY_URL="http://127.0.0.1:9002"
  bad "media-gateway: Compose não retornou o binding da porta 80"
fi

# 7. radar via exec (sem porta publicada no host — é a regra)
if compose exec -T radar python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health/ready')" 2>/dev/null; then
  ok "radar: /health/ready (via exec, sem porta no host)"
else
  bad "radar: /health/ready falhou via exec"
fi

# 8. backend -> radar pela radar-net
if compose exec -T backend curl -fsS --max-time 5 http://radar:8000/health/live -o /dev/null; then
  ok "radar-net: backend alcança radar:8000/health/live"
else
  bad "radar-net: backend NÃO alcança radar:8000"
fi

# 9. buckets presentes + objeto-marcador no público (one-shot rc na rede
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
      rc cp --quiet /tmp/marker local/public-local/public/asset/smoke-check.txt >/dev/null 2>&1 || exit 1
      printf quarantine > /tmp/quarantine-marker
      rc cp --quiet /tmp/quarantine-marker local/quarantine-local/quarantine/smoke-policy-check.txt >/dev/null 2>&1 || exit 1
      printf outside > /tmp/outside-marker
      rc cp --quiet /tmp/outside-marker local/quarantine-local/outside/smoke-policy-check.txt >/dev/null 2>&1 || exit 1
      rc cp --quiet /tmp/outside-marker local/private-local/private/smoke-policy-check.txt >/dev/null 2>&1 || exit 1
      echo present
    ' 2>/dev/null || true
)"
if [[ "$BUCKETS" == "present" ]]; then
  ok "rustfs: buckets presentes + marcador público enviado"
else
  bad "rustfs: verificação de buckets/marcador falhou"
fi

# 10. leitura anônima direta do OBJETO no público (o navegador não tem
#    credencial S3). O check seguinte prova o caminho usado pela aplicação.
if [[ "$(curl -fsS --max-time 5 "http://127.0.0.1:9000/public-local/public/asset/smoke-check.txt" 2>/dev/null)" == "smoke" ]]; then
  ok "rustfs: objeto anônimo lê sem credencial no public-local (fotos do navegador OK)"
else
  bad "rustfs: leitura anônima do objeto em public-local falhou"
fi

# 11. privado e quarentena fechados para anônimo (espera HTTP 403)
for bucket in private-local quarantine-local; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:9000/$bucket/" || true)"
  if [[ "$code" == "403" ]]; then
    ok "rustfs: $bucket nega leitura anônima (403)"
  else
    bad "rustfs: $bucket respondeu HTTP '$code' (esperado 403)"
  fi
done

# 12. media-gateway: usa a base sem path, encaminha somente o namespace
#     público opaco e não funciona como proxy aberto para outros buckets,
#     paths ou métodos.
if [[ "$(curl -fsS --max-time 5 "$MEDIA_GATEWAY_URL/public/asset/smoke-check.txt" 2>/dev/null)" == "smoke" ]]; then
  ok "media-gateway: objeto público acessível pela URL da aplicação"
else
  bad "media-gateway: objeto público não foi servido"
fi

head_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
  -X HEAD "$MEDIA_GATEWAY_URL/public/asset/smoke-check.txt" || true)"
if [[ "$head_code" == "200" ]]; then
  ok "media-gateway: HEAD do objeto público retorna 200"
else
  bad "media-gateway: HEAD respondeu HTTP '$head_code' (esperado 200)"
fi

for path in /public/ /public/asset/ /public-local/public/asset/ \
  /private-local/private/smoke-policy-check.txt \
  /quarantine-local/quarantine/smoke-policy-check.txt; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$MEDIA_GATEWAY_URL$path" || true)"
  if [[ "$code" == "404" ]]; then
    ok "media-gateway: rota $path rejeitada (404)"
  else
    bad "media-gateway: rota $path respondeu HTTP '$code' (esperado 404)"
  fi
done

for method in PUT POST DELETE; do
  write_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X "$method" \
    --data 'blocked' "$MEDIA_GATEWAY_URL/public/asset/smoke-write-check.txt" || true)"
  if [[ "$write_code" == "405" ]]; then
    ok "media-gateway: $method no namespace público rejeitado (405)"
  else
    bad "media-gateway: $method respondeu HTTP '$write_code' (esperado 405)"
  fi
done

# 13. preflight CORS do direct-upload: navegador (origem :4200) -> rustfs:9000.
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

# 14. O endpoint novo devolve leitura pré-assinada; validar explicitamente que o
# bucket de quarentena continua aceitando os métodos de leitura para todas as
# origens locais configuradas no init. Nenhuma credencial é usada aqui.
for origin in http://localhost:4200 http://localhost:4000 http://127.0.0.1:4200; do
  for method in GET HEAD; do
    READ_PREFLIGHT="$(curl -s -o /dev/null -D - --max-time 5 --resolve rustfs:9000:127.0.0.1 \
      -X OPTIONS 'http://rustfs:9000/quarantine-local/cors-read-probe' \
      -H "Origin: $origin" \
      -H "Access-Control-Request-Method: $method" \
      || true)"
    ALLOW_METHODS="$(printf '%s' "$READ_PREFLIGHT" \
      | grep -Fi 'access-control-allow-methods:' || true)"
    if printf '%s' "$READ_PREFLIGHT" \
      | grep -Fqi "access-control-allow-origin: $origin" \
      && [[ "$ALLOW_METHODS" == *"$method"* ]]; then
      ok "cors: quarentena autoriza $method para $origin"
    else
      bad "cors: quarentena não autoriza $method para $origin"
    fi
  done
done

# 15. policy efetiva da credencial dedicada. O bucket público não é testado
# aqui de forma negativa: no dev ele é deliberadamente anônimo; isso é uma
# regra independente da policy desta credencial.
POLICY_CHECK="$(
  docker run --rm --network "$NET" \
    --env-file "$ENV_FILE" \
    --entrypoint /bin/sh "$RC_IMAGE" -c '
      rc alias set --quiet --region "${RUSTFS_REGION:-us-east-1}" --bucket-lookup path \
        quarantine http://rustfs:9000 "$RUSTFS_READ_ONLY_QUARANTINE_ACCESS_KEY" \
        "$RUSTFS_READ_ONLY_QUARANTINE_SECRET_KEY" >/dev/null 2>&1 || exit 1
      rc cp --quiet quarantine/quarantine-local/quarantine/smoke-policy-check.txt \
        /tmp/quarantine-read >/dev/null 2>&1
      get_status=$?
      if test "$(cat /tmp/quarantine-read 2>/dev/null)" = quarantine; then
        content_status=0
      else
        content_status=1
      fi
      rc ls --quiet quarantine/quarantine-local >/dev/null 2>&1
      list_status=$?
      printf denied > /tmp/quarantine-denied
      rc cp --quiet /tmp/quarantine-denied \
        quarantine/quarantine-local/quarantine/smoke-policy-denied.txt >/dev/null 2>&1
      put_status=$?
      rc rm --quiet quarantine/quarantine-local/quarantine/smoke-policy-check.txt \
        >/dev/null 2>&1
      delete_status=$?
      rc cp --quiet quarantine/quarantine-local/outside/smoke-policy-check.txt \
        /tmp/outside-read >/dev/null 2>&1
      outside_status=$?
      rc cp --quiet quarantine/private-local/private/smoke-policy-check.txt \
        /tmp/private-read >/dev/null 2>&1
      private_status=$?
      if [ "$get_status" -eq 0 ] && [ "$content_status" -eq 0 ] \
        && [ "$list_status" -ne 0 ] \
        && [ "$put_status" -ne 0 ] && [ "$delete_status" -ne 0 ] \
        && [ "$outside_status" -ne 0 ] && [ "$private_status" -ne 0 ]; then
        printf policy-ok
      else
        exit 1
      fi
    ' 2>/dev/null
)"
if [[ "$POLICY_CHECK" == "policy-ok" ]]; then
  ok "rustfs: credencial dedicada limitada a GetObject em quarantine/"
else
  bad "rustfs: policy da credencial dedicada não passou os testes negativos"
fi

echo
if [[ "$FAIL" -ne 0 ]]; then
  echo "smoke: FALHOU" >&2
  exit 1
fi
echo "smoke: todos os checks passaram"
