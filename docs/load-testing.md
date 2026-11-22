# Load testing do staging

O harness de carga é manual, temporário e exclusivo do staging. Ele não é
iniciado pelo deploy normal e não pode ser apontado para produção.

## Pré-condições

- staging healthy;
- Access configurado para `staging.emporiob2b.com.br` e
  `api-staging.emporiob2b.com.br`;
- Service Token do Access provisionado somente no ambiente runtime;
- usuário de teste provisionado fora do Git;
- `LOADTEST_CNPJ` e `LOADTEST_CEP` apontando para fixtures públicas existentes
  nos datasets do staging;
- redes do projeto `emporio-staging` criadas;
- janela de carga autorizada pelo operador.

As redes `apps` e `radar-net` devem existir como prova de que o staging está
subido. A rede `loadtest-egress` pode ainda não existir: ela é criada pelo
`docker compose run` quando o primeiro cenário público é executado.

Não é necessário criar parquet sintético. O Radar deve usar os datasets
existentes no R2 de staging. CNPJ/CEP públicos usados podem aparecer no resumo
da execução, conforme autorização operacional; tokens, senhas, emails, cookies,
headers de autenticação, corpos de resposta e logs brutos nunca aparecem.

## Cenários

```text
public          k6 → Access/Tunnel → API
api-radar       k6 → API → Radar
radar-cnpj      k6 → Radar, somente execução explícita
login-rate-limit k6 → Access/Tunnel → login
```

O cenário `radar-cnpj` usa um serviço perfilado que recebe temporariamente a
rede `radar-net`; o loadtest não é membro permanente dela e não publica a porta
`8000`. O Compose CLI utilizado não oferece `docker compose run --network`;
por isso a separação é feita por serviços perfilados, cada um com uma única
rede declarada.

## Execução

Calibração pública:

```bash
scripts/load-ramp.sh \
  --confirm-staging \
  --scenario public \
  --plan calibration \
  --env-file /caminho/protegido/staging.env
```

API interno:

```bash
scripts/load-ramp.sh \
  --confirm-staging \
  --scenario api-radar \
  --plan calibration \
  --env-file /caminho/protegido/staging.env
```

Radar direto:

```bash
scripts/load-ramp.sh \
  --confirm-staging \
  --scenario radar-cnpj \
  --plan calibration \
  --env-file /caminho/protegido/staging.env
```

Rate limit, em execução separada:

```bash
scripts/load-ramp.sh \
  --confirm-staging \
  --scenario login-rate-limit \
  --env-file /caminho/protegido/staging.env
```

## Matriz de concorrência RFB

Para medir a nova admissão do Radar, `LOADTEST_CNPJS` deve conter fixtures
públicas distintas, separadas por vírgula, existentes no dataset de staging.
O modo `all-miss` usa somente CNPJ e evita a alternância com CEP/cache quente.

Execute:

```bash
scripts/load-matrix.sh \
  --confirm-staging \
  --env-file /caminho/protegido/staging.env
```

Por padrão, a matriz executa:

```text
1, 2, 4, 8 e 12 VUs
```

Cada degrau dura 30 segundos. O Radar pode responder `503` com
`Retry-After: 1` quando `RFB_LOOKUP_ACTIVE_LIMIT=1` e
`RFB_LOOKUP_QUEUE_LIMIT=0`; esses `503` são contabilizados como rejeições de
capacidade esperadas. Respostas `500`, timeouts ou `503` sem `Retry-After`
continuam sendo falhas.

No modo de VUs fixos, cada VU aguarda aproximadamente 1 segundo entre
requisições. Cada degrau recebe uma faixa distinta de CNPJs para evitar
reutilização de fixtures e aquecimento artificial do cache.

Os relatórios individuais e o manifesto ficam em
`relatorios/carga/matrix-<id>/`.

A rampa `full` usa `1 req/s` por 60s, `2 req/s` por 120s, `5 req/s` por 120s
e `10 req/s` por 120s. A calibração usa `1 req/s` por 30s e `2 req/s` por
30s. Os thresholds são conservadores e o resultado não constitui aprovação de
capacidade.

## Segurança e parada

- o alvo público é fixo no hostname de staging;
- produção é recusada pelo script e pelos scripts k6;
- o token do Access só é enviado no modo público;
- o `Origin` de staging é enviado no login;
- o k6 não recebe Docker socket;
- `docker stats` é coletado pelo controlador no host;
- interromper diante de OOM, restart, readiness perdida, timeout ou erro acima
  do threshold;
- a limpeza remove somente o container temporário;
- nunca executar `down -v`, prune ou remoção de volumes.

O teste de rate limit usa senha inválida para a identidade de teste, confirma
`429` e `Retry-After` e não deve ser misturado ao teste de capacidade. Aguardar
a recuperação da janela antes de outro cenário de login.

## Relatório

Por padrão, o controlador grava um resumo JSON em `relatorios/carga/`, contendo
ID, cenário, plano, status, throughput, p50/p95/p99, checks e amostras
sanitizadas de `docker stats`, além de eventos `oom`, `restart` e `die`
observados no projeto, e uma amostra do listener interno de métricas RFB.
Dados brutos permanecem temporários e não são versionados.
