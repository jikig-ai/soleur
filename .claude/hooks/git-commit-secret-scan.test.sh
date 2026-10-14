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
# shellcheck source=../../plugins/soleur/test/lib/gitleaks-probe.sh
source "$REPO_ROOT/plugins/soleur/test/lib/gitleaks-probe.sh"
gl_probe

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
  # Watermark the incident journal BEFORE the hook appends to it, so _last_prefix
  # reads only THIS invocation's rows. A suite-global `tail -1` made the arms
  # order-coupled: they passed only because each happened to expect a different
  # prefix than its predecessor left, so inserting a case between them could make
  # an arm assert on a row it did not produce.
  _JOURNAL_MARK=$(wc -l < "$SOLEUR_TEST_INCIDENT_ROOT/.claude/.rule-incidents.jsonl" 2>/dev/null || echo 0)
  payload=$(jq -nc '{tool_name: "Bash", tool_input: {command: "git commit -m x"}}')
  OUT=$(cd "$cwd" && env PATH="$pd" CLAUDE_PROJECT_DIR="$REPO_ROOT" "$pd/bash" "$HOOK" \
          <<<"$payload" 2>"$errf") || true
  ERR=$(cat "$errf")
}

# The last git-commit-secret-scan incident prefix the hook emitted.
# The last git-commit-secret-scan incident prefix THIS invocation emitted — rows
# at or below the watermark _run_stub recorded are a previous case's and ignored.
_last_prefix() {
  local f="$SOLEUR_TEST_INCIDENT_ROOT/.claude/.rule-incidents.jsonl"
  [[ -f "$f" ]] || { echo "<no incidents file>"; return; }
  tail -n "+$(( ${_JOURNAL_MARK:-0} + 1 ))" "$f" \
    | jq -r 'select(.rule_id | startswith("git-commit-secret-scan")) | .rule_text_prefix' \
    | tail -1
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

# T17/T18: a `-diff` gitattribute removes the `+` lines entirely, so `gitleaks git`
# scans clean no matter how colour is pinned (measured: rc=1/1 finding -> rc=0/0
# findings). Neither core.attributesFile=/dev/null nor GIT_ATTR_NOSYSTEM=1 closes
# it — both govern the GLOBAL/SYSTEM files while `.git/info/attributes` is per-repo.
# T17 is the regression row; T18 is the must-ALLOW control proving the guard is not
# simply denying everything, which an absence-only row could not distinguish.
_t_nodiff_attr() {  # $1 = withsecret|clean ; $2 = expected decision
  # Split declarations: `local a=$1 b="...$a..."` can read $a as unset under
  # `set -u`, because `local` may declare every name before assigning any.
  local mode="$1"
  local want="$2"
  local label="T17/18 staged '-diff' file ($mode) -> $want"
  _needs_gl "$label" || return 0
  local tmp; tmp=$(mktemp -d); _TMP_DIRS+=("$tmp")
  (
    cd "$tmp"
    git init -q -b main
    git config user.email t@t; git config user.name t
    cp "$GITLEAKS_TOML" .gitleaks.toml
    if [[ "$mode" == withsecret ]]; then
      pem=$(_mk_pem "t17_nodiff_syntheticpayload")
      jq -n --arg p "$pem" '{key: $p}' > hidden.json
    else
      printf '{"note":"nothing secret here"}\n' > hidden.json
    fi
    mkdir -p .git/info
    # Untracked and unreviewable — the realistic shape of this bypass.
    echo 'hidden.json -diff' > .git/info/attributes
    git add hidden.json .gitleaks.toml
  )
  # FIXTURE CONTROL: the attribute must actually blind the plain staged scan, or
  # T17 would pass for the wrong reason (a guard that never had to fire).
  if [[ "$mode" == withsecret ]]; then
    local plain_rc=0
    ( cd "$tmp" && gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1 \
        --report-format json --report-path "$tmp/plain.json" >/dev/null 2>&1 ) || plain_rc=$?
    if [[ "$plain_rc" -ne 0 ]]; then
      _report "$label" fail "FIXTURE BROKEN: the -diff attribute did not blind the plain staged scan (rc=$plain_rc), so this row proves nothing"
      return 0
    fi
  fi
  local payload out
  payload=$(jq -nc '{tool_name: "Bash", tool_input: {command: "git commit -m x"}}')
  out=$(cd "$tmp" && CLAUDE_PROJECT_DIR="$REPO_ROOT" bash "$HOOK" <<<"$payload")
  if [[ "$(_decision "$out")" == "$want" ]]; then
    _report "$label" ok
  else
    _report "$label" fail "decision=$(_decision "$out") want=$want"
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
_t_nodiff_attr withsecret deny
_t_nodiff_attr clean allow

# T19: the CI fail-on-skip contract, asserted against the epilogue's REAL BYTES.
# That contract is the only thing stopping 8 arms from reading as green on a
# runner without gitleaks, and nothing asserted it — a refactor of the tail, or a
# `set -e` interaction returning early, would drop it silently and the shard would
# stay green. The block is extracted between the markers below and driven through
# a three-row truth table, so a mutation to the shipped code (not a copy) reds.
_t_ci_contract() {
  local body rc
  body=$(awk '/^# >>> ci-contract-epilogue$/{f=1;next} /^# <<< ci-contract-epilogue$/{f=0} f' "${BASH_SOURCE[0]}")
  if [[ -z "${body//[[:space:]]/}" ]]; then
    _report "T19 CI fail-on-skip contract" fail "epilogue markers matched nothing — the extraction is broken, not the contract"
    return
  fi
  # row 1: CI=true AND skips present -> MUST exit 1
  rc=0; ( set +e; eval 'SKIPPED_ARMS=(x); CI=true; pass=1; fail=0'"
$body" ) >/dev/null 2>&1 || rc=$?
  if [[ "$rc" != 1 ]]; then
    _report "T19 CI=true + skips exits 1" fail "rc=$rc"; return
  fi
  # row 2: skips present but NOT CI -> must NOT exit 1 (local skip stays a skip)
  rc=0; ( set +e; eval 'SKIPPED_ARMS=(x); unset CI; pass=1; fail=0'"
$body" ) >/dev/null 2>&1 || rc=$?
  if [[ "$rc" == 1 ]]; then
    _report "T19 local skip does not fail" fail "rc=$rc"; return
  fi
  # row 3: CI=true but NO skips -> must NOT exit 1
  rc=0; ( set +e; eval 'SKIPPED_ARMS=(); CI=true; pass=1; fail=0'"
$body" ) >/dev/null 2>&1 || rc=$?
  if [[ "$rc" == 1 ]]; then
    _report "T19 CI=true with no skips does not fail" fail "rc=$rc"; return
  fi
  _report "T19 CI fail-on-skip contract (3-row truth table on the real epilogue)" ok
}
# Control for the journal watermark: prove _JOURNAL_MARK actually ADVANCES across
# invocations. Without this the scoping could be inert (a permanently-0 mark is
# byte-identical to the old suite-global `tail -1`) and every arm would still pass
# — inert machinery that reads as a fix.
_t_journal_watermark() {
  local first="${_JOURNAL_MARK:-unset}" repo pd
  if [[ "$first" == unset ]]; then
    _report "T20 journal watermark advances" fail "_JOURNAL_MARK never set — _run_stub did not record it"
    return
  fi
  repo=$(_mk_repo_with_toml); pd=$(_mk_stub_path absent)
  _run_stub "$repo" "$pd"
  local second="${_JOURNAL_MARK:-unset}"
  if [[ "$second" == unset || "$second" -le "$first" ]]; then
    _report "T20 journal watermark advances" fail "mark did not advance ($first -> $second); _last_prefix is effectively suite-global"
  else
    _report "T20 journal watermark advances ($first -> $second)" ok
  fi
}
_t_journal_watermark

_t_ci_contract

# >>> ci-contract-epilogue
echo "=== $pass passed, $fail failed, ${#SKIPPED_ARMS[@]} arm(s) skipped ==="
if (( ${#SKIPPED_ARMS[@]} > 0 )); then
  printf '  skipped: %s\n' "${SKIPPED_ARMS[@]}"
  if [[ "${CI:-}" == "true" ]]; then
    echo "CI=true: ${#SKIPPED_ARMS[@]} arm(s) could not run because gitleaks is not runnable on this runner — a FAILURE, not a skip (the runner must provide gitleaks 8.24.2)." >&2
    exit 1
  fi
fi
# <<< ci-contract-epilogue
[[ "$fail" -eq 0 ]]
