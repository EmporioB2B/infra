# Estado atual

Fotografia factual de 2026-09-26. Não é cronologia de tasks.

## O que existe

- Repos de aplicação independentes na org `EmporioB2B`: `Backend_Java`,
  `Front_Angular`, `Radar_Middleware_Python`, `Hermes_Robo_Whats_Python`.
- Este repositório (`infra/`) está configurado: `AGENTS.md`, `.gitignore`
  (cobre `.env.*` reais e material TLS `*.crt/*.key/*.p12`) e `.opencode`
  com agentes (`arquiteto` primary com Git mutável interditado;
  `context-revisor` subagent, único editor de `context/`), contexto
  (incluindo `servicos.md` e `decisoes.md` refinados por pesquisa em
  documentação oficial), 6 skills canônicas (`compose-infra`,
  `cloudflare-edge`, `dokploy-deploy`, `cicd-ghcr`, `secrets-env`,
  `verification-before-completion`), histórico da análise de bootstrap e
  tasks futuras versionadas (TASK-INFRA-001 a 006).
- Stack de desenvolvimento EXISTENTE em `compose/docker-compose.dev.yml`
  (TASK-INFRA-001), validado em 2026-09-26: todos os serviços healthy,
  `scripts/smoke.sh` exit 0, isolamento da `radar-net` provado (internal,
  sem portas, inalcançável do host e de container fora da rede) e SMTP
  STARTTLS+auth testado ponta a ponta contra o Mailpit. Artefatos do
  mesmo change set: `env/.env.dev.example` (cobre todas as
  `${VAR:?}` do compose; placeholders apenas), `scripts/up-dev.sh`,
  `scripts/smoke.sh`, `scripts/gen-dev-certs.sh` e `docs/networks.md`.
  O perfil `prodlike` (`front-prod`) NÃO foi criado — bloqueado pela
  TASK-INFRA-002; o serviço está documentado como planejado no YAML e no
  doc. Dependência nova descoberta na execução: TASK-INFRA-006
  (repo Backend_Java — URL pública de foto contra emulador S3 local).
  O change set inteiro ainda está SEM commit (repositório sem histórico;
  Git é do operador — enquanto não commitado, os artefatos valem para a
  máquina local, não para clones).
- Ainda NÃO existem neste repo: `compose/docker-compose.e2e.yml` e
  `docker-compose.prod.yml`, `env/.env.prod.example`, `cloudflare/`,
  `scripts/e2e-run.sh`, `docs/deploy-dokploy.md`, `docs/rollback.md`,
  `docs/cicd.md` nem `.github/workflows/` — a cargo das
  TASK-INFRA-003/004/005.
- Dockerfiles de produção prontos e revisados nos 3 projetos principais
  (Back: temurin 25 + usuário não-root + healthcheck em 8081; Front: SSR
  node:22 porta 4000; Radar: python 3.12 slim porta 8000 sem portas
  publicadas).
- Overrides de dev maduros no repo do Back: `docker-compose.yml`
  (backend + postgres-dev + postgres-test), `docker-compose.rustfs.yml`
  (R2 local com bootstrap idempotente de buckets e credencial read-only) e
  `docker-compose.test.yml` — o `docker-compose.dev.yml` deste repo
  espelha o override RustFS do Back (único desvio: política anônima no
  bucket público, dev-only).
- Rascunho `docker-compose.yml` na raiz do workspace (nome `ifra-vps`, com
  cloudflared + traefik): **não funcional** (nomes de env divergem do
  código; healthcheck da api aponta porta/path errados). Aposentado pela
  TASK-INFRA-001; ainda presente no disco — remover ou manter é decisão
  final do operador.
- Nenhum repo possui `.github/workflows` — não existe CI hoje.

## Fatos dos serviços que afetam a infra

- Back serve HTTP puro em 8080 com `forward-headers-strategy: framework`;
  actuator em 8081; profile `container` exige 6 envs sem default; profile
  `prod` exige `APP_PASSWORD_RESET_BASE_URL`.
- Radar valida o endpoint R2 como `https://<account>.r2.cloudflarestorage.com`
  (S3 local é rejeitado) e o ViaCEP como `https://viacep.com.br/ws`; não tem
  autenticação de entrada; estado em SQLite reconstruível.
- Front compila `apiBaseUrl`/`imageBaseUrl` no bundle (produção atual:
  vazios) e o SSR valida `Host` contra `allowedHosts` (hoje só `localhost`).
  Ambos são bloqueadores de produção e viram task no repo Front
  (TASK-INFRA-002 rastreia a dependência).
- O proxy de dev do Front aponta para `http://backend:8080` — o serviço da
  api no compose dev deve se chamar `backend`.
- Back com `APP_EMAIL_ENABLED=true` valida SMTP no boot: exige credenciais
  não vazias e STARTTLS obrigatório + auth (propriedades fixas no
  `application.yml`) — em produção o provedor real precisa suportar
  STARTTLS+AUTH (`SMTP_PORT` configurável; default 587) (`servicos.md`).
- A URL pública de foto gerada pelo Back é inviável contra emulador S3
  local com path (validação proíbe) ou vhost (RustFS retorna 403) —
  bloqueio registrado como TASK-INFRA-006; o dev roda com
  `APP_STORAGE_R2_PUBLICO_BASE_URL` vazio.

## Pendências conhecidas

- Tasks TASK-INFRA-001 a 006 (planejamento local em `../tasks/futuras/`,
  não versionado desde 2026-09-26). Estado:
  001 concluída e arquivada (`../passadas/20260926_TASK-INFRA-001-compose-dev-integrado.md`),
  aguardando apenas o commit do operador — o repositório ainda não tem
  histórico, logo os artefatos valem para esta máquina mas não para
  clones; 002 abre dependências no repo Front; 003/004/005 não
  iniciadas; 006 é dependência de código no repo Backend_Java.
- Backlog futuro (não bloqueia o MVP de deploy): mTLS/gateway interno do
  Radar (TASK-080/006 no repo Back e TASK-006 no repo Radar), staging,
  monitoramento/uptime, backup do Supabase, entrada do Hermes no stack,
  pin de imagem por sha no Dokploy.
- Intenção de produto registrada apenas no rascunho aposentado da raiz
  (destruído em 2026-09-26): integração de **gateway de pagamento**
  (`PAYMENT_GATEWAY_BASE_URL/CLIENT_ID/CLIENT_SECRET/TOKEN/
  WEBHOOK_SECRET`). Nenhum repo irmão tem código do assunto; quando sair
  do papel, vira feature no Backend_Java e a Infra trata do webhook
  público e egress do gateway no compose de produção.
- Decisões de produto pendentes que afetam a borda: domínio `www` (redirect
  na CF), política de cache do bucket público `media`.
