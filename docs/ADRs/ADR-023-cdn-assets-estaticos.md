# ADR-023 — CDN para Assets Estáticos (Imagens, JS, CSS)

**Status:** Aceito  
**Data:** 2026-03-10  
**Decisores:** Time de Arquitetura  
**Tags:** `frontend` `infraestrutura` `performance` `edge`

---

## Contexto

O FoodeApp possui dois canais de frontend:

- **Web** (React) — produz um bundle de JS, CSS, HTML e assets (imagens, fontes, ícones)
- **Mobile** (React Native) — distribui via App Store / Play Store, mas consome assets remotos (imagens de pratos, banners, logos de restaurantes)

Sem um CDN:

- Todos os requisições de assets chegam diretamente nos pods do Kubernetes, consumindo banda e CPU de serve estático que nada têm a ver com a lógica da aplicação
- Usuários geograficamente distantes do cluster sofrem latência alta no carregamento
- Um deploy que invalida o bundle inteiro causa pico de tráfego no servidor de origem
- Não há camada de cache HTTP entre o browser e o servidor

A arquitetura já inclui **Cloudflare** como WAF/DNS visível nos diagramas (ver [diagrama de arquitetura](../diagrams/draft/Togther/arquitetura_ueat.v1.drawio)); o CDN já está na topologia — esta ADR formaliza as regras de uso.

---

## Decisão

**Usar Cloudflare CDN para distribuição de todos os assets estáticos do FoodeApp.**

### Escopo do CDN

| Tipo de asset | Mutável? | Estratégia de cache |
|---|---|---|
| JS bundle (com hash no nome) | Não (imutável) | `Cache-Control: public, max-age=31536000, immutable` |
| CSS bundle (com hash no nome) | Não (imutável) | `Cache-Control: public, max-age=31536000, immutable` |
| `index.html` | Sim (muda a cada deploy) | `Cache-Control: no-cache` (sempre revalidar) |
| Imagens de produtos/restaurantes (CDN-hosted) | Raramente | `Cache-Control: public, max-age=86400` + purge no upload |
| Fontes e ícones estáticos | Não (imutável) | `Cache-Control: public, max-age=31536000, immutable` |
| Assets de upload do usuário (fotos de perfil) | Raramente | `Cache-Control: public, max-age=3600` + purge via API |

### Regra de imutabilidade

O build do React (Vite/CRA/Next) gera nomes com hash de conteúdo por padrão:

```
/assets/index.a1b2c3d4.js
/assets/style.e5f6a7b8.css
```

Qualquer mudança no conteúdo produz um hash diferente → URL diferente → sem problema de cache stale. O `index.html` referencia os hashes atuais e deve **nunca** ser cacheado agressivamente.

### Topologia de acesso

```
Browser / App
    │
    ▼
Cloudflare CDN (PoP geográfico)
    │
    ├── HIT: serve do cache do edge (sem chegar no cluster)
    │
    └── MISS: encaminha para Origin (Kubernetes Ingress)
              └── Retorna asset + Cloudflare armazena no edge
```

### Separação de responsabilidades

| Camada | Cuida de |
|---|---|
| Cloudflare CDN | Cache geográfico de assets estáticos; WAF; DDoS mitigation |
| Kong (ADR-009) | Roteamento de **chamadas de API** (JSON, autenticação, rate limit) |
| Kubernetes Ingress | Fallback origin para MISS de CDN + roteamento interno |

> **Regra:** Assets estáticos **nunca** devem passar pelo Kong. Kong processa APIs. O CDN é a borda para arquivos.

### Invalidação no deploy

1. O pipeline CI/CD (Terraform — ADR-020) faz upload dos novos artefatos para o bucket/origin
2. Arquivos com hash novo criam URLs novas — sem necessidade de purge
3. `index.html` precisa de purge explícito após deploy:
   ```
   curl -X POST "https://api.cloudflare.com/client/v4/zones/{ZONE_ID}/purge_cache" \
     -H "Authorization: Bearer $CF_TOKEN" \
     -d '{"files":["https://foodeapp.com/index.html"]}'
   ```
4. Imagens que sofreram update (ex: foto de produto editada) → purge via API no evento de upload

### CORS

Assets são servidos do mesmo domínio (`foodeapp.com`) ou de um subdomínio dedicado (`cdn.foodeapp.com`). Se usar subdomínio:

```
Access-Control-Allow-Origin: https://foodeapp.com
```

Fontes e fontes de terceiros precisam de configuração explícita de CORS no Cloudflare Page Rule.

### HTTPS

Cloudflare fornece TLS automático (Full Strict). Todo acesso a assets é HTTPS obrigatório — HTTP deve ser redirecionado automaticamente via regra de Cloudflare.

---

## Consequências

### ✅ Positivas

- **TTFB menor** — assets são servidos do PoP mais próximo do usuário (Cloudflare tem >300 PoPs)
- **Redução de carga no cluster** — requisições de assets não chegam aos pods; origem só é chamada em MISS
- **Cache-busting seguro** — hashing de arquivo garante que o browser sempre recebe a versão correta sem precisar de TTL curto
- **WAF e DDoS já inclusos** — Cloudflare já na topologia serve os dois propósitos (CDN + segurança de borda)
- **React Native se beneficia** — imagens de pratos e banners servidas via CDN chegam mais rápido no app

### ❌ Negativas

- **Custo** — Cloudflare tem plano free generoso para assets, mas uploads e cache purge em escala têm custo
- **Complexidade no deploy** — pipeline precisa executar purge do `index.html` após cada release
- **Debug de cache** — investigar "por que o usuário vê versão antiga?" requer entender o fluxo CDN → cache do browser

### ➖ Neutras

- **Cache do browser ainda existe** — CDN não substitui o cache local do browser; `max-age` dos arquivos imutáveis é longo de propósito
- **Cloudflare Analytics** — passa a ter visibilidade de tráfego de assets separado do tráfego de API

---

## Alternativas Consideradas

| Alternativa | Por que não |
|---|---|
| AWS CloudFront | Não usamos AWS; adiciona vendor desnecessário ao lado do Cloudflare já presente |
| Azure CDN | Mesmo motivo |
| Servir assets direto do Kubernetes Ingress (sem CDN) | Latência alta; carga nos pods; sem edge cache geográfico |
| Nginx no cluster como servidor de estáticos | Funciona para desenvolvimento, mas não resolve latência geográfica nem escala |

---

## Relacionamentos

- **[ADR-003](ADR-003-stack-tecnologias.md)** — React Web é quem gera os bundles JS/CSS servidos via CDN
- **[ADR-009](ADR-009-api-gateway-kong.md)** — Kong cuida das APIs; CDN cuida dos estáticos — responsabilidades separadas
- **[ADR-011](ADR-011-docker-kubernetes.md)** — Kubernetes Ingress é a origem (origin server) do CDN
- **[ADR-015](ADR-015-cache-multicamadas.md)** — CDN é a camada L0 (mais externa) da estratégia de cache
- **[ADR-020](ADR-020-terraform-iac.md)** — Configuração do Cloudflare (zone, page rules, purge token) deve ser gerenciada via Terraform

---

## Notas Futuras

- Quando o produto escalar para múltiplas regiões, considerar Cloudflare R2 (object storage) como origin para assets de upload de usuário, eliminando o round-trip até o cluster
- Avaliar Cloudflare Images para redimensionamento on-the-fly de fotos de pratos (evita gerar múltiplos tamanhos no upload)
