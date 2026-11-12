# Índice do contexto compartilhado

Este arquivo é o ponto de entrada do contexto do Emporio B2B Infra. Ele
contém ponteiros estáveis, não histórico de execução.

## Sempre consultar

| Arquivo | Responde a |
|---|---|
| `objetivo.md` | propósito, responsabilidades e limites deste repositório |
| `arquitetura.md` | topologia alvo: redes, domínios, túnel, registry e cadeia CI/CD |
| `servicos.md` | imagens, portas, envs reais, healthchecks e restrições de cada serviço |
| `decisoes.md` | decisões arquiteturais aprovadas e suas justificativas |
| `estado_atual.md` | fotografia factual do que existe hoje |
| `vps_oracle.md` | estado factual e segurança da VPS OCI em São Paulo |
| `../../docs/staging-contract.md`, `../../docs/staging-compose.md` | contrato e operação do staging (artefatos no repo versus implantação) |

## Consultar conforme o escopo

| Escopo | Contextos |
|---|---|
| Escrever ou revisar compose | `arquitetura.md`, `servicos.md`, skill `compose-infra` |
| Observabilidade e logs | `arquitetura.md`, `servicos.md`, `decisoes.md`, `estado_atual.md`, `docs/observability.md`, skill `observability-logs` |
| Cloudflare, domínios, túnel, media/R2 | `arquitetura.md`, skill `cloudflare-edge` |
| CI/CD, imagens e GHCR | `arquitetura.md`, `../../docs/cicd.md` (contrato de publicação/staging), skill `cicd-ghcr` |
| Deploy, Dokploy e rollback | `decisoes.md`, skill `dokploy-deploy` |
| VPS OCI, hardening do host e ambientes compartilhados | `vps_oracle.md`, `arquitetura.md`, skill `dokploy-deploy` |
| Testes integrados e E2E | `estado_atual.md`, tasks em `../tasks/futuras/` |
| Bootstrap e smoke de roles PostgreSQL | `estado_atual.md`, `servicos.md`, `decisoes.md`, `docs/database-roles.md` |
| Justificativa histórica de decisão | arquivo específico em `../tasks/passadas/` |

## Regra de leitura

`tasks/passadas/` só deve ser consultado quando a justificativa histórica for
necessária (é versionado). `tasks/task_atual.md` e `tasks/futuras/` são
locais e ignorados pelo git — `futuras/` é o planejamento pessoal do
operador (decisão de 2026-09-26).

## Regra de atualização

Atualize somente o documento factual afetado quando topologia, serviços,
decisões ou artefatos de infra mudarem. Não acrescente entradas cronológicas
de bugs, testes, revisões ou conversas.
