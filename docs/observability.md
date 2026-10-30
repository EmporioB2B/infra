# Observabilidade de logs

## Dev local

O Backend e os demais serviços continuam escrevendo em `stdout`/`stderr`. O
Compose local coleta esses streams sem montar `/var/run/docker.sock`:

```text
containers
  └─ Docker logging driver fluentd (loopback:24224)
       └─ Vector
            └─ Loki (volume loki-data, retenção local de 7 dias)
                 └─ Grafana (volume grafana-data, UI em 127.0.0.1:3000)
```

O Vector usa um buffer em disco no volume `vector-data`. O driver Docker usa
modo assíncrono para que a indisponibilidade transitória do coletor não impeça
o serviço da aplicação de iniciar. Isso é uma solução de desenvolvimento; não
é uma garantia de entrega de logs de produção.

### Subida

`scripts/up-dev.sh` sobe Loki, Vector e Grafana antes do restante da stack. A
senha da UI vem de `GRAFANA_ADMIN_PASSWORD` em `env/.env.dev`, que deve ser
preenchida a partir do example e nunca versionada.

```bash
scripts/up-dev.sh
scripts/smoke.sh
```

Acesse:

```text
http://127.0.0.1:3000
```

Os datasources `Emporio Loki` e `Emporio Prometheus` são provisionados
automaticamente. O dashboard `Emporio B2B — Backend` também é carregado do
diretório versionado `compose/grafana/dashboards/`, dentro da pasta `Emporio
B2B`.

No Grafana, abra **Explore** e consulte, por exemplo:

```logql
{environment="dev"}
{environment="dev", container=~".*backend.*"}
```

O datasource `Emporio Prometheus` também é provisionado automaticamente. O
Prometheus não publica porta no host: ele coleta o Backend pela `metrics-net` e
o Grafana o consulta pela rede `observability`.

```promql
up{job="emporio-backend", environment="dev"}
rate(radar_http_requests_total{job="emporio-backend"}[5m])
rate(storage_failures_total{job="emporio-backend"}[5m])

# Memória: apenas a heap agregada da JVM (sem RSS do container, ver adiante)
jvm_heap_used_bytes{job="emporio-backend"}
jvm_heap_used_bytes{job="emporio-backend"} / jvm_heap_max_bytes{job="emporio-backend"}

# Latência: média (rate sum/count) e máx — o contrato NÃO expõe buckets,
# então histogram_quantile/_bucket não funciona aqui.
sum by (operation) (rate(radar_http_duration_seconds_sum{job="emporio-backend"}[5m]))
  / sum by (operation) (rate(radar_http_duration_seconds_count{job="emporio-backend"}[5m]))
max by (operation) (radar_http_duration_seconds_max{job="emporio-backend"})

# HTTP RED curado da API (labels: route_template, method, status_class, outcome)
sum by (outcome) (rate(http_server_requests_total{job="emporio-backend"}[5m]))
sum(rate(http_server_duration_seconds_sum{job="emporio-backend"}[5m]))
  / sum(rate(http_server_duration_seconds_count{job="emporio-backend"}[5m]))

# Servidor e pools
tomcat_threads_busy{job="emporio-backend"}
hikaricp_connections_active{job="emporio-backend"}
increase(executor_rejections_total{job="emporio-backend"}[5m])
```

O contrato local é:

```text
Backend 10.254.20.10:8081/actuator/prometheus
        └─ metrics-net (internal)
Prometheus 10.254.20.20
        └─ observability ── Grafana:3000
```

O Backend não publica `8081`; `MANAGEMENT_SERVER_ADDRESS` é injetado pelo
Compose como `10.254.20.10`. O Prometheus usa o volume nomeado
`prometheus-data`, retenção temporal fixa de 7 dias e WAL comprimido. O
endpoint `/-/healthy` indica processo vivo e `/-/ready` indica que o coletor
está pronto para consultas; ambos são validados pelo smoke.

Contrato de métricas do Backend (vigente, verificado no scrape da imagem atual):

- **HTTP:** o binder cru `http.server.requests` (`http_server_requests_seconds`)
  continua **excluído** pelo `MeterFilter`; o que existe é o **RED curado**
  próprio do Backend — `http_server_requests_total` e
  `http_server_duration_seconds_{count,sum,max}` — com labels finitas
  `route_template, method, status_class, outcome`. As séries só aparecem após
  tráfego real em `/api`.
- **Latência:** o contrato **não expõe buckets/percentis** (`*_bucket` não
  existe). Painéis usam **média** (`rate(sum)/rate(count)`) e **máx**
  (`*_max`), nunca `histogram_quantile`.
- **Memória:** a única série é a **heap agregada da JVM**
  (`jvm_heap_used_bytes`/`jvm_heap_max_bytes`). **Não há `jvm_memory_*` por
  pool, nem buffer, nem GC pause.** **RSS/memória real do container não é
  observável no Grafana** — depende de `process_memory_rss_bytes` (lib
  `micrometer-jvm-extras`) que o Backend ainda não instrumenta. **Isso é
  pendência registrada para o dev Java**, não uma omissão da Infra.

A allowlist de métricas operacionais e suas tags (domínio, cardinalidade de
valores) continua responsabilidade da aplicação. A Infra valida a fronteira
observada contra labels arbitrárias, IDs, PII e URLs
(`scripts/check-metrics-cardinality.py`) sem duplicar a allowlist do Backend.

As portas `GRAFANA_PORT` e `VECTOR_FLUENTD_PORT` podem ser alteradas no env
local se houver conflito. Loki não é publicado no host; é acessado por
Grafana e Vector na rede `observability`. Prometheus também não é publicado;
use o Grafana ou `docker compose exec prometheus` para consultas locais.

Para validar restart e recuperação do target sem destruir volumes:

```bash
scripts/metrics-resilience.sh
```

O script reinicia somente o Prometheus, comprova a preservação de uma amostra
histórica e da configuração/volume, para temporariamente o Backend, prova
`up=0`, inicia o Backend novamente e prova o retorno para `up=1`. Ele restaura
o Backend ao sair, inclusive em caso de falha.

Para provar que o dashboard é auto-provisionado sem depender da senha persistida
no volume `grafana-data` do dev (que diverge do env em boot reaproveitado e só
causaria 401 falso-positivo), suba um Grafana descartável de banco limpo com os
mesmos arquivos versionados montados. Este teste **não** toca o `grafana-data`
do stack nem cria volume nomeado; usa bind temporário em `/tmp/opencode`:

```bash
scripts/check-grafana-provisioning.sh
```

## Produção: Grafana Cloud Loki via Dokploy

O Compose da aplicação não deve conter Loki ou Grafana Cloud. O fluxo previsto
é:

```text
api/front/radar stdout/stderr
       └─ Docker logs com rotação no host
            └─ Vector gerenciado pelo Dokploy
                 └─ provider Grafana Loki (HTTPS)
```

No Dokploy:

1. abrir **Settings → Logs & Metrics**;
2. criar provider **Grafana Loki**;
3. inserir endpoint, tenant/usuário quando aplicável e token de escrita;
4. selecionar a VPS e fazer **Deploy**;
5. validar o estado `Running` do agente e a chegada de logs.

O Dokploy instala `dokploy-vector`; ele não cria uma conta Grafana nem um
servidor Loki. As credenciais ficam somente no painel/Secrets Provider. A
retenção é definida pelo provider Grafana Cloud; logs que já chegaram ao
provider sobrevivem a restart ou recreate do container da aplicação.

Não expor Grafana/Loki por um novo hostname público nesta fase. O subdomínio e
a política de acesso para uma UI de observabilidade ainda não são decisão da
borda; use o acesso privado oferecido pelo provider ou uma VPN/Cloudflare
Access quando houver task própria.

## Limites e segurança

- não montar Docker socket em coletor do stack;
- não colocar `request_id`, `event_id`, token ou PII como label Loki;
- não gravar logs em arquivo dentro do Backend;
- não usar `down -v` para limpar volumes de observabilidade;
- o pipeline de logs não é dependência de saúde do Backend;
- produção precisa validar egress HTTPS, retenção, custo e rotação do token no
  Dokploy antes da promoção.
