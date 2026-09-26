# 20260926 — TASK-INFRA-000 — Análise de bootstrap e plano aprovado

**Status:** concluída (arquivo imutável)
**Tipo:** análise técnica + decisões do operador + bootstrap do repositório
**Origem:** pedido do operador: avaliação completa da infraestrutura e plano
para testes integrados e deploy via Dokploy/CI-CD com túnel Cloudflare.

## O que foi lido

- Contextos `.opencode/context/*` e `AGENTS.md` de Backend_Java,
  Front_Angular e Radar_Middleware_Python (mais AGENTS.md do Hermes);
- Dockerfiles, composes e `.env.example` dos três projetos;
- `application*.yml` do Back, `config.py` do Radar, `angular.json`,
  `src/server.ts` e `src/environments/*` do Front;
- `docker-compose.yml` da raiz do workspace (rascunho `ifra-vps` com
  cloudflared + traefik).

## Principais achados

1. A raiz do workspace não é repo git; os 4 projetos são repos
   independentes na org `EmporioB2B`; nenhum possui CI (`.github/`).
2. O rascunho `docker-compose.yml` da raiz não sobe: nomes de env divergem
   do código real dos três serviços (ex.: `DB_HOST`/`SECRET_JWT` vs
   `SPRING_DATASOURCE_URL`/`APP_JWT_SECRET`; `R2_ENDPOINT`/
   `RADAR_SQLITE_PATH` vs `CLOUDFLARE_*`/`SQLITE_PATH`; `API_BASE_URL`/
   `SSR_JWT_SECRET` não existem no Front) e o healthcheck da api aponta
   `wget :8080/actuator/health` quando o management real é `curl :8081`.
3. Bloqueadores de deploy no Front: `security.allowedHosts` compilado só
   com `localhost` (SSR rejeitaria o Host público do túnel) e
   `apiBaseUrl`/`imageBaseUrl` compilados vazios em produção (browser
   chamaria `/api` relativo na origem do front).
4. O Back serve HTTP puro com `forward-headers-strategy: framework`: TLS
   termina na borda Cloudflare; logo o Traefik não é necessário para HTTPS.
5. O Radar não tem autenticação serviço-a-serviço (mTLS é task futura nos
   repos Back/Radar) e valida o endpoint R2 como
   `https://<account>.r2.cloudflarestorage.com` — S3 local (RustFS) é
   rejeitado para o Radar; o Back, por outro lado, já emula R2 com RustFS.
6. Profile `container` do Back exige 6 envs sem default; profile `prod`
   exige `APP_PASSWORD_RESET_BASE_URL`.
7. `proxy.conf.json` do Front aponta para `http://backend:8080` — o serviço
   da api no compose dev deve se chamar `backend`.
8. Front e api em subdomínios do mesmo eTLD+1 são same-site: o cookie de
   refresh `SameSite=Lax` host-only funciona no desenho
   `api.emporiob2b.com.br`; CORS com credentials já é default do profile
   `prod`.

## Decisões do operador (Q&A de 2026-09-26)

- Dokploy confirmado como plataforma de deploy (stack Compose deste repo);
- Traefik removido do desenho (cloudflared roteia por hostname);
- GHCR privado + novo repo `EmporioB2B/Infra`;
- Radar em dev usa credenciais do bucket R2 de teste já presentes no `.env`
  local do projeto Radar (arquivo não lido por agentes, nunca versionado);
- E2E = percorrer os fluxos manualmente com o front "como se fosse
  produção"; RustFS no dev simula também o bucket público de fotos;
- automação de browser (Playwright) fica para depois.

## Resultado

Plano em 5 tasks registrado em `../futuras/` (TASK-INFRA-001 a 005);
contexto inicial criado (`objetivo`, `arquitetura`, `servicos`, `decisoes`,
`estado_atual`); skills canônicas criadas (`compose-infra`,
`cloudflare-edge`, `dokploy-deploy`, `cicd-ghcr`,
`verification-before-completion`); `.gitignore` do repo espelha a convenção
dos projetos de aplicação com `tasks/futuras/` versionado.
