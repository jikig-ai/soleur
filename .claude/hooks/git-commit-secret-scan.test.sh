#!/usr/bin/env bash
# shellcheck disable=SC2016  # single-quoted command text under test is data, never expanded
# Tests for .claude/hooks/git-commit-secret-scan.sh.
# Deterministic — uses a temp git repo per test, no network, no real secrets.
set -euo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

# A hook, `git rebase --exec` or an exported shell can hand this suite GIT_DIR / GIT_INDEX_FILE;
# either beats cwd and `git -C`, so every fixture below would write into the CALLER's
# repository. Clear them before anything runs (T39 sets GIT_DIR on the hook call itself).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_PREFIX

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
    --arg w "$cwd" \
    '{tool_name: $t, cwd: $w, tool_input: {command: $c}}')
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
# $1 = gitleaks stub mode: absent | unrunnable | emptyreport | findings | clean | byroot
# $2 = perl links perl as well (the lexer needs it; the default stub PATH has none)
_mk_stub_path() {
  local mode="$1" d t p extra=""
  [[ "${2:-}" == perl ]] && extra=perl
  d=$(mktemp -d "$SUITE_TMP/path.XXXXXX")
  for t in bash sh git jq mktemp grep cat dirname basename rm date flock sed awk tr \
           head tail cut wc sort env readlink realpath mkdir chmod touch id stat ls $extra; do
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
    clean)
      # Runnable; the scan finds nothing (exit 0, no report).
      cat > "$d/gitleaks" <<'STUB'
#!/bin/sh
[ "$1" = version ] && { echo 8.24.2; exit 0; }
exit 0
STUB
      ;;
    byroot)
      # Runnable; fails with no report ONLY when run inside $GL_STUB_FAIL_DIR, and
      # delegates to the real binary ($GL_REAL) everywhere else.
      cat > "$d/gitleaks" <<'STUB'
#!/bin/sh
[ "$1" = version ] && { echo 8.24.2; exit 0; }
case "$PWD" in *"$GL_STUB_FAIL_DIR") exit 2 ;; esac
exec "$GL_REAL" "$@"
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
  payload=$(jq -nc --arg w "$cwd" '{tool_name: "Bash", cwd: $w, tool_input: {command: "git commit -m x"}}')
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
  payload=$(jq -nc --arg w "$tmp" '{tool_name: "Bash", cwd: $w, tool_input: {command: "git commit -m x"}}')
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
  payload=$(jq -nc --arg w "$tmp" '{tool_name: "Bash", cwd: $w, tool_input: {command: "git commit -m x"}}')
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

# ---- #10609: the scan targets the repository the commit names -----------------
# The incident (2026-10-19): the session cwd was a core.bare=true root with no
# .gitleaks.toml, the commit was `cd <worktree> && git commit`, and the hook scanned
# nothing ("bypass .gitleaks.toml absent"). Every arm below runs the hook with the
# process cwd AND the payload .cwd set to that bare root unless stated.

# Run the hook with an arbitrary command. $1 = process cwd, $2 = command, $3 = a
# _mk_stub_path directory (optional). PAYLOAD_CWD overrides the payload .cwd; RUN_ENV
# (array of NAME=value) is exported to the hook; HOOK_OVERRIDE swaps the script. The
# command rides jq --arg and the hook's stdin only — it is never evaluated here.
# Sets OUT and ERR.
RUN_ENV=()
_run_cmd() {
  local cwd="$1" command="$2" pd="${3:-}" payload errf hook="${HOOK_OVERRIDE:-$HOOK}"
  errf=$(mktemp "$SUITE_TMP/err.XXXXXX")
  _JOURNAL_MARK=$(wc -l < "$SOLEUR_TEST_INCIDENT_ROOT/.claude/.rule-incidents.jsonl" 2>/dev/null || echo 0)
  payload=$(jq -nc --arg c "$command" --arg w "${PAYLOAD_CWD:-$cwd}" \
    '{tool_name: "Bash", cwd: $w, tool_input: {command: $c}}')
  if [[ -n "$pd" ]]; then
    OUT=$(cd "$cwd" && env PATH="$pd" ${RUN_ENV[@]+"${RUN_ENV[@]}"} CLAUDE_PROJECT_DIR="$REPO_ROOT" \
            "$pd/bash" "$hook" <<<"$payload" 2>"$errf") || true
  else
    OUT=$(cd "$cwd" && env ${RUN_ENV[@]+"${RUN_ENV[@]}"} CLAUDE_PROJECT_DIR="$REPO_ROOT" \
            bash "$hook" <<<"$payload" 2>"$errf") || true
  fi
  ERR=$(cat "$errf")
}

# _expect <label> <process cwd> <command> <allow|deny> [substring | !substring ...]
# A leading ! on a substring means the reason must NOT contain it. EXPECT_PD names a
# _mk_stub_path directory. The decision is compared exactly; OUT/ERR stay set.
_expect() {
  local label="$1" cwd="$2" cmd="$3" want="$4" d r s; shift 4
  _run_cmd "$cwd" "$cmd" "${EXPECT_PD:-}"
  d=$(_decision "$OUT"); r=$(_reason "$OUT")
  for s in "$@"; do
    if [[ "$s" == '!'* ]]; then
      if [[ "$r" == *"${s#!}"* ]]; then
        _report "$label" fail "reason must not contain '${s#!}' (decision=$d reason=${r:0:240})"; return 0
      fi
    elif [[ "$r" != *"$s"* ]]; then
      _report "$label" fail "reason lacks '$s' (decision=$d reason=${r:0:240})"; return 0
    fi
  done
  if [[ "$d" == "$want" ]]; then
    _report "$label" ok
  else
    _report "$label" fail "decision=$d want=$want reason=${r:0:240} err=${ERR:0:160}"
  fi
}

# The incident topology: a core.bare=true root with NO .gitleaks.toml, plus a linked
# worktree carrying the toml. $1 = leak (a staged fake PEM, assembled by _mk_pem) or
# clean. Sets FX_ROOT and FX_WT to PHYSICAL paths (git reports toplevels physically).
_mk_bare_root_with_worktree() {
  local mode="$1" root
  root=$(mktemp -d "$SUITE_TMP/bare.XXXXXX")
  (
    cd "$root"
    git init -q -b main
    git config user.email t@t; git config user.name t
    echo seed > seed.txt; git add seed.txt
    git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m seed
    git config core.bare true
    git worktree add -q .worktrees/wt -b wtb
    cd .worktrees/wt
    cp "$GITLEAKS_TOML" .gitleaks.toml
    if [[ "$mode" == leak ]]; then
      jq -n --arg p "$(_mk_pem "t5_bareroot_syntheticpayload_$(date +%s)")" \
        '{variables: {private_key: {value: $p}}}' > leak.json
      git add leak.json .gitleaks.toml
    else
      echo hello > f.txt; git add f.txt .gitleaks.toml
    fi
  )
  FX_ROOT=$(cd "$root" && pwd -P); FX_WT=$(cd "$root/.worktrees/wt" && pwd -P)
}

# A plain repo (own .gitleaks.toml) with a staged fake PEM.
_mk_leaky_repo() {
  local tmp; tmp=$(mktemp -d "$SUITE_TMP/leaky.XXXXXX")
  (
    cd "$tmp"
    git init -q -b main
    git config user.email t@t; git config user.name t
    cp "$GITLEAKS_TOML" .gitleaks.toml
    jq -n --arg p "$(_mk_pem "t5_leakyrepo_syntheticpayload_$(date +%s)")" \
      '{variables: {private_key: {value: $p}}}' > leak.json
    git add leak.json .gitleaks.toml
  )
  (cd "$tmp" && pwd -P)
}

# FIXTURE CONTROL: a plain staged scan inside the leaky worktree must report the
# finding, or every deny below would be passing for a reason that is not the hook's.
_fx_control() {
  local rc=0 rp; rp=$(mktemp "$SUITE_TMP/plain.XXXXXX")
  ( cd "$1" && gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1 \
      --report-format json --report-path "$rp" >/dev/null 2>&1 ) || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    _report "T21-T43 fixture control" fail "FIXTURE BROKEN: plain gitleaks found nothing in $1 (rc=$rc), so no deny below proves anything"
    return 1
  fi
}

_t_target_resolution() {
  _needs_gl "T21-T43 target resolution" || return 0
  local R W R2 W2 A B pd cp s1 s2 cmd
  _mk_bare_root_with_worktree leak; R="$FX_ROOT"; W="$FX_WT"
  _mk_bare_root_with_worktree clean; R2="$FX_ROOT"; W2="$FX_WT"
  _fx_control "$W" || return 0
  A=$(_mk_repo_with_toml); B=$(_mk_leaky_repo)

  _expect "T21 incident replay: bare-root cwd, 'cd <wt> && git commit' → deny naming the leak and the worktree" \
    "$R" "cd $W && git commit -m x" deny "leak.json" "$W"
  _expect "T22 'git -C <wt> commit' → deny (detection must see global options)" \
    "$R" "git -C $W commit -m x" deny "leak.json"
  _expect "T23 no cd, bare root → allow via the legacy '.gitleaks.toml absent' bypass (old behaviour unchanged)" \
    "$R" "git commit -m x" allow
  if [[ "$(_last_prefix)" == ".gitleaks.toml absent"* ]]; then
    _report "T23b the legacy bypass row is still '.gitleaks.toml absent'" ok
  else
    _report "T23b the legacy bypass row is still '.gitleaks.toml absent'" fail "prefix=$(_last_prefix)"
  fi
  _expect "T24 relative target 'cd .worktrees/wt' → deny" \
    "$R" "cd .worktrees/wt && git commit -m x" deny "leak.json"

  _expect "T25a leaky repo is the SECOND target (cd A && cd wt)" \
    "$R" "cd $A && cd $W && git commit -m x" deny "leak.json" "$W"
  _expect "T25b leaky repo is the SECOND target (git -C A status && git -C wt commit)" \
    "$R" "git -C $A status && git -C $W commit -m x" deny "leak.json" "$W"
  _expect "T25c leaky repo is the FIRST target (cd wt && cd A)" \
    "$R" "cd $W && cd $A && git commit -m x" deny "leak.json" "$W"
  _expect "T26 a -C on a non-commit command does not displace the cwd repo (fallback roots stay unioned)" \
    "$B" "git -C $A status; git commit -m x" deny "leak.json" "$B"

  # Each fallback root is its own contract: process cwd and payload .cwd can differ.
  _expect "T26b the PROCESS-cwd root is scanned even when the command names a clean target" \
    "$B" "git -C $A commit -m x" deny "leak.json"
  PAYLOAD_CWD="$B" _expect "T26c the PAYLOAD-cwd root is scanned even when the command names a clean target" \
    "$A" "git -C $A commit -m x" deny "leak.json"
  PAYLOAD_CWD="$A" _expect "T26d the PROCESS-cwd root is scanned when the payload .cwd differs" \
    "$B" "git -C $A commit -m x" deny "leak.json"
  _expect "T43d must-ALLOW: a loose-match non-commit in a LEAKY repo is not scanned (the lexer must confirm a commit)" \
    "$B" "git --no-pager log --grep commit" allow
  _expect "T43e must-ALLOW: quoted 'git -C x commit' in a LEAKY repo is data" \
    "$B" 'echo "git -C x commit"' allow

  local frag
  for s in 'expansion::cd "$WT" && git commit -m x' \
           'expansion::cd $WT && git commit -m x' \
           'expansion::cd "$(pwd)/wt" && git commit -m x' \
           'expansion::cd `pwd` && git commit -m x' \
           'goes to a directory the walker cannot see::cd - && git commit -m x' \
           'uses ~::cd ~someone && git commit -m x' \
           'uses ~::cd ~/wt && git commit -m x' \
           'glob or brace pattern::cd .worktrees/* && git commit -m x'; do
    frag="${s%%::*}"; cmd="${s#*::}"
    _expect "T27 non-literal target is DENIED, never skipped (cause: $frag): $cmd" \
      "$R" "$cmd" deny "cannot determine" "NOT scanned" "its own command" "git worktree list" "$frag"
  done
  _expect "T27c the deny text names the forms that do not work" \
    "$R" 'cd "$WT" && git commit -m x' deny '$(...)' "GIT_DIR" "bash -c"

  _expect "T29 bash -c 'cd <wt> && git commit' → deny" \
    "$R" "bash -c 'cd $W && git commit -m x'" deny "leak.json"
  _expect "T29b the commit hidden in a variable (eval \"\$CMD\") → deny" \
    "$R" "CMD='cd $W && git commit -m x'; eval \"\$CMD\"" deny "cannot determine" "string held in an expansion"
  _expect "T29c the commit hidden in a variable (bash -c \"\$SCRIPT\") → deny" \
    "$R" "SCRIPT='cd $W && git commit -m x'; bash -c \"\$SCRIPT\"" deny "cannot determine" "script held in an expansion"

  _expect "T30a GIT_WORK_TREE= on a commit → deny (cannot determine)" \
    "$R" "GIT_WORK_TREE=$W git commit -m x" deny "cannot determine" "GIT_WORK_TREE"
  _expect "T30b git --work-tree= on a commit → deny (cannot determine)" \
    "$R" "git --work-tree=$W commit -m x" deny "cannot determine" "--work-tree"
  _expect "T30c git --git-dir= on a commit → deny (cannot determine)" \
    "$R" "git --git-dir=$R/.git commit -m x" deny "cannot determine" "--git-dir"

  pd=$(_mk_stub_path findings)
  EXPECT_PD="$pd" _expect "T31 no perl → a tokenised commit is DENIED naming the cause (stub gitleaks would report a finding: that must not be the reason)" \
    "$R" "cd $W && git commit -m x" deny "cannot determine" "perl" "!private-key"
  _expect "T32 unbalanced quote (lexer error) → deny" \
    "$R" "cd \"$W && git commit -m x" deny "cannot determine" "not parseable"

  cp=$(mktemp -d "$SUITE_TMP/hookcopy.XXXXXX")
  mkdir -p "$cp/.claude"
  cp -R "$REPO_ROOT/.claude/hooks" "$cp/.claude/hooks"
  rm -f "$cp/.claude/hooks/lib/commit-target-roots.sh"
  HOOK_OVERRIDE="$cp/.claude/hooks/git-commit-secret-scan.sh" \
    _expect "T33 library missing → a commit is DENIED with the literal repair" \
    "$R" "git commit -m x" deny "git checkout -- .claude/hooks/lib"
  HOOK_OVERRIDE="$cp/.claude/hooks/git-commit-secret-scan.sh" \
    _expect "T33b library missing leaves a non-commit call untouched" \
    "$R" "git status" allow

  _expect "T34 must-ALLOW control: cd into a CLEAN worktree" \
    "$R2" "cd $W2 && git commit -m x" allow
  cmd=$(printf '%s\n' "git -C $W2 commit -m \"\$(cat <<'EOF'" 'cd "$WT" && git commit' 'EOF' ')"')
  _expect "T35 must-ALLOW: a heredoc message that MENTIONS a non-literal cd is data, not a target" \
    "$R2" "$cmd" allow

  s1="$SUITE_TMP/sentinel1"; s2="$SUITE_TMP/sentinel2"
  _expect "T36a nothing is executed while resolving: cd \"\$(touch <sentinel>)\"" \
    "$R" 'cd "$(touch '"$s1"')" && git commit -m x' deny "cannot determine"
  if [[ ! -e "$s1" ]]; then _report "T36a the sentinel does not exist (command substitution never ran)" ok
  else _report "T36a the sentinel does not exist (command substitution never ran)" fail "$s1 was created"; fi
  _expect "T36b nothing is executed while resolving: eval-shaped text" \
    "$R" 'eval "touch '"$s2"'"; cd "$X" && git commit -m x' deny "cannot determine"
  if [[ ! -e "$s2" ]]; then _report "T36b the sentinel does not exist (eval never ran)" ok
  else _report "T36b the sentinel does not exist (eval never ran)" fail "$s2 was created"; fi

  _expect "T37 must-ALLOW: a literal target that does not exist drops out (no false deny)" \
    "$A" "cd /nonexistent/dir && git commit -m x" allow

  RUN_ENV=("GIT_DIR=$A/.git")
  _expect "T39 an inherited GIT_DIR cannot redirect the resolver or the scan" \
    "$R" "cd $W && git commit -m x" deny "leak.json"
  RUN_ENV=()

  pd=$(_mk_stub_path byroot perl)
  RUN_ENV=("GL_STUB_FAIL_DIR=${A##*/}" "GL_REAL=$(command -v gitleaks)")
  EXPECT_PD="$pd" _expect "T41 the loop does not end at a root whose scan errored (clean A errors, leaky B still denies)" \
    "$R" "cd $A && git -C $B commit -m x" deny "leak.json"
  # Witness: root A's scan really errored (the stub exits 2 there), so the row proves the
  # loop continued PAST an errored root rather than never meeting one.
  if [[ "$ERR" == *"exited 2"* ]]; then _report "T41b root A's scan errored (the stub fired) and the loop continued" ok
  else _report "T41b root A's scan errored (the stub fired) and the loop continued" fail "stderr: ${ERR:0:200}"; fi
  RUN_ENV=()

  PAYLOAD_CWD="$W" _expect "T42 the separate-cd repair: payload .cwd is the worktree, the command carries no cd" \
    "$R" "git commit -m x" deny "leak.json"

  _expect "T43a must-ALLOW: 'git -C <wt> log' is not a commit" "$R" "git -C $W log --oneline" allow
  _expect "T43b must-ALLOW: 'git --no-pager status' is not a commit" "$R" "git --no-pager status" allow
  _expect "T43c must-ALLOW: a quoted mention of 'git -C x commit' is data" "$R" 'echo "git -C x commit"' allow

  # S-repair: the repairs the deny text recommends must themselves pass THROUGH the
  # hook (be scanned), and must not dead-end a clean worktree.
  _expect "S-repair 1 literal 'cd <abs> && git commit' is scanned (leak → deny)" "$R" "cd $W && git commit -m x" deny "leak.json"
  _expect "S-repair 2 literal 'git -C <abs> commit' is scanned (leak → deny)" "$R" "git -C $W commit -m x" deny "leak.json"
  _expect "S-repair 3 literal 'cd <abs>; git commit' is scanned (leak → deny)" "$R" "cd $W; git commit -m x" deny "leak.json"
  _expect "S-repair 4 a lazily bound WT=<abs>; cd \"\$WT\" is still denied" "$R" "WT=$W; cd \"\$WT\" && git commit -m x" deny "cannot determine"
  _expect "S-repair 5 literal 'cd <abs> && git commit' ALLOWS a clean worktree" "$R2" "cd $W2 && git commit -m x" allow
  _expect "S-repair 6 literal 'git -C <abs> commit' ALLOWS a clean worktree" "$R2" "git -C $W2 commit -m x" allow
  _expect "S-repair 7 literal 'cd <abs>; git commit' ALLOWS a clean worktree" "$R2" "cd $W2; git commit -m x" allow

  # AC11: a command with no directory-affecting token never spawns perl.
  pd=$(_mk_stub_path clean)
  if [[ -e "$pd/perl" ]]; then _report "AC11 fixture PATH carries perl" fail "stub PATH must not contain perl"
  else
    EXPECT_PD="$pd" _expect "AC11 plain 'git commit' on a PATH with no perl still scans and allows a clean repo" \
      "$A" "git commit -m x" allow
  fi
}

# #10609 review round: every launcher, option form, quoting form and ordering the walker must
# see through, each as its own row with a DIFFERENT leaky member (a first-only or last-only
# resolver, or a swapped cause, fails at least one).
_t_target_resolution2() {
  _needs_gl "T44-T70 launcher/option/ordering/root rows" || return 0
  local R W R2 W2 A B NT pd w o r s cp many i
  _mk_bare_root_with_worktree leak; R="$FX_ROOT"; W="$FX_WT"
  _mk_bare_root_with_worktree clean; R2="$FX_ROOT"; W2="$FX_WT"
  _fx_control "$W" || return 0
  A=$(_mk_repo_with_toml); B=$(_mk_leaky_repo)
  NT=$(mktemp -d "$SUITE_TMP/notoml.XXXXXX")
  ( cd "$NT" && git init -q -b main && echo x > f.txt && git add f.txt )

  # T44: a launcher in front of git must not hide the target (the whole #10609 class).
  for w in 'timeout 5' 'sudo' 'nice -n 5' 'xargs' 'rtk' 'flock /tmp/soleur-lock' 'exec -a x' 'command' 'setsid' 'stdbuf -oL'; do
    _expect "T44 launcher '$w' before 'git -C <wt> commit' → deny" "$R" "$w git -C $W commit -m x" deny "leak.json" "$W"
  done
  _expect "T44b 'sudo -D <wt> git commit' → deny" "$R" "sudo -D $W git commit -m x" deny "leak.json"
  _expect "T44c 'sudo env -C <wt> git commit' → deny" "$R" "sudo env -C $W git commit -m x" deny "leak.json"

  # T45: git global options that take a separate operand.
  for o in '--namespace n' '--config-env k=V' '--attr-source HEAD' '--super-prefix p' '--no-pager -c k=v' '-c k=v --no-pager'; do
    _expect "T45 git $o -C <wt> commit → deny" "$R" "git $o -C $W commit -m x" deny "leak.json"
  done

  # T46: quoting and path forms the strict regex and the old pre-filter could not see.
  for s in 'git "-C" WT commit -m x' '/usr/bin/git -C WT commit -m x' "'git' -C WT commit -m x" '(git -C WT commit -m x)' 'git -C "WT" commit -m x'; do
    _expect "T46 quoting/path form: $s" "$R" "${s//WT/$W}" deny "leak.json"
  done

  # T47: env forms.
  for s in '/usr/bin/env -C WT git commit -m x' 'env -CWT git commit -m x' 'env -iC WT git commit -m x' 'env --ch WT git commit -m x' 'env -u FOO -C WT git commit -m x'; do
    _expect "T47 env form: $s" "$R" "${s//WT/$W}" deny "leak.json"
  done

  # T48: repository-location variables set by something other than a leading assignment.
  _expect "T48a 'export GIT_DIR=...; git commit' → deny" "$R" "export GIT_DIR=$W/.git; git commit -m x" deny "cannot determine" "GIT_DIR"
  _expect "T48b 'declare -x GIT_WORK_TREE=...; git commit' → deny" "$R" "declare -x GIT_WORK_TREE=$W; git commit -m x" deny "cannot determine" "GIT_WORK_TREE"
  _expect "T48c 'GIT_INDEX_FILE=... git commit' → deny" "$R" "GIT_INDEX_FILE=$W/.git/index git commit -m x" deny "cannot determine" "GIT_INDEX_FILE"
  _expect "T48d 'git -c core.worktree=... commit' → deny" "$R" "git -c core.worktree=$W commit -m x" deny "cannot determine" "core.worktree"

  # T49: a shell runner whose script is held in a variable, in every option spelling.
  for r in 'sh -c' 'zsh -c' 'bash -lc' 'bash -ce' 'bash -o pipefail -c' 'sudo bash -c' 'timeout 5 bash -c'; do
    _expect "T49 runner '$r' with a script in a variable → deny" "$R" "S='cd $W && git commit -m x'; $r \"\$S\"" deny "cannot determine" "script held in an expansion"
  done

  # T50: a target created by the same command does not exist yet.
  _expect "T50a 'git worktree add <new> && cd <new> && git commit' → deny" \
    "$R" "git worktree add $R/.worktrees/newwt && cd $R/.worktrees/newwt && git commit -m x" deny "cannot determine" "does not exist yet" "as its own call"
  _expect "T50b 'mkdir -p <new> && cd <new> && git commit' → deny" \
    "$R" "mkdir -p $R/newdir && cd $R/newdir && git commit -m x" deny "cannot determine" "does not exist yet"

  # T51: a bounded number of targets (an unbounded chain outlives the hook's timeout).
  many=""
  for i in $(seq 1 40); do many+="cd d$i && "; done
  _expect "T51 more than 32 distinct targets → deny, quickly" "$R" "${many}git commit -m x" deny "cannot determine" "more than 32"

  # T52: a refusal after the last commit cannot change its target; the one before still can.
  _expect "T52a 'git -C <clean> commit && cd -' → allow (the later cd cannot retarget the commit)" \
    "$R2" "git -C $W2 commit -m x && cd - >/dev/null" allow
  _expect "T52b 'cd \"\$X\" && git -C <clean> commit' → deny (the refusal precedes the commit)" \
    "$R2" "cd \"\$X\" && git -C $W2 commit -m x" deny "cannot determine"

  # T53: a lexer failure on a loose-only match is denied for ITS cause, with the right repair.
  _expect "T53a unbalanced quote on a loose-only form → deny (parse)" "$R" "git -C \"$W commit -m x" deny "cannot determine" "not parseable" "balanced quotes" "!install perl"
  pd=$(_mk_stub_path findings)
  EXPECT_PD="$pd" _expect "T53b no perl on a loose-only form → deny (tooling)" "$R" "git -C $W commit -m x" deny "cannot determine" "perl" "perl is on PATH" "plain 'git commit'" "!No rewrite" "!private-key"

  # T54: a broken library denies a commit and leaves a non-commit alone.
  cp=$(mktemp -d "$SUITE_TMP/hookcopy2.XXXXXX")
  mkdir -p "$cp/.claude"
  cp -R "$REPO_ROOT/.claude/hooks" "$cp/.claude/hooks"
  rm -f "$cp/.claude/hooks/lib/commit-target-roots.sh"
  HOOK_OVERRIDE="$cp/.claude/hooks/git-commit-secret-scan.sh" \
    _expect "T54a library missing: 'git log --grep=commit' (no option form) → allow" "$R" "git log --grep=commit" allow
  HOOK_OVERRIDE="$cp/.claude/hooks/git-commit-secret-scan.sh" \
    _expect "T54b library missing: the deny says no rewrite can help" "$R" "git commit -m x" deny "cannot determine" "No rewrite of the command can help" "git checkout -- .claude/hooks/lib"

  # T55: an unrunnable gitleaks keeps its allow + bypass row AHEAD of the undeterminable deny.
  pd=$(_mk_stub_path unrunnable perl)
  EXPECT_PD="$pd" _expect "T55 unrunnable gitleaks + undeterminable target → allow via the bypass row" "$R" 'cd "$X" && git commit -m x' allow
  if [[ "$(_last_prefix)" == "gitleaks unrunnable"* ]]; then _report "T55b the allow carries the 'gitleaks unrunnable' row" ok
  else _report "T55b the allow carries the 'gitleaks unrunnable' row" fail "prefix=$(_last_prefix)"; fi

  # T56: a target without .gitleaks.toml is skipped, and the scan CONTINUES to the next root.
  _expect "T56a toml-less root first, leaky root second → deny" "$R" "cd $NT && cd $W && git commit -m x" deny "leak.json" "$W"
  _expect "T56b a toml-less target alone → allow (existing per-root policy) via the bypass row" "$R2" "git -C $NT commit -m x" allow

  # T57: relative targets resolve against each base on its own, and compose.
  PAYLOAD_CWD="$A" _expect "T57a relative target reachable only from the PROCESS cwd" "$R" "cd .worktrees/wt && git commit -m x" deny "leak.json"
  PAYLOAD_CWD="$R" _expect "T57b relative target reachable only from the PAYLOAD cwd" "$A" "cd .worktrees/wt && git commit -m x" deny "leak.json"
  _expect "T57c relative targets compose ('cd .worktrees && cd wt')" "$R" "cd .worktrees && cd wt && git commit -m x" deny "leak.json"

  # T58: the deny names its cause, and the causes carry DIFFERENT repairs.
  _expect "T58a target causes lead with the literal-path repair" "$R" 'cd "$X" && git commit -m x' deny "git -C /abs/path commit" "cd /abs/path && git commit" "as its own command"
}

# The verdict helpers must be able to REJECT: a helper that always says yes leaves every
# assertion green, and the count floor below cannot see it (a neutered helper still counts).
_t_helper_selftest() {
  local out
  out=$( ( _expect "selftest-expect-mismatch" "$REPO_ROOT" "git status" deny ) 2>&1 ) || true
  if [[ "$out" != *"[FAIL] selftest-expect-mismatch"* ]]; then
    printf '[FATAL] instrument self-test: _expect did not report a decision mismatch (got: %s)\n' "${out:0:200}" >&2; exit 1
  fi
  out=$( ( _expect "selftest-expect-match" "$REPO_ROOT" "git status" allow ) 2>&1 ) || true
  if [[ "$out" != *"[ok] selftest-expect-match"* ]]; then
    printf '[FATAL] instrument self-test: _expect did not report a matching decision (got: %s)\n' "${out:0:200}" >&2; exit 1
  fi
  out=$( ( _expect "selftest-expect-fragment" "$REPO_ROOT" "git status" allow "no-such-fragment" ) 2>&1 ) || true
  if [[ "$out" != *"[FAIL] selftest-expect-fragment"* ]]; then
    printf '[FATAL] instrument self-test: _expect ignored a missing reason fragment (got: %s)\n' "${out:0:200}" >&2; exit 1
  fi
  out=$( ( _w_row "selftest-row-mismatch" 'cd /a' '/zzz;' 0 0 ) 2>&1 ) || true
  if [[ "$out" != *"[FAIL] walker: selftest-row-mismatch"* ]]; then
    printf '[FATAL] instrument self-test: _w_row did not report a mismatch (got: %s)\n' "${out:0:200}" >&2; exit 1
  fi
  out=$( ( _w_row "selftest-row-fragment" 'cd "$X"' '' 1 0 "no-such-fragment" ) 2>&1 ) || true
  if [[ "$out" != *"[FAIL] walker: selftest-row-fragment"* ]]; then
    printf '[FATAL] instrument self-test: _w_row ignored a missing reason fragment (got: %s)\n' "${out:0:200}" >&2; exit 1
  fi
  out=$( ( _w_row "selftest-row-match" 'cd /a' '/a;' 0 0 ) 2>&1 ) || true
  if [[ "$out" != *"[ok] walker: selftest-row-match"* ]]; then
    printf '[FATAL] instrument self-test: _w_row did not report a match (got: %s)\n' "${out:0:200}" >&2; exit 1
  fi
}


# Reviewer kill rows (test-design seat, fix round): one row per surviving mutant of the first
# fix round. Named K<n> after the mutant family each one kills.
_k_selftest() {  # label output must-contain-pattern
  if [[ "$2" == *"$3"* ]]; then _report "$1" ok; else _report "$1" fail "helper did not react: got '${2:0:160}' want '$3'"; fi
}

_mk_nodiff_bare() {
  local root; root=$(mktemp -d "$SUITE_TMP/ndbare.XXXXXX")
  (
    cd "$root"
    git init -q -b main; git config user.email t@t; git config user.name t
    echo seed > seed.txt; git add seed.txt
    git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m seed
    git config core.bare true
    git worktree add -q .worktrees/wt -b wtb
    mkdir -p .git/info; echo 'hidden.json -diff' > .git/info/attributes
    cd .worktrees/wt
    cp "$GITLEAKS_TOML" .gitleaks.toml
    jq -n --arg p "$(_mk_pem "k6_nodiff_syntheticpayload_$(date +%s)")" '{key: $p}' > hidden.json
    git add hidden.json .gitleaks.toml
  )
  FX_ROOT=$(cd "$root" && pwd -P); FX_WT=$(cd "$root/.worktrees/wt" && pwd -P)
}

_w_lexstub() {  # label perl-body want
  local label="$1" body="$2" want="$3" lib="$REPO_ROOT/.claude/hooks/lib/commit-target-roots.sh" f got
  f=$(mktemp "$SUITE_TMP/lexstub.XXXXXX"); printf '%s' "$body" | tee "$f" >/dev/null
  got=$(env bash -c 'source "$1" || { echo SOURCE-FAILED; exit 0; }; CTR_LEXER="$2"; ctr_collect "x"; printf "S=%s K=%s" "$CTR_LEX_STATE" "$CTR_LEX_KIND"' _ "$lib" "$f" 2>&1) || true
  if [[ "$got" == "$want" ]]; then _report "K18 lexstub: $label" ok; else _report "K18 lexstub: $label" fail "got '$got' want '$want'"; fi
}

_k_main() {
  _needs_gl "K rows" || return 0
  local R W R2 W2 A B NT NTL PLAIN E1 E2 pd cp c i deep tl ND NDW out
  _mk_bare_root_with_worktree leak; R="$FX_ROOT"; W="$FX_WT"
  _mk_bare_root_with_worktree clean; R2="$FX_ROOT"; W2="$FX_WT"
  _fx_control "$W" || return 0
  A=$(_mk_repo_with_toml); B=$(_mk_leaky_repo)
  NT=$(mktemp -d "$SUITE_TMP/notoml.XXXXXX"); ( cd "$NT" && git init -q -b main && echo x > f.txt && git add f.txt )
  NTL=$(mktemp -d "$SUITE_TMP/notomlleak.XXXXXX")
  ( cd "$NTL" && git init -q -b main && git config user.email t@t && git config user.name t \
      && jq -n --arg p "$(_mk_pem "k16_notoml_leak_$(date +%s)")" '{key: $p}' > leak.json && git add leak.json )
  PLAIN=$(mktemp -d "$SUITE_TMP/plain.XXXXXX")
  E1=$(mktemp -d "$SUITE_TMP/e1.XXXXXX"); E2=$(mktemp -d "$SUITE_TMP/e2.XXXXXX")

  # K1 multi-bad listing (cap 3, 'and N more')
  _expect "K1a five refusals: causes 2 and 3 named, 'and 2 more', 4th cause absent" "$R" \
    'cd "$X" && cd ~ && cd - && cd /q* && cd "$Y" && git commit -m x' deny "uses ~" "goes to a directory the walker cannot see" "and 2 more" "!glob or brace pattern"
  _expect "K1b four refusals: 'and 1 more'" "$R" 'cd "$X" && cd ~ && cd - && cd /q* && git commit -m x' deny "uses ~" "and 1 more"
  _expect "K1c two refusals: both named, no 'more'" "$R" 'cd "$X" && cd ~ && git commit -m x' deny "contains an expansion" "uses ~" "!more)"
  # K2 lexer bound surfaced by the hook
  deep=""; tl=""; for i in $(seq 1 20); do deep+='echo $('; tl+=')'; done
  _expect "K2 hook: a lexer bound denies with the split repair" "$R" "${deep}git -C $W commit -m x${tl}" deny "cannot determine" "Split the command"
  # K3 library missing + loose-only form
  cp=$(mktemp -d "$SUITE_TMP/hookcopy3.XXXXXX"); mkdir -p "$cp/.claude"; cp -R "$REPO_ROOT/.claude/hooks" "$cp/.claude/hooks"
  rm -f "$cp/.claude/hooks/lib/commit-target-roots.sh"
  HOOK_OVERRIDE="$cp/.claude/hooks/git-commit-secret-scan.sh" \
    _expect "K3 library missing + loose-only 'git -C <wt> commit' -> deny" "$R" "git -C $W commit -m x" deny "git checkout -- .claude/hooks/lib"
  # K4 inherited index / work-tree env cannot redirect the scan
  RUN_ENV=("GIT_INDEX_FILE=$A/.git/index")
  _expect "K4a inherited GIT_INDEX_FILE cannot blind the scan" "$R" "cd $W && git commit -m x" deny "leak.json"
  RUN_ENV=("GIT_WORK_TREE=$A")
  _expect "K4b inherited GIT_WORK_TREE cannot blind the scan" "$R" "cd $W && git commit -m x" deny "leak.json"
  RUN_ENV=()
  # K5 not in a work tree
  _expect "K5 cwd outside any repository -> allow" "$PLAIN" "git commit -m x" allow
  if [[ "$(_last_prefix)" == "not inside git work tree"* ]]; then _report "K5b the row is 'not inside git work tree'" ok
  else _report "K5b the row is 'not inside git work tree'" fail "prefix=$(_last_prefix)"; fi
  # K6 -diff attribute in a root reached only through the command
  _mk_nodiff_bare; ND="$FX_ROOT"; NDW="$FX_WT"
  local prc=0; ( cd "$NDW" && gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1 --report-format json --report-path "$SUITE_TMP/ndplain.json" >/dev/null 2>&1 ) || prc=$?
  if [[ "$prc" -ne 0 ]]; then _report "K6 fixture control" fail "the -diff attr did not blind the plain scan (rc=$prc)"
  else _expect "K6 -diff secret in a root named by the command (cwd is the bare root) -> deny" "$ND" "cd $NDW && git commit -m x" deny "-diff"; fi
  # K7 existing non-repo targets / creators with existing targets
  _expect "K7a existing non-repo target drops out (no false deny)" "$A" "cd $PLAIN && git commit -m x" allow
  _expect "K7b creator + EXISTING clean repo target -> allow" "$R2" "mkdir -p $SUITE_TMP/k7b && cd $W2 && git commit -m x" allow
  _expect "K7c creator + EXISTING non-repo dir -> allow" "$A" "mkdir -p $PLAIN/n && cd $PLAIN && git commit -m x" allow
  # K8 every creator word
  for c in 'git clone u /nope-k8/n' 'git init /nope-k8/n' 'git submodule add u /nope-k8/n' 'cp -r a /nope-k8/n' 'mv a /nope-k8/n' \
           'ln -s a /nope-k8/n' 'install -d /nope-k8/n' 'rsync -a a/ /nope-k8/n' 'tar -xf a.tar -C /nope-k8/n' 'unzip a.zip -d /nope-k8/n'; do
    _expect "K8 creator '$c' + missing target -> deny" "$R2" "$c && cd /nope-k8/n && git commit -m x" deny "does not exist yet"
  done
  # K14 window of three resolved directories
  local E0 E3; E0=$(mktemp -d "$SUITE_TMP/e0.XXXXXX"); E3=$(mktemp -d "$SUITE_TMP/e3.XXXXXX")
  _expect "K14 relative target composed against the 3rd-last of FOUR resolved dirs" "$R" "cd $E0 && cd .worktrees && cd $E1 && cd $E2 && cd wt && git commit -m x" deny "leak.json"
  _expect "K14b relative target 4th-last of five resolved dirs is OUT of the documented window -> allow" "$R" "cd $E0 && cd .worktrees && cd $E1 && cd $E2 && cd $E3 && cd wt && git commit -m x" allow
  # K15 leaky root in 3rd and 4th position
  _expect "K15a leaky root FOURTH of four targets" "$R" "cd $A && cd $W2 && cd $NT && cd $W && git commit -m x" deny "leak.json" "$W"
  _expect "K15b leaky root THIRD of three targets" "$R" "cd $A && cd $W2 && cd $W && git commit -m x" deny "leak.json" "$W"
  # K16 a toml-less root is skipped even when it holds a secret
  _expect "K16 toml-less root with a staged secret -> allow (policy: skipped)" "$R2" "git -C $NTL commit -m x" allow
  if [[ "$(_last_prefix)" == ".gitleaks.toml absent"* ]]; then _report "K16b skipped via the '.gitleaks.toml absent' row" ok
  else _report "K16b skipped via the '.gitleaks.toml absent' row" fail "prefix=$(_last_prefix)"; fi

  # K9-K13 walker rows
  _w_row "K9 bash --norc -c \$S"        'bash --norc -c "$S"'           '' 1 1 "expansion"
  _w_row "K9 bash --login -c \$S"       'bash --login -c "$S"'          '' 1 1 "expansion"
  _w_row "K9 bash -O extglob -c \$S"    'bash -O extglob -c "$S"'       '' 1 1 "expansion"
  _w_row "K10 typeset -x GIT_DIR"       'typeset -x GIT_DIR=/g; git commit -m x' '' 1 1 "GIT_DIR"
  _w_row "K10 readonly GIT_DIR"         'readonly GIT_DIR=/g; git commit -m x'   '' 1 1 "GIT_DIR"
  _w_row "K10 local GIT_DIR"            'local GIT_DIR=/g; git commit -m x'      '' 1 1 "GIT_DIR"
  _w_row "K10 builtin export GIT_DIR"   'builtin export GIT_DIR=/g; git commit -m x' '' 1 1 "GIT_DIR"
  _w_row "K10 command declare -x GIT_WORK_TREE" 'command declare -x GIT_WORK_TREE=/w; git commit -m x' '' 1 1 "GIT_WORK_TREE"
  _w_row "K10 export FOO=1 GIT_DIR (2nd operand)" 'export FOO=1 GIT_DIR=/g; git commit -m x' '' 1 1 "GIT_DIR"
  _w_row "K10 sudo sh -c \$S"           'sudo sh -c "$S"'               '' 1 1 "expansion"
  _w_row "K10 doas dash -c \$S"         'doas dash -c "$S"'             '' 1 1 "expansion"
  _w_row "K10 time ksh -c \$S"          'time ksh -c "$S"'              '' 1 1 "expansion"
  _w_row "K10 command eval \$X"         'command eval "$X"'             '' 1 1 "expansion"
  _w_row "K10 builtin pushd <dir>"      'builtin pushd /a && git commit -m x' '/a;' 0 1
  _w_row "K11 git -c core.bare=true"    'git -c core.bare=true commit -m x' '' 1 1 "core.bare"
  _w_row "K12 trailing refusal after a commit that already has one before it" 'cd "$X" && git commit -m a; cd "$Y"' '' 1 1 "expansion"
  _w_row "K13 launcher --chdir=<dir>"   'sudo --chdir=/a git commit -m x'  '/a;' 0 1
  _w_row "K13 launcher --chdir <dir>"   'sudo --chdir /a git commit -m x'  '/a;' 0 1
  _w_row "K20 env --unset NAME -C <dir>" 'env --unset FOO -C /a git commit -m x' '/a;' 0 1
  _w_row "K20 cd -e <dir>"              'cd -e /a && git commit -m x'    '/a;' 0 1
  _w_row "K20 repeated env -C"          'env -C /a -C /b git commit -m x' '/a;/b;' 0 1

  # K21 pre-filter tokens the suite does not drive
  local pf lib2="$REPO_ROOT/.claude/hooks/lib/commit-target-roots.sh"
  for pf in 'dash -c "git commit"' 'ksh -c "git commit"' 'chroot /x git commit' 'nsenter -t 1 git commit' 'typeset -x A=1; git commit' 'declare -x A=1; git commit' 'export A=1; git commit' 'doas git commit' 'eval "git commit"' 'git --git-dir=x commit'; do
    if bash -c 'source "$1" && ctr_wants_lex "$2"' _ "$lib2" "$pf"; then _report "K21 pre-filter matches: $pf" ok
    else _report "K21 pre-filter matches: $pf" fail "ctr_wants_lex returned false"; fi
  done
  # K22 the deny HEADER names the root that held the finding (the recovery text names it too)
  _expect "K22 header names the finding root, not the first root" "$R" "cd $A && cd $W && git commit -m x" deny "staged index of $W."
  # K23 deny rows are journalled
  _expect "K23 undeterminable deny" "$R" 'cd "$X" && git commit -m x' deny "cannot determine"
  if [[ "$(_last_prefix)" == "git-commit-secret-scan: BLOCKED"* ]]; then _report "K23b the deny is journalled" ok
  else _report "K23b the deny is journalled" fail "prefix=$(_last_prefix)"; fi

  # K24 _fx_control must be able to fail
  out=$( ( _fx_control "$A"; echo "fxrc=$?" ) 2>&1 ) || true
  _k_selftest "K24a _fx_control returns 1 on a fixture with no finding" "$out" "fxrc=1"
  _k_selftest "K24b _fx_control reports the broken fixture" "$out" "[FAIL] T21-T43 fixture control"
  # K25 RUN_ENV reaches the hook on the NO-stub-PATH branch (T39 depends on it)
  local stubenv; stubenv=$(mktemp "$SUITE_TMP/stubenv.XXXXXX")
  printf '%s\n' 'cat >/dev/null' "printf '%s' \"{\\\"hookSpecificOutput\\\":{\\\"permissionDecision\\\":\\\"deny\\\",\\\"permissionDecisionReason\\\":\\\"probe=\${PROBE_X-unset}\\\"}}\"" > "$stubenv"
  RUN_ENV=("PROBE_X=seen")
  HOOK_OVERRIDE="$stubenv" _expect "K25 RUN_ENV is exported to the hook (no stub PATH)" "$REPO_ROOT" "git status" deny "probe=seen"
  RUN_ENV=()
  # K27 _last_prefix is scoped to THIS invocation
  _expect "K27 setup: a run that journals a bypass" "$R" "git commit -m x" allow
  _expect "K27 a run that journals nothing" "$R" "git status" allow
  if [[ -z "$(_last_prefix)" ]]; then _report "K27b _last_prefix is empty after a run that emitted no row" ok
  else _report "K27b _last_prefix is empty after a run that emitted no row" fail "stale prefix=$(_last_prefix)"; fi

  # K17 helper self-tests the suite does not carry
  local stubdeny stubnone out
  stubdeny=$(mktemp "$SUITE_TMP/stubdeny.XXXXXX"); stubnone=$(mktemp "$SUITE_TMP/stubnone.XXXXXX")
  printf '%s\n' 'cat >/dev/null' "printf '%s' '{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"aaa cause\"}}'" > "$stubdeny"
  printf '%s\n' 'cat >/dev/null' > "$stubnone"
  out=$( ( HOOK_OVERRIDE="$stubdeny" _expect "st-neg" "$REPO_ROOT" "git status" deny '!aaa' ) 2>&1 ) || true
  _k_selftest "K17a _expect must FAIL when a !-fragment IS present" "$out" "[FAIL] st-neg"
  out=$( ( HOOK_OVERRIDE="$stubnone" _expect "st-crash" "$REPO_ROOT" "git status" allow ) 2>&1 ) || true
  _k_selftest "K17b _expect must FAIL when the hook printed NOTHING but allow was wanted" "$out" "[FAIL] st-crash"
  out=$( ( HOOK_OVERRIDE="$stubdeny" _expect "st-2nd" "$REPO_ROOT" "git status" deny "aaa" "no-such" ) 2>&1 ) || true
  _k_selftest "K17c _expect must FAIL when the SECOND fragment is missing" "$out" "[FAIL] st-2nd"
  out=$( ( _w_lex "st-lex" 'cd /a && git commit -m x' "S=unavailable K=parse" ) 2>&1 ) || true
  _k_selftest "K17d _w_lex must FAIL on a state mismatch" "$out" "[FAIL] lexer state: st-lex"
  out=$( ( _w_row "st-bad" 'cd "$X" && git commit -m x' '' 0 1 ) 2>&1 ) || true
  _k_selftest "K17e _w_row must FAIL when ONLY the refusal count differs" "$out" "[FAIL] walker: st-bad"
  out=$( ( _w_row "st-commit" 'ls' '' 0 1 ) 2>&1 ) || true
  _k_selftest "K17f _w_row must FAIL when ONLY the commit flag differs" "$out" "[FAIL] walker: st-commit"
  out=$( ( _w_row "st-frag2" 'cd "$X" && git commit -m x' '' 1 1 "uses ~" ) 2>&1 ) || true
  _k_selftest "K17g _w_row must FAIL on a wrong cause fragment" "$out" "[FAIL] walker: st-frag2"

  # K18 lexer stream integrity (the framing guards)
  _w_lexstub "valid stream" 'print "C\0top\0" . "2\0-\0cd\0-\0/a\0OK\0";' "S=ok K="
  _w_lexstub "no OK at all (stream ends after a record)" 'print "C\0top\0" . "1\0-\0ls\0";' "S=unavailable K=parse"
  _w_lexstub "truncated header" 'print "C\0top\0";' "S=unavailable K=parse"
  _w_lexstub "truncated words" 'print "C\0top\0" . "2\0-\0cd\0";' "S=unavailable K=parse"
  _w_lexstub "data after OK" 'print "OK\0junk\0";' "S=unavailable K=parse"
  _w_lexstub "non-numeric argc" 'print "C\0top\0" . "abc\0-\0ls\0OK\0";' "S=unavailable K=parse"
  _w_lexstub "zero-led argc" 'print "C\0top\0" . "01\0-\0ls\0OK\0";' "S=unavailable K=parse"
  _w_lexstub "unknown tag" 'print "ZZ\0";' "S=unavailable K=parse"
  _w_lexstub "empty output" 'print "";' "S=unavailable K=tooling"
  _w_lexstub "E exit2 frame" 'print "E\0exit2\0";' "S=unavailable K=parse"
  _w_lexstub "E depth frame" 'print "E\0depth\0";' "S=unavailable K=bound"
}

# Second review round: shapes the first fix round left open, and the behaviours it added.
_t_target_resolution3() {
  _needs_gl "T60-T75 round-2 rows" || return 0
  local R W R2 W2 A cp s deep inter i
  _mk_bare_root_with_worktree leak; R="$FX_ROOT"; W="$FX_WT"
  _mk_bare_root_with_worktree clean; R2="$FX_ROOT"; W2="$FX_WT"
  _fx_control "$W" || return 0
  A=$(_mk_repo_with_toml)

  # T60: the look-through visits every command word, not just the first (a user named git).
  for s in 'sudo -u git git -C WT commit -m x' 'sudo --user git git -C WT commit -m x' 'runuser -u git -- git -C WT commit -m x'; do
    _expect "T60 look-through past an operand named like a command: $s" "$R" "${s//WT/$W}" deny "leak.json"
  done
  # T61: a shell fed its script on stdin hides the commit from the lexer.
  _expect "T61a here-string into bash → deny" "$R" "bash <<< 'cd $W && git commit -m x'" deny "cannot determine" "stdin"
  _expect "T61b pipe into bash → deny" "$R" "echo 'cd $W && git commit -m x' | bash" deny "cannot determine" "stdin"
  _expect "T61c must-ALLOW: a bare 'bash' with no heredoc or pipe is not a stdin script" "$R2" "git -C $W2 commit -m x; bash" allow
  # T62: launchers that take the command as one string.
  _expect "T62a flock -c '<git ...>' → deny" "$R" "flock /tmp/soleur-lock -c 'git -C $W commit -m x'" deny "cannot determine" "command string"
  _expect "T62b su <user> -c '<git ...>' → deny" "$R" "su deploy -c 'cd $W && git commit -m x'" deny "cannot determine" "command string"
  _expect "T62c must-ALLOW: 'gh pr create --body \"see git commit hooks\"' is prose" "$R2" 'gh pr create --body "see git commit hooks"' allow
  # T63: chroot / nsenter move the commit somewhere the walker cannot see.
  _expect "T63a chroot → deny" "$R" "chroot /r git commit -m x" deny "cannot determine" "changes the root or namespace"
  _expect "T63b nsenter → deny" "$R" "nsenter --wd=$W git commit -m x" deny "cannot determine" "changes the root or namespace"
  # T64: launcher chdir options, attached -D<dir>, and long forms.
  for s in 'sudo -DWT git commit -m x' 'sudo --chdir=WT git commit -m x' 'bwrap --chdir WT git commit -m x' 'systemd-run --working-directory=WT git commit -m x'; do
    _expect "T64 launcher chdir: $s" "$R" "${s//WT/$W}" deny "leak.json"
  done
  # T65: loops and functions run their text out of order, so no refusal is dropped there.
  _expect "T65a loop: commit before a cd to an expansion → deny" "$R2" 'for d in /a /b; do git commit -m x; cd "$d"; done' deny "cannot determine"
  _expect "T65b function: commit before a cd to an expansion → deny" "$R2" 'f() { git commit -m x; }; cd "$D"; f' deny "cannot determine"
  _expect "T65c straight line: a cd to an expansion AFTER the commit → allow" "$R2" 'git commit -m x && cd "$D"' allow
  # T66: a creator that comes AFTER the last commit cannot make its target the commit's target.
  _expect "T66a commit then 'mkdir -p sub && cd sub' → allow" "$R2" "git -C $W2 commit -m x && mkdir -p sub && cd sub" allow
  _expect "T66b commit then 'git worktree add new && cd new' → allow" "$R2" "git -C $W2 commit -m x && git worktree add ../new-wt -b nb && cd ../new-wt" allow
  # T67: quoted prose that happens to match the strict regex is not a commit.
  _expect "T67a prose with 'git commit' and a later cd to an expansion → allow" "$R2" 'echo "next: git commit later" && cd "$X" && ls' allow
  _expect "T67b gh pr create naming 'git commit' under a cd to an expansion → allow" "$R2" 'cd "$WT" && gh pr create --title "fix git commit hook" --body "the git commit path"' allow
  # T68: a library-missing install leans toward the deny for loose forms with quoting.
  cp=$(mktemp -d "$SUITE_TMP/hookcopy4.XXXXXX")
  mkdir -p "$cp/.claude"
  cp -R "$REPO_ROOT/.claude/hooks" "$cp/.claude/hooks"
  rm -f "$cp/.claude/hooks/lib/commit-target-roots.sh"
  HOOK_OVERRIDE="$cp/.claude/hooks/git-commit-secret-scan.sh" \
    _expect "T68a library missing + a quoted subcommand → deny" "$R" 'git "commit" -m x' deny "cannot determine" "No rewrite of the command can help"
  HOOK_OVERRIDE="$cp/.claude/hooks/git-commit-secret-scan.sh" \
    _expect "T68b library missing + 'git log --grep=commit' (no option form, no quoting) → allow" "$R" "git log --grep=commit" allow
  # T69: the nesting bound (a chain of env words recursed once per word and segfaulted the hook).
  deep=""
  for i in $(seq 1 100); do deep+="env "; done
  # T70: a launcher word between env words branches at every level; depth alone does not bound the work.
  inter="foo env"
  for i in $(seq 1 40); do inter+=" foo env"; done
  _expect "T70 interleaved launcher/env chain → deny, quickly" "$R" "${inter} git -C $W commit -m x" deny "cannot determine" "more than"
  _expect "T71 loop: a path created by the commit's own loop body → deny" "$R2" 'f() { git commit -m x; }; git init -q /nope-v/n; cd /nope-v/n; f' deny "cannot determine" "does not exist yet"
  _expect "T69 100 chained env words → deny, quickly" "$R" "${deep}git commit -m x" deny "cannot determine" "nests launchers"
}

# Walker rows: source the library and read what ctr_collect extracts. The command
# is passed as an ARGUMENT to a child bash — it is data, never evaluated.
_w_row() {  # label command want_targets want_nbad want_commit [fragment of the FIRST refusal reason]
  local label="$1" cmd="$2" want="T=$3|B=$4|C=$5" frag="${6:-}" got head reason state lib="$REPO_ROOT/.claude/hooks/lib/commit-target-roots.sh"
  got=$(env HOME=/h bash -c '
    source "$1" || { echo "SOURCE-FAILED"; exit 0; }
    ctr_collect "$2"
    printf "T="; for t in ${CTR_TARGETS[@]+"${CTR_TARGETS[@]}"}; do printf "%s;" "$t"; done
    printf "|B=%s|C=%s|R=%s|S=%s" "${#CTR_BAD[@]}" "$CTR_COMMIT_SEEN" "${CTR_BAD[0]-}" "$CTR_LEX_STATE"
  ' _ "$lib" "$cmd" 2>&1) || true
  head="${got%%|R=*}"; reason="${got#*|R=}"; state="${reason##*|S=}"; reason="${reason%|S=*}"
  # An unavailable lexer reports nothing, which would satisfy every "no target, no refusal" row.
  if [[ "$state" == ok && "$head" == "$want" && ( -z "$frag" || "$reason" == *"$frag"* ) ]]; then _report "walker: $label" ok
  else _report "walker: $label" fail "got '$got' want '$want' reason-fragment '$frag'"; fi
}

# What ctr_collect reports about the LEXER itself (state, kind). $2 is data, never evaluated.
_w_lex() {  # label command want ("S=ok K=" | "S=unavailable K=parse" ...) [PATH override]
  local label="$1" cmd="$2" want="$3" lp="${4:-$PATH}" got lib="$REPO_ROOT/.claude/hooks/lib/commit-target-roots.sh"
  got=$(env PATH="$lp" bash -c '
    source "$1" || { echo "SOURCE-FAILED"; exit 0; }
    ctr_collect "$2"
    printf "S=%s K=%s" "$CTR_LEX_STATE" "$CTR_LEX_KIND"
  ' _ "$lib" "$cmd" 2>&1) || true
  if [[ "$got" == "$want" ]]; then _report "lexer state: $label" ok
  else _report "lexer state: $label" fail "got '$got' want '$want'"; fi
}

_t_walker() {
  local lib="$REPO_ROOT/.claude/hooks/lib/commit-target-roots.sh"
  if [[ ! -r "$lib" ]]; then _report "walker: library exists" fail "$lib is not readable"; return 0; fi
  _w_row "redirect after cd (2>&1)"            'cd /a 2>&1 && git commit -m x'        '/a;'   0 1
  _w_row "redirect after cd (&>)"              'cd /a &> /dev/null && git commit -m x' '/a;'  0 1
  _w_row "cd inside a substitution"            'echo $(cd /s && true) && git commit -m x' '/s;' 0 1
  _w_row "# mid-word is not a comment"         'cd /a#b && git commit -m x'           '/a#b;' 0 1
  _w_row "builtin cd / command git"            'builtin cd /a && command git commit -m x' '/a;' 0 1
  _w_row "cd -P -- <dir>"                      'cd -P -- /a && git commit -m x'       '/a;'   0 1
  _w_row "pushd"                               'pushd /a >/dev/null && git commit -m x' '/a;' 0 1
  _w_row "repeated -C"                         'git -C /a -C b commit -m x'           '/a;b;' 0 1
  _w_row "-c k=v is not a target"              'git -c k=v commit -m x'               ''      0 1
  _w_row "commit -C HEAD: -C after the subcommand is not a global option" 'git commit -C HEAD' '' 0 1
  _w_row "quoted path with a space"            'cd "/a b" && git commit -m x'         '/a b;' 0 1
  _w_row "env -C <dir>"                        'env -C /a git commit -m x'            '/a;'   0 1
  _w_row "subshell"                            '(cd /a && git commit -m x)'           '/a;'   0 1
  _w_row "eval \"\$CMD\" is bad and may hide a commit" 'eval "$CMD"'                  ''      1 1
  _w_row "bash -c \"\$SCRIPT\" is bad and may hide a commit" 'bash -c "$SCRIPT"'      ''      1 1
  _w_row "bare cd goes to HOME"                'cd && git commit -m x'                '/h;'   0 1
  _w_row "--git-dir is bad"                    'git --git-dir=/g commit -m x'         ''      1 1
  _w_row "GIT_DIR= is bad"                     'GIT_DIR=/g git commit -m x'           ''      1 1
  # Built by concatenation so the fixture-relative ratchet does not read this DATA as a git write.
  local dq='"'
  _w_row "an expanded -C operand is bad"       "git -C ${dq}"'$X'"${dq} commit -m x"  ''      1 1
  _w_row "quoted cd text is data"              'echo "cd /a"; git commit -m x'        ''      0 1
  _w_row "git log is not a commit"             'git -C /a log --oneline'              '/a;'   0 0
  _w_row "cd ~ is bad (cause)"                 'cd ~ && git commit -m x'              ''      1 1 "uses ~"
  _w_row "cd - is bad (cause)"                 'cd - && git commit -m x'              ''      1 1 "cd -"
  _w_row "glob ? is bad"                       'cd /a? && git commit -m x'            ''      1 1 "glob"
  _w_row "glob [ is bad"                       'cd /a[1] && git commit -m x'          ''      1 1 "glob"
  _w_row "brace is bad"                        'cd /a{b,c} && git commit -m x'        ''      1 1 "glob"
  _w_row "expansion in cd is bad (cause)"      'cd "$X" && git commit -m x'           ''      1 1 "expansion"
  _w_row "sh -c \"\$S\" is bad"                 'sh -c "$S"'                           ''      1 1 "expansion"
  _w_row "zsh -c \"\$S\" is bad"                'zsh -c "$S"'                          ''      1 1 "expansion"
  _w_row "dash -c \"\$S\" is bad"               'dash -c "$S"'                         ''      1 1 "expansion"
  _w_row "ksh -c \"\$S\" is bad"                'ksh -c "$S"'                          ''      1 1 "expansion"
  _w_row "bash -lc \"\$S\" is bad"              'bash -lc "$S"'                        ''      1 1 "expansion"
  _w_row "bash -ce \"\$S\" is bad"              'bash -ce "$S"'                        ''      1 1 "expansion"
  _w_row "bash -o pipefail -c \"\$S\" is bad"   'bash -o pipefail -c "$S"'             ''      1 1 "expansion"
  _w_row "sudo bash -c \"\$S\" is bad"          'sudo bash -c "$S"'                    ''      1 1 "expansion"
  _w_row "timeout 5 bash -c \"\$S\" is bad"     'timeout 5 bash -c "$S"'               ''      1 1 "expansion"
  _w_row "a literal bash -c script is re-lexed" 'bash -c "cd /a && git commit -m x"'  '/a;'   0 1
  _w_row "env --chdir=<dir>"                   'env --chdir=/a git commit -m x'       '/a;'   0 1
  _w_row "env --chdir <dir>"                   'env --chdir /a git commit -m x'       '/a;'   0 1
  _w_row "env --ch <dir> (abbreviation)"       'env --ch /a git commit -m x'          '/a;'   0 1
  _w_row "env -C<dir> (attached)"              'env -C/a git commit -m x'             '/a;'   0 1
  _w_row "env -iC <dir> (bundled)"             'env -iC /a git commit -m x'           '/a;'   0 1
  _w_row "/usr/bin/env -C <dir>"               '/usr/bin/env -C /a git commit -m x'   '/a;'   0 1
  _w_row "env -S hides a command"              "env -S 'git -C /a commit'"            ''      1 1 "env -S"
  _w_row "env -u NAME skips its operand"       'env -u FOO git -C /a commit -m x'     '/a;'   0 1
  _w_row "env NAME=v prefix"                   'env FOO=1 git -C /a commit -m x'      '/a;'   0 1
  _w_row "env GIT_DIR=x is bad"                'env GIT_DIR=/g git commit -m x'       ''      1 1 "GIT_DIR"
  _w_row "git --git-dir <path> (separate) is bad" 'git --git-dir /g commit -m x'      ''      1 1 "--git-dir"
  _w_row "git --work-tree <path> (separate) is bad" 'git --work-tree /w commit -m x'  ''      1 1 "--work-tree"
  _w_row "a leading NAME=v is skipped"         'FOO=1 git -C /a commit -m x'          '/a;'   0 1
  _w_row "GIT_WORK_TREE= is bad"               'GIT_WORK_TREE=/w git commit -m x'     ''      1 1 "GIT_WORK_TREE"
  _w_row "GIT_INDEX_FILE= is bad"              'GIT_INDEX_FILE=/i git commit -m x'    ''      1 1 "GIT_INDEX_FILE"
  _w_row "GIT_COMMON_DIR= is bad"              'GIT_COMMON_DIR=/c git commit -m x'    ''      1 1 "GIT_COMMON_DIR"
  _w_row "export GIT_DIR is bad"               'export GIT_DIR=/g; git commit -m x'   ''      1 1 "GIT_DIR"
  _w_row "declare -x GIT_WORK_TREE is bad"     'declare -x GIT_WORK_TREE=/w; git commit -m x' '' 1 1 "GIT_WORK_TREE"
  _w_row "git -c core.worktree= is bad"        'git -c core.worktree=/w commit -m x'  ''      1 1 "core.worktree"
  _w_row "pushd +1 rotates the stack (bad)"    'pushd +1 && git commit -m x'          ''      1 1 "rotates"
  _w_row "pushd with no operand is bad"        'pushd && git commit -m x'             ''      1 1 "no operand"
  _w_row "exec wrapper"                        'exec git -C /a commit -m x'           '/a;'   0 1
  _w_row "nohup wrapper"                       'nohup git -C /a commit -m x'          '/a;'   0 1
  _w_row "time wrapper"                        'time git -C /a commit -m x'           '/a;'   0 1
  _w_row "command -p wrapper"                  'command -p git -C /a commit -m x'     '/a;'   0 1
  _w_row "timeout 5 git -C"                    'timeout 5 git -C /a commit -m x'      '/a;'   0 1
  _w_row "sudo git -C"                         'sudo git -C /a commit -m x'           '/a;'   0 1
  _w_row "nice -n 5 git -C"                    'nice -n 5 git -C /a commit -m x'      '/a;'   0 1
  _w_row "xargs git -C"                        'xargs git -C /a commit -m x'          '/a;'   0 1
  _w_row "rtk git -C"                          'rtk git -C /a commit -m x'            '/a;'   0 1
  _w_row "flock <file> git -C"                 'flock /l git -C /a commit -m x'       '/a;'   0 1
  _w_row "exec -a <name> git -C"               'exec -a x git -C /a commit -m x'      '/a;'   0 1
  _w_row "sudo -D <dir> git commit"            'sudo -D /a git commit -m x'           '/a;'   0 1
  _w_row "sudo env -C <dir> git commit"        'sudo env -C /a git commit -m x'       '/a;'   0 1
  _w_row "a launcher with -D and no git after it" 'ls -D /a'                          ''      0 0
  _w_row "git --namespace <n> -C <dir>"        'git --namespace n -C /a commit -m x'  '/a;'   0 1
  _w_row "git --config-env <k=V> -C <dir>"     'git --config-env k=V -C /a commit -m x' '/a;' 0 1
  _w_row "git --attr-source <rev> -C <dir>"    'git --attr-source HEAD -C /a commit -m x' '/a;' 0 1
  _w_row "git --super-prefix <p> -C <dir>"     'git --super-prefix p -C /a commit -m x' '/a;' 0 1
  _w_row "git --no-pager -c k=v -C <dir>"      'git --no-pager -c k=v -C /a commit -m x' '/a;' 0 1
  _w_row "an unknown git option then commit counts as a commit" 'git --frobnicate commit -m x' '' 0 1
  _w_row "an unknown option that swallows the subcommand still counts as a commit" 'git --frobnicate val commit -m x' '' 0 1
  _w_row "…and its -C operand is still collected" 'git --frobnicate val -C /a commit -m x' '/a;' 0 1
  _w_row "an unknown git option without commit is not a commit" 'git --frobnicate log' ''  0 0
  _w_row "git --no-pager log --grep commit is not a commit" 'git --no-pager log --grep commit' '' 0 0
  _w_row "git worktree add is not a commit"    'git worktree add /a b'                ''      0 0
  _w_row "a quoted global option"              'git "-C" /a commit -m x'              '/a;'   0 1
  _w_row "an absolute git path"                '/usr/bin/git -C /a commit -m x'       '/a;'   0 1
  _w_row "a quoted command word"               "'git' -C /a commit -m x"              '/a;'   0 1
  _w_row "an expanded command word is bad"    '"$GIT" -C /a commit -m x'             ''      1 1 "command word"
  _w_row "a refusal AFTER the last commit is dropped" 'git -C /a commit -m x && cd "$X"' '/a;' 0 1
  _w_row "a refusal BEFORE the commit is kept" 'cd "$X" && git -C /a commit -m x'     '/a;'   1 1
  _w_row "a second commit re-arms the refusals" 'git commit -m a; cd "$X"; git commit -m b' '' 1 1
  _w_row "duplicate targets collapse"          'cd /a && cd /a && git commit -m x'    '/a;'   0 1
  local many="" expmany="" i
  for i in $(seq 1 40); do many+="cd /d$i && "; if [ "$i" -le 32 ]; then expmany+="/d$i;"; fi; done
  _w_row "more than 32 distinct targets is refused" "${many}git commit -m x" "$expmany" 1 1 "more than 32"
  _w_row "sudo -u git git -C <dir> (operand named git)" 'sudo -u git git -C /a commit -m x' '/a;' 0 1
  _w_row "sudo --user git git -C <dir>"        'sudo --user git git -C /a commit -m x' '/a;' 0 1
  _w_row "runuser -u git -- git -C <dir>"      'runuser -u git -- git -C /a commit -m x' '/a;' 0 1
  _w_row "bash with a here-string is a stdin script" 'bash <<< "cd /a && git commit"' '' 1 1 "stdin"
  _w_row "echo | bash is a stdin script"       'echo x | bash'                        ''      1 1 "stdin"
  _w_row "a trailing bare bash is not a stdin script" 'git commit -m x; bash'         ''      0 1
  _w_row "bash <script> is an operand, not stdin" 'bash ./run.sh'                     ''      0 0
  _w_row "flock -c '<git ...>' is an unreadable string" "flock /l -c 'git -C /a commit'" ''   1 1 "command string"
  _w_row "su <user> -c '<git ...>' is an unreadable string" "su u -c 'cd /a && git commit'" '' 1 1 "command string"
  _w_row "gh pr create naming git commit is prose" 'gh pr create --body "see git commit hooks"' '' 0 0
  _w_row "chroot is refused when git follows"  'chroot /r git commit -m x'           ''      1 1 "changes the root"
  _w_row "nsenter is refused when git follows" 'nsenter -t 1 git commit -m x'        ''      1 1 "changes the root"
  _w_row "chroot without git is ignored"       'chroot /r ls'                         ''      0 0
  _w_row "sudo -D<dir> (attached)"             'sudo -D/a git commit -m x'            '/a;'   0 1
  _w_row "bwrap --chdir <dir>"                 'bwrap --chdir /a git commit -m x'     '/a;'   0 1
  _w_row "systemd-run --working-directory=<dir>" 'systemd-run --working-directory=/a git commit -m x' '/a;' 0 1
  _w_row "launcher --wd=<dir>"                 'nsenter --wd=/a ls'                   ''      0 0
  _w_row "cd -LP <dir> (option cluster)"       'cd -LP /a && git commit -m x'         '/a;'   0 1
  _w_row "cd -Pe <dir> (option cluster)"       'cd -Pe /a && git commit -m x'         '/a;'   0 1
  _w_row "pushd -n <dir>"                      'pushd -n /a && git commit -m x'       '/a;'   0 1
  _w_row "bash --rcfile <f> -c \"\$S\" is bad"   'bash --rcfile f -c "$S"'             ''      1 1 "expansion"
  _w_row "env --c=<dir> (abbreviation)"        'env --c=/a git commit -m x'           '/a;'   0 1
  _w_row "env --c <dir> (abbreviation)"        'env --c /a git commit -m x'           '/a;'   0 1
  _w_row "env --sp <string> (abbreviation)"    "env --sp 'git -C /a commit'"          ''      1 1 "split-string"
  _w_row "git -c Core.WorkTree= (case-insensitive key)" 'git -c Core.WorkTree=/w commit -m x' '' 1 1 "moves the work tree"
  _w_row "git --config-env=core.worktree=VAR"  'git --config-env=core.worktree=V commit -m x' '' 1 1 "moves the work tree"
  _w_row "git --config-env core.worktree=VAR (two words)" 'git --config-env core.worktree=V commit -m x' '' 1 1 "moves the work tree"
  _w_row "loop: the refusal after the commit is KEPT" 'for d in /a /b; do git commit -m x; cd "$d"; done' '' 1 1 "expansion"
  _w_row "function: the refusal after the commit is KEPT" 'f() { git commit -m x; }; cd "$D"; f' '' 1 1 "expansion"
  local chain=""
  for i in $(seq 1 40); do chain+="env "; done
  _w_row "a 40-deep env chain is refused, not recursed" "${chain}git commit -m x"     ''      1 1 "nests launchers"
  _w_row "bash -s -- <args> reads stdin"        'echo x | bash -s -- a'                ''      1 1 "stdin"
  _w_row "bash -s <arg> reads stdin"            'echo x | bash -s foo'                 ''      1 1 "stdin"
  _w_row "bash +x with a here-string reads stdin" 'bash +x <<< x'                      ''      1 1 "stdin"
  _w_row "bash < <(cmd) reads stdin"            'bash < <(echo x)'                     ''      1 1 "stdin"
  _w_row "bash --version | head is not a stdin script" 'bash --version | head -1; git commit -m x' '' 0 1
  _w_row "which bash | head is not a shell being run" 'which bash | head -1 && git commit -m x'   '' 0 1
  _w_row "echo run bash | tee is not a shell being run" 'echo run bash | tee n && git commit -m x' '' 0 1
  _w_row "git log | grep -w bash is not a shell being run" 'git log --oneline | grep -w bash; git commit -m x' '' 0 1
  _w_row "a ninth command word behind a launcher is refused, not skipped" 'a git git git git git git git git git -C /w commit' '' 1 1 "more than 8 command words"
  _w_lex "a parseable command"                 'cd /a && git commit -m x'             "S=ok K="
  _w_lex "an unbalanced quote is a parse failure" 'git -C "/a commit'                "S=unavailable K=parse"
  local deep="" tail=""
  for i in $(seq 1 20); do deep+='echo $('; tail+=')'; done
  _w_lex "20-deep nesting trips a bound"       "${deep}true${tail}"                   "S=unavailable K=bound"
  local nopl; nopl=$(_mk_stub_path absent)
  _w_lex "no perl is a tooling failure"        'cd /a && git commit -m x'             "S=unavailable K=tooling" "$nopl"

  local w
  for w in 'cd x' 'pushd x' 'GIT_DIR=x git commit' 'GIT_WORK_TREE=x git commit' 'git --git-dir=x commit' \
           'git --work-tree=x commit' 'git -C x commit' 'env -C x git commit' 'bash -c "git commit"' 'eval "$X"' \
           'sudo -D x git commit' '/usr/bin/env -C x git commit' 'export GIT_DIR=x; git commit' 'GIT_INDEX_FILE=x git commit' \
           'git -c core.worktree=x commit' 'sh -c "git commit"' 'zsh -c "git commit"' 'doas git commit'; do
    if bash -c 'source "$1" && ctr_wants_lex "$2"' _ "$lib" "$w"; then _report "pre-filter matches: $w" ok
    else _report "pre-filter matches: $w" fail "ctr_wants_lex returned false"; fi
  done
  for w in 'git commit -m x' 'git commit --amend --no-edit' 'git status && git commit -m x' 'git add -A && git commit -m "fix: tidy"'; do
    if bash -c 'source "$1" && ctr_wants_lex "$2"' _ "$lib" "$w"; then _report "pre-filter skips: $w" fail "ctr_wants_lex returned true (a perl spawn on the no-token path)"
    else _report "pre-filter skips: $w" ok; fi
  done
}

# T40: the walker depends on shell-argv.pl's record framing, which no other suite pins
# (shell-argv-parity.test.sh pins argv traces, not the NUL framing).
_t_lexer_contract() {
  local lib="$REPO_ROOT/.claude/hooks/lib/commit-target-roots.sh" got lexer
  if [[ ! -r "$lib" ]]; then _report "T40 lexer contract" fail "library missing"; return 0; fi
  lexer=$(bash -c 'source "$1" && printf "%s" "$CTR_LEXER"' _ "$lib" 2>/dev/null) || lexer=""
  if [[ -z "$lexer" || ! -r "$lexer" ]]; then
    _report "T40 the hook's resolved lexer path is a readable file" fail "CTR_LEXER='$lexer'"; return 0
  fi
  _report "T40 the hook's resolved lexer path is a readable file" ok
  got=$(printf '%s' 'cd /a' | perl "$lexer" | tr '\0' '|')
  if [[ "$got" == 'C|top|2|-|cd|-|/a|OK|' ]]; then _report "T40 lexer framing (C, ctx, argc, flags, arg, OK)" ok
  else _report "T40 lexer framing (C, ctx, argc, flags, arg, OK)" fail "got '$got'"; fi
}

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
# The assertion-count floor, driven on its REAL bytes (extracted between the markers below)
# through a truth table, so deleting it or breaking its arithmetic reds here instead of
# silently letting a suite that asserts nothing exit 0.
_t_floor_contract() {
  local body rc
  body=$(awk '/^# >>> assertion-floor$/{f=1;next} /^# <<< assertion-floor$/{f=0} f' "${BASH_SOURCE[0]}")
  if [[ -z "${body//[[:space:]]/}" ]]; then
    _report "floor contract" fail "floor markers matched nothing — the extraction is broken, not the floor"; return
  fi
  # row 1: below the floor and nothing skipped -> the REAL block must exit 1
  rc=0; ( set +e; eval 'pass=1; fail=0; SKIPPED_ARMS=()'"
$body" ) >/dev/null 2>&1 || rc=$?
  if [[ "$rc" != 1 ]]; then _report "floor contract: below the floor exits 1" fail "rc=$rc (MIN in the file: $(grep -m1 '^MIN_ASSERTIONS=' "${BASH_SOURCE[0]}"))"; return; fi
  # row 2: at the floor -> must NOT exit 1
  rc=0; ( set +e; eval 'pass=1000; fail=0; SKIPPED_ARMS=()'"
$body" ) >/dev/null 2>&1 || rc=$?
  if [[ "$rc" == 1 ]]; then _report "floor contract: at or above the floor passes" fail "rc=$rc"; return; fi
  # row 3: arms were skipped (no runnable gitleaks) -> the floor does not bind
  rc=0; ( set +e; eval 'pass=1; fail=0; SKIPPED_ARMS=(x)'"
$body" ) >/dev/null 2>&1 || rc=$?
  if [[ "$rc" == 1 ]]; then _report "floor contract: a skip-reduced run is left to the CI epilogue" fail "rc=$rc"; return; fi
  _report "floor contract (3-row truth table on the real block)" ok
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

# The #10609 arms run AFTER the watermark control: _run_cmd advances _JOURNAL_MARK too,
# and T20 expects the mark to advance across ITS OWN invocation.
_t_helper_selftest
_t_target_resolution
_t_target_resolution2
_k_main
_t_target_resolution3
_t_walker
_t_lexer_contract

_t_ci_contract
_t_floor_contract

# >>> assertion-floor
# Assertion-count FLOOR (not equality: every added row would otherwise need a bump). A helper
# that goes silent still counts nothing, so deleting the calls — or neutering the helpers —
# drops the total below this and the suite cannot exit 0 having asserted nothing. Skip-aware:
# a host with no runnable gitleaks skips whole arms (reported, and failed under CI=true by the
# epilogue), so the floor only binds when nothing was skipped. Reported by printf + exit,
# never through the helpers it backstops. Raise it in the same edit that adds rows.
MIN_ASSERTIONS=405
if (( ${#SKIPPED_ARMS[@]} == 0 )) && (( pass + fail < MIN_ASSERTIONS )); then
  printf '[FATAL] assertion floor: %s assertion(s) ran, expected at least %s — rows or helpers were dropped\n' "$((pass + fail))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
# <<< assertion-floor

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
