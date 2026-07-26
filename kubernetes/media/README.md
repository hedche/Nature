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
| FlareSolverr | none (in-cluster only) | Cloudflare challenge solver for Prowlarr | no |

FlareSolverr is stateless (no config PVC, no ingress, no secrets); Prowlarr
reaches it at `http://flaresolverr.media.svc.cluster.local:8191`.

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
  image automation (`image-automation.yaml`, lsio `-ls<build>` tag ordering;
  FlareSolverr isn't an lsio image, so it uses a semver policy on its
  `vX.Y.Z` tags instead).

## Configuration (after first deploy or cluster rebuild)

Almost everything is applied by the idempotent wiring script:

```sh
./kubernetes/media/configure-media.sh
```

It reads the `secrets.yaml` (`qbittorrent:` WebUI creds, `arr:` admin
account, `media-secrets` API keys) and applies: qBittorrent categories
(`tv` → `/data/torrents/tv`, `movies` → `/data/torrents/movies`), the shared
Forms-auth admin account on all three UIs, root folders (`/data/media/tv`,
`/data/media/movies`), the qBittorrent download client in Sonarr/Radarr
(host `10.30.1.57:8080` — **no remote path mapping**; both sides see
identical `/data/...` paths), the Prowlarr→Sonarr/Radarr application
links, and both Prowlarr indexer proxies: the gluetun HTTP proxy on hermes
(tag `vpn`, for ISP-blocked indexers) and FlareSolverr (tag `flaresolverr`,
for Cloudflare-protected indexers). API keys are not generated state: they're pinned via the
`media-secrets` Secret (`scripts/secrets.sh`, `SONARR__AUTH__APIKEY` etc.)
into the pods, so a config-PVC loss + re-run of this script restores the
whole setup. Prereqs: `kubectl` (cereal context), `yq`, `python3`.

It also hardens each Sonarr/Radarr indexer against junk/fake releases:
`minimumSeeders=3` (drops dead / suspiciously low-seed results) and
`rejectBlocklistedTorrentHashesWhileGrabbing=true` (refuses a hash you've
already blocklisted, even from another indexer). A Prowlarr full resync can
reset these *arr-side fields, so just re-run the script afterwards — it's
idempotent.

It also keeps the 1 TB disk under control, but by **size rather than by
source**. The script sets each quality's `maxSize`/`preferredSize` in MB per
minute of runtime:

| Resolution | preferred | max | ≈ for a 100-minute film |
| ---------- | --------- | --- | ----------------------- |
| ≤576p (SD) | 6         | 12  | 1.2 GB                  |
| 720p       | 8         | 15  | 1.5 GB                  |
| 1080p      | 12        | 25  | 2.5 GB                  |
| 2160p      | 45        | 90  | 9 GB                    |

Size is the right lever because the *arr parsers give you no way to express
"small rip": BRRip, BDRip and a 12 GB Blu-ray encode all parse as the same
`Bluray-<res>` quality. Banning the source therefore rejected a 900 MB YIFY
BRRip and a bloated Blu-ray identically, while letting a fat 1080p WEB-DL
straight through. A MB/minute ceiling rejects the bloat from *every* source
and lets the small rip in.

Only the formats that are huge by construction rather than by encoder choice
stay banned outright, since no size cap makes them reasonable: **Remux**
(untouched stream, new container), **BR-DISK** (full disc image) and
**Raw-HD** (raw HD transport stream).

Beyond that, each quality profile is scoped to what its name promises —
`SD` ≤576p, `HD-720p` 720p only, `HD-1080p` 1080p only, `HD - 720p/1080p`
both, `Ultra-HD` 2160p, `Any` everything ≤1080p. Profiles you renamed or
created yourself aren't touched except to untick the giants. Profiles are
edited in place, so items already assigned keep their profile; the cutoff is
retargeted to the profile's ceiling only if the old one fell out of scope.
Changes are forward-looking — they don't cancel anything already in the
download queue (clear those from Radarr → Activity and re-search).

Note the stack-wide malware backstop lives on hermes
(`configure-qbittorrent.sh`, excluded executable extensions); the *arr layer
has no "malware score", so name-based blocking can't catch a well-named fake —
prefer a moderated private tracker for the real fix.

Still manual (deliberately — they're accounts/choices, not derivable state):

1. **Indexers** in Prowlarr: Settings → Indexers; they sync to Sonarr/Radarr
   automatically.
2. **Proxy tags on indexers**: the proxies themselves are scripted, but which
   indexers need them is a choice — tag an indexer `vpn` if your ISP blocks
   it, `flaresolverr` if it sits behind Cloudflare (an indexer can carry
   both; the VPN doesn't solve Cloudflare and vice versa). Untagged indexers
   stay direct.
3. Plex needs nothing: it reads `/mnt/data/media` locally on hermes; new
   imports appear on library scan.

## Failure modes

- hermes USB disk absent → `nfs-server` refuses to start (systemd drop-in) and
  the sonarr/radarr pods hang mounting `/data`. Fail-safe by design; reattach
  the disk and `sudo systemctl start nfs-server` on hermes.
- An NFS-server restart briefly stalls *arr I/O (hard-mount semantics); pods
  recover on their own.
