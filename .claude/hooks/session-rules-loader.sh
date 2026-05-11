#!/usr/bin/env bash
# session-rules-loader.sh — SessionStart hook for change-class-aware AGENTS.md loading.
#
# Issue: #3493
# Matchers: startup|resume|clear|compact
# Reads the envelope JSON on stdin, classifies the session's change set, and
# emits hookSpecificOutput.additionalContext containing the relevant
# AGENTS.<class>.md sidecar(s) plus an operator-readable stamp and the
# `LOADER_FAIL_CLOSED=1` escape command.
#
# Mid-session pivot safety (per CPO sign-off PR #3496): the substitute for the
# dropped PreToolUse pivot detector is the combination of:
#   1. `[compliance-tier]`-tagged rules live in AGENTS.core.md (always loaded).
#   2. `mixed` default for ambiguous / multi-class / empty diffs (fail-closed).
#   3. The stamp + hint line below — operator-side discipline is the floor.
#   4. The slim 3-field per-session manifest for SOC 2 CC6.1/CC7.2 evidence.
#
# Worktree path resolution (Kieran P0-1 fix): when invoked from a bare repo
# root, `git rev-parse --show-toplevel` returns empty. Prefer envelope `cwd`,
# fall back to `--git-common-dir`, last-resort `pwd`. Precedent:
# `.claude/hooks/worktree-write-guard.sh:25`.
set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
CWD=""
SESSION_ID=""
if command -v jq >/dev/null 2>&1 && [[ -n "$INPUT" ]]; then
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
fi

# Resolve repo root (worktree path) with three-tier fallback.
if [[ -n "$CWD" && -d "$CWD" ]]; then
  REPO_ROOT="$CWD"
else
  REPO_ROOT=""
  if command -v git >/dev/null 2>&1; then
    COMMON_DIR=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "")
    if [[ -n "$COMMON_DIR" ]]; then
      # `git-common-dir` for a worktree returns `<bare>/.git`; strip the
      # trailing `/.git` and we're at the bare root. For a worktree-aware
      # invocation we still need a working tree — pwd is the safer floor.
      REPO_ROOT="$(pwd)"
    fi
  fi
  REPO_ROOT="${REPO_ROOT:-$(pwd)}"
fi

# Compute change set (committed-on-branch ∪ working-tree) with submodule noise stripped.
CHANGES=$(
  {
    git -C "$REPO_ROOT" diff --name-only origin/main...HEAD --ignore-submodules=all 2>/dev/null || true
    git -C "$REPO_ROOT" status --porcelain --ignore-submodules=all 2>/dev/null | awk '{ print $2 }' || true
  } | sort -u
)

# Classifier — inline regex (no shared library; single source of truth lives
# alongside the script). Mirrored in tools/migration/classify-rules.sh's
# 5-PR spot-check pass; parity is asserted by Phase 6.5.
DOCS_RE='\.(md|markdown|txt|njk|html)$|^\.github/.*\.md$'
CODE_RE='\.(ts|tsx|js|jsx|py|go|rs|swift|kt|java|c|cpp|cs|php|sh|bash|zsh|rb)$'
INFRA_RE='\.tf$|^apps/[^/]+/infra/|\.github/workflows/|/?Dockerfile|/migrations/.*\.sql$'

HAS_DOCS=0; HAS_CODE=0; HAS_INFRA=0
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if [[ "$path" =~ $DOCS_RE  ]]; then HAS_DOCS=1;  fi
  if [[ "$path" =~ $CODE_RE  ]]; then HAS_CODE=1;  fi
  if [[ "$path" =~ $INFRA_RE ]]; then HAS_INFRA=1; fi
done <<< "$CHANGES"

# Class selection. Multi-class / empty / explicit override → load everything (fail-closed).
CLASSES="core"
if [[ "${LOADER_FAIL_CLOSED:-}" == "1" ]]; then
  CLASSES="core docs-only rest"
elif [[ -z "$CHANGES" ]]; then
  CLASSES="core docs-only rest"
elif (( HAS_CODE + HAS_INFRA + HAS_DOCS > 1 )); then
  CLASSES="core docs-only rest"
elif (( HAS_DOCS == 1 )); then
  CLASSES="core docs-only"
elif (( HAS_CODE == 1 || HAS_INFRA == 1 )); then
  CLASSES="core rest"
fi

# Concatenate sidecars in order. Missing-file → fail-closed: drop accumulated
# context, re-walk all sidecars, mark the class set so the operator sees the
# fall-back transition.
CONTEXT=""
FAIL_SAFE_TRIGGERED=0
for class in $CLASSES; do
  case "$class" in
    core)      sidecar="$REPO_ROOT/AGENTS.core.md" ;;
    docs-only) sidecar="$REPO_ROOT/AGENTS.docs.md" ;;
    rest)      sidecar="$REPO_ROOT/AGENTS.rest.md" ;;
    *)         continue ;;
  esac
  if [[ -f "$sidecar" ]]; then
    CONTEXT+=$'\n\n---\n\n'
    CONTEXT+="$(<"$sidecar")"
  else
    FAIL_SAFE_TRIGGERED=1
    break
  fi
done

if (( FAIL_SAFE_TRIGGERED == 1 )); then
  CONTEXT=""
  for sc in "$REPO_ROOT"/AGENTS.core.md "$REPO_ROOT"/AGENTS.docs.md "$REPO_ROOT"/AGENTS.rest.md; do
    if [[ -f "$sc" ]]; then
      CONTEXT+=$'\n\n---\n\n'
      CONTEXT+="$(<"$sc")"
    fi
  done
  CLASSES="core docs-only rest"
  FAIL_SAFE_NOTE=" — fail-safe: sidecar missing"
else
  FAIL_SAFE_NOTE=""
fi

# Stamp + hint — both ≤ 200 bytes per line (asserted in Phase 4.5 test).
RULE_COUNT=$(printf '%s' "$CONTEXT" | grep -cE '^- .*\[id: ' || true)
TOTAL_RULES=$(grep -hcE '^- .*\[id: ' "$REPO_ROOT"/AGENTS*.md 2>/dev/null | paste -sd+ - | bc 2>/dev/null || echo 0)
CLASSES_DISPLAY="${CLASSES// /+}"
STAMP="[rules-loader] loaded: ${CLASSES_DISPLAY} (${RULE_COUNT} of ${TOTAL_RULES} rules)${FAIL_SAFE_NOTE}"
HINT="[rules-loader] scope shift? LOADER_FAIL_CLOSED=1 bash .claude/hooks/session-rules-loader.sh < <(echo '{}')"

# Slim manifest (3 fields). Key by session_id; fallback to timestamp.
MANIFEST_DIR="$REPO_ROOT/.claude/.session-manifests"
mkdir -p "$MANIFEST_DIR"
TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
KEY="${SESSION_ID:-$TS}"
MANIFEST="$MANIFEST_DIR/${KEY}.json"
RULE_IDS_JSON=$(printf '%s' "$CONTEXT" \
  | grep -oE '\[id: [a-z0-9-]+\]' \
  | sed 's/^\[id: //;s/\]$//' \
  | sort -u \
  | jq -Rsc 'split("\n") | map(select(length > 0))')

jq -nc \
  --arg ts "$TS" \
  --arg cls "$CLASSES" \
  --argjson ids "$RULE_IDS_JSON" \
  '{timestamp: $ts, change_class: $cls, rule_ids_loaded: $ids}' \
  > "$MANIFEST"

# Final output envelope.
OUT_BODY="${STAMP}"$'\n'"${HINT}"$'\n'"[rules-loader] manifest: ${MANIFEST}"$'\n'"${CONTEXT}"
jq -nc --arg out "$OUT_BODY" '{ hookSpecificOutput: { additionalContext: $out } }'
exit 0
