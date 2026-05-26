#!/usr/bin/env bash
# Lefthook commit-time advisory hook for skill-security-scan (#2719).
#
# Runs the scanner against each staged SKILL.md / agent MD. ALWAYS exits 0
# (advisory). On HIGH-RISK without an override artifact in the same diff,
# prints a one-line stderr breadcrumb so the operator sees the warning even
# when committing via IDE / `git commit --no-verify` would have bypassed the
# Claude Code tool-layer hook.
#
# Belt-and-suspenders only. The load-bearing block lives in:
#   1. PreToolUse hook on Write (.claude/hooks/skill-security-scan-write.sh)
#   2. CI pre-merge required check (.github/workflows/skill-security-scan-pr-trailer.yml)
#   3. CI post-merge audit (.github/workflows/skill-security-scan-postmerge.yml)
#
# Per AGENTS.md `hr-the-host-terminal-is-warp` and lefthook conventions, this
# hook uses $CLAUDE_PROJECT_DIR for path resolution; falls back to git root.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SCANNER="$PROJECT_DIR/plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh"

# Source incidents.sh with no-op fallback if not present.
if [ -f "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" ]; then
  # shellcheck disable=SC1091
  . "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" || true
fi

emit() { command -v emit_incident >/dev/null 2>&1 && emit_incident "$@" || true; }

if [ ! -x "$SCANNER" ] && [ ! -f "$SCANNER" ]; then
  echo "skill-security-scan-advisory: scanner not present at $SCANNER (skipping)" >&2
  exit 0
fi

# Iterate staged file args from lefthook ({staged_files}).
for path in "$@"; do
  [ -f "$path" ] || continue
  case "$path" in
    *SKILL.md|.claude/agents/*.md|plugins/soleur/agents/*.md)
      verdict="$(SKILL_SECURITY_SCAN_OFFLINE=1 bash "$SCANNER" < "$path" 2>/dev/null | head -1 | grep -oE 'HIGH-RISK|REVIEW|LOW-RISK' || echo 'UNKNOWN')"
      case "$verdict" in
        HIGH-RISK)
          # Check for override artifact in current branch staged or committed diff.
          override_present=0
          if git diff --cached --name-only --diff-filter=A 2>/dev/null | grep -q '^knowledge-base/security/skill-overrides/'; then
            override_present=1
          fi
          if [ "$override_present" = "1" ]; then
            echo "skill-security-scan-advisory: HIGH-RISK on $path WITH override artifact present (proceeding)" >&2
            emit skill-security-scan applied "high-risk-with-override"
          else
            echo "skill-security-scan-advisory: HIGH-RISK on $path (no override artifact in diff). See plugins/soleur/skills/skill-security-scan/references/override-mechanism.md" >&2
            emit skill-security-scan applied "high-risk-no-override"
          fi
          ;;
        REVIEW)
          echo "skill-security-scan-advisory: REVIEW on $path" >&2
          emit skill-security-scan applied "review"
          ;;
        LOW-RISK)
          emit skill-security-scan applied "low-risk"
          ;;
      esac
      ;;
  esac
done

exit 0
