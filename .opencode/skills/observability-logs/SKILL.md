---
name: observability-logs
description: Use when designing or reviewing container log collection, Loki, Grafana, Vector, Docker logging drivers or Grafana Cloud integration for the Emporio B2B Infra repository.
---

# Observabilidade de logs

## Contrato

- aplicações escrevem somente em `stdout`/`stderr`;
- o Backend mantém ECS JSON, `DEBUG/INFO/WARN` em stdout e `ERROR` em stderr;
- nenhum segredo, token, cookie, Authorization, body, query string, PII ou URL
  pré-assinada entra no evento;
- `request_id`, `operation_id` e `event_id` não podem virar labels Loki: são
  campos de alta cardinalidade e ficam no corpo estruturado;
- labels Loki ficam limitadas a ambiente, serviço/container e origem.

## Dev local

O Compose dev usa o logging driver Docker `fluentd` com `fluentd-async`, enviando
para o Vector local em uma porta publicada somente em loopback. O Vector recebe
o protocolo Fluent, preserva eventos ECS e envia para o Loki local com buffer em
disco. Esse desenho não monta `/var/run/docker.sock`.

Loki e Grafana são auxiliares do dev e não podem ser dependências do Backend
para iniciar. A UI do Grafana fica em loopback e o armazenamento usa volumes
nomeados. A retenção local é limitada para evitar crescimento ilimitado.

## Produção via Dokploy

O Dokploy **não instala Loki**. Em `Settings → Logs & Metrics`, o operador
configura um provider Grafana Loki e seleciona a VPS; o Dokploy instala o
`dokploy-vector` no servidor e envia os logs dos containers ao provider.

- endpoint e credenciais vivem no Dokploy/Secrets Provider;
- nenhum token entra no Compose, task, skill ou `env/*.example`;
- a retenção é a do provider Grafana Cloud;
- logs já enviados sobrevivem a restart/recreate do container da aplicação;
- a garantia para eventos ainda não enviados depende do agente, buffer local e
  rotação Docker;
- a configuração precisa de egress HTTPS e não deve conectar o Vector à
  `radar-net`.

## Segurança e operação

- nunca usar Dozzle ou qualquer coletor que monte Docker socket no stack oficial;
- não publicar Loki, Vector ou Grafana na LAN/VPS;
- não usar `latest` em imagens de produção;
- usar volumes nomeados para dados locais e configurar retenção/limite;
- revisar cardinalidade e redaction antes de enviar logs externos;
- testar ingestão, consulta, restart e indisponibilidade temporária do destino.

## Fontes

Práticas reescritas a partir da documentação oficial do Docker Fluentd logging
driver, Vector Fluent/Loki sinks, Grafana Loki e Dokploy Logs & Metrics. A
skill não autoriza configuração de provider ou operação contra produção.
