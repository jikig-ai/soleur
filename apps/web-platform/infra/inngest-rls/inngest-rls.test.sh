#!/usr/bin/env bash
# Static-shape guards for the Inngest RLS-lockdown SQL artifacts.
# Mirrors the sibling apps/web-platform/infra/inngest-*.test.sh style. No DB
# connection — these assert each SQL artifact's SHAPE so a future edit cannot
# silently introduce a break-Inngest or re-expose change.
#
# ONE ARTIFACT, ONE PROFILE — READ THIS BEFORE ADDING AN ASSERTION.
#
#   0001_enable_rls_lockdown.sql -> soleur-inngest-prd (pigsfuxruiopinouvjwy)
#     A DEDICATED, single-tenant Inngest project. Schema-wide revoke is correct
#     there, and `ALTER DEFAULT PRIVILEGES` is REQUIRED (it is the durable
#     recurrence fix for future Inngest-version tables).
#
# THIS FILE USED TO GUARD TWO ARTIFACTS WITH DELIBERATELY INVERTED SHAPES, and
# the inversion is worth recording because it is the thing a future edit could
# undo by accident. `0002_dev_inngest_tables_lockdown.sql` targeted soleur-dev,
# a CO-TENANTED project where the dark Inngest backend shared `public` with the
# app's 52 tables — so there, `ALTER DEFAULT PRIVILEGES` was FORBIDDEN (it would
# have revoked the default grants every future dev app migration relies on) and
# a schema-wide catalog loop was FORBIDDEN too (it would have revoked
# anon/authenticated across those 52 app tables). Exactly the opposite of 0001.
#
# That co-tenancy ended: the cutover moved Inngest to its own project, the 14
# dark tables were dropped on 2026-09-19 (#6488, run 35471968669), and 0002 was
# retired with them. Its profile and the two guards that existed only for it
# (`check_no_schemawide_ddl_loop`, `check_sequence_ddl_is_allowlist_bound`) went
# at the same time.
#
# => If a second artifact is ever added here, give it its OWN profile. Bolting it
#    onto 0001's assertions is how the inversion above gets lost: a co-tenanted
#    artifact would fail 0001's `ALTER DEFAULT PRIVILEGES` required-check, and the
#    tempting "fix" — adding that statement to it — is precisely the catastrophe
#    these guards exist to prevent.
#
# IMPORTANT: assertions about APPLIED CODE run against the artifact with `--`
# line-comments STRIPPED ($CODE), because the break-glass comment legitimately
# names `postgres`, `service_role`, `DISABLE ROW LEVEL SECURITY`, and re-`GRANT`
# — a raw grep would false-match that prose (grep-over-script-body false-match
# class). There is no raw-text reader any more: the only assertions that read the
# unstripped artifact belonged to the 0002 profile, retired 2026-09-19 with the
# artifact itself (#6488), so `$RAW` and its two helpers went with them rather
# than being left as an unused seam the next author would reach for.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_0001="$DIR/0001_enable_rls_lockdown.sql"

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

# MINIMUM-CARDINALITY GUARD FOR ALLOW_14 — at top level, deliberately.
#
# It used to live inside profile_0002, which was the only profile that iterated the
# array by name. But profile_0001's negative-noun loop consumes ALLOW_14 too
# (`for nt in "${ALLOW_14[@]}" users conversations`), so when the 0002 profile was
# deleted with its artifact (#6488), the array kept a live consumer and lost its only
# cardinality check — it could then silently shrink and profile_0001 would report `ok`
# over fewer names, which is the vacuity class the guard exists for, reintroduced BY the
# cleanup. Hoisting it first was a prerequisite of that deletion, not a tidy-up after it.
if [[ "${#ALLOW_14[@]}" -eq 14 ]]; then
  ok "[allowlist] ALLOW_14 cardinality is 14 (guard against a vacuously-empty check)"
else
  bad "[allowlist] ALLOW_14 has ${#ALLOW_14[@]} entries, expected 14 — every loop over it would be vacuous"
fi

# --- profile state -----------------------------------------------------------
CODE=""; LABEL=""

load_profile() {
  LABEL="$(basename "$1")"
  if [[ ! -f "$1" ]]; then
    echo "FAIL: artifact not found at $1"
    exit 1
  fi
  CODE="$(sed -E 's/--.*$//' "$1")"
}

has_code()    { printf '%s' "$CODE" | grep -iqE "$1"; }
absent_code() { ! printf '%s' "$CODE" | grep -iqE "$1"; }
# if/then/else helpers (not `A && B || C`, which runs C when B fails — SC2015).
check_has()     { if has_code "$1";    then ok "[$LABEL] $2"; else bad "[$LABEL] $3"; fi; }
check_absent()  { if absent_code "$1"; then ok "[$LABEL] $2"; else bad "[$LABEL] $3"; fi; }

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
# Legitimately NOT flagged: 0002's non-allowlisted REPORT reads relkind='r'/'p'
# schema-wide but emits no DDL.
#

# $CODE strips ONLY `--` line comments, so a `/* ... */` block is invisible to the
# stripper and stays in $CODE — every `check_has` below would still find the tokens
# it names inside a wholly commented-out file. Wrapping 0001's ENTIRE revoke DO-block
# in `/* */` left the suite GREEN 42/0 (mutation-proven 2026-07-15).
#
# Rather than teach the stripper to handle nested/quoted block comments (a real
# tokenizer problem), FORBID the construct: both artifacts contain ZERO `/*` today
# and have no need for one — `--` is the house style throughout.
check_no_block_comments() {
  check_absent '/\*' \
    "no /* */ block comments (the \$CODE stripper only handles --; a block comment would hide real code from every check above)" \
    "FORBIDDEN: /* */ block comment present — \$CODE strips only --, so every check_has here can pass against commented-out code. Use -- instead."
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

  # Inngest ships GENERIC nouns and has no namespace discipline. If the NEGATIVE
  # guard (0c) ever names one, 0001 RAISEs on prd FOREVER — killing the ADR-030 I8
  # self-heal. The guard MUST use app-distinctive names only.
  #
  # The forbidden set is ALLOW_14 — the names Inngest is PROVEN to ship (re-derived
  # from the live catalog), each of which would break prd the moment it is added —
  # plus users/conversations, generic nouns goose could plausibly ship later.
  # (The prior assertion checked ONLY users/conversations: the wrong set twice over.
  # Inngest ships NEITHER, while `events`/`apps`/`functions` — which it DOES ship —
  # passed the guard freely. Mutation-verified 2026-07-15.)
  #
  # DISCRIMINATOR: `IS NOT NULL` (0c, the negative guard) vs `IS NULL` (0b, the
  # positive sentinel). goose_db_version and function_runs are in ALLOW_14 AND
  # legitimately appear in 0b — asserting on the bare to_regclass() call would
  # false-RED the correct file. Scope to the NEGATIVE construct only.
  local neg_offenders=() nt flat
  flat="$(printf '%s' "$CODE" | tr '\n' ' ' | tr -s ' ')"
  for nt in "${ALLOW_14[@]}" users conversations; do
    if printf '%s' "$flat" | grep -iqE "to_regclass\('public\.${nt}'\)[[:space:]]+IS[[:space:]]+NOT[[:space:]]+NULL"; then
      neg_offenders+=("$nt")
    fi
  done
  if [[ "${#neg_offenders[@]}" -eq 0 ]]; then
    ok "[$LABEL] negative guard names no Inngest-shipped/generic noun (checked ${#ALLOW_14[@]}+2 names against the IS NOT NULL construct)"
  else
    bad "[$LABEL] FORBIDDEN: negative guard names Inngest-shipped table(s): ${neg_offenders[*]} — 0001 would RAISE on prd permanently, killing the ADR-030 I8 self-heal"
  fi

  # Ordering: the guard is worthless if it runs AFTER the revoke loop. Assert the
  # byte-offset of the app-distinctive guard precedes the FIRST REVOKE.
  #
  # `REVOKE[[:space:]]` alone was the WRONG pattern: it matches the word REVOKE inside
  # 0001's own RAISE EXCEPTION prose ("A schema-wide REVOKE here would break the app"),
  # which sits in a string literal — NOT a comment, so $CODE keeps it — and precedes
  # the real revoke loop. revoke_off therefore pointed at PROSE, and this check
  # returned the right verdict only BY ACCIDENT (the prose happens to fall after the
  # guard). Match actual revoke STATEMENTS instead: a dynamic `EXECUTE format('REVOKE`
  # or a REVOKE at the start of a line. Prose REVOKE is mid-line inside a string, so
  # neither alternative can match it — correct by construction, not by luck.
  local guard_off revoke_off
  guard_off="$(printf '%s' "$CODE" | grep -abioE "to_regclass\('public\.kb_files'\)" | head -1 | cut -d: -f1)"
  revoke_off="$(printf '%s' "$CODE" | grep -abioE "(EXECUTE[[:space:]]+format\('REVOKE|^[[:space:]]*REVOKE[[:space:]])" | head -1 | cut -d: -f1)"
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

  check_no_block_comments
  check_no_privileged_revoke
}

# =============================================================================
# PROFILE: 0002 — soleur-dev (CO-TENANTED; table-scoped ONLY)
# =============================================================================

echo "inngest-rls.test.sh — per-artifact static shape guards"
profile_0001

echo "---"
echo "passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]] || exit 1
