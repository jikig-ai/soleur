#!/usr/bin/env bash
#
# MUTATION BATTERY for the #6733 G4 root-mtime bracket, and for C1's non-regression.
#
# WHY THIS IS A SEPARATE FILE (and not an extension of workspaces-luks-verify-root-mtime.test.sh):
# that suite is the MECHANISM harness — it proves the three rows of the plan's mechanism table
# using filesystem physics performed by the harness itself, and its assertions are narrative and
# ordered. This suite does something structurally different: it MUTATES THE SUT (it copies
# workspaces-cutover.sh into scratch, edits it against a pristine backup, and executes the REAL
# `assert_mount_quiesced` out of the mutated copy) and it MUTATES THE DESTINATION TREE to prove
# C1 still rejects. Those need a per-case teardown, a per-case landing assertion, and a shim PATH.
# Folding them in would have made the mechanism suite's floor and narrative unreadable, and would
# have coupled a RED in the battery to a RED in the reproduction. They are registered as two
# explicit steps in infra-validation.yml, so both are visible coverage.
#
# AUTHORSHIP (task 5.7e / AC26). Written by an agent that did NOT write the assertions in
# workspaces-luks-verify-root-mtime.test.sh nor the fix in workspaces-cutover.sh. The point of the
# separation is adversarial: this file exists to make the fix and its first harness look correct
# while being wrong, and to report loudly where that succeeded.
#
# ------------------------------------------------------------------------------------------------
# THE ONE RULE THAT OUTRANKS THE OTHERS (task 5.11): every itemize code below is MEASURED by
# actually running rsync in this process. Nothing is predicted from memory. A case whose icode
# cannot be produced here is recorded as UNMEASURED and asserted only on the property that WAS
# measured (that C1 rejects), never on a remembered string.
#
# HARNESS DISCIPLINE (both classes bit this repo inside the last week — see the 2026-07-19
# learnings):
#   * NEVER `producer | grep -q PATTERN` under pipefail. `grep -q` exits on first match, the
#     producer takes SIGPIPE, the pipeline returns 141, and a NEGATIVE assertion fails OPEN.
#     Every grep in this file runs against a real FILE or a herestring (task 5.7g).
#   * Every mutation carries a LANDING ASSERTION against a pristine backup, computed by an
#     instrument INDEPENDENT of rsync. A mutation whose fingerprint is baseline-identical did not
#     land and is reported UN-RUN, never caught (task 5.8).
#   * `[^\n]` in a POSIX ERE excludes the LETTER n, not newlines. This file uses `.*`.
#   * Anchors are SYNTAX, never bare tokens that also appear in the comments explaining them
#     (cq-assert-anchor-not-bare-token).
#   * Zero assertions executed is a LOUD FAILURE, never a green run.
#
# OPEN FINDINGS. Two mutations SURVIVE the shipped fix. They are reported through open_finding(),
# which prints an unmissable block and is counted in the summary, but does NOT fail the suite:
# a permanently-RED registered step is a gate everyone learns to ignore. The findings are for the
# fix author to resolve; when either is fixed, the pin below flips and this file must be updated.
# See the OPEN FINDING blocks at m19a and m21 for the measured evidence.
# ------------------------------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUTOVER="$SCRIPT_DIR/workspaces-cutover.sh"

pass=0; fails=0; asserted=0; findings=0; unmeasured=0
declare -a FINDING_LOG=() ICODE_LOG=() UNMEASURED_LOG=()

ok()   { pass=$((pass + 1));   asserted=$((asserted + 1)); printf 'ok    - %s\n' "$1"; }
fail() { fails=$((fails + 1)); asserted=$((asserted + 1)); printf 'FAIL  - %s\n' "$1"; }
note() { printf '#       %s\n' "$1"; }
# UN-RUN: a mutation that did not land. Explicitly NOT a pass — it is a null result, and the
# 2026-07-19 learning is that a null result wearing a green result's clothes is the whole defect.
unrun() { fails=$((fails + 1)); asserted=$((asserted + 1)); printf 'UN-RUN- %s\n' "$1"; }
open_finding() {
  findings=$((findings + 1)); asserted=$((asserted + 1))
  FINDING_LOG+=("$1")
  printf 'OPEN  - %s\n' "$1"
}
record_icode() { ICODE_LOG+=("$1|$2"); }
record_unmeasured() { unmeasured=$((unmeasured + 1)); UNMEASURED_LOG+=("$1|$2"); printf 'UNMEAS- %s: %s\n' "$1" "$2"; }

# Non-degeneracy floor. Bumped deliberately when cases are added; a suite that runs fewer
# assertions than it claims to own has silently lost coverage and must not report green.
MIN_ASSERTIONS=48

skip() { printf 'SKIP: %s\n' "$1"; exit 0; }

# =================================================================================================
# C0 — capability preflight (task 5.7f).
#
# GNU-vs-uutils is probed FUNCTIONALLY, not by vendor string, and the distinction is deliberate.
# The plan says "SKIP on uutils". Taken literally that would have skipped this entire battery on
# this host (Ubuntu 25.10 ships rust-coreutils 0.8.0 with NO GNU stat/touch available at all), and
# every icode below would have been UNMEASURED — trading a measured result for a remembered one,
# which is the exact failure 5.11 forbids. What actually matters is not the vendor but whether the
# two capabilities the bracket depends on hold: `stat -c %y` nanosecond fidelity and a `touch -r`
# reference round-trip that preserves them. Both are probed here and the suite SKIPs if either
# fails. The icodes themselves come from RSYNC, which is genuine upstream 3.4.1 on every host.
#
# Measured on this host (uutils 0.8.0): ns fidelity HOLDS through both `stat -c %y` and
# `touch -r`. Recorded rather than assumed, and re-probed on every run.
# =================================================================================================
command -v rsync   >/dev/null 2>&1 || skip "rsync required"
command -v lsof    >/dev/null 2>&1 || skip "lsof required — the real assert_mount_quiesced cannot run without it"
command -v python3 >/dev/null 2>&1 || skip "python3 required — it is the rsync-INDEPENDENT instrument every landing assertion is measured with"
[ -r "$CUTOVER" ] || { printf 'FAIL  - cutover script not readable at %s\n' "$CUTOVER"; exit 1; }

SCRATCH="$(mktemp -d)"        # never a fixed /tmp name: parallel worktrees are normal here
trap 'rm -rf "$SCRATCH"' EXIT

COREUTILS_VENDOR="$(stat --version 2>/dev/null | head -1 || echo unknown)"
note "coreutils in use: ${COREUTILS_VENDOR}"
note "rsync in use: $(rsync --version 2>/dev/null | head -1)"

stat -c %y -- "$SCRATCH" >/dev/null 2>&1 || skip "'stat -c %y' unsupported — the ns read-back cannot be measured here"
mkdir -p "$SCRATCH/.cap"
touch -d '@1700000000.123456789' -- "$SCRATCH/.cap" 2>/dev/null || skip "'touch -d @epoch.ns' unsupported — ns fidelity cannot be established"
: >"$SCRATCH/.capref"
touch -r "$SCRATCH/.cap" "$SCRATCH/.capref" 2>/dev/null || skip "'touch -r' unsupported — the reference round-trip cannot be measured here"
cap_want="$(stat -c %y -- "$SCRATCH/.cap")"
cap_got="$(stat -c %y -- "$SCRATCH/.capref")"
case "$cap_want" in
  *.123456789*) : ;;
  *) skip "the scratch filesystem does not retain nanosecond mtimes (got '${cap_want}') — the ns read-back guard is unobservable here, and a green run would not be evidence about prod" ;;
esac
[ "$cap_want" = "$cap_got" ] || skip "'touch -r' did not round-trip the nanosecond component ('${cap_want}' -> '${cap_got}') — coreutils here cannot express the fix's contract"
note "ns fidelity MEASURED on this host: stat -c %y and touch -r both preserve '${cap_want}'"
rm -rf "$SCRATCH/.cap" "$SCRATCH/.capref"

# Directory mtimes must actually move on create/unlink, else the whole mechanism is unobservable —
# a property of the scratch filesystem, not evidence that the defect is absent. SKIP, never pass.
_g0="$(stat -c %y -- "$SCRATCH")"
: >"$SCRATCH/.granprobe"; rm -f "$SCRATCH/.granprobe"
_g1="$(stat -c %y -- "$SCRATCH")"
[ "$_g0" != "$_g1" ] || skip "scratch filesystem does not record directory mtime changes — the defect is unobservable here"

# =================================================================================================
# Fixture (task 5.12) — shape DERIVED FROM THE PRODUCTION LAYOUT.
# On web-1 /mnt/data's top level is INFRASTRUCTURE (workspaces/ plugins/ redis/) and user identity
# lives one level deeper at workspaces/<id>/. A fixture with user dirs at depth 1 makes
# depth-sensitive checks agree with the fixture and hides their vacuity — the 2026-07-19 class.
#
# HOSTILE FILENAME (task 5.12): %n carries user workspace filenames and the tree already treats
# that channel as hostile (_vscrub). A newline-bearing name is present in the fixture AND is itself
# mutated (mH below), so the hostile path is exercised by the battery, not merely created by it.
# =================================================================================================
MOUNT="$SCRATCH/mnt"        # the SRC / rsync transfer root — `./` in the itemize output IS this
STAGING="$SCRATCH/stg"      # the DST
mkdir -p "$MOUNT" "$STAGING"
mkdir -p "$MOUNT/workspaces/ws-a/.git" "$MOUNT/workspaces/ws-b" "$MOUNT/plugins" "$MOUNT/redis/appendonlydir"
printf 'alpha\n'     >"$MOUNT/workspaces/ws-a/file.txt"
printf 'ref: main\n' >"$MOUNT/workspaces/ws-a/.git/HEAD"
printf 'notes\n'     >"$MOUNT/workspaces/ws-b/notes.md"
printf 'plugin=1\n'  >"$MOUNT/plugins/p.conf"
printf 'aof\n'       >"$MOUNT/redis/appendonlydir/appendonly.aof.1.incr.aof"
HOSTILE=$'ws-a/hostile\nname.txt'
printf 'hostile\n'   >"$MOUNT/workspaces/$HOSTILE"
if [ -f "$MOUNT/workspaces/$HOSTILE" ]; then
  ok "fixture: newline-bearing filename created under workspaces/ws-a (hostile %n channel, task 5.12)"
else
  fail "fixture: could not create a newline-bearing filename — the hostile-name case (mH) cannot run"
fi

# =================================================================================================
# The script's EXACT invocations, lifted verbatim from workspaces-cutover.sh.
# =================================================================================================
# pass-2 delta rsync (§G3, the last write to DST) — also this suite's "reconverge DST to pristine".
pass2() { rsync -aHAX --numeric-ids --delete --checksum "$MOUNT"/ "$STAGING"/; }
# The C1 itemized verify, verbatim from verify_byte_identity. stdout -> $1, stderr -> $2.
# NO PIPE: the caller greps the FILE (task 5.7g).
verify_into() {
  local vout="$1" verr="$2" rc=0
  rsync -aHAXi --numeric-ids --checksum --delete --dry-run --out-format='%i %n' \
    "$MOUNT"/ "$STAGING"/ >"$vout" 2>"$verr" || rc=$?
  return "$rc"
}
# C1's own diff counter, verbatim from workspaces-cutover.sh. Counts EVERY itemize code.
diff_n() { grep -cE '^(\*deleting|[<>ch.*][fdLDS])' "$1" || true; }

VOUT="$SCRATCH/vout"; VERR="$SCRATCH/verr"

# --- The rsync-INDEPENDENT landing instrument (task 5.8) -----------------------------------------
# Landing must NOT be measured with rsync: rsync is the system under test for m1-m12, so using it
# to prove a mutation landed would conflate "the mutation did not apply" with "the mutation applied
# but rsync cannot see it" — and the second is precisely the failure this battery hunts. This walks
# the tree with python3's os.lstat and reports type, mode, uid, gid, size, mtime_ns, symlink target,
# content hash and xattrs. NUL-safe, so the newline-bearing fixture name cannot forge a boundary.
FPPY="$SCRATCH/treefp.py"
cat >"$FPPY" <<'PYEOF'
import hashlib, os, stat as st, sys
root = sys.argv[1]
rows = []
for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
    dirnames.sort(); filenames.sort()
    for name in list(dirnames) + list(filenames):
        p = os.path.join(dirpath, name)
        rel = os.path.relpath(p, root)
        try:
            s = os.lstat(p)
        except OSError as e:
            rows.append("%s\terr=%s" % (rel, e.errno)); continue
        f = ["mode=%o" % s.st_mode, "uid=%d" % s.st_uid, "gid=%d" % s.st_gid,
             "size=%d" % s.st_size, "mtime_ns=%d" % s.st_mtime_ns]
        if st.S_ISLNK(s.st_mode):
            f.append("link=%s" % os.readlink(p))
        elif st.S_ISREG(s.st_mode):
            h = hashlib.sha256()
            with open(p, "rb") as fh:
                for chunk in iter(lambda: fh.read(65536), b""):
                    h.update(chunk)
            f.append("sha=%s" % h.hexdigest())
        try:
            xs = sorted(os.listxattr(p, follow_symlinks=False))
            for x in xs:
                f.append("xattr:%s=%s" % (x, os.getxattr(p, x, follow_symlinks=False).hex()))
        except OSError:
            pass
        rows.append(rel.replace("\n", "\\n") + "\t" + " ".join(f))
# The root itself, so a root-level mtime/mode mutation is landable evidence too.
s = os.lstat(root)
rows.append(".\tmode=%o uid=%d gid=%d mtime_ns=%d" % (s.st_mode, s.st_uid, s.st_gid, s.st_mtime_ns))
sys.stdout.write("\n".join(sorted(rows)))
PYEOF
tree_fp() { python3 "$FPPY" "$1" | sha256sum | cut -d' ' -f1; }

# -aHAX means ACLs (-A) and xattrs (-X). A filesystem without them makes the verify rsync ERROR,
# which is a harness condition, not evidence about the defect.
if ! pass2 >"$SCRATCH/p2.out" 2>"$SCRATCH/p2.err"; then
  note "pass-2 rsync stderr: $(tr '\n' ' ' <"$SCRATCH/p2.err")"
  skip "the script's exact pass-2 rsync (-aHAX) cannot run on this filesystem — ACL/xattr support missing"
fi
rc=0; verify_into "$VOUT" "$VERR" || rc=$?
if [ "$rc" -ne 0 ]; then
  note "verify rsync stderr: $(tr '\n' ' ' <"$VERR")"
  skip "the script's exact C1 verify rsync cannot run on this filesystem (rc=$rc)"
fi
n="$(diff_n "$VOUT")"
if [ "$n" -eq 0 ]; then
  ok "B0: baseline — C1 is CLEAN after the pass-2 delta rsync (every mutation below starts from this)"
else
  fail "B0: baseline is NOT clean ($n difference(s)) — every m1-m12 verdict below would be measuring leftover state: $(tr '\n' '|' <"$VOUT")"
fi

# =================================================================================================
# PART A — C1 NON-REGRESSION (m1-m12 + mH). Mutate the DESTINATION; C1 must REJECT every one.
#
# Per case: reconverge DST -> pristine, fingerprint it, mutate, RE-fingerprint (landing assertion),
# then run the real C1 verify and MEASURE the icode. Baseline-identical fingerprint => UN-RUN.
# =================================================================================================
DST_PRISTINE_FP=""
reconverge() {
  pass2 >/dev/null 2>&1
  local rc=0; verify_into "$VOUT" "$VERR" || rc=$?
  local n; n="$(diff_n "$VOUT")"
  DST_PRISTINE_FP="$(tree_fp "$STAGING")"
  [ "$rc" -eq 0 ] && [ "$n" -eq 0 ]
}

# dst_case <id> <description> <mutation-command...>
# Runs the whole per-case protocol and MEASURES the icode. Never predicts one.
dst_case() {
  local id="$1" desc="$2"; shift 2
  if ! reconverge; then
    unrun "$id: could not reconverge DST to a pristine baseline before mutating — verdict would measure leftover state"
    return
  fi
  local before="$DST_PRISTINE_FP"
  if ! "$@" >"$SCRATCH/mut.err" 2>&1; then
    unrun "$id ($desc): the mutation command itself FAILED: $(tr '\n' ' ' <"$SCRATCH/mut.err")"
    return
  fi
  local after; after="$(tree_fp "$STAGING")"
  if [ "$before" = "$after" ]; then
    unrun "$id ($desc): DST fingerprint is BASELINE-IDENTICAL — the mutation did NOT land. This is a null result, not a caught one (task 5.8)."
    return
  fi
  ok "$id-land: the mutation LANDED — DST fingerprint differs from the pristine backup (${before:0:12} -> ${after:0:12})"
  local rc=0; verify_into "$VOUT" "$VERR" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "$id ($desc): the verify rsync itself errored (rc=$rc) — C1's verdict cannot be attributed to the mutation: $(tr '\n' ' ' <"$VERR")"
    return
  fi
  local n; n="$(diff_n "$VOUT")"
  local codes; codes="$(tr '\n' '|' <"$VOUT" | sed 's/|$//')"
  if [ "$n" -ge 1 ]; then
    ok "$id ($desc): C1 REJECTS — $n difference(s). MEASURED: $codes"
    record_icode "$id" "$codes"
  else
    fail "$id ($desc): C1 did NOT reject a landed destination mutation — the gate has a hole here. MUTATION SURVIVED."
    record_icode "$id" "SURVIVED — C1 emitted nothing"
  fi
}

# --- m1: content byte change, same size ---
m1() { printf 'blpha\n' >"$STAGING/workspaces/ws-a/file.txt"; }
dst_case m1 "content byte change, same size" m1

# --- m2: size change ---
m2() { printf 'plugin=1 and more\n' >"$STAGING/plugins/p.conf"; }
dst_case m2 "size change" m2

# --- m3: permission change ---
m3() { chmod 0600 "$STAGING/workspaces/ws-a/file.txt"; }
dst_case m3 "permission change" m3

# --- m4: NON-ROOT directory mtime change. THE SHARPEST CASE (task 5.2): identical icode shape to
#     the tolerance that was proposed and rejected, different path. This is what a blanket
#     --omit-dir-times or a loose icode match would have swallowed. Permanent guard. ---
m4() { touch -d '2020-01-01 00:00:00' "$STAGING/workspaces"; }
dst_case m4 "NON-ROOT dir mtime change (guards against a future --omit-dir-times)" m4

# --- m5: deleted file in DST ---
m5() { rm -f "$STAGING/plugins/p.conf"; }
dst_case m5 "file deleted from DST" m5

# --- m6: added file in a DST subdir ---
m6() { printf 'rogue\n' >"$STAGING/workspaces/ws-a/rogue.txt"; }
dst_case m6 "rogue file added to a DST subdir" m6

# --- m7: owner/group change. The plan recorded this UNMEASURED because chgrp to the SAME group is
#     a no-op. Established properly here: pick a group we are actually a member of that is NOT the
#     file's current group. If no such group exists, record UNMEASURED — never a predicted icode. ---
CUR_GID="$(python3 -c 'import os,sys; print(os.lstat(sys.argv[1]).st_gid)' "$STAGING/workspaces/ws-b/notes.md")"
ALT_GID=""
for g in $(id -G); do [ "$g" != "$CUR_GID" ] && { ALT_GID="$g"; break; }; done
if [ -n "$ALT_GID" ]; then
  m7() { chgrp "$ALT_GID" "$STAGING/workspaces/ws-b/notes.md"; }
  dst_case m7 "group ownership change (gid $CUR_GID -> $ALT_GID)" m7
else
  record_unmeasured m7 "no alternate group available to this uid — a chgrp to the same gid is a no-op, and a predicted icode is the false-result class the 2026-07-19 learning names"
fi

# --- m8: file replaced by a directory ---
m8() { rm -f "$STAGING/plugins/p.conf"; mkdir -p "$STAGING/plugins/p.conf"; }
dst_case m8 "file replaced by a directory" m8

# --- m9: symlink swap ---
m9() { rm -f "$STAGING/workspaces/ws-a/file.txt"; ln -s /etc/hostname "$STAGING/workspaces/ws-a/file.txt"; }
dst_case m9 "regular file replaced by a symlink" m9

# --- m10: xattr change. The plan recorded this UNMEASURED because setfattr was absent from the
#     sandbox. Established here through python3's os.setxattr instead of predicting a code. If the
#     filesystem refuses user xattrs, it is recorded UNMEASURED rather than asserted. ---
if python3 -c 'import os,sys; os.setxattr(sys.argv[1], "user.g4probe", b"1")' "$STAGING/plugins/p.conf" 2>/dev/null; then
  python3 -c 'import os,sys; os.removexattr(sys.argv[1], "user.g4probe")' "$STAGING/plugins/p.conf" 2>/dev/null || true
  m10() { python3 -c 'import os,sys; os.setxattr(sys.argv[1], "user.g4probe", b"mutated")' "$STAGING/plugins/p.conf"; }
  dst_case m10 "extended-attribute change on a DST file" m10
else
  record_unmeasured m10 "this filesystem/mount refuses user.* xattrs (no user_xattr, or a container overlay) — the icode cannot be produced here and must not be guessed"
fi

# --- m11 / m12 (task 5.3): the `./` line IS PRESENT and C1 must STILL reject. These are the cases
#     a "tolerate .d..t...... ./" narrowing would have eroded: the root line arrives WITH a
#     companion, so tolerating the root line alone would not be a blanket — but tolerating it as a
#     line-level filter would still have to be proven not to swallow these. Measured, not argued. ---
m11() { printf 'rogue\n' >"$STAGING/rogue"; }
dst_case m11 "rogue entry added at the DST ROOT (./ line present, must still reject)" m11
m12() { rm -rf "$STAGING/redis"; }
dst_case m12 "infra dir deleted from the DST ROOT (./ line present, must still reject)" m12

# The `./` line really is present in m11/m12 — otherwise "the tolerance must never become a
# blanket" is proven against cases that never carried the root line in the first place.
for pair in m11 m12; do
  case "$pair" in
    m11) reconverge >/dev/null 2>&1; printf 'rogue\n' >"$STAGING/rogue" ;;
    m12) reconverge >/dev/null 2>&1; rm -rf "$STAGING/redis" ;;
  esac
  rc=0; verify_into "$VOUT" "$VERR" || rc=$?
  root_line="$(grep -cE '^\.d\.\.t\.\.\.\.\.\. \./$' "$VOUT" || true)"
  total="$(diff_n "$VOUT")"
  if [ "$rc" -eq 0 ] && [ "$root_line" -eq 1 ] && [ "$total" -gt 1 ]; then
    ok "$pair-root: the './' root line IS present AND is not the only difference ($total total) — C1 rejects with the root line in play, so a root-line tolerance would not have been a safe blanket"
  else
    fail "$pair-root: expected the './' line plus at least one companion (root_line=$root_line total=$total rc=$rc) — this case does not actually exercise the tolerance hazard it exists for: $(tr '\n' '|' <"$VOUT")"
  fi
done

# --- mH: mutate the HOSTILE newline-bearing filename itself (task 5.12). The fixture merely
#     creating it proves nothing about the diagnostic path; mutating it forces rsync's %n escaping
#     through C1's counter and through the itemize output the operator actually reads. ---
mH() { printf 'tampered\n' >"$STAGING/workspaces/$HOSTILE"; }
dst_case mH "content change on the newline-bearing hostile filename" mH
reconverge >/dev/null 2>&1; printf 'tampered\n' >"$STAGING/workspaces/$HOSTILE"
rc=0; verify_into "$VOUT" "$VERR" || rc=$?
hn="$(diff_n "$VOUT")"
if [ "$rc" -eq 0 ] && [ "$hn" -eq 1 ]; then
  ok "mH-count: C1's diff counter reports exactly 1 difference for the newline-bearing path — rsync's %n escaping did not split it into two phantom rows"
else
  fail "mH-count: expected exactly 1 counted difference for the hostile filename, got $hn (rc=$rc) — a newline in %n is inflating or hiding the count: $(tr '\n' '|' <"$VOUT")"
fi

# =================================================================================================
# PART B — THE FIX ITSELF. Executes the REAL `assert_mount_quiesced` out of a mutated COPY of
# workspaces-cutover.sh (task 5.10 — entrypoint coverage, not a reimplementation).
#
# The script is `set -uo pipefail` with no -e and its die() calls `exit 1`, so each case runs in a
# `bash -c` SUBPROCESS that sources the copy and calls the real function. That is also the seam the
# script's own sourced-detection guard exists for: sourcing returns after every function is defined
# but before `trap cleanup EXIT` and the main body.
# =================================================================================================
SUT="$SCRATCH/sut.sh"
SUT_PRISTINE="$SCRATCH/sut.pristine.sh"
cp "$CUTOVER" "$SUT_PRISTINE"
SHIMBIN="$SCRATCH/shimbin"

# sut_reset — restore the SUT from the pristine backup. Every SUT mutation is applied to a fresh
# copy of THIS file, never to $CUTOVER and never to a previously mutated copy.
sut_reset() { cp "$SUT_PRISTINE" "$SUT"; }

# sut_mutate <old> <new> — apply a SUT mutation with a hard anchor assertion and a landing
# assertion against the pristine backup (task 5.8). A missing anchor is LOUD, never a silent no-op.
sut_mutate() {
  python3 - "$SUT" "$1" "$2" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if old not in s:
    sys.stderr.write("ANCHOR MISSING — the mutation cannot land: %r\n" % old); sys.exit(3)
if s.count(old) != 1:
    sys.stderr.write("ANCHOR AMBIGUOUS — %d occurrences, refusing a partial mutation\n" % s.count(old)); sys.exit(4)
open(p, "w").write(s.replace(old, new, 1))
PY
  local prc=$?
  [ "$prc" -eq 0 ] || return "$prc"
  if cmp -s "$SUT_PRISTINE" "$SUT"; then return 9; fi     # baseline-identical => did NOT land
  return 0
}

# make_lsof_shim <body> — a PATH-shadowing lsof that runs <body> INSIDE the probe bracket (it is
# invoked between `exec 9>` and the fingerprint re-check) and then reports the script's real probe
# fd back, so the positive control passes unless the case wants it to fail.
make_lsof_shim() {
  mkdir -p "$SHIMBIN"
  { printf '#!/usr/bin/env bash\n'
    # shellcheck disable=SC2016  # literal SUT source text / shim body, must not expand
    printf 'ln="$2"\n'
    printf '%s\n' "$1"
    printf 'echo "COMMAND PID USER FD TYPE DEVICE SIZE NODE NAME"\n'
    # shellcheck disable=SC2016  # literal SUT source text / shim body, must not expand
    printf 'for p in "$ln"/.luks-g4-probe.*; do [ -e "$p" ] && echo "bash 1 u 9w REG 0,0 0 1 $p"; done\n'
    printf 'exit 0\n'; } >"$SHIMBIN/lsof"
  chmod +x "$SHIMBIN/lsof"
}

# run_amq <use-shim:yes|no> — run the REAL assert_mount_quiesced against $MOUNT out of $SUT.
# Sets AMQ_RC and AMQ_OUT.
AMQ_RC=0; AMQ_OUT=""
run_amq() {
  local p="$PATH"
  [ "$1" = yes ] && p="$SHIMBIN:$PATH"
  AMQ_OUT="$(PATH="$p" WORKSPACES_MOUNT="$MOUNT" WORKSPACES_STAGING="$STAGING" \
    bash -c '. "$1"; assert_mount_quiesced pre-verify; echo AMQ_RETURNED_OK' _ "$SUT" 2>&1)"
  AMQ_RC=$?
}
# Negative/positive assertions on the captured output use a HERESTRING, never `echo | grep -q`
# (task 5.7g): under pipefail an early match SIGPIPEs the producer to 141 and a negative assertion
# fails OPEN.
out_has()  { grep -qE -- "$1" <<<"$AMQ_OUT"; }

# --- m13 / m14: THE NON-VACUITY PAIR (task 5.4) ---------------------------------------------------
# The shim sleeps 1.1s in place of `lsof +D "$MOUNT"`, which on the real /workspaces volume is a
# multi-second recursive scan. That is not cosmetic: rsync compares directory mtimes at WHOLE-SECOND
# granularity (measured as A2-gran in workspaces-luks-verify-root-mtime.test.sh, and re-measured as
# m17 below), so without the sleep the probe's create and unlink land inside one second, C1 could
# not see the move ANYWAY, and m13's clean result would be a granularity artifact wearing a working
# fix's clothes. The sleep makes m14's RED attributable to the missing restore and m13's GREEN
# attributable to the restore.
make_lsof_shim 'sleep 1.1'

sut_reset
pass2 >/dev/null 2>&1
m13_pre="$(stat -c %y -- "$MOUNT")"
run_amq yes
m13_post="$(stat -c %y -- "$MOUNT")"
if [ "$AMQ_RC" -eq 0 ] && out_has 'AMQ_RETURNED_OK'; then
  ok "m13-run: the REAL assert_mount_quiesced ran to completion through the unmodified fix (rc=0)"
else
  fail "m13-run: assert_mount_quiesced did not complete (rc=$AMQ_RC) — every m13 verdict below is about a run that did not happen: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 400)"
fi
if [ "$m13_pre" = "$m13_post" ]; then
  ok "m13-mtime: \$MOUNT's root mtime is byte-identical across the real G4 bracket ($m13_post)"
else
  fail "m13-mtime: the root mtime moved across the bracket ($m13_pre -> $m13_post) — the restore did not hold"
fi
if out_has 'SOLEUR_WORKSPACES_LUKS_ROOT_MTIME .*probe_restored=yes' && out_has 'src_moved_after_probe=no'; then
  ok "m13-telemetry: the run emits probe_restored=yes and src_moved_after_probe=no"
else
  fail "m13-telemetry: expected probe_restored=yes + src_moved_after_probe=no in the emitted marker: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 300)"
fi
rc=0; verify_into "$VOUT" "$VERR" || rc=$?
n="$(diff_n "$VOUT")"
if [ "$rc" -eq 0 ] && [ "$n" -eq 0 ]; then
  ok "m13: fix APPLIED — C1 is CLEAN after the real G4 probe ran between pass-2 and the verify"
else
  fail "m13: expected a clean C1 with the fix applied, got $n difference(s) (rc=$rc): $(tr '\n' '|' <"$VOUT")"
fi

# m14 — revert the fix by neutering the SUCCESS-PATH restore only. The four die-path calls are left
# in place deliberately: this must isolate "the restore did not run on the path C1 follows", not
# delete the whole bracket (which would also delete the fingerprint and the read-back and make the
# RED unattributable).
sut_reset
# shellcheck disable=SC2016  # literal SUT source text / shim body, must not expand
if sut_mutate '  _g4_restore_root_mtime "$mref" "$phase"
  mt_post=' '  : "REVERTED BY m14 — no restore on the success path"; rm -f "$mref"
  mt_post='; then
  ok "m14-land: the SUT mutation LANDED — the success-path restore call is replaced in the copy (anchor found exactly once, file differs from the pristine backup)"
  pass2 >/dev/null 2>&1
  m14_sec_pre="$(stat -c %Y -- "$MOUNT")"
  run_amq yes
  m14_sec_post="$(stat -c %Y -- "$MOUNT")"
  if [ "$m14_sec_pre" != "$m14_sec_post" ]; then
    ok "m14-sec: the unbracketed probe moved \$MOUNT's root mtime across a WHOLE SECOND ($m14_sec_pre -> $m14_sec_post) — C1 can see this move, so a RED below is the missing restore and not a coin flip"
  else
    unrun "m14-sec: create and unlink landed in the same whole second — C1 cannot see this move, so m14's result carries no information (task 5.8)"
  fi
  rc=0; verify_into "$VOUT" "$VERR" || rc=$?
  root_line="$(grep -cE '^\.d\.\.t\.\.\.\.\.\. \./$' "$VOUT" || true)"
  n="$(diff_n "$VOUT")"
  if [ "$rc" -eq 0 ] && [ "$root_line" -eq 1 ] && [ "$n" -eq 1 ]; then
    ok "m14: fix REVERTED — C1 emits exactly '.d..t...... ./' and nothing else. The battery is NON-VACUOUS: m13's green is caused by the restore."
    record_icode m14 ".d..t...... ./"
  else
    fail "m14: expected exactly one '.d..t...... ./' with the restore reverted, got root_line=$root_line total=$n (rc=$rc) — m13's green is then NOT attributable to the fix: $(tr '\n' '|' <"$VOUT")"
  fi
else
  fail "m14: the SUT mutation did not land (rc=$?) — a missing/ambiguous anchor must be LOUD, never a silent skip that reports green"
fi

# --- m15: the restore fires on a die path AND does not preempt the original die -------------------
# Forced through the g4_probe_blind path by a shim lsof that exits 0 having reported NO probe line.
# This is an ENVIRONMENT mutation, not a SUT mutation: the die path is reached by the script's own
# unmodified logic, which is what makes the verdict about the shipped code.
sut_reset
mkdir -p "$SHIMBIN"
{ printf '#!/usr/bin/env bash\n'
  printf 'echo "COMMAND PID USER FD TYPE DEVICE SIZE NODE NAME"\n'
  printf 'exit 0\n'; } >"$SHIMBIN/lsof"
chmod +x "$SHIMBIN/lsof"
m15_pre="$(stat -c %y -- "$MOUNT")"
run_amq yes
m15_post="$(stat -c %y -- "$MOUNT")"
if [ "$AMQ_RC" -ne 0 ] && out_has 'g4_probe_blind'; then
  ok "m15-path: the g4_probe_blind die path was actually taken (rc=$AMQ_RC) — the case is not vacuous"
else
  unrun "m15-path: the blind die path was NOT reached (rc=$AMQ_RC) — every m15 verdict below would be about a path that did not run: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 300)"
fi
if [ "$m15_pre" = "$m15_post" ]; then
  ok "m15-restore: the best-effort restore FIRED on the die path — \$MOUNT's root mtime is byte-identical across an aborting run ($m15_post)"
else
  fail "m15-restore: the root mtime was left perturbed on the die path ($m15_pre -> $m15_post) — an abort that corrupts the tree it was certifying"
fi
# The point of best-effort mode: the ORIGINAL, more informative reason must still reach the operator.
if out_has 'the G4 straggler probe is BLIND, not clean'; then
  ok "m15-reason: the ORIGINAL die reason ('BLIND, not clean') reached the operator — the restore did not preempt it"
else
  fail "m15-reason: the original G4 verdict did NOT reach the operator — a restore-skew die replaced a diagnosable abort, re-creating the #6604 undiagnosable-abort class: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 400)"
fi
if out_has 'the G4 root-mtime restore did NOT land'; then
  fail "m15-nopreempt: the STRICT restore-skew die fired on a die path — best-effort mode is not in force and the informative abort was replaced"
else
  ok "m15-nopreempt: no strict restore-skew die on the abort path — best-effort mode holds"
fi

# --- m16: instrument unavailable => the gate REFUSES (task 5.5 / AC7) -----------------------------
# The unifying question from the 2026-07-19 learning: if this instrument were unavailable, does the
# guard REFUSE or PROCEED? Built by symlinking every PATH entry EXCEPT the excluded tool, so the
# absence is real rather than a stubbed `command -v` and lsof is still present (ensure_lsof runs
# first and must not be the thing that fires).
sut_reset
NOSTAT="$SCRATCH/nostat"; mkdir -p "$NOSTAT"
IFS=':' read -r -a _pdirs <<<"$PATH"
for d in "${_pdirs[@]}"; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    b="$(basename -- "$f")"
    [ "$b" = stat ] && continue
    [ -e "$NOSTAT/$b" ] && continue
    [ -x "$f" ] && ln -s "$f" "$NOSTAT/$b" 2>/dev/null
  done
done
if [ -x "$NOSTAT/lsof" ] && [ ! -e "$NOSTAT/stat" ]; then
  ok "m16-land: the instrument-stripped PATH LANDED — lsof present, stat absent (so ensure_lsof cannot be what fires)"
  m16_out="$(PATH="$NOSTAT" WORKSPACES_MOUNT="$MOUNT" \
    bash -c '. "$1"; assert_mount_quiesced pre-verify; echo AMQ_RETURNED_OK' _ "$SUT" 2>&1)"
  m16_rc=$?
  if [ "$m16_rc" -ne 0 ] && grep -qE -- 'g4_mtime_tool_missing' <<<"$m16_out" \
     && grep -qE -- "required probe 'stat' is not on PATH" <<<"$m16_out"; then
    ok "m16: stat unavailable => the gate REFUSES (rc=$m16_rc, g4_mtime_tool_missing) — it does not proceed with an unverifiable bracket"
  else
    fail "m16: with stat absent the gate did NOT refuse (rc=$m16_rc) — a gate that evaporates when a binary is missing is the #6588 silent-failure class: $(tr '\n' '|' <<<"$m16_out" | tail -c 400)"
  fi
  if grep -qE -- 'AMQ_RETURNED_OK' <<<"$m16_out"; then
    fail "m16-noproceed: assert_mount_quiesced RETURNED SUCCESSFULLY with its instruments missing — fail-open"
  else
    ok "m16-noproceed: the function never returned success with its instruments missing"
  fi
else
  unrun "m16: could not build an instrument-stripped PATH (lsof present=$([ -x "$NOSTAT/lsof" ] && echo y || echo n), stat absent=$([ ! -e "$NOSTAT/stat" ] && echo y || echo n)) — the case did not run"
fi

# --- m17: FALSIFIED. RECORDED, NOT ASSERTED. -----------------------------------------------------
# The plan (AC8) claims a %Y-precision restore still emits the diff, "pinning ns precision". It does
# not. rsync 3.4.1 compares directory mtimes at WHOLE-SECOND granularity, so a whole-second-accurate
# restore is SUFFICIENT for C1. Re-measured here rather than cited, because a falsification carried
# forward on a citation is the same unmeasured claim in the other direction. `%y` remains the right
# choice for the fix (strictly more faithful, costs nothing) — but it must not be asserted as an
# icode requirement, and the fix's ns read-back is what actually pins it at runtime (see m20).
pass2 >/dev/null 2>&1
m17_base="$(stat -c %Y -- "$MOUNT")"
touch -d "@${m17_base}.500000000" -- "$MOUNT"
m17_moved="$(stat -c %y -- "$MOUNT")"
rc=0; verify_into "$VOUT" "$VERR" || rc=$?
m17_n="$(diff_n "$VOUT")"
if [ "$rc" -eq 0 ] && [ "$m17_n" -eq 0 ]; then
  ok "m17-FALSIFIED (MEASURED HERE): a SUB-SECOND-only root mtime move ($m17_moved) is INVISIBLE to C1 — rsync compares dir mtimes per whole second, so the plan's m17 is false and is deliberately NOT encoded as an assertion"
  record_icode m17 "FALSIFIED — sub-second-only root move emits NOTHING (0 differences)"
else
  fail "m17-FALSIFIED: expected a sub-second-only root move to be invisible, got $m17_n difference(s) — the falsification itself is wrong on this rsync and the plan's m17 must be revisited: $(tr '\n' '|' <"$VOUT")"
fi

# --- m18: a residual perturbation AFTER the probe bracket still aborts C1 (task 5.7 / AC9) --------
# This is the signal the fix must NOT blind: the restore must undo OUR probe, never a foreign write
# that lands after the bracket closes.
sut_reset
make_lsof_shim 'sleep 1.1'
pass2 >/dev/null 2>&1
run_amq yes
if [ "$AMQ_RC" -eq 0 ]; then
  ok "m18-pre: the bracket completed cleanly first (rc=0) — the abort below is attributable to the POST-bracket write, not to the probe"
else
  unrun "m18-pre: assert_mount_quiesced did not complete (rc=$AMQ_RC) — m18 cannot isolate a post-bracket perturbation"
fi
m18_base="$(stat -c %Y -- "$MOUNT")"
touch -d "@$((m18_base + 2))" -- "$MOUNT"        # whole-second move: C1 can see it (see m17)
m18_after="$(stat -c %Y -- "$MOUNT")"
if [ "$m18_base" != "$m18_after" ]; then
  ok "m18-land: the residual post-bracket perturbation LANDED and crossed a whole second ($m18_base -> $m18_after)"
else
  unrun "m18-land: the residual perturbation did not land — the case did not run"
fi
rc=0; verify_into "$VOUT" "$VERR" || rc=$?
root_line="$(grep -cE '^\.d\.\.t\.\.\.\.\.\. \./$' "$VOUT" || true)"
if [ "$rc" -eq 0 ] && [ "$root_line" -eq 1 ]; then
  ok "m18: a residual root perturbation AFTER the bracket still ABORTS C1 ('.d..t...... ./') — the fix restores its own probe without blinding the foreign-writer signal"
  record_icode m18 ".d..t...... ./ (post-bracket foreign write — correctly NOT absorbed)"
else
  fail "m18: a post-bracket root perturbation did NOT reach C1 (root_line=$root_line rc=$rc) — the fix has blinded the residual-writer signal it promised to preserve: $(tr '\n' '|' <"$VOUT")"
fi

# --- m19: the depth-1 listing fingerprint. TWO variants, because the shipped claim is broader than
#     the shipped behaviour and only measurement separates them. ------------------------------------
# m19b first (the case that WORKS), so m19a's failure cannot be confused with a dead fingerprint.
sut_reset
# shellcheck disable=SC2016  # literal SUT source text / shim body, must not expand
make_lsof_shim ': > "$ln/foreign.keep"'          # an UNMATCHED create: a NET listing change
pass2 >/dev/null 2>&1
run_amq yes
if [ "$AMQ_RC" -ne 0 ] && out_has 'g4_bracket_listing_changed'; then
  ok "m19b: an UNMATCHED in-bracket create (net listing change) is CAUGHT by the depth-1 fingerprint — it dies with g4_bracket_listing_changed and refuses to stamp the root mtime over a real concurrent write"
else
  fail "m19b: the depth-1 fingerprint did NOT catch a net listing change inside the bracket (rc=$AMQ_RC) — the fingerprint is inert: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 400)"
fi
rm -f "$MOUNT/foreign.keep"

# m19a — the case the plan and the in-code comment actually CLAIM: a foreign create+delete PAIR
# landing inside the bracket, "structurally identical to the probe's own".
sut_reset
# shellcheck disable=SC2016  # literal SUT source text / shim body, must not expand
make_lsof_shim ': > "$ln/foreign.tmp"; sleep 1.1; rm -f "$ln/foreign.tmp"'
pass2 >/dev/null 2>&1
m19a_pre="$(stat -c %y -- "$MOUNT")"
run_amq yes
m19a_post="$(stat -c %y -- "$MOUNT")"
if [ -e "$MOUNT/foreign.tmp" ]; then
  unrun "m19a: the foreign entry survived the shim — this is not a create+delete PAIR and the case did not run"
elif [ "$AMQ_RC" -ne 0 ] && out_has 'g4_bracket_listing_changed'; then
  ok "m19a: a MATCHED in-bracket create+delete pair is caught by the fingerprint — the shipped comment's claim holds (if you are reading this after a fix, the OPEN FINDING below has been resolved)"
else
  open_finding "m19a SURVIVES — the depth-1 listing fingerprint does NOT catch a matched in-bracket create+delete pair. MEASURED: assert_mount_quiesced returned rc=$AMQ_RC (success), and \$MOUNT's root mtime was stamped back to $m19a_post (pre=$m19a_pre), erasing the foreign writer's only evidence. This is the exact case the in-code comment claims to cover: _g4_depth1_fingerprint's header says it exists so that 'a create+delete pair landing inside the bracket' does not 'have its evidence overwritten by our own restore', and assert_mount_quiesced's bracket comment says a 'foreign create+delete PAIR ... is invisible to mtime alone once we restore, so this is the only thing standing between us and stamping over someone else's write'. It is not: fp_pre and fp_post are both taken with no probe present, so a MATCHED pair is net-zero and the fingerprint compares equal by construction. The fingerprint catches NET listing changes (m19b) only. The residual blind spot is therefore strictly larger than the comment admits: not just a bare 'touch \$MOUNT', but any foreign create+delete pair. Fix the COMMENT (narrow the claim to net listing changes and widen the recorded residual), or fix the MECHANISM (e.g. fingerprint the root's mtime continuously, or refuse to restore when \$MOUNT's mtime moved more than the probe's own two operations can account for)."
  record_icode m19a "SURVIVED — rc=0, foreign create+delete pair absorbed by the restore"
fi

# --- m20: a TRUNCATING restore is caught by the read-back (task 5.7c / AC18) ----------------------
# A `touch` that exits 0 but writes a coarser stamp is not a failure exit, so an exit-status-only
# guard would pass while the root stayed perturbed. Simulated by mutating the restore primitive to a
# whole-second form that still exits 0.
sut_reset
pass2 >/dev/null 2>&1
touch -d '@1784500000.123456789' -- "$MOUNT"     # force a NON-ZERO ns component ...
m20_ns="$(stat -c %y -- "$MOUNT")"
case "$m20_ns" in
  *.123456789*) ok "m20-pre: \$MOUNT carries a non-zero nanosecond component ($m20_ns) — a whole-second truncation is therefore observable, measured rather than assumed" ;;
  *) unrun "m20-pre: could not establish a non-zero ns component (got $m20_ns) — a truncating restore would be indistinguishable from a faithful one and the case cannot run" ;;
esac
# shellcheck disable=SC2016  # literal SUT source text / shim body, must not expand
if sut_mutate 'touch -r "$ref" "$MOUNT" 2>/dev/null || true' 'touch -d "@$(stat -c %Y "$ref")" "$MOUNT" 2>/dev/null || true'; then
  ok "m20-land: the SUT mutation LANDED — the restore primitive now writes a whole-second stamp and still exits 0"
  make_lsof_shim ':'
  run_amq yes
  if [ "$AMQ_RC" -ne 0 ] && out_has 'g4_root_mtime_restore_skew' && out_has 'the G4 root-mtime restore did NOT land'; then
    ok "m20: a TRUNCATING restore that exits 0 is CAUGHT by the read-back — dies with g4_root_mtime_restore_skew. probe_restored is MEASURED, not asserted."
  else
    fail "m20: a truncating restore was NOT caught (rc=$AMQ_RC) — the read-back guard is inert and the defect can re-enter invisibly: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 400)"
  fi
  if out_has 'probe_restored=yes'; then
    fail "m20-notelemetry: the run still emitted probe_restored=yes after a failed restore — the telemetry asserts a property the read-back just disproved"
  else
    ok "m20-notelemetry: no probe_restored=yes was emitted on the skew path — the emitter is downstream of the guard, so it cannot certify a restore that did not land"
  fi
else
  fail "m20: the SUT mutation did not land — a missing/ambiguous anchor must be LOUD, never a silent skip"
fi

# --- m21: a failed unlink and the restore (task 5.7d / AC19) --------------------------------------
# Simulated by removing "$probe" from the unlink so the entry survives, which is what an EPERM /
# immutable / EROFS unlink failure produces.
sut_reset
# shellcheck disable=SC2016  # literal SUT source text / shim body, must not expand
if sut_mutate 'rm -f "$lout" "$lerr" "$probe"

  # The unlink must have LANDED' 'rm -f "$lout" "$lerr"

  # The unlink must have LANDED'; then
  ok "m21-land: the SUT mutation LANDED — the probe is no longer unlinked, simulating a failed unlink"
  make_lsof_shim ':'
  pass2 >/dev/null 2>&1
  m21_pre="$(stat -c %y -- "$MOUNT")"
  run_amq yes
  m21_post="$(stat -c %y -- "$MOUNT")"
  m21_left="$(find "$MOUNT" -maxdepth 1 -name '.luks-g4-probe.*' 2>/dev/null | wc -l)"
  if [ "$m21_left" -ge 1 ]; then
    ok "m21-pre: the probe entry really did survive ($m21_left present) — the guard's precondition is measured, not assumed"
  else
    unrun "m21-pre: no surviving probe entry — the failed-unlink case did not run"
  fi
  if [ "$AMQ_RC" -ne 0 ] && out_has 'g4_probe_unremovable' \
     && out_has 'the G4 probe file survived its own unlink'; then
    ok "m21: a surviving probe entry BLOCKS the run — the guard fires with g4_probe_unremovable and the gate refuses (fail-closed)"
  else
    fail "m21: a surviving probe entry did NOT stop the run (rc=$AMQ_RC) — the gate would certify a tree still carrying its own artifact: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 400)"
  fi
  # The second half of m21, and the part the task actually asks about: does the surviving probe
  # BLOCK the restore? Measured against the mtime, not against the message.
  if [ "$m21_pre" = "$m21_post" ]; then
    open_finding "m21 PARTIALLY SURVIVES — the surviving-probe guard fires, but it does NOT block the restore, and its own die message says it does. MEASURED: \$MOUNT's root mtime is UNCHANGED across the run ($m21_post), i.e. the restore RAN, while the die message reads 'refusing to restore \$MOUNT's mtime over a tree that still carries our artifact'. The code is workspaces-cutover.sh's g4_probe_unremovable branch: it calls _g4_restore_root_mtime ... best-effort on the line BEFORE the die that claims it refused to. Not fail-open — the run still aborts and C1 never certifies anything — but the operator (and any forensic reader of the tree afterwards) is told the mtime was left perturbed when it was stamped back, over a root that still carries a probe artifact. Either drop the restore call from this branch to match AC19's '[ ! -e \$probe ] || die sits between unlink and restore', or reword the die to say what it does."
    record_icode m21 "guard fires; restore NOT blocked (message/behaviour mismatch)"
  else
    ok "m21-norestore: the surviving probe BLOCKED the restore — \$MOUNT's mtime was left perturbed ($m21_pre -> $m21_post), matching the die message's claim"
  fi
  rm -f "$MOUNT"/.luks-g4-probe.*
else
  fail "m21: the SUT mutation did not land — a missing/ambiguous anchor must be LOUD, never a silent skip"
fi

# =================================================================================================
# PART C — CALL-ORDER ASSERTIONS AGAINST THE FILE (task 5.9 / AC10).
#
# Data-only and behaviour-only mutations cannot catch a MISORDERED restore: every case in Part B
# would stay green if the restore were moved above the unlink on a run where the unlink happened to
# succeed anyway. The only seam that can see ordering is the file itself. Anchored on SYNTAX against
# a COMMENT-STRIPPED copy — a bare-token grep matching the comment that EXPLAINS the trap is a
# documented recurring error here (cq-assert-anchor-not-bare-token). Every missing anchor is LOUD:
# there is no silent '' comparison anywhere below.
# =================================================================================================
FUNC="$SCRATCH/amq.body"
sed -n '/^assert_mount_quiesced() {$/,/^}$/p' "$CUTOVER" | sed -e 's/[[:space:]]*#.*$//' >"$FUNC"
if [ -s "$FUNC" ]; then
  ok "C-anchor: located assert_mount_quiesced() in the SUT ($(wc -l <"$FUNC") lines, comments stripped)"
else
  fail "C-anchor: could NOT locate assert_mount_quiesced() — every ordering verdict below would be vacuous"
fi

# ln_of <name> <ere> — resolve a single anchor to a line number, LOUDLY. Returns 1 and reports on a
# missing anchor rather than yielding '' into an arithmetic comparison that would silently pass.
ln_of() {
  local name="$1" pat="$2" v
  v="$(grep -nE -- "$pat" "$FUNC" | head -1 | cut -d: -f1)"
  if [ -z "$v" ]; then
    fail "C-order: ANCHOR MISSING for '$name' (/$pat/) — the ordering assertions that depend on it cannot run and must not report green"
    return 1
  fi
  printf '%s' "$v"
}

# shellcheck disable=SC2016  # literal SUT source text: these must match the script's syntax, not expand
a_fp_pre="$(ln_of 'fingerprint capture'  'fp_pre="\$\(_g4_depth1_fingerprint\)"')" || a_fp_pre=""
# shellcheck disable=SC2016
a_open="$(ln_of 'probe open'             'exec 9>"\$probe"')" || a_open=""
# shellcheck disable=SC2016
a_rm="$(ln_of 'probe unlink'             '^[[:space:]]*rm -f "\$lout" "\$lerr" "\$probe"')" || a_rm=""
# shellcheck disable=SC2016
a_exists="$(ln_of 'surviving-probe guard' '^[[:space:]]*if \[ -e "\$probe" \]; then')" || a_exists=""
# shellcheck disable=SC2016
a_fp_post="$(ln_of 'fingerprint re-check' 'fp_post="\$\(_g4_depth1_fingerprint\)"')" || a_fp_post=""
# shellcheck disable=SC2016
a_restore="$(ln_of 'strict restore'       '^[[:space:]]*_g4_restore_root_mtime "\$mref" "\$phase"$')" || a_restore=""

order_pair() {                      # <desc> <earlier-name> <earlier> <later-name> <later>
  if [ -z "$3" ] || [ -z "$5" ]; then
    fail "C-order: $1 — cannot compare, a required anchor is missing ($2='$3' $4='$5')"
  elif [ "$3" -lt "$5" ]; then
    ok "C-order: $1 ($2 line $3 < $4 line $5)"
  else
    fail "C-order: $1 VIOLATED — $2 (line $3) does not precede $4 (line $5)"
  fi
}
order_pair "the fingerprint is captured BEFORE the probe is opened" fp_pre "$a_fp_pre" exec9 "$a_open"
order_pair "the probe is opened BEFORE it is unlinked"              exec9 "$a_open" unlink "$a_rm"
order_pair "the surviving-probe guard sits AFTER the unlink"        unlink "$a_rm" guard "$a_exists"
order_pair "the fingerprint is re-checked AFTER the unlink"         unlink "$a_rm" fp_post "$a_fp_post"
order_pair "the strict restore sits AFTER the surviving-probe guard" guard "$a_exists" restore "$a_restore"
order_pair "the strict restore sits AFTER the fingerprint re-check"  fp_post "$a_fp_post" restore "$a_restore"

# Die paths must not leave the tree SILENTLY perturbed. Three of the four restore; the
# probe-unremovable path deliberately does NOT — the probe is still sitting in the tree there, so
# stamping the mtime back would dress a contaminated tree as a pristine one. Perturbed-with-the-
# artifact-present is strictly more honest than pristine-looking-but-contaminated, and the run
# aborts either way so C1 never certifies it.
#
# This asserted 4 until the m21 finding: the unremovable branch restored AND its die message said
# it refused to. The count moved to 3 because the CODE was corrected to match the message — so the
# guard here is the count PLUS the no-restore-with-a-stated-reason, not a relaxed count.
# Counted, not sampled: `grep -c` (never `| grep -q`, task 5.7g).
# shellcheck disable=SC2016  # literal SUT source text, must not expand
be_n="$(grep -cE '_g4_restore_root_mtime "\$mref" "\$phase" best-effort' "$FUNC" || true)"
# shellcheck disable=SC2016  # literal SUT source text, must not expand
unrem_body="$(sed -n '/if \[ -e "\$probe" \]; then/,/^  fi$/p' "$FUNC")"
unrem_restores="$(grep -cE '_g4_restore_root_mtime' <<<"$unrem_body" || true)"
unrem_says_no="$(grep -cE 'refusing to restore' <<<"$unrem_body" || true)"
if [ "$be_n" -eq 3 ] && [ "$unrem_restores" -eq 0 ] && [ "$unrem_says_no" -ge 1 ]; then
  ok "C-diepaths: 3 die paths restore best-effort; the probe-unremovable path does NOT restore and its die says so (code and message agree — m21)"
else
  fail "C-diepaths: expected 3 best-effort restores + a non-restoring probe-unremovable path whose die states it (found be=$be_n unrem_restores=$unrem_restores unrem_says_no=$unrem_says_no) — either an abort leaves \$MOUNT silently perturbed, or the die message contradicts the code"
fi

# The `exec 9>` failure path must NOT restore: nothing was created, so there is nothing to undo, and
# a restore there would stamp a timestamp the probe never moved.
uncreatable_body="$(sed -n '/emit_drift g4_probe_uncreatable/{=;}' "$FUNC" | head -1)"
if [ -n "$uncreatable_body" ]; then
  ctx="$(sed -n "$((uncreatable_body - 3)),${uncreatable_body}p" "$FUNC")"
  if grep -qE -- '_g4_restore_root_mtime' <<<"$ctx"; then
    fail "C-uncreatable: the g4_probe_uncreatable path restores the mtime — but exec 9> FAILED there, so nothing was perturbed and the restore stamps a move that never happened"
  else
    ok "C-uncreatable: the g4_probe_uncreatable path correctly does NOT restore (exec 9> failed; nothing was created)"
  fi
else
  fail "C-uncreatable: ANCHOR MISSING — could not locate the g4_probe_uncreatable path"
fi

# C1's predicate must remain byte-unchanged: this bug is fixed on the probe, never by narrowing the
# gate. Anchored on the full invocation and on the absence of the narrowing flag.
BODY_NC="$SCRATCH/cutover.nocomment"
sed -e 's/[[:space:]]*#.*$//' "$CUTOVER" >"$BODY_NC"
if grep -qE -- "^[[:space:]]*rsync -aHAXi --numeric-ids --checksum --delete --dry-run --out-format='%i %n'" "$BODY_NC" \
   && ! grep -qE -- 'omit-dir-times' "$BODY_NC"; then
  ok "C-gate: C1's itemize invocation is byte-unchanged and carries no --omit-dir-times — the gate was not narrowed"
else
  fail "C-gate: C1's verify invocation changed or gained --omit-dir-times — the gate was narrowed instead of the probe fixed"
fi
# Anchored with grep -F on the LITERAL counter expression. An ERE here would need the itemize
# character class double-escaped through both the shell and the regex engine, and a mis-escaped
# pattern silently matches nothing — which is a harness bug that reads exactly like a real SUT
# regression. -F removes the escaping layer entirely.
# shellcheck disable=SC2016  # literal SUT source text, must not expand
C1_COUNTER='diff_n="$(grep -cE '"'"'^(\*deleting|[<>ch.*][fdLDS])'"'"' "$vout" || true)"'
if grep -qF -- "$C1_COUNTER" "$BODY_NC"; then
  ok "C-gate-count: C1's diff_n counter is byte-unchanged (every itemize code still counts)"
else
  fail "C-gate-count: C1's diff_n counter changed — AC2 requires the predicate to be untouched by this fix"
fi

# Entrypoint coupling (task 5.10): the perturbing call must sit between the pass-2 write and C1.
# shellcheck disable=SC2016
p2_ln="$(grep -nE -- '^[[:space:]]*rsync -aHAX --numeric-ids --delete --checksum "\$MOUNT"/ "\$STAGING"/' "$BODY_NC" | head -1 | cut -d: -f1)"
q_ln="$(grep -nE -- '^[[:space:]]*assert_mount_quiesced pre-verify$' "$BODY_NC" | head -1 | cut -d: -f1)"
# shellcheck disable=SC2016
v_ln="$(grep -nE -- '^[[:space:]]*verify_byte_identity "\$MOUNT" "\$STAGING"$' "$BODY_NC" | head -1 | cut -d: -f1)"
if [ -n "$p2_ln" ] && [ -n "$q_ln" ] && [ -n "$v_ln" ] && [ "$p2_ln" -lt "$q_ln" ] && [ "$q_ln" -lt "$v_ln" ]; then
  ok "C-path: 'assert_mount_quiesced pre-verify' (line $q_ln) sits BETWEEN the pass-2 rsync (line $p2_ln) and C1 (line $v_ln) — Part B exercises the real abort path"
else
  fail "C-path: could not prove the call ordering (pass2='$p2_ln' quiesce='$q_ln' verify='$v_ln') — a missing anchor is a HARNESS error, never evidence"
fi

# AC21: no `local x="$(cmd)"` in the new code — `local` returns 0 regardless, masking the exit
# status in a shell with no `-e`. Scoped to the two functions this fix added.
masked=0
for fn in _g4_restore_root_mtime _g4_depth1_fingerprint emit_root_mtime ensure_mtime_tools; do
  sed -n "/^${fn}() {\$/,/^}\$/p" "$CUTOVER" | sed -e 's/[[:space:]]*#.*$//' >"$SCRATCH/fn.body"
  c="$(grep -cE -- 'local [a-zA-Z_]+="\$\(' "$SCRATCH/fn.body" || true)"
  [ "$c" -gt 0 ] && { masked=$((masked + c)); note "  masked-status site in $fn: $c"; }
done
if [ "$masked" -eq 0 ]; then
  ok "C-localmask: no 'local x=\$(cmd)' in the fix's new functions — exit status is not masked in a shell with no -e (AC21)"
else
  fail "C-localmask: $masked 'local x=\$(cmd)' site(s) in the fix's new functions — 'local' returns 0 regardless, so a failed stat/touch never reaches its die (AC21)"
fi

# =================================================================================================
# Summary
# =================================================================================================
echo
echo "===== MEASURED ICODE TABLE (every row produced by running rsync in this process) ====="
for r in "${ICODE_LOG[@]}"; do printf '  %-6s %s\n' "${r%%|*}" "${r#*|}"; done
if [ "${#UNMEASURED_LOG[@]}" -gt 0 ]; then
  echo
  echo "===== UNMEASURED (recorded explicitly; NO icode is predicted for these) ====="
  for r in "${UNMEASURED_LOG[@]}"; do printf '  %-6s %s\n' "${r%%|*}" "${r#*|}"; done
fi
if [ "${#FINDING_LOG[@]}" -gt 0 ]; then
  echo
  echo "############################################################################"
  echo "##  OPEN FINDINGS — MUTATIONS THAT SURVIVED THE SHIPPED FIX               ##"
  echo "############################################################################"
  for f in "${FINDING_LOG[@]}"; do printf '  * %s\n\n' "$f"; done
  echo "  These do NOT fail this suite (a permanently-RED registered step is a gate"
  echo "  everyone learns to ignore) — but they are defects in the fix, not in the"
  echo "  battery, and each pin above flips the moment one is resolved."
  echo "############################################################################"
fi

echo
if [ "$asserted" -lt "$MIN_ASSERTIONS" ]; then
  printf 'FAIL  - NON-DEGENERACY FLOOR: only %d assertion(s) executed, expected at least %d.\n' "$asserted" "$MIN_ASSERTIONS"
  printf '        A suite that asserts (almost) nothing must never report green.\n'
  fails=$((fails + 1))
fi
printf 'workspaces-luks-g4-mutation: %d passed, %d failed, %d open finding(s), %d unmeasured (%d assertions)\n' \
  "$pass" "$fails" "$findings" "$unmeasured" "$asserted"
[ "$fails" -eq 0 ]
