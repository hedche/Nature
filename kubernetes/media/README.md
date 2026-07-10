# media — Sonarr / Radarr / Prowlarr

The *arr layer of the media stack, running on cereal and pointed at qBittorrent
on the hermes VM (`10.30.1.57`). Downloads and the media library live on
hermes' 1TB USB disk, NFS-exported as `10.30.1.57:/mnt/data` and mounted at
`/data` in the Sonarr/Radarr pods — byte-identical to qBittorrent's container
paths, so imports are hardlinks and **no remote path mappings are needed**.

| App | UI | Purpose | /data mount |
|---|---|---|---|
| Sonarr | `https://sonarr.<tailnet>.ts.net` | TV | yes |
| Radarr | `https://radarr.<tailnet>.ts.net` | Movies | yes |
| Prowlarr | `https://prowlarr.<tailnet>.ts.net` | Indexer manager | no |

Design constraints (do not "simplify" these away):

- **Config PVCs are ceph-block, never NFS** — the *arrs use SQLite, which
  corrupts over NFS. Only bulk media data is on the NFS volume.
- The `media-env` ConfigMap pins `PUID/PGID=1000`, matching qBittorrent on
  hermes and the `all_squash,anonuid=1000` NFS export.
- The *arrs are deliberately **not** behind the VPN: only the download client
  needs it (Servarr guidance); *arr apps behind shared VPN IPs get rate-limited
  or banned by metadata providers. The one exception is ISP-blocked indexers,
  handled per-indexer via the proxy below.
- Images are pinned in `kustomization.yaml` and bumped automatically by Flux
  image automation (`image-automation.yaml`, lsio `-ls<build>` tag ordering).

## Configuration (after first deploy or cluster rebuild)

Almost everything is applied by the idempotent wiring script:

```sh
./kubernetes/media/configure-media.sh
```

It reads the root `secrets.yaml` (`qbittorrent:` WebUI creds, `arr:` admin
account, `media-secrets` API keys) and applies: qBittorrent categories
(`tv` → `/data/torrents/tv`, `movies` → `/data/torrents/movies`), the shared
Forms-auth admin account on all three UIs, root folders (`/data/media/tv`,
`/data/media/movies`), the qBittorrent download client in Sonarr/Radarr
(host `10.30.1.57:8080` — **no remote path mapping**; both sides see
identical `/data/...` paths), and the Prowlarr→Sonarr/Radarr application
links. API keys are not generated state: they're pinned via the
`media-secrets` Secret (`scripts/secrets.sh`, `SONARR__AUTH__APIKEY` etc.)
into the pods, so a config-PVC loss + re-run of this script restores the
whole setup. Prereqs: `kubectl` (cereal context), `yq`, `python3`.

Still manual (deliberately — they're accounts/choices, not derivable state):

1. **Indexers** in Prowlarr: Settings → Indexers; they sync to Sonarr/Radarr
   automatically.
2. **VPN proxy for ISP-blocked indexers only**: Settings → Indexers → Add
   Indexer Proxy → HTTP, host `10.30.1.57`, port `8888`, tag `vpn`; apply the
   `vpn` tag to any indexer your ISP blocks. Untagged indexers stay direct.
3. Plex needs nothing: it reads `/mnt/data/media` locally on hermes; new
   imports appear on library scan.

## Failure modes

- hermes USB disk absent → `nfs-server` refuses to start (systemd drop-in) and
  the sonarr/radarr pods hang mounting `/data`. Fail-safe by design; reattach
  the disk and `sudo systemctl start nfs-server` on hermes.
- An NFS-server restart briefly stalls *arr I/O (hard-mount semantics); pods
  recover on their own.
