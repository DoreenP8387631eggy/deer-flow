#!/bin/bash
# cleanup.sh - Clean up smoke test artifacts, temporary files, and optionally stop running services
# Usage: ./cleanup.sh [--docker] [--logs] [--all] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
LOG_DIR="${PROJECT_ROOT}/.agent/logs"
TMP_DIR="${PROJECT_ROOT}/.agent/tmp"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Flags
CLEAN_DOCKER=false
CLEAN_LOGS=false
CLEAN_ALL=false
DRY_RUN=false

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --docker    Stop and remove smoke-test Docker containers and networks
  --logs      Remove agent log files older than 7 days
  --all       Perform all cleanup tasks
  --dry-run   Show what would be removed without actually removing anything
  -h, --help  Show this help message
EOF
  exit 0
}

# Parse arguments
for arg in "$@"; do
  case $arg in
    --docker)   CLEAN_DOCKER=true ;;
    --logs)     CLEAN_LOGS=true ;;
    --all)      CLEAN_ALL=true ;;
    --dry-run)  DRY_RUN=true ;;
    -h|--help)  usage ;;
    *) log_error "Unknown option: $arg"; usage ;;
  esac
done

if $CLEAN_ALL; then
  CLEAN_DOCKER=true
  CLEAN_LOGS=true
fi

if ! $CLEAN_DOCKER && ! $CLEAN_LOGS; then
  log_warn "No cleanup target specified. Use --docker, --logs, or --all."
  usage
fi

# ── Docker cleanup ────────────────────────────────────────────────────────────
clean_docker() {
  log_info "Cleaning up Docker resources for deer-flow smoke tests..."

  if ! command -v docker &>/dev/null; then
    log_warn "Docker not found — skipping Docker cleanup."
    return 0
  fi

  # Stop containers whose names match the project pattern
  local containers
  containers=$(docker ps -a --filter "name=deer-flow" --format "{{.Names}}" 2>/dev/null || true)

  if [[ -z "$containers" ]]; then
    log_info "No deer-flow containers found."
  else
    while IFS= read -r container; do
      if $DRY_RUN; then
        log_info "[DRY-RUN] Would stop and remove container: $container"
      else
        log_info "Stopping container: $container"
        docker stop "$container" &>/dev/null || true
        docker rm   "$container" &>/dev/null || true
        log_info "Removed container: $container"
      fi
    done <<< "$containers"
  fi

  # Remove dangling images created during smoke tests
  local dangling
  dangling=$(docker images --filter "dangling=true" --filter "label=project=deer-flow" -q 2>/dev/null || true)
  if [[ -n "$dangling" ]]; then
    if $DRY_RUN; then
      log_info "[DRY-RUN] Would remove dangling images: $dangling"
    else
      docker rmi $dangling &>/dev/null || true
      log_info "Removed dangling deer-flow images."
    fi
  fi

  # Prune networks labelled for the project
  if $DRY_RUN; then
    log_info "[DRY-RUN] Would prune deer-flow Docker networks."
  else
    docker network prune -f --filter "label=project=deer-flow" &>/dev/null || true
    log_info "Pruned deer-flow Docker networks."
  fi
}

# ── Log cleanup ───────────────────────────────────────────────────────────────
clean_logs() {
  log_info "Cleaning up agent log files older than 7 days in: ${LOG_DIR}"

  if [[ ! -d "$LOG_DIR" ]]; then
    log_warn "Log directory not found: ${LOG_DIR} — skipping."
    return 0
  fi

  local old_logs
  old_logs=$(find "$LOG_DIR" -type f -name "*.log" -mtime +7 2>/dev/null || true)

  if [[ -z "$old_logs" ]]; then
    log_info "No log files older than 7 days found."
    return 0
  fi

  while IFS= read -r logfile; do
    if $DRY_RUN; then
      log_info "[DRY-RUN] Would remove: $logfile"
    else
      rm -f "$logfile"
      log_info "Removed: $logfile"
    fi
  done <<< "$old_logs"

  # Also clean up the tmp directory if it exists
  if [[ -d "$TMP_DIR" ]]; then
    if $DRY_RUN; then
      log_info "[DRY-RUN] Would remove tmp directory: ${TMP_DIR}"
    else
      rm -rf "$TMP_DIR"
      log_info "Removed tmp directory: ${TMP_DIR}"
    fi
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  if $DRY_RUN; then
    log_warn "Dry-run mode enabled — no changes will be made."
  fi

  $CLEAN_DOCKER && clean_docker
  $CLEAN_LOGS   && clean_logs

  log_info "Cleanup complete."
}

main
