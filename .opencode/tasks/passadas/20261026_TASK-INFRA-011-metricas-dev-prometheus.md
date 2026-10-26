# TASK-INFRA-011 — Camada de métricas no desenvolvimento

**Status:** promovida
**Data:** 2026-10-26
**Repo alvo:** `infra`

## Entrega

- `metrics-net` como bridge `internal: true`;
- subnet `10.254.20.0/24` e gateway `10.254.20.1`;
- Backend em `10.254.20.10` com `MANAGEMENT_SERVER_ADDRESS` injetado;
- Prometheus em `10.254.20.20`, sem porta publicada;
- scrape de `10.254.20.10:8081/actuator/prometheus` a cada 15s;
- datasource `Emporio Prometheus` provisionado no Grafana;
- retenção local Prometheus de 7 dias em volume nomeado;
- remoção da publicação dev de `8081`;
- smoke com prova de scrape, target, isolamento, redes e ausência de Docker socket;
- documentação, env example, skills e contextos atualizados.

## Evidências

- `scripts/up-dev.sh`: exit 0; bootstrap limpo com todos os serviços healthy;
- `scripts/smoke.sh`: exit 0; todos os checks passaram;
- `docker compose --env-file env/.env.dev -f compose/docker-compose.dev.yml config --quiet`: exit 0;
- `promtool check config`: configuração Prometheus válida;
- `shellcheck` via `koalaman/shellcheck:v0.10.0`: exit 0;
- `git diff --check`: exit 0;
- `docker network inspect`: `metrics-net` interna com Backend/Prometheus e
  `radar-net` interna com Backend/Radar;
- host `127.0.0.1:8081`: sem resposta;
- host Docker alcança `10.254.20.10:8081`: limitação conhecida de bridge,
  documentada e fora do escopo de firewall;
- Radar não alcança `10.254.20.10:8081`;
- nenhum serviço monta `/var/run/docker.sock`.

## Limitações e decisões preservadas

- `internal: true` não é firewall contra o próprio host Docker;
- `http.server.requests` permanece fora do contrato;
- restart/recuperação do Prometheus ficam para TASK-INFRA-012;
- produção, remote write e Grafana Cloud ficam para TASK-INFRA-013;
- nenhum deploy ou operação de produção foi executado.

## Dependências verificadas

O Backend_Java atualizado fornece `MANAGEMENT_SERVER_ADDRESS` obrigatório,
bind privado em `10.254.20.10`, healthcheck parametrizado e imagem somente com
`EXPOSE 8080`. O volume PostgreSQL dev foi recriado pelo operador antes da
validação, eliminando o checksum Flyway divergente preexistente.
