#!/usr/bin/env bash
# Static-shape guards for the soleur-inngest-prd RLS-lockdown migration.
# Mirrors the sibling apps/web-platform/infra/inngest-*.test.sh style. No DB
# connection — these assert the SQL artifact's SHAPE so a future edit cannot
# silently introduce a break-Inngest or re-expose change.
#
# IMPORTANT: every assertion runs against the migration with `--` line-comments
# STRIPPED ($SQL_CODE), because the break-glass comment legitimately names
# `postgres`, `service_role`, `DISABLE ROW LEVEL SECURITY`, and re-`GRANT` — a
# raw grep would false-match that prose (grep-over-script-body false-match class).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL="$DIR/0001_enable_rls_lockdown.sql"

pass=0; fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

# RED gate: the artifact must exist.
if [[ ! -f "$SQL" ]]; then
  echo "FAIL: migration not found at $SQL"
  exit 1
fi

# Code = the migration with line-comments removed (everything after `--`).
SQL_CODE="$(sed -E 's/--.*$//' "$SQL")"

has_code()    { printf '%s' "$SQL_CODE" | grep -iqE "$1"; }
absent_code() { ! printf '%s' "$SQL_CODE" | grep -iqE "$1"; }

echo "inngest-rls.test.sh — static shape guards for $(basename "$SQL")"

# --- Required constructs (idempotent lockdown) -------------------------------
has_code 'ENABLE[[:space:]]+ROW[[:space:]]+LEVEL[[:space:]]+SECURITY' \
  && ok "enables RLS" || bad "missing ENABLE ROW LEVEL SECURITY"

has_code 'DO[[:space:]]+\$\$' \
  && ok "uses a DO-block loop (dynamic over current tables — no hard-coded 14)" \
  || bad "missing DO \$\$ loop"

has_code 'REVOKE[[:space:]]+ALL[[:space:]]+ON[[:space:]]+public' \
  && ok "revokes table grants" || bad "missing per-table REVOKE"

has_code 'REVOKE[[:space:]]+ALL[[:space:]]+ON[[:space:]]+SEQUENCE' \
  && ok "revokes sequence grants" || bad "missing sequence REVOKE"

# Default-privilege revoke for grantor postgres on TABLES + SEQUENCES + FUNCTIONS
# (the durable recurrence fix). All three classes must be present.
has_code 'ALTER[[:space:]]+DEFAULT[[:space:]]+PRIVILEGES[[:space:]]+FOR[[:space:]]+ROLE[[:space:]]+postgres' \
  && ok "ALTER DEFAULT PRIVILEGES FOR ROLE postgres present" \
  || bad "missing ALTER DEFAULT PRIVILEGES FOR ROLE postgres"
for cls in TABLES SEQUENCES FUNCTIONS; do
  has_code "REVOKE[[:space:]]+ALL[[:space:]]+ON[[:space:]]+$cls[[:space:]]+FROM" \
    && ok "default-priv revoke covers $cls" \
    || bad "default-priv revoke missing class $cls"
done

# Lock-acquisition + statement guards (data-integrity HIGH).
has_code 'SET[[:space:]]+lock_timeout' \
  && ok "SET lock_timeout present (fail-fast on contention)" \
  || bad "missing SET lock_timeout"
has_code 'SET[[:space:]]+statement_timeout' \
  && ok "SET statement_timeout present" || bad "missing SET statement_timeout"

# Fail-closed identity preflight: must reference the Inngest sentinel tables AND
# RAISE EXCEPTION (refuse to run against a non-Inngest project).
{ has_code 'to_regclass' \
    && has_code 'goose_db_version' \
    && has_code 'function_runs' \
    && has_code 'RAISE[[:space:]]+EXCEPTION'; } \
  && ok "fail-closed Inngest-sentinel identity preflight present" \
  || bad "missing identity preflight (to_regclass sentinel + RAISE EXCEPTION)"

# --- Forbidden constructs (would break Inngest or re-expose) ------------------
absent_code 'FORCE[[:space:]]+ROW[[:space:]]+LEVEL[[:space:]]+SECURITY' \
  && ok "no FORCE ROW LEVEL SECURITY (owner bypass preserved)" \
  || bad "FORBIDDEN: FORCE ROW LEVEL SECURITY present — would lock Inngest out"

absent_code 'CREATE[[:space:]]+POLICY' \
  && ok "no CREATE POLICY (tables stay client-unreachable)" \
  || bad "FORBIDDEN: CREATE POLICY present — re-opens client access"

# No re-GRANT in the applied code (break-glass re-GRANT lives only in a comment).
absent_code '(^|[^A-Za-z])GRANT[[:space:]]' \
  && ok "no GRANT statement in applied code" \
  || bad "FORBIDDEN: GRANT present in applied SQL"

# Never revoke from postgres / service_role. Inspect every REVOKE statement's
# role list (comments already stripped); the targets must be only anon/authenticated.
bad_revoke=0
while IFS= read -r line; do
  [[ "$line" =~ [Rr][Ee][Vv][Oo][Kk][Ee] ]] || continue
  if printf '%s' "$line" | grep -iqE '\b(postgres|service_role)\b'; then
    bad_revoke=1
    printf '       offending REVOKE: %s\n' "$(printf '%s' "$line" | tr -s ' ')"
  fi
done < <(printf '%s' "$SQL_CODE" | tr ';' '\n')
[[ "$bad_revoke" -eq 0 ]] \
  && ok "no REVOKE targets postgres/service_role" \
  || bad "FORBIDDEN: a REVOKE targets postgres or service_role"

echo "---"
echo "passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]] || exit 1
