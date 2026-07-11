#!/usr/bin/env bash
# Idempotently apply the media stack's application-level wiring:
#   - qBittorrent categories (tv, movies) on hermes
#   - Sonarr/Radarr/Prowlarr admin account (Forms auth) from secrets.yaml
#   - Sonarr/Radarr root folders + qBittorrent download client
#   - Prowlarr -> Sonarr/Radarr application links (full sync)
#   - Prowlarr indexer proxies: VPN (gluetun, tag vpn) + FlareSolverr
#     (tag flaresolverr)
#
# Everything it applies is derived from this repo + the root secrets.yaml
# (qbittorrent: WebUI creds, arr: webui creds, kubernetes.secrets
# media-secrets: API keys). Run after a fresh deploy or cluster rebuild;
# re-running is safe. Indexers remain manual (see README.md).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SECRETS_FILE="${REPO_ROOT}/secrets.yaml"
QB_URL="${QB_URL:-http://10.30.1.57:8080}"

for cmd in yq kubectl python3; do
    command -v "$cmd" &>/dev/null || { echo "ERROR: $cmd is required." >&2; exit 1; }
done
[[ -f "$SECRETS_FILE" ]] || { echo "ERROR: ${SECRETS_FILE} not found." >&2; exit 1; }

sec() {
    local v
    v="$(yq -r "$1 // \"\"" "$SECRETS_FILE")"
    [[ -n "$v" && "$v" != SET_ON_FIRST_LOGIN && "$v" != YOUR_* ]] \
        || { echo "ERROR: $1 missing in secrets.yaml" >&2; exit 1; }
    printf '%s' "$v"
}

export QB_USER QB_PASS ARR_USER ARR_PASS SONARR_KEY RADARR_KEY PROWLARR_KEY QB_URL
QB_USER="$(sec '.qbittorrent.webui_username')"
QB_PASS="$(sec '.qbittorrent.webui_password')"
ARR_USER="$(sec '.arr.webui_username')"
ARR_PASS="$(sec '.arr.webui_password')"
SONARR_KEY="$(sec '(.kubernetes.secrets[] | select(.name == "media-secrets")).data.SONARR__AUTH__APIKEY')"
RADARR_KEY="$(sec '(.kubernetes.secrets[] | select(.name == "media-secrets")).data.RADARR__AUTH__APIKEY')"
PROWLARR_KEY="$(sec '(.kubernetes.secrets[] | select(.name == "media-secrets")).data.PROWLARR__AUTH__APIKEY')"

# Local port-forwards: the ClusterIP services aren't reachable from the LAN.
PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null || true; }
trap cleanup EXIT
kubectl -n media port-forward deploy/sonarr 18989:8989 >/dev/null 2>&1 & PIDS+=($!)
kubectl -n media port-forward deploy/radarr 17878:7878 >/dev/null 2>&1 & PIDS+=($!)
kubectl -n media port-forward deploy/prowlarr 19696:9696 >/dev/null 2>&1 & PIDS+=($!)
sleep 3

python3 - <<'PYEOF'
import http.cookiejar
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

QB = os.environ["QB_URL"]
QB_USER, QB_PASS = os.environ["QB_USER"], os.environ["QB_PASS"]
ARR_USER, ARR_PASS = os.environ["ARR_USER"], os.environ["ARR_PASS"]
APPS = {
    "sonarr": ("http://127.0.0.1:18989", "v3", os.environ["SONARR_KEY"]),
    "radarr": ("http://127.0.0.1:17878", "v3", os.environ["RADARR_KEY"]),
    "prowlarr": ("http://127.0.0.1:19696", "v1", os.environ["PROWLARR_KEY"]),
}


def api(app, path, payload=None, method=None):
    base, ver, key = APPS[app]
    req = urllib.request.Request(
        f"{base}/api/{ver}{path}",
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={"X-Api-Key": key, "Content-Type": "application/json"},
        method=method or ("POST" if payload is not None else "GET"),
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read().decode()
            return r.status, json.loads(body) if body else None
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]


def wait_ready(app, tries=20):
    for _ in range(tries):
        try:
            st, _ = api(app, "/health")
            if st == 200:
                return
        except OSError:
            pass
        time.sleep(3)
    raise SystemExit(f"{app}: API not reachable via port-forward")


def ensure_auth(app):
    st, cfg = api(app, "/config/host")
    if st != 200:
        print(f"{app}: read host config -> HTTP {st} {cfg}")
        return
    if cfg.get("username") == ARR_USER and cfg.get("authenticationMethod") == "forms":
        print(f"{app}: admin account already configured")
        return
    cfg.update(
        authenticationMethod="forms",
        authenticationRequired="enabled",
        username=ARR_USER,
        password=ARR_PASS,
        passwordConfirmation=ARR_PASS,
    )
    st, r = api(app, f"/config/host/{cfg['id']}", cfg, method="PUT")
    print(f"{app}: apply admin account -> HTTP {st}" + ("" if st in (200, 202) else f" {r}"))


def ensure_rootfolder(app, path):
    _, folders = api(app, "/rootfolder")
    if any(f["path"] == path for f in folders):
        print(f"{app}: root folder {path} present")
        return
    st, r = api(app, "/rootfolder", {"path": path})
    print(f"{app}: add root folder {path} -> HTTP {st}" + ("" if st == 201 else f" {r}"))


def ensure_downloadclient(app, cat_field, cat):
    _, clients = api(app, "/downloadclient")
    if any(c["name"] == "qBittorrent" for c in clients):
        print(f"{app}: download client qBittorrent present")
        return
    payload = {
        "enable": True,
        "protocol": "torrent",
        "priority": 1,
        "removeCompletedDownloads": True,
        "removeFailedDownloads": True,
        "name": "qBittorrent",
        "implementation": "QBittorrent",
        "implementationName": "qBittorrent",
        "configContract": "QBittorrentSettings",
        "tags": [],
        "fields": [
            {"name": "host", "value": "10.30.1.57"},
            {"name": "port", "value": 8080},
            {"name": "useSsl", "value": False},
            {"name": "urlBase", "value": ""},
            {"name": "username", "value": QB_USER},
            {"name": "password", "value": QB_PASS},
            {"name": cat_field, "value": cat},
            {"name": "initialState", "value": 0},
            {"name": "sequentialOrder", "value": False},
            {"name": "firstAndLast", "value": False},
        ],
    }
    prio = ("recentTvPriority", "olderTvPriority") if cat_field == "tvCategory" \
        else ("recentMoviePriority", "olderMoviePriority")
    payload["fields"] += [{"name": p, "value": 0} for p in prio]
    st, r = api(app, "/downloadclient/test", payload)
    if st != 200:
        print(f"{app}: qBittorrent test FAILED -> HTTP {st} {r}")
        return
    st, r = api(app, "/downloadclient", payload)
    print(f"{app}: add download client -> HTTP {st}" + ("" if st == 201 else f" {r}"))


def ensure_vpn_indexer_proxy():
    """'vpn' tag + gluetun HTTP proxy so ISP-blocked indexers (tagged vpn)
    egress via the NordVPN tunnel on hermes. Cloudflare-protected indexers
    are NOT fixed by this (the challenge fires regardless of egress IP)."""
    _, tags = api("prowlarr", "/tag")
    tag = next((t for t in tags if t["label"] == "vpn"), None)
    if tag is None:
        _, tag = api("prowlarr", "/tag", {"label": "vpn"})
        print("prowlarr: created tag vpn")
    _, proxies = api("prowlarr", "/indexerproxy")
    if any(p["name"] == "VPN (gluetun)" for p in proxies):
        print("prowlarr: indexer proxy VPN (gluetun) present")
        return
    payload = {
        "name": "VPN (gluetun)",
        "implementation": "Http",
        "implementationName": "Http",
        "configContract": "HttpSettings",
        "tags": [tag["id"]],
        "fields": [
            {"name": "host", "value": "10.30.1.57"},
            {"name": "port", "value": 8888},
            {"name": "username", "value": ""},
            {"name": "password", "value": ""},
        ],
    }
    st, r = api("prowlarr", "/indexerproxy/test", payload)
    if st != 200:
        print(f"prowlarr: VPN proxy test FAILED -> HTTP {st} {r}")
        return
    st, r = api("prowlarr", "/indexerproxy", payload)
    print(f"prowlarr: add indexer proxy VPN (gluetun) -> HTTP {st}" + ("" if st == 201 else f" {r}"))


def ensure_flaresolverr_proxy():
    """'flaresolverr' tag + the in-cluster FlareSolverr service so
    Cloudflare-protected indexers (tagged flaresolverr) get their challenges
    solved by a headless browser. Orthogonal to the vpn tag; an indexer can
    carry both."""
    _, tags = api("prowlarr", "/tag")
    tag = next((t for t in tags if t["label"] == "flaresolverr"), None)
    if tag is None:
        _, tag = api("prowlarr", "/tag", {"label": "flaresolverr"})
        print("prowlarr: created tag flaresolverr")
    _, proxies = api("prowlarr", "/indexerproxy")
    if any(p["name"] == "FlareSolverr" for p in proxies):
        print("prowlarr: indexer proxy FlareSolverr present")
        return
    payload = {
        "name": "FlareSolverr",
        "implementation": "FlareSolverr",
        "implementationName": "FlareSolverr",
        "configContract": "FlareSolverrSettings",
        "tags": [tag["id"]],
        "fields": [
            {"name": "host", "value": "http://flaresolverr.media.svc.cluster.local:8191"},
            {"name": "requestTimeout", "value": 60},
        ],
    }
    st, r = api("prowlarr", "/indexerproxy/test", payload)
    if st != 200:
        print(f"prowlarr: FlareSolverr proxy test FAILED -> HTTP {st} {r}")
        return
    st, r = api("prowlarr", "/indexerproxy", payload)
    print(f"prowlarr: add indexer proxy FlareSolverr -> HTTP {st}" + ("" if st == 201 else f" {r}"))


def ensure_prowlarr_app(name, base_url, key_env, cats):
    _, apps = api("prowlarr", "/applications")
    if any(a["name"] == name for a in apps):
        print(f"prowlarr: app {name} present")
        return
    payload = {
        "name": name,
        "implementation": name,
        "implementationName": name,
        "configContract": f"{name}Settings",
        "syncLevel": "fullSync",
        "tags": [],
        "fields": [
            {"name": "prowlarrUrl", "value": "http://prowlarr.media.svc.cluster.local:9696"},
            {"name": "baseUrl", "value": base_url},
            {"name": "apiKey", "value": os.environ[key_env]},
            {"name": "syncCategories", "value": cats},
        ],
    }
    st, r = api("prowlarr", "/applications/test", payload)
    if st != 200:
        print(f"prowlarr: {name} test FAILED -> HTTP {st} {r}")
        return
    st, r = api("prowlarr", "/applications", payload)
    print(f"prowlarr: add app {name} -> HTTP {st}" + ("" if st == 201 else f" {r}"))


MIN_SEEDERS = 3


def harden_indexers(app):
    """Per-indexer anti-junk hardening on Sonarr/Radarr:
      - rejectBlocklistedTorrentHashesWhileGrabbing: refuse a hash we've already
        blocklisted (e.g. a failed fake release) even if another indexer offers it.
      - minimumSeeders: drop dead / suspiciously low-seed results.
    These are *arr-side fields on each Prowlarr-synced indexer. A Prowlarr full
    resync can reset them, so this is re-applied every run (idempotent)."""
    _, indexers = api(app, "/indexer")
    for ix in indexers:
        changed = False
        if not ix.get("enableRss") and not ix.get("enableAutomaticSearch"):
            pass
        for f in ix.get("fields", []):
            if f["name"] == "rejectBlocklistedTorrentHashesWhileGrabbing" and f.get("value") is not True:
                f["value"] = True
                changed = True
            if f["name"] == "minimumSeeders" and (f.get("value") or 1) < MIN_SEEDERS:
                f["value"] = MIN_SEEDERS
                changed = True
        if not changed:
            print(f"{app}: indexer {ix['name']} already hardened")
            continue
        st, r = api(app, f"/indexer/{ix['id']}", ix, method="PUT")
        print(f"{app}: harden indexer {ix['name']} (min seeders {MIN_SEEDERS}, reject blocklisted hashes) -> HTTP {st}"
              + ("" if st in (200, 202) else f" {r}"))


def qbittorrent_categories():
    cj = http.cookiejar.CookieJar()
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    # qBittorrent's CSRF protection rejects logins without an Origin/Referer.
    op.addheaders = [("Referer", QB), ("Origin", QB)]
    data = urllib.parse.urlencode({"username": QB_USER, "password": QB_PASS}).encode()
    with op.open(QB + "/api/v2/auth/login", data, timeout=30) as r:
        if r.read().decode() not in ("", "Ok."):
            raise SystemExit("qbittorrent: login failed — check secrets.yaml qbittorrent creds")
    with op.open(QB + "/api/v2/torrents/categories", timeout=30) as r:
        cats = json.load(r)
    for cat, path in (("tv", "/data/torrents/tv"), ("movies", "/data/torrents/movies")):
        if cat in cats:
            print(f"qbittorrent: category {cat} present")
            continue
        data = urllib.parse.urlencode({"category": cat, "savePath": path}).encode()
        with op.open(QB + "/api/v2/torrents/createCategory", data, timeout=30) as r:
            print(f"qbittorrent: create category {cat} -> HTTP {r.status}")


qbittorrent_categories()
for app in APPS:
    wait_ready(app)
    ensure_auth(app)
ensure_rootfolder("sonarr", "/data/media/tv")
ensure_rootfolder("radarr", "/data/media/movies")
ensure_downloadclient("sonarr", "tvCategory", "tv")
ensure_downloadclient("radarr", "movieCategory", "movies")
ensure_vpn_indexer_proxy()
ensure_flaresolverr_proxy()
ensure_prowlarr_app("Sonarr", "http://sonarr.media.svc.cluster.local:8989", "SONARR_KEY",
                    [5000, 5010, 5020, 5030, 5040, 5045, 5050])
ensure_prowlarr_app("Radarr", "http://radarr.media.svc.cluster.local:7878", "RADARR_KEY",
                    [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060])
harden_indexers("sonarr")
harden_indexers("radarr")
print("media wiring applied.")
PYEOF
