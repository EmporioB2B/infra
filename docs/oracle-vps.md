# VPS Oracle Cloud — provisionamento e estado

Este documento registra a configuração inicial reportada pelo operador para a
VPS do Emporio B2B. É um snapshot, não um inventário remoto: confirme os valores
na console OCI antes de alterar rede, instância ou firewall. Não registra IP
público, OCIDs, chaves, tokens ou credenciais.

## Objetivo e estado

- A VPS será usada primeiro para **staging**; depois, por falta de outra
  máquina, a intenção aprovada é hospedar staging e produção no mesmo host.
- Em 2026-11-11 a instância foi criada e o acesso SSH testado. Dokploy `v0.31.0`
  foi instalado; o projeto `Emporio Staging` e um serviço Compose foram criados
  no painel. O repo Infra contém `compose/docker-compose.staging.yml`, mas o
  painel ainda não recebeu YAML/configuração e não há aplicações implantadas.
  A borda Cloudflare de staging foi configurada em 2026-11-13 (túnel
  `emporio-staging`, DNS e Access verificados); o connector liga no deploy.
- Staging e produção precisarão usar stacks, redes, volumes, domínios, dados e
  segredos distintos. Isso não é isolamento forte: o kernel, host e daemon Docker
  serão compartilhados. Não colocar dados nem credenciais de produção no staging.
- A proteção do staging escolhida é Cloudflare Access na borda; não será usado
  Nginx Basic Auth como portão. Hostnames aprovados:
  `staging.emporiob2b.com.br` e `api-staging.emporiob2b.com.br`.

## Instância e armazenamento

| Item | Configuração reportada |
|---|---|
| Nome | `emporio-infra-sp` |
| Região / AD | `SA-VINHEDO-1` / `AD-1` (São Paulo) |
| Shape | `VM.Standard.A1.Flex`, 4 OCPUs ARM, 24 GB RAM, 4 Gbps; console marcou Always Free-eligible |
| Sistema | Canonical Ubuntu 24.04 Minimal aarch64, build `2026.10.27-0` |
| Boot volume | 100 GB, Balanced, 10 VPU; criptografia em trânsito ligada; chave gerenciada pela Oracle |
| Volumes adicionais | Nenhum associado |
| Manutenção | OCI escolhe opção de migração; restart após manutenção habilitado |

O selo Always Free foi observado na console para o shape, mas não se verificou
faturamento nem limites totais da tenancy. A primeira tentativa A1 retornou falta
temporária de capacidade em AD-1; a instância foi criada numa tentativa
posterior.

## Topologia OCI criada

```text
Internet
  └─ Internet Gateway: emporio-igw
       └─ route table emporio-public-rt: 0.0.0.0/0 → emporio-igw
            └─ public regional subnet: 10.0.0.0/24
                 └─ emporio-primary-vnic (IPv4 privado + público automáticos)
```

- VCN `emporio-vcn`, CIDR `10.0.0.0/16`.
- Subnet `emporio-public-subnet-sp`, regional, pública; DNS hostname habilitado.
  Domínio privado gerado: `emporiopublicsu.emporiovcn.oraclevcn.com`.
- Security List associada: `emporio-public-sl`; sem NSG associado.
- Ingress planejado/configurado: apenas TCP/22 cujo source é o IP público de
  saída do operador em `/32`. O valor do IP é omitido porque pode mudar.
- Egress: stateful para `0.0.0.0/0` em todos os protocolos. Isso é rota/saída,
  não regra de entrada.
- IPv6 não foi habilitado. Nenhum ingress 80/443/3000 ou de portas de aplicação.
- O IP público foi atribuído automaticamente, mas não deve ser tratado como
  permanente sem confirmação de reserva na OCI.

## Acesso e verificações executadas

- Acesso como `ubuntu` via chave SSH funcionou após reboot. `sudo whoami`
  retornou `root`; não foi criado outro usuário Linux.
- Configuração efetiva do SSH após ajuste: chave pública habilitada, senha e
  keyboard-interactive desabilitados, `PermitRootLogin no`. O operador manteve
  a sessão anterior aberta e validou um novo login `ubuntu` após reload.
- Nmap TCP completo (`-p-`) a partir da origem autorizada reportou `22/tcp open`
  e 65.534 portas filtradas. É uma prova daquela origem e instante, não scan
  UDP nem inventário de listeners locais.
- Nmap TCP pós-instalação nos ports 22/80/443/3000, da origem autorizada,
  reportou somente `22/tcp open`; as outras três ficaram filtradas. Dokploy e
  Traefik publicam 3000/80/443 no host, então a Security List OCI é essencial:
  não adicionar ingress web. O painel foi usado por SSH forwarding em
  `127.0.0.1:13000`. O operador adiou MFA/passkey temporariamente e aceitou a
  exceção; TASK-INFRA-018 foi encerrada com essa limitação e TASK-INFRA-022
  acompanha o MFA. Não criar rota não-SSH para o painel enquanto pendente.
- Ubuntu 24.04 já tinha `apt-daily.timer` e `apt-daily-upgrade.timer` enabled;
  `APT::Periodic::Update-Package-Lists` e
  `APT::Periodic::Unattended-Upgrade` estavam em `1`. Allowed Origins inclui
  Noble, Noble Security e ESM security; `noble-updates`, `proposed` e
  `backports` estavam comentados. `Automatic-Reboot` não estava explicitamente
  definido (default Ubuntu: não reiniciar automaticamente). Essas atualizações
  tratam pacotes do SO, não imagens Docker ou releases do Dokploy.
- Dokploy e Docker/Swarm estão instalados; serviços `dokploy` e
  `dokploy-postgres` reportados 1/1 Running e `dokploy-traefik` Up. A cópia
  revisada do instalador define `/etc/dokploy` como 0750; o operador confirmou
  `stat` como `750 root:root`. UFW, Fail2ban, rotação de logs Docker, backup/snapshot do
  boot volume e recursos Cloudflare não foram configurados/verificados.
- Contrato da TASK-INFRA-019: PostgreSQL 17 local, fluxo administrativo/
  migrador/runtime separado e sem dados copiados da produção; R2 de staging
  dedicado por serviço; SMTP real com credencial distinta da produção e
  STARTTLS+AUTH. Hostnames aprovados: `staging.emporiob2b.com.br`,
  `api-staging.emporiob2b.com.br` e `media-staging.emporiob2b.com.br` (Custom
  Domain do bucket público R2). Recursos externos e valores concretos ainda
  não foram provisionados; nenhum segredo é registrado. Consulte
  [`staging-contract.md`](staging-contract.md).

## Guardrails operacionais e próximos gates

1. Manter ingress OCI restrito a SSH `/32`; não abrir 80/443/3000. O túnel
   Cloudflare é iniciado de dentro da VPS.
2. Manter o painel apenas via SSH forwarding; MFA/passkey foi adiado com
   exceção aceita. Concluir TASK-INFRA-022 antes de criar rota externa de admin.
3. O Dokploy v0.31.0 foi instalado pela cópia revisada e digest-verificada do
   release asset; não repetir o instalador sem revisar impactos. `/etc/dokploy`
   foi verificado como `750 root:root`.
4. Usar Cloudflare Access no staging e rotas do Tunnel apenas para hostnames
   aprovados. O domínio público de mídia R2 não passa pela VPS.
5. Imagens de aplicação para esta instância devem incluir `linux/arm64`; a
   automação de CI/CD multiarch ainda é pré-requisito.
6. Separar totalmente credenciais, banco, storage e dados do staging e da
   produção. Isolamento por stacks/redes Docker no mesmo host não equivale a
   máquinas isoladas.

Ver também o contexto detalhado em
[`../.opencode/context/vps_oracle.md`](../.opencode/context/vps_oracle.md).
