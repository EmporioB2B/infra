---
name: compose-infra
description: Use when writing or reviewing any docker-compose artifact (dev, e2e, prod) of the Emporio B2B Infra repository; enforces real env names, network isolation, healthchecks, volumes, hardening and validation with evidence.
---

# Compose de infraestrutura

Todo compose deste repositório materializa a topologia de
`context/arquitetura.md` com os fatos de `context/servicos.md`. Fontes das
práticas: documentação oficial Docker Compose (produção, múltiplos
arquivos, networking) e Production Hardening Guide do Dokploy.

## Estrutura de arquivos

- um compose por ambiente, sem `build:` misturado com imagem de registry no
  mesmo serviço:
  - `compose/docker-compose.dev.yml` — build local dos repos irmãos
    (`../../Backend_Java` etc.) + emuladores;
  - `compose/docker-compose.e2e.yml` — override do dev para suíte
    automatizada (padrão `-f dev -f e2e`, como o Back faz com
    `docker-compose.test.yml`);
  - `compose/docker-compose.prod.yml` — somente `image:` do GHCR, nunca
    `build:`;
- mudanças de um ambiente não vazam para outro: cada arquivo é completo no
  seu propósito ou declare o base explicitamente no comando/script;
- `name:` do projeto estável (`emporio-dev`, `emporio-prod`); nomes de
  rede/volume não dependem do diretório de checkout.

## Nomes e fatos — nunca de memória

- nomes de env, portas, healthchecks, usuários, paths de volume e comandos
  de cada serviço saem de `context/servicos.md`, que reflete o código-fonte
  dos repos irmãos; em caso de dúvida, confira a fonte
  (`application*.yml`, `config.py`, `angular.json`, Dockerfile) antes de
  escrever;
- o rascunho aposentado da raiz do workspace (`ifra-vps`, com `DB_HOST`,
  `SECRET_JWT`, `R2_ENDPOINT`, `API_BASE_URL`, `SSR_JWT_SECRET`, healthcheck
  `wget :8080`) **não é referência** em nada;
- no compose dev o serviço da api chama-se `backend` (o `proxy.conf.json`
  do Front aponta para `http://backend:8080`); em prod chama-se `api`;
- discovery por nome de serviço, nunca por IP (IP muda a cada recreate).

## Envs e segredos

- env obrigatória sem default usa `${VAR:?mensagem objetiva}` — falha cedo,
  nunca sobe meia-configuração;
- opcionais usam `${VAR:-default-seguro}`; default inseguro (senha, chave,
  host de produção) é proibido;
- segredos entram por `env_file` local ignorado (dev) ou pelo painel do
  Dokploy (prod); nunca inline no YAML; detalhes na skill `secrets-env`;
- `environment:` explícito tem precedência sobre `env_file` — use isso a
  favor (override do e2e sobre o dev);
- cada compose novo/alterado atualiza o `env/*.example` correspondente no
  mesmo change set.

## Saúde e ordenação

- todo serviço de longa duração tem `healthcheck` com o binário que existe
  na imagem (api: `curl` em `http://127.0.0.1:8081/actuator/health` — porta
  de management, não 8080; radar: `/health/ready`; front: fetch do Node;
  postgres: `pg_isready`);
- `interval`/`timeout`/`retries`/`start_period` calibrados: start_period
  cobre o bootstrap real (radar sincroniza SQLite do R2 no startup:
  90s+; api com Flyway: 30–40s);
- dependência de prontidão usa `depends_on` com
  `condition: service_healthy` (ou `service_completed_successfully` para
  jobs one-shot como `rustfs-init`);
- healthcheck "criado/running" não é aceite: o gate é **healthy**.

## Redes e isolamento

- padrão canônico (espelha o padrão `internal` + `public` da doc Docker):
  - `radar-net` — `internal: true`, membros exclusivamente api+radar; sem
    gateway externo; é a contenção do Radar enquanto não há auth
    serviço-a-serviço;
  - `egress` — bridge comum para saída externa (R2, ViaCEP em dev/prod;
    Supabase, SMTP em prod); um serviço em `internal` + `egress` alcança a
    internet só pela não-interna (comportamento documentado, esperado);
  - dev: `default` liga front↔backend↔emuladores; prod: `apps` liga
    cloudflared↔front↔api;
- o radar **não declara `ports:`** em nenhum compose, nem `expose`
  publicado, nem `network_mode: host/service:`;
- em dev, toda publicação de porta é prefixada `127.0.0.1:` (postgres, api
  8080/8081, rustfs 9000/9001, mailpit 8025, front 4200/4000); alternativa
  equivalente: `driver_opts: com.docker.network.bridge.host_binding_ipv4:
  "127.0.0.1"` na rede;
- em prod, nenhum serviço de aplicação publica porta; a única peça com
  conectividade é o cloudflared, e ela é **outbound** (7844);
- nunca montar `/var/run/docker.sock` em serviço nosso (o rascunho montava
  para o Traefik; sem Traefik não existe essa necessidade — socket é root
  no host);
- `network_mode: host` é proibido.

## Volumes

- named volumes para estado (postgres `pgdata`, rustfs `rustfs-data`, radar
  `radar_state`); bind mounts só para código em dev (hot-reload do
  `Dockerfile-dev`), nunca em prod;
- caminho de destino é o path real da imagem: radar em
  `/var/lib/radar-middleware/state` (a imagem cria `logs/` e `state/` com
  dono `radar:radar`; montar em path errado quebra permissões e o
  bootstrap);
- em prod, **nunca bind-mount de arquivo do repositório**: o AutoDeploy do
  Dokploy faz `git clone` a cada deploy e limpa o diretório; use named
  volume ou File Mounts (`../files`) do Dokploy; named volume é o que
  permite Volume Backups;
- volume do radar é descartável por decisão (SQLite reconstruível do R2);
  volume do postgres dev também; nenhum volume de prod é descartável.

## Hardening (prod)

- `security_opt: [no-new-privileges:true]` nos serviços de aplicação;
- `restart: unless-stopped` (dev e prod);
- logging `json-file` com `max-size`/`max-file` em todos os serviços
  (impede disco cheio; o daemon.json da VPS também deve ter default);
- imagens de terceiros pinadas por tag específica ou digest em prod
  (cloudflared, postgres, rustfs, mailpit): `:latest` só é aceitável para
  as nossas imagens com `pull_policy: always` e tagueamento por sha no CI
  (ver `cicd-ghcr`);
- recursos: quando a VPS tiver margem apertada, definir `mem_limit`/`cpus`
  por serviço antes de deixar o OOM-killer escolher;
- sem `privileged`, sem `cap_add`, sem dispositivos do host.

## Validação mínima (evidência, não intenção)

1. `docker compose -f <arquivo> config --quiet` exit 0 (sintaxe +
   resolução de envs);
2. `up -d` e todos os serviços **healthy** (`docker compose ps`);
3. `scripts/smoke.sh` exit 0;
4. testes negativos de isolamento: radar inalcançável do host (nenhuma
   porta) e de container fora da `radar-net` (`docker compose exec backend
   curl http://radar:8000/health/live` OK; de outro container/host falha);
   `docker network inspect` confirma `internal: true`;
5. dev: `docker compose ps` mostra tudo vinculado a `127.0.0.1`;
6. `git diff --check` e leitura do diff final (nenhum segredo).
