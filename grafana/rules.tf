###############################################################################
# Off-site alert rules — the vantage point that survives cereal dying.
#
# READ THIS BEFORE EDITING A QUERY.
#
# Grafana-managed rules are NOT Prometheus rules. In Prometheus, a comparison
# like `x == 0` FILTERS samples: it returns an empty vector when false, and an
# empty vector simply means "nothing is firing". Grafana instead classifies an
# empty result as **No Data**, and applies no_data_state to it.
#
# So the natural Prometheus phrasing — `absent(...)`, `x == 0`, `x > 0`, `< 4` —
# returns empty during NORMAL operation, which under no_data_state = "Alerting"
# fires permanently and carries zero information. Grafana's own guidance:
# "Grafana Alerting implements a built-in No Data state logic, so you don't need
# to detect missing data with absent_* queries."
#
# Every rule below therefore follows one shape:
#   A = PromQL returning a BARE NUMBER (no comparison), forced to always produce
#       a sample with `or on() vector(0)` where the series can vanish entirely
#   B = a threshold expression holding the comparison   <- this is the condition
# and no_data_state is a per-rule judgement about whether missing data is itself
# the bad news — NOT a blanket setting.
#
# The local PrometheusRules in kubernetes/monitoring-rules/rules/ are the
# opposite case: Prometheus has no No Data concept, so absent() there is correct
# and must be left alone.
###############################################################################
resource "grafana_rule_group" "cereal_cloud" {
  provider         = grafana.stack
  name             = "cereal-offsite"
  folder_uid       = grafana_folder.cereal.uid
  interval_seconds = 60

  # `or on() vector(0)` is load-bearing: bare absent() returns an EMPTY vector while the heartbeat is healthy, which Grafana classifies as No Data — and with no_data_state=Alerting that fires 24/7. Forcing a numeric 0/1 makes the healthy case Normal and leaves No Data meaning what it should: Grafana Cloud cannot query at all.
  rule {
    name           = "ClusterSilent"
    condition      = "B"
    for            = "5m"
    no_data_state  = "Alerting"
    exec_err_state = "Alerting"
    is_paused      = false

    data {
      ref_id = "A"
      relative_time_range {
        from = 900
        to   = 0
      }
      datasource_uid = var.prom_datasource_uid
      model = jsonencode({
        refId      = "A"
        expr       = "max_over_time(nature:cluster_heartbeat{cluster=\"cereal\"}[10m]) or on() vector(0)"
        instant    = true
        range      = false
        editorMode = "code"
        datasource = { type = "prometheus", uid = var.prom_datasource_uid }
      })
    }

    data {
      ref_id = "B"
      relative_time_range {
        from = 0
        to   = 0
      }
      datasource_uid = "__expr__"
      model = jsonencode({
        refId      = "B"
        type       = "threshold"
        expression = "A"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "lt", params = [1] }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }

    labels = {
      severity = "critical"
      cluster  = "cereal"
      origin   = "grafana-cloud"
    }

    annotations = {
      summary     = "cereal has gone silent — no heartbeat reaching Grafana Cloud"
      description = "The recording rule nature:cluster_heartbeat stopped arriving for 10m. Either the cluster is dead, the WAN is down, or remote_write is broken. The LAN-side Home Assistant watchdog is the other half of this check."
    }
  }

  # count() over an empty vector returns empty, so `or on() vector(0)` is what makes total loss report 0 rather than No Data.
  rule {
    name           = "NodeMissing"
    condition      = "B"
    for            = "10m"
    no_data_state  = "Alerting"
    exec_err_state = "Alerting"
    is_paused      = false

    data {
      ref_id = "A"
      relative_time_range {
        from = 900
        to   = 0
      }
      datasource_uid = var.prom_datasource_uid
      model = jsonencode({
        refId      = "A"
        expr       = "count(up{job=\"node-exporter\",cluster=\"cereal\"} == 1) or on() vector(0)"
        instant    = true
        range      = false
        editorMode = "code"
        datasource = { type = "prometheus", uid = var.prom_datasource_uid }
      })
    }

    data {
      ref_id = "B"
      relative_time_range {
        from = 0
        to   = 0
      }
      datasource_uid = "__expr__"
      model = jsonencode({
        refId      = "B"
        type       = "threshold"
        expression = "A"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "lt", params = [4] }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }

    labels = {
      severity = "critical"
      cluster  = "cereal"
      origin   = "grafana-cloud"
    }

    annotations = {
      summary     = "Fewer than 4 cereal nodes are reporting"
      description = "One or more of cereal, snap, crackle, pop has stopped being scraped. Check power first — on 2026-09-02 crackle and pve both died to a brownout and neither powers on again by itself."
    }
  }

  # The comparison lives in the threshold expression, not the PromQL. `node_power_supply_online == 0` would return empty on mains power, which reads as No Data and fires permanently.
  rule {
    name           = "CerealOnBatteryCloud"
    condition      = "B"
    for            = "5m"
    no_data_state  = "Alerting"
    exec_err_state = "Alerting"
    is_paused      = false

    data {
      ref_id = "A"
      relative_time_range {
        from = 900
        to   = 0
      }
      datasource_uid = var.prom_datasource_uid
      model = jsonencode({
        refId      = "A"
        expr       = "min(node_power_supply_online{power_supply=\"ACAD\",cluster=\"cereal\"})"
        instant    = true
        range      = false
        editorMode = "code"
        datasource = { type = "prometheus", uid = var.prom_datasource_uid }
      })
    }

    data {
      ref_id = "B"
      relative_time_range {
        from = 0
        to   = 0
      }
      datasource_uid = "__expr__"
      model = jsonencode({
        refId      = "B"
        type       = "threshold"
        expression = "A"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "lt", params = [1] }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }

    labels = {
      severity = "critical"
      cluster  = "cereal"
      origin   = "grafana-cloud"
    }

    annotations = {
      summary     = "cereal is running on battery — charger unplugged"
      description = "Duplicated from the local rule on purpose: this one survives the local Alertmanager dying. ~5 hours before the control plane goes down. See HARDWARE.md."
    }
  }

  # Reaches the cloud for free because Node Conditions surface through kube-state-metrics, which is already in the remote_write allow-list.
  rule {
    name           = "NVMeDMAFaultCloud"
    condition      = "B"
    for            = "5m"
    no_data_state  = "Alerting"
    exec_err_state = "Alerting"
    is_paused      = false

    data {
      ref_id = "A"
      relative_time_range {
        from = 900
        to   = 0
      }
      datasource_uid = var.prom_datasource_uid
      model = jsonencode({
        refId      = "A"
        expr       = "max(kube_node_status_condition{condition=\"NVMeDMAFault\",status=\"true\",cluster=\"cereal\"}) or on() vector(0)"
        instant    = true
        range      = false
        editorMode = "code"
        datasource = { type = "prometheus", uid = var.prom_datasource_uid }
      })
    }

    data {
      ref_id = "B"
      relative_time_range {
        from = 0
        to   = 0
      }
      datasource_uid = "__expr__"
      model = jsonencode({
        refId      = "B"
        type       = "threshold"
        expression = "A"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }

    labels = {
      severity = "critical"
      cluster  = "cereal"
      origin   = "grafana-cloud"
    }

    annotations = {
      summary     = "NVMe DMA fault detected on a cereal node — go straight to a physical power-cycle"
      description = "node-problem-detector raised the NVMeDMAFault node condition. Remote reboots are accepted and silently ignored during this fault. See docs/nvme-dma-fault-monitoring.md."
    }
  }

  # Threshold, not `ceph_health_status > 0`, which returns empty when healthy.
  rule {
    name           = "CephUnhealthyCloud"
    condition      = "B"
    for            = "30m"
    no_data_state  = "Alerting"
    exec_err_state = "Alerting"
    is_paused      = false

    data {
      ref_id = "A"
      relative_time_range {
        from = 900
        to   = 0
      }
      datasource_uid = var.prom_datasource_uid
      model = jsonencode({
        refId      = "A"
        expr       = "max(ceph_health_status{cluster=\"cereal\"})"
        instant    = true
        range      = false
        editorMode = "code"
        datasource = { type = "prometheus", uid = var.prom_datasource_uid }
      })
    }

    data {
      ref_id = "B"
      relative_time_range {
        from = 0
        to   = 0
      }
      datasource_uid = "__expr__"
      model = jsonencode({
        refId      = "B"
        type       = "threshold"
        expression = "A"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }

    labels = {
      severity = "warning"
      cluster  = "cereal"
      origin   = "grafana-cloud"
    }

    annotations = {
      summary     = "Ceph is not HEALTH_OK"
      description = "0=OK 1=WARN 2=ERR. Losing a second OSD blocks writes — the pool is size 3 / min_size 2."
    }
  }

  # job MUST stay "synthetic" — it is set by the Synthetics check's `job` argument in synthetics.tf. Rename one and this rule silently never matches.
  rule {
    name           = "PublicEndpointDown"
    condition      = "B"
    for            = "5m"
    no_data_state  = "Alerting"
    exec_err_state = "Alerting"
    is_paused      = false

    data {
      ref_id = "A"
      relative_time_range {
        from = 900
        to   = 0
      }
      datasource_uid = var.prom_datasource_uid
      model = jsonencode({
        refId      = "A"
        expr       = "min(probe_success{job=\"synthetic\"})"
        instant    = true
        range      = false
        editorMode = "code"
        datasource = { type = "prometheus", uid = var.prom_datasource_uid }
      })
    }

    data {
      ref_id = "B"
      relative_time_range {
        from = 0
        to   = 0
      }
      datasource_uid = "__expr__"
      model = jsonencode({
        refId      = "B"
        type       = "threshold"
        expression = "A"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "lt", params = [1] }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }

    labels = {
      severity = "critical"
      cluster  = "cereal"
      origin   = "grafana-cloud"
    }

    annotations = {
      summary     = "The public /healthz is failing from outside"
      description = "Outside-in check: cluster + home internet + Cloudflare tunnel. Independent of the remote_write path, so it can fire when the metrics pipeline cannot."
    }
  }

  # no_data_state = OK, not Alerting. This is a budget gauge, not a liveness check — a missing billing metric is not an outage.
  rule {
    name           = "SeriesCapApproaching"
    condition      = "B"
    for            = "1h"
    no_data_state  = "OK"
    exec_err_state = "Alerting"
    is_paused      = false

    data {
      ref_id = "A"
      relative_time_range {
        from = 900
        to   = 0
      }
      datasource_uid = var.usage_datasource_uid
      model = jsonencode({
        refId      = "A"
        expr       = "grafanacloud_instance_active_series"
        instant    = true
        range      = false
        editorMode = "code"
        datasource = { type = "prometheus", uid = var.usage_datasource_uid }
      })
    }

    data {
      ref_id = "B"
      relative_time_range {
        from = 0
        to   = 0
      }
      datasource_uid = "__expr__"
      model = jsonencode({
        refId      = "B"
        type       = "threshold"
        expression = "A"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "gt", params = [8000] }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }

    labels = {
      severity = "warning"
      cluster  = "cereal"
      origin   = "grafana-cloud"
    }

    annotations = {
      summary     = "Approaching the 10k free-tier active-series cap"
      description = "Over the cap Grafana Cloud DROPS samples silently, which would make the dead-man's switch look healthy while being blind. Tighten the remote_write allow-list in kubernetes/monitoring/helmrelease.yaml."
    }
  }

  # no_data_state = OK: the ALERTS series legitimately has no members whenever nothing is firing, which is the normal state. ClusterSilent already covers the cluster-is-gone case.
  rule {
    name           = "LocalAlertUndelivered"
    condition      = "B"
    for            = "10m"
    no_data_state  = "OK"
    exec_err_state = "Alerting"
    is_paused      = false

    data {
      ref_id = "A"
      relative_time_range {
        from = 900
        to   = 0
      }
      datasource_uid = var.prom_datasource_uid
      model = jsonencode({
        refId      = "A"
        expr       = "count(ALERTS{alertstate=\"firing\",severity=\"critical\",cluster=\"cereal\"}) or on() vector(0)"
        instant    = true
        range      = false
        editorMode = "code"
        datasource = { type = "prometheus", uid = var.prom_datasource_uid }
      })
    }

    data {
      ref_id = "B"
      relative_time_range {
        from = 0
        to   = 0
      }
      datasource_uid = "__expr__"
      model = jsonencode({
        refId      = "B"
        type       = "threshold"
        expression = "A"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "gt", params = [0] }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }

    labels = {
      severity = "critical"
      cluster  = "cereal"
      origin   = "grafana-cloud"
    }

    annotations = {
      summary     = "A critical alert is firing inside cereal — check it arrived by Telegram too"
      description = "Third delivery path. If the local Alertmanager cannot deliver (revoked bot token, dead WAN), Grafana Cloud still tells you something is wrong, over its own contact points."
    }
  }

  # The max() wrapping max_over_time is load-bearing twice over.
  #  1. It makes BOTH branches of the `or` share an empty label set. The left
  #     branch otherwise carries the externalLabels (cluster/prometheus/
  #     prometheus_replica) while vector(0) carries none, and Grafana keys alert
  #     instances by label set — so at last-sample+30h the labelled instance
  #     would vanish, be stale-resolved as MissingSeries, and send
  #     "[RESOLVED] PeanutBriefingSilentCloud" ~4h into a genuine total outage,
  #     on the one alert whose whole purpose is to be believed when everything
  #     else is dark.
  #  2. The recording rule already collapses local labels, but this query must
  #     not depend on that. A second Prometheus replica or any future relabel
  #     would re-split the series, and max_over_time([30h]) would then page off
  #     a dead one for 30h. Measured precedent in the recording rule's comment.
  # {cluster="cereal"} stays INSIDE the max(): Grafana Cloud is a shared tenant
  # with oracle, so an unqualified matcher stays satisfied while the other
  # cluster is alive and cereal could die unnoticed.
  rule {
    name           = "PeanutBriefingSilentCloud"
    condition      = "B"
    for            = "15m"
    no_data_state  = "Alerting"
    exec_err_state = "Alerting"
    is_paused      = false

    data {
      ref_id = "A"
      relative_time_range {
        from = 108000
        to   = 0
      }
      datasource_uid = var.prom_datasource_uid
      model = jsonencode({
        refId      = "A"
        expr       = "time() - (max(max_over_time(nature:peanut_briefing_last_success_timestamp_seconds{cluster=\"cereal\"}[30h])) or on() vector(0))"
        instant    = true
        range      = false
        editorMode = "code"
        datasource = { type = "prometheus", uid = var.prom_datasource_uid }
      })
    }

    data {
      ref_id = "B"
      relative_time_range {
        from = 0
        to   = 0
      }
      datasource_uid = "__expr__"
      model = jsonencode({
        refId      = "B"
        type       = "threshold"
        expression = "A"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          type      = "query"
          evaluator = { type = "gt", params = [93600] }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last", params = [] }
        }]
      })
    }

    labels = {
      severity = "critical"
      cluster  = "cereal"
      origin   = "grafana-cloud"
    }

    annotations = {
      summary     = "No successful peanut briefing for over 26h, seen from outside the cluster"
      description = "Off-site twin of the in-cluster PeanutBriefingSilent, at the same 26h/15m so the pair is diagnostic: both firing means the briefing is broken, this one alone means local Alertmanager delivery failed, the local one alone means remote_write broke. Value is time() minus nature:peanut_briefing_last_success_timestamp_seconds; ~1.79e9 means no sample reached Grafana Cloud within 30h at all. NOTE: for a dead cluster this fires up to 26h late by construction — ClusterSilent (for: 5m) is the prompt dead-cereal detector, do not weaken it on the strength of this rule."
    }
  }
}
