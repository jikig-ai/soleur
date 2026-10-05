#!/usr/bin/env bash
# Create a new runtime feature flag in Flagsmith + wire it into the codebase.
#
# Contract: SKILL.md in the parent directory.
# Usage: bash create.sh <kebab-name> [--description "..."] [--dev-on] [--prd-on] [--flagsmith-only] [--dry-run]
#
# Run the write in your OWN terminal: the ack below needs a person to type yes.
# An agent runs only `--dry-run` and prints this command for the operator.
#
# Exit codes:
#   0 — success / dry-run
#   1 — usage / name / already-registered failure, or the operator did not type
#       yes at the ack (stdout: SOLEUR_BOOTSTRAP_ABORTED stage=ack; nothing mutated)
#   2 — prerequisite missing, or an option value that looks like a flag
#   3 — Flagsmith API error
#   4 — file edit / audit append failed
#   5 — Doppler write failed
#  64 — no TTY on stdin for a write run (stdout: SOLEUR_BOOTSTRAP_INPUT_REQUIRED);
#       refused before any credential fetch or network call (#8486)

set -euo pipefail

# (#7797) Refuse to run under shell tracing. UNCONDITIONAL — deliberately NOT
# gated on a non-emptiness test of the credential variable, because
# every credential this script handles (the Flagsmith management key, and the
# soleur/prd SUPABASE_SERVICE_ROLE_KEY the audit helper binds) is acquired by
# `doppler secrets get` BELOW this point, so a conditional arm would test an empty
# variable at guard time, open, and then trace the acquisition itself. The refusal
# prints on STDOUT because agent runtimes surface stdout and swallow stderr
# (knowledge-base/project/constitution.md > Code Style).
case "$-" in
  *x*)
    printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n'
    exit 78
    ;;
esac

# (#7873) `--disable` closes ~/.curlrc and `--noproxy '*'` closes the proxy vars,
# but neither touches the env that subverts TLS ITSELF. SSLKEYLOGFILE writes the
# session keys and the CA vars substitute the trust store, so a CURL_CA_BUNDLE
# MITM of these credentials works with every other guard fully intact.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME \
      HOSTALIASES LOCALDOMAIN RES_OPTIONS

# Shared WORM audit-append helper (PostgREST RPC; no DB-CLI binary). See #4581 PR-1.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../scripts/audit-flag-flip.sh"

# Human-presence gate (#8486, ADR-249). Every production write below waits on the
# operator-script library's class-2 ack, which has NO skip variable and no flag:
# it needs a person typing `yes` at a terminal, so an agent's tool subprocess
# (no TTY) is refused with exit 64 before any credential fetch. Clear anything an
# inherited environment could use to pre-empt the library's double-source guard
# or to stand in for its ack before sourcing it. (BASH_ENV runs before this
# script and cannot be cleared from inside it — recorded in ADR-249 as a
# hijack-class residual.)
unset _SOLEUR_OPERATOR_SCRIPT_LOADED SOLEUR_OP_ACKED
unset -f soleur_op_ack_or_die soleur_op_input_required soleur_op_aborted
# shellcheck source=../../../scripts/lib/operator-script.sh
source "$SCRIPT_DIR/../../../scripts/lib/operator-script.sh"
[[ ${SOLEUR_OP_LIB_API:-0} -eq 1 ]] || {
  printf 'SOLEUR_BOOTSTRAP_LIB_INCOMPATIBLE need=1 got=%s\n' "${SOLEUR_OP_LIB_API:-0}"
  exit 64
}

readonly FLAGSMITH_PROJECT_ID=39082
readonly FLAGSMITH_ENV_DEV_ID=90722
readonly FLAGSMITH_ENV_PRD_ID=90721
readonly FLAGSMITH_API="https://api.flagsmith.com/api/v1"
readonly SERVER_TS="apps/web-platform/lib/feature-flags/server.ts"
readonly ENV_EXAMPLE="apps/web-platform/.env.example"

DRY_RUN=0
DEV_ON=0
PRD_ON=0
FLAGSMITH_ONLY=0
DESCRIPTION=""
NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)        DRY_RUN=1; shift ;;
    --dev-on)         DEV_ON=1; shift ;;
    --prd-on)         PRD_ON=1; shift ;;
    --flagsmith-only) FLAGSMITH_ONLY=1; shift ;;
    --description)
      # A value that looks like a flag is refused, so `--description --dry-run`
      # can never read as a dry run to one parser and a write to another (#8486).
      [[ $# -ge 2 && "$2" != --* ]] || { echo "--description needs a value that does not start with --" >&2; exit 2; }
      DESCRIPTION="$2"; shift 2 ;;
    --*)              echo "unknown flag: $1" >&2; exit 1 ;;
    *)                NAME="$1"; shift ;;
  esac
done

[[ -z "$NAME" ]] && { echo "Usage: create.sh <kebab-name> [--description ...] [--dev-on] [--prd-on] [--dry-run]" >&2; exit 1; }
[[ ! "$NAME" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] && { echo "name must be lowercase kebab-case (got: $NAME)" >&2; exit 1; }

ENV_VAR="FLAG_$(echo "$NAME" | tr 'a-z-' 'A-Z_')"

# --- no TTY, no write: refuse before any credential fetch or network call ---
if [[ $DRY_RUN -eq 0 ]]; then [[ -t 0 ]] || soleur_op_input_required "destructive-write-ack(no-skip-variable-by-design)" ack; fi

# --flagsmith-only (gap 1, #4581 PR-2): the flag is ALREADY code-wired (in
# RUNTIME_FLAGS + .env.example) — this run only creates the Flagsmith feature.
# Skip the file-existence checks AND the "already appears in server.ts" exit-1
# precheck (which would fire precisely because the flag IS already wired), plus
# the server.ts/.env.example edits and the Doppler mirror further down.
if [[ $FLAGSMITH_ONLY -eq 0 ]]; then
  [[ ! -f "$SERVER_TS" ]] && { echo "missing $SERVER_TS (run from repo root)" >&2; exit 2; }
  [[ ! -f "$ENV_EXAMPLE" ]] && { echo "missing $ENV_EXAMPLE" >&2; exit 2; }

  # Pre-check: flag name not already registered.
  if grep -qE "[\"']${NAME}[\"']" "$SERVER_TS"; then
    echo "'$NAME' already appears in $SERVER_TS" >&2; exit 1
  fi
  if grep -qE "^${ENV_VAR}=" "$ENV_EXAMPLE"; then
    echo "$ENV_VAR already in $ENV_EXAMPLE" >&2; exit 1
  fi
fi

TOKEN=$(doppler secrets get FLAGSMITH_MANAGEMENT_API_KEY -p soleur -c cli_ops --plain 2>/dev/null || true)
[[ -z "$TOKEN" ]] && { echo "FLAGSMITH_MANAGEMENT_API_KEY not in Doppler soleur/cli_ops" >&2; exit 2; }

fs_api() { curl --disable --noproxy '*' -sS -H "Authorization: Api-Key $TOKEN" -H "Content-Type: application/json" "$@"; }

# Pre-check: not already a feature in Flagsmith.
EXISTING=$(fs_api "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/features/?q=${NAME}" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(','.join(f['name'] for f in d.get('results', []) if f['name'] == '$NAME'))")
if [[ -n "$EXISTING" ]]; then
  echo "feature '$NAME' already exists in Flagsmith — use flag-set-role to toggle" >&2; exit 1
fi

PRD_DOPPLER_VAL=$([[ $PRD_ON -eq 1 ]] && echo 1 || echo 0)

# --- propose ---------------------------------------------------------------
echo "→ Proposed mutations:"
echo "  1. Flagsmith: create feature '$NAME' (default_enabled=false)"
[[ $DEV_ON -eq 1 ]] && echo "     + segment override role-dev=ON in BOTH envs"
[[ $PRD_ON -eq 1 ]] && echo "     + segment override role-prd=ON in BOTH envs"
if [[ $FLAGSMITH_ONLY -eq 1 ]]; then
  echo "  (--flagsmith-only: skipping server.ts / $ENV_EXAMPLE / Doppler — flag is already code-wired)"
else
  echo "  2. $SERVER_TS: add \"$NAME\": \"$ENV_VAR\" to RUNTIME_FLAGS"
  echo "  3. $ENV_EXAMPLE: add $ENV_VAR=$PRD_DOPPLER_VAL"
  echo "  4. Doppler: $ENV_VAR=$PRD_DOPPLER_VAL in soleur/dev AND soleur/prd"
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo "(dry-run — exiting 0)"
  exit 0
fi

soleur_op_ack_or_die "Create flag '${NAME}' in Flagsmith and wire it into the code and Doppler (dev + prd) now? Type yes: "

# --- audit append (WORM) ---------------------------------------------------
ACTOR=$(doppler secrets get OPERATOR_EMAIL -p soleur -c cli_ops --plain 2>/dev/null | tr '[:upper:]' '[:lower:]')
[[ -z "$ACTOR" ]] && { echo "FATAL: OPERATOR_EMAIL not in Doppler soleur/cli_ops" >&2; exit 4; }

# `|| true` normalizes a Doppler auth/network failure to the exit-4 contract (the
# [[ -z ]] guard) instead of letting `set -e` abort at the assignment with exit 1.
AUDIT_URL=$(doppler secrets get SUPABASE_URL -p soleur -c dev --plain 2>/dev/null) || true
AUDIT_SRK=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c dev --plain 2>/dev/null) || true
[[ -z "$AUDIT_URL" || -z "$AUDIT_SRK" ]] && { echo "FATAL: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not in Doppler soleur/dev" >&2; exit 4; }

AUDIT_ID=$(audit_flag_flip_rpc "$AUDIT_URL" "$AUDIT_SRK" "$NAME" "dev" "global" "create" null null "$ACTOR") || exit 4
echo "  audit_id=$AUDIT_ID"

# --- create feature --------------------------------------------------------
echo "→ Creating Flagsmith feature '$NAME'…"
RESP=$(fs_api -X POST "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/features/" \
  -d "$(python3 -c "
import json, sys
print(json.dumps({
    'name': '$NAME',
    'description': '''$DESCRIPTION''' or None,
    'default_enabled': False,
    'project': $FLAGSMITH_PROJECT_ID,
}))
")")
FEATURE_ID=$(echo "$RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id",""))')
[[ -z "$FEATURE_ID" ]] && { echo "Flagsmith feature create failed: $RESP" >&2; exit 3; }
echo "  feature_id=$FEATURE_ID"

# --- segment overrides (if requested) --------------------------------------
apply_override() {
  local env_id="$1" segment_id="$2"
  local body
  body=$(printf '{"feature_states_to_create":[{"feature_segment":{"segment":%d},"enabled":true,"feature_state_value":{"type":"unicode","string_value":null,"integer_value":null,"boolean_value":null}}],"feature_states_to_update":[],"segment_ids_to_delete_overrides":[],"publish_immediately":true}' "$segment_id")
  fs_api -X POST "${FLAGSMITH_API}/environments/${env_id}/features/${FEATURE_ID}/versions/" -d "$body" >/dev/null
}

resolve_segment() {
  fs_api "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/segments/" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); [print(s['id']) for s in d.get('results', []) if s['name']=='$1']"
}

if [[ $DEV_ON -eq 1 ]]; then
  SEG=$(resolve_segment "role-dev")
  echo "→ Applying role-dev=ON in dev env…"; apply_override "$FLAGSMITH_ENV_DEV_ID" "$SEG"
  echo "→ Applying role-dev=ON in prd env…"; apply_override "$FLAGSMITH_ENV_PRD_ID" "$SEG"
fi
if [[ $PRD_ON -eq 1 ]]; then
  SEG=$(resolve_segment "role-prd")
  echo "→ Applying role-prd=ON in dev env…"; apply_override "$FLAGSMITH_ENV_DEV_ID" "$SEG"
  echo "→ Applying role-prd=ON in prd env…"; apply_override "$FLAGSMITH_ENV_PRD_ID" "$SEG"
fi

# --- code-wiring + Doppler mirror (skipped under --flagsmith-only) ----------
if [[ $FLAGSMITH_ONLY -eq 1 ]]; then
  echo
  echo "✓ Done (--flagsmith-only). Flagsmith feature '$NAME' created; server.ts /"
  echo "  $ENV_EXAMPLE / Doppler left untouched (flag is already code-wired)."
  echo "  Next: scope it per-org with soleur:flag-set-role $NAME prd on --org <orgId>."
  exit 0
fi

# --- edit server.ts ---------------------------------------------------------
echo "→ Editing $SERVER_TS…"
python3 <<PY || exit 4
import re, sys
p = "$SERVER_TS"
with open(p) as f: src = f.read()
new_line = '  "$NAME": "$ENV_VAR",\n'
m = re.search(r'(const RUNTIME_FLAGS = \{)([^}]*)(\}[ \t]*as const;)', src, re.DOTALL)
if not m:
    print('RUNTIME_FLAGS block not found in', p, file=sys.stderr); sys.exit(1)
body = m.group(2).rstrip()
if not body.endswith(','): body += ','
body += '\n' + new_line
src = src[:m.start(2)] + body + src[m.end(2):]
with open(p, 'w') as f: f.write(src)
print('  added entry to RUNTIME_FLAGS')
PY

# --- edit .env.example -----------------------------------------------------
echo "→ Editing $ENV_EXAMPLE…"
python3 <<PY || exit 4
p = "$ENV_EXAMPLE"
with open(p) as f: lines = f.readlines()
# Insert after the existing FLAG_KB_CHAT_SIDEBAR line.
out = []
inserted = False
for line in lines:
    out.append(line)
    if not inserted and line.startswith('FLAG_KB_CHAT_SIDEBAR='):
        out.append('$ENV_VAR=$PRD_DOPPLER_VAL\n')
        inserted = True
if not inserted:
    out.append('$ENV_VAR=$PRD_DOPPLER_VAL\n')
with open(p, 'w') as f: f.writelines(out)
print('  added $ENV_VAR=$PRD_DOPPLER_VAL')
PY

# --- mirror Doppler --------------------------------------------------------
echo "→ Doppler dev: $ENV_VAR=$PRD_DOPPLER_VAL…"
printf '%s' "$PRD_DOPPLER_VAL" | doppler secrets set "$ENV_VAR" -p soleur -c dev --silent || exit 5
echo "→ Doppler prd: $ENV_VAR=$PRD_DOPPLER_VAL…"
printf '%s' "$PRD_DOPPLER_VAL" | doppler secrets set "$ENV_VAR" -p soleur -c prd --silent || exit 5

echo
echo "✓ Done. Next: review the diff in $SERVER_TS + $ENV_EXAMPLE, then commit:"
echo "    git add $SERVER_TS $ENV_EXAMPLE && git commit -m 'feat(flags): add $NAME runtime flag'"
exit 0
