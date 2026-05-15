#!/usr/bin/env bash
# Fixture-based tests for prod-write-defer-gate.sh. Synthesized fixtures
# (TEST-FIXTURE-NOT-REAL token) verify the inline-regex-array gate at the
# anchor + match + bypass + mode + fail-closed axes.
#
# Isolation pattern matches ship-unpushed-commits-gate.test.sh / pre-merge-
# rebase.test.sh: per-test mktemp work-tree + incidents root; INCIDENTS_REPO_ROOT
# redirects the .rule-incidents.jsonl off the operator's real sink.

set -uo pipefail
# -e omitted: tests must report FAIL when the hook misbehaves, not abort the
# whole run. Final exit code is driven by $FAIL.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/prod-write-defer-gate.sh"

PASS=0
FAIL=0
TOTAL=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }

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
assert_match_dry "A3 doppler -c prd_terraform set"    "doppler secrets set FOO=bar --config prd_terraform"           "prod-write-defer-doppler-prd-secrets"

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
assert_match_dry "B7 env-prefixed doppler prd"        "DOPPLER_CONFIG=prd_terraform doppler secrets set X=Y --config prd_terraform" "prod-write-defer-doppler-prd-secrets"
assert_match_dry "B8 short-flag doppler -c prd"       "doppler secrets set FOO=bar -c prd"                           "prod-write-defer-doppler-prd-secrets"
assert_match_dry "B9 tofu apply"                      "tofu apply"                                                   "prod-write-defer-terraform-apply"
assert_match_dry "B10 push master alias"              "git push origin master"                                       "prod-write-defer-git-push-main"

# ============================================================
# Tier C: adjacent non-matches (must NOT fire)
# ============================================================
echo "--- Tier C: adjacent non-matches ---"
assert_nomatch "C1 push feat branch (not main)"          "git push origin feat-foo"
assert_nomatch "C2 push feat-main-update (substring)"    "git push origin feat-main-update"
assert_nomatch "C3 terraform plan (not apply)"           "terraform plan"
assert_nomatch "C4 terraform apply substring in echo"    "echo 'hint: try terraform apply later'"
assert_nomatch "C5 doppler --config prd-staging"         "doppler secrets set FOO=bar --config prd-staging"
assert_nomatch "C6 doppler --config dev"                 "doppler secrets set FOO=bar --config dev"
assert_nomatch "C7 git pull origin main"                 "git pull origin main"
assert_nomatch "C8 echo gh pr merge example"             "echo 'gh pr merge example'"

# ============================================================
# Tier D: enforce-mode wrapped envelope + decision value
# ============================================================
echo "--- Tier D: enforce mode (wrapped defer envelope) ---"
assert_match_enforce "D1 enforce push main"            "git push origin main"                                         "prod-write-defer-git-push-main"
assert_match_enforce "D2 enforce terraform apply"      "terraform apply -auto-approve"                                "prod-write-defer-terraform-apply"
assert_match_enforce "D3 enforce doppler prd"          "doppler secrets set FOO=bar --config prd_terraform"           "prod-write-defer-doppler-prd-secrets"

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

echo ""
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]]
