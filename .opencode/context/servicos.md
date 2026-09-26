# Catálogo de serviços

Fatos verificados nos repositórios em 2026-09-26 (commits da data). Este
catálogo é a fonte canônica de nomes de env, portas e restrições para os
composes deste repositório. Rascunhos antigos (como o
`docker-compose.yml` da raiz do workspace, que usava `DB_HOST`,
`SECRET_JWT`, `R2_ENDPOINT`, `API_BASE_URL` etc.) não refletem o código e
estão aposentados.

## Backend_Java (serviço `api` em prod; `backend` em dev)

- Repo: `EmporioB2B/Backend_Java`; imagem alvo:
  `ghcr.io/emporiob2b/backend-java`.
- Imagem: `eclipse-temurin:25-jre-jammy`, usuário `emporio` (10001),
  `EXPOSE 8080 8081`; healthcheck da imagem:
  `curl --fail http://127.0.0.1:8081/actuator/health`.
- Portas: aplicação **8080**; management/actuator **8081** (health/info;
  nunca rotear pelo túnel; em dev pode publicar em 127.0.0.1).
- Profiles: `dev`, `test`, `container`, `prod`. Combinações vigentes:
  dev em compose `dev,container`; produção `prod,container`.
- Envs **obrigatórias sem default** no profile `container`:
  `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`,
  `SPRING_DATASOURCE_PASSWORD`, `APP_JWT_SECRET`,
  `APP_CORS_ALLOWED_ORIGINS`, `RADAR_BASE_URL`.
  No profile `prod` soma-se `APP_PASSWORD_RESET_BASE_URL`.
- Envs relevantes por escopo:
  - Radar: `RADAR_BASE_URL` (dev/prod: `http://radar:8000`),
    `RADAR_CONNECT_TIMEOUT`, `RADAR_READ_TIMEOUT`,
    `RADAR_MAX_RESPONSE_BYTES`.
  - Storage R2: `APP_STORAGE_PROVIDER` (`DISABLED|LOCAL|R2`),
    `APP_STORAGE_ALLOW_INSECURE_HTTP`,
    `APP_STORAGE_READ_WRITE_R2_{ENDPOINT,ACCESS_KEY_ID,SECRET_ACCESS_KEY}`,
    `APP_STORAGE_READ_ONLY_R2_{ENDPOINT,ACCESS_KEY_ID,SECRET_ACCESS_KEY}`,
    `APP_STORAGE_R2_{QUARENTENA,PRIVADO,PUBLICO}_BUCKET`,
    `APP_STORAGE_R2_{QUARENTENA,PRIVADO,PUBLICO}_PREFIX`,
    `APP_STORAGE_R2_REGION`, `APP_STORAGE_R2_PUBLICO_BASE_URL`,
    `APP_STORAGE_R2_PRESIGNED_{UPLOAD,READ}_TTL`,
    `APP_STORAGE_DIRECT_UPLOAD_MAX_BYTES`. Não existe
    `APP_STORAGE_R2_DEV_PUBLICO_BASE_URL` no código (nome de rascunho
    antigo, nunca implementado; só a base única
    `APP_STORAGE_R2_PUBLICO_BASE_URL` é vinculada em
    `application.yml`/`application-dev.yml`).
  - Restrição da URL pública de foto: `StorageProperties.publicBaseUrlIsSafe`
    proíbe path na base do public-base-url (aceita apenas null, vazio ou
    `/`) e `R2StorageProvider.publicUrl()` compõe `base + "/" + storageKey`.
    Em emulador S3 local sem vhost (RustFS) isso é um beco sem saída:
    path-style exige o bucket no path (a validação proíbe) e vhost-style
    retornou HTTP 403 (evidência 2026-09-26). O dev roda com a base vazia;
    a URL pública de foto via emulador local é inviável enquanto o código
    for este — dependência registrada em TASK-INFRA-006 (repo
    Backend_Java). Em produção a base é o domínio custom da borda sem path
    e não há bloqueio.
  - Email: `APP_EMAIL_ENABLED`, `APP_EMAIL_HEALTH_ENABLED`, `SMTP_HOST`,
    `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `APP_EMAIL_FROM`,
    `APP_EMAIL_REPLY_TO`, `APP_EMAIL_MEDIA_BASE_URL` (default prod:
    `https://media.emporiob2b.com.br`). Com `APP_EMAIL_ENABLED=true`,
    `EmailConfiguration.validateEnabledConfiguration` falha o boot sem
    `SMTP_USERNAME`/`SMTP_PASSWORD` não vazios e sem SMTP autenticado com
    STARTTLS obrigatório: as propriedades JavaMail são fixas no
    `application.yml` (`mail.smtp.auth=true`, `starttls.enable=true`,
    `starttls.required=true`, `ssl.checkserveridentity=true`, sem
    `ssl.trust`, `test-connection=false`, timeouts finitos). Vale para
    qualquer compose (dev e prod): o servidor SMTP — emulador ou provedor
    real — precisa suportar STARTTLS+AUTH; SMTP plano não funciona. Em
    dev isso é atendido pelo Mailpit com certificado autoassinado
    (SAN=`mailpit`) + truststore do JVM (ver `arquitetura.md`, seção dev).
  - URLs públicas do Front: `CADASTRO_CONFIRMATION_BASE_URL`,
    `APP_PASSWORD_RESET_BASE_URL` (prod: `https://emporiob2b.com.br`).
  - Auth/cookie: `APP_AUTH_COOKIE_SECURE` (o profile `container` já
    defaulta `true` — em dev sobre HTTP puro é preciso override explícito
    `false`, senão o cookie de refresh não é aceito em `localhost`),
    `APP_AUTH_COOKIE_SAME_SITE` (default `Lax`; suficiente — front e api são
    same-site), `APP_AUTH_COOKIE_{NAME,HTTP_ONLY,PATH}`.
  - Rate limit por IP atrás de proxy: `VALIDACAO_CNPJ_TRUSTED_PROXIES`
    (produção: rede do túnel/containers).
- Banco: dev/test `postgres:16-alpine` local; **produção Supabase externo**
  (`SPRING_DATASOURCE_URL` jdbc com SSL). Flyway é dono do schema.
- Verificação canônica: `./mvnw -B verify` (Testcontainers; exige daemon
  Docker; ~3 min em 8 CPUs).

## Radar_Middleware_Python (serviço `radar`)

- Repo: `EmporioB2B/Radar_Middleware_Python`; imagem alvo:
  `ghcr.io/emporiob2b/radar-middleware`.
- Imagem: `python:3.12.14-slim-bookworm`, usuário `radar` (10001),
  `ENTRYPOINT radar-middleware`; diretórios da imagem:
  `/var/lib/radar-middleware/{logs,state}` (dono `radar:radar`).
- Porta interna: **8000** (`PORT`). **Nunca publicar no host**; sem
  `ports:` em nenhum compose.
- Envs reais (Pydantic settings, `env_prefix=""`, case-sensitive):
  `ENVIRONMENT`, `LOG_LEVEL`, `PORT`,
  `CLOUDFLARE_KEY_ID`, `CLOUDFLARE_SECRET_KEY`, `CLOUDFLARE_URL_ACCESS`,
  `CLOUDFLARE_BUCKET_NAME`, `CLOUDFLARE_REGION`,
  `CLOUDFLARE_CEP_OBJECT_KEY`, `CLOUDFLARE_CEP_MANIFEST_OBJECT_KEY`,
  `CLOUDFLARE_ESTABELECIMENTOS_OBJECT_KEY`,
  `CLOUDFLARE_EMPRESAS_OBJECT_KEY`, `CLOUDFLARE_SOCIOS_OBJECT_KEY`,
  `CLOUDFLARE_NUCLEO_RFB_MANIFEST_OBJECT_KEY`,
  `SQLITE_PATH`, `SQLITE_BUSY_TIMEOUT_MS`, `SQLITE_WRITE_RETRY_ATTEMPTS`,
  `SQLITE_WRITE_DEADLINE_SECONDS`, `SQLITE_WRITE_BACKOFF_SECONDS`,
  `SQLITE_WRITE_JITTER_SECONDS`,
  `VIACEP_BASE_URL`, `VIACEP_TIMEOUT`, `VIACEP_MAX_RESPONSE_BYTES`.
- Restrições duras do `config.py` (validação sem rede):
  - `CLOUDFLARE_URL_ACCESS` **somente** `https://<account>.r2.cloudflarestorage.com`
    (sem porta, sem path) — S3 local (RustFS/MinIO) é rejeitado; dev usa o
    bucket R2 de teste real, credenciais no `.env` local do repo Radar.
  - `VIACEP_BASE_URL` somente `https://viacep.com.br/ws`.
- Estado: SQLite em `SQLITE_PATH` (volume em
  `/var/lib/radar-middleware/state`); reconstruível do R2 no bootstrap.
- Rotas: `GET /health/live`, `GET /health/ready`,
  `GET /internal/v1/ceps/{cep}`,
  `GET /internal/v1/estabelecimentos/{cnpj}`,
  `GET /internal/v1/estabelecimentos/{cnpj}/dados-cadastrais`,
  `GET /internal/v1/empresas/{cnpj_basico}/socios`.
- Sem autenticação serviço-a-serviço hoje; isolamento por rede Docker
  interna exclusiva. Verificação canônica:
  `uv run pytest tests/unit tests/contract tests/integration -q`,
  `uv run ruff check .`, `uv run ruff format --check .`.

## Front_Angular (serviço `front`)

- Repo: `EmporioB2B/Front_Angular`; imagem alvo:
  `ghcr.io/emporiob2b/front-angular`.
- Imagem prod: `node:22-bookworm-slim`, usuário `node` (1000), porta
  **4000** (`PORT`), `CMD node dist/Emporio_Front/server/server.mjs`;
  healthcheck da imagem usa fetch do Node em `localhost`.
- Único env lido em runtime hoje: `PORT`. `apiBaseUrl` e `imageBaseUrl` são
  **compilados no bundle** (`src/environments/*.ts`; produção atual: vazios)
  — virar build-arg é pré-requisito de deploy (task no repo Front).
- SSR valida o header `Host` contra `security.allowedHosts` do
  `angular.json` (hoje `["localhost"]`) — incluir domínio público é
  pré-requisito de deploy (task no repo Front).
- Imagem dev: `Dockerfile-dev` (`ng serve` em 4200, hot-reload,
  `proxy.conf.json` → `http://backend:8080`). Não publicar.
- Verificação canônica: `npm run lint`, `npm run typecheck`,
  `npm run test`, `npm run build`. Não há framework E2E ainda.

## Emuladores (somente dev/integração)

| Serviço | Papel | Notas |
|---|---|---|
| `postgres` (postgres:16-alpine) | banco do Back | prod usa Supabase; nunca subir em produção |
| `rustfs` + `rustfs-init` | R2 do Back (quarentena, privado e **público de fotos**) | espelho do `docker-compose.rustfs.yml` do Back (`rustfs/rustfs:1.0.0-rc.6` + cliente `rustfs/rc:v0.1.30`); credencial read-only própria; console 9001 |
| `mailpit` (`axllent/mailpit:v1.31.2`) | SMTP do Back + UI para links de email | `SMTP_HOST=mailpit`, porta 1025 interna (não publicada); UI 127.0.0.1:8025; healthcheck canônico `/mailpit readyz` |

No `rustfs-init` do compose de dev, a política anônima do bucket público
usa `rc bucket anonymous set download` — a forma antiga `rc anonymous set`
está deprecated no `rustfs/rc:v0.1.30` (verificado no help do binário). A
leitura anônima só é necessária no dev (o navegador carrega fotos sem
credencial S3); nem o override do Back nem a produção a aplicam — lá o
público é servido pela borda (`media.emporiob2b.com.br`).

Para atender a validação de email do Back (seção Email acima), o Mailpit
de dev roda com `MP_SMTP_AUTH_ACCEPT_ANY=1` (aceita qualquer par de
credenciais) e STARTTLS via `MP_SMTP_TLS_CERT`/`MP_SMTP_TLS_KEY` com o
certificado gerado por `scripts/gen-dev-certs.sh`.

O Radar **não** é emulado: usa o R2 de teste real (restrição do
`config.py`).

## Hermes_Robo_Whats_Python

Fora do stack nesta fase. Consumidor futuro da API privada do Radar
(mesmo padrão de rede interna). Sem imagem, compose ou CI neste momento.
