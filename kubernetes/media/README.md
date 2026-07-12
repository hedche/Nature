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

It reads the root `secrets.yaml` (`qbittorrent:` WebUI creds, `arr:` admin
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

It also restricts every Sonarr/Radarr **quality profile to web releases at
1080p or below**: all `Bluray-*` and `Remux-*` qualities and anything above
1080p (2160p/4K) are disallowed, leaving WEBDL/WEBRip and HDTV/SDTV/DVD (≤1080p)
allowed as smaller fallbacks. This is the standard TRaSH-guide mechanism for
excluding a source — a quality that isn't allowed is never grabbed — and it
keeps Blu-ray/Remux (20–60 GB+) off the 1 TB disk. Profiles are edited in place,
so items already assigned to a profile keep it but stop accepting Blu-ray on
their next search/upgrade; the cutoff is retargeted to a web quality if needed.
A profile that would be left with nothing allowed (Radarr's stock **Ultra-HD**,
which is all 2160p) is skipped rather than broken — don't assign anything to it.
The change is forward-looking: it does not cancel Blu-rays already in the
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
