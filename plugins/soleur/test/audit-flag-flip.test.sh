#!/usr/bin/env bash
# Tests for the shared WORM audit-append helper (plugins/soleur/scripts/audit-flag-flip.sh)
# and the psql->PostgREST RPC conversion of the three flag-audit scripts (#4581 PR-1).
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
HELPER="$REPO_ROOT/plugins/soleur/scripts/audit-flag-flip.sh"
CREATE="$REPO_ROOT/plugins/soleur/skills/flag-create/scripts/create.sh"
FLIP="$REPO_ROOT/plugins/soleur/skills/flag-set-role/scripts/flip.sh"
SETROLE="$REPO_ROOT/plugins/soleur/skills/user-set-role/scripts/set-role.sh"
fail=0

# --- 1. Helper exists and defines the function -----------------------------
if [[ ! -f "$HELPER" ]]; then
  echo "audit-flag-flip: FAIL — helper missing at $HELPER" >&2; exit 1
fi
grep -Fq 'audit_flag_flip_rpc()' "$HELPER" || { echo "audit-flag-flip: FAIL — audit_flag_flip_rpc() not defined" >&2; fail=1; }

# --- 2. Helper uses --argjson for the bool/null args (not --arg) ------------
# before/after map to bool columns; --arg would send JSON strings -> PostgREST 400.
grep -Eq -- '--argjson[[:space:]]+(b|af|before|after)\b' "$HELPER" \
  || { echo "audit-flag-flip: FAIL — helper must use --argjson for bool/null args" >&2; fail=1; }

# --- 3. Helper routes through the RPC with service_role headers -------------
grep -Fq '/rest/v1/rpc/audit_flag_flip' "$HELPER" || { echo "audit-flag-flip: FAIL — RPC path missing" >&2; fail=1; }
grep -Fq 'apikey:' "$HELPER" || { echo "audit-flag-flip: FAIL — apikey header missing" >&2; fail=1; }
grep -Fq 'Authorization: Bearer' "$HELPER" || { echo "audit-flag-flip: FAIL — Bearer header missing" >&2; fail=1; }

# --- 4. Behavioral: stub curl on PATH, assert return-code contract ----------
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
# Emits $FAKE_BODY then a newline then $FAKE_CODE (mirrors curl -w '\n%{http_code}').
printf '%s\n%s' "${FAKE_BODY:-}" "${FAKE_CODE:-200}"
STUB
chmod +x "$STUB_DIR/curl"

run_helper() { # $1=body $2=code  -> echoes id, returns helper's rc
  FAKE_BODY="$1" FAKE_CODE="$2" PATH="$STUB_DIR:$PATH" bash -c '
    set -euo pipefail
    source "'"$HELPER"'"
    audit_flag_flip_rpc "https://x.supabase.co" "srk" "f" "dev" "global" "create" null null "a@b.co"
  '
}

# 4a. 2xx + scalar uuid -> rc 0, echoes the id
if id=$(run_helper '"11111111-1111-1111-1111-111111111111"' 200); then
  [[ "$id" == *11111111* ]] || { echo "audit-flag-flip: FAIL — id not echoed (got: $id)" >&2; fail=1; }
else
  echo "audit-flag-flip: FAIL — 2xx+uuid should return 0" >&2; fail=1
fi

# 4b. non-2xx -> rc 4
if run_helper '{"message":"denied"}' 403 >/dev/null 2>&1; then
  echo "audit-flag-flip: FAIL — non-2xx must return 4" >&2; fail=1
else
  rc=$?; [[ "$rc" == "4" ]] || { echo "audit-flag-flip: FAIL — non-2xx rc=$rc (expected 4)" >&2; fail=1; }
fi

# 4c. 2xx but null/empty id -> rc 4
if run_helper 'null' 200 >/dev/null 2>&1; then
  echo "audit-flag-flip: FAIL — missing id must return 4" >&2; fail=1
else
  rc=$?; [[ "$rc" == "4" ]] || { echo "audit-flag-flip: FAIL — missing-id rc=$rc (expected 4)" >&2; fail=1; }
fi

# --- 5. Forbidden-token guard: no psql/DATABASE_URL_POOLER/5432/6543 --------
# Strip comments (everything from the first '#') before grepping so doc-mentions
# don't false-positive; stripping can only mask a token, never invent one — and a
# real forbidden token in the audit path is never followed by '#' on its line.
for s in "$CREATE" "$FLIP" "$SETROLE"; do
  if sed 's/#.*//' "$s" | grep -nE '\bpsql\b|DATABASE_URL_POOLER|\b5432\b|\b6543\b'; then
    echo "audit-flag-flip: FAIL — forbidden psql/DB-pooler token remains in $(basename "$s")" >&2; fail=1
  fi
done

# --- 6. Each script sources the shared helper ------------------------------
for s in "$CREATE" "$FLIP" "$SETROLE"; do
  grep -Fq 'audit-flag-flip.sh' "$s" || { echo "audit-flag-flip: FAIL — $(basename "$s") does not source the helper" >&2; fail=1; }
done

[ "$fail" -eq 0 ] || exit 1
echo "audit-flag-flip: ok"
