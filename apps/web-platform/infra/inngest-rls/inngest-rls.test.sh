#!/usr/bin/env bash
# Static-shape guards for the Inngest RLS-lockdown SQL artifacts.
# Mirrors the sibling apps/web-platform/infra/inngest-*.test.sh style. No DB
# connection — these assert each SQL artifact's SHAPE so a future edit cannot
# silently introduce a break-Inngest or re-expose change.
#
# PER-ARTIFACT PROFILES — READ THIS BEFORE ADDING AN ASSERTION.
# There are two artifacts with DELIBERATELY INVERTED required shapes. They MUST
# NOT share one assertion set:
#
#   0001_enable_rls_lockdown.sql       -> soleur-inngest-prd (pigsfuxruiopinouvjwy)
#     A DEDICATED, single-tenant Inngest project. Schema-wide revoke is correct
#     there, and `ALTER DEFAULT PRIVILEGES` is REQUIRED (it is the durable
#     recurrence fix for future Inngest-version tables).
#
#   0002_dev_inngest_tables_lockdown.sql -> soleur-dev (mlwiodleouzwniehynfz)
#     A CO-TENANTED project: the dark Inngest backend shares `public` with the
#     app's 52 tables. `ALTER DEFAULT PRIVILEGES` is FORBIDDEN here — it would
#     revoke the default grants that every FUTURE dev app migration relies on,
#     breaking the dev app. A schema-wide catalog loop is likewise FORBIDDEN:
#     it would revoke anon/authenticated across those 52 app tables.
#
# => If you "extend" this file by bolting 0002 onto 0001's assertions, 0002 will
#    fail the `ALTER DEFAULT PRIVILEGES` required-check, and the tempting "fix"
#    (adding that statement to 0002) is precisely the catastrophe these guards
#    exist to prevent. Add to the correct profile instead.
#
# IMPORTANT: assertions about APPLIED CODE run against the artifact with `--`
# line-comments STRIPPED ($CODE), because the break-glass comment legitimately
# names `postgres`, `service_role`, `DISABLE ROW LEVEL SECURITY`, and re-`GRANT`
# — a raw grep would false-match that prose (grep-over-script-body false-match
# class). The few assertions that deliberately assert a COMMENT exists read
# $RAW instead and say so at the call site.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_0001="$DIR/0001_enable_rls_lockdown.sql"
SQL_0002="$DIR/0002_dev_inngest_tables_lockdown.sql"

# The 14 dark-Inngest tables on soleur-dev. Re-derived from the live catalog
# 2026-07-15 (never from a migration grep — see the learning
# 2026-07-09-derive-db-object-sets-from-live-catalog-not-migration-grep.md).
ALLOW_14=(
  apps event_batches events function_finishes function_runs functions
  goose_db_version history migrations queue_snapshot_chunks spans
  trace_runs traces worker_connections
)

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

# --- profile state -----------------------------------------------------------
RAW=""; CODE=""; LABEL=""

load_profile() {
  LABEL="$(basename "$1")"
  if [[ ! -f "$1" ]]; then
    echo "FAIL: artifact not found at $1"
    exit 1
  fi
  RAW="$(cat "$1")"
  CODE="$(sed -E 's/--.*$//' "$1")"
}

has_code()    { printf '%s' "$CODE" | grep -iqE "$1"; }
absent_code() { ! printf '%s' "$CODE" | grep -iqE "$1"; }
has_raw()     { printf '%s' "$RAW"  | grep -iqE "$1"; }
# if/then/else helpers (not `A && B || C`, which runs C when B fails — SC2015).
check_has()     { if has_code "$1";    then ok "[$LABEL] $2"; else bad "[$LABEL] $3"; fi; }
check_absent()  { if absent_code "$1"; then ok "[$LABEL] $2"; else bad "[$LABEL] $3"; fi; }
check_raw_has() { if has_raw "$1";     then ok "[$LABEL] $2"; else bad "[$LABEL] $3"; fi; }

# Never revoke from postgres / service_role. Inspect every REVOKE statement's
# role list (comments already stripped); the targets must be only anon/authenticated.
check_no_privileged_revoke() {
  local bad_revoke=0 line
  while IFS= read -r line; do
    [[ "$line" =~ [Rr][Ee][Vv][Oo][Kk][Ee] ]] || continue
    if printf '%s' "$line" | grep -iqE '\b(postgres|service_role)\b'; then
      bad_revoke=1
      printf '       offending REVOKE: %s\n' "$(printf '%s' "$line" | tr -s ' ')"
    fi
  done < <(printf '%s' "$CODE" | tr ';' '\n')
  if [[ "$bad_revoke" -eq 0 ]]; then
    ok "[$LABEL] no REVOKE targets postgres/service_role"
  else
    bad "[$LABEL] FORBIDDEN: a REVOKE targets postgres or service_role"
  fi
}

# The invariant is "no schema-wide catalog loop DRIVES DDL" — NOT "pg_tables is
# never mentioned". A bare `grep -c 'FROM pg_tables'` is the wrong test twice
# over: an allowlist-filtered `FROM pg_tables WHERE tablename = ANY(allow)`
# would score 1 and fail correct code, while a `pg_class`-based schema-wide loop
# would score 0 and PASS the catastrophe. So: split into `;`-delimited statement
# fragments and flag any fragment that BOTH (a) scans the catalog for ORDINARY or
# PARTITIONED tables schema-wide and (b) contains an EXECUTE (i.e. emits DDL).
#
# Legitimately NOT flagged: 0002's non-allowlisted REPORT reads relkind='r'
# schema-wide but emits no DDL, and 0002's sequence loop emits DDL but scans
# relkind='S' scoped to one allowlisted table.
#
# ⚠️ awk RS=";" is load-bearing — do NOT "simplify" this to `tr ';' '\n'` piped
# into `read -r`. That reads LINES, not fragments: the catalog source and the
# EXECUTE sit on DIFFERENT lines, so the conjunction never matches and the guard
# silently passes the catastrophe. (Caught by mutation-testing this very check on
# 2026-07-15 — it was vacuous in exactly that way before this fix.)
# Input is lowercased so the patterns need no case-insensitivity extension
# (IGNORECASE is gawk-only; this must also work under mawk).
check_no_schemawide_ddl_loop() {
  local offenders
  offenders="$(printf '%s' "$CODE" | tr '[:upper:]' '[:lower:]' | awk '
    BEGIN { RS = ";" }
    /execute/ &&
    (/pg_tables/ || /pg_matviews/ ||
     /relkind[ \t]*=[ \t]*.r./ || /relkind[ \t]*=[ \t]*.p./ ||
     /relkind[ \t]*in[ \t]*\(/) {
      gsub(/[ \t\n]+/, " ")
      print "       offending schema-wide DDL fragment:" substr($0, 1, 150)
    }')"
  if [[ -z "$offenders" ]]; then
    ok "[$LABEL] no schema-wide catalog loop drives DDL (allowlist-driven only)"
  else
    printf '%s\n' "$offenders"
    bad "[$LABEL] FORBIDDEN: a schema-wide table-catalog scan emits DDL — would reach the app's 52 tables"
  fi
}

# =============================================================================
# PROFILE: 0001 — soleur-inngest-prd (DEDICATED project; schema-wide is correct)
# =============================================================================
profile_0001() {
  load_profile "$SQL_0001"
  echo
  echo "profile: $LABEL  (target: soleur-inngest-prd — dedicated, schema-wide revoke CORRECT)"

  # --- Required constructs (idempotent lockdown) -----------------------------
  check_has 'ENABLE[[:space:]]+ROW[[:space:]]+LEVEL[[:space:]]+SECURITY' \
    "enables RLS" "missing ENABLE ROW LEVEL SECURITY"

  check_has 'DO[[:space:]]+\$\$' \
    "uses a DO-block loop (dynamic over current tables — no hard-coded set)" \
    "missing DO \$\$ loop"

  check_has 'REVOKE[[:space:]]+ALL[[:space:]]+ON[[:space:]]+public' \
    "revokes table grants" "missing per-table REVOKE"

  check_has 'REVOKE[[:space:]]+ALL[[:space:]]+ON[[:space:]]+SEQUENCE' \
    "revokes sequence grants" "missing sequence REVOKE"

  # Matviews have no RLS — a grant is their only access control; the lockdown must revoke them.
  check_has 'pg_matviews' \
    "revokes matview grants (relkind 'm' completeness)" "missing matview REVOKE loop"

  # Default-privilege revoke for grantor postgres on TABLES + SEQUENCES + FUNCTIONS
  # (the durable recurrence fix). REQUIRED here — and FORBIDDEN in 0002. This is
  # the single most important inversion between the two profiles.
  check_has 'ALTER[[:space:]]+DEFAULT[[:space:]]+PRIVILEGES[[:space:]]+FOR[[:space:]]+ROLE[[:space:]]+postgres' \
    "ALTER DEFAULT PRIVILEGES FOR ROLE postgres present (required on a DEDICATED project)" \
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
    ok "[$LABEL] fail-closed Inngest-sentinel identity preflight present"
  else
    bad "[$LABEL] missing identity preflight (to_regclass sentinel + RAISE EXCEPTION)"
  fi

  # --- Negative guard: refuse to run against a CO-TENANTED project ------------
  # The Inngest-sentinel preflight above encodes "goose tables exist => Inngest-only
  # project". The dark backend on soleur-dev FALSIFIED that: soleur-dev satisfies it
  # too. This guard adds the missing half — abort if APP tables are present.
  for t in kb_files workspace_invitations byok_delegation_acceptances; do
    check_has "to_regclass\('public\.${t}'\)" \
      "negative guard names app-distinctive table ${t}" \
      "negative guard missing app-distinctive table ${t}"
  done

  # Inngest ships GENERIC nouns (apps, events, functions, history, migrations,
  # traces) and has no namespace discipline. A guard on `users`/`conversations`
  # would make 0001 RAISE on prd forever the day goose ships public.users —
  # killing the ADR-030 I8 self-heal. The guard MUST use app-distinctive names.
  check_absent "to_regclass\('public\.(users|conversations)'\)" \
    "negative guard avoids generic nouns (users/conversations) Inngest could create" \
    "FORBIDDEN: negative guard uses a generic noun — a future goose table would break the prd lockdown permanently"

  # Ordering: the guard is worthless if it runs AFTER the revoke loop. Assert the
  # byte-offset of the app-distinctive guard precedes the FIRST REVOKE.
  local guard_off revoke_off
  guard_off="$(printf '%s' "$CODE" | grep -abioE "to_regclass\('public\.kb_files'\)" | head -1 | cut -d: -f1)"
  revoke_off="$(printf '%s' "$CODE" | grep -abioE 'REVOKE[[:space:]]' | head -1 | cut -d: -f1)"
  if [[ -n "$guard_off" && -n "$revoke_off" && "$guard_off" -lt "$revoke_off" ]]; then
    ok "[$LABEL] negative guard (offset $guard_off) precedes the first REVOKE (offset $revoke_off)"
  else
    bad "[$LABEL] negative guard does NOT precede the first REVOKE (guard=${guard_off:-none} revoke=${revoke_off:-none}) — it would abort only AFTER revoking"
  fi

  # --- Forbidden constructs (would break Inngest or re-expose) ----------------
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

  check_no_privileged_revoke
}

# =============================================================================
# PROFILE: 0002 — soleur-dev (CO-TENANTED; table-scoped ONLY)
# =============================================================================
profile_0002() {
  load_profile "$SQL_0002"
  echo
  echo "profile: $LABEL  (target: soleur-dev — CO-TENANTED with 52 app tables; table-scoped ONLY)"

  # --- Required: the lockdown itself ----------------------------------------
  check_has 'ENABLE[[:space:]]+ROW[[:space:]]+LEVEL[[:space:]]+SECURITY' \
    "enables RLS" "missing ENABLE ROW LEVEL SECURITY"

  check_has 'REVOKE[[:space:]]+ALL[[:space:]]+ON[[:space:]]+public' \
    "revokes table grants" "missing per-table REVOKE"

  check_has 'REVOKE[[:space:]]+ALL[[:space:]]+ON[[:space:]]+SEQUENCE' \
    "revokes sequence grants" "missing sequence REVOKE"

  # --- Required: the target set is the explicit 14-name allowlist ------------
  local missing=() t
  for t in "${ALLOW_14[@]}"; do
    has_code "'${t}'" || missing+=("$t")
  done
  if [[ "${#missing[@]}" -eq 0 ]]; then
    ok "[$LABEL] all 14 allowlisted table names present as literals"
  else
    bad "[$LABEL] allowlist incomplete — missing literal(s): ${missing[*]}"
  fi

  # Minimum-cardinality guard: a data-derived loop that silently iterates an
  # EMPTY source would exit 0 with ZERO coverage and prove nothing.
  if [[ "${#ALLOW_14[@]}" -eq 14 ]]; then
    ok "[$LABEL] allowlist cardinality is 14 (guard against a vacuously-empty check)"
  else
    bad "[$LABEL] ALLOW_14 has ${#ALLOW_14[@]} entries, expected 14 — the allowlist check would be vacuous"
  fi

  # The revoke loop's source must BE the allowlist array, not a catalog scan.
  check_has 'FOREACH[[:space:]]+[A-Za-z_]+[[:space:]]+IN[[:space:]]+ARRAY' \
    "revoke loop iterates the allowlist array (FOREACH ... IN ARRAY)" \
    "missing FOREACH ... IN ARRAY — the revoke source must be the allowlist, never a catalog scan"

  # Sequences must be DERIVED from the allowlisted tables, not hard-coded.
  check_has '(pg_depend|pg_get_serial_sequence)' \
    "sequences derived via pg_depend/pg_get_serial_sequence" \
    "missing sequence derivation — must not hard-code sequence names"
  check_absent 'goose_db_version_id_seq' \
    "no hard-coded goose_db_version_id_seq (goes stale on the next identity column)" \
    "FORBIDDEN: hard-coded sequence name — derive from the allowlisted tables instead"

  # Lock-acquisition + statement guards (mirror 0001; fail-fast is safe + retryable).
  check_has 'SET[[:space:]]+lock_timeout' \
    "SET lock_timeout present (fail-fast on contention)" "missing SET lock_timeout"
  check_has 'SET[[:space:]]+statement_timeout' \
    "SET statement_timeout present" "missing SET statement_timeout"

  # Positive sentinel: refuse to run where Inngest's tables are absent.
  if has_code 'to_regclass' \
     && has_code 'goose_db_version' \
     && has_code 'function_runs' \
     && has_code 'RAISE[[:space:]]+EXCEPTION'; then
    ok "[$LABEL] fail-closed Inngest-sentinel positive preflight present"
  else
    bad "[$LABEL] missing positive sentinel (to_regclass + RAISE EXCEPTION)"
  fi

  # Non-allowlisted RLS-disabled tables must be REPORTED, never aborted on: an
  # allowlist-driven revoke structurally cannot touch them, so aborting protects
  # nothing while disabling the re-assertion of the 14.
  check_has 'RAISE[[:space:]]+(NOTICE|WARNING)' \
    "reports non-allowlisted findings via RAISE NOTICE/WARNING (never aborts on them)" \
    "missing RAISE NOTICE/WARNING — non-allowlisted tables must be reported, not aborted on"

  # --- Documentation asserted on RAW (these assert a COMMENT exists) ---------
  # Deliberate $RAW reads: the break-glass block and the ALTER DEFAULT PRIVILEGES
  # rationale are PROSE. They cannot be asserted against comment-stripped $CODE.
  check_raw_has 'BREAK-GLASS' \
    "break-glass incident-response block documented (raw-file check: asserts a comment)" \
    "missing BREAK-GLASS comment block"
  check_raw_has 'ALTER[[:space:]]+DEFAULT[[:space:]]+PRIVILEGES' \
    "documents WHY ALTER DEFAULT PRIVILEGES must never run here (raw-file check: asserts a comment)" \
    "missing the ALTER DEFAULT PRIVILEGES rationale comment"

  # --- FORBIDDEN: the co-tenancy divergences from 0001 ------------------------
  # THE most important assertion in this file. On a co-tenanted project this
  # would revoke the default grants every FUTURE dev app migration depends on.
  # Note the deliberate pairing with the check_raw_has above: the token MUST
  # appear in prose and MUST NOT appear in applied code. A raw-file grep would
  # fail this correct implementation — which is why $CODE is comment-stripped.
  check_absent 'ALTER[[:space:]]+DEFAULT[[:space:]]+PRIVILEGES' \
    "no ALTER DEFAULT PRIVILEGES in applied code (would break every future dev app migration)" \
    "FORBIDDEN: ALTER DEFAULT PRIVILEGES present — on a CO-TENANTED project this kills the dev app"

  check_no_schemawide_ddl_loop

  check_absent 'FORCE[[:space:]]+ROW[[:space:]]+LEVEL[[:space:]]+SECURITY' \
    "no FORCE ROW LEVEL SECURITY (owner bypass keeps Inngest working)" \
    "FORBIDDEN: FORCE ROW LEVEL SECURITY present — would lock Inngest out"

  check_absent 'CREATE[[:space:]]+POLICY' \
    "no CREATE POLICY (tables stay client-unreachable; owner bypasses non-forced RLS)" \
    "FORBIDDEN: CREATE POLICY present — re-opens client access"

  check_absent '(^|[^A-Za-z])GRANT[[:space:]]' \
    "no GRANT statement in applied code" \
    "FORBIDDEN: GRANT present in applied SQL"

  # Matviews: Inngest ships none; explicitly out of scope for 0002 (0001 covers
  # them for its own dedicated project, where a schema-wide sweep is safe).
  check_absent 'pg_matviews' \
    "no pg_matviews sweep (out of scope on a co-tenanted project — would reach app matviews)" \
    "FORBIDDEN: pg_matviews sweep present — schema-wide on a co-tenanted project"

  check_no_privileged_revoke
}

echo "inngest-rls.test.sh — per-artifact static shape guards"
profile_0001
profile_0002

echo "---"
echo "passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]] || exit 1
