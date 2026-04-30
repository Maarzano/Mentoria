# ADR-009: API Gateway com Kong

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Com múltiplos microserviços, os clientes (frontend web, app mobile, parceiros externos) não devem conhecer os endereços internos de cada serviço. É necessário um ponto de entrada único que centralize:

- Roteamento de requisições para o serviço correto.
- Autenticação e autorização (verificação de tokens JWT, por exemplo).
- Rate limiting para proteger os serviços de abuso.
- Logging e observabilidade de entrada.
- SSL termination.
- Transformação de requests/responses quando necessário.

Sem um API Gateway, cada cliente precisaria conhecer os endereços de todos os serviços e cada serviço precisaria reimplementar autenticação, rate limiting, etc.

## Decisão

Usaremos o **Kong** como API Gateway do FoodeApp.

- O Kong ficará na borda da infraestrutura, recebendo todas as requisições externas.
- O roteamento interno será feito via Kong para os serviços corretos (ou para os BFFs — ADR-010).
- Plugins do Kong serão utilizados para: autenticação JWT, rate limiting, logging, CORS, e health checks.
- Os BFFs (ADR-010) ficam atrás do Kong — o Kong roteia para o BFF correto baseado no cliente/rota.
- Comunicação interna entre microserviços **nunca passa** pelo Kong. A comunicação assíncrona ocorre via fila (RabbitMQ — ADR-006) e a comunicação síncrona direta é gerenciada pelo service mesh (ADR-022), dentro do cluster Kubernetes.

### Topologia de entrada:

```
Cliente (Web/App)
       ↓
     Kong (API Gateway)
       ↓
   BFF Web  |  BFF Mobile
       ↓
  Microserviços internos
```

## Consequências

### Positivas

- Ponto único de entrada: facilita controle de segurança, logging e rate limiting.
- Kong é altamente extensível via plugins (open source e enterprise).
- Suporte nativo a Kubernetes (Kong Ingress Controller).
- Separa preocupações de infraestrutura da lógica de negócio dos serviços.
- Facilita a configuração de autenticação centralizada sem que cada serviço precise implementar.
- Configurável via declarativo (deck CLI) facilitando IaC (ADR-020).

### Negativas / Trade-offs

- O Kong se torna um **ponto único de falha** se não for configurado com alta disponibilidade (múltiplas réplicas no Kubernetes).
- Adiciona latência nas requisições (um hop a mais), mas geralmente em milissegundos aceitáveis.
- Curva de aprendizado para configuração avançada de plugins e roteamento.
- O Kong precisa de um banco de dados (PostgreSQL ou modo DB-less) para armazenar configurações.

### Neutras / Observações

- O Kong é exclusivo para tráfego **externo → interno**. Qualquer comunicação **interna** (serviço → serviço) deve usar o service mesh (ADR-022) ou a fila (ADR-006). Nunca rotear tráfego interno pelo Kong.
- Opções avaliadas e descartadas: NGINX (muito básico para o que precisamos), AWS API Gateway (lock-in de cloud), Traefik (mais simples, mas menos rico em plugins para as necessidades do FoodeApp).
- Usar **modo DB-less** (configuração declarativa via YAML) é recomendado para simplificar a operação e facilitar versionamento com IaC.
- O Kong deve ser monitorado como qualquer outro componente crítico da infraestrutura (ADR-018).
