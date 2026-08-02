#!/usr/bin/env bash
# Parse the PreToolUse tool-call envelope without shell evaluation.
#
# ADR-155 — hook stdin is MODEL-CONTROLLED and untrusted; a hook must not depend
#           on an invariant of that input which it cannot itself verify.
# ADR-156 — a hook that cannot fully parse its input ASKS. It never continues
#           silently and it never denies.
#
# Replaces, in 20 hooks:
#
#   eval "$(echo "$INPUT" | jq -r '@sh "COMMAND=\(.tool_input.command // "")"' ...)"
#
# which had two defects (issue #7164). First, `jq @sh` shell-quotes each element
# of an ARRAY as a separate word, so ["x","touch","/tmp/PWNED"] renders as
# COMMAND='x' 'touch' '/tmp/PWNED' — an assignment followed by a COMMAND, run by
# eval before the permission prompt with operator privileges. Second, the
# `|| echo 'COMMAND=""'` fallback emptied every field on a parse failure, so
# every guard in the file no-opped with exit 0 and no record.
#
# Usage (the caller owns the exit; see .claude/hooks/README.md):
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"
#   if ! hook_parse_input "$INPUT"; then
#     hook_input_report "<hook-basename>"
#     hook_input_should_ask && { hook_input_emit_ask "<hook-basename>"; exit 0; }
#     exit 0
#   fi
#
# Source it FAIL-HARD — no `|| true`, no `|| :`, no `2>/dev/null`. A fail-soft
# source leaves hook_parse_input undefined; under `set -euo pipefail` the hook
# then dies at the call, prints nothing, exits non-zero, and the tool proceeds.
# That is defect 2 reintroduced one line above where every test points.
#
# Compatible with bash 3.2 and jq 1.5: no mapfile, no declare -n, no
# --raw-output0 (jq >= 1.7), no read -d.

# --- Published globals ------------------------------------------------------
# Initialised at source time so `set -u` callers can reference them before the
# first parse. Every one is reset at the top of every hook_parse_input call —
# a value inherited from the environment must not survive into a decision.
# shellcheck disable=SC2034  # consumed by the 20 calling hooks, not in this file
HOOK_CMD=""
# shellcheck disable=SC2034
HOOK_TOOL_NAME=""
# shellcheck disable=SC2034
HOOK_CWD=""
# shellcheck disable=SC2034
HOOK_SESSION_ID=""
# shellcheck disable=SC2034
HOOK_FILE_PATH=""
HOOK_INPUT_REASON=""
HOOK_INPUT_HOOK=""

# The hook designated to emit the `ask` envelope. The other hooks report and
# exit 0. All-emit would turn a persistent fault (jq missing) into an
# unrecoverable loop: 18 hooks fire per Bash call and repairing PATH is itself a
# Bash call, so the operator would face 18 prompts per repair attempt.
# ADR-156; the contract test asserts every PreToolUse matcher carrying a
# migrated hook also carries this one.
HOOK_INPUT_RESPONDER="guardrails"

# --- The program ------------------------------------------------------------
# ONE CONSTANT jq program with FIXED accessors. Not a variadic
# <VAR> <jq-expr> API: that form would need program interpolation, an
# odd-argument-count path, caller-supplied variable names and `printf -v`, each
# of which is a failure mode this shape simply does not have. There is no `$`
# anywhere in the program text.
#
# Field order is the CONTRACT. Do not reorder.
#   slot 1 .tool_input.command
#   slot 2 .tool_name
#   slot 3 .cwd
#   slot 4 .session_id
#   slot 5 .tool_input.file_path // .tool_input.notebook_path
#
# Three properties are structural rather than defensive:
#
#   * The status token is computed BEFORE any value is emitted, so no value can
#     forge it. One token, not a per-field tag: it halves the slot count and
#     removes any need to render or scrub a bad value.
#   * `catch {}` yields an OBJECT — a non-string — so a non-object `tool_input`
#     or a non-object root is handled by the same `all(type == "string")` check
#     with no separate error tag and no `has("__e")` branch. Catching to `""`
#     instead would make an unreadable field indistinguishable from a clean
#     empty one: rc 0, guards no-op, no incident. That was a real bug in an
#     earlier draft.
#   * Values on the BAD path are emitted EMPTY. Nothing is coerced, nothing is
#     rendered, nothing needs a separator scrub, and no payload content can
#     reach telemetry or disk. Coercion (`tojson`) was measured and rejected:
#     it closes the RCE and leaves every anchored guard evaded, because
#     ["git","stash"] matches no guard regex.
#
# Separator is RS (U+001E), emitted as a jq escape. NOT NUL: jq drops NUL from
# input string values and cannot emit it from a literal (measured), so a
# NUL-delimited design silently truncates.
_HOOK_INPUT_JQ='
[ (try (.tool_input.command // "") catch {}),
  (try (.tool_name        // "") catch {}),
  (try (.cwd              // "") catch {}),
  (try (.session_id       // "") catch {}),
  (try (.tool_input.file_path // .tool_input.notebook_path // "") catch {}) ]
| (if all(type == "string") then "ok" else "bad" end), "\u001e",
  (.[] | (if type == "string" then . else "" end), "\u001e")
'

# --- hook_parse_input <json> ------------------------------------------------
# rc 0 — parsed, and every contracted field is a string. Values are byte-exact.
# rc 1 — anything else. HOOK_INPUT_REASON classifies; the caller asks.
#
# THE RETURN CODE IS NORMATIVE. The reason is diagnostic only.
hook_parse_input() {
  local input="${1-}"
  HOOK_INPUT_REASON=""
  HOOK_CMD=""; HOOK_TOOL_NAME=""; HOOK_CWD=""; HOOK_SESSION_ID=""; HOOK_FILE_PATH=""

  if ! command -v jq >/dev/null 2>&1; then
    HOOK_INPUT_REASON="jq_missing"
    return 1
  fi

  # The trailing `printf 'X'` sentinel and the program's trailing separator are
  # REDUNDANT WITH EACH OTHER and load-bearing as a PAIR. Command substitution
  # strips trailing newlines; the trailing separator currently shields the last
  # value, and the sentinel shields it if the separator is ever dropped.
  # Removing either alone is invisible. Removing both silently truncates
  # trailing newlines from the last field on the HAPPY path. (Measured.)
  # ONE jq invocation, on one line — the contract test asserts exactly one `jq`
  # in this file (a mechanism ban is deterministic where a wall-clock comparison
  # is not). The stderr sink is chosen into a variable rather than duplicating
  # the call site, so `mktemp` being unavailable degrades the DIAGNOSTIC only,
  # never the parse.
  local raw jq_err jq_errsink=/dev/null jq_rc=0
  jq_err="$(mktemp -t hookinput.XXXXXXXX 2>/dev/null)" || jq_err=""
  [[ -n "$jq_err" ]] && jq_errsink="$jq_err"
  raw="$(printf '%s' "$input" | jq -j "$_HOOK_INPUT_JQ" 2>"$jq_errsink"; printf 'X')"
  jq_rc=${PIPESTATUS[1]:-0}
  raw=${raw%X}

  # Split on RS. The window between `set -f` and its restore is exactly these
  # few lines and contains no `return`, so no rc path can leak the modified
  # shell state.
  #   * `${IFS-}` NOT `$IFS`: with IFS unset under `set -u` the latter KILLS the
  #     shell — printing nothing, exiting non-zero, and letting the tool proceed
  #     — in the one line whose entire job is safety. (Measured.)
  #   * `set -f` before the split, restored CONDITIONALLY: an unconditional
  #     `set +f` would ENABLE globbing for a caller that had it off. Only a
  #     value that is ENTIRELY a glob can expand here, which is why the contract
  #     test uses a command of exactly `*` and not `rm *`.
  # `_hi_hadifs` is a SEPARATE flag and not a test on `_hi_oldifs`: `local
  # _hi_oldifs=${IFS-}` always SETS the variable (to the empty string when IFS
  # was unset), so `${_hi_oldifs+set}` is unconditionally true and the
  # `unset IFS` branch would be unreachable — restoring IFS to "" for a caller
  # that had it unset, which is a different shell state, not the original one.
  local _hi_hadifs=0 _hi_hadf=0
  [[ -n "${IFS+set}" ]] && _hi_hadifs=1
  local _hi_oldifs=${IFS-}
  case "$-" in *f*) _hi_hadf=1 ;; esac
  set -f
  IFS=$'\x1e'
  # shellcheck disable=SC2206  # deliberate IFS word-split on RS; globbing is off
  local -a _hi_s=($raw)
  if (( _hi_hadifs )); then IFS=$_hi_oldifs; else unset IFS; fi
  (( _hi_hadf )) || set +f

  # THE SLOT COUNT IS THE PARSE-FAILURE DETECTOR, NOT jq's EXIT CODE. Empty
  # stdin gives jq rc 0 with zero output, so `if ! jq ...; then` would ship a
  # hook that treats empty input as a successful parse. jq's rc is captured
  # anyway, purely to tell "we shipped a broken hook" apart from "the model sent
  # junk" — collapsing those two is how a broken gate hides as a bad payload.
  local n=${#_hi_s[@]}
  if (( n != 6 )); then
    if (( n > 6 )); then
      # A value carried the separator and raised the record count. The program
      # emits exactly 6 records unconditionally, so a boundary forge is
      # structurally detectable rather than a silent desync.
      HOOK_INPUT_REASON="separator"
    elif (( n == 0 )); then
      # This is where jq's exit code earns its keep. Measured on jq 1.8.1:
      #   rc 3 — OUR program failed to COMPILE. A hook shipped with a bad
      #          expression is our bug and must never be reported as the model
      #          having sent junk; that collapse is how a broken gate hides.
      #   rc 5 — the DOCUMENT is invalid (malformed, truncated, lone surrogate).
      #   rc 0 with no output — empty stdin.
      if (( jq_rc == 3 )); then
        HOOK_INPUT_REASON="internal"
      else
        HOOK_INPUT_REASON="unparseable"
      fi
    else
      # 1..5 records from a constant program means OUR program is broken, or jq
      # died mid-stream. Never blamed on the payload.
      HOOK_INPUT_REASON="internal"
    fi
    if [[ "$HOOK_INPUT_REASON" == "internal" && -n "$jq_err" ]]; then
      # <=120 bytes of OUR OWN diagnostic. jq's stderr on a compile error names
      # our program, never attacker content.
      local _hi_detail
      _hi_detail="$(tr -d '\n' < "$jq_err" 2>/dev/null)"
      HOOK_INPUT_REASON="internal:${_hi_detail:0:120}"
    fi
    [[ -n "$jq_err" ]] && rm -f "$jq_err" 2>/dev/null
    return 1
  fi
  [[ -n "$jq_err" ]] && rm -f "$jq_err" 2>/dev/null

  if [[ ${_hi_s[0]} != "ok" ]]; then
    # A contracted field is not a string. This is the attack signature, and it
    # is SURFACED, never coerced.
    HOOK_INPUT_REASON="nonstring"
    return 1
  fi

  HOOK_CMD="${_hi_s[1]}"
  HOOK_TOOL_NAME="${_hi_s[2]}"
  HOOK_CWD="${_hi_s[3]}"
  HOOK_SESSION_ID="${_hi_s[4]}"
  HOOK_FILE_PATH="${_hi_s[5]}"
  return 0
}

# --- hook_input_report <hook-basename> --------------------------------------
# Record the fault. PURE with respect to control flow: it always returns, and it
# never calls exit. A sourced library that exits terminates its caller
# invisibly, is untestable without a subshell, and silently no-ops inside `$( )`
# or a pipeline — so the exit lives at the call site in all 20 hooks, where it
# is explicit, greppable and uniform.
#
# Telemetry carries the hook name and the reason classifier. NEVER a field
# value: the jq program emits bad-path values empty by construction, so there is
# no rendering of attacker content in existence to log.
hook_input_report() {
  HOOK_INPUT_HOOK="${1:-unknown}"
  local reason="${HOOK_INPUT_REASON:-unknown}"
  # Only the enum head reaches the rule_id; an `internal:<jq stderr>` detail
  # stays out of the aggregation key.
  local reason_key="${reason%%:*}"

  # Sourced IDEMPOTENTLY and on the FAILURE PATH ONLY, so the happy path pays
  # nothing. A lower-layer helper must not call upward into a function it does
  # not source: `command not found` under `set -euo pipefail` kills the hook and
  # the tool proceeds — which is the exact silent disarm this file exists to end.
  if ! declare -f emit_incident >/dev/null 2>&1; then
    # shellcheck source=incidents.sh
    source "$(dirname "${BASH_SOURCE[0]}")/incidents.sh" 2>/dev/null || true
  fi

  if declare -f emit_incident >/dev/null 2>&1; then
    emit_incident "hook-input-${reason_key}" "warn" \
      "PreToolUse hook input could not be parsed; guards did not run" \
      "hook=${HOOK_INPUT_HOOK} reason=${reason}" \
      "PreToolUse" "hook_self_fault"
  fi

  if declare -f headless_or_stderr >/dev/null 2>&1; then
    SOLEUR_HOOK_NAME="$HOOK_INPUT_HOOK" headless_or_stderr warn \
      "hook input unparseable (${reason}) — guards did NOT run for this call"
  else
    echo "[${HOOK_INPUT_HOOK}] hook input unparseable (${reason}) — guards did NOT run for this call" >&2
  fi
  return 0
}

# --- hook_input_should_ask --------------------------------------------------
# True only for the designated responder, and only when escalation is enabled.
# The kill switch suppresses ESCALATION ONLY — parsing, the type assertion and
# the telemetry all still run. Without an in-band escape hatch there is no
# recovery if the posture proves noisy. Precedent: SOLEUR_DISABLE_SESSION_STATE.
hook_input_should_ask() {
  [[ "${SOLEUR_DISABLE_HOOK_INPUT_ASK:-}" == "1" ]] && return 1
  [[ "${HOOK_INPUT_HOOK:-}" == "$HOOK_INPUT_RESPONDER" ]]
}

# --- hook_input_emit_ask <hook-basename> ------------------------------------
# The envelope is a printf of a CONSTANT template — never `jq -n`. One of the
# trigger conditions is "jq is missing", and emit_incident itself builds its row
# with `jq -nc`, so on that path telemetry is unrecordable and this reason string
# is the ONLY surviving channel.
#
# `hookEventName` MUST ride in the SAME object as `permissionDecision`. Without
# it Claude Code silently ignores the envelope and the tool runs — a test
# asserting only `permissionDecision == "ask"` would pass while production is
# wide open (DEFER-DECISION-PAYLOAD-SHAPE.md).
#
# Both interpolations are our own values: a literal basename from the call site
# and a reason from a fixed enum. No field value is ever interpolated.
hook_input_emit_ask() {
  local hook="${1:-unknown}"
  local reason="${HOOK_INPUT_REASON:-unknown}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"SAFETY: %s could not fully parse the tool-call envelope (reason: %s), so its guards did NOT run for this call. Hook stdin is model-controlled and is not trusted (ADR-155); a hook that cannot parse its input asks rather than continuing silently (ADR-156). Approve only if you are confident this command is safe. Set SOLEUR_DISABLE_HOOK_INPUT_ASK=1 to suppress this prompt."}}\n' \
    "$hook" "$reason"
}
