#!/usr/bin/env bash
# PreToolUse(Bash) hook: denies `gh pr merge` when the merge's head diff vs
# origin/main adds or modifies KB session artifacts that are not under an
# archive/ directory — knowledge-base/project/{specs/<dir>/**, plans/*,
# brainstorms/*}.
#
# wg-kb-artifacts-archived-in-pr — closes the #10064 class: ship Phase 6
# step 5.5's archive run was a numbered item inside the "If an open PR
# exists" arm, so an agent that wrote the PR body itself never ran it and
# the PR merged with its spec dir live on main. The skill-side fix (ship
# `## Phase 6.45: KB Artifact Archival`) makes archival a named phase;
# this hook is the mechanical check that proves it ran. `gh pr ready` is
# deliberately NOT gated: ready marks review-readiness, not publication —
# the merge is the leak event (ruling, decision-challenges).
#
# Contract-inherited PreToolUse(Bash) input shape (sibling-hook parity,
# ship-unpushed-commits-gate.sh):
#   .tool_input.command  (string) — the bash command string
#   .cwd                 (string) — absolute path to the working directory
#   .tool_name           ("Bash") — confirms matcher dispatched correctly
#
# Fail-open conditions (exit 0):
#   - hook input lacks .cwd or path is not an absolute existing directory
#   - not a git repository (git rev-parse --git-dir fails)
#   - HEAD-path merges only: not a work tree (bare repo), detached HEAD,
#     or branch is main/master — HEAD is not the merge's measured object
#     in those states. A numbered `gh pr merge <N>` or
#     `--match-head-commit <sha>` resolves a pushed object and gates on
#     EVERY checkout state (soleur:schedule merges from a main checkout).
#   - proven-foreign repo pointer (-R/--repo/GH_REPO/GH_HOST resolving to
#     a DIFFERENT repository) — the merge is not ours
#   - SOLEUR_SKIP_KB_ARCHIVE_GATE=1 (named in every deny)
#   - unresolvable merge-base (shallow clone): git cannot compare. Warns
#     via headless_or_stderr — no fail-open path is silent.
#
# Fail-closed conditions (deny + emit_incident):
#   - unresolvable merge target: the command names a target the resolver
#     cannot uniquely prove (mixed numbers, non-bare positional, foreign
#     cd, unprovable repo pointer, raw-vs-scan disagreement). A HEAD
#     fallback would mismeasure the object this gate exists to census —
#     simultaneously a false-pass and a false-deny.
#   - git fetch fails (origin main, refs/pull/<N>/head, or the pinned
#     sha): an unverifiable head is the silent-miss class this gate
#     exists to end.
#   - any A/M row at a non-archive path under the three KB roots in
#     merge-base...head.
#
# Hook ordering: wired after ship-unpushed-commits-gate.sh in
# .claude/settings.json (itself after pre-merge-rebase.sh so auto-sync
# pushes land first). The hook mutates nothing — only fetches.

set -eo pipefail
# -u (nounset) omitted: hook failure paths must return JSON, not crash silently.

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

# shellcheck source=lib/hook-input.sh
# FAIL-HARD (no `|| true`): a fail-soft source leaves hook_parse_input
# undefined, the hook dies at the call under `set -e`, prints nothing, exits
# non-zero, and the tool proceeds — defect 2 of #7164.
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"

if ! declare -f hook_parse_input >/dev/null 2>&1; then
  echo "[ship-kb-archive-gate] hook-input helper missing — guards did NOT run for this call" >&2
  exit 0
fi

INPUT=$(cat)
# Parse hook stdin WITHOUT shell evaluation (ADR-156: stdin is
# model-controlled and untrusted). ADR-157: a hook that cannot fully parse
# its input asks; the exit lives at the call site, not inside the library.
if ! hook_parse_input "$INPUT"; then
  hook_input_report "ship-kb-archive-gate"
  hook_input_should_ask && { hook_input_emit_ask "ship-kb-archive-gate"; exit 0; }
  exit 0
fi
CMD="$HOOK_CMD"
WORK_DIR="$HOOK_CWD"
: "${CMD:=}"
: "${WORK_DIR:=}"

# Deliberate one-keystroke repair for a wedged gate — named in every deny
# message (sibling parity: SOLEUR_SKIP_OPERATOR_STEP_GATE et al.).
if [[ "${SOLEUR_SKIP_KB_ARCHIVE_GATE:-}" == "1" ]]; then
  exit 0
fi

SCAN=$(strip_command_bodies "$CMD")

# Trigger boundary (ruling): the sibling's `(^|&&|\|\||;)` set widened per
# pre-merge-rebase.sh:121 + prod-write-defer-gate.sh:179 — `|` (x | gh pr
# merge), `\(` ($()/subshell), `[[:space:]]--[[:space:]]` (the sanctioned
# `with_lock merge-main 600 -- gh pr merge` arming form, #3689 class) plus
# a repeated invocation-prefix clause (env assignments and launcher
# keywords: `FOO=1 gh pr merge`, `time gh pr merge`, `if gh pr merge`).
# `gh pr merge` ONLY — the sibling's `ready` alternation is deliberately
# not absorbed. Documented residuals, shared with every sibling: quoted
# `bash -c '…'` payloads (blanked by strip_command_bodies), `eval`
# indirection, `$GH` variable invocation, `gh api …/merge`, and UI merges
# — none fire; postmerge Phase 5.8 is the net. The census reads the head
# at invoke time but `--auto` merges the queue-time head — a post-arm
# push of live-path artifacts slips every gate in this family; Phase 5.8
# catches the landed result.
_MERGE_BOUNDARY='(^|&&|\|\||\||;|\(|[[:space:]]--[[:space:]])'
_MERGE_PREFIX='(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]&#|;()]+|if|while|until|then|do|elif|else|!|time|env|command|builtin|exec|nohup|sudo)[[:space:]]+)*'
if ! grep -qE "${_MERGE_BOUNDARY}[[:space:]]*${_MERGE_PREFIX}gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)" <<<"$SCAN"; then
  exit 0
fi

# One line per REAL `gh pr merge` invocation, carrying its argument text.
# Shape copied from pre-merge-rebase.sh:126-131 with the anchor widened to
# the same boundary as the fire-check above (a deliberate, documented
# deviation — the sibling's narrower anchor is the #3689 class this gate
# closes on its own trigger).
# `|| true`: a no-match grep exits 1 under pipefail and would abort the hook.
_merge_args() {
  grep -oE '(^|&&|\|\||\||;|\(|[[:space:]]--[[:space:]])[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]&#|;()]+|if|while|until|then|do|elif|else|!|time|env|command|builtin|exec|nohup|sudo)[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+merge([[:space:]][^;&|]*)?' <<<"$1" \
    | sed -E 's/^[^g]*gh[[:space:]]+pr[[:space:]]+merge//' || true
  # `^[^g]*`, not `.*`: the match's prefix is only separators, and a greedy
  # `.*` would skip to the LAST `gh pr merge` in the segment.
}
_scan_args=$(_merge_args "$SCAN")

# Help pass-through (#9454, verbatim semantics from pre-merge-rebase.sh):
# `gh pr merge --help` / `-h` merges nothing, so when EVERY invocation in
# the quote-stripped $SCAN carries an argument token exactly `--help` or
# `-h`, exit 0 now. Quoted text is blanked in $SCAN, so `--body "--help"`
# is not a help form; a single real merge anywhere keeps the hook running.
# No invocation parsed → no skip. A trailing shell comment is cut first.
if [[ -n "$_scan_args" ]] \
   && awk '{ sub(/[[:space:]]#.*$/, "") } $0 !~ /(^|[[:space:]])(--help|-h)([[:space:]]|$)/ { bad = 1 } END { exit bad }' <<<"$_scan_args"; then
  exit 0
fi

# Validate WORK_DIR: absolute path AND existing directory. Defense against
# argument injection — `git -C "-x"` would treat the arg as a flag (CWE-88).
if [[ "$WORK_DIR" != /* ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi
# `rev-parse --git-dir`, NOT --is-inside-work-tree (ruling): a bare repo
# must still reach the numbered-resolution path — only the HEAD path needs
# a work tree.
if ! git -C "$WORK_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# --- begin verbatim import -------------------------------------------------
# The five helpers below are copied byte-for-byte from
# .claude/hooks/pre-merge-rebase.sh (#8778/#9401 resolver) and are pinned
# byte-equal by ship-kb-archive-gate.test.sh's parity case, per the repo's
# copied-helper convention (assert_fixture_dir precedent). Do not reword
# one side only — a hand-edited copy reintroduces the #8778 false-pass /
# false-deny pair the source absorbed two shipped fixes for. If the source
# changes, re-copy.
#
# _merge_args above is a documented exception: its boundary alternation is
# widened per the trigger ruling, so the parity pin diffs the five helpers
# below only.

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
# --- end verbatim import ---------------------------------------------------

# _repo_pointers_all_parsed — 0 iff at least one repo-pointer operand was
# sighted AND every sighted operand parses to a concrete (host, slug) pair.
# Reads the same ambient state as _repo_pointers_same_repo. Used with it to
# discriminate "unprovable" (some operand unparseable or flag-without-
# operand → deny) from "proven foreign" (every operand parses and the set
# is not all-same-repo → exit 0, the merge is not ours).
_repo_pointers_all_parsed() {
  local _ops _k _op _pp _ps _have=0
  _ops=$({ _repo_flag_operands <<<"$_scan_args"; _repo_flag_operands <<<"$_cmd_args"
          _repo_env_operands "$SCAN"; _repo_env_operands "$CMD"
          [[ -n "${GH_REPO:-}" ]] && printf 'R\t%s\n' "$GH_REPO"
          [[ -n "${GH_HOST:-}" ]] && printf 'H\t%s\n' "$GH_HOST"; :; } ) || _ops=""
  [[ -n "$_ops" ]] || return 1
  while IFS=$'\t' read -r _k _op; do
    case "$_k" in
      F) return 1 ;;
      H) _have=1
         [[ -n "${_op#*://}" ]] || return 1 ;;
      R) _have=1
         _pp=$(_repo_url_parts "$_op"); _ps="${_pp#*$'\t'}"
         [[ -n "$_ps" ]] || return 1 ;;
    esac
  done <<<"$_ops"
  [[ "$_have" == "1" ]]
}

_cmd_args=$(_merge_args "$CMD")

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
if [[ "$_REPO_PTR" == "1" && "$_REPO_SAME" != "1" ]] && _repo_pointers_all_parsed; then
  # Every pointer parses and the set is not all-same-repo → the merge
  # targets another repository. Not ours to census (ruling: proven-foreign
  # exits 0; unprovable is the deny arm below).
  exit 0
fi
if [[ "$_REPO_SAME" == "1" ]]; then
  _scan_args=$(_strip_repo_flags <<<"$_scan_args")
  _cmd_args=$(_strip_repo_flags <<<"$_cmd_args")
fi

# Deny helper: one JSON object on stdout, one incident row. Reason text is
# assembled by the caller and passed as $1.
_deny() {
  local reason="$1"
  emit_incident "wg-kb-artifacts-archived-in-pr" deny \
    "Archive KB artifacts into archive/ inside the" "$CMD"
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Which head is being merged. Every REAL `gh pr merge` invocation is parsed
# with the detector's own anchor, in BOTH $SCAN (quoted text blanked) and
# $CMD (raw): a number must survive quote-stripping unchanged (`877"9"`
# strips to `877`), and text that merely mentions `gh pr merge 1` (an
# `echo`, a comment) is not an invocation.
_tok_scan=$(awk '{ print ($1 == "" ? "-" : $1) }' <<<"$_scan_args" || true)
_tok_cmd=$(awk '{ print ($1 == "" ? "-" : $1) }' <<<"$_cmd_args" || true)
MERGE_TARGET_WHY=""
TARGET_KIND=""       # sha | pr | head
PR_HEAD_NUMBER=""
HEAD_OID=""

if [[ "$_tok_scan" != "$_tok_cmd" ]]; then
  MERGE_TARGET_WHY="the gh pr merge invocations differ once quoted text is removed"
fi

# --match-head-commit <40-hex> (the admin hatch's exact merged sha) takes
# precedence when present; a flag sighted without a valid operand denies.
_mhc_scan=$(grep -oE -- '--match-head-commit([[:space:]]+|=)[0-9a-f]{40}([^0-9a-f]|$)' <<<"$_scan_args" \
            | grep -oE '[0-9a-f]{40}' | sort -u || true)
_mhc_cmd=$(grep -oE -- '--match-head-commit([[:space:]]+|=)[0-9a-f]{40}([^0-9a-f]|$)' <<<"$_cmd_args" \
            | grep -oE '[0-9a-f]{40}' | sort -u || true)
if [[ -z "$MERGE_TARGET_WHY" ]]; then
  if [[ "$_mhc_scan" != "$_mhc_cmd" ]]; then
    MERGE_TARGET_WHY="the gh pr merge invocations differ once quoted text is removed"
  elif [[ -n "$_mhc_scan" ]] && [[ "$(grep -c . <<<"$_mhc_scan" || true)" != "1" ]]; then
    MERGE_TARGET_WHY="more than one --match-head-commit sha; merge one PR per command"
  elif [[ -n "$_mhc_scan" ]]; then
    TARGET_KIND="sha"; HEAD_OID="$_mhc_scan"
  elif grep -q -- '--match-head-commit' <<<"$_scan_args"; then
    MERGE_TARGET_WHY="a --match-head-commit flag names no 40-hex sha"
  fi
fi

if [[ -z "$MERGE_TARGET_WHY" && -z "$TARGET_KIND" ]]; then
  # Positional = any token not beginning with '-', across every residue.
  _pos_scan=$(awk '{ for (i = 1; i <= NF; i++) if ($i !~ /^-/) print $i }' <<<"$_scan_args" | sort -u || true)
  if [[ -z "$_pos_scan" ]]; then
    # Flag-only invocation (e.g. `gh pr merge --squash --auto`): no named
    # target, so the merge's object is the session's pushed branch — the
    # HEAD path (ruling: a purely flag-only invocation correctly takes it).
    TARGET_KIND="head"
  else
    # Every invocation's FIRST token must be the same bare PR number.
    _firsts_ok=1
    while IFS= read -r _t; do
      [[ -n "$_t" ]] || continue
      [[ "$_t" =~ ^#?[0-9]+$ ]] || _firsts_ok=0
    done <<<"$_tok_scan"
    _pr_nums=$(sed 's/^#//' <<<"$_pos_scan" | grep -E '^[0-9]+$' | sort -u || true)
    if [[ "$_firsts_ok" == "1" ]] \
       && [[ "$(grep -c . <<<"$_pos_scan" || true)" == "1" ]] \
       && [[ "$(grep -c . <<<"$_pr_nums" || true)" == "1" ]]; then
      TARGET_KIND="pr"; PR_HEAD_NUMBER="$_pr_nums"
    else
      MERGE_TARGET_WHY="a gh pr merge invocation does not name a bare PR number; put the number right after 'gh pr merge'"
    fi
  fi
fi

# Repo pointer sighted but not proven same-repo (and not proven foreign —
# that arm exits above): unprovable → deny.
if [[ -z "$MERGE_TARGET_WHY" && "$_REPO_PTR" == "1" && "$_REPO_SAME" != "1" ]]; then
  MERGE_TARGET_WHY="the command points gh at another repository or one the hook cannot prove is this checkout's origin (-R/--repo, GH_REPO or GH_HOST); drop the pointer and re-issue"
fi

# In-command cd into a checkout of another repository (verbatim ladder arm).
if [[ -z "$MERGE_TARGET_WHY" ]]; then
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

if [[ -n "$MERGE_TARGET_WHY" ]]; then
  _deny "BLOCKED: cannot prove which head this merge lands (${MERGE_TARGET_WHY}). This gate censuses the exact head's diff for unarchived KB artifacts; a HEAD fallback would measure the wrong object. Re-issue with one bare PR number ('gh pr merge <N>') or a clean '--match-head-commit <40-hex>'. Hatch: SOLEUR_SKIP_KB_ARCHIVE_GATE=1 bypasses."
fi

# --- resolve the head object ---------------------------------------------

CURRENT_BRANCH=$(git -C "$WORK_DIR" symbolic-ref --short -q HEAD 2>/dev/null || echo "")

if [[ "$TARGET_KIND" == "head" ]]; then
  # HEAD-path fail-opens (ruling): exempt ONLY this path — the measured
  # object is the session branch, meaningless in these states.
  if [[ "$(git -C "$WORK_DIR" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
    exit 0
  fi
  if [[ -z "$CURRENT_BRANCH" ]] || [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]]; then
    exit 0
  fi
  # Refname validation: defense against argument injection into git argv.
  if [[ ! "$CURRENT_BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]] || [[ "$CURRENT_BRANCH" == -* ]]; then
    exit 0
  fi
  # `gh pr merge` merges the PR's REMOTE head — census origin/<branch>, not
  # local HEAD, which can lag it (a live artifact pushed from elsewhere
  # under-measures the same way; the sibling pays the same fetch cost,
  # ship-unpushed-commits-gate.sh:131). A branch with no upstream has no
  # mergeable head — gh fails before this gate's subject exists.
  if ! git -C "$WORK_DIR" fetch --no-tags --quiet origin "$CURRENT_BRANCH" >/dev/null 2>&1; then
    if git -C "$WORK_DIR" rev-parse --verify -q "refs/remotes/origin/${CURRENT_BRANCH}" >/dev/null 2>&1; then
      _deny "BLOCKED: \`git fetch origin ${CURRENT_BRANCH}\` failed; cannot verify the pushed head for live-path KB artifacts. Run the fetch manually, then re-issue. Hatch: SOLEUR_SKIP_KB_ARCHIVE_GATE=1 bypasses."
    fi
    exit 0
  fi
  HEAD_OID=$(git -C "$WORK_DIR" rev-parse "origin/${CURRENT_BRANCH}" 2>/dev/null || echo "")
  if [[ ! "$HEAD_OID" =~ ^[0-9a-f]{40}$ ]]; then
    exit 0
  fi
elif [[ "$TARGET_KIND" == "pr" ]]; then
  # refs/pull/<N>/head, not refs/heads/<name>: needs no branch name in a
  # git argv, and no `gh` dependency — the ref is a git object.
  # `ls-remote`, NOT fetch-then-FETCH_HEAD: FETCH_HEAD is a shared mutable
  # file, and a concurrent fetch in this clone (another session's hooks,
  # a parallel drain) between the fetch and the rev-parse substitutes a
  # DIFFERENT valid oid — the census then measures a head that is not the
  # merge's. Pin the oid first, then fetch only if the object is missing
  # (the fetch is for objects only; nothing reads FETCH_HEAD after).
  # Fail-CLOSED on read/fetch failure (sibling T9 posture): an
  # unverifiable head is the silent-miss class this gate exists to end.
  HEAD_OID=$(git -C "$WORK_DIR" ls-remote origin "refs/pull/${PR_HEAD_NUMBER}/head" 2>/dev/null | awk '{print $1; exit}')
  if [[ ! "$HEAD_OID" =~ ^[0-9a-f]{40}$ ]]; then
    _deny "BLOCKED: \`git ls-remote origin refs/pull/${PR_HEAD_NUMBER}/head\` returned no commit; cannot verify the merge head for live-path KB artifacts against an unfetched object. Check the PR number and network/origin, then re-issue. Hatch: SOLEUR_SKIP_KB_ARCHIVE_GATE=1 bypasses."
  fi
  if ! git -C "$WORK_DIR" cat-file -e "${HEAD_OID}^{commit}" 2>/dev/null; then
    if ! git -C "$WORK_DIR" fetch --no-tags --quiet origin "refs/pull/${PR_HEAD_NUMBER}/head" >/dev/null 2>&1 \
       || ! git -C "$WORK_DIR" cat-file -e "${HEAD_OID}^{commit}" 2>/dev/null; then
      _deny "BLOCKED: \`git fetch origin refs/pull/${PR_HEAD_NUMBER}/head\` failed; cannot verify the merge head for live-path KB artifacts against an unfetched object. Retry the fetch manually (check network/origin), then re-issue. Hatch: SOLEUR_SKIP_KB_ARCHIVE_GATE=1 bypasses."
    fi
  fi
else
  # --match-head-commit: the exact object GitHub will merge (the admin
  # hatch's pinned sha). Present locally, or fetch it; unreachable → deny.
  if ! git -C "$WORK_DIR" cat-file -e "${HEAD_OID}^{commit}" 2>/dev/null; then
    if ! git -C "$WORK_DIR" fetch --no-tags --quiet origin "$HEAD_OID" >/dev/null 2>&1 \
       || ! git -C "$WORK_DIR" cat-file -e "${HEAD_OID}^{commit}" 2>/dev/null; then
      _deny "BLOCKED: --match-head-commit ${HEAD_OID:0:12} is not fetchable from origin; cannot verify the merge head for live-path KB artifacts. Hatch: SOLEUR_SKIP_KB_ARCHIVE_GATE=1 bypasses."
    fi
  fi
fi

# Refresh origin/main. Redirect BOTH stdout and stderr (git fetch prints
# progress to stderr; mixing with hook JSON corrupts the harness-side jq
# parse). Fail-CLOSED: a fetch failure means the merge-base cannot be
# trusted, and silent-miss is the exact class this gate exists to prevent.
if ! git -C "$WORK_DIR" fetch --no-tags origin main >/dev/null 2>&1; then
  _deny "BLOCKED: \`git fetch origin main\` failed; cannot census the merge head's KB artifacts against a stale origin/main. Run \`git fetch origin main\` manually, then re-issue. Hatch: SOLEUR_SKIP_KB_ARCHIVE_GATE=1 bypasses."
fi

BASE=$(git -C "$WORK_DIR" merge-base origin/main "$HEAD_OID" 2>/dev/null || true)
if [[ -z "$BASE" ]]; then
  # Unresolvable merge-base = shallow-clone class: git genuinely cannot
  # compare, and denying every merge from a shallow checkout would wedge
  # drain/schedule sessions. archive-kb.sh already degrades on the same
  # condition, so the exposure predates this hook. Warn — never silent.
  headless_or_stderr warn "[ship-kb-archive-gate] merge-base unresolvable (shallow clone?); skipping KB-artifact census for this merge."
  exit 0
fi

# Census: A/M rows under the three KB roots, non-archive only.
#   - `*/archive/*` rows are already archived — pass.
#   - specs/ requires depth ≥ 2 (specs/<dir>/<file>, <dir> != archive);
#     a root-level specs/.gitkeep never fires.
#   - learnings/ and the domain KB dirs are never archived and never
#     gated — not session artifacts.
# -z + read -d '': --name-status alone quotes paths containing special
# characters. With -z each record is `STATUS\tPATH\0`.
LEAKY=""
count=0
while IFS= read -r -d '' _st && IFS= read -r -d '' _path; do
  [[ -n "$_path" ]] || continue
  case "$_path" in
    */archive/*) continue ;;
    knowledge-base/project/specs/*/*)
      _dir="${_path#knowledge-base/project/specs/}"
      _dir="${_dir%%/*}"
      [[ "$_dir" == "archive" ]] && continue
      ;;
    knowledge-base/project/plans/*|knowledge-base/project/brainstorms/*)
      ;;
    *) continue ;;
  esac
  LEAKY+="${_st}"$'\t'"${_path}"$'\n'
  count=$((count + 1))
  [[ "$count" -ge 10 ]] && break
done < <(git -C "$WORK_DIR" diff --name-status -z --diff-filter=AM \
           "$BASE" "$HEAD_OID" -- \
           knowledge-base/project/specs \
           knowledge-base/project/plans \
           knowledge-base/project/brainstorms 2>/dev/null)

if [[ -z "$LEAKY" ]]; then
  # Sibling-convention silent exit on pass.
  exit 0
fi

# Sanitize the row list: C0 control bytes except \t and \n, DEL, U+2028-9,
# 80-char truncation (sibling precedent; CWE-117/CWE-532).
ROWS=$(printf '%s' "$LEAKY" \
  | LC_ALL=C tr -d '\000-\010\013-\037\177' \
  | LC_ALL=C sed -e $'s/\xe2\x80\xa8//g' -e $'s/\xe2\x80\xa9//g' \
  | awk '{ if (length($0) > 80) print substr($0,1,79)"…"; else print $0 }')

_deny "BLOCKED: this merge lands KB artifacts at live paths — archive them inside the PR (rule wg-kb-artifacts-archived-in-pr).

Unarchived artifacts in the merge head's diff vs origin/main (≤10 shown):
${ROWS}
Fix: bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh
then: git add -A knowledge-base && git commit -m \"chore(kb): archive <branch> artifacts at ship\" && git push
(the check reads the pushed PR head — a local-only archive does not clear it).
For an M-row on specs/<dir>/ — archive-kb refuses to collapse a modified live spec dir by design — use the manual path:
  git mv knowledge-base/project/specs/<dir> knowledge-base/project/specs/archive/<ts>-<dir> && git commit && git push
Ordering: archive only AFTER ship's last live-path reads — Phase 6 step 2.5 (decision-challenges render) and step 5 (Operator Holds). It belongs inside ship \"## Phase 6.45: KB Artifact Archival\".
Hatch: SOLEUR_SKIP_KB_ARCHIVE_GATE=1 bypasses."
