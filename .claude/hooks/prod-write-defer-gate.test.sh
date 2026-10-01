#!/usr/bin/env bash
# Fixture-based tests for prod-write-defer-gate.sh. Synthesized fixtures
# (TEST-FIXTURE-NOT-REAL token) verify the inline-regex-array gate at the
# anchor + match + bypass + mode + fail-closed axes.
#
# Isolation pattern matches ship-unpushed-commits-gate.test.sh / pre-merge-
# rebase.test.sh: per-test mktemp work-tree + incidents root; INCIDENTS_REPO_ROOT
# redirects the .rule-incidents.jsonl off the operator's real sink.

set -uo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"
# -e omitted: tests must report FAIL when the hook misbehaves, not abort the
# whole run. Final exit code is driven by $FAIL.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/prod-write-defer-gate.sh"

PASS=0
FAIL=0
TOTAL=0

command -v jq >/dev/null 2>&1 || { echo "UNRESOLVED: jq missing — this suite asserted nothing; install jq"; exit 3; }

make_payload() {
  local cmd="$1" cwd="${2:-/tmp/TEST-FIXTURE-NOT-REAL-cwd}"
  jq -nc --arg c "$cwd" --arg x "$cmd" '{tool_name:"Bash", tool_input:{command:$x}, cwd:$c, session_id:"TEST-FIXTURE-NOT-REAL-session"}'
}

# run_hook MODE PAYLOAD INCIDENTS_ROOT [extra-env...]
#   MODE: "dry" (SOLEUR_DEFER_DRYRUN=1) or "enforce" (SOLEUR_DEFER_DRYRUN=0)
# Echoes the hook's stdout (the JSON envelope or empty).
run_hook() {
  local mode="$1" payload="$2" incidents="$3"; shift 3
  local dryrun=1
  [[ "$mode" == "enforce" ]] && dryrun=0
  env -i \
    HOME="${HOME:?}" PATH="$PATH" \
    INCIDENTS_REPO_ROOT="$incidents" \
    SOLEUR_DEFER_DRYRUN="$dryrun" \
    "$@" \
    bash -c 'printf "%s" "$1" | "'"$HOOK"'" 2>/dev/null' _ "$payload"
}

# assert_match_dry NAME CMD EXPECTED_RULE_ID
# Dry-run path: hook should emit kind=would_defer for the matched rule_id,
# and return empty/allow output (no permissionDecision).
assert_match_dry() {
  local name="$1" cmd="$2" expected_rule="$3"
  local tmp; tmp=$(mktemp -d); local incidents="$tmp/incidents"
  mkdir -p "$incidents"
  local payload; payload=$(make_payload "$cmd")
  local out; out=$(run_hook dry "$payload" "$incidents")
  local jsonl="$incidents/.claude/.rule-incidents.jsonl"
  local decision; decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  local seen_kind seen_rule
  if [[ -f "$jsonl" ]]; then
    seen_rule=$(jq -r 'select(.kind=="would_defer") | .rule_id' "$jsonl" | head -1)
    seen_kind=$(jq -r '.kind' "$jsonl" | head -1)
  else
    seen_rule=""; seen_kind=""
  fi
  if [[ "$decision" == "" && "$seen_kind" == "would_defer" && "$seen_rule" == "$expected_rule" ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  cmd=$cmd"
    echo "  decision=$decision (expected empty), kind=$seen_kind (expected would_defer), rule=$seen_rule (expected $expected_rule)"
    echo "  stdout=$out"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$tmp"
}

# assert_match_enforce NAME CMD EXPECTED_RULE_ID
# Enforce path: hook should emit kind=defer_requested and return the wrapped
# defer envelope with permissionDecision=defer + hookEventName=PreToolUse.
assert_match_enforce() {
  local name="$1" cmd="$2" expected_rule="$3"
  local tmp; tmp=$(mktemp -d); local incidents="$tmp/incidents"
  mkdir -p "$incidents"
  local payload; payload=$(make_payload "$cmd")
  local out; out=$(run_hook enforce "$payload" "$incidents")
  local jsonl="$incidents/.claude/.rule-incidents.jsonl"
  local decision event_name reason seen_kind seen_rule
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  event_name=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null || echo "")
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null || echo "")
  if [[ -f "$jsonl" ]]; then
    seen_rule=$(jq -r 'select(.kind=="defer_requested") | .rule_id' "$jsonl" | head -1)
    seen_kind=$(jq -r '.kind' "$jsonl" | head -1)
  else
    seen_rule=""; seen_kind=""
  fi
  if [[ "$decision" == "defer" && "$event_name" == "PreToolUse" \
        && "$seen_kind" == "defer_requested" && "$seen_rule" == "$expected_rule" \
        && -n "$reason" ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  cmd=$cmd"
    echo "  decision=$decision (expected defer), event_name=$event_name (expected PreToolUse)"
    echo "  kind=$seen_kind (expected defer_requested), rule=$seen_rule (expected $expected_rule)"
    echo "  reason=$reason"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
}

# assert_match_default_unset NAME CMD EXPECTED_RULE_ID
# Default-when-unset path (AC3): invoke the hook with SOLEUR_DEFER_DRYRUN
# completely UNSET (not pinned to 0 or 1) and assert the enforce envelope.
# This is the ONE behavior the rest of the suite does not cover — every other
# case pins the env var via run_hook, so a silent revert of the `:-0` default
# back to `:-1` would pass all of them. This case is the sole guard against
# that revert (see plan §Sharp Edges). Mirrors assert_match_enforce's
# assertions but uses `env -i` WITHOUT SOLEUR_DEFER_DRYRUN.
assert_match_default_unset() {
  local name="$1" cmd="$2" expected_rule="$3"
  local tmp; tmp=$(mktemp -d); local incidents="$tmp/incidents"
  mkdir -p "$incidents"
  local payload; payload=$(make_payload "$cmd")
  local out
  out=$(env -i \
    HOME="${HOME:?}" PATH="$PATH" \
    INCIDENTS_REPO_ROOT="$incidents" \
    bash -c 'printf "%s" "$1" | "'"$HOOK"'" 2>/dev/null' _ "$payload")
  local jsonl="$incidents/.claude/.rule-incidents.jsonl"
  local decision event_name reason seen_kind seen_rule
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  event_name=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null || echo "")
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null || echo "")
  if [[ -f "$jsonl" ]]; then
    seen_rule=$(jq -r 'select(.kind=="defer_requested") | .rule_id' "$jsonl" | head -1)
    seen_kind=$(jq -r '.kind' "$jsonl" | head -1)
  else
    seen_rule=""; seen_kind=""
  fi
  if [[ "$decision" == "defer" && "$event_name" == "PreToolUse" \
        && "$seen_kind" == "defer_requested" && "$seen_rule" == "$expected_rule" \
        && -n "$reason" ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  cmd=$cmd"
    echo "  decision=$decision (expected defer), event_name=$event_name (expected PreToolUse)"
    echo "  kind=$seen_kind (expected defer_requested), rule=$seen_rule (expected $expected_rule)"
    echo "  reason=$reason"
    echo "  (SOLEUR_DEFER_DRYRUN intentionally UNSET — a failure here implies the :-0 enforce default reverted to :-1 dry-run)"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$tmp"
}

# assert_nomatch NAME CMD
# Hook should output empty JSON / no decision, and emit NO incident.
assert_nomatch() {
  local name="$1" cmd="$2"
  local tmp; tmp=$(mktemp -d); local incidents="$tmp/incidents"
  mkdir -p "$incidents"
  local payload; payload=$(make_payload "$cmd")
  local out; out=$(run_hook dry "$payload" "$incidents")
  local jsonl="$incidents/.claude/.rule-incidents.jsonl"
  local decision; decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  local incident_count=0
  [[ -f "$jsonl" ]] && incident_count=$(wc -l < "$jsonl" | tr -d ' ')
  if [[ "$decision" == "" && "$incident_count" == "0" ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name (false positive)"
    echo "  cmd=$cmd"
    echo "  decision=$decision (expected empty), incidents=$incident_count (expected 0)"
    echo "  stdout=$out"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$tmp"
}

# ============================================================
# Tier A: canonical-form regex matches (dry-run mode, 3 rules)
# ============================================================
echo "--- Tier A: canonical matches (dry-run) ---"
assert_match_dry "A1 git push origin main"            "git push origin main"                                         "prod-write-defer-git-push-main"
assert_match_dry "A2 terraform apply"                 "terraform apply"                                              "prod-write-defer-terraform-apply"
assert_match_dry "A3 doppler -c prd_terraform set"    "doppler secrets set FOO=bar --config prd_terraform"           "prod-write-defer-doppler-secrets-stdout"

# ============================================================
# Tier B: form variations (the wrapped-invocation class)
# ============================================================
echo "--- Tier B: form variations ---"
assert_match_dry "B1 short-flag -f"                   "git push -f origin main"                                      "prod-write-defer-git-push-main"
assert_match_dry "B2 force-with-lease"                "git push --force-with-lease origin main"                      "prod-write-defer-git-push-main"
assert_match_dry "B3 refspec HEAD:main"               "git push origin HEAD:main"                                    "prod-write-defer-git-push-main"
assert_match_dry "B4 wrapped via -- separator"        "bash session-state.sh with_lock -- git push origin main"      "prod-write-defer-git-push-main"
assert_match_dry "B5 chained &&"                      "git fetch && git push origin main"                            "prod-write-defer-git-push-main"
assert_match_dry "B6 chained ;"                       "echo go; terraform apply"                                     "prod-write-defer-terraform-apply"
assert_match_dry "B7 env-prefixed doppler prd"        "DOPPLER_CONFIG=prd_terraform doppler secrets set X=Y --config prd_terraform" "prod-write-defer-doppler-secrets-stdout"
assert_match_dry "B8 short-flag doppler -c prd"       "doppler secrets set FOO=bar -c prd"                           "prod-write-defer-doppler-secrets-stdout"
assert_match_dry "B9 tofu apply"                      "tofu apply"                                                   "prod-write-defer-terraform-apply"
assert_match_dry "B10 push master alias"               "git push origin master"                                       "prod-write-defer-git-push-main"
assert_match_dry "B11 trailing semicolon"              "git push origin main;"                                        "prod-write-defer-git-push-main"
assert_match_dry "B12 wrapped in subshell parens"      "(git push origin main)"                                       "prod-write-defer-git-push-main"
assert_match_dry "B13 trailing chained sequence"       "git push origin main; echo done"                              "prod-write-defer-git-push-main"
assert_match_dry "B14 backgrounded"                    "git push origin main &"                                       "prod-write-defer-git-push-main"
# Widened rule: doppler-stdout-echo trap covers `delete` and configs {dev,ci} (issue #4029).
assert_match_dry "B15 doppler delete -c prd"           "doppler secrets delete X -p soleur -c prd --yes"              "prod-write-defer-doppler-secrets-stdout"
assert_match_dry "B16 doppler delete -c dev"           "doppler secrets delete X -p soleur -c dev --yes"              "prod-write-defer-doppler-secrets-stdout"
assert_match_dry "B17 doppler delete -c prd_terraform" "doppler secrets delete X -c prd_terraform --yes"              "prod-write-defer-doppler-secrets-stdout"
assert_match_dry "B18 doppler delete -c ci"            "doppler secrets delete X -c ci --yes"                         "prod-write-defer-doppler-secrets-stdout"
assert_match_dry "B19 doppler set -c dev"              "doppler secrets set X=Y -c dev"                               "prod-write-defer-doppler-secrets-stdout"
assert_match_dry "B20 doppler set -c ci"               "doppler secrets set X=Y -c ci"                                "prod-write-defer-doppler-secrets-stdout"
assert_match_dry "B21 env-prefixed delete"             "DOPPLER_CONFIG=prd doppler secrets delete X --config prd --yes" "prod-write-defer-doppler-secrets-stdout"
assert_match_dry "B22 wrapped delete via -- separator" "bash session-state.sh with_lock secret-rotate 300 -- doppler secrets delete X -c prd --yes" "prod-write-defer-doppler-secrets-stdout"
assert_match_dry "B23 chained && delete"               "gh issue close 1 && doppler secrets delete X -c prd --yes"    "prod-write-defer-doppler-secrets-stdout"
assert_match_dry "B24 delete -c prd_orchestration"     "doppler secrets delete TENANT_X_INSTALLATION_ID -c prd_orchestration --yes" "prod-write-defer-doppler-secrets-stdout"
assert_match_dry "B25 set -c prd_orchestration"        "doppler secrets set TENANT_X_INSTALLATION_ID=123 --config prd_orchestration" "prod-write-defer-doppler-secrets-stdout"

# ============================================================
# Tier C: adjacent non-matches (must NOT fire)
# ============================================================
echo "--- Tier C: adjacent non-matches ---"
assert_nomatch "C1 push feat branch (not main)"          "git push origin feat-foo"
assert_nomatch "C2 push feat-main-update (substring)"    "git push origin feat-main-update"
assert_nomatch "C3 terraform plan (not apply)"           "terraform plan"
assert_nomatch "C4 terraform apply substring in echo"    "echo 'hint: try terraform apply later'"
assert_nomatch "C5 doppler --config prd-staging"         "doppler secrets set FOO=bar --config prd-staging"
assert_nomatch "C6 doppler --config preview"             "doppler secrets set FOO=bar --config preview"
assert_nomatch "C7 git pull origin main"                 "git pull origin main"
assert_nomatch "C8 echo gh pr merge example"             "echo 'gh pr merge example'"
assert_nomatch "C9 terraform apply -help (read-only)"    "terraform apply -help"
assert_nomatch "C10 terraform apply --help (read-only)"  "terraform apply --help"
assert_nomatch "C11 terraform apply -version"            "terraform apply -version"
assert_nomatch "C12 tofu apply -v (short read-only)"     "tofu apply -v"
assert_nomatch "C13 push to branch with main-fixup"      "git push origin main-fixup"
assert_nomatch "C14 push to slash-separated feat/main"   "git push origin feat/dashboard-main"
assert_nomatch "C15 doppler secrets get (read-only)"     "doppler secrets get --config prd_terraform"
assert_nomatch "C16 doppler --config=prd (equals-form)"  "doppler secrets set FOO=bar --config=prd_terraform"
# Widened-rule adjacent non-matches: delete reads + delete --help + adjacent verbs.
assert_nomatch "C17 doppler secrets list --config prd"   "doppler secrets list --config prd"
assert_nomatch "C18 doppler secrets download --config prd" "doppler secrets download --config prd"
assert_nomatch "C19 doppler delete --help (read-only)"   "doppler secrets delete --help"
assert_nomatch "C20 doppler delete -h (short read-only)" "doppler secrets delete -h"
assert_nomatch "C21 doppler set --help (read-only)"      "doppler secrets set --help"
assert_nomatch "C22 doppler delete -c prd-staging"       "doppler secrets delete X -c prd-staging --yes"
assert_nomatch "C23 doppler delete --config=prd (equals-form)" "doppler secrets delete X --config=prd --yes"
assert_nomatch "C24 echo substring of delete"            "echo 'doppler secrets delete example'"
assert_nomatch "C25 doppler set -c stg (staging)"        "doppler secrets set FOO=bar -c stg"

# ============================================================
# Tier D: enforce-mode wrapped envelope + decision value
# ============================================================
echo "--- Tier D: enforce mode (wrapped defer envelope) ---"
assert_match_enforce "D1 enforce push main"            "git push origin main"                                         "prod-write-defer-git-push-main"
assert_match_enforce "D2 enforce terraform apply"      "terraform apply -auto-approve"                                "prod-write-defer-terraform-apply"
assert_match_enforce "D3 enforce doppler prd"          "doppler secrets set FOO=bar --config prd_terraform"           "prod-write-defer-doppler-secrets-stdout"
# D4 (AC3): default-when-unset must be enforce. SOLEUR_DEFER_DRYRUN is NOT set
# in the env — exercises the hardcoded `${SOLEUR_DEFER_DRYRUN:-0}` fallback.
# RED against the pre-flip `:-1` default (would emit would_defer/allow).
assert_match_default_unset "D4 default-unset enforce"  "terraform apply"                                              "prod-write-defer-terraform-apply"

# ============================================================
# Tier E: bypass (TTY + env reason+operator) → kind=bypass, allow
# ============================================================
echo "--- Tier E: bypass (env reason+operator) ---"
{
  tmp=$(mktemp -d); incidents="$tmp/incidents"; mkdir -p "$incidents"
  payload=$(make_payload "git push origin main")
  # Bypass via env vars (non-TTY path that still succeeds because reason+operator are set).
  out=$(env -i \
    HOME="${HOME:?}" PATH="$PATH" \
    INCIDENTS_REPO_ROOT="$incidents" \
    SOLEUR_DEFER_DRYRUN=0 \
    CLAUDE_HOOK_BYPASS=1 \
    CLAUDE_HOOK_BYPASS_REASON="hotfix-incident-12345 test" \
    CLAUDE_HOOK_BYPASS_OPERATOR="ops-test@TEST-FIXTURE-NOT-REAL.local" \
    bash -c 'printf "%s" "$1" | "'"$HOOK"'" 2>/dev/null' _ "$payload")
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  jsonl="$incidents/.claude/.rule-incidents.jsonl"
  seen_kind=$(jq -r 'select(.kind=="bypass") | .kind' "$jsonl" 2>/dev/null | head -1)
  if [[ "$decision" == "" && "$seen_kind" == "bypass" ]]; then
    echo "PASS: E1 bypass with env reason+operator → kind=bypass, allow"
    PASS=$((PASS+1))
  else
    echo "FAIL: E1 (decision=$decision expected empty; kind=$seen_kind expected bypass)"
    echo "  jsonl=$(cat "$jsonl" 2>/dev/null)"
    FAIL=$((FAIL+1))
  fi
  TOTAL=$((TOTAL+1))
  rm -rf "$tmp"
}

# ============================================================
# Tier F: bypass missing reason → fail CLOSED
# ============================================================
echo "--- Tier F: bypass without CLAUDE_HOOK_BYPASS_REASON → fail-closed ---"
{
  tmp=$(mktemp -d); incidents="$tmp/incidents"; mkdir -p "$incidents"
  payload=$(make_payload "git push origin main")
  # BYPASS=1 but no reason env var → must DENY + emit hook_self_fault.
  # Policy intent (no interactive TTY-prompt path): reason MUST be authorial
  # (env-set), never inferred from a terminal prompt. Operator email can
  # fall through to resolve_operator_email but reason cannot.
  out=$(env -i \
    HOME="${HOME:?}" PATH="$PATH" \
    INCIDENTS_REPO_ROOT="$incidents" \
    SOLEUR_DEFER_DRYRUN=0 \
    CLAUDE_HOOK_BYPASS=1 \
    bash -c 'printf "%s" "$1" | "'"$HOOK"'" 2>/dev/null' _ "$payload")
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  jsonl="$incidents/.claude/.rule-incidents.jsonl"
  seen_kind=$(jq -r 'select(.kind=="hook_self_fault") | .kind' "$jsonl" 2>/dev/null | head -1)
  if [[ "$decision" == "deny" && "$seen_kind" == "hook_self_fault" ]]; then
    echo "PASS: F1 bypass missing reason → deny + hook_self_fault"
    PASS=$((PASS+1))
  else
    echo "FAIL: F1 (decision=$decision expected deny; kind=$seen_kind expected hook_self_fault)"
    echo "  out=$out"
    echo "  jsonl=$(cat "$jsonl" 2>/dev/null)"
    FAIL=$((FAIL+1))
  fi
  TOTAL=$((TOTAL+1))
  rm -rf "$tmp"
}

# ============================================================
# Tier G: broken regex (synthesized SOLEUR_DEFER_TARGETS_OVERRIDE) → fail CLOSED
# ============================================================
# Why: the production TARGETS array is hardcoded and reviewed, but the gate
# must defend against accidentally-introduced bad patterns (e.g., a future
# operator adds `[invalid` to the manifest). We simulate this via an
# override env var the hook honors only when set explicitly.
echo "--- Tier G: broken regex → fail-closed ---"
{
  tmp=$(mktemp -d); incidents="$tmp/incidents"; mkdir -p "$incidents"
  payload=$(make_payload "git push origin main")
  out=$(env -i \
    HOME="${HOME:?}" PATH="$PATH" \
    INCIDENTS_REPO_ROOT="$incidents" \
    SOLEUR_DEFER_DRYRUN=0 \
    SOLEUR_DEFER_TARGETS_OVERRIDE='broken-rule|hr-test|[invalid(unclosed' \
    bash -c 'printf "%s" "$1" | "'"$HOOK"'" 2>/dev/null' _ "$payload")
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  jsonl="$incidents/.claude/.rule-incidents.jsonl"
  seen_kind=$(jq -r 'select(.kind=="hook_self_fault") | .kind' "$jsonl" 2>/dev/null | head -1)
  if [[ "$decision" == "deny" && "$seen_kind" == "hook_self_fault" ]]; then
    echo "PASS: G1 broken regex → deny + hook_self_fault"
    PASS=$((PASS+1))
  else
    echo "FAIL: G1 (decision=$decision expected deny; kind=$seen_kind expected hook_self_fault)"
    echo "  out=$out"
    echo "  jsonl=$(cat "$jsonl" 2>/dev/null)"
    FAIL=$((FAIL+1))
  fi
  TOTAL=$((TOTAL+1))
  rm -rf "$tmp"
}

# G2: invalid SOLEUR_DEFER_DRYRUN value → fail-closed via the case `*)` arm.
# Guards the plan §User-Brand Impact "mistyped flip" paralysis path: if the
# `:-0` default is ever edited to a non-0/non-1 value, the hook must DENY
# (deny_self_fault), never silently allow. Without this case a future edit
# that produces e.g. `:-O` (letter O) would fail open with no test signal.
{
  tmp=$(mktemp -d); incidents="$tmp/incidents"; mkdir -p "$incidents"
  payload=$(make_payload "terraform apply")
  out=$(env -i \
    HOME="${HOME:?}" PATH="$PATH" \
    INCIDENTS_REPO_ROOT="$incidents" \
    SOLEUR_DEFER_DRYRUN=99 \
    bash -c 'printf "%s" "$1" | "'"$HOOK"'" 2>/dev/null' _ "$payload")
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  jsonl="$incidents/.claude/.rule-incidents.jsonl"
  seen_kind=$(jq -r 'select(.kind=="hook_self_fault") | .kind' "$jsonl" 2>/dev/null | head -1)
  if [[ "$decision" == "deny" && "$seen_kind" == "hook_self_fault" ]]; then
    echo "PASS: G2 invalid SOLEUR_DEFER_DRYRUN value → deny + hook_self_fault"
    PASS=$((PASS+1))
  else
    echo "FAIL: G2 (decision=$decision expected deny; kind=$seen_kind expected hook_self_fault)"
    echo "  out=$out"
    echo "  jsonl=$(cat "$jsonl" 2>/dev/null)"
    FAIL=$((FAIL+1))
  fi
  TOTAL=$((TOTAL+1))
  rm -rf "$tmp"
}

# ============================================================
# Tier H: approval log writer (enforce mode appends row)
# ============================================================
echo "--- Tier H: approval log writer ---"
{
  tmp=$(mktemp -d); incidents="$tmp/incidents"; mkdir -p "$incidents"
  payload=$(make_payload "git push origin main")
  out=$(env -i \
    HOME="${HOME:?}" PATH="$PATH" \
    INCIDENTS_REPO_ROOT="$incidents" \
    SOLEUR_DEFER_DRYRUN=0 \
    SOLEUR_OPERATOR_EMAIL="approver@TEST-FIXTURE-NOT-REAL.local" \
    bash -c 'printf "%s" "$1" | "'"$HOOK"'" 2>/dev/null' _ "$payload")
  approvals="$incidents/.claude/logs/approvals.jsonl"
  if [[ -f "$approvals" ]] \
     && jq -e '.rule_id == "prod-write-defer-git-push-main" and .approval_method == "tty_resume" and .operator_email == "approver@TEST-FIXTURE-NOT-REAL.local"' "$approvals" >/dev/null 2>&1; then
    echo "PASS: H1 enforce mode appends approvals.jsonl row"
    PASS=$((PASS+1))
  else
    echo "FAIL: H1 approval log missing or wrong shape"
    echo "  approvals=$(cat "$approvals" 2>/dev/null)"
    FAIL=$((FAIL+1))
  fi
  TOTAL=$((TOTAL+1))
  rm -rf "$tmp"
}

# =============================================================================
# Tier I — Guard 3 of #8486 (ADR-249): the operator-ack script rule
# =============================================================================
# Property. A Bash command that executes any ack-calling operator script in
# write mode is deferred; a read-only invocation of the same script, and a
# command that merely names the path, is allowed. The rule's population is
# pinned to Guard 2's: operator-ack-arms.tsv (plugins/soleur/test/fixtures/)
# must be set-identical to the grep-derived ack callers, and every row is driven
# through every invocation shape. The ERE and the arm table live in different
# files; the grep-derived population is the third leg, owned by neither.
echo "--- Tier I: operator-ack script rule (#8486) ---"

REPO_ROOT_G3="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARMS_G3="$REPO_ROOT_G3/plugins/soleur/test/fixtures/operator-ack-arms.tsv"
G3_SB="$(mktemp -d)"
# Composed with the incident sandbox's own EXIT cleanup (lib/test-incident-sandbox.sh), never over it.
trap 'rm -rf "$G3_SB"; _soleur_inc_sb_cleanup' EXIT

# g3_decide <hook> <cmd> [extra-env...] -> defer | allow | deny | ERR:<raw>
g3_decide() {
  local hook="$1" cmd="$2"; shift 2
  local inc out d
  inc="$(mktemp -d "$G3_SB/inc.XXXXXX")"
  # Through a file, not --arg: a 1 MB command exceeds the per-argument limit.
  printf '%s' "$cmd" > "$inc/cmd"
  out="$(jq -nc --rawfile x "$inc/cmd" '{tool_name:"Bash", tool_input:{command:$x}, cwd:"/tmp/TEST-FIXTURE-NOT-REAL-cwd", session_id:"TEST-FIXTURE-NOT-REAL-session"}' \
    | env -i HOME="${HOME:?}" PATH="$PATH" INCIDENTS_REPO_ROOT="$inc" SOLEUR_DEFER_DRYRUN=0 "$@" bash "$hook" 2>/dev/null)"
  if [[ "$out" == "{}" ]]; then echo allow; return; fi
  d="$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$out" 2>/dev/null)"
  if [[ -n "$d" ]]; then echo "$d"; else echo "ERR:${out:0:120}"; fi
}

# g3_expect <label> <expected> <cmd> [hook] [extra-env...]
g3_expect() {
  local label="$1" want="$2" cmd="$3" hook="${4:-$HOOK}"; shift 4 2>/dev/null || shift $#
  local got; got="$(g3_decide "$hook" "$cmd" "$@")"
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" ]]; then
    echo "PASS: $label"; PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected $want, got $got"
    echo "  cmd=$(printf '%s' "$cmd" | tr '\n' '~' | cut -c1-200)"
    FAIL=$((FAIL + 1))
  fi
}

# g3_mutant_catches <label> <mutant-hook> <want-on-pristine> <cmd> — the case
# must give <want> on the pristine hook AND something else on the mutant.
g3_mutant_catches() {
  local label="$1" mut="$2" want="$3" cmd="$4" got_p got_m
  got_p="$(g3_decide "$HOOK" "$cmd")"; got_m="$(g3_decide "$mut" "$cmd")"
  TOTAL=$((TOTAL + 1))
  if [[ "$got_p" == "$want" && "$got_m" != "$want" ]]; then
    echo "PASS: $label (pristine $got_p, mutant $got_m)"; PASS=$((PASS + 1))
  else
    echo "FAIL: $label — pristine $got_p (want $want), mutant $got_m (must differ)"; FAIL=$((FAIL + 1))
  fi
}

# --- population: the grep-derived ack callers (same exclusions as Guard 2) ---
g3_population() {
  local rel
  git -C "$REPO_ROOT_G3" grep -l -e 'soleur_op_ack_or_die' -- '*.sh' \
    | grep -vE '\.test\.sh$|(^|/)test/|(^|/)scripts/lib/operator-script\.sh$|(^|/)operator-bootstrap/template\.sh$|^knowledge-base/' \
    | sort | while IFS= read -r rel; do
        grep -vE '^[[:space:]]*#' "$REPO_ROOT_G3/$rel" \
          | grep -qE '(^|[;&|({][[:space:]]*|[[:space:]]\|\|[[:space:]]*|^[[:space:]]+)soleur_op_ack_or_die([[:space:]]|$)' \
          && printf '%s\n' "$rel"
      done
}

# g3_identity <population-list> -> 0 iff every member has a write-mode DEFER on
# its canonical invocation AND is named by the arm table, and vice versa.
g3_identity() {
  local pop="$1" tabled rel v=0 argv
  tabled="$(grep -vE '^[[:space:]]*(#|$)' "$ARMS_G3" | cut -f1 | sort -u)"
  [[ -n "$(comm -3 <(printf '%s\n' "$pop") <(printf '%s\n' "$tabled"))" ]] && { echo "  identity: $(comm -3 <(printf '%s\n' "$pop") <(printf '%s\n' "$tabled") | tr -s '\t\n' '  ')"; v=1; }
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    # The member's own first write argv (so audit-sentry is invoked with --apply);
    # an untabled member gets a generic argv.
    argv="$(awk -F'\t' -v s="$rel" '$1==s && $2=="write" {print $3; exit}' "$ARMS_G3")"
    [[ -z "$argv" || "$argv" == "-" ]] && argv="x y z"
    [[ "$(g3_decide "$HOOK" "bash $REPO_ROOT_G3/$rel $argv")" == defer ]] || { echo "  identity: $rel not deferred"; v=1; }
  done <<<"$pop"
  return "$v"
}

if [[ ! -r "$ARMS_G3" ]]; then
  # M6 — an unreadable arm table fails closed; it never reports 0 cases.
  echo "FAIL: I0 arm table unreadable: $ARMS_G3"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1))
else
  G3_POP="$(g3_population)"
  TOTAL=$((TOTAL + 1))
  if [[ -n "$G3_POP" ]] && g3_identity "$G3_POP"; then
    echo "PASS: I0 set identity: ack callers == arm table, each deferred in write mode ($(wc -l <<<"$G3_POP") scripts)"; PASS=$((PASS + 1))
  else
    echo "FAIL: I0 set identity between ack callers, arm table and the hook's ERE broke"; FAIL=$((FAIL + 1))
  fi
  # M3 — a second ack caller the ERE does not know: identity must go RED.
  TOTAL=$((TOTAL + 1))
  if ! g3_identity "$(printf '%s\napps/web-platform/scripts/new-ack-caller.sh\n' "$G3_POP")"; then
    echo "PASS: I0-M3 an unknown ack caller breaks set identity"; PASS=$((PASS + 1))
  else
    echo "FAIL: I0-M3 an unknown ack caller did not break set identity"; FAIL=$((FAIL + 1))
  fi

  # --- every row x every invocation shape ------------------------------------
  G3_ROWS=0
  while IFS=$'\t' read -r script mode argv _profile; do
    [[ -n "$script" && "$script" != \#* ]] || continue
    G3_ROWS=$((G3_ROWS + 1))
    [[ "$argv" == "-" ]] && argv=""
    abs="$REPO_ROOT_G3/$script"
    plug_rel="${script#plugins/soleur/}"
    want_plain=allow; [[ "$mode" == write ]] && want_plain=defer
    g3_expect "I1 [$mode] bash abs: $script $argv"        "$want_plain" "bash $abs $argv"
    if [[ "$script" == plugins/soleur/* ]]; then
      g3_expect "I1 [$mode] plugin-root var: $plug_rel $argv" "$want_plain" "bash \"\${CLAUDE_PLUGIN_ROOT}/$plug_rel\" $argv"
    fi
    g3_expect "I1 [$mode] bare rel path: $script $argv"   "$want_plain" "$script $argv"
    g3_expect "I1 [$mode] cd && ./: $script $argv"        "$want_plain" "cd $(dirname "$abs") && ./$(basename "$abs") $argv"
    g3_expect "I1 [$mode] doppler run --: $script $argv"  "$want_plain" "doppler run -p soleur -c prd -- bash $abs $argv"
    g3_expect "I1 [$mode] bash -c: $script $argv"         "$want_plain" "bash -c 'bash $abs $argv'"
    # A PTY wrapper cancels every read-only escape: DEFER in both modes.
    g3_expect "I1 [$mode] script -qec: $script $argv"     defer         "script -qec \"bash $abs $argv\" /dev/null"
    g3_expect "I1 [$mode] yes | script -qc: $script $argv" defer        "yes | script -qc \"$abs $argv\""
  done < "$ARMS_G3"
  TOTAL=$((TOTAL + 1))
  if [[ "$G3_ROWS" -ge 10 ]]; then echo "PASS: I1 drove $G3_ROWS arm rows"; PASS=$((PASS + 1))
  else echo "FAIL: I1 drove only $G3_ROWS arm rows"; FAIL=$((FAIL + 1)); fi
fi

FLIP_G3="$REPO_ROOT_G3/plugins/soleur/skills/flag-set-role/scripts/flip.sh"
DELETE_G3="$REPO_ROOT_G3/plugins/soleur/skills/flag-delete/scripts/delete.sh"
CREATE_G3="$REPO_ROOT_G3/plugins/soleur/skills/flag-create/scripts/create.sh"
SETROLE_G3="$REPO_ROOT_G3/plugins/soleur/skills/user-set-role/scripts/set-role.sh"

# --- specific shapes (AC6) -----------------------------------------------------
g3_expect "I2 escape is per call, not per command"      defer "bash $DELETE_G3 f; echo --dry-run"
g3_expect "I2 newline ends the argument tail"            defer "bash $FLIP_G3 f prd on"$'\n'"echo --dry-run"
g3_expect "I2 dry-run then write in one command"         defer "bash $FLIP_G3 f prd on --dry-run && bash $FLIP_G3 f prd on"
g3_expect "I2 dry-run then PTY write"                    defer "bash $FLIP_G3 f prd on --dry-run && yes | script -qc \"bash $FLIP_G3 f prd on\""
g3_expect "I2 --dry-run as a quoted option value"        defer "bash $CREATE_G3 newflag --description \"--dry-run\""
g3_expect "I2 read-only under a PTY wrapper"             defer "script -qc \"bash $SETROLE_G3 u prd --dry-run\""
g3_expect "I2 heredoc piped to bash"                     defer "cat <<EOF | bash"$'\n'"bash $FLIP_G3 f prd on"$'\n'"EOF"
g3_expect "I2 reader piped to a shell"                   defer "cat $FLIP_G3 | bash -s f prd on"
g3_expect "I2 variable path"                             defer "S=/opt/soleur/skills/flag-set-role/scripts; bash \$S/flip.sh f prd on"
g3_expect "I2 cd into the skill dir"                     defer "cd plugins/soleur/skills/flag-set-role && bash scripts/flip.sh f prd on"
g3_expect "I2 cd into flag-delete, bare delete.sh"       defer "cd plugins/soleur/skills/flag-delete/scripts && ./delete.sh f"
g3_expect "I2 audit-sentry --apply"                      defer "bash apps/web-platform/scripts/audit-sentry-extra-text-references.sh --apply"
g3_expect "I2 audit-sentry inventory (read-only)"        allow "bash apps/web-platform/scripts/audit-sentry-extra-text-references.sh"
g3_expect "I2 provision-hetzner has no read-only escape" defer "bash plugins/soleur/skills/provision-hetzner/scripts/provision-hetzner.sh --dry-run"
# H2 — must-ALLOW: naming a path is not executing it.
g3_expect "I3 cat flip.sh"                               allow "cat $FLIP_G3"
g3_expect "I3 git log -- flip.sh"                        allow "git log -- plugins/soleur/skills/flag-set-role/scripts/flip.sh"
g3_expect "I3 grep in delete.sh"                         allow "grep -n ack plugins/soleur/skills/flag-delete/scripts/delete.sh"
g3_expect "I3 bash -n flip.sh"                           allow "bash -n $FLIP_G3"
g3_expect "I3 a different *-flip.sh"                     allow "bash apps/web-platform/infra/inngest-cutover-flip.sh"
g3_expect "I3 an unrelated create.sh"                    allow "bash apps/web-platform/scripts/create.sh"

# --- M12 — the rule fails CLOSED on its own error --------------------------------
g3_expect "I4-M12 injected return fault -> deny"         deny  "bash $FLIP_G3 f prd on" "$HOOK" SOLEUR_DEFER_TEST_INJECT_FAULT=return
g3_expect "I4-M12 injected crash -> deny via EXIT trap"  deny  "bash $FLIP_G3 f prd on" "$HOOK" SOLEUR_DEFER_TEST_INJECT_FAULT=exit
g3_expect "I4 a fault never fires without the prefilter" allow "git status" "$HOOK" SOLEUR_DEFER_TEST_INJECT_FAULT=exit

# --- H4 — a 1 MB command is decided within the hook's timeout --------------------
big="cat <<EOF | tee /dev/null"$'\n'"$(head -c 1000000 /dev/zero | tr '\0' 'a')"$'\n'"EOF"$'\n'"bash $FLIP_G3 f prd on"
t0=$(date +%s%N)
g3_expect "I5-H4 1 MB command with a trailing write" defer "$big"
t1=$(date +%s%N)
TOTAL=$((TOTAL + 1))
if (( (t1 - t0) / 1000000 < 20000 )); then echo "PASS: I5-H4 decided in $(( (t1 - t0) / 1000000 )) ms"; PASS=$((PASS + 1))
else echo "FAIL: I5-H4 took $(( (t1 - t0) / 1000000 )) ms"; FAIL=$((FAIL + 1)); fi

# --- hook mutations: each must flip a case the pristine hook gets right ----------
g3_mutant() { # <name> <perl program> -> path of the mutated hook (with its lib/)
  local d="$G3_SB/mut-$1"
  mkdir -p "$d"; cp -r "$SCRIPT_DIR/lib" "$d/lib"; cp "$HOOK" "$d/prod-write-defer-gate.sh"
  perl -0777 -pi -e "$2" "$d/prod-write-defer-gate.sh"
  if cmp -s "$HOOK" "$d/prod-write-defer-gate.sh" || ! bash -n "$d/prod-write-defer-gate.sh" 2>/dev/null; then
    echo "MUTANT-DID-NOT-LAND"; return 1
  fi
  echo "$d/prod-write-defer-gate.sh"
}
g3_row() { # <label> <name> <perl> <want-on-pristine> <cmd>
  local mut; mut="$(g3_mutant "$2" "$3")"
  if [[ "$mut" == MUTANT-DID-NOT-LAND ]]; then
    echo "FAIL: $1 — mutation did not land"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); return
  fi
  g3_mutant_catches "$1" "$mut" "$4" "$5"
}
g3_row "I6-M1 flip.sh dropped from the ERE"            m1  's{OPACK_UNIQUE=.flip\\\.sh\|}{OPACK_UNIQUE=\x27}' \
  defer "bash $FLIP_G3 f prd on"
g3_row "I6-M2 escape read from the whole command"      m2  's{\[\[ " \$tail " =~ \[\[:space:\]\]--dry-run}{[[ " \$cmd " =~ [[:space:]]--dry-run}' \
  defer "bash $DELETE_G3 f; echo --dry-run"
g3_row "I6-M7 only interpreter-prefixed calls count"   m7  's{(    any_write=1\n)}{    [[ "\$first" == bash || "\$first" == sh ]] || continue\n$1}' \
  defer "$FLIP_G3 f prd on"
g3_row "I6-M8 only the leftmost call is evaluated"     m8  's{(    calls=\$\(\(calls \+ 1\)\)\n)}{$1    (( calls > 1 )) \&\& break\n}' \
  defer "bash $FLIP_G3 f prd on --dry-run && bash $FLIP_G3 f prd on"
g3_row "I6-M9 newline dropped from the tail stops"     m9  's{(OPACK_TAIL_RE=\$\x27\^\(\[\^;&\|\)"\\\x27#`)\\n}{$1}' \
  defer "bash $FLIP_G3 f prd on"$'\n'"echo --dry-run"
g3_row "I6-M10 escape kept under a PTY wrapper"        m10 's{if \(\( ! pty \)\); then}{if true; then}' \
  defer "script -qc \"bash $SETROLE_G3 u prd --dry-run\""
g3_row "I6-M11 pipe-to-shell no longer cancels readers" m11 's{\[\[ "\$cmd" =~ \$OPACK_TO_SHELL_RE \]\] && to_shell=1}{:}' \
  defer "cat $FLIP_G3 | bash -s f prd on"

# Phase 4.2d — the Monitor tool carries the command in the same slot.
g3_monitor_decide() {
  local inc out
  inc="$(mktemp -d "$G3_SB/inc.XXXXXX")"
  out="$(jq -nc --arg x "$1" '{tool_name:"Monitor", tool_input:{command:$x, description:"d", timeout_ms:1000}, cwd:"/tmp/TEST-FIXTURE-NOT-REAL-cwd", session_id:"TEST-FIXTURE-NOT-REAL-session"}' \
    | env -i HOME="${HOME:?}" PATH="$PATH" INCIDENTS_REPO_ROOT="$inc" SOLEUR_DEFER_DRYRUN=0 bash "$HOOK" 2>/dev/null)"
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out" 2>/dev/null
}
TOTAL=$((TOTAL + 1))
if [[ "$(g3_monitor_decide "bash $FLIP_G3 f prd on")" == defer && "$(g3_monitor_decide "bash $FLIP_G3 f prd on --dry-run")" == allow ]]; then
  echo "PASS: I8 Monitor payload: write deferred, dry-run allowed"; PASS=$((PASS + 1))
else
  echo "FAIL: I8 Monitor payload not gated like Bash"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if jq -e '[.hooks.PreToolUse[] | select(.matcher=="Monitor") | .hooks[].command | select(test("prod-write-defer-gate"))] | length >= 1' "$REPO_ROOT_G3/.claude/settings.json" >/dev/null; then
  echo "PASS: I8 settings.json registers the gate for the Monitor tool"; PASS=$((PASS + 1))
else
  echo "FAIL: I8 settings.json does not register prod-write-defer-gate for Monitor"; FAIL=$((FAIL + 1))
fi

# H1 — the harness itself: a decider that always answers allow must fail a DEFER row.
TOTAL=$((TOTAL + 1))
if [[ "$(g3_decide /bin/true "bash $FLIP_G3 f prd on")" != defer ]]; then
  echo "PASS: I7-H1 a hook that prints nothing is not read as a defer"; PASS=$((PASS + 1))
else
  echo "FAIL: I7-H1 the harness reads a silent hook as a defer"; FAIL=$((FAIL + 1))
fi
rm -rf "$G3_SB"

# Anti-vacuity floor for the whole suite. Reports directly (printf + exit),
# never through the counters it backstops.
if [[ "$TOTAL" -lt 218 ]]; then
  printf 'FAIL: anti-vacuity floor: only %s assertions ran, floor is 218\n' "$TOTAL"
  exit 1
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]]
