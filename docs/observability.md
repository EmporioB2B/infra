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

### Radar — métricas internas

O Radar expõe um listener Prometheus separado em `10.254.21.30:8082/metrics`.
Ele não possui `ports:`; o Prometheus chega ao endpoint exclusivamente pela
rede interna `radar-metrics-net` (Prometheus `10.254.21.20`). A Infra mantém essa
rede separada da `metrics-net` do Backend para preservar o teste negativo
Radar→Backend:8081.

O contrato inclui `radar_health_ready`, métricas de CPU/RSS do processo, HTTP
RED curado, consultas CEP por UF e cidade primária por código municipal. O
smoke aplica o mesmo checker de cardinalidade e rejeita CEP, CNPJ, correlation
ID, path instanciado, query string e PII em labels. A série de cidade é própria
para tabela/ranking; o Geomap depende de um catálogo posterior que relacione
`codigo_cidade` a nome e coordenadas. O risco aceito pelo dono do Radar de
traceback bruto em stderr por timeout do listener não altera a decisão de
manter o endpoint somente na rede privada, sem publicação ou roteamento externo.

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

## Staging: logs via Dokploy + métricas via Prometheus remote_write

Decisão do operador (2026-11-13): o staging estreia completo, testando o
desenho de observabilidade de produção de ponta a ponta, dentro do teto de
2 CPU/12 GiB por stack.

- **Logs**: mesmo fluxo da produção descrito abaixo — `dokploy-vector` no
  host, configurado em Settings → Logs & Metrics do Dokploy, enviando ao
  Grafana Cloud Loki. Nenhum Loki/Grafana entra no Compose.
- **Métricas**: o Compose de staging inclui um Prometheus (`prom/prometheus`
  pinado por digest) que raspa a API (`10.254.30.10:8081`, management com bind
  na `metrics-net` interna) e o Radar (`10.254.31.30:8082`, listener separado
  na `radar-metrics-net` interna) e envia as séries ao Grafana Cloud por
  `remote_write`. Retenção local de 7 dias; UI somente em loopback do
  container; saída externa exclusiva pela `prometheus-egress`.
- Credenciais: URL e instance ID no Environment do Dokploy; o token
  (`metrics:write`) em File Mount dedicado lido via `password_file` — nunca
  em shell, repo ou log. Detalhes de montagem e validação em
  `docs/staging-compose.md`.
- Dashboards de staging versionados para importação manual: logs Loki em
  `compose/grafana/dashboards-staging/emporio-staging-logs.json` e métricas
  Prometheus em `compose/grafana/dashboards-staging/emporio-staging-metrics.json`.
  Eles ficam fora de `compose/grafana/dashboards/`, diretório provisionado
  automaticamente no Grafana local de dev. Importando os JSONs no Grafana
  Cloud, selecione o datasource Loki/Prometheus correspondente no passo de
  importação; os dashboards não dependem de UID local fixo.
- O Label browser reportado pelo operador (2026-11-14) mostra como labels
  indexados `dokploy_application`, `dokploy_environment`, `dokploy_project`,
  `dokploy_server`, `dokploy_test` e `service_name`; `service_name` aparece
  como `unknown_service`. `dokploy_service` é campo do envelope JSON, não label
  indexado. Para o stack observado, selecionar
  `dokploy_application="emporio-staging"`; `dokploy_environment` veio como
  `production`, por isso não é usado para classificar esse stack.
- Os eventos chegam como JSON externo com metadata de Dokploy/Docker e campo
  `message` contendo o JSON estruturado da aplicação. O dashboard filtra o
  label indexado de aplicação, faz `| json` no envelope, filtra o campo
  `dokploy_service`, reescreve a linha para `message` e faz parse do JSON
  interno. Os dropdowns de serviço são valores estáticos dos serviços definidos
  em `compose/docker-compose.staging.yml`, pois as variáveis Loki `label_values`
  só listam labels indexados — não campos JSON extraídos. São opções fixas e
  controladas pela Infra (sem entrada livre); a opção `All` é mapeada para `.*`.
  O nível também é dropdown estático, com o mesmo mapeamento para mostrar todos.
  Backend/Front usam `log_level`: o parser JSON Loki sanitiza pontos em nomes de
  campos para `_` e achata objetos aninhados; Radar usa `level`. Fonte:
  [Loki LogQL parser](https://grafana.com/docs/loki/latest/query/log_queries/)
  (consultado em 2026-11-14). **Relato do operador (2026-11-14):** testou no
  Cloud as consultas/snippets de API/Front e Radar; essa execução não foi
  reproduzida independentemente nesta sessão. IDs
  Dokploy e request/correlation/event IDs nunca viram labels.
- O Backend registra um evento estruturado de acesso HTTP com `method`, path
  sanitizado, `status` e `duration_ms` (`AccessLogFilter`); o Front registra
  evento SSR com os mesmos dados de acesso via `server-logger.ts`. O dashboard
  oferece contagem de 4xx/5xx para API/Front. As séries RED do Prometheus seguem
  úteis para status_class/outcome e latência agregada. O Radar desativa
  `uvicorn.access` porque sua URL pode conter CEP; não reabilitar esse access
  log. Outros containers são mostrados como logs brutos, sem pressupor parser de
  nível comum.
- O Dokploy informa que containers implantados antes de ativar Logs & Metrics
  podem precisar de redeploy para receber metadados `dokploy_*`; o operador
  relata logs no Cloud e confirmou a busca no dashboard; esta task não acessou a
  UI de configuração do provider nem verificou independentemente a ingestão.
  Fonte do contrato geral:
  [Dokploy Logs & Metrics](https://docs.dokploy.com/docs/core/logs-and-metrics)
  (consultado em 2026-11-14); labels/valores acima são evidência reportada pelo
  operador, não inspeção independente.
- O dashboard Prometheus usa os jobs e `environment="staging"` do template de
  remote_write. `status_class`/`outcome` e latência vêm do RED; códigos exatos
  4xx/5xx da API/Front são consultados no evento de access log. Backend expõe
  média e máximo (sem buckets/percentis); Radar expõe histograma com
  buckets e o dashboard calcula p50/p95. As séries HTTP só aparecem após
  tráfego real. O dashboard Prometheus foi importado em um Grafana local
  descartável, e as expressões PromQL passaram pelo parser `promtool check
  rules`; isso não valida execução contra séries reais. **Relato do operador
  (2026-11-14):** no Grafana Cloud confirmou os snippets LogQL e a busca
  Request/Correlation ID da TASK-INFRA-024 e testou a versão atual do dashboard
  Prometheus, conferindo consultas/séries disponíveis. Não houve verificação
  independente da conta ou ingestão Cloud nesta sessão.
- **Dashboard ampliado de métricas (TASK-INFRA-025, promovida em 2026-11-14):**
  35 painéis e 84 expressões PromQL; importação testada em Grafana 12
  descartável e sintaxe validada por `promtool check rules`. O operador confirma
  que importou/testou a versão atual no Grafana Cloud e conferiu as séries
  disponíveis; essa confirmação não foi reproduzida independentemente nesta
  sessão. O dashboard
  agrega os grupos já expostos pelos dois targets — API: RED por rota, heap,
  CPU do processo JVM, threads/GC, Tomcat, Hikari, executores, dependência
  Back→Radar, storage, email, notificações, catálogo e abrangência; Radar:
  RED/CEP, CPU e memória do processo, descritores de arquivo e fila de campanhas.
  Os timers Java continuam limitados a média/máximo; p50/p95 só são calculados
  para histogramas do Radar. Isso **não** representa CPU/RAM por container:
  API RSS não está exposto, métricas de processo do Radar não equivalem aos
  limites cgroup, e cAdvisor permanece fora desta task. Séries de domínio
  podem ficar vazias até o fluxo correspondente gerar tráfego.

### Importação manual dos dashboards de staging

1. No Grafana Cloud, crie a pasta `Emporio B2B - Staging` (se ainda não existir)
   e confirme que existem os datasources Loki e Prometheus
   apontando para os dados desta stack; Grafana Cloud não seleciona um datasource
   automaticamente só por importar um JSON.
2. Em **Dashboards → New → Import**, carregue um JSON de
   `compose/grafana/dashboards-staging/` e selecione o datasource correspondente
   solicitado pelo formulário. Importe os dois arquivos separadamente. Para
   atualizar o dashboard de logs, confirme o overwrite do UID
   `emporio-staging-logs`; para importar/atualizar métricas, use o UID
   `emporio-staging-metrics`. Coloque ambos na pasta de staging.
3. No dashboard de logs, use o dropdown `Serviço` e `Nível`; a aplicação já
   fica fixada em `emporio-staging`. As opções de serviço correspondem ao
   Compose versionado. Teste `api` + `ERROR`, `radar` + `ERROR`, depois
   `All`; os painéis HTTP devem mostrar 4xx e 5xx da API/Front. O dashboard não
   tem data links: clicar nos gráficos não navega nem gera query. Em vez disso,
   confira o painel de código **Consultas LogQL para copiar no Explore**: ele
   acompanha os dropdowns. Copie a consulta da fonte desejada e cole no Explore.
   Se não houver eventos no intervalo escolhido, o painel pode ficar vazio.
4. No dashboard de métricas, teste período com tráfego na API e no Radar. A
   versão ampliada inclui runtime, pools, executores e operações de domínio que
   já pertencem aos contratos dos dois targets. RED e métricas de domínio só
   aparecem depois que as operações correspondentes ocorrem; readiness e target
   `up` não dependem de tráfego de negócio. Heap da API não é RSS/container, e
   CPU/RSS do Radar são métricas do processo.

### Drilldown por Request ID / Correlation ID

Um ponto do gráfico é uma contagem agregada por serviço/classe/intervalo, não
um evento individual com um `request_id` único. Use os dropdowns para preparar
a query no painel de código e execute-a no Explore; escolha uma linha específica
e copie o ID do corpo do evento.

O dashboard inclui a caixa `Request/Correlation ID`: cole um `request_id` de um
evento da API (ou `correlation_id` do Radar), pressione **Enter** e aguarde os
painéis para listar eventos que compartilham o valor, parseando o JSON interno.
No código do Backend,
`RestClientRadarHttpClient` encaminha o `request_id` do MDC como
`X-Correlation-ID`; o Radar aceita esse header e o registra como
`correlation_id`. Isso permite procurar a chamada API→Radar pelo mesmo ID.
Não use o ID como label Loki: é um campo de alta cardinalidade no corpo do log.
O `request_id` de um evento SSR do Front não deve ser presumido igual ao da
requisição API do navegador; teste a propagação antes de tratar Front, API e
Radar como uma única cadeia.

LogQL de referência no Explore para a estrutura observada (o serviço é campo
extraído do JSON, não stream label):

```logql
{dokploy_application="emporio-staging"} | json | dokploy_service="api" | line_format "{{.message}}" | json | log_level=~"(?i)(error|fatal|critical)"
{dokploy_application="emporio-staging"} | json | dokploy_service="api" | line_format "{{.message}}" | json | status=~"5.."
{dokploy_application="emporio-staging"} | json | dokploy_service="radar" | line_format "{{.message}}" | json | level=~"(?i)(error|fatal|critical)"
{dokploy_application="emporio-staging"} | json | line_format "{{.message}}" | json | (request_id="COLE_AQUI_O_ID" or correlation_id="COLE_AQUI_O_ID")
```

O dashboard de logs mostra códigos HTTP 4xx/5xx para API/Front; use o dashboard
Prometheus para status_class/outcome e latência agregada. O Radar desativa
`uvicorn.access` porque a URL de acesso pode conter CEP; não reabilitar access
logs nem usar campos de alta cardinalidade como labels Loki.

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
