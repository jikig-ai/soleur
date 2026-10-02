#!/usr/bin/env bash
# fix-round-seats.sh — the single path→seat map for review fix-commit targeted
# rounds AND the `none`-tier panel trigger-gating (ADR-267). One map, two
# consumers, so no second prose predicate table can drift from it.
#
# Usage:
#   fix-round-seats.sh --files <newline-or-comma file list> [--finding-seats <seat,...>]
#
# stdout: one seat leaf-name per line, deduped, deterministic order (the
# never-shed safety floor seats emit first).
#
# Exit codes:
#   0  seats emitted (or legitimately none: empty --files, or non-source paths
#      that map to no seat)
#   2  usage error
#
# --finding-seats carries the seats that reported the findings being fixed
# (from the dedup ledger — see references/risk-tier-and-fix-rounds.md). Every
# token is validated against the canonical seat registry below; unknown tokens
# are dropped with an `unknown-seat:` stderr warning and NEVER echoed raw —
# the input is model-emitted text, and a forged token carrying whitespace or
# metacharacters must not smuggle an extra output line.
#
# Portability: POSIX/bash only — no timeout, sed -i, readlink -f, stat -c,
# date -d (operator hosts include stock macOS).
set -uo pipefail

usage() {
  cat <<'EOF'
Usage: fix-round-seats.sh --files <newline-or-comma file list> [--finding-seats <seat,...>]

Prints the review seats a fix-commit diff should re-spawn, one per line:
{path-mapped seats} ∪ {--finding-seats} ∪ {conditional seats}. A source-touching
fix never resolves empty — unmatched source files emit the code-quality-analyst
floor. An empty --files list emits nothing plus a `note: empty fix diff` stderr
line (a zero-change round legitimately spawns zero seats).

Exit 0 on valid input; exit 2 on usage error.
EOF
}

# Canonical seat registry (leaf names). The parity guard
# plugins/soleur/test/review-tier-parity.test.ts pins this set against
# review.workflow.js DIMENSIONS/agentType — extend both, never one.
SEAT_REGISTRY='security-sentinel code-quality-analyst git-history-analyzer pattern-recognition-specialist architecture-strategist performance-oracle data-integrity-guardian agent-native-reviewer user-impact-reviewer data-migration-expert deployment-verification-agent kieran-rails-reviewer dhh-rails-reviewer test-design-reviewer structural-enumeration semgrep-sast shellcheck anti-slop gdpr-gate'

# Emission order — the never-shed floor seats first, then registry order.
SEAT_ORDER='security-sentinel code-quality-analyst git-history-analyzer pattern-recognition-specialist architecture-strategist performance-oracle data-integrity-guardian agent-native-reviewer user-impact-reviewer data-migration-expert deployment-verification-agent kieran-rails-reviewer dhh-rails-reviewer test-design-reviewer structural-enumeration semgrep-sast shellcheck anti-slop gdpr-gate'

# Byte-identical mirror of preflight Check 6 Step 6.1's SENSITIVE_PATH_RE (the
# canonical literal lives in plugins/soleur/skills/preflight/SKILL.md). The
# parity test pins this copy against the canonical one — edit together or not
# at all.
SENSITIVE_PATH_RE='^(apps/web-platform/(server|supabase|app/api|middleware\.ts$)|apps/web-platform/lib/(stripe|auth|byok|security-headers|csp|log-sanitize|safe-session|safe-return-to|supabase)|apps/web-platform/lib/(legal|auth)/|apps/[^/]+/infra/|.+/doppler[^/]*\.(yml|yaml|sh)$|\.github/workflows/.*(doppler|secret|token|deploy|release|version-bump|web-platform|infra-validation|cla|cf-token|linkedin-token).*\.ya?ml$)'

# Byte-identical mirror of the gdpr-gate canonical path regex (source of truth:
# plugins/soleur/skills/gdpr-gate/SKILL.md `## Path globs (canonical)`).
GDPR_PATH_RE='^(apps/web-platform/supabase/migrations/|apps/web-platform/lib/auth/|apps/web-platform/server/.*auth.*\.(ts|tsx|js)|apps/web-platform/app/api/.*\.(ts|tsx)$|.*\.sql$)'

SOURCE_RE='\.(ts|tsx|js|jsx|rb|py|go|rs|swift|kt|java|c|cpp|cs|php|sh|bash|zsh|mjs|cjs)$'
MIGRATION_RE='(/migrations/|/migrate/|\.sql$)'
PERSIST_RE='(apps/web-platform/(server|supabase|lib/))'
PERF_RE='(apps/web-platform/(server|supabase)/|inngest|cron|queue|worker|bench|perf)'
AGENT_SURFACE_RE='(apps/web-platform/(app|components)/|plugins/soleur/(agents|skills|commands|docs)/)'
TEST_RE='(\.test\.|\.spec\.|_test\.|_spec\.|(^|/)test_[^/]*\.py$|__tests__/|(^|/)tests?/|(^|/)spec/|Tests\.swift$)'
SHELL_RE='\.(sh|bash|zsh)$'
ANTISLOP_RE='(apps/web-platform/(app|components)/.*\.(tsx|jsx|css)$|apps/web-platform/server/.*\.(ts|tsx)$|plugins/soleur/docs/.*\.(njk|css)$)'

FILES_SEEN=""
FILES_GIVEN=0
FINDING_SEATS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --files)
      [[ $# -ge 2 ]] || { echo "fix-round-seats: --files needs a value" >&2; exit 2; }
      FILES_SEEN="$2"; FILES_GIVEN=1; shift 2 ;;
    --finding-seats)
      [[ $# -ge 2 ]] || { echo "fix-round-seats: --finding-seats needs a value" >&2; exit 2; }
      FINDING_SEATS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "fix-round-seats: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[[ "$FILES_GIVEN" -eq 1 ]] || { usage >&2; exit 2; }

if [[ -z "$FILES_SEEN" ]]; then
  echo "note: empty fix diff" >&2
fi

# Emit at most once per seat: membership test on the newline-list.
SEATS=""
add() { case "$SEATS" in *"$1"*) ;; *) SEATS="${SEATS}${1}
";; esac; }
has() { case "$SEATS" in *"$1"*) return 0 ;; *) return 1 ;; esac; }

floor_needed=0
# Split on newlines AND commas. The while loop is heredoc-fed (not piped) so it
# does NOT run in a subshell — SEATS/floor_needed survive it.
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  area=0
  if printf '%s\n' "$f" | grep -qE "$MIGRATION_RE"; then
    add data-integrity-guardian; add data-migration-expert; add deployment-verification-agent
    area=1
  fi
  if printf '%s\n' "$f" | grep -qE "$PERSIST_RE"; then add data-integrity-guardian; area=1; fi
  if printf '%s\n' "$f" | grep -qE "$SENSITIVE_PATH_RE"; then add security-sentinel; area=1; fi
  if printf '%s\n' "$f" | grep -qE "$GDPR_PATH_RE"; then add gdpr-gate; area=1; fi
  if printf '%s\n' "$f" | grep -qE "$ANTISLOP_RE"; then add anti-slop; area=1; fi
  if printf '%s\n' "$f" | grep -qE "$AGENT_SURFACE_RE"; then add agent-native-reviewer; area=1; fi
  if printf '%s\n' "$f" | grep -qE "$PERF_RE"; then add performance-oracle; area=1; fi
  if printf '%s\n' "$f" | grep -qE "$TEST_RE"; then add test-design-reviewer; area=1; fi
  if printf '%s\n' "$f" | grep -qE "$SHELL_RE"; then
    add shellcheck
  elif printf '%s\n' "$f" | grep -qE "$SOURCE_RE"; then
    add semgrep-sast
  fi
  if printf '%s\n' "$f" | grep -qE "$SOURCE_RE"; then
    # The floor guards "a source fix with no judgment seat". Deterministic SAST
    # (semgrep/shellcheck) and the test-design arm do count a file as covered —
    # they map the file's area; only a source file matching NO arm needs the
    # generalist floor.
    [[ "$area" -eq 1 ]] || floor_needed=1
  fi
done <<EOF_FILES
$(printf '%s\n' "$FILES_SEEN" | tr ',' '\n')
EOF_FILES

if [[ "$floor_needed" -eq 1 ]]; then
  add code-quality-analyst
fi

# --finding-seats: validated against the registry; unknown tokens dropped with
# a stderr warning and never echoed raw to stdout.
if [[ -n "$FINDING_SEATS" ]]; then
  for tok in $(printf '%s' "$FINDING_SEATS" | tr ',' ' '); do
    valid=0
    for s in $SEAT_REGISTRY; do
      [[ "$tok" == "$s" ]] && { valid=1; break; }
    done
    if [[ "$valid" -eq 1 ]]; then
      add "$tok"
    else
      printf 'unknown-seat: %s\n' "$tok" >&2
    fi
  done
fi

# Emit in canonical order (floor seats first), deduped.
for s in $SEAT_ORDER; do
  if has "$s"; then printf '%s\n' "$s"; fi
done
exit 0

