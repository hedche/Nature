###############################################################################
# Everything below feeds ~/.config/nature/secrets.yaml. See ./README.md.
# `terraform output -raw <name>` prints the real value; a bare `output` prints
# <sensitive>.
###############################################################################
output "prometheus_url" {
  description = "GRAFANA_CLOUD_PROM_URL in nature-vars"
  value       = data.grafana_cloud_stack.this.prometheus_remote_write_endpoint
}

output "prometheus_username" {
  description = "grafana-cloud-credentials.prometheus-username (monitoring ns)"
  value       = tostring(data.grafana_cloud_stack.this.prometheus_user_id)
}

output "loki_url" {
  description = "GRAFANA_CLOUD_LOKI_URL in nature-vars — append /loki/api/v1/push"
  value       = "${data.grafana_cloud_stack.this.logs_url}/loki/api/v1/push"
}

output "loki_username" {
  description = "GRAFANA_CLOUD_LOKI_USERNAME in nature-vars"
  value       = tostring(data.grafana_cloud_stack.this.logs_user_id)
}

output "push_token" {
  description = "grafana-cloud-credentials prometheus-token AND logging/loki-token"
  value       = grafana_cloud_access_policy_token.cereal_push.token
  sensitive   = true
}

output "available_probes" {
  description = "Live Synthetics probe names -> ids. Check before hardcoding any."
  value       = data.grafana_synthetic_monitoring_probes.main.probes
}
