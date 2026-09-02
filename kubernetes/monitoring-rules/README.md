# Monitoring rules — everything that needs the Prometheus Operator CRDs

Split out of `../monitoring/` for one reason: **CRD ordering**.

`PrometheusRule`, `ServiceMonitor`, `PodMonitor` and `Probe` are custom resources whose
CRDs are installed by the `kube-prometheus-stack` HelmRelease in `../monitoring/`. Flux
dry-runs every resource in a Kustomization before applying any of it, so keeping these in
the same Kustomization as the HelmRelease deadlocks on a first install:

```
PodMonitor/monitoring/node-problem-detector dry-run failed:
  no matches for kind "PodMonitor" in version "monitoring.coreos.com/v1"
```

Nothing is applied, so the HelmRelease never installs the CRDs, so the dry-run never
starts passing. Observed on the real first deploy, not theoretical.

`kubernetes/flux/monitoring.yaml` sets `wait: true`, so the `monitoring` Kustomization is
only reported Ready once the HelmRelease has actually reconciled and the CRDs exist. This
Kustomization `dependsOn` it, so it applies strictly afterwards.

| File | Needs |
|---|---|
| `rules/` | `PrometheusRule` |
| `servicemonitor-ceph.yaml` | `ServiceMonitor` |
| `podmonitor-node-problem-detector.yaml` | `PodMonitor` — the DaemonSet itself stays in `../monitoring/node-problem-detector/`, since it needs no CRD |
