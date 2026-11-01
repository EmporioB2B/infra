# TASK-INFRA-016 — Roles DB bootstrap e smoke isolado (Fase 1)

**Status:** concluída — 2026-11-01.
**Escopo:** artefatos da Infra para provisionar e testar roles em PostgreSQL
descartável. Sem integração do runner Flyway do Backend ao Compose.

## Entregas

- `database/bootstrap/roles.sql`: bootstrap idempotente de
  `emporio_owner` (`NOLOGIN`), `emporio_migrador` e `emporio_app` (`LOGIN`),
  membership com `SET TRUE`, `INHERIT FALSE`, `ADMIN FALSE`, privilégios
  operacionais mínimos e pós-condições que falham se runtime puder assumir owner
  ou executar `CREATE` no database/schema `public`. Sem senhas ou grants DML de
  domínio.
- `scripts/smoke-db-roles.sh`: teste em containers descartáveis `tmpfs`, com
  senhas aleatórias em memória. Verifica autenticação válida/inválida,
  membership, ownership real após `SET ROLE`, negações de runtime, acesso
  humano sintético de leitura/manutenção e terminação/revogação de sessão.
- `docs/database-roles.md`: uso e limites da Fase 1; explicita que bootstrap é
  psql, não deve ser aplicado em produção antes de validação Supabase, e que o
  Compose/Backend ainda não usa essas roles.
- Contextos factuais atualizados por auditoria do `context-revisor` e revisão do
  arquiteto: `.opencode/context/{indice,arquitetura,servicos,decisoes,estado_atual}.md`.

## Evidências

| Comando | Resultado |
|---|---|
| `./scripts/smoke-db-roles.sh postgres:16-alpine` | exit 0; todos os checks de role, login, ownership, runtime e fixture humana passaram. |
| `./scripts/smoke-db-roles.sh postgres:17-alpine` | exit 0; mesmos checks passaram. |
| `docker run --rm -v "$PWD/scripts:/mnt:ro" koalaman/shellcheck:stable /mnt/smoke-db-roles.sh` | exit 0; sem avisos. |
| `bash -n scripts/smoke-db-roles.sh` | exit 0. |
| `git diff --check` e `git diff --no-index --check` dos arquivos novos | sem erros de whitespace. |
| `git check-ignore -v env/.env.dev` | `.env.dev` coberto por `.gitignore`; não lido nem exibido. |

Nenhuma credencial foi impressa; o smoke confirmou autenticação errada negada
sem exibir valores. Containers de teste foram removidos ao encerrar e não
usaram volumes nomeados.

## Limites e dependências remanescentes

- O teste local não prova privilégios, ownership ou capacidade administrativa no
  Supabase gerenciado PostgreSQL 17.
- O Compose integrado ainda usa a identidade atual `emporio`; não injeta
  `emporio_app` e não executa runner Flyway separado. O acesso do processo Java
  como `emporio_app` depende da futura integração com o runner do Backend.
- Não foram alterados arquivos do Backend nem do Compose integrado; não houve
  operação no Supabase/prod nem remoção de volumes.
- A tag de deploy SHA/digest foi decidida pelo operador; a automação de CI e
  release fica para task posterior. `:latest` pode continuar publicado, mas não
  será seletor de release.

## Auditoria do contexto

O `context-revisor` atualizou somente `context/`. O arquiteto revisou o diff e
ajustou a documentação para distinguir o seletor SHA decidido da publicação
opcional da tag `:latest`. Nenhum achado MÉDIO+ ficou sem arbitragem dentro do
escopo da Fase 1.
