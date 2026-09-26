# Índice de skills do Emporio B2B Infra

O OpenCode descobre automaticamente `skills/<nome>/SKILL.md`. Este arquivo é
somente o catálogo humano; não substitui o frontmatter nem duplica o
conteúdo das skills.

## Skills obrigatórias

| Skill | Quando usar | Situação |
|---|---|---|
| `verification-before-completion` | promoção ou declaração de conclusão de qualquer task de infra | obrigatória |
| `secrets-env` | qualquer change set que toque env, segredo, token ou credencial (compose, CI, Dokploy, Cloudflare) | obrigatória nesses escopos |

## Skills condicionais

| Skill | Quando usar | Situação |
|---|---|---|
| `compose-infra` | escrever ou revisar qualquer docker-compose (dev, e2e, prod) | ativa |
| `cloudflare-edge` | túnel, DNS, domínios, headers encaminhados, media/R2, cookies/CORS de borda | ativa |
| `dokploy-deploy` | deploy, redeploy, rollback, envs/segredos no painel, hardening da VPS, stack compose | ativa |
| `cicd-ghcr` | workflows GitHub Actions, build/push de imagens, GHCR, trigger de deploy | ativa |

## Fronteiras de seleção

- Fatos por serviço (nomes de env, portas, healthchecks) nunca vêm de
  memória: a fonte é `context/servicos.md`, auditada pelo `context-revisor`
  contra o código dos repos irmãos.
- Skills deste repo não autorizam mudança de código nos repositórios de
  aplicação; tasks que exigem mudança lá (ex.: `allowedHosts` do Front) são
  registradas como dependência e executadas com a governança do repo dono.
- Nenhuma skill autoriza operação destrutiva contra produção, VPS, volumes
  ou registros sem autorização explícita do operador, nem Git mutável
  (papel exclusivo do operador).

## Política de proveniência de skills

Não instalamos skills de terceiros (skills.sh, marketplaces, repositórios
externos). Comportamentos úteis de skills públicas são **estudados e
reescritos** dentro das skills canônicas deste diretório, com a origem
citada quando relevante (ex.: gate function de
`obra/superpowers:verification-before-completion`). Isso mantém a cadeia de
confiança: nenhum artefato externo entra no repo sem revisão, e o conteúdo
versionado aqui é 100% nosso. As práticas técnicas das skills vêm de
documentação oficial (Docker, Cloudflare, Dokploy, GitHub) e são
revalidadas quando a task tocar o assunto.

Skills pessoais ficam fora deste diretório, em
`~/.config/opencode/skills/`.
