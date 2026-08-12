#!/usr/bin/env bash
# tenant-dpa-register-guard.test.sh -- suite + mutation battery for the tenant-DPA register guard.
#
# Closes #7349 defects A1 and A2, both of which were guard-shaped no-ops:
#
#   A1  knowledge-base/legal/tenant-dpa-register.md carried
#         awk '/^\| /' <register> | grep -c 'status: dpa-signed'
#       while the Status vocabulary (and therefore any real Status cell) uses the BARE
#       token `dpa-signed`. The predicate could never match a table row. Measured: with a
#       signed row planted, the old predicate still returned 0.
#
#   A2  tenant-provisioning.md Step 0 asserted
#         grep -c '^|' <register> | xargs -I{} test {} -ge 3
#       "header + separator + >=1 data row". The EMPTY register has exactly 3 pipe-lines
#       (header, separator, and the `| _(none yet)_ |` placeholder), so the gate was
#       vacuously true on the empty set -- it would have kept passing until the moment it
#       mattered. Measured: 3 on the empty register.
#
# Both are now routed through the real script scripts/tenant-dpa-register-guard.sh, so this
# suite drives THE REAL FILE. It deliberately does NOT re-declare the good predicate in a
# heredoc: a fixture that restates the correct idiom asserts only that a known-good snippet
# is known-good, and stays green after the real guard regresses.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only). The live register is used
# only for the reachability floor -- per #7387, detection without reachability is exactly
# how the original defect shipped.
#
# Registered by hand in scripts/test-all.sh; scripts/lint-orphan-test-suites.sh fails if
# that registration is ever dropped.

set -euo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO_ROOT/scripts/tenant-dpa-register-guard.sh"
LIVE_REGISTER="$REPO_ROOT/knowledge-base/legal/tenant-dpa-register.md"
RUNBOOK="$REPO_ROOT/knowledge-base/engineering/operations/runbooks/tenant-provisioning.md"

# Floor calibrated to the CURRENT assertion count -- deliberately NO slack. A floor below the
# real count is deletion headroom: at 26-against-29 three assertions could be removed (including
# all three that pin the column anchor) and the suite still exited 0. A floor still permits
# GROWTH, which equality would turn into a spurious failure; it is only the slack that was wrong.
MIN_ASSERTIONS=42

passes=0
fails=0
pass() { passes=$((passes + 1)); echo "[ok] $1"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }

# DISPATCHER SELF-TEST. The floor sees `total = passes + fails`, so neutering fail() ALONE
# leaves the count intact while silently absorbing real failures. Prove both counters move
# before any real assertion runs.
_p0=$passes; _f0=$fails
pass "dispatcher self-test: pass() increments"; fail "dispatcher self-test: fail() increments (EXPECTED)"
if (( passes == _p0 + 1 && fails == _f0 + 1 )); then
  passes=$_p0; fails=$_f0            # rewind; the probe is not a real assertion
  pass "dispatcher self-test: both counters are live"
else
  passes=$_p0; fails=$((_f0 + 1))
  echo "[FAIL] dispatcher self-test: pass()/fail() are not both incrementing -- assertions are unobservable" >&2
fi

[[ -x "$GUARD" ]] || { echo "guard script missing or not executable: $GUARD" >&2; exit 2; }

SANDBOX=$(mktemp -d -t tenant-dpa-guard.XXXXXXXX) || { echo "mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT

HEADER='| Tenant slug | Legal entity | Founder UUID | DPA signed date | DPA counter-signed date | Sub-processors (Schedule 2) | Status | Notes |'
SEP='|---|---|---|---|---|---|---|---|'

# Build a register fixture. Every argument after the first is emitted as a table row.
build_register() {
  local out="$1"; shift
  {
    printf -- '---\ntitle: "fixture"\n---\n\n## Rows\n\n'
    printf '%s\n%s\n' "$HEADER" "$SEP"
    local row
    for row in "$@"; do printf '%s\n' "$row"; done
    printf -- '\n## Status values\n\n- `dpa-signed` -- executed by both parties.\n'
  } > "$out" || { echo "fixture write failed" >&2; exit 2; }
}

EMPTY_ROW='| _(none yet)_ | | | | | | |'
SIGNED_ROW='| acme | Acme SARL | 00000000-0000-4000-8000-000000000001 | 2026-08-10 | 2026-08-10 | Hetzner; Cloudflare | dpa-signed | first tenant |'
PROV_ROW='| beta | Beta SAS | 00000000-0000-4000-8000-000000000002 | 2026-08-01 | 2026-08-02 | Hetzner | provisioned | |'
ABORT_ROW='| gamma | Gamma SL | 00000000-0000-4000-8000-000000000003 | 2026-07-01 | 2026-07-02 | Hetzner | aborted-provisioning-at-step-4 | teardown done |'

# --------------------------------------------------------------------------------------
# A1 -- signed-row detection. BOTH ARMS ARE REQUIRED: a guard that always fires passes a
# one-arm test, which is precisely how the dead predicate survived review.
# --------------------------------------------------------------------------------------

reg_empty="$SANDBOX/empty.md";    build_register "$reg_empty" "$EMPTY_ROW"
reg_signed="$SANDBOX/signed.md";  build_register "$reg_signed" "$SIGNED_ROW"
reg_mixed="$SANDBOX/mixed.md";    build_register "$reg_mixed" "$PROV_ROW" "$SIGNED_ROW" "$ABORT_ROW"
reg_nonsigned="$SANDBOX/nons.md"; build_register "$reg_nonsigned" "$PROV_ROW" "$ABORT_ROW"

n=$("$GUARD" --register "$reg_signed" count-signed)
[[ "$n" == "1" ]] && pass "A1 arm 1: fires on a planted signed row (got $n)" \
                  || fail "A1 arm 1: planted signed row not detected (got '$n', want 1)"

n=$("$GUARD" --register "$reg_empty" count-signed)
[[ "$n" == "0" ]] && pass "A1 arm 2: does NOT fire once the row is removed (got $n)" \
                  || fail "A1 arm 2: fired on the empty register (got '$n', want 0)"

n=$("$GUARD" --register "$reg_nonsigned" count-signed)
[[ "$n" == "0" ]] && pass "A1: non-signed statuses are not counted as signed (got $n)" \
                  || fail "A1: counted a non-signed status (got '$n', want 0)"

n=$("$GUARD" --register "$reg_mixed" count-signed)
[[ "$n" == "1" ]] && pass "A1: counts only the signed row among mixed statuses (got $n)" \
                  || fail "A1: mixed-status count wrong (got '$n', want 1)"

# The old predicate's exact failure. Pinning it keeps a revert visibly red rather than
# silently green.
if "$GUARD" --register "$reg_signed" count-signed | grep -qx '0'; then
  fail "A1 regression: the guard reports 0 against a planted signed row (the #7349 defect)"
else
  pass "A1 regression: a planted signed row is never reported as 0"
fi

# `status: dpa-signed` is the DEAD form. A register that literally contains it in a Notes
# cell must not be counted -- otherwise the fix would merely relocate the false positive.
reg_prosetrap="$SANDBOX/prose.md"
build_register "$reg_prosetrap" \
  '| delta | Delta Oy | 00000000-0000-4000-8000-000000000004 | | | | provisioned | prior status: dpa-signed noted here |'
n=$("$GUARD" --register "$reg_prosetrap" count-signed)
[[ "$n" == "0" ]] && pass "A1: a Notes cell mentioning the status does not count as signed (got $n)" \
                  || fail "A1: Notes-cell prose counted as a signed row (got '$n', want 0)"

# Anchor on the Status COLUMN, not a bare token: a tenant slug literally named
# `dpa-signed` must not be counted (cq-assert-anchor-not-bare-token).
reg_slugtrap="$SANDBOX/slug.md"
build_register "$reg_slugtrap" \
  '| dpa-signed | Epsilon Ltd | 00000000-0000-4000-8000-000000000005 | | | | provisioned | |'
n=$("$GUARD" --register "$reg_slugtrap" count-signed)
[[ "$n" == "0" ]] && pass "A1: the token in a non-Status column does not count (got $n)" \
                  || fail "A1: matched the token outside the Status column (got '$n', want 0)"

# --------------------------------------------------------------------------------------
# A2 -- data-row counting and the fail-closed empty/populated split.
# --------------------------------------------------------------------------------------

n=$("$GUARD" --register "$reg_empty" count-data-rows)
[[ "$n" == "0" ]] && pass "A2: the '_(none yet)_' placeholder is not a data row (got $n)" \
                  || fail "A2: placeholder counted as a data row (got '$n', want 0) -- the vacuous-gate defect"

n=$("$GUARD" --register "$reg_mixed" count-data-rows)
[[ "$n" == "3" ]] && pass "A2: counts real data rows (got $n)" \
                  || fail "A2: data-row count wrong (got '$n', want 3)"

if "$GUARD" --register "$reg_empty" assert-populated >/dev/null 2>&1; then
  fail "A2: assert-populated PASSED on the empty register (the #7349 vacuous gate)"
else
  pass "A2: assert-populated fails closed on the empty register"
fi

"$GUARD" --register "$reg_signed" assert-populated >/dev/null 2>&1 \
  && pass "A2: assert-populated succeeds once a real row exists" \
  || fail "A2: assert-populated rejected a populated register"

"$GUARD" --register "$reg_empty" assert-empty >/dev/null 2>&1 \
  && pass "A2: assert-empty succeeds on the empty register (the §6.1 clock baseline)" \
  || fail "A2: assert-empty rejected the empty register"

# ---------------------------------------------------------------------------------------
# A3 -- assert-signed. Step 0 of tenant-provisioning.md asks whether a SIGNED DPA is
# recorded. It used to run assert-populated, which only asks whether the register is
# NON-EMPTY. The register is append-only, so once ANY row is ever written -- including a
# row for a tenant that has since been offboarded -- a row-count gate is permanently green
# for every future tenant. That is the same vacuous-gate shape this guard was built to
# replace, one layer up, and it was found in review of #7349 before a second tenant
# existed to be harmed by it.
# ---------------------------------------------------------------------------------------

reg_offboarded="$SANDBOX/offboarded-only.md"
cat > "$reg_offboarded" <<'EOF'
## Rows

| Tenant | DPA signed | Status | Notes |
|--------|-----------|--------|-------|
| acme | 2026-01-01 | offboarded-with-data-deleted | gone |
EOF

# The exact false-negative: populated, zero signed.
"$GUARD" --register "$reg_offboarded" assert-populated >/dev/null 2>&1 \
  && pass "A3: assert-populated is TRUE with zero signed rows (documents why Step 0 cannot use it)" \
  || fail "A3: fixture wrong -- assert-populated should pass on a non-empty register"

if "$GUARD" --register "$reg_offboarded" assert-signed >/dev/null 2>&1; then
  fail "A3: assert-signed PASSED with zero dpa-signed rows -- Step 0 gate is vacuous"
else
  pass "A3: assert-signed fails closed when no row is dpa-signed"
fi

"$GUARD" --register "$reg_signed" assert-signed >/dev/null 2>&1 \
  && pass "A3: assert-signed succeeds once a dpa-signed row exists" \
  || fail "A3: assert-signed rejected a register holding a signed row"

if "$GUARD" --register "$reg_empty" assert-signed >/dev/null 2>&1; then
  fail "A3: assert-signed PASSED on the empty register"
else
  pass "A3: assert-signed fails closed on the empty register"
fi

# The runbook must cite the predicate that answers Step 0's question, not the row-count one.
if grep -q 'tenant-dpa-register-guard.sh assert-signed' "$RUNBOOK"; then
  pass "A3: tenant-provisioning.md Step 0 cites assert-signed"
else
  fail "A3: Step 0 does not cite assert-signed -- the vacuous row-count gate is back"
fi

if "$GUARD" --register "$reg_signed" assert-empty >/dev/null 2>&1; then
  fail "A2: assert-empty PASSED on a populated register"
else
  pass "A2: assert-empty fails on a populated register"
fi

# The two assertions must be genuinely distinct verdicts, not two spellings of one check.
if "$GUARD" --register "$reg_empty" assert-empty >/dev/null 2>&1 \
   && ! "$GUARD" --register "$reg_empty" assert-populated >/dev/null 2>&1; then
  pass "A2: empty and populated are distinct verdicts on the same input"
else
  fail "A2: empty/populated verdicts are not distinguishable"
fi

# --------------------------------------------------------------------------------------
# Parser regressions found at review. Each was a SILENT wrong answer, not an error: the guard
# returned a count the caller had no way to distrust.
# --------------------------------------------------------------------------------------

# A Status-bearing table ABOVE `## Rows` used to capture the column, rendering the real rows
# table invisible while still exiting 0.
reg_above="$SANDBOX/above.md"
{ printf -- '## Summary\n\n| Quarter | Status |\n|---|---|\n| Q3 | open |\n\n'
  printf -- '## Rows\n\n%s\n%s\n%s\n' "$HEADER" "$SEP" "$SIGNED_ROW"; } > "$reg_above"
n=$("$GUARD" --register "$reg_above" count-signed)
[[ "$n" == "1" ]] && pass "parser: a Status table above '## Rows' does not capture the column (got $n)" \
                  || fail "parser: bound to the wrong table (got '$n', want 1)"

# An escaped pipe in a cell LEFT of Status shifted every column right of it.
reg_esc="$SANDBOX/esc.md"
build_register "$reg_esc" \
  '| acme | Acme SARL | 00000000-0000-4000-8000-000000000001 | 2026-08-10 | 2026-08-10 | Hetzner \| Cloudflare | dpa-signed | ok |'
n=$("$GUARD" --register "$reg_esc" count-signed)
[[ "$n" == "1" ]] && pass "parser: an escaped pipe in a left-hand cell does not shift the Status column (got $n)" \
                  || fail "parser: escaped pipe shifted the column (got '$n', want 1)"

# GFM trailing pipes are optional; without one the LAST cell was never compared.
reg_notrail="$SANDBOX/notrail.md"
{ printf -- '## Rows\n\n| Tenant slug | Legal entity | Status\n|---|---|---\n| acme | Acme SARL | dpa-signed\n'; } > "$reg_notrail"
n=$("$GUARD" --register "$reg_notrail" count-signed)
[[ "$n" == "1" ]] && pass "parser: a row with no trailing pipe still has its Status compared (got $n)" \
                  || fail "parser: last cell skipped without a trailing pipe (got '$n', want 1)"

# The placeholder must be position-INDEPENDENT: a column inserted left of the slug made an
# EMPTY register report a tenant, so Step 0's "STOP, do not provision" gate passed on it.
reg_shift="$SANDBOX/shift.md"
{ printf -- '## Rows\n\n| Region | Tenant slug | Status | Notes |\n|---|---|---|---|\n| eu | _(none yet)_ | | |\n'; } > "$reg_shift"
n=$("$GUARD" --register "$reg_shift" count-data-rows)
[[ "$n" == "0" ]] && pass "parser: the placeholder is matched in any column, not a fixed index (got $n)" \
                  || fail "parser: an empty register reported ${n} tenant row(s) after a column insert"

# A data row whose first cell starts with a hyphen used to be eaten as a separator.
reg_hyphen="$SANDBOX/hyphen.md"
{ printf -- '## Rows\n\n| Tenant slug | Status |\n|---|---|\n| -acme | dpa-signed |\n'; } > "$reg_hyphen"
n=$("$GUARD" --register "$reg_hyphen" count-signed)
[[ "$n" == "1" ]] && pass "parser: a hyphen-leading first cell is a data row, not a separator (got $n)" \
                  || fail "parser: hyphen-leading row eaten as a separator (got '$n', want 1)"

# assert-populated must distinguish >=1 from ==1 -- it was only ever driven at 0 and 1 rows.
"$GUARD" --register "$reg_mixed" assert-populated >/dev/null 2>&1 \
  && pass "A2: assert-populated succeeds at 3 rows (>=1, not ==1)" \
  || fail "A2: assert-populated rejected a 3-row register"

# --------------------------------------------------------------------------------------
# Fail-closed on unusable input -- never a vacuous 0.
# --------------------------------------------------------------------------------------

# `rc=$?` on its own line after a failing command is an ABORT under `set -e`: the failing
# command is a complete statement, so the shell exits there and the capture never runs.
# `|| rc=$?` keeps the failure inside a compound command, where errexit is suspended.
rc=0; "$GUARD" --register "$SANDBOX/does-not-exist.md" count-signed >/dev/null 2>&1 || rc=$?
[[ "$rc" == "2" ]] && pass "fail-closed: exit 2 on a missing register (rc=$rc)" \
                   || fail "fail-closed: missing register did not exit 2 (rc=$rc)"

notable="$SANDBOX/notable.md"
printf -- '---\ntitle: "x"\n---\n\nNo rows table here.\n' > "$notable"
rc=0; "$GUARD" --register "$notable" count-signed >/dev/null 2>&1 || rc=$?
[[ "$rc" == "2" ]] && pass "fail-closed: exit 2 when the rows table is absent (rc=$rc)" \
                   || fail "fail-closed: absent rows table did not exit 2 (rc=$rc)"

nostatus="$SANDBOX/nostatus.md"
{
  printf -- '---\ntitle: "x"\n---\n\n## Rows\n\n'
  printf '%s\n%s\n' '| Tenant slug | Legal entity | Notes |' '|---|---|---|'
  printf '%s\n' '| acme | Acme SARL | |'
} > "$nostatus"
rc=0; "$GUARD" --register "$nostatus" count-signed >/dev/null 2>&1 || rc=$?
[[ "$rc" == "2" ]] && pass "fail-closed: exit 2 when no Status column exists (rc=$rc)" \
                   || fail "fail-closed: missing Status column did not exit 2 (rc=$rc)"

rc=0; "$GUARD" --register "$reg_empty" no-such-subcommand >/dev/null 2>&1 || rc=$?
[[ "$rc" == "2" ]] && pass "fail-closed: exit 2 on an unknown subcommand (rc=$rc)" \
                   || fail "fail-closed: unknown subcommand did not exit 2 (rc=$rc)"

# --------------------------------------------------------------------------------------
# Reachability against the LIVE corpus (#7387: detection != reachability). A guard that
# cannot reach its real input is still a no-op, however well it scores on fixtures.
# --------------------------------------------------------------------------------------

[[ -f "$LIVE_REGISTER" ]] && pass "reachability: the live register exists at the cited path" \
                          || fail "reachability: live register missing at $LIVE_REGISTER"

live_rows=$(awk '/^\| /' "$LIVE_REGISTER" | wc -l)
(( live_rows >= 1 )) && pass "reachability: the guard's input is non-empty (${live_rows} table line(s))" \
                     || fail "reachability: the live register exposes no table lines -- input is empty"

"$GUARD" --register "$LIVE_REGISTER" count-signed >/dev/null 2>&1 \
  && pass "reachability: the guard runs clean against the live register" \
  || fail "reachability: the guard errored against the live register"

# DECIDABILITY, not emptiness. "Jikigai has zero tenants" is a business fact with an expiry
# date, not a code property: encoding it here means onboarding tenant #1 reds the suite on the
# day the guard finally matters, and the under-pressure fix is to delete the assertion.
rc=0; live_signed=$("$GUARD" --register "$LIVE_REGISTER" count-signed) || rc=$?
[[ "$rc" == "0" && "$live_signed" =~ ^[0-9]+$ ]] \
  && pass "live register is DECIDABLE (signed-row count = ${live_signed}, rc=0)" \
  || fail "live register is undecidable: rc=$rc out='${live_signed}' -- the guard cannot parse its real input"

# The placeholder literal is coupled to the register's markdown. If the register reworded it
# and the guard did not, an EMPTY register would count as populated -- the A2 defect respelled.
grep -qF '_(none yet)_' "$LIVE_REGISTER" \
  && pass "coupling: the guard's placeholder literal appears verbatim in the live register" \
  || fail "coupling: the register's empty-state placeholder no longer matches the guard's literal"

# --------------------------------------------------------------------------------------
# Call-site coupling. The dead predicates must not come back, and the runbook + register
# must cite the real guard rather than re-implementing it.
# --------------------------------------------------------------------------------------

if grep -q "status: dpa-signed" "$LIVE_REGISTER"; then
  fail "call-site: the dead 'status: dpa-signed' form is still present in the register"
else
  pass "call-site: the dead 'status: dpa-signed' form is gone from the register"
fi

if grep -qE "grep -c ['\"]\^\|['\"]" "$RUNBOOK"; then
  fail "call-site: the vacuous \"grep -c '^|' ... -ge 3\" gate is still present in the runbook"
else
  pass "call-site: the vacuous pipe-line-count gate is gone from the runbook"
fi

# Subcommand alternation derived from the guard's own usage block rather than restated:
# a hand-maintained closed list went stale the moment `assert-signed` was added (#7349
# review), reporting "the runbook does not invoke the guard" when it did.
_SUBCMDS=$("$GUARD" --help | awk '/^Subcommands:/{f=1;next} /^$/{f=0} f{print $1}' | paste -sd'|')
[[ -n "$_SUBCMDS" ]] || fail "call-site: could not derive subcommands from --help"
grep -qE "bash scripts/tenant-dpa-register-guard\.sh (${_SUBCMDS})" "$RUNBOOK" \
  && pass "call-site: the runbook carries an executable INVOCATION, not a prose mention" \
  || fail "call-site: the runbook mentions the guard but does not invoke it"

grep -q 'tenant-dpa-register-guard.sh' "$LIVE_REGISTER" \
  && pass "call-site: the register cites the real guard script" \
  || fail "call-site: the register does not cite scripts/tenant-dpa-register-guard.sh"

# A3 -- the status vocabulary is one form, not two.
if grep -qE 'aborted-provisioning([^-]|$)' "$RUNBOOK"; then
  fail "A3: the runbook still writes the bare 'aborted-provisioning' status"
else
  pass "A3: the runbook uses the 'aborted-provisioning-at-step-N' vocabulary"
fi

# --------------------------------------------------------------------------------------
# Mutation battery -- prove the assertions above can actually fail.
# --------------------------------------------------------------------------------------

MUT="$SANDBOX/mut"; mkdir -p "$MUT" || { echo "mkdir failed" >&2; exit 2; }
PRISTINE="$MUT/pristine.sh"
cp "$GUARD" "$PRISTINE" || { echo "cp failed" >&2; exit 2; }

mutate_and_check() {
  local label="$1" sed_expr="$2"
  local mutant="$MUT/mutant.sh"
  cp "$PRISTINE" "$mutant" || { echo "cp failed" >&2; exit 2; }
  sed -E -i "$sed_expr" "$mutant" || { echo "sed failed" >&2; exit 2; }
  chmod +x "$mutant"
  if diff -q "$PRISTINE" "$mutant" >/dev/null 2>&1; then
    fail "mutation '$label': sed changed nothing -- the verdict would be vacuous"
    return
  fi
  # With the mutation applied, the planted-signed-row arm must stop reporting 1.
  local got
  got=$("$mutant" --register "$reg_signed" count-signed 2>/dev/null || echo "ERR")
  if [[ "$got" == "1" ]]; then
    fail "mutation '$label': survived -- guard still reports 1 on a planted signed row"
  else
    pass "mutation '$label': detected (got '$got')"
  fi
}

mutate_and_check "status-token-broken" 's/dpa-signed/dpa-signedX/'
mutate_and_check "always-zero"         's/^[[:space:]]*printf .%s\\n. .\$\{?count\}?.$/printf "0\\n"/'

# --------------------------------------------------------------------------------------

total=$((passes + fails))
echo
echo "passed: ${passes} failed: ${fails} total: ${total}"

if (( total < MIN_ASSERTIONS )); then
  echo "suite ran only ${total} assertions, expected at least ${MIN_ASSERTIONS} -- assertions are not running" >&2
  exit 1
fi

(( fails == 0 )) || exit 1
echo "=== tenant-dpa-register-guard: all assertions passed ==="
