---
name: cicd-ghcr
description: Use when creating or reviewing GitHub Actions workflows for the Emporio B2B repositories; least-privilege permissions, SHA-pinned actions, test gates, buildx with GHA cache, GHCR tagging, Dokploy deploy trigger and script-injection hygiene.
---

# CI/CD com GitHub Actions + GHCR

Cada repositório de aplicação tem o próprio workflow (detecção de mudança é
nativa: o workflow roda no repo que recebeu o push); o repo Infra tem
validação de artefatos e a suíte de integração. O padrão canônico fica em
`docs/cicd.md`. Fontes: guia oficial "Security hardening for GitHub
Actions", guia "Publishing Docker images" (docker/login-action,
metadata-action, build-push-action) e docs do Dokploy (Auto Deploy/API).

## Princípios

- **teste antes de imagem, imagem antes de deploy**: job `test` verde é
  pré-condição do `image`, que é pré-condição do `deploy`; jamais
  `if: always()` em etapa de publicação;
- **least privilege**: `permissions: contents: read` como default do
  workflow; `packages: write` somente no job `image`; `id-token: write`
  somente se attestation estiver ativa; nenhum `write-all`;
- **reprodutibilidade**: runner `ubuntu-latest`, plataforma
  `linux/amd64` (VPS x86) explícita; multi-arch só com necessidade real.

## Segurança de supply chain (regras do guia oficial)

- actions de terceiros pinadas por **commit SHA completo**, com o tag na
  mesma linha em comentário (`docker/login-action@<sha> # v3.x`) para o
  Dependabot conseguir atualizar;
- Dependabot habilitado para `github-actions` nos 4 repos (version updates
  + security updates);
- não usar `pull_request_target` nem `workflow_run` com checkout de código
  não confiável; PR de fork nunca recebe segredo de deploy;
- **script injection**: entrada não confiável (título de PR, nome de
  branch, mensagem de commit) nunca é interpolada direto em `run:` —
  passar por `env:` intermediário e usar `"$VAR"` no shell;
- `CODEOWNERS` cobrindo `.github/workflows/` (mudança de pipeline exige
  revisão);
- secrets: um secret por valor (nunca blob JSON/YAML — quebra o redaction);
  valor derivado/gerado em runtime registrado com `::add-mask::`; segredos
  de deploy em **environment** `production` (com required reviewer se o
  operador quiser gate manual); auditar logs de run de teste com entrada
  inválida para confirmar redaction.

## Estrutura do workflow de aplicação (canônica)

```yaml
name: ci
on:
  push: { branches: [main] }
  pull_request:
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
permissions: { contents: read }
```

- job `test` — gate canônico do repo (ver `context/servicos.md`):
  - Back: `actions/setup-java` (temurin 25, cache maven) +
    `./mvnw -B verify` (Testcontainers; requer daemon Docker do runner);
  - Front: `npm ci` + `npm run lint` + `npm run typecheck` +
    `npm run test` + `npm run build`;
  - Radar: `uv sync --locked` + `pytest` + `ruff check` +
    `ruff format --check`;
  - `timeout-minutes` explícito (Back ~30; demais ~15);
- job `image` — `if: github.event_name == 'push' && github.ref ==
  'refs/heads/main'`, `needs: test`, `permissions: { contents: read,
  packages: write }`:
  1. `docker/setup-buildx-action` (SHA-pinned);
  2. `docker/login-action` com `registry: ghcr.io`,
     `username: ${{ github.actor }}`, `password: ${{ secrets.GITHUB_TOKEN }}`;
  3. `docker/metadata-action` → tags `type=sha,format=long` +
     `type=raw,value=latest` (só em main);
  4. `docker/build-push-action` com `context: .`, `platforms:
     linux/amd64`, `cache-from: type=gha`, `cache-to: type=gha,mode=max`,
     `push: true`;
  5. opcional (recomendado): `actions/attest` (provenance/SBOM) — se o
     pull no Dokploy apresentar atrito com attestation, documentar
     `provenance: false` como decisão, não como descoberta silenciosa;
- job `deploy` — `needs: image`, `environment: production`, roda somente
  em `main`:
  - `curl -sf -X POST` na API/webhook do Dokploy com
    `x-api-key: ${{ secrets.DOKPLOY_API_KEY }}` e o id do stack
    (`secrets.DOKPLOY_COMPOSE_ID`);
  - corpo/URL sempre via `env:` (nunca interpolando contexto não confiável
    no script);
  - 1 retry em falha 5xx/timeout; falha final falha o job e notifica;
  - nunca imprimir a resposta com headers de autenticação em log.

## Nomenclatura e tags

- imagens: `ghcr.io/emporiob2b/backend-java`,
  `ghcr.io/emporiob2b/front-angular`, `ghcr.io/emporiob2b/radar-middleware`
  (minúsculo, o GHCR normaliza);
- toda publicação gera `:<sha>` (rastreio/rollback) + `:latest` (consumo do
  compose prod com `pull_policy: always`); direção de registro: migrar o
  compose para pin por sha via `*_IMAGE_TAG` (hardening do Dokploy
  recomenda evitar `:latest`);
- visibilidade dos pacotes: **privado**; acesso do Dokploy via PAT
  `read:packages` dedicado (não usar o token da CI para pull externo).

## Workflows do repo Infra

- `validate.yml` (push/PR): `docker compose config --quiet` em cada
  compose; `hadolint` em Dockerfiles que existirem aqui; `actionlint` em
  todos os workflows; `shellcheck` em `scripts/`;
- `integration.yml` (`workflow_dispatch` + cron noturno): sobe o compose
  dev/e2e com imagens do GHCR, roda a suíte de integração, publica
  relatório como artefato; **nunca** dispara em PR de fork (segredos R2 de
  teste); informativo até estabilizar (não bloqueia deploy);
- suíte de integração não usa segredo de produção.

## Verificação de workflow novo

1. `actionlint` exit 0;
2. PR de teste: job `test` roda, `image`/`deploy` não rodam;
3. merge em `main` (ou commit vazio de validação): imagem visível no GHCR
   com as duas tags; deploy disparado e smoke público verde
   (`dokploy-deploy`);
4. teste de falha: gate `test` quebrado de propósito em branch → nenhuma
   imagem publicada;
5. revisão de logs: nenhum segredo (redaction confirmado).
