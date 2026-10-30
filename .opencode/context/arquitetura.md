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

## Desenvolvimento/integração (máquina local)

**Existente — dev:** mesma topologia principal de redes da produção planejada,
com a rede adicional `metrics-net` exclusiva do dev para o scrape do Backend,
emuladores no lugar dos serviços externos e sem cloudflared. Implementado em
`compose/docker-compose.dev.yml`, com healthchecks, `scripts/smoke.sh`,
isolamento da `radar-net`, `media-gateway` local para fotos públicas e
observabilidade local.
Detalhes de portas/publicação em `docs/networks.md`:

```text
services:
  postgres   postgres:16-alpine (db emporio)          127.0.0.1:5432
  backend    build ../Backend_Java (dev,container)    127.0.0.1:8080
             management 10.254.20.10:8081 somente na metrics-net
  radar      build ../Radar_Middleware_Python         SEM portas;
             env_file local do Radar (R2 de teste)
  rustfs     emula R2 do Back (quarentena/privado/    127.0.0.1:9000/9001
              público de fotos) + rustfs-init
  media-gateway  nginx para fotos públicas              127.0.0.1:9002 → :80
                (default externo 9002; MEDIA_GATEWAY_PORT é opcional)
  mailpit    SMTP com STARTTLS+auth; UI               127.0.0.1:8025
  loki       armazenamento local de logs              somente rede observability
  vector     coleta Fluent → Loki                     127.0.0.1:${VECTOR_FLUENTD_PORT:-24224} (driver)
  prometheus scrape do Backend pela metrics-net    também na observability
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

volumes:
  pgdata, rustfs-data, radar_state, prometheus-data (named); bind-mount somente-leitura
  de certs/dev para backend e mailpit (material TLS efêmero de dev,
  ignorado pelo git); loki-data, vector-data e grafana-data (named)
```

- **Existente — dev:** o Backend mantém ECS JSON em stdout/stderr e os serviços
  de aplicação e emuladores de longa duração usam o driver Docker `fluentd`
  assíncrono para o Vector local
  (`Backend_Java/src/main/resources/application-container.yml:24-33`,
  `Backend_Java/src/main/resources/logback-spring.xml:7-42`,
  `compose/docker-compose.dev.yml:25-35,151-172,174-282,292-316,325-355,385-410,417-439,447-468`). Loki,
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
  (`compose/docker-compose.dev.yml:53-76,119-145`,
  `compose/prometheus/prometheus.yml:1-17`,
  `compose/grafana/provisioning/dashboards/provider.yaml:1-12`,
  `compose/grafana/dashboards/emporio-backend.json:21-287`,
  `scripts/smoke.sh:80-115,221-256`, `scripts/metrics-resilience.sh:45-84`,
  `scripts/check-metrics-cardinality.py:13-30`,
  `scripts/check-grafana-provisioning.sh:1-21`,
  `Backend_Java/src/main/java/br/com/emporio/infrastructure/config/MetricsConfiguration.java:114-127,284-298`,
  `Backend_Java/src/main/java/br/com/emporio/infrastructure/observability/HttpMetricsFilter.java:33-34,81-89`).
- **Existente — dev:** `metrics-net` é `internal: true` e não publica 8081,
  mas isso não é firewall contra o próprio host Docker: o host pode alcançar
  diretamente `10.254.20.10:8081`. A arquitetura não promete bloquear esse
  acesso; a contenção verificada é entre containers e por ausência de publish
  (`compose/docker-compose.dev.yml:276-281,504-513`,
  `scripts/smoke.sh:62-78,139-150`).
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

## Cadeia CI/CD

```text
push em main (repo de aplicação)
  └─> GitHub Actions do repo
        job test    gate canônico do projeto
                    (Back: ./mvnw -B verify | Front: lint+typecheck+test+build
                     | Radar: uv sync + pytest + ruff)
        job image   docker/build-push-action + cache GHA
                    -> ghcr.io/emporiob2b/<repo>:<sha> e :latest
        job deploy  (somente em main) curl na API do Dokploy
                    -> redeploy do stack compose -> pull :latest -> recreate
```

- Cada projeto é um repositório independente, então a detecção de mudança é
  nativa: o workflow roda apenas no repo que recebeu o push.
- O compose de produção referencia `:latest` com `pull_policy: always`;
  toda imagem fica também tagueada com o sha do commit para rastreio e
  rollback (repin do sha anterior + redeploy).
- O repo Infra terá workflow próprio de validação (`docker compose config`,
  hadolint, actionlint) e disparará a suíte de integração sob demanda
  (planejado — nenhum `.github/workflows/` existe ainda em qualquer repo;
  TASK-INFRA-003/005; ver `estado_atual.md`).

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
