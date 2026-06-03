#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks `gh pr ready` / `gh pr merge --auto` when
# the PR diff adds runbook content (or new runbooks) whose FIRST debug step
# under a "What to do" / "Triage" / "Diagnosis" heading uses SSH-class
# commands as the primary action.
#
# Enforces hard rule `hr-no-ssh-fallback-in-runbooks`. PRIMARY debug steps
# must be a Sentry search URL, a `gh run view`, a `curl` to an API, or a
# `doppler secrets get` probe — NOT `ssh root@`, `docker exec`,
# `journalctl -f`, `systemctl restart`, etc.
#
# Detection: scan `git diff --unified=0` for ADDED lines under runbook
# headings (`.md` files in `knowledge-base/engineering/operations/runbooks/`) and
# flag the FIRST non-blank, non-heading content line under a triage-class
# heading if it matches the SSH-class regex.
#
# Override: `SOLEUR_SKIP_RUNBOOK_SSH_GATE=1` for the genuine cases (a runbook
# section literally documenting the last-resort SSH dance under a clearly-
# labelled "Last-resort diagnosis" heading).

set -eo pipefail

INPUT=$(cat)
eval "$(echo "$INPUT" | jq -r '@sh "CMD=\(.tool_input.command // "") WORK_DIR=\(.cwd // "")"' 2>/dev/null || echo 'CMD="" WORK_DIR=""')"
: "${CMD:=}"
: "${WORK_DIR:=}"

if ! echo "$CMD" | grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+(ready|merge\s+.*--auto)(\s|$|&&|\|\||;)'; then
  exit 0
fi
if [[ "$WORK_DIR" != /* ]] || [[ ! -d "$WORK_DIR" ]]; then exit 0; fi
cd "$WORK_DIR" 2>/dev/null || exit 0
if [[ "${SOLEUR_SKIP_RUNBOOK_SSH_GATE:-}" == "1" ]]; then exit 0; fi

# Determine branch + base for the diff. Mirrors the canonical form in
# sibling gate hooks; falls open if HEAD is detached or base is unknown.
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
[[ -z "$BRANCH" || "$BRANCH" == "HEAD" ]] && exit 0
git fetch origin main 2>/dev/null || true

# Pull the diff against origin/main. If the merge-base lookup fails, fail-open.
BASE=$(git merge-base "origin/main" HEAD 2>/dev/null || true)
[[ -z "$BASE" ]] && exit 0

# Files in scope: runbook .md added or modified.
RUNBOOK_FILES=$(git diff --name-only "$BASE"...HEAD -- 'knowledge-base/engineering/operations/runbooks/*.md' 2>/dev/null || true)
[[ -z "$RUNBOOK_FILES" ]] && exit 0

# SSH-class regex — match the verb at the start of a content line.
# Bullets/numbered-list/code-fence content. Bash ERE.
SSH_RE='^[[:space:]]*([-*]|[0-9]+\.)?[[:space:]]*`?(ssh\b|docker\s+exec\b|journalctl\s+.*(-f\b|--follow\b)|systemctl\s+(restart|stop|start|kill)\b|kill\b|systemd-run\b)'

VIOLATIONS=()
for f in $RUNBOOK_FILES; do
  # Get ADDED lines only (lines starting with `+` in unified diff, minus the
  # `+++` file headers).
  added=$(git diff --unified=0 "$BASE"...HEAD -- "$f" 2>/dev/null | grep -E '^\+[^+]' | sed 's/^+//')
  [[ -z "$added" ]] && continue
  # Match against the SSH regex.
  hits=$(printf '%s\n' "$added" | grep -niE "$SSH_RE" 2>/dev/null || true)
  [[ -z "$hits" ]] && continue
  # Filter out hits that fall inside a "Last-resort diagnosis" or "Emergency
  # only" section — those are sanctioned. The check is heuristic: scan the
  # full added-line window for one of those headings before the hit.
  if printf '%s\n' "$added" | grep -qiE '(last-?resort|emergency only|when all else fails)' ; then
    # If the file has a "last-resort" heading in its added content, only
    # block if the hit appears BEFORE that heading in the diff order.
    last_resort_line=$(printf '%s\n' "$added" | grep -niE '(last-?resort|emergency only|when all else fails)' | head -1 | awk -F: '{print $1}')
    while IFS= read -r hit; do
      hit_line=$(echo "$hit" | awk -F: '{print $1}')
      if [[ "$hit_line" -lt "$last_resort_line" ]]; then
        VIOLATIONS+=("$f: line $hit_line — '$hit'")
      fi
    done <<< "$hits"
  else
    while IFS= read -r hit; do
      VIOLATIONS+=("$f: '$hit'")
    done <<< "$hits"
  fi
done

[[ ${#VIOLATIONS[@]} -eq 0 ]] && exit 0

REASON_LINES=()
REASON_LINES+=("Runbook content adds SSH-class commands as PRIMARY debug steps (hr-no-ssh-fallback-in-runbooks).")
REASON_LINES+=("")
REASON_LINES+=("Violations:")
for v in "${VIOLATIONS[@]}"; do REASON_LINES+=("  $v"); done
REASON_LINES+=("")
REASON_LINES+=("Resolve via:")
REASON_LINES+=("  (a) Move the SSH step under a heading containing 'Last-resort diagnosis' / 'Emergency only' / 'When all else fails'.")
REASON_LINES+=("  (b) Replace with a no-SSH equivalent: Sentry search URL, 'gh run view <id>', curl to an API, doppler secrets get <KEY>.")
REASON_LINES+=("  (c) Override (rare): SOLEUR_SKIP_RUNBOOK_SSH_GATE=1 <cmd>.")

REASON=$(printf '%s\n' "${REASON_LINES[@]}")
jq -nc --arg r "$REASON" '{decision: "deny", reason: $r}'
exit 0
