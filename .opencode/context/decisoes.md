# Decisões arquiteturais da infraestrutura

> Documento vivo. As decisões registradas aqui são referência até serem
> revistas por task própria. A análise histórica disponível está em
> `../tasks/passadas/`.

## Deploy e borda

| Tema | Decisão | Justificativa |
|---|---|---|
| Plataforma de deploy | **Dokploy v0.31.0** self-hosted na VPS OCI; staging primeiro e produção depois na mesma máquina, em projetos/stacks distintos; Compose deste repo na branch `main` | Não há segunda máquina disponível; Dokploy atende Compose, envs e registry. Instalado em 2026-11-11 |
| Reverse proxy de aplicação | **Sem proxy próprio/sem Nginx Basic Auth**; o Traefik instalado pelo Dokploy não será o destino das rotas do Tunnel | TLS e proteção de staging ficam na Cloudflare; `cloudflared` aponta diretamente aos containers. O Dokploy mantém o Traefik interno dele |
| Entrada pública | **Cloudflare Tunnel** (`cloudflared` container com token) | Nenhuma porta HTTP publicada na VPS; dispensa gestão de certificado local |
| Proteção do staging | **Cloudflare Access**, aplicado aos hostnames `staging.emporiob2b.com.br` e `api-staging.emporiob2b.com.br`; configurado na borda, interceptação verificada em 2026-11-13 (HTTP 302 ao time domain `soft-salad-0948`); primeiro login real pendente | Hostnames aprovados como contrato; zona Active, túnel `emporio-staging` criado no dashboard (Inactive esperado até o connector ligar no deploy) e rotas `staging`→`http://front:4000` / `api-staging`→`http://api:8080` reportadas pelo operador; DNS na borda Cloudflare verificado por `dig`; policy/IdP não auditados. Gate de identidade sem publicar porta de autenticação na VPS |
| Staging + produção no mesmo host | **Decidido por restrição de recursos:** ambos na mesma VPS OCI; stacks/redes/volumes/segredos separados, sem dados/credenciais de produção no staging | Não constitui isolamento forte; comprometimento do host/Docker ou exaustão de recursos pode afetar os dois. Isolamento forte exigiria outra VM, indisponível agora |
| Administração do host | Manter usuário OCI `ubuntu`, SSH por chave, sem senha e sem login SSH direto de root; nenhum usuário Linux adicional para separar os ambientes | Usuários Linux não criam, por si, isolamento de stacks; o Dokploy usa Docker/Swarm rootful e rootless não é substituto direto |
| MFA do painel Dokploy | **Adiado temporariamente por decisão explícita do operador**; painel fica exclusivamente atrás de SSH forwarding até TASK-INFRA-022 | Exceção temporária aceita; não criar rota externa/Cloudflare para o painel antes de concluir MFA/passkey |
| Arquitetura da VM | Oracle Cloud `VM.Standard.A1.Flex`, ARM64 (`aarch64`); imagens GHCR multiarch `linux/amd64,linux/arm64` antes de deploy | A1 é ARM; publisher Infra de roles e workflows Back/Radar estão versionados declarando ambas as plataformas. Publicação das três imagens de staging verificada em 2026-11-13 (`imagetools inspect` colado pelo operador; tags/digests em `estado_atual.md`); runs não auditados; Front sem workflow, publicação manual; perfil staging do Front verificado em 2026-11-13 (`grep` na imagem: URL `api-staging` nos bundles browser e SSR; evidência em `estado_atual.md`) — gates de imagem da TASK-INFRA-021 fechados |
| Banco do staging | PostgreSQL 17 em container local; bootstrap administrativo, migrador e runtime separados; sem cópia de dados de produção | Isola staging do Supabase produtivo enquanto migrations evoluem; compatibilidade local PG17 tem prova isolada, mas Supabase gerenciado continua sem validação |
| R2 do staging | Recursos dedicados de staging para Back e Radar, com credenciais separadas por serviço/finalidade e da produção; Radar usa R2 real | Evita compartilhamento de dados e credenciais entre ambientes/serviços; nomes e policies reais ainda serão provisionados pelo operador |
| SMTP do staging | SMTP real de staging, com credenciais distintas da produção, STARTTLS+AUTH, remetente de teste e destinatários controlados | Permite validar email sem expor credenciais produtivas; provedor/conexão/remetente concretos ainda serão provisionados |
| Branch/release flow | **Planejado — staging:** PR para `main`; após gate verde, push em `main` publica imagem multiarch etiquetada pelo SHA completo; operador seleciona referências SHA e faz deploy manual no Dokploy. Actions não faz deploy. **Produção está fora do contrato atual.** | Evita drift e preserva rastreabilidade; publicação Back/Radar evidenciada por tags verificadas no formato dos workflows (runs não auditados), publisher Infra de roles sem execução comprovada, Front sem workflow (publicação manual verificada em 2026-11-13); deploy não exercitado (`../../docs/cicd.md:10-19,23-35,62-76,115-129`) |
| Domínios | `emporiob2b.com.br`→front, `api.emporiob2b.com.br`→api, `media.emporiob2b.com.br`→bucket público R2 (custom domain, não passa pela VPS) | Desenho do operador; same-site preserva cookie `SameSite=Lax` |
| Mídia de staging | `media-staging.emporiob2b.com.br` como Custom Domain do bucket público R2 dedicado de staging; não passa pelo Tunnel | Hostname aprovado. **Relato do operador, não verificado independentemente nesta sessão:** associação e acesso público ao logo funcionais; cache/WAF não verificados. Não reutilizar bucket/domínio produtivo |
| Limites por stack | **Teto de 2 CPU e 12 GiB RAM por stack** na VPS de 4 OCPUs/24 GB — divisão meio a meio entre staging e produção futura (decisão do operador de 2026-11-13; substitui o teto inicial de 1,5 CPU/3 GiB). Limites por serviço no Compose; o Compose de staging atual soma 1,75 CPU/3.375 GiB nos long-lived (incluindo o Prometheus de métricas), dentro do teto | Com tráfego inicial baixo, a divisão meio a meio é viável e permite testar tudo em staging, inclusive observabilidade completa. Limites são tetos, não reservas: host/Dokploy/Docker consomem ~1–2 GB (estimativa) e a soma dos tetos (24 GiB) não deixa folga de sistema se ambos os stacks estourarem simultaneamente — monitorar a folga real do host antes da produção entrar. Sizing não validado por carga; validar no runtime ARM64 e rever se houver OOM/timeout (`../../docs/staging-compose.md:106-118`) |
| Banco em produção | **Supabase externo PostgreSQL 17**; nenhum postgres em container prod | Decisão do operador; dev integrado emula com `postgres:16-alpine` |

## Imagens e CI/CD

| Tema | Decisão | Justificativa |
|---|---|---|
| Registry | **GHCR privado** (`ghcr.io/emporiob2b/*`); Dokploy autentica com PAT | Nativo do GitHub Actions (`GITHUB_TOKEN`), sem conta extra |
| Triggers | **Existente — Infra/Backend/Radar:** workflows versionados em PRs e push em `main`; PR testa sem publicar, push repete o gate e publica após sucesso. Publicação das imagens Back/Radar verificada em 2026-11-13 (tags no formato dos workflows; runs não auditados); publisher Infra de roles sem execução comprovada. O publisher Infra filtra alterações do bootstrap/smoke/workflow. **Front:** sem workflow; imagem publicada manualmente pelo operador, verificada em 2026-11-13 | Cada projeto é independente; o publisher Infra valida o SQL canônico. Contratos/fontes: `../../docs/cicd.md:23-35,82-110`; `../../.github/workflows/publish-roles-bootstrap.yml:1-16,25-43,66-74`; `../Backend_Java/.github/workflows/backend-ci.yml:3-16,78-87`; `../Radar_Middleware_Python/.github/workflows/ci.yml:3-16,48-56` |
| Tags e seleção de versão | **Planejado — staging:** tag SHA completo é a referência operacional; `:latest` é dispensável e, se publicado, não seleciona deploy. Produção fora do contrato | Rastreabilidade; index digests das três imagens de staging confirmados em 2026-11-13 (`imagetools inspect` colado pelo operador; referências em `estado_atual.md`), reconfirmar no preparo operacional. Contrato em `../../docs/cicd.md:62-76` |
| Trigger de deploy | **Planejado — staging:** deploy manual pelo operador no painel Dokploy; Actions não chama API/webhook. Nenhum deploy de produção definido | Evita expor/automatizar o canal administrativo (`../../docs/cicd.md:13-19,103-110,115-129`) |
| Gate e publicação | **Existente — Infra/Backend/Radar:** workflows versionados com gate antes da publicação GHCR multiarch (`linux/amd64,linux/arm64`) em push para `main`; o publisher Infra valida PostgreSQL 16/17 e igualdade byte a byte do SQL extraído antes de publicar. Imagens de aplicação Back/Radar/Front publicadas e verificadas em 2026-11-13 (`imagetools inspect`; runs não auditados); package de roles remoto e acesso do Backend seguem não verificados. **Front:** sem workflow; publicação manual e perfil staging do bundle verificados em 2026-11-13 (`grep` na imagem: URL `api-staging` nos bundles browser e SSR) | Falha no gate bloqueia publicação; as tags verificadas coincidem com o formato dos workflows Back/Radar, evidenciando execução dos jobs, mas os runs não foram auditados e a existência do workflow não prova configuração remota (`../../.github/workflows/publish-roles-bootstrap.yml:25-43,66-103`; `../Backend_Java/.github/workflows/backend-ci.yml:78-120`; `../Radar_Middleware_Python/.github/workflows/ci.yml:18-59,77-85`; `../../docs/cicd.md:82-110`) |
| Proteção de `main` e revisão | **Planejado — processo manual:** trabalhar em branch, abrir PR, aguardar CI verde e então fazer merge. **Existente — contrato documentado:** não há enforcement técnico de branch protection no estado atual descrito; push direto/merge sem checks continuam tecnicamente possíveis, sem afirmar configuração real no GitHub. CODEOWNERS, revisão independente e proteção de branch com checks são **planejados para o futuro**, quando houver segundo mantenedor com escrita e o plano/configuração permitir | O contrato diferencia processo da equipe de controles técnicos; não pressupor revisão independente nem bloqueio de push direto (`../../docs/cicd.md:23-35,91-100,175-179`; `../skills/cicd-ghcr/SKILL.md:42-49`) |

## Redes e isolamento

| Tema | Decisão | Justificativa |
|---|---|---|
| Back↔Radar | Rede Docker exclusiva `radar-net` (`internal: true`); Radar **sem portas publicadas** | Radar não tem auth serviço-a-serviço ainda (mTLS é task futura); isolamento estrutural reduz a zona de ataque |
| Egress | Bridges de egress separadas para serviços que precisam de saída externa; staging usa `api-egress`, `radar-egress`, `tunnel-egress` e `prometheus-egress` em single-service, com `apps` interna | A saída a R2/ViaCEP, SMTP, Cloudflare e remote_write não adiciona Front/Tunnel à rede de outro serviço; `radar-net` permanece exclusivamente API↔Radar |
| Dev | Portas publicadas somente em `127.0.0.1` | Nada do stack local fica exposto na LAN |
| Management do Back | Porta 8081 nunca roteada pelo túnel | Actuator só para diagnóstico interno |
| Back↔Prometheus | Rede Docker dedicada `metrics-net` (`internal: true`), Backend em `10.254.20.10` e Prometheus em `10.254.20.20` | O scrape é uma comunicação técnica separada da API e da `radar-net`; não há publish de 8081 |
| Radar↔Prometheus no dev | **Existente — dev:** rede Docker exclusiva `radar-metrics-net` (`internal: true`), Radar em `10.254.21.30` e Prometheus em `10.254.21.20`; `metrics-net` continua somente Backend+Prometheus | Separar o listener 8082 preserva o teste negativo Radar→Backend:8081; o endpoint não tem publish |
| Métricas de staging | **Existente — artefato, não implantado:** redes internas `metrics-net` (`10.254.30.0/24`: api `10.254.30.10` ↔ prometheus `10.254.30.20`) e `radar-metrics-net` (`10.254.31.0/24`: radar `10.254.31.30` ↔ prometheus `10.254.31.20`), distintas das do dev; `prometheus-egress` exclusiva para o remote_write; management da API com bind em `10.254.30.10`, não mais loopback | Mesma separação do dev, preservando o negativo Radar→Backend:8081; nenhum publish de 8081/8082/9090 e o Prometheus não é dependência de saúde de ninguém (`compose/docker-compose.staging.yml:121,154-155,206-214,322-327,366-384`) |
| Banco e roles no dev integrado | **Existente — dev:** `postgres → db-bootstrap → migrate → backend`; bootstrap aplica o artefato canônico Infra em read-only e injeta senhas via ambiente; migration é one-shot `emporio_migrador`, runtime é `emporio_app` com `currentSchema` de domínio | Admin, runtime e migration têm credenciais separadas por função; o backend não recebe credenciais admin/migrador. `db-bootstrap` verifica formato (mínimo de 32 caracteres alfanuméricos) e distinção entre as três credenciais, sem imprimir valores (`compose/docker-compose.dev.yml:181-218`; `env/.env.dev.example:21-27`; `database/bootstrap/roles.sql:3-5`). |
| Coleta local de métricas | Prometheus sem porta publicada, target fixo `10.254.20.10:8081`, scrape a cada 15s e timeout de 5s | O bind do management do Backend ocorre somente na interface de métricas; o IP evita ambiguidade de DNS em container com múltiplas redes. `internal: true` não é firewall contra o host Docker |
| Limite de isolamento do host | O host Docker pode alcançar diretamente o IP de bridge `10.254.20.10`; não há promessa de firewall nesse caminho | O escopo protege a superfície publicada e o tráfego entre containers; bloquear o host contra a bridge exigiria uma decisão de firewall fora desta camada (`compose/docker-compose.dev.yml:495-522`; `scripts/smoke.sh:63-80`) |
| Logs da aplicação | **Existente — dev:** Backend em stdout/stderr ECS e containers coletados por Vector→Loki→Grafana local; **planejado — integração staging/produção:** Dokploy Vector→Grafana Cloud Loki (nível host, sem mudar o Compose). **Relato do operador (2026-11-14, não verificado independentemente):** logs observados no Cloud e dashboard Loki testado (snippets LogQL, Request/Correlation ID e ausência de navegação) | Separar aplicação de armazenamento/consulta; não gravar arquivos no Backend nem montar Docker socket |

## Ambiente de dev/integração

| Tema | Decisão | Justificativa |
|---|---|---|
| Radar em dev | Usa o **bucket R2 de teste real** via `env_file` do `.env` local do repo Radar (não versionado) | `config.py` rejeita endpoint que não seja `https://<account>.r2.cloudflarestorage.com`; RustFS não é aceito pelo Radar |
| R2 do Back em dev | **RustFS** local (quarentena/privado/público), espelho do override `docker-compose.rustfs.yml` do Back, com desvio dev-only de leitura anônima no público; o `media-gateway` local resolve a URL pública sem expor os outros buckets (ver `servicos.md`) | Emula os 3 buckets, inclusive o **público de fotos** pedido pelo operador |
| SMTP em dev | **Mailpit** (UI em `127.0.0.1:8025`); precisa servir STARTTLS+auth — restrição de boot do Back com email habilitado (`servicos.md`); atendida com certificado dev + truststore (`scripts/gen-dev-certs.sh`) | Percorrer fluxos de email (confirmação, reset) sem provedor real |
| Front em dev | `Dockerfile-dev` (ng serve + proxy) como padrão; imagem SSR de produção em profile `prodlike` para E2E "como se fosse produção" | Operador quer testar todos os percursos manualmente; `prodlike` depende das build-args do Front (task de pré-requisito) |
| Nome do serviço api em dev | `backend` | `proxy.conf.json` do Front já aponta para `http://backend:8080`; evita mudança no repo Front |
| Observabilidade local | **Existente — dev:** Loki + Vector + Prometheus + Grafana no Compose dev; UI somente em loopback; volumes nomeados e retenção de 7 dias | Reproduzir consulta de logs e métricas sem credenciais externas ou socket Docker |
| Recuperação de volumes dev | **Existente — dev:** Compose usa explicitamente `emporio-dev_pgdata_v2` e `emporio-dev_radar_state_v2`, mantendo os volumes antigos intactos para rollback/investigação local | O volume antigo do Radar não tinha `cep_cidades` e o pgdata antigo tinha checksums Flyway incompatíveis; não é uma decisão de produção |

## Escopo de testes

| Tema | Decisão | Justificativa |
|---|---|---|
| E2E agora | **Manual**, contra o compose dev "prod-like"; sem framework de browser nesta fase | Operador definiu E2E como percorrer os fluxos, não necessariamente automação |
| Automação | Suíte de integração API-level (Back↔Radar↔storage↔email) no repo Infra via `workflow_dispatch`/cron; Playwright vira task futura no repo Front | Nível 2 antes do nível 3 |

## Observabilidade (staging e produção)

- O Grafana Cloud Loki é o destino de staging e produção; a conta/stack é
  existente (criada pelo operador em 2026-11-13). **Relato do operador
  (2026-11-14, não verificado independentemente nesta sessão):** logs de
  staging aparecem no Cloud; os labels reportados incluem
  `dokploy_application`, `dokploy_environment`, `dokploy_organization`,
  `dokploy_project`, `dokploy_server`, `dokploy_test` e `service_name`
  (`unknown_service`). A aplicação reportada é `emporio-staging`, o ambiente
  `production`, e `dokploy_service` é campo do envelope JSON, não label
  indexado. **Relato do operador (2026-11-14, não verificado
  independentemente):** o teste Cloud do dashboard Loki confirmou snippets,
  busca Request/Correlation ID API→Radar e ausência de navegação. Provider/
  agente efetivos não foram verificados independentemente. A integração de
  produção segue planejada. O Dokploy não
  provisiona Loki: `Settings → Logs & Metrics` instala `dokploy-vector` no
  servidor e envia os logs ao provider configurado
  (`../../docs/observability.md:187-216`;
  `../../compose/grafana/dashboards-staging/emporio-staging-logs.json:18,46,53`).
- **Existente — artefatos de métricas de staging (direção aprovada em
  2026-11-13; implantação/configuração não verificadas independentemente):**
  Prometheus com `remote_write` para Grafana Cloud **dentro do Compose de
  staging**, com redes internas `metrics-net` (`10.254.30.0/24`) e
  `radar-metrics-net` (`10.254.31.0/24`), distintas das do dev,
  `MANAGEMENT_SERVER_ADDRESS` da API em `10.254.30.10` (bind na `metrics-net`,
  não mais loopback), `METRICS_BIND_ADDRESS`/`METRICS_PORT` no Radar
  (`10.254.31.30:8082`) e bridge `prometheus-egress` exclusiva. Template sem
  segredos em `compose/prometheus/prometheus.staging.yml`; token de escrita em
  File Mount lido via `password_file`, nunca por shell. O Compose liga
  explicitamente `../files/prometheus.template.yml` e
  `../files/remote-write-token` aos destinos read-only, assim como
  `../files/roles.sql` para o bootstrap; cadastro no Dokploy sem referência
  `volumes:` não monta o arquivo. Os File Paths efetivos no painel e os arquivos
  em containers não estão confirmados.
  Validação local do artefato (`config --quiet`, entrypoint na imagem real +
  `promtool`) passou; deploy na VPS e scrape local de runtime não foram
  verificados independentemente. Existem dashboards Loki/Prometheus de staging
  em `compose/grafana/dashboards-staging/`
  (`docs/observability.md:180-238`). **Relato do operador (2026-11-14, não
  verificado independentemente):** importou/testou no Grafana Cloud o dashboard
  de métricas expandido (35 painéis/84 expressões), suas consultas e as séries
  disponíveis; não se afirma quais painéis/valores específicos passaram.
  Permanecem pendentes scrape/runtime local de staging e verificação
  independente da ingestão/configuração Cloud. As 84 expressões passaram
  `promtool check rules`; Grafana 12 descartável aceitou a importação via API
  (HTTP 200).
- **Existente — conta/stack Grafana Cloud (2026-11-13, operador):** slug
  `smallmarzipan1294`, região `prod-sa-east-1` (São Paulo), free tier; Access
  Policies `emporio-staging-logs` (`logs:write`) e `emporio-staging-metrics`
  (`metrics:write`) criadas, sem geração de tokens confirmada (a policy de
  metrics exibia 0 tokens na última tela vista); nenhum token foi
  visto/registrado. Endpoints públicos de ingestão verificados por `curl`
  (HTTP 401 sem auth): Loki `https://logs-prod-024.grafana.net` (tenant/user
  `1878826`) e remote_write
  `https://prometheus-prod-40-prod-sa-east-1.grafana.net/api/prom/push`
  (instance/user `3766316`). IDs são usuários de basic auth, não segredos; as
  URLs internas `*-local-nlb.internal.grafana.net` dos datasources da UI não
  servem para ingestão externa. `env/.env.staging.example:74-86` contém os
  valores verificados de `PROMETHEUS_REMOTE_WRITE_URL/USERNAME` e documenta o
  provider Loki (URL/user; token somente no painel); `docker compose config
  --quiet` com o example vigente exit 0.
- **Contrato de logs staging:** stdout dos containers →
  `json-file` com rotação (buffer local; driver proposital para o agente do
  Dokploy, não `fluentd` como no dev) → `dokploy-vector` no host → push HTTPS
  → Grafana Cloud Loki, sem mudar o Compose e sem porta inbound; métricas
  também push (`remote_write`). Estado/configuração efetivos do provider e do
  agente não foram auditados nesta sessão. Destino: URL Loki + tenant
  `1878826` + token `logs:write` no provider, URL remote_write + instance
  `3766316` nas envs do Compose, token `metrics:write` no File Mount
  `/etc/prometheus/remote-write-token`
  (`compose/docker-compose.staging.yml:24-28`,
  `../../docs/observability.md:161-185,192-197`).
- Ressalva registrada: os tetos de 2 CPU/12 GiB por stack são limites, não
  reservas — a soma (24 GiB) não deixa folga de sistema se ambos os stacks
  estourarem simultaneamente; monitorar a folga real do host antes da
  produção entrar (ver linha "Limites por stack").
- **Contrato planejado — produção:** o provider deve receber somente logs já
  redigidos pela aplicação; `request_id`,
  `operation_id` e outros campos de alta cardinalidade não são labels Loki.
- A configuração do provider e seus tokens é operação do painel Dokploy, não
  artefato deste repo.

## Refinamentos pós-pesquisa (2026-09-26, mesma sessão)

Decisões mantidas, com detalhamento vindo da documentação oficial (Docker,
Cloudflare, Dokploy, GitHub):

- **Traefik do Dokploy**: o Dokploy instala o próprio Traefik
  (`dokploy-traefik`) no host. O nosso stack **não rota por ele** — o
  cloudflared do nosso compose aponta direto para `front:4000`/`api:8080`
  (padrão "direct container access" documentado pelo próprio Dokploy). Não
  criar Domains no painel para os serviços do stack, evitando rota
  duplicada.
- **cloudflared pinado**: imagem do cloudflared com tag específica (não
  `:latest`) e `--no-autoupdate`; atualização é decisão de deploy.
- **Tags de imagem:** **planejado — staging:** a referência operacional é o
  SHA completo, com digest conferido antes do deploy; `:latest` é dispensável e
  nunca seleciona staging. Produção não está definida pelo contrato atual
  (`../../docs/cicd.md:62-76,149-150`).
- **AutoDeploy e arquivos do repo**: o Dokploy faz `git clone` a cada
  deploy e limpa o diretório — nenhum bind-mount de arquivo do repositório
  no compose prod; estado somente em named volumes (habilita Volume
  Backups) ou File Mounts do painel.
- **Skills de terceiros**: política definida — não instalar skills externas
  (skills.sh etc.); comportamentos úteis são reescritos nas skills
  canônicas com origem citada (ver `skills/README.md`).
- **Agentes**: ciclo enxuto com `arquiteto` (primary, implementa artefatos
  de infra) e `context-revisor` (subagent, audita e corrige somente
  `context/`); Git mutável é exclusivo do operador.

## Repositório

| Tema | Decisão | Justificativa |
|---|---|---|
| Casa da infra | Novo repo **`EmporioB2B/Infra`** (pasta `infra/` ao lado dos projetos) | A raiz do workspace não é repo; os 4 projetos são independentes |
| `.opencode` | Só `context/`, `skills/` e `tasks/` (+ `agents/` desde o refinamento) | Infra é governança, não app |
| `tasks/futuras/` | **Não versionado** — local, pessoal do operador (revogação de 2026-09-26 da exceção que o mantinha no git; convenção igual à dos repos de aplicação) | Decisão explícita do operador ao comitar; `tasks/passadas/` continua versionado como histórico/evidência imutável |
| Permissões do agente arquiteto | Padrão `allow` em bash/edição no dev; mutações de Git, destruição irreversível, SSH/VPS e `sudo` genérico interditados. Exceções somente via `sudo -n docker ps`, `docker stats --no-stream` e `docker logs --since ...` (read-only de observabilidade) | Operador 2026-09-26: Docker amplo em dev, mas operações não reversíveis seguem bloqueadas. Operador 2026-11-14 autorizou leitura limitada de logs e métricas da VPS; as permissões não autorizam ação em VPS/produção sem autorização explícita por ação. Docker group/socket continua equivalente a privilégio root |
| Rascunho da raiz | `docker-compose.yml` da raiz do workspace (nome `ifra-vps`) **aposentado** após a TASK-INFRA-001 | Envs não batem com o código real; healthcheck errado; mantido só até o dev compose validar |
