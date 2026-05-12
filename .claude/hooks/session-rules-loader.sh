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
set -uo pipefail
# NOTE: `set -e` is deliberately OFF. A non-zero exit from this hook produces
# no `additionalContext` envelope — Claude Code would then boot with the bare
# 4.3 kB pointer index and ZERO rule bodies, including the 5 compliance-tier
# rules. That is the `single-user incident` failure mode user-impact-reviewer
# flagged on PR #3496. Errors are handled inline (`|| true` on tolerant paths,
# explicit fallback emission at the end on hard failures).
trap 'emit_core_only_fallback "hook trap fired before emit"; exit 0' ERR

# HEADLESS_MODE classifier — boolean, downstream hooks read this to decide
# whether to route warnings through headless_or_stderr or stderr. Boolean
# only; the 3-value enum (peek vs bg) was rejected by simplicity review
# because no consumer currently needs to distinguish. Re-introduce if a
# concrete need emerges.
if [[ ! -t 0 ]] && [[ -n "${CLAUDECODE:-}" ]]; then
  export HEADLESS_MODE=1
else
  export HEADLESS_MODE=0
fi

# emit_core_only_fallback: invoked from ERR trap or any failure branch that
# cannot continue safely. Reads AGENTS.core.md from `${REPO_ROOT:-$PWD}` and
# emits a minimal additionalContext so the agent never boots bodyless.
emit_core_only_fallback() {
  local reason="${1:-unknown}"
  local root="${REPO_ROOT:-$PWD}"
  local fb=""
  if [[ -r "$root/AGENTS.core.md" ]]; then
    fb="$(<"$root/AGENTS.core.md")"
  fi
  printf '%s' "{\"hookSpecificOutput\":{\"additionalContext\":$(jq -Rs . <<<"[rules-loader] FALLBACK ($reason): loaded AGENTS.core.md only"$'\n'"$fb")}}"
}

INPUT=$(cat 2>/dev/null || true)
CWD=""
SESSION_ID=""
if command -v jq >/dev/null 2>&1 && [[ -n "$INPUT" ]]; then
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
fi

# Resolve repo root with three-tier fallback. Critical: must point at a real
# git worktree, otherwise the operator (or a malicious envelope) could redirect
# manifest writes to arbitrary writable locations. See review on PR #3496.
REPO_ROOT=""
if [[ -n "$CWD" && -d "$CWD" ]]; then
  REPO_ROOT="$CWD"
elif command -v git >/dev/null 2>&1; then
  # `git-common-dir` resolves to `<bare>/.git` or `<bare>/.git/worktrees/<name>`.
  # `--show-toplevel` is the working-tree we want; only use common-dir as a
  # last-resort floor.
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
fi
REPO_ROOT="${REPO_ROOT:-$(pwd)}"

# Refuse to operate outside a git worktree. Otherwise a crafted envelope
# `{"cwd":"/tmp/x"}` lets the hook plant `.claude/.session-manifests/` and
# overwrite arbitrary `*.json` paths via `session_id`. Fallback to AGENTS.core.md
# from REPO_ROOT so the agent still receives the compliance-tier rules.
if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  emit_core_only_fallback "cwd $REPO_ROOT not inside a git worktree"
  exit 0
fi

# Sanitize SESSION_ID for use as a filename. Anything outside [A-Za-z0-9._-]
# becomes `_`; `..` segments are folded. Prevents `{"session_id":"../../foo"}`
# from writing manifests outside .claude/.session-manifests/.
SESSION_ID="${SESSION_ID//[^A-Za-z0-9._-]/_}"

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
  if [[ -L "$sidecar" ]]; then
    # Symlinks are a prompt-injection vector (an attacker who controls a
    # symlink in the repo could redirect AGENTS.<class>.md to /etc/passwd or
    # a crafted payload). Reject and fall through to fail-safe.
    FAIL_SAFE_TRIGGERED=1
    break
  fi
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
    if [[ -L "$sc" ]]; then continue; fi
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

# Stamp + hint — both ≤ 200 bytes per line (asserted in test 11).
RULE_COUNT=$(printf '%s' "$CONTEXT" | grep -cE '^- .*\[id: ' || true)
# Single-pipeline awk avoids the multi-line `paste -sd+ | bc` failure mode
# where `grep -hc` emits one count per file (e.g., `"0\n5\n0\n4"`) and `bc`
# either crashes or returns a multi-line value that violates the stamp-byte
# contract.
TOTAL_RULES=$(grep -hE '^- .*\[id: ' "$REPO_ROOT"/AGENTS*.md 2>/dev/null | wc -l | tr -d ' ')
CLASSES_DISPLAY="${CLASSES// /+}"
STAMP="[rules-loader] loaded: ${CLASSES_DISPLAY} (${RULE_COUNT} of ${TOTAL_RULES} rules)${FAIL_SAFE_NOTE}"
# The hint embeds the *current* REPO_ROOT so the agent can re-run the loader
# against the same worktree without relying on `$PWD` (which depends on the
# Bash tool's resetting CWD between calls). Bare `echo '{}'` would have empty
# cwd → re-classification against the wrong tree.
HINT="[rules-loader] scope shift? LOADER_FAIL_CLOSED=1 bash .claude/hooks/session-rules-loader.sh < <(printf '{\"cwd\":\"%s\"}' \"$REPO_ROOT\")"

# Slim manifest (3 fields). Key by sanitized session_id; fallback to timestamp.
# SESSION_ID has already been stripped of any non-alphanum (see top of file);
# if it ends up empty after sanitization (e.g., the envelope sent `../`), the
# `:-$TS` fallback ensures we still write into MANIFEST_DIR, never outside.
MANIFEST_DIR="$REPO_ROOT/.claude/.session-manifests"
mkdir -p "$MANIFEST_DIR" 2>/dev/null || {
  emit_core_only_fallback "cannot create $MANIFEST_DIR (read-only fs?)"
  exit 0
}
TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
KEY="${SESSION_ID:-$TS}"
[[ -z "$KEY" || "$KEY" == "." || "$KEY" == ".." ]] && KEY="$TS"
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
