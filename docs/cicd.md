# Contrato de CI/CD — Emporio B2B

Este documento define o contrato inicial para os workflows de
`Backend_Java`, `Front_Angular` e `Radar_Middleware_Python`. Cada repositório
de aplicação é dono e implementa seus próprios workflows. A Infra mantém este
padrão, valida sua conformidade e governa o Compose de staging.

## Estado e limites

- O Backend já possui `.github/workflows/backend-ci.yml`, com jobs de `verify`
  e publicação GHCR; ele ainda não baixa o artefato de roles nem define
  `EMPORIO_INFRA_ROLES_BOOTSTRAP_PATH`. Front e Radar ainda não possuem
  workflows. Nenhuma execução remota foi verificada nesta tarefa. A Infra tem
  `publish-roles-bootstrap.yml`, mas o package e o acesso GHCR do Backend ainda
  não foram publicados/configurados.
- A publicação acontece no GHCR privado. O CI **não faz deploy** e não chama a
  API/webhook do Dokploy.
- O deploy de staging é **manual pelo operador no Dokploy**, usando o painel
  pelo canal administrativo aprovado. Não expor o painel ou a API do Dokploy à
  internet para habilitar CI.
- Produção está fora deste contrato. Promoção de imagem, workflow de produção e
  aprovação de produção exigirão decisão e tarefa próprias.
- TASK-INFRA-002 e a conclusão da build staging do Front continuam pré-requisitos
  para publicar uma imagem Front apta ao staging.

## Fluxo de branches e gates

1. Branches de trabalho abrem PR para `main`.
2. PR executa o gate de teste do respectivo projeto. PR, inclusive de fork, não
   publica imagem, não faz deploy e não recebe segredos de deploy.
3. O processo da equipe exige trabalhar em branch, abrir PR para `main` e
   aguardar os checks de CI antes do merge. **No estado atual, `main` não tem
   branch protection**: o GitHub não bloqueia tecnicamente push direto ou merge
   sem checks. Esta é uma exceção temporária do repositório privado/plano atual,
   não uma garantia de enforcement do GitHub.
4. Merge/push em `main` executa novamente o gate e, somente após sucesso,
   publica a imagem multiarch no GHCR.
5. A imagem publicada fica disponível para deploy manual em staging. Uma falha
   de testes impede a publicação.

O gate canônico por repositório é:

| Repositório | Gate obrigatório |
|---|---|
| Backend_Java | `./mvnw -B verify` (inclui Testcontainers; o runner precisa do Docker disponível) |
| Front_Angular | `npm ci`, `npm run lint`, `npm run typecheck`, `npm run test`, `npm run build` |
| Radar_Middleware_Python | `uv sync --locked`, `uv run pytest`, `uv run ruff check .`, `uv run ruff format --check .` |

O Front deve produzir a imagem de staging com o perfil `staging` e os valores
de build aprovados no contrato de staging: API
`https://api-staging.emporiob2b.com.br` e mídia
`https://media-staging.emporiob2b.com.br`. Esses valores não são segredos. A
imagem deve preservar `localhost` e o hostname de staging em `allowedHosts`.
Não publicar uma imagem de produção como se fosse a imagem de staging.

## Imagens, tags e plataformas

| Repositório | Imagem GHCR |
|---|---|
| Backend_Java | `ghcr.io/emporiob2b/backend-java` |
| Front_Angular | `ghcr.io/emporiob2b/front-angular` |
| Radar_Middleware_Python | `ghcr.io/emporiob2b/radar-middleware` |

- Pacotes GHCR são privados. O workflow usa `GITHUB_TOKEN`; `packages: write`
  fica restrito ao job de publicação. Os demais jobs mantêm apenas as
  permissões necessárias, com `contents: read` como padrão.
- Cada publicação em `main` cria a tag com o **SHA completo do commit**. Essa é
  a referência de versão selecionada manualmente para staging; não usar `latest`
  como seletor de deploy. Um alias `latest` é dispensável neste fluxo e, se
  publicado, serve apenas para conveniência, nunca para staging ou produção.
- O Compose de staging recebe referências completas nas variáveis
  `BACKEND_IMAGE`, `FRONT_IMAGE` e `RADAR_IMAGE`, no formato
  `ghcr.io/emporiob2b/<imagem>:<sha-completo>`. Cada referência deve existir no
  GHCR e corresponder à publicação aprovada antes de iniciar o deploy.
- Publicar manifest multiarch para `linux/amd64` e `linux/arm64`. Buildx/QEMU é
  a estratégia inicial; runner ARM nativo pode ser adotado se necessário. O
  build multiarch não substitui o smoke real no staging ARM64.
- A tag SHA é a referência operacional aprovada inicialmente. Ela não é, por
  si só, uma garantia criptográfica de imutabilidade no registry: conferir o
  digest publicado durante a preparação do deploy e preservar esse dado no
  registro operacional do release. Não promover `latest`.

## Artefato Infra de roles para o CI do Backend

- A fonte canônica permanece `database/bootstrap/roles.sql`, pertencente à
  Infra. `database/bootstrap/Dockerfile` cria uma imagem OCI mínima de
  transporte; não é serviço para execução e não duplica o SQL no repo Backend.
- `.github/workflows/publish-roles-bootstrap.yml` roda os smokes em PostgreSQL
  16 e 17 e compara a extração do artefato byte a byte com o SQL canônico.
  Pull requests validam, mas não publicam. Push em `main` só publica depois dos
  gates verdes.
- Package pretendido: `ghcr.io/emporiob2b/infra-roles-bootstrap`, privado,
  multiarch, tag `sha-<SHA completo da Infra>` e digest reportado pelo workflow.
  Consumidores devem fixar o digest, nunca `latest`. O package ainda não foi
  publicado nem teve seu acesso remoto validado.
- Provenance e SBOM estão explicitamente desabilitados nessa primeira versão do
  pacote de transporte (somente SQL, sem runtime); o commit da Infra é incluído
  como metadata e o consumidor fixa o digest. Reavaliar attestations numa
  mudança própria, sem presumir que o registry/consumidor já as valida.
- Depois da primeira publicação, o operador concede `Read` ao repositório
  `Backend_Java` em GHCR → package → **Manage Actions access**. Isso concede
  acesso ao package, não ao repositório Infra. A permissão deve ser confirmada
  no painel; nenhuma credencial manual é necessária.
- O workflow do Backend consumirá o digest com `GITHUB_TOKEN` limitado a
  `packages: read`, extrairá `/bootstrap/roles.sql` para área temporária e
  definirá `EMPORIO_INFRA_ROLES_BOOTSTRAP_PATH` antes de `./mvnw -B verify`.
  O workflow atual do Backend ainda não contém esses passos; eles pertencem ao
  repo Back e não são implementados por esta tarefa Infra. PR/fork não recebe
  PAT nem secret de longa duração; a leitura no evento PR precisa ser provada
  em run real.
- Quando `roles.sql` mudar, a Infra valida e publica outra referência; o Back
  atualiza o digest por PR. O provisionamento do banco/roles continua Infra; as
  migrations e o runner Flyway continuam Backend.

## Requisitos dos workflows

- Separar jobs de teste e publicação; publicação depende do sucesso dos testes
  e só pode rodar em push para `refs/heads/main`.
- Usar `timeout-minutes` explícito. Como ponto de partida: cerca de 30 minutos
  para o Backend e 15 minutos para Front e Radar; ajustar com evidência de
  duração real.
- Usar Buildx e cache GHA quando aplicável. Publicar as duas plataformas num
  único manifest multiarch.
- Fixar actions de terceiros por SHA de commit completo e incluir o tag da
  versão em comentário na mesma linha. Manter Dependabot para GitHub Actions.
- `CODEOWNERS` cobrindo `.github/workflows/` e revisão de code owner são
  requisitos futuros, ativados quando houver pelo menos um segundo mantenedor
  com acesso de escrita capaz de fazer revisão independente. Até lá, não
  adicionar o próprio usuário como code owner nem criar times sem mantenedores
  efetivos; seguir o processo manual de PR e CI descrito acima, sem afirmar que
  há revisão independente ou bloqueio técnico de pushes diretos.
- Quando houver outro desenvolvedor e o plano/configuração do GitHub permitir,
  habilitar proteção de `main` com PR e checks obrigatórios, sem force-push ou
  exclusão, e `CODEOWNERS` para `.github/workflows/`. Até essa mudança, ambos
  são requisitos operacionais futuros, não controles técnicos ativos.
- Usar `concurrency` para evitar trabalho redundante em PR. Não interromper um
  deploy em andamento: deploys ainda não são executados por Actions; o operador
  também não deve iniciar duas atualizações simultâneas no mesmo stack.
- Não interpolar título de PR, branch ou mensagem de commit diretamente em
  `run:`; encaminhar entrada não confiável por `env:` e citá-la no shell.
- Não usar `pull_request_target` nem `workflow_run` com checkout de código não
  confiável. Não usar `write-all` ou permissões amplas.
- Considerar provenance/SBOM como melhoria posterior. Não habilitar attestations
  sem validar a compatibilidade do pull privado do Dokploy; eventual decisão de
  desabilitá-las deve ser documentada, não silenciosa.

## Segredos e acesso ao registry

- O fluxo de CI e publicação não precisa de `DOKPLOY_API_KEY`, Compose ID,
  token de túnel ou credenciais do ambiente de staging. Não criar esses secrets
  nos repos de aplicação para este contrato.
- A autenticação de publicação usa o `GITHUB_TOKEN` automático com escopo
  mínimo. Não usar PAT de escrita se `GITHUB_TOKEN` for suficiente.
- O Dokploy precisa de credencial GHCR de leitura configurada pelo operador,
  separada dos tokens de CI. Segredos reais vivem no painel/armazenamento
  aprovado e nunca em YAML, logs ou documentação.
- Front não recebe segredo para compilar URLs públicas. Nenhuma chave JWT,
  credencial R2, SMTP ou variável de produção pode entrar no bundle ou no build
  da imagem.

## Procedimento de deploy manual em staging

1. Confirmar que os gates do commit passaram e que a imagem publicada está
   disponível no GHCR para `linux/amd64` e `linux/arm64`.
2. Registrar o repositório, SHA completo, tag e digest de cada imagem escolhida.
3. No Compose do serviço de staging no Dokploy, definir `BACKEND_IMAGE`,
   `FRONT_IMAGE` e `RADAR_IMAGE` para as referências SHA completas desejadas.
   Manter as imagens não alteradas nas referências já aprovadas; não substituir
   as três por tags de commits sem verificação.
4. Acionar o deploy pelo painel Dokploy através do acesso administrativo
   aprovado. Não abrir API, webhook ou painel à internet e não automatizar esse
   passo via Actions neste estágio.
5. Confirmar que o `db-bootstrap` e o `migrate` do Backend terminam com sucesso,
   que API, Front e Radar ficam healthy, e executar o smoke/validação de staging
   em ARM64. Migration falha bloqueia a aceitação do deploy.
6. Registrar as referências efetivamente implantadas e os resultados. Em caso
   de falha, não declarar staging atualizado; diagnosticar e selecionar
   manualmente referências conhecidas. Não executar rollback automático de
   schema.

O Compose controla a ordem `postgres → db-bootstrap → migrate → api`; a API usa
a mesma imagem Backend selecionada para o job `migrate`. Migrations devem ser
compatíveis com a versão anterior da aplicação durante a atualização
(estratégia expand/contract). Migration não é executada contra o Supabase de
produção por este fluxo.

## Recuperação

- Registrar as referências SHA anteriores antes do deploy, para permitir
  repin manual das imagens pelo operador.
- Repin de imagem não reverte alterações de schema nem dados. Não tentar
  rollback automático do PostgreSQL; migrations devem privilegiar mudanças
  retrocompatíveis e falhas de schema exigem diagnóstico e procedimento
  explícito.
- A promoção futura de produção deverá reutilizar as referências já verificadas
  em staging, com gate e aprovação separados.

## Validação e aceite do contrato

- `actionlint` sem erros em cada workflow implementado.
- PR real executa os testes e não publica imagem nem aciona Dokploy.
- Um merge/execução de validação em `main` publica imagem privada com as tags
  esperadas e manifest `linux/amd64,linux/arm64`.
- Teste negativo: falha no gate de testes impede publicação.
- Revisão de logs confirma que nenhum segredo foi exposto.
- Operador implanta manualmente em staging as referências SHA conferidas; o
  Compose conclui bootstrap/migration e os serviços ficam healthy em ARM64,
  seguido de smoke aprovado.

Este contrato não afirma que o workflow do Backend tenha integrado o artefato
de roles, que workflows de Front/Radar existam, nem que proteção de `main`,
package GHCR, acesso Actions, integração Dokploy ou deploy de staging estejam
configurados. O workflow versionado da Infra ainda precisa ser executado no
GitHub para publicar o package. No estado atual, a proteção de `main` está
explicitamente ausente; o fluxo por PR/CI é manual. Cada item deve ser validado
no repositório/ambiente dono antes de ser tratado como existente.
