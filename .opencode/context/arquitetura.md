# Arquitetura da infraestrutura

Documento vivo da topologia alvo. Fatos por serviço (envs, portas, imagens)
ficam em `servicos.md`; justificativas de escolha ficam em `decisoes.md`.

## Domínios e borda Cloudflare (planejado — produção)

```text
Browser ──HTTPS──> Cloudflare (CDN/WAF/edge, TLS termina aqui)
  ├─ emporiob2b.com.br       ──tunnel──> front:4000   (Angular SSR)
  ├─ api.emporiob2b.com.br   ──tunnel──> api:8080     (Spring Boot)
  └─ media.emporiob2b.com.br ──────────> bucket público R2 (custom domain;
                                           sem gateway na VPS)
```

- O túnel é iniciado pela VPS (outbound); nenhuma porta HTTP/HTTPS é
  publicada no host. Além do SSH, a VPS não expõe superfície.
- O ingress do túnel é configurado no dashboard Zero Trust por hostname,
  apontando para os containers na rede Docker `apps`.
- O Back serve HTTP puro e confia em `X-Forwarded-*`
  (`forward-headers-strategy: framework`); o cloudflared injeta esses
  headers. Não existe terminação TLS dentro da VPS.
- `emporiob2b.com.br` e `api.emporiob2b.com.br` são same-site (mesmo
  eTLD+1): o cookie de refresh `SameSite=Lax` host-only da api continua
  válido no desenho de subdomínio. CORS com credentials é necessário
  (cross-origin) e já é o default do profile `prod` do Back.
- A porta de management do Back (8081) nunca é roteada pelo túnel.

## Produção (VPS + Dokploy) (planejado)

```text
Dokploy (painel) ── gerencia stack Compose do repo Infra (branch main)
                     imagens: ghcr.io/emporiob2b/* (pull_policy: always)

services:
  cloudflared ── apps ──> front:4000, api:8080
  front       ── apps ──> api:8080            (SSR server-side, rede interna)
  api         ── radar-net (internal) ──> radar:8000
  api, radar  ── egress ──> internet (Supabase:5432/6543, R2:443,
                                       SMTP:587, ViaCEP:443)
  api/front/radar ── stdout/stderr ──> Docker logs ──> Dokploy Vector
                                      ──> Grafana Cloud Loki (planejado)

networks:
  apps      bridge            cloudflared ↔ front ↔ api
  radar-net bridge internal   exclusivamente api ↔ radar; radar sem ports
  egress    bridge            saída controlada para serviços externos

volumes:
  radar_state  -> /var/lib/radar-middleware/state (SQLite reconstruível
                  a partir do R2 no bootstrap)

ausentes por decisão:
  postgres   (produção usa Supabase externo)
  traefik    (cloudflared roteia por hostname; ver decisoes.md)
```

O Radar não possui autenticação serviço-a-serviço implementada (mTLS é task
futura no repo Radar). Enquanto isso, a mitigação é estrutural: rede
`radar-net` interna e exclusiva, nenhuma porta publicada, egress somente
para R2/ViaCEP.

## Hospedagem OCI: staging primeiro, produção no mesmo host (planejado)

**Decisão do operador (2026-11-11):** provisionar staging primeiro e hospedar
produção futuramente na mesma VPS por não haver uma segunda máquina disponível.
O estado factual da instância e da rede está em
[`vps_oracle.md`](vps_oracle.md), com runbook em
[`../../docs/oracle-vps.md`](../../docs/oracle-vps.md).

```text
Browser → Cloudflare Access (staging) → Cloudflare Tunnel (outbound da VPS)
                                      → front/api do stack staging

VPS OCI única: Dokploy instalado + staging primeiro + produção futura
                projetos/stacks, redes, volumes e segredos separados
```

- A VM `VM.Standard.A1.Flex` roda Ubuntu 24.04 Minimal `aarch64`; a console OCI
  mostrou 4 OCPUs/24 GB como Always Free-eligible. Confirmar faturamento/quotas
  diretamente na tenancy; o selo do shape não comprova todos os recursos.
- Ingress OCI observado/configurado: SSH TCP/22 do IPv4 do operador em `/32`;
  não abrir 80/443/3000. A conexão `cloudflared` é outbound. Enquanto MFA/
  passkey estiver pendente na TASK-INFRA-022, o painel Dokploy fica somente via
  SSH forwarding local; não criar rota Tunnel/Access, DNS público ou ingress
  OCI para o painel.
- Staging será protegido por Cloudflare Access; não será adicionado Nginx Basic
  Auth na VPS. Hostnames aprovados: `staging.emporiob2b.com.br` para o Front e
  `api-staging.emporiob2b.com.br` para a API. O bucket público R2 dedicado de
  staging usará `media-staging.emporiob2b.com.br` como Custom Domain, fora do
  Tunnel. Disponibilidade/configuração desses domínios, Tunnel, Access e
  associação do Custom Domain R2 ainda não foram verificadas/configuradas;
  Access protege Front/API, não o domínio público de mídia.
- Stacks separados no mesmo Docker host são isolamento operacional, não
  isolamento forte: kernel, daemon e recursos físicos são compartilhados.
  Exigir segredos, banco, storage e dados de staging distintos; nunca permitir
  que staging use credenciais/dados de produção.
- **Contrato de staging decidido (TASK-INFRA-019):** PostgreSQL 17 local em
  container; bootstrap administrativo, migrador (`emporio_migrador`) e runtime
  (`emporio_app`) separados; sem copiar dados de produção. Back e Radar terão
  recursos/credenciais R2 dedicados de staging, não compartilhados entre si ou
  com produção; Radar usa R2 real. SMTP real terá credenciais próprias,
  STARTTLS+AUTH e remetente/destinatários controlados. Nomes reais dos buckets,
  credenciais, sender e dados de conexão continuam a ser provisionados pelo
  operador no Dokploy, nunca registrados aqui. Produção continua usando Supabase
  externo e não terá Postgres container. Detalhes: `../../docs/staging-contract.md`.
- **Existente — configuração staging do Front:** `apiBaseUrl` e `imageBaseUrl`
  apontam aos URLs aprovados e `allowedHosts` inclui `staging.emporiob2b.com.br`
  preservando `localhost` para o healthcheck
  (`../Front_Angular/angular.json:36-38,80-90`). Isso não comprova build/
  publicação ARM64 nem implantação. O contrato de build é API
  `https://api-staging.emporiob2b.com.br`, mídia
  `https://media-staging.emporiob2b.com.br` e Hosts permitidos
  `staging.emporiob2b.com.br` e `localhost`. O `scripts/build.mjs` possui
  perfil staging, mas o Dockerfile atual ainda executa `build:production`; a
  imagem precisa selecionar o perfil staging. Build/publicação ARM64 e deploy
  permanecem gates sob a governança dos repos donos.
- A arquitetura pretendida continua sem Traefik de aplicação: o Dokploy traz o
  Traefik dele, mas o Tunnel roteará diretamente aos containers. O modo de
  isolamento de deployments do Dokploy permanece por avaliar antes de implantar
  stacks de aplicação.
- **Gate ARM64:** imagens GHCR precisam incluir `linux/arm64`. A skill
  `cicd-ghcr` foi atualizada para exigir `linux/amd64,linux/arm64`; workflows de
  CI ainda não existem. Resolver nos repositórios donos e validar no staging
  ARM64 antes do deploy de produção.
- **Existente (2026-11-11):** Dokploy v0.31.0 instalado; projeto e serviço
  Compose `Emporio Staging` criados no painel, sem YAML nem aplicações, e o
  PostgreSQL de staging ainda não foi criado. Tunnel e Access ainda não
  configurados; painel acessado por SSH forward. MFA/passkey foi adiado com
  exceção temporária aceita e é acompanhado pela TASK-INFRA-022. Evidências em
  `vps_oracle.md`.
- **Existente — artefatos TASK-INFRA-020 no repo, não carregados no Dokploy nem implantados:**
  `compose/docker-compose.staging.yml` e `env/.env.staging.example` definem o
  projeto `emporio-staging`. `apps` é interna (front/api/cloudflared),
  `radar-net` interna e só API↔Radar; `database` interna (postgres/bootstrap/
  migrate/api). Redes `api-egress`, `radar-egress` e `tunnel-egress` são bridges
  separadas, cada uma ligada apenas ao serviço que precisa sair. Nenhum serviço
  publica porta. Volumes `emporio-staging_pgdata` (persistente) e
  `emporio-staging_radar_state` são named volumes. Teto aprovado inicial por
  stack: 1,5 CPU/3 GiB; limites long-lived no Compose somam 1,5 CPU/2.875 GiB
  e jobs one-shot têm limites próprios. Não é sizing validado por carga.
  O Dokploy File Mount `/bootstrap/roles.sql`, valores reais, imagens app ARM64,
  Tunnel/Access/R2/SMTP e primeiro deploy continuam pendentes (TASK-INFRA-021).

## Desenvolvimento/integração (máquina local)

**Existente — dev:** mesma topologia principal de redes da produção planejada,
com as redes adicionais `metrics-net` (scrape do Backend) e
`radar-metrics-net` (scrape do Radar),
emuladores no lugar dos serviços externos e sem cloudflared. Implementado em
`compose/docker-compose.dev.yml`, com healthchecks, `scripts/smoke.sh`,
isolamento da `radar-net`, `media-gateway` local para fotos públicas e
observabilidade local.
Detalhes de portas/publicação em `docs/networks.md`:

```text
services:
  postgres   postgres:16-alpine (db emporio)          127.0.0.1:5432
  db-bootstrap → migrate → backend (one-shot → API)
              roles SQL read-only; admin → migrador → app
  backend    emporio-backend:dev (build default ../Backend_Java;
              BACKEND_BUILD_CONTEXT override)         127.0.0.1:8080
  migrate    mesma imagem emporio-backend:dev; runner `migrate`
             management 10.254.20.10:8081 somente na metrics-net
  radar      build ../Radar_Middleware_Python         SEM portas;
             env_file local do Radar (R2 de teste); metrics 10.254.21.30:8082
  rustfs     emula R2 do Back (quarentena/privado/    127.0.0.1:9000/9001
              público de fotos) + rustfs-init
  media-gateway  nginx para fotos públicas              127.0.0.1:9002 → :80
                (default externo 9002; MEDIA_GATEWAY_PORT é opcional)
  mailpit    SMTP com STARTTLS+auth; UI               127.0.0.1:8025
  loki       armazenamento local de logs              somente rede observability
  vector     coleta Fluent → Loki                     127.0.0.1:${VECTOR_FLUENTD_PORT:-24224} (driver)
  prometheus scrape do Backend pela metrics-net    e Radar pela radar-metrics-net;
             também na observability
  grafana    UI/query Loki + Prometheus               127.0.0.1:${GRAFANA_PORT:-3000}
  front-dev  Dockerfile-dev (ng serve + proxy)        127.0.0.1:4200
  front-prod profile "prodlike": imagem SSR de        127.0.0.1:4000
              produção — [PLANEJADO], ainda não existe no compose
             (bloqueado pela TASK-INFRA-002; ver docs/networks.md)

networks:
  default    front-dev ↔ backend ↔ emuladores (postgres, rustfs, rustfs-init,
             media-gateway, mailpit); logging driver → Vector via loopback
  radar-net  internal: exclusivamente backend ↔ radar
  egress     radar → R2 de teste / ViaCEP
  observability  vector ↔ loki ↔ prometheus ↔ grafana; sem acesso a radar-net
  metrics-net    internal: backend:10.254.20.10 ↔ prometheus:10.254.20.20
  radar-metrics-net internal: radar:10.254.21.30 ↔ prometheus:10.254.21.20

volumes:
  pgdata = emporio-dev_pgdata_v2, rustfs-data, radar_state,
  prometheus-data (named); bind-mount somente-leitura
  de certs/dev para backend e mailpit (material TLS efêmero de dev,
  ignorado pelo git); loki-data, vector-data e grafana-data (named)
```

- **Existente — dev integrado:** banco segue `postgres → db-bootstrap → migrate → backend`. O bootstrap monta `database/bootstrap/roles.sql` como somente-leitura e recebe credenciais por ambiente; `migrate` é one-shot com `SPRING_FLYWAY_*`; a API runtime usa `emporio_app` e só inicia após a migration concluir com sucesso. A URL JDBC de migration usa `currentSchema` public-first; a URL runtime lista os schemas de domínio. `scripts/up-dev.sh` informa branch, SHA curto e estado clean/dirty; checkout fora do clone canônico `../Backend_Java` em `main` limpo é classificado como build de trabalho, não bloqueado (`compose/docker-compose.dev.yml:154-353`; `scripts/up-dev.sh:18-79,171-230`).
- **Existente — Fase 2 dev integrado:** `postgres → db-bootstrap → migrate → backend` é a cadeia do Compose. `backend` e `migrate` compartilham `emporio-backend:dev`; o launcher identifica branch, SHA e dirty state da fonte de build. O runner executa isoladamente em PostgreSQL descartável 16/17 via `tmpfs`; essa prova não substitui o Compose integrado (`compose/docker-compose.dev.yml:150-210,217-228,340-353`; `scripts/up-dev.sh:18-79,185-230`).
- **Credenciais dev:** `POSTGRES_ADMIN_USER/PASSWORD`, `SPRING_DATASOURCE_PASSWORD` e `SPRING_FLYWAY_PASSWORD` são configurações locais; o Backend recebe somente a senha runtime, e `migrate` somente a migradora. O bootstrap valida as três senhas (mínimo 32 caracteres alfanuméricos, distintas) sem imprimir seus valores (`env/.env.dev.example:23-36`; `compose/docker-compose.dev.yml:177-215`).
- **Validação integrada dev:** em 2026-11-09, `scripts/up-dev.sh --no-build` concluiu os jobs e iniciou serviços healthy; `scripts/smoke.sh` passou inclusive isolamento, métricas, mídia, RustFS e CORS; seed repetido confirmou os registros do admin sem duplicatas. O preflight indicou Backend em `main`, SHA `8eed3342dfecb4656df68d712dff1ef5389668d4`; como foi usado `--no-build`, isso não prova que a imagem local existente veio desse checkout. Os volumes v2 e legados foram preservados. Supabase gerenciado não foi testado (evidência: `.opencode/tasks/passadas/20261109_TASK-INFRA-016-db-bootstrap-migrate-dev.md`).
- **Planejado — produção:** o fluxo de roles/bootstrap e migration no Supabase gerenciado ainda exige validação operacional; a integração dev não constitui prova de prontidão de produção (`../Backend_Java/docs/database/DB-08-13-contrato-infra-backend.md:283-285,357-360`).

- **Existente — dev:** os volumes nomeados efetivos do banco e do estado do
  Radar são `emporio-dev_pgdata_v2` e `emporio-dev_radar_state_v2`. Eles
  preservam os volumes dev antigos sem remoção destrutiva, pois o estado antigo
  do Radar não tinha `cep_cidades` e o pgdata antigo carregava checksums Flyway
  incompatíveis (6/8). Essa recuperação é local de dev; não cria nem presume
  volumes equivalentes em produção.

- **Existente — dev:** o Backend mantém ECS JSON em stdout/stderr e os serviços
  de aplicação e emuladores de longa duração usam o driver Docker `fluentd`
  assíncrono para o Vector local
  (`Backend_Java/src/main/resources/application-container.yml:24-33`,
  `Backend_Java/src/main/resources/logback-spring.xml:7-42`,
  `compose/docker-compose.dev.yml:25-35,151-172,177-285,295-325,334-364,385-410,417-439,447-477`). Loki,
  Vector, Prometheus e Grafana usam `json-file` rotacionado para não formar um
  ciclo de coleta.
  Nenhum serviço monta `/var/run/docker.sock`.
- **Existente — dev:** o Grafana provisiona o datasource `Emporio Loki`, fica
  preso a `127.0.0.1` e o Loki retém logs locais por 7 dias no volume
  `loki-data`; o Vector possui buffer de sink em disco em `vector-data`.
- **Existente — dev:** o Prometheus `prom/prometheus:v3.5.0` coleta
  `10.254.20.10:8081/actuator/prometheus` pela `metrics-net` interna, sem porta
  publicada, e o Grafana provisiona o datasource `Emporio Prometheus`
  (uid `emporio-prometheus`) pela rede `observability`. A retenção local
  configurada é de 7 dias no volume `prometheus-data`, com WAL comprimido. O
  healthcheck usa `/-/ready` e o smoke também valida `/-/healthy`; o dashboard
  `emporio-backend-dev` é montado e provisionado de arquivo (provider com
  `updateIntervalSeconds: 30`, `allowUiUpdates: false`), e
  `scripts/check-grafana-provisioning.sh` prova o autoprovisionamento num
  Grafana descartável de banco vazio. O script de resiliência cobre restart do
  coletor, preservação do nome do volume e do hash da configuração, além do
  retorno do target `up` de 0 para 1 e a preservação de uma amostra histórica
  de `process_start_time_seconds`.
  O scrape carrega o **contrato de métricas vigente do Backend**
  (`servicos.md`, seção Backend_Java): HTTP **RED curado** presente
  (`http_server_requests_total` + `http_server_duration_seconds` com labels
  `route_template,method,status_class,outcome`), enquanto o binder cru
  `http_server_requests_seconds`, `disk_*`, `jvm_memory_*` por pool, GC pause e
  as famílias Tomcat de sessão/keepalive/cache/global continuam **excluídos**;
  heap e Tomcat aparecem como agregados **sem labels**; timers não têm
  buckets/percentis, então painéis usam média/máx, nunca
  `histogram_quantile`; RSS do container não é observável — pendência de
  instrumentação em `Backend_Java`, não decisão da Infra. O smoke veta só a
  família crua e prova a heap; a cardinalidade da fronteira é validada por
  allowlist de chaves de label (inclui `route_template`/`method`) sem
  duplicar os valores de domínio do Backend.
  O job `emporio-radar` raspa `10.254.21.30:8082/metrics` pela
  `radar-metrics-net` (`10.254.21.20` no Prometheus), separada da
  `metrics-net` do Backend para preservar o negativo Radar→Backend:8081. O
  Radar expõe readiness, processo, HTTP RED, consultas CEP por UF e cidade
  primária por código; o catálogo de coordenadas para Geomap continua pendente.
  (`compose/docker-compose.dev.yml:53-76,119-145,288-325,495-542`,
  `compose/prometheus/prometheus.yml:1-25`,
  `compose/grafana/provisioning/dashboards/provider.yaml:1-12`,
  `compose/grafana/dashboards/emporio-backend.json:21-335`,
  `scripts/smoke.sh:82-141,153-220,222-299`, `scripts/metrics-resilience.sh:45-84`,
  `scripts/check-metrics-cardinality.py:13-33`,
  `scripts/check-grafana-provisioning.sh:1-21`,
  `Backend_Java/src/main/java/br/com/emporio/infrastructure/config/MetricsConfiguration.java:114-127,284-298`,
  `Backend_Java/src/main/java/br/com/emporio/infrastructure/observability/HttpMetricsFilter.java:33-34,81-89`).
- **Existente — dev:** `metrics-net` é `internal: true` e não publica 8081,
  mas isso não é firewall contra o próprio host Docker: o host pode alcançar
  diretamente `10.254.20.10:8081`. A arquitetura não promete bloquear esse
  acesso; a contenção verificada é entre containers e por ausência de publish
  (`compose/docker-compose.dev.yml:276-281,495-522`,
  `scripts/smoke.sh:63-80,143-151`).
- **Planejado — produção:** o Dokploy configura `Settings → Logs & Metrics`
  com provider Grafana Loki; o `dokploy-vector` envia os logs dos containers
  para o endpoint HTTPS. O Dokploy não instala Loki/Grafana Cloud e nenhum
  token é versionado neste repo.

- O serviço da api chama-se `backend` de propósito: o `proxy.conf.json` do
  Front já aponta para `http://backend:8080`.
- O Radar em dev usa o bucket R2 de teste real (credenciais no `.env` local
  do projeto Radar, nunca versionado): o `config.py` valida
  `https://<account>.r2.cloudflarestorage.com` e rejeita S3 local.
- **Existente — dev:** RustFS é o R2 do Back, incluindo o bucket público de
  fotos. A leitura anônima do bucket (desvio `rustfs-init` dev-only) torna o
  emulador verificável em path-style direto; o `media-gateway` traduz a base
  pública default `APP_STORAGE_R2_PUBLICO_BASE_URL=http://localhost:9002` +
  `/public/asset/...` para
  `rustfs:9000/public-local/public/asset/...`. Assim, a base pública do Back
  não contém path e a URL de foto gerada pela aplicação é utilizável no
  navegador local. O gateway escuta na porta 80 do container, responde health
  em `/healthz`, aceita apenas `GET`/`HEAD` em `/public/asset/` e não
  encaminha privado, quarentena, raiz de bucket ou métodos de escrita (fontes:
  `compose/docker-compose.dev.yml:385-415`,
  `compose/media-gateway.nginx.conf:16-37`,
  `env/.env.dev.example:69-73`).
- **Existente — dev:** o `imageBaseUrl` do Front continua compilado conforme
  o bundle do Front; o media-gateway atende a base pública configurada pelo
  Back, não altera essa configuração do Front.
- Mailpit: como o Back exige SMTP autenticado com STARTTLS obrigatório
  quando email está habilitado (`servicos.md`), o dev serve o Mailpit com
  STARTTLS usando um certificado autoassinado SAN=`mailpit` e monta um
  truststore PKCS12 com esse certificado no backend (`/certs`, ro), via
  `scripts/gen-dev-certs.sh`. Material efêmero de desenvolvimento, nunca
  versionado; o profile `prod` usa o cacerts padrão com provedor real.
- Em dev HTTP puro, `APP_AUTH_COOKIE_SECURE` precisa do override explícito
  `false` no compose (o profile `container` defaulta `true` — `servicos.md`).
- O RustFS mantém a quarentena sem leitura anônima. O `rustfs-init` cria uma
  credencial dedicada ao Backend para `s3:GetObject` apenas em
  `quarantine-local/quarantine/*`; a policy não concede listagem, escrita,
  deleção ou recursos dos buckets privado/público; a leitura anônima dev-only
  do bucket público é uma regra independente. O CORS de GET/HEAD é aplicado
  também à quarentena e coberto pelo smoke nas origens locais permitidas.
- **Planejado — produção:** `APP_STORAGE_R2_PUBLICO_BASE_URL` será
  `https://media.emporiob2b.com.br`; o domínio custom serve diretamente o
  bucket público R2, sem `media-gateway` na VPS. O equivalente está descrito
  em `docs/storage-r2-handoff.md`, sem aplicação no R2, Cloudflare ou Dokploy.

## Cadeia CI/CD (publisher de roles existente; CI das aplicações ainda não verificada)

```text
PR para main (repo de aplicação)
  └─> GitHub Actions (existente no Backend; demais repos conforme contrato)
        job test    gate canônico do projeto
        push em main após gate verde
          └─> publicar imagem multiarch linux/amd64 + linux/arm64 no GHCR
              tag SHA completo; latest opcional, nunca seletor de deploy
              (planejado; contrato em docs/cicd.md)
  operador seleciona referências SHA completas e faz deploy manual no Dokploy
  (planejado para staging; produção fora do contrato)
```

- **Planejado — contrato de publicação das aplicações:** os três repos de aplicação publicam no GHCR privado após gate verde; cada publicação em `main` usa SHA completo e manifest multiarch. `latest` é dispensável e não seleciona deploy (`../../docs/cicd.md:10-19,31-35,62-76`).
- **Existente — workflows versionados, execução não verificada:** Infra contém `.github/workflows/publish-roles-bootstrap.yml` (valida o SQL em PostgreSQL 16/17 e o artefato, publica em push/main após os gates); Backend contém `.github/workflows/backend-ci.yml`. A existência dos arquivos não comprova runs, package GHCR, permissões Manage Actions access ou publicação/leitura remota. `validate.yml` e `integration.yml` continuam planejados (`../../.github/workflows/publish-roles-bootstrap.yml:1-16,25-43,66-103`; `../../docs/cicd.md:8-14,82-110`).
- **Existente — contrato do harness no Backend:** `EMPORIO_INFRA_ROLES_BOOTSTRAP_PATH` indica o caminho do SQL canônico externo lido pelos testes, com precedência sobre fallback allowlisted para a chave no `.env`; não contém o SQL e não substitui o bootstrap. O workflow Back deve disponibilizar o artefato e definir essa variável para `./mvnw -B verify`; essa integração remota ainda não foi verificada (`../Backend_Java/src/test/java/br/com/emporio/infrastructure/migration/InfrastructureRolesBootstrapSupport.java:21,30-42,45-69,71-109`; `../../docs/cicd.md:103-110`). A fonte SQL permanece Infra; migrations e runner Flyway permanecem Backend.
- **Planejado — fluxo de contribuição:** branch → PR para `main` → CI verde → merge é o processo manual da equipe. **Existente — contrato documentado:** branch protection não bloqueia tecnicamente push direto nem merge sem checks no estado atual que o contrato descreve; isso não comprova configuração real no GitHub. CODEOWNERS e proteção de branch com checks obrigatórios ficam para quando houver segundo mantenedor com escrita e o plano/configuração permitir (`../../docs/cicd.md:23-35,91-100,175-179`; `../skills/cicd-ghcr/SKILL.md:42-49`).
- **Planejado — staging:** o operador faz deploy manual no Dokploy selecionando referências SHA completas; Actions não chama API/webhook nem recebe segredos de deploy (`../../docs/cicd.md:13-19,103-110,115-139`).
- **Fora do escopo do contrato:** produção, promoção, workflow de produção e migration no Supabase (`../../docs/cicd.md:18-19,135-150`). Não há job de migration/deploy no fluxo CI/CD vigente.
- **Existente — estado observado:** há workflow publisher de roles na Infra e workflow de CI/publicação no Backend; ambos ainda carecem de evidência de execução remota nesta auditoria. Package GHCR de roles, Manage Actions access do Backend, consumo do artefato pelo workflow Back e publicação remota permanecem não verificados. Front, Radar e execução/deploy manual seguem sem comprovação nesta auditoria (`../../.github/workflows/publish-roles-bootstrap.yml:1-16`; `../Backend_Java/.github/workflows/backend-ci.yml:1-18`; `../../docs/cicd.md:8-14,91-110`).

## Estrutura do repositório

Alvo; o que existe hoje em cada caminho está fotografado em
`estado_atual.md`.

```text
infra/
  README.md                    # setup dev e resolução do RustFS no navegador
  AGENTS.md
  compose/
    docker-compose.dev.yml      # ambiente local integrado
    docker-compose.e2e.yml      # override para suíte automatizada
    docker-compose.prod.yml     # produção (Dokploy)
  env/
    .env.dev.example
    .env.prod.example           # checklist completo de segredos de prod
  cloudflare/
    tunnel-ingress.md           # hostnames, DNS e media->R2
  scripts/
    up-dev.sh  init-rustfs.sh  smoke.sh  e2e-run.sh
  docs/
    deploy-dokploy.md  networks.md  rollback.md  cicd.md
    storage-r2-handoff.md
  .github/workflows/
    validate.yml  integration.yml
```

Os repositórios de aplicação são clonados como irmãos do `infra/` na máquina
local (o compose de dev usa `build: ../<Projeto>`).
