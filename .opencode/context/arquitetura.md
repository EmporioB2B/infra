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

**Existente — dev:** mesma topologia de redes da produção planejada, com
emuladores no lugar dos serviços externos e sem cloudflared. Implementado em
`compose/docker-compose.dev.yml`, com healthchecks, `scripts/smoke.sh`,
isolamento da `radar-net` e `media-gateway` local para fotos públicas.
Detalhes de portas/publicação em `docs/networks.md`:

```text
services:
  postgres   postgres:16-alpine (db emporio)          127.0.0.1:5432
  backend    build ../Backend_Java (dev,container)    127.0.0.1:8080/8081
  radar      build ../Radar_Middleware_Python         SEM portas;
             env_file local do Radar (R2 de teste)
  rustfs     emula R2 do Back (quarentena/privado/    127.0.0.1:9000/9001
              público de fotos) + rustfs-init
  media-gateway  nginx para fotos públicas              127.0.0.1:9002 → :80
                (default externo 9002; MEDIA_GATEWAY_PORT é opcional)
  mailpit    SMTP com STARTTLS+auth; UI               127.0.0.1:8025
  front-dev  Dockerfile-dev (ng serve + proxy)        127.0.0.1:4200
  front-prod profile "prodlike": imagem SSR de        127.0.0.1:4000
              produção — [PLANEJADO], ainda não existe no compose
             (bloqueado pela TASK-INFRA-002; ver docs/networks.md)

networks:
  default    front-dev ↔ backend ↔ emuladores (postgres, rustfs, media-gateway,
             mailpit)
  radar-net  internal: exclusivamente backend ↔ radar
  egress     radar → R2 de teste / ViaCEP

volumes:
  pgdata, rustfs-data, radar_state (named); bind-mount somente-leitura
  de certs/dev para backend e mailpit (material TLS efêmero de dev,
  ignorado pelo git)
```

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
  `compose/docker-compose.dev.yml:266-291`,
  `compose/media-gateway.nginx.conf:16-37`,
  `env/.env.dev.example:59-65`).
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
