# Decisões arquiteturais da infraestrutura

> Documento vivo. Cada decisão foi aprovada pelo operador em 2026-09-26 e é
> referência até ser revista por task própria. A análise completa que originou
> estas decisões está em `../tasks/passadas/`.

## Deploy e borda

| Tema | Decisão | Justificativa |
|---|---|---|
| Plataforma de deploy | **Dokploy** self-hosted na VPS, stack do tipo Compose apontando para este repo (branch `main`) | Painel pronto para compose + envs + registry; operador já usa o termo "dockploy" para ele |
| Reverse proxy na VPS | **Sem Traefik** | O Back serve HTTP puro (TLS termina na borda Cloudflare); cloudflared roteia por hostname no Zero Trust. Menos uma peça, menos superfície |
| Entrada pública | **Cloudflare Tunnel** (`cloudflared` container com token) | Nenhuma porta HTTP publicada na VPS; dispensa gestão de certificado local |
| Domínios | `emporiob2b.com.br`→front, `api.emporiob2b.com.br`→api, `media.emporiob2b.com.br`→bucket público R2 (custom domain, não passa pela VPS) | Desenho do operador; same-site preserva cookie `SameSite=Lax` |
| Banco em produção | **Supabase externo**; nenhum postgres em container prod | Decisão do operador; dev emula com `postgres:16-alpine` |

## Imagens e CI/CD

| Tema | Decisão | Justificativa |
|---|---|---|
| Registry | **GHCR privado** (`ghcr.io/emporiob2b/*`); Dokploy autentica com PAT | Nativo do GitHub Actions (`GITHUB_TOKEN`), sem conta extra |
| Detecção de mudança | Workflow **por repositório de aplicação** (push em `main`) | Cada projeto já é um repo independente; paths-filter desnecessário |
| Tags | `:<sha>` + `:latest`; compose prod usa `:latest` com `pull_policy: always` | Simplicidade no redeploy; sha garante rastreio/rollback |
| Trigger de deploy | Job final do workflow chama a **API do Dokploy** (`DOKPLOY_API_KEY` em secret) | Redeploy puxa a imagem nova e recria só o container afetado |
| Gate de testes | Comandos canônicos de cada repo rodam **antes** do build de imagem | Falhou o teste, não publica imagem |

## Redes e isolamento

| Tema | Decisão | Justificativa |
|---|---|---|
| Back↔Radar | Rede Docker exclusiva `radar-net` (`internal: true`); Radar **sem portas publicadas** | Radar não tem auth serviço-a-serviço ainda (mTLS é task futura); isolamento estrutural reduz a zona de ataque |
| Egress | Rede `egress` para saída externa (R2, ViaCEP, Supabase, SMTP) | Separa tráfego interno de saída |
| Dev | Portas publicadas somente em `127.0.0.1` | Nada do stack local fica exposto na LAN |
| Management do Back | Porta 8081 nunca roteada pelo túnel | Actuator só para diagnóstico interno |

## Ambiente de dev/integração

| Tema | Decisão | Justificativa |
|---|---|---|
| Radar em dev | Usa o **bucket R2 de teste real** via `env_file` do `.env` local do repo Radar (não versionado) | `config.py` rejeita endpoint que não seja `https://<account>.r2.cloudflarestorage.com`; RustFS não é aceito pelo Radar |
| R2 do Back em dev | **RustFS** local (quarentena/privado/público), espelho do override `docker-compose.rustfs.yml` do Back, com desvio dev-only de leitura anônima no público (ver `servicos.md`; URL pública via app ainda bloqueada — TASK-INFRA-006) | Emula os 3 buckets, inclusive o **público de fotos** pedido pelo operador |
| SMTP em dev | **Mailpit** (UI em `127.0.0.1:8025`); precisa servir STARTTLS+auth — restrição de boot do Back com email habilitado (`servicos.md`); atendida com certificado dev + truststore (`scripts/gen-dev-certs.sh`) | Percorrer fluxos de email (confirmação, reset) sem provedor real |
| Front em dev | `Dockerfile-dev` (ng serve + proxy) como padrão; imagem SSR de produção em profile `prodlike` para E2E "como se fosse produção" | Operador quer testar todos os percursos manualmente; `prodlike` depende das build-args do Front (task de pré-requisito) |
| Nome do serviço api em dev | `backend` | `proxy.conf.json` do Front já aponta para `http://backend:8080`; evita mudança no repo Front |

## Escopo de testes

| Tema | Decisão | Justificativa |
|---|---|---|
| E2E agora | **Manual**, contra o compose dev "prod-like"; sem framework de browser nesta fase | Operador definiu E2E como percorrer os fluxos, não necessariamente automação |
| Automação | Suíte de integração API-level (Back↔Radar↔storage↔email) no repo Infra via `workflow_dispatch`/cron; Playwright vira task futura no repo Front | Nível 2 antes do nível 3 |

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
- **Tags de imagem**: o Production Hardening Guide do Dokploy recomenda
  evitar `:latest` em produção. Mantido no MVP `:latest` +
  `pull_policy: always` + tag `:sha` sempre publicada (rollback por
  repin); **direction of record**: migrar o compose prod para pin por sha
  via env `*_IMAGE_TAG` (refinamento da TASK-INFRA-003/004).
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
