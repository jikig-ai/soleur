#!/usr/bin/env bash
# Mutation attestation for check_sequence_ddl_is_allowlist_bound in inngest-rls.test.sh.
#
# WHY THIS FILE EXISTS
# --------------------
# inngest-rls.test.sh's sequence guard exists to stop ONE catastrophe: a sequence-revoke
# loop that emits DDL without an allowlist join would REVOKE ALL on every sequence in
# `public` — including the 52 app tables co-tenanted on soleur-dev. A guard that cannot
# fail on that mutation buys nothing while reading as protection, which is worse than no
# guard at all.
#
# The claim "this guard is non-vacuous" is only worth what its evidence is worth. Asserted
# in a comment it is prose; asserted here it is re-checked on every CI run. This file was
# added after a session crash destroyed an ad-hoc, uncommitted run of exactly this matrix
# and left the guard's value claim unattested — the labels M3/M6 below survived only
# because they were re-derivable from the guard's own two detection arms.
#
# WHAT IT PROVES (both halves are load-bearing)
#   M3, M6   — the guard goes RED when the allowlist binding is removed, once per
#              detection arm (relkind='S' catalog scan; pg_sequences view).
#   M3b, M6b — the guard stays GREEN while the binding is intact. A guard that fired on
#              any sequence code would pass M3/M6 for the wrong reason and block honest
#              edits. RED-only evidence cannot tell those two guards apart.
#
# ISOLATION: every mutation is applied to a throwaway sandbox that mirrors the four repo
# levels inngest-rls.test.sh resolves REPO_ROOT through ($DIR/../../../..), never to the
# tracked artifact. There is no path by which an interrupted run leaves 0002 mutated.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../../../.." && pwd)"

GUARD_FAIL='FORBIDDEN: a sequence loop emits DDL without an allowlist join'
GUARD_OK='sequence-revoke DDL is bound to the allowlist'

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT INT TERM

# Mirror only what inngest-rls.test.sh reads: its own dir (SQL_0001/SQL_0002 via $DIR) and
# DEV_WF via REPO_ROOT. The four-deep path is what makes REPO_ROOT land on $SANDBOX.
SB_DIR="$SANDBOX/apps/web-platform/infra/inngest-rls"
mkdir -p "$SB_DIR" "$SANDBOX/.github/workflows"
cp "$DIR/0001_enable_rls_lockdown.sql" "$DIR/0002_dev_inngest_tables_lockdown.sql" \
   "$DIR/inngest-rls.test.sh" "$SB_DIR/"
cp "$REPO_ROOT/.github/workflows/apply-inngest-rls-dev.yml" "$SANDBOX/.github/workflows/"

SB_SQL="$SB_DIR/0002_dev_inngest_tables_lockdown.sql"
PRISTINE="$SANDBOX/0002.pristine"
cp "$SB_SQL" "$PRISTINE"

reset_sandbox() { cp "$PRISTINE" "$SB_SQL"; }

# assert_mutation_applied <case> <predicate: present|absent> <pattern>
# A mutation that silently fails to apply would test the UNMUTATED file and report a
# false GREEN — the exact vacuity this suite exists to disprove. Fail loudly instead.
assert_mutation_applied() {
  local case_name="$1" predicate="$2" pattern="$3"
  if [[ "$predicate" == "absent" ]] && grep -qF "$pattern" "$SB_SQL"; then
    bad "[$case_name] mutation did not apply — '$pattern' still present; case would be vacuous"
    return 1
  fi
  if [[ "$predicate" == "present" ]] && ! grep -qF "$pattern" "$SB_SQL"; then
    bad "[$case_name] mutation did not apply — '$pattern' absent; case would be vacuous"
    return 1
  fi
  return 0
}

# run_case <name> <expect: RED|GREEN> <description>
run_case() {
  local name="$1" expect="$2" desc="$3" out state
  out="$(bash "$SB_DIR/inngest-rls.test.sh" 2>&1)"

  if grep -qF "$GUARD_FAIL" <<<"$out"; then
    state="RED"
  elif grep -qF "$GUARD_OK" <<<"$out"; then
    state="GREEN"
  else
    # Neither line present: the guard never ran. Silently treating this as a pass would
    # let a renamed/deleted guard read as proven.
    bad "[$name] guard produced NEITHER verdict line — it did not run (renamed or removed?)"
    return
  fi

  if [[ "$state" == "$expect" ]]; then
    ok "[$name] guard=$state as specified — $desc"
  else
    bad "[$name] guard=$state, expected $expect — $desc"
  fi
}

echo "inngest-rls-mutation.test.sh — non-vacuity proof for the sequence-DDL allowlist guard"
echo

# --- BASELINE ---------------------------------------------------------------------
# The tracked artifact binds via `AND tc.relname = t`, so the guard must be GREEN. If this
# is RED the mutations below prove nothing about the guard.
run_case "BASE" "GREEN" "unmutated 0002 (bound by tc.relname = t)"

# --- M3: relkind='S' catalog loop, binding removed -> schema-wide sequence revoke ---
reset_sandbox
perl -0pi -e "s/\n\s*AND tc\.relname = t\n/\n/" "$SB_SQL"
if assert_mutation_applied "M3" absent "AND tc.relname = t"; then
  run_case "M3" "RED" "relkind='S' loop with the allowlist binding REMOVED"
fi

# --- M6: same catastrophe via the pg_sequences arm ---------------------------------
reset_sandbox
perl -0pi -e "s/FROM pg_class s\b/FROM pg_sequences s/" "$SB_SQL"
perl -0pi -e "s/\n\s*WHERE s\.relkind = 'S'\n\s*AND tn\.nspname = 'public'\n\s*AND tc\.relname = t\n/\n      WHERE tn.nspname = 'public'\n/" "$SB_SQL"
if assert_mutation_applied "M6" present "pg_sequences" \
   && assert_mutation_applied "M6" absent "AND tc.relname = t"; then
  run_case "M6" "RED" "pg_sequences loop with the allowlist binding REMOVED"
fi

# --- NEGATIVE CONTROLS -------------------------------------------------------------
# M6b: the pg_sequences arm with the binding INTACT is safe. RED here would mean the guard
# keys on the source rather than the binding, and would block a legitimate refactor.
reset_sandbox
perl -0pi -e "s/FROM pg_class s\b/FROM pg_sequences s/" "$SB_SQL"
if assert_mutation_applied "M6b" present "pg_sequences"; then
  run_case "M6b" "GREEN" "pg_sequences loop, binding INTACT (false-positive check)"
fi

# M3b: pg_get_serial_sequence is the guard's other sanctioned way to express the binding.
reset_sandbox
perl -0pi -e "s/\n(\s*)AND tc\.relname = t\n/\n\$1AND s.oid = pg_get_serial_sequence(tc.relname, 'id')::regclass\n/" "$SB_SQL"
if assert_mutation_applied "M3b" present "pg_get_serial_sequence"; then
  run_case "M3b" "GREEN" "binding expressed via pg_get_serial_sequence (alt escape hatch)"
fi

echo "---"
echo "passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]] || exit 1
