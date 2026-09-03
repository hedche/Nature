###############################################################################
# Contact points and the notification policy tree.
#
# A notification policy's contact_point is a single string, so "Telegram AND
# email" is not two contact points on one route — it is ONE contact point
# holding two integration blocks. Grafana fans out across the blocks.
###############################################################################
resource "grafana_contact_point" "telegram" {
  provider = grafana.stack
  name     = "nature-telegram"

  telegram {
    token      = var.telegram_bot_token
    chat_id    = var.telegram_chat_id
    parse_mode = "HTML"

    disable_web_page_preview = true
    message                  = <<-EOT
      <b>[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}</b>
      {{ range .Alerts }}{{ .Annotations.summary }}
      {{ if .Annotations.description }}{{ .Annotations.description }}
      {{ end }}{{ end }}
    EOT
  }
}

# Critical alerts go to Telegram AND email, from a single contact point.
resource "grafana_contact_point" "critical" {
  provider = grafana.stack
  name     = "nature-critical"

  telegram {
    token                    = var.telegram_bot_token
    chat_id                  = var.telegram_chat_id
    parse_mode               = "HTML"
    disable_web_page_preview = true
    message                  = <<-EOT
      <b>[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}</b>
      {{ range .Alerts }}{{ .Annotations.summary }}
      {{ if .Annotations.description }}{{ .Annotations.description }}
      {{ end }}{{ end }}
    EOT
  }

  email {
    addresses    = [var.alert_email]
    single_email = true
    subject      = "[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}"
    message      = <<-EOT
      {{ len .Alerts.Firing }} firing / {{ len .Alerts.Resolved }} resolved.
      {{ range .Alerts }}{{ .Annotations.summary }}
      {{ if .Annotations.description }}{{ .Annotations.description }}
      {{ end }}{{ end }}
    EOT
  }
}

# This resource owns the ENTIRE policy tree for the org — anything configured by
# hand in the UI is replaced on apply.
resource "grafana_notification_policy" "root" {
  provider = grafana.stack

  contact_point = grafana_contact_point.telegram.name
  group_by      = ["alertname", "cluster"]

  group_wait      = "30s"
  group_interval  = "5m"
  repeat_interval = "4h"

  policy {
    contact_point   = grafana_contact_point.critical.name
    continue        = false
    group_wait      = "10s"
    repeat_interval = "1h"

    matcher {
      label = "severity"
      match = "="
      value = "critical"
    }
  }
}

resource "grafana_folder" "cereal" {
  provider = grafana.stack
  title    = "cereal"
}
