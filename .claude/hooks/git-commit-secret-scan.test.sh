#!/usr/bin/env bash
# Tests for .claude/hooks/git-commit-secret-scan.sh.
# Deterministic — uses a temp git repo per test, no network, no real secrets.
set -euo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/git-commit-secret-scan.sh"
GITLEAKS_TOML="$REPO_ROOT/.gitleaks.toml"
pass=0; fail=0

# Owning trap for every per-case mktemp dir (lint-trap-tempfile-ownership,
# ADR-129). Functions still rm -rf eagerly; this is the death-mid-case net.
_TMP_DIRS=()
_cleanup_tmp_dirs() { ((${#_TMP_DIRS[@]} == 0)) || rm -rf "${_TMP_DIRS[@]}"; }
trap _cleanup_tmp_dirs EXIT
# One suite-level scratch root, registered HERE in the parent shell. Helpers that
# are called as `x=$(helper)` run in a subshell, so a `_TMP_DIRS+=` inside them
# is discarded and their dirs would leak; they create under this root instead.
SUITE_TMP=$(mktemp -d); _TMP_DIRS+=("$SUITE_TMP")

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

# --- Tool availability (#8266) ------------------------------------------------
# Arms that need a REAL gitleaks run only where one is runnable. A resolvable
# but unrunnable binary (an unpinned mise shim) used to turn these arms into
# verdicts about the rules; now they SKIP locally, naming the cause, and the
# suite FAILS under CI=true, where the runner is contracted to provide the tool
# (ADR-188; "a guard that can silently disarm must FAIL in CI and SKIP only
# locally"). The probe mirrors the hook's: timeout -> gtimeout -> bare, so a
# host without GNU timeout (stock macOS) is not misread as "unrunnable".
GL_OK=0
GL_REASON=""
_gl_probe() {
  local to=() errf rc=0
  if ! command -v gitleaks >/dev/null 2>&1; then GL_REASON="gitleaks not on PATH"; return; fi
  if command -v timeout >/dev/null 2>&1; then to=(timeout 10)
  elif command -v gtimeout >/dev/null 2>&1; then to=(gtimeout 10); fi
  errf=$(mktemp); _TMP_DIRS+=("$errf")
  ${to[@]+"${to[@]}"} gitleaks version >/dev/null 2>"$errf" || rc=$?
  if (( rc == 0 )); then GL_OK=1; return; fi
  GL_REASON="gitleaks not runnable (rc=$rc, $(printf '%q' "$(head -1 "$errf")"))"
}
_gl_probe

SKIPPED=()
_skip_arm() {  # $1 = arm label, $2 = reason
  SKIPPED+=("$1")
  echo "SKIP — git-commit-secret-scan.test: $1 — $2. CI pins gitleaks 8.24.2 — install that version or pin it in your version manager."
}
_needs_gl() {  # return 1 (after recording a skip) when no runnable gitleaks
  [[ "$GL_OK" == 1 ]] && return 0
  _skip_arm "$1" "$GL_REASON"
  return 1
}

# Build a PATH from symlinks to the tools the hook needs, WITHOUT gitleaks and
# WITHOUT timeout/gtimeout. Dropping one PATH entry cannot remove a tool that
# lives in /usr/bin beside git and jq, so the absent/no-timeout arms need this.
# $1 = gitleaks stub mode: absent | unrunnable | emptyreport | findings
_mk_stub_path() {
  local mode="$1" d t p
  d=$(mktemp -d "$SUITE_TMP/path.XXXXXX")
  for t in bash sh git jq mktemp grep cat dirname basename rm date flock sed awk tr \
           head tail cut wc sort env readlink realpath mkdir chmod touch id stat ls; do
    p=$(command -v "$t" 2>/dev/null) || continue
    [[ "$p" == /* ]] && ln -s "$p" "$d/$t"
  done
  # Stub bodies are quoted heredocs: they are DATA written into the stub, and the
  # redirect inside the findings stub is the stub's own, not a fixture write.
  case "$mode" in
    absent) ;;
    unrunnable)
      cat > "$d/gitleaks" <<'STUB'
#!/bin/sh
echo "mise ERROR No version is set for shim: gitleaks" >&2
exit 1
STUB
      ;;
    emptyreport)
      cat > "$d/gitleaks" <<'STUB'
#!/bin/sh
[ "$1" = version ] && { echo 8.24.2; exit 0; }
exit 2
STUB
      ;;
    findings)
      # Runnable; the scan writes a one-finding report to --report-path, exit 1.
      cat > "$d/gitleaks" <<'STUB'
#!/bin/sh
[ "$1" = version ] && { echo 8.24.2; exit 0; }
rp=""; while [ $# -gt 0 ]; do [ "$1" = --report-path ] && rp="$2"; shift; done
printf '%s' '[{"RuleID":"private-key","File":"leak.json","StartLine":1}]' > "$rp"
exit 1
STUB
      ;;
  esac
  [[ -f "$d/gitleaks" ]] && chmod +x "$d/gitleaks"
  printf '%s\n' "$d"
}

# Run the hook for `git commit` in $1 under PATH=$2. Sets OUT and ERR.
_run_stub() {
  local cwd="$1" pd="$2" errf payload
  errf=$(mktemp); _TMP_DIRS+=("$errf")
  payload=$(jq -nc '{tool_name: "Bash", tool_input: {command: "git commit -m x"}}')
  OUT=$(cd "$cwd" && env PATH="$pd" CLAUDE_PROJECT_DIR="$REPO_ROOT" "$pd/bash" "$HOOK" \
          <<<"$payload" 2>"$errf") || true
  ERR=$(cat "$errf")
}

# The last git-commit-secret-scan incident prefix the hook emitted.
_last_prefix() {
  local f="$SOLEUR_TEST_INCIDENT_ROOT/.claude/.rule-incidents.jsonl"
  [[ -f "$f" ]] || { echo "<no incidents file>"; return; }
  jq -r 'select(.rule_id == "git-commit-secret-scan") | .rule_text_prefix' "$f" | tail -1
}

_mk_repo_with_toml() {  # prints a temp repo with .gitleaks.toml + a staged file
  local tmp; tmp=$(mktemp -d "$SUITE_TMP/repo.XXXXXX")
  (
    cd "$tmp"
    git init -q -b feat
    git config user.email t@t; git config user.name t
    cp "$GITLEAKS_TOML" .gitleaks.toml
    echo "hello" > f.txt
    git add f.txt .gitleaks.toml
  )
  printf '%s\n' "$tmp"
}

# T11: gitleaks ABSENT → allow + "not installed" bypass, remediation names the pin.
t_absent_bypasses() {
  local repo pd; repo=$(_mk_repo_with_toml); pd=$(_mk_stub_path absent)
  _run_stub "$repo" "$pd"
  local p; p=$(_last_prefix)
  if [[ "$(_decision "$OUT")" == "allow" && "$p" == "gitleaks not installed"* \
        && "$ERR" == *"8.24.2"* && "$ERR" != *"brew install"* ]]; then
    _report "T11 gitleaks absent → allow, 'not installed' bypass, names 8.24.2" ok
  else
    _report "T11 gitleaks absent → allow, 'not installed' bypass, names 8.24.2" fail \
      "decision=$(_decision "$OUT") prefix=$p err=${ERR:0:160}"
  fi
}

# T12: gitleaks RESOLVES but CANNOT RUN → allow + distinct "unrunnable" bypass,
# never the "exited N but produced no findings report" (transient) branch.
t_unrunnable_bypasses() {
  local repo pd; repo=$(_mk_repo_with_toml); pd=$(_mk_stub_path unrunnable)
  _run_stub "$repo" "$pd"
  local p; p=$(_last_prefix)
  if [[ "$(_decision "$OUT")" == "allow" && "$p" == "gitleaks unrunnable"* \
        && "$ERR" == *"8.24.2"* && "$ERR" != *"produced no findings report"* ]]; then
    _report "T12 gitleaks unrunnable → allow, 'unrunnable' bypass, names 8.24.2" ok
  else
    _report "T12 gitleaks unrunnable → allow, 'unrunnable' bypass, names 8.24.2" fail \
      "decision=$(_decision "$OUT") prefix=$p err=${ERR:0:160}"
  fi
}

# T13: RUNNABLE gitleaks whose scan errors with no report → the transient branch.
t_runnable_empty_report() {
  local repo pd; repo=$(_mk_repo_with_toml); pd=$(_mk_stub_path emptyreport)
  _run_stub "$repo" "$pd"
  local p; p=$(_last_prefix)
  if [[ "$(_decision "$OUT")" == "allow" && "$p" == "gitleaks exit="* ]]; then
    _report "T13 runnable gitleaks, scan error, no report → allow via 'exit=' bypass" ok
  else
    _report "T13 runnable gitleaks, scan error, no report → allow via 'exit=' bypass" fail \
      "decision=$(_decision "$OUT") prefix=$p"
  fi
}

# T14: a WORKING gitleaks on a host WITHOUT timeout/gtimeout (stock macOS) must
# still scan — the probe may not treat a missing `timeout` as an unrunnable tool.
t_no_timeout_still_scans() {
  local repo pd; repo=$(_mk_repo_with_toml); pd=$(_mk_stub_path findings)
  if [[ -e "$pd/timeout" || -e "$pd/gtimeout" ]]; then
    _report "T14 no-timeout host still scans" fail "fixture PATH carries a timeout binary"
    return
  fi
  _run_stub "$repo" "$pd"
  if [[ "$(_decision "$OUT")" == "deny" ]]; then
    _report "T14 working gitleaks + no timeout binary → scan runs (deny on finding)" ok
  else
    _report "T14 working gitleaks + no timeout binary → scan runs (deny on finding)" fail \
      "decision=$(_decision "$OUT") prefix=$(_last_prefix) err=${ERR:0:160}"
  fi
}

# T15/T16: a user's colour config must not blind the scan (measured: gitleaks
# git --staged returns 0 findings on a staged key under color.ui/color.diff=always).
_t_colour_denies() {  # $1 = config key
  local key="$1" label="T15/16 staged PEM denies under $1=always"
  _needs_gl "$label" || return 0
  local tmp; tmp=$(mktemp -d); _TMP_DIRS+=("$tmp")
  (
    cd "$tmp"
    git init -q -b main
    git config user.email t@t; git config user.name t
    cp "$GITLEAKS_TOML" .gitleaks.toml
    pem=$(_mk_pem "t15_colour_${key//./_}_syntheticpayload")
    jq -n --arg p "$pem" '{key: $p}' > leakc.json
    git add leakc.json .gitleaks.toml
  )
  local payload out
  payload=$(jq -nc '{tool_name: "Bash", tool_input: {command: "git commit -m x"}}')
  out=$(cd "$tmp" && env GIT_CONFIG_COUNT=1 "GIT_CONFIG_KEY_0=$key" GIT_CONFIG_VALUE_0=always \
          CLAUDE_PROJECT_DIR="$REPO_ROOT" bash "$HOOK" <<<"$payload")
  if [[ "$(_decision "$out")" == "deny" ]]; then
    _report "$label" ok
  else
    _report "$label" fail "decision=$(_decision "$out")"
  fi
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
  _needs_gl "T4 clean staged content → allow" || return 0
  local tmp; tmp=$(mktemp -d); _TMP_DIRS+=("$tmp")
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
  _needs_gl "T5 PEM in staged JSON → deny" || return 0
  local tmp; tmp=$(mktemp -d); _TMP_DIRS+=("$tmp")
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
  _needs_gl "T6 git commit --amend triggers scan" || return 0
  local tmp; tmp=$(mktemp -d); _TMP_DIRS+=("$tmp")
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
  _needs_gl "T7 chained && git commit triggers scan" || return 0
  local tmp; tmp=$(mktemp -d); _TMP_DIRS+=("$tmp")
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
  _needs_gl "T9 deny reason cites learning file" || return 0
  local tmp; tmp=$(mktemp -d); _TMP_DIRS+=("$tmp")
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

# T10: Devin wire name `exec` reaches the gated scan (kind map, #8205).
t_devin_exec_triggers_scan() {
  _needs_gl "T10 Devin exec reaches scan" || return 0
  local tmp; tmp=$(mktemp -d); _TMP_DIRS+=("$tmp")
  (
    cd "$tmp"
    git init -q -b main
    git config user.email t@t; git config user.name t
    cp "$GITLEAKS_TOML" .gitleaks.toml
    pem=$(_mk_pem "t10_devinexecsyntheticpayload")
    jq -n --arg p "$pem" '{key: $p}' > leak5.json
    git add leak5.json .gitleaks.toml
  )
  local out; out=$(_run "$tmp" "exec" "git commit -m 'add'")
  if [[ "$(_decision "$out")" == "deny" ]]; then
    _report "T10 Devin exec tool_name reaches scan → deny" ok
  else
    _report "T10 Devin exec tool_name reaches scan → deny" fail "$(_decision "$out")"
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
t_devin_exec_triggers_scan
t_absent_bypasses
t_unrunnable_bypasses
t_runnable_empty_report
t_no_timeout_still_scans
_t_colour_denies color.ui
_t_colour_denies color.diff

echo "=== $pass passed, $fail failed, ${#SKIPPED[@]} arm(s) skipped ==="
if (( ${#SKIPPED[@]} > 0 )); then
  printf '  skipped: %s\n' "${SKIPPED[@]}"
  if [[ "${CI:-}" == "true" ]]; then
    echo "CI=true: ${#SKIPPED[@]} arm(s) could not run because gitleaks is not runnable on this runner — a FAILURE, not a skip (the runner must provide gitleaks 8.24.2)." >&2
    exit 1
  fi
fi
[[ "$fail" -eq 0 ]]
