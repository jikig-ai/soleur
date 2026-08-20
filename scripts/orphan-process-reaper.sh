#!/usr/bin/env bash
# orphan-process-reaper.sh — find, and on explicit request reclaim, PROCESSES
# that have outlived their work on this box (#7537).
#
# THIS IS ABOUT PROCESSES. `apps/web-platform/infra/orphan-reaper.sh` already
# exists and is UNRELATED: it is a 33-line systemd-timer script that removes
# stale `.orphaned-*` workspace DIRECTORIES on the production web host. It has
# nothing to do with processes, with /proc, or with this machine. The two names
# are a collision, not a family.
#
# WHAT IT LOOKS FOR, and why the conjunction is this narrow.
# `scripts/tmpfs-guard.sh` reclaims FILES and deliberately skips entries with
# open file descriptors — correct for a live run, and exactly why an orphaned
# process survives it. The gap closed here is a process whose working directory
# and executing script have BOTH been unlinked out from under it, which keeps
# consuming CPU and tmpfs with its output unrecoverable by construction.
#
# The difficulty is the discriminator, not the signal: a detached run and an
# orphaned one look identical under `ps`. So a pid is an ANCHOR only under a
# six-gate conjunction (G1-G6 below, plus G7 on the pid namespace), and any
# error reading any of them leaves the process UNFLAGGED AND ALIVE.
#
# TWO SIGNALS ARE NEVER CONSULTED AT ALL — not "never as a positive term",
# never:
#   * `exe`  — a `claude` self-update unlinks the running binary (~11 live hits
#              measured on this box). Reading it at all would make P2 a
#              polarity discipline instead of a structural property.
#   * `fd/1`, `fd/2` — a deleted stdout with a live cwd IS this repo's own
#              `scripts/tmpfs-guard.sh` cron instance (measured: pid 704313,
#              75 s old and healthy). A reaper keyed on that shape kills the
#              tmpfs guard on its next cron tick.
#
# EVIDENCE STATUS, stated because prose drifts toward the flattering reading:
# the four-way conjunction returned ZERO hits across 222 own-uid processes on
# the probed box. That is evidence of SPECIFICITY in a sample containing no
# orphan. It is NOT evidence of sensitivity — nothing here has ever been
# observed firing on a real orphan in the wild. The only sensitivity evidence
# that exists is the synthesized end-to-end arm in the test suite. That is why
# the trigger REPORTS and never reaps, and why `reap` must be invoked by a
# person or an agent who has read the full set.
#
# WHY NOT proc.sh. `plugins/soleur/scripts/lib/proc.sh` already enumerates and
# signals processes with a full safety apparatus, and deliberately REFUSES a
# deleted cwd — `[[ "$cwd" == *' (deleted)' ]] && return 1` — because for its
# question ("does this process belong to my worktree?") an unresolvable path is
# a refusal. This tool asks the opposite question ("is this inode unlinked?"),
# so the two predicates diverge on purpose. See the reciprocal note there.
#
# SEAMS (every name below is read by the code that follows; a seam that is
# documented but unimplemented produces a test that sets it, observes no
# effect, and passes for the wrong reason):
#   ORPHAN_PROC_ROOT                procfs root                    (default /proc)
#   ORPHAN_REAPER_SELF_PID          pid to treat as the scanner    (default $$)
#   ORPHAN_REAPER_MIN_AGE_S         age floor in seconds           (default 600)
#   ORPHAN_REAPER_MAX_SET           cardinality cap                (default 64)
#   ORPHAN_REAPER_DRY_RUN           set to a non-off value -> rehearse
#   ORPHAN_REAPER_SIGNAL_SINK       FILE PATH pids are appended to (never executed)
#   ORPHAN_REAPER_EVIDENCE_FILE     evidence sink instead of logger
#   ORPHAN_REAPER_LOCKFILE          advisory lock path
#   ORPHAN_REAPER_NO_FLOCK          1 -> skip locking entirely
#   ORPHAN_REAPER_EXCLUDE_PGID      process group to exclude (passed by the caller)
#   ORPHAN_REAPER_SELF_CWD_OVERRIDE scanner cwd, for the structural-refusal arm
#   ORPHAN_REAPER_RECYCLE_PID       fault injection: force a late refusal on this pid
#   ORPHAN_REAPER_FORCE_EUID        fault injection: pretend to be this uid
#
# The last three are FAULT-INJECTION seams and are fail-safe by construction:
# each can only cause a REFUSAL, never an extra signal. They exist because the
# branches they reach (late refusal, structural refusal, root refusal) cannot
# otherwise be driven from a synthesized procfs, and an un-drivable branch is a
# guard that cannot be proved to fire.
#
# Usage:  orphan-process-reaper.sh [report|reap]
# Exit:   0 = the walk completed (whether or not anything was found)
#         1 = the walk was structurally invalid
# Findings live on the summary line, NEVER in the exit code: `test-all.sh`'s
# suite_exit_class() maps anything outside {0, signal range} to `failed`, so a
# "candidates found" exit code would turn the gate red the first time the
# detector ever worked, and the cheapest remedy would be to delete the line.

set -euo pipefail

# --- Seams -----------------------------------------------------------------
# `-` and not `:-` on the root: UNSET must fall back to /proc, but EMPTY-BUT-SET
# must be REFUSED below. scripts/lib/test-contention.sh binds its own root with
# `:-`, so an empty seam there silently reverts the borrowed helpers to the real
# /proc while this script's walk would glob /[0-9]* at the FILESYSTEM ROOT.
ORPHAN_PROC_ROOT="${ORPHAN_PROC_ROOT-/proc}"
ORPHAN_REAPER_SELF_PID="${ORPHAN_REAPER_SELF_PID:-$$}"
ORPHAN_REAPER_MIN_AGE_S="${ORPHAN_REAPER_MIN_AGE_S:-600}"
ORPHAN_REAPER_MAX_SET="${ORPHAN_REAPER_MAX_SET:-64}"
ORPHAN_REAPER_SIGNAL_SINK="${ORPHAN_REAPER_SIGNAL_SINK:-}"
ORPHAN_REAPER_EVIDENCE_FILE="${ORPHAN_REAPER_EVIDENCE_FILE:-}"
ORPHAN_REAPER_NO_FLOCK="${ORPHAN_REAPER_NO_FLOCK:-0}"
ORPHAN_REAPER_EXCLUDE_PGID="${ORPHAN_REAPER_EXCLUDE_PGID:-}"
ORPHAN_REAPER_SELF_CWD_OVERRIDE="${ORPHAN_REAPER_SELF_CWD_OVERRIDE:-}"
ORPHAN_REAPER_RECYCLE_PID="${ORPHAN_REAPER_RECYCLE_PID:-}"
ORPHAN_REAPER_FORCE_EUID="${ORPHAN_REAPER_FORCE_EUID:-}"

MODE="${1:-report}"

say() { printf '[orphan-process-reaper] %s\n' "$1" >&2; }

# The canonical byte-wise sanitizer (plugins/soleur/scripts/lib/proc.sh). LC_ALL=C
# is load-bearing and pinned: it is what makes the class byte-wise, so \x7f,
# U+2028 and U+2029 fall out as non-printable BYTES rather than being treated as
# printable characters in a UTF-8 locale.
_orphan_sanitize() { printf '%s' "${1:-}" | LC_ALL=C tr -c '[:print:]' '?'; }

# --- Counters --------------------------------------------------------------
# `unreadable` is load-bearing, not decoration: the fail-toward-alive rule
# silently drops candidates, and without a count of those drops there is no
# evidence distinguishing "no orphans" from "the conjunction is unsatisfiable in
# production". The staged counters below it exist because a foreign-uid or
# no-fd/255 pre-filter miss is a ~417-pid constant baseline on this box that
# would otherwise swamp the signal.
scanned=0; anchors=0; set_members=0; would_signal=0; signalled=0
failed=0; refused=0; refused_cap=0; late_refused=0
skipped_same_pgroup=0; skipped_foreign_ns=0; skipped_foreign_uid=0
prefiltered_no_fd255=0; unreadable=0; unreadable_denied=0; unreadable_gone=0
valid=1; evidence=down

# Deferred output: attacker-influenceable values are emitted LAST, one per line
# (AC23). Spaces, `=` and `/` are printable and SURVIVE the tr pass, so a
# directory named `x signalled pid=1 cwd=/y` would otherwise render verbatim
# inside a report line — indistinguishable from a real kill record to a reader,
# to a `grep signalled`, and to the suite's own negative assertion.
PATH_LINES=()

emit_summary() {
  printf 'ORPHAN_SCAN valid=%s mode=%s scanned=%s anchors=%s set_members=%s would_signal=%s signalled=%s failed=%s refused=%s refused_cap=%s late_refused=%s skipped_same_pgroup=%s skipped_foreign_ns=%s skipped_foreign_uid=%s prefiltered_no_fd255=%s unreadable=%s unreadable_denied=%s unreadable_gone=%s evidence=%s\n' \
    "$valid" "$MODE" "$scanned" "$anchors" "$set_members" "$would_signal" \
    "$signalled" "$failed" "$refused" "$refused_cap" "$late_refused" \
    "$skipped_same_pgroup" "$skipped_foreign_ns" "$skipped_foreign_uid" \
    "$prefiltered_no_fd255" "$unreadable" "$unreadable_denied" \
    "$unreadable_gone" "$evidence"
  local l
  for l in ${PATH_LINES[@]+"${PATH_LINES[@]}"}; do printf '%s\n' "$l"; done
}

die_invalid() {  # reason
  valid=0
  say "structurally invalid walk: $1"
  emit_summary
  exit 1
}

# --- CI (AC28j) ------------------------------------------------------------
# test-all.sh runs on GitHub-hosted runners in three ci.yml shards and in
# main-health-monitor.yml. The existing CI exemption guards tc_acquire, not the
# preamble, so this needs its own.
if [[ -n "${CI:-}" ]]; then
  say "CI detected — skipping the /proc walk (no orphans to reclaim on an ephemeral runner)"
  exit 0
fi

# --- Privilege floor (AC28b) ----------------------------------------------
# G1 is `stat -Lc '%u' == id -u`, so under sudo "own uid" silently becomes uid 0
# and the enforcement-by-accident (readlink failing on a foreign process)
# evaporates — measured, `readlink /proc/1/cwd` fails as uid 1001 and succeeds
# as root. The reap set would become EVERY root process with an unlinked cwd, a
# populated class on a box mid-apt transaction. The banner below prints a `reap`
# command an operator may reflexively prefix with sudo when it "doesn't work",
# so this is the realistic path rather than a hypothetical one.
_euid="${ORPHAN_REAPER_FORCE_EUID:-${EUID:-$(id -u)}}"
if [[ "$_euid" == "0" ]]; then
  say "refusing to run as root: G1 would PASS for every root process and the reap set would become box-wide"
  valid=0
  emit_summary
  exit 1
fi
SELF_UID="$(id -u)"

# --- Seam validation, before anything is assigned anywhere -----------------
if [[ -z "$ORPHAN_PROC_ROOT" ]]; then
  die_invalid "ORPHAN_PROC_ROOT is set but empty — refusing rather than reverting to /proc"
fi
if [[ "$ORPHAN_PROC_ROOT" != /* ]]; then
  die_invalid "ORPHAN_PROC_ROOT must be absolute, got '$(_orphan_sanitize "$ORPHAN_PROC_ROOT")'"
fi
if [[ ! -d "$ORPHAN_PROC_ROOT" ]]; then
  die_invalid "ORPHAN_PROC_ROOT is not a directory"
fi

# Procfs identity, NOT name (AC28c). A `!= /proc` string comparison refuses
# harmless aliases while permitting the one dangerous case it cannot see: a
# procfs from a foreign PID namespace bind-mounted at /proc, whose pids are not
# pids in this process's kill namespace. Measured: `proc` for /proc, `tmpfs` for
# /tmp.
_rootfstype=""
_rootfstype=$(stat -fc '%T' "$ORPHAN_PROC_ROOT" 2>/dev/null) || _rootfstype=""
ROOT_IS_PROCFS=0
[[ "$_rootfstype" == "proc" ]] && ROOT_IS_PROCFS=1

# --- Borrowed primitives ---------------------------------------------------
# TC_PROC_ROOT and TC_SELF_PID are set from THIS script's own seams BEFORE the
# source. These — not TC_TMPDIR — are the seams that govern the borrowed
# helpers: _tc_self_and_ancestors() reads both as globals. test-all.sh exports
# TC_TMPDIR and neither of the other two, so pinning only this script's procfs
# seam would leave self-exclusion reading the REAL /proc, making the
# self-exclusion arms assert nothing and letting a synthetic pid collide with a
# live one.
TC_PROC_ROOT="$ORPHAN_PROC_ROOT"
TC_SELF_PID="$ORPHAN_REAPER_SELF_PID"
export TC_PROC_ROOT TC_SELF_PID
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/test-contention.sh"
# shellcheck source=/dev/null
. "$_LIB"

# Only three PRIVATE readers are borrowed. No public tc_* verb is called:
# tc_acquire locks with a 3600 s budget (a preamble probe must never queue
# behind a whole suite) and tc_preamble performs the measured 6.6 s walk.
#
# The assertion is not decoration. These names are underscore-private, so an
# upstream rename silently empties the exclusion set — and errexit does not
# rescue it, because `local x=$(_tc_pgrp …)` masks the substitution's status
# behind `local`'s own return of 0.
declare -F _tc_self_and_ancestors >/dev/null 2>&1 || \
  die_invalid "borrowed primitive _tc_self_and_ancestors is missing — the exclusion set would silently empty"
declare -F _tc_pgrp >/dev/null 2>&1 || \
  die_invalid "borrowed primitive _tc_pgrp is missing — the process-group exclusion would silently empty"
declare -F _tc_starttime_ticks >/dev/null 2>&1 || \
  die_invalid "borrowed primitive _tc_starttime_ticks is missing — the age floor would have no operand"

CLK_TCK="$(getconf CLK_TCK 2>/dev/null || echo 100)"
[[ "$CLK_TCK" =~ ^[0-9]+$ ]] && [[ "$CLK_TCK" -gt 0 ]] || CLK_TCK=100

# --- Evidence channel (AC28g) ---------------------------------------------
# Probed ONCE at startup and printed on the counter line. Without the probe the
# tool either silently becomes report-only forever or proceeds believing it
# recorded — and after a successful kill the /proc entry is gone, so the
# evidence links can never be re-examined by anyone.
if [[ -n "$ORPHAN_REAPER_EVIDENCE_FILE" ]]; then
  if printf '' >> "$ORPHAN_REAPER_EVIDENCE_FILE" 2>/dev/null; then evidence=ok; fi
elif command -v logger >/dev/null 2>&1; then
  evidence=ok
fi

evidence_write() {  # record
  if [[ -n "$ORPHAN_REAPER_EVIDENCE_FILE" ]]; then
    printf '%s\n' "$1" >> "$ORPHAN_REAPER_EVIDENCE_FILE" 2>/dev/null || return 1
    return 0
  fi
  logger -t orphan-process-reaper -- "$1" 2>/dev/null || return 1
  return 0
}

# --- The unlinked predicate — EXACTLY ONE SITE ----------------------------
# Link count is the kernel's own answer to "is this inode unlinked". One syscall
# on the magic link; it never re-resolves the reported path, and it is therefore
# immune to all three problems the earlier designs worked around:
#   * the `' (deleted)'` suffix is a string the KERNEL appends, and a directory
#     may legitimately carry it (measured: st_nlink 2 for a live directory
#     literally named `work (deleted)`, versus 0 for a genuinely deleted cwd);
#   * an inode NUMBER is unique per device, not globally;
#   * a `%d:%i` comparison needs two stats with a window between them.
# All three disappear rather than being defended against.
#
# The PROPERTY is "genuinely unlinked, namespace-independently". st_nlink is
# today's mechanism for it — the tests are written against the property, so
# switching mechanism later does not read as weakening a guard.
_orphan_is_unlinked() {  # link-path
  local n
  n=$(stat -Lc '%h' "$1" 2>/dev/null) || return 1
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  [[ "$n" == "0" ]]
}

_orphan_nlink() {  # link-path -> prints nlink or '?'
  local n
  n=$(stat -Lc '%h' "$1" 2>/dev/null) || n="?"
  printf '%s' "$n"
}

_orphan_cwd_key() {  # pid -> prints dev:inode, or empty
  # DEVICE-QUALIFIED, never bare %i. R2a retired the %d:%i comparison from the
  # DELETEDNESS test, but set membership is still an inode-NUMBER equality test
  # and the cross-device collision applies to it verbatim: /tmp is dev 50
  # (tmpfs) and a worktree is dev 66307 (ext4), and tmpfs hands inode numbers
  # from a monotonic counter, so the number an own-uid process's directory
  # receives is STEERABLE. Without %d an unrelated process can be walked into a
  # foreign anchor's reap set while both independently pass every gate —
  # restating the gates per member does not catch it, because each is genuinely
  # unlinked.
  local k
  k=$(stat -Lc '%d:%i' "$ORPHAN_PROC_ROOT/$1/cwd" 2>/dev/null) || k=""
  printf '%s' "$k"
}

# --- Exclusion set (G4) ----------------------------------------------------
SELF_CHAIN=" $(_tc_self_and_ancestors)"
SELF_PGID=""
if [[ -n "$ORPHAN_REAPER_EXCLUDE_PGID" ]]; then
  # Passed in EXPLICITLY by the caller rather than inferred. `timeout` runs its
  # child in its own process group, so computing the pgid here at a call site
  # wrapped in `timeout` would return timeout's pid rather than the suite's, and
  # the suite's own command-substitution forks would not be excluded.
  SELF_PGID="$ORPHAN_REAPER_EXCLUDE_PGID"
else
  SELF_PGID=$(_tc_pgrp "$ORPHAN_PROC_ROOT/$ORPHAN_REAPER_SELF_PID/stat") || SELF_PGID=""
fi
[[ "$SELF_PGID" =~ ^[0-9]+$ ]] || SELF_PGID=""

NS_MNT_SELF=""
NS_MNT_SELF=$(readlink "$ORPHAN_PROC_ROOT/$ORPHAN_REAPER_SELF_PID/ns/mnt" 2>/dev/null) || NS_MNT_SELF=""
[[ -n "$NS_MNT_SELF" ]] || { NS_MNT_SELF=$(readlink /proc/self/ns/mnt 2>/dev/null) || NS_MNT_SELF=""; }
NS_PID_SELF=""
NS_PID_SELF=$(readlink "$ORPHAN_PROC_ROOT/$ORPHAN_REAPER_SELF_PID/ns/pid" 2>/dev/null) || NS_PID_SELF=""
[[ -n "$NS_PID_SELF" ]] || { NS_PID_SELF=$(readlink /proc/self/ns/pid 2>/dev/null) || NS_PID_SELF=""; }

# The scanner's own cwd identity, for the structural refusal.
SELF_CWD_KEY=""
if [[ -n "$ORPHAN_REAPER_SELF_CWD_OVERRIDE" ]]; then
  SELF_CWD_KEY=$(stat -Lc '%d:%i' "$ORPHAN_REAPER_SELF_CWD_OVERRIDE" 2>/dev/null) || SELF_CWD_KEY=""
else
  SELF_CWD_KEY=$(stat -Lc '%d:%i' /proc/self/cwd 2>/dev/null) || SELF_CWD_KEY=""
fi

# --- Uptime (G6 base) ------------------------------------------------------
# Read from the SEAM ROOT, never a literal /proc/uptime. Against a fixture root,
# differencing a synthesized starttime from the real box uptime yields
# meaningless ages, makes the two-direction age arm impossible, and makes the
# unreadable-uptime case unreachable.
UPTIME_S=""
if [[ -r "$ORPHAN_PROC_ROOT/uptime" ]]; then
  UPTIME_S=$(awk '{print int($1)}' "$ORPHAN_PROC_ROOT/uptime" 2>/dev/null) || UPTIME_S=""
fi
[[ "$UPTIME_S" =~ ^[0-9]+$ ]] || UPTIME_S=""

# --- The classification chokepoint ----------------------------------------
# ONE function. Both verbs consume this one walk's classified output without
# re-deriving a verdict, and the gate set quantifies over MEMBERS as well as
# anchors. A second classification site — a verb testing a link itself, a "quick
# pre-filter" that decides rather than narrows — makes the guard narrower than
# the property it claims.
#
# Returns 0 when the pid qualifies for the requested role, non-zero otherwise.
# Sets _OC_* for the caller. EVERY failure path leaves the process ALIVE.
_OC_AGE=""; _OC_STARTTIME=""; _OC_CWD_KEY=""; _OC_CWD_NLINK=""; _OC_FD255_NLINK=""
_orphan_classify() {  # pid role(anchor|member)
  local pid="$1" role="$2" d="$ORPHAN_PROC_ROOT/$1"
  _OC_AGE=""; _OC_STARTTIME=""; _OC_CWD_KEY=""; _OC_CWD_NLINK="?"; _OC_FD255_NLINK="?"

  # G1 — own uid. The `-L` is load-bearing and gets its own assertion:
  # measured, `stat -c '%u'` on a symlink reports the LINK's uid while
  # `stat -Lc '%u'` reports the target's, so the un-dereferenced form silently
  # classifies every foreign process as own-uid. Enforcement is structurally
  # redundant (readlink fails on a foreign process) — which is exactly why the
  # counter matters: without a field whose value differs, removing this gate has
  # no observable at all.
  local owner
  owner=$(stat -Lc '%u' "$d" 2>/dev/null) || owner=""
  if [[ ! "$owner" =~ ^[0-9]+$ ]]; then
    unreadable=$((unreadable + 1)); unreadable_gone=$((unreadable_gone + 1)); return 1
  fi
  if [[ "$owner" != "$SELF_UID" ]]; then
    skipped_foreign_uid=$((skipped_foreign_uid + 1)); return 1
  fi

  # G4 — not the scanner, an ancestor, or its process group. Applied HERE, so it
  # quantifies over members too. An earlier draft applied it to anchors only:
  # run `git worktree remove` on a worktree with a suite running inside it and
  # test-all.sh, the reaper it spawned, and every suite child share ONE unlinked
  # cwd — so the reap set becomes the caller's entire process tree and the
  # reaper kills its own ancestors.
  if [[ "$SELF_CHAIN" == *" $pid "* ]]; then return 1; fi
  local pgid
  pgid=$(_tc_pgrp "$d/stat") || pgid=""
  if [[ "$pgid" =~ ^[0-9]+$ ]] && [[ -n "$SELF_PGID" ]] && [[ "$pgid" == "$SELF_PGID" ]]; then
    skipped_same_pgroup=$((skipped_same_pgroup + 1)); return 1
  fi

  # G5 — same mount namespace. Sandboxed processes (bwrap, rootless containers,
  # `unshare -m`, all of which this repo runs own-uid by design) routinely
  # operate with an unlinked or namespace-private cwd as NORMAL operation, and
  # their lifecycle belongs to their supervisor, not to this tool. Refuse to
  # adjudicate rather than guessing.
  local ns
  ns=$(readlink "$d/ns/mnt" 2>/dev/null) || ns=""
  if [[ -z "$ns" ]]; then
    unreadable=$((unreadable + 1)); unreadable_denied=$((unreadable_denied + 1)); return 1
  fi
  if [[ -n "$NS_MNT_SELF" && "$ns" != "$NS_MNT_SELF" ]]; then
    skipped_foreign_ns=$((skipped_foreign_ns + 1)); return 1
  fi

  # G7 — same pid namespace. G5 covers ns/mnt and nothing covered ns/pid; a
  # foreign pid namespace means these pids are not pids in this process's kill
  # namespace.
  local nsp
  nsp=$(readlink "$d/ns/pid" 2>/dev/null) || nsp=""
  if [[ -z "$nsp" ]]; then
    unreadable=$((unreadable + 1)); unreadable_denied=$((unreadable_denied + 1)); return 1
  fi
  if [[ -n "$NS_PID_SELF" && "$nsp" != "$NS_PID_SELF" ]]; then
    skipped_foreign_ns=$((skipped_foreign_ns + 1)); return 1
  fi

  # G2 — cwd genuinely unlinked.
  _OC_CWD_NLINK="$(_orphan_nlink "$d/cwd")"
  if ! _orphan_is_unlinked "$d/cwd"; then
    # A failed stat and a live directory are DIFFERENT outcomes, and only the
    # first is a reading error. Both leave the process alive.
    if [[ "$_OC_CWD_NLINK" == "?" ]]; then
      unreadable=$((unreadable + 1)); unreadable_gone=$((unreadable_gone + 1))
    fi
    return 1
  fi
  _OC_CWD_KEY="$(_orphan_cwd_key "$pid")"
  [[ -n "$_OC_CWD_KEY" ]] || { unreadable=$((unreadable + 1)); return 1; }

  # G3 — anchors only: fd/255 is an unlinked REGULAR FILE at an ABSOLUTE path
  # ending `' (deleted)'`. All three terms, because `%h == 0` alone is far
  # broader than "the bash script is unlinked": measured, a memfd_create file
  # has nlink 0 and reports as a regular file, so any process holding a memfd on
  # fd 255 satisfies a bare link-count test with no bash, no script and no
  # orphan — and an anchor authorizes a whole REAP SET. Pipes, unix sockets and
  # eventfds are nlink 1 and were never the risk. The two added terms are
  # NARROWING and fail toward alive, so neither re-opens the polarity problem
  # the link-count test closed: the suffix test is dangerous only as a SOLE term.
  if [[ "$role" == "anchor" ]]; then
    local fdl
    fdl=$(readlink "$d/fd/255" 2>/dev/null) || fdl=""
    _OC_FD255_NLINK="$(_orphan_nlink "$d/fd/255")"
    if [[ -z "$fdl" ]]; then
      unreadable=$((unreadable + 1)); unreadable_denied=$((unreadable_denied + 1)); return 1
    fi
    [[ "$fdl" == /* ]] || return 1
    [[ "$fdl" == *' (deleted)' ]] || return 1
    _orphan_is_unlinked "$d/fd/255" || {
      [[ "$_OC_FD255_NLINK" == "?" ]] && { unreadable=$((unreadable + 1)); unreadable_gone=$((unreadable_gone + 1)); }
      return 1
    }
    local ftype
    ftype=$(stat -Lc '%F' "$d/fd/255" 2>/dev/null) || ftype=""
    [[ "$ftype" == "regular file" || "$ftype" == "regular empty file" ]] || return 1
  fi

  # G6 — older than the age floor.
  #
  # THE MEASURED FAIL-OPEN this validation closes: `_tc_stat_field` returns EXIT
  # 0 WITH EMPTY OUTPUT on an unreadable stat file, and empty is arithmetic zero
  # even under `set -u`, so `(( (now - "") > 600 ))` PASSES — the gate whose
  # entire job is to spare fresh processes fails open. The same emptiness makes
  # starttime-based identity vacuous, since empty-at-scan equals empty-at-signal.
  # A non-numeric reading is `unreadable`, never a verdict.
  local st
  st=$(_tc_starttime_ticks "$d/stat") || st=""
  if [[ ! "$st" =~ ^[0-9]+$ ]]; then
    unreadable=$((unreadable + 1)); unreadable_gone=$((unreadable_gone + 1)); return 1
  fi
  if [[ -z "$UPTIME_S" ]]; then
    unreadable=$((unreadable + 1)); unreadable_denied=$((unreadable_denied + 1)); return 1
  fi
  _OC_STARTTIME="$st"
  local age=$(( UPTIME_S - (st / CLK_TCK) ))
  _OC_AGE="$age"
  if (( age < ORPHAN_REAPER_MIN_AGE_S )); then return 1; fi

  return 0
}

# --- Advisory lock, matching the scripts/tmpfs-guard.sh precedent ----------
# Its OWN non-blocking flock. NEVER tc_acquire: that lock serialises whole
# suites with a 3600 s budget, and a preamble probe must not queue behind one.
#
# Two details in the precedent are hard-won and are the reason for adopting it
# wholesale rather than inventing a variant:
#   * On contention it LOGS and exits 0 — never silently. A silent skip is
#     indistinguishable from "ran and found nothing", which is the exact
#     confusion the valid/scanned counters exist to prevent.
#   * If the lockfile cannot be CREATED it runs UNSERIALISED and says so. It
#     must never fall back to `exec 9>/dev/null`: that locks the /dev/null
#     inode, which is shared with every process on the box, so an unrelated
#     flocker would block this run indefinitely and it would then report
#     "another run is in flight" — which is false, at the worst possible moment.
if [[ "$ORPHAN_REAPER_NO_FLOCK" != "1" ]] && command -v flock >/dev/null 2>&1; then
  _lockfile="${ORPHAN_REAPER_LOCKFILE:-${TMPDIR:-/tmp}/.orphan-process-reaper-$(id -u).lock}"
  # Creatability is probed with `:` FIRST, deliberately, and the `exec` below
  # carries NO stderr redirection of its own. `exec 9>"$f" 2>/dev/null` — the
  # obvious form, and the one the precedent uses — applies BOTH redirections to
  # the CURRENT SHELL permanently, so every later `say` (including the "another
  # run is in flight" line this block exists to print) is silently discarded for
  # the rest of the run. Measured here: the contention path took the correct
  # branch, exited 0, and printed nothing at all, which is indistinguishable
  # from "ran and found nothing" — the exact confusion the counters exist to
  # prevent.
  if : >> "$_lockfile" 2>/dev/null; then
    exec 9>> "$_lockfile"
    if ! flock -n 9; then
      say "another orphan-process-reaper run is in flight — skipping"
      exit 0
    fi
  else
    say "lockfile unavailable ($(_orphan_sanitize "$_lockfile")) — running unserialised"
  fi
fi

# --- The walk --------------------------------------------------------------
# ONE guarded walk, pre-filtered on fd/255 EXISTENCE before anything is stat'ed.
# Measured: 31 pids box-wide carry an fd/255 (30 bash + 1 dbus-daemon) out of
# 592, so the pre-filter is what keeps this cheap enough to sit on the repo's
# hottest path.
#
# `[[ -d "$d" && ! -L "$d" ]] || continue` — both terms load-bearing. Bash
# WITHOUT nullglob iterates a non-matching pattern ONCE, LITERALLY (measured),
# and nullglob is set in none of the three sibling libraries, so an empty procfs
# would otherwise report scanned=1. And `[[ -d ]]` is TRUE for a
# symlink-to-directory while every downstream read is `stat -L`, which follows
# it silently: real /proc has no numeric symlink entries, but a fixture root or
# an operator-supplied root does.
ANCHOR_PIDS=()
ANCHOR_KEYS=()
ALL_PIDS=()

for d in "$ORPHAN_PROC_ROOT"/[0-9]*; do
  [[ -d "$d" && ! -L "$d" ]] || continue
  pid="${d##*/}"
  # `^[1-9][0-9]*$`, never `^[0-9]+$`: the permissive form admits both `0` and
  # `0777`, and `kill -TERM 0` signals the CALLER'S ENTIRE PROCESS GROUP — for
  # an operator running `reap` from their own shell, that is their foreground
  # job. Real /proc never produces such entries, which is exactly why only the
  # seam path can reach them, and the seam path is the one already treated as
  # dangerous.
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue
  scanned=$((scanned + 1))
  ALL_PIDS+=("$pid")
  if [[ ! -e "$d/fd/255" && ! -L "$d/fd/255" ]]; then
    prefiltered_no_fd255=$((prefiltered_no_fd255 + 1))
    continue
  fi
  if _orphan_classify "$pid" anchor; then
    ANCHOR_PIDS+=("$pid")
    ANCHOR_KEYS+=("$_OC_CWD_KEY")
    anchors=$((anchors + 1))
    printf 'anchor pid=%s age=%s uid=%s starttime=%s cwd_nlink=%s fd255_nlink=%s\n' \
      "$pid" "$_OC_AGE" "$SELF_UID" "$_OC_STARTTIME" "$_OC_CWD_NLINK" "$_OC_FD255_NLINK"
    _cwdl=$(readlink "$d/cwd" 2>/dev/null) || _cwdl=""
    PATH_LINES+=("path pid=$pid kind=cwd value=$(_orphan_sanitize "$_cwdl")")
    _fdl=$(readlink "$d/fd/255" 2>/dev/null) || _fdl=""
    PATH_LINES+=("path pid=$pid kind=fd255 value=$(_orphan_sanitize "$_fdl")")
  fi
done

# --- The reap set ----------------------------------------------------------
# Anchors are what the detector IDENTIFIES; the reap set is what a confirmed
# anchor AUTHORIZES.
#
# The conjunction the issue specifies flags exactly one process — the bash
# wrapper — and leaves the non-bash child that is actually holding the cores:
# measured, `fd/255` is bash's script descriptor and is structurally absent on
# every non-shell process. The issue is written about reclaiming 62 CPU-minutes,
# and a mutation battery's CPU lives in its children. So the conjunction is
# preserved verbatim as the ANCHOR, and a confirmed anchor extends to every
# own-uid process whose cwd resolves to the SAME deleted dev:inode pair —
# measured identical across all three processes in that shape, because children
# inherit cwd across fork and an unlinked directory keeps its inode. That is
# exact set membership, not a heuristic, and no process is ever reaped without a
# confirmed anchor.
#
# Membership RESTATES every gate on the member's own links; it never inherits
# the anchor's verdict.
SET_PIDS=()
SET_ROLES=()
SET_ANCHOR=()
SET_STARTTIME=()
SET_AGE=()
SET_CWDNL=()
SET_FDNL=()

if (( anchors > 0 )); then
  for i in "${!ANCHOR_PIDS[@]}"; do
    a_pid="${ANCHOR_PIDS[$i]}"
    a_key="${ANCHOR_KEYS[$i]}"
    [[ -n "$a_key" ]] || continue

    # STRUCTURAL REFUSAL — the scanner is inside the doomed directory and cannot
    # adjudicate it.
    if [[ -n "$SELF_CWD_KEY" && "$SELF_CWD_KEY" == "$a_key" ]]; then
      die_invalid "the scanner's own cwd is the candidate inode — it cannot adjudicate the directory it is standing in"
    fi

    members=()
    for p in ${ALL_PIDS[@]+"${ALL_PIDS[@]}"}; do
      [[ "$p" == "$a_pid" ]] && continue
      k="$(_orphan_cwd_key "$p")"
      [[ -n "$k" && "$k" == "$a_key" ]] || continue
      _orphan_classify "$p" member || continue
      members+=("$p")
    done

    total=$(( ${#members[@]} + 1 ))

    # CARDINALITY CAP. The default is measured against the motivating incident
    # rather than guessed: `git worktree remove` under a running test-all.sh
    # produces a suite tree far wider than the 8 an earlier draft proposed, so
    # that value would have refused precisely the incident this tool exists for.
    # The cap bars AUTOMATIC action only — the full set is always reported, and
    # `reap` takes an explicit override the banner names, so it is a speed bump
    # for a human rather than a wall for the tool. It is also a free
    # denial-of-reaping (any own-uid process can fchdir into the doomed inode
    # enough times to hold a set over the cap), which is a further reason it
    # must not be a hard wall.
    over_cap=0
    if (( total > ORPHAN_REAPER_MAX_SET )); then
      over_cap=1
      refused_cap=$((refused_cap + 1))
      say "set for anchor $a_pid has $total members, over the cap of $ORPHAN_REAPER_MAX_SET — refusing to act automatically; re-run with ORPHAN_REAPER_MAX_SET=$total to override"
    fi

    for p in ${members[@]+"${members[@]}"}; do
      set_members=$((set_members + 1))
      printf 'member pid=%s anchor=%s\n' "$p" "$a_pid"
      if (( over_cap == 0 )); then
        _orphan_classify "$p" member || continue
        SET_PIDS+=("$p"); SET_ROLES+=("member"); SET_ANCHOR+=("$a_pid")
        SET_STARTTIME+=("$_OC_STARTTIME"); SET_AGE+=("$_OC_AGE")
        SET_CWDNL+=("$_OC_CWD_NLINK"); SET_FDNL+=("$_OC_FD255_NLINK")
      fi
    done
    # The anchor itself counts as a set member for reporting.
    set_members=$((set_members + 1))
    if (( over_cap == 0 )); then
      _orphan_classify "$a_pid" anchor || continue
      SET_PIDS+=("$a_pid"); SET_ROLES+=("anchor"); SET_ANCHOR+=("$a_pid")
      SET_STARTTIME+=("$_OC_STARTTIME"); SET_AGE+=("$_OC_AGE")
      SET_CWDNL+=("$_OC_CWD_NLINK"); SET_FDNL+=("$_OC_FD255_NLINK")
    fi
  done
fi

would_signal="${#SET_PIDS[@]}"

# --- Verbs -----------------------------------------------------------------
case "$MODE" in
  report)
    if (( would_signal > 0 )); then
      # Name the exact command for the set that was found. This is the whole
      # trigger design: the contention is paid at suite launch, where an actor —
      # operator or agent — is present and already reading stderr, so the first
      # strike is a READER'S JUDGMENT rather than a state file. An earlier
      # channel wrote to an alarm file that its own health predicate deleted
      # five minutes later; that was worse than a report nobody acts on, it was
      # a report nobody RECEIVES.
      printf 'reap_command bash scripts/orphan-process-reaper.sh reap\n'
      say "$would_signal process(es) look orphaned; nothing has been signalled. Review the set above, then run: bash scripts/orphan-process-reaper.sh reap"
    fi
    emit_summary
    exit 0
    ;;
  reap) ;;
  *)
    say "unknown verb '$(_orphan_sanitize "$MODE")' — expected report or reap"
    valid=0
    emit_summary
    exit 1
    ;;
esac

# --- reap ------------------------------------------------------------------
# SEAM SAFETY. The walk globs "$ORPHAN_PROC_ROOT"/[0-9]* and fixtures are
# directories named like `4242`. Real pids on this box were measured in the
# 2.9-million range, but LOW pids are live. So `reap` refuses outright when the
# root is not a real procfs unless a signal sink is injected — a seam that is
# documented but unimplemented produces a test that passes for the wrong reason.
if (( ROOT_IS_PROCFS == 0 )) && [[ -z "$ORPHAN_REAPER_SIGNAL_SINK" ]]; then
  say "refusing to reap: ORPHAN_PROC_ROOT is not a procfs and no signal sink was injected — a fixture directory named for a live pid would receive a real TERM"
  valid=0
  emit_summary
  exit 1
fi

# The evidence channel must be live BEFORE anything is signalled. After a
# successful kill the /proc entry is gone, so the evidence links can never be
# re-examined by anyone — and the victim class has unrecoverable output by
# construction, so this is the only record that a false positive ever happened.
if [[ "$evidence" != "ok" ]]; then
  say "refusing to reap: the evidence channel is down, and an unrecorded reap of an unrecoverable-output process leaves no trace that a false positive happened"
  refused=$((refused + 1))
  emit_summary
  exit 1
fi

# Fail-safe dry-run parsing: anything other than an EXPLICIT off value means
# rehearsal, because proc.sh already paid for the alternative — PROC_SH_DRY_RUN=true
# once performed a real kill on a rehearsal request. An UNSET seam is a real run,
# because the verb itself is the explicit request.
DRY=0
if [[ -n "${ORPHAN_REAPER_DRY_RUN+set}" ]]; then
  case "${ORPHAN_REAPER_DRY_RUN}" in
    0|no|NO|false|FALSE|off|OFF) DRY=0 ;;
    *) DRY=1 ;;
  esac
fi

signal_one() {  # index
  local i="$1" pid="${SET_PIDS[$1]}" role="${SET_ROLES[$1]}"
  local d="$ORPHAN_PROC_ROOT/$pid"

  # Re-verification at the signal site covers pid recycling AND inode recycling,
  # which are the same class: an inode number is pinned only while something
  # holds it, and /tmp is tmpfs with fast churn, so a set membership computed at
  # T0 is not evidence at T1.
  local now_st
  now_st=$(_tc_starttime_ticks "$d/stat") || now_st=""
  if [[ -n "$ORPHAN_REAPER_RECYCLE_PID" && "$pid" == "$ORPHAN_REAPER_RECYCLE_PID" ]]; then
    now_st="__recycled__"   # fault injection; can only cause a REFUSAL
  fi
  if [[ ! "$now_st" =~ ^[0-9]+$ ]] || [[ "$now_st" != "${SET_STARTTIME[$i]}" ]]; then
    late_refused=$((late_refused + 1)); return 0
  fi
  if ! _orphan_is_unlinked "$d/cwd"; then
    late_refused=$((late_refused + 1)); return 0
  fi
  if ! _orphan_classify "$pid" "$role"; then
    late_refused=$((late_refused + 1)); return 0
  fi
  # The anchor must still be alive and still unlinked.
  if ! _orphan_is_unlinked "$ORPHAN_PROC_ROOT/${SET_ANCHOR[$i]}/cwd"; then
    late_refused=$((late_refused + 1)); return 0
  fi
  # Operand validation AT THE SIGNAL SITE, not only at the walk.
  if [[ ! "$pid" =~ ^[1-9][0-9]*$ ]] || [[ "$pid" == "1" ]]; then
    refused=$((refused + 1)); return 0
  fi

  local cmdline=""
  cmdline=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || cmdline=""
  # Verdict FIRST, attacker-influenceable cmdline LAST.
  local rec
  rec="orphan-reap verdict=authorized pid=$pid role=$role uid=$SELF_UID starttime=${SET_STARTTIME[$i]} age=${SET_AGE[$i]} cwd_nlink=${SET_CWDNL[$i]} fd255_nlink=${SET_FDNL[$i]} anchor=${SET_ANCHOR[$i]} cmdline=$(_orphan_sanitize "$cmdline")"
  if ! evidence_write "$rec"; then
    say "evidence write failed for pid $pid — refusing to signal it unrecorded"
    refused=$((refused + 1)); return 0
  fi

  if (( DRY == 1 )); then
    return 0
  fi

  if [[ -n "$ORPHAN_REAPER_SIGNAL_SINK" ]]; then
    printf '%s\n' "$pid" >> "$ORPHAN_REAPER_SIGNAL_SINK" 2>/dev/null || { failed=$((failed + 1)); return 0; }
  else
    # TERM only, one pid at a time, never to a process group, no automatic
    # escalation to KILL. Quoted and `--`-terminated at the signal site.
    kill -TERM -- "$pid" 2>/dev/null || { failed=$((failed + 1)); return 0; }
  fi
  signalled=$((signalled + 1))
  printf 'signalled pid=%s role=%s\n' "$pid" "$role"
  return 0
}

# CHILDREN BEFORE THE ANCHOR, so a supervising parent cannot respawn them.
for i in "${!SET_PIDS[@]}"; do
  [[ "${SET_ROLES[$i]}" == "member" ]] || continue
  signal_one "$i"
done
for i in "${!SET_PIDS[@]}"; do
  [[ "${SET_ROLES[$i]}" == "anchor" ]] || continue
  signal_one "$i"
done

emit_summary
exit 0
