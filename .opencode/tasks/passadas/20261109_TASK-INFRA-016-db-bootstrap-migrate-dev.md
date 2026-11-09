# TASK-INFRA-016 — Bootstrap de roles e migrations no Compose dev

**Status:** promovida
**Data:** 2026-11-09
**Repo alvo:** `infra`
**Skills:** `compose-infra`, `secrets-env`, `verification-before-completion`

## Objetivo

Integrar o fluxo de banco DB-08 no Compose de desenvolvimento, garantindo que
roles e migrations sejam concluídos antes do Backend e do seed de admin.

## Entrega

- Integrado `database/bootstrap/roles.sql` canônico do rebase base, incluindo
  reconciliação idempotente de membership migrador pré-existente.
- Compose dev ordena `postgres → db-bootstrap → migrate → backend`; o Front
  inicia após Backend healthy. O Backend usa `emporio_app`; o job one-shot
  recebe exclusivamente `SPRING_FLYWAY_*` como `emporio_migrador`.
- `db-bootstrap` define credenciais de runtime/migration sem imprimi-las e
  valida tamanho mínimo, charset alfanumérico e distinção entre as três
  credenciais.
- `scripts/up-dev.sh` valida Backend em `main` limpo, informa o SHA, espera jobs
  one-shot por exit code e healthchecks dos serviços long-lived.
- Seed define o `search_path` dos schemas de domínio após V10.
- Atualizados `env/.env.dev.example`, `README.md`, `docs/networks.md` e contextos.
- Nenhum volume legado foi removido ou recriado; `emporio-dev_pgdata_v2` e os
  volumes v2 do stack foram mantidos.

## Evidências

- `sha256sum database/bootstrap/roles.sql` coincide com o arquivo no HEAD
  rebaseado (`ddddc5d`):
  `f80391cc9c8e5b05091f540687eb41a469c27c2fdb82575cf060cd1a6482c494`.
- `docker compose --env-file env/.env.dev -f compose/docker-compose.dev.yml
  config --quiet`: exit 0; o `.env.dev` real não foi lido/imprimido pelo agente.
- Validação da implementação original antes do rebase: `scripts/up-dev.sh
  --no-build` exit 0, jobs `db-bootstrap`, `migrate`, `rustfs-init` exit 0,
  Backend/Front healthy e seed completou. A imagem foi reutilizada; o SHA do
  source informado pelo preflight não comprova a proveniência dessa imagem.
- O seed foi executado novamente: identidade, vínculo, papel e nove
  capacidades permaneceram ativos; não inseriu duplicatas.
- `docker compose ps --all`: todos os serviços long-lived healthy; jobs
  one-shot concluídos com exit 0.
- `scripts/smoke.sh`: execução final exit 0, incluindo API, Front, scrape,
  redes `internal`, isolamento Radar, RustFS, mídia e CORS. O HTTP RED foi
  reportado como SKIP porque não houve tráfego `/api` desde o boot.
- Negativos explícitos: host não alcança Radar em 8000 nem listener de métricas
  em 8082; Grafana, fora da `radar-net`, não resolve/alcança `radar:8000`.
  Backend→Radar foi confirmado pelo smoke.
- `bash -n scripts/up-dev.sh scripts/seed-admin-dev.sh`: exit 0.
- ShellCheck dos dois scripts via `koalaman/shellcheck:stable`: exit 0.
- `git diff --check`: exit 0.
- `git check-ignore -v env/.env.dev`: confirma `.env.dev` ignorado.

## Resolução do rebase

- Mantidas as melhorias do `origin/main` que vieram junto: usuário admin do
  Postgres configurável (`POSTGRES_ADMIN_USER`), imagem `emporio-backend:dev`
  compartilhada entre Backend/migrate, bootstrap via `psql \getenv`, preflight
  flexível `BACKEND_BUILD_CONTEXT` e jobs one-shot aguardados pelo launcher.
- Removidos os blocos duplicados de `db-bootstrap`/`migrate` da versão antiga;
  preservados o caminho read-only do SQL, validação das três credenciais,
  `search_path` do seed e as documentações da mudança.
- A resolução final passou validação estática: Compose com o example,
  `bash -n`, ShellCheck e `git diff --check`. Não foi executado novo `up-dev`/
  smoke depois da resolução exata do rebase; o operador deve fazê-lo antes de
  finalizar o rebase/push.

## Observação de validação

A primeira execução do smoke após a subida reportou temporariamente o target
`emporio-radar` como não-UP; nessa janela houve timeout de healthcheck do
Radar. O target voltou a `up=1`, o serviço ficou healthy e a execução seguinte
do smoke passou sem alteração de artefatos entre as duas execuções. O fato foi
registrado como transitório, não como prova de estabilidade prolongada; se
reaparecer, investigar o healthcheck/pressão do Radar com o dono do repositório
irmão.

## Limitações

- Validação executada somente em desenvolvimento local; não houve acesso a
  Supabase, produção, Dokploy ou Cloudflare.
- O volume legado `emporio-dev_pgdata` foi deixado intacto conforme política.
- Nenhum código de repositório irmão foi alterado.
