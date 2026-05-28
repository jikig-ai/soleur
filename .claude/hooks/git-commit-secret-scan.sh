#!/usr/bin/env bash
# PreToolUse hook on Bash matching `git commit`. Scans the staged index for
# secret-shaped strings (PEM bodies, vendor tokens, AWS keys) via gitleaks
# and denies the commit if any are found.
#
# Why this hook exists alongside lefthook: lefthook's pre-commit hook is
# only triggered when a `.git/hooks/pre-commit` symlink is installed in
# the working repo (lefthook install). In Soleur's bare-repo + worktree
# topology, fresh worktrees do NOT inherit the hook from the bare repo
# unless `lefthook install` is re-run per worktree. The "Secret-scanning
# floor (#3121)" gate defined in lefthook.yml therefore never fires for
# many local commits — CI catches the leak only at push time. This
# PreToolUse hook closes the gap at the Bash-tool boundary, runs
# regardless of .git/hooks/ state, and cannot be bypassed by
# `git commit --no-verify`.
#
# Source rule: terraform-show-json leak incident (2026-05-25 learning).
# Routing: relies on the same `.gitleaks.toml` and gitleaks binary that
# lefthook would have used — no rule duplication.
#
# Hook stdin: JSON payload from Claude Code with tool_name + tool_input.
# Hook stdout: JSON {hookSpecificOutput: {hookEventName, permissionDecision, permissionDecisionReason}}.
# Hook exit code: 0 always (JSON output controls the gate).
#
# Fail-open conditions (the hook allows the commit + emits a warn):
#   - gitleaks binary not installed on PATH
#   - Not inside a git work tree
#   - .gitleaks.toml not present at the repo root
# These are operator-environment issues, not secret-leak signals — the
# user should fix their tooling but a missing binary should not block
# every commit. CI re-scans on every push as the load-bearing gate.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [ -f "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" ]; then
  # shellcheck disable=SC1091
  . "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" || true
fi
emit() { command -v emit_incident >/dev/null 2>&1 && emit_incident "$@" || true; }

allow() {
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
}

deny() {
  local reason="$1"
  emit git-commit-secret-scan deny "git-commit-secret-scan: $reason"
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

payload="$(cat)"
tool_name="$(echo "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"

# Only fire on Bash.
[ "$tool_name" = "Bash" ] || allow

command="$(echo "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$command" ] || allow

# Match `git commit` as a command-leading verb. Tolerates:
#   - bare `git commit ...`
#   - chained: `... && git commit ...`, `... ; git commit ...`, `... | git commit ...`
#   - leading whitespace
# Rejects:
#   - substring matches inside other args (e.g. `echo "git commit example"`)
#   - other git subcommands (git-commit-tree, git commit-graph)
#
# The regex anchors `git commit` after one of: start-of-string, whitespace
# after a chain operator (`&&`, `||`, `;`, `|`), or `$(`. Then requires a
# trailing space-or-end so `commit-tree` / `commit-graph` are not matched.
if ! echo "$command" | grep -qE '(^|[[:space:]]|&&|\|\||;|\$\()[[:space:]]*git[[:space:]]+commit([[:space:]]|$)'; then
  allow
fi

# At this point: the tool call is a `git commit` (or a chain containing one).
# Run gitleaks against the staged index. Fail-open if gitleaks is missing.

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "[git-commit-secret-scan] WARN: gitleaks not installed — skipping scan. Install via 'brew install gitleaks' or release page." >&2
  emit git-commit-secret-scan bypass "gitleaks not installed"
  allow
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  emit git-commit-secret-scan bypass "not inside git work tree"
  allow
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [ -z "$repo_root" ] || [ ! -f "$repo_root/.gitleaks.toml" ]; then
  echo "[git-commit-secret-scan] WARN: .gitleaks.toml not found at repo root — skipping scan." >&2
  emit git-commit-secret-scan bypass ".gitleaks.toml absent"
  allow
fi

# Run the same scan lefthook.yml configures, against the staged index only.
# `--exit-code 1` makes gitleaks return non-zero on findings.
# `--redact` ensures the matched secret bytes do not appear in stderr.
# `--no-banner` reduces output noise.
# `--report-format json` + `--report-path` capture findings for the deny
# reason without printing the raw secrets to the hook's stdout/stderr.
report_file="$(mktemp -t gitleaks-staged-XXXXXX.json)"
trap 'rm -f "$report_file"' EXIT INT TERM

# `gitleaks git --pre-commit --staged` scans only files added to the index
# (matches the lefthook-staged invocation byte-for-byte). The hook's CWD
# may not be the repo root, so cd into it first.
scan_rc=0
(
  cd "$repo_root" || exit 1
  gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1 \
    --report-format json --report-path "$report_file" >/dev/null 2>&1
) || scan_rc=$?

if [ "$scan_rc" -eq 0 ]; then
  allow
fi

# scan_rc != 0 → findings present (or gitleaks crashed). Build a redacted
# deny reason that names the files + rule IDs but never the secret body.
findings_count=0
findings_summary=""
if [ -s "$report_file" ]; then
  findings_count="$(jq -r 'length' "$report_file" 2>/dev/null || echo 0)"
  # Each finding: {RuleID, File, StartLine}. Cap at 5 to keep the deny
  # reason terse; the operator can re-run gitleaks locally to see the rest.
  findings_summary="$(jq -r '
    [.[] | "\(.File):\(.StartLine) (\(.RuleID))"] | .[0:5] | join("; ")
  ' "$report_file" 2>/dev/null || echo "")"
fi

if [ "$findings_count" = "0" ] || [ -z "$findings_summary" ]; then
  # gitleaks exited non-zero but the report file is empty/missing — likely
  # a transient gitleaks error rather than a real finding. Fail-open with
  # a warn so a broken binary doesn't block every commit.
  echo "[git-commit-secret-scan] WARN: gitleaks exited $scan_rc but produced no findings report; allowing commit. Run 'gitleaks git --pre-commit --staged' locally to diagnose." >&2
  emit git-commit-secret-scan bypass "gitleaks exit=$scan_rc, empty report"
  allow
fi

reason="BLOCKED: gitleaks found ${findings_count} secret-shaped string(s) in the staged index. Locations: ${findings_summary}. The default action is to scrub the secrets — never commit-then-rotate. Recovery: (1) unstage the offending file(s) with 'git restore --staged <path>'; (2) redact the secret bytes in place; (3) re-stage and retry. If the staged content is a captured-real fixture from 'terraform show -json' or similar, strip the '.variables' block — terraform-show-json embeds sensitive HCL variables verbatim regardless of sensitive=true. See knowledge-base/project/learnings/security-issues/2026-05-25-terraform-show-json-leaks-sensitive-variables-into-fixtures.md."

deny "$reason"
