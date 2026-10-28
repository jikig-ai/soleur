#!/usr/bin/env bash
# watch-brand-hex-triggers-11177.sh — weekly test of the two "re-evaluate when" triggers on the
# brand-hex-gate tracker (#11177). NOTIFY-ONLY: the tracker is never closed, reopened, relabelled
# or edited; the only GitHub writes are `issue comment` (via wn_post in the shared library) and
# the only reads are `issue view`. It comments ONLY when a trigger fires, never otherwise.
#
# RESIDUAL (accepted, bounded): a commit judged CLEAN leaves no sentinel, so the commits inside the
# window are judged again every Monday, up to the candidate cap and the run budget below (about
# ten runner-minutes a week at the cap); findings and unjudgeable commits are sentineled and never
# re-run. The gate judged at HEAD, not at each commit's own time, so a later gate tightening can
# report an old commit that was legal when made - the comment calls every finding a lead.
#
# Trigger 1 - a third hook sources the simulated index. Tracked `.claude/hooks/*.sh` and any
#   tracked `plugins/**/hooks/*.sh` (read with `git ls-files`/`git show`, never the working tree),
#   minus anything under lib/ and *.test.sh, minus git-commit-secret-scan.sh and
#   brand-hex-commit-gate.sh (the gate adopting the lib IS the planned change, so it must not
#   fire), fires when a NON-comment line names `commit-index-sim`. An empty tracked-hook listing is
#   exit 3, never "clean". Notified once: key `trigger-1:v1`.
#   LIMIT: it only sees hooks that name the lib DIRECTLY in `.claude/hooks/*.sh` or
#   `plugins/**/hooks/*.sh`. A hook that reaches it through a wrapper lib, a variable-built path or
#   a non-.sh hook is NOT detected. A hit is a lead, not proof; a miss is not proof of absence.
# Trigger 2 - the gate rejects content that reached the default branch. First-parent commits after
#   the tracker was created (the window is ANCESTRY-based: it starts after the oldest first-parent
#   commit whose committer date is >= createdAt, so a skew-dated commit in the middle can neither
#   hide nor truncate the in-window commits around it; a pre-window commit with a FUTURE date would
#   widen it, a known superset). The newest 120 that touch the gate's own path classes
#   (UI_RE/EMAIL_RE are READ from the gate source, never copied) are judged, found in ONE
#   `git log --name-only` pass. Each is judged by the REAL committed gate: one reused
#   `git worktree add --no-checkout --detach`, per commit `git update-ref --no-deref HEAD <first-parent>`
#   then `git read-tree <commit>` into that worktree's own index (the gate unsets GIT_INDEX_FILE, so
#   an env-var index would be ignored; read-tree replaces the whole index, so no reset is needed and
#   the per-commit cost roughly halves on a shared clone; machine-dependent), a plain `git commit -m x` payload
#   on stdin, under `timeout -k 5 60`. The gate child runs under `env -i` with an ALLOWLIST: PATH,
#   HOME (an empty scratch directory), LANG=C, TMPDIR (the run's scratch directory) and
#   CLAUDE_PROJECT_DIR (another empty scratch directory, so no incident ledger is written), plus any
#   `WATCH_GATE_X_*` variable (a test seam for the stub gate; nothing else). No token, host or
#   regex override and no GIT_* variable can reach it.
#   Every git call is made with the git location and config variables (GIT_DIR, GIT_INDEX_FILE,
#   GIT_CONFIG_COUNT, GIT_CONFIG_KEY_*/GIT_CONFIG_VALUE_*, GIT_CONFIG_PARAMETERS, GIT_CONFIG_GLOBAL/
#   SYSTEM, GIT_CEILING_DIRECTORIES, ...) unset, so an inherited one can never point a write at a
#   different repository or inject a configuration value.
#   POSITIVE CONTROL: before the loop the same worktree and gate run a synthetic off-palette file
#   (staged only in the worktree's own index, never committed) and MUST answer `deny`; anything else
#   is exit 3, because a gate that cannot deny here would make every "clean" result meaningless.
#   Only an `allow` or `deny` JSON verdict counts, and stderr is screened for `WARN` only (the gate
#   may print benign notes; a stderr line containing WARN makes that commit unjudgeable). A `deny`
#   is a finding (key `trigger-2:<40-hex sha>`). One commit with a timeout, a stderr WARN, a
#   non-zero exit or unusable output is "unjudgeable" (key `trigger-2-unjudgeable:<sha>`, a
#   `::warning::` naming the reason): reported once, skipped, the loop continues, never called
#   off-brand. Systemic failure is exit 3 (preflight, the canary, or the first three judged commits
#   all unjudgeable). The sentinel is checked BEFORE judging, so a sentineled commit is never re-run.
#   RESIDUAL (accepted): an unjudgeable verdict is recorded permanently. A transient gate timeout
#   later in a run (after the first three commits judged fine) is sentineled and never re-judged;
#   the comment says the commit could not be judged, never that it is clean.
#   The commit stream is verified: every header SHA and its first parent must equal the next entries
#   of the first-parent list written beforehand, so a tracked path named like a header (a control
#   character plus 40 hex digits) cannot hide the real commit's files; a mismatch is exit 3.
#   The run budget (default 480 s) is measured from SCRIPT START and checked while collecting
#   candidates and between commits (the collection check applies only once a candidate exists, so at least one
#   candidate is always judged); on overrun it stops,
#   prints `examined=N truncated=1 budget=1` and a ::warning:: and exits 0. Newest-first order can
#   starve the oldest clean commits under a truncation: a documented residual with no watermark
#   (CTO ruling S1). `scanned=` (first-parent commits looked at) next to `candidates=` tells a quiet
#   window from a collapsed path filter.
#
# The comment lists only NEW findings (summary above 10, every finding still sentineled) and says
# the route cannot be inferred from the default branch (a chained add-then-commit, a --no-verify
# commit and a human commit look alike): it is a lead for the ruling session.
#
# Modes:  (none)         run both detectors, post once if anything is new
#         --dry-run      run both detectors (the tracker read stays read-only; a failed read is a
#                        ::warning::, not exit 3), print the would-be comment, make no
#                        `issue comment` call, spend no sentinel
#         --print-state  local git only, no network: print the trigger-1 hook list and the trigger-2
#                        candidate-commit count (the discoverability probe). Exit 0 only when both
#                        were measured; `hooks=unknown` / `candidates=unknown` is exit 3.
# Env (test seams, like WATCH_NOW in the library): WATCH_LOOP_BUDGET (seconds from script start,
#   default 480), WATCH_GATE_TIMEOUT (seconds per commit, default 60), WATCH_CREATED_AT
#   (--print-state window), WATCH_ELAPSED_OFFSET (seconds pretended to have elapsed already).
#
# Exit: 0 posted, or any no-op (tracker not open or gone, nothing new, dry-run, print-state);
#       1 comment post failed; 2 usage (anything but no argument, --dry-run or --print-state); 3 cannot establish (a read the verdict depends on failed,
#       a tool or the gate is missing, history unreadable, invalid path-class regex, canary or
#       systemic gate failure) - nothing is posted so the next run retries; 78 refusing to run
#       under xtrace.
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script holds a live GitHub token and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

SCRIPT_START=$SECONDS
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/watch-notify-once.sh
. "$SCRIPT_DIR/lib/watch-notify-once.sh" || { echo "::error::cannot source the shared watcher library" >&2; exit 3; }
# The library assigns WN_DRY_RUN=0 itself; only the --dry-run flag below may switch it on.

ISSUE=11177
GATE_REL=".claude/hooks/brand-hex-commit-gate.sh"
EXCLUDED_HOOKS=(git-commit-secret-scan.sh brand-hex-commit-gate.sh)
CAP=120
SUMMARY_MAX=10
BUDGET="${WATCH_LOOP_BUDGET:-480}"
GATE_TIMEOUT="${WATCH_GATE_TIMEOUT:-60}"
ELAPSED_OFFSET="${WATCH_ELAPSED_OFFSET:-0}"
PRINT_STATE_CREATED="${WATCH_CREATED_AT:-2026-10-26T11:33:12Z}"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}'

usage() { echo "usage: ${0##*/} [--dry-run|--print-state]" >&2; exit 2; }
MODE=run
# Only no argument, `--dry-run` or `--print-state` is accepted: a lone empty argument is a usage error.
if [[ "$#" -gt 1 ]]; then usage; fi
if [[ "$#" -eq 1 ]]; then
  case "$1" in
    --dry-run) WN_DRY_RUN=1 ;;
    --print-state) MODE=print-state ;;
    *) usage ;;
  esac
fi
[[ "$BUDGET" =~ ^[1-9][0-9]{0,5}$ && "$GATE_TIMEOUT" =~ ^[1-9][0-9]{0,4}$ && "$ELAPSED_OFFSET" =~ ^[0-9]{1,6}$ ]] || { echo "::error::WATCH_LOOP_BUDGET/WATCH_GATE_TIMEOUT must be positive integers and WATCH_ELAPSED_OFFSET a non-negative integer" >&2; exit 2; }
SCRIPT_START=$((SCRIPT_START - ELAPSED_OFFSET))
over_budget() { [[ "$(( SECONDS - SCRIPT_START ))" -ge "$BUDGET" ]]; }

# Every git call goes through gitx: the git location AND configuration variables are removed so an
# inherited one (a hook, a wrapper, a CI shell) can never redirect an update-ref/read-tree/worktree
# write at another repository's branch or index, nor inject a config value (GIT_CONFIG_COUNT with
# GIT_CONFIG_KEY_n/GIT_CONFIG_VALUE_n, GIT_CONFIG_PARAMETERS). The numbered ones are found in `env`.
GIT_UNSET=(); GATE_PASS=()
for _v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_PREFIX \
          GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM GIT_CONFIG GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM \
          GIT_NO_REPLACE_OBJECTS GIT_REPLACE_REF_BASE GIT_GRAFT_FILE GIT_SHALLOW_FILE; do GIT_UNSET+=(-u "$_v"); done
while IFS= read -r -d '' _kv; do
  _n="${_kv%%=*}"
  case "$_n" in
    GIT_CONFIG_KEY_*|GIT_CONFIG_VALUE_*) GIT_UNSET+=(-u "$_n") ;;
    # The only variables forwarded to the gate child besides its fixed allowlist (see judge_gate): the
    # stub-gate seam of the test suite. A real run has none.
    WATCH_GATE_X_[A-Z0-9_]*) GATE_PASS+=("$_kv") ;;
  esac
done < <(env -0)
gitx() { env "${GIT_UNSET[@]}" git "$@"; }

REPO_ROOT=""; WT=""; EMPTY=""
# The scratch directory is created BEFORE the functions that write into it, so every write site below
# is rooted at one binding the fixture scanner can resolve: an absolute TMPDIR-or-/var/tmp base, then
# mktemp under it. cleanup (armed on the next line group) removes it on every exit path.
TMP_BASE=${TMPDIR:-/var/tmp}
WORK="$(mktemp -d "$TMP_BASE/watch-brand-hex.XXXXXXXX")" || { echo "::error::mktemp failed" >&2; exit 3; }
# ONE cleanup for everything this run creates: the reused worktree, then its scratch directory.
cleanup() {
  if [[ -n "$WT" && -n "$REPO_ROOT" ]]; then gitx -C "$REPO_ROOT" worktree remove --force "$WT" >/dev/null 2>&1; fi
  if [[ -n "$WORK" ]]; then rm -rf "$WORK"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# san: ONE third-party string as an inert code span; no @ at all; a closing keyword followed by a
# reference (including owner/repo#N) is broken up so the comment cannot close anything.
# wn_sanitize (the library) does the stripping and has been broadened (format and separator
# characters, variation selectors, tag characters); san builds on it and so inherits any further
# broadening, and only adds the two things the library leaves alone.
san() {
  local s
  s="$(wn_sanitize "$1")" || s='`?`'
  s="${s//@/(at)}"
  printf '%s' "$s" | perl -pe 's/\b(close[sd]?|fix(?:e[sd])?|resolve[sd]?)\b(\W{0,8})([\w.\/-]*#)(?=\d)/$1$2$3 /gi'
}

# ------------------------------------------------------------------ trigger 1 ----
HOOKS=(); HOOK_NAMES=(); HOOK_EXCL=(); FIRED=()
is_excluded_hook() {
  local b="${1##*/}" x
  for x in "${EXCLUDED_HOOKS[@]}"; do [[ "$b" == "$x" ]] && return 0; done
  return 1
}
t1_run() {
  local f content noncomment named TRACKED=()
  HOOKS=(); HOOK_NAMES=(); HOOK_EXCL=(); FIRED=()
  gitx -C "$REPO_ROOT" ls-files -z > "$WORK/ls" 2>/dev/null || { echo "::error::git ls-files failed; cannot list the tracked hooks" >&2; return 3; }
  mapfile -d '' -t TRACKED < "$WORK/ls"
  for f in ${TRACKED[@]+"${TRACKED[@]}"}; do
    case "$f" in
      */lib/*|*.test.sh) continue ;;
    esac
    if [[ "$f" =~ ^\.claude/hooks/[^/]+\.sh$ || "$f" =~ ^plugins/(.+/)?hooks/[^/]+\.sh$ ]]; then HOOKS+=("$f"); fi
  done
  if [[ "${#HOOKS[@]}" -eq 0 ]]; then
    echo "::error::no tracked hook files found (.claude/hooks/*.sh, plugins/**/hooks/*.sh); cannot establish trigger 1" >&2
    return 3
  fi
  for f in "${HOOKS[@]}"; do
    content="$(gitx -C "$REPO_ROOT" show ":$f" 2>/dev/null)" || { echo "::error::cannot read tracked hook $(san "$f"); cannot establish trigger 1" >&2; return 3; }
    noncomment="$(grep -vE '^[[:space:]]*#' <<<"$content")" || true
    named=no
    if grep -qF 'commit-index-sim' <<<"$noncomment"; then named=yes; fi
    HOOK_NAMES+=("$named")
    if is_excluded_hook "$f"; then HOOK_EXCL+=(yes); continue; fi
    HOOK_EXCL+=(no)
    if [[ "$named" == yes ]]; then
      FIRED+=("$f")
    fi
  done
  return 0
}

# ------------------------------------------------------------------ trigger 2 ----
UI_RE=""; EMAIL_RE=""; WN_CREATED_EPOCH=""; BASE=""
CAND_SHA=(); CAND_PAR=(); CAND_MORE=0; SCANNED=0; TRUNC_BUDGET=0
T2_CUR=""; T2_PAR=""; T2_HIT=0
# class_of PATH: rc 0 in a gate path class, 1 not, 3 an invalid regex (bash =~ rc 2 is NOT "no match").
class_of() {
  local r
  [[ "$1" =~ $UI_RE ]]; r=$?
  if [[ "$r" -eq 0 ]]; then return 0; fi
  if [[ "$r" -ne 1 ]]; then return 3; fi
  [[ "$1" =~ $EMAIL_RE ]]; r=$?
  if [[ "$r" -eq 0 ]]; then return 0; fi
  if [[ "$r" -ne 1 ]]; then return 3; fi
  return 1
}
# The path classes come from the gate's own source (its defaults), so a gate change moves them.
load_classes() {
  local src="$REPO_ROOT/$GATE_REL" r
  UI_RE="$(sed -nE 's/^UI_RE="\$\{SOLEUR_BRAND_HEX_UI_RE:-(.*)\}"$/\1/p' "$src" 2>/dev/null)"
  EMAIL_RE="$(sed -nE 's/^EMAIL_RE="\$\{SOLEUR_BRAND_HEX_EMAIL_RE:-(.*)\}"$/\1/p' "$src" 2>/dev/null)"
  if [[ -z "$UI_RE" || -z "$EMAIL_RE" ]]; then
    echo "::error::cannot read the UI_RE/EMAIL_RE path classes from ${GATE_REL}; cannot establish trigger 2" >&2
    return 3
  fi
  class_of "probe"; r=$?
  if [[ "$r" -eq 3 ]]; then
    echo "::error::the UI_RE/EMAIL_RE path class in ${GATE_REL} is not a valid regex; cannot establish trigger 2" >&2
    return 3
  fi
  return 0
}
# t2_base: the commit BEFORE the window, by ancestry. Walking the first-parent chain newest first,
# the window starts after the OLDEST commit whose committer date is >= createdAt, so a skew-dated
# commit in the middle (which `--since` treats as the end of history) cannot drop anything.
# BASE is empty when the whole chain is in the window; BASE=HEAD when nothing is.
t2_base() {
  BASE=""
  gitx -C "$REPO_ROOT" log --first-parent --format='%H %ct' HEAD > "$WORK/fp" 2>/dev/null || return 3
  BASE="$(awk -v c="$WN_CREATED_EPOCH" '
    { if ($2 + 0 >= c + 0) last = NR; a[NR] = $1 }
    END { if (NR == 0) print "ERR"; else if (last == 0) print a[1]; else if (last == NR) print "-"; else print a[last + 1] }' "$WORK/fp")" || return 3
  case "$BASE" in
    ERR) return 3 ;;
    -) BASE="" ;;
  esac
  [[ -z "$BASE" || "$BASE" =~ ^[0-9a-f]{40}$ ]] || return 3
  return 0
}
# t2_flush MORE: account the commit just read (T2_CUR/T2_PAR/T2_HIT). rc 0 continue, 1 stop (cap or
# budget), 3 error. MORE=1 when another commit follows (so a budget stop is a real truncation).
t2_flush() {
  if [[ ! "$T2_CUR" =~ ^[0-9a-f]{40}$ ]]; then return 0; fi
  if [[ "$T2_PAR" =~ ^[0-9a-f]{40}$ ]]; then
    SCANNED=$((SCANNED + 1))
    if [[ "$T2_HIT" -eq 1 ]]; then
      if [[ "${#CAND_SHA[@]}" -ge "$CAP" ]]; then CAND_MORE=1; return 1; fi
      CAND_SHA+=("$T2_CUR"); CAND_PAR+=("$T2_PAR")
    fi
  fi
  T2_CUR=""; T2_PAR=""; T2_HIT=0
  if [[ "${#CAND_SHA[@]}" -ge 1 ]] && [[ "$1" -eq 1 ]] && over_budget; then TRUNC_BUDGET=1; return 1; fi
  return 0
}
# t2_collect: newest-first first-parent commits in the window that touch the path classes, at most
# CAP of them (CAND_MORE=1 when more existed), from ONE git log pass parsed here.
t2_collect() {
  local tok first=0 range=HEAD r fr hdr_sha hdr_par hi=0 FP=()
  CAND_SHA=(); CAND_PAR=(); CAND_MORE=0; SCANNED=0; TRUNC_BUDGET=0; T2_CUR=""; T2_PAR=""; T2_HIT=0
  t2_base || { echo "::error::git log failed; cannot establish trigger 2" >&2; return 3; }
  if [[ -n "$BASE" ]]; then range="${BASE}..HEAD"; fi
  # The first-parent list written by t2_base is the oracle for the header stream below.
  mapfile -t FP < <(awk '{ print $1 }' "$WORK/fp")
  gitx -C "$REPO_ROOT" log --first-parent --no-renames --name-only -z --diff-merges=first-parent --format='%x01%H%x20%P' "$range" > "$WORK/log" 2>/dev/null \
    || { echo "::error::git log failed; cannot establish trigger 2" >&2; return 3; }
  while IFS= read -r -d '' tok || [[ -n "$tok" ]]; do
    if [[ "$first" -eq 1 ]]; then tok="${tok#$'\n'}"; first=0; fi
    if [[ "$tok" =~ ^$'\001'([0-9a-f]{40})\ ?([0-9a-f]{40})? ]]; then
      # t2_flush runs its own =~ matches, which would clobber BASH_REMATCH: capture first.
      hdr_sha="${BASH_REMATCH[1]}"; hdr_par="${BASH_REMATCH[2]:-}"
      # A tracked path named like a header (control character + 40 hex digits) must not forge one:
      # each real header carries the next first-parent SHA, in order, and its first parent.
      if [[ "$hdr_sha" != "${FP[$hi]:-}" || "$hdr_par" != "${FP[$((hi + 1))]:-}" ]]; then
        echo "::error::the commit stream does not match the first-parent list (a tracked path named like a commit header, or history changed during the run); cannot establish trigger 2" >&2
        return 3
      fi
      hi=$((hi + 1))
      t2_flush 1; fr=$?
      if [[ "$fr" -eq 3 ]]; then return 3; fi
      if [[ "$fr" -eq 1 ]]; then return 0; fi
      T2_CUR="$hdr_sha"; T2_PAR="$hdr_par"; T2_HIT=0; first=1
      continue
    fi
    [[ -n "$tok" && "$T2_HIT" -eq 0 ]] || continue
    class_of "$tok"; r=$?
    if [[ "$r" -eq 3 ]]; then echo "::error::the UI_RE/EMAIL_RE path class is not a valid regex; cannot establish trigger 2" >&2; return 3; fi
    if [[ "$r" -eq 0 ]]; then T2_HIT=1; fi
  done < "$WORK/log"
  t2_flush 0; fr=$?
  if [[ "$fr" -eq 3 ]]; then return 3; fi
  # Natural end of the stream: the commit after the last header must be the window base (or the
  # history must end there), else a header was swallowed.
  if [[ "${FP[$hi]:-}" != "$BASE" ]]; then
    echo "::error::the commit stream ended before the window base of the first-parent list; cannot establish trigger 2" >&2
    return 3
  fi
  return 0
}

already_notified() { # rc 0 notified, 1 not, 3 comments unreadable
  local r
  wn_sentinel_present "trigger-2:$1"; r=$?
  if [[ "$r" -eq 3 ]]; then return 3; fi
  if [[ "$r" -eq 0 ]]; then return 0; fi
  wn_sentinel_present "trigger-2-unjudgeable:$1"; r=$?
  if [[ "$r" -eq 3 ]]; then return 3; fi
  if [[ "$r" -eq 0 ]]; then return 0; fi
  return 1
}

render_item() { # sha detail
  local subj
  subj="$(gitx -C "$REPO_ROOT" log -1 --format=%s "$1" 2>/dev/null)" || subj=""
  printf -- '- `%s` %s: %s' "${1:0:12}" "$(san "$subj")" "$(san "$2")"
}

# judge_gate: run the REAL gate in the reused worktree against whatever its index holds, exactly the
# way a candidate is run. Sets G_VERDICT (allow|deny|unjudgeable), G_REASON, G_OUT.
GATE=""; GATE_HOME=""; OUTF="$WORK/gate.out"; ERRF="$WORK/gate.err"; G_VERDICT=""; G_REASON=""; G_OUT=""
judge_gate() {
  local g_rc gate_err decision
  # Allowlist, not denylist: nothing but these variables (and the WATCH_GATE_X_* test seam) exists in the gate child.
  ( cd "$WT" && env -i "PATH=$PATH" "HOME=$GATE_HOME" LANG=C "TMPDIR=$WORK" "CLAUDE_PROJECT_DIR=$EMPTY" ${GATE_PASS[@]+"${GATE_PASS[@]}"} \
      timeout -k 5 "$GATE_TIMEOUT" bash "$GATE" ) < "$WORK/payload" > "$OUTF" 2> "$ERRF"
  g_rc=$?
  G_VERDICT=unjudgeable; G_REASON="unusable output"
  G_OUT="$(cat "$OUTF" 2>/dev/null)"; gate_err="$(cat "$ERRF" 2>/dev/null)"
  if [[ "$g_rc" -eq 124 || "$g_rc" -eq 137 ]]; then
    G_REASON="timeout"
  elif [[ "$g_rc" -ne 0 ]]; then
    G_REASON="gate exit ${g_rc}"
  elif [[ "$gate_err" == *WARN* ]]; then
    G_REASON="gate warning"
  else
    decision="$(jq -r 'select(type=="object") | .hookSpecificOutput.permissionDecision // empty' <<<"$G_OUT" 2>/dev/null)" || decision=""
    case "$decision" in
      allow) G_VERDICT=allow; G_REASON="" ;;
      deny) G_VERDICT=deny; G_REASON="" ;;
      *) G_VERDICT=unjudgeable ;;
    esac
  fi
}

# canary: the positive control. Stage a synthetic off-palette UI file in the worktree's OWN index
# (never a commit) and require the real gate to deny it. The loop's per-commit update-ref/read-tree
# replaces this index, so nothing of it reaches a real candidate.
canary() {
  local csha why
  if ! gitx -C "$WT" read-tree "${CAND_PAR[0]}" >/dev/null 2>&1; then
    echo "::error::canary: cannot load the first candidate's parent into the worktree index; cannot establish trigger 2" >&2
    return 3
  fi
  csha="$(printf 'export const s = { color: "#ff00aa" };\n' | gitx -C "$WT" hash-object -w --stdin 2>/dev/null)" || csha=""
  if [[ ! "$csha" =~ ^[0-9a-f]{40,64}$ ]] \
     || ! gitx -C "$WT" update-index --add --cacheinfo "100644,${csha},apps/web-platform/components/zz-canary.tsx" >/dev/null 2>&1; then
    echo "::error::canary: cannot stage the synthetic off-palette file; cannot establish trigger 2" >&2
    return 3
  fi
  judge_gate
  if [[ "$G_VERDICT" != deny ]]; then
    if [[ "$G_VERDICT" == allow ]]; then why="answered allow instead of deny"; else why="was unjudgeable (${G_REASON})"; fi
    echo "::error::the gate cannot deny in this environment (positive control ${why}); a clean result would be meaningless, cannot establish trigger 2" >&2
    return 3
  fi
  return 0
}

examined=0; judged=0; unj_count=0; skipped=0
FIND_SHA=(); FIND_TXT=(); UNJ=(); UNJ_TXT=()
t2_run() {
  local idx sha parent rc loc
  examined=0; judged=0; unj_count=0; skipped=0
  FIND_SHA=(); FIND_TXT=(); UNJ=(); UNJ_TXT=()
  load_classes || return 3
  t2_collect || return 3
  if [[ "${#CAND_SHA[@]}" -eq 0 ]]; then return 0; fi

  GATE="$REPO_ROOT/$GATE_REL"
  WT="$WORK/wt"; EMPTY="$WORK/empty"; GATE_HOME="$WORK/gate-home"
  mkdir "$EMPTY" "$GATE_HOME" || return 3
  printf '%s' "$PAYLOAD" > "$WORK/payload" || return 3
  if ! gitx -C "$REPO_ROOT" worktree add -q --no-checkout --detach "$WT" "${CAND_PAR[0]}" >/dev/null 2>&1; then
    WT=""
    echo "::error::cannot create the throwaway worktree; cannot establish trigger 2" >&2
    return 3
  fi
  canary || return 3

  for idx in "${!CAND_SHA[@]}"; do
    sha="${CAND_SHA[$idx]}"; parent="${CAND_PAR[$idx]}"
    if [[ "$examined" -ge 1 ]] && over_budget; then TRUNC_BUDGET=1; break; fi
    examined=$((examined + 1))
    # The sentinel is checked BEFORE judging: a sentineled commit is never re-run through the gate.
    already_notified "$sha"; rc=$?
    if [[ "$rc" -eq 3 ]]; then echo "::error::could not evaluate the comments of #${ISSUE}; posting nothing" >&2; return 3; fi
    if [[ "$rc" -eq 0 ]]; then skipped=$((skipped + 1)); continue; fi

    judged=$((judged + 1))
    # Per commit: HEAD to the first parent (no reset: read-tree replaces the whole index anyway), then
    # the commit's tree into this worktree's own index.
    if gitx -C "$WT" update-ref --no-deref HEAD "$parent" >/dev/null 2>&1 && gitx -C "$WT" read-tree "$sha" >/dev/null 2>&1; then
      judge_gate
    else
      echo "::error::cannot refresh the worktree index for ${sha:0:12}; cannot establish trigger 2" >&2
      return 3
    fi

    case "$G_VERDICT" in
      allow) : ;;
      deny)
        G_REASON="$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"$G_OUT" 2>/dev/null)" || G_REASON=""
        loc="$(sed -nE 's/.*Locations: (.*)\. Remediation:.*/\1/p' <<<"$G_REASON" | head -n 1)"
        [[ -n "$loc" ]] || loc="$G_REASON"
        FIND_SHA+=("$sha"); FIND_TXT+=("$(render_item "$sha" "$loc")") ;;
      *)
        unj_count=$((unj_count + 1))
        echo "::warning::commit ${sha:0:12} unjudgeable: ${G_REASON}" >&2
        UNJ+=("$sha"); UNJ_TXT+=("$(render_item "$sha" "$G_REASON")") ;;
    esac

    # Systemic: the gate itself is broken (not one odd commit).
    if [[ "$judged" -eq 3 && "$unj_count" -eq 3 ]]; then
      echo "::error::the first three judged commits were all unjudgeable (last reason: ${G_REASON}); the gate is not working, cannot establish trigger 2" >&2
      return 3
    fi
  done
  return 0
}

# ----------------------------------------------------------------------- body ----
T1_NEW=0
compose() {
  local out i n shown
  out="### Brand-hex gate watch: a re-evaluation trigger on this tracker fired"$'\n\n'
  if [[ "$T1_NEW" -eq 1 ]]; then
    out+="**Trigger 1: a third hook now names the simulated-index library.** Besides the two hooks this tracker expects (the secret scan and the brand-hex gate itself), these tracked hooks have a non-comment line naming \`commit-index-sim\`:"$'\n\n'
    for i in "${FIRED[@]}"; do out+="- $(san "$i")"$'\n'; done
    out+=$'\n'
  fi
  if [[ "${#FIND_SHA[@]}" -gt 0 ]]; then
    n="${#FIND_SHA[@]}"; shown="$n"; [[ "$shown" -le "$SUMMARY_MAX" ]] || shown="$SUMMARY_MAX"
    out+="**Trigger 2: the gate rejects content that reached the default branch.** Run against each first-parent commit since this tracker was opened, the committed brand-hex gate denies ${n} commit(s) (an off-brand colour reached the default branch)"
    if [[ "$n" -gt "$SUMMARY_MAX" ]]; then out+="; the first ${shown} are listed"; fi
    out+=":"$'\n\n'
    for ((i = 0; i < shown; i++)); do out+="${FIND_TXT[$i]}"$'\n'; done
    if [[ "$n" -gt "$SUMMARY_MAX" ]]; then out+="... and $((n - shown)) more, each recorded so it is reported once."$'\n'; fi
    out+=$'\n'"The route cannot be inferred from the default branch: a chained add-then-commit, a no-verify commit and a human commit look alike. Treat these as leads for the ruling session, not verdicts."$'\n\n'
  fi
  if [[ "${#UNJ[@]}" -gt 0 ]]; then
    out+="**Commits the gate could not judge.** These commits could not be judged by the gate (timeout or unusable output); they are skipped, reported once and not re-run, and say nothing about their content:"$'\n\n'
    for i in "${UNJ_TXT[@]}"; do out+="${i}"$'\n'; done
    out+=$'\n'
  fi
  out+="Nothing was changed by this watcher. Each finding above is reported once; this tracker stays open for the ruling session to decide the next step."$'\n'
  BODY="$out"
}

sentinel_block() {
  local s lines=""
  if [[ "$T1_NEW" -eq 1 ]]; then lines+="$(wn_sentinel "trigger-1:v1")"$'\n'; fi
  for s in ${FIND_SHA[@]+"${FIND_SHA[@]}"}; do
    [[ "$s" =~ ^[0-9a-f]{40}$ ]] || continue
    lines+="$(wn_sentinel "trigger-2:${s}")"$'\n'
  done
  for s in ${UNJ[@]+"${UNJ[@]}"}; do
    [[ "$s" =~ ^[0-9a-f]{40}$ ]] || continue
    lines+="$(wn_sentinel "trigger-2-unjudgeable:${s}")"$'\n'
  done
  printf '%s' "$lines"
}

# --------------------------------------------------------------------- modes ----
REPO_ROOT="$(gitx rev-parse --show-toplevel 2>/dev/null)" || { echo "::error::not inside a git work tree; cannot establish" >&2; exit 3; }

if [[ "$MODE" == print-state ]]; then
  ps_rc=0
  echo "watch=brand-hex-11177 mode=print-state"
  if ! t1_run 2>/dev/null; then
    echo "trigger1 hooks=unknown"
    exit 3
  fi
  echo "trigger1 hooks=${#HOOKS[@]} fired=${#FIRED[@]}"
  for idx in "${!HOOKS[@]}"; do
    printf 'hook=%s names_sim=%s excluded=%s\n' "$(printf '%s' "${HOOKS[$idx]}" | tr -d '\000-\037')" "${HOOK_NAMES[$idx]:-?}" "${HOOK_EXCL[$idx]:-?}"
  done
  WN_CREATED="$PRINT_STATE_CREATED"
  WN_CREATED_EPOCH="$(wn_epoch "$WN_CREATED")" || { echo "::error::WATCH_CREATED_AT is not an ISO-8601 Z timestamp" >&2; exit 2; }
  if load_classes 2>/dev/null && t2_collect 2>/dev/null; then
    echo "trigger2 since=${WN_CREATED} scanned=${SCANNED} candidates=${#CAND_SHA[@]} cap=${CAP} more=${CAND_MORE} budget=${TRUNC_BUDGET}"
  else
    echo "trigger2 since=${WN_CREATED} candidates=unknown"
    ps_rc=3
  fi
  exit "$ps_rc"
fi

wn_preflight || exit 3

wn_read_issue "$ISSUE"; rc=$?
if [[ "$WN_DRY_RUN" -eq 1 ]]; then
  # Like scripts 1 and 2: the dry-run read is read-only and never fatal. A failed read falls back to
  # the --print-state window start and treats every finding as unreported.
  if [[ "$rc" -eq 0 ]]; then
    notopen=""; [[ "$WN_STATE" == "OPEN" ]] || notopen=" (not OPEN: a real run would post nothing)"
    echo "dry-run: tracker #${ISSUE} state=${WN_STATE}${notopen}; sentinels are per finding (trigger-1:v1, trigger-2:<sha>) and are checked while detecting"
  else
    echo "::warning::dry-run: could not read #${ISSUE} (${WN_ERR_HTTP:-rc ${rc}}); using the fallback window start ${PRINT_STATE_CREATED} and treating every finding as unreported"
    WN_STATE="UNKNOWN"; WN_CREATED="$PRINT_STATE_CREATED"
    # shellcheck disable=SC2034  # WN_JSON is read by wn_sentinel_present in the sourced library
    WN_JSON='{"comments":[]}'
  fi
else
  # The two notices below are the library's own wording (wn_notify_once_main in watch-notify-once.sh);
  # the suite pins that they still match.
  if [[ "$rc" -eq 4 ]]; then echo "::notice::tracker #${ISSUE} no longer resolves; tracker gone, nothing to watch"; exit 0; fi
  if [[ "$rc" -ne 0 ]]; then echo "::error::could not read #${ISSUE} (state/comments; ${WN_ERR_HTTP:-no HTTP status}); posting nothing" >&2; exit 3; fi
  if [[ "$WN_STATE" != "OPEN" ]]; then
    echo "::notice::#${ISSUE} is '${WN_STATE}' (not OPEN); nothing to watch; delete the watcher per the RETIREMENT block in code-quality-followups-watch.yml"
    exit 0
  fi
fi
WN_CREATED_EPOCH="$(wn_epoch "$WN_CREATED")" || { echo "::error::unusable createdAt on #${ISSUE}; cannot establish the window" >&2; exit 3; }

# Preflight the gate and the history before any detector runs.
[[ -r "$REPO_ROOT/$GATE_REL" ]] || { echo "::error::the brand-hex-commit-gate hook file (${GATE_REL}) is not readable; cannot run trigger 2" >&2; exit 3; }
if [[ "$(gitx -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null)" != false ]] || ! gitx -C "$REPO_ROOT" rev-parse -q --verify HEAD >/dev/null 2>&1; then
  echo "::error::git history is not fully readable (shallow checkout or no HEAD); use fetch-depth: 0" >&2
  exit 3
fi

t1_run || exit 3
if [[ "${#FIRED[@]}" -gt 0 ]]; then
  wn_sentinel_present "trigger-1:v1"; rc=$?
  if [[ "$rc" -eq 3 ]]; then echo "::error::could not evaluate the comments of #${ISSUE}; posting nothing" >&2; exit 3; fi
  if [[ "$rc" -eq 1 ]]; then T1_NEW=1; fi
fi
t2_run || exit 3

echo "trigger1 hooks=${#HOOKS[@]} fired=${#FIRED[@]} new=${T1_NEW}"
t2_line="trigger2 scanned=${SCANNED} candidates=${#CAND_SHA[@]} examined=${examined}"
if [[ "$CAND_MORE" -eq 1 || "$TRUNC_BUDGET" -eq 1 ]]; then t2_line+=" truncated=1"; fi
if [[ "$TRUNC_BUDGET" -eq 1 ]]; then t2_line+=" budget=1"; fi
t2_line+=" findings=${#FIND_SHA[@]} unjudgeable=${#UNJ[@]} already_notified=${skipped}"
echo "$t2_line"
if [[ "$CAND_MORE" -eq 1 ]]; then echo "::warning::more than ${CAP} candidate commits in the window; only the newest ${CAP} were examined" >&2; fi
if [[ "$TRUNC_BUDGET" -eq 1 ]]; then echo "::warning::the ${BUDGET}s run budget (measured from script start) ended the examination early; the oldest candidates were not examined this run" >&2; fi

if [[ "$T1_NEW" -eq 0 && "${#FIND_SHA[@]}" -eq 0 && "${#UNJ[@]}" -eq 0 ]]; then
  if [[ "$CAND_MORE" -eq 1 || "$TRUNC_BUDGET" -eq 1 ]]; then echo "no new findings; nothing to post (truncated)"; else echo "no new findings; nothing to post"; fi
  exit 0
fi

compose
body="$(printf '%s\n%s' "$BODY" "$(sentinel_block)")"
body="${body%$'\n'}"

if [[ "$WN_DRY_RUN" == 1 ]]; then
  printf '%s\n' "$body"
  echo "dry-run: nothing posted, no sentinel spent"
  exit 0
fi
# wn_post runs in THIS shell (a here-string, not a pipeline subshell) so its WN_ERR_HTTP survives.
if ! wn_post "$ISSUE" <<<"$body"; then
  echo "::error::posting the notice on #${ISSUE} failed (${WN_ERR_HTTP:-no HTTP status})" >&2
  exit 1
fi
echo "posted the notice on #${ISSUE} (trigger1_new=${T1_NEW} findings=${#FIND_SHA[@]} unjudgeable=${#UNJ[@]})"
exit 0
