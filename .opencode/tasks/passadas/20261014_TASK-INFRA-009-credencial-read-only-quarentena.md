# 20261014 — TASK-INFRA-009 — credencial read-only da quarentena

**Status:** concluída (arquivo imutável)
**Tipo:** implementação de artefatos deste repo
**Origem:** solicitação do operador + change set `543b552` do `Backend_Java`
**Execução:** 2026-10-14, sem deploy ou alteração de produção

## Objetivo

Preparar a leitura autorizada de documentos em quarentena no Backend sem
reutilizar as credenciais read-write/read-only existentes.

## Fatos confirmados

O Backend consome exatamente:

- `APP_STORAGE_READ_ONLY_QUARENTENA_R2_ENDPOINT`;
- `APP_STORAGE_READ_ONLY_QUARENTENA_R2_ACCESS_KEY_ID`;
- `APP_STORAGE_READ_ONLY_QUARENTENA_R2_SECRET_ACCESS_KEY`.

No dev, o Compose fornece esses valores a partir de:

- `RUSTFS_READ_ONLY_QUARANTINE_ACCESS_KEY`;
- `RUSTFS_READ_ONLY_QUARANTINE_SECRET_KEY`.

O prefixo efetivo é `quarantine/`; o namespace público é fixo em `public/`
no código do Backend, portanto `APP_STORAGE_R2_PUBLICO_PREFIX` foi removida
do Compose.

## Artefatos

- `compose/docker-compose.dev.yml` — wiring das três variáveis do Backend e
  das duas credenciais novas; remoção de env público não consumido.
- `env/.env.dev.example` — placeholders das credenciais dedicadas.
- `scripts/init-rustfs.sh` — validação de formato/placeholders, colisões,
  policy idempotente e usuário dedicado com somente
  `s3:GetObject` em
  `arn:aws:s3:::quarantine-local/quarantine/*`.
- `scripts/smoke.sh` — validação de CORS `GET`/`HEAD` nas três origens dev e
  testes efetivos de leitura, listagem, escrita, deleção, prefixo externo e
  bucket privado para a credencial dedicada.
- `README.md`, `docs/networks.md` e `docs/storage-r2-handoff.md` — setup,
  topologia, exceção pública dev-only e handoff da policy equivalente para R2.
- `.opencode/context/{arquitetura,servicos,estado_atual}.md` — fatos atuais,
  limites de produção e evidência da validação.

## Evidências

| Gate | Comando/observação | Resultado |
|---|---|---|
| Compose com env real | `docker compose --env-file env/.env.dev -f compose/docker-compose.dev.yml config --quiet` | exit 0 |
| Stack | `scripts/up-dev.sh --no-build` | todos os serviços long-running healthy; `rustfs-init` exit 0 |
| Smoke | `scripts/smoke.sh` | exit 0; health, buckets, anonimato, CORS e policy dedicada OK |
| Idempotência | `docker compose ... run --rm rustfs-init` após o stack | exit 0; policy e CORS recriados sem erro |
| Policy isolada | RustFS efêmero + credencial dedicada | `GetObject` permitido; listagem, `PutObject`, `DeleteObject`, prefixo externo, privado e público com anonimato desativado negados |
| Isolamento | host→Radar e container default→Radar | falharam como esperado; backend→Radar passou |
| Rede | `docker network inspect emporio-dev_radar-net` | `internal=true`, membros somente backend/radar |
| Portas | `docker ps` | bindings publicados em `127.0.0.1`; Radar sem porta |
| CORS | preflight RustFS | `GET`/`HEAD` passaram nas 3 origens dev |
| Shell | ShellCheck em `init-rustfs.sh`, `smoke.sh`, `up-dev.sh` + `bash -n` | exit 0 |
| Higiene | `git check-ignore`, `git diff --check`, revisão do diff | env real ignorado; diff limpo; nenhum segredo no change set |
| Auditoria | `context-revisor` | contexto corrigido e revisão do achado médio arbitrada; smoke ampliado para policy |

## Limites

- O `.env` real do `Backend_Java` e o `.env.dev` real não foram abertos,
  impressos, copiados nem versionados; foram apenas consumidos pelos gates.
- O handoff R2 é documental. Nenhuma API do Cloudflare, R2, Dokploy ou VPS
  foi acionada.
- A leitura anônima do bucket público no dev permanece uma regra separada;
  a credencial dedicada não recebe recursos desse bucket na policy.
