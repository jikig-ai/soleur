#!/usr/bin/env bash
set -euo pipefail

# Lint: bot workflows that create PRs via GITHUB_TOKEN must post synthetic
# check-runs for ALL required checks.
#
# Bot PRs created via GITHUB_TOKEN do not trigger CI (GitHub prevents
# infinite loops). Without synthetic check-runs for every required check,
# auto-merge is permanently blocked.
#
# Scope is content-based (since #3548): the lint walks every workflow in
# .github/workflows/, exempts skill-security-scan-pr-trailer.yml (real CI,
# not a bot workflow), and applies a two-part predicate:
#
#   (1) `gh pr create` appears inside a shell `run:` block (not a prompt:
#       block, not a YAML-level comment). The existing has_shell_pr_create
#       helper handles this.
#   (2) `gh api .../check-runs` appears inside a shell `run:` block — i.e.,
#       the workflow posts synthetic check-runs inline rather than via the
#       shared bot-pr-with-synthetic-checks composite action. Composite-
#       action consumers are covered by the action's CHECK_NAMES list and
#       are intentionally exempt from this lint.
#
# Workflows where `gh pr create` only appears inside claude-code-action
# prompt blocks are exempt -- the App token (app/claude) triggers real CI.
# These print a `skip:` line for operator visibility.
#
# Refs: #826, #1468, #3543, #3548

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="${WORKFLOW_DIR:-.github/workflows}"
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/required-checks.txt}"

# --- Load required checks from config ---

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "FAIL: Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

required_checks=()
while IFS= read -r line; do
  # Strip trailing inline comments and surrounding whitespace, but PRESERVE
  # internal whitespace -- check names may contain spaces (e.g.
  # "skill-security-scan PR gate" is one check, not three).
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  # Strip a single matching pair of surrounding double quotes — operators
  # may write `"foo bar"` to make the spaces explicit; the grep patterns
  # below match the workflow's `-f name="foo bar"` form independently.
  if [[ "$line" == \"*\" ]]; then
    line="${line#\"}"
    line="${line%\"}"
  fi
  [[ -z "$line" ]] && continue
  required_checks+=("$line")
done < "$CONFIG_FILE"

if [[ ${#required_checks[@]} -eq 0 ]]; then
  echo "FAIL: No required checks found in $CONFIG_FILE" >&2
  exit 1
fi

echo "Required synthetic checks: ${required_checks[*]}"
echo "---"

# --- Helper: check if file has gh pr create in a shell run: block ---
# Returns 0 (true) if gh pr create appears in a YAML run: block,
# returns 1 (false) if it only appears in prompt: blocks or similar.

# scan_run_blocks walks the file once, calling a predicate function per
# line that lives inside a shell `run:` block. Returns 0 iff the predicate
# returns 0 for any in-run line; returns 1 otherwise. Used as the
# load-bearing distinguisher between header-comment mentions
# (e.g., "synthetic check-runs satisfy") and real inline calls
# (`gh api .../check-runs`). YAML-level `#` comments and `prompt:` blocks
# are excluded by construction.
#
# Known limitation: the `run:` regex also matches YAML keys named `run:`
# at the JOB level (`jobs:\n  run:\n    steps:...`). In practice this is
# benign — the inner step-level `run:` resets run_indent to a deeper level
# and the load-bearing predicates (`gh pr create`, `gh api ... check-runs`)
# are themselves uncommon outside shell contexts. Tracked in the follow-up
# scope-out issue for a future YAML-aware rewrite.
scan_run_blocks() {
  local file="$1" predicate="$2"
  local in_run=false
  local run_indent=0

  while IFS= read -r wfline; do
    # Match `run:` followed by an optional YAML block-scalar style indicator
    # (`|`, `|-`, `|+`, `>`, `>-`, `>+`) and end-of-line — OR `run:` followed
    # by an inline scalar (not starting with a block-scalar indicator).
    # `run: |-` is the canonical idiom in many GitHub Actions style guides;
    # a regex that matches only `|` and bare scalars produces a silent false-
    # negative on every `|-` / `|+` / `>` block.
    if [[ "$wfline" =~ ^([[:space:]]*)run:[[:space:]]*([\|\>][-+]?)?[[:space:]]*$ ]] || \
       [[ "$wfline" =~ ^([[:space:]]*)run:[[:space:]]+[^\|\>[:space:]] ]]; then
      in_run=true
      local prefix="${BASH_REMATCH[1]}"
      run_indent=${#prefix}
      continue
    fi

    if $in_run; then
      if [[ "$wfline" =~ ^([[:space:]]*)[a-zA-Z_-]+: ]]; then
        local key_prefix="${BASH_REMATCH[1]}"
        if [[ ${#key_prefix} -le $run_indent ]]; then
          in_run=false
          continue
        fi
      fi

      if "$predicate" "$wfline"; then
        return 0
      fi
    fi
  done < "$file"

  return 1
}

# Line-level predicate: `gh pr create` invocation. Whitespace-flexible so
# `gh  pr  create` (multiple spaces, tabs) does not silently escape.
_is_gh_pr_create_line() {
  [[ "$1" =~ gh[[:space:]]+pr[[:space:]]+create ]]
}

# Line-level predicate: same-line `gh api` + `check-runs` (the canonical
# inline synthetic-posting shape, e.g.,
# `gh api "repos/.../check-runs" \`). Both tokens required on the same
# line — a naive `check-runs` substring would false-positive on header
# comments like rule-metrics-aggregate.yml's "synthetic check-runs satisfy".
_is_inline_check_runs_post_line() {
  [[ "$1" == *"gh api"* && "$1" == *"check-runs"* ]]
}

has_shell_pr_create() {
  scan_run_blocks "$1" _is_gh_pr_create_line
}

has_inline_check_runs_post() {
  scan_run_blocks "$1" _is_inline_check_runs_post_line
}

# Exact-basename match for the CI-not-bot exclusion. Substring matching
# (`*skill-security-scan-pr-trailer*`) would silently exclude attacker- or
# typo-introduced files like `evil-skill-security-scan-pr-trailer.yml` or
# `skill-security-scan-pr-trailer-v2.yml`.
is_excluded_workflow() {
  [[ "$(basename "$1")" == "skill-security-scan-pr-trailer.yml" ]]
}

# --- Scan workflows ---

failures=0
checked=0
skipped=0

for file in "$WORKFLOW_DIR"/*.yml; do
  [[ -f "$file" ]] || continue

  # Exclude skill-security-scan-pr-trailer.yml: real CI workflow on
  # pull_request_target, not a bot PR-creator. Matches the exclusion in
  # scripts/audit-bot-codeql-coverage.sh.
  is_excluded_workflow "$file" && continue

  # Only check files that create PRs (anywhere in the file). Whitespace-
  # flexible so `gh  pr  create` (extra spaces or tabs) does not bypass.
  grep -qE "gh[[:space:]]+pr[[:space:]]+create" "$file" || continue

  # Check if gh pr create appears in a shell run: block
  if ! has_shell_pr_create "$file"; then
    # gh pr create only in prompt: blocks (App token handles CI) or in
    # YAML-level comments (e.g., pr-auto-close-scanner.yml).
    skipped=$((skipped + 1))
    echo "skip: $file (no shell-level PR creation — App token or comment-only)"
    continue
  fi

  # Composite-action consumers do not post synthetics inline — coverage is
  # provided by .github/actions/bot-pr-with-synthetic-checks/action.yml.
  # Skip silently; the action itself ensures correctness for these files.
  if ! has_inline_check_runs_post "$file"; then
    continue
  fi

  checked=$((checked + 1))
  file_failures=()

  for check_name in "${required_checks[@]}"; do
    # Look for synthetic check-run creation patterns:
    # 1. Checks API:   -f name=<bareword> or -f name="<quoted>"  (multi-word
    #    names like "skill-security-scan PR gate" require quoting in shell)
    # 2. Statuses API: -f context=<bareword> or -f context="<quoted>"
    # ERE-escape any regex meta in the check name (rare, but conservative).
    escaped=$(printf '%s' "$check_name" | sed 's/[][\.^$*+?(){}|/\\]/\\&/g')
    if ! grep -qE "\-f name=${escaped}([[:space:]]|$)" "$file" && \
       ! grep -qE "\-f name=\"${escaped}\"" "$file" && \
       ! grep -qE "\-f context=${escaped}([[:space:]]|$)" "$file" && \
       ! grep -qE "\-f context=\"${escaped}\"" "$file"; then
      file_failures+=("$check_name")
    fi
  done

  if [[ ${#file_failures[@]} -gt 0 ]]; then
    echo "FAIL: $file is missing synthetic check-runs for: ${file_failures[*]}"
    failures=$((failures + 1))
  else
    echo "ok: $file (all ${#required_checks[@]} synthetics present)"
  fi
done

echo "---"

if [[ "$checked" -eq 0 && "$skipped" -gt 0 ]]; then
  echo "All $skipped PR-creating workflow(s) use App tokens (no synthetics needed)."
  exit 0
fi

if [[ "$checked" -eq 0 ]]; then
  echo "No bot workflows with inline synthetic check-runs posting found."
  exit 0
fi

if [[ "$failures" -gt 0 ]]; then
  echo ""
  echo "$failures of $checked workflow(s) are missing synthetic check-runs."
  echo "Bot PRs from these workflows will deadlock on the CI Required ruleset."
  echo ""
  echo "Fix: add synthetic check-run posts for all required checks after 'gh pr create'."
  echo "See scheduled-weekly-analytics.yml for the correct pattern."
  echo "Required checks are defined in: $CONFIG_FILE"
  echo "Ref: #1468"
  exit 1
fi

echo "All $checked GITHUB_TOKEN workflow(s) post complete synthetic check-runs."
if [[ "$skipped" -gt 0 ]]; then
  echo "($skipped additional workflow(s) skipped -- PR creation via App token)"
fi
exit 0
