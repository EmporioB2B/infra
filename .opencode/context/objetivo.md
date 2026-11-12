# Objetivo do Emporio B2B Infra

Ser dono da infraestrutura conjunta do marketplace Emporio B2B: ambiente
local reproduzível para testes de integração e E2E (**existente — dev**),
staging (**planejado — próximo ambiente**) e produção (**planejada — posterior**)
via Dokploy na VPS OCI, cadeia CI/CD dos repositórios de aplicação e borda
Cloudflare (túnel + domínios; **planejada**).

O operador decidiu que staging e produção compartilharão a mesma VPS por não
haver uma segunda máquina disponível. São ambientes lógicos separados, não uma
fronteira forte de segurança; ver `vps_oracle.md` e `decisoes.md`.

## Responsabilidades

- Compose de desenvolvimento/integração (**existente — dev**): api, front,
  radar, postgres, RustFS (emulando R2, inclusive o bucket público de fotos),
  Mailpit (capturando SMTP) e observabilidade local (Vector, Loki, Prometheus
  e Grafana), na mesma topologia principal de redes da produção planejada.
- Compose de staging (**existente — artefatos no repo; implantação planejada**): protegido por
  Cloudflare Access e separado de produção em stacks, redes, volumes, dados e
  credenciais; PostgreSQL local em container e integrações com R2/SMTP reais
  de teste/staging, ainda sem configuração implantada. TASK-INFRA-020 criou
  Compose, env example e runbooks; não foram carregados no Dokploy.
- Compose de produção (**planejado — produção**): `cloudflared`, front, api e
  radar; sem banco em container (o PostgreSQL do Back é o Supabase externo),
  no mesmo host OCI de staging por decisão do operador.
- CI/CD: **existente — workflow publisher Infra** de bootstrap de roles,
  versionado mas ainda não executado/verificado remotamente; Backend também tem
  workflow CI/publicação versionado, sem execução verificada nesta auditoria.
  **Planejado — demais aplicações:** teste e publicação multiarch no GHCR; o
  deploy de staging é manual pelo operador no Dokploy, sem chamada de Actions à
  API/webhook. Package GHCR, permissões Manage Actions access, consumo do
  artefato pelo Back e publicação remota permanecem não verificados. Produção
  está fora do contrato (`../../.github/workflows/publish-roles-bootstrap.yml:1-16`;
  `../Backend_Java/.github/workflows/backend-ci.yml:1-18`;
  `../../docs/cicd.md:8-19,23-35,82-110`).
- Borda Cloudflare (**planejada**): túnel para
  `emporiob2b.com.br` (front) e `api.emporiob2b.com.br` (api);
  o staging usará Cloudflare Access; `media.emporiob2b.com.br` resolve para o
  bucket público do R2 sem passar pela VPS. Tunnel/Access ainda não foram
  configurados.
- Runbooks: smoke tests (**existente — dev**); deploy, rollback e gestão de
  segredos (**planejado — produção**).

## Limites

- Este repositório não contém código de aplicação. Contratos, Dockerfiles,
  testes e comportamento pertencem aos repositórios irmãos.
- A integração com os serviços acontece somente por imagens Docker
  publicadas no GHCR, contratos HTTP e variáveis de ambiente catalogadas em
  `servicos.md`.
- Este repositório não guarda segredos; apenas arquivos `*.example` com
  placeholders. Segredos reais vivem no `.env` local (ignorado) e no painel
  do Dokploy.
- Mudanças de código necessárias ao deploy (ex.: `allowedHosts` e URLs
  compiladas do Front) são registradas como tasks de dependência e
  executadas nos repositórios donos, com a governança deles.
