#!/usr/bin/env bash
# PreToolUse(Bash) hook: defers prod-write commands for explicit operator approval.
#
# Three inline starter regexes (telemetry-driven expansion via follow-up PRs):
#   prod-write-defer-git-push-main           — git push origin {main,master,HEAD:main,HEAD:master}
#   prod-write-defer-terraform-apply         — terraform / tofu apply
#   prod-write-defer-doppler-secrets-stdout  — doppler secrets {set|delete} ... --config {prd|prd_terraform|prd_orchestration|dev|ci}
#                                              (widened from the original `set`-only / `prd[_terraform]`-only shape
#                                              after issue #4029 — `delete` renders the post-deletion surviving-secrets
#                                              table to stdout, leaking value chunks from sibling secrets;
#                                              `prd_orchestration` added at PR #4031 review since tenant-* runbooks
#                                              operate against it and the same trap class applies to
#                                              cross-tenant value chunks rendered post-deletion).
#
# Mode (controlled by SOLEUR_DEFER_DRYRUN, default 1):
#   1 (dry-run, default) — emit kind=would_defer, allow (output "{}").
#   0 (enforce)          — emit kind=defer_requested, append approvals.jsonl,
#                          return wrapped defer envelope (hookEventName=PreToolUse,
#                          permissionDecision=defer). DEFER_VALUE empirically
#                          verified in DEFER-DECISION-PAYLOAD-SHAPE.md (CC 2.1.142).
#
# Bypass (CLAUDE_HOOK_BYPASS=1):
#   TTY + reason + operator set        → emit kind=bypass, allow.
#   non-TTY without env reason+operator → emit kind=hook_self_fault, DENY (fail closed).
#
# Fail-CLOSED on regex compile / jq parse / manifest unreadable.
# F1 by contrast (would have) failed OPEN — F1 collapsed to roadmap per Phase 0.1.

set -uo pipefail
# -e omitted intentionally: any failure path must return JSON, never crash silently.

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

SOLEUR_DEFER_DRYRUN="${SOLEUR_DEFER_DRYRUN:-1}"
# Empirically verified: "defer" gives silent pause, suitable for claude --resume.
# See .claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md.
DEFER_VALUE="defer"

# --- Inline TARGETS array: rule_id|prose_ref|regex (bash ERE) -----------
# Regex engine: bash [[ =~ ]] (ERE). POSIX [[:space:]], NOT \s.
# Anchor `(^|&&|\|\||;|[[:space:]]--[[:space:]])` catches wrapped invocations
# (e.g., `bash session-state.sh with_lock ... -- git push origin main`) and
# chained `&&` / `;` / `||` forms. Without this anchor, the regex misses the
# class of bug surfaced in learning 2026-05-12-cross-session-lock-lease-bash-primitives.md.
#
# Expansion gate: NEW entries only after 2-week dry-run telemetry from operator
# (see .claude/hooks/README.md). CI/scheduled-runs do not accumulate hits.
# Trailing class `([[:space:]]|;|\)|&|$)` mirrors the leading anchor — without
# `;`/`)`/`&` a `git push origin main;` or `(git push origin main)` slips past
# the gate even though the leading anchor already treats those operators as
# significant.
declare -a DEFAULT_TARGETS=(
  "prod-write-defer-git-push-main|hr-menu-option-ack-not-prod-write-auth|(^|&&|\\|\\||;|\\(|[[:space:]]--[[:space:]])[[:space:]]*git[[:space:]]+push([[:space:]]+(-f|--force(-with-lease)?))?[[:space:]]+origin[[:space:]]+(main|master|HEAD:main|HEAD:master)([[:space:]]|;|\\)|&|$)"
  "prod-write-defer-terraform-apply|hr-all-infrastructure-provisioning-servers|(^|&&|\\|\\||;|\\(|[[:space:]]--[[:space:]])[[:space:]]*(terraform|tofu)[[:space:]]+apply([[:space:]]|;|\\)|&|$)"
  "prod-write-defer-doppler-secrets-stdout|hr-menu-option-ack-not-prod-write-auth|(^|&&|\\|\\||;|\\(|[[:space:]]--[[:space:]])[[:space:]]*([A-Za-z_]+=[A-Za-z0-9_]+[[:space:]]+)*doppler[[:space:]]+secrets[[:space:]]+(set|delete)([[:space:]]+[^[:space:]]+)*[[:space:]]+(--config|-c)[[:space:]]+(prd|prd_terraform|prd_orchestration|dev|ci)([[:space:]]|;|\\)|&|$)"
)

# Post-match read-only escape: a few command classes are matched by the
# above regexes because the verb (`apply`) is the same, but a `-help` /
# `-version` / `-h` / `-v` flag is read-only. Operators run these to
# inspect, not to mutate prod — gating them on this surface would
# realize the plan §User-Brand Impact bullet-1 "paralyzing-ship" vector.
# Per-rule allowlist: rule_id → bash glob fragments that mark the
# command as read-only when present anywhere after the verb.
declare -A READONLY_FLAG_PATTERNS=(
  ["prod-write-defer-terraform-apply"]='(^|[[:space:]])-(-?)(help|version|h|v)([[:space:]]|=|$)'
  # `doppler secrets {set,delete} --help` is read-only; the verbs share `-h`/`--help`
  # but neither has `--version`. Pattern omits `version`/`v` to avoid escaping
  # a non-existent flag (consistent with the per-verb flag-set narrative in
  # plan §Research Insights "Read-only escape pattern").
  ["prod-write-defer-doppler-secrets-stdout"]='(^|[[:space:]])-(-?)(help|h)([[:space:]]|=|$)'
)

# Allow tests to inject broken regex for fail-closed verification.
# Production callers MUST NOT set this. The override accepts the same
# pipe-delimited shape.
if [[ -n "${SOLEUR_DEFER_TARGETS_OVERRIDE:-}" ]]; then
  TARGETS=("$SOLEUR_DEFER_TARGETS_OVERRIDE")
else
  TARGETS=("${DEFAULT_TARGETS[@]}")
fi

# --- Self-fault deny helper ---------------------------------------------
# Emit hook_self_fault and return a DENY envelope. Used when the hook
# itself cannot make a trustworthy decision (broken regex, missing env,
# etc.). Always exits 0 (the deny is conveyed through JSON, not exit code).
deny_self_fault() {
  local reason="$1" cmd_snippet="$2"
  emit_incident "prod-write-defer-hook-self-fault" "deny" \
    "F2 defer-gate self-fault — failing closed" \
    "$cmd_snippet" "PreToolUse" "hook_self_fault"
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED (prod-write-defer-gate self-fault): " + $reason)
    }
  }'
  exit 0
}

# --- Operator-email resolver (inline, 4-line) ---------------------------
# Per learning 2026-04-24-fake-git-author-bare-repo-bot-override: prefer
# --global git config because bare-repo+worktree topology silently reads
# repo-level git config which is operator-controlled at lower trust.
resolve_operator_email() {
  if [[ -n "${SOLEUR_OPERATOR_EMAIL:-}" ]]; then echo "$SOLEUR_OPERATOR_EMAIL"
  elif [[ -n "${GITHUB_ACTOR:-}" ]]; then echo "${GITHUB_ACTOR}@users.noreply.github.com"
  else
    local email
    email=$(git config --global --get user.email 2>/dev/null || true)
    if [[ -n "$email" ]]; then echo "$email"; else echo "unknown@local"; fi
  fi
}

# --- Approval log writer (flock-protected, 1y TTL via rotate_if_needed) -
append_approval_log() {
  local rule_id="$1" resolved_command="$2" operator_email="$3" approval_method="$4" session_id="$5"
  local repo_root file ts args_hash
  repo_root="$(_incidents_repo_root)" || return 0
  file="$repo_root/.claude/logs/approvals.jsonl"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  args_hash="$(printf '%s' "$resolved_command" | sha256sum | cut -d' ' -f1)"

  mkdir -p "$(dirname "$file")" 2>/dev/null || return 0
  [[ -f "$file" ]] || : > "$file" 2>/dev/null || return 0

  # 1-year TTL via rotate_if_needed's 3rd positional `age_threshold_days`
  # (see log-rotation.sh:82). Earlier draft used LOG_ROTATION_AGE_SECONDS
  # which the rotator does not honor — it would have silently downgraded
  # to the 30-day default.
  if declare -F rotate_if_needed >/dev/null 2>&1; then
    rotate_if_needed "$file" "" 365 2>/dev/null || true
  fi

  local line
  line=$(jq -nc \
    --arg ts "$ts" \
    --arg t "Bash" \
    --arg h "$args_hash" \
    --arg c "${resolved_command:0:1024}" \
    --arg o "$operator_email" \
    --arg m "$approval_method" \
    --arg r "$rule_id" \
    --arg s "$session_id" \
    '{timestamp:$ts, tool:$t, args_hash:$h, resolved_command:$c, operator_email:$o, approval_method:$m, rule_id:$r, session_id:$s}' \
    2>/dev/null) || return 0

  ( flock -x 9; printf '%s\n' "$line" >&9 ) 9>>"$file" 2>/dev/null || true
}

# --- Read + parse hook stdin (single jq @sh-escape, sibling-hook pattern) -
INPUT=$(cat)
eval "$(echo "$INPUT" | jq -r '@sh "CMD=\(.tool_input.command // "") SESSION_ID=\(.session_id // "")"' 2>/dev/null || echo 'CMD="" SESSION_ID=""')"
: "${CMD:=}"
: "${SESSION_ID:=}"

# Empty command → no-op (sibling-hook convention).
if [[ -z "$CMD" ]]; then
  echo '{}'
  exit 0
fi

# Cap command snippet for telemetry (matches lib/incidents.sh 1024-byte cap).
CMD_SNIPPET="${CMD:0:1024}"

# --- Iterate TARGETS; first match wins ----------------------------------
MATCHED_RULE=""
MATCHED_RULE_PROSE=""

for entry in "${TARGETS[@]}"; do
  # IFS=| split into three fields. Validate shape; broken entries → fail-closed.
  IFS='|' read -r rule_id prose_ref regex_pat <<< "$entry"
  if [[ -z "$rule_id" || -z "$regex_pat" ]]; then
    deny_self_fault "malformed TARGETS entry (missing fields)" "$CMD_SNIPPET"
  fi
  # bash [[ =~ ]] returns 0 (match), 1 (no match), 2 (invalid regex).
  # Capture rc directly — chaining via && loses the 2-signal.
  [[ "$CMD" =~ $regex_pat ]]
  rc=$?
  if [[ "$rc" -ge 2 ]]; then
    deny_self_fault "regex compile failure for $rule_id" "$CMD_SNIPPET"
  fi
  if [[ "$rc" -eq 0 ]]; then
    # Post-match read-only escape (terraform apply -help / -version etc.).
    readonly_pat="${READONLY_FLAG_PATTERNS[$rule_id]:-}"
    if [[ -n "$readonly_pat" ]] && [[ "$CMD" =~ $readonly_pat ]]; then
      continue
    fi
    MATCHED_RULE="$rule_id"
    MATCHED_RULE_PROSE="$prose_ref"
    break
  fi
done

# No match → no-op, allow (output "{}").
if [[ -z "$MATCHED_RULE" ]]; then
  echo '{}'
  exit 0
fi

# --- Bypass handling -----------------------------------------------------
# Bypass policy (no silent overrides):
#   1. CLAUDE_HOOK_BYPASS_REASON is REQUIRED (env-set). The interactive TTY-
#      prompt path was rejected — a non-empty reason must be authorial.
#   2. Operator identity is resolved (env → git --global → "unknown@local").
#   3. Missing reason → fail-closed with kind=hook_self_fault.
if [[ "${CLAUDE_HOOK_BYPASS:-}" == "1" ]]; then
  BYPASS_REASON="${CLAUDE_HOOK_BYPASS_REASON:-}"
  BYPASS_OPERATOR="${CLAUDE_HOOK_BYPASS_OPERATOR:-}"
  if [[ -z "$BYPASS_REASON" ]]; then
    deny_self_fault "bypass requires CLAUDE_HOOK_BYPASS_REASON env var (no interactive prompt path)" "$CMD_SNIPPET"
  fi
  if [[ -z "$BYPASS_OPERATOR" ]]; then
    BYPASS_OPERATOR="$(resolve_operator_email)"
  fi
  emit_incident "$MATCHED_RULE" "bypass" \
    "F2 defer-gate bypass: $MATCHED_RULE_PROSE" \
    "$CMD_SNIPPET" "PreToolUse" "bypass"
  # Strip C0 control bytes + DEL + U+2028/U+2029 from operator-facing stderr
  # (CWE-117 log/terminal injection — operator's terminal hygiene).
  CMD_DISPLAY=$(printf '%s' "$CMD_SNIPPET" | LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed -e $'s/\xe2\x80\xa8//g' -e $'s/\xe2\x80\xa9//g')
  echo "[prod-write-defer-gate] BYPASS by $BYPASS_OPERATOR — $BYPASS_REASON :: $CMD_DISPLAY" >&2
  echo '{}'
  exit 0
fi

# --- Mode branch: dry-run vs enforce ------------------------------------
case "$SOLEUR_DEFER_DRYRUN" in
  1)
    # Dry-run: emit telemetry, allow.
    emit_incident "$MATCHED_RULE" "applied" \
      "F2 defer-gate dry-run would defer: $MATCHED_RULE_PROSE" \
      "$CMD_SNIPPET" "PreToolUse" "would_defer"
    echo '{}'
    exit 0
    ;;
  0)
    # Enforce: emit telemetry, append approval log, return wrapped defer envelope.
    OPERATOR_EMAIL="$(resolve_operator_email)"
    emit_incident "$MATCHED_RULE" "deny" \
      "F2 defer-gate defer requested: $MATCHED_RULE_PROSE" \
      "$CMD_SNIPPET" "PreToolUse" "defer_requested"
    append_approval_log "$MATCHED_RULE" "$CMD" "$OPERATOR_EMAIL" "tty_resume" "$SESSION_ID"
    # Resume hint on stderr — CC renders defer silently, operator needs the
    # session_id+command somewhere visible. See DEFER-DECISION-PAYLOAD-SHAPE.md.
    # Strip C0 control bytes + DEL + U+2028/U+2029 from operator-facing stderr.
    CMD_DISPLAY=$(printf '%s' "$CMD_SNIPPET" | LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed -e $'s/\xe2\x80\xa8//g' -e $'s/\xe2\x80\xa9//g')
    SESSION_ID_SAFE=$(printf '%s' "$SESSION_ID" | LC_ALL=C tr -d '\000-\037\177')
    echo "[prod-write-defer-gate] DEFERRED $MATCHED_RULE: $CMD_DISPLAY" >&2
    if [[ -n "$SESSION_ID_SAFE" ]]; then
      echo "[prod-write-defer-gate] resume via: claude --resume $SESSION_ID_SAFE" >&2
    fi
    jq -n \
      --arg rule "$MATCHED_RULE" \
      --arg cmd "$CMD_SNIPPET" \
      --arg decision "$DEFER_VALUE" \
      '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: $decision,
          permissionDecisionReason: ($rule + ": prod-write deferred for explicit operator approval. Command: " + $cmd)
        }
      }'
    exit 0
    ;;
  *)
    deny_self_fault "invalid SOLEUR_DEFER_DRYRUN value '$SOLEUR_DEFER_DRYRUN' (expected 0 or 1)" "$CMD_SNIPPET"
    ;;
esac
