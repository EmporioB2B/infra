# Emporio B2B — Infraestrutura

Este repositório contém o Compose de desenvolvimento integrado e a
infraestrutura compartilhada do Emporio B2B. O stack local inclui Backend,
Frontend, Radar, PostgreSQL, RustFS, media-gateway, Mailpit e observabilidade
local com Vector, Loki, Prometheus e Grafana.

## Subir o ambiente local

Os repositórios `infra`, `Backend_Java`, `Front_Angular` e
`Radar_Middleware_Python` precisam estar clonados lado a lado. Antes da
primeira subida:

1. Copie `env/.env.dev.example` para `env/.env.dev` e preencha os valores
   locais exigidos, incluindo a senha da UI do Grafana e o par dedicado
   `RUSTFS_READ_ONLY_QUARANTINE_{ACCESS_KEY,SECRET_KEY}`. Não versione o
   arquivo real.
2. Garanta que `Radar_Middleware_Python/.env` esteja configurado localmente;
   ele contém as credenciais do R2 de teste e não deve ser copiado para este
   repositório.
3. Em `env/.env.dev`, defina também `ADMIN_DEV_PASSWORD` com uma senha
   exclusiva para o admin local. O valor é usado somente pelo seed ignorado e
   nunca é impresso ou versionado.
4. Execute na raiz deste repositório:

   ```bash
   scripts/up-dev.sh
   ```

   Use `scripts/up-dev.sh --no-build` quando as imagens locais já estiverem
   atualizadas. O launcher verifica a configuração, inicia o RustFS e aguarda
   os serviços ficarem saudáveis. Para verificar o ambiente, execute
   `scripts/smoke.sh`.

### Fotos públicas no navegador

O Backend usa `http://localhost:9002` (porta padrão, configurável por
`MEDIA_GATEWAY_PORT`) como base pública de mídia no dev. O
`media-gateway` publica somente `/public/asset/...` e encaminha a leitura
para `public-local/public/asset/...` no RustFS. Não use
`http://localhost:9000/public-local` como `APP_STORAGE_R2_PUBLICO_BASE_URL`:
essa URL contém o path do bucket e é rejeitada pela validação do Backend.

O acesso direto ao RustFS em `:9000` continua necessário somente para o upload
pré-assinado; siga a configuração de `hosts` abaixo para que o navegador
resolva o hostname `rustfs` assinado pelo Backend.

## Obrigatório para upload direto do navegador ao RustFS

O Backend cria uma URL pré-assinada de upload cujo hostname é
`rustfs:9000`. Esse hostname faz parte da assinatura SigV4: o navegador deve
resolver `rustfs` para o RustFS local e preservar esse hostname na requisição.
O DNS interno do Docker só é conhecido pelos containers; o navegador no host
não recebe essa resolução automaticamente.

No arquivo `hosts` **do sistema onde o navegador está rodando**, adicione:

```text
127.0.0.1 rustfs
```

| Navegador executado em | Arquivo `hosts` |
|---|---|
| Linux ou navegador dentro do WSL | `/etc/hosts` |
| Windows (inclusive navegador no host com Docker/WSL2) | `C:\Windows\System32\drivers\etc\hosts` |
| macOS | `/etc/hosts` |

Edite o arquivo com as permissões administrativas necessárias. O Compose
publica o RustFS somente em `127.0.0.1:9000`, então esse mapeamento aponta
para o serviço local sem expô-lo à rede LAN.

### Confirmar a resolução

No Linux/WSL:

```bash
getent hosts rustfs
curl -fsS http://rustfs:9000/health
```

No macOS:

```bash
dscacheutil -q host -a name rustfs
curl -fsS http://rustfs:9000/health
```

No Windows PowerShell:

```powershell
Resolve-DnsName rustfs
curl.exe -fsS http://rustfs:9000/health
```

A resolução deve apontar para `127.0.0.1` e o healthcheck HTTP deve responder.
Se o navegador ainda não resolver o nome após editar `hosts`, feche e abra o
navegador para limpar uma possível resolução em cache.

Sem esse mapeamento, o PUT do navegador falha normalmente com
`ERR_NAME_NOT_RESOLVED`; a confirmação do upload também pode falhar porque o
objeto nunca chegou ao RustFS. **Não substitua `rustfs` por `localhost` na URL
pré-assinada**: isso altera o `Host` assinado e invalida a assinatura.
`scripts/smoke.sh` usa uma resolução forçada própria para seus testes e, por
isso, um smoke verde não prova que o navegador do host possui este mapeamento.

Este requisito é somente para o Compose local de desenvolvimento. Consulte
[`docs/networks.md`](docs/networks.md) para detalhes das redes e do upload
direto.

## Observabilidade no Grafana local

O bootstrap já sobe a observabilidade local e imprime a URL da UI:

```text
http://127.0.0.1:3000
```

O login usa `GRAFANA_ADMIN_USER`/`GRAFANA_ADMIN_PASSWORD` do env local. Os
datasources Loki e Prometheus já vêm provisionados; consulte
[`docs/observability.md`](docs/observability.md) para as queries e para o
procedimento de produção via Grafana Cloud/Dokploy.
