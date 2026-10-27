#!/usr/bin/env bash
# watch-brand-hex-triggers-11177.sh — weekly test of the two "re-evaluate when" triggers on the
# brand-hex-gate tracker (#11177). NOTIFY-ONLY: the tracker is never closed, reopened, relabelled
# or edited; the only GitHub writes are `issue comment` (via wn_post in the shared library) and
# the only reads are `issue view`. It comments ONLY when a trigger fires, never otherwise.
#
# Trigger 1 - a third hook sources the simulated index. Tracked `.claude/hooks/*.sh` and any
#   tracked `plugins/**/hooks/*.sh` (read with `git ls-files`/`git show`, never the working tree),
#   minus anything under lib/ and *.test.sh, minus git-commit-secret-scan.sh and
#   brand-hex-commit-gate.sh (the gate adopting the lib IS the planned change, so it must not
#   fire), fires when a NON-comment line names `commit-index-sim`. An empty tracked-hook listing is
#   exit 3, never "clean". Notified once: key `trigger-1:v1`.
# Trigger 2 - the gate rejects content that reached the default branch. First-parent commits since
#   the tracker's createdAt, newest 200 that touch the gate's own path classes (UI_RE/EMAIL_RE are
#   READ from the gate source, never copied). Each is judged by the REAL committed gate: one reused
#   `git worktree add --no-checkout --detach`, per commit `git reset --mixed -q <first-parent>` then
#   `git read-tree <commit>` into that worktree's own index (the gate unsets GIT_INDEX_FILE, so an
#   env-var index would be ignored), a plain `git commit -m x` payload on stdin, CLAUDE_PROJECT_DIR
#   at an empty scratch directory (no incident ledger is written), under `timeout -k 5 60`. Only an
#   `allow` or `deny` JSON verdict with a quiet stderr counts. A `deny` is a finding (key
#   `trigger-2:<40-hex sha>`). One commit with a timeout, a stderr WARN or unusable output is
#   "unjudgeable" (key `trigger-2-unjudgeable:<sha>`): reported once, skipped, the loop continues,
#   never called off-brand. Systemic failure is exit 3 (preflight, or the first three judged
#   commits all unjudgeable). The sentinel is checked BEFORE judging, so a sentineled commit is
#   never re-run. Loop budget 600 s; both caps print `examined=N truncated=1` (+ ` budget=1`) and a
#   ::warning:: and exit 0. Newest-first order can starve the oldest clean commits under a budget
#   truncation: a documented residual with no watermark (CTO ruling S1).
#
# The comment lists only NEW findings (summary above 10, every finding still sentineled) and says
# the route cannot be inferred from the default branch (a chained add-then-commit, a --no-verify
# commit and a human commit look alike): it is a lead for the ruling session.
#
# Modes:  (none)         run both detectors, post once if anything is new
#         --dry-run      run both detectors, print the would-be comment, post nothing, spend no sentinel
#         --print-state  local git only, no network: print the trigger-1 hook list and the trigger-2
#                        candidate-commit count (the discoverability probe), exit 0
# Env (test seams, like WATCH_NOW in the library): WATCH_LOOP_BUDGET (seconds, default 600),
#   WATCH_GATE_TIMEOUT (seconds per commit, default 60), WATCH_CREATED_AT (--print-state window).
#
# Exit: 0 posted, or any no-op (tracker not open or gone, nothing new, dry-run, print-state);
#       1 comment post failed; 2 usage; 3 cannot establish (a read the verdict depends on failed,
#       a tool or the gate is missing, history unreadable, systemic gate failure) - nothing is
#       posted so the next run retries; 78 refusing to run under xtrace.
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script holds a live GitHub token and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/watch-notify-once.sh
. "$SCRIPT_DIR/lib/watch-notify-once.sh" || { echo "::error::cannot source the shared watcher library" >&2; exit 3; }
# The library defaults this from the environment; an inherited value must never silently switch
# this run to dry-run (only the --dry-run flag below may).
WN_DRY_RUN=0

ISSUE=11177
GATE_REL=".claude/hooks/brand-hex-commit-gate.sh"
EXCLUDED_HOOKS=(git-commit-secret-scan.sh brand-hex-commit-gate.sh)
CAP=200
SUMMARY_MAX=10
BUDGET="${WATCH_LOOP_BUDGET:-600}"
GATE_TIMEOUT="${WATCH_GATE_TIMEOUT:-60}"
PRINT_STATE_CREATED="${WATCH_CREATED_AT:-2026-10-26T11:33:12Z}"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}'

usage() { echo "usage: ${0##*/} [--dry-run|--print-state]" >&2; exit 2; }
MODE=run
case "${1:-}" in
  "") ;;
  --dry-run) WN_DRY_RUN=1 ;;
  --print-state) MODE=print-state ;;
  *) usage ;;
esac
[[ "$#" -le 1 ]] || usage
[[ "$BUDGET" =~ ^[1-9][0-9]{0,5}$ && "$GATE_TIMEOUT" =~ ^[1-9][0-9]{0,4}$ ]] || { echo "::error::WATCH_LOOP_BUDGET/WATCH_GATE_TIMEOUT must be positive integers" >&2; exit 2; }

REPO_ROOT=""; WORK=""; WT=""; EMPTY=""
# ONE cleanup for everything this run creates: the reused worktree, then its scratch directory.
cleanup() {
  if [[ -n "$WT" && -n "$REPO_ROOT" ]]; then git -C "$REPO_ROOT" worktree remove --force "$WT" >/dev/null 2>&1; fi
  if [[ -n "$WORK" ]]; then rm -rf "$WORK"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# san: ONE third-party string as an inert code span; no @ at all; a closing keyword followed by a
# reference (including owner/repo#N) is broken up so the comment cannot close anything.
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
  git -C "$REPO_ROOT" ls-files -z > "$WORK/ls" 2>/dev/null || { echo "::error::git ls-files failed; cannot list the tracked hooks" >&2; return 3; }
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
    content="$(git -C "$REPO_ROOT" show ":$f" 2>/dev/null)" || { echo "::error::cannot read tracked hook ${f}; cannot establish trigger 1" >&2; return 3; }
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
UI_RE=""; EMAIL_RE=""
CAND_SHA=(); CAND_PAR=(); CAND_MORE=0
# The path classes come from the gate's own source (its defaults), so a gate change moves them.
load_classes() {
  local src="$REPO_ROOT/$GATE_REL"
  UI_RE="$(sed -nE 's/^UI_RE="\$\{SOLEUR_BRAND_HEX_UI_RE:-(.*)\}"$/\1/p' "$src" 2>/dev/null)"
  EMAIL_RE="$(sed -nE 's/^EMAIL_RE="\$\{SOLEUR_BRAND_HEX_EMAIL_RE:-(.*)\}"$/\1/p' "$src" 2>/dev/null)"
  if [[ -z "$UI_RE" || -z "$EMAIL_RE" ]]; then
    echo "::error::cannot read the UI_RE/EMAIL_RE path classes from ${GATE_REL}; cannot establish trigger 2" >&2
    return 3
  fi
}
# touches_classes PARENT SHA: rc 0 when the commit changes a file in a gate path class, 1 when not, 3 on a git error.
touches_classes() {
  local f files=()
  git -C "$REPO_ROOT" diff-tree -r --no-renames --name-only -z "$1" "$2" > "$WORK/dt" 2>/dev/null || return 3
  mapfile -d '' -t files < "$WORK/dt"
  for f in ${files[@]+"${files[@]}"}; do
    if [[ "$f" =~ $UI_RE || "$f" =~ $EMAIL_RE ]]; then return 0; fi
  done
  return 1
}
# t2_collect: newest-first first-parent commits since the tracker was created that touch the path
# classes, at most CAP of them; CAND_MORE=1 when more existed.
t2_collect() {
  local sha rest par rc
  CAND_SHA=(); CAND_PAR=(); CAND_MORE=0
  git -C "$REPO_ROOT" log --first-parent --since="$WN_CREATED" --format='%H %P' HEAD > "$WORK/log" 2>/dev/null \
    || { echo "::error::git log failed; cannot establish trigger 2" >&2; return 3; }
  while read -r sha rest; do
    par="${rest%% *}"
    [[ "$sha" =~ ^[0-9a-f]{40}$ && "$par" =~ ^[0-9a-f]{40}$ ]] || continue
    touches_classes "$par" "$sha"; rc=$?
    if [[ "$rc" -eq 3 ]]; then echo "::error::git diff-tree failed for ${sha:0:12}; cannot establish trigger 2" >&2; return 3; fi
    [[ "$rc" -eq 0 ]] || continue
    if [[ "${#CAND_SHA[@]}" -ge "$CAP" ]]; then CAND_MORE=1; break; fi
    CAND_SHA+=("$sha"); CAND_PAR+=("$par")
  done < "$WORK/log"
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
  subj="$(git -C "$REPO_ROOT" log -1 --format=%s "$1" 2>/dev/null)" || subj=""
  printf -- '- `%s` %s: %s' "${1:0:12}" "$(san "$subj")" "$(san "$2")"
}

examined=0; judged=0; unj_count=0; skipped=0; TRUNC_BUDGET=0
FIND_SHA=(); FIND_TXT=(); UNJ=(); UNJ_TXT=()
t2_run() {
  local idx sha parent rc g_rc outf errf gate gate_out gate_err decision verdict reason loc loop_start
  examined=0; judged=0; unj_count=0; skipped=0; TRUNC_BUDGET=0
  FIND_SHA=(); FIND_TXT=(); UNJ=(); UNJ_TXT=()
  load_classes || return 3
  t2_collect || return 3
  if [[ "${#CAND_SHA[@]}" -eq 0 ]]; then return 0; fi

  gate="$REPO_ROOT/$GATE_REL"
  WT="$WORK/wt"; EMPTY="$WORK/empty"; outf="$WORK/gate.out"; errf="$WORK/gate.err"
  mkdir "$EMPTY" || return 3
  printf '%s' "$PAYLOAD" > "$WORK/payload" || return 3
  if ! git -C "$REPO_ROOT" worktree add -q --no-checkout --detach "$WT" "${CAND_PAR[0]}" >/dev/null 2>&1; then
    WT=""
    echo "::error::cannot create the throwaway worktree; cannot establish trigger 2" >&2
    return 3
  fi

  loop_start=$SECONDS
  for idx in "${!CAND_SHA[@]}"; do
    sha="${CAND_SHA[$idx]}"; parent="${CAND_PAR[$idx]}"
    if [[ "$(( SECONDS - loop_start ))" -ge "$BUDGET" ]]; then TRUNC_BUDGET=1; break; fi
    examined=$((examined + 1))
    # The sentinel is checked BEFORE judging: a sentineled commit is never re-run through the gate.
    already_notified "$sha"; rc=$?
    if [[ "$rc" -eq 3 ]]; then echo "::error::could not evaluate the comments of #${ISSUE}; posting nothing" >&2; return 3; fi
    if [[ "$rc" -eq 0 ]]; then skipped=$((skipped + 1)); continue; fi

    judged=$((judged + 1))
    # Per commit: HEAD to the first parent, then the commit's tree into this worktree's own index.
    if git -C "$WT" reset --mixed -q "$parent" >/dev/null 2>&1 && git -C "$WT" read-tree "$sha" >/dev/null 2>&1; then
      ( cd "$WT" && env -u GIT_INDEX_FILE -u GIT_DIR -u GIT_WORK_TREE -u SOLEUR_BRAND_HEX_UI_RE -u SOLEUR_BRAND_HEX_EMAIL_RE \
          "CLAUDE_PROJECT_DIR=$EMPTY" timeout -k 5 "$GATE_TIMEOUT" bash "$gate" ) < "$WORK/payload" > "$outf" 2> "$errf"
      g_rc=$?
    else
      echo "::error::cannot refresh the worktree index for ${sha:0:12}; cannot establish trigger 2" >&2
      return 3
    fi

    verdict=unjudgeable; reason="unusable output"; loc=""
    gate_out="$(cat "$outf" 2>/dev/null)"; gate_err="$(cat "$errf" 2>/dev/null)"
    if [[ "$g_rc" -eq 124 || "$g_rc" -eq 137 ]]; then
      reason="timeout"
    elif [[ "$g_rc" -ne 0 ]]; then
      reason="gate exit ${g_rc}"
    elif [[ "$gate_err" == *WARN* ]]; then
      reason="gate warning"
    else
      decision="$(jq -r 'select(type=="object") | .hookSpecificOutput.permissionDecision // empty' <<<"$gate_out" 2>/dev/null)" || decision=""
      case "$decision" in
        allow) verdict=allow ;;
        deny) verdict=deny ;;
        *) verdict=unjudgeable ;;
      esac
    fi

    case "$verdict" in
      allow) : ;;
      deny)
        reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"$gate_out" 2>/dev/null)" || reason=""
        loc="$(sed -nE 's/.*Locations: (.*)\. Remediation:.*/\1/p' <<<"$reason" | head -n 1)"
        [[ -n "$loc" ]] || loc="$reason"
        FIND_SHA+=("$sha"); FIND_TXT+=("$(render_item "$sha" "$loc")") ;;
      *)
        unj_count=$((unj_count + 1))
        UNJ+=("$sha"); UNJ_TXT+=("$(render_item "$sha" "$reason")") ;;
    esac

    # Systemic: the gate itself is broken (not one odd commit).
    if [[ "$judged" -eq 3 && "$unj_count" -eq 3 ]]; then
      echo "::error::the first three judged commits were all unjudgeable (timeout or unusable gate output); the gate is not working, cannot establish trigger 2" >&2
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
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "::error::not inside a git work tree; cannot establish" >&2; exit 3; }
WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/watch-brand-hex.XXXXXXXX")" || { echo "::error::mktemp failed" >&2; exit 3; }

if [[ "$MODE" == print-state ]]; then
  echo "watch=brand-hex-11177 mode=print-state"
  t1_run 2>/dev/null
  echo "trigger1 hooks=${#HOOKS[@]} fired=${#FIRED[@]}"
  for idx in "${!HOOKS[@]}"; do
    printf 'hook=%s names_sim=%s excluded=%s\n' "$(printf '%s' "${HOOKS[$idx]}" | tr -d '\000-\037')" "${HOOK_NAMES[$idx]:-?}" "${HOOK_EXCL[$idx]:-?}"
  done
  WN_CREATED="$PRINT_STATE_CREATED"
  if load_classes 2>/dev/null && t2_collect; then
    echo "trigger2 since=${WN_CREATED} candidates=${#CAND_SHA[@]} cap=${CAP} more=${CAND_MORE}"
  else
    echo "trigger2 since=${WN_CREATED} candidates=unknown"
  fi
  exit 0
fi

wn_preflight || exit 3

wn_read_issue "$ISSUE"; rc=$?
if [[ "$rc" -eq 4 ]]; then echo "::notice::tracker #${ISSUE} no longer resolves; tracker gone, nothing to watch"; exit 0; fi
if [[ "$rc" -ne 0 ]]; then echo "::error::could not read #${ISSUE} (state/comments); posting nothing" >&2; exit 3; fi
if [[ "$WN_STATE" != "OPEN" ]]; then
  echo "::notice::#${ISSUE} is '${WN_STATE}' (not OPEN); nothing to watch; delete the watcher per the RETIREMENT block in code-quality-followups-watch.yml"
  exit 0
fi
[[ "$WN_CREATED" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || { echo "::error::unusable createdAt on #${ISSUE}; cannot establish the window" >&2; exit 3; }

# Preflight the gate and the history before any detector runs.
[[ -r "$REPO_ROOT/$GATE_REL" ]] || { echo "::error::the brand-hex-commit-gate hook file (${GATE_REL}) is not readable; cannot run trigger 2" >&2; exit 3; }
if [[ "$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null)" != false ]] || ! git -C "$REPO_ROOT" rev-parse -q --verify HEAD >/dev/null 2>&1; then
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
t2_line="trigger2 examined=${examined}"
if [[ "$CAND_MORE" -eq 1 || "$TRUNC_BUDGET" -eq 1 ]]; then t2_line+=" truncated=1"; fi
if [[ "$TRUNC_BUDGET" -eq 1 ]]; then t2_line+=" budget=1"; fi
t2_line+=" findings=${#FIND_SHA[@]} unjudgeable=${#UNJ[@]} already_notified=${skipped}"
echo "$t2_line"
if [[ "$CAND_MORE" -eq 1 ]]; then echo "::warning::more than ${CAP} candidate commits in the window; only the newest ${CAP} were examined" >&2; fi
if [[ "$TRUNC_BUDGET" -eq 1 ]]; then echo "::warning::the ${BUDGET}s loop budget ended the examination early; the oldest candidates were not examined this run" >&2; fi

if [[ "$T1_NEW" -eq 0 && "${#FIND_SHA[@]}" -eq 0 && "${#UNJ[@]}" -eq 0 ]]; then
  echo "no new findings; nothing to post"
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
if ! printf '%s\n' "$body" | wn_post "$ISSUE"; then
  echo "::error::posting the notice on #${ISSUE} failed" >&2
  exit 1
fi
echo "posted the notice on #${ISSUE} (trigger1_new=${T1_NEW} findings=${#FIND_SHA[@]} unjudgeable=${#UNJ[@]})"
exit 0
