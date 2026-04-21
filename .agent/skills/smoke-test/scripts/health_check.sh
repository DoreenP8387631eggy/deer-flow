#!/bin/bash
# health_check.sh - Verify that all core services are healthy after deployment
# Used as a post-deploy validation step in the smoke-test skill

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

BACKEND_URL="${BACKEND_URL:-http://localhost:8000}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-/health}"
MAX_RETRIES="${MAX_RETRIES:-10}"
RETRY_INTERVAL="${RETRY_INTERVAL:-5}"   # seconds between retries
TIMEOUT="${TIMEOUT:-5}"                  # curl connect/read timeout

# Colour helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass()  { echo -e "${GREEN}[PASS]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
info()  { echo -e "${YELLOW}[INFO]${NC} $*"; }

FAILURES=0

# ── Helpers ──────────────────────────────────────────────────────────────────

# wait_for_url <url> <label>
# Retries up to MAX_RETRIES times, returning 0 on first success.
wait_for_url() {
    local url="$1"
    local label="$2"
    local attempt=1

    while [[ $attempt -le $MAX_RETRIES ]]; do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout "$TIMEOUT" \
            --max-time "$TIMEOUT" \
            "$url" 2>/dev/null || echo "000")

        if [[ "$http_code" =~ ^2 ]]; then
            pass "${label} responded with HTTP ${http_code} (attempt ${attempt}/${MAX_RETRIES})"
            return 0
        fi

        info "${label} not ready yet (HTTP ${http_code}) — waiting ${RETRY_INTERVAL}s … (${attempt}/${MAX_RETRIES})"
        sleep "$RETRY_INTERVAL"
        (( attempt++ ))
    done

    fail "${label} did not become healthy after ${MAX_RETRIES} attempts"
    return 1
}

# check_json_key <url> <jq_filter> <expected> <label>
# Fetches JSON from url and asserts that jq_filter equals expected.
check_json_key() {
    local url="$1"
    local filter="$2"
    local expected="$3"
    local label="$4"

    if ! command -v jq &>/dev/null; then
        info "jq not found — skipping JSON assertion for ${label}"
        return 0
    fi

    local actual
    actual=$(curl -s --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" "$url" \
        | jq -r "$filter" 2>/dev/null || echo "")

    if [[ "$actual" == "$expected" ]]; then
        pass "${label}: ${filter} == '${expected}'"
    else
        fail "${label}: expected '${expected}', got '${actual}'"
        (( FAILURES++ ))
    fi
}

# ── Checks ───────────────────────────────────────────────────────────────────

check_backend_health() {
    info "Checking backend health at ${BACKEND_URL}${HEALTH_ENDPOINT} …"
    if wait_for_url "${BACKEND_URL}${HEALTH_ENDPOINT}" "Backend"; then
        check_json_key "${BACKEND_URL}${HEALTH_ENDPOINT}" '.status' 'ok' "Backend health status"
    else
        (( FAILURES++ ))
    fi
}

check_frontend_health() {
    info "Checking frontend at ${FRONTEND_URL} …"
    if ! wait_for_url "${FRONTEND_URL}" "Frontend"; then
        (( FAILURES++ ))
    fi
}

check_api_docs() {
    local docs_url="${BACKEND_URL}/docs"
    info "Checking API docs at ${docs_url} …"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" \
        "$docs_url" 2>/dev/null || echo "000")

    if [[ "$http_code" =~ ^2 ]]; then
        pass "API docs reachable (HTTP ${http_code})"
    else
        fail "API docs not reachable (HTTP ${http_code})"
        (( FAILURES++ ))
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    echo "======================================="
    echo " DeerFlow — Service Health Check"
    echo "======================================="
    echo "  Backend  : ${BACKEND_URL}"
    echo "  Frontend : ${FRONTEND_URL}"
    echo "  Retries  : ${MAX_RETRIES} × ${RETRY_INTERVAL}s"
    echo "---------------------------------------"

    check_backend_health
    check_frontend_health
    check_api_docs

    echo "---------------------------------------"
    if [[ $FAILURES -eq 0 ]]; then
        pass "All health checks passed."
        exit 0
    else
        fail "${FAILURES} health check(s) failed."
        exit 1
    fi
}

main "$@"
