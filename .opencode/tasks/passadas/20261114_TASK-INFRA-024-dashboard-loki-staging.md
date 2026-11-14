# TASK-INFRA-024 — corrigir dashboard Loki de staging

## Resultado

Arquivada em 2026-11-14 após implementação e autorização explícita do operador.

## Escopo realizado

- Corrigido `compose/grafana/dashboards-staging/emporio-staging-logs.json`
  para selecionar pelo label indexado `dokploy_application`, interpretar o
  envelope JSON e separar serviço/nível/status por campos do evento.
- Incluídos dropdowns estáticos, painéis de logs e contagens HTTP/WARN/ERROR,
  busca por `request_id`/`correlation_id` e snippets LogQL em painel Text/Code
  para cópia manual no Explore.
- Removidos todos os data links conforme instrução do operador. Clique em ponto
  agregado não copia nem gera query.
- Atualizada a documentação de observabilidade e o contexto factual por
  auditoria do `context-revisor`.

## Evidência

- Grafana local descartável `grafana/grafana:12.0.0`: importação dos dashboards
  via API HTTP 200; logs com oito painéis e métricas com cinco.
- Verificação estática fresca em 2026-11-14: JSON parseável, oito painéis, sem
  links/data links e painel Text/Code com variáveis de serviço, nível, status e
  request ID; `git diff --check` exit 0.
- `scripts/check-grafana-provisioning.sh` passou; `promtool` validou a sintaxe do
  Prometheus dev e dez expressões PromQL do dashboard de métricas.
- **Confirmação manual do operador no Grafana Cloud (2026-11-14):** reimportou
  a versão sem links, testou os snippets de API/Front e Radar no Explore, a
  busca Request/Correlation ID encontrando Backend→Radar e confirmou que os
  gráficos não navegam.

## Limitações remanescentes

- A confirmação de comportamento Cloud é relato explícito do operador; não
  houve acesso independente à conta Cloud nesta sessão.
- Essa task não alterou provider/Dokploy, Compose, segredos ou repositórios
  irmãos.
