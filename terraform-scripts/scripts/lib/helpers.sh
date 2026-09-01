################################################################################
# scripts/lib/helpers.sh
#
# Shared logging + colour + tiny utility helpers. Source this from every
# script in scripts/ and from deploy.sh at the top:
#
#   source "$(dirname "$0")/scripts/lib/helpers.sh"
################################################################################

# Only define colours when writing to a real terminal.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BLUE=$'\033[0;34m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  RED=$'\033[0;31m'
  BOLD=$'\033[1m'
  NC=$'\033[0m'
else
  BLUE=""; GREEN=""; YELLOW=""; RED=""; BOLD=""; NC=""
fi

log_info()    { echo "${BLUE}[INFO]${NC}    $*"; }
log_success() { echo "${GREEN}[OK]${NC}      $*"; }
log_warning() { echo "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo "${RED}[ERROR]${NC}   $*" >&2; }

hr() { printf '%.0s─' $(seq 1 78); echo; }

banner() {
  local title="$1"
  echo
  echo "${BOLD}${BLUE}"
  hr
  echo "  $title"
  hr
  echo "${NC}"
}

# require_cmd curl aws terraform ...
require_cmd() {
  local missing=0
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log_error "Missing required command: $cmd"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ]
}

# Print the timestamp shared by every artefact in a single run.
ts() { date -u +%Y%m%dT%H%M%SZ; }
