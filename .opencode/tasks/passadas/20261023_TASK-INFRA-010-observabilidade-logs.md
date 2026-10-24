# 20261023 — TASK-INFRA-010 — Observabilidade de logs dev/prod

**Status:** concluída (change set preparado; commit e produção cabem ao operador)
**Tipo:** implementação de artefatos de infra + atualização de governança
**Repo alvo:** `infra`
**Origem:** pedido do operador para disponibilizar Grafana no dev e preparar o
contrato de Grafana Cloud Loki via Dokploy em produção.

## Entrega

- Compose dev com `grafana/grafana:12.0.0`, `grafana/loki:3.5.1` e
  `timberio/vector:0.49.0-alpine`;
- Docker logging driver `fluentd` assíncrono para os serviços da aplicação,
  sem montagem de `/var/run/docker.sock`;
- Vector recebe Fluent em loopback, preserva o ECS JSON e envia ao Loki com
  buffer em disco;
- datasource Loki provisionado no Grafana;
- volumes `loki-data`, `vector-data` e `grafana-data`, com retenção local de
  Loki em 168h;
- Grafana publicado somente em `127.0.0.1:${GRAFANA_PORT:-3000}`;
- bootstrap e smoke atualizados;
- documentação, contexto e skill `observability-logs` adicionados;
- task futura registrada para a configuração do provider Grafana Cloud no
  Dokploy.

## Produção

O change set não configura produção. O contrato documentado é:

```text
containers -> Docker logs -> dokploy-vector -> provider Grafana Loki
```

O Dokploy instala o agente Vector ao configurar `Settings → Logs & Metrics`; ele
não instala Loki nem cria a conta Grafana Cloud. Endpoint, tenant/usuário e
token permanecem no painel/Secrets Provider. Nenhuma operação contra Dokploy,
VPS ou Grafana Cloud foi executada.

## Evidências frescas

| Gate | Comando/observação | Resultado |
|---|---|---|
| Compose com example | `docker compose --env-file env/.env.dev.example -f compose/docker-compose.dev.yml config --quiet` | exit 0 |
| Compose com env local | mesmo comando com override temporário de `GRAFANA_ADMIN_PASSWORD` no ambiente do processo | exit 0 |
| Loki | container oficial com `-verify-config=true` | config is valid |
| Vector | `vector validate --config-toml /etc/vector/vector.toml --skip-healthchecks` | component configuration validated |
| bootstrap | `scripts/up-dev.sh --no-build` com override temporário de senha no processo | todos os serviços healthy; Grafana/Loki/Vector healthy |
| smoke | `scripts/smoke.sh` com override temporário de senha no processo | todos os checks passaram, incluindo Backend → Vector → Loki |
| restart | restart do Backend + `up --wait` | Backend healthy e smoke posterior verde |
| Grafana datasource | GET autenticado no datasource UID `emporio-loki` | HTTP 200 |
| isolamento | host → `radar:8000` falha; `mailpit` → `radar:8000` falha; Backend alcança Radar | conforme esperado |
| rede | `docker network inspect emporio-dev_radar-net` | `Internal=true`, somente Backend e Radar |
| portas/socket | `docker compose ps` + inspect dos mounts | publicações somente loopback; sem Docker socket |
| shell | `bash -n`; ShellCheck em `koalaman/shellcheck:stable` | exit 0 |
| diff/higiene | `git diff --check`; `git check-ignore -v` | limpo; `.env.dev` e TLS ignorados |

## Limitação explícita e handoff

`env/.env.dev` real não foi lido nem editado. Antes do uso normal, o operador
deve adicionar uma senha local em `GRAFANA_ADMIN_PASSWORD` conforme
`env/.env.dev.example`; a validação usou apenas um override temporário de
processo. O volume local do Grafana criado durante a validação pode ser
alterado pela UI do Grafana antes de uso compartilhado.

Grafana Cloud, Dokploy, VPS, Cloudflare, R2 de produção e qualquer segredo real
permanecem fora desta execução.

## Auditoria de contexto

O `context-revisor` auditou e atualizou somente `.opencode/context/`.
O achado médio sobre o healthcheck do Vector foi arbitrado com uma correção
cirúrgica: o healthcheck passou a consultar a API local de liveness; a
validação estática de configuração continua separada e a ingestão é coberta
pelo smoke.

## Commit sugerido

```text
feat(infra): add local Grafana log observability
```
