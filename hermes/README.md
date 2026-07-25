# hermes — VPN-Protected Torrent Stack + Plex + YouTube Downloads

Docker Compose stack on the `hermes` VM (`10.30.1.57`, provisioned by
[`../proxmox/`](../proxmox/README.md)): [Gluetun](https://github.com/qdm12/gluetun)
as a NordVPN WireGuard gateway with [qBittorrent](https://github.com/linuxserver/docker-qbittorrent)
running entirely inside its network namespace, plus
[Plex](https://github.com/linuxserver/docker-plex) for playback and
[MeTube](https://github.com/alexta69/metube) + [File Browser](https://github.com/filebrowser/filebrowser)
for YouTube downloads (host-networked, outside the VPN). Desired state
lives in this repo; hermes is only the Docker host (same philosophy as `../pxe/`).

| Port  | Service                       | LAN plumbing |
|-------|-------------------------------|--------------|
| 8080  | qBittorrent WebUI (in gluetun)| `127.0.0.1` publish + socket proxy |
| 8081  | MeTube (yt-dlp web UI)        | `network_mode: host` |
| 8082  | File Browser (youtube rw; media/torrents ro) | `network_mode: host` |
| 8888  | gluetun HTTP proxy (Prowlarr) | `127.0.0.1` publish + socket proxy |
| 32400 | Plex                          | `network_mode: host` |

```
Nature LAN 10.30.1.0/24                hermes VM (10.30.1.57)
┌──────────────┐                      ┌─────────────────────────────────┐
│ Mac browser  │── http://:8080 ──────│ gluetun ◄── network namespace ──┤
│ Sonarr/Radarr│      (WebUI/API)     │   │           qbittorrent       │
│  (cereal,    │── proxy :8888 ───────│   │                             │
│ ../kubernetes│      (VPN egress)    │   ▼                             │
│   /media/)   │                      │ WireGuard tunnel (NordVPN)      │
└──────┬───────┘                      └───┼─────────────────────────────┘
       │ NFS 10.30.1.57:/mnt/data ──► /data  ▼  ALL torrent traffic,
       └─ (torrents + media library)  internet  both directions
```

- **Kill switch**: qBittorrent has no network interface of its own
  (`network_mode: service:gluetun`). Peers, trackers, DHT — every packet in or
  out goes through the tunnel; if the VPN drops, there is no route and traffic
  stops rather than leaking.
- **LAN access**: Docker publishes the WebUI on `127.0.0.1:8080` only; a
  `systemd-socket-proxyd` unit (`systemd/qbittorrent-proxy.*`, installed by the
  deploy script) serves `10.30.1.57:8080` to the LAN and forwards to localhost.
  Direct Docker port publishing is broken on hermes: the manually-installed
  Tailscale (`/home/ubuntu/bin/tailscaled`, accept-routes on) has
  `10.30.1.0/24 dev tailscale0` in routing table 52, which steers replies from
  Docker's DNAT/FORWARD path into tailscale0 instead of eth0. Host-terminated
  connections re-originate from the host's own IP, which Tailscale's
  LAN-to-LAN exemption rule (pref 100) routes correctly out eth0.
- **The pref-100 rule is load-bearing and Tailscale can flush it.** Everything
  above depends on that one rule; without it table 52 wins and hermes is dark on
  the LAN (ping, SSH, `:8080` all dead) while the VM is perfectly healthy — the
  guest console still shows a login prompt and `qm status` still says `running`.
  `tailscaled.service` adds it in `ExecStartPost`, but that fires only at service
  start, and tailscaled reprograms routing whenever peers churn. On 2026-07-25 it
  was flushed under a tailscaled that had been up 14 days (`NRestarts=0`), so
  nothing reinstated it and qBittorrent dropped off the LAN. A 30s timer
  (`lan-route-rule-watchdog.sh` + `systemd/hermes-lan-route-rule.*`, installed by
  the deploy script) now re-asserts the rule and logs the repair:

  ```sh
  systemctl list-timers hermes-lan-route-rule.timer
  journalctl -t hermes-lan-route-rule        # one line per repair
  ip rule show | grep '^100:'                # the rule itself
  ```

  Repeated repair entries mean Tailscale is flushing it often; the root-cause fix
  is to stop hermes accepting a subnet route for the LAN it is physically on
  (`tailscale set --accept-routes=false`, which also drops the `10.96.0.0/12` and
  `10.244.0.0/16` cluster routes — check nothing on hermes needs them first).

## Prerequisites

- hermes VM up (Terraform in `../proxmox/`), 1TB USB HDD mounted at `/mnt/data`.
- `nordvpn:` stanza in the `secrets.yaml` (schema:
  `../talos/secrets.yaml.template`). Get the WireGuard private key from
  <https://my.nordaccount.com/dashboard/nordvpn/manual-configuration/>.
- Local tools: `ssh`, `rsync`, `yq` (and optionally `direnv`).

## Deploy

```sh
./deploy-to-hermes.sh            # add --dry-run to preview
```

The script is idempotent. On each run it:

1. Installs Docker Engine + compose plugin from the official apt repo if
   missing (skip with `--skip-bootstrap`).
2. Aborts unless `/mnt/data` is a real mountpoint (the USB disk is `nofail` —
   this prevents downloads landing on the OS disk if it's absent).
3. Creates `/mnt/data/{torrents/{tv,movies,incomplete},media/{tv,movies},youtube}`
   and `/home/ubuntu/appdata/{gluetun,qbittorrent,plex,metube,filebrowser}`
   (app configs live on the OS disk deliberately, so container state survives
   the data disk being away).
4. Rsyncs this directory to `/home/ubuntu/nature-hermes`.
5. Writes the NordVPN key from `secrets.yaml` to a `chmod 600` `.env` on
   hermes (the secret never lands in git or in this directory).
6. `docker compose -p nature-hermes-media up -d --remove-orphans`.
7. Installs/refreshes the `systemd-socket-proxyd` units (qBittorrent WebUI
   `:8080`, gluetun HTTP proxy `:8888`) and the NFS export of `/mnt/data`
   (see below).

## One-time qBittorrent setup

1. Temporary WebUI password:
   `ssh ubuntu@10.30.1.57 "docker logs qbittorrent 2>&1 | grep -i password"`
2. Log in at <http://10.30.1.57:8080> as `admin`, set a permanent password
   (Options → WebUI) and record it under `qbittorrent:` in `secrets.yaml` —
   the Sonarr/Radarr stack on cereal (`../kubernetes/media/`) authenticates
   with it.
3. Options → Downloads: default save path `/data/torrents`, enable incomplete
   folder `/data/torrents/incomplete`.
4. Create categories `tv` → `/data/torrents/tv` and `movies` →
   `/data/torrents/movies` (Sonarr/Radarr assign these).

WebUI authentication stays **on** (no LAN bypass): the WebUI can write to
arbitrary save paths, and the *arr apps handle credentials natively.

## qBittorrent policy (`configure-qbittorrent.sh`)

`./configure-qbittorrent.sh` (also run at the end of `deploy-to-hermes.sh`)
applies two reproducible settings, since qBittorrent's config lives in appdata
and not in git:

- **Malware guard** — qBittorrent's "excluded file names" is set to a list of
  executable/script/installer extensions (`*.exe`, `*.scr`, `*.bat`, `*.ps1`,
  `*.msi`, `*.jar`, …; full list in the script). Any matching file inside *any*
  torrent is marked "do not download", no matter how the torrent was added.
  qBittorrent is the only downloader in the stack, so this is the single
  chokepoint: a fake release whose payload is a `.exe` (a common trick — Sonarr
  will happily grab one from a public indexer) downloads nothing. Video/audio/
  subtitle files are never matched.
- **Category paths** — `use_category_paths_in_manual_mode` is enabled so a
  torrent with the `tv`/`movies` category lands in `/data/torrents/tv` etc.,
  instead of piling into the `/data/torrents` root. (Imports work either way —
  Sonarr/Radarr read the path from qBittorrent — but this keeps things tidy.)

The script is idempotent and reads the WebUI credentials from `secrets.yaml`;
it skips with a warning if the permanent password has not been recorded yet.

## Plex

- **`http://10.30.1.57:32400/web`** — runs with `network_mode: host`
  (Plex-recommended for DLNA/GDM discovery; also dodges the Tailscale × Docker
  DNAT issue below, and deliberately does NOT tunnel through the VPN — only
  torrent traffic must).
- **Claiming**: on a fresh `/config`, grab a token from <https://plex.tv/claim>
  (valid ~4 min) and deploy with it:
  `PLEX_CLAIM=claim-XXXX ./deploy-to-hermes.sh`. Already-claimed servers
  ignore it.
- **Libraries**: media mounts are read-only. Point each library at **only**
  its `/data/media` folder — `/data/media/movies` (Movies) and
  `/data/media/tv` (TV) — the clean, renamed, deduplicated layout the cereal
  Sonarr/Radarr namespace builds by hardlink-importing completed downloads.
  Do **not** add the `/data/torrents/*` dirs: imports are hardlinks (same
  inode in both trees), so Plex would index every item twice, and
  `/data/torrents` also holds raw release names, season packs, the
  `incomplete/` dir, and any junk/fake releases that Plex would match poorly
  or shouldn't see at all.
- **Caveats**: 2 vCPU and no GPU passthrough — expect direct play; heavy
  transcodes will struggle (set clients to "Original" quality). Plex metadata
  lives in `/home/ubuntu/appdata/plex` on the 40 GB OS disk — keep an eye on
  it as the library grows.

## MeTube + File Browser (`:8081` / `:8082`)

YouTube download workflow, phone-friendly over Tailscale (the cereal subnet
router advertises `10.30.1.0/24`, so any tailnet device reaches these
directly — no per-service Tailscale config):

- **MeTube — `http://10.30.1.57:8081`**: paste a video or playlist URL, pick
  quality/format in the UI, downloads run in the background via yt-dlp.
  Files land in `/mnt/data/youtube`; playlists get their own subfolder with
  index-prefixed filenames (`<Playlist Title>/001 - <title>.mp4`) so they
  list in order. Queue/history state lives in `/home/ubuntu/appdata/metube`
  (OS disk). Clearing a finished item from the queue does **not** delete the
  file. Capped at 2 concurrent downloads (2 vCPU shared with Plex).
- **File Browser — `http://10.30.1.57:8082`**: browse and download the
  whole data disk from a phone browser — `youtube/` (read-write, even after
  items leave the MeTube queue; deletion here *is* the retention policy,
  nothing auto-prunes it), plus `media/` and `torrents/` (**read-only**
  mounts: with no auth, a writable mount would let anyone on the LAN/tailnet
  delete the Plex library or yank files out from under seeding torrents).
- **No VPN on purpose**: YouTube throttles/blocks shared VPN IPs; home-IP
  egress is the reliable path, and per the VPN-boundary rule only torrent
  traffic tunnels. Both use `network_mode: host` (the Plex pattern), which
  sidesteps the Tailscale × Docker DNAT breakage — no socket-proxy units.
- **No auth on File Browser, deliberately** (`FB_NOAUTH`): reachable from
  home LAN + tailnet only, content is non-sensitive, and its write scope is
  confined to the `/mnt/data/youtube` bind mount (everything else read-only). This keeps deploys fully
  reproducible with zero secret plumbing (this repo is public). The auth
  choice is baked into the BoltDB at first init — to add auth later, wipe
  `/home/ubuntu/appdata/filebrowser` and redeploy with `FB_USERNAME` +
  `FB_PASSWORD` sourced from `secrets.yaml` via the deploy script's `.env`.
- **When YouTube downloads break** (HTTP 403, "nsig extraction failed",
  "Sign in to confirm you're not a bot"): this is the yt-dlp arms race, not
  a config problem. Bump the pinned `metube` image tag in
  `docker-compose.yml` (releases track yt-dlp near-weekly) and redeploy.
  If churn gets annoying, `YTDL_NIGHTLY_UPDATE_TIME` makes the container
  self-update yt-dlp nightly (mutates the running container; a restart
  reverts to the baked version).

## NFS export for the cereal media namespace

The Sonarr/Radarr pods on cereal (`../kubernetes/media/`) must see the same
filesystem qBittorrent downloads to, so hardlink imports work and no remote
path mappings are needed. The deploy script installs `nfs-kernel-server` and
exports the whole data disk (`nfs/nature-media.exports` →
`/etc/exports.d/nature-media.exports`):

```
/mnt/data 10.30.1.0/24(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
```

- **One export of the whole disk** so `/data/torrents` → `/data/media`
  hardlinks/renames never cross a mount boundary on the client. This means
  `/mnt/data/youtube` rides along in the export too — harmless, and the
  single-export rule is deliberate.
- **`all_squash,anonuid/gid=1000`**: every client identity maps to
  `ubuntu:ubuntu`, matching qBittorrent's `PUID/PGID` — ownership is
  deterministic no matter what uid the pods present.
- **Disk-absent guard**: `systemd/nfs-server-data-disk.conf` (drop-in,
  `RequiresMountsFor=/mnt/data`) stops `nfs-server` from ever exporting the
  empty stub dir when the `nofail` USB disk is missing at boot. After
  reattaching: `sudo systemctl start nfs-server`.
- NFS is host-terminated, so the Tailscale × Docker DNAT breakage below does
  not apply to it.

## VPN HTTP proxy for Prowlarr (`:8888`)

Only the download client belongs behind the VPN — *arr apps routed through
shared VPN IPs get rate-limited/banned by their metadata providers. The one
exception is UK-ISP-blocked indexer sites, which Prowlarr (the single indexer
egress for the stack) routes per-indexer through gluetun's built-in HTTP proxy
(`HTTPPROXY=on`, `:8888`): traffic entering it egresses via the NordVPN
tunnel. Same LAN plumbing as the WebUI: Docker publishes `127.0.0.1:8888`
only, and `systemd/gluetun-httpproxy.*` serves `10.30.1.57:8888` to the LAN.
Configure in Prowlarr as an HTTP Indexer Proxy tagged `vpn` (see
`../kubernetes/media/README.md`).

## Verifying the kill switch

```sh
# Host WAN IP vs container IP — must differ; container shows a NordVPN IP:
ssh ubuntu@10.30.1.57 'curl -s ifconfig.me; echo'
ssh ubuntu@10.30.1.57 'docker exec qbittorrent curl -s ifconfig.me; echo'

# Stop the VPN — qbittorrent must lose all connectivity:
ssh ubuntu@10.30.1.57 'docker stop gluetun && docker exec qbittorrent curl -s -m 10 https://1.1.1.1; echo "exit=$?"'
ssh ubuntu@10.30.1.57 'docker start gluetun'
```

## Caveats

- **Gluetun restarts break the shared namespace.** Compose handles the common
  case (`depends_on: … restart: true` recreates qbittorrent when gluetun is
  recreated by a deploy). If gluetun restarts at runtime (crash, manual
  `docker stop/start`), qbittorrent keeps the stale namespace — DNS breaks and
  it goes `unhealthy` within ~3 minutes. `docker compose up -d` will NOT fix
  it (nothing changed); recover with `docker restart qbittorrent`, or add
  [`qmcgaw/deunhealth`](https://github.com/qdm12/deunhealth) later for
  auto-restarts.
- **No port forwarding on NordVPN**: no inbound peer connections, so
  downloading is unaffected but you only seed to peers that accept outbound
  connections. Accepted trade-off.
- **USB disk absent**: the downloads bind mount uses
  `bind.create_host_path: false`, so qbittorrent refuses to start instead of
  writing to an unmounted `/mnt/data` stub. Reattach the disk and redeploy.
