---
name: verification-before-completion
description: Use before declaring any Emporio B2B Infra task complete, fixed, or passing; requires fresh command evidence (gate function) for compose validity, stack health, isolation, CI, deploy and secret hygiene.
---

# Verificação antes de concluir

## Lei de ferro

**Nenhuma declaração de conclusão sem evidência de verificação fresca.**

Se o comando de prova não foi executado nesta sessão, você não pode afirmar
que passa. "Violinar a letra desta regra é violar o espírito desta regra":
não vale evidência de run anterior, relato de agente, intenção, confiança
ou "deve estar funcionando". (Padrão comportamental adotado a partir de
`obra/superpowers:verification-before-completion`, copiado — não
instalado — conforme política de skills do repo.)

## Função de gate (5 passos, toda afirmação de sucesso)

1. identifique o **comando de prova** daquela afirmação;
2. execute-o **agora**, fresco;
3. leia a saída **completa** e o exit code (não só a última linha);
4. confira se a evidência sustenta exatamente a afirmação feita;
5. declare o resultado **com a evidência anexa** (comando, exit code,
   duração, trecho relevante da saída).

Atalhos bloqueados: confiar em relatório de subagente sem reexecutar o
gate; usar "lint passou" como prova de build; usar "container criou" como
prova de healthy; assumir cobertura/latência/isolamento não medidos.

## Evidência mínima por escopo

- **compose**: `docker compose -f <arquivo> config --quiet` exit 0;
  `up -d` com todos os serviços **healthy** (`docker compose ps` — não
  "created", não "running"); `depends_on: service_healthy` exercitado na
  ordem real de subida;
- **isolamento (sempre, em qualquer change set de rede/compose)**: radar
  sem `ports:`; inalcançável do host (conexão falha) e de container fora da
  `radar-net`; alcançável do backend (`docker compose exec backend curl
  http://radar:8000/health/live`); `docker network inspect` mostra
  `internal: true`; `radar-net` contém exatamente api+radar;
- **dev**: todas as portas publicadas vinculadas a `127.0.0.1`
  (`docker compose ps` + `config`);
- **smoke**: `scripts/smoke.sh` exit 0 com saída registrada (health api
  8081, `/health/ready` do radar pela rede interna, front respondendo,
  buckets RustFS presentes);
- **percurso manual E2E (quando for o escopo)**: jornada registrada com o
  que foi observado em cada passo (cadastro → email no Mailpit → documentos
  no RustFS → aprovação → login; fotos servidas pelo bucket público local);
- **CI/workflow**: `actionlint` exit 0; run real com jobs verdes; imagem
  visível no GHCR com as tags esperadas; teste de falha comprova que gate
  quebrado não publica; revisão de log confirma redaction de segredo;
- **deploy (quando houver)**: smoke público pós-deploy completo da skill
  `dokploy-deploy` (domínios, media, logs sem erro);
- **segredos**: `git status`/`git diff` sem segredo; `git check-ignore -v`
  confirma `.env*` reais ignorados e `*.example` versionáveis; checklist da
  skill `secrets-env`;
- **todos**: `git diff --check`; leitura do diff final; contexto
  (`context/*.md`) atualizado no mesmo change set quando fato vigente
  mudou — com auditoria do `context-revisor` quando o arquiteto solicitar.

Registrar por evidência: comando, exit code, duração, ambiente e
limitações. Diferenciar falha preexistente de falha introduzida; não ocultar
verificação indisponível — reportar como limitação explícita.

## Proibições

- declarar rollback funcional sem executá-lo de verdade;
- `down -v`, prune, `rmi`, `volume rm`, `network rm`, `kill` ou qualquer
  comando destrutivo em produção/VPS sem autorização explícita do operador;
- commitar segredo "só para testar";
- executar Git mutável (papel do operador);
- alterar código de repositório de aplicação a partir de task deste repo;
- promover task com achado MÉDIO+ não arbitrado.
