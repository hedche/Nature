# Headlamp

Private Kubernetes dashboard for the `cereal` cluster.

## Access

Headlamp is exposed through the Tailscale Kubernetes operator using the `tailscale` IngressClass.

From a Tailscale-connected device, open:

```text
https://headlamp.<tailnet>.ts.net
```

or, when MagicDNS search domains are working:

```text
https://headlamp
```

## Login token

Generate a short-lived read-only token:

```bash
kubectl -n headlamp create token headlamp --duration=24h
```

Paste the token into Headlamp when prompted.

The token uses the `headlamp-readonly` ClusterRole and intentionally cannot read Kubernetes Secrets or mutate cluster resources.

## iPhone requirements

- Tailscale app installed and connected to the same tailnet.
- Tailnet ACLs allow the iPhone/user to reach devices tagged `tag:k8s`.
- MagicDNS and Tailscale HTTPS are enabled in the tailnet admin console.

