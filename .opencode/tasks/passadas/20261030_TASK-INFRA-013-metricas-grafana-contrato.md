# TASK-INFRA-013 — Alinhar métricas Grafana ao contrato vigente do Backend

**Status:** promovida
**Data:** 2026-10-30
**Repo alvo:** `infra`
**Tipo:** correção de drift de contrato (repositório irmão) + robustez de gate

## Contexto

A TASK-INFRA-012 promoveu o scrape Prometheus + dashboard, mas o Backend avançou
o contrato depois disso (`f5821cc` HTTP RED curado, `f19ff8d` heap/Tomcat
agregados). Levantamento pedido pelo operador ("quem decidiu não subir memória?")
confirmou: a exclusão de `jvm_memory.*` é decisão do `MeterFilter` do Backend, não
da Infra; e o Backend já expõe agora heap agregada + RED curado. Verificação no
scrape vivo da imagem atual (built 2026-10-30 15:30).

## Entrega (artefatos deste repo)

- **Dashboard** `compose/grafana/dashboards/emporio-backend.json` (v2):
  - painel de latência p95 substituído por **média + máx** (`rate(_sum)/rate(_count)`
    e `_max`) — o contrato não expõe `*_bucket`/percentis;
  - novas linhas/painéis: **heap JVM** (`jvm_heap_used_bytes`/`jvm_heap_max_bytes`),
    **HTTP RED** (`http_server_requests_total`, `http_server_duration_seconds_*`
    por `outcome`/`status_class`), **Tomcat** (threads/conexões agregados),
    **rejeições de executor**; painel de classes corrigido para a gauge
    `jvm_classes_loaded_classes`;
- **`scripts/check-metrics-cardinality.py`**: aceita as labels do RED curado
  (`route_template`, `method`); parser endurecido com `rsplit("}",1)` para
  tolerar `{var}` dentro de templates de rota; mantém veto de URL/e-mail/UUID.
- **`scripts/smoke.sh`**: corrige falso-positivo que vetava `http_server_requests`
  (passa a vetar só a família crua `http_server_requests_seconds`/`disk_*`);
  prova positiva de heap presente; HTTP RED validado **quando** há tráfego `/api`;
  check do dashboard tornou-se **independente de senha** (JSON válido no host +
  API best-effort, sem depender do volume `grafana-data` reaproveitado).
- **`scripts/check-grafana-provisioning.sh`** (novo): prova determinística de que o
  dashboard auto-provisiona num Grafana de banco limpo (bind em `/tmp/opencode`,
  container `--rm`, sem volume nomeado, sem tocar no `grafana-data` do dev).
- **`docs/observability.md`** e **`README.md`**: contrato de métricas vigente
  documentado (RED curado × binder cru excluído; sem buckets → média/máx; heap
  agregada como único sinal de memória; **RSS do container não observável —
  pendência do dev Java**); cita os novos scripts.
- **Skills**: `observability-logs` ganha seção "Métricas (fronteira consumida)";
  `verification-before-completion` ganha o gate de métricas/observabilidade
  (promtool, shellcheck, metrics-resilience, check-grafana-provisioning,
  check-metrics-cardinality, RED depende de tráfego).
- **Contexto** (`servicos.md`, `arquitetura.md`, `estado_atual.md`, `decisoes.md`):
  codificado o contrato de métricas com `file:line` dos irmãos, corrigida a
  exposição do actuator (`health,info,prometheus`) e drifts de linha — via
  auditoria do `context-revisor`.

## Evidências (frescas, nesta sessão)

- `scripts/check-grafana-provisioning.sh`: exit 0 — `title="Emporio B2B — Backend"`,
  HTTP 200 em banco limpo (prova de parse do novo JSON no engine do Grafana).
- `scripts/smoke.sh`: exit 0 — inclui `OK metrics: heap JVM presente`,
  `OK metrics: scrape sem labels fora da allowlist`, `OK grafana: dashboard
  emporio-backend.json é JSON válido`; `SKIP` não-fatal para API 401 (drift de
  senha do volume) e para RED sem tráfego.
- RED curado exercitado com tráfego real (`/api/v1/catalogo/destaques` 2xx,
  `busca` 4xx, rota inexistente 4xx/unknown): 36 séries no TSDB com as labels
  `route_template/method/status_class/outcome`; `check-metrics-cardinality.py`
  aceita o scrape real (exit 0).
- `scripts/metrics-resilience.sh`: exit 0 — restart preservou volume/config +
  amostra histórica; `up` Backend 0→1 após parada transitória; sem remoção de volume.
- `docker compose ... config --quiet`: exit 0; `promtool check config`: exit 0.
- `shellcheck` (koalaman v0.10.0) sobre smoke, metrics-resilience,
  check-grafana-provisioning, up-dev, init-rustfs: exit 0.
- `python3 -m json.tool` do dashboard e `py_compile` do checker: exit 0.
- `git diff --check`: exit 0.

## Decisão de design

- **Não importar dashboard da comunidade.** Análise dos JSONs (4701/12900/3662/11378,
  baixados e examinados): eles consultam `application=`/`instance=` (não emitimos
  `application`), nomes cruos renomeados/agregados pelo Backend e famílias que o
  contrato exclui (`jvm_memory_*`, `jvm_gc_pause`, `jvm_buffer_*`,
  `http_server_requests_seconds`, `tomcat_*_threads` com sufixo, `process_memory_rss`).
  Import direto renderia "No data" em massa. Mantivemos o dashboard próprio
  versionado, apenas roubando ideias de layout.

## Dependência pendente (repositório Java)

- **RSS/memória real do container**: requer `process_memory_rss_bytes`
  (lib `micrometer-jvm-extras`) no Backend e passagem pelo `MeterFilter` deles.
  Registrado em `estado_atual.md` / `docs/observability.md` como pendência do
  repo Java. Não é decisão/topologia da Infra. A Infra adiciona o painel quando a
  série existir, sem reescrever o resto.

## Fora do escopo preservado

- produção, Grafana Cloud, remote write, alertas/SLOs;
- nenhuma alteração de código/instrumentação/allowlist nos irmãos;
- nenhum volume removido; nenhum comando destrutivo; nenhum `git` mutável.

## Observação de higiene

- Os 4 `grafana-dash-*.json` na raiz eram **referências temporárias de análise**;
  decisão do operador: **removê-los antes do commit** (não devem entrar no repo).
