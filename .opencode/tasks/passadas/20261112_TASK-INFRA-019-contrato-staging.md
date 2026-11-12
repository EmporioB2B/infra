# TASK-INFRA-019 — Contrato do staging: banco local, R2 e SMTP reais de teste

**Status:** concluída em 2026-11-12
**Repo alvo:** Infra; dependências de Front/CI rastreadas para os repos donos

## Resultado

- Hostnames aprovados: `staging.emporiob2b.com.br` (Front),
  `api-staging.emporiob2b.com.br` (API), ambos protegidos por Cloudflare Access;
  `media-staging.emporiob2b.com.br` é o Custom Domain do bucket público R2 de
  staging e não passa pelo Tunnel. Disponibilidade e configuração externas não
  foram verificadas nem aplicadas.
- PostgreSQL 17 local; fluxo bootstrap administrativo → `emporio_migrador` →
  `emporio_app`; sem copiar dados de produção.
- R2 dedicado por serviço/escopo no Back e no Radar; Radar permanece em R2 real.
  Nomes de buckets, credenciais e policies reais ainda não provisionados.
- SMTP real de staging com credenciais diferentes das produtivas, STARTTLS+AUTH,
  remetente de teste e destinatários controlados. Provedor e valores reais ficam
  por provisionar no Dokploy.
- Contrato de build do Front rastreado em TASK-INFRA-002:
  `apiBaseUrl=https://api-staging.emporiob2b.com.br`,
  `imageBaseUrl=https://media-staging.emporiob2b.com.br`,
  `allowedHosts` inclui `staging.emporiob2b.com.br`. O operador informa que a
  implementação no Front está em andamento; esta task não alterou o repo irmão.
- Requisito multiarch (`linux/amd64,linux/arm64`) dos repos Back/Front/Radar
  rastreado em TASK-INFRA-003. Workflows first-party não foram encontrados; a
  publicação continua gate antes do deploy.
- Inventário de nomes/placeholders e responsável/local por escopo em
  `env/.env.staging.example` e `docs/staging-contract.md`; valores reais nunca
  lidos, solicitados ou versionados.
- Contextos atualizados: `arquitetura.md`, `decisoes.md`, `servicos.md`,
  `estado_atual.md`, `vps_oracle.md`; `docs/oracle-vps.md` sincronizado.

## Evidência

- Auditoria somente leitura das fontes nos repos irmãos: `Backend_Java/Dockerfile`,
  profiles `application-container.yml`/`application-prod.yml`, migrations e
  contrato de roles; `Front_Angular/Dockerfile`, `angular.json`, ambientes e
  resolução de imagem; `Radar_Middleware_Python/Dockerfile` e `config.py`.
- Build de imagem local a partir de `../Backend_Java` e prova atual em PG17:
  `docker build -t emporio-infra-task019-backend:local ../Backend_Java && scripts/smoke-db-migration-runner.sh emporio-infra-task019-backend:local postgres:17-alpine`
  — exit 0. Smoke descartável em tmpfs aplicou V1–V10, levantou API como
  `emporio_app` healthy e confirmou negações de DDL, TRUNCATE e `SET ROLE`;
  não usou volume persistente nem credenciais externas.
- `git diff --check` — exit 0.
- Higiene env: `git check-ignore -v env/.env.staging.example` confirmou a exceção
  versionável `!.env.*.example`; `env/.env.staging` segue ignorado por `.env.*`.
- Auditoria do `context-revisor`: os contextos refletem que recursos/DNS ainda
  não estão provisionados; achados MEDIUM sobre Front e workflows foram
  arbitrados como gates de deploy, não bloqueadores do contrato. O Compose e
  qualquer deploy ficam fora da TASK-INFRA-019 e seguem na TASK-INFRA-020/021.

## Limitações e gates posteriores

- A prova PG17 cobre o runner/migrations locais e runtime, não Supabase gerenciado.
- Cloudflare DNS/Tunnel/Access, Custom Domain R2, buckets, credenciais e SMTP
  reais não foram criados/configurados.
- Front e workflows multiarch são responsabilidade dos repos donos; não houve
  alteração nesses repos. Só imagens multiarch publicadas e compatíveis podem
  ser usadas no primeiro deploy ARM64.
- Nenhum Compose foi criado e nenhum deploy foi executado.
