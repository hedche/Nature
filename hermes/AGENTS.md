# hermes media stack — agent conventions

- **This directory is the source of truth** for the Docker media stack on the hermes VM
  (`ubuntu@10.30.1.57`): Gluetun (NordVPN WireGuard) + qBittorrent + Plex. Deploy with
  `./deploy-to-hermes.sh` (idempotent: bootstraps Docker, rsyncs, generates the remote
  `.env` from the root `secrets.yaml`, `compose up`). Never `docker compose` by hand on
  the guest except for debugging; change the repo and redeploy.
- **VPN boundary**: only qBittorrent runs inside gluetun's network namespace
  (`network_mode: service:gluetun` = kill switch). Plex and anything else must NOT be
  routed through the VPN. Secrets live in `secrets.yaml` under `nordvpn:` (WireGuard
  key) and `qbittorrent:` (WebUI credentials — use these for Sonarr/Radarr/API work).
- **Tailscale × Docker gotcha (will bite again)**: hermes runs a manually-installed
  tailscaled (`/home/ubuntu/bin/`, custom unit) with accept-routes, which puts
  `10.30.1.0/24` in routing table 52 and silently breaks *any* Docker-published port
  from the LAN (DNAT replies get steered into tailscale0; localhost still works, which
  masks it). Fixes in use: publish on `127.0.0.1` + `systemd-socket-proxyd` unit
  (qBittorrent WebUI :8080) or `network_mode: host` (Plex :32400). Test a plain nginx
  publish before debugging app config for this symptom. Never enable a Tailscale exit
  node on hermes — it would capture gluetun's tunnel. Details: `README.md` here.
- **Gluetun restarts break qbittorrent's namespace** (DNS dies, healthcheck flips
  unhealthy in ~3 min); `docker compose up -d` will NOT fix an unchanged container —
  recover with `docker restart qbittorrent`.
- **Storage**: 1TB USB HDD whole-disk passthrough at `/mnt/data` (`nofail`) holds
  `torrents/` and `media/`; container configs deliberately live on the OS disk at
  `/home/ubuntu/appdata/`. See `../proxmox/AGENTS.md` for the disk-attach caveat.
