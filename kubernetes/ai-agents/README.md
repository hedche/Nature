# AI agent access (read-only troubleshooting)

Read-only cluster access for AI agents (Claude Code and similar), so they can
inspect pods, logs, events, and Flux state on `cereal` without being able to
mutate anything or read Secrets. Design rationale and alternatives:
[`docs/ai-agent-cluster-access.md`](../../docs/ai-agent-cluster-access.md).

What this kustomization creates:

- Namespace `ai-agents`
- ClusterRole `ai-agent-readonly` — get/list/watch on workloads, `pods/log`,
  events, storage, Flux CRs, Tailscale CRs. **No secrets, no exec, no
  port-forward, no mutating verbs.**
- ClusterRoleBinding for group `tag:ai-agent` (Tailscale API server proxy)
  and ServiceAccount `ai-agents/ai-agent` (token fallback)

The Tailscale operator's API server proxy is enabled in auth mode
(`apiServerProxyConfig.mode: "true"` in
`kubernetes/tailscale/operator/helmrelease.yaml`).

## Tailnet ACL (manual, admin console)

The one piece that can't live in this repo. In the
[Tailscale ACL policy](https://login.tailscale.com/admin/acls), add:

```jsonc
{
  "tagOwners": {
    "tag:ai-agent": []
  },
  "grants": [
    {
      "src": ["tag:ai-agent"],
      "dst": ["tag:k8s-operator"],
      "ip": ["tcp:443"],
      "app": {
        "tailscale.com/cap/kubernetes": [
          { "impersonate": { "groups": ["tag:ai-agent"] } }
        ]
      }
    }
  ]
}
```

Then join the agent's host to the tailnet with an auth key tagged
`tag:ai-agent` (Settings → Keys; reusable + ephemeral recommended).

## Agent host setup

Kubeconfig — no client certs, the tailnet identity is the credential:

```bash
tailscale configure kubeconfig tailscale-operator
```

MCP server (recommended over raw kubectl) — one instance, pinned to cereal:

```jsonc
// .mcp.json
{
  "mcpServers": {
    "cereal": {
      "command": "npx",
      "args": ["-y", "kubernetes-mcp-server@latest", "--read-only"]
    }
  }
}
```

`--read-only` is defense-in-depth; the RBAC identity is the real boundary.

## Token fallback (no tailnet device)

For an agent that can reach the API endpoint but can't join the tailnet:

```bash
kubectl -n ai-agents create token ai-agent --duration=1h
```

Tokens expire on their own — never store one anywhere persistent.

## Verification

From the agent identity, confirm the positive and negative space:

```bash
kubectl auth whoami                    # group tag:ai-agent (or the SA)
kubectl auth can-i list pods           # yes
kubectl auth can-i get secrets         # no
kubectl auth can-i create pods         # no
kubectl auth can-i create pods/exec    # no
```
