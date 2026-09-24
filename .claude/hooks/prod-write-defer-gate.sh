#!/usr/bin/env bash
# PreToolUse(Bash, Monitor) hook: defers prod-write commands for explicit operator approval.
# Registered for Monitor too (#8486): a Monitor script is a shell command
# (tool_input.command), so a write run as a monitor must not bypass the gate.
#
# Four inline rules (the first three telemetry-driven; the fourth, #8486, is
# exempt from the dry-run expansion gate — see its block below):
#   prod-write-defer-git-push-main           — git push origin {main,master,HEAD:main,HEAD:master}
#   prod-write-defer-terraform-apply         — terraform / tofu apply
#   prod-write-defer-doppler-secrets-stdout  — doppler secrets {set|delete} ... --config {prd|prd_terraform|prd_orchestration|dev|ci}
#                                              (widened from the original `set`-only / `prd[_terraform]`-only shape
#                                              after issue #4029 — `delete` renders the post-deletion surviving-secrets
#                                              table to stdout, leaking value chunks from sibling secrets;
#                                              `prd_orchestration` added at PR #4031 review since tenant-* runbooks
#                                              operate against it and the same trap class applies to
#                                              cross-tenant value chunks rendered post-deletion).
#   prod-write-defer-operator-ack-script     — a write-mode invocation of any operator script that
#                                              gates its production writes on the operator-script
#                                              library's TTY ack (#8486, ADR-249): flag-create,
#                                              flag-delete, user-set-role, flag-set-role,
#                                              provision-hetzner, audit-sentry … --apply. Every
#                                              call in the command is evaluated (not only the
#                                              leftmost), a read-only escape is scoped to that
#                                              call's own argument tail, and the rule fails CLOSED
#                                              on its own error (EXIT trap -> deny envelope).
#
# Mode (controlled by SOLEUR_DEFER_DRYRUN, default 0):
#   1 (dry-run)          — emit kind=would_defer, allow (output "{}").
#   0 (enforce, default) — emit kind=defer_requested, append approvals.jsonl,
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

SOLEUR_DEFER_DRYRUN="${SOLEUR_DEFER_DRYRUN:-0}"
# Empirically verified: "defer" gives silent pause, suitable for claude --resume.
# See .claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md.
DEFER_VALUE="defer"

# --- Inline TARGETS array: rule_id|prose_ref|regex (bash ERE) -----------
# Regex engine: bash [[ =~ ]] (ERE). POSIX [[:space:]], NOT \s.
# Anchor `(^|&&|\|\||;|[[:space:]]--[[:space:]])` catches wrapped invocations
# (e.g., `bash <plugin-root>/scripts/lib/session-state.sh with_lock ... -- git push origin main`) and
# chained `&&` / `;` / `||` forms. Without this anchor, the regex misses the
# class of bug surfaced in learning 2026-05-12-cross-session-lock-lease-bash-primitives.md.
#
# Expansion gate: NEW entries only after 2-week dry-run telemetry from operator
# (see .claude/hooks/README.md). CI/scheduled-runs do not accumulate hits.
# Trailing class `([[:space:]]|;|\)|&|$)` mirrors the leading anchor — without
# `;`/`)`/`&` a `git push origin main;` or `(git push origin main)` slips past
# the gate even though the leading anchor already treats those operators as
# significant.
# --- Rule 4: operator scripts behind the TTY ack (#8486, ADR-249) -----------
# WHY THIS RULE SKIPS THE 2-WEEK DRY-RUN EXPANSION GATE: after #8486 there is no
# legitimate agent invocation of these scripts in write mode — the script itself
# refuses a write with no TTY (exit 64 before any credential fetch). So a false-
# positive defer costs nothing a correct run would have produced. The case this
# backstop exists for is an agent that allocates a PTY (`script -qc`,
# `unbuffer`, `expect`, `python3 -c 'import pty…'`) and types `yes` into it.
#
# Unique basenames match anywhere as a path token (preceded by `/`, whitespace, a
# quote or a command boundary, so `inngest-cutover-flip.sh` does not match: `-`
# precedes `flip.sh`). The generic basenames create.sh/delete.sh match only
# dir-qualified, or bare after a `cd` into their skill directory.
OPACK_RULE="prod-write-defer-operator-ack-script"
OPACK_UNIQUE='flip\.sh|set-role\.sh|provision-hetzner\.sh|audit-sentry-extra-text-references\.sh'
OPACK_QUALIFIED='flag-create/scripts/create\.sh|flag-delete/scripts/delete\.sh'
OPACK_CALL_RE="(^|[^A-Za-z0-9_.-])(${OPACK_QUALIFIED}|${OPACK_UNIQUE})([^A-Za-z0-9_.-].*)?\$"
OPACK_CD_CONTEXT_RE='(^|[;&|(]|[[:space:]])cd[[:space:]]+[^;&|]*flag-(create|delete)(/scripts)?/?["'"'"']?[[:space:]]*(;|&&|\|\||$)'
# A PTY wrapper or a `yes |` pipe anywhere cancels every read-only escape: a dry
# run never needs a TTY, and the PTY route is the one this rule exists for.
OPACK_PTY_RE='(^|[^A-Za-z0-9_.-])(script|unbuffer|expect)([[:space:]]|$)|pty\.(spawn|fork|openpty)|(^|[^A-Za-z0-9_.-])yes([[:space:]][^|;&]*)?\|'
# Output piped into an interpreter (or process substitution / eval) cancels the
# reader escape: `cat …/flip.sh | bash` runs the script.
OPACK_TO_SHELL_RE='\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh|dash|ksh|script|expect|source)([[:space:]]|$)|<\(|(^|[^A-Za-z0-9_])eval([[:space:]]|$)'
OPACK_READERS='^(cat|less|more|head|tail|grep|egrep|rg|git|wc|ls|stat|file|diff|shellcheck|test|\[|\[\[)$'
# A call's argument tail ends at the next separator, quote, comment, backtick or
# newline; `$(` is cut separately below.
OPACK_TAIL_RE=$'^([^;&|)"\'#`\n]*)'
OPACK_SEG_BOUNDARY=$';&|(\n`'

# opack_prefilter <cmd> — a fixed-string test so the common command pays nothing.
opack_prefilter() {
  [[ "$1" == *flip.sh* || "$1" == *set-role.sh* || "$1" == *provision-hetzner.sh* \
     || "$1" == *audit-sentry-extra-text-references.sh* || "$1" == *create.sh* || "$1" == *delete.sh* ]]
}

# opack_verdict <cmd> -> rc 0 = at least one call is a write (defer);
#                        rc 1 = every call is a reader or a read-only mode (allow);
#                        any other rc = the rule could not decide (caller denies).
opack_verdict() {
  local cmd="$1" re="$OPACK_CALL_RE" rem consumed="" prefix seg first second tail name
  local pty=0 to_shell=0 any_write=0 calls=0 rc
  case "${SOLEUR_DEFER_TEST_INJECT_FAULT:-}" in
    return) return 3 ;;
    exit) exit 1 ;;
  esac
  [[ "" =~ $re ]]; rc=$?
  (( rc >= 2 )) && return 3
  if [[ "$cmd" =~ $OPACK_CD_CONTEXT_RE ]]; then
    re="(^|[^A-Za-z0-9_.-])(${OPACK_QUALIFIED}|${OPACK_UNIQUE}|create\.sh|delete\.sh)([^A-Za-z0-9_.-].*)?\$"
  fi
  [[ "$cmd" =~ $OPACK_PTY_RE ]] && pty=1
  [[ "$cmd" =~ $OPACK_TO_SHELL_RE ]] && to_shell=1
  rem="$cmd"
  while [[ "$rem" =~ $re ]]; do
    local -a m=("${BASH_REMATCH[@]}")
    calls=$((calls + 1))
    (( calls > 256 )) && return 3
    prefix="${rem:0:$(( ${#rem} - ${#m[0]} ))}"
    name="${m[2]##*/}"
    # --- the segment this call sits in, for the reader escape ---------------
    seg="${consumed}${prefix}${m[1]}"
    seg="${seg##*[$OPACK_SEG_BOUNDARY]}"
    read -r first second _ <<<"$seg" || true
    while [[ "$first" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
      seg="${seg#*"$first"}"; read -r first second _ <<<"$seg" || true
    done
    # --- the call's own argument tail -----------------------------------------
    tail="${m[3]:-}"
    [[ "$tail" == [\"\']* ]] && tail="${tail:1}"
    [[ "$tail" =~ $OPACK_TAIL_RE ]] && tail="${BASH_REMATCH[1]}"
    tail="${tail%%\$(*}"
    consumed="${consumed}${prefix}${m[1]}${m[2]}"
    rem="${m[3]:-}"
    if (( ! to_shell )) && [[ "$first" =~ $OPACK_READERS ]]; then
      continue
    fi
    if (( ! to_shell )) && [[ ( "$first" == sed || "$first" == bash || "$first" == sh ) && "$second" == -n ]]; then
      continue
    fi
    if (( ! pty )); then
      case "$name" in
        flip.sh|set-role.sh|create.sh|delete.sh)
          [[ " $tail " =~ [[:space:]]--dry-run[[:space:]] ]] && continue ;;
        audit-sentry-extra-text-references.sh)
          [[ " $tail " =~ [[:space:]]--apply[[:space:]] ]] || continue ;;
      esac
    fi
    any_write=1
  done
  (( any_write )) && return 0
  return 1
}

# Once the prefilter hits, a crash anywhere below must not become an allow:
# Claude Code RUNS the command when a hook exits non-zero or prints nothing.
OPACK_DECIDED=0
opack_exit_guard() {
  if [[ "${OPACK_DECIDED:-0}" != 1 ]]; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED (prod-write-defer-gate self-fault): the operator-ack rule could not decide; failing closed (#8486)"}}'
  fi
  exit 0
}

declare -a DEFAULT_TARGETS=(
  "prod-write-defer-git-push-main|hr-menu-option-ack-not-prod-write-auth|(^|&&|\\|\\||;|\\(|[[:space:]]--[[:space:]])[[:space:]]*git[[:space:]]+push([[:space:]]+(-f|--force(-with-lease)?))?[[:space:]]+origin[[:space:]]+(main|master|HEAD:main|HEAD:master)([[:space:]]|;|\\)|&|$)"
  "prod-write-defer-terraform-apply|hr-all-infrastructure-provisioning-servers|(^|&&|\\|\\||;|\\(|[[:space:]]--[[:space:]])[[:space:]]*(terraform|tofu)[[:space:]]+apply([[:space:]]|;|\\)|&|$)"
  "${OPACK_RULE}|hr-menu-option-ack-not-prod-write-auth|${OPACK_CALL_RE}"
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
  OPACK_DECIDED=1
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

# --- Operator-email resolver (inline) -----------------------------------
# Per learning 2026-04-24-fake-git-author-bare-repo-bot-override: on a BARE
# repo + worktree topology, prefer `--global` git config because repo-level
# config is operator-controllable at lower trust.
#
# CAVEAT — authority inversion on the non-bare Concierge surface (ADR-099
# §Known latent surfaces, #6191): there `--global` is the baked
# `github-actions[bot]` identity while `--local` is the host-seeded owner, so
# on Concierge this `--global` fallback can record the BOT as the operator in
# the approval audit log. Accepted (not resolved): the path feeds an audit log
# — NOT a git operation — and is reached ONLY when BOTH SOLEUR_OPERATOR_EMAIL
# and GITHUB_ACTOR are unset. An active fix (a bot-shape discriminator applied
# to both scopes) would trade a known-wrong value for a possibly-mis-downgraded
# human/service account; see ADR-099 §latent + decision-challenges.md D1.
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
    --arg t "${HOOK_TOOL_NAME:-Bash}" \
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

# --- Read + parse hook stdin (single jq fork, no eval — sibling-hook pattern) -
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
  echo "[prod-write-defer-gate] hook-input helper missing — guards did NOT run for this call" >&2
  exit 0
fi

INPUT=$(cat)
# Parse hook stdin WITHOUT shell evaluation (ADR-156: stdin is
# model-controlled and untrusted). A non-string field is surfaced, never
# coerced — coercion closes the RCE and leaves the guards evaded (#7164).
# ADR-157: a hook that cannot fully parse its input asks. The exit lives
# HERE, at the call site, not inside the library.
if ! hook_parse_input "$INPUT"; then
  hook_input_report "prod-write-defer-gate"
  hook_input_should_ask && { hook_input_emit_ask "prod-write-defer-gate"; exit 0; }
  exit 0
fi
CMD="$HOOK_CMD"
SESSION_ID="$HOOK_SESSION_ID"
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
  if [[ "$rule_id" == "$OPACK_RULE" ]]; then
    opack_prefilter "$CMD" || continue
    trap opack_exit_guard EXIT
    rc=0
    opack_verdict "$CMD" || rc=$?
    case "$rc" in
      0) MATCHED_RULE="$rule_id"; MATCHED_RULE_PROSE="$prose_ref"; break ;;
      1) continue ;;
      *) deny_self_fault "operator-ack rule could not decide (rc=$rc)" "$CMD_SNIPPET" ;;
    esac
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
  OPACK_DECIDED=1
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
  OPACK_DECIDED=1
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
    OPACK_DECIDED=1
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
    else
      # No session_id in the hook payload — still give the operator a recovery
      # path rather than a silent pause (plan §User-Brand Impact bullet-1).
      echo "[prod-write-defer-gate] resume via: claude --resume (no session_id in payload; pick the paused session)" >&2
    fi
    OPACK_DECIDED=1
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
