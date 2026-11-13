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
- **Existente — imagem de staging publicada, verificada em 2026-11-13:**
  `ghcr.io/emporiob2b/backend-java:10d03d7796b8a996c1580dcf56a3f95ea24c58dc`,
  manifest multiarch `linux/amd64` + `linux/arm64`, index digest
  `sha256:222d33f7c5bd5c1ebf3314b8441d62e6f61b1891594ca09c3cda1351f3c3ead4`
  (`docker buildx imagetools inspect` executado pelo operador em máquina
  autenticada no GHCR; saída colada nesta sessão). A tag SHA completo coincide
  com o formato do workflow versionado
  (`../Backend_Java/.github/workflows/backend-ci.yml:115-116`), evidenciando
  execução do job de publicação; o run no Actions não foi auditado. Fato
  verificado, não configuração: valores reais de imagem vão somente no
  Dokploy.
- Imagem: `eclipse-temurin:25-jre-jammy`, usuário `emporio` (10001),
  `EXPOSE 8080`; healthcheck da imagem usa o endereço injetado pelo profile
  `container`: `curl --fail http://${MANAGEMENT_SERVER_ADDRESS}:8081/actuator/health`.
- Portas: aplicação **8080**; management/actuator **8081** (expõe
  `health,info,prometheus` no profile `container`; nunca publicar nem rotear
  pelo túnel; no Compose dev fica somente na `metrics-net` em
  `10.254.20.10` e é coletada pelo Prometheus). Esse bind privado não impede o
  host Docker de alcançar diretamente o IP da bridge; não há garantia de
  firewall nesse caminho (`Backend_Java/Dockerfile:23-38`,
  `Backend_Java/src/main/resources/application-container.yml:35-42`,
  `compose/docker-compose.dev.yml:177-190,262-285,513-522`).
- Profiles: `dev`, `test`, `container`, `prod`. Combinações vigentes:
  dev em compose `dev,container`; produção `prod,container`.
- **Contrato de métricas do Backend (existente, verificado no código-fonte do
  irmão e no scrape dev; a Infra consome, não é dona dos valores de domínio)**
  via `/actuator/prometheus` (8081):
  - HTTP **RED curado** próprio: `http_server_requests_total` (Counter) +
    `http_server_duration_seconds` (Timer, exposto como `_count`/`_sum`/`_max`)
    com exatamente as labels `route_template,method,status_class,outcome`;
    `route_template` é template do catálogo Spring MVC (com `{var}`) ou
    `unknown`; `/actuator/**` fica fora do filtro; as séries só materializam
    após tráfego em `/api`
    (`Backend_Java/src/main/java/br/com/emporio/infrastructure/observability/HttpMetricsFilter.java:33-34,57-60,81-89,214-233`,
    `Backend_Java/src/main/java/br/com/emporio/infrastructure/config/MetricsConfiguration.java:284-298`).
  - O binder cru `http.server.requests` (`http_server_requests_seconds`)
    **continua excluído (deny)**, junto com `disk.free|total`, `jvm.memory.*`
    por pool, `jvm.buffer.*`, `jvm.gc.pause`, `jvm.info` e as famílias Tomcat
    de sessões/keepalive/cache/global/servlet; o `MeterFilter` rejeita todo
    nome não inventariado (deny-by-default)
    (`MetricsConfiguration.java:114-127,165-179,202-205`). HTTP **não** está
    "fora do contrato": o que não existe é o binder cru; o RED curado existe.
  - Heap agregada da JVM disponível, **sem labels**: `jvm_heap_used_bytes` e
    `jvm_heap_max_bytes` (o máximo pode ser `NaN` quando a JVM não reporta
    máximo)
    (`Backend_Java/src/main/java/br/com/emporio/infrastructure/config/RuntimeMetricsConfiguration.java:110-119,126-128`).
  - Timers exportados **sem buckets/percentis** (nenhum `publishPercentiles`
    no código, nenhum `management.metrics.distribution` nos resources):
    `histogram_quantile` não funciona; latência se mede por **média**
    (`_sum`/`_count`) e **máx** (`*_max`), que é o contrato dos painéis.
  - Tomcat agregado disponível **sem labels** (soma dos MBeans dos conectores):
    `tomcat_threads_busy|current|config_max`,
    `tomcat_connections_current|config_max`
    (`RuntimeMetricsConfiguration.java:133-138`,
    `MetricsConfiguration.java:98-100,186-188`).
  - Hikari com pool finito permitido: `emporio-pool` (dev),
    `emporio-test-pool` (test), `emporio-b2b-pool` (container/prod)
    (`MetricsConfiguration.java:94-95,196-198`,
    `application-dev.yml:10`, `application-test.yml:10`,
    `application-container.yml:8`).
  - Executors: `executor_rejections_total{name=...}` com `name` ∈
    `emailTaskExecutor|emailResultTaskExecutor`
    (`Backend_Java/src/main/java/br/com/emporio/infrastructure/email/config/EmailExecutorConfiguration.java:27-28,96-104`,
    `MetricsConfiguration.java:96-97,133-135,199-201`).
  - **Limite (pendência do repo `Backend_Java`, não decisão da Infra):**
    memória real do container (RSS) **não é observável** —
    `process_memory_rss_bytes` não é emitido (não há dependência
    `micrometer-jvm-extras` no `pom.xml` e o filtro deny rejeitaria o nome não
    inventariado). Para memória, use a heap agregada.
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
    (`compose/docker-compose.dev.yml:385-415`;
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
- Banco: **existente — dev integrado** usa `postgres:16-alpine`, database
  `emporio` e role administrativa parametrizada por `POSTGRES_ADMIN_USER`;
  **planejado — produção** usa Supabase externo PostgreSQL 17
  (`SPRING_DATASOURCE_URL` JDBC com SSL). Flyway gerencia as migrations; o
  owner dos objetos do novo modelo é `emporio_owner`.
- **Contrato aprovado — staging:** PostgreSQL 17 local; fluxo `postgres →
  db-bootstrap → migrate → api`, com credencial administrativa apenas no
  bootstrap; `SPRING_FLYWAY_URL`/`SPRING_FLYWAY_USER` no job migrador e
  `SPRING_FLYWAY_PASSWORD` no bootstrap (para definir a role) e migrador, nunca
  API; `SPRING_DATASOURCE_PASSWORD` no bootstrap (para definir a role) e API
  runtime como `emporio_app`. Não copiar dados de produção. O contrato R2/SMTP
  por serviço e as gates ainda abertas estão em
  [`../../docs/staging-contract.md`](../../docs/staging-contract.md).
- **Existente — artefatos Compose de staging (TASK-INFRA-020; implantação não verificada nesta sessão):** PostgreSQL
  `17-alpine` por digest, sem `ports:`; readiness `pg_isready`; named volume
  `emporio-staging_pgdata`. `db-bootstrap` usa Postgres CLI + File Mount
  `/bootstrap/roles.sql`; `migrate` usa imagem Backend `migrate`, ambos jobs
  one-shot. API `prod,container`, porta 8080 sem publish e management 8081 com
  bind em `10.254.30.10` na `metrics-net` interna — não mais loopback (health
  da imagem usa esse endereço); Front SSR porta 4000 sem publish e healthcheck
  Node em `localhost`; Radar API 8000 sem publish, health em `/health/ready` e
  metrics `10.254.31.30:8082` na `radar-metrics-net` interna. `prometheus`
  (`${PROMETHEUS_IMAGE}` pinada por digest) sem publish, web em
  `127.0.0.1:9090` dentro do container, healthcheck `wget /-/ready`, retenção
  7d com WAL comprimido no volume `emporio-staging_prometheus-data`, limites
  0.25 CPU/512M; entrypoint valida envs e interpola URL/username no template
  via `sed`, token lido de `password_file` (File Mount), nunca por shell; não é
  dependência de saúde de nenhum serviço. O fluxo depende dos File Mounts no
  Dokploy (`roles.sql`, template do Prometheus, token remote_write) e imagens
  imutáveis GHCR multiarch antes do deploy. File Mount wiring **existente no
  artefato**: `../files/roles.sql` → `/bootstrap/roles.sql`,
  `../files/prometheus.template.yml` →
  `/etc/prometheus/prometheus.template.yml` e
  `../files/remote-write-token` → `/etc/prometheus/remote-write-token`, todos
  read-only. Dokploy File Mounts são armazenados sob `../files/` e só entram no
  container por referência explícita no `volumes:`; o cadastro por si só não
  conecta o arquivo. Os nomes efetivos/File Paths do painel e a presença dos
  arquivos nos containers não foram confirmados; render local não é validação
  de implantação (`compose/docker-compose.staging.yml:63-65,322-325`,
  `../../docs/staging-compose.md:32-51`). Teto aprovado: 2 CPU/12 GiB por
  stack (decisão do operador de 2026-11-13, divisão meio a meio da VPS entre
  staging e produção futura; substitui o teto inicial de 1,5 CPU/3 GiB). Os
  limites long-lived somam 1,75 CPU/3.375 GiB (incluindo o Prometheus) —
  dentro do teto, válido para o primeiro deploy — e jobs têm limites próprios.
  Métricas de staging (Prometheus com `remote_write` no Compose) são artefato
  **existente, não implantado**; logs via `dokploy-vector` → Grafana Cloud Loki
  seguem **planejados** (ver `arquitetura.md`/`decisoes.md`;
  `compose/docker-compose.staging.yml:121,154-155,206-214,295-342`).
- **Existente — seed manual de admin de staging (não executado/verificado nesta
  sessão):** `scripts/seed-admin-staging.sh --confirm-staging` direciona
  exclusivamente ao serviço `postgres` do projeto `emporio-staging` ou seu
  sufixo de projeto gerado pelo Dokploy, valida o DB `emporio`, exige container
  healthy e confirmação interativa, e é independente dos jobs
  `db-bootstrap`/`migrate`, API e deploy. Após as migrations, cria/atualiza
  `admin@emporiob2b.com.br` e concede `ADMIN_NEGOCIO` no escopo `PLATAFORMA`
  com nove capacidades administrativas; a senha é solicitada sem eco, vira
  BCrypt custo 12; somente o hash é persistido no banco. Reexecução substitui a
  senha, e o seed não cria `perfil_usuario`. A V1 do Backend cria a organização `Emporio B2B` ativa do
  tipo `PLATAFORMA`. Tratar a conta como superusuário: operação manual somente
  em staging, nunca produção. O operador relata staging funcional, mas VPS,
  staging e execução do seed não foram verificados nesta sessão
  (`scripts/seed-admin-staging.sh:2-3,6-18,21-41,44-65,67-92,94-130,132-174,177-191`;
  `../../docs/staging-compose.md:62-78`;
  `../Backend_Java/src/main/resources/db/migration/V1__fundacao_clientes.sql:92-96`).
- **Existente — Fase 2, Compose dev integrado:** a sequência é
  `postgres → db-bootstrap → migrate → backend`. `db-bootstrap` usa a
  credencial administrativa, monta `database/bootstrap/roles.sql` read-only e
  define senhas independentes de app/migrador; `migrate` chama `migrate` na
  imagem Backend como `emporio_migrador`; `backend` conecta como `emporio_app`
  e tem Flyway desabilitado. A senha admin não chega ao Backend nem a senha
  migradora ao runtime; a senha app não chega ao job migration
  (`compose/docker-compose.dev.yml:150-210,217-228,336-353`,
  `env/.env.dev.example:23-32`, `docs/database-roles.md:47-62`).
- **Existente — build dev:** `backend` e `migrate` compartilham a tag local
  `emporio-backend:dev`; o contexto default é `../Backend_Java`, com override
  `BACKEND_BUILD_CONTEXT`. `scripts/up-dev.sh` reporta branch, SHA curto e
  clean/dirty do checkout, e sinaliza como não canônico um build fora do clone
  `../Backend_Java` em `main` limpo
  (`compose/docker-compose.dev.yml:217-222,336-342`,
  `scripts/up-dev.sh:18-28,50-79`).
- **Existente — Fase 1 de roles:** `database/bootstrap/roles.sql` cria e configura
  `emporio_owner` como NOLOGIN, `emporio_migrador` e `emporio_app` como LOGIN;
  o migrador pode fazer `SET ROLE emporio_owner` sem herança/delegação. O
  runtime não tem membership de owner nem CREATE no database/schema `public`.
  O script não define senhas, privilégios DML de domínio ou
  `ALTER DEFAULT PRIVILEGES` (`database/bootstrap/roles.sql:3-7,9-95`).
- **Existente — prova isolada de roles:**
  `scripts/smoke-db-roles.sh` é limitado a `postgres:16-alpine` e
  `postgres:17-alpine`; usa container com `tmpfs` e credenciais efêmeras, não
  o Compose persistente. Ele testa autenticação e privilégios PostgreSQL
  (`scripts/smoke-db-roles.sh:1-18,26-64,102-187,189-263`).
- **Existente — prova isolada do runner/runtime:**
  `scripts/smoke-db-migration-runner.sh` aceita `postgres:16-alpine` e
  `postgres:17-alpine`; ambos os comandos passaram, segundo a execução
  reportada, com a imagem local `emporio-backend:dev` construída do clone
  `Backend_Java_Cliente`. Em PostgreSQL descartável sobre tmpfs, aplica V1–V10,
  confirma health da API Java e sessão runtime como `emporio_app`, e verifica
  negações de DDL, TRUNCATE e `SET ROLE emporio_owner`, sem volume persistente
  (`scripts/smoke-db-migration-runner.sh:1-5,22-24,33-48,67-91,93-149`). Não
  valida o clone canônico `../Backend_Java` nem o Supabase gerenciado.
- **Existente — dev integrado, execução reportada:** `scripts/up-dev.sh`
  executado com `BACKEND_BUILD_CONTEXT=../Backend_Java_Cliente`; jobs
  `db-bootstrap`, `migrate` e `rustfs-init` terminaram com exit 0 e serviços
  long-lived ficaram healthy. Source branch `dev/cliente`, SHA `bf99658885e9`,
  dirty com 5 entradas: build de trabalho, não canônico. `scripts/smoke.sh`
  terminou com exit 0 e passou bootstrap/migration, V10, sessão Java como
  `emporio_app`, negações DDL/TRUNCATE/SET ROLE, redes, Radar, RustFS e
  observabilidade; HTTP RED idle foi `SKIP` esperado sem tráfego `/api`. O
  `emporio-dev_pgdata_v2` foi criado nessa subida; os volumes legados
  `emporio-dev_pgdata` e `emporio-dev_radar_state` foram reportados como
  remanescentes e deixados intactos. Isso não valida o clone canônico
  `../Backend_Java` em `main` nem Supabase gerenciado. Fontes do contrato de
  verificação: `scripts/up-dev.sh:18-28,50-79,171-198`,
  `scripts/smoke.sh:83-157,407-412`, `compose/docker-compose.dev.yml:607-610`;
  execução e saída completas reportadas pelo operador.
- **Existente — dev integrado / contrato DB-08:** `db-bootstrap` monta o
  bootstrap SQL em read-only; define senhas de `emporio_app` e
  `emporio_migrador` por `psql` stdin usando `\getenv` e quoting do psql. Valida
  três credenciais distintas, mínimo 32 caracteres alfanuméricos sem imprimir
  valores. O Backend não recebe credenciais administrativas ou de migration
  (`compose/docker-compose.dev.yml:177-215,217-353`;
  `env/.env.dev.example:23-36`; `database/bootstrap/roles.sql:3-99`).
- **Existente — dev integrado:** migration usa URL public-first e o runner
  one-shot `SPRING_FLYWAY_*`; runtime usa `emporio_app` com
  `currentSchema=identidade,catalogo,mercadoria,comercial,infraestrutura,venda,pedidos`.
  Flyway automático permanece desabilitado no serviço API (`compose/docker-compose.dev.yml:340-353`; `Backend_Java/src/main/resources/application.yml:37-40`; `Backend_Java/src/main/resources/application-container.yml:2-12`).
- **Validação integrada dev (2026-11-09):** `scripts/up-dev.sh --no-build`
  concluiu jobs e healthchecks; seed repetido manteve admin, vínculo, papel e
  nove capacidades; `scripts/smoke.sh` passou. O preflight identificou
  `Backend_Java` em `main` no SHA `8eed3342dfecb4656df68d712dff1ef5389668d4`,
  mas `--no-build` reutilizou imagem local e não comprova sua origem. Os
  volumes legados foram mantidos. A validação não abrange Supabase/produção
  (`.opencode/tasks/passadas/20261109_TASK-INFRA-016-db-bootstrap-migrate-dev.md`).
- Verificação canônica: `./mvnw -B verify` (Testcontainers; exige daemon
  Docker; ~3 min em 8 CPUs).

## Radar_Middleware_Python (serviço `radar`)

- Repo: `EmporioB2B/Radar_Middleware_Python`; imagem alvo:
  `ghcr.io/emporiob2b/radar-middleware`.
- Imagem: `python:3.12.14-slim-bookworm`, usuário `radar` (10001),
  `ENTRYPOINT radar-middleware`; diretórios da imagem:
  `/var/lib/radar-middleware/{logs,state}` (dono `radar:radar`).
- Porta interna: **8000** (`PORT`). No Compose integrado da Infra, **nunca
  publicar no host**; o Compose standalone local do próprio Radar ainda
  publica 8000 para desenvolvimento isolado e não é usado pelo stack integrado
  (`Radar_Middleware_Python/docker-compose.yml:9-20`).
- **Existente — dev, contrato promovido:** listener Prometheus separado em
  `METRICS_BIND_ADDRESS:METRICS_PORT`; a Infra configura
  `10.254.21.30:8082`, endpoint `/metrics`, sem publicação no host. O scrape
  ocorre na rede interna exclusiva `radar-metrics-net` (`prometheus` em
  `10.254.21.20` ↔ `radar` em `10.254.21.30`), não na `metrics-net` do Backend,
  para preservar o negativo Radar→Backend:8081. O listener usa WSGI bounded,
  registro Prometheus isolado e as famílias `radar_health_ready`, o process
  collector (`process_*`), `radar_http_requests_total`,
  `radar_http_duration_seconds`, `radar_cep_queries_total`,
  `radar_cep_lookup_duration_seconds` e
  `radar_cep_primary_city_queries_total{uf,codigo_cidade}`. As labels de CEP
  usam `uf/outcome`; a cidade primária só materializa quando o código é
  resolvido pelo mapa de referência (fontes no irmão:
  `src/radar_middleware/infrastructure/observability/prometheus.py:77-80,124-165,240-248`,
  `src/radar_middleware/infrastructure/config.py:201-207`).
- **Existente — staging, artefato não implantado:** o Compose de staging
  configura `METRICS_BIND_ADDRESS=10.254.31.30` e `METRICS_PORT=8082`; o
  listener fica somente na `radar-metrics-net` interna (`10.254.31.0/24`,
  Prometheus em `10.254.31.20`), sem publicação no host
  (`compose/docker-compose.staging.yml:206-207,213-214,374-381`).
- Envs reais (Pydantic settings, `env_prefix=""`, case-sensitive):
  `ENVIRONMENT`, `LOG_LEVEL`, `PORT`,
  `METRICS_BIND_ADDRESS`, `METRICS_PORT`,
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
- **Existente — CI versionado; publicação verificada, run não auditado:**
  `.github/workflows/ci.yml` tem job verify (pytest + ruff check/format) e job
  publish em push de `main`, publicando
  `ghcr.io/emporiob2b/radar-middleware:sha-<github.sha>` com
  `platforms: linux/amd64,linux/arm64` e actions pinadas por SHA.
  **Verificado em 2026-11-13** (`docker buildx imagetools inspect` executado
  pelo operador em máquina autenticada no GHCR; saída colada nesta sessão):
  `ghcr.io/emporiob2b/radar-middleware:sha-00208110c84de630ae0ef6b432c3988bd41e0ed4`
  publicado com manifest multiarch `linux/amd64` + `linux/arm64`, index digest
  `sha256:340395eef841bd8c96b22dd2e02672c8d8af55cc761517f0ac2419f25e4f3478`;
  o index inclui ainda 2 attestation-manifests `unknown/unknown` (proveniência
  buildx — normal, não são plataformas executáveis). A tag coincide com o
  formato do workflow, evidenciando execução do job de publicação; o run no
  Actions não foi auditado. O formato de
  tag `sha-<SHA>` difere do `<sha-completo>` previsto para imagens de aplicação
  em `docs/cicd.md:67-74`; a referência `RADAR_IMAGE` do staging precisa
  refletir a tag realmente publicada
  (`Radar_Middleware_Python/.github/workflows/ci.yml:18-59,77-85`).
- **Pendência de visualização:** o Radar ainda não entrega catálogo de
  coordenadas para `codigo_cidade`. Existe um mapa de referência de municípios
  com códigos e nomes RFB/IBGE, mas ele não contém latitude/longitude; o Grafana
  pode exibir UF/código/ranking, mas o Geomap continua **planejado** e depende
  do catálogo de coordenadas posterior
  (`src/radar_middleware/infrastructure/cep/municipios.py:44-54`). O listener
  WSGI é bounded (timeout de conexão e no máximo quatro conexões), e o risco
  residual aceito pelo dono do Radar de traceback em stderr permanece contido
  pela rede privada e ausência de publish/roteamento externo
  (`Radar_Middleware_Python/src/radar_middleware/infrastructure/observability/prometheus.py:72-120`,
  `Radar_Middleware_Python/src/radar_middleware/infrastructure/observability/logging_setup.py:150-205`).

## Front_Angular (serviço `front`)

- Repo: `EmporioB2B/Front_Angular`; imagem alvo:
  `ghcr.io/emporiob2b/front-angular`.
- Imagem prod: `node:22-bookworm-slim`, usuário `node` (1000), porta
  **4000** (`PORT`), `CMD node dist/Emporio_Front/server/server.mjs`;
  healthcheck da imagem usa fetch do Node em `localhost`.
- Único env lido em runtime hoje: `PORT`. `apiBaseUrl` e `imageBaseUrl` são
  **compilados no bundle** (`src/environments/*.ts`; produção atual: vazios);
  o Dockerfile aceita `ARG BUILD_PROFILE=production`, `ARG API_BASE_URL` e
  `ARG IMAGE_BASE_URL` e executa `npm run build -- "$BUILD_PROFILE"`
  (`../Front_Angular/Dockerfile:17-19,33-35`). Runtime override não existe.
- SSR valida `Host` contra `security.allowedHosts` definido nas options do
  target de build — `localhost` + `staging.emporiob2b.com.br`, valendo para
  qualquer perfil; `localhost` preserva o healthcheck da imagem
  (`../Front_Angular/angular.json:36-38`).
- Imagem dev: `Dockerfile-dev` (`ng serve` em 4200, hot-reload,
  `proxy.conf.json` → `http://backend:8080`); no Compose dev publica somente
  em `127.0.0.1:4200`.
- Verificação canônica: `npm run lint`, `npm run typecheck`,
  `npm run test`, `npm run build`. Não há framework E2E ainda.
- **Existente — configuração staging no Front:** build inputs
  `apiBaseUrl=https://api-staging.emporiob2b.com.br`,
  `imageBaseUrl=https://media-staging.emporiob2b.com.br`
  (`../Front_Angular/build.env.example:1-2`,
  `../Front_Angular/scripts/build-config.mjs:1-4,26-34`), SSR `allowedHosts`
  incluindo `staging.emporiob2b.com.br` e preservando `localhost` para o
  healthcheck da imagem (`../Front_Angular/angular.json:36-38`). A mídia será o Custom Domain do bucket
  público R2 dedicado do Back, fora do Tunnel; a associação ainda não foi
  provisionada. **Existente — Front atual:** `apiBaseUrl` e `imageBaseUrl` de
  produção continuam vazios (`../Front_Angular/src/environments/environment.ts:9-15`;
  `../Front_Angular/angular.json:44-49`). Staging possui configuração própria
  (`fileReplacements` para `environment.staging.ts`,
  `../Front_Angular/angular.json:78-85`). O Dockerfile é parametrizado
  (`ARG BUILD_PROFILE=production`, `ARG API_BASE_URL`, `ARG IMAGE_BASE_URL`;
  `npm run build -- "$BUILD_PROFILE"`). **Existente — imagem publicada,
  verificada em 2026-11-13:**
  `ghcr.io/emporiob2b/front-angular:32614c57fc8089e12de4406b51e485d5caf7c08a`,
  manifest multiarch `linux/amd64` + `linux/arm64`, index digest
  `sha256:e140c9ff322d59d1e59610cdec5c3c93da18d38f4eea07c4dccc066c4b710d53`
  (`docker buildx imagetools inspect` executado pelo operador em máquina
  autenticada no GHCR; saída colada nesta sessão). Publicação manual — o
  Front não tem workflow de CI/publicação. **Perfil staging — verificado em
  2026-11-13:** o operador executou
  `docker run --rm --entrypoint sh ghcr.io/emporiob2b/front-angular:32614c57fc8089e12de4406b51e485d5caf7c08a -c "grep -rl 'api-staging.emporiob2b.com.br' dist | head -3"`;
  o pull resolveu para o mesmo index digest
  `sha256:e140c9ff322d59d1e59610cdec5c3c93da18d38f4eea07c4dccc066c4b710d53`
  e o grep retornou `dist/Emporio_Front/browser/chunk-CbtmA7w5.js` e
  `dist/Emporio_Front/server/chunk-KNXTD5V5.mjs` — a URL
  `https://api-staging.emporiob2b.com.br` está compilada nos bundles browser e
  SSR da imagem publicada. Fonte: `environment.ts` e `environment.staging.ts`
  diferem apenas no rótulo `environment` ('production' vs 'staging') e leem os
  mesmos defines `__API_BASE_URL__`/`__IMAGE_BASE_URL__`
  (`../Front_Angular/src/environments/environment.ts:12-14`;
  `../Front_Angular/src/environments/environment.staging.ts:6-8`); o Dockerfile
  defaulta `BUILD_PROFILE=production`, e `build-config.mjs` usa as URLs de
  staging como default no perfil staging, exigindo ambas não vazias
  (`../Front_Angular/Dockerfile:19,33-35`;
  `../Front_Angular/scripts/build-config.mjs:1-4,26-41`). O rótulo é cosmético;
  a prova substantiva são as URLs de staging compiladas nos dois bundles.
  Comprovar run/deploy segue gate.
  Runtime override não existe.

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
  (`compose/docker-compose.dev.yml:78-93`).
- **Existente — dev:** `vector` usa `timberio/vector:0.49.0-alpine`, recebe o
  protocolo Fluent em `24224` publicado somente como
  `127.0.0.1:${VECTOR_FLUENTD_PORT:-24224}`, tenta parsear o JSON dos eventos e
  preserva os campos ECS do Backend ao enviar ao Loki com buffer em disco no
  volume `vector-data`. A API local de health em `8686` é consultada pelo
  healthcheck; a validação estática de configuração é feita separadamente no
  gate (`vector validate --skip-healthchecks`). O serviço reinicia com
  `unless-stopped`, usando `json-file` rotacionado em 10 MiB/3 arquivos
  (`compose/docker-compose.dev.yml:95-117`). Não monta Docker socket.
- **Existente — dev:** `grafana` usa `grafana/grafana:12.0.0`, publica a UI
  somente em `127.0.0.1:${GRAFANA_PORT:-3000}`, provisiona o datasource Loki e
  persiste dados no volume `grafana-data`. `GRAFANA_ADMIN_PASSWORD` é
  obrigatória; `GRAFANA_ADMIN_USER` defaulta `admin`, e a UI desabilita cadastro
  e acesso anônimo. O healthcheck consulta `/api/health` a cada 10s, com
  `start_period` de 20s e 12 tentativas; reinicia com `unless-stopped` e usa
  `json-file` rotacionado em 10 MiB/3 arquivos
  (`compose/docker-compose.dev.yml:119-145`).
- **Existente — dev:** `prometheus` usa `prom/prometheus:v3.5.0`, sem porta
  publicada, com healthcheck em `/-/ready`, volume `prometheus-data`, WAL
  comprimido e retenção local de 7 dias. Ele participa da `metrics-net` com IP
  `10.254.20.20` e da `observability`; coleta
  `10.254.20.10:8081/actuator/prometheus` a cada 15s com timeout de 5s.
  O Grafana provisiona por arquivo o datasource `Emporio Prometheus`
  (uid `emporio-prometheus`, `http://prometheus:9090`) e o dashboard
  `emporio-backend-dev` (provider com `updateIntervalSeconds: 30` e
  `allowUiUpdates: false`), ambos somente-leitura, de
  `compose/grafana/`. O dashboard segue o contrato vigente do Backend:
  HTTP RED curado, latência por **média/máx** (sem `histogram_quantile` —
  nenhuma série `*_bucket` existe no scrape) e o painel de classes carregadas
  usa `jvm_classes_loaded_classes`; o teste do Backend é que afirma o prefixo
  `jvm_classes_loaded_count` no scrape filtrado (`MetricsConfigurationTest.java:621-624`).
  O smoke valida `/-/healthy` e `/-/ready` do coletor, veta no scrape só a
  família crua `http_server_requests_seconds` e `disk_*` (o RED curado é
  legítimo e não casa no veto), prova a presença de `jvm_heap_used_bytes` e
  valida o RED condicionalmente (só há série após tráfego `/api`).
  `scripts/metrics-resilience.sh` verifica nome do volume, hash da
  configuração e amostra histórica de `process_start_time_seconds` no
  restart, além de `up` 0→1; `scripts/check-grafana-provisioning.sh` prova o
  autoprovisionamento do dashboard num Grafana descartável de banco vazio.
  A verificação de cardinalidade da Infra (`scripts/check-metrics-cardinality.py`)
  valida as chaves de labels da fronteira — allowlist que inclui
  `route_template` e `method` — e padrões sensíveis de valor (URL, e-mail,
  UUID); ela não duplica a allowlist finita de valores do Backend nem mede o
  número de séries.
  (`compose/docker-compose.dev.yml:53-76,119-145`,
  `compose/prometheus/prometheus.yml:1-25`,
  `compose/grafana/provisioning/datasources/prometheus.yaml:4-8`,
  `compose/grafana/provisioning/dashboards/provider.yaml:1-12`,
  `compose/grafana/dashboards/emporio-backend.json:21-335`,
  `scripts/check-metrics-cardinality.py:13-33`,
  `scripts/smoke.sh:82-141,222-299`,
  `scripts/metrics-resilience.sh:45-84`,
  `scripts/check-grafana-provisioning.sh:1-21`,
  `Backend_Java/src/test/java/br/com/emporio/infrastructure/config/MetricsConfigurationTest.java:621-624`).
 - **Existente — dev:** o mesmo Prometheus coleta o Radar em job separado
   `emporio-radar`, pela rede interna `radar-metrics-net` (`10.254.21.20` no
   Prometheus → `10.254.21.30:8082/metrics` no Radar), sem compartilhar a
   `metrics-net` do Backend. O scrape expõe `radar_health_ready`, métricas de
   processo, HTTP RED, CEP por `uf/outcome` e cidade primária por
   `uf/codigo_cidade`; o mapa de nomes/códigos existe no Radar, mas o catálogo
   de coordenadas para Geomap ainda não existe. O smoke valida target, readiness, ausência de publish 8082,
   membros `radar/prometheus` e labels sem CEP/CNPJ/PII
   (`compose/prometheus/prometheus.yml:9-25`,
   `compose/docker-compose.dev.yml:288-325,495-532`, `scripts/smoke.sh:117-220,289-299`).
- **Existente — dev:** o Backend escreve ECS no console, separando
  `DEBUG/INFO/WARN` em stdout e `ERROR` em stderr; não há appender de arquivo
  (`Backend_Java/src/main/resources/application-container.yml:24-33`,
  `Backend_Java/src/main/resources/logback-spring.xml:7-42`). O contrato ECS é
  verificado diretamente para o Backend; não é uma afirmação de formato dos
  demais serviços sem fonte correspondente.
- **Existente — destino Grafana Cloud (2026-11-13, operador):** conta/stack
  `smallmarzipan1294`, região `prod-sa-east-1` (São Paulo), free tier; Access
  Policies `emporio-staging-logs` (`logs:write`) e `emporio-staging-metrics`
  (`metrics:write`) criadas, geração dos tokens não confirmada. Endpoints
  públicos de ingestão verificados por `curl` (HTTP 401 sem auth): Loki
  `https://logs-prod-024.grafana.net` (tenant/user `1878826`) e remote_write
  `https://prometheus-prod-40-prod-sa-east-1.grafana.net/api/prom/push`
  (instance/user `3766316`). URLs e IDs não são segredos (IDs são usuários de
  basic auth) e estão no `env/.env.staging.example:74-86`; somente os tokens
  são segredos do painel/File Mount. As URLs internas
  `*-local-nlb.internal.grafana.net` dos datasources provisionados na UI não
  servem para ingestão externa.
- **Planejado — implantação staging/produção:** o Dokploy instala
  `dokploy-vector` ao associar a VPS a um provider Grafana Loki em
  `Settings → Logs & Metrics` (URL Loki + tenant `1878826` + token
  `logs:write`); o provider ainda não foi configurado. Loki/Grafana não entram
  no Compose da aplicação. Logs de staging: stdout → driver `json-file` com
  rotação (buffer local; proposital para o agente do Dokploy, não `fluentd`
  como no dev) → `dokploy-vector` → push HTTPS outbound, sem porta inbound
  (`compose/docker-compose.staging.yml:24-28`,
  `../../docs/observability.md:161-185,192-197`).
- **Existente — staging, artefato implementado, não implantado (direção
  aprovada em 2026-11-13):** o serviço `prometheus` do Compose de staging usa
  `${PROMETHEUS_IMAGE}` (example:
  `prom/prometheus:v3.5.0@sha256:63805ebb8d2b3920190daf1cb14a60871b16fd38bed42b857a3182bc621f4996`,
  digest verificado no Docker Hub), sem porta publicada, web em
  `127.0.0.1:9090` dentro do container, healthcheck `wget /-/ready`, retenção
  de 7 dias com WAL comprimido no volume `emporio-staging_prometheus-data` e
  limites 0.25 CPU/512M. O entrypoint `sh` exige
  `PROMETHEUS_REMOTE_WRITE_URL` (HTTPS) e `PROMETHEUS_REMOTE_WRITE_USERNAME`,
  interpola os placeholders `__REMOTE_WRITE_URL__`/`__REMOTE_WRITE_USERNAME__`
  via `sed` no template montado em `/etc/prometheus/prometheus.template.yml`
  e executa o coletor; o token de escrita (`metrics:write`) é lido de
  `password_file` no File Mount `/etc/prometheus/remote-write-token`, nunca
  por shell. Redes internas `metrics-net` (`10.254.30.0/24`) e
  `radar-metrics-net` (`10.254.31.0/24`), distintas das do dev, e bridge
  `prometheus-egress` exclusiva para o remote_write.
  `MANAGEMENT_SERVER_ADDRESS` da API é `10.254.30.10` (bind na `metrics-net`,
  não mais loopback); o Radar usa `METRICS_BIND_ADDRESS=10.254.31.30`/
  `METRICS_PORT=8082`. O template `compose/prometheus/prometheus.staging.yml`
  não contém segredos: `external_labels`
  `environment=staging`/`cluster=emporio-staging`, scrape da API em
  `10.254.30.10:8081/actuator/prometheus` e do Radar em
  `10.254.31.30:8082/metrics`, labels `environment`/`service`. O Prometheus
  não é dependência de saúde de nenhum serviço. O example contém os valores
  verificados (não secretos) de `PROMETHEUS_REMOTE_WRITE_URL/USERNAME` do
  destino Grafana Cloud `smallmarzipan1294`; o token `metrics:write` vai
  somente no File Mount e não tem geração confirmada. Validação local:
  `config --quiet` exit 0 com o example vigente, entrypoint na imagem real
  com valores fictícios + `promtool check config` SUCCESS; deploy na VPS,
  ingestão real no Grafana Cloud e
  scrape em runtime não provados — pendentes do primeiro deploy/smoke.
  Dashboards do dev importados no Grafana Cloud seguem pendentes de operação.
  Ressalva: tetos de 2 CPU/12 GiB por stack não reservam folga de sistema se
  ambos os stacks estourarem simultaneamente — monitorar a folga real do host
  antes da produção entrar
  (`compose/docker-compose.staging.yml:121,154-155,206-214,295-342,366-392`,
  `compose/prometheus/prometheus.staging.yml:14-44`,
  `env/.env.staging.example:12,25,74-86`,
  `../../docs/staging-compose.md:51-104`).

## Hermes_Robo_Whats_Python

Fora do stack nesta fase. Consumidor futuro da API privada do Radar
(mesmo padrão de rede interna). Sem imagem, compose ou CI neste momento.
