# Compose de staging — operação e limites

O stack versionado está em `compose/docker-compose.staging.yml`, com projeto
Compose estável `emporio-staging`. O YAML é fonte de topologia, não evidência de
deploy: não houve configuração no painel Dokploy, Cloudflare, R2 ou SMTP.

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
  TASK-INFRA-003 e o build da imagem Front com perfil staging são gates antes do
  primeiro deploy. O Dockerfile atual ainda chama `build:production`; a
  configuração `staging` do Angular precisa ser selecionada pela imagem do repo
  dono antes de promover o Front para o GHCR.

## Bootstrap PostgreSQL

`db-bootstrap` aplica o SQL canônico da Infra e o job `migrate` executa o runner
Flyway da imagem Back; a API só inicia depois de migração bem-sucedida. Como o
Dokploy limpa/recria o checkout em deploy, não bind-montar arquivo do clone.
Antes do deploy, cadastrar em **Advanced → Mounts → File Mounts** do serviço
Compose um arquivo com conteúdo atual de
`database/bootstrap/roles.sql`, destino exato `/bootstrap/roles.sql`, somente
leitura se o painel oferecer essa opção. O job falhará fechado se o arquivo não
estiver presente. Em atualizações futuras, sincronizar/revisar o File Mount com
o SQL canônico antes do redeploy; este change set não opera o painel.

O volume `emporio-staging_pgdata` é persistente e não deve ser removido por
`down -v` ou operação equivalente. A política operacional de backup e retenção
de dados do staging precisa ser definida antes do deploy.
O Compose não impõe quota de disco ao named volume; monitoramento e limite de
armazenamento no host/daemon são follow-up operacional, não foram configurados.

O healthcheck do Front usa `http://localhost:4000/`; a allowlist SSR compilada
na imagem precisa preservar `localhost` junto ao hostname público de staging.

## Redes e exposição

- `apps` é interna: Front ↔ API ↔ cloudflared. Apenas API tem rede interna
  `radar-net` em comum com o Radar.
- `database` é interna e sem portas publicadas: Postgres, jobs DB e API.
- `api-egress`, `radar-egress` e `tunnel-egress` são bridges separadas, cada uma
  ligada somente ao serviço que precisa de saída externa. Isso evita que o
  Tunnel ou o Front compartilhem a rede de egress do Radar.
- Nenhum serviço declara `ports:`. Actuator 8081 fica no loopback do container
  da API; Postgres 5432 não é publicado; Radar 8000/8082 não é publicado.
- `radar-net` e `database` com `internal: true` não são promessa de firewall
  contra o host Docker; o Compose só garante ausência de publish e isolamento
  entre containers fora dessas redes.

## Limites de recursos aprovados

O operador aprovou teto inicial agregado **por stack** de 1,5 CPU e 3 GiB de
RAM, para preservar espaço para produção futura na VPS de 4 OCPUs/24 GB. Os
limites do Compose somam no máximo 1,5 CPU e 2.875 GiB nos serviços long-lived;
os jobs bootstrap/migration rodam antes da API e também têm limites próprios.
Isso é um teto inicial, não sizing validado por carga; TASK-INFRA-021 deve
confirmar health/boot/smoke em ARM64 e pedir revisão se houver OOM ou timeout.

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
