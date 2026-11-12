# TASK-INFRA-020 — Compose e env example do staging

**Status:** concluída em 2026-11-12
**Repo alvo:** Infra

## Resultado

- Criados `compose/docker-compose.staging.yml`, `env/.env.staging.example`,
  `docs/staging-compose.md` e `cloudflare/staging-ingress.md`; atualizados
  contextos e handoff Oracle. O Compose tem nome estável `emporio-staging` e
  usa somente `image:` (sem `build:`).
- Topologia: `apps` interna para Front/API/cloudflared; `radar-net` interna e
  compartilhada somente por API/Radar; `database` interna para Postgres/jobs/API;
  redes egress distintas e single-service para API, Radar e Tunnel. Nenhum
  serviço declara `ports:`. Postgres 17 tem volume nomeado persistente.
- Fluxo do DB codificado: `postgres → db-bootstrap → migrate → api`, com roles
  admin/migrator/runtime distintas. `db-bootstrap` exige File Mount do Dokploy em
  `/bootstrap/roles.sql` com o SQL canônico; esse File Mount não foi criado no
  painel.
- Configuração Back/Radar/SMTP/Tunnel usa env vars obrigatórias por serviço;
  `.env.staging.example` contém nomes/placeholders somente. Credenciais, DNS,
  Tunnel, Access, R2 e SMTP não foram provisionados.
- Imagens externas fixadas em manifests multiarch: PostgreSQL
  `17-alpine@sha256:e5d2edd28b1f8d40a0a6c0c9cdc545b19b56a0d5d88f94bc11a97d970d4700d0`
  e cloudflared `2026.10.7@sha256:4955524aeaa379e154023d5a027c250f7b35041a2e7e950cf13f144bc9b9c5ba`.
  Imagens Back/Front/Radar usam variáveis de referência imutável; o SHA real é
  placeholder porque não há publicação GHCR multiarch confirmada.
- Limites aprovados pelo operador por stack: 1,5 CPU e 3 GiB. Limites long-lived
  somam 1,5 CPU/2.875 GiB; jobs one-shot têm limites próprios. É teto inicial,
  não sizing validado por carga. DuckDB do Radar tem caminho lookup RFB sem
  `memory_limit`; pode causar OOM sob carga e deve ser verificado no smoke.
- Hostnames aprovados no TASK-INFRA-019 aparecem no handoff: Front/API atrás de
  Access e `media-staging.emporiob2b.com.br` como Custom Domain do bucket público
  R2, fora do Tunnel. Nenhuma alteração foi aplicada em Cloudflare/Dokploy/VPS.

## Evidência

- `docker compose --env-file env/.env.staging.example -f compose/docker-compose.staging.yml config --quiet` — exit 0.
- Verificação estrutural sobre `docker compose config --format json` — PASS:
  nenhum serviço publica portas; `radar-net` é interna e contém somente
  API/Radar; `database` é interna; Postgres/Radar/Front/Tunnel estão nas redes
  esperadas; nenhum image ref usa `:latest`; limites long-lived somam 1,50 CPU e
  2.875 GiB.
- Checker do example — PASS: todos os 34 nomes usados por `${VAR:?}` no Compose
  existem em `env/.env.staging.example`.
- `git diff --check` — exit 0; scan anti-segredos sem achados; `git check-ignore`
  confirmou `.env.staging.example` versionável e `.env.staging` real ignorado.
- Auditoria context-revisor concluiu que o Compose e a documentação distinguem
  artefatos no repo de implantação ainda inexistente. Achado MEDIUM Front foi
  arbitrado: `angular.json`/`scripts/build.mjs` definem staging, mas o Dockerfile
  atual ainda executa `build:production`; isso, imagens ARM64 e workflows dos
  repos donos são gates de deploy, não impedem validar o Compose estático.

## Limitações e gates posteriores

- Nenhuma imagem de app GHCR real/SHA ou publicação `linux/arm64` foi verificada;
  o Front ainda precisa selecionar o perfil staging no Dockerfile/build do repo
  dono. TASK-INFRA-003 e TASK-INFRA-002 continuam gates antes do deploy.
- Não foram executados `up`, healthchecks runtime, smoke nem testes de rede em
  containers staging; esse trabalho é da TASK-INFRA-021. `config --quiet` e o
  checker provaram sintaxe/topologia declarada, não serviço saudável.
- Dokploy não recebeu YAML nem File Mount. O operador deve configurar o File
  Mount e envs por serviço no painel, e provisionar recursos/segredos de staging
  antes de qualquer deploy.
- A disponibilidade dos hostnames, Access/Tunnel, R2 Custom Domain e política
  de exposição/cache de mídia não foram verificadas/aplicadas.
- O limite de storage/disco do volume PostgreSQL não é imposto pelo Compose;
  backup/retention e monitoramento do boot volume devem ser definidos antes de
  operar dados que precisem de retenção.
