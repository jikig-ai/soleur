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
# (strip_heredocs): quoted spans stay visible, because `bash -c "gh pr merge 7"` and `--remove-label "parked"` are commands too.
# A statement is one piece of the command between the chain operators (&& || ; | &); inside a statement the quote and
# parenthesis characters become spaces and a trailing ` #` comment is cut, so every pattern below reads plain words.
if command -v strip_heredocs >/dev/null 2>&1; then
  PSCAN=$(strip_heredocs "$CMD")
else
  PSCAN="$CMD"
fi
PARKED_GH_TIMEOUT="${SOLEUR_PARKED_GH_TIMEOUT:-10}"
[[ "$PARKED_GH_TIMEOUT" =~ ^[0-9]+$ ]] || PARKED_GH_TIMEOUT=10
# `gh`, optionally behind the shared wrapper prefix, optionally with a global -R/--repo; the boundary character before it may be
# anything but a word character or a hyphen (so `/usr/bin/gh`, `\gh`, `$(gh`, `|gh` all count, `foo-gh` does not).
PARKED_STMT_PFX='(^|[^[:alnum:]_-])('"${SOLEUR_BOUNDARY_PFX:-}"'[[:space:]]+)*gh[[:space:]]+((-R|--repo)[[:space:]=]+[^[:space:]]+[[:space:]]+)?'
parked_incident() {
  declare -f emit_incident >/dev/null 2>&1 || return 0
  emit_incident wg-block-pr-ready-on-undeferred-operator-steps deny "parked barrier blocked a merge, enqueue or un-park" "${CMD:0:200}" 2>/dev/null || true
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
parked_barrier() {
  local stmt plain after tok repo n
  local -a toks=() prs=()
  local nonflag
  while IFS= read -r stmt; do
    [[ "$stmt" == *gh* ]] || continue
    plain=${stmt//[\"\'\`()]/ }
    plain=${plain%%[[:space:]]#*}
    [[ -n "${plain//[[:space:]]/}" ]] || continue
    repo=""
    if [[ "$plain" =~ (^|[[:space:]])(-R|--repo)[[:space:]=]+([^[:space:]]+) ]]; then repo="${BASH_REMATCH[3]}"; fi
    # Removing or replacing the label: never allowed from an agent session, whatever the PR carries.
    if grep -qiE "${PARKED_STMT_PFX}(pr|issue)[[:space:]]+edit[[:space:]].*--remove-label[[:space:]=]+([^[:space:]]*,)?parked(,|[[:space:]]|$)" <<<"$plain" \
       || grep -qiE "${PARKED_STMT_PFX}label[[:space:]]+(delete|edit)[[:space:]]+parked([[:space:]]|$)" <<<"$plain"; then
      parked_deny "Removing, renaming or deleting the 'parked' label is reserved for the operator: PR merge and enqueue are held by that label. The operator changes it in the GitHub UI or from their own terminal; then the hold line in the plan is rewritten."
    fi
    if grep -qE "${PARKED_STMT_PFX}api[[:space:]]" <<<"$plain"; then
      if grep -qiE '(-X|--method)[[:space:]=]*DELETE' <<<"$plain" && grep -qiE 'labels/parked([[:space:]]|$)' <<<"$plain"; then
        parked_deny "Removing the 'parked' label is reserved for the operator: PR merge and enqueue are held by that label. The operator removes it in the GitHub UI or from their own terminal; then the hold line in the plan is rewritten."
      fi
      # Replacing or clearing the whole label set removes `parked` too: judge it by the PR it is aimed at.
      if grep -qiE '(-X|--method)[[:space:]=]*(PUT|PATCH|DELETE)' <<<"$plain" && grep -qE 'issues/[^[:space:]/]+/labels([[:space:]]|$)' <<<"$plain"; then
        if [[ "$plain" =~ issues/([0-9]+)/labels([[:space:]]|$) ]]; then parked_check_pr "${BASH_REMATCH[1]}" "$repo"; else parked_any_hold "A label write on an issue or PR" "$repo"; fi
      fi
      if grep -qE 'pulls/[^[:space:]/]+/merge' <<<"$plain"; then
        if [[ "$plain" =~ pulls/([0-9]+)/merge ]]; then parked_check_pr "${BASH_REMATCH[1]}" "$repo"; else parked_any_hold "A merge through gh api" "$repo"; fi
      fi
      if grep -qiE 'mergePullRequest|enablePullRequestAutoMerge|enqueuePullRequest|removeLabelsFromLabelable|clearLabelsFromLabelable' <<<"$plain"; then
        parked_any_hold "A GraphQL merge, enqueue or label mutation" "$repo"
      fi
      continue
    fi
    grep -qE "${PARKED_STMT_PFX}pr[[:space:]]+merge([[:space:]]|\$)" <<<"$plain" || continue
    # --disable-auto only un-arms an auto-merge: allowed. A whole token, so a flag value or a comment cannot carry it.
    [[ "$plain" =~ (^|[[:space:]])--disable-auto([[:space:]]|$) ]] && continue
    after=${plain#*merge}
    read -ra toks <<<"$after"
    prs=(); nonflag=0
    for tok in "${toks[@]}"; do
      if [[ "$tok" =~ ^[0-9]+$ ]]; then prs+=("$tok")
      elif [[ "$tok" =~ pull/([0-9]+) ]]; then prs+=("${BASH_REMATCH[1]}")
      elif [[ "$tok" =~ ^[0-9]*[\<\>] ]]; then :   # a redirection (2>, >/dev/null) is not a target
      elif [[ "$tok" != -* ]]; then nonflag=1
      fi
    done
    for n in "${prs[@]}"; do parked_check_pr "$n" "$repo"; done
    if [[ ${#prs[@]} -eq 0 ]]; then
      # No literal number: the current branch's PR is the target of a bare merge; a non-flag word (a variable, a branch name)
      # makes the target unknowable, so any parked PR holds it.
      n=$(parked_gh pr view --json number --jq .number 2>/dev/null || true)
      if [[ "$n" =~ ^[0-9]+$ ]]; then parked_check_pr "$n" "$repo"; fi
      if (( nonflag )); then parked_any_hold "This merge" "$repo"; fi
    fi
  done < <(sed -E 's/(&&|\|\||;|\||&)/\n/g' <<<"$PSCAN")
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
