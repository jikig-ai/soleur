#!/usr/bin/env bash
# Delete a runtime feature flag end-to-end — the exact inverse of flag-create.
# Removes the flag from ALL FIVE sites:
#   1. Flagsmith feature (DELETE → 204; DB cascade removes all segment/identity overrides)
#   2. server.ts RUNTIME_FLAGS entry
#   3. .env.example FLAG_<X>= line
#   4. flag-set-role/scripts/flip.sh FLAG_ENV_VARS map entry (the 5th site the
#      issue's 4-site framing misses — a stale entry lets flag-set-role try to
#      flip a deleted flag)
#   5. Doppler secret in soleur/dev AND soleur/prd
#
# Contract: SKILL.md in the parent directory. Inverse of flag-create/scripts/create.sh.
#
# Usage: bash delete.sh <kebab-name> [--dry-run]
#
# Exit codes (same map as create.sh):
#   0 — success / dry-run / operator aborted at the typed-yes prompt
#   1 — name validation failure
#   2 — prerequisite missing
#   3 — Flagsmith API error
#   4 — file edit / audit append failed
#   5 — Doppler delete failed
#
# Per-exit-code recovery state (a destructive op's audit trail must distinguish
# full from partial delete — see SKILL.md "Recovery from a partial delete").
# The stderr message disambiguates the two exit-4 sub-cases:
#   exit 3 → nothing mutated (Flagsmith DELETE was the first mutation; a non-204
#            means no code/Doppler change happened). Re-run is safe.
#   exit 4 (audit message "FATAL: audit RPC …") → pre-mutation: the WORM append
#            failed BEFORE the Flagsmith DELETE, so nothing was mutated. Re-run safe.
#   exit 4 (server.ts/.env.example/flip.sh edit message) → Flagsmith feature is
#            GONE but a code-file edit failed. Half-deleted: finish the remaining
#            edits + Doppler deletes by hand (or re-run — the code-cleanup steps
#            are idempotent: each is a no-op if already removed).
#   exit 5 → Flagsmith + all code files done; a Doppler delete failed. Re-run
#            (idempotent) or remove FLAG_<X> from Doppler dev/prd by hand.
#
# Audit action: 'archive' (migration 071's WORM check constraint allows
# on/off/create/archive — 'archive' is the sanctioned flag-removed action; no
# schema change needed). before=current default_enabled, after=null.

set -euo pipefail

# Shared WORM audit-append helper (PostgREST RPC). See #4581 PR-1.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../scripts/audit-flag-flip.sh"

readonly FLAGSMITH_PROJECT_ID=39082
readonly FLAGSMITH_API="https://api.flagsmith.com/api/v1"
readonly SERVER_TS="apps/web-platform/lib/feature-flags/server.ts"
readonly ENV_EXAMPLE="apps/web-platform/.env.example"
readonly FLIP_SH="plugins/soleur/skills/flag-set-role/scripts/flip.sh"

DRY_RUN=0
NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --*)       echo "unknown flag: $1" >&2; exit 1 ;;
    *)         NAME="$1"; shift ;;
  esac
done

# --- name validation FIRST, before ANY interpolation (security P0-2) --------
# $NAME is later interpolated into python3 source, the ?q= URL, and grep/sed
# patterns; an unvalidated name with a quote/newline/regex metachar is an
# injection vector. This is the first executable line after arg parse.
[[ -z "$NAME" ]] && { echo "Usage: delete.sh <kebab-name> [--dry-run]" >&2; exit 1; }
[[ ! "$NAME" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] && { echo "name must be lowercase kebab-case (got: $NAME)" >&2; exit 1; }

ENV_VAR="FLAG_$(echo "$NAME" | tr 'a-z-' 'A-Z_')"

# --- prerequisites ----------------------------------------------------------
command -v curl >/dev/null    || { echo "missing: curl" >&2; exit 2; }
command -v python3 >/dev/null || { echo "missing: python3" >&2; exit 2; }
command -v doppler >/dev/null || { echo "missing: doppler" >&2; exit 2; }
[[ -f "$SERVER_TS" ]]   || { echo "missing $SERVER_TS (run from repo root / worktree)" >&2; exit 2; }
[[ -f "$ENV_EXAMPLE" ]] || { echo "missing $ENV_EXAMPLE" >&2; exit 2; }
[[ -f "$FLIP_SH" ]]     || { echo "missing $FLIP_SH" >&2; exit 2; }

# --- validate the flag EXISTS (inverse of create's "already registered") ----
if ! grep -qE "\"${NAME}\"" "$SERVER_TS"; then
  echo "'$NAME' is not in $SERVER_TS RUNTIME_FLAGS — nothing to delete (use flag-list to see active flags)" >&2
  exit 1
fi

TOKEN=$(doppler secrets get FLAGSMITH_MANAGEMENT_API_KEY -p soleur -c cli_ops --plain 2>/dev/null || true)
[[ -z "$TOKEN" ]] && { echo "FLAGSMITH_MANAGEMENT_API_KEY not in Doppler soleur/cli_ops" >&2; exit 2; }

fs_api() { curl -sS -H "Authorization: Api-Key $TOKEN" -H "Content-Type: application/json" "$@"; }

# --- resolve Flagsmith feature_id via EXACT-name filter (security P2-2) ------
# ?q= is substring (name__icontains) — a bare pick could DELETE the wrong
# feature, so filter to f['name'] == NAME exactly (create.sh:68-69 shape).
RESOLVED=$(fs_api "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/features/?q=${NAME}&page_size=100" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
for f in d.get('results', []):
    if f['name'] == '$NAME':
        print(f\"{f['id']}\t{str(bool(f.get('default_enabled'))).lower()}\"); sys.exit(0)
" 2>/dev/null || true)
FEATURE_ID="${RESOLVED%%$'\t'*}"
DEFAULT_ENABLED="${RESOLVED##*$'\t'}"
[[ "$RESOLVED" != *$'\t'* ]] && { FEATURE_ID=""; DEFAULT_ENABLED=""; }

# --- propose ----------------------------------------------------------------
echo "→ Proposed deletion of flag '$NAME' (5 sites):"
if [[ -n "$FEATURE_ID" ]]; then
  echo "  1. Flagsmith: DELETE feature '$NAME' (id=$FEATURE_ID; cascade removes all segment/identity overrides)"
else
  echo "  1. Flagsmith: feature '$NAME' NOT FOUND — skipping (code-side cleanup continues; drift recovery)"
fi
echo "  2. $SERVER_TS: remove \"$NAME\": \"$ENV_VAR\" from RUNTIME_FLAGS"
echo "  3. $ENV_EXAMPLE: remove $ENV_VAR= line"
echo "  4. $FLIP_SH: remove [\"$NAME\"]=\"$ENV_VAR\" from FLAG_ENV_VARS map"
echo "  5. Doppler: delete $ENV_VAR in soleur/dev AND soleur/prd"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "(dry-run — exiting 0 before any mutation)"
  exit 0
fi

read -r -p "Proceed? Type 'yes': " ACK
[[ "$ACK" == "yes" ]] || { echo "aborted" >&2; exit 0; }

# --- audit append (WORM) BEFORE any mutation --------------------------------
# Records intent: action=archive (migration 071's sanctioned flag-removed
# action), target=global, before=current enablement, after=null. Abort (exit 4)
# on audit failure — destructive ops must be audited.
ACTOR=$(doppler secrets get OPERATOR_EMAIL -p soleur -c cli_ops --plain 2>/dev/null | tr '[:upper:]' '[:lower:]')
[[ -z "$ACTOR" ]] && { echo "FATAL: OPERATOR_EMAIL not in Doppler soleur/cli_ops" >&2; exit 4; }
AUDIT_URL=$(doppler secrets get SUPABASE_URL -p soleur -c dev --plain 2>/dev/null) || true
AUDIT_SRK=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c dev --plain 2>/dev/null) || true
[[ -z "$AUDIT_URL" || -z "$AUDIT_SRK" ]] && { echo "FATAL: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not in Doppler soleur/dev" >&2; exit 4; }
BEFORE_BOOL=$([[ "$DEFAULT_ENABLED" == "true" || "$DEFAULT_ENABLED" == "false" ]] && echo "$DEFAULT_ENABLED" || echo null)
AUDIT_ID=$(audit_flag_flip_rpc "$AUDIT_URL" "$AUDIT_SRK" "$NAME" "dev" "global" "archive" "$BEFORE_BOOL" null "$ACTOR") || exit 4
echo "  audit_id=$AUDIT_ID"

# --- 1. DELETE Flagsmith feature (first mutation) ---------------------------
if [[ -n "$FEATURE_ID" ]]; then
  echo "→ Deleting Flagsmith feature '$NAME' (id=$FEATURE_ID)…"
  CODE=$(fs_api -o /dev/null -w '%{http_code}' -X DELETE "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/features/${FEATURE_ID}/")
  [[ "$CODE" == "204" ]] || { echo "Flagsmith DELETE returned HTTP $CODE (expected 204)" >&2; exit 3; }
  echo "  deleted (HTTP 204; cascade removed all overrides)"
else
  echo "→ Flagsmith: feature absent, skipping (code-side cleanup continues)"
fi

# --- 2. strip server.ts RUNTIME_FLAGS entry --------------------------------
echo "→ Editing $SERVER_TS…"
NAME="$NAME" python3 <<'PY' || exit 4
import os, re, sys
p = "apps/web-platform/lib/feature-flags/server.ts"
name = os.environ["NAME"]
with open(p) as f: src = f.read()
m = re.search(r'(const RUNTIME_FLAGS = \{)(.*?)(\}[ \t]*as const;)', src, re.DOTALL)
if not m:
    print('RUNTIME_FLAGS block not found in', p, file=sys.stderr); sys.exit(1)
body = m.group(2)
# Remove the "<name>": "FLAG_<X>", line (with surrounding indentation/newline).
new_body, n = re.subn(r'\n[ \t]*"' + re.escape(name) + r'"\s*:\s*"[A-Z0-9_]+"\s*,?', '', body)
if n == 0:
    print(f'no RUNTIME_FLAGS entry for "{name}" found', file=sys.stderr); sys.exit(1)
src = src[:m.start(2)] + new_body + src[m.end(2):]
with open(p, 'w') as f: f.write(src)
print(f'  removed {n} RUNTIME_FLAGS entr{"y" if n==1 else "ies"} for "{name}"')
PY

# --- 3. remove .env.example FLAG_<X>= line ---------------------------------
echo "→ Editing $ENV_EXAMPLE…"
ENV_VAR="$ENV_VAR" python3 <<'PY' || exit 4
import os, sys
p = "apps/web-platform/.env.example"
ev = os.environ["ENV_VAR"]
with open(p) as f: lines = f.readlines()
out = [l for l in lines if not l.startswith(ev + "=")]
if len(out) == len(lines):
    print(f'  (no {ev}= line in {p} — already absent)')
else:
    with open(p, 'w') as f: f.writelines(out)
    print(f'  removed {ev}= line')
PY

# --- 4. remove flip.sh FLAG_ENV_VARS map entry (the 5th site) ---------------
echo "→ Editing $FLIP_SH FLAG_ENV_VARS map…"
NAME="$NAME" python3 <<'PY' || exit 4
import os, re, sys
p = "plugins/soleur/skills/flag-set-role/scripts/flip.sh"
name = os.environ["NAME"]
with open(p) as f: lines = f.readlines()
pat = re.compile(r'^\s*\["' + re.escape(name) + r'"\]="[A-Z0-9_]+"\s*$')
out = [l for l in lines if not pat.match(l.rstrip('\n'))]
if len(out) == len(lines):
    print(f'  (no FLAG_ENV_VARS entry for "{name}" — already absent)')
else:
    with open(p, 'w') as f: f.writelines(out)
    print(f'  removed FLAG_ENV_VARS["{name}"] entry')
PY

# --- 5. delete Doppler secrets (dev + prd) ----------------------------------
# `> /dev/null` is MANDATORY on each delete line: the Doppler delete command
# prints the full remaining config to stdout (2026-05-26 learning). Never
# echo/tee the delete output.
echo "→ Doppler dev: delete $ENV_VAR…"
doppler secrets delete "$ENV_VAR" -p soleur -c dev --yes > /dev/null || exit 5
echo "→ Doppler prd: delete $ENV_VAR…"
doppler secrets delete "$ENV_VAR" -p soleur -c prd --yes > /dev/null || exit 5

# Verify deletion. The missing-key message is "Could not find requested secret"
# (NOT "not found") with a non-zero exit — verified live 2026-06-15. `2>&1 | grep
# -q` is safe (-q discards output; no config dump risk on the read path).
for cfg in dev prd; do
  if doppler secrets get "$ENV_VAR" -p soleur -c "$cfg" --plain >/dev/null 2>&1; then
    echo "  ⚠ $ENV_VAR still present in soleur/$cfg after delete — investigate" >&2
  else
    echo "  ✓ $ENV_VAR gone from soleur/$cfg"
  fi
done

# --- outcome signal (P1-1) --------------------------------------------------
# The pre-mutation WORM row recorded intent (action=archive). Reaching this line
# means all 5 sites succeeded — a clean exit 0 IS the full-delete signal, and the
# per-exit-code recovery doc (header + SKILL.md) distinguishes any partial outcome
# (non-zero exit). The WORM action enum (071) has no "complete" value, so a second
# row would duplicate the archive action without adding signal; the exit code is
# the authoritative full-vs-partial discriminator.

echo
echo "✓ Done. '$NAME' removed from all 5 sites. Review + commit:"
echo "    git add $SERVER_TS $ENV_EXAMPLE $FLIP_SH && git commit -m 'feat(flags): delete $NAME runtime flag'"
exit 0
