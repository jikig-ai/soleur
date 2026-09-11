#!/usr/bin/env bash
# Guard 1 (#7849): the shell fixture-env chokepoint.
#
# Producer for AC2 and for Guard 1 rows M3/M4. The subject is
# plugins/soleur/test/lib/git-fixture-env.sh, which owns ONE GIT_LOCATION_VARS array read by both
# the fail-loud tripwire and the git_fixture_env builder. Before this file existed the tripwire was
# inlined in test-helpers.sh and there was no shell sibling of the builder at all, so every shell
# suite that created a fixture wrote its own env -- the fourth spelling of one idea (#7849).
#
# This suite does NOT source test-helpers.sh. It cannot: half of what it asserts is the behaviour of
# the tripwire that test-helpers.sh triggers at source time, and a suite cannot both arm a guard and
# observe it arming. The pass/fail helpers are therefore local and deliberately minimal.
set -uo pipefail

# A sandbox-building suite must not inherit a 4 GiB machine-global tmpfs (work/SKILL.md): a direct
# invocation, which is the documented inner loop while editing the subject, gets the bare /tmp.
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
LIB="$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"

PASS=0; FAIL=0; ASSERTIONS=0
# The verdict reads an APPEND-ONLY ledger, not the counters (see the exit trap below). A counter is
# one assignment away from lying; a ledger line has to be deleted to disappear.
readonly MIN_ASSERTIONS=24
_VERDICT_LEDGER="$(mktemp "$TMPDIR/gfe-verdict.XXXXXXXX")" || {
  printf '[FATAL] mktemp failed for the verdict ledger\n' >&2; exit 2; }
ok()  { printf '  [ok]   %s\n' "$1"; printf 'ok\n'   >>"$_VERDICT_LEDGER"; PASS=$((PASS+1)); ASSERTIONS=$((ASSERTIONS+1)); }
bad() { printf '  [FAIL] %s\n' "$1"; printf 'FAIL\n' >>"$_VERDICT_LEDGER"; FAIL=$((FAIL+1)); ASSERTIONS=$((ASSERTIONS+1)); }

# --- instrument self-test (ADR-193) --------------------------------------------------------------
# Drive both helpers once each before any real assertion and require both counters to have moved.
# A suite whose only gate is a failure counter can be neutered by disarming the counter; this makes
# that mutation observable. The check reports through printf + exit, never through the helpers it
# backstops.
_p0=$PASS; _f0=$FAIL
ok  "instrument self-test: pass() increments"
bad "instrument self-test: fail() increments (EXPECTED -- not a real failure)"
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 )); then
  printf '[FATAL] instrument self-test did not move both counters (pass %d->%d, fail %d->%d)\n' \
    "$_p0" "$PASS" "$_f0" "$FAIL" >&2
  exit 1
fi
# Reset so the self-test does not colour the real result.
# Reset the LEDGER together with the counters. The self-test deliberately drives ok() and bad()
# once each, so its two rows would otherwise make the conservation check fail on every clean run --
# a check that fires on a healthy suite is one the next reader disables.
PASS=0; FAIL=0; ASSERTIONS=0
: > "$_VERDICT_LEDGER"
printf '  [ok]   instrument self-test cleared (both counters moved)\n'
printf 'ok\n' >>"$_VERDICT_LEDGER"
PASS=1; ASSERTIONS=1

# One owning EXIT trap for every fixture this suite allocates (ADR-129 rule (c)).
#
# ONE parent directory, removed by one trap -- NOT an array of fixture paths appended by mkfixture.
# `mkfixture` is called as `F="$(mkfixture)"`, and command substitution runs the function in a
# SUBSHELL: an array append there is discarded, so an array-based trap frees nothing while looking
# exactly like it works. Measured: it left all 6 directories behind.
#
# Measured before any trap existed: 7 call sites, no trap, no `rm` anywhere in the file -- 6 leaked
# directories and ~416 KB per full-gate run, into a machine-global 4 GiB tmpfs shared by every
# parallel worktree.
_FIXTURE_ROOT="$(mktemp -d "$TMPDIR/gfe-shell.XXXXXXXX")" || {
  printf '[FATAL] mktemp -d failed; harness cannot set up\n' >&2; exit 2; }
# Guarded on the shape this function itself creates, so the trap cannot be aimed elsewhere.
# ONE owning EXIT trap: fixture cleanup AND the verdict.
#
# The verdict lives in the trap, and reads the LEDGER rather than the counters, because a bare
# `if (( FAIL > 0 )); then exit 1; fi` at the bottom of a suite is deletable in one line -- measured
# on this very file: 3 `[FAIL]` lines printed and the suite exited 0. In the trap it fires even on
# an early `exit 0`, and because it counts ledger rows, neutering `fail()` into `pass()` is caught
# by the conservation check instead of silently passing.
# RESIDUAL, stated because it is invisible from a green run: deleting the `trap
# _verdict_and_cleanup EXIT` line below silences all of this, and a suite cannot defend its own exit
# from inside itself. Measured: trap deleted + a real regression injected => rc=0. What the ledger
# DOES close is the two mutations that do not touch the trap -- rewriting `bad()` to increment PASS
# (caught by conservation) and dropping the ledger write (caught by conservation). The remaining
# hole needs an external guard asserting every suite HAS a verdict; ADR-193's
# guard-vacuity-floor.test.sh is the natural home, but its population today is "suites that already
# carry a shape-recognizable floor". Tracked in #7889.
_verdict_and_cleanup() {
  local _rc=$?
  local ledger_fail=0 ledger_total=0
  if [[ -r "${_VERDICT_LEDGER:-}" ]]; then
    ledger_fail=$(grep -c '^FAIL$' "$_VERDICT_LEDGER" || true)
    ledger_total=$(grep -c . "$_VERDICT_LEDGER" || true)
  fi
  [[ -n "${_FIXTURE_ROOT:-}" && "$_FIXTURE_ROOT" == "$TMPDIR"/gfe-shell.* ]] && rm -rf "$_FIXTURE_ROOT"
  [[ -n "${_VERDICT_LEDGER:-}" ]] && rm -f "$_VERDICT_LEDGER"

  # Conservation: the counters must agree with the append-only record. A `fail()` rewritten to
  # increment PASS moves both counters and leaves the ledger unchanged, so this catches it.
  if (( ledger_total != ASSERTIONS || ledger_fail != FAIL )); then
    printf '[FATAL] verdict ledger disagrees with the counters: ledger %d rows / %d FAIL vs counters %d assertions / %d FAIL\n' \
      "$ledger_total" "$ledger_fail" "$ASSERTIONS" "$FAIL" >&2
    exit 1
  fi
  if (( ledger_total < MIN_ASSERTIONS )); then
    printf '[FATAL] assertion floor: %d ledger rows < %d\n' "$ledger_total" "$MIN_ASSERTIONS" >&2
    exit 1
  fi
  (( ledger_fail > 0 )) && exit 1
  exit "$_rc"
}
trap _verdict_and_cleanup EXIT

mkfixture() {
  local d
  d="$(mktemp -d "$_FIXTURE_ROOT/fx.XXXXXXXX")" || {
    printf '[FATAL] mktemp -d failed; harness cannot set up\n' >&2; exit 2; }
  mkdir -p "$d/repo" || { printf '[FATAL] mkdir failed in %s\n' "$d" >&2; exit 2; }
  printf '%s' "$d/repo"
}

printf '\n=== the file exists and is sourceable ===\n'
if [[ -f "$LIB" ]]; then
  ok "lib/git-fixture-env.sh exists"
else
  bad "lib/git-fixture-env.sh MISSING at $LIB"
  printf '\n  the remaining assertions cannot run without it\n'
  printf '\n=== summary ===\n  %d passed, %d failed, %d assertions\n' "$PASS" "$FAIL" "$ASSERTIONS"
  exit 1
fi

printf '\n=== ONE array, and it is non-vacuous ===\n'
# Derive from the file rather than from a sourced copy: this pins the LITERAL the parity test reads.
# grep -v the declaration line: the array is NAMED GIT_LOCATION_VARS, so a bare GIT_ extraction
# counts the container as one of its own members. Anchor on the member lines only.
ARR_N=$(sed -n '/^readonly GIT_LOCATION_VARS=(/,/^)/p' "$LIB" | grep -vE '^readonly ' | grep -coE '\bGIT_[A-Z_]+\b')
if (( ARR_N >= 9 )); then
  ok "GIT_LOCATION_VARS array literal carries $ARR_N names (floor 9)"
else
  bad "GIT_LOCATION_VARS derived only $ARR_N names -- extraction broke or the list shrank"
fi
# The array must appear EXACTLY once. Two copies is the defect this file exists to retire.
DEFS=$(grep -cE '^readonly GIT_LOCATION_VARS=\(' "$LIB")
if (( DEFS == 1 )); then ok "GIT_LOCATION_VARS is defined exactly once"
else bad "GIT_LOCATION_VARS defined $DEFS times -- there must be exactly one"; fi

printf '\n=== the tripwire refuses an inherited git-location environment ===\n'
out=$(GIT_DIR=/tmp/hostile bash -c 'source "$1" 2>&1; echo "UNREACHED"' _ "$LIB" 2>&1); rc=$?
if (( rc == 97 )); then ok "tripwire exits 97 under an inherited GIT_DIR"
else bad "tripwire exited $rc under an inherited GIT_DIR, expected 97"; fi
if [[ "$out" != *UNREACHED* ]]; then ok "tripwire aborts rather than returning"
else bad "tripwire returned control -- the suite kept running under a hostile env"; fi
if [[ "$out" == *"unset "* ]]; then ok "tripwire prints an actionable unset remedy"
else bad "tripwire printed no unset remedy"; fi

# Every member must be refused, not just GIT_DIR. A tripwire fixtured on one name cannot see a
# member silently dropped from the array.
missed=""
while read -r v; do
  [[ -n "$v" ]] || continue
  r=$(env "$v=/tmp/hostile" bash -c 'source "$1"' _ "$LIB" >/dev/null 2>&1; echo $?)
  [[ "$r" == "97" ]] || missed="$missed $v"
done < <(sed -n '/^readonly GIT_LOCATION_VARS=(/,/^)/p' "$LIB" | grep -vE '^readonly ' | grep -oE '\bGIT_[A-Z_]+\b')
if [[ -z "$missed" ]]; then ok "every GIT_LOCATION_VARS member is refused"
else bad "tripwire did NOT refuse:$missed"; fi

printf '\n=== the escape hatch is honoured and announced ===\n'
out=$(SOLEUR_GIT_TRIPWIRE_ALLOW=1 GIT_DIR=/tmp/hostile bash -c 'source "$1"; echo REACHED' _ "$LIB" 2>&1); rc=$?
if (( rc == 0 )) && [[ "$out" == *REACHED* ]]; then ok "SOLEUR_GIT_TRIPWIRE_ALLOW=1 disarms the tripwire"
else bad "escape hatch did not disarm (rc=$rc)"; fi
if [[ "$out" == *"DISARMED"* ]]; then ok "the disarm is ANNOUNCED on a green run"
else bad "the escape hatch disarmed SILENTLY -- that is the shape this guard exists to prevent"; fi

printf '\n=== git_fixture_env: the ceiling ===\n'
F="$(mkfixture)"
env_out=$(bash -c 'source "$1"; git_fixture_env "$2" && env' _ "$LIB" "$F" 2>&1); rc=$?
if (( rc == 0 )); then ok "git_fixture_env succeeds on a well-formed fixture"
else bad "git_fixture_env failed (rc=$rc) on a well-formed fixture: $(printf '%s' "$env_out" | head -3)"; fi
want_ceiling="$(cd -P "$(dirname "$F")" && pwd -P)"
got_ceiling=$(printf '%s\n' "$env_out" | grep '^GIT_CEILING_DIRECTORIES=' | head -1 | cut -d= -f2-)
if [[ "$got_ceiling" == "$want_ceiling" ]]; then ok "ceiling is the fixture PARENT, resolved ($got_ceiling)"
else bad "ceiling is [$got_ceiling], expected [$want_ceiling]"; fi

printf '\n=== git_fixture_env: an unenforceable ceiling FAILS, and exports nothing first ===\n'
# git silently ignores a ceiling that is "/" or non-absolute, and ":" splits it into fragments that
# are all discarded. A ceiling that looks set but is ignored is worse than none: it reads as
# protection. Each of these must abort -- and abort BEFORE exporting anything, because a partial
# env is the silent degradation this file exists to prevent.
REL_BASE="$(mkfixture)"; mkdir -p "$REL_BASE/sub" || { printf '[FATAL] mkdir failed\n' >&2; exit 2; }
for bad_dir in "/tmp" "relative/path" "$TMPDIR/has:colon/repo"; do
  # `env -u` is load-bearing, and its absence was a latent hermeticity defect. This probe asserts
  # the BUILDER exported nothing before refusing, but it reads the builder's own signature variable
  # out of an environment it never cleared — so it conflated "the builder exported this" with "this
  # variable has a value from anywhere". It therefore passed only while the ambient environment
  # happened to be empty, i.e. for a reason unrelated to the property it names, and reddened for any
  # developer carrying GIT_CONFIG_KEY_0 for an unrelated purpose (a gpg workaround, a direnv). #7917
  # was the first thing in this repo to set it, which is how it surfaced.
  probe=$(env -u GIT_CONFIG_COUNT -u GIT_CONFIG_KEY_0 -u GIT_CONFIG_VALUE_0 \
    -u GIT_CEILING_DIRECTORIES -u GIT_AUTHOR_NAME \
    bash -c 'source "$1"; git_fixture_env "$2" >/dev/null 2>&1 || true; echo "CEIL=${GIT_CEILING_DIRECTORIES:-<unset>} ID=${GIT_AUTHOR_NAME:-<unset>} SIGN=${GIT_CONFIG_KEY_0:-<unset>}"' _ "$LIB" "$bad_dir" 2>&1)
  r=$(bash -c 'source "$1"; git_fixture_env "$2" >/dev/null 2>&1' _ "$LIB" "$bad_dir"; echo $?)
  if [[ "$r" != "0" ]]; then ok "refuses an unenforceable ceiling for [$bad_dir]"
  else bad "ACCEPTED an unenforceable ceiling for [$bad_dir]"; fi
  if [[ "$probe" == *"CEIL=<unset>"* && "$probe" == *"ID=<unset>"* && "$probe" == *"SIGN=<unset>"* ]]; then
    ok "exported nothing before validating [$bad_dir]"
  else bad "PARTIAL env leaked for [$bad_dir]: $probe"; fi
done

# A relative path that EXISTS is the case the ceiling arm structurally cannot catch: cd -P resolves
# it to an absolute physical path, so the computed ceiling is absolute and passes every check below
# it. Only the input guard can refuse this, so fixture it from inside the parent directory.
relprobe=$(cd "$REL_BASE" && bash -c 'source "$1"; git_fixture_env "sub" >/dev/null 2>&1; echo "rc=$?; CEIL=${GIT_CEILING_DIRECTORIES:-<unset>}"' _ "$LIB" 2>&1)
if [[ "$relprobe" == *"rc=0"* ]]; then
  bad "ACCEPTED an EXISTING relative fixture dir -- resolved against the caller CWD: $relprobe"
else
  ok "refuses an EXISTING relative fixture dir (the ceiling arm cannot see this case)"
fi

printf '\n=== git_fixture_env: a fixture can actually init and commit ===\n'
F2="$(mkfixture)"
cout=$(bash -c '
  source "$1"; git_fixture_env "$2" || exit 9
  cd "$2" || exit 9
  git init -q . >/dev/null 2>&1 || exit 10
  echo hi > f.txt; git add f.txt || exit 11
  git commit -q -m "fixture commit" >/dev/null 2>&1 || exit 12
  git log -1 --format=%s
' _ "$LIB" "$F2" 2>&1); rc=$?
if (( rc == 0 )) && [[ "$cout" == *"fixture commit"* ]]; then ok "a swept fixture can init, add and commit"
else bad "fixture commit failed (rc=$rc): $(printf '%s' "$cout" | tail -2)"; fi

# Assert the AUTHORSHIP, not merely that a commit happened. git auto-detects a name from the passwd
# gecos entry when only the email is pinned, so a commit-succeeds assertion passes with the identity
# exports removed -- measured: mutation M6 survived exactly that way. This also pins
# cq-test-fixtures-synthesized-only: the commit must carry the synthesized identity, never the
# developer own.
ident=$(bash -c '
  source "$1"; git_fixture_env "$2" || exit 9
  cd "$2" || exit 9
  git log -1 --format="%an|%ae|%cn|%ce"
' _ "$LIB" "$F2" 2>&1)
if [[ "$ident" == "Soleur Fixture|fixture@example.com|Soleur Fixture|fixture@example.com" ]]; then
  ok "commit carries the synthesized identity on all four fields"
else
  bad "commit identity is [$ident], expected the synthesized identity on all four fields"
fi

printf '\n=== git_fixture_env: signing is neutralised even repo-LOCALLY (deepen-plan D-1) ===\n'
# The measured gap. GIT_CONFIG_GLOBAL=/dev/null and GIT_CONFIG_NOSYSTEM=1 do NOT reach a REPO-LOCAL
# commit.gpgsign=true, so a fixture that sets one fails "gpg failed to sign the data". The builder
# must carry GIT_CONFIG_COUNT/KEY_0/VALUE_0 as an override. This fixtures the direction where the
# weaker implementation gives a false pass: without the override the commit below fails.
F3="$(mkfixture)"
sout=$(bash -c '
  source "$1"; git_fixture_env "$2" || exit 9
  cd "$2" || exit 9
  git init -q . >/dev/null 2>&1 || exit 10
  git config commit.gpgsign true || exit 11
  git config user.signingkey DEADBEEFDEADBEEF || exit 11
  echo hi > f.txt; git add f.txt || exit 12
  git commit -q -m "signed-off fixture" >/dev/null 2>&1 || exit 13
  git log -1 --format=%s
' _ "$LIB" "$F3" 2>&1); rc=$?
if (( rc == 0 )) && [[ "$sout" == *"signed-off fixture"* ]]; then
  ok "a repo-local commit.gpgsign=true is overridden by the builder"
else
  bad "repo-local commit.gpgsign=true was NOT overridden (rc=$rc) -- GIT_CONFIG_COUNT override missing"
fi

printf '\n=== the prefix sweep reaches non-location GIT_ variables ===\n'
# The tripwire refuses the LOCATION family; the sweep must clear the whole GIT_ prefix. These are
# the members no name list reliably covers and that the TS sibling documents as load-bearing:
# GIT_SSH (a GIT_SSH_COMMAND prefix rule cannot match it -- the prefix is longer than the name),
# the GIT_TRACE family (appends to an absolute path, i.e. a write outside the fixture), and
# GIT_ASKPASS/SSH_ASKPASS (both name a program git will execute). None of them trips the tripwire,
# so without this case the entire sweep can be deleted with the suite still green -- measured:
# mutation M8 survived exactly that way.
F5="$(mkfixture)"
sweep=$(GIT_SSH=/tmp/evil-ssh \
        GIT_SSH_COMMAND=/tmp/evil-cmd \
        GIT_TRACE=/tmp/evil-trace.log \
        GIT_ASKPASS=/tmp/evil-askpass \
        SSH_ASKPASS=/tmp/evil-ssh-askpass \
        bash -c 'source "$1"; git_fixture_env "$2" >/dev/null || exit 9
                 printf "SSH=%s CMD=%s TRACE=%s ASK=%s SASK=%s" \
                   "${GIT_SSH:-<gone>}" "${GIT_SSH_COMMAND:-<gone>}" "${GIT_TRACE:-<gone>}" \
                   "${GIT_ASKPASS:-<gone>}" "${SSH_ASKPASS:-<gone>}"' _ "$LIB" "$F5" 2>&1)
if [[ "$sweep" == "SSH=<gone> CMD=<gone> TRACE=<gone> ASK=<gone> SASK=<gone>" ]]; then
  ok "the prefix sweep clears GIT_SSH, GIT_SSH_COMMAND, GIT_TRACE, GIT_ASKPASS and SSH_ASKPASS"
else
  bad "the sweep left execution/trace vectors behind: $sweep"
fi

printf '\n=== INCIDENTS_REPO_ROOT survives the sweep (task 4.4) ===\n'
F4="$(mkfixture)"
iout=$(INCIDENTS_REPO_ROOT=/tmp/sentinel-root bash -c 'source "$1"; git_fixture_env "$2" >/dev/null || exit 9; echo "GOT=${INCIDENTS_REPO_ROOT:-<unset>}"' _ "$LIB" "$F4" 2>&1)
if [[ "$iout" == *"GOT=/tmp/sentinel-root"* ]]; then
  ok "INCIDENTS_REPO_ROOT survives git_fixture_env (the ledger sink is not swept away)"
else
  bad "INCIDENTS_REPO_ROOT did NOT survive: $iout"
fi

printf '\n=== summary ===\n'
printf '  %d passed, %d failed, %d assertions\n' "$PASS" "$FAIL" "$ASSERTIONS"
# No verdict here: the EXIT trap owns it, reading the append-only ledger. A bare check at this
# position is deletable in one line and the suite would exit 0 with [FAIL] lines on screen.
exit 0
