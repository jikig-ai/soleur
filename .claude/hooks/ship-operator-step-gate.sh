#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks `gh pr ready` and `gh pr merge --auto` when the
# PR body contains undeferred operator-step accretions.
#
# Enforces hard rule `hr-never-label-any-step-as-manual-without` and workflow
# gate `wg-block-pr-ready-on-undeferred-operator-steps` at the
# `gh pr ready` / `gh pr merge --auto` boundary — closing the bypass class
# where the agent skips /ship Phase 5.5 (where the gate is documented) and
# goes straight to `gh pr ready`.
#
# Pattern source: ship/SKILL.md §Undeferred Operator-Step Gate, with broader
# detection regex covering phrasings observed in real PRs that slipped the
# narrower /ship version (PR #4227, 2026-05-21):
#   - `Operator: <noun>` (capitalised, with colon — bullet headings)
#   - `Operator (verify|confirm|set|file|check|...)`  (extended verb set)
#   - `T+<N><units>` verification bullets ("T+90 min", "T+24h")
#   - `Within <N>h of merge: (file|run|verify)`
#   - `**Post-merge**:` blocks with action verbs
#
# Contract-inherited PreToolUse(Bash) input shape (sibling-hook parity):
#   .tool_input.command  (string) — the bash command string
#   .cwd                 (string) — absolute path to working directory
#
# Fail-open conditions (exit 0 silently):
#   - input lacks .cwd or path is not an absolute existing directory
#   - command is not `gh pr ready` / `gh pr merge --auto`
#   - cannot read PR body (no PR exists yet, gh not authenticated, etc.)
#
# Fail-closed conditions (deny + emit_incident):
#   - PR body contains operator-step accretions without OPEN
#     `deferred-automation` / `automation gap` companion issues
#
# The `parked` barrier (#12197, CTO rulings 2026-11-07 and 2026-11-08), a SEPARATE branch that runs first. It is a BEST-EFFORT
# GUARDRAIL against accidental merges by agent sessions working in a checkout that carries this file. It is NOT an access
# control: the real hold on a parked PR is its DRAFT status (GitHub refuses to merge a draft; drain-prs excludes drafts), and this
# hook is absent from origin/main until the pull request that adds it merges, so a session on a main-based checkout does not run
# it. While a PR carries the existing `parked` label ("Reviewed draft held until an approved window; do not merge or arm
# auto-merge"), a `gh pr merge` that is not `--disable-auto` (plain, --auto, --admin, chained, quoted, wrapped in `bash -c`, a
# PR URL, `-R/--repo`, a `gh api` merge or a GraphQL merge/enqueue mutation) is denied, and so is anything that removes or
# replaces the label (`gh pr|issue edit --remove-label`, `gh label delete|edit`, a `gh api` write on the labels). A merge whose
# target cannot be read as a literal PR number (a shell variable, a branch name) is denied while ANY open PR is parked, and a
# failed or hung label read (bounded by `timeout`, default 10 s) fails CLOSED. `gh pr ready` is not blocked. The override
# SOLEUR_SKIP_OPERATOR_STEP_GATE does not lift it: the operator clears the label in the UI or in their own terminal, then the
# hold line is rewritten. Limits, stated plainly: it matches command TEXT, so a merge hidden in a script file, built from `$GH`
# or `xargs` input, run from a GitHub Actions job (schedule), or made by a human or an admin UI merge is not seen; the other merge
# sites in skills and scripts do not check `parked` (tracked in the consolidated follow-up issue).

set -eo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh" 2>/dev/null || true

# shellcheck source=lib/hook-input.sh
# FAIL-HARD (no `|| true`): a fail-soft source leaves hook_parse_input
# undefined, the hook dies at the call under `set -e`, prints nothing, exits
# non-zero, and the tool proceeds — defect 2 of #7164, reintroduced one line
# above where every test points.
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"

# The source above is fail-hard, but 12 of the 20 hooks run `set -uo pipefail`
# WITHOUT -e. There a missing helper makes hook_parse_input return 127, `!`
# inverts that to true, the response functions are 127 too, and the hook reaches
# `exit 0` — a clean pass-through with no row and no prompt, which is defect 2
# reintroduced by a broken deploy. Assert it explicitly instead of relying on -e.
if ! declare -f hook_parse_input >/dev/null 2>&1; then
  echo "[ship-operator-step-gate] hook-input helper missing — guards did NOT run for this call" >&2
  exit 0
fi

INPUT=$(cat)
# Parse hook stdin WITHOUT shell evaluation (ADR-156: stdin is
# model-controlled and untrusted). A non-string field is surfaced, never
# coerced — coercion closes the RCE and leaves the guards evaded (#7164).
# ADR-157: a hook that cannot fully parse its input asks. The exit lives
# HERE, at the call site, not inside the library.
if ! hook_parse_input "$INPUT"; then
  hook_input_report "ship-operator-step-gate"
  hook_input_should_ask && { hook_input_emit_ask "ship-operator-step-gate"; exit 0; }
  exit 0
fi
CMD="$HOOK_CMD"
WORK_DIR="$HOOK_CWD"
: "${CMD:=}"
: "${WORK_DIR:=}"

# Match either `gh pr ready` or `gh pr merge` with --auto flag. The chained-
# operator clause catches `gh pr ready && gh pr merge --squash --auto` and
# similar. Word-boundary-anchored to avoid false positives on quoted strings.
# scans $SCAN (commit bodies/heredocs stripped — see lib/incidents.sh) so a
# commit message documenting `gh pr ready` is not mistaken for one (#5192).
# incidents.sh is SOFT-sourced above (`2>/dev/null || true`); under `set -e` a
# bare `strip_command_bodies` call would abort + fail-OPEN if the lib failed to
# load, so guard on the helper and fall back to raw $CMD (fail-toward-firing).
if command -v strip_command_bodies >/dev/null 2>&1; then
  SCAN=$(strip_command_bodies "$CMD")
else
  SCAN="$CMD"
fi
# ---- the parked barrier (see the header) ---------------------------------------------------------------------------------
# Runs BEFORE the ready / merge --auto trigger below, which stays exactly as it was. Only heredoc BODIES are blanked here
# (strip_heredocs); the statement splitter below (PARKED_AWK) then decides what is a command and what is only text, so that
# `bash -c "gh pr merge 7"` is read and `git commit -m "docs: gh pr merge 7"` is not.
if command -v strip_heredocs >/dev/null 2>&1; then
  PSCAN=$(strip_heredocs "$CMD")
else
  PSCAN="$CMD"
fi
PARKED_GH_TIMEOUT="${SOLEUR_PARKED_GH_TIMEOUT:-10}"
[[ "$PARKED_GH_TIMEOUT" =~ ^[0-9]+$ ]] || PARKED_GH_TIMEOUT=10
parked_incident() {
  declare -f emit_incident >/dev/null 2>&1 || return 0
  emit_incident parked-merge-barrier deny "parked barrier blocked a merge, enqueue or un-park" "${CMD:0:200}" 2>/dev/null || true
}
parked_deny() {
  local why="$1"
  parked_incident
  jq -nc --arg r "$why" '{decision: "deny", reason: $r}'
  exit 0
}
# Every gh READ the barrier makes is bounded: a hung gh must read as "could not read" (deny), not as a hook timeout the
# harness may treat as non-blocking.
parked_gh() {
  if command -v timeout >/dev/null 2>&1; then timeout "$PARKED_GH_TIMEOUT" gh "$@"; else gh "$@"; fi
}
# parked_check_pr <n> [repo]: deny when PR n carries the label (any case) or its labels cannot be read.
parked_check_pr() {
  local n="$1" repo="${2:-}" labels
  local -a ra=()
  [[ -n "$repo" ]] && ra=(--repo "$repo")
  if ! labels=$(parked_gh pr view "$n" "${ra[@]}" --json labels --jq '.labels[].name' 2>/dev/null); then
    parked_deny "Could not read the labels of PR #${n}, so the 'parked' barrier fails closed: merge and enqueue of a held PR are reserved for the operator. Retry once gh answers."
  fi
  if grep -qixF 'parked' <<<"$labels"; then
    parked_deny "PR #${n} carries the 'parked' label: merge and enqueue of this PR are reserved for the operator. Agent sessions on this branch and drain-prs do not merge or arm auto-merge on it; the PR's DRAFT status is the real hold. The operator removes the label (GitHub UI or their own terminal), then the hold line in the plan is rewritten. This is not overridable by SOLEUR_SKIP_OPERATOR_STEP_GATE."
  fi
}
# parked_any_hold <why> [repo]: deny when ANY open PR carries the label, for a command whose target is not a literal PR number.
parked_any_hold() {
  local why="$1" repo="${2:-}" c
  local -a ra=()
  [[ -n "$repo" ]] && ra=(--repo "$repo")
  if ! c=$(parked_gh pr list --label parked --state open "${ra[@]}" --json number --jq length 2>/dev/null) || [[ ! "$c" =~ ^[0-9]+$ ]]; then
    parked_deny "Could not list the open 'parked' PRs, so the barrier fails closed for ${why}. Retry once gh answers."
  fi
  if (( c > 0 )); then
    parked_deny "${why} cannot be matched to a literal PR number, and ${c} open PR(s) carry the 'parked' label: merge, enqueue and label changes on a held PR are reserved for the operator. Use the literal PR number (the barrier then checks that PR only)."
  fi
}
# The statement splitter. gh is recognised only at COMMAND POSITION, so a commit message, an echo or a grep that merely MENTIONS
# `gh pr merge 7` is not a command. The shell grammar this has to respect is small, and an awk character walker reads it once:
#   - a quoted span is one word; its content is hidden from the command-position view (B, the span becomes `Q`) and kept for the
#     argument view (P, spaces inside it become \001, an empty span becomes \004), so both views have the SAME words;
#   - EXCEPT the quoted argument of `bash|sh|zsh|dash|ksh -c` or of `eval`: that text IS a command, so it is spliced into the stream
#     as if it were unquoted;
#   - a command substitution inside double quotes ("$(gh pr merge 7)") is queued and walked as its own text;
#   - ; | & && || ( ) { } and a backtick end a statement, except the & of a redirection (2>&1, &>) and the braces of ${...};
#   - a backslash-newline joins lines, and an UNQUOTED # starts a comment.
# Input: the command with newlines turned into \002. Output: one `B<TAB>P` line per non-empty statement.
read -r -d '' PARKED_AWK <<'AWK' || true
function flush(   b, p) {
  b = B; p = P; B = ""; P = ""
  if (b ~ /^[ ]*$/) return
  gsub(/\t/, " ", b); gsub(/\t/, " ", p)
  print b "\t" p
}
function add(x) { B = B x; P = P x }
function lastword(   t) { t = B; sub(/[ ]+$/, "", t); sub(/^.*[ ]/, "", t); return t }
function ispayload(   lw) {
  lw = lastword()
  if (lw == "eval") return 1
  if (lw ~ /^-[A-Za-z]*c$/ && B ~ /(^|[ \/])(bash|sh|zsh|dash|ksh)[ ]/) return 1
  return 0
}
function queue_sub(c,   i, j, inner) {
  i = index(c, "$(")
  if (i > 0) {
    inner = substr(c, i + 2); j = length(inner)
    while (j > 0 && substr(inner, j, 1) != ")") j--
    if (j > 0) inner = substr(inner, 1, j - 1)
    QUEUE[++QT] = inner
  }
  i = index(c, "`")
  if (i > 0) {
    inner = substr(c, i + 1); j = length(inner)
    while (j > 0 && substr(inner, j, 1) != "`") j--
    if (j > 0) inner = substr(inner, 1, j - 1)
    QUEUE[++QT] = inner
  }
}
function endq(content, dq) {
  if (dq && (index(content, "$(") > 0 || index(content, "`") > 0)) queue_sub(content)
  gsub("[ \t\002]", "\001", content)
  if (content == "") content = "\004"
  B = B "Q"; P = P content
}
function walk(s,   L, i, c, nx, q, qc, pd, j) {
  L = length(s); i = 1; q = ""; qc = ""; pd = ""
  while (i <= L) {
    c = substr(s, i, 1); nx = substr(s, i + 1, 1)
    if (q == "'") {
      if (c == "'") { endq(qc, 0); q = ""; qc = "" } else qc = qc c
      i++; continue
    }
    if (q == "\"") {
      if (c == "\\" && i < L) { qc = qc c nx; i += 2; continue }
      if (c == "\"") { endq(qc, 1); q = ""; qc = ""; i++; continue }
      qc = qc c; i++; continue
    }
    if (c == "\\") {
      if (nx == "\002") { add(" "); i += 2; continue }
      if (i < L) { add(c nx); i += 2; continue }
      add(c); i++; continue
    }
    if (c == " " || c == "\t") { add(" "); i++; continue }
    if (c == "\002") { flush(); i++; continue }
    if (c == "#") {
      if (B == "" || B ~ /[ ]$/) { while (i <= L && substr(s, i, 1) != "\002") i++; continue }
      add(c); i++; continue
    }
    if (c == "'" || c == "\"") {
      if (c == pd) { pd = ""; i++; continue }
      if (pd == "" && ispayload()) { pd = c; i++; continue }
      q = c; qc = ""; i++; continue
    }
    if (c == "$" && nx == "{") {
      j = index(substr(s, i), "}")
      if (j > 0) { add(substr(s, i, j)); i += j; continue }
    }
    if (c == ";" || c == "|" || c == "(" || c == ")" || c == "`" || c == "{" || c == "}") { flush(); i++; continue }
    if (c == "&") {
      if (nx == "&") { flush(); i += 2; continue }
      if (nx == ">" || substr(s, i - 1, 1) == ">" || substr(s, i - 1, 1) == "<") { add(c); i++; continue }
      flush(); i++; continue
    }
    add(c); i++
  }
  if (q != "") endq(qc, (q == "\""))
  flush()
}
BEGIN { B = ""; P = ""; QT = 0 }
{ walk($0) }
END { h = 1; while (h <= QT) { walk(QUEUE[h]); h++ } }
AWK
# The words that may stand BEFORE `gh` in a command (wrappers, assignments, flags, keywords). Anything else before it means `gh`
# is an argument of some other command (git commit -m ..., echo, grep) and is not run.
PARKED_PREFIX_RE='^([A-Za-z_][A-Za-z0-9_]*=.*|env|sudo|command|nice|nohup|time|timeout|watch|xargs|rtk|run|err|test|proxy|bypass|summary|exec|builtin|eval|bash|sh|zsh|dash|ksh|if|then|do|else|elif|while|until|!|-.*|[0-9][0-9.]*[smhd]?)$'
# parked_is_parked <word>: the word names the label (any case, \001 spaces dropped).
parked_is_parked() {
  local v=${1//$'\001'/}
  v=${v//[[:space:]]/}
  grep -qixF 'parked' <<<"$v"
}
# parked_removes_label <args...>: a --remove-label (or =) value that lists the label, among others or alone.
parked_removes_label() {
  local -a a=("$@") items=()
  local i v item
  for ((i = 0; i < ${#a[@]}; i++)); do
    v=""
    case "${a[i]}" in
      --remove-label) v=${a[i+1]:-} ;;
      --remove-label=*) v=${a[i]#--remove-label=} ;;
    esac
    [[ -n "$v" ]] || continue
    IFS=',' read -ra items <<<"$v" || true
    for item in "${items[@]}"; do
      if parked_is_parked "$item"; then return 0; fi
    done
  done
  return 1
}
# parked_statement <B view> <P view>: judge one statement.
parked_statement() {
  local -a bt=() pt=() rest=() args=() prs=()
  local nb i gi=-1 t base wl=0 fx=0 k=0 nr c1 c2 repo="" tok skip=0 nonflag=0 n cur rc=0 method="" mu txt hasfield=0
  read -ra bt <<<"$1" || true
  read -ra pt <<<"$2" || true
  nb=${#bt[@]}
  (( nb > 0 )) || return 0
  [[ ${#pt[@]} -eq $nb ]] || pt=("${bt[@]}")
  for ((i = 0; i < nb; i++)); do
    t=${bt[i]}; base=${t##*/}; base=${base#\\}
    if [[ "$base" == gh ]]; then gi=$i; break; fi
    if (( wl )); then [[ "$t" == -- ]] && wl=0; continue; fi
    if (( fx )); then [[ "$t" == -exec || "$t" == -execdir ]] && fx=0; continue; fi
    case "$t" in
      with_lock) wl=1; continue ;;
      find) fx=1; continue ;;
    esac
    [[ "$t" =~ $PARKED_PREFIX_RE ]] || return 0
  done
  (( gi >= 0 )) || return 0
  rest=("${pt[@]:gi+1}"); nr=${#rest[@]}
  for ((i = 0; i < nr; i++)); do
    case "${rest[i]}" in
      -R|--repo) repo=${rest[i+1]:-} ;;
      --repo=*) repo=${rest[i]#--repo=} ;;
    esac
  done
  repo=${repo//$'\001'/}
  while (( k < nr )); do
    case "${rest[k]}" in
      -R|--repo) k=$((k + 2)) ;;
      -*) k=$((k + 1)) ;;
      *) break ;;
    esac
  done
  c1=${rest[k]:-}; c2=${rest[k+1]:-}
  args=("${rest[@]:k+2}")
  # Removing or renaming the label: never allowed from an agent session, whatever the PR carries.
  if [[ "$c1" == pr || "$c1" == issue ]] && [[ "$c2" == edit ]] && parked_removes_label "${args[@]}"; then
    parked_deny "Removing, renaming or deleting the 'parked' label is reserved for the operator: PR merge and enqueue are held by that label. The operator changes it in the GitHub UI or from their own terminal; then the hold line in the plan is rewritten."
  fi
  if [[ "$c1" == label && ( "$c2" == delete || "$c2" == edit ) ]]; then
    for tok in "${args[@]}"; do
      [[ "$tok" == -* ]] && continue
      if parked_is_parked "$tok"; then
        parked_deny "Removing, renaming or deleting the 'parked' label is reserved for the operator: PR merge and enqueue are held by that label. The operator changes it in the GitHub UI or from their own terminal; then the hold line in the plan is rewritten."
      fi
      break
    done
  fi
  if [[ "$c1" == api ]]; then
    args=("${rest[@]:k+1}")
    for ((i = 0; i < ${#args[@]}; i++)); do
      case "${args[i]}" in
        -X|--method) method=${args[i+1]:-} ;;
        --method=*) method=${args[i]#--method=} ;;
        -X?*) method=${args[i]#-X} ;;
        -f|-F|--field|--raw-field|--input) hasfield=1 ;;
      esac
    done
    if [[ -z "$method" ]]; then if (( hasfield )); then method=POST; else method=GET; fi; fi
    mu=$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')
    txt="${args[*]}"
    # A write to the label object itself (rename, delete) or to a label on the parked name.
    if [[ "$mu" != GET ]] && grep -qiE 'labels/parked([[:space:]]|$)' <<<"$txt"; then
      parked_deny "Removing, renaming or deleting the 'parked' label is reserved for the operator: PR merge and enqueue are held by that label. The operator changes it in the GitHub UI or from their own terminal; then the hold line in the plan is rewritten."
    fi
    # Replacing or clearing the label set (or editing the issue/PR object) can drop `parked`: judge it by the PR it is aimed at.
    if [[ "$mu" == PUT || "$mu" == PATCH || "$mu" == DELETE ]]; then
      if [[ "$txt" =~ (issues|pulls)/([0-9]+)(/labels)?([[:space:]]|$) ]]; then
        parked_check_pr "${BASH_REMATCH[2]}" "$repo"
      elif [[ "$txt" =~ (issues|pulls)/[^[:space:]/]*[\$\`][^[:space:]]* ]]; then
        parked_any_hold "A label or issue write on a PR" "$repo"
      fi
    fi
    if grep -qE 'pulls/[^[:space:]/]+/merge' <<<"$txt"; then
      if [[ "$txt" =~ pulls/([0-9]+)/merge ]]; then parked_check_pr "${BASH_REMATCH[1]}" "$repo"; else parked_any_hold "A merge through gh api" "$repo"; fi
    fi
    if grep -qiE 'mergePullRequest|enablePullRequestAutoMerge|enqueuePullRequest|removeLabelsFromLabelable|clearLabelsFromLabelable|updateIssue|updatePullRequest|deleteLabel|updateLabel' <<<"$txt"; then
      parked_any_hold "A GraphQL merge, enqueue or label mutation" "$repo"
    fi
    return 0
  fi
  [[ "$c1" == pr && "$c2" == merge ]] || return 0
  # --disable-auto only un-arms an auto-merge: allowed. A whole word, so a flag value or a comment cannot carry it.
  for tok in "${args[@]}"; do [[ "$tok" == --disable-auto ]] && return 0; done
  for tok in "${args[@]}"; do
    if (( skip )); then skip=0; continue; fi
    case "$tok" in
      -t|--subject|-b|--body|-F|--body-file|--match-head-commit|-A|--author-email|-R|--repo) skip=1; continue ;;
      -*) continue ;;
    esac
    tok=${tok#\#}
    if [[ "$tok" =~ ^[0-9]+$ ]]; then prs+=("$tok")
    elif [[ "$tok" =~ pull/([0-9]+) ]]; then prs+=("${BASH_REMATCH[1]}")
    elif [[ "$tok" =~ ^[0-9]*[\<\>] ]]; then :   # a redirection (2>, >/dev/null) is not a target
    else nonflag=1
    fi
  done
  for n in "${prs[@]}"; do parked_check_pr "$n" "$repo"; done
  if [[ ${#prs[@]} -eq 0 ]]; then
    # No literal number: the current branch's PR is the target of a bare merge; any other word (a variable, a branch name, a
    # token with $ or a backtick) makes the target unknowable, so any parked PR holds it. A current-branch read that fails for any
    # reason but "no pull requests found" is a failed read: it fails closed.
    cur=$(parked_gh pr view --json number --jq .number 2>&1) || rc=$?
    if (( rc == 0 )); then
      if [[ "$cur" =~ ^[0-9]+$ ]]; then parked_check_pr "$cur" "$repo"; else parked_any_hold "The current branch's PR (unreadable answer)" "$repo"; fi
    elif ! grep -qi 'no pull requests found' <<<"$cur"; then
      parked_any_hold "The current branch's PR (the read failed)" "$repo"
    fi
    if (( nonflag )); then parked_any_hold "This merge" "$repo"; fi
  fi
  return 0
}
parked_barrier() {
  local bstr pstr
  if ! command -v awk >/dev/null 2>&1; then
    # No statement splitter: judge the whole command coarsely rather than let it through unread.
    if grep -qiE 'gh[[:space:]]+(pr[[:space:]]+(merge|edit)|issue[[:space:]]+edit|label|api)' <<<"$PSCAN"; then
      parked_any_hold "A command the barrier cannot parse (no awk)"
    fi
    return 0
  fi
  while IFS=$'\t' read -r bstr pstr; do
    parked_statement "$bstr" "$pstr"
  done < <(printf '%s' "$PSCAN" | tr '\n' '\002' | awk "$PARKED_AWK")
  return 0
}
if [[ "$WORK_DIR" == /* && -d "$WORK_DIR" ]]; then cd "$WORK_DIR" 2>/dev/null || true; fi
if grep -qE '(^|[^[:alnum:]_-])gh[[:space:]]' <<<"$PSCAN"; then
  parked_barrier
fi

if ! grep -qE '(^|&&|\|\||;)\s*('"${SOLEUR_BOUNDARY_PFX:-}"'[[:space:]]+)*gh\s+pr\s+(ready|merge\s+.*--auto)(\s|$|&&|\|\||;)' <<<"$SCAN"; then
  exit 0
fi

# Validate WORK_DIR
if [[ "$WORK_DIR" != /* ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi
cd "$WORK_DIR" 2>/dev/null || exit 0

# Allow override via env var (CI workflows, ultrareview, etc.)
if [[ "${SOLEUR_SKIP_OPERATOR_STEP_GATE:-}" == "1" ]]; then
  exit 0
fi

# Resolve the PR number. Try the command first (e.g., `gh pr ready 4227`),
# then fall back to the current branch's PR.
PR_NUM=$(echo "$CMD" | grep -oE 'gh\s+pr\s+(ready|merge[^|;&]*)\s+([0-9]+)' | grep -oE '[0-9]+$' | head -1 || true)
if [[ -z "$PR_NUM" ]]; then
  PR_NUM=$(gh pr view --json number --jq .number 2>/dev/null || true)
fi
[[ -n "$PR_NUM" ]] || exit 0

PR_BODY=$(gh pr view "$PR_NUM" --json body --jq .body 2>/dev/null || true)
[[ -n "$PR_BODY" ]] || exit 0

PR_BODY_FILE=$(mktemp)
trap 'rm -f "$PR_BODY_FILE"' EXIT INT TERM

# Strip fenced code blocks — quotations of the gate's own regex inside
# ```...``` MUST NOT count as undeferred declarations. Fail-closed on
# unbalanced fence per /ship parity.
printf '%s' "$PR_BODY" | awk '
  /^```/ { in_fence = !in_fence; next }
  !in_fence { print }
  END { if (in_fence) exit 2 }
' > "$PR_BODY_FILE" || printf '%s' "$PR_BODY" > "$PR_BODY_FILE"

# Strip HTML-comment override blocks (operator attestation per /ship §687)
sed -i 's|<!--[^>]*-->||g' "$PR_BODY_FILE"

# Broader regex than ship/SKILL.md §Detection — covers the phrasings PR #4227
# slipped past. Anchored to list/bullet markers (no prose false-positives).
#
# Group A: explicit operator/manual declarations
#   - `Operator:` / `Operator <verb>` / `manual gate` / `post-merge operator`
#   - Extended verb set: run/create/provision/configure/paste/cop(y/ies)
#     PLUS verify/confirm/check/file/set/install/upload/audit/click
# Group B: time-anchored verification bullets
#   - `T+<N><units>` (e.g., T+90 min, T+24h, T+2 weeks)
# Group C: post-merge-clock bullets
#   - `Within <N><units> of merge: <verb>`
# Group D: AC-PM<N> tokens (legacy from ship gate)
GROUP_A='[Oo]perator\s*:|[Oo]perator\s+(run|create|provision|configure|paste|cop(y|ies)|verif(y|ies)|confirm|check|file|set|install|upload|audit|click)s?|manual\s+gate|post-merge\s+operator'
GROUP_B='T\+[0-9]+\s*(min|m|h|hour|d|day|wk|week)s?\b.*(verif|check|confirm|file|run)'
GROUP_C='[Ww]ithin\s+[0-9]+\s*(min|m|h|hour|d|day|wk|week)s?(\s+of\s+merge)?\s*:.*(file|run|verif|check|confirm|create|provision|set)'
GROUP_D='AC-PM[0-9]+'

DETECT_RE="^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+(\[[[:space:]xX]\][[:space:]]+)?(\*\*)?(${GROUP_A}|${GROUP_B}|${GROUP_C}|${GROUP_D})"

MATCHES=$(grep -niE "$DETECT_RE" "$PR_BODY_FILE" 2>/dev/null || true)

if [[ -z "$MATCHES" ]]; then
  exit 0
fi

# For each match, verify a `(Tracks|Refs) #NNNN` companion exists on the same,
# previous, or next line AND points to an OPEN issue whose body contains the
# `deferred-automation` or `automation gap` sentinel.
UNDEFERRED=()
while IFS= read -r match_line; do
  line_no=$(echo "$match_line" | awk -F: '{print $1}')
  [[ "$line_no" =~ ^[0-9]+$ ]] || continue
  prev=$((line_no > 1 ? line_no - 1 : 1))
  ctx=$(sed -n "${prev}p;${line_no}p;$((line_no+1))p" "$PR_BODY_FILE")
  refs=$(printf '%s' "$ctx" | grep -oE '(Tracks|Refs)[[:space:]]+#[0-9]+' || true)
  if [[ -z "$refs" ]]; then
    UNDEFERRED+=("$match_line"); continue
  fi
  ok=0
  for n in $(printf '%s' "$refs" | grep -oE '[0-9]+'); do
    state=$(gh issue view "$n" --json state --jq .state 2>/dev/null || echo "")
    [[ "$state" == "OPEN" ]] || continue
    body=$(gh issue view "$n" --json body --jq .body 2>/dev/null || echo "")
    if grep -qiE 'deferred-automation|automation gap' <<<"$body"; then
      ok=1; break
    fi
  done
  [[ "$ok" == 1 ]] || UNDEFERRED+=("$match_line")
done <<< "$MATCHES"

if [[ ${#UNDEFERRED[@]} -eq 0 ]]; then
  exit 0
fi

# Fail-closed: deny the tool call with a structured message.
declare -f emit_incident >/dev/null && \
  emit_incident wg-block-pr-ready-on-undeferred-operator-steps applied \
    "PreToolUse gate blocked gh pr ready/merge --auto for PR #${PR_NUM}" 2>/dev/null || true

REASON_LINES=()
REASON_LINES+=("PR #${PR_NUM} body contains ${#UNDEFERRED[@]} undeferred operator-step accretion(s) (see hr-never-label-any-step-as-manual-without).")
REASON_LINES+=("")
REASON_LINES+=("Matching lines:")
for m in "${UNDEFERRED[@]}"; do
  REASON_LINES+=("  $m")
done
REASON_LINES+=("")
REASON_LINES+=("Resolve via one of:")
REASON_LINES+=("  (a) Inline-execute each step now (Doppler/gh/Playwright/MCP — see hr-exhaust-all-automated-options-before).")
REASON_LINES+=("  (b) File a 'deferred-automation' tracked issue per match: gh issue create --label type/chore --title '...' --body 'deferred-automation backlog item; re-evaluate when: <criterion>' then add 'Tracks #N' next to each match in the PR body.")
REASON_LINES+=("  (c) Emergency override: SOLEUR_SKIP_OPERATOR_STEP_GATE=1 <cmd> (use sparingly; logged as gate-override).")
REASON_LINES+=("  (d) If 2+ of the matches are scriptable and blocked on the SAME credential you cannot mint: invoke skill soleur:operator-bootstrap to generate knowledge-base/project/specs/<feature>/bootstrap.sh, then point ONE tracked follow-through issue's auto_command at its --list plus the stage protocol (the issue closes on the verify stage's stdout markers; bootstrap.sh alone exits 64 without --stage) (hr-multi-step-post-merge-bootstrap-script) — the one option that removes the step instead of recording it.")

REASON=$(printf '%s\n' "${REASON_LINES[@]}")

jq -nc --arg r "$REASON" '{decision: "deny", reason: $r}'
exit 0
