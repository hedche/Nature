###############################################################################
# Synthetic Monitoring — the outside-in check against the public /healthz.
#
# TWO-PHASE APPLY on a cold state, because provider grafana.sm reads a token
# from a resource created in the same run:
#     terraform apply -target=grafana_synthetic_monitoring_installation.this
#     terraform apply
###############################################################################

# SM needs its own publisher credential to write probe results back into the
# stack's Prometheus and Loki. Separate from the cereal_push policy.
resource "grafana_cloud_access_policy" "sm_publish" {
  provider = grafana.cloud

  region = data.grafana_cloud_stack.this.region_slug
  name   = "sm-publisher-cereal"
  scopes = ["metrics:write", "logs:write", "traces:write", "stacks:read"]

  realm {
    type       = "stack"
    identifier = data.grafana_cloud_stack.this.id
  }
}

resource "grafana_cloud_access_policy_token" "sm_publish" {
  provider = grafana.cloud

  region           = grafana_cloud_access_policy.sm_publish.region
  access_policy_id = grafana_cloud_access_policy.sm_publish.policy_id
  name             = "sm-publisher-cereal"
}

resource "grafana_synthetic_monitoring_installation" "this" {
  provider = grafana.cloud

  stack_id              = data.grafana_cloud_stack.this.id
  metrics_publisher_key = grafana_cloud_access_policy_token.sm_publish.token
}

provider "grafana" {
  alias           = "sm"
  sm_access_token = grafana_synthetic_monitoring_installation.this.sm_access_token
  sm_url          = grafana_synthetic_monitoring_installation.this.stack_sm_api_url
}

data "grafana_synthetic_monitoring_probes" "main" {
  provider   = grafana.sm
  depends_on = [grafana_synthetic_monitoring_installation.this]
}

resource "grafana_synthetic_monitoring_check" "cereal_health" {
  provider = grafana.sm

  # `job` becomes the job LABEL on probe_success. rules.tf matches
  # probe_success{job="synthetic"} — change one and the alert never fires.
  job     = "synthetic"
  target  = var.health_url
  enabled = true

  # MILLISECONDS, not seconds.
  #
  # Free tier is 100k API-test executions/month, metered per probe and rounded
  # up to the minute. The arithmetic (probes x 43200 / freq_minutes):
  #   2 probes @  60s =  86,400/mo  <- fits, but is 86% of the whole allowance
  #   3 probes @  60s = 129,600/mo  <- OVER the free tier
  #   3 probes @ 120s =  64,800/mo  <- fits comfortably
  # Three probes at 120s is chosen: more vantage points, more headroom, and a
  # 2-minute check interval is ample for an endpoint whose outage is measured
  # in minutes anyway.
  frequency = 120000
  timeout   = 10000

  probes = [
    data.grafana_synthetic_monitoring_probes.main.probes["London"],
    data.grafana_synthetic_monitoring_probes.main.probes["Frankfurt"],
    data.grafana_synthetic_monitoring_probes.main.probes["Paris"],
    # Amsterdam was retired in the Feb 2025 probe replacement — referencing it
    # fails at plan time. `terraform output available_probes` lists live keys.
  ]

  labels = {
    cluster = "cereal"
  }

  # Keep the shipped series small; the free tier caps active series at 10k and
  # SeriesCapApproaching already warns at 8000.
  basic_metrics_only = true

  # "none" on purpose: low/medium/high makes SM auto-provision its own
  # Grafana-managed rules, which would duplicate the ones in rules.tf.
  alert_sensitivity = "none"

  settings {
    http {
      method     = "GET"
      ip_version = "V4"

      fail_if_not_ssl    = true
      valid_status_codes = [200]

      # kubernetes/health/configmap.yaml serves the literal body "ok".
      fail_if_body_not_matches_regexp = ["ok"]
    }
  }
}
