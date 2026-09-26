---
name: secrets-env
description: Use when defining, reviewing or rotating any environment variable, secret, token or credential across compose files, GitHub Actions, Dokploy and Cloudflare for Emporio B2B.
---

# Envs e segredos

Um segredo vazado exige rotação imediata e não pode ser "desvazado". Esta
skill cobre o ciclo completo: onde cada valor vive, como entra no runtime,
como se valida e como se rotaciona. Fontes: hardening oficial de GitHub
Actions, Production Hardening Guide do Dokploy, práticas 12-factor
(config no ambiente, não no código).

## Camadas de configuração (onde cada valor vive)

| Camada | Onde | O que contém |
|---|---|---|
| Versionado | `env/*.example`, compose (`${VAR}`) | nomes, defaults seguros, placeholders |
| Dev local | `.env` local (ignorado), `.env` do repo Radar (ignorado lá) | senhas de dev, chaves RustFS, JWT de dev, credenciais R2 de teste |
| CI | GitHub secrets/environments por repo | `DOKPLOY_API_KEY`, ids de stack; `GITHUB_TOKEN` é automático |
| Produção | painel do Dokploy (Environment do compose → `.env` na VPS) ou Secrets Provider | tudo que é segredo de prod |
| Borda | dashboard Cloudflare | token do túnel (referenciado, nunca copiado para o repo) |

Regras estruturais:

- o repo versiona **nomes e exemplos**, nunca valores; `*.example` com
  placeholder autoexplicativo (`replace-with-...` / `__SET_BY_...__`);
- compose referencia `${VAR:?mensagem}` para obrigatórias (falha cedo) e
  `${VAR:-default}` para opcionais com default seguro;
- o `.env` do Dokploy não é injetado automaticamente nos containers: o
  compose precisa consumir via `${VAR}` ou `env_file` (ver
  `dokploy-deploy`);
- um valor por variável; nunca blob JSON/YAML com múltiplos segredos
  (quebra o redaction automático do Actions).

## Inventário de segredos do sistema

- **Back**: `APP_JWT_SECRET` (≥256 bits), `SPRING_DATASOURCE_PASSWORD`
  (Supabase em prod), `SMTP_PASSWORD`, chaves R2 read-write e read-only
  (`APP_STORAGE_*`), `APP_STORAGE_R2_*`;
- **Radar**: `CLOUDFLARE_KEY_ID`/`CLOUDFLARE_SECRET_KEY` (bucket privado
  de Parquets);
- **Front**: nenhum segredo — `SSR_JWT_SECRET` de rascunhos antigos **não
  existe** no Front; segredo de JWT não entra em bundle de browser, ponto;
- **Infra/borda**: `CLOUDFLARED_TUNNEL_TOKEN`, `DOKPLOY_API_KEY`, PAT
  GHCR `read:packages` (Dokploy), PAT GHCR `write:packages` (só se CI não
  usar `GITHUB_TOKEN`), credenciais do painel Dokploy (2FA/passkey);
- chaves R2 do bucket **público** de media: o bucket é público por
  decisão; ainda assim a credencial de escrita dele é segredo do Back.

## Geração e qualidade

- segredos longos e aleatórios: `openssl rand -hex 32` (ou 64) — JWT,
  tokens, senhas internas;
- credenciais RustFS de dev seguem as validações do `rustfs-init` do Back
  (16–128 chars alnuméricos na access key; read-only ≠ read-write);
- escopo mínimo por credencial: PAT do Dokploy só `read:packages`; PAT de
  CI só o que o workflow usa; token do Dokploy API por integração e com
  expiração; token R2 do Radar restrito ao bucket privado (bucket-scoped
  token quando disponível); tokens de API Cloudflare restritos à conta/zone
  necessária;
- nunca reutilizar o mesmo segredo entre ambientes (dev ≠ teste ≠ prod) —
  o vazamento de dev não pode comprometer prod.

## Manuseio em CI (regras do hardening oficial)

- segredos só via `secrets.*`; valores sensíveis impressos por engano
  devem ser mascarados com `::add-mask::` e o log apagado + segredo
  rotacionado;
- segredos de deploy vivem em **environment** `production` (permite
  required reviewers e isola de PRs); PR de fork não recebe segredo;
- não passar segredo como argumento de CLI visível em `ps`/log de step;
  preferir env do step;
- auditar periodicamente: lista de secrets usados ainda é necessária?
  rotação em dia?

## Validação anti-vazamento (todo change set)

1. `git status`/`git diff`: nenhum `.env` real, `*.pem`, `*.key`, token ou
   senha;
2. `git check-ignore -v` confirma que `.env` local e padrões sensíveis
   estão ignorados;
3. `*.example` novo cobre todas as `${VAR:?}` do compose alterado;
4. nenhum segredo em log de workflow (revisar run de teste com entrada
   inválida);
5. nenhum segredo em imagem Docker (Dockerfile não copia `.env`; conferir
   `.dockerignore` dos repos quando o fluxo tocar build).

## Rotação (procedimento por tipo)

- **JWT secret (Back)**: atualizar no Dokploy → redeploy → tokens emitidos
  antes caem (refresh tokens persistidos seguem válidos conforme o modelo
  do Back); comunicar janela;
- **senha Supabase**: rotacionar no painel Supabase → atualizar env →
  redeploy;
- **chaves R2**: criar chave nova (escopo igual) → atualizar Back/Radar →
  redeploy → revogar a antiga;
- **token do túnel**: rotacionar no dashboard CF → atualizar env do
  cloudflared → redeploy (túnel reconecta outbound);
- **`DOKPLOY_API_KEY`**: gerar token novo com expiração → atualizar
  secrets dos 3 repos → revogar o antigo;
- **PAT GHCR**: gerar novo → atualizar Registry no Dokploy → validar pull
  → revogar;
- registro: toda rotação fica anotada no runbook (`docs/deploy-dokploy.md`)
  com data e motivo — sem valor, só metadado.

## Proibições

- commitar segredo "só para testar", em branch, stash ou histórico (Git
  não esquece — vazou, rotacionou);
- imprimir valor de segredo em terminal, log, relatório de task, contexto
  ou mensagem de commit;
- ler `.env` real dos repos irmãos (o Radar mantém credenciais de teste lá;
  agentes referenciam o arquivo por `env_file`, não pelo conteúdo);
- colocar segredo em nome de imagem, tag, label, annotation ou URL;
- usar credencial de produção em ambiente de dev/teste.
