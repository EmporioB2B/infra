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

O datasource `Emporio Loki` é provisionado automaticamente. No Grafana,
abra **Explore** e consulte, por exemplo:

```logql
{environment="dev"}
{environment="dev", container=~".*backend.*"}
```

As portas `GRAFANA_PORT` e `VECTOR_FLUENTD_PORT` podem ser alteradas no env
local se houver conflito. Loki não é publicado no host; é acessado por
Grafana e Vector na rede `observability`.

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
