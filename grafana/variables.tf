variable "cloud_access_policy_token" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Bootstrap credential — the ONE thing Terraform cannot create for you.
    grafana.com -> Administration -> Cloud access policies -> Create access policy
      realm  : org
      scopes : accesspolicies:read, accesspolicies:write, accesspolicies:delete,
               stacks:read, stack-service-accounts:write
    then "Add token" on that policy. Store it in ~/.config/nature/secrets.yaml
    under grafana.cloud_access_policy_token; .envrc exports it as TF_VAR_*.
  EOT
}

variable "stack_slug" {
  type        = string
  description = "Slug of the free-tier stack you created by hand, i.e. <slug>.grafana.net"
}

variable "telegram_bot_token" {
  type        = string
  sensitive   = true
  description = "Reuses the existing peanut bot. Same value as peanut-secrets.TELEGRAM_BOT_TOKEN."
}

variable "telegram_chat_id" {
  type        = string
  description = "STRING, not number — Telegram group ids are negative and must stay quoted."
}

variable "alert_email" {
  type        = string
  default     = "lydia@leafbit.uk"
  description = "Second delivery path for critical alerts. Grafana Cloud sends it; there is no SMTP relay in this repo."
}

variable "health_url" {
  type        = string
  default     = "https://cereal-health.leafbit.uk/healthz"
  description = "Public endpoint the Synthetics check probes, from kubernetes/health/."
}

variable "prom_datasource_uid" {
  type        = string
  default     = "grafanacloud-prom"
  description = <<-EOT
    UID of the stack's built-in Prometheus datasource. "grafanacloud-prom" is the
    short form and is what Grafana's own Cloud docs hardcode; the NAME is the
    longer grafanacloud-<org>-prom. Verify with:
      curl -s -H "Authorization: Bearer <glsa_token>" \
        "https://<slug>.grafana.net/api/datasources" | jq -r '.[]|"\(.uid)\t\(.name)"'
  EOT
}

variable "usage_datasource_uid" {
  type        = string
  default     = "grafanacloud-usage"
  description = <<-EOT
    grafanacloud_instance_active_series lives in the billing/usage datasource, NOT
    the stack's own Prometheus. Verify the UID with the same curl as above before
    trusting SeriesCapApproaching.
  EOT
}
