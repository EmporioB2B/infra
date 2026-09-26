# Tasks do Emporio B2B Infra

## Convenção deste repositório

- `task_atual.md`, `mensagem/` e `futuras/` são **locais e ignorados pelo
  git** — planejamento pessoal do operador, igual aos projetos de aplicação
  (decisão de 2026-09-26, revogando a exceção anterior);
- tasks futuras usam o prefixo `TASK-INFRA-NNN` e recebem atualização
  cirúrgica de status/escopo quando a realidade mudar;
- quando concluída, a task é arquivada em `passadas/` com data no nome do
  arquivo e torna-se imutável; **`passadas/` é versionado** — a
  justificativa das decisões precisa sobreviver ao clone; o contexto
  (`context/*.md`) é atualizado no mesmo change set.

## Estrutura de uma task futura

Cabeçalho com `Status`, `Tipo`, `Repo alvo` e `Origem`; seções `Objetivo`,
`Escopo`, `Fora do escopo`, `Dependências` e `Critérios de aceite`. O aceite
referencia a skill `verification-before-completion`.

## Histórico compartilhado

- `passadas/` contém decisões e evidências técnicas selecionadas;
- arquivos arquivados são aditivos e imutáveis;
- histórico não substitui o contexto atual.
