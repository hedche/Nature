# hermes — VPN-Protected Torrent Stack + Plex

Docker Compose stack on the `hermes` VM (`10.30.1.57`, provisioned by
[`../proxmox/`](../proxmox/README.md)): [Gluetun](https://github.com/qdm12/gluetun)
as a NordVPN WireGuard gateway with [qBittorrent](https://github.com/linuxserver/docker-qbittorrent)
running entirely inside its network namespace, plus
[Plex](https://github.com/linuxserver/docker-plex) for playback. Desired state
lives in this repo; hermes is only the Docker host (same philosophy as `../pxe/`).

```
Nature LAN 10.30.1.0/24                hermes VM (10.30.1.57)
┌──────────────┐                      ┌─────────────────────────────────┐
│ Mac browser  │── http://:8080 ──────│ gluetun ◄── network namespace ──┤
│ Sonarr/Radarr│      (WebUI/API)     │   │           qbittorrent       │
└──────────────┘                      │   ▼                             │
                                      │ WireGuard tunnel (NordVPN)      │
                                      └───┼─────────────────────────────┘
                                          ▼  ALL torrent traffic,
                                     internet  both directions
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

## Prerequisites

- hermes VM up (Terraform in `../proxmox/`), 1TB USB HDD mounted at `/mnt/data`.
- `nordvpn:` stanza in the root `secrets.yaml` (schema:
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
3. Creates `/mnt/data/torrents/{tv,movies,incomplete}` and
   `/home/ubuntu/appdata/{gluetun,qbittorrent}` (app configs live on the OS
   disk deliberately, so qBittorrent state survives the data disk being away).
4. Rsyncs this directory to `/home/ubuntu/nature-hermes`.
5. Writes the NordVPN key from `secrets.yaml` to a `chmod 600` `.env` on
   hermes (the secret never lands in git or in this directory).
6. `docker compose -p nature-hermes-media up -d --remove-orphans`.

## One-time qBittorrent setup

1. Temporary WebUI password:
   `ssh ubuntu@10.30.1.57 "docker logs qbittorrent 2>&1 | grep -i password"`
2. Log in at <http://10.30.1.57:8080> as `admin`, set a permanent password
   (Options → WebUI) and record it under `qbittorrent:` in `secrets.yaml` —
   the future Sonarr/Radarr stack authenticates with it.
3. Options → Downloads: default save path `/data/torrents`, enable incomplete
   folder `/data/torrents/incomplete`.
4. Create categories `tv` → `/data/torrents/tv` and `movies` →
   `/data/torrents/movies` (Sonarr/Radarr assign these).

WebUI authentication stays **on** (no LAN bypass): the WebUI can write to
arbitrary save paths, and the *arr apps handle credentials natively.

## Plex

- **`http://10.30.1.57:32400/web`** — runs with `network_mode: host`
  (Plex-recommended for DLNA/GDM discovery; also dodges the Tailscale × Docker
  DNAT issue below, and deliberately does NOT tunnel through the VPN — only
  torrent traffic must).
- **Claiming**: on a fresh `/config`, grab a token from <https://plex.tv/claim>
  (valid ~4 min) and deploy with it:
  `PLEX_CLAIM=claim-XXXX ./deploy-to-hermes.sh`. Already-claimed servers
  ignore it.
- **Libraries**: media mounts are read-only. Point libraries at
  `/data/torrents/movies` + `/data/media/movies` (Movies) and
  `/data/torrents/tv` + `/data/media/tv` (TV). The `/data/media` tree is empty
  for now — it is the future Sonarr/Radarr-managed layout; the torrent dirs
  let you watch straight away.
- **Caveats**: 2 vCPU and no GPU passthrough — expect direct play; heavy
  transcodes will struggle (set clients to "Original" quality). Plex metadata
  lives in `/home/ubuntu/appdata/plex` on the 40 GB OS disk — keep an eye on
  it as the library grows.

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
