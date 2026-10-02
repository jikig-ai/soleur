#!/usr/bin/env bash
# PreToolUse hook: review evidence gate + auto-sync against origin/main before gh pr merge.
#
# pre-merge:review-evidence-gate — blocks gh pr merge when no review evidence exists on the branch.
# Review evidence is detected via three signals (any one suffices):
# (1) todos/ files tagged "code-review" (legacy, pre-#1329)
# (2) a commit matching "refactor: add code review findings" (legacy, pre-#1329)
# (3) GitHub issues with "code-review" label referencing the branch's PR (current, post-#1329)
# No escape hatch — run /review before merging.
#
# Signals 1-2 read the commits of the PR BEING MERGED, resolved from GitHub
# (`gh pr view <N>`), not whatever HEAD the session is anchored on (#8778). See
# the "PR-head evidence range" block below for the four states.
#
# Auto-sync: merges origin/main into the feature branch to ensure it is current before merge,
# only when the session cwd is PR N's own checkout (state O) or the PR could not be
# resolved (state L); from any other checkout it is skipped and reported (#8778).
# The sync itself is also conditional (#9401): when the incoming origin/main delta shares
# NO file with the branch's diff it is skipped (`delta disjoint` in additionalContext) so a
# green head SHA is not invalidated; a diff that cannot be computed falls through to the
# sync. Repository pointers (`-R`/`--repo`/`GH_REPO`/`GH_HOST`) that prove same-repo against
# this checkout's origin are stripped before the PR number is parsed; anything else keeps
# the legacy unresolved state. Note: filename says "rebase" for historical reasons;
# strategy is merge (not rebase).
#
# Corresponding prose rules:
#   constitution.md "Before creating a PR or merging, merge latest origin/main into the feature branch"
#   pre-merge:review-evidence-gate — blocks gh pr merge without review evidence (self-documented in this script)
#
# Error handling: fail-open on infrastructure errors (network, non-git context),
# fail-closed on logical errors (conflicts, dirty tree, push failure, missing review evidence).

set -eo pipefail
# -u (nounset) omitted: hook failure paths must return JSON, not crash silently.

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

# shellcheck source=../../plugins/soleur/scripts/lib/session-state.sh
# headless_or_stderr routes warns to a log file under $GIT_COMMON_DIR/
# soleur-session-state/logs/$PPID.log when stderr is not a TTY and
# CLAUDECODE is set (running under `claude --bg`). Otherwise echoes to
# stderr as before. Tolerate missing helper for legacy worktrees.
_SS_LIB="$(dirname "${BASH_SOURCE[0]}")/../../plugins/soleur/scripts/lib/session-state.sh"
if [[ -f "$_SS_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$_SS_LIB"
else
  headless_or_stderr() { echo "[$1] $2" >&2; }
fi
export SOLEUR_HOOK_NAME="pre-merge-rebase"

# shellcheck source=lib/hook-input.sh
# FAIL-HARD (no `|| true`): a fail-soft source leaves hook_parse_input undefined
# and the hook dies at the call, letting the tool proceed (#7164 defect 2).
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"

# The source above is fail-hard, but 12 of the 20 hooks run `set -uo pipefail`
# WITHOUT -e. There a missing helper makes hook_parse_input return 127, `!`
# inverts that to true, the response functions are 127 too, and the hook reaches
# `exit 0` — a clean pass-through with no row and no prompt, which is defect 2
# reintroduced by a broken deploy. Assert it explicitly instead of relying on -e.
if ! declare -f hook_parse_input >/dev/null 2>&1; then
  echo "[pre-merge-rebase] hook-input helper missing — guards did NOT run for this call" >&2
  exit 0
fi

INPUT=$(cat)
__HI_RAW="$INPUT"
# ADR-156: hook stdin is model-controlled. A non-string field is surfaced,
# never coerced — this hook never ran eval, but `jq -r` renders an array
# across lines, which matches none of its guards, so the payload would have
# slipped every gate below (#7164). ADR-157: it asks instead.
if ! hook_parse_input "$__HI_RAW"; then
  hook_input_report "pre-merge-rebase"
  hook_input_should_ask && { hook_input_emit_ask "pre-merge-rebase"; exit 0; }
  exit 0
fi

# `|| true`: under `set -eo pipefail`, jq exits 5 on malformed/empty stdin and
# would otherwise abort the script before the fail-open guards below — breaking
# the header's "fail-open on infrastructure errors" invariant. Degrade to "" so
# a malformed payload yields no merge-detection and a clean exit 0 (#4600).
CMD="$HOOK_CMD"

# Strip commit-message bodies before merge-detection so a commit whose message
# documents "gh pr merge" (e.g. `git commit -m "do not hand-roll gh pr merge"`)
# is not mistaken for a merge (#4600). perl -0777 slurps the whole (possibly
# multi-line) command; the /gs substitutions blank, in order:
#   1. heredoc bodies — `<<[-]['"]?DELIM['"]? … \nDELIM` (covers `git commit
#      -F - <<EOF … EOF`). Only the body between the opening line and the
#      closing delimiter is blanked; the markers and anything AFTER the closing
#      delimiter (where a real chained `gh pr merge` could live) are preserved.
#   2. double- and single-quoted spans (escape-aware) — covers `-m "…"` and the
#      `-m "$(cat <<EOF … EOF)"` shape where the heredoc sits inside the quote.
# Both leave the command structure OUTSIDE quotes/heredocs intact, where a real
# chained `gh pr merge` lives. Sibling precedent: follow-through-directive-
# gate.sh:72 ("sed -E can't do non-greedy across newlines" — same
# multiline-quoted-body class). On strip-tool failure, fall back to the raw
# $CMD so we fail TOWARD firing (over-detect), never toward a silent
# merge-bypass.
# The perl one-liner that used to live inline here is now the shared
# strip_command_bodies helper in lib/incidents.sh (#5192) — same canonical
# regex, one tested copy consumed by every phrase-detecting gate.
SCAN=$(strip_command_bodies "$CMD")

# Early exit: only intercept gh pr merge commands.
# Word boundary (\s|$) prevents false positives on hypothetical merge-* subcommands.
# Chain operator pattern from guardrails.sh catches chained commands.
# Runs against $SCAN (quote-stripped), not $CMD, per the #4600 fix above.
if ! grep -qE '(^|&&|\|\||;|\s--\s)\s*gh\s+pr\s+merge(\s|$)' <<<"$SCAN"; then
  exit 0
fi
# Note: the `\s--\s` alternative catches the with_lock wrapped form
# (`bash session-state.sh with_lock merge-main 600 -- gh pr merge ...`)
# so the wrapped form does NOT bypass the review-evidence gate, the
# uncommitted-changes check, or the origin/main auto-sync.

# Working directory from hook input. `.cwd` is the SESSION's anchored directory,
# not where an in-command `cd` lands — a root-anchored subagent running
# `cd <worktree> && gh pr merge N` still reports the root here (#8778). So it
# locates a git repository and the sync target; it does not decide WHICH commits
# the review gate reads — the PR-head resolver below does.
WORK_DIR="$HOOK_CWD"
if [[ -z "$WORK_DIR" ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi

# Verify we are in a git repository
if ! git -C "$WORK_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# Resolve current branch for main/master skip and detached HEAD handling
CURRENT_BRANCH=$(git -C "$WORK_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)

# Skip if already on main/master -- nothing to sync (the agent is merging a PR
# *into* main, not from it). This also skips the review gate for a session
# anchored on main, the same cwd-dependence #8778 fixes elsewhere; kept because
# the soleur:schedule template merges bot PRs from a main checkout (#8791).
if [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]]; then
  exit 0
fi

# Refresh origin/main BEFORE the review-evidence gate (#6724).
#
# Both local signals below are scoped with `origin/main..<evidence tip>`, so they are only
# as accurate as the locally-cached origin/main ref. A stale ref silently widens
# that range and lets commits already on main count as this branch's own review
# evidence — which re-opens the vacuity the scoping exists to close. This hook
# in particular merges origin/main in and pushes, so on a second merge attempt
# the cached ref is guaranteed to be behind unless it is refreshed here.
#
# This deliberately does NOT exit on failure. The sync logic further down fails
# open on a network error, which is correct for syncing; but if the fetch kept
# that behaviour at this position, any network failure would return 0 BEFORE the
# gate ran, turning "unplug the network" into a universal gate bypass. The
# outcome is recorded and acted on after the gate instead.
FETCH_OK=1
if ! git -C "$WORK_DIR" fetch --no-tags origin main >/dev/null 2>&1; then
  FETCH_OK=0
fi

# PR-head evidence range (#8778). The gate must read the commits GitHub will
# merge, not the session's HEAD (`.cwd` is the session anchor, not where an
# in-command `cd` lands). States (the #8778 plan's L/O/P/N table):
#   L legacy — the merge target is not ONE bare PR number in this repository
#              (see "Which PR is being merged" below), or gh did not answer with
#              a 40-hex head oid: today's `origin/main..HEAD` in the session cwd.
#   O own    — the cwd IS PR N's branch and descends from its head: keep
#              `origin/main..HEAD`, so a trailer commit not yet pushed still counts
#              (ship-unpushed-commits-gate.sh denies a merge that leaves it
#              unpushed; this state leans on that sibling, see its T11 ordering).
#   P PR     — otherwise, when the head commit is local (after fetching
#              refs/pull/<N>/head if needed): `origin/main..<oid>`.
#   N none   — the head cannot be fetched, the PR is not OPEN, or it comes from a
#              fork (its author wrote every commit in the range, so a trailer
#              there is self-asserted): Signals 1-2 are skipped and only Signal 3
#              (a code-review-labelled issue, which needs triage rights) can allow.
EVIDENCE_TIP="HEAD"
RANGE_SOURCE="session cwd $WORK_DIR"
PR_HEAD_NUMBER=""
PR_HEAD_OID=""
PR_HEAD_REF=""
OWN_CHECKOUT=0
SAME_BRANCH=0

# Which PR is being merged. Every REAL `gh pr merge` invocation is parsed with
# the detector's own anchor, in BOTH $SCAN (quoted text blanked) and $CMD (raw):
# a number must survive quote-stripping unchanged (`877"9"` strips to `877`), and
# text that merely mentions `gh pr merge 1` (an `echo`, a comment) is not an
# invocation. The resolver runs only when every invocation's first argument is
# the SAME bare PR number and nothing points gh at another repository;
# otherwise the reason is carried into the deny text. `|| true` on each capture:
# a no-match grep exits 1 under pipefail and would abort the hook (fail-open).
_merge_args() {
  grep -oE '(^|&&|\|\||;|[[:space:]]--[[:space:]])[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge([[:space:]][^;&|]*)?' <<<"$1" \
    | sed -E 's/^[^g]*gh[[:space:]]+pr[[:space:]]+merge//' || true
  # `^[^g]*`, not `.*`: the match's prefix is only separators, and a greedy `.*`
  # would skip to the LAST `gh pr merge` in the segment (`… 4243 # gh pr merge 4242`).
}
_scan_args=$(_merge_args "$SCAN")
_cmd_args=$(_merge_args "$CMD")

# Same-repository -R/--repo/GH_REPO/GH_HOST normalisation (#9401). A `gh pr
# merge` scoped to THIS repository resolves the PR head exactly as the flagless
# form does — every drain/one-shot reference emits `gh pr merge -R <repo> <N>`,
# which the unconditional refusal below used to pin in state L forever, so the
# gate then graded the SESSION's HEAD rather than the PR's commits.
#
# The proof is symmetric: every repo-pointer operand sighted on EITHER the
# quote-stripped or the raw side is normalised to (host, owner/repo) and
# compared against the session checkout's `origin`. Only when every operand
# proves same-repo are the flag tokens stripped from BOTH arg residues, so the
# bare-number and scan/cmd-agreement arms below see equal text. Any foreign,
# malformed or unverifiable operand leaves the residues untouched and the
# original deny arm fires unchanged. An origin whose URL is not a parseable
# remote (a local-path checkout) proves nothing → refused, as today. A quoted
# operand arrives blanked on the $SCAN side, so the two sides disagree on the
# proof and the pointer stays refused — also as today.

# _repo_url_parts <url-or-operand> → "host<TAB>owner/repo" lowercased, or a
# blank pair when unparseable. Covers https://h/o/r(.git), ssh://[u@]h[:p]/o/r,
# scp-style [u@]h:o/r, a HOST/o/r operand, and a bare o/r (empty host).
_repo_url_parts() {
  local u="$1" host="" slug="" rest=""
  case "$u" in
    *://*)  rest="${u#*://}"
            [[ "$rest" == */* ]] || { printf '\t\n'; return; }
            host="${rest%%/*}"; slug="${rest#*/}" ;;
    *:*/*)  host="${u%%:*}"; slug="${u#*:}" ;;   # scp-style [user@]host:o/r
    */*/*)  host="${u%%/*}"; slug="${u#*/}" ;;   # HOST/OWNER/REPO operand
    */*)    slug="$u" ;;                         # bare OWNER/REPO
    *)      printf '\t\n'; return ;;
  esac
  host="${host##*@}"; host="${host%%:*}"
  slug="${slug%/}"; slug="${slug%.git}"
  [[ -n "$slug" && "$slug" == */* && "$slug" != */*/* ]] || { host=""; slug=""; }
  # tr, not ${x,,} — bash 4 case-folding is a parse error on stock macOS bash
  # 3.2 (repo convention; the failure would silently dead-code the -R arm).
  printf '%s\t%s\n' "$host" "$slug" | tr '[:upper:]' '[:lower:]'
}

# _repo_flag_operands — one "R<tab><operand>" line per -R/--repo sighting in a
# `_merge_args` residue, "F" for a flag form that names no operand. Only the
# token shapes the deny arm's regex recognises are emitted; anything else is
# left for the bare-number arm below.
# The -R/--repo token grammar is enumerated in THREE places that must drift
# together: the sighting regex (the `_REPO_PTR` grep below), this extractor,
# and _strip_repo_flags. Drift fails closed (an unproven form is denied), but
# keep them aligned.
_repo_flag_operands() {
  awk '{
    for (i = 1; i <= NF; i++) {
      t = $i
      if (t == "-R" || t == "--repo") {
        if (i < NF) { print "R\t" $(i+1); i++ } else { print "F" }
      } else if (t ~ /^--repo=/) {
        print "R\t" substr(t, 8)   # empty operand parses to nothing → refuse
      } else if (t ~ /^-[A-Za-z]*R$/) {            # bundled short form: -dR, -sR
        if (i < NF) { print "R\t" $(i+1); i++ } else { print "F" }
      } else if (t ~ /^-[A-Za-z]*R./) {            # attached operand: -Ro/r
        print "R\t" substr(t, index(t, "R") + 1)
      }
    }
  }'
}

# _repo_env_operands <text> — "R<tab><v>" per GH_REPO=, "H<tab><v>" per
# GH_HOST= assignment, the same anchored shapes the deny arm scans for.
_repo_env_operands() {
  local _t=$'\t'
  # The value ends at whitespace OR a command separator — an unquoted `;`/`&`/`|`
  # belongs to the shell, not the assignment (`export GH_REPO=o/r; gh pr merge`).
  # NOTE: this scans the RAW command too, so a quoted `GH_REPO=` mention (text
  # that never executes) fails the same-repo proof → deny. Fail-closed, low
  # rate — the pre-change posture for any env sighting was also deny.
  grep -oE '(^|[^A-Za-z0-9_])GH_(REPO|HOST)=[^[:space:];&|]*' <<<"$1" \
    | sed -E "s/^[^A-Za-z0-9_]?GH_REPO=/R${_t}/; s/^[^A-Za-z0-9_]?GH_HOST=/H${_t}/" || true
}

# _repo_pointers_same_repo — 0 iff EVERY repo-pointer operand in both arg
# residues and both raw/scan texts resolves to this checkout's origin repo.
# Reads ambient state ($_scan_args, $_cmd_args, $SCAN, $CMD, $WORK_DIR) — the
# caller must set those before invoking.
# Hostless operands (o/r, HOST/owner/repo handled above) resolve against
# GH_HOST= when set — gh's documented override — else gh's default github.com.
_repo_pointers_same_repo() {
  local _oparts _ohost _oslug _ops _gh_host _bad=0
  # Ambient env counts as operands: gh honors GH_HOST/GH_REPO exported in the
  # session env even when the command text carries none, so a hostless -R or a
  # flagless merge is steered by them. Seeding the proof from them keeps both
  # directions honest (a foreign ambient host → deny; a matching ambient host
  # lets a hostless operand prove same-repo on a GHE checkout).
  _gh_host="${GH_HOST:-}"
  # config --get, NOT remote get-url: get-url resolves url.insteadOf rewrites,
  # collapsing distinct configured URLs onto their rewrite targets — the raw
  # configured URL is what identifies the repository gh would act on.
  _oparts=$(_repo_url_parts "$(git -C "$WORK_DIR" config --get remote.origin.url 2>/dev/null || true)")
  _ohost="${_oparts%%$'\t'*}"; _oslug="${_oparts#*$'\t'}"
  [[ -n "$_oslug" ]] || return 1   # local-path or unparseable origin proves nothing
  _ops=$({ _repo_flag_operands <<<"$_scan_args"; _repo_flag_operands <<<"$_cmd_args"
          _repo_env_operands "$SCAN"; _repo_env_operands "$CMD"
          [[ -n "${GH_REPO:-}" ]] && printf 'R\t%s\n' "$GH_REPO"
          [[ -n "${GH_HOST:-}" ]] && printf 'H\t%s\n' "$GH_HOST"; :; } ) || _ops=""
  [[ -n "$_ops" ]] || return 1
  local _k _op _h _pp _ph _ps
  while IFS=$'\t' read -r _k _op; do
    [[ "$_k" == "H" ]] || continue
    _h="${_op#*://}"; _h="${_h%%/*}"; _h="${_h%%:*}"
    _h=$(printf '%s' "$_h" | tr '[:upper:]' '[:lower:]')
    [[ -n "$_h" && "$_h" == "$_ohost" ]] || _bad=1
    _gh_host="$_h"
  done <<<"$_ops"
  while IFS=$'\t' read -r _k _op; do
    case "$_k" in
      H) : ;;   # judged above
      F) _bad=1 ;;   # a flag without its operand cannot be verified
      R) _pp=$(_repo_url_parts "$_op"); _ph="${_pp%%$'\t'*}"; _ps="${_pp#*$'\t'}"
         if [[ -z "$_ps" || "$_ps" != "$_oslug" ]] \
            || [[ -n "$_ph" && "$_ph" != "$_ohost" ]] \
            || [[ -z "$_ph" && "${_gh_host:-github.com}" != "$_ohost" ]]; then
           _bad=1
         fi ;;
    esac
  done <<<"$_ops"
  [[ "$_bad" == "0" ]]
}

# _strip_repo_flags — drop every -R/--repo token(+operand) from a `_merge_args`
# residue. Runs ONLY after _repo_pointers_same_repo proved every operand
# same-repo; a residue it cannot clean must never reach the checks below.
# Shape table mirrors _repo_flag_operands and the sighting regex — see the
# cross-reference comment there.
_strip_repo_flags() {
  awk '{
    out = ""
    for (i = 1; i <= NF; i++) {
      t = $i
      if (t == "-R" || t == "--repo" || t ~ /^-[A-Za-z]*R$/) { i++; continue }
      if (t ~ /^--repo=/ || t ~ /^-[A-Za-z]*R./) continue
      out = out (out == "" ? "" : " ") t
    }
    print out
  }'
}

_REPO_PTR=0
_REPO_SAME=0
# Sighting regex — third member of the -R grammar triple (see _repo_flag_operands).
if grep -qE '(^|[[:space:]])(--repo([[:space:]=]|$)|-[A-Za-z]*R)' <<<"$_scan_args
$_cmd_args" \
   || grep -qE '(^|[^A-Za-z0-9_])GH_(REPO|HOST)=' <<<"$SCAN
$CMD"; then
  _REPO_PTR=1
  _repo_pointers_same_repo && _REPO_SAME=1
fi
if [[ "$_REPO_SAME" == "1" ]]; then
  _scan_args=$(_strip_repo_flags <<<"$_scan_args")
  _cmd_args=$(_strip_repo_flags <<<"$_cmd_args")
fi

_tok_scan=$(awk '{ print ($1 == "" ? "-" : $1) }' <<<"$_scan_args" || true)
_tok_cmd=$(awk '{ print ($1 == "" ? "-" : $1) }' <<<"$_cmd_args" || true)
_pr_nums=$(sed 's/^#//' <<<"$_tok_scan" | grep -E '^[0-9]+$' | sort -u || true)
MERGE_TARGET_WHY=""
if [[ "$_tok_scan" != "$_tok_cmd" ]]; then
  MERGE_TARGET_WHY="the gh pr merge invocations differ once quoted text is removed"
elif grep -qvE '^#?[0-9]+$' <<<"$_tok_scan"; then
  MERGE_TARGET_WHY="a gh pr merge invocation does not name a bare PR number; put the number right after 'gh pr merge'"
elif [[ "$(grep -c . <<<"$_pr_nums" || true)" != "1" ]]; then
  MERGE_TARGET_WHY="more than one PR number; merge one PR per command"
elif [[ "$_REPO_PTR" == "1" && "$_REPO_SAME" != "1" ]]; then
  MERGE_TARGET_WHY="the command points gh at another repository or one the hook cannot prove is this checkout's origin (-R/--repo, GH_REPO or GH_HOST); drop the pointer and re-issue"
else
  _origin=$(git -C "$WORK_DIR" remote get-url origin 2>/dev/null || true)
  while IFS= read -r _dir; do
    [[ -n "$_dir" ]] || continue
    [[ "$_dir" == /* ]] || _dir="$WORK_DIR/$_dir"
    [[ -d "$_dir" ]] || continue
    _dir_origin=$(git -C "$_dir" remote get-url origin 2>/dev/null || true)
    if [[ -n "$_dir_origin" && "$_dir_origin" != "$_origin" ]]; then
      MERGE_TARGET_WHY="the command cd's into a checkout of another repository"
    fi
  done < <(grep -oE '(^|&&|\|\||;)[[:space:]]*(cd|pushd)[[:space:]]+[^;&|[:space:]]+' <<<"$SCAN" | awk '{ print $NF }' || true)
fi

if [[ -z "$MERGE_TARGET_WHY" ]]; then
  PR_HEAD_NUMBER="$_pr_nums"
  # timeout -> gtimeout -> unbounded (stock macOS has neither; a bare `timeout`
  # would exit 127 there and pin every Mac in L). The guarded expansion keeps an
  # empty array safe if -u is ever enabled (git-commit-secret-scan.sh precedent).
  _to=()
  if command -v timeout >/dev/null 2>&1; then _to=(timeout -k 2 10)
  elif command -v gtimeout >/dev/null 2>&1; then _to=(gtimeout -k 2 10); fi
  # From inside $WORK_DIR with no --repo: gh resolves the repository from the
  # checkout's own remotes (the pre-merge-auto-close-scan.sh precedent, #6775).
  _pr_json=$(cd "$WORK_DIR" && ${_to[@]+"${_to[@]}"} gh pr view "$PR_HEAD_NUMBER" \
               --json headRefName,headRefOid,isCrossRepository,state 2>/dev/null) || _pr_json=""
  # One parse; "-" sentinels because tab is IFS whitespace and an empty field
  # would shift every later one left.
  IFS=$'\t' read -r _oid _ref _xrepo _state < <(jq -r \
    '[(.headRefOid // "-"), (.headRefName // "-"), ((.isCrossRepository // false) | tostring), (.state // "-")] | @tsv' \
    <<<"$_pr_json" 2>/dev/null || true) || true
  # Validated before it reaches any git argv: a branch name or `--flag` must never
  # become a revision. headRefName never reaches git at all.
  if [[ "$_oid" =~ ^[0-9a-f]{40}$ ]]; then
    PR_HEAD_OID="$_oid"
    [[ "$_ref" == "-" ]] || PR_HEAD_REF="$_ref"
    [[ -n "$PR_HEAD_REF" && "$CURRENT_BRANCH" == "$PR_HEAD_REF" ]] && SAME_BRANCH=1
    if [[ "$_state" != "OPEN" ]]; then
      EVIDENCE_TIP=""
      RANGE_SOURCE="PR #${PR_HEAD_NUMBER} is ${_state}, not OPEN; its commits are not this merge's evidence"
    elif [[ "$_xrepo" == "true" ]]; then
      EVIDENCE_TIP=""
      RANGE_SOURCE="PR #${PR_HEAD_NUMBER} is from a fork; commits its author wrote are not review evidence, only a code-review-labelled issue counts"
    else
      _have=0
      git -C "$WORK_DIR" cat-file -e "${_oid}^{commit}" 2>/dev/null && _have=1
      if [[ "$_have" == "0" ]]; then
        # refs/pull/<N>/head, not refs/heads/<name>: it needs no branch name in a
        # git argv. Objects and FETCH_HEAD only; no branch ref moves.
        ${_to[@]+"${_to[@]}"} git -C "$WORK_DIR" fetch --no-tags --quiet origin \
          "refs/pull/${PR_HEAD_NUMBER}/head" >/dev/null 2>&1 || true
        git -C "$WORK_DIR" cat-file -e "${_oid}^{commit}" 2>/dev/null && _have=1
      fi
      if [[ "$SAME_BRANCH" == "1" && "$_have" == "1" ]] \
         && git -C "$WORK_DIR" merge-base --is-ancestor "$_oid" HEAD 2>/dev/null; then
        OWN_CHECKOUT=1
        RANGE_SOURCE="PR #${PR_HEAD_NUMBER}'s own checkout $WORK_DIR"
      elif [[ "$_have" == "1" ]]; then
        EVIDENCE_TIP="$_oid"
        RANGE_SOURCE="PR #${PR_HEAD_NUMBER} head per GitHub"
      else
        EVIDENCE_TIP=""
        RANGE_SOURCE="PR #${PR_HEAD_NUMBER} head ${_oid:0:12} not fetchable, so its commits were NOT evaluated; run: git fetch origin pull/${PR_HEAD_NUMBER}/head and re-issue (if that fetch fails, the network is the blocker, not review)"
      fi
    fi
  else
    RANGE_SOURCE+="; PR #${PR_HEAD_NUMBER} head not resolved (gh pr view gave no valid head oid: retry if it timed out, otherwise check gh auth status / gh pr view ${PR_HEAD_NUMBER})"
  fi
else
  RANGE_SOURCE+="; PR head not resolved: ${MERGE_TARGET_WHY}"
fi

# pre-merge:review-evidence-gate — Review evidence gate.
# Block gh pr merge when no review evidence exists on the branch.
# Signals 1-2 are local; Signal 3 requires network (gh API).
# Fires before the detached-HEAD exit because gh pr merge acts on a PR number:
# the resolver above reads that PR's head, so no branch checkout is needed
# (except in state L, which reads the session cwd's HEAD).

# Check 1 (legacy): todo files tagged "code-review" INTRODUCED BY THIS BRANCH.
#
# This was `grep -rl "code-review" "$WORK_DIR/todos/"` — a repo-global grep, and
# therefore structurally unfailable (#6724). todos/ is a tracked directory that
# lives on main, so a single long-lived review todo anywhere in it satisfied the
# gate for EVERY branch, forever, including branches where review never ran. The
# gate could not deny anything for as long as that file existed.
#
# `-G'code-review'` selects commits whose DIFF adds or removes a line matching
# the pattern, so this asks "did THIS BRANCH introduce review evidence?".
#
# The obvious formulation — list the paths the branch touched, then grep those
# paths — is still vacuous, just more narrowly. `git log --name-only` yields
# paths, and grep then reads whatever those paths contain IN THE CURRENT
# CHECKOUT. So a branch that merely TOUCHES a pre-existing main-side todo (a
# `resolve-todo-parallel` sweep, marking one done, a reformat) lists that path,
# grep matches the `code-review` tag that came from main, and the gate passes
# with no review having run. Matching on the diff instead of on the working
# tree closes that; it is the same class of residual the repo-global grep had.
# `-G` alone is still not enough: it matches lines ADDED **or REMOVED**, so a
# sweep that merely deletes a completed review todo (`git rm todos/...`) would
# count as evidence. So each candidate path must ALSO still carry the tag in
# evidence tip's blob — evidence that was introduced and is still there.
REVIEW_TODOS=""
REVIEW_COMMIT=""
# Never hand git an empty tip: `origin/main..` means `origin/main..HEAD`, which is
# state N's false ALLOW re-entering through the back door.
if [[ -n "$EVIDENCE_TIP" ]]; then
while IFS= read -r _todo; do
  [[ -n "$_todo" ]] || continue
  # grep -c, not grep -q: -c reads all input and never early-closes the pipe,
  # so the producer cannot take SIGPIPE and be misread as "no match" (#6992).
  if [ "$(git -C "$WORK_DIR" show "$EVIDENCE_TIP:$_todo" 2>/dev/null | grep -c "code-review" || true)" -gt 0 ]; then
    REVIEW_TODOS="$_todo"
    break
  fi
done < <(git -C "$WORK_DIR" log "origin/main..$EVIDENCE_TIP" -G'code-review' \
           --name-only --format= -- todos/ 2>/dev/null | sort -u)

# Check 2: review commit, or the machine-emitted review trailer.
#
# The `Reviewed-By-Soleur:` trailer is the durable signal, emitted by
# plugins/soleur/skills/review/scripts/emit-review-trailer.sh. It exists because
# a zero-finding review legitimately produces no artifacts and no commit, so the
# message-pattern signals below cannot fire for it — the gate would deny exactly
# the branches that were clean (#6724).
#
# The two message patterns are retained as legacy fallbacks for branches
# reviewed before the trailer existed: "refactor: add code review findings" and
# the "review: <summary> (P<N>)" fix-inline convention (with an OPTIONAL
# conventional-commit scope -- this repo writes `review(6178): ...`, which a
# bare `review: ` regex misses, reading as "review never ran"; PR #6933) from
# rf-review-finding-default-fix-inline (post-#2374).
REVIEW_COMMIT=$(git -C "$WORK_DIR" log "origin/main..$EVIDENCE_TIP" --oneline 2>/dev/null \
  | grep -E "^[a-f0-9]+ (refactor: add code review findings|review(\([^)]*\))?: )" || true)
if [[ -z "$REVIEW_COMMIT" ]]; then
  REVIEW_COMMIT=$(git -C "$WORK_DIR" log "origin/main..$EVIDENCE_TIP" \
    --format='%(trailers:key=Reviewed-By-Soleur,valueonly)' 2>/dev/null \
    | grep '[^[:space:]]' || true)
fi
fi

# Check 3 (current): GitHub issues with "code-review" label referencing this PR.
# Coupled to review-todo-structure.md issue body template ("**Source:** PR #<number>").
# Fail open if gh is unavailable or network fails (Signal 3 is additive, not required).
REVIEW_ISSUES=""
if [[ -z "$REVIEW_TODOS" ]] && [[ -z "$REVIEW_COMMIT" ]]; then
  # Only run the network check if local signals found nothing.
  # The PR number is the resolver's parse above (#8778), so Signals 1-2 and
  # Signal 3 read the same PR. #7409's repeated locked/unlocked arms name the SAME
  # number and resolve to one (an unbounded extraction made the search phrase
  # "PR #N\nN" and denied a PR that had evidence). When the target could not be
  # tied to one PR of this repository, Signal 3 is skipped rather than guessed,
  # except for a merge naming no number at all (legacy branch lookup).
  PR_NUMBER="$PR_HEAD_NUMBER"
  if [[ -z "$PR_NUMBER" && -z "$_pr_nums" ]] \
     && ! grep -qE '(^|[[:space:]])(--repo([[:space:]=]|$)|-[A-Za-z]*R)' <<<"$_scan_args"; then
    # No PR number in command args -- fall back to branch-based lookup
    PR_NUMBER=$(gh pr list --repo "$(git -C "$WORK_DIR" remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||;s|\.git$||')" \
      --head "$CURRENT_BRANCH" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)
  fi
  if [[ -n "$PR_NUMBER" ]]; then
    # Wrap the phrase in literal quotes so GitHub search treats "PR #N" as an
    # exact phrase (otherwise `#123` tokenizes loosely and matches unrelated
    # issues that happen to reference the PR prefix — confirmed in soleur/#2186
    # session when search "PR #123" returned issues that never mentioned 123).
    REVIEW_ISSUES=$(gh issue list --label code-review --state all --search "\"PR #${PR_NUMBER}\"" \
      --limit 1 --json number --jq '.[0].number // empty' 2>/dev/null || true)
  fi
fi

# A stale origin/main makes BOTH local signals untrustworthy in the UNSAFE
# direction, so they are discarded rather than merely warned about (#6724).
#
# Hoisting the fetch above the gate stopped a network failure from
# short-circuiting the gate, but recording FETCH_OK without acting on it left a
# verified bypass: with origin/main stale, `origin/main..HEAD` widens to include
# commits already on main, and this hook MERGES origin/main on every successful
# run — so after one pass a branch inherits main's whole `review:` history.
# Measured: a branch with zero review evidence of its own PASSES the gate in
# that state. This PR makes it strictly worse, because emit-review-trailer.sh
# guarantees main's history is dense with `review:` subjects and trailers.
#
# Signal 3 is unaffected (it queries the remote by PR number, not the local
# range), so a fetch failure degrades to Signal-3-only rather than to a bypass.
# The same widening applies to any evidence tip, not only HEAD.
if [[ "$FETCH_OK" != "1" ]]; then
  REVIEW_TODOS=""
  REVIEW_COMMIT=""
fi

if [[ -z "$REVIEW_TODOS" ]] && [[ -z "$REVIEW_COMMIT" ]] && [[ -z "$REVIEW_ISSUES" ]]; then
  emit_incident "rf-never-skip-qa-review-before-merging" deny \
    "Never skip QA/review before merging. Full pipeline:" "$CMD"
  # The range actually read, derived from the tip so the label cannot drift from it.
  _range="origin/main..${EVIDENCE_TIP:0:12}"
  [[ -n "$EVIDENCE_TIP" && "$FETCH_OK" == "1" ]] || _range="none (local signals skipped)"
  _notes=""
  [[ "$FETCH_OK" == "1" ]] || _notes+=" origin/main could not be fetched, so the local signals were discarded: run git fetch origin main and re-issue."
  # Where to fix it. A subagent's cwd resets per call, so name the PR's checkout.
  _where=""
  if [[ -n "$PR_HEAD_REF" && "$OWN_CHECKOUT" != "1" ]]; then
    _wt=$(git -C "$WORK_DIR" worktree list --porcelain 2>/dev/null \
      | awk -v b="branch refs/heads/$PR_HEAD_REF" '/^worktree /{w=substr($0,10)} $0==b{print w; exit}' || true)
    if [[ -n "$_wt" ]]; then
      _where=" Run the trailer script and the push from PR #$PR_HEAD_NUMBER's checkout: cd $_wt first (the gate reads the PR head as pushed, so an unpushed trailer there does not count)."
    else
      _where=" Run the trailer script and the push from a checkout of PR #$PR_HEAD_NUMBER's branch ($PR_HEAD_REF); the gate reads the PR head as pushed."
    fi
  fi
  jq -n --arg range "$_range" --arg source "$RANGE_SOURCE" --arg notes "$_notes" --arg where "$_where" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: No review evidence for commits in " + $range + " (" + $source + ")." + $notes + " If review has NOT run: run /soleur:review. If it HAS run (or found nothing, which emits no artifacts): bash plugins/soleur/skills/review/scripts/emit-review-trailer.sh --findings <n>." + $where + " Signals checked: todos/ tagged code-review introduced by the PR, a review: commit or Reviewed-By-Soleur: trailer, a code-review-labelled issue citing this PR. Note the scope is the PR only — evidence already on main does not count. Run the trailer script as its own command, then git push, then re-issue gh pr merge: a chained `emit-review-trailer.sh && gh pr merge` is denied because this hook evaluates the whole command before any of it runs. A code-review issue filed only to satisfy this gate is not review.")
    }
  }'
  exit 0
fi

# Sync only the PR's own checkout (#8778). When GitHub answered and the cwd is not
# PR N's branch at or ahead of its head (state P or N), the dirty-tree check,
# `git merge origin/main` and `git push` would act on a branch that is not being
# merged. Placed BEFORE the detached-HEAD exit so a root-anchored session is told
# too. Reported through additionalContext, which the agent sees; stderr it does not.
if [[ -n "$PR_HEAD_OID" && "$OWN_CHECKOUT" != "1" ]]; then
  if [[ "$SAME_BRANCH" == "1" ]]; then
    _skip="is PR #$PR_HEAD_NUMBER's branch but is not at or ahead of its pushed head ${PR_HEAD_OID:0:12} (behind or diverged; pull before relying on local state)"
  else
    _skip="is not PR #$PR_HEAD_NUMBER's checkout (${PR_HEAD_REF:-?} @ ${PR_HEAD_OID:0:12})"
  fi
  jq -n --arg m "Pre-merge hook: $WORK_DIR ($CURRENT_BRANCH) $_skip; skipped the uncommitted-changes check and the origin/main auto-sync. GitHub merges the PR head as pushed; if it rejects the PR as not up to date, run gh pr update-branch $PR_HEAD_NUMBER." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
  exit 0
fi

# Check for detached HEAD -- auto-sync needs a branch to push
if [[ "$CURRENT_BRANCH" == "HEAD" ]]; then
  headless_or_stderr warn "Detached HEAD state. Skipping auto-sync."
  exit 0
fi

# Check for uncommitted changes (tracked files only -- untracked files
# cannot conflict with merge and should not block it).
# Skip if not inside a work tree (bare repo context): git diff --quiet HEAD
# returns 128 and git diff --cached --quiet returns 1 (empty index vs HEAD),
# both false positives. Fail open in bare repo setups (#1386).
if [[ "$(git -C "$WORK_DIR" rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]]; then
  if ! git -C "$WORK_DIR" diff --quiet HEAD 2>/dev/null || \
     ! git -C "$WORK_DIR" diff --cached --quiet 2>/dev/null; then
    emit_incident "hr-when-a-command-exits-non-zero-or-prints" deny \
      "When a command exits non-zero or prints a warning" "$CMD"
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: Uncommitted changes detected. Commit before merging."
      }
    }'
    exit 0
  fi
fi

# The fetch itself now happens above the review-evidence gate (#6724) so that a
# network failure cannot short-circuit the gate. Its outcome is consumed here,
# preserving the original fail-open-on-network-error behaviour for SYNCING only.
if [[ "$FETCH_OK" != "1" ]]; then
  headless_or_stderr warn "Could not fetch origin/main (network error). Proceeding with merge."
  exit 0
fi

# Check if sync is needed by comparing merge-base with origin/main tip
MERGE_BASE=$(git -C "$WORK_DIR" merge-base HEAD origin/main 2>/dev/null) || true
REMOTE_MAIN=$(git -C "$WORK_DIR" rev-parse origin/main 2>/dev/null) || true

if [[ -z "$MERGE_BASE" ]] || [[ -z "$REMOTE_MAIN" ]]; then
  # Could not determine relationship -- fail open
  headless_or_stderr warn "Could not determine branch relationship with main. Proceeding with merge."
  exit 0
fi

if [[ "$MERGE_BASE" == "$REMOTE_MAIN" ]]; then
  # Already up-to-date, no sync needed
  headless_or_stderr info "Branch already up-to-date with origin/main."
  exit 0
fi

# Disjoint-delta skip (#9401). The sync below exists to satisfy the ruleset's
# up-to-date ancestry check; when the incoming main delta shares NO file with
# this branch's diff, landing it is content-free for the PR's purposes but
# still mints a new head SHA — which restarts the required-check set and
# invalidates a green head, the stale-green livelock measured on #9339 while
# `main` was moving hourly and CI took ~25 minutes. A provably disjoint
# incoming delta is therefore announced and skipped: an --admin merge lands
# the certified head unmodified (a plain admin-merge-ready.sh <N> <G> grades G
# directly — the disjoint path needs no carryover flag), while a non-admin merge gets
# GitHub's own not-up-to-date refusal — exactly what an absent hook leaves.
#
# Failure direction is preserved: any error computing either file set (a
# corrupt ref, a missing object) falls THROUGH to the sync below, so the
# pre-#9401 behaviour survives whenever the disjointness proof cannot run.
# --no-renames so a main-side rename of a PR-touched path lists its OLD name
# (delete+add) instead of only the destination — a rename+modify would
# otherwise read disjoint. --name-only reports post-image names under default
# rename detection.
_PR_FILES=""
_INCOMING_FILES=""
if _PR_FILES=$(git -C "$WORK_DIR" diff --name-only --no-renames "$MERGE_BASE" HEAD 2>/dev/null) \
   && _INCOMING_FILES=$(git -C "$WORK_DIR" diff --name-only --no-renames "$MERGE_BASE" "$REMOTE_MAIN" 2>/dev/null); then
  # Fixed-string whole-line membership: no sorting, no locale hazard, -q
  # early-exit. rc is captured because ! alone conflates grep error (rc>=2 →
  # must fall through to the sync) with clean no-match (rc=1 → disjoint). A
  # one-sided-empty set still prints a blank pattern line that cannot match a
  # filename → disjoint; both-empty matches the blank line → sync (harmless).
  _dj_rc=0
  grep -Fxqf <(printf '%s\n' "$_PR_FILES") \
             <(printf '%s\n' "$_INCOMING_FILES") || _dj_rc=$?
  if [[ "$_dj_rc" == 1 ]]; then
    headless_or_stderr info "origin/main advanced only on files disjoint from this branch — sync skipped (delta disjoint)"
    jq -n --arg branch "$CURRENT_BRANCH" \
          --arg incoming "$(printf '%s\n' "$_INCOMING_FILES" | grep -c . || true)" \
          --arg prfiles "$(printf '%s\n' "$_PR_FILES" | grep -c . || true)" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: ("Pre-merge hook: origin/main moved " + $incoming + " file(s), all disjoint from " + $branch + "\u0027s " + $prfiles + " changed file(s) (delta disjoint) — no sync merge, the head SHA stays put. A non-admin merge may still fail GitHub\u0027s not-up-to-date check (a --auto enqueue just parks): either run `gh pr update-branch` for a verified server-side merge, or gate an --admin merge with plugins/soleur/scripts/admin-merge-ready.sh to land the verified head unmodified — the admin path does not exist for a workflow-editing PR.")
      }
    }'
    exit 0
  fi
fi

# Serialize against concurrent main-sync attempts (sibling sessions
# pre-flighting `gh pr merge --auto` from a different worktree). Lock name
# is `rebase-main` per plan §Implementation Phases for the hook surface,
# even though the strategy here is `git merge` (see top-of-file comment on
# the historical filename).
acquire_lock rebase-main 60 || headless_or_stderr warn "rebase-main lock contended; proceeding without serialization"
# Release on any exit path below (merge failure, push failure, success).
trap 'release_lock rebase-main 2>/dev/null || true' EXIT

# Attempt merge
if ! git -C "$WORK_DIR" merge origin/main >/dev/null 2>&1; then
  # Merge failed -- capture conflicts BEFORE aborting (abort clears conflict state)
  CONFLICT_FILES=$(git -C "$WORK_DIR" diff --name-only --diff-filter=U 2>/dev/null \
    | head -5 | tr '\n' ', ' | sed 's/,$//')
  git -C "$WORK_DIR" merge --abort 2>/dev/null || true

  # REGENERABLE-ARTIFACT RETRY (ADR-235). model.likec4.json is the one generated file still
  # committed -- the web-platform C4 viewer fetches it from GitHub as a committed blob on the
  # request path (app/api/kb/c4/project/route.ts; no build step) -- so concurrent .c4 edits
  # conflict on it. The resolver completes the merge and regenerates it
  # from the MERGED sources; anything else it refuses, leaving the tree byte-identical, so the
  # deny below is unchanged for every other conflict.
  #
  # AFTER the abort, deliberately: the resolver requires a clean tree and no merge in
  # progress, and it is a precondition rather than a nicety -- running it on the conflicted
  # tree would make it refuse, which reads identically to "not regenerable".
  #
  # It does not take the rebase-main lock: this hook already holds it (acquired above) and the
  # resolver is documented as taking none, so there is no re-entrancy here.
  REGEN_RESOLVER="$WORK_DIR/plugins/soleur/scripts/resolve-regenerable-conflicts.sh"
  REGEN_ERR=""
  REGEN_OK=0
  if [[ -f "$REGEN_RESOLVER" ]]; then
    # CAPTURE stderr, never discard it. This was `>/dev/null 2>&1`, which falsified the
    # resolver's central design contract -- "the distinction lives in stderr, prefixed
    # `not applicable:` or `regen failed:`, where a human reads it" -- at the one call site
    # that is genuinely UNATTENDED (a PreToolUse hook on `gh pr merge`). The operator got
    # only "Merge of origin/main failed." with no way to tell a refusal from a failure.
    if REGEN_ERR="$( cd "$WORK_DIR" && bash "$REGEN_RESOLVER" origin/main 2>&1 >/dev/null )"; then
      REGEN_OK=1
    fi
  fi
  if [[ "$REGEN_OK" -eq 1 ]]; then
    headless_or_stderr info "regenerable conflict resolved — merge committed, continuing"
  else
    [[ -n "$REGEN_ERR" ]] && headless_or_stderr info "regen-on-conflict declined: $REGEN_ERR"
    # The resolver's refusal is the diagnosis; carry its last [regen-on-conflict] line into the
    # deny reason, which is the only text an agent sees (stderr of a PreToolUse hook is not).
    REGEN_WHY="$(printf '%s\n' "$REGEN_ERR" | grep '^\[regen-on-conflict\]' | grep -v '\] regenerating ' | tail -1 | LC_ALL=C tr -d '\000-\037\177' | cut -c1-400)" || REGEN_WHY=""
    emit_incident "hr-when-a-command-exits-non-zero-or-prints" deny \
      "When a command exits non-zero or prints a warning" "$CMD"
    jq -n --arg files "${CONFLICT_FILES:-unknown}" --arg why "$REGEN_WHY" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ("BLOCKED: Merge of origin/main failed. Conflicting files: " + $files + ". " + (if $why != "" then $why + " " else "" end) + "Resolve conflicts manually before merging; regenerate a generated artifact rather than hand-merging it (merge-pr SKILL.md 3.2b).")
      }
    }'
    exit 0
  fi
fi

# Merge succeeded -- push to update the remote branch.
# Regular push (not force-push) since merge does not rewrite history.
if ! PUSH_OUTPUT=$(git -C "$WORK_DIR" push origin HEAD 2>&1); then
  emit_incident "hr-when-a-command-exits-non-zero-or-prints" deny \
    "When a command exits non-zero or prints a warning" "$CMD"
  jq -n --arg output "$PUSH_OUTPUT" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: Merge succeeded but push failed. Push manually before merging. Error: " + $output)
    }
  }'
  exit 0
fi

# Return success with context so the agent knows what happened
jq -n --arg branch "$CURRENT_BRANCH" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: ("Pre-merge hook: merged origin/main into " + $branch + " and pushed. Branch is now current.")
  }
}'
exit 0
