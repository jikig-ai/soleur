#!/usr/bin/env bash
#
# Reproduction harness for the C1 false abort (#6733).
#
# THE DEFECT, AS IT WAS (measured, not hypothesised). `assert_mount_quiesced` (workspaces-cutover.sh,
# the G4 quiescence gate) used to open its positive-control probe by CREATING an entry in the mount:
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
# emitted exactly one line, `.d..t...... ./`, and five real cutovers safe-aborted having copied a
# byte-identical tree.
#
# C1 IS CORRECT. The probe was the defect, and it was fixed AT SOURCE: the probe is now a
# READ-open of an already-existing directory (`exec 9<"$MOUNT/workspaces"`), which lsof reports
# just as it reported the write fd and which moves no mtime at all. This suite keeps the RED
# reproduction (A2) so the mechanism stays measured rather than remembered, pins the shipped
# read-probe as the thing that actually runs (A3/A4), and pins that nobody "fixes" any future
# recurrence by narrowing C1 instead.
#
# THE INVARIANT THIS SUITE PINS (post-fix):
#     THE G4 PROBE DOES NOT MOVE $MOUNT's ROOT MTIME.
# Stated as a direct property of the shipped probe, not as a property inferred through a repair.
#
# WHAT THIS SUITE PROVES:
#   A1  clean immediately after a pass-2-equivalent rsync          (with a positive control)
#   A2  `.d..t...... ./` after the OLD create+unlink probe run VERBATIM  <- why it had to change
#   A4  the SHIPPED read-open probe moves NO mtime and leaves C1 clean   <- the fix's shape
#   A3  couples the above to the REAL script: is today's `assert_mount_quiesced` a read-probe?
#
# ---------------------------------------------------------------------------------------------
# WHY THE FD IS A READ-OPEN OF AN EXISTING DIRECTORY UNDER $MOUNT (#6733, the CTO's ruling).
#
# G4 property (c) is a POSITIVE CONTROL. `lsof` exits 1 BOTH when it finds nothing and when it
# errors, writing diagnostics only to stderr — so an errored probe is indistinguishable from a
# quiesced mount. The script closes that by holding its OWN fd under $MOUNT and REQUIRING the
# scan to report it back, or dying with `g4_probe_blind`.
#
# RELOCATING THE FD OUTSIDE $MOUNT IS STILL REJECTED, and for an unchanged reason: `lsof +D
# "$MOUNT"` enumerates open files *under the directory tree $MOUNT*. An fd opened outside that
# tree is by construction never listed, so the positive control could never match and EVERY
# invocation would take the `g4_probe_blind` die path. Relocation does not weaken the control —
# it converts the gate into an unconditional abort.
#
# WHAT CHANGED: holding a READ-ONLY fd on a path that ALREADY EXISTS under $MOUNT was previously
# rejected here, on the grounds that the holder filter subtracted the probe BY PATH
# (`grep -vF -- "$probe"`), so aiming the probe at a real path would subtract a GENUINE straggler
# holding that same path — a fail-open in the gate meant to catch stragglers. That objection was
# correct about the OLD filter and is now obsolete: the shipped filter subtracts by PID
# (`awk -v p="$$" 'NR>1 && $2 != p'`), so only THIS process's rows are removed and a straggler
# holding workspaces/ is still reported in full. The PID filter is what makes the read-probe
# admissible. The two changes are ONE change and must not be separated — a future edit that
# returns the holder filter to a path-subtraction re-opens the fail-open this paragraph describes.
#
# The read-open is zero-perturbation: it moves atime only, and C1 compares neither atime nor
# ctime. Measured directly as A4 below, and again against the real function in the mutation
# battery. Also still rejected (plan Non-Goals): keeping a CREATE and relocating it one level
# deeper, which merely moves the diff to `.d..t...... workspaces/` — a real difference C1 must
# reject, and it would additionally have to create in a directory holding user data.
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
#
# 29 is the ACTUAL count this suite executes on a capable host, not a round number below it. It was
# 17 while the suite carried a defect-mode branch that emitted `ok` when the fix was ABSENT — so the
# suite passed with AND without the fix (measured: stripping the fix still gave 18 passed / 0
# failed). Both halves of that are fixed here: the defect branches now `fail`, and the floor is the
# real count, so a case that silently stops executing reds the suite instead of sliding under a
# floor with headroom to spare.
MIN_ASSERTIONS=29

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
# A4 — THE SHIPPED SHAPE. The same interval, the same lsof stand-in, but the fd is a READ-OPEN of
# an EXISTING directory (`exec 9<"$MOUNT/workspaces"`) instead of a create+unlink. Nothing is
# created, nothing is unlinked, and NOTHING IS REPAIRED: the root's mtime is asserted unchanged as
# a DIRECT property of the probe, not inferred through a restore that could itself be wrong.
#
# The same `sleep` stand-in for the lsof scan is MANDATORY here, for the reason A2-gran measured:
# without it the whole sequence stays inside one whole second, C1 could not have seen a move
# anyway, and A4's clean result would be a granularity artifact wearing a working fix's clothes.
# With it, A2 and A4 differ in EXACTLY ONE variable — the direction of the redirection — so A4's
# clean result is attributable to that and nothing else.
# =================================================================================================
pass2 >/dev/null 2>&1
b_pre="$(stat -c %y -- "$MOUNT")"
b_sec_pre="$(stat -c %Y -- "$MOUNT")"
exec 9<"$MOUNT/workspaces"   # the SHIPPED probe: read-open an already-required directory
sleep 1.1                    # stands in for `lsof +D "$MOUNT"` (seconds on the real mount)
exec 9<&-
b_post="$(stat -c %y -- "$MOUNT")"
b_sec_post="$(stat -c %Y -- "$MOUNT")"

# Non-vacuity: A2 proved this same interval DOES move the root when the fd is a create. So the
# interval is long enough to be seen; a clean A4 is therefore about the read, not about the clock.
if [ "$b_sec_pre" = "$b_sec_post" ] && [ "$b_pre" = "$b_post" ]; then
  ok "A4-mtime: the READ-open probe left \$MOUNT's root mtime byte-identical at ns precision ($b_post) — no perturbation to repair (A2 proved the same interval moves it when the fd is a create)"
else
  fail "A4-mtime: the read-open moved the root mtime ($b_pre -> $b_post) — the shipped probe perturbs the tree C1 certifies, which is the whole defect"
fi

# The listing must ALSO be untouched — a read cannot add an entry, and this is what makes "no
# mtime move" mean "no perturbation" rather than "a perturbation that happened to be restored".
if [ ! -e "$MOUNT/.luks-g4-probe.$$" ] && [ -z "$(find "$MOUNT" -maxdepth 1 -name '.luks-g4-probe.*' -print -quit)" ]; then
  ok "A4-listing: the read-open created NO entry under \$MOUNT — nothing to unlink, so the failed-unlink and surviving-artifact failure modes cannot exist"
else
  fail "A4-listing: a probe entry exists under \$MOUNT after a read-open — the probe is still creating"
fi

rc=0; verify_into "$VOUT" "$VERR" || rc=$?
n="$(diff_n "$VOUT")"
if [ "$rc" -eq 0 ] && [ "$n" -eq 0 ]; then
  ok "A4: read-open probe => C1 verify CLEAN (0 differences) — the shipped fix shape is sufficient"
else
  fail "A4: expected a clean verify with the read-open probe, got $n difference(s) (rc=$rc): $(tr '\n' '|' <"$VOUT")"
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

# THE SHIPPED SIGNATURE — the probe is a READ-OPEN of an existing directory under $MOUNT.
# Anchored on the REDIRECTION OPERATOR, which is the entire behavioural difference between the
# defect and the fix. `<` vs `>` is one character, and it is the character that decides whether
# this gate perturbs the tree C1 certifies.
#
# NOTE ON MUTATION-RESISTANCE: asserting only "an fd is opened under $MOUNT" would be satisfied by
# `exec 9>"$MOUNT/..."` — i.e. by the defect itself. The direction is asserted POSITIVELY (a read
# redirection must be present) AND the write form is asserted ABSENT, so neither a re-introduced
# create nor a read-plus-create hybrid can satisfy this pair.
# shellcheck disable=SC2016  # literal SUT source text, must not expand
if grep -qE 'exec 9<"\$wsdir"' "$FUNC_NC"; then
  ok "A3-site: the probe READ-opens \$wsdir (exec 9<) — the fd is acquired without creating anything"
else
  fail "A3-site: no 'exec 9<\"\$wsdir\"' in assert_mount_quiesced — the shipped read-probe is not what runs"
fi

# $wsdir must actually resolve UNDER $MOUNT, or `lsof +D "$MOUNT"` can never report the fd and the
# positive control becomes an unconditional abort (see the header block). Asserted on the
# assignment, not assumed from the variable's name.
# shellcheck disable=SC2016  # literal SUT source text, must not expand
if grep -qE 'wsdir="\$MOUNT/workspaces"' "$FUNC_NC"; then
  ok "A3-under: \$wsdir is composed as \$MOUNT/workspaces — the fd is inside the tree 'lsof +D \$MOUNT' scans"
else
  fail "A3-under: \$wsdir is not composed under \$MOUNT — an fd outside that tree is never listed, so G4 would take the g4_probe_blind die path on EVERY run"
fi

# The WRITE forms must be gone. Both the redirection and the old probe-path composition: either one
# returning re-creates the #6733 abort, and the second is how it would come back (a helper that
# rebuilds the path, then writes to it elsewhere).
# shellcheck disable=SC2016  # literal SUT source text, must not expand
if grep -qE 'exec 9>' "$FUNC_NC"; then
  fail "A3-nowrite: assert_mount_quiesced still contains a WRITE redirection (exec 9>) — the probe creates an entry under \$MOUNT and C1 will abort on a byte-identical tree (#6733)"
else
  ok "A3-nowrite: no 'exec 9>' write redirection anywhere in assert_mount_quiesced"
fi
# shellcheck disable=SC2016  # literal SUT source text, must not expand
if grep -qE 'luks-g4-probe' "$FUNC_NC"; then
  fail "A3-noprobefile: the '.luks-g4-probe' entry name is back in assert_mount_quiesced — the create+unlink probe has been reintroduced"
else
  ok "A3-noprobefile: the '.luks-g4-probe' entry name is gone — nothing composes a file to create under \$MOUNT"
fi

# NO REPAIR MACHINERY. The fix is the ABSENCE of a perturbation, so the presence of a restore is
# itself a regression signal: it would mean something started perturbing again. `touch -r` is the
# anchor (`git grep 'touch -r'` over the tree is otherwise empty in this function).
if grep -qE 'touch[[:space:]]+-r' "$FUNC_NC"; then
  fail "A3-norestore: assert_mount_quiesced contains a 'touch -r' mtime restore — Option B removes the perturbation at source, so a restore means a write-probe has returned and is being compensated for rather than removed"
else
  ok "A3-norestore: no 'touch -r' restore in assert_mount_quiesced — there is no perturbation to repair (the fix is removal, not compensation)"
fi

# The helpers the bracket needed must be GONE FROM THE FILE, not merely unused. A dead
# _g4_restore_root_mtime left behind is a loaded gun for the next editor.
for _fn in _g4_restore_root_mtime _g4_depth1_fingerprint ensure_mtime_tools emit_root_mtime; do
  if grep -qE "^${_fn}\(\) \{" "$CUTOVER"; then
    fail "A3-nohelpers: the bracket helper ${_fn}() is still defined in $CUTOVER — dead repair machinery for a perturbation that no longer exists"
  else
    ok "A3-nohelpers: ${_fn}() is gone from the script"
  fi
done

# --- The PID-based holder filter (the change that MAKES the read-probe admissible) ---------------
# This is the load-bearing pair described in the header: a read-probe on a REAL path is only safe
# because the holder filter subtracts by PID, not by path. If the filter ever reverts to a path
# subtraction, a genuine straggler holding workspaces/ would be subtracted from the holder list —
# a fail-open in the exact gate whose purpose is to catch stragglers.
#
# Inverting this guard (using `==` instead of `!=`) would report ONLY our own fd as a holder and
# never a real one, so the assertion below pins the OPERATOR, not merely the presence of an awk.
# shellcheck disable=SC2016  # literal SUT source text, must not expand
if grep -qE 'holders="\$\(awk -v p="\$\$" .NR>1 && \$2 != p.' "$FUNC_NC"; then
  ok "A3-pidfilter: holders are filtered by PID with '!=' (NR>1 && \$2 != p) — our own rows are dropped, a straggler's are NOT"
else
  fail "A3-pidfilter: the holder filter is not the PID-based 'NR>1 && \$2 != p' form — a path-subtraction filter would subtract a GENUINE straggler holding workspaces/, which is what made the read-probe inadmissible before"
fi
# The old path-subtraction must be gone, or the fail-open above can coexist with the new filter.
# shellcheck disable=SC2016  # literal SUT source text, must not expand
if grep -qE 'grep -vF -- "\$probe"' "$FUNC_NC"; then
  fail "A3-nopathsub: the old path-subtraction holder filter (grep -vF -- \"\$probe\") is still present — it subtracts a genuine straggler that holds the probed path"
else
  ok "A3-nopathsub: the path-subtraction holder filter is gone"
fi

# --- No pipe in the gate (property (b), the SIGPIPE fail-open) ------------------------------------
# `producer | grep -q` under pipefail returns 141 on an early match, so `if ! ...` fails OPEN. The
# function must contain no pipe into a predicate at all. Anchored on the comment-stripped body so
# the prose explaining the trap cannot satisfy the check.
if grep -qE '\|[[:space:]]*grep -q' "$FUNC_NC"; then
  fail "A3-nopipe: assert_mount_quiesced pipes into 'grep -q' — under pipefail an early match SIGPIPEs the producer to 141 and a negative assertion fails OPEN (property (b))"
else
  ok "A3-nopipe: no '| grep -q' predicate in assert_mount_quiesced — property (b) holds"
fi

# --- The child-inheritance guard ------------------------------------------------------------------
# Bash does not set O_CLOEXEC on `exec 9<`, so a child inherits fd 9. Under the PID filter a child
# that inherited it reads as a FOREIGN straggler and would abort every cutover. Measured 2026-07-20:
# a child in the same pipeline appears in `lsof +D` output with its own inherited `9r DIR` row.
# shellcheck disable=SC2016  # literal SUT source text, must not expand
if grep -qE 'lsof \+D "\$MOUNT" 9<&-' "$FUNC_NC"; then
  ok "A3-cloexec: the lsof invocation carries '9<&-' — the child cannot inherit the probe fd and be miscounted as a straggler"
else
  fail "A3-cloexec: the lsof invocation does not close fd 9 in the child ('9<&-') — an inheriting child is indistinguishable from a foreign straggler under the PID filter, and would abort every run"
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
