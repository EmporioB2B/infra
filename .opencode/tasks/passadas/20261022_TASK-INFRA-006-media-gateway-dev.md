# 20261022 — TASK-INFRA-006 — Media gateway público local para RustFS

**Status:** concluída (change set preparado; commit cabe ao operador)
**Tipo:** implementação de infraestrutura dev + documentação
**Repo alvo:** `infra`
**Origem:** investigação transversal do erro `422` na criação de marca. O
Backend confirmou que manteria a abstração `GestaoArquivos → StorageProvider`
e que a URL pública local deveria ser provida pela infraestrutura.

## Resultado

Foi adicionado ao compose dev um `media-gateway` baseado em
`nginx:1.27.5-alpine`, publicado somente em
`127.0.0.1:${MEDIA_GATEWAY_PORT:-9100}`. O Backend recebe a base sem path:

```text
http://localhost:${MEDIA_GATEWAY_PORT:-9100}
```

O gateway traduz:

```text
/public/... → rustfs:9000/public-local/public/...
```

e aceita somente `GET`, `HEAD` e `OPTIONS` em `/public/`. Raiz, listagem,
privado, quarentena e métodos de escrita são rejeitados. O RustFS continua
publicado localmente para o upload pré-assinado, cujo `Host` precisa continuar
sendo `rustfs:9000`.

## Arquivos do change set

- `compose/docker-compose.dev.yml`
- `compose/media-gateway.nginx.conf`
- `env/.env.dev.example`
- `scripts/smoke.sh`
- `scripts/up-dev.sh`
- `README.md`
- `docs/networks.md`
- `.opencode/context/arquitetura.md`
- `.opencode/context/servicos.md`
- `.opencode/context/estado_atual.md`
- `.opencode/context/decisoes.md`

O código do `Backend_Java` não foi alterado. A correção genérica de semântica
do `503 STORAGE_INDISPONIVEL` e a correção das queries obsoletas de
`produto_imagem.url` permanecem sob responsabilidade do repo Backend.

## Evidências frescas

| Gate | Comando | Resultado |
|---|---|---|
| compose padrão | `docker compose --env-file env/.env.dev -f compose/docker-compose.dev.yml config --quiet` | exit 0 |
| compose com porta alternativa | `MEDIA_GATEWAY_PORT=9191 docker compose --env-file env/.env.dev -f compose/docker-compose.dev.yml config --quiet` | exit 0 |
| configuração Nginx | `docker compose ... run --rm --no-deps media-gateway nginx -t -c /etc/nginx/nginx.conf` | syntax ok; test successful |
| stack | `docker compose ... up -d --wait --wait-timeout 600` | backend, front, postgres, radar, RustFS, Mailpit e gateway healthy; `rustfs-init` exited 0 |
| smoke | `scripts/smoke.sh` | exit 0 em duas execuções finais; objeto público, `HEAD`, CORS, bloqueios 404/405 e policy de quarentena OK |
| shell | `docker run --rm -v "$PWD:/work:ro" koalaman/shellcheck:stable /work/scripts/smoke.sh /work/scripts/up-dev.sh && bash -n scripts/smoke.sh scripts/up-dev.sh` | exit 0 |
| isolamento host | `curl --max-time 3 http://127.0.0.1:8000/health/live` | falha esperada; Radar sem porta publicada |
| isolamento rede | Backend alcança `radar:8000`; `front-dev` não resolve `radar` | positivo/negativo esperados |
| rede interna | `docker network inspect emporio-dev_radar-net` | `Internal=true`; membros somente Backend e Radar |
| bindings | `docker compose ... ps` | publicações somente em `127.0.0.1`; gateway em `127.0.0.1:9100` |
| diff | `git diff --check` | exit 0 |

## Auditoria de contexto

O `context-revisor` auditou e editou somente `.opencode/context/`. As
alterações foram revisadas: arquitetura, catálogo de serviços, decisões e
estado atual agora descrevem o gateway dev e não afirmam mais que a URL pública
local continua bloqueada.

Achados transbordantes arbitrados:

- variáveis obsoletas ainda existentes no `.env.example` e no compose standalone
  do `Backend_Java`: não foram editadas por fronteira de repositório; ficam para
  task do Backend;
- `shellcheck` não disponível no host: resolvido executando a imagem oficial
  em container, com saída limpa;
- o smoke revelou uma fragilidade de pipeline `grep` sob `pipefail`: corrigida
  no próprio script e revalidada duas vezes.

## Limitações

- não houve mudança nem validação contra produção, Cloudflare, R2 real ou
  Dokploy;
- o fluxo completo de criação de marca depende da correção em andamento no
  Backend; a Infra validou a URL pública local e suas restrições de rede.

## Promoção

Task arquivada após os gates acima e auditoria do contexto. O operador deve
revisar o diff, fazer o commit e executar a validação do Backend quando o repo
irmão publicar suas correções.
