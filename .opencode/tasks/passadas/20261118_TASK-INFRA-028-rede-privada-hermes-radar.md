# TASK-INFRA-028 — Rede privada de integração Hermes↔Radar (dev/staging)

**Status:** promovida — artefatos Infra preparados e validados em dev.
**Data:** 2026-11-18
**Tipo:** Compose, isolamento de rede e documentação
**Repo alvo:** Infra

## Resultado

A Infra define uma rede Docker bridge `internal: true` distinta por ambiente:

- dev: `emporio-dev_hermes-radar-net`;
- staging: `emporio-staging_hermes-radar-net`.

Os dois arquivos Compose declaram o Radar na nova rede; ele permanece também na
`radar-net` existente para API↔Radar. API/Backend não participa da rede nova.
Nenhum serviço Hermes foi adicionado ao Compose da Infra; Hermes deve conectar seu
Compose à rede pelo nome estável, sob governança do repositório dono. Não houve
alteração em repositório irmão.

O smoke agora verifica que a rede dev é interna, contém Radar e somente serviços
Compose autorizados (`radar`, `app`, `worker`), e que a porta 8000 do Radar não
está publicada. A allowlist do checker de métricas foi alinhada às labels
limitadas `delivery_status` e `execution_status` já emitidas pelo Radar.

HTTP sem TLS/autenticação permanece uma exceção exclusivamente para dev/staging;
não é decisão de produção. Callback Radar→Hermes permanece futuro, condicionado
à implementação Hermes RDR-02.

## Arquivos alterados

- `compose/docker-compose.dev.yml`
- `compose/docker-compose.staging.yml`
- `scripts/smoke.sh`
- `scripts/check-metrics-cardinality.py`
- `docs/networks.md`
- `docs/staging-compose.md`
- `.opencode/context/arquitetura.md`
- `.opencode/context/decisoes.md`
- `.opencode/context/estado_atual.md`
- `.opencode/context/servicos.md`

## Evidências

Validação estática com os examples, sem imprimir configuração resolvida:

```text
docker compose --env-file env/.env.dev.example \
  -f compose/docker-compose.dev.yml config --quiet
exit 0

docker compose --env-file env/.env.staging.example \
  -f compose/docker-compose.staging.yml config --quiet
exit 0

bash -n scripts/smoke.sh
exit 0

git diff --check
exit 0
```

Dev local:

- `scripts/up-dev.sh --no-build` concluiu com exit 0; jobs one-shot terminaram
  com exit 0 e serviços long-lived ficaram healthy. O preflight identificou o
  checkout Backend `dev/negocios`; como foi usado `--no-build`, isso não prova a
  origem das imagens locais reutilizadas.
- `docker network inspect emporio-dev_hermes-radar-net` reportou
  `internal=true` e somente `emporio-dev-radar-1` conectado. Hermes ainda não
  anexou seu Compose.
- Probe temporária na rede privada para `http://radar:8000/health/live` retornou
  HTTP 200; o container de probe foi removido ao terminar.
- `scripts/smoke.sh` terminou com exit 0. Verificou Radar healthy, 8000/8082 sem
  publicação, redes existentes preservadas, nova rede interna com membership
  permitido, isolamento, métricas/cardinalidade, portas locais, observabilidade
  e demais checks do stack. O `SKIP` de HTTP RED sem tráfego `/api` foi esperado.
- O primeiro smoke nesta execução falhou por labels Radar ainda ausentes na
  allowlist e um timeout transitório do Front. A allowlist foi corrigida; o
  `curl` seguinte retornou 200 e os smokes completos posteriores passaram.
- ShellCheck via container passou em `scripts/smoke.sh`. A varredura de todos os
  scripts também encontrou SC2016 preexistente em
  `scripts/seed-admin-staging.sh`, que não foi alterado. `promtool check config`,
  `scripts/check-grafana-provisioning.sh` e `scripts/metrics-resilience.sh`
  passaram.

## Limitações e próximos passos

- Os dois `docker compose config --quiet` validam os artefatos, não a
  implantação staging.
- Não houve deploy, acesso à VPS ou consulta ao Dokploy. A capacidade de dois
  stacks Dokploy compartilharem a rede externa segue pendente de validação
  operacional autorizada.
- Hermes não foi conectado em runtime nesta task. O alias `hermes:3000`, o
  consumo do endpoint pelo worker e o callback não foram validados com o Hermes
  na rede. O repositório Hermes deve declarar a rede como externa e anexar os
  serviços necessários.
- O callback funcional aguarda RDR-02 e contrato próprio de limites/timeouts;
  esta task não implementa nem smoke-testa o callback.
- A integração real Hermes→Radar e o smoke manual acordado dependem do adapter
  Hermes e da anexação do Compose Hermes.
- O `context-revisor` auditou/corrigiu os contextos. O diff final dos contextos
  foi revisto; `git diff --check` passou.

## Próximas ações

1. O responsável do Hermes conecta `worker` e `app` à rede externa conforme o
   contrato e implementa o adapter/endpoint sob governança do repo Hermes.
2. O operador valida, com autorização específica, a rede compartilhada entre
   stacks no Dokploy staging.
3. Após RDR-02, executar smoke manual de callback com dados sintéticos.

Nenhuma operação de produção ou Git mutável foi executada.
