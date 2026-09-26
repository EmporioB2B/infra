# 20260926 — TASK-INFRA-001 — Compose de desenvolvimento integrado

**Status:** concluída (arquivo imutável)
**Tipo:** implementação (artefatos deste repo)
**Origem:** plano aprovado na análise de bootstrap (`20260926_TASK-INFRA-000-analise-plano-bootstrap.md`)
**Execução:** 2026-09-26, autorizada pelo operador nesta conversa ("pode realizar a execução da task 1")

## Artefatos criados

- `compose/docker-compose.dev.yml` — projeto `emporio-dev`; serviços
  `postgres`, `backend` (nome obrigatório — proxy do Front), `radar` (sem
  `ports:`; `env_file` do `.env` local do repo Radar), `rustfs` +
  `rustfs-init` (espelho do override do Back + política anônima
  dev-only no bucket público via `rc bucket anonymous set download`),
  `mailpit` (`axllent/mailpit:v1.31.2`, STARTTLS+auth), `front-dev`
  (hot-reload via bind de `src/`+`public/`); redes `default`,
  `radar-net` (`internal: true`), `egress`; volumes `pgdata`,
  `rustfs-data`, `radar_state`; logging json-file rotacionado; toda
  publicação em `127.0.0.1`.
- `env/.env.dev.example` — placeholders; cobre todas as `${VAR:?}`.
- `scripts/up-dev.sh` — pré-checagens (daemon, `.env`, `.env` do Radar
  por caminho sem ler, irmãos vizinhos), certs dev, `config --quiet`,
  `up -d --build --wait`.
- `scripts/smoke.sh` — 9 checks (api UP, front, UI mailpit, radar
  ready via exec, backend→radar, buckets + marcador, leitura anônima
  de OBJETO no público, 403 no privado/quarentena).
- `scripts/gen-dev-certs.sh` — cert autoassinado SAN=`mailpit` +
  truststore PKCS12 do JVM (material efêmero em `certs/dev/`,
  git-ignorado).
- `docs/networks.md` — topologia, regras, testes de isolamento e o
  bloqueio do perfil `prodlike`.
- `.opencode/tasks/futuras/TASK-INFRA-006-dependencia-back-url-publica-emulador.md`
  — dependência nova no repo Back (ver "desvios" §2).
- TASK-INFRA-002: registrado achado do `imageBaseUrl:
  http://localhost:8081` no contrato do Front.

## Desvios do plano original — todos com evidência da execução

1. **`APP_STORAGE_R2_PUBLICO_BASE_URL` vazio em dev** (não
   `http://localhost:9000/public-local`):
   `StorageProperties.publicBaseUrlIsSafe` proíbe path na base e
   `R2StorageProvider.publicUrl` é `base + "/" + key`; no RustFS,
   path-style precisa de path e vhost-style foi testado → HTTP 403
   (`curl --resolve public-local.localhost:9000:127.0.0.1 ...`), com o
   MESMO objeto servindo 200 em path-style. Logo a URL pública gerada
   pelo app não tem como funcionar contra emulador local — vira
   TASK-INFRA-006 (repo Back). O bucket público em si funciona e é
   coberto pelo smoke com objeto-marcador anônimo.
2. **Mailpit não podia ser SMTP plano**: o Back valida no boot, com
   email habilitado, `auth`/`starttls.required`/`checkserveridentity`
   (fixos no `application.yml`) + `SMTP_USERNAME`/`SMTP_PASSWORD` não
   vazios — evidência: crash `EmailConfigurationException` no
   primeiro `up`. Solução infra-only: cert dev SAN=`mailpit` no
   Mailpit (`MP_SMTP_TLS_CERT/KEY`), `MP_SMTP_AUTH_ACCEPT_ANY=1` e
   truststore dedicado no JVM do backend via `JAVA_TOOL_OPTIONS`.
   Prova ponta a ponta: `curl --ssl-reqd --cacert /certs/mailpit.crt`
   de dentro do backend → mensagem na API do Mailpit.
3. **`RADAR_READ_TIMEOUT=10s` no dev** (default do Back é 1s): primeira
   consulta CNPJ com DuckDB/httpfs frio levou ~4,5s (seguintes ~0,3s);
   com 1s o percorso devolvendo 503 (`CONSULTA_CNPJ_INDISPONIVEL`)
   contra um radar que respondeu 200.
4. **`front-prod`/`prodlike` não criado**: bloqueadores da
   TASK-INFRA-002 continuam no repo Front (conferido: `allowedHosts
   ["localhost"]`, Dockerfile sem ARGs). Documentado no YAML e no
   `docs/networks.md`; E2E manual usa `front-dev`.
5. **Conflito de portas resolvido com stop não-destrutivo**: o
   container `emporio-b2b-rustfs-1` (stack de dev do PRÓPRIO Back,
   projeto `emporio-b2b`) ocupava `127.0.0.1:9000/9001` e foi pausado
   com `docker stop` (volume intacto; o operador o reata com o compose
   do Back).

## Evidências (2026-09-26, sessão de execução)

| Gate | Comando | Resultado |
|---|---|---|
| compose válido | `docker compose --env-file env/.env.dev -f compose/docker-compose.dev.yml config --quiet` | exit 0 |
| fail-fast sem env | `docker compose -f compose/... config --quiet` (sem env-file) | exit 1 com mensagens objetivas por variável |
| credencial placeholder | `compose run --rm -e RUSTFS_ACCESS_KEY=replace-with-anything rustfs-init` | exit 1 (validação do init); com env real: exit 0 |
| stack completo healthy | `up -d --wait` + `ps` | 6/6 healthy (init exited 0, `service_completed_successfully`) |
| smoke | `scripts/smoke.sh` | exit 0, 9/9 OK (reexecutado após edits finais) |
| isolamento host→radar | `curl 127.0.0.1:8000` | connection refused |
| isolamento cross-network | python one-shot na `default` → `radar:8000` | `gaierror` (nome nem resolve) |
| radar-net interna | `docker network inspect` | `Internal: true`; membros exatamente `backend` e `radar` |
| portas loopback | `docker ps` | tudo `127.0.0.1:`; radar sem mapeamento |
| SMTP real | `curl --ssl-reqd --user ... smtp://mailpit:1025` de dentro do backend + API `:8025/api/v1/messages` | mensagem `smoke-starttls` na caixa |
| percurso CNPJ | `POST :8080/api/v1/auth/register/validar-cnpj {"cnpj":"33000167000101"}` | HTTP 200 com dados reais (PETROBRAS) via Radar→R2 de teste |
| lint | `shellcheck` (container oficial) nos 3 scripts | exit 0 |
| segredos | `git status --short -uall`, `git check-ignore -v`, `git diff --check` | `.env.dev`, `certs/dev/*` ignorados; nada sensível no change set; diff limpo |
| auditoria | `context-revisor` em `context/` | edições aplicadas e revisadas (achados ≥MÉDIO arbitrados acima: §2-§5, pins no `servicos.md`, negativa do `DEV_PUBLICO`) |

## Aceite residual (pós-commite, do operador)

- Percorrer manualmente o percurso completo restante no navegador
  (pré-cadastro com confirmação por link do Mailpit → upload de
  documento → aprovação admin → login); a infraestrutura de cada etapa
  está validada, a navegação é manual por definição da decisão de
  escopo. Fotos no navegador ficam bloqueadas pela TASK-006 (emulador)
  com o bucket verificado pelo smoke.
- `chmod +x scripts/*.sh` antes do commit (bit de execução não é
  aplicável por agente neste repo).
- Decidir o destino do rascunho `docker-compose.yml` da raiz do
  workspace (aposentado por esta task; remoção é do operador).
