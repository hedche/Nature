###############################################################################
# The push credential the cluster uses for remote_write and Loki.
#
# Its `token` output is what goes into ~/.config/nature/secrets.yaml as
# grafana-cloud-credentials, and the URLs below become the GRAFANA_CLOUD_*
# entries in nature-vars. See ./README.md for the copy-out step.
###############################################################################
resource "grafana_cloud_access_policy" "cereal_push" {
  provider = grafana.cloud

  # Must be the stack's own region slug (prod-eu-west-0, ...), never "eu".
  # ForceNew: changing it destroys and recreates, rotating the token.
  region       = data.grafana_cloud_stack.this.region_slug
  name         = "cereal-push"
  display_name = "cereal remote_write + log push"

  scopes = ["metrics:write", "logs:write"]

  realm {
    type = "stack"
    # For type=stack this is the NUMERIC stack id, not the slug.
    identifier = data.grafana_cloud_stack.this.id
  }
}

resource "grafana_cloud_access_policy_token" "cereal_push" {
  provider = grafana.cloud

  region = grafana_cloud_access_policy.cereal_push.region
  # .policy_id, NOT .id — .id is the composite "{region}:{policyId}" and the
  # Cloud API answers 404 for it rather than erroring in Terraform.
  access_policy_id = grafana_cloud_access_policy.cereal_push.policy_id
  name             = "cereal-push-token"
  display_name     = "cereal push token"

  # expires_at deliberately unset. It is ForceNew, so any computed value
  # (timeadd(timestamp(), ...)) silently rotates the credential every apply.
}
