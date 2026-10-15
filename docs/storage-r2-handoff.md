# Handoff — leitura de documentos em quarentena no R2

Este documento prepara a configuração equivalente para produção. Ele não
executa nenhuma alteração no Cloudflare, no R2 ou no Dokploy.

## Contrato do Backend

O Backend usa uma credencial separada para emitir a URL pré-assinada de
leitura do objeto que permanece em quarentena:

```text
APP_STORAGE_READ_ONLY_QUARENTENA_R2_ENDPOINT=https://<account>.r2.cloudflarestorage.com
APP_STORAGE_READ_ONLY_QUARENTENA_R2_ACCESS_KEY_ID=<chave dedicada>
APP_STORAGE_READ_ONLY_QUARENTENA_R2_SECRET_ACCESS_KEY=<segredo dedicado>
APP_STORAGE_R2_QUARENTENA_BUCKET=<bucket de quarentena>
APP_STORAGE_R2_QUARENTENA_PREFIX=quarantine/
```

Esses valores devem ser preenchidos somente no ambiente do Dokploy; este
arquivo não contém valores reais.

## Permissão desejada

Criar uma API token/key própria, diferente das credenciais read-write e
read-only existentes, com o menor escopo efetivo:

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject"],
  "Resource": ["arn:aws:s3:::<bucket-de-quarentena>/quarantine/*"]
}
```

Não conceder `ListBucket`, `PutObject`, `DeleteObject`, escrita de qualquer
tipo, nem incluir recursos dos buckets privado ou público nessa credencial. A
quarentena também não deve ter leitura anônima nem domínio público; a
exposição pública de `media` é uma regra separada e não é uma permissão
concedida à credencial de quarentena.

O painel/API do R2 deve ser conferido no momento do handoff: se a permissão
Object Read do Cloudflare só puder ser limitada ao bucket e não ao prefixo,
não registrar a configuração como equivalente. Nesse caso, usar um bucket de
quarentena dedicado ou obter uma política com escopo de prefixo antes do
deploy; não reutilizar uma credencial mais ampla como atalho.

## CORS do bucket de quarentena

Configurar somente as origens efetivamente usadas pelo Front em produção e
confirmar `GET` e `HEAD` para leitura. Preservar os métodos já exigidos pelo
fluxo de upload, sem adicionar métodos de escrita apenas para este endpoint.
Não habilitar `*` junto com credenciais. O CORS do
bucket público `media` é uma decisão separada e não deve ser copiado para a
quarentena.

## Checklist de handoff

- [ ] Confirmar bucket e prefixo reais no ambiente do Dokploy, sem os gravar
      neste repositório.
- [ ] Criar a credencial dedicada com Object Read e escopo mínimo disponível.
- [ ] Confirmar por teste negativo que o token não tem listagem ampla,
      escrita, deleção ou escopo nos buckets privado/público.
- [ ] Confirmar URL pré-assinada de `GET` e expiração pelo TTL do Backend.
- [ ] Aplicar e testar CORS `GET`/`HEAD` somente para as origens permitidas.
- [ ] Registrar a data e o escopo da credencial no runbook de produção, nunca
      o valor da chave/segredo.
- [ ] Só então atualizar as variáveis no Environment do Dokploy e executar o
      deploy com autorização explícita do operador.
