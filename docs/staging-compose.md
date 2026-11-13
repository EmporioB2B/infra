# Compose de staging — operação e limites

O stack versionado está em `compose/docker-compose.staging.yml`, com projeto
Compose estável `emporio-staging`. O YAML é fonte de topologia, não evidência de
deploy. O operador relata que o staging está funcional e que o Custom Domain
R2 de mídia serve o logo; Infra não inspecionou Dokploy, R2 ou SMTP
independentemente nesta revisão. A borda Cloudflare (Tunnel/DNS/Access) foi
configurada em 2026-11-13.

## Dokploy e ambiente

- Usar o projeto/serviço Compose de staging existente no Dokploy e apontar para
  este arquivo; não criar Domains do Traefik para os serviços.
- O Environment do Compose no Dokploy deve conter as variáveis de interpolação
  exigidas pelo YAML. O `.env.staging.example` é checklist de nomes/placeholders
  para validação local, não deve ser carregado inteiro nos containers.
- Distribuir cada variável somente aos serviços que precisam dela: segredos do
  Postgres/bootstrap; senha do migrador no bootstrap e migration job; senha da
  role runtime no bootstrap e API; credenciais Back, Radar e Tunnel somente nos
  respectivos serviços. Não guardar valores reais no repo.
- As imagens `backend-java`, `front-angular` e `radar-middleware` precisam ser
  referências SHA imutáveis no GHCR, com manifest `linux/amd64,linux/arm64`.
  `__SET_STAGING_SHA__` no example é placeholder, não tag publicável/deployável.
  Publicação multiarch das três imagens e perfil staging do Front verificados
  em 2026-11-13 (tags, digests e evidência em
  `.opencode/context/estado_atual.md`). Gates remanescentes antes do primeiro
  deploy: File Mount, valores reais por serviço e deploy/smoke (a borda
  Cloudflare já está configurada). O Front segue sem workflow de CI (publicação
  manual); isso é pendência do contrato de produção (TASK-INFRA-002/003), não
  do staging.

## Bootstrap PostgreSQL

`db-bootstrap` aplica o SQL canônico da Infra e o job `migrate` executa o runner
Flyway da imagem Back; a API só inicia depois de migração bem-sucedida. Como o
Dokploy limpa/recria o checkout em deploy, não bind-montar arquivo do clone.
Antes do deploy, cadastrar em **Advanced → Mounts → File Mounts** do serviço
Compose os três arquivos abaixo. Cadastrar um File Mount no Dokploy, por si só,
não o monta dentro do container: o Compose os referencia explicitamente em
`../files/`.

| File Path no Dokploy / nome em `../files/` | Mount Path no Dokploy / destino no container | Conteúdo |
|---|---|---|
| `roles-bootstrap.sql` | `/bootstrap/roles.sql` | `database/bootstrap/roles.sql` |
| `prometheus.template.yml` | `/etc/prometheus/prometheus.template.yml` | `compose/prometheus/prometheus.staging.yml` |
| `remote-write-token` | `/etc/prometheus/remote-write-token` | somente token `metrics:write` |

No formulário File Mount do Dokploy, **File Path é somente o nome do arquivo**
(sem `/` inicial); **Mount Path é o caminho completo no container, incluindo o
nome do arquivo**. O Dokploy guarda o arquivo em `../files/<File Path>`; para
Compose, o YAML precisa ligar essa origem ao destino usando `volumes:`. Exemplo
do bootstrap: `../files/roles-bootstrap.sql:/bootstrap/roles.sql:ro`. Use nomes
de File Path que correspondam exatamente às fontes declaradas no Compose. O bootstrap/Prometheus falham se os arquivos
necessários não existirem ou forem diretórios. Em atualizações futuras,
sincronizar os conteúdos versionados antes do redeploy; nunca registrar o token
no repo.

O volume `emporio-staging_pgdata` é persistente e não deve ser removido por
`down -v` ou operação equivalente. A política operacional de backup e retenção
de dados do staging precisa ser definida antes do deploy.
O Compose não impõe quota de disco ao named volume; monitoramento e limite de
armazenamento no host/daemon são follow-up operacional, não foram configurados.

### Criar o admin inicial (operação manual)

A migration V1 cria a organização `Emporio B2B` (`PLATAFORMA`); ela não cria
usuário admin. Depois que o staging estiver saudável e as migrations tiverem
terminado, o operador pode executar `scripts/seed-admin-staging.sh
--confirm-staging` em um host conectado ao daemon Docker que gerencia o staging.
O script localiza exclusivamente o serviço Compose `postgres` cujo projeto
seja `emporio-staging` ou tenha o sufixo gerado pelo Dokploy (por exemplo,
`emporio-staging-elh12i`), verifica também o banco `emporio`, exige estado
`healthy` e confirmação digitada `staging`.
Ele solicita a senha do admin sem eco, gera BCrypt e executa o seed idempotente
em transação usando a credencial administrativa disponível dentro do container.
Ao executar novamente, a senha informada substitui a senha anterior; use uma
senha exclusiva de staging, diferente da produção.

O seed é deliberadamente manual e **não** é dependência de `db-bootstrap`,
`migrate`, API ou deploy. Ele concede `ADMIN_NEGOCIO` no escopo `PLATAFORMA` e
as nove capacidades administrativas do seed dev; isso equivale a um
superusuário de staging. A senha em claro não é gravada nem impressa (somente o
hash BCrypt é persistido no banco). A operação só
altera o banco se a verificação explícita do alvo passar; não rode em produção.
O e-mail inicial é `admin@emporiob2b.com.br`.

### Logo estático dos emails

O Backend referencia o logo por `APP_MEDIA_BASE_URL` + `/img/email/logo.png`;
não consulta o banco para escolher o logo. Para staging,
`scripts/publish-email-logo-staging.sh [caminho/logo.png]` publica o PNG no
bucket público configurado e valida um GET pela URL
`https://media-staging.emporiob2b.com.br/img/email/logo.png`. Por padrão, a
origem é `../Front_Angular/public/img/logo.png`; passe outro caminho se o asset
não estiver nesse clone. O script é somente staging, sobrescreve essa chave,
não altera o banco e exige confirmação digitada `staging`.

Antes de executar, instale AWS CLI v2 e carregue as variáveis de
`env/.env.email-logo.staging.example` em `env/.env.email-logo.staging`, arquivo
local ignorado (nunca preencha ou use o example como arquivo de credenciais).
Rode o script como o usuário normal, sem `sudo`, após carregar o arquivo no
shell. Esse arquivo contém somente configuração/credencial do uploader; a base
`APP_MEDIA_BASE_URL` é configurada separadamente na API pelo Compose. O token `EMAIL_LOGO_R2_*`
deve ser exclusivo e restrito à escrita no bucket público de staging; não
reutilize credenciais do Radar ou de produção. O script não verifica a policy
efetiva do token; confirme-a ao provisioná-lo no Cloudflare. O logo do Front
mede 556×449 px;
o template de email limita a largura a 180 px e define altura automática.
Cloudflare pode manter o objeto em cache por até 5 minutos conforme o metadata
enviado; regras de cache no domínio continuam sendo decisão separada.

O healthcheck do Front usa `http://localhost:4000/`; a allowlist SSR compilada
na imagem precisa preservar `localhost` junto ao hostname público de staging.

## Métricas — Prometheus → Grafana Cloud

O staging envia métricas ao Grafana Cloud por `remote_write` (decisão do
operador de 2026-11-13: estrear completo, testando em staging o desenho de
produção). Logs seguem o caminho separado do `dokploy-vector` no host
(`docs/observability.md`); Loki/Grafana não entram no Compose.

- Imagem `prom/prometheus:v3.5.0` pinada por digest no example; retenção local
  de 7 dias com WAL comprimido no volume `emporio-staging_prometheus-data`;
  UI somente em `127.0.0.1:9090` dentro do container.
- O entrypoint interpola **somente** URL e instance ID do remote_write
  (Environment do Dokploy: `PROMETHEUS_REMOTE_WRITE_URL`,
  `PROMETHEUS_REMOTE_WRITE_USERNAME`) no template, via `sed` com delimitador
  `|`; exige HTTPS e falha fechado sem os valores. O **token nunca passa por
  shell**: é lido de `password_file`.
- File Mounts adicionais no Dokploy (Advanced → Mounts → File Mounts), com os
  campos File Path/Mount Path listados na tabela Bootstrap PostgreSQL acima:
  `prometheus.template.yml`
  recebe o conteúdo de `compose/prometheus/prometheus.staging.yml` (sem
  segredos); `remote-write-token` recebe somente o token da Access Policy do
  Grafana Cloud com escopo `metrics:write`. O Compose monta ambos em
  `/etc/prometheus/` como read-only. Sincronizar o template com o repo antes de
  redeploy que o altere; token real somente no painel.
- Alvos de scrape: API `10.254.30.10:8081/actuator/prometheus` e Radar
  `10.254.31.30:8082/metrics`, com labels `environment=staging` e `service`;
  `external_labels` `environment=staging`, `cluster=emporio-staging`.
- O Prometheus não é dependência de saúde de nenhum serviço da aplicação
  (sem `depends_on` apontando para ele).
- Validação local deste change set: `docker compose config --quiet` exit 0;
  entrypoint executado na imagem real com valores fictícios + `promtool check
  config` SUCCESS, sem placeholders residuais. A prova de ingestão no Grafana
  Cloud acontece no smoke pós-deploy.

## Redes e exposição

- `apps` é interna: Front ↔ API ↔ cloudflared. Apenas API tem rede interna
  `radar-net` em comum com o Radar.
- `database` é interna e sem portas publicadas: Postgres, jobs DB e API.
- `metrics-net` é interna (subnet `10.254.30.0/24`): somente API (management
  em `10.254.30.10`) e Prometheus (`10.254.30.20`). `radar-metrics-net` é
  interna e separada (subnet `10.254.31.0/24`): somente Radar (métricas em
  `10.254.31.30:8082`) e Prometheus (`10.254.31.20`) — a separação preserva o
  isolamento negativo Radar → Backend:8081, como no dev.
- `api-egress`, `radar-egress`, `tunnel-egress` e `prometheus-egress` são
  bridges separadas, cada uma ligada somente ao serviço que precisa de saída
  externa. Isso evita que o Tunnel ou o Front compartilhem a rede de egress do
  Radar, e dá ao Prometheus saída própria para o remote_write.
- Nenhum serviço declara `ports:`. Actuator 8081 faz bind no IP da
  `metrics-net` dentro do container da API, sem publicação; Postgres 5432 não
  é publicado; Radar 8000 não é publicado e o listener de métricas 8082 fica
  somente na `radar-metrics-net`. A UI do Prometheus escuta em
  `127.0.0.1:9090` dentro do próprio container (healthcheck).
- `radar-net`, `database`, `metrics-net` e `radar-metrics-net` com
  `internal: true` não são promessa de firewall contra o host Docker; o
  Compose só garante ausência de publish e isolamento entre containers fora
  dessas redes.
- O healthcheck do Radar usa `/health/ready` (não apenas liveness), pois API
  e Front dependem do cache CEP íntegro. A sondagem pode executar verificação
  SQLite de conjunto completo; no staging mediu 5,1 s. Por isso, o Compose
  concede até 12 s ao cliente Python, 15 s ao healthcheck Docker e repete a
  cada 30 s, evitando falso `unhealthy` pelo timeout anterior de 2 s.
- O healthcheck da API consulta `/actuator/health`; o Compose habilita o
  contributor de saúde do SMTP e o transporte tem timeouts de até 5 s.
  A sondagem concede até 10 s ao `curl`, 12 s ao healthcheck Docker e repete
  a cada 30 s para não expirar antes do orçamento configurado do SMTP nem
  abrir conexões SMTP excessivas a cada 10 s.

## Limites de recursos aprovados

Decisão do operador (2026-11-13): a VPS de 4 OCPUs/24 GB será dividida meio a
meio entre staging e produção futura — teto de **2 CPU e 12 GiB por stack**,
substituindo o teto inicial de 1,5 CPU/3 GiB. O motivo original (não estrangular
a produção) permanece; o tráfego inicial previsto é baixo.
Os limites atuais do Compose somam no máximo 1,75 CPU e 3.375 GiB nos serviços
long-lived (incluindo o Prometheus de métricas); os jobs bootstrap/migration
rodam antes da API e também têm limites próprios. Limites são tetos, não
reservas: host, Dokploy e daemon Docker também consomem recursos; monitorar a
folga real do host antes de a produção entrar. Não é sizing validado por carga;
TASK-INFRA-021 deve confirmar health/boot/smoke em ARM64 e pedir revisão se
houver OOM ou timeout.

Não existe teste de carga deste stack e o cap de memória do Radar não limita
todas as consultas: o caminho de lookup RFB do DuckDB usa `memory_limit=None`
no código atual. O limite de container contém o processo, mas pode causar OOM
em consulta de dados; observar no smoke antes de considerar o staging saudável.

## Imagens externas fixadas

- PostgreSQL 17 Alpine: manifest multiarch
  `postgres:17-alpine@sha256:e5d2edd28b1f8d40a0a6c0c9cdc545b19b56a0d5d88f94bc11a97d970d4700d0`.
- Cloudflare cloudflared `2026.10.7`: manifest multiarch
  `cloudflare/cloudflared:2026.10.7@sha256:4955524aeaa379e154023d5a027c250f7b35041a2e7e950cf13f144bc9b9c5ba`.
- Digest/tag verificados nos manifests do Docker Hub em 2026-11-12; revisar e
  atualizar em task própria, não usar `latest`.
