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
- **Existente — VPS OCI (2026-11-11):** instância `emporio-infra-sp` em
  `SA-VINHEDO-1`/AD-1, `VM.Standard.A1.Flex` (4 OCPUs/24 GB ARM64), Ubuntu
  24.04 Minimal aarch64 e boot volume 100 GB. A console marcou o shape como
  Always Free-eligible; cobrança/uso total não foi auditado. VCN/subnet pública,
  rota pelo Internet Gateway e regra de SSH restrita ao IP de saída do operador
  foram reportadas como criadas; detalhes e evidência em
  [`vps_oracle.md`](vps_oracle.md) e
  [`../../docs/oracle-vps.md`](../../docs/oracle-vps.md).
- **Existente — acesso da VPS:** SSH como `ubuntu` por chave, `sudo` funcional;
  `PermitRootLogin no`, `PasswordAuthentication no`,
  `KbdInteractiveAuthentication no`. Nova sessão validada. Nmap TCP da origem
  autorizada encontrou só `22/tcp open`; não foi scan UDP.
- **Existente — Dokploy (2026-11-11):** `v0.31.0` instalado; serviços
  `dokploy`/`dokploy-postgres` reportados 1/1 Running e Traefik Up. O projeto
  `Emporio Staging` e um serviço Compose foram criados no painel, sem YAML ou
  app implantado. Nmap TCP pós-instalação (22/80/443/3000), da origem autorizada,
  mostrou só 22/tcp aberta; containers publicam portas localmente, OCI bloqueia
  ingress web. Painel acessado por SSH forward `:13000`; operador adiou
  MFA/passkey e aceitou exceção temporária. TASK-INFRA-018 foi arquivada com
  esta exceção; TASK-INFRA-022 acompanha o MFA. Não criar rota não-SSH ao painel
  enquanto ela estiver pendente.
- **Contrato decidido — TASK-INFRA-019:** PostgreSQL 17 local com roles
  administrativas/migradora/runtime separadas; dados próprios, sem cópia de
  produção; R2 dedicado por serviço (Back e Radar); SMTP real com credenciais
  distintas da produção e STARTTLS+AUTH; hostnames aprovados
  `staging.emporiob2b.com.br`, `api-staging.emporiob2b.com.br` e
  `media-staging.emporiob2b.com.br` (Custom Domain do bucket público R2). Nomes
  reais de buckets e credenciais não foram provisionados/registrados.
  **Existente — artefatos TASK-INFRA-020:** Compose
  `compose/docker-compose.staging.yml`, template
  `compose/prometheus/prometheus.staging.yml`, example de env, runbook e
  handoff Cloudflare. **Existente — contrato de logo estático de email:**
  há script manual staging-only e `env/.env.email-logo.staging.example` para
  publicar o PNG no bucket público de staging; a referência é fixa em
  `/img/email/logo.png`, não seleciona logo por organização e não altera DB
  (`scripts/publish-email-logo-staging.sh:2-3,6-10,13-26,29-43,45-67`,
  `docs/staging-compose.md:85-103`). **Existente — staging artefatos:** o
  Compose usa `APP_MEDIA_BASE_URL` e exige também
  `CADASTRO_CONFIRMATION_BASE_URL` e `APP_PASSWORD_RESET_BASE_URL`
  (`compose/docker-compose.staging.yml:120-122`); o example cobre as três
  (`env/.env.staging.example:23-25`). **Existente — código irmão:**
  `Backend_Java_Anuncios` usa `APP_MEDIA_BASE_URL` e exige as URLs de
  confirmação/reset no profile `prod`
  (`../Backend_Java_Anuncios/src/main/resources/application.yml:158`,
  `../Backend_Java_Anuncios/src/main/resources/application-prod.yml:8-11`). O clone canônico `Backend_Java` usado pelo
  Compose dev ainda lê `APP_EMAIL_MEDIA_BASE_URL` e mantém defaults locais
  (`src/main/resources/application.yml:93,113,158`; `application-prod.yml:9`);
  não concluir que o nome legado pode ser removido do dev. **Relato do operador,
  não verificado independentemente nesta sessão:** associação Custom Domain R2
  `media-staging.emporiob2b.com.br` e asset do logo funcionais; não houve acesso
  a Cloudflare/R2/VPS nem validação de deploy nesta auditoria.
  **Relato do operador, não verificado independentemente nesta sessão:**
  staging funcional. O operador também mostrou logs de API/Front do stack no
  Grafana Cloud; isso comprova que alguns containers produziram logs recebidos,
  mas não confirma saúde integral, rotas ou o estado do deploy. **Existente — borda
   Cloudflare de staging (2026-11-13):** zona `emporiob2b.com.br` Active
  (NS `dora`/`gannon.ns.cloudflare.com`); túnel remotamente gerenciado
  `emporio-staging` (`87a7e326-bc1b-43fb-9091-212fa38e0fdb`) criado no
  dashboard da conta dona da zona. No último estado verificado (2026-11-13), o
  connector estava Inactive e ainda não implantado na VPS; deveria ligar via
  compose/Dokploy no deploy. O relato posterior de logs Cloud não confirma seu
  estado atual.
  **Verificado (2026-11-13, `dig`/`curl` públicos):** DNS de
  `staging.emporiob2b.com.br` e `api-staging.emporiob2b.com.br` na borda
  Cloudflare (`188.114.96.2`/`188.114.97.2`, proxied) e Access interceptando
  ambos com HTTP 302 ao login do time domain `soft-salad-0948`.
  **Reportado pelo operador (não verificado independentemente):** rotas de
  published application `staging` → `http://front:4000` e `api-staging` →
  `http://api:8080` (o painel exige URL com prefixo `http://`), alvo CNAME
  `<tunnel-id>.cfargotunnel.com` no dashboard e SSL/TLS da zona em Full
  (strict). Policy/IdP do Access não auditados; o 302 prova interceptação,
  não login — primeiro login real pendente. `media-staging.emporiob2b.com.br`
  tem associação Custom Domain R2 e logo público reportados pelo operador como
  funcionais, sem verificação independente nesta sessão; fica fora do túnel.
  Imagens GHCR ARM64 e
  perfil staging da imagem do Front verificados em 2026-11-13
  (`imagetools inspect` + `grep` na imagem publicada; referências no bullet
  de imagens abaixo); **Existente — wiring de File Mounts no artefato:** o
  Compose referencia `../files/roles.sql`, `../files/prometheus.template.yml`
  e `../files/remote-write-token` como binds read-only para
  `/bootstrap/roles.sql`, `/etc/prometheus/prometheus.template.yml` e
  `/etc/prometheus/remote-write-token`. Render/topologia validado com
  `docker compose config` e inspeção dos mounts; isso não comprova arquivos
  existentes no Dokploy. O File Mount anteriormente informado pelo operador
  tinha UI `File Path /bootstrap/roles.sql`, `Mount Path /`; mapeamentos finais
  da UI e arquivos presentes nos containers não foram confirmados. Os File Paths
  devem produzir os nomes exatos sob `../files/`. Fonte:
  `compose/docker-compose.staging.yml:63-65,322-325`,
  `../../docs/staging-compose.md:32-51`.
  **Relato posterior do operador:** logs de API/Front aparecem no Grafana Cloud;
  provider/agente e labels ainda não foram auditados independentemente. Env de
  métricas no painel (nomes e URLs não secretos verificados no example), valores
  reais, primeiro login Access, connector e saúde integral/deploy/smoke não
  foram verificados nesta sessão. Ver
  [`../../docs/staging-contract.md`](../../docs/staging-contract.md).
- **Existente — conta/stack Grafana Cloud (2026-11-13, criada pelo operador):**
  slug `smallmarzipan1294`, região `prod-sa-east-1` (São Paulo), free tier.
  Access Policies criadas: `emporio-staging-logs` (`logs:write`) e
  `emporio-staging-metrics` (`metrics:write`); a geração dos tokens não está
  confirmada (a policy de metrics exibia 0 tokens na última tela vista) e
  nenhum token foi visto/registrado. Endpoints públicos de ingestão
  verificados por `curl` (HTTP 401 sem auth — existem e exigem autenticação):
  Loki `https://logs-prod-024.grafana.net` (tenant/user `1878826`) e Prometheus
  remote_write
  `https://prometheus-prod-40-prod-sa-east-1.grafana.net/api/prom/push`
  (instance/user `3766316`, consistente com a URL do datasource de usage
  insights do stack). Os IDs são usuários de basic auth, não segredos. Os
  datasources provisionados na UI do Grafana exibem URLs internas
  `*-local-nlb.internal.grafana.net`, que não servem para ingestão externa;
  os endpoints públicos acima são os corretos. Destino: URL Loki + tenant
  `1878826` + token `logs:write` → provider Grafana Loki no Dokploy
  (`Settings → Logs & Metrics`, última verificação em 2026-11-13 indicava
  não configurado; o relato mais recente do operador está abaixo); URL
  remote_write + instance
  `3766316` → envs do Compose de staging; token `metrics:write` → File Mount
  `/etc/prometheus/remote-write-token`. **Existente — example atualizado:**
  `env/.env.staging.example:74-86` contém os valores verificados de
  `PROMETHEUS_REMOTE_WRITE_URL/USERNAME` (não secretos) e comentários com a
  URL/user do provider Loki e o destino dos tokens (somente painel/File
  Mount); `docker compose config --quiet` com o example vigente exit 0.
  **Relato do operador (2026-11-14, não verificado independentemente nesta
  sessão):** logs de staging aparecem no Grafana Cloud. O Label browser reportado
  lista `dokploy_application`, `dokploy_environment`,
  `dokploy_organization`, `dokploy_project`, `dokploy_server`, `dokploy_test`
  e `service_name`; `service_name=unknown_service`,
  `dokploy_application=emporio-staging` e
  `dokploy_environment=production`. `dokploy_service` não é label indexado;
   o envelope externo é JSON com `message` contendo JSON interno. **Relato do
   operador (2026-11-14):** confirmou no Cloud os snippets LogQL, a busca por
   Request/Correlation ID API→Radar e que os gráficos não navegam. Provider/
   agente e ingestão de métricas não foram verificados independentemente nesta
   sessão.
- **Plano aprovado — hosting:** staging primeiro; produção futura dividirá a
   mesma VPS por não haver outra máquina. Stacks, redes e segredos separados não
   formam uma fronteira forte de segurança. Cloudflare Access de staging
   configurado na borda e interceptando os dois hostnames (302 verificado em
   2026-11-13); túnel `emporio-staging` criado no dashboard. Último estado do
   connector verificado em 2026-11-13: Inactive, ainda não ligado na VPS.
   Operador posteriormente mostrou logs da API/Front no Grafana Cloud, mas isso
   não comprova o connector, o túnel público ou saúde integral. Primeiro login
   Access segue sem evidência independente nesta sessão.
- **Planejado — contrato CI/CD das aplicações:** `docs/cicd.md` determina gate de testes e
  publicação GHCR multiarch `linux/amd64,linux/arm64` por SHA completo em
  `main`; `latest` é opcional e não seleciona deploy. Deploy de staging é
  manual no Dokploy pelo operador; Actions não faz deploy. Produção está fora
  do contrato (`docs/cicd.md:8-19,23-35,62-76,115-129`).
- **Existente — estado dos workflows:** Infra tem `.github/workflows/publish-roles-bootstrap.yml`,
  Backend tem `.github/workflows/backend-ci.yml` e Radar tem
  `.github/workflows/ci.yml` (job verify com pytest+ruff e job publish em push
  de `main`, tag `sha-<github.sha>`, `platforms: linux/amd64,linux/arm64`,
  actions pinadas por SHA). Os três estão versionados. Front não possui
  diretório `.github/` — segue sem workflow de CI/publicação; sua imagem de
  staging foi publicada manualmente pelo operador. A publicação remota das
  imagens de aplicação está verificada (2026-11-13, `docker buildx imagetools
  inspect` colado pelo operador; referências no bullet de imagens abaixo): as
  tags do Back (SHA completo) e do Radar (`sha-<SHA>`) coincidem com o formato
  dos workflows versionados, evidenciando execução dos jobs de publicação; os
  runs no Actions em si não foram auditados. Package GHCR de roles, Manage
  Actions access do Backend, consumo remoto do artefato pelo workflow Back e
  deploy continuam não verificados; os pacotes
  `emporiob2b/{backend-java,front-angular,radar-middleware}` existem com as
  tags verificadas e não são legíveis anonimamente (privados). A tag
  `sha-<SHA>` do Radar diverge
  do formato `<sha-completo>` previsto no contrato
  (`.github/workflows/publish-roles-bootstrap.yml:1-16,25-43,66-103`;
  `../Backend_Java/.github/workflows/backend-ci.yml:1-18,44-53,109-120`;
  `../Radar_Middleware_Python/.github/workflows/ci.yml:18-59,77-85`;
  `docs/cicd.md:8-14,67-74,91-110`).
- **Existente — contrato do harness de roles:** no Backend, `EMPORIO_INFRA_ROLES_BOOTSTRAP_PATH`
  é um caminho de arquivo lido pelo harness de testes; variável de processo tem
  precedência e, ausente, o harness lê apenas essa chave exata do `.env`, sem
  carregar outras chaves. O workflow Back versionado já baixa o package
  `infra-roles-bootstrap` pinado por digest, extrai `/bootstrap/roles.sql` e
  define essa variável antes de `./mvnw -B verify`; a execução remota e o
  acesso ao package não estão verificados
  (`../Backend_Java/src/test/java/br/com/emporio/infrastructure/migration/InfrastructureRolesBootstrapSupport.java:21,30-42,45-109`;
  `../Backend_Java/.github/workflows/backend-ci.yml:26-27,44-68`;
  `docs/cicd.md:103-110`). O SQL canônico e bootstrap de roles pertencem à Infra;
  migrations e runner Flyway pertencem ao Backend.
- **Existente — Front staging parametrizado:** o repo dono define as URLs de
  staging e `allowedHosts`, e o Dockerfile aceita `ARG BUILD_PROFILE=production`,
  `ARG API_BASE_URL` e `ARG IMAGE_BASE_URL`, executando
  `npm run build -- "$BUILD_PROFILE"`; `build.env.example` documenta as URLs de
  staging como entradas de build. A imagem ARM64 publicada manualmente está
  verificada (2026-11-13, `imagetools inspect`) e o perfil staging do bundle
  publicado também (2026-11-13, `grep` na imagem; evidência no bullet de
  imagens abaixo); comprovar run/deploy segue gate da TASK-INFRA-021, e os
  pré-requisitos de produção/prodlike do Front seguem sob TASK-INFRA-002/003;
  o Front não tem workflow de CI/publicação
  (`../Front_Angular/Dockerfile:17-19,33-35`,
  `../Front_Angular/build.env.example:1-5`,
  `../Front_Angular/angular.json:36-38,78-85`).
- **Existente — dev:** compose de desenvolvimento em
  `compose/docker-compose.dev.yml`, definindo todos os serviços de longa duração,
  e jobs one-shot `db-bootstrap` e `migrate` para o contrato DB-08 Infra–Backend;
  `media-gateway` local para fotos públicas, `scripts/smoke.sh`, policy
  dedicada, isolamento da `radar-net`, SMTP dev e observabilidade local
  Vector/Loki/Prometheus/Grafana. Arquivos de suporte:
  `README.md` (setup dev, logs no Grafana e requisito de hosts do upload direto),
  `env/.env.dev.example` (cobre todas as
  `${VAR:?}` do compose; placeholders apenas), `scripts/up-dev.sh`,
  `scripts/init-rustfs.sh`, `scripts/smoke.sh`, `scripts/gen-dev-certs.sh` e
  `docs/networks.md`/`docs/observability.md`.
- **Existente — dev:** o example cobre os nomes das variáveis obrigatórias com
  placeholders completos `replace-with-*`; o operador ainda precisa substituir
  cada valor antes da subida, pois o `rustfs-init` rejeita placeholders como
  credenciais reais (`env/.env.dev.example:23-43,53`,
  `scripts/init-rustfs.sh:8-24`).
- **Existente — dev:** os logs dos serviços de aplicação seguem stdout/stderr
  pelo driver Docker `fluentd` assíncrono para `vector`; Loki e Grafana não
  montam Docker socket, a UI do Grafana fica em loopback e os dados usam
  `loki-data`, `vector-data` e `grafana-data`. O Vector também não monta o
  socket; seu healthcheck consulta a API local de liveness, enquanto a
  validação de configuração e o smoke verificam a chegada de um log do Backend
  ao Loki. O launcher aguarda healthchecks dos serviços long-lived e estados
  de sucesso dos jobs one-shot (`scripts/up-dev.sh:75-81,122-154`;
  `compose/docker-compose.dev.yml:53-596`)
  e o smoke contém a prova de ingestão (`scripts/smoke.sh:362-367`).
- **Existente — dev:** o Backend e o Prometheus participam da `metrics-net`
  (`internal: true`, subnet `10.254.20.0/24`); o Backend usa
  `10.254.20.10:8081` para management e o Prometheus usa `10.254.20.20`.
  O Prometheus não publica porta, participa também da rede `observability`,
  mantém retenção de 7 dias com WAL comprimido no volume `prometheus-data` e o
  Grafana possui o datasource `emporio-prometheus` e o dashboard
  `emporio-backend-dev` provisionados por arquivo (provider com
  `updateIntervalSeconds: 30`, `allowUiUpdates: false`). O bootstrap
  aguarda os healthchecks declarados; o smoke contém checks de health/readiness
  (`/-/healthy` e `/-/ready` do coletor), scrape, target, datasource,
  dashboard, cardinalidade, logs e isolamento, veta no scrape somente a família
  crua `http_server_requests_seconds` e `disk_*` — não o RED curado, que é
  legítimo —, prova a heap agregada `jvm_heap_used_bytes` e valida o HTTP RED
  quando há tráfego `/api` desde o boot; ainda exige que `front-dev` esteja
  running/healthy além de responder em `127.0.0.1:4200`.
  `scripts/metrics-resilience.sh` cobre restart/recuperação sem remoção de
  volume, verificando identidade do volume, hash da configuração e transição do
  target `up` de 0 para 1, além da persistência de uma amostra histórica de
  `process_start_time_seconds`; `scripts/check-grafana-provisioning.sh` prova o
  autoprovisionamento do dashboard num Grafana descartável de banco vazio, sem
  tocar o `grafana-data` do dev. O dashboard está alinhado ao contrato vigente
  do Backend (`servicos.md`, seção Backend_Java): HTTP RED curado, latência por
  média/máx (nenhuma série `*_bucket` no scrape — `histogram_quantile` não
  funciona), heap/Tomcat agregados sem labels, Hikari e executores; o painel de
  classes carregadas usa a série observada `jvm_classes_loaded_classes`, e o
  teste do Backend é que afirma o prefixo `jvm_classes_loaded_count` no scrape
  (`MetricsConfigurationTest.java:621-624`). O checker de cardinalidade da
  Infra (`scripts/check-metrics-cardinality.py`) mantém allowlist de chaves de
  label da fronteira — incluindo `route_template`, `method`, `uf` e
  `codigo_cidade` — sem duplicar os valores de domínio do Backend; o mesmo
  checker é aplicado ao scrape do Radar pelo smoke. O host Docker também pode alcançar
  diretamente `10.254.20.10:8081`; `internal: true` e ausência de `ports:` não
  constituem firewall contra o host (`scripts/smoke.sh:62-80,143-151`;
  `compose/docker-compose.dev.yml:495-522`).
- **Existente — dev:** o mesmo Prometheus coleta o Radar pela
  `radar-metrics-net` em `10.254.21.30:8082/metrics`, sem publicação de 8082.
  A rede é separada da `metrics-net` para manter o isolamento Radar→Backend:8081;
  o smoke verifica target, readiness, labels e os membros das três redes
  (`compose/docker-compose.dev.yml:288-325,495-532`,
  `compose/prometheus/prometheus.yml:18-25`, `scripts/smoke.sh:117-220,289-299`).
- **Existente — Radar promovido:** o código usa `METRICS_BIND_ADDRESS` e
  `METRICS_PORT`, listener WSGI bounded em 8082 e registro isolado com
  `radar_health_ready`, `process_*`, HTTP RED, consultas CEP e cidade primária
  por `uf,codigo_cidade`. O mapa empacotado de municípios contém nomes/códigos,
  mas não coordenadas; Geomap permanece **planejado**. Traceback residual em
  stderr é aceito pelo dono do Radar e não altera o endpoint privado
  (`Radar_Middleware_Python/src/radar_middleware/infrastructure/config.py:201-207`,
  `Radar_Middleware_Python/src/radar_middleware/infrastructure/observability/prometheus.py:72-165,240-248`,
  `Radar_Middleware_Python/src/radar_middleware/infrastructure/cep/data/municipios_rfb.csv:1`).
- **Existente — dev:** os volumes efetivos de banco e estado do Radar são
  `emporio-dev_pgdata_v2` e `emporio-dev_radar_state_v2`. Os volumes antigos
  `emporio-dev_pgdata` e `emporio-dev_radar_state` foram reportados pelo Compose
  como remanescentes e deixados intactos; na execução integrada reportada,
  `emporio-dev_pgdata_v2` foi criado. Os volumes antigos são preservados para
  rollback/investigação manual: o estado antigo do Radar não tinha
  `cep_cidades`, e o pgdata antigo carregava checksums Flyway incompatíveis
  (6/8). Essa recuperação é somente local de dev; a produção continua sem
  PostgreSQL em container e o SQLite do Radar é reconstruível
  (`compose/docker-compose.dev.yml:534-542,607-610`; execução reportada pelo
  operador).
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
  `rustfs:9000` (fontes: `compose/docker-compose.dev.yml:385-415`,
  `compose/media-gateway.nginx.conf:16-37`,
  `env/.env.dev.example:69-73`).
- **Existente — dev:** `scripts/seed-admin-dev.sh` conecta ao Postgres como o
  usuário administrativo configurado pelo serviço e define o `search_path`
  para `identidade,pg_catalog`; semeia, em uma
  transação, o usuário de teste, o vínculo `ATIVO` na organização
  `PLATAFORMA`, o papel `ADMIN_NEGOCIO`/`PLATAFORMA` e as nove capacidades
  administrativas de plataforma. A senha do fixture vem de
  `ADMIN_DEV_PASSWORD` no ambiente local ignorado e não é impressa. O fixture
  continua somente de dev e não cria `perfil_usuario` (fonte do artefato:
  `scripts/seed-admin-dev.sh:46-49,84-249`;
  schema/contratos: `Backend_Java/src/main/resources/db/migration/V2__autenticacao_autorizacao.sql:109-145,376-424`).
- **Limitação existente — dev:** `scripts/seed-admin-dev.sh` só pode rodar
  depois que o Postgres novo estiver saudável e o serviço one-shot `migrate`
  tiver aplicado o schema vigente; o SQL do seed define `search_path` para
  `identidade,catalogo,mercadoria,comercial,infraestrutura,venda,pedidos,public`.
  Ele cria o usuário, vínculo, papel e nove
  capacidades, mas não cria `perfil_usuario`. É um seed local do Back, não uma
  preparação de produção (`scripts/seed-admin-dev.sh:46-49,92-94,204-250`,
  `Backend_Java/src/main/resources/application.yml:37-39`,
  `Backend_Java/src/main/resources/db/migration/V2__autenticacao_autorizacao.sql:16-60`).
- **Existente — seed manual de admin do staging (artefato; execução não verificada nesta sessão):**
  `scripts/seed-admin-staging.sh --confirm-staging` é uma operação separada do
  bootstrap, migration, API e deploy; exige acesso ao daemon Docker que gerencia
  o projeto Compose `emporio-staging` (ou o sufixo de projeto gerado pelo Dokploy),
  encontra exatamente um container `postgres` em execução e saudável, e requer
  confirmação digitada `staging`.
  Solicita senha sem eco, gera BCrypt custo 12 e executa seed idempotente em
  transação usando a credencial administrativa dentro do container. Cria/atualiza
  `admin@emporiob2b.com.br`, ativa o vínculo e concede `ADMIN_NEGOCIO` com escopo
  `PLATAFORMA` e nove capacidades administrativas. A migration V1 do Backend,
  não o seed, cria a organização ativa `Emporio B2B` (`PLATAFORMA`). O resultado
  equivale a superusuário de staging; não usar em produção. A senha em claro não
  é gravada nem impressa (somente o hash BCrypt fica no banco); ao repetir a
  execução, a senha informada é substituída. Não cria `perfil_usuario`
  (`scripts/seed-admin-staging.sh:2-3,6-18,21-41,44-65,67-92,94-130,132-174,177-191`;
  `../../docs/staging-compose.md:62-78`;
  `../Backend_Java/src/main/resources/db/migration/V1__fundacao_clientes.sql:92-96`).
  O operador informou que staging está funcional, mas esta sessão não acessou
  VPS/staging nem executou o seed; funcionamento e resultado em runtime não
  foram verificados independentemente.
- **Existente — dev integrado / contrato DB-08:** `database/bootstrap/roles.sql` é o artefato Infra canônico para `psql`, sem senhas nem grants DML de domínio; o Compose o monta em `db-bootstrap` como read-only e injeta as senhas de serviço por ambiente. `db-bootstrap` verifica que as três credenciais tenham ao menos 32 caracteres, sejam somente alfanuméricas e distintas, sem imprimir valores. `migrate` chama `migrate` com `SPRING_FLYWAY_*`; `backend` usa `emporio_app`, `SPRING_DATASOURCE_PASSWORD` e `currentSchema` dos schemas de domínio, dependendo de sucesso do job. `env/.env.dev.example` nomeia as três variáveis. `scripts/up-dev.sh --no-build` completou os jobs e deixou os serviços healthy; o seed idempotente confirmou os registros do admin e `scripts/smoke.sh` passou os gates de API, métricas, isolamento, Front, RustFS, mídia e CORS. O histórico Flyway e `identidade.usuario` existem no PostgreSQL dev. Os volumes legados foram preservados (`database/bootstrap/roles.sql:3-5`; `compose/docker-compose.dev.yml:154-368`; `env/.env.dev.example:21-27`).
- **Existente — preflight dev:** `scripts/up-dev.sh` identifica branch, SHA curto e dirty state do contexto Backend configurado; permite checkout de trabalho com aviso, enquanto apenas o clone `../Backend_Java` em `main` limpo é classificado canônico. Não lê `.env` do Backend (`scripts/up-dev.sh:18-28,50-79`).
- **Planejado — produção:** validar bootstrap/roles e a sequência de migration em PostgreSQL 17 gerenciado/Supabase ainda é requisito antes de afirmar prontidão; testes em PostgreSQL descartável e Compose dev não demonstram essa prontidão (`../Backend_Java/docs/database/DB-08-13-contrato-infra-backend.md:283-285,357-360`).
- **Existente — dev:** `scripts/up-dev.sh` inicia RustFS antes do restante do stack, confirma seu
  attachment à rede default do projeto e recria somente o container RustFS
  se a rede estiver ausente, preservando `rustfs-data`. O job
  `rustfs-init` usa `scripts/init-rustfs.sh` read-only, cria as credenciais
  read-only geral e dedicada da quarentena, espera o endpoint
  `rustfs:9000` com até 15 tentativas separadas por 2 segundos e o launcher
  imprime os logs do job caso falhe; o launcher também
  anuncia a URL do `media-gateway` após a subida.
- **Existente — Fase 1 de roles PostgreSQL:** `database/bootstrap/roles.sql`
  cria/configura `emporio_owner` (NOLOGIN), `emporio_migrador` e
  `emporio_app` (LOGIN), permitindo ao migrador `SET ROLE emporio_owner` sem
  herança ou delegação de membership; o runtime não recebe membership de owner
  nem CREATE no database/schema `public`. O bootstrap não define senhas, grants
  DML de domínio nem `ALTER DEFAULT PRIVILEGES`
  (`database/bootstrap/roles.sql:3-7,9-95`).
- **Existente — Fase 1, prova isolada:** `scripts/smoke-db-roles.sh` aceita
  `postgres:16-alpine` e `postgres:17-alpine`, executa em container descartável
  com `tmpfs` e credenciais efêmeras geradas em memória; remove o container ao
  sair. Verifica autenticação, atributos/membership, `SET ROLE`/ownership,
  restrições de `emporio_app` e fixtures humanas sintéticas. **Não** valida
  Supabase gerenciado, configuração/ownership real no Supabase, nem a conexão
  do processo Java como `emporio_app`
  (`scripts/smoke-db-roles.sh:1-18,26-64,102-183,185-260`).
- **Existente — Fase 2, Compose dev:** a cadeia é `postgres → db-bootstrap →
  migrate → backend`; `backend` e `migrate` usam a mesma imagem local
  `emporio-backend:dev`. `db-bootstrap` executa o SQL canônico read-only e
  provisiona credenciais distintas; `migrate` executa o runner Flyway do
  Backend como `emporio_migrador`, e o runtime usa `emporio_app` com
  `currentSchema` de schemas de domínio, sem segredo admin/migrador
  (`compose/docker-compose.dev.yml:150-210,217-228,336-353`,
  `env/.env.dev.example:23-32`, `docs/database-roles.md:47-71`).
- **Existente — launcher dev:** o contexto de build default é
  `../Backend_Java`, configurável por `BACKEND_BUILD_CONTEXT`; o launcher
  reporta branch, SHA curto e estado clean/dirty e classifica checkout que não
  seja o clone canônico `main` limpo como fonte de trabalho
  (`compose/docker-compose.dev.yml:217-222`, `scripts/up-dev.sh:18-28,50-79`).
- **Existente — launcher dev:** a subida padrão constrói explicitamente as
  imagens locais do Backend e do Radar antes de iniciar o stack; `--no-build`
  reutiliza as imagens locais existentes e falha se qualquer uma estiver
  ausente (`scripts/up-dev.sh:28-29,155-166`).
- **Existente — prova isolada:** `scripts/smoke-db-roles.sh` passou em banco
  descartável. O `scripts/smoke-db-migration-runner.sh` é parametrizado para
  `postgres:16-alpine` e `postgres:17-alpine`; ambos os comandos passaram,
  segundo a execução reportada, usando a imagem local `emporio-backend:dev`
  construída do clone `Backend_Java_Cliente`. A prova usa PostgreSQL em tmpfs,
  aplica V1–V10, verifica API Java healthy, sessão runtime como `emporio_app`
  e nega DDL, TRUNCATE e `SET ROLE` para o runtime, sem volume persistente
  (`scripts/smoke-db-roles.sh:1-18,49-64,102-187,263`,
  `scripts/smoke-db-migration-runner.sh:1-5,22-24,33-48,67-91,93-149`). Não
  valida o clone canônico `../Backend_Java` nem o Supabase gerenciado.
- **Existente — dev, smoke integrado aprovado (execução reportada):** o operador
  executou `scripts/up-dev.sh` com
  `BACKEND_BUILD_CONTEXT=../Backend_Java_Cliente`; `db-bootstrap`, `migrate` e
  `rustfs-init` terminaram com exit 0 e os serviços de longa duração ficaram
  healthy. O launcher identificou source branch `dev/cliente`, SHA
  `bf99658885e9`, dirty com 5 entradas: build de trabalho, não canônico. Nesta
  sessão, `scripts/smoke.sh` terminou com exit 0; passaram os checks de
  bootstrap/migration, V10, sessão Java como `emporio_app`, negações de
  DDL/TRUNCATE/SET ROLE, redes, Radar, RustFS e observabilidade. HTTP RED idle
  foi `SKIP` esperado, pois não havia tráfego `/api`. O volume
  `emporio-dev_pgdata_v2` foi criado nesta subida; `emporio-dev_pgdata` e
  `emporio-dev_radar_state` foram reportados como remanescentes e deixados
  intactos. A evidência valida esse clone de trabalho e essa execução, não o
  clone canônico `../Backend_Java` em `main` nem o Supabase gerenciado
  (launcher: `scripts/up-dev.sh:18-28,50-79,171-198`; verificações:
  `scripts/smoke.sh:83-157,407-412`; execução e saída completas reportadas pelo
  operador).
- **Planejado — produção:** validar o bootstrap/ownership e a separação de
  credenciais no Supabase gerenciado; nenhuma prova local substitui essa
  validação (`database/bootstrap/roles.sql:3-7`, `docs/database-roles.md:12-16`).
- **Planejado — produção:** `APP_STORAGE_R2_PUBLICO_BASE_URL` aponta para
  `https://media.emporiob2b.com.br`, servido diretamente pelo bucket público
  R2, sem `media-gateway` na VPS. `docs/storage-r2-handoff.md` descreve a
  credencial dedicada, prefixo `quarantine/`, policy somente `s3:GetObject` e
  CORS `GET`/`HEAD`; não há aplicação no R2, Cloudflare ou Dokploy.
- **Planejado — publicação/staging:** publicação por SHA completo e deploy
  manual no Dokploy, conforme contrato vigente. Não inclui migration via CI,
  Supabase, nem deploy automático; produção permanece fora do escopo
  (`docs/cicd.md:13-19,62-76,103-110,115-139`).
- **Existente — documentação CI/CD:** `docs/cicd.md` documenta contrato, mas
  não comprova runs, configuração de proteção de `main`, package GHCR de
  roles, permissões de leitura ou deploy. A publicação remota das imagens de
  aplicação está verificada (2026-11-13, bullet de imagens acima); a
  existência dos workflows Infra/Backend/Radar não equivale a consumo
  integrado do artefato de roles
  (`.github/workflows/publish-roles-bootstrap.yml:1-16`;
  `../Backend_Java/.github/workflows/backend-ci.yml:1-18`;
  `../Radar_Middleware_Python/.github/workflows/ci.yml:1-16`;
  `docs/cicd.md:8-14,91-110,207-213`).
- Dockerfiles de produção prontos e revisados nos 3 projetos principais
  (Back: temurin 25 + usuário não-root + healthcheck em 8081; Front: SSR
  node:22 porta 4000, build parametrizado por `BUILD_PROFILE`/`API_BASE_URL`/
  `IMAGE_BASE_URL`; Radar: python 3.12 slim porta 8000 sem portas
  publicadas).
- **Existente — imagens de staging no GHCR, multiarch verificado (2026-11-13):**
  o operador executou `docker buildx imagetools inspect` em máquina própria
  autenticada no GHCR (clone `Emporio_Mkt`) e colou a saída nesta sessão; o
  clone desta sessão (`Emporio_git`) não possui credencial GHCR. As três
  imagens têm manifest multiarch `linux/amd64` + `linux/arm64`:
  - `ghcr.io/emporiob2b/backend-java:10d03d7796b8a996c1580dcf56a3f95ea24c58dc`
    — index digest
    `sha256:222d33f7c5bd5c1ebf3314b8441d62e6f61b1891594ca09c3cda1351f3c3ead4`;
  - `ghcr.io/emporiob2b/radar-middleware:sha-00208110c84de630ae0ef6b432c3988bd41e0ed4`
    — index digest
    `sha256:340395eef841bd8c96b22dd2e02672c8d8af55cc761517f0ac2419f25e4f3478`;
    o index inclui ainda 2 attestation-manifests `unknown/unknown`
    (proveniência buildx — normal, não são plataformas executáveis);
  - `ghcr.io/emporiob2b/front-angular:32614c57fc8089e12de4406b51e485d5caf7c08a`
    — index digest
    `sha256:e140c9ff322d59d1e59610cdec5c3c93da18d38f4eea07c4dccc066c4b710d53`.
  As tags do Back (SHA completo) e do Radar (`sha-<SHA>`) coincidem com o
  formato dos workflows versionados
  (`../Backend_Java/.github/workflows/backend-ci.yml:115-116`;
  `../Radar_Middleware_Python/.github/workflows/ci.yml:59,81-83`), o que
  evidencia execução dos jobs de publicação; a auditoria dos runs no Actions
  em si não foi feita. O Front não tem workflow — publicação manual pelo
  operador. Essas referências são fato verificado, não configuração: valores
  reais de imagem vão somente no Dokploy. O gate "imagens ARM64 publicadas"
  está verificado. **Perfil staging do Front — verificado (2026-11-13):** o
  operador executou, em máquina autenticada no GHCR,
  `docker run --rm --entrypoint sh ghcr.io/emporiob2b/front-angular:32614c57fc8089e12de4406b51e485d5caf7c08a -c "grep -rl 'api-staging.emporiob2b.com.br' dist | head -3"`;
  o pull resolveu para o index digest
  `sha256:e140c9ff322d59d1e59610cdec5c3c93da18d38f4eea07c4dccc066c4b710d53`
  (o mesmo verificado acima) e o grep retornou
  `dist/Emporio_Front/browser/chunk-CbtmA7w5.js` e
  `dist/Emporio_Front/server/chunk-KNXTD5V5.mjs`: a URL
  `https://api-staging.emporiob2b.com.br` está compilada nos bundles browser e
  SSR da imagem publicada. Na fonte do repo dono, `environment.ts` e
  `environment.staging.ts` diferem apenas no rótulo `environment`
  ('production' vs 'staging') e leem os mesmos defines
  `__API_BASE_URL__`/`__IMAGE_BASE_URL__`; `build-config.mjs` exige as duas
  URLs não vazias no perfil staging (defaultando às URLs aprovadas), e
  `allowedHosts` (`localhost` + `staging.emporiob2b.com.br`) está nas options
  do target de build, valendo para qualquer perfil
  (`../Front_Angular/src/environments/environment.ts:12-14`;
  `../Front_Angular/src/environments/environment.staging.ts:6-8`;
  `../Front_Angular/scripts/build-config.mjs:1-4,26-41`;
  `../Front_Angular/angular.json:36-38`). O rótulo é cosmético; a prova
  substantiva são as URLs de staging compiladas nos dois bundles. Com isso,
  todos os gates de imagem da TASK-INFRA-021 estão fechados: Back/Radar/Front
  multiarch `linux/amd64`+`linux/arm64` + perfil staging do Front verificados.
  Gates remanescentes da 021: confirmar File Paths UI `roles.sql`,
  `prometheus.template.yml` e `remote-write-token` (fontes sob `../files/`),
  recadastrar/atualizar YAML no Dokploy, confirmar os arquivos nos containers
  e rerodar deploy/smoke. Render local não comprova esses gates; token
  `metrics:write` ainda sem geração confirmada. Também: provider Loki no Dokploy (conta/stack Grafana Cloud existente,
  endpoints/IDs verificados — bullet próprio em "O que existe"), envs de
  métricas no painel (`PROMETHEUS_IMAGE`,
  `PROMETHEUS_REMOTE_WRITE_URL/USERNAME` — valores verificados no example),
  provisionamento de valores reais
  (R2 Back/Radar + objetos parquet do Radar, SMTP, senhas Postgres, JWT, token
  do túnel), primeiro login Access (rotas do túnel reportadas pelo operador e
  interceptação Access verificada em 2026-11-13; policy/IdP não auditados),
  connector ligado no deploy e o deploy/smoke em si.
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
- **Existente — workflows:** há publisher de roles em Infra e workflows CI/publicação
  no Backend e no Radar. A publicação remota das imagens de aplicação está
  verificada (2026-11-13, `imagetools inspect`); os runs no Actions não foram
  auditados e o publisher de roles segue sem execução comprovada. O Front
  segue sem workflow (imagem publicada manualmente). Essa existência não
  significa que o CI completo dos repositórios esteja operacional.

## Fatos dos serviços que afetam a infra

- Back serve HTTP puro em 8080 com `forward-headers-strategy: framework`;
  actuator em 8081; profile `container` exige 7 envs sem default, incluindo
  `MANAGEMENT_SERVER_ADDRESS`; profile
  `prod` exige `APP_PASSWORD_RESET_BASE_URL`.
- Contrato de métricas do Backend verificado no código-fonte do irmão e no
  scrape dev: HTTP **RED curado** (`http_server_requests_total` +
  `http_server_duration_seconds`, labels `route_template,method,status_class,outcome`)
  existe, enquanto o binder cru `http_server_requests_seconds` e as famílias
  `disk_*`/`jvm_memory_*`/GC pause/`jvm.info` continuam excluídos; timers sem
  buckets/percentis; heap e Tomcat agregados sem labels; Hikari com pools
  finitos (`emporio-pool|emporio-test-pool|emporio-b2b-pool`) e
  `executor_rejections_total` por executor de email (detalhes com fontes em
  `servicos.md`, seção Backend_Java).
- Radar valida o endpoint R2 como `https://<account>.r2.cloudflarestorage.com`
  (S3 local é rejeitado) e o ViaCEP como `https://viacep.com.br/ws`; não tem
  autenticação de entrada; estado em SQLite reconstruível.
- Front compila `apiBaseUrl`/`imageBaseUrl` no bundle (produção atual:
  vazios). O SSR valida `Host` contra `allowedHosts` definido nas options do
  target de build — `localhost` + `staging.emporiob2b.com.br`, valendo para
  qualquer perfil (`../Front_Angular/angular.json:36-38`). O build staging usa
  `environment.staging.ts` e define as URLs aprovadas da API e mídia
  (`../Front_Angular/angular.json:78-85`,
  `../Front_Angular/scripts/build-config.mjs:1-4,26-34`). O Dockerfile aceita
  `BUILD_PROFILE`/`API_BASE_URL`/`IMAGE_BASE_URL` como build-args
  (`../Front_Angular/Dockerfile:17-19,33-35`). A imagem ARM64 publicada e o
  perfil staging do bundle estão verificados (2026-11-13, `imagetools inspect`
  + `grep` na imagem: URL `api-staging` nos bundles browser e SSR — evidência
  no bullet de imagens); o run/deploy segue não comprovado.
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
- Memória real do container (RSS) **não é observável** no Grafana local: a
  série `process_memory_rss_bytes` exige instrumentação
  `micrometer-jvm-extras` que o `Backend_Java` ainda não possui, e o filtro
  `MetricsConfiguration` rejeita nomes não inventariados. É pendência futura
  do repositório Java (dependência registrada), **não** decisão ou limitação
  de topologia da Infra; até lá os painéis de memória usam a heap agregada da
  JVM.
- Backlog futuro (não bloqueia o MVP de deploy): mTLS/gateway interno do
  Radar (TASK-080/006 no repo Back e TASK-006 no repo Radar),
  monitoramento/uptime, backup do Supabase, entrada do Hermes no stack,
  pin de imagem por sha no Dokploy. A integração de produção com Grafana Cloud
  Loki permanece planejada: o Dokploy configura o provider e instala
  `dokploy-vector`; nenhum Loki/Grafana entra no Compose da aplicação.
- **Relato do operador — logs de staging (2026-11-14, não verificado
   independentemente nesta sessão):** logs aparecem no Grafana Cloud. O operador
   reporta Label browser com labels indexados
   `dokploy_application`, `dokploy_environment`, `dokploy_organization`,
   `dokploy_project`, `dokploy_server`, `dokploy_test` e `service_name`;
   `service_name=unknown_service`, `dokploy_application=emporio-staging` e
   `dokploy_environment=production`. `dokploy_service` não é label indexado.
   O envelope externo é JSON com metadata e `message` contendo JSON interno.
   Provider/agente efetivos e tokens não foram verificados independentemente
   (`compose/docker-compose.staging.yml:24-28`,
   `../../docs/observability.md:161-216`).
 - **Existente — dashboard Loki de staging (artefato versionado; interação
   reportada pelo operador, não verificada independentemente):** fixa o filtro pelo
  label de aplicação, parseia envelope, filtra `dokploy_service` extraído,
  formata `message` e parseia JSON interno. Os seletores `service`, `level` e
  `statusClass` são estáticos; serviço inclui `api`, `front`, `radar`, `postgres`,
  `db-bootstrap`, `migrate`, `cloudflared` e `prometheus`; nível inclui
  ERROR/WARN/INFO/DEBUG e status inclui All/4xx/5xx. A consulta usa `log_level`
  para API/Front e `level` para Radar. O Front emite `log.level`; conforme
  comportamento documentado do parser JSON Loki, pontos em nomes de campos são
   sanitizados para `_`, então `log_level` é o nome esperado. **Relato do
   operador (2026-11-14):** testou no Cloud as consultas/snippets de API/Front e
   Radar; resultado não reproduzido independentemente nesta sessão.
    **Existente no JSON (versão 7):** não há data links. O painel Text/Code
    interpola os dropdowns `service`, `level` e `statusClass` nos snippets
    LogQL, incluindo um snippet para `requestId`, para cópia manual no Explore.
    Clicar em um ponto não gera nem copia uma query específica. Uma variável
    textbox `requestId` e painel
   de logs fazem parse do envelope e de `message`, filtrando o valor digitado
   contra `request_id` ou `correlation_id`. Backend `CorrelationIdFilter`
   registra `X-Request-Id` no MDC; `RestClientRadarHttpClient` propaga esse
   `request_id` como `X-Correlation-ID`; Radar aceita-o em
   `problem_details.correlation_id` e grava `correlation_id` no JSONL. O
   interceptor do browser Front gera um ID por request; `server.ts` SSR
   lê/gera ID para a requisição SSR. Não equiparar esse ID ao ID de uma chamada
   de API nem presumir que componham a mesma cadeia. O dashboard trata esses IDs como campos do corpo, não os configura
   como labels Loki. O Label browser reportado pelo operador não inclui IDs,
    mas o estado atual no Cloud não foi verificado independentemente. **Relato
    do operador (2026-11-14):** confirmou expansão/cópia dos snippets, busca por
    ID da cadeia API→Radar e ausência de navegação nos gráficos; esse resultado
     não foi reproduzido independentemente nesta sessão.
   (`docs/observability.md:187-216,246-253`;
   `compose/grafana/dashboards-staging/emporio-staging-logs.json:90-240,247-302`;
   `../Backend_Java/src/main/java/br/com/emporio/infrastructure/security/CorrelationIdFilter.java:21,36`;
   `../Backend_Java/src/main/java/br/com/emporio/infrastructure/radar/http/RestClientRadarHttpClient.java:412-416`;
   `../Radar_Middleware_Python/src/radar_middleware/api/problem_details.py:30-45`;
   `../Radar_Middleware_Python/src/radar_middleware/infrastructure/observability/logging_setup.py:135-146`;
   `../Front_Angular/src/app/core/http/correlation-id.interceptor.ts:4-15`;
   `../Front_Angular/src/server.ts:57-61`).
 - **Existente — métricas de staging, artefatos implementados; implantação não
    verificada:** o Compose de staging contém Prometheus com `remote_write` para
    Grafana Cloud, redes internas `metrics-net` (`10.254.30.0/24`) e
    `radar-metrics-net` (`10.254.31.0/24`), distintas do dev, management da API
    em `10.254.30.10`, Radar em `10.254.31.30:8082` e bridge
    `prometheus-egress`; o template de scrape é
    `compose/prometheus/prometheus.staging.yml`. O dashboard versionado atual
     contém 35 painéis/84 expressões nos jobs API e Radar. As 84 expressões
      passaram `promtool check rules`; Grafana 12 descartável aceitou esta versão
      por importação via API (HTTP 200). **Relato do operador (2026-11-14, não
      verificado independentemente):** importou/testou no Grafana Cloud o
      dashboard expandido, suas consultas e as séries disponíveis; não se afirma
      quais painéis/valores específicos passaram. Permanecem pendentes
      scrape/runtime local de staging e verificação independente da
      ingestão/configuração Cloud. API expõe heap
    JVM agregada (não RSS/container) e CPU do processo JVM; Radar expõe CPU,
    RSS e memória virtual do processo. Métricas cgroup/container não estão
    disponíveis e cAdvisor está fora do escopo. Backend Java não tem buckets
    de duração, portanto seus painéis usam média/máximo, não percentis; somente
    os histogramas do Radar permitem p50/p95. O escopo exclui Front, Postgres,
    cloudflared e host. RED e métricas de domínio podem depender de tráfego;
    `up` é scrape, readiness só é exposta pelo Radar. Fontes:
    `compose/grafana/dashboards-staging/emporio-staging-metrics.json:41-90,164-220,309-345,1157-1233,1279-1316,1440-1472,1650-1676`,
    `compose/prometheus/prometheus.staging.yml:14-44`,
    `../Radar_Middleware_Python/src/radar_middleware/infrastructure/observability/prometheus.py:72-165,174-187,240-248`,
    `../Backend_Java/src/main/java/br/com/emporio/infrastructure/config/MetricsConfiguration.java:114-127,284-298`,
    `../Backend_Java/src/main/java/br/com/emporio/infrastructure/observability/HttpMetricsFilter.java:45-47,97-106`,
      `docs/observability.md:224-243`. A validação de config/compose existente
      não prova deployment; deploy na VPS e verificação independente da
      ingestão/configuração Cloud seguem pendentes. Ressalva: os tetos de 2 CPU/12 GiB por
    stack não reservam folga se ambos os stacks estourarem simultaneamente
    (`compose/docker-compose.staging.yml:295-342,366-392`,
    `../../docs/staging-compose.md:51-80`).
- **Existente — contrato e artefatos de staging:** contrato, Compose
  `compose/docker-compose.staging.yml` (incluindo o Prometheus de métricas),
  template `compose/prometheus/prometheus.staging.yml`, env example e runbooks
  existem no repo; não foram carregados no Dokploy nem implantados. O teto
  aprovado por stack é 2 CPU/12 GiB (decisão do operador de 2026-11-13, divisão
  meio a meio entre staging e produção futura; substitui o teto inicial de
  1,5 CPU/3 GiB); os limites long-lived do Compose atual somam 1,75 CPU/
  3.375 GiB (incluindo o Prometheus), dentro do teto, e permanecem válidos para
  o primeiro deploy. Todos os gates de imagem da
  TASK-INFRA-021 estão verificados (2026-11-13): Back/Radar/Front multiarch
  `linux/amd64`+`linux/arm64` (`imagetools inspect` colado pelo operador) e
  perfil staging do Front (`grep` na imagem publicada; URL `api-staging` nos
  bundles browser e SSR — referências e evidência no bullet de imagens em
  "O que existe"). TASK-INFRA-021 continua bloqueada pela confirmação dos
  File Paths no Dokploy (`roles.sql`, `prometheus.template.yml`,
  `remote-write-token` sob `../files/`), recadastro/atualização do YAML,
  confirmação dos arquivos nos containers e rerun do deploy/smoke; render local
  não comprova implantação. Token sem geração confirmada. Também segue bloqueada pelo
  provider Loki no Dokploy (conta/stack Grafana Cloud existente, endpoints/IDs
  verificados), pelas envs de métricas no painel (`PROMETHEUS_IMAGE`,
  `PROMETHEUS_REMOTE_WRITE_URL/USERNAME` — valores verificados no example),
  pelo provisionamento de valores
  reais (R2 Back/Radar + objetos parquet do Radar, SMTP, senhas Postgres, JWT,
  token do túnel), pelo primeiro login Access e pelo deploy/smoke em si.
  **Existente — borda de staging (2026-11-13):** zona Active na Cloudflare,
  túnel `emporio-staging` criado no dashboard (Inactive esperado; connector
  desligado na VPS até o deploy), rotas `staging` → `http://front:4000` e
  `api-staging` → `http://api:8080` reportadas pelo operador; DNS dos dois
  hostnames na borda Cloudflare e interceptação Access (302 ao time domain
  `soft-salad-0948`) verificados por `dig`/`curl`; policy/IdP não auditados,
  primeiro login pendente; associação do Custom Domain R2 `media-staging` e
  asset do logo reportados como funcionais pelo operador, sem validação
  independente nesta sessão. Detalhes e evidência no bullet de artefatos TASK-INFRA-020
  em "O que existe" e em `vps_oracle.md`. PG17 e roles separadas, assim como
  URLs são o desenho aprovado; buckets e credenciais Back/Radar/SMTP seguem
  sem provisionamento independentemente confirmado nesta auditoria.
   O Dokploy está instalado. O operador mostrou logs de API/Front associados ao
   stack staging no Grafana Cloud, mas o deploy integral e o estado em runtime
   não foram auditados independentemente; MFA do painel foi adiado com exceção
   aceita (TASK-INFRA-022).
  Produção na mesma máquina continua futura e requer revisão explícita de
  recursos/isolamento (`docs/oracle-vps.md:12-20,83-91`;
  `tasks/passadas/20261112_TASK-INFRA-018-hardening-dokploy-excecao-mfa.md`;
  `.opencode/tasks/futuras/TASK-INFRA-019-contrato-staging.md:3-8`).
- Intenção de produto registrada apenas no rascunho aposentado da raiz
  (destruído em 2026-09-26): integração de **gateway de pagamento**
  (`PAYMENT_GATEWAY_BASE_URL/CLIENT_ID/CLIENT_SECRET/TOKEN/
  WEBHOOK_SECRET`). Nenhum repo irmão tem código do assunto; quando sair
  do papel, vira feature no Backend_Java e a Infra trata do webhook
  público e egress do gateway no compose de produção.
- Decisões de produto pendentes que afetam a borda: domínio `www` (redirect
  na CF), política de cache do bucket público `media`.
