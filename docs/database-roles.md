# Roles do PostgreSQL — bootstrap, Compose integrado e smokes

## Escopo atual

`database/bootstrap/roles.sql` é o bootstrap canônico da Infra para identidades
operacionais. Ele cria/reconcilia `emporio_owner` (`NOLOGIN`),
`emporio_migrador` (login com `SET ROLE` restrito ao owner) e `emporio_app`
(login sem membership para owner). O bootstrap não define senhas, grants DML de
domínio ou `ALTER DEFAULT PRIVILEGES`; esses grants pertencem às migrations do
Backend.

O script aplica apenas o que a integração precisa para conectar e criar schemas
/ objetos de migration em `public` enquanto necessário. A permissão e a
transferência de ownership ainda precisam ser validadas no Supabase gerenciado;
o teste local não é evidência dessa validação. **Não aplicar em Supabase/prod**
antes dessa prova e de um plano para os objetos preexistentes.

O arquivo usa metacomandos do `psql` (`\set`/`\gexec`); executá-lo pelo cliente
`psql`, não colar seu conteúdo diretamente no SQL Editor do Supabase.

## Prova local descartável

Execute, sem precisar subir o Compose integrado:

```sh
bash scripts/smoke-db-roles.sh postgres:16-alpine
bash scripts/smoke-db-roles.sh postgres:17-alpine
```

O smoke cria um container PostgreSQL descartável com `tmpfs`, gera credenciais
aleatórias em memória, aplica o bootstrap, introduz membership incorreta e
reaplica para provar reconciliação/idempotência, e valida:

- autenticação válida e rejeição de senha inválida;
- atributos e membership (`SET TRUE`, `INHERIT FALSE`, `ADMIN FALSE`);
- `session_user=emporio_migrador`, `current_user=emporio_owner` e ownership
  efetivo de um objeto de prova;
- negação de `SET ROLE`, `CREATE` e `TRUNCATE` para `emporio_app`;
- acesso humano efêmero de leitura versus manutenção sintética, terminação de
  uma sessão e revogação de logins no banco descartável.

As roles humanas e os grants da fixture são criados somente dentro do smoke;
não definem os privilégios de operadores no Supabase. O container é removido ao
final e não usa volumes nomeados. O script não imprime nem grava valores das
credenciais. Não execute esse smoke apontando para o Compose persistente ou para
Supabase.

## Compose de desenvolvimento integrado — Fase 2

O Compose da Infra integra a sequência `postgres → db-bootstrap → migrate →
backend`. O Postgres dev usa `POSTGRES_ADMIN_USER/PASSWORD`; o serviço one-shot
`db-bootstrap` monta o script acima como read-only e define as senhas das roles
via `psql` stdin. `migrate` chama o runner `migrate` do Backend como
`emporio_migrador`; o serviço longo `backend` conecta apenas como `emporio_app`
com `currentSchema` dos schemas core. Bootstrap e migration precisam terminar
com sucesso antes de a API iniciar.

Para dev local, mantenha valores distintos somente em `env/.env.dev`, que é
ignorado pelo Git: admin Postgres, `SPRING_DATASOURCE_PASSWORD` (app) e
`SPRING_FLYWAY_PASSWORD` (migrador). `.env.dev.example` contém placeholders.
O Backend não recebe a senha administrativa nem a migradora; a senha da role
app não deve aparecer no job `migrate`. Não passe senhas como argumentos nem
imprima a configuração resolvida.

O dev diário constrói uma vez a imagem local `emporio-backend:dev`, compartilhada
por `migrate` e `backend`; não exige atualização manual de SHA. Por padrão, o
contexto é `../Backend_Java`. Para testar outro clone/branch explicitamente,
use `BACKEND_BUILD_CONTEXT=../Backend_Java_Cliente scripts/up-dev.sh` a partir
da raiz da Infra. O launcher imprime caminho, branch, SHA curto e estado
clean/dirty; uma branch de trabalho ou working tree modificada é identificada
como build não canônico, não bloqueada. O modo `--no-build` reutiliza a imagem
local existente.

O volume antigo não é migrado automaticamente. Bootstrap e launcher não
transferem ownership, apagam nem recriam volumes; a adoção greenfield requer a
remoção deliberada pelo operador do volume antigo. Nunca use este bootstrap no
Supabase/prod antes da validação gerenciada e do plano de ownership existente.

## Smokes

`scripts/smoke-db-roles.sh postgres:16-alpine|postgres:17-alpine` continua a
provar roles em banco descartável independente. `scripts/smoke.sh`, após subir
o Compose integrado, também verifica conclusão dos jobs, configuração runtime
sem segredos privilegiados, V10 no histórico Flyway, role/membership/negações e
uma sessão PostgreSQL efetiva de `emporio_app` aberta pelo Backend Java. Esses
smokes locais não validam capacidades administrativas do Supabase gerenciado.

Para exercitar o runner Flyway e uma instância Java runtime sem usar o volume do
Compose integrado, execute `scripts/smoke-db-migration-runner.sh
emporio-backend:dev postgres:16-alpine` e repita com `postgres:17-alpine`. O
smoke usa PostgreSQL descartável em tmpfs, monta o bootstrap read-only, gera
senhas efêmeras e remove containers/rede ao sair; não usa nem remove volumes
Docker. A imagem deve já conter o runner `migrate`.
