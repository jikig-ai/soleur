#!/usr/bin/env bash
# Tests for rule-incident-marker-capture.sh (ADR-179 decision 9, #7450).
#
# The hook consumes a marker emitted by payload markdown. On the review path that
# markdown is CONTRIBUTOR-WRITABLE, so the validation is not hygiene — it is the
# property that bounds the worst case to a rejected telemetry row. Most of the cases
# below are therefore REJECTION cases, each fixtured so it would land a row if the
# corresponding check were deleted.
set -uo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HOOK_DIR}/../.." && pwd)"
HOOK="${HOOK_DIR}/rule-incident-marker-capture.sh"

PASS=0
FAIL=0
# The INDEPENDENT case counter (ADR-193 #2). It moves in assert() — the ASSERTION helper —
# and NEVER in pass()/fail(), the VERDICT helpers. A counter incremented inside the verdict
# helpers moves WITH the verdict, so stubbing fail() would drop the row and its count together
# and the conservation identity at the tail would hold under the exact fault it exists to
# catch. Never increment this inside `$( )`; a subshell discards it.
CASES=0

# VERDICT helpers — they own PASS/FAIL and nothing else.
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() {
  echo "FAIL: $1"
  [[ -n "${2:-}" ]] && echo "      $2"
  FAIL=$((FAIL + 1))
  return 0
}

# ASSERTION helper — owns CASES. $1 = description, $2 = condition (eval'd), $3 = failure detail.
assert() {
  CASES=$((CASES + 1))
  if eval "$2"; then
    pass "$1"
  else
    fail "$1" "${3:-$2}"
  fi
}

SANDBOX="$(mktemp -d)" || { echo "FAIL: harness could not build a sandbox — aborting rather than reporting a verdict"; exit 2; }
trap 'rm -rf "${SANDBOX}"' EXIT
mkdir -p "${SANDBOX}/.claude" || { echo "FAIL: harness setup"; exit 2; }

# Drive the hook with a Bash PostToolUse payload; writes are redirected into the
# sandbox by INCIDENTS_REPO_ROOT, so the operator's real corpus is never touched.
# CLAUDE_PROJECT_DIR still points at the real repo so the lib and the rule corpus
# resolve exactly as in production.
drive() {
  local cmd="$1"
  : > "${SANDBOX}/.claude/.rule-incidents.jsonl"
  jq -nc --arg c "$cmd" '{hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:$c}}' \
    | INCIDENTS_REPO_ROOT="${SANDBOX}" CLAUDE_PROJECT_DIR="${REPO_ROOT}" bash "${HOOK}" >/dev/null 2>&1
  echo $?
}
# `grep -c .` EXITS 1 on an empty file while still printing 0, so a `|| echo 0`
# fallback appends a SECOND line and every equality check against "0" fails. The
# harness must not manufacture its own verdicts.
rows() {
  local n
  n="$(grep -c . "${SANDBOX}/.claude/.rule-incidents.jsonl" 2>/dev/null)" || n=0
  printf '%s' "${n:-0}"
}
last_rule() { tail -1 "${SANDBOX}/.claude/.rule-incidents.jsonl" 2>/dev/null | jq -r '.rule_id // empty' 2>/dev/null; }
last_text() { tail -1 "${SANDBOX}/.claude/.rule-incidents.jsonl" 2>/dev/null | jq -r '.rule_text_prefix // empty' 2>/dev/null; }

# --- 1. Happy path: a real corpus rule id lands a row -------------------------------
rc=$(drive "echo 'SOLEUR_RULE_APPLIED rule=cq-write-failing-tests-before note=Write failing tests BEFORE implementation code'")
assert "1: in-corpus rule id emits exactly one row" \
  '[[ "$(rows)" == "1" && "$(last_rule)" == "cq-write-failing-tests-before" && "$rc" == "0" ]]' \
  "expected 1 row for an in-corpus rule (rows=$(rows) rule=$(last_rule) rc=$rc)"

# --- 2. THE SECURITY CASE: an id absent from the closed corpus is REJECTED ----------
# This is the contributor-injection fixture. Deleting the corpus check makes it pass.
rc=$(drive "echo 'SOLEUR_RULE_APPLIED rule=attacker-invented-rule note=arbitrary'")
assert "2: rule id absent from the AGENTS.rules.md corpus is rejected (and the hook still exits 0)" \
  '[[ "$(rows)" == "0" && "$rc" == "0" ]]' \
  "an uncorpused rule id landed a row — the closed-corpus check is not holding (rows=$(rows) rc=$rc)"

# --- 3. Shape rejection: uppercase / overlong / path-shaped ids ---------------------
bad=0
for id in 'Rule-With-Caps' '../../etc/passwd' 'x' 'rule;id'; do
  drive "echo 'SOLEUR_RULE_APPLIED rule=${id} note=n'" >/dev/null
  [[ "$(rows)" == "0" ]] || bad=$((bad + 1))
done
assert "3: malformed rule ids (caps, traversal, too-short, metacharacter) all rejected" \
  '[[ "$bad" -eq 0 ]]' "${bad}/4 malformed rule ids landed a row"

# --- 4. Reserved synthetic prefixes are accepted -----------------------------------
bad=0
for id in 'te-envelope-outlier' 'gdpr-gate-staleness' 'cost-of-filing-file' 'encryption-posture-design-time-default'; do
  drive "echo 'SOLEUR_RULE_APPLIED rule=${id} note=n'" >/dev/null
  [[ "$(rows)" == "1" ]] || bad=$((bad + 1))
done
assert "4: reserved synthetic prefixes accepted (te-, gdpr-gate-, cost-of-filing-, encryption-posture)" \
  '[[ "$bad" -eq 0 ]]' \
  "${bad}/4 reserved synthetic ids were rejected — they would fail the aggregator orphan-gate as orphans"

# --- 5. The reserved list MIRRORS the aggregator's orphan-gate exemptions -----------
# An id accepted here but not exempt there fails that gate; drift between the two is
# invisible from either side alone.
AGG="${REPO_ROOT}/scripts/rule-metrics-aggregate.sh"
missing=""
for p in 'te-' 'gdpr-gate-' 'context-reviewed-'; do
  grep -qF "startswith(\"${p}\")" "${AGG}" 2>/dev/null || missing="${missing} ${p}"
done
assert "5: reserved prefixes still exempt in rule-metrics-aggregate.sh" \
  '[[ -z "${missing}" ]]' \
  "prefixes accepted by the hook but no longer exempt in the aggregator:${missing}"

# --- 6. Note sanitisation strips shell/JSON metacharacters -------------------------
drive "echo 'SOLEUR_RULE_APPLIED rule=cq-write-failing-tests-before note=drop\$(id)me\`x\`'" >/dev/null
t="$(last_text)"
# Evaluated into a plain boolean rather than inlined into the condition string: the pattern
# needs literal `$(` and a backtick, and burying those in an eval'd condition is where a
# quoting slip turns a real check into an always-true one.
sanitised=1
[[ "$(rows)" == "1" ]] || sanitised=0
# shellcheck disable=SC2034  # consumed via `eval "$condition"` in assert()
case "$t" in *'$('*|*'`'*) sanitised=0 ;; esac
assert "6: note sanitised — command-substitution characters stripped before reaching jq" \
  '[[ "$sanitised" -eq 1 ]]' "note retained metacharacters or wrong row count (rows=$(rows) text=${t})"

# --- 7. Kill-switch --------------------------------------------------------------
: > "${SANDBOX}/.claude/.rule-incidents.jsonl"
jq -nc '{tool_input:{command:"echo '"'"'SOLEUR_RULE_APPLIED rule=cq-write-failing-tests-before note=n'"'"'"}}' \
  | SOLEUR_DISABLE_RULE_MARKER_CAPTURE=1 INCIDENTS_REPO_ROOT="${SANDBOX}" CLAUDE_PROJECT_DIR="${REPO_ROOT}" \
    bash "${HOOK}" >/dev/null 2>&1
assert "7: SOLEUR_DISABLE_RULE_MARKER_CAPTURE=1 short-circuits" \
  '[[ "$(rows)" == "0" ]]' "kill-switch did not suppress the emission (rows=$(rows))"

# --- 8. A command with no marker is a no-op ---------------------------------------
rc=$(drive "git status --short")
assert "8: unmarked commands are a silent no-op" \
  '[[ "$(rows)" == "0" && "$rc" == "0" ]]' \
  "an unmarked command produced a row or a non-zero exit (rows=$(rows) rc=$rc)"

# --- 9. Malformed hook input never blocks the tool call ----------------------------
bad=0
for payload in '' 'not json at all' '{"tool_input":{}}'; do
  printf '%s' "$payload" | INCIDENTS_REPO_ROOT="${SANDBOX}" CLAUDE_PROJECT_DIR="${REPO_ROOT}" bash "${HOOK}" >/dev/null 2>&1
  [[ $? -eq 0 ]] || bad=$((bad + 1))
done
assert "9: empty / invalid / field-less input all exit 0 (fire-and-forget contract)" \
  '[[ "$bad" -eq 0 ]]' \
  "${bad}/3 malformed inputs produced a non-zero exit — the hook can block a tool call"

# --- 10. Every marker the payload actually emits is ACCEPTED by this hook ----------
# The producer/consumer parity check. A marker shipped in payload markdown that this
# hook rejects is a silent telemetry loss with nothing red anywhere.
emitted=0
rejected=""
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  emitted=$((emitted + 1))
  # NO EXEMPTION FOR `${…}` IDS — this line used to read
  #   case "$id" in *'${'*) continue ;; esac
  # with a comment promising to "probe its resolved forms", and then probed nothing. That
  # exemption sat around the one marker in the corpus that was broken: `review/SKILL.md`
  # emitted `rule=cost-of-filing-${DISPOSITION}`, which can NEVER match this hook's
  # `rule=[A-Za-z0-9._-]+ note=` needle (`$` and `{` are outside the class), so it produced
  # zero rows permanently while this test reported the corpus clean.
  #
  # An unexpanded `${` in an id is therefore a DEFECT, not a case to skip: the hook reads
  # `.tool_input.command` — pre-expansion text — so from its vantage there is no runtime
  # expansion to resolve. A marker id must be a static literal.
  case "$id" in
    *'${'*|*'$('*)
      rejected="${rejected} ${id}(unexpanded-expansion-in-id)"
      continue
      ;;
  esac
  drive "echo 'SOLEUR_RULE_APPLIED rule=${id} note=n'" >/dev/null
  [[ "$(rows)" == "1" ]] || rejected="${rejected} ${id}"
done < <(grep -rhoE "SOLEUR_RULE_APPLIED rule=[^ ]+" "${REPO_ROOT}/plugins/soleur/skills/" 2>/dev/null \
           | sed 's/.*rule=//' | sort -u)

# SCAN-VACUITY FLOOR (ADR-193 #1). This measures the SYSTEM UNDER TEST — how many markers the
# payload emits — and it used to report through fail(). ADR-193 #1 covers floors of that kind
# too: they route through the same verdict helper and are silenced by the same fault. Reported
# with printf >&2 + exit 1 DIRECTLY, so a neutered fail() cannot mute it.
MARKER_SCAN_MIN=10
if (( emitted < MARKER_SCAN_MIN )); then
  printf '\n[FATAL] anti-vacuity floor: only %d distinct payload marker(s) discovered, expected >= %d.\n' \
    "$emitted" "$MARKER_SCAN_MIN" >&2
  printf '  The producer scan is vacuous — that is not the same as the corpus being clean.\n' >&2
  echo "Total: ${PASS} pass, ${FAIL} fail (${CASES} assertions)"
  exit 1
fi
assert "10: all ${emitted} distinct payload markers are accepted by this hook (producer/consumer parity)" \
  '[[ -z "${rejected}" ]]' \
  "payload emits markers this hook REJECTS (silent telemetry loss):${rejected}"

echo
# --- Accounting conservation (ADR-193 #3) ------------------------------------------
# Ordered BEFORE the floor per ADR-193 #4: a neutered fail() deflates the verdict counts, so a
# floor reading them would ALSO trip and would report the misleading "arms were deleted". This
# says "a verdict was discarded" instead. Reported with printf >&2 + exit 1 DIRECTLY, never
# through pass()/fail(): a check that reports by calling a verdict helper increments the very
# counter the exit status reads, so neutering the helper silences the rows AND the check meant
# to notice the silence. The literal `[FATAL] accounting` is load-bearing —
# guard-vacuity-floor's ARM 10 builds its conservation population by grepping that string.
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting: PASS+FAIL (%d) != CASES (%d).\n' \
    "$((PASS + FAIL))" "$CASES" >&2
  if [[ $((PASS + FAIL)) -lt "$CASES" ]]; then
    printf '  An assertion was counted but its verdict was discarded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `CASES=$((CASES + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  echo "Total: ${PASS} pass, ${FAIL} fail (${CASES} assertions)"
  exit 1
fi

# --- Anti-vacuity floor (ADR-193 #1) -----------------------------------------------
# This suite had NO suite-level floor: delete every case and it printed `Total: 0 pass, 0 fail`
# and exited 0. Reads the INDEPENDENT case counter, and reports directly.
#
# Zero headroom against the current count, so any deletion is loud. Ratchet when adding cases,
# and read a floor failure on an otherwise-green run as "you added cases, update this number".
HOOK_MIN_ASSERTIONS=10
if (( CASES < HOOK_MIN_ASSERTIONS )); then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$CASES" "$HOOK_MIN_ASSERTIONS" >&2
  printf '  Cases were deleted or skipped; a green run here would be a coverage loss.\n' >&2
  echo "Total: ${PASS} pass, ${FAIL} fail (${CASES} assertions)"
  exit 1
fi

echo "Total: ${PASS} pass, ${FAIL} fail (${CASES} assertions)"
[[ "${FAIL}" -eq 0 ]]
