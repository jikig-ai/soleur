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
# if/then/else helpers (not `A && B || C`, which runs C when B fails — SC2015).
check_has()    { if has_code "$1"; then ok "$2"; else bad "$3"; fi; }
check_absent() { if absent_code "$1"; then ok "$2"; else bad "$3"; fi; }

echo "inngest-rls.test.sh — static shape guards for $(basename "$SQL")"

# --- Required constructs (idempotent lockdown) -------------------------------
check_has 'ENABLE[[:space:]]+ROW[[:space:]]+LEVEL[[:space:]]+SECURITY' \
  "enables RLS" "missing ENABLE ROW LEVEL SECURITY"

check_has 'DO[[:space:]]+\$\$' \
  "uses a DO-block loop (dynamic over current tables — no hard-coded 14)" \
  "missing DO \$\$ loop"

check_has 'REVOKE[[:space:]]+ALL[[:space:]]+ON[[:space:]]+public' \
  "revokes table grants" "missing per-table REVOKE"

check_has 'REVOKE[[:space:]]+ALL[[:space:]]+ON[[:space:]]+SEQUENCE' \
  "revokes sequence grants" "missing sequence REVOKE"

# Matviews have no RLS — a grant is their only access control; the lockdown must revoke them.
check_has 'pg_matviews' \
  "revokes matview grants (relkind 'm' completeness)" "missing matview REVOKE loop"

# Default-privilege revoke for grantor postgres on TABLES + SEQUENCES + FUNCTIONS
# (the durable recurrence fix). All three classes must be present.
check_has 'ALTER[[:space:]]+DEFAULT[[:space:]]+PRIVILEGES[[:space:]]+FOR[[:space:]]+ROLE[[:space:]]+postgres' \
  "ALTER DEFAULT PRIVILEGES FOR ROLE postgres present" \
  "missing ALTER DEFAULT PRIVILEGES FOR ROLE postgres"
for cls in TABLES SEQUENCES FUNCTIONS; do
  check_has "REVOKE[[:space:]]+ALL[[:space:]]+ON[[:space:]]+${cls}[[:space:]]+FROM" \
    "default-priv revoke covers ${cls}" \
    "default-priv revoke missing class ${cls}"
done

# Lock-acquisition + statement guards (data-integrity HIGH).
check_has 'SET[[:space:]]+lock_timeout' \
  "SET lock_timeout present (fail-fast on contention)" \
  "missing SET lock_timeout"
check_has 'SET[[:space:]]+statement_timeout' \
  "SET statement_timeout present" "missing SET statement_timeout"

# Fail-closed identity preflight: must reference the Inngest sentinel tables AND
# RAISE EXCEPTION (refuse to run against a non-Inngest project).
if has_code 'to_regclass' \
   && has_code 'goose_db_version' \
   && has_code 'function_runs' \
   && has_code 'RAISE[[:space:]]+EXCEPTION'; then
  ok "fail-closed Inngest-sentinel identity preflight present"
else
  bad "missing identity preflight (to_regclass sentinel + RAISE EXCEPTION)"
fi

# --- Forbidden constructs (would break Inngest or re-expose) ------------------
check_absent 'FORCE[[:space:]]+ROW[[:space:]]+LEVEL[[:space:]]+SECURITY' \
  "no FORCE ROW LEVEL SECURITY (owner bypass preserved)" \
  "FORBIDDEN: FORCE ROW LEVEL SECURITY present — would lock Inngest out"

check_absent 'CREATE[[:space:]]+POLICY' \
  "no CREATE POLICY (tables stay client-unreachable)" \
  "FORBIDDEN: CREATE POLICY present — re-opens client access"

# No re-GRANT in the applied code (break-glass re-GRANT lives only in a comment).
check_absent '(^|[^A-Za-z])GRANT[[:space:]]' \
  "no GRANT statement in applied code" \
  "FORBIDDEN: GRANT present in applied SQL"

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
if [[ "$bad_revoke" -eq 0 ]]; then
  ok "no REVOKE targets postgres/service_role"
else
  bad "FORBIDDEN: a REVOKE targets postgres or service_role"
fi

echo "---"
echo "passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]] || exit 1
