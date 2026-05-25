#!/usr/bin/env bash
# Tests for .claude/hooks/git-commit-secret-scan.sh.
# Deterministic — uses a temp git repo per test, no network, no real secrets.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/git-commit-secret-scan.sh"
GITLEAKS_TOML="$REPO_ROOT/.gitleaks.toml"
pass=0; fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1))
    echo "[ok] $label"
  else
    fail=$((fail + 1))
    echo "[FAIL] $label $detail" >&2
  fi
}

# Build a payload string for the hook and capture its JSON decision.
# Each case sets up a temp git repo with its own staged state, invokes
# the hook in that CWD, and inspects the permissionDecision.
_run() {
  local cwd="$1" tool="$2" command="$3"
  local payload
  payload=$(jq -nc \
    --arg t "$tool" \
    --arg c "$command" \
    '{tool_name: $t, tool_input: {command: $c}}')
  (cd "$cwd" && CLAUDE_PROJECT_DIR="$REPO_ROOT" bash "$HOOK" <<<"$payload")
}

_decision() {
  echo "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

_reason() {
  echo "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'
}

# Build a synthetic PEM at runtime. The header/footer literals are split
# across separate printf arguments so this source file never contains the
# contiguous bytes `-----BEGIN RSA PRIVATE KEY-----` — the project's
# CI-side gitleaks scan would otherwise flag this test file as a leak.
# At runtime, printf assembles the canonical PEM shape that the hook's
# own gitleaks invocation must match.
_mk_pem() {
  local body="${1:-syntheticbase64padding1234567890abcdefghijklmnopqrstuvwxyzABCDEF}"
  printf -- '%s%s%s\n%s\n%s%s%s' \
    '-----' 'BEGIN' ' RSA PRIVATE KEY-----' \
    "MIIEowIBAAKCAQEA${body}" \
    '-----' 'END' ' RSA PRIVATE KEY-----'
}

# T1: non-Bash tool → allow.
t_non_bash_tool() {
  local out; out=$(_run "$REPO_ROOT" "Write" "irrelevant")
  if [[ "$(_decision "$out")" == "allow" ]]; then
    _report "T1 non-Bash tool → allow" ok
  else
    _report "T1 non-Bash tool → allow" fail "$(_decision "$out")"
  fi
}

# T2: Bash command that isn't `git commit` → allow.
t_bash_non_commit() {
  local out; out=$(_run "$REPO_ROOT" "Bash" "git status")
  if [[ "$(_decision "$out")" == "allow" ]]; then
    _report "T2 Bash 'git status' → allow" ok
  else
    _report "T2 Bash 'git status' → allow" fail "$(_decision "$out")"
  fi
}

# T3: substring-only `git commit` in a different context → allow.
t_substring_not_match() {
  local out; out=$(_run "$REPO_ROOT" "Bash" 'echo "the git commit example"')
  if [[ "$(_decision "$out")" == "allow" ]]; then
    _report "T3 substring 'git commit' inside echo → allow" ok
  else
    _report "T3 substring 'git commit' inside echo → allow" fail "$(_decision "$out")"
  fi
}

# T4: clean staged content + git commit → allow.
t_clean_commit() {
  local tmp; tmp=$(mktemp -d)
  (
    cd "$tmp"
    git init -q -b main
    git config user.email t@t; git config user.name t
    cp "$GITLEAKS_TOML" .gitleaks.toml
    echo "hello world" > clean.txt
    git add clean.txt .gitleaks.toml
  )
  local out; out=$(_run "$tmp" "Bash" "git commit -m 'add clean.txt'")
  if [[ "$(_decision "$out")" == "allow" ]]; then
    _report "T4 clean staged content → allow" ok
  else
    _report "T4 clean staged content → allow" fail "$(_decision "$out")"
  fi
  rm -rf "$tmp"
}

# T5: staged content with synthetic PEM body → deny.
# We construct an unmistakable RSA private-key header that gitleaks'
# default-pack `private-key` rule (or similar) catches. The PEM is fully
# synthetic — random base64 padding, no real keypair.
t_pem_blocks_commit() {
  local tmp; tmp=$(mktemp -d)
  (
    cd "$tmp"
    git init -q -b main
    git config user.email t@t; git config user.name t
    cp "$GITLEAKS_TOML" .gitleaks.toml
    pem=$(_mk_pem "t5_syntheticpayload_$(date +%s)")
    jq -n --arg p "$pem" '{variables: {private_key: {value: $p}}}' > leak.json
    git add leak.json .gitleaks.toml
  )
  local out; out=$(_run "$tmp" "Bash" "git commit -m 'add fixture'")
  local d; d=$(_decision "$out")
  if [[ "$d" == "deny" ]]; then
    local r; r=$(_reason "$out")
    if [[ "$r" == *"gitleaks"* ]] && [[ "$r" == *"leak.json"* ]]; then
      _report "T5 PEM in staged JSON → deny (names file)" ok
    else
      _report "T5 PEM in staged JSON → deny (names file)" fail "reason: $r"
    fi
  else
    _report "T5 PEM in staged JSON → deny" fail "decision=$d"
  fi
  rm -rf "$tmp"
}

# T6: `git commit --amend` triggers the scan (same regex must match `--amend`).
t_amend_triggers_scan() {
  local tmp; tmp=$(mktemp -d)
  (
    cd "$tmp"
    git init -q -b main
    git config user.email t@t; git config user.name t
    cp "$GITLEAKS_TOML" .gitleaks.toml
    echo "initial" > seed.txt
    git add seed.txt .gitleaks.toml
    git commit -q -m "seed"
    pem=$(_mk_pem "t6_amendsyntheticpayload")
    jq -n --arg p "$pem" '{key: $p}' > leak2.json
    git add leak2.json
  )
  local out; out=$(_run "$tmp" "Bash" "git commit --amend --no-edit")
  if [[ "$(_decision "$out")" == "deny" ]]; then
    _report "T6 'git commit --amend' triggers scan → deny on PEM" ok
  else
    _report "T6 'git commit --amend' triggers scan → deny on PEM" fail "$(_decision "$out")"
  fi
  rm -rf "$tmp"
}

# T7: chained `&& git commit` triggers the scan.
t_chained_commit() {
  local tmp; tmp=$(mktemp -d)
  (
    cd "$tmp"
    git init -q -b main
    git config user.email t@t; git config user.name t
    cp "$GITLEAKS_TOML" .gitleaks.toml
    pem=$(_mk_pem "t7_chainedsyntheticpayload")
    jq -n --arg p "$pem" '{key: $p}' > leak3.json
    git add leak3.json .gitleaks.toml
  )
  local out; out=$(_run "$tmp" "Bash" "git status && git commit -m 'add'")
  if [[ "$(_decision "$out")" == "deny" ]]; then
    _report "T7 chained '... && git commit' triggers scan → deny" ok
  else
    _report "T7 chained '... && git commit' triggers scan → deny" fail "$(_decision "$out")"
  fi
  rm -rf "$tmp"
}

# T8: git-commit-tree / git-commit-graph are NOT matched (boundary check).
t_commit_tree_not_matched() {
  local out; out=$(_run "$REPO_ROOT" "Bash" "git commit-tree abc123")
  if [[ "$(_decision "$out")" == "allow" ]]; then
    _report "T8 'git commit-tree' NOT matched → allow" ok
  else
    _report "T8 'git commit-tree' NOT matched → allow" fail "$(_decision "$out")"
  fi
}

# T9: deny reason references the terraform-show-json learning file.
t_reason_cites_learning() {
  local tmp; tmp=$(mktemp -d)
  (
    cd "$tmp"
    git init -q -b main
    git config user.email t@t; git config user.name t
    cp "$GITLEAKS_TOML" .gitleaks.toml
    pem=$(_mk_pem "t9_citelearningsyntheticpayload")
    jq -n --arg p "$pem" '{key: $p}' > leak4.json
    git add leak4.json .gitleaks.toml
  )
  local out; out=$(_run "$tmp" "Bash" "git commit -m 'add'")
  local r; r=$(_reason "$out")
  if [[ "$r" == *"terraform-show-json"* ]] || [[ "$r" == *"2026-05-25-terraform-show-json-leaks"* ]]; then
    _report "T9 deny reason cites learning file" ok
  else
    _report "T9 deny reason cites learning file" fail "reason: ${r:0:120}"
  fi
  rm -rf "$tmp"
}

t_non_bash_tool
t_bash_non_commit
t_substring_not_match
t_clean_commit
t_pem_blocks_commit
t_amend_triggers_scan
t_chained_commit
t_commit_tree_not_matched
t_reason_cites_learning

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
