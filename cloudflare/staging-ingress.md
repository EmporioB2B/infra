# Handoff Cloudflare — staging

Este arquivo é uma instrução para configuração posterior; nenhuma alteração foi
aplicada ao dashboard Cloudflare, DNS, Tunnel, Access ou R2.

## Tunnel remoto

Usar Tunnel remotamente gerenciado, iniciado outbound pelo serviço `cloudflared`
do Compose. O token (`CLOUDFLARED_TUNNEL_TOKEN`) existe somente no Environment/
Secrets Provider do serviço Dokploy. Não criar arquivo local de credentials nem
rota de Tunnel para o painel Dokploy.

Configurar somente estas Published Application Routes no dashboard:

| Hostname | Serviço de origem |
|---|---|
| `staging.emporiob2b.com.br` | `http://front:4000` |
| `api-staging.emporiob2b.com.br` | `http://api:8080` |

Aplicar Cloudflare Access aos dois hostnames. Não criar rotas para Postgres,
Radar, metrics/actuator 8081/8082, Dokploy ou qualquer porta do host. A VPS não
deve receber ingress OCI HTTP/HTTPS; o Tunnel é outbound.

## Mídia pública R2

Associar `media-staging.emporiob2b.com.br` como Custom Domain **ao bucket público
R2 dedicado de staging do Back**, não ao Tunnel e nunca ao bucket de produção.
Configurar `APP_STORAGE_R2_PUBLICO_BASE_URL` e `APP_EMAIL_MEDIA_BASE_URL` com
`https://media-staging.emporiob2b.com.br`. Este hostname serve objetos públicos;
não associá-lo ao bucket privado/quarentena.

Política de cache/WAF, regras de exposição e custom domain devem ser revisadas
no dashboard antes de publicar fotos. Este handoff não provisiona recursos nem
define regra de cache.
