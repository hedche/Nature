# Ansible — Nature Homelab

Ansible playbooks and roles for managing non-Talos infrastructure in the Nature homelab.

## Current Roles

### `cups_server`

Configures a Debian/Raspbian host as a CUPS print server with Avahi/mDNS discovery.

**What it does:**
- Installs CUPS, `cups-browsed`, `printer-driver-gutenprint`, `avahi-daemon`, `ipp-usb`
- Enables and starts CUPS + Avahi services
- Adds the configured user to `lpadmin`
- Deploys `cupsd.conf` from a Jinja2 template (allows remote access by default)
- Deploys PPD files and creates printers via `lpadmin`
- Ensures printers are accepting jobs and enabled

**Usage:**

1. Ensure your `secrets.yaml` (`~/.config/nature/secrets.yaml`) contains the printer serial:
   ```yaml
   cups:
     printerSerial: "331AEC"
   ```

2. Run the playbook:
   ```bash
   ansible-playbook -i inventory.yml photon.yml
   ```

**Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `cups_allow_remote` | `true` | Open port 631 and allow all remote access |
| `cups_browsing` | `true` | Enable CUPS mDNS browsing |
| `cups_printers` | See `defaults/main.yml` | Dict of printers to create |
| `cups_admin_user` | `pi` | User added to `lpadmin` group |
| `cups_printer_serial` | From `secrets.yaml` | USB serial of the printer |

**Files:**
- `ansible/roles/cups_server/files/Canon_MG6100.ppd` — PPD for Canon MG6100 series
