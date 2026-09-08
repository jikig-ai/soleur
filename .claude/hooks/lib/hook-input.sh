#!/usr/bin/env bash
# Parse the PreToolUse tool-call envelope without shell evaluation.
#
# ADR-156 — hook stdin is MODEL-CONTROLLED and untrusted; a hook must not depend
#           on an invariant of that input which it cannot itself verify.
# ADR-157 — a hook that cannot fully parse its input ASKS. It never continues
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
# unrecoverable loop: 19 hooks fire per Bash call and repairing PATH is itself a
# Bash call, so the operator would face 19 prompts per repair attempt.
# (19, not 18, since #7165 registered grep-rewrite.sh on the Bash matcher.)
# ADR-157; the contract test asserts every PreToolUse matcher carrying a
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
# The record separator. This is the BASH side; the jq program below writes the
# same byte four more times as the \u001e escape, so "one place" would be an
# over-claim - what is true is that there is one bash-side definition and the
# two encodings are pinned against each other by an assertion in the contract
# suite. A drift between them changes the field count silently.
#
# NOT `readonly`. That was tried and measured: this library has no include
# guard, so a second `source` of it then aborts with "readonly variable" - and
# under `set -euo pipefail`, which the hooks use, that KILLS the hook before any
# guard runs. The hardening that costs nothing is the READ spelling: every read
# below is `${_HOOK_INPUT_RS-}`, so an unset variable degrades to the already
# fail-closed `internal:count` arm instead of killing the shell. Same reasoning
# the `${IFS-}` note below already records, and the reason a bare `$IFS` is
# banned fifteen lines from here.
_HOOK_INPUT_RS=$'\x1e'

_HOOK_INPUT_JQ='
# d maps ONLY null (absent) to "". It must not use the // operator: in jq that
# is a FALSY-alternative, so a JSON false would be rewritten to "" before the
# type check below could see it - rc 0, empty value, no incident, no ask.
# Measured. Writing "// null" is not a shortcut either; it maps false to null
# and reopens the same hole. NB no apostrophes in this block: the program is a
# single-quoted bash string and one would terminate it.
def d(f): (try f catch {}) | if . == null then "" else . end;
# file_path with a notebook_path fallback, preserving the same null-only rule.
# has() on a non-object raises, which catch {} turns into an object - a
# non-string - so the shared check still handles it.
def fp: (try (if (.tool_input | has("file_path")) and (.tool_input.file_path != null)
              then .tool_input.file_path else .tool_input.notebook_path end)
         catch {}) | if . == null then "" else . end;
# THE ROOT MUST BE AN OBJECT. A JSON null root reached every accessor as null,
# d() mapped null to "", all five results were strings, so the program said "ok"
# and the caller was handed a fully-parsed envelope with EVERY FIELD EMPTY -
# rc 0, no incident row, no ask, and every anchored guard matching an empty
# command. A silent total disarm, and the one shape that produced it.
#
# A scalar or array root already failed (the accessors raise and catch {} yields
# a non-string), but it failed as "bad", reporting a non-string FIELD when the
# real fault is the document.
#
# SCOPE - ANSWERED, not deferred. A reviewer measured that an EMPTY OBJECT `{}`
# reaches the same five-empty-strings state through the arm below, and asked
# whether this check closes the disarm CLASS or only the `null` INSTANCE. It
# closes the instance. That is the right scope, and the reasoning is recorded
# here rather than in a backlog row because the question is settled, not parked:
#
#   1. ONE ENVELOPE SERIALIZES ONE TOOL CALL. `{}` means the model supplied no
#      command, so there is nothing for a guard to match. The "disarm" is guards
#      declining to fire on a call that carries nothing to fire on. For it to
#      have teeth the model would have to send `{}` to the hook while sending a
#      real command to the tool, and the envelope IS the tool call.
#   2. The reviewer explicitly declined to claim reachability: "I could not
#      settle that from this repo, so I am not claiming an exploit."
#   3. Coverage strictly INCREASED here. Before, `null` and `{}` both allowed
#      silently; now `null` is caught and `{}` is unchanged. No payload became
#      more dangerous. Two payloads getting different reason strings is an enum
#      aesthetic, not a widened hole.
#
# The obvious widening - require a non-empty tool_name - was checked against the
# tree and REJECTED on evidence, not on scope discipline: grep-rewrite.sh line
# 197 admits an EMPTY tool_name explicitly (its guard is "empty OR Bash"), i.e. a
# production hook deliberately treats an absent tool_name as acceptable, and two
# contract fixtures pass envelopes carrying no tool_name and expect rc 0. The
# harness invariant such a widening would rest on does not hold here.
# NB no apostrophes and no dollar signs in this block: it lives inside the jq
# program string, and A11 asserts both.
#
# A4 is the countervailing tested decision - "absence, null and empty are
# LEGITIMATE and must still pass" - and `{tool_input:{command:null}}`, a
# legitimate Read-shaped payload, is all-empty by the same measure.
if type != "object" then
  "nonobject", "\u001e", (range(5) | ("", "\u001e"))
else
  [ d(.tool_input.command), d(.tool_name), d(.cwd), d(.session_id), fp ]
  | (if all(type == "string") then "ok" else "bad" end), "\u001e",
    (.[] | (if type == "string" then . else "" end), "\u001e")
end
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
  # is not).
  #
  # NO TEMPFILE. An earlier draft captured jq's stderr to a `mktemp` file to
  # carry <=120 bytes of diagnostic text. That cost an allocate+unlink pair on
  # EVERY invocation — 19 hooks fire per Bash tool call — on the hot path, to
  # carry garnish. jq's EXIT CODE already makes the only distinction that
  # matters, and with exactly one constant program in this file there is no
  # second program the stderr text could disambiguate between.
  # THE RETURN CODE COMES BACK AS THE SUBSTITUTION'S OWN EXIT STATUS.
  #
  # It cannot be read afterwards. The original form was:
  #
  #     raw="$(printf ... | jq ...; printf 'X')"
  #     jq_rc=${PIPESTATUS[1]:-0}
  #
  # PIPESTATUS on that second line describes the ASSIGNMENT, not the pipeline
  # inside the substitution. Measured on bash 5.3.9 it is `(0)` with LENGTH 1,
  # so `PIPESTATUS[1]` was always unset, `:-0` always fired, jq_rc was
  # unconditionally 0, the `jq_rc == 3` arm was dead code, and empty stdin, a
  # rejected document and OUR OWN PROGRAM FAILING TO COMPILE were one reason
  # (#7275).
  #
  # An earlier revision of this fix carried the rc out INSIDE the output, as an
  # RS-delimited trailing field, and stripped it before the split. That worked -
  # the strip is sound, the two expansions pivot on the same byte by
  # construction - but it co-mingled a CONTROL value into a stream the payload
  # partly controls, and its safety then rested on a three-step argument
  # (anchoring + `%d` + a numeric tripwire). `exit "$_hi_rc"` needs no argument
  # at all: the value never enters the data stream, so no payload can reach it.
  #
  # `|| jq_rc=$?` rather than a bare assignment: as the right operand of `||`
  # the assignment is exempt from errexit BY THE SHELL GRAMMAR, so this holds
  # whether or not a caller has `shopt -s inherit_errexit`. Measured both ways.
  # Command substitution captures stdout regardless of exit status, so `raw` is
  # populated on every path.
  #
  # The `X` sentinel still earns its keep: command substitution strips trailing
  # newlines, and the sentinel shields the last field's. The jq program's own
  # trailing separator is the redundant half of that pair, as documented above.
  local raw jq_rc=0
  raw="$(printf '%s' "$input" | jq -j "$_HOOK_INPUT_JQ" 2>/dev/null
         _hi_rc=$?
         printf 'X'
         exit "$_hi_rc")" || jq_rc=$?
  raw=${raw%X}

  # WHOSE FAULT IS THE RETURN CODE? Measured on jq 1.8.1:
  #   0        - clean
  #   5        - the DOCUMENT is invalid (malformed, truncated, lone surrogate)
  #   3        - OUR program failed to compile
  #   2        - usage / system error, e.g. a write failure (ours)
  #   128+n    - jq killed by a signal: OOM-killer, SIGSEGV (the environment's)
  #
  # rc 5 IS THE ONLY CODE THAT MEANS "THE MODEL SENT JUNK". An earlier revision
  # of this fix enumerated OUR faults (rc 3) and let the residue default to
  # theirs, so rc 2, 126 and 137 were all reported as `baddoc` - reproducing
  # #7275's own collapse one code over, on the surface whose whole thesis is
  # that a broken gate must never hide behind a plausible payload class. On a
  # silent-disarm surface the fail-safe polarity is the opposite: name the one
  # code that means their document, and default everything else to ours.
  #
  # Interpolating $jq_rc into the reason is safe BECAUSE of the carrier above:
  # it is the substitution's exit status, never a value derived from payload
  # bytes. Under the retired strip-based carrier it would have been the latter,
  # and a crafted payload could have reached telemetry through it.
  local rc_fault=""
  if (( jq_rc == 5 )); then
    rc_fault="payload"
  elif (( jq_rc != 0 )); then
    rc_fault="ours"
  fi

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
  IFS=${_HOOK_INPUT_RS-}
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

  # OUR FAULT IS CHECKED FIRST. A jq that failed to compile, was killed, or hit
  # a system error also emits nothing, so it reaches the zero-field arm too. If
  # the count were tested first, a broken hook would be reported as the model
  # having sent junk - precisely the collapse that lets a broken gate hide.
  if [[ $rc_fault == "ours" ]]; then
    HOOK_INPUT_REASON="internal:rc${jq_rc}"
    return 1
  fi

  if (( n != 6 )); then
    if (( n > 6 )); then
      if (( n % 6 == 0 )) && [[ -z $rc_fault ]]; then
        # jq is a STREAM processor: two concatenated documents run the constant
        # program twice and emit 12 slots with rc 0. That is a multi-document
        # payload, not a forged boundary - and reporting it as `separator` sends
        # an operator hunting for RS injection in a field value that contains
        # none. An exact multiple of 6 with a clean rc is unforgeable from
        # inside a single document, because injecting a separator can only ADD
        # fields, never land on a multiple by construction.
        HOOK_INPUT_REASON="multidoc"
      else
        # A value carried the separator and raised the record count. The program
        # emits exactly 6 records unconditionally, so a boundary forge is
        # structurally detectable rather than a silent desync.
        HOOK_INPUT_REASON="separator"
      fi
    elif (( n == 0 )); then
      # The two payload classes the old code could not tell apart. `empty` is
      # nobody's fault - there was no document. `baddoc` is a document jq
      # rejected, which is the one that means the model sent junk.
      if [[ $rc_fault == "payload" ]]; then
        HOOK_INPUT_REASON="baddoc"
      else
        HOOK_INPUT_REASON="empty"
      fi
    else
      # 1..5 records from a constant program. This arm is the one the earlier
      # revision left classifying on COUNT ALONE while `jq_rc` sat in scope
      # three lines away - the same asymmetry as the defect being fixed, one
      # size smaller. A partial record with a clean rc is unambiguously ours; a
      # partial record with rc 5 is jq abandoning a bad document mid-stream.
      if [[ $rc_fault == "payload" ]]; then
        HOOK_INPUT_REASON="baddoc"
      else
        HOOK_INPUT_REASON="internal:count"
      fi
    fi
    return 1
  fi

  # A COMPLETE RECORD IS NOT A SUCCESSFUL PARSE. A valid envelope followed by
  # trailing garbage emits all six slots AND exits 5: jq produced the record,
  # then rejected the rest of the document. The old code tested only the count,
  # so this returned 0 and the hook ran its guards against a document jq had
  # already refused. An unclassified non-zero rc is a fault-suppression channel.
  if [[ $rc_fault == "payload" ]]; then
    HOOK_INPUT_REASON="baddoc"
    return 1
  fi

  if [[ ${_hi_s[0]} == "nonobject" ]]; then
    # The document parsed but its root is not an object, so no contracted field
    # could exist. Distinct from `nonstring`, which is an object whose FIELD is
    # of the wrong type - conflating them reports a field fault for a document
    # that never had fields.
    HOOK_INPUT_REASON="nonobject"
    return 1
  fi

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
      "PreToolUse hook input was not usable; guards did not run" \
      "hook=${HOOK_INPUT_HOOK} reason=${reason}" \
      "PreToolUse" "hook_self_fault"
  fi

  if declare -f headless_or_stderr >/dev/null 2>&1; then
    SOLEUR_HOOK_NAME="$HOOK_INPUT_HOOK" headless_or_stderr warn \
      "hook input not usable (${reason}) — guards did NOT run for this call"
  else
    echo "[${HOOK_INPUT_HOOK}] hook input not usable (${reason}) — guards did NOT run for this call" >&2
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
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"SAFETY: %s could not fully parse the tool-call envelope (reason: %s), so its guards did NOT run for this call. Hook stdin is model-controlled and is not trusted (ADR-156); a hook that cannot parse its input asks rather than continuing silently (ADR-157). Approve only if you are confident this command is safe. Set SOLEUR_DISABLE_HOOK_INPUT_ASK=1 to suppress this prompt."}}\n' \
    "$hook" "$reason"
}
