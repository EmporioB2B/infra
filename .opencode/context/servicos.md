# Catálogo de serviços

Fatos verificados nos repositórios irmãos e nos artefatos deste repo. Este
catálogo é a fonte canônica de nomes de env, portas e restrições para os
composes deste repositório. Rascunhos antigos (como o
`docker-compose.yml` da raiz do workspace, que usava `DB_HOST`,
`SECRET_JWT`, `R2_ENDPOINT`, `API_BASE_URL` etc.) não refletem o código e
estão aposentados.

## Backend_Java (serviço `api` em prod; `backend` em dev)

- Repo: `EmporioB2B/Backend_Java`; imagem alvo:
  `ghcr.io/emporiob2b/backend-java`.
- Imagem: `eclipse-temurin:25-jre-jammy`, usuário `emporio` (10001),
  `EXPOSE 8080`; healthcheck da imagem usa o endereço injetado pelo profile
  `container`: `curl --fail http://${MANAGEMENT_SERVER_ADDRESS}:8081/actuator/health`.
- Portas: aplicação **8080**; management/actuator **8081** (health/info;
  nunca publicar nem rotear pelo túnel; no Compose dev fica somente na
  `metrics-net` em `10.254.20.10` e é coletada pelo Prometheus). Esse bind
  privado não impede o host Docker de alcançar diretamente o IP da bridge;
  não há garantia de firewall nesse caminho (`Backend_Java/Dockerfile:23-38`,
  `Backend_Java/src/main/resources/application-container.yml:35-42`,
  `compose/docker-compose.dev.yml:174-183,266-276`).
- Profiles: `dev`, `test`, `container`, `prod`. Combinações vigentes:
  dev em compose `dev,container`; produção `prod,container`.
- Envs **obrigatórias sem default** no profile `container`:
  `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`,
  `SPRING_DATASOURCE_PASSWORD`, `APP_JWT_SECRET`,
  `APP_CORS_ALLOWED_ORIGINS`, `RADAR_BASE_URL`,
  `MANAGEMENT_SERVER_ADDRESS`.
  No profile `prod` soma-se `APP_PASSWORD_RESET_BASE_URL`.
- Envs relevantes por escopo:
  - Radar: `RADAR_BASE_URL` (dev/prod: `http://radar:8000`),
    `RADAR_CONNECT_TIMEOUT`, `RADAR_READ_TIMEOUT`,
    `RADAR_MAX_RESPONSE_BYTES`.
  - Storage R2: `APP_STORAGE_PROVIDER` (`DISABLED|LOCAL|R2`),
    `APP_STORAGE_ALLOW_INSECURE_HTTP`,
    `APP_STORAGE_READ_WRITE_R2_{ENDPOINT,ACCESS_KEY_ID,SECRET_ACCESS_KEY}`,
    `APP_STORAGE_READ_ONLY_R2_{ENDPOINT,ACCESS_KEY_ID,SECRET_ACCESS_KEY}`,
    `APP_STORAGE_READ_ONLY_QUARENTENA_R2_{ENDPOINT,ACCESS_KEY_ID,SECRET_ACCESS_KEY}`,
    `APP_STORAGE_R2_{QUARENTENA,PRIVADO,PUBLICO}_BUCKET`,
    `APP_STORAGE_R2_{QUARENTENA,PRIVADO}_PREFIX`,
    `APP_STORAGE_R2_REGION`, `APP_STORAGE_R2_PUBLICO_BASE_URL`,
    `APP_STORAGE_R2_PRESIGNED_{UPLOAD,READ}_TTL`,
    `APP_STORAGE_DIRECT_UPLOAD_MAX_BYTES`. Não existe
    `APP_STORAGE_R2_DEV_PUBLICO_BASE_URL` no código (nome de rascunho
    antigo, nunca implementado; só a base única
    `APP_STORAGE_R2_PUBLICO_BASE_URL` é vinculada em
    `application.yml`/`application-dev.yml`).
    O namespace público é fixo em `public/` por `StorageNamespace`, e
    `publicObjectPath` produz `public/asset/<SHA-256 da referência>`
    (`Backend_Java/src/main/java/br/com/emporio/infrastructure/storage/StorageNamespace.java:15-40`).
    `APP_STORAGE_R2_PUBLICO_PREFIX` não é lida pelo Backend e não é definida
    pelo compose deste repo; o override RustFS do Backend ainda a contém como
    variável inerte (`Backend_Java/docker-compose.rustfs.yml:19-23`).
  - **Existente — dev:** `StorageProperties.publicBaseUrlIsSafe` proíbe path
    na base do public-base-url (aceita apenas null, vazio ou `/`) e
    `R2StorageProvider.publicUrl()` compõe `base + "/" + publicObjectPath(reference)`
    (`Backend_Java/src/main/java/br/com/emporio/infrastructure/config/StorageProperties.java:324-330`;
    `Backend_Java/src/main/java/br/com/emporio/infrastructure/storage/provider/R2StorageProvider.java:353-364`).
    O `media-gateway` resolve a limitação do path-style do RustFS sem alterar
    o contrato do Backend: no dev, a base default é
    `APP_STORAGE_R2_PUBLICO_BASE_URL=http://localhost:9002` (com
    `MEDIA_GATEWAY_PORT` opcional) e `/public/asset/...` é traduzido
    internamente para `rustfs:9000/public-local/public/asset/...`.
  - **Existente — dev:** `media-gateway` usa `nginx:1.27.5-alpine`, escuta
    `80` no container e publica somente `127.0.0.1:9002` por default
    (`MEDIA_GATEWAY_PORT` pode sobrescrever); o healthcheck é `/healthz`, a
    configuração é somente-leitura e o serviço fica apenas na rede `default`.
    Aceita `GET`/`HEAD` exclusivamente em `/public/asset/`, rejeita
    escrita e não roteia buckets privado/quarentena ou listagem
    (`compose/docker-compose.dev.yml:266-291`;
    `compose/media-gateway.nginx.conf:16-37`; o teste de integração do Back
    aguarda `/healthz` na porta 80 e confirma a URL pública opaca em
    `Backend_Java/src/test/java/br/com/emporio/infrastructure/storage/provider/RustFsStorageIT.java:144-151,348-414`).
  - **Planejado — produção:** a base será o domínio custom da borda, sem
    path (`APP_STORAGE_R2_PUBLICO_BASE_URL=https://media.emporiob2b.com.br`),
    e não haverá media-gateway na VPS; `media.emporiob2b.com.br` será servido
    diretamente pelo bucket público R2.
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
  - [EXISTENTE — dev] A credencial
    `APP_STORAGE_READ_ONLY_QUARENTENA_R2_*` é distinta das credenciais
    read-write/read-only e serve apenas para presign de leitura no
    bucket/prefixo de quarentena. No compose dev, o prefixo efetivo é
    `quarantine/` (o fallback do `application.yml` sem override é `qa/`); no
    RustFS dev a policy equivalente permite
    somente `s3:GetObject` em `arn:aws:s3:::quarantine-local/quarantine/*`,
    sem listagem, escrita, deleção ou recursos dos buckets privado/público; a
    leitura anônima dev-only do bucket público é uma regra independente.
  - [PLANEJADO — produção] O handoff de produção descreve a mesma credencial,
    prefixo e policy mínima, mas não aplica alteração no R2, Cloudflare ou
    Dokploy.
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
  `proxy.conf.json` → `http://backend:8080`); no Compose dev publica somente
  em `127.0.0.1:4200`.
- Verificação canônica: `npm run lint`, `npm run typecheck`,
  `npm run test`, `npm run build`. Não há framework E2E ainda.

## Emuladores (somente dev/integração)

| Serviço | Papel | Notas |
|---|---|---|
| `postgres` (**existente — dev**, postgres:16-alpine) | banco do Back | prod usa Supabase; nunca subir em produção |
| `rustfs` + `rustfs-init` (**existente — dev**) | R2 do Back (quarentena, privado e **público de fotos**) | espelho do `docker-compose.rustfs.yml` do Back (`rustfs/rustfs:1.0.0-rc.6` + cliente `rustfs/rc:v0.1.30`); credencial read-only geral e credencial dedicada read-only da quarentena; console 9001 |
| `media-gateway` (**existente — dev**) | URL local de fotos públicas | `nginx:1.27.5-alpine`; container na porta 80, publicação default `127.0.0.1:9002`; health `/healthz`; `/public/asset/...` → `rustfs:9000/public-local/public/asset/...`; somente `GET`/`HEAD`; sem privado/quarentena/escrita/listagem |
| `mailpit` (**existente — dev**, `axllent/mailpit:v1.31.2`) | SMTP do Back + UI para links de email | `SMTP_HOST=mailpit`, porta 1025 interna (não publicada); UI 127.0.0.1:8025; healthcheck canônico `/mailpit readyz` |

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

O Radar **existente — dev** não é emulado: usa o R2 de teste real (restrição do
`config.py`).

## Observabilidade de logs

- **Existente — dev:** `loki` usa `grafana/loki:3.5.1`, escuta `3100` somente
  na rede `observability`, armazena no volume `loki-data` e retém 7 dias
  (`compose/loki/config.yaml:3-4,28-38`). O healthcheck consulta `/ready` a cada
  5s, com `start_period` de 10s e 12 tentativas; reinicia com
  `unless-stopped` e usa `json-file` rotacionado em 10 MiB/3 arquivos
  (`compose/docker-compose.dev.yml:56-65`).
- **Existente — dev:** `vector` usa `timberio/vector:0.49.0-alpine`, recebe o
  protocolo Fluent em `24224` publicado somente como
  `127.0.0.1:${VECTOR_FLUENTD_PORT:-24224}`, tenta parsear o JSON dos eventos e
  preserva os campos ECS do Backend ao enviar ao Loki com buffer em disco no
  volume `vector-data`. A API local de health em `8686` é consultada pelo
  healthcheck; a validação estática de configuração é feita separadamente no
  gate (`vector validate --skip-healthchecks`). O serviço reinicia com
  `unless-stopped`, usando `json-file` rotacionado em 10 MiB/3 arquivos
  (`compose/docker-compose.dev.yml:67-87`). Não monta Docker socket.
- **Existente — dev:** `grafana` usa `grafana/grafana:12.0.0`, publica a UI
  somente em `127.0.0.1:${GRAFANA_PORT:-3000}`, provisiona o datasource Loki e
  persiste dados no volume `grafana-data`. `GRAFANA_ADMIN_PASSWORD` é
  obrigatória; `GRAFANA_ADMIN_USER` defaulta `admin`, e a UI desabilita cadastro
  e acesso anônimo. O healthcheck consulta `/api/health` a cada 10s, com
  `start_period` de 20s e 12 tentativas; reinicia com `unless-stopped` e usa
  `json-file` rotacionado em 10 MiB/3 arquivos
  (`compose/docker-compose.dev.yml:89-114`).
- **Existente — dev:** `prometheus` usa `prom/prometheus:v3.5.0`, sem porta
  publicada, com healthcheck em `/-/healthy`, volume `prometheus-data` e
  retenção local de 7 dias. Ele participa da `metrics-net` com IP
  `10.254.20.20` e da `observability`; coleta
  `10.254.20.10:8081/actuator/prometheus` a cada 15s com timeout de 5s.
  O Grafana provisiona o datasource `Emporio Prometheus` apontando para
  `http://prometheus:9090`.
- **Existente — dev:** o Backend escreve ECS no console, separando
  `DEBUG/INFO/WARN` em stdout e `ERROR` em stderr; não há appender de arquivo
  (`Backend_Java/src/main/resources/application-container.yml:22-31`,
  `Backend_Java/src/main/resources/logback-spring.xml:7-42`). O contrato ECS é
  verificado diretamente para o Backend; não é uma afirmação de formato dos
  demais serviços sem fonte correspondente.
- **Planejado — produção:** o Dokploy instala `dokploy-vector` ao associar a
  VPS a um provider Grafana Loki em `Settings → Logs & Metrics`; endpoint,
  tenant/usuário e token são segredos do painel/Secrets Provider. Loki/Grafana
  não entram no Compose da aplicação no MVP.

## Hermes_Robo_Whats_Python

Fora do stack nesta fase. Consumidor futuro da API privada do Radar
(mesmo padrão de rede interna). Sem imagem, compose ou CI neste momento.
