# QNAP PXE Recovery Server

This directory defines a containerized PXE boot service for the QNAP NAS at `10.30.1.20`.

The PXE service is managed from Git and pushed to the NAS over SSH. QNAP is only the Docker host; the desired state lives in this repo.

## Design

- `dnsmasq` provides proxyDHCP and TFTP.
- `nginx` serves iPXE menus and HTTP boot assets on port `8080`.
- `images.yaml` defines bootable images.
- `nodes.yaml` defines known Talos nodes for optional unattended reinstall.
- `generated/` is produced by scripts and is gitignored.

The Compose stack uses `network_mode: host` because PXE discovery depends on LAN broadcast traffic and the service should be reachable on the NAS IP, `10.30.1.20`.

## QNAP Prerequisites

On the TS-251+:

1. Assign or reserve `10.30.1.20` for the NAS.
2. Install and enable Container Station.
3. Enable SSH for an admin-equivalent user.
4. Confirm Docker Compose is available:
   ```bash
   ssh admin@10.30.1.20 'docker compose version'
   ```
5. Disable QNAP native TFTP/DHCP services if they conflict with this container.

The deploy script defaults to:

```bash
QNAP_SSH_HOST=admin@10.30.1.20
QNAP_PXE_DIR=/share/Container/nature-pxe
COMPOSE_PROJECT=nature-pxe
```

Override them with environment variables or deploy flags.

## Deploy

```bash
./pxe/deploy-to-qnap.sh
```

The script:

1. Generates iPXE assets from `pxe/images.yaml`.
2. Syncs this directory to `/share/Container/nature-pxe` with `rsync --delete`.
3. Runs Docker Compose on the NAS:
   ```bash
   docker compose -p nature-pxe up -d --build --remove-orphans
   ```

Dry run:

```bash
./pxe/deploy-to-qnap.sh --dry-run
```

Validate after deploy:

```bash
./pxe/test-pxe.sh
```

## Safe Talos Recovery Flow

This is the default and recommended mode.

```bash
./pxe/deploy-to-qnap.sh
```

Then:

1. Boot the target Talos node from PXE.
2. Select `Talos maintenance mode`.
3. From your workstation, apply the existing generated config:
   ```bash
   ./talos/bootstrap.sh apply <node>
   ```
4. Check cluster health:
   ```bash
   ./talos/bootstrap.sh status
   ```

This mode does not serve Talos machine configs over HTTP.

## Optional Unattended Talos Reinstall

Unattended mode copies generated Talos configs into the PXE HTTP tree and adds a menu entry that fetches config by client MAC address.

Before using it:

1. Replace every `TODO` MAC in `pxe/nodes.yaml`.
2. Confirm the network is trusted.
3. Understand that Talos configs contain cluster secrets.

Deploy:

```bash
./pxe/deploy-to-qnap.sh --include-talos-configs
```

For non-interactive use:

```bash
./pxe/deploy-to-qnap.sh --include-talos-configs --yes-risk-expose-talos-configs
```

After reinstalling, remove served configs:

```bash
./pxe/deploy-to-qnap.sh
```

## Adding Bootable Images

Add entries to `pxe/images.yaml`.

Talos entries use the shared `talos:` settings:

```yaml
images:
    - id: talos-maintenance
      label: Talos maintenance mode
      type: talos
```

Generic iPXE chain entries are also supported:

```yaml
images:
    - id: netbootxyz
      label: netboot.xyz
      type: ipxe-chain
      url: https://boot.netboot.xyz
```

Then redeploy:

```bash
./pxe/deploy-to-qnap.sh
```

## DHCP / Router Notes

The container runs `dnsmasq` in proxyDHCP mode, so your existing DHCP server should continue assigning addresses.

If you prefer router-managed PXE options instead of proxyDHCP:

- UEFI boot file: `ipxe.efi`
- BIOS boot file: `undionly.kpxe`
- Next server / TFTP server: `10.30.1.20`

ProxyDHCP is the safer default for this homelab because it avoids replacing the existing DHCP service.

## Security Notes

- Do not commit anything under `pxe/generated/`.
- Do not use unattended mode on an untrusted LAN.
- Redeploy without `--include-talos-configs` after unattended reinstall.
- The container does not mount the Docker socket.
- HTTP listens on `8080` to avoid QNAP web UI conflicts.

