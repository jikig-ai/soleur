#!/usr/bin/env bash
# Tests for rule-incident-marker-capture.sh (ADR-179 decision 9, #7450).
#
# The hook consumes a marker emitted by payload markdown. On the review path that
# markdown is CONTRIBUTOR-WRITABLE, so the validation is not hygiene — it is the
# property that bounds the worst case to a rejected telemetry row. Most of the cases
# below are therefore REJECTION cases, each fixtured so it would land a row if the
# corresponding check were deleted.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HOOK_DIR}/../.." && pwd)"
HOOK="${HOOK_DIR}/rule-incident-marker-capture.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

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
if [[ "$(rows)" == "1" && "$(last_rule)" == "cq-write-failing-tests-before" && "$rc" == "0" ]]; then
  pass "1: in-corpus rule id emits exactly one row"
else
  fail "1: expected 1 row for an in-corpus rule (rows=$(rows) rule=$(last_rule) rc=$rc)"
fi

# --- 2. THE SECURITY CASE: an id absent from the closed corpus is REJECTED ----------
# This is the contributor-injection fixture. Deleting the corpus check makes it pass.
rc=$(drive "echo 'SOLEUR_RULE_APPLIED rule=attacker-invented-rule note=arbitrary'")
if [[ "$(rows)" == "0" && "$rc" == "0" ]]; then
  pass "2: rule id absent from the AGENTS.rules.md corpus is rejected (and the hook still exits 0)"
else
  fail "2: an uncorpused rule id landed a row — the closed-corpus check is not holding (rows=$(rows))"
fi

# --- 3. Shape rejection: uppercase / overlong / path-shaped ids ---------------------
bad=0
for id in 'Rule-With-Caps' '../../etc/passwd' 'x' 'rule;id'; do
  drive "echo 'SOLEUR_RULE_APPLIED rule=${id} note=n'" >/dev/null
  [[ "$(rows)" == "0" ]] || bad=$((bad + 1))
done
if [[ "$bad" -eq 0 ]]; then
  pass "3: malformed rule ids (caps, traversal, too-short, metacharacter) all rejected"
else
  fail "3: ${bad}/4 malformed rule ids landed a row"
fi

# --- 4. Reserved synthetic prefixes are accepted -----------------------------------
bad=0
for id in 'te-envelope-outlier' 'gdpr-gate-staleness' 'cost-of-filing-file' 'encryption-posture-design-time-default'; do
  drive "echo 'SOLEUR_RULE_APPLIED rule=${id} note=n'" >/dev/null
  [[ "$(rows)" == "1" ]] || bad=$((bad + 1))
done
if [[ "$bad" -eq 0 ]]; then
  pass "4: reserved synthetic prefixes accepted (te-, gdpr-gate-, cost-of-filing-, encryption-posture)"
else
  fail "4: ${bad}/4 reserved synthetic ids were rejected — they would fail the aggregator orphan-gate as orphans"
fi

# --- 5. The reserved list MIRRORS the aggregator's orphan-gate exemptions -----------
# An id accepted here but not exempt there fails that gate; drift between the two is
# invisible from either side alone.
AGG="${REPO_ROOT}/scripts/rule-metrics-aggregate.sh"
missing=""
for p in 'te-' 'gdpr-gate-' 'context-reviewed-'; do
  grep -qF "startswith(\"${p}\")" "${AGG}" 2>/dev/null || missing="${missing} ${p}"
done
if [[ -z "${missing}" ]]; then
  pass "5: reserved prefixes still exempt in rule-metrics-aggregate.sh"
else
  fail "5: prefixes accepted by the hook but no longer exempt in the aggregator:${missing}"
fi

# --- 6. Note sanitisation strips shell/JSON metacharacters -------------------------
drive "echo 'SOLEUR_RULE_APPLIED rule=cq-write-failing-tests-before note=drop\$(id)me\`x\`'" >/dev/null
t="$(last_text)"
if [[ "$(rows)" == "1" && "$t" != *'$('* && "$t" != *'`'* ]]; then
  pass "6: note sanitised — command-substitution characters stripped before reaching jq"
else
  fail "6: note retained metacharacters (text=${t})"
fi

# --- 7. Kill-switch --------------------------------------------------------------
: > "${SANDBOX}/.claude/.rule-incidents.jsonl"
jq -nc '{tool_input:{command:"echo '"'"'SOLEUR_RULE_APPLIED rule=cq-write-failing-tests-before note=n'"'"'"}}' \
  | SOLEUR_DISABLE_RULE_MARKER_CAPTURE=1 INCIDENTS_REPO_ROOT="${SANDBOX}" CLAUDE_PROJECT_DIR="${REPO_ROOT}" \
    bash "${HOOK}" >/dev/null 2>&1
if [[ "$(rows)" == "0" ]]; then
  pass "7: SOLEUR_DISABLE_RULE_MARKER_CAPTURE=1 short-circuits"
else
  fail "7: kill-switch did not suppress the emission"
fi

# --- 8. A command with no marker is a no-op ---------------------------------------
rc=$(drive "git status --short")
if [[ "$(rows)" == "0" && "$rc" == "0" ]]; then
  pass "8: unmarked commands are a silent no-op"
else
  fail "8: an unmarked command produced a row or a non-zero exit (rows=$(rows) rc=$rc)"
fi

# --- 9. Malformed hook input never blocks the tool call ----------------------------
bad=0
for payload in '' 'not json at all' '{"tool_input":{}}'; do
  printf '%s' "$payload" | INCIDENTS_REPO_ROOT="${SANDBOX}" CLAUDE_PROJECT_DIR="${REPO_ROOT}" bash "${HOOK}" >/dev/null 2>&1
  [[ $? -eq 0 ]] || bad=$((bad + 1))
done
if [[ "$bad" -eq 0 ]]; then
  pass "9: empty / invalid / field-less input all exit 0 (fire-and-forget contract)"
else
  fail "9: ${bad}/3 malformed inputs produced a non-zero exit — the hook can block a tool call"
fi

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

if [[ "$emitted" -lt 10 ]]; then
  fail "10: only ${emitted} distinct markers discovered in the payload — the scan is vacuous, not the corpus clean"
elif [[ -z "${rejected}" ]]; then
  pass "10: all ${emitted} distinct payload markers are accepted by this hook (producer/consumer parity)"
else
  fail "10: payload emits markers this hook REJECTS (silent telemetry loss):${rejected}"
fi

echo
echo "Total: ${PASS} pass, ${FAIL} fail"
[[ "${FAIL}" -eq 0 ]]
