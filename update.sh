#!/bin/bash
# update.sh — Pull the latest ubersdr-cwskimmer image and restart the container.
# Run this from the directory containing docker-compose.yml and .env, or
# pass the install directory as the first argument:
#   bash update.sh [/path/to/install/dir] [--force-update]
#
# Flags:
#   --force-update   Also refresh docker-compose.yml from upstream (overwrites local edits)

set -e

FORCE_UPDATE=false
INSTALL_DIR=""
for _arg in "$@"; do
    case "$_arg" in
        --force-update) FORCE_UPDATE=true ;;
        *) [ -z "$INSTALL_DIR" ] && INSTALL_DIR="$_arg" ;;
    esac
done
INSTALL_DIR="${INSTALL_DIR:-$(dirname "$(realpath "$0")")}"

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
success "Updated .env.example (your .env was not changed)"

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
