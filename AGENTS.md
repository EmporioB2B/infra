# Instruções compartilhadas do Emporio B2B Infra

Este repositório é dono da infraestrutura conjunta do marketplace Emporio
B2B: compose de desenvolvimento/integração, compose de produção, túnel
Cloudflare, cadeia CI/CD dos repositórios de aplicação e deploy na VPS via
Dokploy.

Antes de qualquer trabalho, leia `.opencode/context/indice.md`. Os nomes de
variáveis de ambiente, portas, healthchecks e restrições reais de cada
serviço estão em `.opencode/context/servicos.md`; nunca invente nomes a
partir de memória ou de rascunhos antigos.

Código de aplicação pertence aos repositórios irmãos (`Backend_Java`,
`Front_Angular`, `Radar_Middleware_Python`, `Hermes_Robo_Whats_Python`).
Este repositório não importa, duplica nem altera código deles; a integração
acontece somente por imagens Docker publicadas (GHCR), contratos HTTP e
variáveis de ambiente documentadas.

## Agentes e ciclo de trabalho

O trabalho segue dois agentes canônicos em `.opencode/agents/`:

- **`arquiteto`** (primary): governa topologia, compose, CI/CD, borda e
  docs; implementa diretamente os artefatos deste repo; Git mutável
  (`add`, `commit`, `push`, tags, resets, merges) é **interditado** — o
  arquiteto prepara o change set e o operador executa; deploy e operações
  de produção exigem autorização explícita do operador para cada ação.
- **`context-revisor`** (subagent): audita se `context/` reflete os
  artefatos reais e os repos irmãos; é o único agente além do arquiteto que
  edita algo, e edita somente `.opencode/context/`; tudo mais é reportado.

## Regras obrigatórias

- Segredos, tokens, credenciais e `.env` reais nunca entram no Git, em logs,
  em compose ou em documentação; apenas arquivos `*.example` com
  placeholders.
- O Radar não publica portas no host e só fala com a api pela rede Docker
  interna exclusiva (`radar-net`, `internal: true`).
- Compose de desenvolvimento publica portas somente em `127.0.0.1`.
- Produção não possui banco em container: o PostgreSQL do Back é o Supabase
  externo; o estado local do Radar (SQLite) é reconstruível.
- Operações destrutivas (`down -v`, prune de volume/imagem/rede, qualquer
  ação contra a VPS ou produção) exigem autorização explícita do operador.
- Compose e docs deste repositório são a fonte da verdade da topologia;
  mudança de topologia atualiza o contexto no mesmo change set.

## Tasks

`.opencode/tasks/task_atual.md`, `mensagem/` e `tasks/futuras/` são locais e
ignorados pelo git: `tasks/futuras/` é planejamento pessoal do operador
(convenção dos projetos de aplicação; decisão revogada e realinhada em
2026-09-26). Tasks em `tasks/futuras/` recebem atualização cirúrgica de
status; `tasks/passadas/` é histórico aditivo e imutável — este sim
versionado, pois a justificativa das decisões precisa sobreviver ao clone.
