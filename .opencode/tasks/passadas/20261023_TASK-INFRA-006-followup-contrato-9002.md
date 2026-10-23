# 20261023 — TASK-INFRA-006 follow-up — contrato público `/public/asset`

**Status:** concluída (change set preparado; commit cabe ao operador)
**Tipo:** alinhamento final de infraestrutura dev + verificação transversal
**Repo alvo:** `infra`
**Origem:** contrato final publicado pelo `Backend_Java` no commit `8cc8fb6`
(`fix(storage): align RustFS public media URL with gateway`).

## Alteração aplicada

O gateway local foi alinhado ao contrato efetivo do Backend:

```text
Browser: http://localhost:9002/public/asset/<sha256>
Gateway: nginx:80, health /healthz
RustFS:  http://rustfs:9000/public-local/public/asset/<sha256>
```

O compose dev agora usa, por default:

```text
APP_STORAGE_R2_PUBLICO_BASE_URL=http://localhost:9002
```

O gateway aceita somente `GET`/`HEAD` em `/public/asset/`. Raiz, paths sem
`asset`, bucket exposto, privado, quarentena e métodos de escrita são
rejeitados. Produção continua planejada com
`https://media.emporiob2b.com.br`, sem gateway na VPS.

## Arquivos ajustados

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

Nenhum código ou arquivo do `Backend_Java` foi alterado. O override standalone
do Backend ainda contém a variável inerte `APP_STORAGE_R2_PUBLICO_PREFIX` e usa
um gateway próprio com tag diferente; ambos foram registrados pelo
`context-revisor` como transbordamentos fora da fronteira desta task.

## Evidências frescas

| Gate | Comando/observação | Resultado |
|---|---|---|
| compose | `docker compose --env-file env/.env.dev -f compose/docker-compose.dev.yml config --quiet` | exit 0 |
| porta alternativa | `MEDIA_GATEWAY_PORT=9003 ... config --quiet` | exit 0 |
| Nginx | `... run --rm --no-deps media-gateway nginx -t` | syntax ok; test successful |
| build/stack | `up -d --build --wait` e nova espera `up -d --wait` após timeout do wrapper | imagens Back/Front/Radar construídas; todos os serviços healthy em `docker compose ps` |
| infra smoke | `scripts/smoke.sh` | exit 0; gateway 9002, GET/HEAD, 404/405, RustFS policy e CORS do upload OK |
| Backend storage | `./mvnw -B failsafe:integration-test -Dit.test=RustFsStorageIT` | BUILD SUCCESS; 6 testes, 0 falhas |
| Backend catálogo/logo | `./mvnw -B failsafe:integration-test -Dit.test='CatalogoControllerIT,MarcaLogoUploadIT'` | BUILD SUCCESS; 31 testes, 0 falhas |
| API real dev | `curl` em `:8080` e via proxy `:4200` para `/api/v1/catalogo/destaques` | HTTP 200 `{"marcas":[],"produtos":[]}` |
| URL pública negativa | GET direto em `/public-local/...` no gateway | HTTP 404; bucket não exposto |
| isolamento | host não alcança `:8000`; Backend alcança Radar; Front não resolve Radar | esperado |
| rede | `docker network inspect emporio-dev_radar-net` | `Internal=true`; somente Backend e Radar |
| scripts | ShellCheck em container + `bash -n` | exit 0 |
| diff | `git diff --check` | exit 0 |

## Limitações explícitas

- A suíte integral `./mvnw -B verify` do Backend não foi concluída nesta
  sessão: a execução iniciou o Surefire completo e ultrapassou o limite de
  120s da ferramenta. As duas suítes de integração focadas acima passaram.
- Não houve operação contra produção, Cloudflare, R2 real ou Dokploy.

## Auditoria de contexto

O `context-revisor` confirmou o contrato final do Backend e atualizou somente
`.opencode/context/`. Os achados médios sobre o override standalone do Backend
e a duplicação de gateways foram arbitrados como fora do escopo desta task;
nenhum código irmão foi tocado.

## Commit sugerido

```text
fix(infra): align RustFS media gateway with public asset contract
```
