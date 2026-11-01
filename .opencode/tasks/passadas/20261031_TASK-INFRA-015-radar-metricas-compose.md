# TASK-INFRA-015 — Integrar métricas Prometheus do Radar no Compose dev

**Status:** promovida
**Data:** 2026-10-31
**Repo alvo:** `infra`
**Dependência:** Radar_Middleware_Python — endpoint Prometheus promovido pelo dono

## Entrega

- Radar integrado ao Compose dev com:
  - `METRICS_BIND_ADDRESS=10.254.21.30`;
  - `METRICS_PORT=8082`;
  - nenhum `ports:`/publish de 8082;
- nova rede interna exclusiva `emporio-dev_radar-metrics-net`:
  - Prometheus `10.254.21.20`;
  - Radar `10.254.21.30`;
  - subnet `10.254.21.0/24`;
- `metrics-net` original preservada exclusivamente para Backend+Prometheus,
  mantendo o negativo Radar→Backend:8081;
- job Prometheus `emporio-radar` em `10.254.21.30:8082/metrics`;
- checker de cardinalidade ampliado para `uf`, `codigo_cidade` e histogram `le`;
- smoke ampliado para scrape/readiness/target Radar, ausência de publish,
  topologia das três redes e PII/cardinalidade do scrape Radar;
- dashboard ampliado com readiness, RSS/CPU do processo Radar, consultas CEP por
  UF e top cidades por código; Geomap permanece planejado até catálogo de
  coordenadas;
- `docs/networks.md`, `docs/observability.md`, `README.md` e contextos
  atualizados;
- placeholders abreviados inválidos de `env/.env.dev.example` substituídos por
  placeholders completos `replace-with-*`;
- volumes dev v2 explícitos (`emporio-dev_radar_state_v2` e
  `emporio-dev_pgdata_v2`) criados sem remover os volumes antigos, pois o Radar
  antigo não possuía `cep_cidades` e o Postgres antigo apresentava checksums
  Flyway incompatíveis.

## Evidências

- `scripts/up-dev.sh --no-build`: stack canônico healthy após os volumes v2;
- build real do Radar via `scripts/up-dev.sh`: imagem construída a partir do
  código promovido;
- Prometheus alcançou `10.254.21.30:8082/metrics` e expôs
  `radar_health_ready`;
- target Prometheus `emporio-radar`: `up=1`;
- requisição real Backend→Radar para CEP `01001000`: HTTP 200;
- scrape real materializou:
  - `radar_cep_queries_total{uf="SP",outcome="hit"}`;
  - `radar_cep_primary_city_queries_total{uf="SP",codigo_cidade="7107"}`;
- `emporio-dev_radar-metrics-net`: interna, somente Radar+Prometheus;
- `emporio-dev_metrics-net`: interna, somente Backend+Prometheus;
- `emporio-dev_radar-net`: interna, somente Backend+Radar;
- host `127.0.0.1:8082`: conexão recusada; Compose não retornou publicação;
- checker de cardinalidade Radar: exit 0;
- `scripts/smoke.sh`: exit 0;
- `scripts/metrics-resilience.sh`: exit 0;
- `check-grafana-provisioning.sh`: exit 0, dashboard HTTP 200 em Grafana limpo;
- `docker compose config --quiet`: exit 0;
- `promtool check config`: exit 0;
- ShellCheck dos scripts: exit 0;
- JSON/Python e `git diff --check`: exit 0.

## Limitações/pendências

- O catálogo `codigo_cidade → nome → latitude/longitude` ainda não foi entregue;
  por isso há ranking por código, mas não Geomap.
- Traceback bruto de timeout do listener WSGI do Radar permanece risco residual
  aceito pelo dono do Radar; o endpoint continua restrito à rede privada sem
  roteamento/publicação.
- O seed-admin dev apresentou erro separado durante a primeira subida dos
  volumes novos; os logs posteriores mostram Flyway aplicando V1–V9 e o
  Backend ficou healthy. Não foi executado `repair`, `dropdb`, `DROP` ou remoção
  de volume; investigação do seed/schema pertence ao Backend.
- Produção/Grafana Cloud não foram alterados; não existe Prometheus local no
  Compose de produção nesta fase.
- O ID `TASK-INFRA-014` já pertence à task futura de Supabase; esta integração
  foi arquivada como `TASK-INFRA-015` para evitar colisão.
