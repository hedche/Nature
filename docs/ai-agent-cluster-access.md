# AI Agent Access to the `cereal` Cluster

How to give AI agents (Claude Code, other LLM-driven tooling) enough access to
troubleshoot the **cereal** Talos cluster — pods, logs, events, Flux status —
without the ability to mutate the cluster or read secrets.

This is a design/research doc: nothing in it is applied yet. It surveys current
best practice and proposes an implementation that reuses infrastructure this
repo already runs (Tailscale Kubernetes operator, Headlamp-style read-only
RBAC, Flux GitOps).

---

## 1. Principles (industry best practice, 2025–2026)

The consistent guidance across CNCF, Tailscale, and Kubernetes-security
writing on agent access:

1. **Read-only by default.** Start every agent with `get`/`list`/`watch` only.
   A read-only agent is *allowed to be wrong* — a hallucinated diagnosis has no
   blast radius. Additional verbs are earned one at a time, each with its own
   RBAC rule and review.
2. **RBAC is the enforcement boundary, not the tool config.** MCP servers and
   CLIs have "read-only flags", but those are conveniences. The Kubernetes API
   server must enforce the limit via a dedicated identity with a minimal
   ClusterRole, so a misconfigured or compromised tool still can't mutate.
3. **No secrets, no exec.** Explicitly exclude `secrets` from any agent role
   (an agent that can read Secrets can exfiltrate them into a transcript), and
   don't grant `pods/exec`, `pods/attach`, or `pods/portforward` initially.
4. **Short-lived, per-agent credentials.** No long-lived tokens in dotfiles or
   agent environments. Use the TokenRequest API (`kubectl create token
   --duration=…`) or identity-aware proxying, and give each agent its own
   identity so audit logs attribute actions.
5. **Writes go through GitOps, never the API.** The approval gate for an agent
   "fix" is a pull request, reviewed by a human, applied by Flux. This repo
   already mandates exactly this (root `AGENTS.md` §4: no manual cluster
   changes), so the agent write-path already exists and needs no cluster
   credentials at all.
6. **Audit everything.** Impersonated/token identities show up in API server
   audit logs; keep one identity per agent type so "who did what" is answerable.

Sources: [CNCF — Building a Cluster-Aware AI Agent](https://www.cncf.io/blog/2026/06/25/building-a-cluster-aware-ai-agent-with-kubernetes-argo-cd-and-gitops/),
[Tailscale — Securely troubleshoot Kubernetes with Claude Code and MCP](https://tailscale.com/learn/kubernetes-mcp),
[KodeKloud — Running AI Agents Safely Inside Kubernetes](https://kodekloud.com/blog/running-ai-agents-safely-inside-kubernetes/),
[containers/kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server),
[Tailscale — API server proxy](https://tailscale.com/docs/features/kubernetes-operator/how-to/api-server-proxy).

---

## 2. Recommended architecture

Three independent layers, each already partially present in this repo:

```
┌─────────────────┐   tailnet    ┌──────────────────────┐   impersonation   ┌─────────────┐
│  AI agent host   │ ──────────▶ │ Tailscale API server │ ────────────────▶ │  kube-api   │
│ (Claude Code +   │  tag:ai-    │ proxy (auth mode)    │  group tag:ai-    │  RBAC:      │
│  k8s MCP server, │  agent      │ tailscale-operator   │  agent            │  read-only  │
│  --read-only)    │             │ (already deployed)   │                   │  no secrets │
└─────────────────┘              └──────────────────────┘                   └─────────────┘
```

| Layer | Mechanism | Status in repo |
|-------|-----------|----------------|
| **Network** | Tailscale K8s operator API server proxy, auth mode | Operator deployed (`kubernetes/tailscale/operator/`), proxy **disabled** (`apiServerProxyConfig.mode: "false"`) |
| **Authorization** | Dedicated read-only ClusterRole, no secrets/exec | Precedent exists: `headlamp-readonly` (`kubernetes/headlamp/rbac.yaml`) |
| **Tooling** | Kubernetes MCP server in `--read-only` mode | Not yet configured |
| **Write path** | PRs to this repo → review → Flux reconcile | Already the only supported write path |

Why this shape and not alternatives:

- **vs. handing agents the admin kubeconfig** — `talos/kubeconfig` is
  cluster-admin with long-lived client certs; any agent holding it can do
  anything and can't be revoked short of rotating cluster CAs. Ruled out.
- **vs. a static ServiceAccount token in the agent's env** — workable (see
  fallback below) but long-lived tokens leak; the Tailscale proxy gives
  identity-aware, revocable access with no secret material on the agent host.
- **vs. exposing the API server publicly with OIDC** — more moving parts and
  public attack surface; the tailnet already exists and keeps 6443 private.

---

## 3. Implementation plan

### Phase 1 — RBAC identity (manifest, GitOps-applied)

New `kubernetes/ai-agents/` kustomization with a ClusterRole modeled on
`headlamp-readonly`, bound to both a tailnet tag group and a ServiceAccount
(for the token fallback):

```yaml
# kubernetes/ai-agents/rbac.yaml (proposed)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ai-agent-readonly
rules:
  # Same read-only surface as headlamp-readonly: core workloads, apps, batch,
  # networking, storage, CRDs, metrics, Flux CRs, tailscale CRs.
  # Deliberately absent: secrets, pods/exec, pods/attach, pods/portforward,
  # and every mutating verb.
  # (Copy rules from kubernetes/headlamp/rbac.yaml, or factor a shared role.)
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ai-agent-readonly
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ai-agent-readonly
subjects:
  # Tailscale API server proxy maps a tagged device to group "tag:ai-agent"
  - kind: Group
    name: tag:ai-agent
    apiGroup: rbac.authorization.k8s.io
  # Fallback: short-lived tokens minted from this ServiceAccount
  - kind: ServiceAccount
    name: ai-agent
    namespace: ai-agents
```

Simplest option: reuse the existing rule list verbatim. Better option: extract
the shared rules into one `readonly-troubleshooter` ClusterRole used by both
Headlamp and agents, via [ClusterRole aggregation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#aggregated-clusterroles)
so neither consumer drifts.

`pods/log` and `events` are already in the Headlamp rule set — those two plus
Flux CRs (`kustomizations`, `helmreleases`, `gitrepositories`) cover the large
majority of real troubleshooting sessions.

### Phase 2 — Enable the Tailscale API server proxy (auth mode)

One-line change in `kubernetes/tailscale/operator/helmrelease.yaml`:

```yaml
    apiServerProxyConfig:
      mode: "true"   # was "false"
```

Tailnet ACL additions (admin console, not in this repo):

```jsonc
{
  "tagOwners": {
    "tag:ai-agent": []            // devices AI agents run on
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

In auth mode the proxy impersonates the caller toward the API server: a device
tagged `tag:ai-agent` becomes Kubernetes group `tag:ai-agent`, which Phase 1
bound to `ai-agent-readonly`. Result: the agent host holds **no cluster
credentials at all** — its tailnet node key *is* the credential, revocable
from the Tailscale admin console, and `kubectl auth whoami` shows exactly who
the API server thinks is calling.

Human admin access via the same proxy (your own user → `cluster-admin`-ish
group) can ride along, replacing LAN-only kubeconfig use — see
`docs/tailscale-cluster-access.md` Approach A, which this phase implements
declaratively instead of via `helm upgrade` by hand.

### Phase 3 — MCP server on the agent host

Give the agent structured tools rather than raw shell `kubectl`. The
[containers/kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server)
is the current best-of-breed (Go, no kubectl dependency, per-toolset gating):

```jsonc
// .mcp.json on the agent host
{
  "mcpServers": {
    "cereal": {
      "command": "npx",
      "args": [
        "-y", "kubernetes-mcp-server@latest",
        "--read-only",                        // belt
        "--kubeconfig", "~/.kube/cereal-agent.yaml"  // braces: RBAC-limited context
      ]
    }
  }
}
```

Rules of thumb from the field guides:

- **One MCP instance per cluster, pinned to one kubeconfig context** — the
  main incident risk in practice is an agent acting on the wrong cluster.
  Never point an agent instance at a kubeconfig containing both `cereal` and
  `oracle` contexts.
- `--read-only` is defense-in-depth only; the RBAC identity behind the
  kubeconfig is what actually constrains the agent.
- The kubeconfig for the agent contains **no client certs** — just the
  Tailscale proxy endpoint (`tailscale configure kubeconfig tailscale-operator`).

### Fallback — short-lived token (no tailnet device)

For an agent that can reach the API endpoint but can't join the tailnet as a
tagged device (e.g. an ephemeral CI/cloud sandbox), mint a scoped token per
session, mirroring the existing Headlamp flow:

```bash
kubectl -n ai-agents create token ai-agent --duration=1h
```

TokenRequest tokens are audience-bound, expire on their own, and die with the
ServiceAccount if it's ever deleted — never store one anywhere persistent.

---

## 4. What agents explicitly do NOT get

| Capability | Why withheld |
|------------|--------------|
| `secrets` read | Secret values would enter model context/transcripts |
| `pods/exec`, `attach`, `portforward` | Arbitrary code path into workloads; add later, approval-gated, with Tailscale session recording if ever needed |
| Any create/update/patch/delete | Fixes go through PRs to this repo → Flux (root `AGENTS.md` §4) |
| Talos API (`talosctl`, port 50000) | Node-level access is full machine control; humans only |
| `oracle` cluster access | Out of scope; repeat this pattern there separately if wanted |

Escalation path if read-only proves insufficient: keep reads via the proxy,
and let the agent *propose* mutations as PRs (which CI validates via
`scripts/validate-cereal-flux.sh`). That is the approval-gated execution model
the best-practice literature recommends — and it's this repo's native workflow.

---

## 5. Audit & attribution

- **Tailscale path**: each agent device is a distinct tailnet node; the proxy
  impersonates it, so API server audit logs record `tag:ai-agent` + node FQDN.
  Access is revoked by deleting the device or the ACL grant.
- **Token path**: audit logs record
  `system:serviceaccount:ai-agents:ai-agent`; use one ServiceAccount per agent
  type if finer attribution is needed.
- **Optional hardening**: enable a Talos API server [audit policy](https://www.talos.dev/latest/kubernetes-guides/configuration/auditpolicy/)
  that logs request-level metadata for the `tag:ai-agent` group, and Tailscale
  [session recording](https://tailscale.com/docs/features/kubernetes-operator)
  if exec is ever granted.

---

## 6. Suggested rollout order

1. **Phase 1** RBAC manifests (`kubernetes/ai-agents/`) — inert until a
   subject uses them; zero risk.
2. **Phase 2** flip `apiServerProxyConfig.mode` + tailnet ACL — verify with a
   personal device first (`kubectl auth whoami`, `kubectl auth can-i --list`).
3. Confirm the negative space: `kubectl auth can-i get secrets` and
   `kubectl auth can-i create pods` as the agent identity must both say `no`.
4. **Phase 3** MCP config on whatever host runs the agent.
5. Add an `AGENTS.md` note telling agents the read-only kubeconfig/MCP exists,
   so troubleshooting sessions use it instead of asking for admin credentials.
