#!/usr/bin/env bash
# Guard 1: the single write chokepoint. Controls, bite-proof mutations of a sandbox copy, no leftovers.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
check "instrument self-test" selftest
command -v gitleaks >/dev/null 2>&1 || { echo "FAIL - gitleaks is required for this suite"; exit 1; }
GATE="$SKILL/scripts/lib/redact-gate.sh"
clean="$SCRATCH/clean.md"; dirty="$SCRATCH/dirty.md"
printf '# Report\n\nNothing secret here, path docs/secret-handling.md only.\n' > "$clean"
printf '# Report\n\nContact: %s@%s.invalid\n' 'jane.roe' 'example' > "$dirty"
run_gate() { # run_gate <gate-lib> <src> <dest>  -> rc
  # shellcheck source=/dev/null
  ( set +e; export SKILL_DIR="$SKILL" PLUGIN_DIR="$PLUGIN"; source "$1"; lc_emit_checked "$2" "$3" 0 ) >"$SCRATCH/g.out" 2>&1
}
run_gate "$GATE" "$clean" "$SCRATCH/out/clean.md"; rc=$?
check "control: clean bytes are written" bash -c '[ "$1" = 0 ] && [ -f "$2" ] && cmp -s "$3" "$2"' _ "$rc" "$SCRATCH/out/clean.md" "$clean"
check "must-PASS: a path containing the word secret but no value is written" test -f "$SCRATCH/out/clean.md"
run_gate "$GATE" "$dirty" "$SCRATCH/out2/dirty.md"; rc=$?
check "planted email-shaped value: rc 1, reason=redaction-hit, nothing written" bash -c '[ "$1" = 1 ] && grep -q "reason=redaction-hit" "$2" && [ ! -e "$3" ]' _ "$rc" "$SCRATCH/g.out" "$SCRATCH/out2/dirty.md"
check "no temp file and no empty directory left behind after an abort" test ! -e "$SCRATCH/out2"
check "the abort never echoes the matched value" bash -c '! grep -q "jane.roe" "$1"' _ "$SCRATCH/g.out"

# Mutation 1: remove the sentinel call from a sandbox copy -> the gate must now let the planted value through.
mkdir -p "$SCRATCH/mut"
sed 's/^\(.*REDACT_SENTINEL.*\)$/: # mutated: \1/' "$GATE" > "$SCRATCH/mut/gate.sh"
check "mutation landed (sandbox copy differs from the pristine gate)" bash -c '! cmp -s "$1" "$2"' _ "$GATE" "$SCRATCH/mut/gate.sh"
run_gate "$SCRATCH/mut/gate.sh" "$dirty" "$SCRATCH/out3/dirty.md"; rc=$?
check "mutation 1 (sentinel removed): the planted value now gets through, so the suite is sensitive" test "$rc" = 0 -a -f "$SCRATCH/out3/dirty.md"
# Scanner that did not run -> rc 2, never 'found secrets' and never a write.
printf '#!/usr/bin/env bash\nexit 2\n' > "$SCRATCH/s2.sh"; chmod +x "$SCRATCH/s2.sh"
( export LAUNCH_CHECK_REDACT_SENTINEL="$SCRATCH/s2.sh"; run_gate "$GATE" "$clean" "$SCRATCH/out4/c.md" ); rc=$?
check "sentinel exits 2 (did not complete): rc 2 and no file" bash -c '[ "$1" = 2 ] && [ ! -e "$2" ]' _ "$rc" "$SCRATCH/out4/c.md"
( export LAUNCH_CHECK_GITLEAKS="$SCRATCH/s2.sh"; run_gate "$GATE" "$clean" "$SCRATCH/out5/c.md" ); rc=$?
check "gitleaks exits 2 (did not complete): rc 2 and no file" bash -c '[ "$1" = 2 ] && [ ! -e "$2" ]' _ "$rc" "$SCRATCH/out5/c.md"
( export LAUNCH_CHECK_GITLEAKS=gitleaks-does-not-exist; run_gate "$GATE" "$clean" "$SCRATCH/out6/c.md" ); rc=$?
check "gitleaks missing: rc 2 reason=scanner-missing" bash -c '[ "$1" = 2 ] && grep -q "reason=scanner-missing" "$2"' _ "$rc" "$SCRATCH/g.out"
# Source scan: exactly one write path to the report.
nw=$(grep -c 'mv -f\|mv "' "$SKILL/scripts/lib/render.sh" "$SKILL/scripts/launch-check.sh" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
check "render.sh and launch-check.sh never move a file onto the report themselves" test "$nw" = 0
check "no direct redirect to the report path outside the gate" bash -c '! grep -nE ">[> ]*\"?\$\{?(REPORT|DEST)" "$1" "$2" 2>/dev/null' _ "$SKILL/scripts/lib/render.sh" "$SKILL/scripts/launch-check.sh"
# Harness row: a clean string through the same harness must flip the verdict to written.
printf '# Report\n\nclean\n' > "$SCRATCH/notplanted.md"
run_gate "$GATE" "$SCRATCH/notplanted.md" "$SCRATCH/out7/n.md"; rc=$?
check "harness row: replacing the plant with a clean string flips the verdict (suite can fail)" test "$rc" = 0

# --- Review fixes (PR #11867) ---
# The gitleaks layer alone (the sentinel is stubbed to pass): the redaction gate must catch a token-shaped value there.
printf '# Report\n\nvalue: %s\n' "$(planted_secret)" > "$SCRATCH/gl.md"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SCRATCH/s0.sh"; chmod +x "$SCRATCH/s0.sh"
( export LAUNCH_CHECK_REDACT_SENTINEL="$SCRATCH/s0.sh"; run_gate "$GATE" "$SCRATCH/gl.md" "$SCRATCH/out8/g.md" ); rc=$?
check "gitleaks layer alone: rc 1 reason=redaction-hit layer=gitleaks, nothing written" bash -c '[ "$1" = 1 ] && grep -q "layer=gitleaks" "$2" && [ ! -e "$3" ]' _ "$rc" "$SCRATCH/g.out" "$SCRATCH/out8/g.md"
check "the abort never echoes the token" bash -c '! grep -q "ghp_" "$1"' _ "$SCRATCH/g.out"
# Seams are test-only: with LAUNCH_CHECK_TEST unset the overrides are ignored and the real layers run.
( export LAUNCH_CHECK_TEST=0 LAUNCH_CHECK_REDACT_SENTINEL="$SCRATCH/s0.sh"; run_gate "$GATE" "$dirty" "$SCRATCH/out9/d.md" ); rc=$?
check "production mode ignores a sentinel override: the planted value is still caught by the real sentinel" bash -c '[ "$1" = 1 ] && grep -q "layer=sentinel" "$2"' _ "$rc" "$SCRATCH/g.out"
TRUE_BIN=$(command -v true)
( export LAUNCH_CHECK_TEST=0 LAUNCH_CHECK_GITLEAKS="$TRUE_BIN"; run_gate "$GATE" "$SCRATCH/gl.md" "$SCRATCH/out10/g.md" ); rc=$?
check "production mode ignores a scanner override: the token is still caught" test "$rc" = 1
# No scratch directory or temp file is leaked on success or on abort, and no trap noise reaches stderr.
mkdir -p "$SCRATCH/tmpd"
( export TMPDIR="$SCRATCH/tmpd"; run_gate "$GATE" "$clean" "$SCRATCH/out11/c.md" ); rc=$?
check "success: no lc-gate scratch directory is left behind and the trap prints nothing" bash -c '[ "$1" = 0 ] && [ -z "$(ls -A "$2")" ] && ! grep -q "parameter null" "$3"' _ "$rc" "$SCRATCH/tmpd" "$SCRATCH/g.out"
( export TMPDIR="$SCRATCH/tmpd"; run_gate "$GATE" "$dirty" "$SCRATCH/out12/d.md" )
check "abort: no scratch directory left behind either" test -z "$(ls -A "$SCRATCH/tmpd")"
check "the report is written world-readable (644), not as the temp file's 600" bash -c '[ "$(ls -l "$1" | cut -c1-10)" = "-rw-r--r--" ]' _ "$SCRATCH/out/clean.md"
# The write cannot leave the declared root through a symlinked directory.
mkdir -p "$SCRATCH/root" "$SCRATCH/away"; ln -s "$SCRATCH/away" "$SCRATCH/root/kb"
( export LC_DEST_ROOT="$SCRATCH/root"; run_gate "$GATE" "$clean" "$SCRATCH/root/kb/sub/r.md" ); rc=$?
check "destination resolving outside LC_DEST_ROOT: rc 2 write-failed, nothing created outside" bash -c '[ "$1" = 2 ] && grep -q "reason=write-failed" "$2" && [ -z "$(ls -A "$3")" ]' _ "$rc" "$SCRATCH/g.out" "$SCRATCH/away"
# Source scan: every use of the report path is a read or the single chokepoint call.
stray=$(grep -n 'TARGET/\$REPORT_REL' "$SKILL/scripts/lib/render.sh" "$SKILL/scripts/launch-check.sh" | grep -vE 'lc_emit_checked|lc_prev_state|\[ -f|2>/dev/null' || true)
check "no use of the report path other than a read or lc_emit_checked" test -z "$stray"
finish 23
