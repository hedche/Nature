###############################################################################
# Grafana Cloud — provider wiring.
#
# THREE credentials, three surfaces. Getting this wrong is the most common way
# an apply fails, so they are aliased explicitly rather than relying on one
# default provider:
#
#   grafana.cloud  cloud_access_policy_token  -> grafana.com API. Stacks,
#                                                access policies, tokens, the
#                                                Synthetics installation.
#   grafana.stack  url + auth (glsa_...)      -> the stack's own Grafana API.
#                                                Folders, contact points,
#                                                notification policy, rules.
#   grafana.sm     sm_access_token + sm_url   -> the Synthetic Monitoring API.
#
# cloud_access_policy_token does NOT authenticate stack resources, and `auth`
# does NOT authenticate cloud resources. They are separate systems.
###############################################################################
terraform {
  required_version = ">= 1.5"
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.45"
    }
  }
}

provider "grafana" {
  alias                     = "cloud"
  cloud_access_policy_token = var.cloud_access_policy_token
}

data "grafana_cloud_stack" "this" {
  provider = grafana.cloud
  slug     = var.stack_slug
}

# The stack service account + token are minted with the CLOUD credential, which
# is what removes the bootstrap chicken-and-egg: you never have to click a
# service account token into existence before Terraform can manage the stack.
resource "grafana_cloud_stack_service_account" "tf" {
  provider   = grafana.cloud
  stack_slug = data.grafana_cloud_stack.this.slug

  name        = "terraform"
  role        = "Admin"
  is_disabled = false
}

resource "grafana_cloud_stack_service_account_token" "tf" {
  provider   = grafana.cloud
  stack_slug = data.grafana_cloud_stack.this.slug

  name               = "terraform"
  service_account_id = grafana_cloud_stack_service_account.tf.id
}

provider "grafana" {
  alias = "stack"
  url   = data.grafana_cloud_stack.this.url
  auth  = grafana_cloud_stack_service_account_token.tf.key
}
