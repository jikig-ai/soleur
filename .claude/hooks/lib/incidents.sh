#!/usr/bin/env bash
# Rule-incident telemetry helpers for PreToolUse hooks.
#
# Emits one JSON line per deny or bypass to a single flock-guarded file at
# <repo-root>/.claude/.rule-incidents.jsonl. Called BEFORE the hook's
# `jq -n '{hookSpecificOutput: ...}' && exit 0` response so the hook contract
# with Claude Code is unchanged (see ADR-2 in
# knowledge-base/project/plans/2026-04-14-feat-rule-utility-scoring-plan.md).
#
# Source from a hook via:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"
#
# Fire-and-forget: never blocks the hook (all jq invocations on external input
# wrapped in `2>/dev/null || true`, per learning 2026-03-18).

# --- Repo-root resolution --------------------------------------------------
# BASH_SOURCE[0] is the path to THIS file regardless of how it was sourced.
# From .claude/hooks/lib/incidents.sh, the repo root is three dirs up.
# Tests set INCIDENTS_REPO_ROOT to redirect writes off the operator's real
# .claude/.rule-incidents.jsonl; the aggregator uses the same env var.
#
# `cd -P` + `pwd -P` canonicalizes through symlinks (physical path). The
# Python emitter in security_reminder_hook.py uses os.path.realpath — both
# sides must land on the same inode for `flock -x` to interlock. A
# symlinked `.claude/` in the operator's project would otherwise produce
# two disjoint locks on two different inodes and reintroduce the torn
# writes this module exists to prevent.
_incidents_repo_root() {
  if [[ -n "${INCIDENTS_REPO_ROOT:-}" ]]; then
    echo "$INCIDENTS_REPO_ROOT"
    return
  fi
  (cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd -P)
}

# Locate the shared rule-metrics constants (SCHEMA_VERSION). Sourced with
# graceful fallback so an isolated hook still emits a complete line if the
# constants file is missing from a test fixture.
# shellcheck source=/dev/null
_incidents_constants="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)/scripts/lib/rule-metrics-constants.sh"
if [[ -f "$_incidents_constants" ]]; then
  # shellcheck source=/dev/null
  source "$_incidents_constants"
fi
: "${SCHEMA_VERSION:=1}"
unset _incidents_constants

# Source the shared log rotator. Idempotent (function definitions only); the
# fail-soft guard mirrors the constants source above. `2>/dev/null || true`
# matches the leaf-hook callers so a malformed helper never leaks stderr to
# Claude Code's hook stdout/stderr capture.
# shellcheck source=/dev/null
_incidents_rotator="$(dirname "${BASH_SOURCE[0]}")/log-rotation.sh"
if [[ -f "$_incidents_rotator" ]]; then
  # shellcheck source=/dev/null
  source "$_incidents_rotator" 2>/dev/null || true
fi
unset _incidents_rotator

# --- Telemetry-drop sentinels ---------------------------------------------
# In-band sentinel-line schema for cross-sink drop accounting (issue #3509).
#
# Schema:
#   {"schema":1,"hook_event":"<PreToolUse|PostToolUse>","error":"<class>","ts":"<iso8601>"}
#
# Three covered classes:
#   jq_fail        — a jq invocation failed mid-emit (malformed input, OOM,
#                    transient binary failure). Caller MUST emit before its
#                    own `exit 0` / `return 0` so a single drop is countable.
#   flock_timeout  — `flock -w <s>` returned non-zero on the data sink. Only
#                    `agent-token-tee.sh` has a timeout site; the other two
#                    hooks use indefinite `flock -x` and never emit this
#                    class. Counts under sustained contention are a STRICT
#                    LOWER BOUND — the same lock that blocked the data write
#                    can drop the sentinel write too (see no-recursion below).
#   rotation_fail  — `rotate_if_needed` returned non-zero (archive write
#                    failed mid-copy; active file preserved). Caller wraps
#                    the call in an explicit guard:
#                      if ! rotate_if_needed "$file"; then
#                        _emit_drop_sentinel "$file" "$EVENT" rotation_fail
#                      fi
#
# Out-of-scope (issue #3523, deferred):
#   fs_error  — mkdir/touch failure or write-fail post-flock acquisition.
#               Undetectable in-band: the sentinel write to the same disk
#               fails for the same reason as the data write. Tracked as a
#               separate out-of-band monitor.
#
# Discriminator: `error` key presence. Data lines do not carry `error`;
# sentinel lines do. This is intentionally field-additive on schema v1 so
# old aggregators that pre-date this feature stay fail-soft.
#
# No-recursion contract: the helper has exactly one failure mode (silently
# drop the sentinel). Three guarantees keep it from emitting a sentinel
# about itself:
#   1. Pre-formatted JSON string (no jq invocation here) elides jq_fail.
#   2. Non-blocking `flock -n` elides flock-contention recursion — under
#      sustained contention sentinels themselves drop, by design.
#   3. All I/O is wrapped in `2>/dev/null || true` so disk failures vanish
#      silently.
#
# Aggregator filter contract:
#   - scripts/rule-metrics-aggregate.sh   — tightens valid_stream filter
#                                           to `select(.rule_id != null)`
#                                           BEFORE the reduce; sentinels
#                                           never enter `valid_lines`.
#   - scripts/skill-freshness-aggregate.sh — existing `.skill != null`
#                                            filter already excludes
#                                            sentinels from data.
#   - plugins/soleur/skills/compound/scripts/token-efficiency-report.sh
#                                          — existing `.session_id == $s`
#                                            filter already excludes
#                                            sentinels from envelope-sum.
# Each aggregator additionally adds a separate jq pass that counts
# sentinels by `.error` and exposes `summary.drops_<class>_count`.
#
# Compound Phase 3.5 contract:
#   The Deviation Analyst prose reads `.rule-incidents.jsonl` and filters to
#   `event_type ∈ {deny, bypass}`. Sentinels carry no `event_type` so the
#   prose-implicit filter excludes them; the explicit "ignore lines with
#   `error` set" instruction in compound's SKILL.md makes this contractual.
#
# Caller responsibility: pass a canonicalized absolute path (`cd -P + pwd -P`
# resolved by the caller). The helper does NOT re-resolve. Different inode =
# different lock = race.
_emit_drop_sentinel() {
  local active="${1:-}" hook_event="${2:-}" class="${3:-}"
  [[ -z "$active" || -z "$hook_event" || -z "$class" ]] && return 0
  # Belt-and-suspenders input shape gate: even though every in-tree caller
  # passes a hard-coded literal, a typo or future caller drift could embed
  # a `"` / `\` / newline and silently corrupt every downstream JSONL row.
  # Allow-listing the safe character set bounds the blast radius to "drop
  # the sentinel" rather than "poison the stream".
  [[ "$hook_event" =~ ^[A-Za-z_]+$ ]] || return 0
  [[ "$class" =~ ^[a-z_]+$ ]] || return 0
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || ts="1970-01-01T00:00:00Z"
  # Pre-formatted JSON. Class is from a known-safe enum (caller responsibility,
  # also enforced by the regex above).
  # No jq. Single-line. Lands well under 4 KiB even with large hook_event values.
  local sentinel="{\"schema\":1,\"hook_event\":\"${hook_event}\",\"error\":\"${class}\",\"ts\":\"${ts}\"}"
  # Best-effort append. Non-blocking flock; on contention or fs error, drop
  # silently (see no-recursion contract above).
  ( flock -n 9 || exit 0; printf '%s\n' "$sentinel" >&9 ) 9>>"$active" 2>/dev/null || true
  return 0
}

# --- emit_incident <rule_id> <event_type> <prefix> [command_snippet] -------
# See `_emit_drop_sentinel` above for the sentinel-line discriminator and
# aggregator-filter contract. emit_incident itself emits a sentinel via the
# helper on `jq_fail` (line-build failure) and `rotation_fail` (rotator
# returned non-zero); the existing per-`$$` rate-limited stderr warn for
# write failures is preserved for operator visibility.
# event_type ∈ {deny, bypass, applied, warn}
#   deny    — PreToolUse hook blocked an operation (prevents a violation).
#   bypass  — user bypassed the rule with a known escape hatch (LEFTHOOK=0, etc.).
#   applied — a skill/agent explicitly invoked the rule's enforcement path
#             (e.g., ship Phase 5.5 reached its conditional gates).
#   warn    — advisory hook surfaced a concern without blocking (docs-cli-verify).
#
# Synthetic rule_id namespace convention:
#   Callers MAY use a `<prefix>-*` rule_id when the rule_id describes a
#   measurement (not an AGENTS.md rule) AND the aggregator's orphan-gate
#   has been extended to exempt that prefix. Currently reserved:
#     `te-*` — token-efficiency telemetry (issue #3494, compound Phase 1.6).
#   See scripts/rule-metrics-aggregate.sh's orphan-detection block for the
#   exclusion pattern. Adding a new synthetic prefix requires a parallel
#   exclusion line + tests in scripts/rule-metrics-aggregate.test.sh.
# Aggregator counting semantics (scripts/rule-metrics-aggregate.sh):
#   hit_count    = deny
#   bypass_count = bypass
#   applied_count = applied
#   warn_count    = warn
#   fire_count    = deny + bypass + applied + warn (any recognized event)
#   prevented_errors = max(hit_count - bypass_count, 0) — unchanged by new types.
# Python emitter sibling: .claude/hooks/security_reminder_hook.py defines its
# own emit_incident() mirroring this contract; keep SCHEMA_VERSION in sync.
# prefix: first ~50 chars of the rule text (redundant — aggregator uses
#         rule_id as the primary join key — but keeps forensic context if
#         AGENTS.md is ever rebased with new ids).
emit_incident() {
  local rule_id="${1:-}" event="${2:-}" prefix="${3:-}" cmd="${4:-}" hook_event="${5:-PreToolUse}"
  [[ -z "$rule_id" || -z "$event" ]] && return 0

  # Cap cmd length so a single JSONL line stays well under a 4KB kernel
  # write boundary even under O_APPEND. Long PR bodies or multi-line
  # heredoc commands can push a raw command_snippet past 10KB.
  cmd="${cmd:0:1024}"

  local repo_root file ts
  repo_root="$(_incidents_repo_root)" || return 0
  file="$repo_root/.claude/.rule-incidents.jsonl"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Create parent dir (first run) and file (needed by flock on the file itself).
  mkdir -p "$(dirname "$file")" 2>/dev/null || return 0
  [[ -f "$file" ]] || : > "$file" 2>/dev/null || return 0

  # Rotate before writing. The helper holds its own flock briefly; ordering
  # (rotate → release → write) avoids nested-flock semantics. On
  # archive-write failure (return 1) emit a rotation_fail sentinel and
  # proceed — telemetry never blocks the calling hook.
  if declare -F rotate_if_needed >/dev/null 2>&1; then
    if ! rotate_if_needed "$file" 2>/dev/null; then
      _emit_drop_sentinel "$file" "$hook_event" "rotation_fail"
    fi
  fi

  # flock on the file itself; jq -nc emits single-line JSON. On line-build
  # failure emit a jq_fail sentinel before returning silently.
  local line
  line=$(jq -nc \
    --arg ts "$ts" \
    --arg r "$rule_id" \
    --arg e "$event" \
    --arg p "$prefix" \
    --arg c "$cmd" \
    --argjson s "$SCHEMA_VERSION" \
    '{schema:$s, timestamp:$ts, rule_id:$r, event_type:$e, rule_text_prefix:$p, command_snippet:$c}' \
    2>/dev/null) || {
      _emit_drop_sentinel "$file" "$hook_event" "jq_fail"
      return 0
    }

  local write_ok=1
  (
    flock -x 9
    printf '%s\n' "$line" >&9
  ) 9>>"$file" 2>/dev/null || write_ok=0

  if [[ "$write_ok" == "0" ]]; then
    # One stderr line per hook process. $$ scopes the marker to this shell —
    # we want one warn per hook fork, not once globally.
    local marker="/tmp/rule-incidents-warned-$$"
    if [[ ! -f "$marker" ]]; then
      echo "[rule-incidents] warning: failed to write $file (permissions? disk?)" >&2
      : > "$marker" 2>/dev/null || true
    fi
  fi
}

# --- detect_bypass <tool> <command> ---------------------------------------
# Echoes the rule_id of the bypassed rule when the command uses a v1 bypass
# flag. Empty output means no bypass detected.
#
# v1 scope is deliberately minimal to avoid false positives (see
# plan ADR-2 and R3):
#   --no-verify   → cq-never-skip-hooks
#   LEFTHOOK=0    → cq-lefthook-worktree-hang
# Deferred to v2: --force on main, --no-gpg-sign, --amend after a prior deny.
#
# Patterns anchor on bash-adjacent context ("git ", "git\t", LEFTHOOK=0 at
# command start or after a chain operator) to skip substrings embedded in
# echoed strings, heredoc bodies, PR body text, etc.
detect_bypass() {
  local cmd="${2:-}"
  # --no-verify: only recognize when it's a flag to a git invocation in the
  # command. Matches "git ... --no-verify" and "git -C foo commit --no-verify"
  # but not 'echo "avoid --no-verify"' or 'gh pr create --body "don\'t --no-verify"'.
  if [[ "$cmd" =~ (^|[[:space:]]|\&\&|\|\||\;)[[:space:]]*git[[:space:]].*--no-verify ]]; then
    echo "cq-never-skip-hooks"
    return
  fi
  # LEFTHOOK=0: recognize only when it's an environment prefix at the start
  # of the command (standard env-assign-before-command position) or after a
  # chain operator. Not `echo "LEFTHOOK=0 is bad"`.
  if [[ "$cmd" =~ (^|\&\&|\|\||\;)[[:space:]]*LEFTHOOK=0[[:space:]] ]]; then
    echo "cq-when-lefthook-hangs-in-a-worktree-60s"
    return
  fi
}

# --- resolve_command_cwd <command> <hook_input_json> ----------------------
# Echoes the most likely CWD for a Bash tool_input.command, falling through
# (a) `cd <dir> && ...` prefix, (b) `git -C <dir>` flag, (c) hook's `.cwd`
# field. Empty output means no CWD could be resolved.
#
# Consumers: guardrails:block-commit-on-main, guardrails:block-conflict-markers.
# The stash-block guard intentionally does NOT call this — AGENTS.md forbids
# git stash unconditionally, so CWD detection is not needed there.
resolve_command_cwd() {
  local cmd="${1:-}" input="${2:-}" dir=""
  if echo "$cmd" | grep -qE '^\s*cd\s+'; then
    dir=$(echo "$cmd" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif echo "$cmd" | grep -qoE 'git\s+-C\s+\S+'; then
    dir=$(echo "$cmd" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [[ -z "$dir" || ! -d "$dir" ]]; then
    dir=$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null || echo "")
  fi
  echo "$dir"
}
