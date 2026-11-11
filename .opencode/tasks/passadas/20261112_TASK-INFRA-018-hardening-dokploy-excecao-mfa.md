# TASK-INFRA-018 — Hardening pós-instalação do Dokploy

**Status:** encerrada em 2026-11-12 com exceção temporária de MFA aceita pelo
operador; não declarar conformidade total do checklist de hardening.
**Repo alvo:** Infra + VPS Oracle OCI.

## Entregas e evidências reportadas

- Dokploy `v0.31.0` instalado; serviços `dokploy` e `dokploy-postgres` 1/1
  Running, Traefik Up. Projeto `Emporio Staging` e recurso Compose criados,
  sem YAML nem aplicação implantada.
- Cópia revisada e digest-verificada do instalador removeu o leave forçado do
  Swarm e a limpeza da rede, aborta em vez de fallback Docker não pinado e usa
  `/etc/dokploy` com modo 0750.
- O operador executou `sudo stat -c '%a %U:%G %n' /etc/dokploy`; saída:
  `750 root:root /etc/dokploy`.
- SSH efetivo: `PermitRootLogin no`, `PubkeyAuthentication yes`,
  `PasswordAuthentication no`, `KbdInteractiveAuthentication no`; login novo
  como `ubuntu` e `sudo` funcionaram.
- Painel acessado pelo operador por SSH forwarding local
  `127.0.0.1:13000`, não por acesso direto ao IP público.
- Nmap TCP pós-instalação de 22/80/443/3000, da origem autorizada: apenas
  `22/tcp open`; 80/443/3000 filtradas. Docker publica localmente 80/443/3000,
  portanto ingress OCI continua limitado a SSH.
- Contextos e `docs/oracle-vps.md` atualizados com estado e limites observados.

## Exceção de segurança aceita

O operador decidiu **não habilitar MFA/passkey neste momento**. O requisito de
MFA do hardening Dokploy permanece pendente e está rastreado em
`tasks/futuras/TASK-INFRA-022-mfa-painel-dokploy.md`.

Enquanto a exceção estiver ativa:

- painel somente pelo SSH forwarding local;
- não publicar rota Tunnel/Access, DNS público ou ingress OCI para o painel;
- o Cloudflare Access de staging cobre Front/API, não o painel Dokploy.

## Limites da evidência

- Nmap foi feito da origem autorizada e para TCP; não prova comportamento de
  UDP nem de outra origem, embora a Security List OCI permaneça `/32` para SSH.
- 1/1 Running não equivale a healthcheck funcional nem prova aplicação staging.
- MFA não foi habilitado; esta task é encerrada com exceção explicitamente
  aceita, não como hardening completo.
- Nenhum valor de chave, IP público, credencial ou token foi arquivado.
