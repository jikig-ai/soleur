#!/usr/bin/env bash
#
# MUTATION BATTERY for the #6733 G4 read-probe, and for C1's non-regression.
#
# WHY THIS IS A SEPARATE FILE (and not an extension of workspaces-luks-verify-root-mtime.test.sh):
# that suite is the MECHANISM harness — it proves the mechanism using filesystem physics performed
# by the harness itself, plus STRUCTURAL assertions that the shipped script has the right shape.
# This suite does something different in kind: it MUTATES THE SUT (it copies workspaces-cutover.sh
# into scratch, edits it against a pristine backup, and EXECUTES the real `assert_mount_quiesced`
# out of the mutated copy) and it MUTATES THE DESTINATION TREE to prove C1 still rejects. So the
# structural suite answers "is the code shaped like the fix?" and this one answers "does the code
# BEHAVE like the fix when you run it?" — the second is what catches a guard that is present,
# correctly placed, and inverted. Those need a per-case teardown, a landing assertion, and a shim
# PATH.
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
# OPEN FINDINGS. None. The open_finding() machinery is RETAINED deliberately even though nothing
# currently uses it: the two findings it carried (m19a — the depth-1 fingerprint could not catch a
# matched in-bracket create+delete pair; m21 — the surviving-probe guard restored the mtime while
# its die message said it refused to) were both properties of the ROOT-MTIME BRACKET, and the
# bracket is gone. Neither survived into this design because neither failure mode exists in it:
# there is no fingerprint, no restore, and no probe artifact to survive an unlink. Removing the
# reporting machinery along with them would mean the next surviving mutation has nowhere to be
# recorded except a FAIL that reds a registered step forever, which is the pressure that makes
# people delete the case instead of the defect.
#
# WHAT REPLACED THE BRACKET CASES. m19a/m19b, the restore-skew case, the mtime-tool-missing case,
# C-diepaths, C-uncreatable and C-localmask's bracket-helper scope all pinned the internals of a
# repair that no longer exists; asserting them here would be asserting the placement of code that
# is not present. In their place this battery measures the properties the read-probe actually has:
# the root mtime is unchanged across the REAL function (m13, a DIRECT invariant rather than one
# inferred through a restore), an absent workspaces/ fails closed (m15), a genuine straggler is
# still caught while our own fd and any inheriting child are not (m16/m16-foreign), lsof format
# drift fails closed (m19), and a read-only mount fails closed while `errors=remount-ro` does not
# (m20/m20-token).
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
# 79 is the ACTUAL count executed on a capable host, not a round number below it: a floor with
# headroom is a floor that lets a whole case silently stop running.
MIN_ASSERTIONS=79

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

# make_lsof_shim <body> — a PATH-shadowing lsof that runs <body> DURING the scan (it is invoked
# while the SUT holds its read fd) and then reports that fd back, so the positive control passes
# unless the case wants it to fail.
#
# $PPID is the SUT shell — the process that holds fd 9 and whose `$$` the positive control and the
# holder filter are both keyed on. Hardcoding a PID here (the pre-#6733 shim printed a literal `1`)
# would make every positive control fail against the shipped PID filter, i.e. the shim would be
# testing the shim. HEADER shape matters too: the SUT now asserts `^COMMAND +PID +USER`.
make_lsof_shim() {
  mkdir -p "$SHIMBIN"
  { printf '#!/usr/bin/env bash\n'
    # shellcheck disable=SC2016  # literal shim body, must not expand here
    printf 'ln="$2"\n'
    printf '%s\n' "$1"
    printf 'echo "COMMAND     PID USER FD   TYPE DEVICE SIZE/OFF    NODE NAME"\n'
    # shellcheck disable=SC2016  # literal shim body, must not expand here
    printf 'echo "bash    $PPID $(id -un) 9r   DIR   0,50       40 1 $ln/workspaces"\n'
    printf 'exit 0\n'; } >"$SHIMBIN/lsof"
  chmod +x "$SHIMBIN/lsof"
}

# --- the findmnt seam ------------------------------------------------------------------------------
# $MOUNT here is a scratch DIRECTORY, not a real mountpoint, so `findmnt -no OPTIONS "$MOUNT"`
# returns EMPTY on the fixture and the shipped _assert_mount_rw correctly refuses. That refusal is
# right in production and useless as a fixture default, so every case gets a findmnt shim reporting
# a healthy mount, and the cases that are ABOUT mount options override it (m20).
#
# This is a stub of a HOST FACT the fixture cannot reproduce, not of the logic under test: the
# token-splitting comparison in _assert_mount_rw runs for real against whatever this shim reports.
_mk_findmnt() {   # $1 = the OPTIONS string findmnt should report for $MOUNT
  mkdir -p "$SHIMBIN"
  { printf '#!/usr/bin/env bash\n'
    printf 'case "$*" in *OPTIONS*) echo "%s";; *) exit 0;; esac\n' "$1"; } >"$SHIMBIN/findmnt"
  chmod +x "$SHIMBIN/findmnt"
}
_mk_findmnt 'rw,relatime'          # the fixture default: a healthy read-write mount

# run_amq <use-lsof-shim:yes|no> [phase] — run the REAL assert_mount_quiesced out of $SUT.
#
# $SHIMBIN is ALWAYS on PATH (the findmnt shim above must always apply). `no` means "no LSOF shim"
# — the real lsof is reached by removing the shadow — NOT "no shims at all". Conflating the two is
# what made every real-lsof case abort in _assert_mount_rw instead of exercising the probe.
#
# PHASE IS A PARAMETER (#6733): `assert_mount_quiesced freeze` (the freeze_writers call site) was
# never executed by either suite before this change — only `pre-verify` — so half the gate's call
# sites were structurally uncovered. Both are exercised now.
AMQ_RC=0; AMQ_OUT=""
run_amq() {
  local phase="${2:-pre-verify}"
  [ "$1" = no ] && rm -f "$SHIMBIN/lsof"
  AMQ_OUT="$(PATH="$SHIMBIN:$PATH" WORKSPACES_MOUNT="$MOUNT" WORKSPACES_STAGING="$STAGING" \
    bash -c '. "$1"; assert_mount_quiesced "$2"; echo AMQ_RETURNED_OK' _ "$SUT" "$phase" 2>&1)"
  AMQ_RC=$?
}
# Negative/positive assertions on the captured output use a HERESTRING, never `echo | grep -q`
# (task 5.7g): under pipefail an early match SIGPIPEs the producer to 141 and a negative assertion
# fails OPEN.
out_has()  { grep -qE -- "$1" <<<"$AMQ_OUT"; }

# --- m13 / m14: THE NON-VACUITY PAIR -------------------------------------------------------------
# m13 runs the SHIPPED read-probe; m14 mutates ONLY the redirection direction (`9<` -> `9>`) and
# must go RED. One character apart, so m13's green is attributable to the read and to nothing else.
#
# The shim sleeps 1.1s in place of `lsof +D "$MOUNT"`, which on the real /workspaces volume is a
# multi-second recursive scan. That is not cosmetic: rsync compares directory mtimes at WHOLE-SECOND
# granularity (re-measured as m17 below), so without the sleep a create+unlink would land inside one
# second, C1 could not see the move ANYWAY, and m14's RED would be unattributable while m13's green
# would be a granularity artifact wearing a working fix's clothes.
make_lsof_shim 'sleep 1.1'

# m13 runs at BOTH phases. The root-mtime invariant is now DIRECT — asserted on the probe itself,
# not inferred through a restore that could be wrong in its own right.
for _phase in pre-verify freeze; do
  sut_reset
  pass2 >/dev/null 2>&1
  m13_pre="$(stat -c %y -- "$MOUNT")"
  run_amq yes "$_phase"
  m13_post="$(stat -c %y -- "$MOUNT")"
  if [ "$AMQ_RC" -eq 0 ] && out_has 'AMQ_RETURNED_OK'; then
    ok "m13-run[$_phase]: the REAL assert_mount_quiesced ran to completion through the shipped read-probe (rc=0)"
  else
    fail "m13-run[$_phase]: assert_mount_quiesced did not complete (rc=$AMQ_RC) — every m13 verdict for this phase is about a run that did not happen: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 400)"
  fi
  if [ "$m13_pre" = "$m13_post" ]; then
    ok "m13-mtime[$_phase]: \$MOUNT's root mtime is byte-identical across the real G4 probe ($m13_post) — a DIRECT invariant, with no restore in the path to be trusted"
  else
    fail "m13-mtime[$_phase]: the root mtime moved across the probe ($m13_pre -> $m13_post) — the gate is perturbing the tree C1 certifies"
  fi
  if [ -z "$(find "$MOUNT" -maxdepth 1 -name '.luks-g4-probe.*' -print -quit)" ]; then
    ok "m13-listing[$_phase]: no probe artifact was created under \$MOUNT — the create+unlink failure modes cannot exist"
  else
    fail "m13-listing[$_phase]: a .luks-g4-probe.* entry exists under \$MOUNT after the run — the probe is creating again"
  fi
  rc=0; verify_into "$VOUT" "$VERR" || rc=$?
  n="$(diff_n "$VOUT")"
  if [ "$rc" -eq 0 ] && [ "$n" -eq 0 ]; then
    ok "m13[$_phase]: C1 is CLEAN after the real G4 probe ran between pass-2 and the verify"
  else
    fail "m13[$_phase]: expected a clean C1 with the shipped probe, got $n difference(s) (rc=$rc): $(tr '\n' '|' <"$VOUT")"
  fi
done

# m14 — flip ONLY the redirection direction. This is the mutation that would satisfy a placement-only
# assertion ("an fd is opened under $MOUNT") while violating the property, so it is measured against
# BEHAVIOUR (C1's verdict), not against the file's text.
sut_reset
# shellcheck disable=SC2016  # literal SUT source text, must not expand
# The write must land in the MOUNT ROOT, not in workspaces/: `./` in C1's itemize output IS $MOUNT,
# and a create one level deeper produces `.d..t...... workspaces/` instead — a different (also real)
# diff that would not reproduce the reported signature.
if sut_mutate 'if ! exec 9<"$wsdir"; then' 'if ! exec 9>"$MOUNT/.luks-g4-probe.$$"; then'; then
  ok "m14-land: the SUT mutation LANDED — the probe is a WRITE-open in the copy (anchor found exactly once, file differs from the pristine backup)"
  pass2 >/dev/null 2>&1
  m14_sec_pre="$(stat -c %Y -- "$MOUNT")"
  run_amq yes
  m14_sec_post="$(stat -c %Y -- "$MOUNT")"
  rm -f "$MOUNT"/.luks-g4-probe.*
  if [ "$m14_sec_pre" != "$m14_sec_post" ]; then
    ok "m14-sec: the write-probe moved \$MOUNT's root mtime across a WHOLE SECOND ($m14_sec_pre -> $m14_sec_post) — C1 can see this move, so the RED below is the write and not a coin flip"
  else
    unrun "m14-sec: the write-probe's create landed in the same whole second — C1 cannot see this move, so m14 carries no information (task 5.8)"
  fi
  rc=0; verify_into "$VOUT" "$VERR" || rc=$?
  root_line="$(grep -cE '^\.d\.\.t\.\.\.\.\.\. \./$' "$VOUT" || true)"
  if [ "$rc" -eq 0 ] && [ "$root_line" -ge 1 ]; then
    ok "m14: probe reverted to a WRITE => C1 emits '.d..t...... ./'. The battery is NON-VACUOUS: m13's green is caused by the read-open, one character away."
    record_icode m14 ".d..t...... ./ (write-probe reintroduced)"
  else
    fail "m14: expected '.d..t...... ./' with the probe reverted to a write, got root_line=$root_line (rc=$rc) — m13's green is then NOT attributable to the fix: $(tr '\n' '|' <"$VOUT")"
  fi
else
  fail "m14: the SUT mutation did not land — a missing/ambiguous anchor must be LOUD, never a silent skip that reports green"
fi

# --- m15: an ABSENT workspaces/ fails CLOSED ------------------------------------------------------
# The state this guard exists for is the one where a cutover is declared GREEN with every user's
# data missing: $MOUNT is the wrong device, or workspaces/ was auto-created empty beneath a bind
# mount. Downstream, C1 finds no differences, the du byte match reads 0 == 0 and G3's counts agree
# at zero — so nothing further down can catch it. It has to be caught here.
sut_reset
make_lsof_shim ':'
mv "$MOUNT/workspaces" "$SCRATCH/workspaces.parked"
run_amq yes
mv "$SCRATCH/workspaces.parked" "$MOUNT/workspaces"
if [ "$AMQ_RC" -ne 0 ] && out_has 'g4_workspaces_unopenable'; then
  ok "m15: an absent \$MOUNT/workspaces makes the gate REFUSE (rc=$AMQ_RC, g4_workspaces_unopenable) — the wrong-device / empty-bind-source state is caught before any gate can green-light it"
else
  fail "m15: the gate did NOT refuse with workspaces/ absent (rc=$AMQ_RC) — a cutover would proceed and every downstream gate would compare empty against empty and report success: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 400)"
fi
if out_has 'AMQ_RETURNED_OK'; then
  fail "m15-noproceed: assert_mount_quiesced RETURNED SUCCESSFULLY with workspaces/ absent — fail-open"
else
  ok "m15-noproceed: the function never returned success with workspaces/ absent"
fi
# The mount must be restored, or every case below measures a broken fixture.
if [ -d "$MOUNT/workspaces" ]; then
  ok "m15-restore: the fixture's workspaces/ was put back — the cases below run against the real tree"
else
  fail "m15-restore: workspaces/ was not restored — every subsequent verdict is about a broken fixture"
fi

# --- m16: an INHERITED fd in a child is NOT counted as a straggler --------------------------------
# Bash does not set O_CLOEXEC on `exec 9<`, so children inherit fd 9. Under the PID filter an
# inheriting child reads as a FOREIGN straggler, which would abort every cutover. First the PHYSICS
# is measured with real lsof (so the guard is shown to be guarding something real), then the SHIPPED
# function is run with real lsof and must return clean.
if command -v lsof >/dev/null 2>&1; then
  _inh="$SCRATCH/inherit.out"
  ( exec 9<"$MOUNT/workspaces"; lsof +D "$MOUNT" 2>/dev/null | cat >"$_inh" ) || true
  _inh_rows="$(awk 'NR>1 && $0 ~ /workspaces/' "$_inh" 2>/dev/null | grep -c . || true)"
  if [ "${_inh_rows:-0}" -ge 2 ]; then
    ok "m16-physics: an inheriting child really does appear in 'lsof +D' output as its own row ($_inh_rows rows) — the '9<&-' guard is guarding a measured behaviour, not a hypothetical one"
  else
    note "m16-physics: could not observe an inheriting child in lsof output on this host ($_inh_rows row(s)) — the shipped guard is retained as defence in depth; the behavioural assertion below still runs"
  fi
  sut_reset
  pass2 >/dev/null 2>&1
  run_amq no                       # REAL lsof, no shim: this is the end-to-end shape
  if [ "$AMQ_RC" -eq 0 ] && out_has 'AMQ_RETURNED_OK'; then
    ok "m16: with REAL lsof and only our own fd held, the gate returns CLEAN — neither the script's own probe fd nor any child of it is miscounted as a straggler"
  else
    fail "m16: the gate aborted on a quiesced mount with real lsof (rc=$AMQ_RC) — the probe fd or an inheriting child is being counted as a foreign holder: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 400)"
  fi
  # THE OTHER DIRECTION. Without this, m16 above is satisfied by a gate that reports NOTHING ever —
  # including a real straggler. A genuine foreign holder MUST still be caught. This is the pair that
  # pins the PID filter's OPERATOR: inverting `!=` to `==` makes m16 die and m16-foreign pass.
  _hold="$SCRATCH/holder.sh"
  printf '#!/usr/bin/env bash\nexec 9<"$1/workspaces"\nsleep 12\n' >"$_hold"; chmod +x "$_hold"
  "$_hold" "$MOUNT" & _hpid=$!
  sleep 0.4
  run_amq no
  kill "$_hpid" 2>/dev/null || true; wait "$_hpid" 2>/dev/null || true
  if [ "$AMQ_RC" -ne 0 ] && out_has 'a straggler still holds the mount'; then
    ok "m16-foreign: a GENUINE foreign holder of \$MOUNT/workspaces IS caught (rc=$AMQ_RC) — the PID filter drops only our own rows, so m16's clean result is not a gate that reports nothing"
  else
    fail "m16-foreign: a real straggler holding the mount was NOT reported (rc=$AMQ_RC) — the holder filter is subtracting more than this process's own rows, which is a fail-open in the gate's entire purpose: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 400)"
  fi
else
  unrun "m16: lsof is unavailable — the end-to-end read-probe cases did not run"
fi

# --- m17: FALSIFIED. RECORDED, NOT ASSERTED. -----------------------------------------------------
# The plan (AC8) claims a %Y-precision restore still emits the diff, "pinning ns precision". It does
# not. rsync 3.4.1 compares directory mtimes at WHOLE-SECOND granularity, so a whole-second-accurate
# restore is SUFFICIENT for C1. Re-measured here rather than cited, because a falsification carried
# forward on a citation is the same unmeasured claim in the other direction. The record is KEPT even
# though the restore it was about is gone: it is what justifies the 1.1s sleep in every shim above,
# and a future editor who deletes that sleep needs to find this measurement, not re-derive it.
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

# --- m18: a perturbation AFTER the probe still aborts C1 ------------------------------------------
# This is the signal the fix must NOT blind. The read-probe absorbs nothing by construction (it
# writes nothing), but that has to be MEASURED, because "absorbs nothing" is exactly what the
# previous restore-based attempt also claimed while silently absorbing a foreign create+delete pair.
sut_reset
make_lsof_shim 'sleep 1.1'
pass2 >/dev/null 2>&1
run_amq yes
if [ "$AMQ_RC" -eq 0 ]; then
  ok "m18-pre: the probe completed cleanly first (rc=0) — the abort below is attributable to the POST-probe write"
else
  unrun "m18-pre: assert_mount_quiesced did not complete (rc=$AMQ_RC) — m18 cannot isolate a post-probe perturbation"
fi
m18_base="$(stat -c %Y -- "$MOUNT")"
touch -d "@$((m18_base + 2))" -- "$MOUNT"        # whole-second move: C1 can see it (see m17)
m18_after="$(stat -c %Y -- "$MOUNT")"
if [ "$m18_base" != "$m18_after" ]; then
  ok "m18-land: the residual post-probe perturbation LANDED and crossed a whole second ($m18_base -> $m18_after)"
else
  unrun "m18-land: the residual perturbation did not land — the case did not run"
fi
rc=0; verify_into "$VOUT" "$VERR" || rc=$?
root_line="$(grep -cE '^\.d\.\.t\.\.\.\.\.\. \./$' "$VOUT" || true)"
if [ "$rc" -eq 0 ] && [ "$root_line" -eq 1 ]; then
  ok "m18: a foreign root perturbation AFTER the probe still ABORTS C1 ('.d..t...... ./') — the fix removes its own perturbation without blinding the foreign-writer signal"
  record_icode m18 ".d..t...... ./ (post-probe foreign write — correctly NOT absorbed)"
else
  fail "m18: a post-probe root perturbation did NOT reach C1 (root_line=$root_line rc=$rc) — the foreign-writer signal has been blinded: $(tr '\n' '|' <"$VOUT")"
fi

# --- m19: lsof OUTPUT-FORMAT DRIFT fails CLOSED ---------------------------------------------------
# Both the positive control and the holder filter read lsof's SECOND whitespace field as the PID and
# drop row 1 as a header. If a future lsof reordered its columns, the holder filter would read a
# different column entirely — and the dangerous direction is silent: real holders stop matching and
# the gate certifies a busy mount as quiesced. Asserting the header shape converts that into a
# named abort. Driven by a shim that emits a plausible-but-different header.
sut_reset
mkdir -p "$SHIMBIN"
{ printf '#!/usr/bin/env bash\n'
  printf 'echo "PID COMMAND USER FD TYPE DEVICE SIZE/OFF NODE NAME"\n'
  # shellcheck disable=SC2016  # literal shim body, must not expand here
  printf 'echo "$PPID bash $(id -un) 9r DIR 0,50 40 1 $2/workspaces"\n'
  printf 'exit 0\n'; } >"$SHIMBIN/lsof"
chmod +x "$SHIMBIN/lsof"
run_amq yes
if [ "$AMQ_RC" -ne 0 ] && out_has 'g4_lsof_header_unrecognized'; then
  ok "m19: an unrecognised lsof header makes the gate REFUSE (rc=$AMQ_RC, g4_lsof_header_unrecognized) — format drift fails CLOSED instead of silently miscounting the PID column"
else
  fail "m19: a reordered lsof header did NOT stop the run (rc=$AMQ_RC) — the gate would parse the wrong column and could certify a busy mount as quiesced: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 400)"
fi
if out_has 'AMQ_RETURNED_OK'; then
  fail "m19-noproceed: the function RETURNED SUCCESSFULLY on an unparseable lsof format — fail-open"
else
  ok "m19-noproceed: the function never returned success on an unrecognised lsof format"
fi

# --- m20: a READ-ONLY $MOUNT fails CLOSED, and 'errors=remount-ro' does NOT ------------------------
# The removed write-probe proved writability as a side effect; _assert_mount_rw restates it. The
# TOKEN-vs-SUBSTRING distinction is the whole case: `findmnt -no OPTIONS /` really returns
# `rw,relatime,errors=remount-ro` on this host, so a substring test for "ro" would declare every
# healthy mount read-only. Both directions are asserted — a real `ro` must abort, and the
# remount-ro VALUE must not.
sut_reset
make_lsof_shim ':'
_mk_findmnt 'ro,relatime'
run_amq yes
if [ "$AMQ_RC" -ne 0 ] && out_has 'g4_mount_read_only'; then
  ok "m20: a READ-ONLY \$MOUNT makes the gate REFUSE (rc=$AMQ_RC, g4_mount_read_only) — the writability signal the write-probe smuggled in is preserved without writing"
else
  fail "m20: a read-only \$MOUNT did NOT stop the run (rc=$AMQ_RC) — rollback() could not remount, and the retained plaintext is the only copy until Phase 5: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 400)"
fi
# THE SUBSTRING TRAP, asserted in the direction that would break production. A `case "$opts" in *ro*)`
# implementation passes m20 above and fails here — which is precisely why m20 alone is not enough.
_mk_findmnt 'rw,relatime,errors=remount-ro'
run_amq yes
if [ "$AMQ_RC" -eq 0 ] && out_has 'AMQ_RETURNED_OK'; then
  ok "m20-token: 'rw,relatime,errors=remount-ro' is accepted — the check compares comma-separated TOKENS, so the 'ro' inside the errors= VALUE does not trip it"
else
  fail "m20-token: a healthy 'rw,relatime,errors=remount-ro' mount was REJECTED (rc=$AMQ_RC) — the option check is matching a substring, which aborts every cutover on the kernel's default mount options: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 400)"
fi
# An UNREADABLE options list must also refuse: an unknown read/write state is not a writable one.
_mk_findmnt ''
run_amq yes
if [ "$AMQ_RC" -ne 0 ] && out_has 'g4_mount_opts_unreadable'; then
  ok "m20-unreadable: unreadable mount options make the gate REFUSE (g4_mount_opts_unreadable) — an unknown read/write state is not treated as writable"
else
  fail "m20-unreadable: the gate proceeded with unreadable mount options (rc=$AMQ_RC) — a silent unknown reads as healthy: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 400)"
fi
_mk_findmnt 'rw,relatime'   # restore the healthy-mount default for the cases below

# --- m21: lsof unavailable => the gate REFUSES (task 5.5 / AC7) -----------------------------------
# The unifying question from the 2026-07-19 learning: if this instrument were unavailable, does the
# guard REFUSE or PROCEED? Built by symlinking every PATH entry EXCEPT lsof, so the absence is real
# rather than a stubbed `command -v`.
sut_reset
NOLSOF="$SCRATCH/nolsof"; mkdir -p "$NOLSOF"
IFS=':' read -r -a _pdirs <<<"$PATH"
for d in "${_pdirs[@]}"; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    b="$(basename -- "$f")"
    [ "$b" = lsof ] && continue
    [ -e "$NOLSOF/$b" ] && continue
    [ -x "$f" ] && ln -s "$f" "$NOLSOF/$b" 2>/dev/null
  done
done
if [ -x "$NOLSOF/stat" ] && [ ! -e "$NOLSOF/lsof" ]; then
  ok "m21-land: the instrument-stripped PATH LANDED — stat present, lsof absent"
  m21_out="$(PATH="$NOLSOF" WORKSPACES_MOUNT="$MOUNT" \
    bash -c '. "$1"; assert_mount_quiesced pre-verify; echo AMQ_RETURNED_OK' _ "$SUT" 2>&1)"
  m21_rc=$?
  if [ "$m21_rc" -ne 0 ] && grep -qE -- 'lsof_install_failed' <<<"$m21_out"; then
    ok "m21: lsof unavailable => the gate REFUSES (rc=$m21_rc, lsof_install_failed) — property (a), it does not silently skip"
  else
    fail "m21: with lsof absent the gate did NOT refuse (rc=$m21_rc) — a gate that evaporates when a binary is missing is the #6588 silent-failure class: $(tr '\n' '|' <<<"$m21_out" | tail -c 400)"
  fi
  if grep -qE -- 'AMQ_RETURNED_OK' <<<"$m21_out"; then
    fail "m21-noproceed: assert_mount_quiesced RETURNED SUCCESSFULLY with lsof missing — fail-open"
  else
    ok "m21-noproceed: the function never returned success with lsof missing"
  fi
else
  unrun "m21: could not build an instrument-stripped PATH (stat present=$([ -x "$NOLSOF/stat" ] && echo y || echo n), lsof absent=$([ ! -e "$NOLSOF/lsof" ] && echo y || echo n)) — the case did not run"
fi

# --- m22: the POSITIVE CONTROL is still load-bearing ----------------------------------------------
# An lsof that scans nothing (exits 0, reports only a header) must reach g4_probe_blind. Without
# this, every "clean" verdict above could be produced by a probe that never looked.
sut_reset
mkdir -p "$SHIMBIN"
{ printf '#!/usr/bin/env bash\n'
  printf 'echo "COMMAND     PID USER FD   TYPE DEVICE SIZE/OFF    NODE NAME"\n'
  printf 'exit 0\n'; } >"$SHIMBIN/lsof"
chmod +x "$SHIMBIN/lsof"
run_amq yes
if [ "$AMQ_RC" -ne 0 ] && out_has 'g4_probe_blind'; then
  ok "m22: an lsof that reports no fd at all reaches g4_probe_blind (rc=$AMQ_RC) — property (c) holds; a scan that did not reach the mount is not a clean mount"
else
  fail "m22: a blind lsof did NOT abort the run (rc=$AMQ_RC) — every clean verdict in this suite could be produced by a probe that never looked: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 400)"
fi
# The positive control requires the PATH too, not just our PID — so an lsof that reported our
# process holding something ELSE cannot satisfy it. This is what makes an empty holder list evidence
# that the scan descended to workspaces/.
sut_reset
mkdir -p "$SHIMBIN"
{ printf '#!/usr/bin/env bash\n'
  printf 'echo "COMMAND     PID USER FD   TYPE DEVICE SIZE/OFF    NODE NAME"\n'
  # shellcheck disable=SC2016  # literal shim body, must not expand here
  printf 'echo "bash    $PPID $(id -un) 9r   DIR   0,50       40 1 $2/plugins"\n'
  printf 'exit 0\n'; } >"$SHIMBIN/lsof"
chmod +x "$SHIMBIN/lsof"
run_amq yes
if [ "$AMQ_RC" -ne 0 ] && out_has 'g4_probe_blind'; then
  ok "m22-path: our PID reported against a DIFFERENT path does not satisfy the positive control — it still dies g4_probe_blind, so the control proves the scan reached workspaces/ and not merely that lsof ran"
else
  fail "m22-path: the positive control was satisfied by a row bearing our PID but the WRONG path (rc=$AMQ_RC) — an lsof that scanned only \$MOUNT's top level would pass the control while never looking where the data lives: $(tr '\n' '|' <<<"$AMQ_OUT" | tail -c 400)"
fi
rm -f "$SHIMBIN/lsof"

# =================================================================================================
# PART C — ORDER + STRUCTURE ASSERTIONS AGAINST THE FILE (task 5.9 / AC10).
#
# Behaviour-only mutations cannot catch every misordering: a gate whose steps run in the wrong order
# can still produce the right verdict on the one run the test happened to observe. The only seam
# that sees ordering is the file itself. Anchored on SYNTAX against a COMMENT-STRIPPED copy — a
# bare-token grep matching the comment that EXPLAINS the trap is a documented recurring error here
# (cq-assert-anchor-not-bare-token). Every missing anchor is LOUD: there is no silent '' comparison.
#
# NOTE ON SCOPE. The bracket-era ordering set (fingerprint-before-open, unlink-before-guard,
# restore-after-unlink, the four die-path restores) is GONE, not relaxed: it pinned the internal
# steps of a repair that no longer exists. Asserting it against this function would be asserting
# placement of code that is not there. What remains are the orderings that still carry meaning.
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
a_rw="$(ln_of 'writability assert'  '^[[:space:]]*_assert_mount_rw "\$phase"')" || a_rw=""
# shellcheck disable=SC2016
a_open="$(ln_of 'probe read-open'   'exec 9<"\$wsdir"')" || a_open=""
# shellcheck disable=SC2016
a_lsof="$(ln_of 'lsof invocation'   'lsof \+D "\$MOUNT" 9<&-')" || a_lsof=""
# shellcheck disable=SC2016
a_hdr="$(ln_of 'header assert'      'g4_lsof_header_unrecognized')" || a_hdr=""
# shellcheck disable=SC2016
a_pc="$(ln_of 'positive control'    'awk -v p="\$\$" -v n="\$wsdir"')" || a_pc=""
# shellcheck disable=SC2016
a_hold="$(ln_of 'holder filter'     'holders="\$\(awk -v p="\$\$"')" || a_hold=""
# shellcheck disable=SC2016
a_emit="$(ln_of 'holder emit'       '^[[:space:]]*emit_freeze_holders "\$holders"')" || a_emit=""
# shellcheck disable=SC2016
a_die="$(ln_of 'straggler die'      'a straggler still holds the mount')" || a_die=""

order_pair() {                      # <desc> <earlier-name> <earlier> <later-name> <later>
  if [ -z "$3" ] || [ -z "$5" ]; then
    fail "C-order: $1 — cannot compare, a required anchor is missing ($2='$3' $4='$5')"
  elif [ "$3" -lt "$5" ]; then
    ok "C-order: $1 ($2 line $3 < $4 line $5)"
  else
    fail "C-order: $1 VIOLATED — $2 (line $3) does not precede $4 (line $5)"
  fi
}
# The fd must be open BEFORE the scan, or the positive control can never see it.
order_pair "the probe fd is opened BEFORE lsof runs"                  open "$a_open" lsof "$a_lsof"
# The header shape must be checked BEFORE anything parses a column out of the output — otherwise the
# parse the assert exists to protect has already happened.
order_pair "the header assert precedes the positive control"          header "$a_hdr" poscontrol "$a_pc"
order_pair "the header assert precedes the holder filter"             header "$a_hdr" holders "$a_hold"
# Property (c): the positive control must gate the holder verdict, not follow it.
order_pair "the positive control precedes the holder filter"          poscontrol "$a_pc" holders "$a_hold"
# Property (d): holders are EMITTED before die(), so the abort self-reports (#6604).
order_pair "holders are EMITTED before the straggler die"             emit "$a_emit" die "$a_die"
# The writability assert is a precondition, not an afterthought.
order_pair "the writability assert precedes the probe open"           rwassert "$a_rw" open "$a_open"

# _assert_mount_rw must compare TOKENS, not a substring. This is the one assertion in Part C whose
# inversion is invisible to a reader: `case "$opts" in *ro*)` looks correct and aborts every real
# cutover (measured: `findmnt -no OPTIONS /` returns `rw,relatime,errors=remount-ro`). m20-token
# catches it behaviourally; this catches it structurally, because the two failure directions are
# different and a future edit could satisfy one while breaking the other.
RWFN="$SCRATCH/rw.body"
sed -n '/^_assert_mount_rw() {$/,/^}$/p' "$CUTOVER" | sed -e 's/[[:space:]]*#.*$//' >"$RWFN"
if [ ! -s "$RWFN" ]; then
  fail "C-rw-anchor: could NOT locate _assert_mount_rw() — the writability assertions are vacuous without it"
else
  ok "C-rw-anchor: located _assert_mount_rw() ($(wc -l <"$RWFN") lines, comments stripped)"
  # shellcheck disable=SC2016  # literal SUT source text, must not expand
  if grep -qE "IFS=','[[:space:]]+read -r -a" "$RWFN" && grep -qE '\[ "\$tok" = ro \]' "$RWFN"; then
    ok "C-rw-token: the options list is SPLIT on ',' and each token compared WHOLE ([ \"\$tok\" = ro ]) — 'errors=remount-ro' cannot trip it"
  else
    fail "C-rw-token: _assert_mount_rw does not split on ',' and compare whole tokens — a substring test for 'ro' matches inside 'errors=remount-ro' and would abort every cutover on the kernel's default options"
  fi
  # The inverse: no substring glob against the whole options string.
  if grep -qE 'case "\$opts" in|\*ro\*' "$RWFN"; then
    fail "C-rw-nosubstr: _assert_mount_rw contains a substring match against the whole options string — this is the 'errors=remount-ro' trap"
  else
    ok "C-rw-nosubstr: no substring match against the whole options string"
  fi
fi

# NO WRITE ANYWHERE UNDER $MOUNT. The invariant this whole change exists to enforce, asserted as a
# property of the function rather than of any one line: the gate must not create, truncate, unlink
# or restamp anything inside the tree C1 certifies. Quantified over ALL the shapes that could do it.
wrote=0
while IFS= read -r _pat; do
  [ -n "$_pat" ] || continue
  c="$(grep -cE -- "$_pat" "$FUNC" || true)"
  if [ "$c" -gt 0 ]; then wrote=$((wrote + c)); note "  write-shaped construct in assert_mount_quiesced: /$_pat/ x$c"; fi
done <<'PATEOF'
exec 9>
touch[[:space:]]+-r
rm -f "\$probe"
>[[:space:]]*"\$MOUNT
>[[:space:]]*"\$wsdir
mkdir[[:space:]]
PATEOF
if [ "$wrote" -eq 0 ]; then
  ok "C-nowrite: assert_mount_quiesced contains ZERO write-shaped constructs targeting \$MOUNT (6 shapes checked) — the gate cannot perturb the tree it certifies"
else
  fail "C-nowrite: $wrote write-shaped construct(s) in assert_mount_quiesced — the gate is mutating the tree C1 is about to certify byte-for-byte (#6733)"
fi

# The mktemp files the gate DOES create must live outside $MOUNT. The L3 startup gate is what
# enforces that; assert the gate exists, because without it the three mktemp calls in this function
# would perturb the tree whenever $TMPDIR happened to point inside the mount.
BODY_NC="$SCRATCH/cutover.nocomment"
sed -e 's/[[:space:]]*#.*$//' "$CUTOVER" >"$BODY_NC"
if grep -qE 'emit_drift tmpdir_under_mount' "$BODY_NC" && grep -qE 'case "\$\(mktemp -u\)" in' "$BODY_NC"; then
  ok "C-tmpdir: the L3 gates refuse to run when \$TMPDIR resolves under \$MOUNT — this function's mktemp files cannot perturb the certified tree"
else
  fail "C-tmpdir: no startup assert that \$TMPDIR is outside \$MOUNT — the six mktemp sites in this script would perturb the tree C1 certifies whenever TMPDIR points inside the mount"
fi

# manifest_of must not write either — the SAME invariant, one gate over. `git status --porcelain`
# refreshes and REWRITES .git/index when stat data is racily stale, and the G3 call site runs
# against $STAGING AFTER verify_byte_identity certified DST == SRC. Quantified over ALL THREE
# invocations, not sampled: a fix applied to `status` alone would satisfy a one-member check.
MFN="$SCRATCH/manifest.body"
sed -n '/^manifest_of() {/,/^}$/p' "$CUTOVER" | sed -e 's/[[:space:]]*#.*$//' >"$MFN"
if [ ! -s "$MFN" ]; then
  fail "C-manifest-anchor: could NOT locate manifest_of() — the index-write assertions are vacuous without it"
else
  git_total="$(grep -cE '^[[:space:]]*git ' "$MFN" || true)"
  git_safe="$(grep -cE '^[[:space:]]*git --no-optional-locks -C ' "$MFN" || true)"
  if [ "$git_total" -ge 3 ] && [ "$git_safe" -eq "$git_total" ]; then
    ok "C-manifest: ALL $git_total git invocations in manifest_of carry --no-optional-locks — 'git status' cannot rewrite .git/index inside \$STAGING after C1 certified it"
  else
    fail "C-manifest: only $git_safe of $git_total git invocations in manifest_of carry --no-optional-locks — a bare 'git status --porcelain' refreshes and REWRITES .git/index, mutating the destination tree immediately after verify_byte_identity proved it matched"
  fi
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
# status in a shell with no `-e`. Scoped to the two functions this change owns: the new
# _assert_mount_rw and the rewritten assert_mount_quiesced.
masked=0
for fn in _assert_mount_rw assert_mount_quiesced; do
  sed -n "/^${fn}() {\$/,/^}\$/p" "$CUTOVER" | sed -e 's/[[:space:]]*#.*$//' >"$SCRATCH/fn.body"
  c="$(grep -cE -- 'local [a-zA-Z_]+="\$\(' "$SCRATCH/fn.body" || true)"
  [ "$c" -gt 0 ] && { masked=$((masked + c)); note "  masked-status site in $fn: $c"; }
done
if [ "$masked" -eq 0 ]; then
  ok "C-localmask: no 'local x=\$(cmd)' in the fix's functions — exit status is not masked in a shell with no -e (AC21)"
else
  fail "C-localmask: $masked 'local x=\$(cmd)' site(s) in the fix's functions — 'local' returns 0 regardless, so a failed findmnt/mktemp never reaches its die (AC21)"
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
