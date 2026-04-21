#!/bin/bash
# run_all_checks.sh
# Master smoke test runner that orchestrates all individual check scripts.
# Runs environment, Docker, deployment, and frontend checks in sequence,
# collects results, and produces a final summary report.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/smoke_test_${TIMESTAMP}.log"
SUMMARY_FILE="${LOG_DIR}/smoke_test_${TIMESTAMP}_summary.txt"

# Colour codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Colour

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
mkdir -p "${LOG_DIR}"

log() {
    echo -e "$*" | tee -a "${LOG_FILE}"
}

header() {
    log ""
    log "${CYAN}============================================================${NC}"
    log "${CYAN}  $*${NC}"
    log "${CYAN}============================================================${NC}"
}

# Track overall pass/fail counts
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
declare -A CHECK_RESULTS

run_check() {
    local name="$1"
    local script="$2"
    shift 2
    local extra_args=("$@")

    log ""
    log "${YELLOW}>>> Running: ${name}${NC}"

    if [[ ! -x "${script}" ]]; then
        log "${YELLOW}[SKIP] ${name}: script not found or not executable (${script})${NC}"
        CHECK_RESULTS["${name}"]="SKIP"
        ((SKIP_COUNT++)) || true
        return 0
    fi

    if bash "${script}" "${extra_args[@]}" >> "${LOG_FILE}" 2>&1; then
        log "${GREEN}[PASS] ${name}${NC}"
        CHECK_RESULTS["${name}"]="PASS"
        ((PASS_COUNT++)) || true
    else
        log "${RED}[FAIL] ${name} — see ${LOG_FILE} for details${NC}"
        CHECK_RESULTS["${name}"]="FAIL"
        ((FAIL_COUNT++)) || true
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
header "DeerFlow Smoke Test Suite  |  ${TIMESTAMP}"
log "Log file : ${LOG_FILE}"
log "Summary  : ${SUMMARY_FILE}"

# Determine deployment mode (default: local)
DEPLOY_MODE="${1:-local}"   # local | docker
log "Deploy mode: ${DEPLOY_MODE}"

# 1. Local environment pre-flight
run_check "Local Environment" "${SCRIPT_DIR}/check_local_env.sh"

# 2. Docker availability (always checked; deployment step depends on mode)
run_check "Docker Availability" "${SCRIPT_DIR}/check_docker.sh"

# 3. Deployment
if [[ "${DEPLOY_MODE}" == "docker" ]]; then
    run_check "Docker Deployment" "${SCRIPT_DIR}/deploy_docker.sh"
else
    run_check "Local Deployment" "${SCRIPT_DIR}/deploy_local.sh"
fi

# 4. Frontend health
run_check "Frontend Health" "${SCRIPT_DIR}/frontend_check.sh"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "Smoke Test Summary"

{
    echo "DeerFlow Smoke Test — ${TIMESTAMP}"
    echo "Deploy mode : ${DEPLOY_MODE}"
    echo ""
    printf '%-30s %s\n' "Check" "Result"
    printf '%-30s %s\n' "-----" "------"
    for check in "${!CHECK_RESULTS[@]}"; do
        printf '%-30s %s\n' "${check}" "${CHECK_RESULTS[$check]}"
    done
    echo ""
    echo "PASSED : ${PASS_COUNT}"
    echo "FAILED : ${FAIL_COUNT}"
    echo "SKIPPED: ${SKIP_COUNT}"
} | tee -a "${LOG_FILE}" > "${SUMMARY_FILE}"

log ""
if [[ "${FAIL_COUNT}" -gt 0 ]]; then
    log "${RED}Smoke tests FAILED (${FAIL_COUNT} failure(s)). Check ${LOG_FILE} for details.${NC}"
    exit 1
else
    log "${GREEN}All smoke tests PASSED.${NC}"
    exit 0
fi
