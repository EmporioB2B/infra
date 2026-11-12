# VPS Oracle Cloud — estado factual

Snapshot baseado na console OCI e em comandos executados pelo operador em
2026-11-11. Não é inventário obtido por API e pode ficar desatualizado; confira
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
- A proteção escolhida para o staging é Cloudflare Access na borda (ainda não
  configurado), não Nginx Basic Auth. Cloudflare Tunnel e rotas DNS também ainda
  não foram criados.
- Dokploy está instalado; o painel permanece acessível pelo SSH forward local
  `127.0.0.1:13000`. O operador adiou MFA/passkey temporariamente e aceitou a
  exceção; follow-up em TASK-INFRA-022. Até lá, não criar rota não-SSH para o
  painel. Nunca publicar a porta 3000. 80/443 de entrada também permanecem
  bloqueadas na OCI; `cloudflared` inicia conexões outbound.
- Shape ARM64 torna `linux/arm64` requisito de imagens GHCR. A skill CI/CD foi
  atualizada para exigir `linux/amd64,linux/arm64`; workflows de aplicação ainda
  não existem, portanto build/publish multiarch é gate antes de deploy.
- Não há public IP, OCID, chave SSH, token de túnel, token Dokploy, credenciais
  Supabase/R2/SMTP ou valores de ambiente reais neste contexto.
