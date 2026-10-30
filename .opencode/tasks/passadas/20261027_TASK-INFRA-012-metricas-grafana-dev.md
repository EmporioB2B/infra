# TASK-INFRA-012 — Dashboards e robustez das métricas locais

**Status:** promovida
**Data:** 2026-10-27
**Repo alvo:** `infra`

## Entrega

- retenção Prometheus local de 7 dias mantida no volume nomeado
  `prometheus-data`;
- WAL comprimido habilitado explicitamente no Compose dev;
- healthcheck do Prometheus usando `/-/ready`, com smoke validando também
  `/-/healthy`;
- provider de dashboards Grafana provisionado por arquivo;
- dashboard `Emporio B2B — Backend` provisionado automaticamente, com painéis
  de disponibilidade, JVM/processo/sistema, Hikari, executores, Radar,
  storage, email, notificações, catálogo e imagens;
- smoke atualizado para validar dashboard, readiness, cardinalidade de labels,
  ausência de famílias excluídas, logs, isolamento e ausência de Docker socket;
- `scripts/metrics-resilience.sh` criado para provar restart do Prometheus,
  preservação de volume/configuração/amostra histórica e recuperação do target
  `up` após indisponibilidade transitória do Backend;
- PromQL, LogQL, retenção, WAL e operação de resiliência documentados;
- contextos factuais atualizados e auditados pelo `context-revisor`.

## Arquivos principais

- `compose/docker-compose.dev.yml`
- `compose/prometheus/prometheus.yml`
- `compose/grafana/provisioning/dashboards/provider.yaml`
- `compose/grafana/dashboards/emporio-backend.json`
- `scripts/smoke.sh`
- `scripts/check-metrics-cardinality.py`
- `scripts/metrics-resilience.sh`
- `docs/observability.md`
- `README.md`
- `.opencode/context/arquitetura.md`
- `.opencode/context/servicos.md`
- `.opencode/context/estado_atual.md`

## Evidências

- `scripts/up-dev.sh --no-build`: exit 0; stack completo healthy;
- `scripts/smoke.sh`: exit 0; health/readiness, scrape, target, dashboard,
  cardinalidade, Loki, isolamento, portas e storage passaram;
- `scripts/metrics-resilience.sh`: exit 0; restart preservou volume,
  configuração e amostra histórica; Backend produziu `up=0` parado e `up=1`
  após recuperação;
- `docker compose --env-file env/.env.dev -f compose/docker-compose.dev.yml config --quiet`: exit 0;
- `promtool check config`: exit 0 na imagem `prom/prometheus:v3.5.0`;
- `shellcheck`: exit 0 via `koalaman/shellcheck:v0.10.0`;
- `python3 -m py_compile` do checker de cardinalidade: exit 0;
- validação JSON do dashboard: exit 0;
- `git diff --check`: exit 0;
- `git check-ignore -v`: confirmou `.env.dev`, chave TLS e truststore ignorados;
- dashboard consultável pela API local do Grafana e série Prometheus observada
  `jvm_classes_loaded_count_classes_total` conferida no scrape real.

## Auditoria e decisões

O `context-revisor` auditou os artefatos e editou somente os três contextos
factuais. Os achados médios sobre amostra histórica e nome da série foram
arbitrados em um único loop cirúrgico: o teste histórico foi adicionado e o
dashboard/contexto foram alinhados ao nome observado no Prometheus. A
validação de cardinalidade permanece deliberadamente como verificação de
fronteira; a allowlist finita de valores continua sendo responsabilidade do
Backend.

## Limitações preservadas

- sem produção, Grafana Cloud, remote write, alertas ou SLOs;
- painéis operacionais podem exibir `No data` quando não houver fluxo real
  correspondente no ambiente ocioso;
- nenhuma alteração foi feita no código do Backend ou em outro repositório;
- nenhum volume foi removido e nenhuma operação de produção foi executada.
