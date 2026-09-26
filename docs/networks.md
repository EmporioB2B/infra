# Redes e isolamento — stack de desenvolvimento

O compose de dev (`compose/docker-compose.dev.yml`) usa **a mesma topologia
de redes da produção** (ver `../.opencode/context/arquitetura.md`), com
emuladores no lugar dos serviços externos e sem cloudflared.

```text
                         ┌───────────────────────────────────────────┐
 host (navegador)        │  só 127.0.0.1 — nada exposto na LAN       │
   :4200 front-dev ──────┤                                           │
   :8080/:8081 backend ──┤   default (bridge)                        │
   :9000/:9001 rustfs ───┤     front-dev ↔ backend ↔ postgres        │
   :8025 mailpit (UI) ───┤     backend ↔ rustfs, mailpit             │
                         │                                           │
                         │   egress (bridge)  ── internet:           │
                         │     radar → R2 de teste / ViaCEP          │
                         └───────────────────────────────────────────┘

   radar-net (bridge, internal: true)   ← zona de contenção
     backend ──http://radar:8000── radar        (SEM portas no host)
```

## Regras

| Rede | Tipo | Membros | Regra |
|---|---|---|---|
| `default` | bridge | front-dev, backend, postgres, rustfs, mailpit | tráfego interno do stack; toda publicação no host é prefixada `127.0.0.1` |
| `radar-net` | bridge **`internal: true`** | backend, radar | única via para a API privada do Radar; sem gateway — nada entra/sai dela pelo host nem por outras redes |
| `egress` | bridge | radar | saída controlada para o R2 de teste real e ViaCEP |

- **Radar nunca publica porta** (`ports:` ausente em qualquer compose, dev
  ou prod) e só é alcançado por containers na `radar-net`. Enquanto o Radar
  não tem autenticação serviço-a-serviço (mTLS é task futura nos repos
  irmãos), esse isolamento é a mitigação estrutural.
- Um serviço em rede `internal` + `egress` alcança a internet **somente**
  pela `egress` — comportamento documentado do Docker, esperado aqui.
- O serviço da api chama-se **`backend`** em dev (e `api` em produção) de
  propósito: `proxy.conf.json` do Front aponta para `http://backend:8080`.
- A porta de management do Back (**8081**) é publicada em dev somente em
  `127.0.0.1` para diagnóstico; em produção **nunca** é roteada pelo túnel.
- SMTP do Back → `mailpit:1025` fica na `default` (não publicada). A caixa
  de entrada local é auditada na UI `http://localhost:8025`.
- RustFS (`:9000`) emula o R2 do Back — inclusive o bucket **público de
  fotos**, que no dev exige leitura anônima (política aplicada pelo
  `rustfs-init`, desvio documentado no YAML; em produção o público é
  servido pela borda `media.emporiob2b.com.br`). O Radar **não** usa o
  RustFS: ele valida `https://<account>.r2.cloudflarestorage.com` e usa o
  bucket R2 de teste real via `env_file` do `.env` local do repo Radar.
- A URL pública de foto gerada pelo Back (`publicUrl = base + key`) **não é
  utilizável pelo navegador contra o RustFS**: a validação do Back proíbe
  path na base e o RustFS não resolve vhost (evidências de 2026-09-26 no
  comentário do compose). O dev roda com
  `APP_STORAGE_R2_PUBLICO_BASE_URL` vazio e o bucket público é verificado
  pelo `smoke.sh` em path-style direto (`http://localhost:9000/public-local/…`).
  A lacuna do navegador está registrada como **TASK-INFRA-006**
  (repo Backend_Java).

## Direct-upload no dev (navegador → RustFS)

O Back assina URLs pré-assinadas de upload com o **Host embutido na
assinatura SigV4** — o navegador tem que resolver exatamente o hostname do
endpoint (`rustfs:9000`). O `StorageProperties.isLocalHost` do Back tem
allowlist hardcoded para HTTP: somente `rustfs`, `localhost`, `127.0.0.1`
e `::1` (`rustfs.localhost` é rejeitado no binding — evidência 2026-09-26;
relacionado à TASK-006). O compose publica `127.0.0.1:9000`, então falta
apenas o navegador conhecer o nome `rustfs`:

| Onde roda o navegador | Arquivo (editar como admin/root) | Linha a adicionar |
|---|---|---|
| Windows (browser do host, WSL2 embaixo) | `C:\Windows\System32\drivers\etc\hosts` | `127.0.0.1 rustfs` |
| Linux direto / navegador dentro do WSL | `/etc/hosts` | `127.0.0.1 rustfs` |

Sem a entrada: o PUT falha com `net::ERR_NAME_NOT_RESOLVED` e o
`/confirmar` devolve 422 (observado em 2026-09-26). Com a entrada, o fluxo
fecha: preflight OPTIONS → 200 com ACAO; PUT pré-assinado → 200; confirmar
→ 202/OK. O CORS dos três buckets é aplicado pelo `rustfs-init`
(origens `http://localhost:4200`, `http://localhost:4000`,
`http://127.0.0.1:4200`; `AllowedHeader *` — o wildcard parcial `x-amz-*`
**não** é suportado pelo RustFS e devolve 403 no preflight, evidência de
mesma data). O `scripts/smoke.sh` cobra o preflight (check 10) já
resolvendo `rustfs` via `--resolve`, independente do hosts do navegador.

## Perfil `prodlike` (front-prod) — bloqueado

A imagem SSR de produção do Front (serviço `front-prod`, perfil
`prodlike`, `127.0.0.1:4000`) ainda **não pode ser criada**: conferido em
2026-09-26, o repo `Front_Angular` mantém `security.allowedHosts`
compilado como `["localhost"]` (`angular.json`) e o `Dockerfile` não expõe
ARGs para `apiBaseUrl`/`imageBaseUrl` (hoje vazios no bundle de produção).
Pré-requisitos na **TASK-INFRA-002**; ao concluir, adicionar o serviço e
atualizar este doc. Até lá o E2E manual percorre os fluxos com o
`front-dev` (proxy interno para `backend:8080`).

## Testes de isolamento (executar após `up`)

```bash
# do host: radar é inalcançável (porta 8000 não publicada)
curl -m 3 http://127.0.0.1:8000/health/live   # deve FALHAR (connection refused)

# da radar-net: backend alcança o radar
docker compose --env-file env/.env.dev -f compose/docker-compose.dev.yml \
  exec backend curl -fsS http://radar:8000/health/live                 # deve PASSAR

# fora da radar-net: containers da `default` não veem o radar
docker compose --env-file env/.env.dev -f compose/docker-compose.dev.yml \
  exec mailpit sh -c 'wget -q -T 3 -O /dev/null http://radar:8000/ || exit 1'  # deve FALHAR

# a rede é interna de fato
docker network inspect emporio-dev_radar-net \
  --format '{{json .Inspect.Options.Internal}}'                        # true
```
