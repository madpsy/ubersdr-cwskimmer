#!/bin/bash
# update.sh — Pull the latest ubersdr-cwskimmer image and restart the container.
# Run this from the directory containing docker-compose.yml and .env, or
# pass the install directory as the first argument:
#   bash update.sh [/path/to/install/dir] [--force-update]
#
# Flags:
#   --force-update   Also refresh docker-compose.yml from upstream (overwrites local edits)

set -e

# ── Self-protection: re-exec from temp copy so self-overwrite doesn't corrupt execution ─
if [ -z "$_UPDATE_SH_RUNNING" ]; then
    _TMPSCRIPT=$(mktemp /tmp/update-sh-XXXXXX.sh)
    cp "$0" "$_TMPSCRIPT"
    chmod +x "$_TMPSCRIPT"
    export _UPDATE_SH_RUNNING=1
    export _UPDATE_SH_INSTALL_DIR="$(dirname "$(realpath "$0")")"
    exec bash "$_TMPSCRIPT" "$@"
fi

FORCE_UPDATE=false
INSTALL_DIR=""
for _arg in "$@"; do
    case "$_arg" in
        --force-update) FORCE_UPDATE=true ;;
        *) [ -z "$INSTALL_DIR" ] && INSTALL_DIR="$_arg" ;;
    esac
done
INSTALL_DIR="${INSTALL_DIR:-${_UPDATE_SH_INSTALL_DIR:-$(dirname "$(realpath "$0")")}}"

# ── Colours ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RESET='\033[0m'

success() { echo -e "${GREEN}✓ ${RESET}$*"; }
warn()    { echo -e "${YELLOW}⚠ ${RESET}$*"; }
info()    { echo -e "${CYAN}ℹ ${RESET}$*"; }
header()  { echo -e "\n${BOLD}${CYAN}$*${RESET}"; }
error()   { echo -e "\033[0;31m✗ ${RESET}$*" >&2; }

header "=== ubersdr-cwskimmer updater ==="

# ── Sanity checks ──────────────────────────────────────────────────────────────
if [ ! -f "$INSTALL_DIR/docker-compose.yml" ]; then
    error "No docker-compose.yml found in: $INSTALL_DIR"
    echo "  Run install-hub.sh first, or pass the correct install directory:"
    echo "    bash update.sh ~/ubersdr/cwskimmer"
    exit 1
fi

if [ ! -f "$INSTALL_DIR/.env" ]; then
    error "No .env file found in: $INSTALL_DIR"
    echo "  Run install-hub.sh to perform a fresh install."
    exit 1
fi

cd "$INSTALL_DIR"

# docker compose (v2 plugin) or docker-compose (v1 standalone)
if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    error "Docker Compose is not installed."
    exit 1
fi

IMAGE="madpsy/ubersdr-cwskimmer:latest"
REPO_RAW="https://raw.githubusercontent.com/madpsy/ubersdr-cwskimmer/main"

# ── Pull latest Docker image ───────────────────────────────────────────────────
header "Pulling latest image from Docker Hub..."
docker pull "$IMAGE"
success "Image up to date: $IMAGE"

# ── Refresh docker-compose.yml (only if --force-update) ───────────────────────
if [ "$FORCE_UPDATE" = true ]; then
    header "Refreshing docker-compose.yml (--force-update)..."
    cp docker-compose.yml docker-compose.yml.bak
    info "Backed up existing docker-compose.yml → docker-compose.yml.bak"
    curl -fsSL "$REPO_RAW/docker-compose.yml" \
        | grep -v '^\s*build:' \
        > docker-compose.yml
    success "docker-compose.yml updated"
else
    info "Skipping docker-compose.yml refresh (pass --force-update to overwrite)"
fi

# ── Refresh .env.example (not .env) ───────────────────────────────────────────
curl -fsSL "$REPO_RAW/.env.example" -o .env.example
success "Updated .env.example"

# ── Sync known values from UberSDR API into .env ──────────────────────────────
# Read current host/port from .env so we can reach the API
_env_val() { grep -m1 "^$1=" .env 2>/dev/null | cut -d= -f2-; }
_UBERSDR_HOST=$(_env_val UBERSDR_HOST)
_UBERSDR_PORT=$(_env_val UBERSDR_PORT)
_UBERSDR_HOST="${_UBERSDR_HOST:-ubersdr.local}"
_UBERSDR_PORT="${_UBERSDR_PORT:-8080}"

# JSON parser (jq preferred, python3 fallback)
_parse_json() {
    local json="$1" key="$2"
    if command -v jq &>/dev/null; then
        echo "$json" | jq -r "$key // empty" 2>/dev/null
    else
        python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    keys = '$key'.lstrip('.').split('.')
    for k in keys:
        d = d[k]
    print(d if d is not None else '')
except Exception:
    print('')
" <<< "$json" 2>/dev/null
    fi
}

# Try host-reachable addresses (installer runs on host, not inside Docker)
_API_JSON=""
for _probe in "$_UBERSDR_HOST" "172.20.0.1" "ubersdr.local"; do
    info "Querying UberSDR API at http://${_probe}:${_UBERSDR_PORT}/api/description ..."
    if _API_JSON=$(curl -fsSL --max-time 5 "http://${_probe}:${_UBERSDR_PORT}/api/description" 2>/dev/null); then
        _cs=$(_parse_json "$_API_JSON" '.cw_skimmer_callsign')
        [ -z "$_cs" ] && _cs=$(_parse_json "$_API_JSON" '.receiver.callsign')
        if [ -n "$_cs" ]; then
            success "Reached UberSDR API (via ${_probe})"
            break
        fi
    fi
    _API_JSON=""
done

if [ -n "$_API_JSON" ]; then
    _API_CALLSIGN=$(_parse_json  "$_API_JSON" '.cw_skimmer_callsign')
    [ -z "$_API_CALLSIGN" ] && _API_CALLSIGN=$(_parse_json "$_API_JSON" '.receiver.callsign')
    _API_QTH=$(_parse_json       "$_API_JSON" '.receiver.location')
    _API_SQUARE=$(_parse_json    "$_API_JSON" '.receiver.gps.maidenhead')
    _API_RBN_SPOTS=$(_parse_json "$_API_JSON" '.cw_skimmer_rbn_spots')

    # Helper: update a key in .env only if the API returned a non-empty value
    _update_env() {
        local key="$1" val="$2"
        if [ -n "$val" ]; then
            if grep -q "^${key}=" .env; then
                sed -i "s|^${key}=.*|${key}=${val}|" .env
                info "  Updated ${key}=${val}"
            else
                echo "${key}=${val}" >> .env
                info "  Added   ${key}=${val}"
            fi
        fi
    }

    header "Syncing station details from UberSDR API..."
    [ -n "$_API_CALLSIGN"  ] && info "  Callsign  : $_API_CALLSIGN"
    [ -n "$_API_QTH"       ] && info "  QTH       : $_API_QTH"
    [ -n "$_API_SQUARE"    ] && info "  Square    : $_API_SQUARE"
    [ -n "$_API_RBN_SPOTS" ] && info "  RBN spots : $_API_RBN_SPOTS"

    _update_env "CALLSIGN"      "$_API_CALLSIGN"
    _update_env "QTH"           "$_API_QTH"
    _update_env "SQUARE"        "$_API_SQUARE"
    _update_env "RBN_SEND_SPOTS" "$_API_RBN_SPOTS"
    success ".env updated with latest API values"
else
    warn "Could not reach UberSDR API — .env values unchanged"
fi

# ── Ensure visible symlink: config → .env ─────────────────────────────────────
if [ ! -e config ] && [ ! -L config ]; then
    ln -s .env config
    info "Created symlink: config → .env  (edit either file)"
elif [ -L config ] && [ "$(readlink config)" = ".env" ]; then
    : # already correct
else
    warn "'config' already exists and is not a symlink to .env — skipping"
fi

# ── Refresh all helper scripts ────────────────────────────────────────────────
for _script in install-hub.sh update.sh start.sh stop.sh restart.sh; do
    curl -fsSL "$REPO_RAW/$_script" -o "$_script"
    chmod +x "$_script"
done
success "Helper scripts updated (install-hub.sh, update.sh, start.sh, stop.sh, restart.sh)"

# ── Restart container ──────────────────────────────────────────────────────────
header "Restarting container..."
$COMPOSE_CMD up -d --pull always --remove-orphans

echo ""
success "ubersdr-cwskimmer updated and restarted successfully!"
echo ""
echo -e "  ${BOLD}Web interface (direct):${RESET}  http://ubersdr.local:7373/vnc.html?autoconnect=true"
echo -e "  ${BOLD}Web interface (via proxy):${RESET}  http://ubersdr.local:8080/addon/cwskimmer/vnc.html?autoconnect=true&path=addon/cwskimmer/websockify"
echo -e "  ${BOLD}Install dir:${RESET}    $INSTALL_DIR"
echo -e "  ${BOLD}Config file:${RESET}    $INSTALL_DIR/config  (symlink to .env)"
echo ""
echo -e "  Start:      ${CYAN}bash $INSTALL_DIR/start.sh${RESET}"
echo -e "  Stop:       ${CYAN}bash $INSTALL_DIR/stop.sh${RESET}"
echo -e "  Update:     ${CYAN}bash $INSTALL_DIR/update.sh${RESET}"
echo -e "  View logs:  ${CYAN}$COMPOSE_CMD -f $INSTALL_DIR/docker-compose.yml logs -f cwskimmer${RESET}"
echo ""
