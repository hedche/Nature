#!/usr/bin/env bash
# Idempotently apply qBittorrent policy that must be reproducible from the repo
# (the qBittorrent config lives in appdata on hermes, not in git):
#
#   1. Malware guard — refuse to download executable/script file types. qBit's
#      "excluded file names" marks any matching file inside ANY torrent as
#      "do not download", regardless of how the torrent was added (Sonarr,
#      Radarr, manual). A fake release whose only payload is an .exe therefore
#      downloads nothing. This is the single chokepoint for the whole stack —
#      qBittorrent is the only downloader.
#   2. Category paths — put category torrents in their subfolder
#      (tv -> /data/torrents/tv) even in manual mode, so Sonarr/Radarr grabs
#      stop piling into the /data/torrents root.
#
# Credentials come from the root secrets.yaml (qbittorrent: stanza). Safe to
# re-run; setPreferences is idempotent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRETS_FILE="${REPO_ROOT}/secrets.yaml"
QB_URL="${QB_URL:-http://10.30.1.57:8080}"

# Executable / script / installer extensions that have no place in a media
# library and are the usual fake-release malware payloads. Video, audio and
# subtitle files are never matched. Update in one place; the script pushes the
# whole list.
EXCLUDED_PATTERNS=(
    "*.exe" "*.scr" "*.bat" "*.cmd" "*.com" "*.pif" "*.msi" "*.msix" "*.msp"
    "*.vbs" "*.vbe" "*.js" "*.jse" "*.wsf" "*.wsh" "*.ws" "*.ps1" "*.psm1"
    "*.jar" "*.lnk" "*.reg" "*.hta" "*.cpl" "*.msc" "*.dll" "*.sys" "*.drv"
    "*.apk" "*.app" "*.deb" "*.rpm" "*.dmg" "*.pkg" "*.run"
)

for cmd in yq python3; do
    command -v "$cmd" &>/dev/null || { echo "ERROR: $cmd is required." >&2; exit 1; }
done
[[ -f "$SECRETS_FILE" ]] || { echo "ERROR: ${SECRETS_FILE} not found." >&2; exit 1; }

QB_USER="$(yq -r '.qbittorrent.webui_username // ""' "$SECRETS_FILE")"
QB_PASS="$(yq -r '.qbittorrent.webui_password // ""' "$SECRETS_FILE")"
if [[ -z "$QB_PASS" || "$QB_PASS" == SET_ON_FIRST_LOGIN || "$QB_PASS" == YOUR_* ]]; then
    echo "WARNING: qBittorrent WebUI password not set in secrets.yaml — skipping." >&2
    echo "         Set it (Options -> WebUI) and record it under qbittorrent:, then re-run." >&2
    exit 0
fi

export QB_URL QB_USER QB_PASS
printf '%s\n' "${EXCLUDED_PATTERNS[@]}" | QB_EXCLUDED="$(cat)" python3 - <<'PYEOF'
import http.cookiejar, json, os, urllib.parse, urllib.request

QB = os.environ["QB_URL"]
excluded = os.environ["QB_EXCLUDED"].strip()

cj = http.cookiejar.CookieJar()
op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
op.addheaders = [("Referer", QB), ("Origin", QB)]  # qBit CSRF wants these
login = urllib.parse.urlencode({"username": os.environ["QB_USER"],
                                "password": os.environ["QB_PASS"]}).encode()
if op.open(QB + "/api/v2/auth/login", login, timeout=30).read().decode() not in ("", "Ok."):
    raise SystemExit("qbittorrent: login failed — check secrets.yaml qbittorrent creds")

prefs = {
    "excluded_file_names_enabled": True,
    "excluded_file_names": excluded,
    "use_category_paths_in_manual_mode": True,
}
data = urllib.parse.urlencode({"json": json.dumps(prefs)}).encode()
op.open(QB + "/api/v2/app/setPreferences", data, timeout=30).read()

# Read back and confirm
now = json.load(op.open(QB + "/api/v2/app/preferences", timeout=30))
assert now["excluded_file_names_enabled"] is True
assert now["use_category_paths_in_manual_mode"] is True
n = len([p for p in now["excluded_file_names"].splitlines() if p.strip()])
print(f"qbittorrent: malware guard ON ({n} blocked extensions); category paths ON")
PYEOF
