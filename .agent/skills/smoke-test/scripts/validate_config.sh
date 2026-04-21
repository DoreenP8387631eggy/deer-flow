#!/usr/bin/env bash
# validate_config.sh — Validates configuration files and environment variables
# required for deer-flow to run correctly.
#
# Usage: ./validate_config.sh [--env-file <path>] [--strict]
#   --env-file <path>  Path to .env file (default: project root .env)
#   --strict           Treat warnings as errors

set -euo pipefail

# ── Colour helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Argument parsing ────────────────────────────────────────────────────────
STRICT=false
ENV_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE="$2"; shift 2 ;;
    --strict)   STRICT=true; shift ;;
    *) error "Unknown argument: $1"; exit 1 ;;
  esac
done

# Resolve project root (two levels up from this script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Default env file location
[[ -z "$ENV_FILE" ]] && ENV_FILE="${PROJECT_ROOT}/.env"

ERRORS=0
WARNINGS=0

fail()  { error "$*"; (( ERRORS++ )); }
advise() { warn "$*";  (( WARNINGS++ )); }

# ── 1. Check .env file exists ────────────────────────────────────────────────
info "Checking env file: ${ENV_FILE}"
if [[ ! -f "$ENV_FILE" ]]; then
  fail ".env file not found at ${ENV_FILE}. Copy .env.example and fill in values."
else
  ok ".env file found"
  # shellcheck disable=SC1090
  set -o allexport; source "$ENV_FILE"; set +o allexport
fi

# ── 2. Required environment variables ───────────────────────────────────────
REQUIRED_VARS=(
  "OPENAI_API_KEY"
  "TAVILY_API_KEY"
)

info "Validating required environment variables…"
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    fail "Required variable \$${var} is not set or empty."
  else
    # Mask the value in output
    masked="${!var:0:4}****"
    ok "\$${var} = ${masked}"
  fi
done

# ── 3. Optional but recommended variables ───────────────────────────────────
OPTIONAL_VARS=(
  "LANGCHAIN_API_KEY"
  "LANGCHAIN_TRACING_V2"
  "LANGCHAIN_PROJECT"
)

info "Checking optional environment variables…"
for var in "${OPTIONAL_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    advise "Optional variable \$${var} is not set (LangSmith tracing disabled)."
  else
    ok "\$${var} is set"
  fi
done

# ── 4. Validate conf/config.yaml if present ──────────────────────────────────
CONFIG_YAML="${PROJECT_ROOT}/conf/config.yaml"
info "Checking conf/config.yaml…"
if [[ ! -f "$CONFIG_YAML" ]]; then
  advise "conf/config.yaml not found — default settings will be used."
else
  ok "conf/config.yaml found"
  # Basic YAML syntax check via Python if available
  if command -v python3 &>/dev/null; then
    if python3 -c "import yaml, sys; yaml.safe_load(open('${CONFIG_YAML}'))" 2>/dev/null; then
      ok "conf/config.yaml is valid YAML"
    else
      fail "conf/config.yaml contains invalid YAML syntax."
    fi
  else
    advise "python3 not found — skipping YAML syntax validation."
  fi
fi

# ── 5. Summary ───────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────"
echo -e "  Errors   : ${RED}${ERRORS}${NC}"
echo -e "  Warnings : ${YELLOW}${WARNINGS}${NC}"
echo "────────────────────────────────────────"

if [[ $ERRORS -gt 0 ]]; then
  error "Configuration validation FAILED. Fix the errors above before proceeding."
  exit 1
fi

if [[ $STRICT == true && $WARNINGS -gt 0 ]]; then
  error "Strict mode: warnings treated as errors. Resolve the warnings above."
  exit 1
fi

ok "Configuration validation passed."
exit 0
