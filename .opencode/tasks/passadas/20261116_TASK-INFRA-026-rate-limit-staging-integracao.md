# TASK-INFRA-026 — Integração do rate limit e trusted proxy no staging

**Status:** promovida  
**Data:** 2026-11-16  
**Tipo:** implementação (integração de Compose, ambiente e borda)  
**Repo alvo:** Infra; dependência de imagem publicada pelo `Backend_Java_Cliente`

## Resultado

O Compose de staging passou a usar `staging,container` no Backend e a injetar
as variáveis do rate limit local de login. A topologia do Tunnel foi separada:

```text
apps:         front ↔ api
tunnel-front: cloudflared ↔ front
tunnel-api:   cloudflared ↔ api
```

Subnets e IPs configurados:

```text
tunnel-api:   10.254.32.0/24
cloudflared:  10.254.32.10
api:          10.254.32.20

tunnel-front: 10.254.33.0/24
cloudflared:  10.254.33.10
front:        10.254.33.20
```

O Backend recebe:

```text
APP_AUTH_TRUSTED_PROXIES=10.254.32.10/32
APP_AUTH_LOGIN_RATE_LIMIT_WINDOW=1m
APP_AUTH_LOGIN_RATE_LIMIT_MAX_IP=10
APP_AUTH_LOGIN_RATE_LIMIT_MAX_IDENTITY=5
APP_AUTH_LOGIN_RATE_LIMIT_MAX_KEYS=20000
```

`APP_AUTH_RATE_LIMIT_KEY` permanece somente no Dokploy/Secrets Provider.

## Arquivos alterados

- `compose/docker-compose.staging.yml`
- `env/.env.staging.example`
- `docs/staging-compose.md`
- `.opencode/context/arquitetura.md`
- `.opencode/context/decisoes.md`
- `.opencode/context/estado_atual.md`
- `.opencode/context/objetivo.md`
- `.opencode/context/servicos.md`
- `.opencode/context/vps_oracle.md`

## Evidências

Validações executadas no checkout:

```text
docker compose --env-file env/.env.staging.example \
  -f compose/docker-compose.staging.yml config --quiet
exit 0

git diff --check
exit 0
```

Validações runtime reportadas pelo operador na VPS:

- todos os serviços do staging ficaram `healthy`;
- `tunnel-api` conteve somente:
  - `cloudflared=10.254.32.10/24`;
  - `api=10.254.32.20/24`;
- `tunnel-front` conteve somente:
  - `cloudflared=10.254.33.10/24`;
  - `front=10.254.33.20/24`;
- `apps` conteve somente API/Front;
- `radar-net` conteve somente API/Radar;
- `database` conteve Postgres/API no momento observado; os jobs one-shot já
  haviam terminado;
- `/dev/tcp` não encontrou listeners no host em `8000`, `8080`, `8081`, `5432`
  ou `9090`;
- os hostnames públicos retornaram `302` do Cloudflare Access.

O `context-revisor` auditou o change set e corrigiu somente os contextos.
`git diff --check -- .opencode/context` passou com exit 0.

## Limitações

- As evidências runtime foram executadas e reportadas pelo operador; não houve
  auditoria independente da VPS nesta sessão.
- O `302` comprova interceptação do Cloudflare Access, mas não comprova uma
  requisição autenticada atravessando o Tunnel.
- O Service Token e o harness k6 pertencem à TASK-INFRA-027.
- O smoke `scripts/smoke.sh` existente é específico do dev; a validação desta
  task usou checks direcionados ao staging e não alterou o smoke dev.
- A imagem Backend e a configuração efetiva de segredos pertencem ao fluxo do
  repositório dono/Dokploy; nenhum segredo foi lido ou versionado.

## Próximo passo

Executar a TASK-INFRA-027 para criar o container de carga staging, Service
Token do Access, teste autenticado API→Radar e relatórios sanitizados.
