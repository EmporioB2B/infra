# Objetivo do Emporio B2B Infra

Ser dono da infraestrutura conjunta do marketplace Emporio B2B: ambiente
local reproduzível para testes de integração e E2E, ambiente de produção na
VPS via Dokploy, cadeia CI/CD dos repositórios de aplicação e borda
Cloudflare (túnel + domínios).

## Responsabilidades

- Compose de desenvolvimento/integração (**existente — dev**): api, front,
  radar, postgres, RustFS (emulando R2, inclusive o bucket público de fotos),
  Mailpit (capturando SMTP) e observabilidade local (Vector, Loki, Prometheus
  e Grafana), na mesma topologia principal de redes da produção planejada.
- Compose de produção (**planejado — produção**): `cloudflared`, front, api e
  radar; sem banco em container (o PostgreSQL do Back é o Supabase externo).
- CI/CD (**planejado — workflows deste repositório ainda não existentes**):
  padrão de GitHub Actions por repositório de aplicação (testes, build de
  imagem, push no GHCR e deploy via API do Dokploy).
- Borda Cloudflare (**planejado — produção**): túnel para
  `emporiob2b.com.br` (front) e `api.emporiob2b.com.br` (api);
  `media.emporiob2b.com.br` resolve para o bucket público do R2 sem passar
  pela VPS.
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
