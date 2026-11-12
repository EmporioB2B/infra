# Contrato do ambiente de staging

Este documento registra as decisões de configuração do staging. Não prova que
DNS, Cloudflare, recursos R2, SMTP ou Dokploy tenham sido provisionados.
Valores secretos são definidos por serviço no Dokploy; este repositório contém
somente nomes de variáveis e placeholders.

## Hostnames e acesso

| Serviço | Hostname aprovado | Proteção/rota pretendida |
|---|---|---|
| Front | `staging.emporiob2b.com.br` | Cloudflare Access → Tunnel → `front:4000` |
| API | `api-staging.emporiob2b.com.br` | Cloudflare Access → Tunnel → `api:8080` |
| Mídia pública | `media-staging.emporiob2b.com.br` | Custom Domain do bucket público R2 de staging; não passa pelo Tunnel |

Os nomes foram aprovados como contrato, mas disponibilidade, DNS, Tunnel e
Access ainda precisam ser verificados/configurados antes do deploy. Proteger os
dois hostnames; não criar rota para o painel Dokploy, Postgres, Radar ou actuator.

## PostgreSQL e dados

- PostgreSQL local em container, versão major **17** (`postgres:17-alpine` no
  contrato inicial), condicionada à compatibilidade com as migrations atuais do
  Backend. A Infra possui prova isolada parametrizada para PG16/PG17; isso não
  equivale a validação do Supabase gerenciado.
- Sequência: `postgres → db-bootstrap → migrate → api`. O bootstrap usa a role
  administrativa; Flyway usa `emporio_migrador`; o runtime usa `emporio_app`.
  Senhas são distintas e cada credencial só é entregue ao job/serviço que precisa
  dela. O runtime não executa Flyway.
- Dados exclusivamente de staging (sintéticos ou criados pelo próprio ambiente).
  Nunca copiar dados de produção.
- O volume do banco é persistente; retenção/backup e sizing serão detalhados
  antes do primeiro deploy. Não executar `down -v`.

## R2

- Back: recursos/buckets de staging dedicados para quarentena, privado e público,
  com credenciais staging próprias e separadas por finalidade, conforme as
  operações realmente exigidas pelo código do Backend.
- Radar: bucket de staging dedicado e credencial de staging exclusiva. O Radar
  usa endpoint R2 real; RustFS/MinIO não são aceitos. O escopo da credencial deve
  ser mínimo para as operações dos objetos configurados.
- Nomes dos buckets, conta/endpoint, chaves e policies reais serão fornecidos e
  provisionados pelo operador no Dokploy/Cloudflare; não são conhecidos nem
  inferidos neste documento. Não compartilhar recursos ou credenciais de produção
  ou entre Back e Radar.
- Hostname público de mídia aprovado: `media-staging.emporiob2b.com.br`, como
  Custom Domain do bucket público R2 dedicado do Back; não passa pelo Tunnel.
  A associação do Custom Domain, políticas de cache/WAF e acessibilidade ainda
  não foram configuradas. Não reutilizar o domínio/bucket de produção.

## SMTP

- SMTP real de staging com credencial exclusiva, diferente da produção; exige
  autenticação e STARTTLS obrigatório, conforme validação do Backend.
- Remetente de teste e destinatários controlados. O provedor, remetente concreto,
  allowlist e dados de conexão serão definidos pelo operador e provisionados no
  Dokploy. Se não houver credencial/serviço de staging adequado, manter o envio
  real bloqueado.

## Gestão de configuração

- Configuração e segredos administrados por serviço no Dokploy, com escopos
  separados para Postgres/bootstrap, migrador, API/Back, Radar e Tunnel.
- Somente nomes e placeholders são versionáveis; valores reais nunca entram no
  repo, task, logs ou documentação.
- Responsabilidade de provisionamento: o operador cria/guarda os valores no
  Dokploy; o escopo funcional segue o serviço dono (Backend para JWT/R2 Back/
  SMTP, Radar para R2 Radar, Infra para token Tunnel e roles locais do Postgres).
  Nenhum desses valores foi obtido ou copiado.
- Inventário de responsabilidade e escopo:

  | Valores (somente nomes) | Serviço que recebe | Responsável funcional | Local do valor real |
  |---|---|---|---|
  | `POSTGRES_ADMIN_PASSWORD` | PostgreSQL/bootstrap, nunca API | Infra (operador) | Environment dos serviços PostgreSQL/bootstrap no Dokploy |
  | `SPRING_FLYWAY_PASSWORD` | bootstrap e job `migrate`, nunca API | Backend (operador provisiona) | Environment dos serviços bootstrap/migrate no Dokploy |
  | `SPRING_DATASOURCE_PASSWORD` | bootstrap e API runtime | Backend (operador provisiona) | Environment dos serviços bootstrap/API no Dokploy |
  | `APP_JWT_SECRET`, SMTP vars | API/Back | Backend (operador provisiona) | Environment do serviço API no Dokploy |
  | `APP_STORAGE_*R2*` | API/Back | Backend (operador provisiona) | Environment do serviço API no Dokploy |
  | `CLOUDFLARE_KEY_ID`, `CLOUDFLARE_SECRET_KEY` | Radar | Radar (operador provisiona) | Environment do serviço Radar no Dokploy |
  | `CLOUDFLARED_TUNNEL_TOKEN` | cloudflared | Infra/Cloudflare (operador provisiona) | Environment do serviço cloudflared no Dokploy |

  A lista acima é inventário de responsabilidade, não indicação de que os
  serviços/credenciais já foram criados. Definir as variáveis separadamente por
  serviço, sem um `.env` real compartilhado.
- A configuração de Front (`apiBaseUrl`, `imageBaseUrl`, `allowedHosts`) é
  compilada na imagem. Contrato de build aprovado: API
  `https://api-staging.emporiob2b.com.br`, mídia
  `https://media-staging.emporiob2b.com.br`; `allowedHosts` inclui
  `staging.emporiob2b.com.br` e mantém `localhost` para o healthcheck da imagem.
  O Front atual não aceita esses valores em
  runtime. O Front agora contém configuração `staging` e build script, mas o
  Dockerfile ainda executa `build:production`; o repo dono precisa concluir e
  validar a seleção de staging na imagem (TASK-INFRA-002; operador informa que a
  implementação está em andamento).
- Publicar imagens de Back, Front e Radar para `linux/arm64` e `linux/amd64` é
  gate de deploy. Não foram encontrados workflows de aplicação que comprovem
  publicação multiarch; as mudanças pertencem aos repos donos e são rastreadas
  como dependências, não implementadas pela Infra.

## Gates ainda não executados

- Confirmar disponibilidade dos hostnames e provisionar DNS/Tunnel/Access.
- Provisionar buckets e credenciais não produtivas de R2 e SMTP no Dokploy.
- Concluir TASK-INFRA-002 no repo Front e workflows multiarch nos repos donos.
- Configurar Custom Domain R2 `media-staging.emporiob2b.com.br` no bucket público
  dedicado e confirmar políticas adequadas para conteúdo de teste.
- Validar em runtime o teto aprovado de 1,5 CPU/3 GiB por stack; o sizing é
  inicial e não houve teste de carga. Definir backup/retention do volume Postgres
  antes de operar dados que precisem ser preservados.
- Provisionar valores reais por serviço no Dokploy; `.env.staging.example` é
  somente nomes/placeholders e não deve ser usado como arquivo de produção.
