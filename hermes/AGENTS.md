# hermes media stack — agent conventions

- **This directory is the source of truth** for the Docker media stack on the hermes VM
  (`ubuntu@10.30.1.57`): Gluetun (NordVPN WireGuard) + qBittorrent + Plex + MeTube +
  File Browser. Deploy with
  `./deploy-to-hermes.sh` (idempotent: bootstraps Docker, rsyncs, generates the remote
  `.env` from the root `secrets.yaml`, `compose up`). Never `docker compose` by hand on
  the guest except for debugging; change the repo and redeploy.
- **VPN boundary**: only qBittorrent runs inside gluetun's network namespace
  (`network_mode: service:gluetun` = kill switch). Plex and anything else must NOT be
  routed through the VPN. Secrets live in `secrets.yaml` under `nordvpn:` (WireGuard
  key) and `qbittorrent:` (WebUI credentials — use these for Sonarr/Radarr/API work).
- **qBittorrent policy is repo-managed** via `configure-qbittorrent.sh` (run by the
  deploy script): a malware guard (executable/script extensions set as qBit "excluded
  file names" — the stack-wide chokepoint, since qBittorrent is the only downloader)
  and category paths (`tv`/`movies` torrents land in their subfolder). qBit config
  lives in appdata, not git, so never hand-set these in the WebUI — change the script
  and re-run.
- **Tailscale × Docker gotcha (will bite again)**: hermes runs a manually-installed
  tailscaled (`/home/ubuntu/bin/`, custom unit) with accept-routes, which puts
  `10.30.1.0/24` in routing table 52 and silently breaks *any* Docker-published port
  from the LAN (DNAT replies get steered into tailscale0; localhost still works, which
  masks it). Fixes in use: publish on `127.0.0.1` + `systemd-socket-proxyd` unit
  (qBittorrent WebUI :8080) or `network_mode: host` (Plex :32400). Test a plain nginx
  publish before debugging app config for this symptom. Never enable a Tailscale exit
  node on hermes — it would capture gluetun's tunnel. Details: `README.md` here.
- **MeTube (:8081) + File Browser (:8082)** are the YouTube download pair: both
  `network_mode: host` (Tailscale gotcha above), both deliberately OUTSIDE the VPN
  (YouTube blocks shared VPN IPs; the VPN is torrent-only). Downloads land on
  `/mnt/data/youtube`; state/DB in appdata. File Browser is noauth on purpose (scoped
  to the youtube mount, LAN/tailnet only, keeps the public repo secret-free). When
  YouTube downloads start failing (403 / nsig / bot-check), bump the pinned `metube`
  image tag first — do not debug app config.
- **Gluetun restarts break qbittorrent's namespace** (DNS dies, healthcheck flips
  unhealthy in ~3 min); `docker compose up -d` will NOT fix an unchanged container —
  recover with `docker restart qbittorrent`.
- **Storage**: 1TB USB HDD whole-disk passthrough at `/mnt/data` (`nofail`) holds
  `torrents/` and `media/`; container configs deliberately live on the OS disk at
  `/home/ubuntu/appdata/`. See `../proxmox/AGENTS.md` for the disk-attach caveat.
- **NFS export**: `/mnt/data` is exported to `10.30.1.0/24` for the cereal `media`
  namespace (`../kubernetes/media/` — Sonarr/Radarr mount it at `/data`, matching
  qBittorrent's container paths so imports are hardlinks). Repo-managed:
  `nfs/nature-media.exports` → `/etc/exports.d/` plus an `nfs-server` drop-in
  (`RequiresMountsFor=/mnt/data`, never export the stub dir), installed by the
  deploy script. gluetun also exposes its HTTP proxy on `:8888` (localhost publish
  + `gluetun-httpproxy` socket-proxy units) so Prowlarr can route ISP-blocked
  indexers through the VPN — never route whole *arr apps through it (metadata
  providers ban shared VPN IPs).
