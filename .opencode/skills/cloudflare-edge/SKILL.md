---
name: cloudflare-edge
description: Use when configuring or reviewing the Cloudflare edge for Emporio B2B; remotely-managed tunnels, ingress routes, DNS, firewall egress, forwarded headers, same-site cookies, media on R2 custom domain and caching.
---

# Borda Cloudflare

A borda é o único ponto de entrada público. TLS termina na Cloudflare; a
VPS não expõe porta inbound HTTP/HTTPS e não gere certificado. Fontes:
documentação oficial Cloudflare Tunnel (seção `/tunnel`, pós-2026),
Create-remote-tunnel, R2 Public Buckets e o guia Cloudflare Tunnels do
Dokploy.

## Modelo e garantias

- túnel **remotamente gerenciado**: objeto persistente no dashboard
  (Networking → Tunnels), identificado por UUID; o `cloudflared` da VPS
  roda com `--token`; ingress configurado no dashboard, não em arquivo
  local;
- conexão **outbound-only** e pós-quântica: o cloudflared abre 4 conexões
  longas para pelo menos 2 datacenters; nenhuma porta inbound é necessária;
  Authenticated Origin Pulls **não se aplica** a túnel (não há listener);
- SSL/TLS da zona em **Full** ou **Full (strict)** — nunca Flexible (loop
  de redirect com proxies);
- tráfego passa por CDN/WAF/DDoS da Cloudflare antes do túnel.

## cloudflared no compose de prod

- imagem pinada por tag específica (não `:latest`) e
  `--no-autoupdate` no comando — atualização é decisão de deploy nossa;
- token via env do Dokploy (`CLOUDFLARED_TUNNEL_TOKEN`); nunca no repo;
- membro da rede `apps` (resolve `front` e `api` por nome de serviço);
- rota por hostname no dashboard (Published application routes):
  - `emporiob2b.com.br` → `http://front:4000`;
  - `api.emporiob2b.com.br` → `http://api:8080`;
- alternativas documentadas e seus trade-offs:
  - apontar para `dokploy-traefik:80` (guia do Dokploy): usa o Traefik
    embutido do Dokploy + Domains do painel — rejeitado por decisão
    (ver `decisoes.md`), o nosso cloudflared roteia direto aos containers;
  - wildcard: CNAME `*` → `<tunnel-id>.cfargotunnel.com` + rota `*` — só
    adotar se houver múltiplos subdomínios;
- path em rota de túnel **não é removido/reescrito** (o serviço recebe o
  path completo); rewrite é regra de Transform na borda ou proxy local —
  não usamos path routing no MVP;
- hostname multi-nível (ex.: `a.b.dominio`) exigiria Advanced Certificate;
  `api.` e `media.` são single-level, OK no plano gratuito;
- HA: réplicas são instâncias adicionais de cloudflared no mesmo túnel (até
  25); com VPS única o ganho é marginal — registrar como melhoria futura,
  não subir réplica no mesmo host sem motivo.

## Firewall e parâmetros

- egress obrigatório: porta **7844** TCP/UDP para
  `region1.v2.argotunnel.com` e `region2.v2.argotunnel.com`
  (http2/quic); 443 opcional (autoupdate — desligado — e Access JWT);
- inbound: bloquear tudo exceto SSH; UFW sozinho **não cobre portas
  publicadas pelo Docker** (Docker escreve iptables direto) — na VPS usar
  `ufw-docker` ou, melhor, não publicar porta nenhuma (nosso desenho);
- run parameters úteis: `--loglevel info`, `--protocol auto` (quic com
  fallback http2), `--metrics` só em 127.0.0.1 se formos coletar;
- origin parameters: `httpHostHeader` não é necessário (Host já chega
  correto); `connectTimeout` default 30s; `noTLSVerify` é irrelevante
  (origens HTTP) e proibido se um dia houver origem HTTPS.

## DNS dos três domínios

- `emporiob2b.com.br` e `api.emporiob2b.com.br`: o dashboard do túnel cria
  os registros CNAME `<tunnel-id>.cfargotunnel.com` ao adicionar as rotas
  (proxy on);
- `media.emporiob2b.com.br`: **não é túnel** — Custom Domain do bucket
  público R2 (a zona precisa estar na mesma conta Cloudflare do bucket);
- decisão pendente: `www` (recomendado: redirect na borda para o apex);
- nunca criar CNAME manual apontando para subdomínio `r2.dev` (caminho não
  suportado).

## Media no R2 (bucket público)

- produção usa **custom domain** (`media.`), não a URL `r2.dev`: a r2.dev é
  rate-limitada, para desenvolvimento, e não suporta WAF/cache/Bot
  Management; se o bucket tiver r2.dev habilitado, **desabilitar** em
  produção;
- cache: por padrão a Cloudflare só cacheia certas extensões — para fotos
  de produto configurar regra **Cache Everything** no domínio `media`
  (avaliar Smart Tiered Cache);
- objetos públicos do marketplace são servidos por chave opaca publicada
  pelo Back (`APP_STORAGE_R2_PUBLICO_BASE_URL=https://media.emporiob2b.com.br`);
  o bucket privado e o de quarentena **nunca** viram domínio público;
- proteção extra de documento privado não passa por aqui: presigned read do
  Back (decisão de aplicação).

## Headers, cookies e CORS (origem = nosso stack)

- o cloudflared injeta `X-Forwarded-For/Proto/Host`; o Back confia via
  `forward-headers-strategy: framework`;
- rate limit por IP do Back (`VALIDACAO_CNPJ_TRUSTED_PROXIES`) deve listar
  a origem confiável (rede do túnel/containers), senão todo cliente parece
  o proxy — ou o IP real não é usado; configurar na TASK-INFRA-004;
- front e api são **same-site** (mesmo eTLD+1 `emporiob2b.com.br`):
  cookie `SameSite=Lax` host-only da api é enviado em fetch
  cross-origin do front; `Secure=true` em prod é satisfeito pelo HTTPS da
  borda; CORS com credentials é obrigatório (cross-origin) e o profile
  `prod` já default `https://emporiob2b.com.br`;
- o SSR do Front valida o header `Host` contra allowlist compilada — o
  domínio público precisa estar nela (task no repo Front, TASK-INFRA-002);
  **não** desabilitar a validação como atalho.

## Proibições

- não publicar serviço interno por túnel, DNS ou firewall: actuator 8081,
  radar, postgres, rustfs, mailpit, painel Dokploy (porta 3000 — acessar
  por túnel privado/VPN com Access, nunca pública sem proteção);
- não criar rota sem hostname explícito (catch-all) no ingress;
- não expor o token do túnel (ele dá acesso para rotear tráfego à VPS);
  rotação imediata em suspeita;
- não usar SSL Flexible;
- não desabilitar WAF/proteções da zona para "resolver" erro de aplicação.
