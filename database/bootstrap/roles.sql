\set ON_ERROR_STOP on

-- Infra bootstrap: identidades e privilégios operacionais somente.
-- Não define senhas, grants DML de domínio ou ALTER DEFAULT PRIVILEGES.
-- Aplicar conectado ao database da aplicação com uma identidade administrativa.
-- Fase 1: validado somente em containers descartáveis PG16/17; não aplicar em
-- Supabase/prod antes da validação gerenciada e do plano de ownership existente.

SELECT 'CREATE ROLE emporio_owner'
WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'emporio_owner')
\gexec

SELECT 'CREATE ROLE emporio_migrador'
WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'emporio_migrador')
\gexec

SELECT 'CREATE ROLE emporio_app'
WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'emporio_app')
\gexec

ALTER ROLE emporio_owner
  NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

ALTER ROLE emporio_migrador
  LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

ALTER ROLE emporio_app
  LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

-- Só o migrador pode mudar explicitamente sua identidade efetiva para o owner.
-- Privilégios não são herdados e a membership não pode ser repassada.
SELECT 'GRANT emporio_owner TO emporio_migrador WITH ADMIN FALSE, INHERIT FALSE, SET TRUE'
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_catalog.pg_auth_members
  WHERE roleid = 'emporio_owner'::regrole
    AND member = 'emporio_migrador'::regrole
    AND set_option
    AND NOT inherit_option
    AND NOT admin_option
)
\gexec

-- Remove qualquer membership direta indevida no owner, sem produzir erro/aviso
-- em uma instalação greenfield e sem tocar em outras memberships do cluster.
SELECT 'REVOKE emporio_owner FROM emporio_app'
WHERE EXISTS (
  SELECT 1
  FROM pg_catalog.pg_auth_members
  WHERE roleid = 'emporio_owner'::regrole
    AND member = 'emporio_app'::regrole
)
\gexec

-- O owner precisa criar schemas futuros e V1–V9/histórico Flyway ainda podem
-- criar objetos em public. Estes são privilégios operacionais, não ACLs DML.
SELECT format('GRANT CONNECT ON DATABASE %I TO emporio_migrador', current_database())
\gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO emporio_app', current_database())
\gexec
SELECT format('GRANT CREATE ON DATABASE %I TO emporio_owner', current_database())
\gexec
GRANT USAGE, CREATE ON SCHEMA public TO emporio_owner;

-- Runtime não pode criar schemas nem objetos no schema legado public.
SELECT format('REVOKE CREATE ON DATABASE %I FROM emporio_app', current_database())
\gexec
REVOKE CREATE ON SCHEMA public FROM emporio_app;

-- Falha fechada se algum privilégio indireto (por exemplo, via PUBLIC) ainda
-- deixar o runtime criar schemas ou objetos no schema legado.
DO $$
BEGIN
  IF NOT pg_catalog.pg_has_role('emporio_migrador', 'emporio_owner', 'SET') THEN
    RAISE EXCEPTION 'emporio_migrador cannot SET ROLE emporio_owner';
  END IF;
  IF pg_catalog.pg_has_role('emporio_app', 'emporio_owner', 'SET') THEN
    RAISE EXCEPTION 'emporio_app can SET ROLE emporio_owner';
  END IF;
  IF pg_catalog.has_database_privilege('emporio_app', current_database(), 'CREATE')
     OR pg_catalog.has_schema_privilege('emporio_app', 'public', 'CREATE') THEN
    RAISE EXCEPTION 'emporio_app retains CREATE privilege after role bootstrap';
  END IF;
END
$$;
