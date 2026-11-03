# TASK-INFRA-017 — Integração DB roles no Compose dev (Fase 2)

**Status:** concluída — 2026-11-03.
**Escopo:** integração local do bootstrap canônico, runner one-shot Flyway e
runtime `emporio_app` no Compose dev da Infra. Sem CI/release ou acesso ao
Supabase gerenciado.

## Entregas

- `compose/docker-compose.dev.yml`: Postgres dev inicia com usuário admin
  distinto; `db-bootstrap` monta `database/bootstrap/roles.sql` read-only,
  confere que as três senhas são não vazias/distintas e as define via `psql`
  stdin; `migrate` executa `migrate` com as três `SPRING_FLYWAY_*`; `backend`
  depende da migration, usa `emporio_app`, `currentSchema` core e Flyway
  desabilitado no boot. `backend`/`migrate` compartilham `emporio-backend:dev`.
- `env/.env.dev.example`: placeholders para `POSTGRES_ADMIN_USER`,
  `POSTGRES_ADMIN_PASSWORD`, `SPRING_DATASOURCE_PASSWORD` e
  `SPRING_FLYWAY_PASSWORD`; somente `env/.env.dev` local guarda valores reais.
- `scripts/up-dev.sh`: constrói uma vez o Backend e executa a cadeia. Exibe
  caminho/branch/SHA/dirty status e classifica checkout de trabalho sem
  bloquear o dev diário; `--no-build` alerta que a referência reportada descreve
  o checkout, não a proveniência da imagem.
- `scripts/seed-admin-dev.sh`: seed conecta pela identidade administrativa e
  seleciona o schema `identidade`.
- `scripts/smoke.sh`: verifica jobs, V10, identidade e credenciais do runtime,
  imagem compartilhada, negações de privilégio e sessão Java efetiva como
  `emporio_app`, além dos checks existentes do stack.
- `scripts/smoke-db-migration-runner.sh`: smoke autocontido em Postgres 16/17
  descartável, credenciais efêmeras, tmpfs e sem volumes nomeados; prova
  bootstrap, V1–V10, health da API e restrições do runtime.
- README, `docs/database-roles.md`, skills de Compose/secrets e contextos
  factuais atualizados. TASK-INFRA-003 futura alinhada à decisão de deploy
  imutável SHA/digest; `:latest` somente alias opcional.

## Evidências

| Verificação | Resultado |
|---|---|
| `docker compose --env-file env/.env.dev.example -f compose/docker-compose.dev.yml config --quiet` | exit 0; placeholders e Compose renderizam sem mostrar configuração. |
| `./scripts/smoke-db-roles.sh postgres:16-alpine` | exit 0; autenticação, reconciliação de membership, owner, runtime e acesso humano sintético. |
| `./scripts/smoke-db-roles.sh postgres:17-alpine` | exit 0; mesmos checks em PG17. |
| `./scripts/smoke-db-migration-runner.sh emporio-backend:dev postgres:16-alpine` | exit 0; V1–V10, Java healthy, sessão app e negações. |
| `./scripts/smoke-db-migration-runner.sh emporio-backend:dev postgres:17-alpine` | exit 0; mesmos checks em PG17. |
| `BACKEND_BUILD_CONTEXT=../Backend_Java_Cliente scripts/up-dev.sh` | execução reportada pelo operador: source `dev/cliente`, SHA `bf99658885e9`, dirty com 5 entradas; jobs concluíram e serviços ficaram healthy. Build identificado como não canônico. |
| `scripts/smoke.sh` | exit 0; checks DB-08, serviço Java, redes, Radar, RustFS, CORS e observabilidade passaram. HTTP RED foi SKIP esperado na primeira execução sem tráfego e passou na execução final com tráfego `/api`. |
| `bash -n` nos scripts tocados e ShellCheck via container | exit 0; sem erros/avisos. |
| `git diff --check` e arquivos novos via `git diff --no-index --check` | sem whitespace inválido. |
| `git check-ignore -v env/.env.dev` | `.env.dev` ignorado; nomes foram conferidos sem ler/imprimir valores. |

## Volumes e segurança

- Nenhum volume foi removido, resetado ou migrado pelo agente. Na execução
  integrada, o Compose criou `emporio-dev_pgdata_v2`; os volumes legados
  `emporio-dev_pgdata` e `emporio-dev_radar_state` foram avisados pelo Compose
  e ficaram intocados. A saída do `up-dev.sh` mostra `emporio-dev_pgdata_v2`
  como volume criado nessa execução.
- Um Compose diagnóstico isolado criou o volume
  `emporio-db-phase2-smoke_rustfs-data` ao resolver recursos não usados após uma
  tentativa de execução de serviço que falhou por redes sobrepostas. Nenhum
  serviço de dados desse projeto iniciou; o volume foi mantido sem remoção
  automática por política.
- Nenhuma senha real foi impressa, commitada ou inspecionada. Nenhuma operação
  ocorreu no Supabase/prod. Não houve mutação Git.

## Limitações e próximos gates

- A execução integrada usou explicitamente o clone de trabalho
  `Backend_Java_Cliente`, não o clone canônico `../Backend_Java` em `main`.
  Revalidar pelo default depois do merge do runner em `Backend_Java`.
- PG16/17 foram containers locais descartáveis; permissões, ownership de objetos
  preexistentes e conectividade precisam ser comprovados no Supabase gerenciado
  antes de qualquer prontidão de produção.
- CI/release com SHA/digest, migration out-of-band e Dokploy pertence a task
  posterior; TASK-INFRA-003 foi corrigida em planejamento, não implementada.

## Auditoria de contexto

`context-revisor` atualizou `estado_atual.md`, `servicos.md` e `arquitetura.md`
com as evidências do stack e seus limites. O arquiteto revisou e corrigiu
`servicos.md` (descrição do owner e formatação) e alinhou a referência de linhas
do bootstrap. Sem achado MÉDIO+ pendente dentro do escopo desta fase.
