---
name: dokploy-deploy
description: Use when deploying, redeploying or rolling back the Emporio B2B production stack on the VPS via Dokploy; compose provider, env handling, GHCR credentials, webhook/API triggers, hardening checklist and rollback by sha tag.
---

# Deploy via Dokploy

Produção é um serviço **Docker Compose** do Dokploy apontando para este
repositório (`EmporioB2B/Infra`, branch `main`), arquivo
`compose/docker-compose.prod.yml`. Fontes: docs oficiais do Dokploy
(Docker Compose, Auto Deploy, guia Cloudflare Tunnels, Production
Hardening Guide).

## Modelo operacional

- o Dokploy é o único caminho de deploy; não subir/alterar container "na
  mão" por SSH fora de runbook aprovado pelo operador;
- o Dokploy instala o próprio Traefik (`dokploy-traefik`) no host — o nosso
  stack **não rota por ele**: o cloudflared do nosso compose aponta direto
  para `front:4000`/`api:8080` (decisão em `decisoes.md`); não criar
  Domains no painel para os serviços do stack, para não gerar rotas
  duplicadas/conflitantes;
- imagens vêm do GHCR privado (`ghcr.io/emporiob2b/*`); o Dokploy
  autentica com credencial de registry (PAT com escopo de leitura
  `read:packages`) configurada em Settings → Registry;
- deploy = `git clone/pull` do repo Infra + `docker compose pull` +
  `up -d` (comando gerenciado pelo painel; override de comando substitui o
  default inteiro, não acrescenta flag).

## Envs e segredos no Dokploy

- a aba Environment do compose escreve um `.env` **ao lado do
  docker-compose.yml** na VPS; variáveis NÃO são injetadas automaticamente
  nos containers: o compose referencia `${VAR}` (nosso padrão) ou declara
  `env_file`;
- segredos de produção vivem no painel (ou Secrets Provider externo quando
  houver vault); o repo contém apenas `env/.env.prod.example` com
  placeholders — checklist completo na skill `secrets-env`;
- token da API do Dokploy: criado no perfil, com **expiração** e um token
  por integração (CI ≠ script ≠ humano), permissão mínima; rotacionar em
  offboarding/suspeita.

## Volumes e arquivos

- usar **named volumes** (`radar_state`) — é o que permite Volume Backups
  do Dokploy e sobrevive ao clone do deploy;
- **nunca** bind-mount de arquivo do repositório: com AutoDeploy o Dokploy
  faz `git clone` a cada deploy e limpa o diretório do repo; mounts de
  arquivo do repo chegam vazios no próximo deploy. Se precisar de arquivo
  na VPS: File Mounts do painel (Advanced → Mounts) ou pasta `../files`;
- paths absolutos do host são limpos em deploy — proibidos;
- backup do volume do radar é opcional (estado reconstruível do R2); o
  que exige política de backup real é o Supabase (externo, fora do
  Dokploy).

## Gatilhos de deploy

- **push no repo Infra** (mudança de compose/docs): AutoDeploy do Dokploy
  (webhook GitHub nativo) — branch configurada precisa ser `main`, senão
  "Branch Not Match";
- **push em repo de aplicação** (nova imagem no GHCR): o workflow do repo
  dispara o redeploy do stack:
  - webhook URL do serviço compose (aba Deployments) chamado pelo job
    `deploy`, ou
  - API: `GET /api/project.all` (descobrir o id) e
    `POST /api/compose.deploy` com header `x-api-key` (para applications o
    endpoint é `/api/application.deploy`);
  - a chamada usa secrets do repo (`DOKPLOY_API_KEY`, id do stack); falha
    da API falha o job — deploy silencioso não existe;
- redeploy puxa `:latest` das nossas imagens (`pull_policy: always`) e
  recria só os containers cuja imagem/config mudou.

## Hardening da VPS (checklist do guia oficial, adaptado)

- host: Ubuntu/Debian LTS, `unattended-upgrades`, SSH só com chave (sem
  root, sem senha), Fail2Ban no sshd, usuário operador não-root no grupo
  `docker`;
- firewall: default deny incoming; liberar só SSH (80/443 **não** são
  necessários no nosso desenho — entrada é pelo túnel); portas publicadas
  pelo Docker ignoram UFW — como não publicamos nenhuma, a superfície é
  mínima; se um dia publicar algo, instalar `ufw-docker`;
- Docker engine (`/etc/docker/daemon.json`): `live-restore: true`,
  `userland-proxy: false`, `log-driver: json-file` com `max-size: 10m` /
  `max-file: 3`; nunca expor o socket Docker por TCP (2375/2376);
- Dokploy: 2FA/passkey em todo membro; roles least-privilege; porta 3000
  do painel **fechada para a internet** (acesso por túnel privado com
  Cloudflare Access ou VPN/Tailscale); tokens de API com expiração;
- compose: `security_opt: no-new-privileges:true` nos serviços de
  aplicação; imagens de terceiros pinadas por tag/digest;
- Isolated Deployments habilitado no stack (rede própria; containers não
  alcançam serviços de outros projetos por nome);
- notificações de falha de deploy configuradas (provider do painel).

## Pós-deploy obrigatório (smoke)

1. painel/`docker compose ps`: todos os serviços healthy;
2. `https://emporiob2b.com.br` renderiza (SSR aceita o Host);
3. `https://api.emporiob2b.com.br` responde em endpoint público do
   contrato (ex.: destaques) — sem expor actuator;
4. `https://media.emporiob2b.com.br/<objeto-de-teste>` serve pelo custom
   domain do R2;
5. logs dos containers recriados sem erro de configuração (env ausente
   falha cedo por `${VAR:?}` — container nem sobe);
6. registrar o resultado no runbook `docs/deploy-dokploy.md`.

## Rollback

- **imagem de aplicação**: toda imagem fica tagueada com o sha do commit no
  GHCR; rollback = repinar o sha anterior (tag/env no painel ou ajuste
  pontual do compose) + redeploy. Direction of record (ver `decisoes.md`):
  migrar de `:latest` para pin por sha via env `*_IMAGE_TAG`;
- **compose/infra**: revert do commit no repo Infra + redeploy (AutoDeploy
  ou webhook);
- **limites**: o schema do Back pertence ao Flyway — rollback de versão
  com migration incompatível exige plano próprio (não é só repinar
  imagem); o SQLite do Radar é reconstruível, rollback sem migração;
- rollback declarado sem execução real não conta como verificação
  (`verification-before-completion`).

## Proibições

- `down -v`, prune ou remoção de volume/rede/imagem em produção;
- expor porta de serviço no host (entrada é só pelo túnel); painel
  Dokploy público sem Access/VPN;
- commitar token do Dokploy, token do túnel, PAT do GHCR ou qualquer
  segredo;
- deploy sem os gates de teste do repo de origem verdes;
- alterar a produção a partir de máquina local sem passar pelo fluxo
  repo → GHCR → Dokploy (exceto runbook de emergência aprovado).
