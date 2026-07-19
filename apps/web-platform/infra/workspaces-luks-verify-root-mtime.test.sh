#!/usr/bin/env bash
#
# Reproduction harness for the C1 false abort (#6733).
#
# THE DEFECT (measured, not hypothesised). `assert_mount_quiesced` (workspaces-cutover.sh, the
# G4 quiescence gate) opens its positive-control probe INSIDE the mount:
#
#     probe="$MOUNT/.luks-g4-probe.$$"
#     exec 9>"$probe"                    # creates a depth-1 entry in $MOUNT
#     ...
#     rm -f "$lout" "$lerr" "$probe"     # removes it
#
# and the main body calls it at `assert_mount_quiesced pre-verify`, BETWEEN the pass-2 delta
# rsync (the last write to $STAGING) and `verify_byte_identity "$MOUNT" "$STAGING"` (C1).
#
# $MOUNT *is* the rsync transfer root, so `./` is $MOUNT. Create+unlink is a NET-ZERO listing
# change — but both operations advance the ROOT DIRECTORY's mtime. C1's itemized rsync therefore
# emits exactly one line, `.d..t...... ./`, and the cutover safe-aborts having copied a
# byte-identical tree.
#
# C1 IS CORRECT. The probe is the defect. This suite pins the mechanism so that a fix is
# measured rather than asserted, and so that nobody "fixes" it by narrowing C1.
#
# WHAT THIS SUITE PROVES (the three rows of the plan's mechanism table):
#   A1  clean immediately after a pass-2-equivalent rsync          (with a positive control)
#   A2  `.d..t...... ./` after the G4 create+unlink run VERBATIM   <- the RED reproduction
#   A4  clean when the same sequence is bracketed by an mtime save/restore (the Phase 2 shape)
#   A3  couples the above to the REAL script: is today's `assert_mount_quiesced` unbracketed?
#
# ---------------------------------------------------------------------------------------------
# TASK 1.6 — WHY THE PROBE FD CANNOT SIMPLY BE RELOCATED OUTSIDE $MOUNT. REJECTED. Concretely:
#
# G4 property (c) is a POSITIVE CONTROL. `lsof` exits 1 BOTH when it finds nothing and when it
# errors, writing diagnostics only to stderr — so an errored probe is indistinguishable from a
# quiesced mount. The script closes that by holding its OWN fd under $MOUNT and REQUIRING the
# scan to report it back:
#
#     workspaces-cutover.sh:467   if ! grep -qF -- "$probe" "$lout"; then ... die "the G4
#                                 straggler probe is BLIND, not clean"
#
# `lsof +D "$MOUNT"` enumerates open files *under the directory tree $MOUNT*. An fd opened
# outside $MOUNT is BY CONSTRUCTION not in that tree, so `lsof +D "$MOUNT"` would never list it,
# the `:467` grep would never match, and EVERY invocation would take the `g4_probe_blind` die
# path. Relocation does not weaken the positive control — it converts the gate into an
# unconditional abort. The freeze could never proceed.
#
# The adjacent candidate — hold a read-only fd on a file that ALREADY exists under $MOUNT — is
# zero-perturbation (a read moves only atime, and C1 at :229 compares neither atime nor ctime),
# but it is rejected for a stronger reason: the holder filter at
#
#     workspaces-cutover.sh:472   holders="$(grep -vF -- "$probe" "$lout" | grep -v '^COMMAND ')"
#
# subtracts $probe from the holder list. Pointing $probe at a real path would make G4 subtract a
# GENUINE straggler that happens to hold that same file — a fail-open in the exact gate whose
# purpose is to catch stragglers. Worse than the bug it would fix.
#
# The probe must therefore stay a fresh entry under $MOUNT; the fix belongs on the mtime, not on
# the location. Also rejected (plan Non-Goals): relocating one level deeper, which merely moves
# the diff to `.d..t...... workspaces/` — still a real difference C1 must reject.
# ---------------------------------------------------------------------------------------------
#
# HARNESS DISCIPLINE (both classes below have bitten this repo inside the last week):
#   * NEVER `producer | grep -q PATTERN` under pipefail. `grep -q` exits on first match, the
#     producer takes SIGPIPE, the pipeline returns 141, and a NEGATIVE assertion fails OPEN and
#     reports green forever. Every grep here runs against a real FILE or a herestring.
#     (2026-07-19: "the harness broke the rule it enforced")
#   * Every happy-path case carries a positive control, so it cannot pass vacuously, and the
#     suite carries a non-degeneracy floor: zero assertions is a LOUD FAILURE, never a green run.
#     (2026-07-19: "my mutation battery was green")
#   * `[^\n]` in a POSIX ERE excludes the LETTER n, not newlines. This file uses `.*`.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUTOVER="$SCRIPT_DIR/workspaces-cutover.sh"

pass=0
fails=0
asserted=0
ok()   { pass=$((pass + 1));   asserted=$((asserted + 1)); printf 'ok   - %s\n' "$1"; }
fail() { fails=$((fails + 1)); asserted=$((asserted + 1)); printf 'FAIL - %s\n' "$1"; }
note() { printf '#      %s\n' "$1"; }

# Non-degeneracy floor (task 1.5). Bumped deliberately when cases are added; a suite that runs
# fewer assertions than it claims to own has silently lost coverage and must not report green.
MIN_ASSERTIONS=17

skip() { printf 'SKIP: %s\n' "$1"; exit 0; }

# --- C0: capability preflight -----------------------------------------------------------------
# uutils/BSD hosts differ from prod (Debian GNU) on `stat -c %y` nanosecond fidelity and on
# `touch -r` reference semantics. A green run there would not be evidence about prod, so SKIP
# cleanly rather than hard-erroring. Precedent:
# plugins/soleur/skills/git-worktree/test/stale-lock-sweep.test.sh:28-29.
command -v rsync >/dev/null 2>&1 || skip "rsync required"
[ -r "$CUTOVER" ] || { printf 'FAIL - cutover script not readable at %s\n' "$CUTOVER"; exit 1; }

SCRATCH="$(mktemp -d)"                    # never a fixed /tmp name: parallel worktrees are normal here
trap 'rm -rf "$SCRATCH"' EXIT

stat -c %y -- "$SCRATCH" >/dev/null 2>&1 || skip "GNU 'stat -c %y' required — non-GNU coreutils host"
: >"$SCRATCH/.capref"
touch -r "$SCRATCH" "$SCRATCH/.capref" 2>/dev/null || skip "GNU 'touch -r' required — non-GNU coreutils host"
rm -f "$SCRATCH/.capref"

# Directory mtimes must actually move on create/unlink, else the mechanism is unobservable here —
# a property of the scratch filesystem, not evidence that the bug is absent. SKIP, never pass.
_g0="$(stat -c %y -- "$SCRATCH")"
: >"$SCRATCH/.granprobe"; rm -f "$SCRATCH/.granprobe"
_g1="$(stat -c %y -- "$SCRATCH")"
[ "$_g0" != "$_g1" ] || skip "scratch filesystem does not record directory mtime changes — the defect is unobservable here"

# --- Fixture (task 1.2) ------------------------------------------------------------------------
# Shape DERIVED FROM THE PRODUCTION LAYOUT, not from what reads well in a test. On web-1,
# /mnt/data's top level is INFRASTRUCTURE (workspaces/ plugins/ redis/) and user identity lives
# one level deeper at workspaces/<id>/. A fixture with user dirs at depth 1 makes depth-sensitive
# checks agree with the fixture and hides their vacuity — the exact defect class of the
# 2026-07-19 "fixture modeled a convenient shape" learning.
#
# Hostile filename (task 5.12): %n carries user workspace filenames, and the tree already treats
# that channel as hostile (_vscrub). A newline-bearing name is included so the fixture exercises
# the path that rsync must escape rather than a sanitised imaginary one.
MOUNT="$SCRATCH/mnt"        # the SRC / rsync transfer root — `./` in the itemize output IS this
STAGING="$SCRATCH/stg"      # the DST
mkdir -p "$MOUNT" "$STAGING"

mkdir -p "$MOUNT/workspaces/ws-a/.git" "$MOUNT/workspaces/ws-b" "$MOUNT/plugins" "$MOUNT/redis/appendonlydir"
printf 'alpha\n'          >"$MOUNT/workspaces/ws-a/file.txt"
printf 'ref: main\n'      >"$MOUNT/workspaces/ws-a/.git/HEAD"
printf 'notes\n'          >"$MOUNT/workspaces/ws-b/notes.md"
printf 'plugin=1\n'       >"$MOUNT/plugins/p.conf"
printf 'aof\n'            >"$MOUNT/redis/appendonlydir/appendonly.aof.1.incr.aof"
HOSTILE=$'ws-a/hostile\nname.txt'
printf 'hostile\n'        >"$MOUNT/workspaces/$HOSTILE"
if [ -f "$MOUNT/workspaces/$HOSTILE" ]; then
  ok "fixture: newline-bearing filename created under workspaces/ws-a (hostile %n channel, task 5.12)"
else
  fail "fixture: could not create a newline-bearing filename — the hostile-name case cannot run"
fi

# --- The script's EXACT invocations ------------------------------------------------------------
# pass-2 delta rsync, verbatim from workspaces-cutover.sh (§G3, the last write to DST).
pass2() {
  rsync -aHAX --numeric-ids --delete --checksum "$MOUNT"/ "$STAGING"/
}
# The C1 itemized verify, verbatim from verify_byte_identity (workspaces-cutover.sh:229).
# stdout -> $1, stderr -> $2, rsync's rc returned. NO PIPE: the caller greps the FILE.
verify_into() {
  local vout="$1" verr="$2" rc=0
  rsync -aHAXi --numeric-ids --checksum --delete --dry-run --out-format='%i %n' \
    "$MOUNT"/ "$STAGING"/ >"$vout" 2>"$verr" || rc=$?
  return "$rc"
}
# C1's own diff counter, verbatim from workspaces-cutover.sh:245. Counts EVERY itemize code.
diff_n() { grep -cE '^(\*deleting|[<>ch.*][fdLDS])' "$1" || true; }

VOUT="$SCRATCH/vout"; VERR="$SCRATCH/verr"

# -aHAX means ACLs (-A) and xattrs (-X). A scratch filesystem without them makes the verify rsync
# ERROR, which is a harness condition, not evidence about the defect.
if ! pass2 >"$SCRATCH/p2.out" 2>"$SCRATCH/p2.err"; then
  note "pass-2 rsync stderr: $(tr '\n' ' ' <"$SCRATCH/p2.err")"
  skip "the script's exact pass-2 rsync (-aHAX) cannot run on this filesystem — ACL/xattr support missing"
fi

# =================================================================================================
# A1 (task 1.3) — the verify is CLEAN immediately after a pass-2-equivalent rsync.
# =================================================================================================
rc=0; verify_into "$VOUT" "$VERR" || rc=$?
if [ "$rc" -ne 0 ]; then
  note "verify rsync stderr: $(tr '\n' ' ' <"$VERR")"
  skip "the script's exact C1 verify rsync cannot run on this filesystem (rc=$rc)"
fi
n="$(diff_n "$VOUT")"
if [ "$n" -eq 0 ]; then
  ok "A1: C1 verify is CLEAN immediately after the pass-2 delta rsync (0 itemized differences)"
else
  fail "A1: verify emitted $n difference(s) straight after pass-2 — fixture/baseline is not clean: $(tr '\n' '|' <"$VOUT")"
fi

# A1 positive control — without this, A1 passes vacuously if the verify can never emit anything
# (wrong paths, a silently-erroring rsync, an --out-format typo). Perturb a NON-ROOT directory's
# mtime and require the verify to see it. This is also plan mutation m4: the case a blanket
# --omit-dir-times or a loose icode match would have swallowed.
touch -d '2020-01-01 00:00:00' "$MOUNT/workspaces"
rc=0; verify_into "$VOUT" "$VERR" || rc=$?
if [ "$rc" -eq 0 ] && grep -qE '^\.d\.\.t\.\.\.\.\.\. workspaces/$' "$VOUT"; then
  ok "A1-pc: positive control — a NON-ROOT dir mtime change emits '.d..t...... workspaces/' (A1 is not vacuous)"
else
  fail "A1-pc: the verify did NOT report a perturbed non-root dir mtime (rc=$rc) — A1's clean result is not evidence: $(tr '\n' '|' <"$VOUT")"
fi

# Re-converge DST and re-assert clean, so A2 starts from a known-clean baseline rather than
# inheriting A1-pc's perturbation.
pass2 >/dev/null 2>&1
rc=0; verify_into "$VOUT" "$VERR" || rc=$?
n="$(diff_n "$VOUT")"
if [ "$rc" -eq 0 ] && [ "$n" -eq 0 ]; then
  ok "A1-re: baseline re-converged clean after the positive control (A2 starts from a clean tree)"
else
  fail "A1-re: could not re-converge to a clean baseline (rc=$rc, diffs=$n) — A2 would measure leftover state"
fi

# =================================================================================================
# A2-gran — MEASURED GRANULARITY. Establish, before A2 relies on it, what C1 can actually SEE.
#
# rsync 3.4.1 compares directory mtimes at WHOLE-SECOND granularity: a move confined to the
# sub-second component is INVISIBLE to the itemized verify. Measured here rather than assumed,
# because two downstream claims depend on it:
#
#   1. A2's reproduction is only deterministic if the probe's create and unlink straddle a
#      second boundary. An earlier draft of this harness ran them back-to-back and was ~50%
#      flaky for exactly this reason — a coin-flip reproduction that would have been reported
#      as a stable one.
#   2. It FALSIFIES the plan's mutation m17 ("a %Y-precision restore still emits the diff —
#      pins ns precision"). It does not: a whole-second restore is sufficient for C1, because
#      C1 cannot see below a second. `%y` remains the right choice for the fix (it is strictly
#      more faithful and costs nothing), but m17 must NOT be encoded as an assertion — an
#      asserted-but-unmeasured icode is the false-result class the 2026-07-19 learning names.
# =================================================================================================
pass2 >/dev/null 2>&1
sub_base="$(stat -c %Y -- "$MOUNT")"
touch -d "@${sub_base}.500000000" -- "$MOUNT"
rc=0; verify_into "$VOUT" "$VERR" || rc=$?
n="$(diff_n "$VOUT")"
if [ "$rc" -eq 0 ] && [ "$n" -eq 0 ]; then
  ok "A2-gran: a SUB-SECOND-only root mtime move is invisible to C1 (rsync compares dir mtimes per whole second) — plan m17 is FALSIFIED, do not assert it"
else
  fail "A2-gran: expected a sub-second-only root move to be invisible, got $n difference(s) — the granularity premise below is wrong: $(tr '\n' '|' <"$VOUT")"
fi

# =================================================================================================
# A2 (task 1.4) — THE RED REPRODUCTION.
# Run the G4 probe's create+unlink sequence VERBATIM (same `exec 9>` + `rm -f` shape as
# workspaces-cutover.sh:454/459/473) between the pass-2 rsync and the verify, exactly as
# `assert_mount_quiesced pre-verify` does at the pre-verify call site. The listing change is
# net-zero. The root's mtime is not.
#
# The `sleep` stands in for what occupies this interval in production: `lsof +D "$MOUNT"`
# (workspaces-cutover.sh:458), a full recursive scan of the mount that takes SECONDS on the real
# /workspaces volume. That is why the create and the unlink reliably land in different whole
# seconds in production, and therefore why the abort reproduces on every real cutover rather
# than intermittently. Omitting it does not make the harness "more verbatim" — it models a
# scan that costs zero time, which is the one shape production never has.
# =================================================================================================
pass2 >/dev/null 2>&1
root_pre="$(stat -c %y -- "$MOUNT")"
sec_pre="$(stat -c %Y -- "$MOUNT")"
probe="$MOUNT/.luks-g4-probe.$$"
exec 9>"$probe"          # :454 — creates the entry (an open fd, so lsof can report it)
sleep 1.1                # :458 — stands in for `lsof +D "$MOUNT"` (seconds on the real mount)
exec 9>&-                # :459
rm -f "$probe"           # :473 — removes it
root_post="$(stat -c %y -- "$MOUNT")"
sec_post="$(stat -c %Y -- "$MOUNT")"

if [ "$sec_pre" != "$sec_post" ]; then
  ok "A2-sec: the probe bracket crossed a whole-second boundary ($sec_pre -> $sec_post) — the reproduction's precondition is MEASURED, not assumed"
else
  fail "A2-sec: create and unlink landed in the same whole second — C1 cannot see this move, so a clean A2 below would be a HARNESS artifact, not a fixed script"
fi

if [ ! -e "$probe" ]; then
  ok "A2-pre: the probe entry is gone — the listing change is net-zero (nothing added, nothing removed)"
else
  fail "A2-pre: the probe file survived the unlink — A2 would measure a leftover entry, not an mtime move"
fi

if [ "$root_pre" != "$root_post" ]; then
  ok "A2-mtime: the create+unlink advanced \$MOUNT's ROOT mtime ($root_pre -> $root_post)"
else
  fail "A2-mtime: the root mtime did not move — the probe sequence did not reproduce its own precondition"
fi

rc=0; verify_into "$VOUT" "$VERR" || rc=$?
n="$(diff_n "$VOUT")"
root_line="$(grep -cE '^\.d\.\.t\.\.\.\.\.\. \./$' "$VOUT" || true)"
if [ "$rc" -eq 0 ] && [ "$root_line" -eq 1 ]; then
  ok "A2: the G4 probe run VERBATIM makes C1 emit '.d..t...... ./' — the production abort is REPRODUCED"
else
  fail "A2: expected exactly one '.d..t...... ./' line after the verbatim G4 probe, got $root_line (rc=$rc): $(tr '\n' '|' <"$VOUT")"
fi
if [ "$n" -eq 1 ]; then
  ok "A2-only: that root line is the ONLY difference ($n total) — zero files differ; C1 aborts on a byte-identical tree"
else
  fail "A2-only: expected exactly 1 total difference, got $n — the reproduction is not the reported signature: $(tr '\n' '|' <"$VOUT")"
fi

# =================================================================================================
# A4 — the third row of the mechanism table: the SAME sequence, bracketed by an mtime
# save/restore, verifies CLEAN. This is the shape Phase 2 puts into `assert_mount_quiesced`, and
# it is what makes A2 a statement about the BRACKETING rather than about `exec 9>` itself.
#
# The same `sleep` stand-in for the lsof scan is MANDATORY here. Without it the bracket stays
# inside one whole second, C1 could not have seen the move anyway (A2-gran), and A4's clean
# result would be a granularity artifact wearing a working fix's clothes — the precise shape of
# "a gate that certifies a property adjacent to the one that matters".
# =================================================================================================
pass2 >/dev/null 2>&1
ref="$SCRATCH/g4ref"; : >"$ref"
touch -r "$MOUNT" "$ref"                      # capture by reference, not via a %y string round-trip
b_pre="$(stat -c %y -- "$MOUNT")"
b_sec_pre="$(stat -c %Y -- "$MOUNT")"
probe2="$MOUNT/.luks-g4-probe.b$$"
exec 9>"$probe2"; sleep 1.1; exec 9>&-; rm -f "$probe2"
[ ! -e "$probe2" ] || fail "A4: probe2 unlink failed — the restore must not run over a surviving entry"
b_sec_unres="$(stat -c %Y -- "$MOUNT")"
if [ "$b_sec_pre" != "$b_sec_unres" ]; then
  ok "A4-pre: before the restore, the root had moved a whole second ($b_sec_pre -> $b_sec_unres) — A4's clean result below is attributable to the RESTORE, not to granularity"
else
  fail "A4-pre: the bracket did not move the root by a whole second — A4 cannot distinguish a working restore from an invisible move"
fi
touch -r "$ref" "$MOUNT"                      # restore
b_post="$(stat -c %y -- "$MOUNT")"
if [ "$b_post" = "$b_pre" ]; then
  ok "A4-readback: the restore is MEASURED — \$MOUNT's mtime reads back identical ($b_post)"
else
  fail "A4-readback: restore skew — pre=$b_pre post=$b_post (a truncating touch exits 0 and would pass an exit-status-only guard)"
fi
rc=0; verify_into "$VOUT" "$VERR" || rc=$?
n="$(diff_n "$VOUT")"
if [ "$rc" -eq 0 ] && [ "$n" -eq 0 ]; then
  ok "A4: probe + root-mtime save/restore => C1 verify CLEAN — the fix shape is sufficient"
else
  fail "A4: expected a clean verify with the restore applied, got $n difference(s) (rc=$rc): $(tr '\n' '|' <"$VOUT")"
fi

# =================================================================================================
# A3 — couple the reproduction to the REAL script.
# A2/A4 are filesystem physics; on their own they do not say which of the two shapes production
# actually runs. Read `assert_mount_quiesced` out of the script, strip comments (a bare-token grep
# matching the comment that EXPLAINS the trap is a documented recurring error here —
# cq-assert-anchor-not-bare-token), and anchor on SYNTAX.
# =================================================================================================
# SC2016 is disabled from here down BY DESIGN: these patterns match the LITERAL TEXT `$MOUNT`,
# `$probe`, `$ref` and `$STAGING` as they appear in the script's source. Expanding them would
# make the assertions match this harness's own runtime values instead of the SUT's syntax —
# turning every structural anchor below into a silent no-match. Each site carries its own
# disable directive so the exemption stays scoped to the anchors that need it.
FUNC="$SCRATCH/amq.body"
sed -n '/^assert_mount_quiesced() {$/,/^}$/p' "$CUTOVER" >"$FUNC"
FUNC_NC="$SCRATCH/amq.body.nocomment"
sed -e 's/[[:space:]]*#.*$//' "$FUNC" >"$FUNC_NC"

if [ -s "$FUNC" ]; then
  ok "A3-anchor: located assert_mount_quiesced() in $CUTOVER ($(wc -l <"$FUNC") lines)"
else
  fail "A3-anchor: could NOT locate assert_mount_quiesced() — every A3 verdict below would be vacuous"
fi

# The defect signature in the SUT: the probe is created under $MOUNT ...
# shellcheck disable=SC2016  # literal SUT source text, must not expand
if grep -qE 'probe="\$MOUNT/\.luks-g4-probe' "$FUNC_NC"; then
  ok "A3-site: the probe path is still composed under \$MOUNT (\$MOUNT/.luks-g4-probe.\$\$)"
else
  fail "A3-site: the probe is no longer created under \$MOUNT — see the task-1.6 block above; relocation defeats G4's positive control at :467"
fi

# ... and nothing restores the root's mtime around it. `touch -r` is the anchor: `git grep 'touch -r'`
# over the tree returns zero hits today, so its APPEARANCE inside this function is an unambiguous
# signal that the Phase 2 fix has landed.
if grep -qE 'touch[[:space:]]+-r' "$FUNC_NC"; then
  # Fixed mode. A2 still reproduces the physics; the SUT no longer runs the unbracketed shape.
  ok "A3: assert_mount_quiesced now brackets the probe with a 'touch -r' root-mtime restore (Phase 2 has landed)"
  # shellcheck disable=SC2016  # literal SUT source text, must not expand
  rm_ln="$(grep -nE '^[[:space:]]*rm -f .*\$probe' "$FUNC_NC" | tail -1 | cut -d: -f1 || true)"
  # shellcheck disable=SC2016  # literal SUT source text, must not expand
  tr_ln="$(grep -nE 'touch[[:space:]]+-r[[:space:]]+"\$ref"' "$FUNC_NC" | tail -1 | cut -d: -f1 || true)"
  if [ -n "$rm_ln" ] && [ -n "$tr_ln" ] && [ "$tr_ln" -gt "$rm_ln" ]; then
    ok "A3-order: the restore (line $tr_ln) sits AFTER the probe unlink (line $rm_ln)"
  else
    fail "A3-order: could not prove restore-after-unlink (unlink='$rm_ln' restore='$tr_ln') — a missing anchor must be loud, never a silent '' comparison"
  fi
else
  # Defect mode — today. This is the assertion that pins the bug: it holds while the script is
  # unfixed and flips the moment Phase 2 lands, at which point the branch above takes over.
  ok "A3: assert_mount_quiesced has NO root-mtime restore around the probe — the unbracketed A2 shape is what runs at 'assert_mount_quiesced pre-verify', so the '.d..t...... ./' abort is the SCRIPT's own doing (DEFECT PRESENT)"
fi

# Entry-point coupling: the perturbing call must actually sit between the pass-2 write and C1.
# Anchored on the call syntax, against a comment-stripped copy of the whole script.
BODY_NC="$SCRATCH/cutover.nocomment"
sed -e 's/[[:space:]]*#.*$//' "$CUTOVER" >"$BODY_NC"
# shellcheck disable=SC2016  # literal SUT source text, must not expand
p2_ln="$(grep -nE '^[[:space:]]*rsync -aHAX --numeric-ids --delete --checksum "\$MOUNT"/ "\$STAGING"/' "$BODY_NC" | head -1 | cut -d: -f1 || true)"
q_ln="$(grep -nE '^[[:space:]]*assert_mount_quiesced pre-verify$' "$BODY_NC" | head -1 | cut -d: -f1 || true)"
# shellcheck disable=SC2016  # literal SUT source text, must not expand
v_ln="$(grep -nE '^[[:space:]]*verify_byte_identity "\$MOUNT" "\$STAGING"$' "$BODY_NC" | head -1 | cut -d: -f1 || true)"
if [ -n "$p2_ln" ] && [ -n "$q_ln" ] && [ -n "$v_ln" ] && [ "$p2_ln" -lt "$q_ln" ] && [ "$q_ln" -lt "$v_ln" ]; then
  ok "A3-path: 'assert_mount_quiesced pre-verify' (line $q_ln) sits BETWEEN the pass-2 rsync (line $p2_ln) and C1 (line $v_ln) — the probe runs on the real abort path"
else
  fail "A3-path: could not prove the call ordering (pass2='$p2_ln' quiesce='$q_ln' verify='$v_ln') — a missing anchor is a HARNESS error, not evidence"
fi

# C1's predicate must remain untouched: this bug is fixed on the probe, never by narrowing the gate.
if grep -qE "^[[:space:]]*rsync -aHAXi --numeric-ids --checksum --delete --dry-run --out-format='%i %n'" "$BODY_NC" \
   && ! grep -qE 'omit-dir-times' "$BODY_NC"; then
  ok "A3-gate: C1's itemize invocation is unchanged and carries no --omit-dir-times (the gate is not narrowed)"
else
  fail "A3-gate: C1's verify invocation changed or gained --omit-dir-times — the gate was narrowed instead of the probe fixed"
fi

# --- Non-degeneracy floor (task 1.5) -----------------------------------------------------------
echo
if [ "$asserted" -lt "$MIN_ASSERTIONS" ]; then
  printf 'FAIL - NON-DEGENERACY FLOOR: only %d assertion(s) executed, expected at least %d.\n' "$asserted" "$MIN_ASSERTIONS"
  printf '       A suite that asserts (almost) nothing must never report green.\n'
  fails=$((fails + 1))
fi
printf 'workspaces-luks-verify-root-mtime: %d passed, %d failed (%d assertions)\n' "$pass" "$fails" "$asserted"
[ "$fails" -eq 0 ]
