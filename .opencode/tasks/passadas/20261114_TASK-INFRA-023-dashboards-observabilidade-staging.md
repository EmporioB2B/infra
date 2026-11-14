# TASK-INFRA-023 — dashboards de observabilidade para staging

**Status: concluída — artefatos e documentação deste repositório.**
Importação no Grafana Cloud, provider/agente Dokploy, LogQL com dados reais e
ingestão Cloud não fazem parte da evidência desta promoção.

## Objetivo e resultado

Preparar dashboards importáveis para separar logs de staging por aplicação,
serviço e nível, e visualizar disponibilidade e métricas HTTP sem confundir
eventos de log com respostas HTTP.

- `compose/grafana/dashboards-staging/emporio-staging-logs.json`: datasource
  Loki selecionável na importação; filtros de ambiente, aplicação e serviço;
  parsing JSON de nível no Backend (ECS) e Radar (JSON Lines); logs brutos para
  os outros containers; séries de ERROR/FATAL/CRITICAL e WARN.
- `compose/grafana/dashboards-staging/emporio-staging-metrics.json`: datasource
  Prometheus selecionável; `up`/readiness, vazão por classe HTTP/outcome, média
  e máximo do Backend sem buckets, p50/p95 Radar usando os buckets existentes,
  e consultas CEP por UF.
- `docs/observability.md`: procedimento de importação, labels Dokploy, limites
  de parsing e diagnóstico quando labels/datasources ou séries não aparecem.
- `.opencode/context/`: topologia/estado atualizados; o relato do operador de
  que logs de staging já aparecem no Grafana Cloud, mas estão misturados, foi
  registrado como não verificado independentemente.

Os dashboards foram mantidos fora de `compose/grafana/dashboards/`, que é
provisionado no Grafana local de dev. HTTP status/outcome é mostrado por RED;
não se pressupõe access log por request. Nenhum ID, correlação, URL ou campo de
alta cardinalidade foi transformado em label Loki. Nenhum segredo, Compose,
workflow ou código de aplicação foi alterado.

## Evidências frescas

- Parse JSON + verificações de contrato via Python: **exit 0**; dois JSONs
  válidos, UIDs distintos para staging, datasource importável, filtros
  `dokploy_environment`/`dokploy_application`/`dokploy_service`, sem IDs ou
  correlation IDs nas queries Loki; queries métricas filtradas para staging,
  RED Backend e buckets usados somente no Radar.
- Importação em Grafana `12.0.0` descartável via API e leitura dos dashboards:
  **HTTP 200**; Logs com 4 painéis e Métricas com 5 painéis. Isso prova
  aceitação dos JSONs pelo Grafana local, não mapeamento de datasource no
  Grafana Cloud.
- `promtool check rules` usando as 10 expressões do dashboard Prometheus:
  **SUCCESS: 10 rules found** (validação de sintaxe PromQL).
- `promtool check config` no template Prometheus local de dev:
  **SUCCESS: valid prometheus config file syntax**.
- `scripts/check-grafana-provisioning.sh`: exit 0; dashboard existente do dev
  auto-provisionado em Grafana descartável (banco limpo).
- `git diff --check`: exit 0.
- `shellcheck scripts/*.sh` em container `koalaman/shellcheck:stable`: exit 1
  por achado preexistente `SC2016` em `scripts/seed-admin-staging.sh:59`;
  script não alterado nesta task, sem achado nos artefatos criados.

## Limitações e gates restantes

- Queries LogQL não foram executadas contra Loki local ou Cloud nesta task;
  Grafana Cloud/Dokploy não foram acessados. O teste local Loki foi barrado
  pelo controle de permissão da ferramenta; não se afirma validade de runtime.
- Ingestão real, labels efetivamente recebidos, provider/agente, datasource
  Cloud, resultados dos painéis e primeiro login não foram auditados. O
  operador relata logs visíveis e misturados em Grafana Cloud; é relato, não
  evidência independente desta sessão.
- `scripts/metrics-resilience.sh` não foi executado: `docker compose ... ps`
  mostrou todos os serviços dev em `exited`; o gate exige stack integrado
  ativo e altera disponibilidade do Backend/Prometheus dev. Nenhum container
  do stack dev foi iniciado ou parado nesta task.
- Depois, o operador pode importar os dois JSONs manualmente, selecionar os
  datasources corretos e confirmar labels. Se o agente/provider foi ativado
  depois dos containers, Dokploy pode exigir redeploy para adicionar
  `dokploy_*`. Validar tráfego API/Radar para as séries RED.

## Auditoria de contexto

`context-revisor` atualizou `estado_atual.md` e `servicos.md`, confirmando que
os arquivos não comprovam datasource, labels/runtime, ingestão ou importação.
O achado MÉDIO de falta de filtro por `dokploy_application` foi corrigido no
dashboard. A alegação inicial de que JSON por si validava as queries foi
restringida: PromQL foi parseado por `promtool`; LogQL não foi executado e a
limitação está documentada. As atualizações de contexto foram revistas e os
relatos externos permanecem identificados como não verificados. Um único loop
cirúrgico foi usado; sem loops adicionais.
