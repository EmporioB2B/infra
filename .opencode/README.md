# OpenCode do Emporio B2B Infra

Esta pasta contém a parte canônica e compartilhada da configuração de
trabalho do OpenCode para o repositório de infraestrutura. A configuração
pessoal de cada desenvolvedor não é versionada.

## Diferenças em relação aos projetos de aplicação

- O ciclo é enxuto: **`arquiteto`** (primary) implementa diretamente os
  artefatos de infra (compose, scripts, docs, workflows deste repo) e
  **`context-revisor`** (subagent) audita e corrige o contexto compartilhado.
  Não existe `implementador` nem dupla de revisores — o revisor de código
  independente é o operador, no diff apresentado antes do commit.
- `tasks/futuras/` **é versionado**: o planejamento de infra é compartilhado
  entre todos os operadores, não pessoal por desenvolvedor.

## Conteúdo compartilhado

| Caminho | Finalidade |
|---|---|
| `agents/` | agentes canônicos: `arquiteto` e `context-revisor` |
| `context/` | fatos atuais, topologia alvo, catálogo de serviços e decisões |
| `skills/` | skills canônicas e catálogo humano |
| `tasks/futuras/` | planejamento compartilhado e versionado |
| `tasks/passadas/` | histórico técnico selecionado, aditivo e imutável |

## Configuração pessoal

`opencode.json` e `tui.json` ficam na máquina de cada desenvolvedor e são
ignorados pelo Git. Um mínimo local pode ser:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "default_agent": "arquiteto",
  "share": "disabled",
  "snapshot": true,
  "formatter": true,
  "lsp": true
}
```

Skills pessoais ficam em `~/.config/opencode/skills/`, fora deste
diretório.

## Git e produção

Todo Git mutável (add/commit/push/tag/reset/checkout/merge/rebase etc.) é
**interditado aos agentes** — quem executa é o operador. O arquiteto
prepara o change set, apresenta diff e sugere mensagem de commit. Deploy e
operações de produção (Dokploy, SSH, dashboards) exigem autorização
explícita do operador para cada ação.

## Tasks e histórico

- `tasks/task_atual.md` é estado pessoal e não entra no Git;
- `tasks/futuras/` entra no Git e é o plano compartilhado do repositório;
- `tasks/passadas/` contém decisões e evidências técnicas; arquivos
  arquivados são aditivos e imutáveis;
- `mensagem/` contém comunicações locais e permanece ignorada.

O contexto atual não recebe relatos cronológicos de bugs, testes, revisões
ou conversas. Uma regra permanente pertence ao contexto apropriado; a
evidência histórica pertence a `tasks/passadas/`.

## Manutenção

Atualize o índice quando um documento de contexto surgir, desaparecer ou
mudar de escopo. Atualize o catálogo quando uma skill mudar de nome, escopo
ou versão. Não reescreva arquivos arquivados em `tasks/passadas/`.

Depois de alterar agents, skills, contexto ou qualquer arquivo de
configuração do OpenCode, reinicie o OpenCode para recarregar a
configuração.
