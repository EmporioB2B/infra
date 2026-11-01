# Roles do PostgreSQL — bootstrap e smoke da Fase 1

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

O smoke cria um container PostgreSQL descartável com `tmpfs`, aplica o
bootstrap duas vezes, gera credenciais aleatórias em memória e valida:

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

## Estado de integração

Esta é somente a Fase 1. O Compose integrado ainda usa a configuração de
datasource atual do Backend; não injeta `emporio_app` nem inicia um runner Flyway
separado. Essa integração depende do runner que o Backend implementará e de uma
fase posterior. O smoke desta fase prova autenticação e privilégios PostgreSQL,
não que o processo Java já esteja conectado como `emporio_app`.

Não reutilize credenciais de teste em dev persistente ou produção. Valores reais
não pertencem a este documento, ao bootstrap SQL ou ao repositório; dev local
usa somente `env/.env.dev` ignorado e produção dependerá do mecanismo operacional
aprovado para o projeto Supabase.
