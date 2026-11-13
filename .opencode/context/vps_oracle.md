# VPS Oracle Cloud — estado factual

Snapshot baseado na console OCI e em comandos executados pelo operador em
2026-11-11, acrescido de fatos de 2026-11-13: borda Cloudflare de staging
configurada no dashboard (túnel `emporio-staging`, rotas e Access), com DNS
e interceptação Access verificados por `dig`/`curl` públicos; publicação das
imagens GHCR verificada por `imagetools inspect` e perfil staging do Front
por `grep` na imagem publicada, ambos colados pelo operador na mesma data;
conta/stack Grafana Cloud criada pelo operador, com endpoints públicos de
ingestão verificados por `curl` (HTTP 401 sem auth).
Não é inventário obtido por API e pode ficar desatualizado; confira
na console antes de qualquer operação. O runbook legível está em
`../../docs/oracle-vps.md`.

## Instância

- Nome: `emporio-infra-sp`.
- Região exibida pela OCI: `SA-VINHEDO-1` (São Paulo), Availability Domain `AD-1`.
- Shape `VM.Standard.A1.Flex`, 4 OCPUs ARM e 24 GB RAM; a console mostrou
  **Always Free-eligible** no lançamento. Isso não é auditoria de faturamento
  nem garantia de que outros recursos/uso estejam dentro dos limites gratuitos.
- Imagem: Canonical Ubuntu 24.04 Minimal aarch64, build `2026.10.27-0`.
- Boot volume: 100 GB, Balanced, 10 VPU; criptografia em trânsito habilitada e
  chave gerenciada pela Oracle. Nenhum block volume adicional foi associado.
- Metadata service requer header de autorização. Restart após manutenção de
  infraestrutura está habilitado; a OCI escolhe a opção de manutenção.
- Na seleção dos Oracle Cloud Agent plugins: Custom Logs Monitoring, Compute
  Instance Run Command, Compute Instance Monitoring e Cloud Guard Workload
  Protection estavam habilitados; Vulnerability Scanning, OS Management Hub,
  Management Agent, Compute RDMA GPU Monitoring, HPC RDMA plugins, Block Volume
  Management e Bastion estavam desabilitados.
- A primeira tentativa de criação retornou `Out of capacity` para A1 em AD-1;
  uma tentativa posterior criou a instância. Capacidade A1 pode variar.

## VCN, VNIC e superfície de rede

- VCN `emporio-vcn`, CIDR informado `10.0.0.0/16`.
- Internet Gateway `emporio-igw`.
- Route table `emporio-public-rt`: rota default `0.0.0.0/0` para o Internet
  Gateway; associada à subnet, não diretamente ao gateway.
- Subnet regional pública `emporio-public-subnet-sp`, CIDR `10.0.0.0/24`, com
  DNS hostname habilitado. Domínio gerado pela OCI:
  `emporiopublicsu.emporiovcn.oraclevcn.com`.
- Security List própria `emporio-public-sl`: ingress SSH TCP/22 limitado ao
  IPv4 público de saída do operador em `/32`; egress stateful para
  `0.0.0.0/0` em todos os protocolos. A lista default não foi escolhida para a
  subnet. Nenhum NSG foi associado.
- VNIC `emporio-primary-vnic`; IPv4 privado automático e IPv4 público automático
  atribuído. IPv6 não habilitado. O IP público não é persistido aqui: endereço
  pode mudar e não é segredo necessário ao contexto.
- Nenhuma regra ingress para HTTP/HTTPS, Dokploy (3000), SSH de qualquer origem,
  nem para portas de aplicação foi planejada. Cloudflare Tunnel será outbound.
- **Pós-instalação Dokploy (2026-11-11):** `dokploy v0.31.0` instalado; os
  serviços `dokploy` e `dokploy-postgres` foram reportados `1/1 Running`, e o
  container `dokploy-traefik` `Up`. O projeto `Emporio Staging` e um serviço
  Compose foram criados no painel, ainda sem YAML nem app implantado.
- Docker publica 3000 e Traefik publica 80/443 TCP e 443 UDP nas interfaces do
  host; o Nmap TCP pós-instalação (22/80/443/3000), executado da origem
  autorizada, mostrou só 22/tcp aberta e as outras três filtradas. A barreira é
  a Security List OCI; manter sem ingress web.

## Acesso administrativo e hardening observado

- Usuário de operação: `ubuntu`; `sudo whoami` retornou `root`. Nenhum segundo
  usuário Linux foi criado para separar ambientes.
- Login SSH por chave validado em nova sessão após reboot. A chave privada fica
  sob controle do operador no WSL; conteúdo, fingerprint e caminho local não
  são registrados neste repositório.
- Configuração efetiva de `sshd -T` após ajuste:
  `PermitRootLogin no`, `PubkeyAuthentication yes`,
  `PasswordAuthentication no`, `KbdInteractiveAuthentication no`.
  Reload do serviço SSH e novo login como `ubuntu` foram validados.
- Nmap TCP `-p-` executado pelo operador a partir da origem autorizada: somente
  `22/tcp open`; 65.534 portas apareceram filtradas. Isso comprova o caminho a
  partir daquela origem e naquele momento; não é um scan UDP nem prova de
  firewall do host. A restrição de origem deriva da Security List OCI.
- `unattended-upgrades`/timers já estavam ativos na imagem: `APT::Periodic` para
  refresh e upgrade diário; Allowed Origins inclui Noble, Noble Security e ESM
  security; os pockets `noble-updates`, `proposed` e `backports` estavam
  comentados. `Automatic-Reboot` não tinha valor explícito; padrão Ubuntu é não
  reiniciar automaticamente. Isso não atualiza imagens Docker/Dokploy.
- A cópia revisada do instalador removeu `swarm leave --force` e a remoção da
  rede, aborta em falha do Docker pinado e configura `/etc/dokploy` como 0750;
  o operador confirmou por `stat` a permissão efetiva `750 root:root`.
  UFW e Fail2ban não foram verificados/configurados.

## Plano de ambientes e limites

- Decisão do operador: começar por **staging** e, por falta de uma segunda
  máquina disponível, hospedar futuramente **staging e produção na mesma VPS**.
  Nenhum ambiente de aplicação está implantado ainda e o PostgreSQL de staging
  ainda não foi criado. O repo contém o Compose da TASK-INFRA-020, ainda não
  carregado no serviço do painel.
- Contrato aprovado na TASK-INFRA-019: PostgreSQL 17 local com bootstrap,
  migrador e runtime separados; sem dados de produção. Back e Radar terão
  recursos/credenciais R2 de staging dedicados e separados; Radar usa R2 real.
  SMTP real terá credencial distinta da produção e STARTTLS+AUTH, com remetente
  de teste e destinatários controlados. Hostnames aprovados:
  `staging.emporiob2b.com.br`, `api-staging.emporiob2b.com.br` e
  `media-staging.emporiob2b.com.br` para Custom Domain do bucket público R2.
  Buckets, credenciais, sender e dados SMTP concretos ainda não foram provisionados e
  nenhum segredo é persistido aqui.
- Os ambientes serão stacks/projetos Dokploy distintos, com redes isoladas,
  volumes, domínios, credenciais e dados separados; staging nunca recebe
  credenciais/dados de produção. Essa separação é operacional, não uma fronteira
  forte: os stacks compartilham kernel, host e Docker daemon; comprometimento do
  host pode afetar ambos e há contenção por CPU/RAM/disco a resolver.
- **Limites aprovados (decisão do operador de 2026-11-13):** teto de 2 CPU e
  12 GiB por stack — divisão meio a meio da VPS de 4 OCPUs/24 GB entre staging
  e produção futura; substitui o teto inicial de 1,5 CPU/3 GiB. O Compose de
  staging atual soma 1,75 CPU/3.375 GiB nos long-lived (incluindo o Prometheus
  de métricas), dentro do teto, e permanece válido para o primeiro deploy.
  Limites são tetos, não reservas: host/Dokploy/Docker consomem ~1–2 GB
  (estimativa) e a soma dos tetos (24 GiB) não deixa folga de sistema se ambos
  os stacks estourarem simultaneamente — monitorar a folga real do host antes
  da produção entrar. Métricas de staging (Prometheus com `remote_write`
  dentro do Compose) são **artefato existente, não implantado**; logs via
  `dokploy-vector` → Grafana Cloud Loki no host seguem **planejados** — a
  conta/stack Grafana Cloud é existente (operador, 2026-11-13:
  `smallmarzipan1294`, `prod-sa-east-1`, free tier; endpoints/IDs verificados
  em `estado_atual.md`/`decisoes.md`), mas o provider Grafana Loki ainda não
  foi configurado no Dokploy e a geração dos tokens não está confirmada
  (`../../docs/staging-compose.md:106-118`; `decisoes.md`).
- A proteção escolhida para o staging é Cloudflare Access na borda, não Nginx
  Basic Auth. **Existente (2026-11-13):** zona `emporiob2b.com.br` Active na
  conta Cloudflare (NS `dora`/`gannon.ns.cloudflare.com`); túnel remotamente
  gerenciado `emporio-staging` (`87a7e326-bc1b-43fb-9091-212fa38e0fdb`)
  criado no dashboard com status Inactive — esperado, pois o connector ainda
  não está implantado na VPS e liga via compose/Dokploy no deploy. Rotas de
  published application criadas pelo operador (reportadas):
  `staging.emporiob2b.com.br` → `http://front:4000` e
  `api-staging.emporiob2b.com.br` → `http://api:8080`; o painel atual exige
  URL com prefixo `http://`. **DNS verificado (2026-11-13):** `dig` no
  resolver local e nos autoritativos `dora`/`gannon` retorna
  `188.114.96.2`/`188.114.97.2` (borda Cloudflare, proxied) para os dois
  hostnames; antes eram NXDOMAIN. O alvo CNAME
  `<tunnel-id>.cfargotunnel.com` fica oculto pelo proxy (comportamento
  correto); a conferência visual do alvo no dashboard é reportada pelo
  operador. **Access verificado (2026-11-13):** `curl -sI` em
  `https://staging.emporiob2b.com.br/` e `https://api-staging.emporiob2b.com.br/`
  retorna HTTP 302 com Location para
  `https://soft-salad-0948.cloudflareaccess.com/cdn-cgi/access/login/<hostname>`
  — barreira de login ativa nos dois hostnames antes do túnel; time domain
  Zero Trust `soft-salad-0948`. A aplicação Access foi criada pelo operador
  antes das rotas; policy/IdP não auditados em detalhe. O 302 prova
  interceptação, não que o operador consegue logar — primeiro login real
  pendente. SSL/TLS da zona em Full (strict) é reportado pelo operador, não
  verificado independentemente (HTTPS funcionando sem loop é consistente).
  `media-staging.emporiob2b.com.br` não configurado: R2 ainda não
  provisionado; não passa pelo túnel. Nome/id do túnel e time domain são
  fatos não secretos; tokens, cookies e o JWT meta das URLs de login não são
  registrados.
- Dokploy está instalado; o painel permanece acessível pelo SSH forward local
  `127.0.0.1:13000`. O operador adiou MFA/passkey temporariamente e aceitou a
  exceção; follow-up em TASK-INFRA-022. Até lá, não criar rota não-SSH para o
  painel. Nunca publicar a porta 3000. 80/443 de entrada também permanecem
  bloqueadas na OCI; `cloudflared` inicia conexões outbound.
- Shape ARM64 torna `linux/arm64` requisito de imagens GHCR. A skill CI/CD foi
  atualizada para exigir `linux/amd64,linux/arm64`; os workflows versionados de
  Backend e Radar declaram ambas as plataformas e o Front não tem workflow
  (publicação manual). Gate de publicação ARM64 verificado em 2026-11-13: as
  três imagens de staging têm manifests `linux/amd64` + `linux/arm64`
  confirmados por `docker buildx imagetools inspect` executado pelo operador
  em máquina autenticada no GHCR (saída colada nesta sessão; tags e index
  digests em `estado_atual.md`). As tags Back/Radar coincidem com o formato
  dos workflows, evidenciando execução dos jobs de publicação; os runs no
  Actions não foram auditados. O perfil staging da imagem do Front está
  verificado em 2026-11-13 (`grep` na imagem publicada: URL `api-staging`
  compilada nos bundles browser e SSR; comando e digest em `estado_atual.md`)
  — todos os gates de imagem da TASK-INFRA-021 fechados. Pendente: validar
  run/deploy no staging ARM64 antes do deploy de produção.
- Não há public IP, OCID, chave SSH, token de túnel, token Dokploy, credenciais
  Supabase/R2/SMTP ou tokens/segredos de ambiente neste contexto. Os endpoints
  e instance IDs do Grafana Cloud registrados são valores não secretos
  (usuários de basic auth), presentes também no example versionado.
