###############################################################################
# Dashboards — new as of issue #73. Everything above this file manages alerting,
# rules and synthetics; `grafana/` had no `grafana_dashboard` resource until now.
#
# One dashboard: SSD/NVMe wear per node and device. The headline number is
# smartctl_device_percentage_used (NVMe only — see the smartctl-exporter section
# of ../kubernetes/monitoring/README.md for why SATA wear instead shows up as a
# generic smartctl_device_attribute series), alongside lifetime bytes written
# (the TBW counterpart) and temperature. All three metrics are allow-listed for
# remote_write in ../kubernetes/monitoring/helmrelease.yaml.
###############################################################################
resource "grafana_dashboard" "nvme_wear" {
  provider  = grafana.stack
  folder    = grafana_folder.cereal.uid
  overwrite = true

  config_json = jsonencode({
    title    = "cereal — SSD/NVMe wear"
    uid      = "cereal-nvme-wear"
    timezone = "browser"
    tags     = ["cereal", "hardware"]
    time = {
      from = "now-90d"
      to   = "now"
    }
    panels = [
      {
        id         = 1
        title      = "Wear — percentage used (NVMe)"
        type       = "timeseries"
        datasource = { type = "prometheus", uid = var.prom_datasource_uid }
        gridPos    = { h = 8, w = 24, x = 0, y = 0 }
        fieldConfig = {
          defaults = {
            unit = "percent"
            max  = 100
            min  = 0
            thresholds = {
              mode = "absolute"
              steps = [
                { color = "green", value = null },
                { color = "yellow", value = 70 },
                { color = "red", value = 85 },
              ]
            }
          }
        }
        targets = [
          {
            refId        = "A"
            expr         = "smartctl_device_percentage_used"
            legendFormat = "{{instance}} — {{device}}"
            datasource   = { type = "prometheus", uid = var.prom_datasource_uid }
          },
        ]
      },
      {
        id         = 2
        title      = "Lifetime data written (TBW)"
        type       = "timeseries"
        datasource = { type = "prometheus", uid = var.prom_datasource_uid }
        gridPos    = { h = 8, w = 24, x = 0, y = 8 }
        fieldConfig = {
          defaults = { unit = "bytes" }
        }
        targets = [
          {
            refId        = "A"
            expr         = "smartctl_device_bytes_written"
            legendFormat = "{{instance}} — {{device}}"
            datasource   = { type = "prometheus", uid = var.prom_datasource_uid }
          },
        ]
      },
      {
        id         = 3
        title      = "Drive temperature"
        type       = "timeseries"
        datasource = { type = "prometheus", uid = var.prom_datasource_uid }
        gridPos    = { h = 8, w = 12, x = 0, y = 16 }
        fieldConfig = {
          defaults = { unit = "celsius" }
        }
        targets = [
          {
            refId        = "A"
            expr         = "smartctl_device_temperature"
            legendFormat = "{{instance}} — {{device}}"
            datasource   = { type = "prometheus", uid = var.prom_datasource_uid }
          },
        ]
      },
      {
        id         = 4
        title      = "SMART overall status (1 = passed)"
        type       = "timeseries"
        datasource = { type = "prometheus", uid = var.prom_datasource_uid }
        gridPos    = { h = 8, w = 12, x = 12, y = 16 }
        fieldConfig = {
          defaults = {
            min = 0
            max = 1
          }
        }
        targets = [
          {
            refId        = "A"
            expr         = "smartctl_device_smart_status"
            legendFormat = "{{instance}} — {{device}}"
            datasource   = { type = "prometheus", uid = var.prom_datasource_uid }
          },
        ]
      },
    ]
  })
}
