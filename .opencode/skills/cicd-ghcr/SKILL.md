---
name: cicd-ghcr
description: Use when creating or reviewing GitHub Actions workflows for the Emporio B2B repositories; least-privilege permissions, SHA-pinned actions, test gates, multiarch GHCR publication, manual staging release contract and script-injection hygiene.
---

# CI/CD com GitHub Actions + GHCR

Cada repositório de aplicação tem o próprio workflow (detecção de mudança é
nativa: o workflow roda no repo que recebeu o push). A Infra possui o workflow
`publish-roles-bootstrap.yml`; `validate.yml` e `integration.yml` continuam
planejados. O contrato vigente fica em
`docs/cicd.md`: Actions testam PRs e publicam imagens multiarch em `main`, mas
**não fazem deploy**. Staging é atualizado manualmente pelo operador no painel
Dokploy, sem expor API/webhook. Produção está fora do contrato atual. Fontes:
guia oficial "Security hardening for GitHub Actions" e guia "Publishing Docker
images" (docker/login-action, metadata-action, build-push-action).

## Princípios

- **teste antes de imagem**: job `test` verde é pré-condição do `image`;
  jamais `if: always()` em etapa de publicação. O deploy de staging é manual,
  fora do workflow;
- **least privilege**: `permissions: contents: read` como default do
  workflow; `packages: write` somente no job `image`; `id-token: write`
  somente se attestation estiver ativa; nenhum `write-all`;
- **reprodutibilidade e compatibilidade de runtime**: runner
  `ubuntu-latest`; publicar `linux/amd64` e `linux/arm64` para suportar a VPS
  Oracle A1 ARM64 e clientes x86. A build multiarch não substitui smoke no
  runtime ARM64; imagens base/dependências também precisam oferecer ARM64.

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
- `CODEOWNERS` cobrindo `.github/workflows/` e revisão independente são
  requisitos quando houver pelo menos um segundo mantenedor com acesso de
  escrita. Até lá, o processo é branch → PR → CI verde → merge, mas a branch
  pode não ter proteção técnica (por exemplo, restrição de plano em repo
  privado); não tratar self-review como revisão independente nem afirmar que
  push direto esteja bloqueado. Habilitar proteção de branch e CODEOWNERS quando
  houver outro mantenedor e o plano/configuração permitir;
- secrets: um secret por valor (nunca blob JSON/YAML — quebra o redaction);
  valor derivado/gerado em runtime registrado com `::add-mask::`; o contrato
  atual de CI/publicação não usa segredos de deploy. Auditar logs de run de
  teste com entrada inválida para confirmar redaction.

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
  3. `docker/metadata-action` → tag `type=sha,format=long` (SHA completo);
     `latest` é dispensável e nunca seleciona staging;
  4. `docker/build-push-action` com `context: .`, `platforms:
     linux/amd64,linux/arm64`, `cache-from: type=gha`,
     `cache-to: type=gha,mode=max`,
     `push: true`;
     usar runner ARM64 nativo ou configurar QEMU/buildx para instruções `RUN`
     cross-platform; o staging ARM64 continua sendo gate de validação real;
  5. attestations/SBOM ficam para avaliação posterior; não habilitar sem
     validar a compatibilidade do pull privado do Dokploy e registrar a decisão.

Não criar job de deploy, `DOKPLOY_API_KEY` ou Compose ID como secrets de CI
para o contrato atual. Após a publicação, o operador seleciona manualmente as
tags SHA completas em `BACKEND_IMAGE`, `FRONT_IMAGE` e `RADAR_IMAGE` no Compose
de staging do Dokploy e valida o deploy conforme `docs/cicd.md`.

## Nomenclatura e tags

- imagens: `ghcr.io/emporiob2b/backend-java`,
  `ghcr.io/emporiob2b/front-angular`, `ghcr.io/emporiob2b/radar-middleware`
  (minúsculo, o GHCR normaliza);
- toda publicação em `main` gera `:<sha-completo>`; essa é a referência
  selecionada manualmente para staging. `:latest` é dispensável e nunca
  seleciona deploy. Conferir e registrar o digest do manifest antes do deploy;
- visibilidade dos pacotes: **privado**; acesso do Dokploy via PAT
  `read:packages` dedicado (não usar o token da CI para pull externo).

## Workflows do repo Infra

- `publish-roles-bootstrap.yml` (existente no repo; execução remota ainda não
  verificada): valida `database/bootstrap/roles.sql` em PostgreSQL 16/17,
  confere a extração do artefato e publica package GHCR privado somente após
  sucesso, em push para `main`; o job publicador tem `packages: write`;
- `validate.yml` (planejado): `docker compose config --quiet` em cada
  compose; `hadolint` em Dockerfiles que existirem aqui; `actionlint` em
  todos os workflows; `shellcheck` em `scripts/`;
- `integration.yml` (planejado; `workflow_dispatch` + cron noturno): sobe o
  compose dev/e2e com imagens do GHCR, roda a suíte de integração e publica
  relatório como artefato; não dispara em PR de fork com secrets R2 de teste;
  informativo até estabilizar (não bloqueia deploy);
- suíte de integração não usa segredo de produção.

## Verificação de workflow novo

1. `actionlint` exit 0;
2. PR de teste: job `test` roda, `image` não roda; nenhum job de deploy existe;
3. merge em `main` (ou validação autorizada): imagem privada visível no GHCR
   com tag SHA completa e manifest multiarch;
4. teste de falha: gate `test` quebrado de propósito em branch → nenhuma
   imagem publicada;
5. revisão de logs: nenhum segredo (redaction confirmado);
6. staging: deploy manual pelo operador com referências conferidas, healthchecks
   e smoke ARM64; essa operação não é executada por GitHub Actions.
