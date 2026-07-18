#!/usr/bin/env bash
# trigger-cron — fire an allowlisted cron manual-trigger via the internal HTTP
# route (no SSH). See plugins/soleur/skills/trigger-cron/SKILL.md.
#
# The no-SSH replacement for the on-host `inngest send` loopback path (#4734,
# #4742). Reads INNGEST_MANUAL_TRIGGER_SECRET read-only from Doppler and POSTs
# to https://app.soleur.ai/api/internal/trigger-cron.
#
# Allowlisted events are derived from EXPECTED_CRON_FUNCTIONS in
# apps/web-platform/server/inngest/cron-manifest.ts — there is NO second
# hand-maintained list here (mirrors lib/inngest/manual-trigger-allowlist.ts).

set -euo pipefail

ROUTE_URL="https://app.soleur.ai/api/internal/trigger-cron"
SECRET_NAME="INNGEST_MANUAL_TRIGGER_SECRET"
DOPPLER_PROJECT="soleur"

usage() {
  cat <<'EOF'
Usage:
  trigger.sh --list
  trigger.sh --event cron/<name>.manual-trigger [--data '<json-object>'] \
             [--config prd|dev] [--dry-run]

Flags:
  --list            Print allowlisted events (from cron-manifest.ts) and exit.
  --event <name>    The cron/<name>.manual-trigger event to fire.
  --data '<json>'   Optional per-cron event.data (JSON object). The route stamps
                    trigger/at over it; caller cannot override them.
  --config <env>    Doppler config to read the secret from (default: prd).
  --dry-run         Print the curl invocation without firing.
EOF
}

# Locate the cron manifest from the repo root (works from any CWD inside the repo).
repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || {
    echo "trigger.sh: not inside a git repo (cannot locate cron-manifest.ts)" >&2
    exit 2
  }
}

# Extract the allowlisted manual-trigger events from cron-manifest.ts.
# Parses the EXPECTED_CRON_FUNCTIONS array literal (cron-<name>) and applies the
# same transform as manualTriggerEventFor: cron-<name> -> cron/<name>.manual-trigger.
list_events() {
  local manifest="$1"
  [[ -f "$manifest" ]] || { echo "trigger.sh: manifest not found: $manifest" >&2; exit 2; }
  awk '
    /EXPECTED_CRON_FUNCTIONS/ { inarr=1 }
    inarr && /\];/ { inarr=0 }
    inarr {
      while (match($0, /"cron-[a-z0-9-]+"/)) {
        tok = substr($0, RSTART+1, RLENGTH-2)   # strip surrounding quotes
        sub(/^cron-/, "", tok)
        print "cron/" tok ".manual-trigger"
        $0 = substr($0, RSTART+RLENGTH)
      }
    }
  ' "$manifest" | sort -u
}

LIST=0
EVENT=""
DATA=""
CONFIG="prd"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) LIST=1; shift ;;
    --event) EVENT="${2:-}"; shift 2 ;;
    --data) DATA="${2:-}"; shift 2 ;;
    --config) CONFIG="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "trigger.sh: unknown flag: $1" >&2; usage >&2; exit 2 ;;
  esac
done

ROOT="$(repo_root)"
MANIFEST="$ROOT/apps/web-platform/server/inngest/cron-manifest.ts"

if [[ "$LIST" -eq 1 ]]; then
  list_events "$MANIFEST"
  exit 0
fi

if [[ -z "$EVENT" ]]; then
  echo "trigger.sh: --event is required (or use --list)" >&2
  usage >&2
  exit 2
fi

case "$CONFIG" in
  prd|dev) ;;
  *) echo "trigger.sh: --config must be 'prd' or 'dev' (got: $CONFIG)" >&2; exit 2 ;;
esac

# Validate the event against the manifest-derived allowlist (fail fast before
# minting a Doppler read or hitting the route). The `--` stops grep from
# interpreting an event string that begins with `-` as an option.
if ! list_events "$MANIFEST" | grep -qxF -- "$EVENT"; then
  echo "trigger.sh: '$EVENT' is not an allowlisted manual-trigger event." >&2
  echo "Run 'trigger.sh --list' to see valid events." >&2
  exit 2
fi

# Build the JSON body. --data must be a JSON object if provided.
if [[ -n "$DATA" ]]; then
  if ! echo "$DATA" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "trigger.sh: --data must be a JSON object (got: $DATA)" >&2
    exit 2
  fi
  BODY=$(jq -nc --arg ev "$EVENT" --argjson d "$DATA" '{event: $ev, data: $d}')
else
  BODY=$(jq -nc --arg ev "$EVENT" '{event: $ev}')
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '%s\n' "# dry-run (config=$CONFIG): would POST to $ROUTE_URL"
  printf '%s\n' "TOKEN=\$(doppler secrets get $SECRET_NAME -p $DOPPLER_PROJECT -c $CONFIG --plain)"
  printf '%s\n' "curl -sS -X POST $ROUTE_URL \\"
  printf '%s\n' "  -H \"Authorization: Bearer \$TOKEN\" -H 'content-type: application/json' \\"
  printf '%s\n' "  -d '$BODY' -w '\\n%{http_code}\\n'"
  exit 0
fi

# Read the secret read-only and fire. The token is piped straight into the curl
# header via a process-substitution-free env var that is unset immediately; it
# is never echoed.
TOKEN="$(doppler secrets get "$SECRET_NAME" -p "$DOPPLER_PROJECT" -c "$CONFIG" --plain)"
if [[ -z "$TOKEN" ]]; then
  echo "trigger.sh: $SECRET_NAME is empty in Doppler $DOPPLER_PROJECT/$CONFIG" >&2
  exit 2
fi

# mktemp, not $$: a PID is predictable and reused across concurrent runs in shared shells
# (same reason token-efficiency-report.sh's SHORTSTAT_TMP mktemp+EXIT-trap block rejects it).
# See ADR-009 Amendment.
RESP=$(mktemp -t trigger-cron-resp.XXXXXXXX)
trap 'rm -f "$RESP"' EXIT INT TERM
HTTP_CODE=$(curl -sS -o "$RESP" -w '%{http_code}' \
  -X POST "$ROUTE_URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d "$BODY")
unset TOKEN

echo "HTTP $HTTP_CODE"
cat "$RESP" 2>/dev/null && echo
rm -f "$RESP"

# 202 = dispatched. Anything else is a failure the caller must act on.
[[ "$HTTP_CODE" == "202" ]] || exit 1
