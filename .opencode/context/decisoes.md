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
| Proteção do staging | **Cloudflare Access**, aplicado aos hostnames `staging.emporiob2b.com.br` e `api-staging.emporiob2b.com.br`; ainda não configurado | Hostnames aprovados como contrato; disponibilidade e configuração de Access/Tunnel/DNS ainda não verificadas. Gate de identidade sem publicar porta de autenticação na VPS |
| Staging + produção no mesmo host | **Decidido por restrição de recursos:** ambos na mesma VPS OCI; stacks/redes/volumes/segredos separados, sem dados/credenciais de produção no staging | Não constitui isolamento forte; comprometimento do host/Docker ou exaustão de recursos pode afetar os dois. Isolamento forte exigiria outra VM, indisponível agora |
| Administração do host | Manter usuário OCI `ubuntu`, SSH por chave, sem senha e sem login SSH direto de root; nenhum usuário Linux adicional para separar os ambientes | Usuários Linux não criam, por si, isolamento de stacks; o Dokploy usa Docker/Swarm rootful e rootless não é substituto direto |
| MFA do painel Dokploy | **Adiado temporariamente por decisão explícita do operador**; painel fica exclusivamente atrás de SSH forwarding até TASK-INFRA-022 | Exceção temporária aceita; não criar rota externa/Cloudflare para o painel antes de concluir MFA/passkey |
| Arquitetura da VM | Oracle Cloud `VM.Standard.A1.Flex`, ARM64 (`aarch64`); imagens GHCR multiarch `linux/amd64,linux/arm64` antes de deploy | A1 é ARM; publisher Infra de roles e workflow Back estão versionados, mas publicação remota ainda não verificada; demais workflows precisam atender ambas plataformas |
| Banco do staging | PostgreSQL 17 em container local; bootstrap administrativo, migrador e runtime separados; sem cópia de dados de produção | Isola staging do Supabase produtivo enquanto migrations evoluem; compatibilidade local PG17 tem prova isolada, mas Supabase gerenciado continua sem validação |
| R2 do staging | Recursos dedicados de staging para Back e Radar, com credenciais separadas por serviço/finalidade e da produção; Radar usa R2 real | Evita compartilhamento de dados e credenciais entre ambientes/serviços; nomes e policies reais ainda serão provisionados pelo operador |
| SMTP do staging | SMTP real de staging, com credenciais distintas da produção, STARTTLS+AUTH, remetente de teste e destinatários controlados | Permite validar email sem expor credenciais produtivas; provedor/conexão/remetente concretos ainda serão provisionados |
| Branch/release flow | **Planejado — staging:** PR para `main`; após gate verde, push em `main` publica imagem multiarch etiquetada pelo SHA completo; operador seleciona referências SHA e faz deploy manual no Dokploy. Actions não faz deploy. **Produção está fora do contrato atual.** | Evita drift e preserva rastreabilidade; publicação e deploy ainda não foram implementados/exercitados (`../../docs/cicd.md:10-19,23-35,62-76,115-129`) |
| Domínios | `emporiob2b.com.br`→front, `api.emporiob2b.com.br`→api, `media.emporiob2b.com.br`→bucket público R2 (custom domain, não passa pela VPS) | Desenho do operador; same-site preserva cookie `SameSite=Lax` |
| Mídia de staging | `media-staging.emporiob2b.com.br` como Custom Domain do bucket público R2 dedicado de staging; não passa pelo Tunnel | Hostname aprovado; associação do domínio R2 e cache/WAF ainda não configurados; não reutilizar bucket/domínio produtivo |
| Limites staging | Teto inicial por stack de 1,5 CPU e 3 GiB RAM; limites por serviço no Compose | Decisão do operador para reservar capacidade a produção futura na mesma VPS; ainda precisa ser validada no runtime ARM64 e revista se houver OOM/timeout |
| Banco em produção | **Supabase externo PostgreSQL 17**; nenhum postgres em container prod | Decisão do operador; dev integrado emula com `postgres:16-alpine` |

## Imagens e CI/CD

| Tema | Decisão | Justificativa |
|---|---|---|
| Registry | **GHCR privado** (`ghcr.io/emporiob2b/*`); Dokploy autentica com PAT | Nativo do GitHub Actions (`GITHUB_TOKEN`), sem conta extra |
| Triggers | **Planejado — aplicações:** workflows em PRs e push em `main`; PR testa sem publicar, push repete o gate e publica após sucesso. **Existente — Infra publisher:** `publish-roles-bootstrap.yml` filtra alterações do bootstrap/smoke/workflow, valida PRs e publica após sucesso em push `main`; execução remota não verificada | Cada projeto é independente; o publisher Infra valida o SQL canônico. Contratos/fontes: `../../docs/cicd.md:23-35,82-110`; `../../.github/workflows/publish-roles-bootstrap.yml:1-16,25-43,66-74` |
| Tags e seleção de versão | **Planejado — staging:** tag SHA completo é a referência operacional; `:latest` é dispensável e, se publicado, não seleciona deploy. Produção fora do contrato | Rastreabilidade; confirmar digest no preparo operacional. Contrato em `../../docs/cicd.md:62-76` |
| Trigger de deploy | **Planejado — staging:** deploy manual pelo operador no painel Dokploy; Actions não chama API/webhook. Nenhum deploy de produção definido | Evita expor/automatizar o canal administrativo (`../../docs/cicd.md:13-19,103-110,115-129`) |
| Gate e publicação | **Planejado — demais aplicações:** gate antes da publicação GHCR multiarch em push para `main`. **Existente — Infra roles:** workflow versionado valida PostgreSQL 16/17 e igualdade byte a byte do SQL extraído antes de publicar package multiarch; nenhuma execução, package remoto ou acesso do Backend foi verificado | Falha no gate bloqueia publicação; a existência do workflow não prova configuração/execução remota (`../../.github/workflows/publish-roles-bootstrap.yml:25-43,66-103`; `../../docs/cicd.md:82-110`) |
| Proteção de `main` e revisão | **Planejado — processo manual:** trabalhar em branch, abrir PR, aguardar CI verde e então fazer merge. **Existente — contrato documentado:** não há enforcement técnico de branch protection no estado atual descrito; push direto/merge sem checks continuam tecnicamente possíveis, sem afirmar configuração real no GitHub. CODEOWNERS, revisão independente e proteção de branch com checks são **planejados para o futuro**, quando houver segundo mantenedor com escrita e o plano/configuração permitir | O contrato diferencia processo da equipe de controles técnicos; não pressupor revisão independente nem bloqueio de push direto (`../../docs/cicd.md:23-35,91-100,175-179`; `../skills/cicd-ghcr/SKILL.md:42-49`) |

## Redes e isolamento

| Tema | Decisão | Justificativa |
|---|---|---|
| Back↔Radar | Rede Docker exclusiva `radar-net` (`internal: true`); Radar **sem portas publicadas** | Radar não tem auth serviço-a-serviço ainda (mTLS é task futura); isolamento estrutural reduz a zona de ataque |
| Egress | Bridges de egress separadas para serviços que precisam de saída externa; staging usa `api-egress`, `radar-egress`, `tunnel-egress` em single-service, com `apps` interna | A saída a R2/ViaCEP, SMTP e Cloudflare não adiciona Front/Tunnel à rede de outro serviço; `radar-net` permanece exclusivamente API↔Radar |
| Dev | Portas publicadas somente em `127.0.0.1` | Nada do stack local fica exposto na LAN |
| Management do Back | Porta 8081 nunca roteada pelo túnel | Actuator só para diagnóstico interno |
| Back↔Prometheus | Rede Docker dedicada `metrics-net` (`internal: true`), Backend em `10.254.20.10` e Prometheus em `10.254.20.20` | O scrape é uma comunicação técnica separada da API e da `radar-net`; não há publish de 8081 |
| Radar↔Prometheus no dev | **Existente — dev:** rede Docker exclusiva `radar-metrics-net` (`internal: true`), Radar em `10.254.21.30` e Prometheus em `10.254.21.20`; `metrics-net` continua somente Backend+Prometheus | Separar o listener 8082 preserva o teste negativo Radar→Backend:8081; o endpoint não tem publish |
| Banco e roles no dev integrado | **Existente — dev:** `postgres → db-bootstrap → migrate → backend`; bootstrap aplica o artefato canônico Infra em read-only e injeta senhas via ambiente; migration é one-shot `emporio_migrador`, runtime é `emporio_app` com `currentSchema` de domínio | Admin, runtime e migration têm credenciais separadas por função; o backend não recebe credenciais admin/migrador. `db-bootstrap` verifica formato (mínimo de 32 caracteres alfanuméricos) e distinção entre as três credenciais, sem imprimir valores (`compose/docker-compose.dev.yml:181-218`; `env/.env.dev.example:21-27`; `database/bootstrap/roles.sql:3-5`). |
| Coleta local de métricas | Prometheus sem porta publicada, target fixo `10.254.20.10:8081`, scrape a cada 15s e timeout de 5s | O bind do management do Backend ocorre somente na interface de métricas; o IP evita ambiguidade de DNS em container com múltiplas redes. `internal: true` não é firewall contra o host Docker |
| Limite de isolamento do host | O host Docker pode alcançar diretamente o IP de bridge `10.254.20.10`; não há promessa de firewall nesse caminho | O escopo protege a superfície publicada e o tráfego entre containers; bloquear o host contra a bridge exigiria uma decisão de firewall fora desta camada (`compose/docker-compose.dev.yml:495-522`; `scripts/smoke.sh:63-80`) |
| Logs da aplicação | **Existente — dev:** Backend em stdout/stderr ECS e containers coletados por Vector→Loki→Grafana local; **planejado — produção:** Dokploy Vector→Grafana Cloud Loki | Separar aplicação de armazenamento/consulta; não gravar arquivos no Backend nem montar Docker socket |

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

## Observabilidade e produção

- O Grafana Cloud Loki é o destino planejado de produção. O Dokploy não
  provisiona Loki: a função `Settings → Logs & Metrics` instala `dokploy-vector`
  no servidor e envia os logs ao provider configurado.
- **Contrato planejado — produção:** o provider deve receber somente logs já
  redigidos pela aplicação; `request_id`,
  `operation_id` e outros campos de alta cardinalidade não são labels Loki.
- A configuração do provider e seus tokens é operação do painel Dokploy e não
  faz parte deste change set local.

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
| Permissões do agente arquiteto | Padrão `allow` em bash/edição no dev; interdição só onde git não desfaz: mutações de git, destruição de dados (volume/prune/`down -v`/`DROP/TRUNCATE`), SSH/VPS, `sudo` | Operador 2026-09-26: "você deve poder executar basicamente qualquer comando docker e de criação dentro do repositório; no fim, teremos sempre o git". A ressalva dos volumes é evidência própria (down -v de 2026-09-26) |
| Rascunho da raiz | `docker-compose.yml` da raiz do workspace (nome `ifra-vps`) **aposentado** após a TASK-INFRA-001 | Envs não batem com o código real; healthcheck errado; mantido só até o dev compose validar |
