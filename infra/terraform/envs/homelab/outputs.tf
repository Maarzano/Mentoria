output "postgres_host" {
  description = "DNS interno do PostgreSQL no K3S"
  value       = "postgresql.foodeapp-system.svc.cluster.local"
}

output "redis_host" {
  description = "DNS interno do Redis no K3S"
  value       = "redis-master.foodeapp-system.svc.cluster.local"
}

output "rabbitmq_host" {
  description = "DNS interno do RabbitMQ no K3S"
  value       = "rabbitmq.foodeapp-system.svc.cluster.local"
}

output "otel_endpoint" {
  description = "Endpoint OTLP do OpenTelemetry Collector"
  value       = "http://otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4317"
}

output "grafana_url" {
  description = "URL do Grafana (acessar via port-forward ou NodePort)"
  value       = "http://monitoring-grafana.monitoring.svc.cluster.local:80"
}
