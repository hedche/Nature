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

## One-time configuration (after first deploy)

1. **qBittorrent** (`http://10.30.1.57:8080`, creds in root `secrets.yaml`
   under `qbittorrent:`): ensure categories `tv` → `/data/torrents/tv` and
   `movies` → `/data/torrents/movies` exist.
2. **Sonarr**: Settings → Media Management → enable hardlinks; add root folder
   `/data/media/tv`. Settings → Download Clients → qBittorrent: host
   `10.30.1.57`, port `8080`, qBittorrent creds, category `tv`. Do **not**
   add a remote path mapping — both sides see identical `/data/...` paths.
3. **Radarr**: same, with root folder `/data/media/movies` and category
   `movies`.
4. **Prowlarr**: Settings → Apps → add Sonarr
   (`http://sonarr.media.svc.cluster.local:8989`, API key from Sonarr →
   Settings → General) and Radarr
   (`http://radarr.media.svc.cluster.local:7878` + key); Prowlarr server URL
   `http://prowlarr.media.svc.cluster.local:9696`. Add indexers — they sync to
   both apps.
5. **VPN proxy for ISP-blocked indexers only**: Settings → Indexers → Add
   Indexer Proxy → HTTP, host `10.30.1.57`, port `8888`, tag `vpn`; apply the
   `vpn` tag to any indexer your ISP blocks. Untagged indexers stay direct.
6. Record the three generated API keys in root `secrets.yaml` (human backup
   only; nothing consumes them from there).
7. Plex needs nothing: it reads `/mnt/data/media` locally on hermes; new
   imports appear on library scan.

## Failure modes

- hermes USB disk absent → `nfs-server` refuses to start (systemd drop-in) and
  the sonarr/radarr pods hang mounting `/data`. Fail-safe by design; reattach
  the disk and `sudo systemctl start nfs-server` on hermes.
- An NFS-server restart briefly stalls *arr I/O (hard-mount semantics); pods
  recover on their own.
