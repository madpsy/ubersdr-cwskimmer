#!/bin/bash
# install-hub.sh — End-user installer / updater for ubersdr-cwskimmer
# Fetches the pre-built image from Docker Hub; no repo clone required.
#
# First-time install (pipe-safe):
#   curl -fsSL https://raw.githubusercontent.com/madpsy/ubersdr-cwskimmer/main/install-hub.sh | bash
#
# Update / re-run after install:
#   bash ~/ubersdr/cwskimmer/install-hub.sh

# ── When piped through curl | bash, stdin is the pipe not the terminal.
#    Save the script to a temp file and re-exec it with /dev/tty as stdin
#    so that interactive read() prompts work correctly.
if [ ! -t 0 ]; then
    TMPSCRIPT=$(mktemp /tmp/install-hub-XXXXXX.sh)
    cat > "$TMPSCRIPT"          # drain stdin (the script itself) into the temp file
    chmod +x "$TMPSCRIPT"
    exec bash "$TMPSCRIPT" "$@" </dev/tty
fi

set -e

IMAGE="madpsy/ubersdr-cwskimmer:latest"
REPO_RAW="https://raw.githubusercontent.com/madpsy/ubersdr-cwskimmer/main"
INSTALL_DIR="${INSTALL_DIR:-$HOME/ubersdr/cwskimmer}"

# ── Colours ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}ℹ ${RESET}$*"; }
success() { echo -e "${GREEN}✓ ${RESET}$*"; }
warn()    { echo -e "${YELLOW}⚠ ${RESET}$*"; }
error()   { echo -e "${RED}✗ ${RESET}$*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}$*${RESET}"; }

# ── Prerequisite checks ────────────────────────────────────────────────────────
header "=== ubersdr-cwskimmer installer ==="

if ! command -v docker &>/dev/null; then
    error "Docker is not installed. Please install Docker first:"
    echo "  https://docs.docker.com/engine/install/"
    exit 1
fi

if ! docker info &>/dev/null; then
    error "Docker daemon is not running or you don't have permission to use it."
    echo "  Try: sudo systemctl start docker"
    echo "  Or add your user to the docker group: sudo usermod -aG docker \$USER"
    exit 1
fi

# docker compose (v2 plugin) or docker-compose (v1 standalone)
if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    error "Docker Compose is not installed. Please install it first:"
    echo "  https://docs.docker.com/compose/install/"
    exit 1
fi

# ── Detect update vs fresh install ────────────────────────────────────────────
IS_UPDATE=false
if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    IS_UPDATE=true
fi

# ── Create install directory ───────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# ── Pull latest image ──────────────────────────────────────────────────────────
header "Pulling latest image from Docker Hub..."
docker pull "$IMAGE"
success "Image up to date: $IMAGE"

# ── Fetch docker-compose.yml (always refresh to pick up upstream changes) ──────
header "Fetching docker-compose.yml..."

# If updating, back up the existing compose file first
if [ "$IS_UPDATE" = true ] && [ -f docker-compose.yml ]; then
    cp docker-compose.yml docker-compose.yml.bak
    info "Backed up existing docker-compose.yml → docker-compose.yml.bak"
fi

# Download compose file and strip the 'build: .' line so it uses the Hub image
curl -fsSL "$REPO_RAW/docker-compose.yml" \
    | grep -v '^\s*build:' \
    > docker-compose.yml
success "docker-compose.yml saved to $INSTALL_DIR"

# ── Fetch all helper scripts into the install dir ─────────────────────────────
for _script in install-hub.sh update.sh start.sh stop.sh restart.sh; do
    curl -fsSL "$REPO_RAW/$_script" -o "$_script"
    chmod +x "$_script"
done
success "Helper scripts installed (install-hub.sh, update.sh, start.sh, stop.sh, restart.sh)"

# ── .env setup ────────────────────────────────────────────────────────────────
if [ "$IS_UPDATE" = true ] && [ -f .env ]; then
    # On update: refresh .env.example but keep the user's existing .env intact
    curl -fsSL "$REPO_RAW/.env.example" -o .env.example
    success "Updated .env.example (your .env was not changed)"
else
    # Fresh install: download .env.example and prompt user to configure
    curl -fsSL "$REPO_RAW/.env.example" -o .env.example

    header "Station configuration"

    # ── JSON parser helper (jq preferred, python3 fallback) ───────────────────
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

    # ── Auto-detect from UberSDR API ───────────────────────────────────────────
    # Try the default address first (or env-supplied values if already set).
    # If the API call succeeds, host/port are confirmed and no prompts are needed.
    # If it fails, fall back to prompting for host/port.
    API_CALLSIGN=""; API_QTH=""; API_SQUARE=""; API_RBN_SPOTS=""
    _try_api() {
        local host="$1" port="$2"
        local url="http://${host}:${port}/api/description"
        local json
        if json=$(curl -fsSL --max-time 5 "$url" 2>/dev/null); then
            local cs
            cs=$(_parse_json "$json" '.receiver.callsign')
            if [ -n "$cs" ]; then
                API_CALLSIGN="$cs"
                API_QTH=$(_parse_json    "$json" '.receiver.location')
                API_SQUARE=$(_parse_json "$json" '.receiver.gps.maidenhead')
                API_RBN_SPOTS=$(_parse_json "$json" '.receiver.cw_skimmer_rbn_spots')
                return 0
            fi
        fi
        return 1
    }

    echo ""
    if [ -n "${UBERSDR_HOST:-}" ] || [ -n "${UBERSDR_PORT:-}" ]; then
        # Env vars supplied — use them directly, no auto-probe needed
        UBERSDR_HOST="${UBERSDR_HOST:-ubersdr}"
        UBERSDR_PORT="${UBERSDR_PORT:-8080}"
        info "Querying UberSDR API at http://${UBERSDR_HOST}:${UBERSDR_PORT}/api/description ..."
        if _try_api "$UBERSDR_HOST" "$UBERSDR_PORT"; then
            success "Auto-detected station details from UberSDR API"
            info "  Callsign  : $API_CALLSIGN"
            [ -n "$API_QTH"       ] && info "  QTH       : $API_QTH"
            [ -n "$API_SQUARE"    ] && info "  Square    : $API_SQUARE"
            [ -n "$API_RBN_SPOTS" ] && info "  RBN spots : $API_RBN_SPOTS"
        else
            warn "Could not reach UberSDR API at http://${UBERSDR_HOST}:${UBERSDR_PORT} — falling back to prompts"
        fi
    else
        # No env vars — probe host-reachable addresses first (installer runs on the host,
        # not inside Docker, so the internal 'ubersdr' hostname won't resolve here).
        # 172.20.0.1 is the Docker bridge gateway (host-side); ubersdr.local is the mDNS name.
        # Either way, the runtime .env value is still 'ubersdr' (resolved inside the container).
        _PROBE_DONE=false
        for _probe_host in "172.20.0.1" "ubersdr.local"; do
            info "Probing UberSDR API at http://${_probe_host}:8080/api/description ..."
            if _try_api "$_probe_host" "8080"; then
                UBERSDR_HOST="ubersdr"
                UBERSDR_PORT="8080"
                success "Auto-detected station details from UberSDR API (via ${_probe_host})"
                info "  Callsign  : $API_CALLSIGN"
                [ -n "$API_QTH"       ] && info "  QTH       : $API_QTH"
                [ -n "$API_SQUARE"    ] && info "  Square    : $API_SQUARE"
                [ -n "$API_RBN_SPOTS" ] && info "  RBN spots : $API_RBN_SPOTS"
                _PROBE_DONE=true
                break
            fi
        done
        if [ "$_PROBE_DONE" = false ]; then
            warn "Could not reach UberSDR API at default addresses — please enter connection details"
            echo ""
            read -r -p "  UberSDR host   [ubersdr]: " INPUT_HOST
            UBERSDR_HOST="${INPUT_HOST:-ubersdr}"
            read -r -p "  UberSDR port   [8080]: " INPUT_PORT
            UBERSDR_PORT="${INPUT_PORT:-8080}"
            # Try once more with the user-supplied values
            info "Retrying UberSDR API at http://${UBERSDR_HOST}:${UBERSDR_PORT}/api/description ..."
            if _try_api "$UBERSDR_HOST" "$UBERSDR_PORT"; then
                success "Auto-detected station details from UberSDR API"
                info "  Callsign  : $API_CALLSIGN"
                [ -n "$API_QTH"       ] && info "  QTH       : $API_QTH"
                [ -n "$API_SQUARE"    ] && info "  Square    : $API_SQUARE"
                [ -n "$API_RBN_SPOTS" ] && info "  RBN spots : $API_RBN_SPOTS"
            else
                warn "Could not reach UberSDR API — station details must be entered manually"
            fi
        fi
    fi
    echo ""

    # ── Callsign ───────────────────────────────────────────────────────────────
    # Priority: env var > API > prompt
    # Pre-set via env var: CALLSIGN=G0XYZ bash install-hub.sh
    if [ -n "${CALLSIGN:-}" ]; then
        CALLSIGN="${CALLSIGN^^}"
        if [ "$CALLSIGN" = "N0CALL" ]; then
            error "CALLSIGN env var is set to the example default (N0CALL). Please set it to your own callsign."
            exit 1
        fi
        info "Using callsign from environment: $CALLSIGN"
    elif [ -n "$API_CALLSIGN" ]; then
        CALLSIGN="${API_CALLSIGN^^}"
        info "Using callsign from API: $CALLSIGN"
    else
        while true; do
            read -r -p "  Callsign: " CALLSIGN
            CALLSIGN="${CALLSIGN^^}"   # uppercase
            if [ -z "$CALLSIGN" ]; then
                warn "Callsign cannot be empty."
            elif [ "$CALLSIGN" = "N0CALL" ]; then
                warn "Please enter your own callsign, not the example default (N0CALL)."
            else
                break
            fi
        done
    fi

    # ── Operator name ──────────────────────────────────────────────────────────
    # Defaults to callsign. Priority: env var > callsign
    # Pre-set via env var: OPERATOR_NAME="Jane" bash install-hub.sh
    if [ -n "${OPERATOR_NAME:-}" ]; then
        NAME="$OPERATOR_NAME"
        info "Using operator name from environment: $NAME"
    else
        NAME="$CALLSIGN"
    fi

    # ── QTH ───────────────────────────────────────────────────────────────────
    # Priority: env var > API > prompt
    # Pre-set via env var: OPERATOR_QTH="London" bash install-hub.sh
    if [ -n "${OPERATOR_QTH:-}" ]; then
        QTH="$OPERATOR_QTH"
        info "Using QTH from environment: $QTH"
    elif [ -n "$API_QTH" ]; then
        QTH="$API_QTH"
        info "Using QTH from API: $QTH"
    else
        read -r -p "  QTH / location [Dalgety Bay]: " INPUT_QTH
        QTH="${INPUT_QTH:-Dalgety Bay}"
    fi

    # ── Grid square ────────────────────────────────────────────────────────────
    # Priority: env var > API > prompt
    # Pre-set via env var: OPERATOR_SQUARE="IO91wm" bash install-hub.sh
    if [ -n "${OPERATOR_SQUARE:-}" ]; then
        SQUARE="$OPERATOR_SQUARE"
        info "Using grid square from environment: $SQUARE"
    elif [ -n "$API_SQUARE" ]; then
        SQUARE="$API_SQUARE"
        info "Using grid square from API: $SQUARE"
    else
        read -r -p "  Grid square    [IO86ha]: " INPUT_SQUARE
        SQUARE="${INPUT_SQUARE:-IO86ha}"
    fi

    # ── RBN spot submission ────────────────────────────────────────────────────
    # Priority: env var > API > default true
    if [ -n "${RBN_SEND_SPOTS:-}" ]; then
        info "Using RBN spot submission from environment: $RBN_SEND_SPOTS"
    elif [ -n "$API_RBN_SPOTS" ]; then
        RBN_SEND_SPOTS="$API_RBN_SPOTS"
        info "Using RBN spot submission from API: $RBN_SEND_SPOTS"
    else
        RBN_SEND_SPOTS=true
    fi

    # ── Band selection ─────────────────────────────────────────────────────────
    # Priority: ALL_BANDS env var > individual BAND_* env vars > API success (all true) > prompts
    # Pre-set individual bands: BAND_160M=false bash install-hub.sh
    # Enable all bands at once: ALL_BANDS=true bash install-hub.sh
    echo ""
    if [ "${ALL_BANDS:-}" = "true" ]; then
        BAND_160M=true; BAND_80M=true; BAND_60M=true; BAND_40M=true
        BAND_30M=true;  BAND_20M=true; BAND_17M=true; BAND_15M=true
        BAND_12M=true;  BAND_10M=true; BAND_10M_BEACONS=true
        info "All bands enabled (ALL_BANDS=true)"
    elif [ -n "${BAND_160M:-}${BAND_80M:-}${BAND_60M:-}${BAND_40M:-}${BAND_30M:-}${BAND_20M:-}${BAND_17M:-}${BAND_15M:-}${BAND_12M:-}${BAND_10M:-}${BAND_10M_BEACONS:-}" ]; then
        # At least one band env var is set — use env vars for all, defaulting unset ones to true
        BAND_160M="${BAND_160M:-true}"; BAND_80M="${BAND_80M:-true}"
        BAND_60M="${BAND_60M:-true}";   BAND_40M="${BAND_40M:-true}"
        BAND_30M="${BAND_30M:-true}";   BAND_20M="${BAND_20M:-true}"
        BAND_17M="${BAND_17M:-true}";   BAND_15M="${BAND_15M:-true}"
        BAND_12M="${BAND_12M:-true}";   BAND_10M="${BAND_10M:-true}"
        BAND_10M_BEACONS="${BAND_10M_BEACONS:-true}"
        info "Band selection loaded from environment variables"
    elif [ -n "$API_CALLSIGN" ]; then
        # API succeeded — enable all bands by default, no prompts
        BAND_160M=true; BAND_80M=true; BAND_60M=true; BAND_40M=true
        BAND_30M=true;  BAND_20M=true; BAND_17M=true; BAND_15M=true
        BAND_12M=true;  BAND_10M=true; BAND_10M_BEACONS=true
        info "All bands enabled (auto-detected via API)"
    else
        header "Band selection"
        echo "Enable/disable bands — type 'true' or 'false' (Enter = keep default):"
        echo ""

        prompt_band() {
            local band="$1" default="$2"
            read -r -p "  ${band} [${default}]: " val
            echo "${val:-$default}"
        }

        BAND_160M=$(prompt_band "160m" "true")
        BAND_80M=$(prompt_band  "80m"  "true")
        BAND_60M=$(prompt_band  "60m"  "true")
        BAND_40M=$(prompt_band  "40m"  "true")
        BAND_30M=$(prompt_band  "30m"  "true")
        BAND_20M=$(prompt_band  "20m"  "true")
        BAND_17M=$(prompt_band  "17m"  "true")
        BAND_15M=$(prompt_band  "15m"  "true")
        BAND_12M=$(prompt_band  "12m"  "true")
        BAND_10M=$(prompt_band  "10m"  "true")
        BAND_10M_BEACONS=$(prompt_band "10m beacons (28.2-28.3 MHz)" "true")
    fi

    cat > .env <<ENVEOF
# CW Skimmer Docker Configuration
# Generated by install-hub.sh — edit this file to change settings,
# then restart the container: docker compose restart

# Station Configuration
CALLSIGN=${CALLSIGN}
NAME=${NAME}
QTH=${QTH}
SQUARE=${SQUARE}

# UberSDR Configuration
UBERSDR_HOST=${UBERSDR_HOST}
UBERSDR_PORT=${UBERSDR_PORT}

# Frequency Calibration (PPM offset; 1 = no correction)
FREQ_CALIBRATION=1

# Callsign Validation (0 = minimal, 1 = normal, 2 = strict)
MIN_QUALITY=0

# Sample Rate (96 or 192 kHz — 96 recommended, uses half the CPU with no loss of CW coverage)
SAMPLE_RATE=96

# Service Control
CWSKIMM_ENABLED=true

# RBN Spot Submission (true = send spots to RBN, false = suppress)
RBN_SEND_SPOTS=${RBN_SEND_SPOTS}

# Band Selection
BAND_160M=${BAND_160M}
BAND_80M=${BAND_80M}
BAND_60M=${BAND_60M}
BAND_40M=${BAND_40M}
BAND_30M=${BAND_30M}
BAND_20M=${BAND_20M}
BAND_17M=${BAND_17M}
BAND_15M=${BAND_15M}
BAND_12M=${BAND_12M}
BAND_10M=${BAND_10M}
BAND_10M_BEACONS=${BAND_10M_BEACONS}
ENVEOF
    success ".env created"
fi

# ── Visible symlink: config → .env ────────────────────────────────────────────
# .env is hidden by default; 'config' is a visible alias for easy editing.
if [ ! -e config ] && [ ! -L config ]; then
    ln -s .env config
    info "Created symlink: config → .env  (edit either file)"
elif [ -L config ] && [ "$(readlink config)" = ".env" ]; then
    : # already correct, nothing to do
else
    warn "'config' already exists and is not a symlink to .env — skipping symlink creation"
fi

# ── Network check ──────────────────────────────────────────────────────────────
header "Checking Docker network..."
if ! docker network ls --format '{{.Name}}' | grep -q '^ubersdr_sdr-network$'; then
    warn "The external Docker network 'ubersdr_sdr-network' does not exist."
    echo ""
    echo "  This network is normally created by the ka9q_ubersdr stack."
    echo "  If you haven't started that stack yet, do so first, then re-run this script."
    echo ""
    echo "  Alternatively, create the network manually and start anyway:"
    echo "    docker network create ubersdr_sdr-network"
    echo ""
    read -r -p "  Create the network now and continue? [y/N]: " CREATE_NET
    if [[ "$CREATE_NET" =~ ^[Yy]$ ]]; then
        docker network create ubersdr_sdr-network
        success "Network 'ubersdr_sdr-network' created"
    else
        warn "Skipping network creation. The container will fail to start until the network exists."
    fi
else
    success "Network 'ubersdr_sdr-network' found"
fi

# ── Start / restart container ──────────────────────────────────────────────────
header "Starting container..."
$COMPOSE_CMD pull --quiet   # ensure compose also has the freshest digest
$COMPOSE_CMD up -d --remove-orphans

echo ""
if [ "$IS_UPDATE" = true ]; then
    success "ubersdr-cwskimmer updated and restarted successfully!"
else
    success "ubersdr-cwskimmer installed and started successfully!"
fi

echo ""
echo -e "  ${BOLD}Web interface (via proxy):${RESET}  http://ubersdr.local:8080/addon/cwskimmer/vnc.html?autoconnect=true&path=addon/cwskimmer/websockify"
echo -e "  ${BOLD}RBN Aggregator telnet:${RESET}   telnet ubersdr.local 7550"
echo -e "  ${BOLD}Install dir:${RESET}    $INSTALL_DIR"
echo -e "  ${BOLD}Config file:${RESET}    $INSTALL_DIR/config  (symlink to .env)"
echo ""
echo -e "  Start:          ${CYAN}bash $INSTALL_DIR/start.sh${RESET}"
echo -e "  Stop:           ${CYAN}bash $INSTALL_DIR/stop.sh${RESET}"
echo -e "  Update:         ${CYAN}bash $INSTALL_DIR/update.sh${RESET}"
echo -e "  View logs:      ${CYAN}$COMPOSE_CMD -f $INSTALL_DIR/docker-compose.yml logs -f cwskimmer${RESET}"
echo ""
