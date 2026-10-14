# TASK-INFRA-008 — Seed do superusuário admin de testes

**Status:** concluída  
**Tipo:** correção de script / fixture local de autenticação  
**Repo alvo:** `infra`  
**Concluída em:** 2026-10-10

## Resultado

O seed local foi atualizado para o schema atual do `Backend_Java` e passou a
criar um superusuário de teste com:

- usuário ativo e email verificado;
- vínculo ativo na organização `PLATAFORMA`;
- papel `ADMIN_NEGOCIO` com escopo `PLATAFORMA`;
- as nove capacidades administrativas de plataforma:
  `ADMIN_GERENCIAR_CADASTRO`, `ADMIN_GERENCIAR_CATEGORIA`,
  `ADMIN_GERENCIAR_CARACTERISTICA`, `ADMIN_GERENCIAR_MARCA`,
  `ADMIN_GERENCIAR_PRODUTO`, `ADMIN_GERENCIAR_MERCADORIA`,
  `ADMIN_GERENCIAR_OFERTA`, `ADMIN_PUBLICAR_OFERTA` e `GESTAO_ADMIN`.

O seed agora é transacional, valida a identidade dos IDs fixos e permanece
idempotente. A senha não é versionada nem impressa: é fornecida por
`ADMIN_DEV_PASSWORD` no ambiente local ignorado, documentado em
`env/.env.dev.example`.

## Arquivos alterados

- `scripts/seed-admin-dev.sh`
- `env/.env.dev.example`
- `README.md`
- `.opencode/context/estado_atual.md` — atualizado pelo
  `context-revisor` e complementado para registrar a senha local não
  versionada.

## Evidências frescas

- `bash -n scripts/seed-admin-dev.sh` — exit 0.
- `docker compose --env-file env/.env.dev -f compose/docker-compose.dev.yml config --quiet` — exit 0.
- `ADMIN_DEV_PASSWORD=... scripts/up-dev.sh --no-build` — stack concluída; todos os serviços long-lived ficaram healthy e o seed terminou com sucesso.
- Execução do seed duas vezes — primeira inseriu nove capacidades; segunda não inseriu papel nem capacidades (`INSERT 0 0`) e confirmou nove capacidades ativas.
- Consulta PostgreSQL — vínculo, timestamps obrigatórios e papel retornaram válidos; capacidades ativas retornaram exatamente as nove esperadas.
- Login `POST /api/v1/auth/login` com `Origin: http://localhost:4200` — HTTP 200; resposta/tokens não foram impressos.
- `scripts/smoke.sh` — exit 0, incluindo health da API, Radar interno, RustFS, CORS e isolamento dos buckets.
- `docker network inspect emporio-dev_radar-net` — `internal=true`, dois containers.
- `git diff --check` — exit 0.
- `git check-ignore -v env/.env.dev .opencode/tasks/task_atual.md` — ambos ignorados pelas regras esperadas.

## Limitações

- `shellcheck` não está instalado no ambiente desta execução.
- O login exige `Origin` permitido pelo `AuthOriginFilter`; o teste foi feito
  com a origem do Front dev.
- Os testes Maven do Backend usam Testcontainers; esta task não altera as
  fixtures nem o código do repositório irmão.
