# Estado atual

Fotografia factual vigente. Não é cronologia de tasks.

## O que existe

- Repos de aplicação independentes na org `EmporioB2B`: `Backend_Java`,
  `Front_Angular`, `Radar_Middleware_Python`, `Hermes_Robo_Whats_Python`.
- Este repositório (`infra/`) está configurado: `AGENTS.md`, `.gitignore`
  (cobre `.env.*` reais e material TLS `*.crt/*.key/*.p12`) e `.opencode`
  com agentes (`arquiteto` primary com Git mutável interditado;
  `context-revisor` subagent, único editor de `context/`), contexto
  (incluindo `servicos.md` e `decisoes.md` refinados por pesquisa em
  documentação oficial), 7 skills canônicas (`compose-infra`,
  `cloudflare-edge`, `dokploy-deploy`, `cicd-ghcr`, `secrets-env`,
  `observability-logs`, `verification-before-completion`), histórico da análise de bootstrap e
  tarefas locais do operador em `.opencode/tasks/`.
- **Existente — dev:** stack de desenvolvimento em
  `compose/docker-compose.dev.yml`, com todos os serviços de longa duração,
  `media-gateway` local para fotos públicas, `scripts/smoke.sh`, policy
  dedicada, isolamento da `radar-net`, SMTP dev e observabilidade local
  Vector/Loki/Grafana. Arquivos de suporte:
  `README.md` (setup dev, logs no Grafana e requisito de hosts do upload direto),
  `env/.env.dev.example` (cobre todas as
  `${VAR:?}` do compose; placeholders apenas), `scripts/up-dev.sh`,
  `scripts/init-rustfs.sh`, `scripts/smoke.sh`, `scripts/gen-dev-certs.sh` e
  `docs/networks.md`/`docs/observability.md`.
- **Existente — dev:** os logs dos serviços de aplicação seguem stdout/stderr
  pelo driver Docker `fluentd` assíncrono para `vector`; Loki e Grafana não
  montam Docker socket, a UI do Grafana fica em loopback e os dados usam
  `loki-data`, `vector-data` e `grafana-data`. O Vector também não monta o
  socket; seu healthcheck consulta a API local de liveness, enquanto a
  validação de configuração e o smoke verificam a chegada de um log do Backend
  ao Loki. O bootstrap aguarda os healthchecks
  declarados (`compose/docker-compose.dev.yml:50-114`) e o smoke contém a prova
  de ingestão (`scripts/smoke.sh:71-94`).
- **Planejado — dev profile:** o perfil `prodlike` (`front-prod`) NÃO foi
  criado — bloqueado pela TASK-INFRA-002; o serviço está documentado no YAML e no
  doc.
- **Existente — dev:** o `media-gateway` publica somente
  `127.0.0.1:9002` por default (`MEDIA_GATEWAY_PORT` é opcional) e encaminha
  `/public/asset/...` para `rustfs:9000/public-local/public/asset/...`; o
  container escuta na porta 80, o health é `/healthz`, e somente `GET`/`HEAD`
  são aceitos nesse namespace. Escrita, listagem, raiz, privado e quarentena
  são rejeitados. O Backend recebe
  `APP_STORAGE_R2_PUBLICO_BASE_URL=http://localhost:9002` em dev; a URL pública
  de fotos é utilizável pelo navegador. O RustFS continua sendo acessado
  diretamente pelo navegador apenas para upload pré-assinado, com o hostname
  `rustfs:9000` (fontes: `compose/docker-compose.dev.yml:266-291`,
  `compose/media-gateway.nginx.conf:16-37`,
  `env/.env.dev.example:59-65`).
- Existe `scripts/seed-admin-dev.sh` para o stack local: ele semeia, em uma
  transação, o usuário de teste, o vínculo `ATIVO` na organização
  `PLATAFORMA`, o papel `ADMIN_NEGOCIO`/`PLATAFORMA` e as nove capacidades
  administrativas de plataforma. A senha do fixture vem de
  `ADMIN_DEV_PASSWORD` no ambiente local ignorado e não é impressa. O fixture
  continua somente de dev e não cria `perfil_usuario` (fonte do artefato:
  `scripts/seed-admin-dev.sh:84-229`;
  schema/contratos: `Backend_Java/src/main/resources/db/migration/V2__autenticacao_autorizacao.sql:109-145,376-424`).
- **Existente — dev:** `scripts/up-dev.sh` inicia RustFS antes do restante do stack, confirma seu
  attachment à rede default do projeto e recria somente o container RustFS
  se a rede estiver ausente, preservando `rustfs-data`. O job
  `rustfs-init` usa `scripts/init-rustfs.sh` read-only, cria as credenciais
  read-only geral e dedicada da quarentena, espera o endpoint
  `rustfs:9000` com até 15 tentativas separadas por 2 segundos e o launcher
  imprime os logs do job caso a subida completa falhe; o launcher também
  anuncia a URL do `media-gateway` após a subida.
- **Planejado — produção:** `APP_STORAGE_R2_PUBLICO_BASE_URL` aponta para
  `https://media.emporiob2b.com.br`, servido diretamente pelo bucket público
  R2, sem `media-gateway` na VPS. `docs/storage-r2-handoff.md` descreve a
  credencial dedicada, prefixo `quarantine/`, policy somente `s3:GetObject` e
  CORS `GET`/`HEAD`; não há aplicação no R2, Cloudflare ou Dokploy.
- Ainda NÃO existem neste repo: `compose/docker-compose.e2e.yml` e
  `docker-compose.prod.yml`, `env/.env.prod.example`, `cloudflare/`,
  `scripts/e2e-run.sh`, `docs/deploy-dokploy.md`, `docs/rollback.md`,
  `docs/cicd.md` nem `.github/workflows/` — a cargo das
  TASK-INFRA-003/004/005.
- Dockerfiles de produção prontos e revisados nos 3 projetos principais
  (Back: temurin 25 + usuário não-root + healthcheck em 8081; Front: SSR
  node:22 porta 4000; Radar: python 3.12 slim porta 8000 sem portas
  publicadas).
- **Existente — Backend_Java:** Overrides de dev maduros no repo do Back: `docker-compose.yml`
  (backend + postgres-dev + postgres-test), `docker-compose.rustfs.yml`
  (R2 local com bootstrap idempotente de buckets e credenciais read-only
  geral/dedicada da quarentena) e
  `docker-compose.test.yml` — o `docker-compose.dev.yml` deste repo
  espelha o override RustFS do Back; além da política anônima dev-only no
  bucket público, o repo Infra adiciona o `media-gateway` para contornar o
  path-style na URL pública sem expor os outros buckets.
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
- **Existente — dev:** a validação do Backend continua proibindo path na base
  pública (`StorageProperties.publicBaseUrlIsSafe`), mas o
  `media-gateway` fornece a base sem path e traduz o namespace fixo
  `public/asset/` para o bucket `public-local`; o dev agora recebe
  `APP_STORAGE_R2_PUBLICO_BASE_URL=http://localhost:9002` por default.

## Pendências conhecidas

- Tasks TASK-INFRA-001 a 006 (planejamento local; não versionado desde
  2026-09-26). Estado:
  001 concluída e arquivada (`../passadas/20260926_TASK-INFRA-001-compose-dev-integrado.md`),
  aguardando apenas o commit do operador — o repositório ainda não tem
  histórico, logo os artefatos valem para esta máquina mas não para
  clones; 002 abre dependências no repo Front; 003/004/005 não
  iniciadas; o follow-up de TASK-INFRA-006 foi arquivado em
  `../passadas/20261023_TASK-INFRA-006-followup-contrato-9002.md`; o gateway
  dev vigente está implementado nos artefatos acima; TASK-INFRA-010 foi
  arquivada com a observabilidade local, mantendo a etapa de provider
  Grafana Cloud no Dokploy como pendência de produção.
  TASK-INFRA-009 tem wiring dev e gates runtime validados; o handoff
  [PLANEJADO — produção] continua sem aplicação no R2.
- Backlog futuro (não bloqueia o MVP de deploy): mTLS/gateway interno do
  Radar (TASK-080/006 no repo Back e TASK-006 no repo Radar), staging,
  monitoramento/uptime, backup do Supabase, entrada do Hermes no stack,
  pin de imagem por sha no Dokploy. A integração de produção com Grafana Cloud
  Loki permanece planejada: o Dokploy configura o provider e instala
  `dokploy-vector`; nenhum Loki/Grafana entra no Compose da aplicação.
- Intenção de produto registrada apenas no rascunho aposentado da raiz
  (destruído em 2026-09-26): integração de **gateway de pagamento**
  (`PAYMENT_GATEWAY_BASE_URL/CLIENT_ID/CLIENT_SECRET/TOKEN/
  WEBHOOK_SECRET`). Nenhum repo irmão tem código do assunto; quando sair
  do papel, vira feature no Backend_Java e a Infra trata do webhook
  público e egress do gateway no compose de produção.
- Decisões de produto pendentes que afetam a borda: domínio `www` (redirect
  na CF), política de cache do bucket público `media`.
