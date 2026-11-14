# TASK-INFRA-025 — ampliar dashboard de métricas de staging

## Resultado

Promovida em 2026-11-14 após validações locais e confirmação explícita do
operador de que testou a versão atual no Grafana Cloud.

## Escopo realizado

- Expandido `compose/grafana/dashboards-staging/emporio-staging-metrics.json`
  de cinco para 35 painéis, com 84 expressões PromQL.
- Acrescentados painéis de rotas HTTP, JVM/heap/process CPU/GC/threads, Tomcat,
  Hikari, executores, chamadas Backend→Radar, storage, email, notificações,
  catálogo, abrangência, processo/CEP/campanhas do Radar.
- Atualizados `docs/observability.md` e contextos factuais para registrar os
  grupos abrangidos, limites de instrumentação e estado de validação.
- Nenhum cAdvisor/exporter adicional, mudança de Compose, segredo ou código de
  repo irmão foi incluído.

## Evidências

- `promtool check rules` na versão final: **84 rules found / SUCCESS**.
- `grafana/grafana:12.0.0` descartável importou o dashboard pela API:
  **HTTP 200**, UID `emporio-staging-metrics`, 35 painéis.
- `scripts/check-grafana-provisioning.sh`: passou.
- Validação estática: JSON válido, 35 IDs únicos, layout sem sobreposição e sem
  `histogram_quantile` para timers HTTP do Backend.
- `git diff --check`: exit 0.
- **Confirmação manual do operador:** testou a versão atual no Grafana Cloud.
- `shellcheck scripts/*.sh` foi executado via `koalaman/shellcheck:stable`;
  retorna exit 1 por aviso informativo SC2016 preexistente em
  `scripts/seed-admin-staging.sh:59` (fora do escopo e sem alteração).

## Limitações preservadas

- A confirmação Cloud é relato do operador; não houve acesso independente à
  conta nesta sessão. O scrape local real não foi exercitado porque o stack dev
  estava parado; `metrics-resilience.sh` e `check-metrics-cardinality.py` não
  foram executados sem scrape/runtime disponível.
- Painéis podem ficar vazios até tráfego/feature correspondente.
- CPU/RSS exibidos são métricas de processo; não são consumo/limite cgroup por
  container. API não expõe RSS e não há métricas de containers nesta versão.
- Backend Java não publica buckets HTTP, logo não há p50/p95 da API. Percentis
  do Radar usam os histogramas existentes.
- Front, PostgreSQL, cloudflared, host e jobs one-shot não têm targets atuais.
  Avaliação de cAdvisor permanece como follow-up separado.
