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
# TMPDIR is pinned to an absolute root: every fixture path below is rooted at SUITE_TMP, and a relative TMPDIR
# would make `mktemp -d` (and every path derived from it) relative (fixture-relative-assert, #7708).
export TMPDIR="${TMPDIR:-/var/tmp}"
SUITE_TMP=$(mktemp -d); _TMP_DIRS+=("$SUITE_TMP")
# The operator's global and system git configuration must not leak into any fixture: a global core.splitIndex or
# feature.manyFiles changed what the simulation saw (review round, test-design). Fixtures set their identity locally.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# The canonical fixture-dir guard (byte-identical to plugins/soleur/test/test-helpers.sh; asserted by
# plugins/soleur/test/fixture-dir-operand-assert.test.sh): refuse an empty, relative or synthetic-fs directory
# before a fixture write, so a function-returned path that came back wrong cannot retarget the write. #7652
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

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
# $1 = gitleaks stub mode: absent | unrunnable | emptyreport | findings | clean | byroot | record
# $2 = perl links perl as well (the lexer needs it; the default stub PATH has none)
# $3 = extra tool names to link (space separated), e.g. "timeout"
_mk_stub_path() {
  local mode="$1" d t p extra="" xt="${3:-}"
  [[ "${2:-}" == perl ]] && extra=perl
  d=$(mktemp -d "$SUITE_TMP/path.XXXXXX")
  # cp, sleep, find, rmdir, mv, cmp, ln: the would-be-index simulation (#10696) copies the index,
  # bounds and sweeps with them. $3 adds more tools by name (e.g. "timeout").
  for t in bash sh git jq mktemp grep cat dirname basename rm date flock sed awk tr \
           head tail cut wc sort env readlink realpath mkdir chmod touch id stat ls \
           cp sleep find rmdir mv cmp ln xargs expr uname seq $extra $xt; do
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
    record)
      # RECORDING stub (#10696 structural tier, ~50 ms a call). Logs every non-probe call to
      # $GL_REC_DIR (calls.log: n, subcommand, GIT_INDEX_FILE, GIT_OBJECT_DIRECTORY,
      # GIT_ALTERNATE_OBJECT_DIRECTORIES, PWD), copies the index it was handed (idx.N), lists it
      # (ls.N = git ls-files -s), and reports a finding when an INDEXED blob contains $GL_REC_MARK.
      # It never reads a real credential: the mark is the fixture's own synthetic body.
      # GL_REC_HOLD: signal "started" then wait (bounded) for $GL_REC_RELEASE. GL_REC_SLEEP: sleep.
      # GL_REC_RC / GL_REC_DETECT_RC: exit with that status (a gitleaks that errors out); with GL_REC_RC_REPORT the
      # finding report is still written first (a gitleaks that finds something AND then fails).
      cat > "$d/gitleaks" <<'STUB'
#!/bin/sh
[ "$1" = version ] && { echo 8.24.2; exit 0; }
d="${GL_REC_DIR:-}"
[ -n "$d" ] || exit 0
sub="$1"; rp=""; src=""; prev=""
for a in "$@"; do
  case "$prev" in --report-path) rp="$a" ;; --source) src="$a" ;; esac
  prev="$a"
done
rg="${SHIM_REAL_GIT:-git}"
# The stub's own git calls must not be able to start a daemon or write anything (fsmonitor pinned off).
g() { "$rg" -c core.fsmonitor=false -c core.untrackedCache=false "$@"; }
n=$(cat "$d/n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$d/n"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$sub" "${GIT_INDEX_FILE-<unset>}" "${GIT_OBJECT_DIRECTORY-<unset>}" \
  "${GIT_ALTERNATE_OBJECT_DIRECTORIES-<unset>}" "$PWD" >> "$d/calls.log"
env | grep -E '^GIT_CONFIG_(COUNT|KEY_|VALUE_|PARAMETERS)' > "$d/env.$n" 2>/dev/null
if [ "$sub" = detect ]; then
  if [ -n "$src" ] && [ -d "$src" ]; then (cd "$src" && find . -type f -print0 | sort -z | tr '\000' '|') > "$d/nodiff.$n"; fi
  exit "${GL_REC_DETECT_RC:-0}"
fi
[ "$sub" = git ] || exit 0
if [ -n "${GIT_INDEX_FILE-}" ]; then
  [ -f "$GIT_INDEX_FILE" ] && { cp "$GIT_INDEX_FILE" "$d/idx.$n"; echo yes > "$d/idxexists.$n"; }
  [ -d "${GIT_OBJECT_DIRECTORY-/nonexistent}" ] && echo yes > "$d/objexists.$n"
  ls -ld "${GIT_OBJECT_DIRECTORY-/nonexistent}" 2>/dev/null | cut -c1-10 > "$d/objperm.$n"
  p=$(dirname "$GIT_INDEX_FILE")
  while [ "$p" != / ] && [ "$p" != . ]; do
    case "$(basename "$p")" in
      commit-sim-*) echo "$p" > "$d/simdir.$n"; ls -ld "$p" | cut -c1-10 > "$d/simperm.$n"; break ;;
    esac
    p=$(dirname "$p")
  done
  g cat-file -t HEAD:seed.txt > "$d/headblob.$n" 2>/dev/null
fi
g ls-files -s > "$d/ls.$n" 2>/dev/null
if [ -n "${GL_REC_HOLD-}" ]; then
  : > "$d/started"
  k=0
  while [ ! -e "${GL_REC_RELEASE-/nonexistent}" ] && [ "$k" -lt 100 ]; do sleep 0.1; k=$((k + 1)); done
fi
[ -n "${GL_REC_SLEEP-}" ] && sleep "$GL_REC_SLEEP"
if [ -n "${GL_REC_RC-}" ] && [ -z "${GL_REC_RC_REPORT-}" ]; then exit "$GL_REC_RC"; fi
if [ -n "${GL_REC_MARK-}" ]; then
  hit=$(g grep --cached -l -F -e "$GL_REC_MARK" 2>/dev/null | head -n 1)
  if [ -n "$hit" ] && [ -n "$rp" ]; then
    printf '[{"RuleID":"private-key","File":"%s","StartLine":1}]' "$hit" > "$rp"
    exit "${GL_REC_RC:-1}"
  fi
fi
exit "${GL_REC_RC:-0}"
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
# NO_PAYLOAD_CWD=1 omits .cwd from the payload; RUN_PROJECT_DIR overrides CLAUDE_PROJECT_DIR (#10696).
# Sets OUT and ERR.
RUN_ENV=()
_run_cmd() {
  local cwd="$1" command="$2" pd="${3:-}" payload errf hook="${HOOK_OVERRIDE:-$HOOK}"
  errf=$(mktemp "$SUITE_TMP/err.XXXXXX")
  _JOURNAL_MARK=$(wc -l < "$SOLEUR_TEST_INCIDENT_ROOT/.claude/.rule-incidents.jsonl" 2>/dev/null || echo 0)
  if [[ "${NO_PAYLOAD_CWD:-0}" == 1 ]]; then
    payload=$(jq -nc --arg c "$command" '{tool_name: "Bash", tool_input: {command: $c}}')
  else
    payload=$(jq -nc --arg c "$command" --arg w "${PAYLOAD_CWD:-$cwd}" \
      '{tool_name: "Bash", cwd: $w, tool_input: {command: $c}}')
  fi
  if [[ -n "$pd" ]]; then
    OUT=$(cd "$cwd" && env PATH="$pd" ${RUN_ENV[@]+"${RUN_ENV[@]}"} CLAUDE_PROJECT_DIR="${RUN_PROJECT_DIR:-$REPO_ROOT}" \
            "$pd/bash" "$hook" <<<"$payload" 2>"$errf") || true
  else
    OUT=$(cd "$cwd" && env ${RUN_ENV[@]+"${RUN_ENV[@]}"} CLAUDE_PROJECT_DIR="${RUN_PROJECT_DIR:-$REPO_ROOT}" \
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
# worktree carrying the toml. $1 = leak (a staged fake PEM, assembled by _mk_pem), clean, or
# (#10696) untracked / clean-untracked (nothing but the config staged; leak.json only in the
# working tree, clean.txt untracked). Sets FX_ROOT and FX_WT to PHYSICAL paths (git reports toplevels physically).
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
    elif [[ "$mode" == untracked || "$mode" == clean-untracked ]]; then
      # #10696: the leak is in the working tree only; the index holds the config and nothing else.
      git add .gitleaks.toml
      echo hello > clean.txt
      if [[ "$mode" == untracked ]]; then
        jq -n --arg p "$(_mk_pem "t10696_sim_leak_payload_7q3kZx")" \
          '{variables: {private_key: {value: $p}}}' > leak.json
      fi
    else
      echo hello > f.txt; git add f.txt .gitleaks.toml
    fi
  )
  FX_ROOT=$(cd "$root" && pwd -P); FX_WT=$(cd "$root/.worktrees/wt" && pwd -P)
}

# A plain repo (own .gitleaks.toml) with a staged fake PEM. #10696 modes (leak NOT in the index):
#   untracked | tracked-modified | ignored | clean  (see _mk_sim_repo)
_mk_leaky_repo() {
  local mode="${1:-staged}" tmp; tmp=$(mktemp -d "$SUITE_TMP/leaky.XXXXXX")
  if [[ "$mode" != staged ]]; then _mk_sim_repo "$tmp" "$mode"; (cd "$tmp" && pwd -P); return 0; fi
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
  # #10696: 'git add -A && git commit -m "fix: tidy"' was a must-skip row here; detecting same-command
  # staging needs the lexer's argv, so it FLIPPED to must-match (see _t_sim_prefilter).
  for w in 'git commit -m x' 'git commit --amend --no-edit' 'git status && git commit -m x'; do
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

# ===========================================================================================
# #10696 — the would-be index. The hook used to scan the index BEFORE the command it guards had
# run, so `git add -A && git commit`, `commit -a` and `commit -- <path>` were scanned against an
# index that did not yet hold the content the commit records. These arms were written FIRST
# (cq-write-failing-tests-before) against the plan's API names; each is RED on the unmodified hook
# for the stated reason (a missing function or a missing behaviour), never for a fixture typo.
#
# TWO STUB TIERS (plan "Stub tiers"):
#   structural  PATH = a stub dir holding the git SHIM (logs every call, mutates nothing, selectable
#               failure modes) and the RECORDING gitleaks stub (copies the index it is handed, lists
#               it, reports a finding when an INDEXED blob holds the fixture's synthetic body). ~0.3 s
#               a run, and the decision is a function of what the SIM INDEX holds.
#   canary      the real gitleaks (a short set: groups 1, 2, 4, 6, 8 and one linked worktree).
# Secret shapes are synthesized at run time by _mk_pem (header/footer split across printf
# arguments); the body is explicit and NON-sequential, because the default _mk_pem body is
# allowlisted by the pinned .gitleaks.toml (measured: it scans clean). Each leak fixture has a
# fixture control (`gitleaks detect --no-git`, rc 1) in _t_sim_fixtures.
#
# CONTRACTS THESE ARMS PIN (the implementation must match; each was ruled in decision-challenges.md):
#   ctr_stage_dump        TEST-ONLY (defined below, exported to the child shells): one summary line
#                         `stage stages=.. opaque=.. refuse=.. all=.. paths_n=.. paths_literal=..
#                         cd_first=..`, one `refuse_why: ..` line, and one
#                         `add exact=.. force=.. lit=.. own_C=.. words: <verb> <%q words>` line per
#                         add/stage record, read from the walker's CTR_* arrays. Asserted by substring on
#                         key=value tokens only. (Decision-challenges row 38.)
#   CIS_DEADLINE_SECONDS  read by commit-index-sim.sh, effective = min(30, v) when v is an integer below 30,
#                         anything else ignored, 0 = no time left (deny). (Decision-challenges row 37.)
#   Deny-text fragments   `its own call` (every sim failure + config-transforming refusal),
#                         `.gitignore` and `separate call` (untracked-file recovery), `force-add`
#                         (non-literal force-add), `the commit in the next` (tooling repair),
#                         no `restore --staged` in a sim deny.
#   Ledger                rule id git-commit-secret-scan-sim-deny (a simulation failure; row text carries
#                         `cause=<enumerated>`: pathspec-missing | sim-timeout | superset-failed ...).
#                         There is no sim-failed bypass row (decision-challenges row 25).
# ===========================================================================================
_SIM_MARK=t10696_sim_leak
_SIM_BODY=t10696_sim_leak_payload_7q3kZx
SIM_N=0
SIM_SNAP=0
SIM_SHIM=""
SIM_SHIMDIR=""
SIM_REAL_GIT=""
SIM_PD=""
SIM_ENV=()
SIM_LOG=""
SIM_REC=""
SIM_TMP=""
SIM_R=""
ROWS_N=0
ROWS_TXT=""

_contains() { [[ "$1" == *"$2"* ]]; }
# Non-vacuous negative: the text must EXIST (a deny reason) and must not contain the needle. On a run
# that allowed, the reason is empty, and a bare _lacks would pass for a reason that is not the hook's.
_nlacks() { [[ -n "$1" && "$1" != *"$2"* ]]; }
# _t <label> <detail> <command...> — one assertion: ok when the command succeeds. The command runs
# in an `if`, so errexit is off inside it and a failing test cannot end the suite.
_t() {
  local label="$1" detail="$2"; shift 2
  if "$@"; then _report "$label" ok; else _report "$label" fail "$detail"; fi
}

# The git SHIM (PATH `git`): resolves the real git by ABSOLUTE path (SHIM_REAL_GIT), logs one line
# per call to $SHIM_LOG with printf %q (never to stdout/stderr), mutates nothing, and execs. It finds
# the verb after `-C <dir>` / `-c k=v`. "SIM=1" = GIT_INDEX_FILE is set and is not $SHIM_REAL_INDEX,
# i.e. a would-be-index call (fixture and gitleaks-internal calls pass through). Failure modes are
# read at CALL time: SHIM_FAIL=addA (a sim `add` carrying -A/--all), replay (a sim `add` carrying
# neither -A/--all nor -u: the exact replay), anyadd; SHIM_MSG / SHIM_RC choose the output. SHIM_FAILV=<verb> fails
# every call of that verb (check-attr, checkout-index, ...) with rc 128.
_sim_init() {
  [[ -n "$SIM_SHIM" ]] && return 0
  SIM_REAL_GIT=$(command -v git)
  SIM_SHIM="$SUITE_TMP/git-shim.sh"
  cat > "$SIM_SHIM" <<'SHIM'
#!/usr/bin/env bash
real="${SHIM_REAL_GIT:?}"
args=("$@"); i=0; n=${#args[@]}; verb=""
while [ "$i" -lt "$n" ]; do
  case "${args[$i]}" in
    -C|-c|--git-dir|--work-tree|--namespace|--config-env|--attr-source|--super-prefix) i=$((i + 2)) ;;
    -*) i=$((i + 1)) ;;
    *) verb="${args[$i]}"; break ;;
  esac
done
sim=0
if [ -n "${GIT_INDEX_FILE-}" ] && [ "${GIT_INDEX_FILE}" != "${SHIM_REAL_INDEX-}" ]; then sim=1; fi
if [ -n "${SHIM_LOG-}" ]; then
  # ONE write per call: the two ends of a pipeline (`git diff | git check-attr`) log concurrently, and a log line
  # written in pieces interleaved under load (a flake that hid the pin on one of the two lines).
  qargs=$(printf '%q ' "$@")
  printf 'SIM=%s VERB=%s LC_ALL=%s OPTLOCKS=%s IDX=%s OBJ=%s ALT=%s ARGS=%s\n' "$sim" "$verb" "${LC_ALL-<unset>}" "${GIT_OPTIONAL_LOCKS-<unset>}" \
    "${GIT_INDEX_FILE-<unset>}" "${GIT_OBJECT_DIRECTORY-<unset>}" "${GIT_ALTERNATE_OBJECT_DIRECTORIES-<unset>}" "$qargs" >> "$SHIM_LOG" 2>/dev/null
fi
if [ -n "${SHIM_FAILV-}" ] && [ "$verb" = "$SHIM_FAILV" ]; then
  printf 'fatal: shim-injected %s failure\n' "$verb" >&2
  exit 128
fi
if [ "$sim" = 1 ] && [ "$verb" = add ] && [ -n "${SHIM_FAIL-}" ]; then
  broad=0; upd=0
  for a in "$@"; do
    case "$a" in -A|--all) broad=1 ;; -u|--update) upd=1 ;; esac
  done
  fail=0
  case "$SHIM_FAIL" in
    addA) [ "$broad" = 1 ] && fail=1 ;;
    replay) [ "$broad" = 0 ] && [ "$upd" = 0 ] && fail=1 ;;
    anyadd) fail=1 ;;
  esac
  if [ "$fail" = 1 ]; then
    printf '%s\n' "${SHIM_MSG:-fatal: shim-injected add failure}" >&2
    exit "${SHIM_RC:-1}"
  fi
fi
exec "$real" "$@"
SHIM
  chmod +x "$SIM_SHIM"
  SIM_SHIMDIR=$(mktemp -d "$SUITE_TMP/shimdir.XXXXXX")
  cp "$SIM_SHIM" "$SIM_SHIMDIR/git"
}

# A stub PATH for the structural tier: the recording gitleaks stub, perl (the lexer), timeout (unless
# $1 is the empty string: the no-timeout host), and the git SHIM in place of the real git.
_mk_sim_path() {
  local d; d=$(_mk_stub_path record perl "${1-}")
  assert_fixture_dir "$d"; rm -f "$d/git"; cp "$SIM_SHIM" "$d/git"; chmod +x "$d/git"
  printf '%s\n' "$d"
}

# Fixtures. The leak is NEVER in the index (the previous shapes staged it, so the unmodified hook
# already denied them). Every mode commits a clean seed first (seed.txt, tracked.json, other.json,
# docs/f.txt, .gitignore, .gitleaks.toml) and then leaves, in the working tree only:
#   untracked         clean.txt, "my file.md", and leak.json holding the synthetic PEM
#   tracked-modified  tracked.json now holds the PEM; other.json changed (clean); clean.txt untracked
#   ignored           clean.txt untracked; ignored.pem (gitignored) holds the PEM
#   clean             clean.txt untracked and nothing else
_mk_sim_repo() {  # <existing empty dir> <mode>
  local dir="$1" mode="$2" pem
  pem=$(_mk_pem "$_SIM_BODY")
  (
    cd "$dir" || exit 1
    git init -q -b main
    git config user.email t@t; git config user.name t
    cp "$GITLEAKS_TOML" .gitleaks.toml
    printf 'ignored.pem\n' > .gitignore
    echo seed > seed.txt
    printf '{"k":"v1"}\n' > tracked.json
    printf '{"k":"o1"}\n' > other.json
    mkdir docs; echo doc > docs/f.txt
    git add -A
    git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m seed
    case "$mode" in
      untracked)
        echo hello > clean.txt; echo md > "my file.md"
        jq -n --arg p "$pem" '{variables: {private_key: {value: $p}}}' > leak.json ;;
      tracked-modified)
        jq -n --arg p "$pem" '{key: $p}' > tracked.json
        printf '{"k":"o2"}\n' > other.json; echo hello > clean.txt ;;
      ignored) echo hello > clean.txt; printf '%s\n' "$pem" > ignored.pem ;;
      clean) echo hello > clean.txt ;;
      *) echo "_mk_sim_repo: bad mode $mode" >&2; exit 1 ;;
    esac
  )
}

# The old shape, with this suite's synthetic body: the leak is STAGED, so a plain commit is the
# separate-call case (no same-command staging) and the unmodified hook already denies it.
_mk_staged_repo() {
  local r; r=$(_mk_leaky_repo untracked)
  git -C "${r:?}" add leak.json
  printf '%s\n' "$r"
}

# FIXTURE CONTROL: the pinned .gitleaks.toml must (or must not) flag this one file.
_fx_ctrl() {  # <label> <file> <expected rc 0|1>
  local label="$1" f="$2" want="$3" d rc=0
  d=$(mktemp -d "$SUITE_TMP/fxc.XXXXXX")
  cp "$f" "$d/"
  gl_run 120 gitleaks detect --no-git --source "$d" --config "$GITLEAKS_TOML" --redact --no-banner \
    --exit-code 1 --report-format json --report-path "$d.json" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq "$want" ]]; then _report "$label" ok
  else _report "$label" fail "FIXTURE BROKEN: gitleaks detect --no-git on $(basename "$f") exited $rc, wanted $want (so no verdict below proves anything)"; fi
}

# Run the hook structurally. $3 = a stub PATH dir (default $SIM_PD); "real" = the real gitleaks with
# only the git shim in front of PATH. Every run gets its own TMPDIR, shim log and recording dir.
# SIM_ENV (array of NAME=value) is added for this run; SIM_TMP_FIXED pre-seeds the TMPDIR.
_sim_run() {  # <cwd> <command> [pd|real]
  local cwd="$1" cmd="$2" pd="${3-$SIM_PD}" saved=() e
  for e in ${RUN_ENV[@]+"${RUN_ENV[@]}"}; do saved+=("$e"); done
  SIM_N=$((SIM_N + 1))
  SIM_REC="$SUITE_TMP/rec.$SIM_N"; mkdir -p "$SIM_REC"
  SIM_LOG="$SUITE_TMP/shim.$SIM_N.log"; assert_fixture_dir "$SIM_LOG"; : > "$SIM_LOG"
  SIM_TMP="${SIM_TMP_FIXED:-$SUITE_TMP/tmp.$SIM_N}"; mkdir -p "$SIM_TMP"
  # SIM_ENV comes LAST: a case can override TMPDIR (a relative one) or any other variable of the run.
  RUN_ENV=(${saved[@]+"${saved[@]}"} "TMPDIR=$SIM_TMP" "SHIM_LOG=$SIM_LOG" \
           "SHIM_REAL_GIT=$SIM_REAL_GIT" "GL_REC_DIR=$SIM_REC" ${SIM_ENV[@]+"${SIM_ENV[@]}"})
  if [[ "$pd" == real ]]; then
    RUN_ENV+=("PATH=$SIM_SHIMDIR:$PATH")
    _run_cmd "$cwd" "$cmd"
  else
    RUN_ENV+=("GL_REC_MARK=$_SIM_MARK")
    _run_cmd "$cwd" "$cmd" "$pd"
  fi
  RUN_ENV=(${saved[@]+"${saved[@]}"})
}

# _verdict <label> <allow|deny> [fragment | !fragment ...] — compares OUT against the decision and
# the reason fragments (a leading ! means the reason must NOT contain it). Sets SIM_R.
_verdict() {
  local label="$1" want="$2" d r s; shift 2
  d=$(_decision "$OUT"); r=$(_reason "$OUT")
  SIM_R="$r"
  for s in "$@"; do
    if [[ "$s" == '!'* ]]; then
      if [[ "$r" == *"${s#!}"* ]]; then
        _report "$label" fail "reason must not contain '${s#!}' (decision=$d reason=${r:0:240})"; return 0
      fi
    elif [[ "$r" != *"$s"* ]]; then
      _report "$label" fail "reason lacks '$s' (decision=$d reason=${r:0:240})"; return 0
    fi
  done
  if [[ "$d" == "$want" ]]; then _report "$label" ok
  else _report "$label" fail "decision=$d want=$want reason=${r:0:200} err=${ERR:0:160}"; fi
}
_sx() {  _sim_run "$2" "$3"; _verdict "$1" "$4" "${@:5}"; }       # <label> <cwd> <cmd> <want> [frag..]
_sxr() { _sim_run "$2" "$3" real; _verdict "$1" "$4" "${@:5}"; }  # the real-gitleaks canary tier

# Accessors over the last _sim_run.
_sim_adds() { grep '^SIM=1 VERB=add ' "$SIM_LOG" 2>/dev/null || true; }
_sim_add_n() { local a; a=$(_sim_adds); if [[ -z "$a" ]]; then echo 0; else printf '%s\n' "$a" | wc -l | tr -d ' '; fi; }
_sim_verb_n() { local c; c=$(grep -c "^SIM=1 VERB=$1 " "$SIM_LOG" 2>/dev/null || true); echo "${c:-0}"; }
_log_n() { wc -l < "$SIM_LOG" | tr -d ' '; }
# The sim adds are the proof of WHICH replay ran. `-A` = the superset; `<word>` = an exact replay.
_exact_add() {  # <word>: a sim add names it and no sim add is the superset or interactive
  local a; a=$(_sim_adds)
  [[ "$a" == *" $1 "* && "$a" != *" -A "* && "$a" != *" -p "* ]]
}
_superset_add() {  # a sim add ran with -A and none ran with -p / -e
  local a; a=$(_sim_adds)
  [[ "$a" == *" -A "* && "$a" != *" -p "* && "$a" != *" -e "* ]]
}
_all_adds_superset() {  # every sim add is `-A` (two roots, mixed directories)
  local a l; a=$(_sim_adds); [[ -n "$a" ]] || return 1
  while IFS= read -r l; do [[ "$l" == *" -A "* ]] || return 1; done <<<"$a"
}
_has_update() { local a; a=$(_sim_adds); [[ "$a" == *" -u "* && "$a" != *" -A "* ]]; }
_no_sim() {
  [[ "$(_log_n)" -gt 0 && "$(_sim_add_n)" -eq 0 ]] || return 1
  [[ -z "$(find "$SIM_TMP" -mindepth 1 -print -quit 2>/dev/null)" ]] || return 1
  return 0
}
_tmp_empty() { [[ -z "$(find "$SIM_TMP" -mindepth 1 -print -quit 2>/dev/null)" ]]; }
# The recorded sim index listings (`git ls-files -s` of the index the gitleaks stub was handed).
_rec_ls() { cat "$SIM_REC"/ls.* 2>/dev/null || true; }
_rec_has() {  # <path> in any recorded index
  _rec_ls | awk -F'\t' -v p="$1" '$2 == p { f = 1 } END { exit !f }'
}
_rec_mode_of() { _rec_ls | awk -F'\t' -v p="$1" '$2 == p { split($1, a, " "); print a[1]; exit }' || true; }
_rec_field() {  # <n-th git call> <field 3|4|5> of calls.log
  awk -F'\t' -v n="$1" -v f="$2" '$2 == "git" { c++; if (c == n) { print $f; exit } }' "$SIM_REC/calls.log" 2>/dev/null || true
}
_rec_git_calls() { awk -F'\t' '$2 == "git" { c++ } END { print c + 0 }' "$SIM_REC/calls.log" 2>/dev/null || echo 0; }
_cat_has() { local f; for f in "$SIM_REC"/"$1".*; do [[ -f "$f" ]] && grep -q -F -e "$2" "$f" && return 0; done; return 1; }

# _rows_since_mark <rule_id> — how many ledger rows with exactly this rule id the LAST hook run wrote
# (the existing _last_prefix cannot count). Sets ROWS_N and ROWS_TXT (the row texts, newline joined).
_rows_since_mark() {
  local f="$SOLEUR_TEST_INCIDENT_ROOT/.claude/.rule-incidents.jsonl" id="$1"
  ROWS_N=0; ROWS_TXT=""
  [[ -f "$f" ]] || return 0
  ROWS_N=$(tail -n "+$(( ${_JOURNAL_MARK:-0} + 1 ))" "$f" | jq -s --arg id "$id" '[.[] | select(.rule_id == $id)] | length' 2>/dev/null) || ROWS_N=0
  ROWS_TXT=$(tail -n "+$(( ${_JOURNAL_MARK:-0} + 1 ))" "$f" | jq -r --arg id "$id" 'select(.rule_id == $id) | .rule_text_prefix' 2>/dev/null) || ROWS_TXT=""
}

# Snapshot / compare helpers for the Guard 2 invariants: the real index BYTES (cmp, never a hash tool
# that is absent on macOS), the real loose-object count, the real git directory listing, and the
# working tree (status plus a checksum of every file). --no-optional-locks so taking the snapshot
# cannot itself refresh the index it is about to compare.
_snap() {  # <repo> <prefix>
  local repo="$1" pre="$2" gd cd2 op
  gd=$(git -C "$repo" rev-parse --absolute-git-dir)
  cd2=$(cd "$repo" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
  op=$(git -C "$repo" rev-parse --git-path objects); case "$op" in /*) ;; *) op="$repo/$op" ;; esac
  cp "$gd/index" "$pre.index" 2>/dev/null || : > "$pre.index"
  find "$op" -type f | wc -l | tr -d ' ' > "$pre.objn"
  { (cd "$gd" && find . -type f | sort); (cd "$cd2" && find . -type f | sort); } > "$pre.gitdir"
  git --no-optional-locks -C "$repo" status --porcelain -uall > "$pre.status" 2>/dev/null || true
  (cd "$repo" && find . -path ./.git -prune -o -type f -exec cksum {} + | sort) > "$pre.tree" 2>/dev/null || true
}
# _assert_repo_untouched <label> <repo> -- <command...> : snapshot, run the command IN THIS SHELL,
# snapshot again, compare. The snapshot is taken INSIDE, before the run (a snapshot taken after the
# hook could not see what it changed): _t_sim_selftest drives it around a command that mutates.
_assert_repo_untouched() {
  local label="$1" repo="$2" a b bad=""; shift 3
  SIM_SNAP=$((SIM_SNAP + 1))
  a="$SUITE_TMP/snap.$SIM_SNAP.a"; b="$SUITE_TMP/snap.$SIM_SNAP.b"
  _snap "$repo" "$a"
  "$@"
  _snap "$repo" "$b"
  cmp -s "$a.index" "$b.index" || bad+=" index"
  cmp -s "$a.objn" "$b.objn" || bad+=" objects"
  cmp -s "$a.gitdir" "$b.gitdir" || bad+=" gitdir"
  cmp -s "$a.status" "$b.status" || bad+=" status"
  cmp -s "$a.tree" "$b.tree" || bad+=" tree"
  if [[ -z "$bad" ]]; then _report "$label" ok; else _report "$label" fail "the run changed:$bad"; fi
}
_mut_index() { git -C "${1:?}" add clean.txt; }
_mut_objects() { echo "mutation-$RANDOM" | git -C "${1:?}" hash-object -w --stdin >/dev/null; }
_mut_tree() { echo changed >> "$1/clean.txt"; }
_mut_gitdir() { : > "$1/.git/sharedindex.mutation"; }

# The helpers must be able to REJECT: a helper that always says yes leaves every arm green.
_t_sim_selftest() {
  _sim_init
  local repo out m
  repo=$(_mk_leaky_repo clean)
  out=$( ( _assert_repo_untouched "st-noop" "$repo" -- true ) 2>&1 ) || true
  if [[ "$out" != *"[ok] st-noop"* ]]; then
    printf '[FATAL] instrument self-test: _assert_repo_untouched failed a run that changed nothing (got: %s)\n' "${out:0:200}" >&2; exit 1
  fi
  for m in index objects tree gitdir; do
    repo=$(_mk_leaky_repo clean)
    out=$( ( _assert_repo_untouched "st-$m" "$repo" -- "_mut_$m" "$repo" ) 2>&1 ) || true
    if [[ "$out" != *"[FAIL] st-$m"* ]]; then
      printf '[FATAL] instrument self-test: _assert_repo_untouched did not see a %s mutation (got: %s)\n' "$m" "${out:0:200}" >&2; exit 1
    fi
  done
  # The verdict helpers must be able to FAIL: a `!fragment` that the reason contains, a missing fragment, a wrong
  # decision and a failing `_t` command each have to report [FAIL], or every negative assertion below is decoration.
  local sv='{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"needle here"}}'
  out=$( ( OUT="$sv"; ERR=""; _verdict "st-bang" deny "!needle" ) 2>&1 ) || true
  [[ "$out" == *"[FAIL] st-bang"* ]] || { printf '[FATAL] instrument self-test: _verdict accepted a reason that contains a !fragment (got: %s)\n' "${out:0:200}" >&2; exit 1; }
  out=$( ( OUT="$sv"; ERR=""; _verdict "st-miss" deny "absent" ) 2>&1 ) || true
  [[ "$out" == *"[FAIL] st-miss"* ]] || { printf '[FATAL] instrument self-test: _verdict accepted a reason lacking a fragment (got: %s)\n' "${out:0:200}" >&2; exit 1; }
  out=$( ( OUT="$sv"; ERR=""; _verdict "st-dec" allow ) 2>&1 ) || true
  [[ "$out" == *"[FAIL] st-dec"* ]] || { printf '[FATAL] instrument self-test: _verdict accepted the wrong decision (got: %s)\n' "${out:0:200}" >&2; exit 1; }
  out=$( ( OUT="$sv"; ERR=""; _verdict "st-ok" deny "needle" "!absent" ) 2>&1 ) || true
  [[ "$out" == *"[ok] st-ok"* ]] || { printf '[FATAL] instrument self-test: _verdict failed a matching verdict (got: %s)\n' "${out:0:200}" >&2; exit 1; }
  out=$( ( _t "st-t" "detail" false ) 2>&1 ) || true
  [[ "$out" == *"[FAIL] st-t"* ]] || { printf '[FATAL] instrument self-test: _t accepted a failing command (got: %s)\n' "${out:0:200}" >&2; exit 1; }
  out=$( ( _report "st-r" fail "d" ) 2>&1 ) || true
  [[ "$out" == *"[FAIL] st-r"* ]] || { printf '[FATAL] instrument self-test: _report did not report a failure (got: %s)\n' "${out:0:200}" >&2; exit 1; }
  # The shim and the recording stub are driven once, directly, so a dead log cannot read as a pass.
  local pd; pd=$(_mk_sim_path)
  repo=$(_mk_leaky_repo clean)
  _sim_run "$repo" "git commit -m x" "$pd"
  if [[ "$(_log_n)" -le 0 ]]; then
    printf '[FATAL] instrument self-test: the git shim logged nothing for a hook run\n' >&2; exit 1
  fi
  if [[ "$(_rec_git_calls)" -ne 1 ]]; then
    printf '[FATAL] instrument self-test: the recording stub saw %s gitleaks git calls for a plain commit, wanted 1\n' "$(_rec_git_calls)" >&2; exit 1
  fi
  # A row-counting helper that always says 0 would pass every "no row" control.
  repo=$(_mk_staged_repo)
  _sim_run "$repo" "git commit -m x" "$pd"
  _rows_since_mark git-commit-secret-scan
  if [[ "$ROWS_N" -ne 1 ]]; then
    printf '[FATAL] instrument self-test: _rows_since_mark counted %s rows for a staged-leak deny, wanted 1\n' "$ROWS_N" >&2; exit 1
  fi
}

# Fixture controls: every leak below is detected (rc 1) by the pinned config, and the clean file is not.
_t_sim_fixtures() {
  _needs_gl "S0 sim fixture controls" || return 0
  _sim_init
  local U T I W
  U=$(_mk_leaky_repo untracked); T=$(_mk_leaky_repo tracked-modified); I=$(_mk_leaky_repo ignored)
  _mk_bare_root_with_worktree untracked; W="$FX_WT"
  _fx_ctrl "S0 fixture control: untracked leak.json is flagged by the pinned .gitleaks.toml" "$U/leak.json" 1
  _fx_ctrl "S0 fixture control: modified tracked.json is flagged" "$T/tracked.json" 1
  _fx_ctrl "S0 fixture control: ignored.pem is flagged" "$I/ignored.pem" 1
  _fx_ctrl "S0 fixture control: bare-root worktree leak.json is flagged" "$W/leak.json" 1
  _fx_ctrl "S0 negative control: clean.txt is not flagged" "$U/clean.txt" 0
  _fx_ctrl "S0 negative control: the committed tracked.json is not flagged (unmodified fixture)" "$U/tracked.json" 0
}

# ---- pre-filter: which commands reach the lexer (Design 2) -----------------------------------
# Over-matching is safe (it only runs the lexer); UNDER-matching is the incident, so every
# staging form is pinned must-match, and the no-staging forms are pinned must-skip (property 2:
# a plain commit pays nothing). 'git add -A && git commit -m "fix: tidy"' FLIPPED from must-skip.
_t_sim_prefilter() {
  local lib="$REPO_ROOT/.claude/hooks/lib/commit-target-roots.sh" w v hd
  if [[ ! -r "$lib" ]]; then _report "G-pf: library exists" fail "$lib is not readable"; return 0; fi
  local match=(
    'git add -A && git commit -m x'
    'git add -A && git commit -m "fix: tidy"'
    'git stage f.txt && git commit -m x'
    'rtk git add clean.txt && rtk git commit -m x'
    'git commit -am x' 'git commit -a -m x' 'git commit -sam x' 'git commit -p -m x'
    'git commit -o f.txt -m x' 'git commit -i f.txt -m x'
    'git commit --all -m x' 'git commit --al -m x' 'git commit --only f.txt -m x' 'git commit --on f.txt -m x'
    'git commit --include f.txt -m x' 'git commit --inc f.txt -m x' 'git commit --interactive' 'git commit --patch'
    'git commit --pa' 'git commit --pathspec-from-file=f.txt'
    'git commit -m x -- f.txt'
    'git commit tracked.json -m x'
    'git commit tracked.json'
  )
  for v in apply update-index checkout cherry-pick merge revert stash am read-tree restore pull switch rebase submodule sparse-checkout; do
    match+=("git $v x && git commit -m x")
  done
  # A heredoc commit message that merely MENTIONS `git add` over-matches (it only costs a lexer run).
  hd=$(printf '%s\n' "git commit -m \"\$(cat <<'EOF'" 'fix: git add things' 'EOF' ')"')
  match+=("$hd")
  for w in "${match[@]}"; do
    if bash -c 'source "$1" && ctr_wants_lex "$2"' _ "$lib" "$w"; then _report "G-pf must-match: ${w//$'\n'/ / }" ok
    else _report "G-pf must-match: ${w//$'\n'/ / }" fail "ctr_wants_lex returned false (the walker would never see this staging form)"; fi
  done
  for w in 'git commit -m x' 'git commit -n -m x' 'git status && git commit -m x' 'git log --oneline && git commit -m x' \
           'git log --grep=commit' 'git commit -m "fix the commit scan"' 'git addr' 'git commit --amend --no-edit'; do
    if bash -c 'source "$1" && ctr_wants_lex "$2"' _ "$lib" "$w"; then
      _report "G-pf must-skip: $w" fail "ctr_wants_lex returned true (a perl spawn on the no-staging path)"
    else _report "G-pf must-skip: $w" ok; fi
  done
}

# ---- walker output through ctr_stage_dump -----------------------------------------------------
# One bash process walks every row (a process per row would cost seconds). The dump format is the
# CTO-ruled one (see the header); rows assert key=value tokens by SUBSTRING, never layout.
# The canonical text form of the walker's staging facts. TEST-ONLY: production never prints them. Exported so the
# child shells that source the walker can call it.
ctr_stage_dump() {
  local i=0 n="${#CTR_ADD_EXACT[@]}" k
  printf 'stage stages=%s opaque=%s refuse=%s unsim=%s all=%s paths_n=%s paths_literal=%s cd_first=%s\n' \
    "${CTR_COMMIT_STAGES:-0}" "${CTR_STAGE_OPAQUE:-0}" "${CTR_STAGE_REFUSE:-0}" "${CTR_STAGE_UNSIMULABLE:-0}" \
    "${CTR_COMMIT_ALL:-0}" "${#CTR_COMMIT_PATHS[@]}" "${CTR_COMMIT_PATHS_LITERAL:-1}" "${CTR_STAGE_CD_FIRST:-0}"
  printf 'refuse_why: %s\n' "${CTR_STAGE_REFUSE_WHY:-}"
  while [ "$i" -lt "$n" ]; do
    printf 'add exact=%s force=%s lit=%s own_C=%s words:' "${CTR_ADD_EXACT[$i]}" "${CTR_ADD_FORCE[$i]}" "${CTR_ADD_LIT[$i]}" "${CTR_ADD_OWNC[$i]}"
    k=0
    while [ "$k" -lt "${CTR_ADD_NW[$i]}" ]; do printf ' %q' "${CTR_ADD_ARGV[$((${CTR_ADD_OFF[$i]} + k))]}"; k=$((k + 1)); done
    printf '\n'
    i=$((i + 1))
  done
  return 0
}
export -f ctr_stage_dump
SD_L=(); SD_C=(); SD_T=()
_sd_add() {  # <label> <command> <token>...
  local label="$1" cmd="$2" IFS=$'\037'; shift 2
  SD_L+=("$label"); SD_C+=("$cmd"); SD_T+=("$*")
}
_sd_check() {
  local lib="$REPO_ROOT/.claude/hooks/lib/commit-target-roots.sh" out i=0 cur="" line tok miss row n="${#SD_C[@]}"
  local rows=() toks IFS_SAVE="$IFS"
  out=$(env HOME=/h bash -c '
    source "$1" || { echo "@@SOURCEFAIL@@"; exit 0; }
    shift
    UNEXP_VAR=plain   # a shell variable that is set and NOT exported (the bare-assignment rows)
    for c in "$@"; do
      ctr_collect "$c"
      if declare -f ctr_stage_dump >/dev/null 2>&1; then ctr_stage_dump; else echo "@@NODUMP@@"; fi
      printf "\n@@ROW@@\n"
    done' _ "$lib" "${SD_C[@]}" 2>&1) || true
  while IFS= read -r line; do
    if [[ "$line" == "@@ROW@@" ]]; then rows[i]="$cur"; i=$((i + 1)); cur=""; else cur+="$line"$'\n'; fi
  done <<<"$out"
  for ((i = 0; i < n; i++)); do
    row="${rows[$i]:-}"; miss=""
    if [[ "$row" == *"@@NODUMP@@"* || -z "$row" ]]; then
      _report "walker-dump: ${SD_L[$i]}" fail "ctr_stage_dump does not exist (the walker records no staging facts yet)"; continue
    fi
    IFS=$'\037' read -r -a toks <<<"${SD_T[$i]}"; IFS="$IFS_SAVE"
    for tok in ${toks[@]+"${toks[@]}"}; do
      [[ "$row" == *"$tok"* ]] || miss+=" [$tok]"
    done
    if [[ -z "$miss" ]]; then _report "walker-dump: ${SD_L[$i]}" ok
    else _report "walker-dump: ${SD_L[$i]}" fail "missing${miss} in: ${row//$'\n'/ | }"; fi
  done
  SD_L=(); SD_C=(); SD_T=()
}

_benign_operand() {
  case "$1" in
    --unified) echo 3 ;; --inter-hunk-context) echo 1 ;; --cleanup) echo strip ;; --date) echo '2020-01-01 00:00' ;;
    --author) echo 'A <a@b.c>' ;; --file|--template) echo /dev/null ;; --trailer) echo 'k=v' ;; --message) echo m ;; *) echo HEAD ;;
  esac
}

# ---- unit C rows (CTO rows 22 to 26): the closed world, the environment allowlist, the commit record --------------
_sd_unit_c_rows() {
  local b64 b65 a64 a65 k
  # row 22: unknown is opaque
  _sd_add 'an expanded subcommand is opaque' 'git "$S" f.txt && git commit -m x' 'stages=1' 'opaque=1'
  _sd_add 'a dashed git-add is opaque' 'git-add f.txt && git commit -m x' 'stages=1' 'opaque=1'
  _sd_add 'a dashed git-add by full path is opaque' '/usr/lib/git-core/git-add f.txt && git commit -m x' 'opaque=1'
  _sd_add 'a dashed verb hidden in an expanded command word is opaque' '$(git --exec-path)/git-add f.txt && git commit -m x' 'opaque=1'
  _sd_add 'a dashed git-commit is a commit that reads its flags (-a)' 'git-commit -a -m x' 'stages=1' 'all=1'
  _sd_add 'a staging verb in a non-git record is opaque (make add)' 'make add && git commit -m x' 'stages=1' 'opaque=1'
  _sd_add 'a staging verb in a non-git record is opaque (npm add)' 'npm add left-pad && git commit -m x' 'opaque=1'
  _sd_add 'a non-git record without a staging verb is not opaque' 'echo hello && git commit -m x' 'stages=0' 'opaque=0'
  _sd_add 'a launcher with git behind it is walked, not opaque (timeout)' 'timeout 5 git add f.txt && git commit -m x' 'opaque=0' 'exact=1'
  _sd_add 'an inline alias.* key is REFUSED on a staging record' 'git -c alias.add=x add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'an inline alias.* key via --config-env is REFUSED' 'git --config-env=alias.add=V add f.txt && git commit -m x' 'refuse=1'
  # row 23: the environment allowlist
  _sd_add 'HOME= on a staging record is refused' 'HOME=/x git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'GIT_EDITOR= is on the allowlist' 'GIT_EDITOR=true git add f.txt && git commit -m x' 'refuse=0' 'exact=1'
  _sd_add 'LC_ALL= is on the allowlist' 'LC_ALL=C git add f.txt && git commit -m x' 'refuse=0'
  _sd_add 'CI= GIT_AUTHOR_NAME= are on the allowlist' 'CI=1 GIT_AUTHOR_NAME=x git add f.txt && git commit -m x' 'refuse=0'
  _sd_add 'GIT_PAGER= TERM= NO_COLOR= TZ= LANG= are on the allowlist' 'GIT_PAGER=cat TERM=dumb NO_COLOR=1 TZ=UTC LANG=C git add f.txt && git commit -m x' 'refuse=0'
  _sd_add 'a name outside the allowlist among allowed ones is refused' 'LC_ALL=C PATH=/x git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'PATH+= is an assignment too' 'PATH+=:/x git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'env NAME= outside the allowlist is refused' 'env HOME=/x git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'env CI= is allowed' 'env CI=1 git add f.txt && git commit -m x' 'refuse=0'
  _sd_add 'env -i is refused' 'env -i git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'env -u is refused' 'env -u HOME git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'env -uHOME is refused' 'env -uHOME git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'env --unset=HOME is refused' 'env --unset=HOME git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'env --unset HOME is refused' 'env --unset HOME git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'env --ignore-environment is refused' 'env --ignore-environment git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'env - is refused' 'env - git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'env -iC <dir> is refused (a bundle)' 'env -iC /a git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'sudo on a staging record is refused' 'sudo git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'doas on a staging record is refused' 'doas git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'runuser on a staging record is refused' 'runuser -u x git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'a launcher that keeps the environment is not refused (nice)' 'nice git add f.txt && git commit -m x' 'refuse=0'
  _sd_add 'export of a name outside the allowlist before a staging command is refused' 'export HOME=/x; git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'unset of a name outside the allowlist is refused' 'unset HOME; git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'a bare assignment before a staging command is refused' 'HOME=/x; git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'a plain shell variable assignment is not in git environment (not refused)' 'F=1; git add f.txt && git commit -m x' 'refuse=0'
  _sd_add 'a bare assignment of a set but unexported name is not refused (git cannot see it)' 'UNEXP_VAR=1; git add f.txt && git commit -m x' 'refuse=0'
  _sd_add 'a bare GIT_* assignment is refused' 'GIT_CONFIG_COUNT=1; git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'declare -x of an outside name is refused' 'declare -x HOME=/x; git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'export of an allowlisted name is not refused' 'export LC_ALL=C; git add f.txt && git commit -m x' 'refuse=0'
  _sd_add 'an export in a command that stages nothing is not refused' 'export HOME=/x; git commit -m x' 'stages=0' 'refuse=0'
  # row 24: a commit record that stages
  _sd_add 'a commit -a under an outside env prefix is refused' 'HOME=/x git commit -a -m x' 'stages=1' 'refuse=1'
  _sd_add 'a commit that stages nothing under an outside env prefix is untouched' 'HOME=/x git commit -m x' 'stages=0' 'refuse=0'
  _sd_add 'a commit -a with a refused -c key is refused' 'git -c core.hooksPath=/x commit -a -m x' 'refuse=1'
  _sd_add 'a commit with a refused -c key that stages nothing is untouched' 'git -c core.hooksPath=/x commit -m x' 'stages=0' 'refuse=0'
  _sd_add 'a commit with a pathspec and --config-env=core.* is refused' 'git --config-env=core.fsmonitor=V commit -m x -- f.txt' 'refuse=1'
  _sd_add 'a commit -a with --namespace is refused' 'git --namespace n commit -a -m x' 'refuse=1'
  _sd_add 'a staging commit whose subcommand an unknown option hid is refused under an outside env prefix' 'HOME=/x git --exec foo commit -a -m x' 'stages=1' 'refuse=1'
  _sd_add 'a staging commit whose subcommand an unknown option hid is refused under a refused -c key' 'git -c core.hooksPath=/x --exec foo commit -a -m x' 'refuse=1'
  _sd_add 'a commit -o under sudo is refused' 'sudo git commit -o f.txt -m x' 'refuse=1'
  _sd_add 'a commit --all under env -i is refused' 'env -i git commit --all -m x' 'refuse=1'
  # commit flags: the known set, the bundle cap
  _sd_add 'an unknown short option makes the stage opaque (-N)' 'git commit -N -m x' 'stages=1' 'opaque=1'
  _sd_add 'an unknown short option inside a bundle is opaque (-nZ)' 'git commit -nZ -m x' 'opaque=1'
  for k in s n v q e z h; do _sd_add "the known short option -$k stages nothing" "git commit -$k -m x" 'stages=0' 'opaque=0'; done
  _sd_add 'a bundle of known options stages nothing' 'git commit -nsvqez -m x' 'stages=0' 'opaque=0'
  printf -v b64 '%64s' ''; b64="${b64// /n}"; b65="${b64}n"
  printf -v a64 '%64s' ''; a64="${a64// /A}"; a65="${a64}A"
  _sd_add 'a 64-character option bundle is read' "git commit -$b64 -m x" 'stages=0' 'opaque=0'
  _sd_add 'a 65-character option bundle is opaque' "git commit -$b65 -m x" 'opaque=1'
  _sd_add 'a long -m<message> attached operand is not a bundle' "git commit -m$(printf '%80s' '' | tr ' ' x)" 'stages=0' 'opaque=0'
  _sd_add 'a 64-character add bundle is read' "git add -$a64 f.txt && git commit -m x" 'exact=1'
  _sd_add 'a 65-character add bundle is non-exact' "git add -$a65 f.txt && git commit -m x" 'exact=0'
  # row 26: content from outside the working tree
  _sd_add 'update-index --add --cacheinfo is unsimulable' 'git update-index --add --cacheinfo 100644,0123456789012345678901234567890123456789,f.txt && git commit -m x' 'stages=1' 'unsim=1'
  _sd_add 'update-index --index-info is unsimulable' 'git update-index --index-info && git commit -m x' 'unsim=1'
  _sd_add 'update-index --add alone is unsimulable' 'git update-index --add f.txt && git commit -m x' 'unsim=1'
  _sd_add 'an abbreviated update-index --cacheinfo (--cac) is unsimulable' 'git update-index --cac 100644,0123456789012345678901234567890123456789,f.txt && git commit -m x' 'unsim=1'
  _sd_add 'update-index --refresh is opaque, not unsimulable' 'git update-index --refresh && git commit -m x' 'stages=1' 'opaque=1' 'unsim=0'
  _sd_add 'apply --index is unsimulable' 'git apply --index p.diff && git commit -m x' 'unsim=1'
  _sd_add 'apply --cached is unsimulable' 'git apply --cached p.diff && git commit -m x' 'unsim=1'
  _sd_add 'apply --3way is unsimulable' 'git apply --3way p.diff && git commit -m x' 'unsim=1'
  _sd_add 'apply -3 is unsimulable' 'git apply -3 p.diff && git commit -m x' 'unsim=1'
  _sd_add 'an abbreviated apply --cac is unsimulable' 'git apply --cac p.diff && git commit -m x' 'unsim=1'
  _sd_add 'a plain apply is opaque, not unsimulable' 'git apply p.diff && git commit -m x' 'stages=1' 'opaque=1' 'unsim=0'
  _sd_add 'apply --check is opaque, not unsimulable' 'git apply --check p.diff && git commit -m x' 'opaque=1' 'unsim=0'
  _sd_add 'an unknown global option that hid the verb still finds update-index --add' 'git --exec foo update-index --add f.txt && git commit -m x' 'unsim=1'
  _sd_add 'an unknown global option that hid the verb still finds apply --cached' 'git --exec foo apply --cached p.diff && git commit -m x' 'unsim=1'
  _sd_add 'a command without them has unsim=0' 'git add f.txt && git commit -m x' 'unsim=0'
}

_t_sim_dump() {
  local v o lib="$REPO_ROOT/.claude/hooks/lib/commit-target-roots.sh" ctl
  [[ -r "$lib" ]] || { _report "walker-dump: library exists" fail "$lib is not readable"; return 0; }

  # --- staging records ---
  _sd_add 'git add -A is one exact record' 'git add -A && git commit -m x' 'stages=1' 'opaque=0' 'refuse=0' 'exact=1' 'force=0' 'words: add -A'
  _sd_add 'git stage is recorded like add' 'git stage f.txt && git commit -m x' 'stages=1' 'exact=1' 'words: stage f.txt'
  _sd_add 'git rm is recognised and IGNORED (adds no blob)' 'git rm f.txt && git commit -m x' 'stages=0' 'opaque=0'
  _sd_add 'git rm --cached is ignored' 'git rm --cached f.txt && git commit -m x' 'stages=0' 'opaque=0'
  _sd_add 'git mv is recognised and IGNORED' 'git mv a.txt b.txt && git commit -m x' 'stages=0' 'opaque=0'
  _sd_add 'a plain commit stages nothing' 'git commit -m x' 'stages=0' 'opaque=0' 'refuse=0' 'all=0' 'paths_n=0'
  _sd_add 'two add records, both kept in text order' 'git add clean.txt && git add leak.json && git commit -m x' 'stages=1' 'words: add clean.txt' 'words: add leak.json'
  _sd_add 'an add AFTER the last commit is still recorded (over-scan only)' 'git commit -m x; git add leak.json' 'stages=1' 'words: add leak.json'
  for v in apply update-index checkout cherry-pick merge revert stash am read-tree restore pull switch rebase submodule sparse-checkout; do
    _sd_add "stage-unknown verb '$v' makes the stage opaque (superset)" "git $v x && git commit -m x" 'stages=1' 'opaque=1'
  done
  _sd_add 'an expansion command word followed by a staging word is opaque' '"$GIT" add f.txt && git commit -m x' 'opaque=1'
  # --- launchers: the pass-through allowlist is exact, everything else is non-exact ---
  _sd_add 'rtk is a pass-through launcher (exact)' 'rtk git add f.txt && rtk git commit -m x' 'exact=1' 'words: add f.txt'
  _sd_add 'timeout is a pass-through launcher (exact)' 'timeout 5 git add f.txt && git commit -m x' 'exact=1'
  _sd_add 'nice is a pass-through launcher (exact)' 'nice -n 5 git add f.txt && git commit -m x' 'exact=1'
  _sd_add 'sudo is a pass-through launcher (exact)' 'sudo git add f.txt && git commit -m x' 'exact=1'
  _sd_add 'env is a pass-through launcher (exact)' 'env FOO=1 git add f.txt && git commit -m x' 'exact=1'
  _sd_add 'command is a pass-through launcher (exact)' 'command git add f.txt && git commit -m x' 'exact=1'
  _sd_add 'flock is a pass-through launcher (exact)' 'flock /l git add f.txt && git commit -m x' 'exact=1'
  _sd_add 'mise exec is an UNKNOWN launcher (non-exact)' 'mise exec -- git add f.txt && git commit -m x' 'stages=1' 'exact=0'
  _sd_add 'xargs is non-exact' 'ls | xargs git add && git commit -m x' 'stages=1' 'exact=0'
  _sd_add 'find -exec is non-exact' 'find . -name x -exec git add {} \; && git commit -m x' 'stages=1' 'exact=0'
  _sd_add 'parallel is non-exact' 'parallel git add ::: a b && git commit -m x' 'exact=0'
  _sd_add 'watch is non-exact' 'watch git add f.txt && git commit -m x' 'exact=0'
  # --- words: literalness ---
  _sd_add 'a $VAR word is non-exact' 'git add $F && git commit -m x' 'exact=0'
  _sd_add 'a "$VAR" word is non-exact' 'git add "$F" && git commit -m x' 'exact=0'
  _sd_add 'a command substitution word is non-exact' 'git add $(ls) && git commit -m x' 'exact=0'
  _sd_add 'an unquoted * is non-exact' 'git add *.json && git commit -m x' 'exact=0'
  _sd_add 'an unquoted ? is non-exact' 'git add f?.txt && git commit -m x' 'exact=0'
  _sd_add 'an unquoted [ is non-exact' 'git add [ab].txt && git commit -m x' 'exact=0'
  _sd_add 'an unquoted brace is non-exact' 'git add {a,b}.txt && git commit -m x' 'exact=0'
  _sd_add 'an unquoted ~ is non-exact' 'git add ~/f.txt && git commit -m x' 'exact=0'
  _sd_add 'a QUOTED glob is a literal pathspec (exact)' 'git add "*.json" && git commit -m x' 'exact=1'
  _sd_add 'a quoted name with a space is exact' 'git add "my file.md" && git commit -m x' 'exact=1' 'words: add my\ file.md'
  _sd_add 'a control byte (0x01) in a word is non-exact' $'git add a\001b && git commit -m x' 'exact=0'
  _sd_add 'a DEL byte (0x7f) in a word is non-exact' $'git add a\177b && git commit -m x' 'exact=0'
  _sd_add 'a newline inside a quoted word is non-exact' $'git add "a\nb" && git commit -m x' 'exact=0'
  _sd_add 'a tab inside a quoted word is non-exact' $'git add "a\tb" && git commit -m x' 'exact=0'
  # --- options: checked on EVERY word before `--`, including words after the pathspec ---
  _sd_add 'add -p is non-exact (interactive)' 'git add -p f.txt && git commit -m x' 'exact=0'
  _sd_add 'add -e is non-exact (opens an editor)' 'git add -e f.txt && git commit -m x' 'exact=0'
  _sd_add 'add -i is non-exact' 'git add -i && git commit -m x' 'exact=0'
  _sd_add 'add --patch is non-exact' 'git add --patch f.txt && git commit -m x' 'exact=0'
  _sd_add 'add --interactive is non-exact' 'git add --interactive && git commit -m x' 'exact=0'
  _sd_add 'add --chmod=+x is non-exact' 'git add --chmod=+x f.txt && git commit -m x' 'exact=0'
  _sd_add 'add --pathspec-from-file=- is non-exact' 'git add --pathspec-from-file=- && git commit -m x' 'exact=0'
  _sd_add 'an option AFTER the pathspec is still checked (f.txt -p)' 'git add f.txt -p && git commit -m x' 'exact=0'
  _sd_add 'an option AFTER the pathspec is still checked (f.txt -e)' 'git add f.txt -e && git commit -m x' 'exact=0'
  _sd_add 'a short bundle is checked per character (-fp)' 'git add -fp f.txt && git commit -m x' 'exact=0'
  _sd_add 'a path named -p after -- is a path, not an option' 'git add -- -p && git commit -m x' 'exact=1'
  _sd_add 'add -A -- <path> is exact' 'git add -A -- f.txt && git commit -m x' 'exact=1'
  _sd_add 'add --pathspec-from-file=- is not literal either (its paths are not words)' 'git add -f --pathspec-from-file=- && git commit -m x' 'lit=0' 'exact=0'
  _sd_add 'two -C options: the record has no single provable directory' 'git -C a -C b add f.txt && git commit -m x' 'own_C=<several>' 'exact=0'
  _sd_add 'add -f carries force=1' 'git add -f f.txt && git commit -m x' 'exact=1' 'force=1'
  _sd_add 'add --force carries force=1' 'git add --force f.txt && git commit -m x' 'exact=1' 'force=1'
  _sd_add 'a -fA bundle carries force=1' 'git add -fA && git commit -m x' 'exact=1' 'force=1'
  _sd_add 'a plain add has force=0' 'git add f.txt && git commit -m x' 'force=0'
  # --- global options before the verb ---
  _sd_add 'git -c user.name=x add: the -c makes the record non-exact (not refused)' 'git -c user.name=x add f.txt && git commit -m x' 'refuse=0' 'exact=0'
  _sd_add 'a pathspec-semantics global option is non-exact' 'git --literal-pathspecs add f.txt && git commit -m x' 'refuse=0' 'exact=0'
  _sd_add '-c core.fsmonitor is REFUSED' 'git -c core.fsmonitor=true add f.txt && git commit -m x' 'refuse=1'
  _sd_add '-c core.* is refused case-insensitively' 'git -c Core.FSMonitor=true add f.txt && git commit -m x' 'refuse=1'
  _sd_add '-c filter.*.clean is REFUSED' 'git -c filter.x.clean=cat add f.txt && git commit -m x' 'refuse=1'
  _sd_add '--config-env=core.* is REFUSED' 'git --config-env=core.fsmonitor=V add f.txt && git commit -m x' 'refuse=1'
  _sd_add '--namespace is REFUSED' 'git --namespace n add f.txt && git commit -m x' 'refuse=1'
  _sd_add '--attr-source is REFUSED' 'git --attr-source HEAD add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'a GIT_* env prefix outside the allowlist is REFUSED' 'GIT_CONFIG_COUNT=0 git add f.txt && git commit -m x' 'refuse=1'
  _sd_add 'a plain add is not refused' 'git add f.txt && git commit -m x' 'refuse=0'
  # --- the directory facts ---
  _sd_add 'git -C <abs> carries own_C on the record' 'git -C /abs/wt add f.txt && git -C /abs/wt commit -m x' 'own_C=/abs/wt'
  _sd_add 'a record with no -C has no own_C' 'git add f.txt && git commit -m x' 'own_C=-'
  _sd_add 'cd <abs> first, && joined: cd_first=1' 'cd /abs && git add f.txt && git commit -m x' 'cd_first=1'
  _sd_add 'cd then ; : cd_first=0' 'cd /abs; git add f.txt && git commit -m x' 'cd_first=0'
  _sd_add 'cd || true: cd_first=0' 'cd /abs || true; git add f.txt && git commit -m x' 'cd_first=0'
  _sd_add 'something before the cd: cd_first=0' 'true && cd /abs && git add f.txt && git commit -m x' 'cd_first=0'
  _sd_add 'a subshell cd: cd_first=0' '(cd /abs); git add f.txt && git commit -m x' 'cd_first=0'
  _sd_add 'pushd first: cd_first=0' 'pushd /abs && git add f.txt && git commit -m x' 'cd_first=0'
  _sd_add 'a ; between the add and the commit: cd_first=0' 'cd /abs && git add f.txt; git commit -m x' 'cd_first=0'
  # --- the commit's own flags ---
  _sd_add 'commit -am: a is a bundle character' 'git commit -am x' 'stages=1' 'all=1'
  _sd_add 'commit -a -m' 'git commit -a -m x' 'all=1'
  _sd_add 'commit -sam: a found inside a bundle' 'git commit -sam x' 'all=1'
  _sd_add 'commit -p implies the all fact (add -u covers it)' 'git commit -p -m x' 'all=1'
  _sd_add 'commit -mall is a MESSAGE, not -a' 'git commit -mall' 'stages=0' 'all=0'
  _sd_add 'commit -am"x" keeps -a' 'git commit -am"x"' 'all=1'
  _sd_add 'commit -Sa: -S takes only an attached remainder (a key id)' 'git commit -Sa' 'stages=0' 'all=0'
  _sd_add 'commit -Sabc: the remainder is the key id' 'git commit -Sabc -m x' 'stages=0' 'all=0'
  _sd_add 'commit -uall is --untracked-files=all' 'git commit -uall -m x' 'stages=0' 'all=0'
  _sd_add 'commit -m -a: the message is "-a"' 'git commit -m -a' 'stages=0' 'all=0'
  _sd_add 'commit -m -- : the message is "--" (no pathspec)' 'git commit -m --' 'stages=0' 'all=0' 'paths_n=0'
  _sd_add 'commit -m -p: the message is "-p"' 'git commit -m -p' 'stages=0' 'all=0'
  _sd_add '--no-all clears the fact' 'git commit --no-all -m x' 'stages=0' 'all=0' 'opaque=0'
  _sd_add '-a then --no-all clears the fact' 'git commit -a --no-all -m x' 'all=0'
  _sd_add '--all sets it' 'git commit --all -m x' 'stages=1' 'all=1'
  _sd_add '--patch stages' 'git commit --patch' 'stages=1'
  _sd_add '--interactive stages' 'git commit --interactive' 'stages=1'
  _sd_add '--pathspec-from-file stages' 'git commit --pathspec-from-file=f.txt -m x' 'stages=1'
  _sd_add 'commit -o <path>' 'git commit -o f.txt -m x' 'stages=1' 'paths_n=1'
  _sd_add 'commit -i <path>' 'git commit -i f.txt -m x' 'stages=1' 'paths_n=1'
  _sd_add 'commit --only <path>' 'git commit --only f.txt -m x' 'stages=1' 'paths_n=1'
  _sd_add 'commit --include <path>' 'git commit --include f.txt -m x' 'stages=1' 'paths_n=1'
  _sd_add 'commit -- <two paths>' 'git commit -m x -- f.txt g.txt' 'stages=1' 'paths_n=2' 'paths_literal=1'
  _sd_add 'commit <bare first word> is a path' 'git commit f.txt -m x' 'stages=1' 'paths_n=1'
  _sd_add 'a positional after -m is a path to the walker (only the pre-filter misses it)' 'git commit -m x f.txt' 'paths_n=1'
  _sd_add 'a $VAR pathspec is non-literal' 'git commit -m x -- $F' 'paths_n=1' 'paths_literal=0'
  _sd_add 'an unquoted glob pathspec is non-literal' 'git commit -m x -- *.json' 'paths_n=1' 'paths_literal=0'
  _sd_add 'a quoted pathspec word is non-literal for the ladder (flag q)' 'git commit -m x -- "a b"' 'paths_n=1' 'paths_literal=0'
  _sd_add 'an unknown long option makes the stage opaque' 'git commit --frobnicate -m x' 'stages=1' 'opaque=1'
  _sd_add 'a unique-prefix abbreviation (--amen) is unknown' 'git commit --amen -m x' 'stages=1' 'opaque=1'
  _sd_add 'an abbreviated staging option (--inc) is unknown' 'git commit --inc f.txt -m x' 'stages=1' 'opaque=1'
  # --- the benign long-option table: a FIXED set taken from `git commit -h`; no count that varies with git ---
  local benign_arg=(--message --file --author --date --reuse-message --reedit-message --fixup --squash --trailer --template --cleanup --unified --inter-hunk-context)
  local benign_flag=(--amend --no-edit --edit --signoff --no-verify --verbose --quiet --dry-run --short --branch --porcelain --long --null --allow-empty --allow-empty-message --reset-author --status --no-status --no-post-rewrite --untracked-files)
  if [[ "${#benign_arg[@]}" -ne 13 || "${#benign_flag[@]}" -ne 20 ]]; then
    printf '[FATAL] the benign long-option table changed size (%s + %s, want 13 + 20): fixed on purpose\n' "${#benign_arg[@]}" "${#benign_flag[@]}" >&2; exit 1
  fi
  for o in "${benign_arg[@]}"; do _sd_add "benign long option $o <operand> stages nothing" "git commit $o operand" 'stages=0' 'opaque=0'; done
  for o in "${benign_flag[@]}"; do _sd_add "benign long option $o stages nothing" "git commit $o" 'stages=0' 'opaque=0'; done
  # The table is only meaningful while the INSTALLED git accepts every entry: git answers an
  # option it does not know with `error: unknown option`.
  ctl=$(mktemp -d "$SUITE_TMP/benign.XXXXXX")
  ( cd "$ctl" && git init -q -b main && git config user.email t@t && git config user.name t && echo a > a.txt && git add a.txt ) >/dev/null 2>&1
  local gerr
  for o in "${benign_arg[@]}"; do
    gerr=$(cd "$ctl" && git commit --dry-run "$o" "$(_benign_operand "$o")" 2>&1) || true
    if [[ "$gerr" == *"unknown option"* ]]; then _report "benign-table: installed git accepts $o" fail "git rejected the option: the table is stale for $(git --version)"
    else _report "benign-table: installed git accepts $o" ok; fi
  done
  for o in "${benign_flag[@]}"; do
    gerr=$(cd "$ctl" && git commit --dry-run "$o" 2>&1) || true
    if [[ "$gerr" == *"unknown option"* ]]; then _report "benign-table: installed git accepts $o" fail "git rejected the option: the table is stale for $(git --version)"
    else _report "benign-table: installed git accepts $o" ok; fi
  done
  _sd_unit_c_rows
  _sd_check
  # The lexer-skipped plain-commit path never calls ctr_collect: the facts must read as zero, not unbound, under set -u.
  local zero
  zero=$(env HOME=/h bash -c 'set -u; source "$1" || { echo SOURCEFAIL; exit 0; }
    if declare -f ctr_stage_dump >/dev/null 2>&1; then ctr_stage_dump 2>&1; else echo NODUMP; fi
    echo "stages-var=${CTR_COMMIT_STAGES:-UNSET}"' _ "$lib" 2>&1) || true
  _t "walker-dump: before any ctr_collect (set -u) the staging facts exist and are all zero, with no add record" "got: ${zero//$'\n'/ | }" \
    _dump_is_zero "$zero"
}
_dump_is_zero() {
  local z="$1"
  [[ "$z" == *"stages=0"* && "$z" == *"opaque=0"* && "$z" == *"refuse=0"* && "$z" == *"all=0"* && "$z" == *"paths_n=0"* \
     && "$z" != *"add exact="* && "$z" != *NODUMP* && "$z" != *SOURCEFAIL* && "$z" == *"stages-var=0"* ]]
}

# ---- groups 1 to 7: the would-be index decides (structural tier) --------------------------------
_row_has() {  # <n> [text]: the last _rows_since_mark counted n rows and (optionally) its text has <text>
  [[ "$ROWS_N" -eq "$1" ]] || return 1
  [[ -z "${2-}" || "$ROWS_TXT" == *"$2"* ]]
}
_idx_pair() { _rec_has "$1" && ! _rec_has "$2"; }
_is_sim_env() {  # <repo>: the first gitleaks git call ran with ABSOLUTE sim variables, none of them the real ones
  local repo="$1" i o a
  i=$(_rec_field 1 3); o=$(_rec_field 1 4); a=$(_rec_field 1 5)
  [[ "$i" == /* && "$i" != "$repo/.git/index" && "$o" == /* && "$o" != "$repo/.git/objects" && "$a" == /* ]]
}
_has_update_paths() {  # <path>: a path-limited add -u (never -A) named it
  local a; a=$(_sim_adds)
  [[ "$a" == *" -u "* && "$a" == *" $1 "* && "$a" != *" -A "* ]]
}

_t_sim_core() {
  _sim_init
  SIM_PD=$(_mk_sim_path)
  local U T r cmd ed mark nsim
  U=$(_mk_leaky_repo untracked); T=$(_mk_leaky_repo tracked-modified)

  # --- group 1: git add -A && git commit, the leak only in the working tree ---
  _sx "G1 'git add -A && git commit -m x', untracked leak -> deny naming leak.json" "$U" "git add -A && git commit -m x" deny "leak.json"
  r="$SIM_R"
  _t "G1b the deny carries the sim recovery text (.gitignore)" "reason=${r:0:300}" _contains "$r" ".gitignore"
  _t "G1c ... and 'separate call'" "reason=${r:0:300}" _contains "$r" "separate call"
  _t "G1d ... and NOT the restore --staged clause (the file is not staged: that advice would loop)" "reason=${r:0:300}" _nlacks "$r" "restore --staged"
  _rows_since_mark git-commit-secret-scan
  _t "G1e a finding in a would-be index keeps the base rule id git-commit-secret-scan, with the plan mode" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "mode=exact"
  _t "G1f ... and cause=finding" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "cause=finding"
  _rows_since_mark git-commit-secret-scan-sim-deny
  nsim="$ROWS_N"
  _t "G1g ... and no sim-deny row (that id is for simulation FAILURES only)" "sim=$nsim" test "$nsim" = 0
  _t "G1h env window: the gitleaks call ran with absolute sim index / objects / alternates (not the real ones)" \
    "idx=$(_rec_field 1 3) obj=$(_rec_field 1 4) alt=$(_rec_field 1 5)" _is_sim_env "$U"
  _t "G1i the sim index holds the untracked leak.json and clean.txt" "ls=$(_rec_ls | head -c 300)" _idx_pair leak.json nothing
  _sx "G1 gap witness: plain 'git commit -m x' on the same shape allows" "$U" "git commit -m x" allow
  _t "G1 gap witness runs no simulation" "log=$(_log_n) adds=$(_sim_add_n)" _no_sim

  # --- group 2: git add <the leak> && git commit ---
  _sx "G2 'git add leak.json && git commit -m x' -> deny naming leak.json" "$U" "git add leak.json && git commit -m x" deny "leak.json"
  _t "G2b the exact replay named leak.json (no add -A)" "adds=$(_sim_adds)" _exact_add leak.json
  _rows_since_mark git-commit-secret-scan
  _t "G2c an exact-replay finding is a base-id row carrying mode=exact" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "mode=exact"

  # --- group 3 (must-PASS controls): an unrelated untracked leak must not deny ---
  _sx "G3 'git add clean.txt && git commit -m x' with an UNRELATED untracked leak -> allow" "$U" "git add clean.txt && git commit -m x" allow
  _t "G3b exact replay (add clean.txt), not add -A" "adds=$(_sim_adds)" _exact_add clean.txt
  _t "G3b2 ... and EXACTLY one sim add ran (a hook that never simulates sees none; one that over-replays sees two)" "sim adds=$(_sim_add_n)" test "$(_sim_add_n)" -eq 1
  _t "G3c the sim index holds clean.txt and NOT the unrelated leak.json" "ls=$(_rec_ls | head -c 300)" _idx_pair clean.txt leak.json
  _sx "G3d quoted name: 'git add \"my file.md\" && git commit -m x' -> allow" "$U" 'git add "my file.md" && git commit -m x' allow
  _t "G3e exact replay of the quoted name" "adds=$(_sim_adds)" _exact_add 'my\ file.md'
  _sx "G3f 'rtk git add clean.txt && rtk git commit -m x' -> allow" "$U" "rtk git add clean.txt && rtk git commit -m x" allow
  _t "G3g exact replay through the rtk launcher" "adds=$(_sim_adds)" _exact_add clean.txt
  _sx "G3h a compliant first add then a leak: 'git add clean.txt && git add leak.json && git commit' -> deny" "$U" \
    "git add clean.txt && git add leak.json && git commit -m x" deny "leak.json"
  _sx "G3i an add AFTER the last commit is still replayed: 'git commit -m x; git add leak.json' -> deny" "$U" \
    "git commit -m x; git add leak.json" deny "leak.json"

  # --- group 4: commit -a with a tracked file modified to hold the leak ---
  for cmd in "git commit -am x" "git commit -a -m x" "git commit -sam x"; do
    _sx "G4 '$cmd', tracked file modified to hold the leak -> deny" "$T" "$cmd" deny "tracked.json"
    _t "G4b '$cmd' ran add -u (not -A)" "adds=$(_sim_adds)" _has_update
  done
  _sx "G4 gap witness: plain 'git commit -m x' on the same shape allows" "$T" "git commit -m x" allow

  # --- group 5: commit -a does NOT take untracked files ---
  _sx "G5 'git commit -a -m x' with an UNTRACKED leak -> allow (add -u only)" "$U" "git commit -a -m x" allow
  _t "G5b it ran add -u and not add -A" "adds=$(_sim_adds)" _has_update

  # --- group 6: pathspec commits record exactly the named tracked paths ---
  _sx "G6 'git commit -m x -- tracked.json' (modified, leak) -> deny" "$T" "git commit -m x -- tracked.json" deny "tracked.json"
  _t "G6b path-limited add -u -- tracked.json" "adds=$(_sim_adds)" _has_update_paths tracked.json
  _sx "G6c the same command with the leak in a DIFFERENT tracked file -> allow" "$T" "git commit -m x -- other.json" allow
  _t "G6d path-limited add -u -- other.json" "adds=$(_sim_adds)" _has_update_paths other.json
  _sx "G6e bare first word: 'git commit tracked.json -m x' -> deny" "$T" "git commit tracked.json -m x" deny "tracked.json"
  _sx "G6f bare first word, other file: 'git commit other.json -m x' -> allow" "$T" "git commit other.json -m x" allow
  _sx "G6g 'git commit -o tracked.json -m x' -> deny" "$T" "git commit -o tracked.json -m x" deny "tracked.json"
  _sx "G6h 'git commit -o other.json -m x' -> allow" "$T" "git commit -o other.json -m x" allow
  _sx "G6i 'git commit -i tracked.json -m x' -> deny" "$T" "git commit -i tracked.json -m x" deny "tracked.json"

  # --- group 7: every form the replay cannot read goes to the SUPERSET (add -A, never add -p) ---
  ed="$SUITE_TMP/editor-marker.sh"; mark="$SUITE_TMP/editor-ran.mark"; rm -f "$mark"
  printf '#!/bin/sh\n: > "%s"\n' "$mark" > "$ed"; chmod +x "$ed"
  SIM_ENV=("EDITOR=$ed" "GIT_EDITOR=$ed")
  local forms=(
    'F=leak.json; git add $F && git commit -m x'
    'git add -p && git commit -m x'
    'git add *.json && git commit -m x'
    'git add {clean,leak}.json && git commit -m x'
    'git add ~/nothing && git commit -m x'
    'ls | xargs git add && git commit -m x'
    "find . -name '*.json' -exec git add {} \\; && git commit -m x"
    'mise exec -- git add clean.txt && git commit -m x'
    'git add clean.txt -e && git commit -m x'
    'git add clean.txt -p && git commit -m x'
    'git add clean.txt --chmod=+x && git commit -m x'
    'git add --pathspec-from-file=- && git commit -m x'
    'for f in leak.json; do git add "$f"; done && git commit -m x'
    'a() { git add leak.json; }; a && git commit -m x'
    'git checkout main -- . && git commit -m x'
  )
  for cmd in "${forms[@]}"; do
    _sx "G7 superset form, untracked leak -> deny: $cmd" "$U" "$cmd" deny "leak.json"
    _t "G7b ... the shim shows add -A and never -p / -e: $cmd" "adds=$(_sim_adds)" _superset_add
  done
  SIM_ENV=()
  _t "G7z the EDITOR marker was never created (no interactive add ran at hook time)" "marker $mark exists" test ! -e "$mark"

}

# ---- the canary set: the REAL gitleaks (plan "Stub tiers": groups 1, 2, 4, 6, 8 and one worktree) ----
_t_sim_canary() {
  _needs_gl "G-canary real-gitleaks arms" || return 0
  _sim_init
  local U T D cl rc=0
  U=$(_mk_leaky_repo untracked); T=$(_mk_leaky_repo tracked-modified)
  _sxr "G1-real [gitleaks] 'git add -A && git commit -m x', untracked leak -> deny naming leak.json" "$U" "git add -A && git commit -m x" deny "leak.json"
  _sxr "G1-real gap witness: plain commit on the same shape allows" "$U" "git commit -m x" allow
  _sxr "G2-real [gitleaks] 'git add leak.json && git commit -m x' -> deny" "$U" "git add leak.json && git commit -m x" deny "leak.json"
  _sxr "G3-real [gitleaks] 'git add clean.txt && git commit -m x' with an unrelated untracked leak -> allow" "$U" "git add clean.txt && git commit -m x" allow
  _sxr "G4-real [gitleaks] 'git commit -am x', tracked file modified to hold the leak -> deny" "$T" "git commit -am x" deny "tracked.json"
  _sxr "G4-real gap witness: plain commit on the same shape allows" "$T" "git commit -m x" allow
  _sxr "G6-real [gitleaks] 'git commit -m x -- tracked.json' -> deny" "$T" "git commit -m x -- tracked.json" deny "tracked.json"
  _sxr "G6-real 'git commit -m x -- other.json' (leak in a different tracked file) -> allow" "$T" "git commit -m x -- other.json" allow

  # --- group 8: a `-diff` gitattribute blinds `gitleaks git`; the guard must still see the would-be blob ---
  D=$(_mk_leaky_repo untracked)
  assert_fixture_dir "$D"; mkdir -p "$D/.git/info"; echo 'leak.json -diff' > "$D/.git/info/attributes"
  cl=$(mktemp -d "$SUITE_TMP/ndclone.XXXXXX")
  cp -a "$D/." "$cl/"; git -C "${cl:?}" add leak.json
  ( cd "$cl" && gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1 --report-format json \
      --report-path "$cl.json" >/dev/null 2>&1 ) || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    _report "G8 fixture control" fail "FIXTURE BROKEN: the -diff attribute did not blind the plain staged scan (rc=$rc), so G8 proves nothing"
    return 0
  fi
  _sxr "G8 [gitleaks] -diff attribute + 'git add leak.json && git commit -m x' -> deny with the -diff message" "$D" \
    "git add leak.json && git commit -m x" deny "-diff"
  local v
  for v in diff check-attr checkout-index; do
    _t "G8b the shim env log shows the sim variables on '$v' (one export covers all four injection sites)" "log=$(grep "VERB=$v " "$SIM_LOG" | head -c 300)" \
      grep -q -E "^SIM=1 VERB=$v .* IDX=/.* OBJ=/.* ALT=/" "$SIM_LOG"
  done
}

# ---- group 9: invariants (Guard 2): the simulation never mutates the real repository ----------
_t_sim_invariants() {
  _sim_init
  [[ -n "$SIM_PD" ]] || SIM_PD=$(_mk_sim_path)
  local U U2 SPL T C S body
  U=$(_mk_leaky_repo untracked); U2=$(_mk_leaky_repo untracked); T=$(_mk_leaky_repo tracked-modified)
  C=$(_mk_leaky_repo clean); S=$(_mk_staged_repo)
  SPL=$(_mk_leaky_repo untracked); git -C "${SPL:?}" config core.splitIndex true

  _assert_repo_untouched "G9a real index / objects / git dir / tree unchanged by a hook run that DENIES (add -A)" "$U" -- \
    _sim_run "$U" "git add -A && git commit -m x"
  _verdict "G9a2 ... and that run denied" deny "leak.json"
  _t "G9a3 ... and the simulation really ran (a sim add is in the shim log)" "sim adds=$(_sim_add_n) log=$(_log_n)" test "$(_sim_add_n)" -ge 1
  _t "G9a4 ... and the private TMPDIR is empty afterwards" "left: $(ls -A "$SIM_TMP")" _tmp_empty
  _t "G9a5 ... and the sim directory was mode 0700" "perm=$(cat "$SIM_REC"/simperm.* 2>/dev/null)" _cat_has simperm 'drwx------'
  _t "G9a6 ... and the quarantined object directory was mode 0700" "perm=$(cat "$SIM_REC"/objperm.* 2>/dev/null)" _cat_has objperm 'drwx------'

  _assert_repo_untouched "G9b real repository unchanged by a hook run that ALLOWS (add clean.txt)" "$U2" -- \
    _sim_run "$U2" "git add clean.txt && git commit -m x"
  _verdict "G9b2 ... and that run allowed" allow
  _t "G9b3 ... and the simulation really ran" "sim adds=$(_sim_add_n)" test "$(_sim_add_n)" -ge 1
  _t "G9b4 ... and the private TMPDIR is empty afterwards" "left: $(ls -A "$SIM_TMP")" _tmp_empty

  _assert_repo_untouched "G9c real git directory gains no sharedindex.* under core.splitIndex=true (add -A)" "$SPL" -- \
    _sim_run "$SPL" "git add -A && git commit -m x"
  _verdict "G9c2 ... and that run denied" deny "leak.json"
  _t "G9c3 ... and the simulation really ran" "sim adds=$(_sim_add_n)" test "$(_sim_add_n)" -ge 1

  _assert_repo_untouched "G9d real repository unchanged by a commit -am run" "$T" -- \
    _sim_run "$T" "git commit -am x"
  _verdict "G9d2 ... and that run denied" deny "tracked.json"
  _t "G9d3 ... and the simulation really ran" "sim adds=$(_sim_add_n)" test "$(_sim_add_n)" -ge 1

  # A plain commit pays nothing: no simulation, no sim directory (the shim log proves the hook ran git).
  _sx "G9e plain 'git commit -m x' allows" "$C" "git commit -m x" allow
  _t "G9e2 ... the shim logged calls and NO sim call; nothing allocated" "log=$(_log_n) adds=$(_sim_add_n)" _no_sim
  _sx "G9f plain 'git commit -n -m x' allows" "$C" "git commit -n -m x" allow
  _t "G9f2 ... the shim logged calls and NO sim call; nothing allocated" "log=$(_log_n) adds=$(_sim_add_n)" _no_sim

  # A separate-call commit (the leak already staged) keeps the old behaviour and the old repair text.
  _sx "G9g a staged leak, plain commit -> deny (the separate-call shape)" "$S" "git commit -m x" deny "leak.json" "restore --staged"
  _rows_since_mark git-commit-secret-scan
  _t "G9g2 ... a non-sim deny keeps the git-commit-secret-scan rule id" "n=$ROWS_N" _row_has 1
  _rows_since_mark git-commit-secret-scan-sim-deny
  _t "G9g3 ... and writes no sim-deny row" "n=$ROWS_N" _row_has 0
}

# The INT/TERM trap must END the hook (measured: bash runs the handler and CONTINUES, so a trap that
# only cleans up lets the hook finish and print a decision). Contract per signal: rc 128+n, empty stdout (allow and
# deny both print JSON), an empty private TMPDIR, and the recording stub proves it ran inside a sim dir.
_t_sim_term() {
  _sim_init
  local sig rc_want U pd tmpd rec rel hp rc outf errf payload n sd
  for sig in TERM INT; do
    if [[ "$sig" == TERM ]]; then rc_want=143; else rc_want=130; fi
    U=$(_mk_leaky_repo untracked); pd=$(_mk_sim_path)
    rec="$SUITE_TMP/rec.$sig"; mkdir -p "$rec"; rel="$SUITE_TMP/release.$sig"; rm -f "$rel"
    tmpd="$SUITE_TMP/tmp.$sig"; mkdir -p "$tmpd"
    outf="$SUITE_TMP/$sig.out"; errf="$SUITE_TMP/$sig.err"; : > "$outf"; rc=0; n=0
    payload=$(jq -nc --arg w "$U" '{tool_name: "Bash", cwd: $w, tool_input: {command: "git add -A && git commit -m x"}}')
    # A background job of a non-interactive shell starts with SIGINT IGNORED, and bash cannot trap a signal that was
    # ignored on entry; perl resets the disposition to the default before it execs the hook.
    ( cd "$U" && exec env PATH="$pd" TMPDIR="$tmpd" CLAUDE_PROJECT_DIR="$REPO_ROOT" SHIM_REAL_GIT="$SIM_REAL_GIT" \
        SHIM_LOG="$SUITE_TMP/shim.$sig.log" GL_REC_DIR="$rec" GL_REC_HOLD=1 GL_REC_RELEASE="$rel" \
        perl -e '$SIG{INT} = "DEFAULT"; $SIG{QUIT} = "DEFAULT"; exec @ARGV or exit 127' "$pd/bash" "$HOOK" <<<"$payload" >"$outf" 2>"$errf" ) &
    hp=$!
    while [[ ! -e "$rec/started" && "$n" -lt 100 ]]; do sleep 0.1; n=$((n + 1)); done
    if [[ ! -e "$rec/started" ]]; then
      kill -KILL "$hp" 2>/dev/null || true; wait "$hp" 2>/dev/null || true
      _report "G9i $sig arm: the gitleaks stub started" fail "the stub never reported 'started' within 10 s: the arm cannot signal the hook mid-scan"
      continue
    fi
    kill -"$sig" "$hp" 2>/dev/null || true
    : > "$rel"
    wait "$hp" || rc=$?
    _t "G9i $sig mid-scan: the hook exits $rc_want (the handler must END the hook, not resume it)" "rc=$rc" test "$rc" -eq "$rc_want"
    _t "G9j $sig ... and printed nothing on stdout (neither allow nor deny)" "stdout=$(head -c 200 "$outf")" test ! -s "$outf"
    SIM_TMP="$tmpd"
    _t "G9k $sig ... and left the private TMPDIR empty" "left: $(ls -A "$tmpd")" _tmp_empty
    sd=$(cat "$rec"/simdir.* 2>/dev/null | head -n 1 || true)
    _t "G9l $sig positive control: the stub ran inside a commit-sim-* directory while it was held" "simdir='${sd}'" _contains "$sd" "commit-sim-"
    _t "G9m $sig ... and that directory is gone after the signal" "simdir=$sd" test -n "$sd" -a ! -e "$sd"
  done
}

_with_pd() { local keep="$SIM_PD"; SIM_PD="$1"; shift; "$@"; SIM_PD="$keep"; }
_distinct_idx() {  # <n>: the recording stub saw n distinct sim indexes (one per scanned root)
  [[ "$(awk -F'\t' '$2 == "git" { print $3 }' "$SIM_REC/calls.log" | sort -u | wc -l | tr -d ' ')" -eq "$1" ]]
}
_no_sleep61() { [[ -z "$(ps -eo args= | awk '$1 == "sleep" && $2 == "61"')" ]]; }

# ---- group 10: the directory the replay may trust (CTO row 15) ----------------------------------
_t_sim_dirproof() {
  _sim_init
  [[ -n "$SIM_PD" ]] || SIM_PD=$(_mk_sim_path)
  local R W U D state cmd
  _mk_bare_root_with_worktree untracked; R="$FX_ROOT"; W="$FX_WT"

  _sx "G10 incident shape: bare-root cwd, 'cd <wt> && git add -A && git commit -m x' -> deny naming leak.json and the worktree" \
    "$R" "cd $W && git add -A && git commit -m x" deny "leak.json" "$W"
  _sx "G10 gap witness: 'cd <wt> && git commit -m x' (the leak is untracked) -> allow" "$R" "cd $W && git commit -m x" allow
  # proof (iii): cd <abs> is the first record, && joined
  _sx "G10c proof (iii) 'cd <abs> && git add clean.txt && git commit', unrelated leak -> allow" "$R" "cd $W && git add clean.txt && git commit -m x" allow
  _t "G10c2 ... an EXACT replay (the directory was proven)" "adds=$(_sim_adds)" _exact_add clean.txt
  _sx "G10c3 deny twin: 'cd <abs> && git add leak.json && git commit' -> deny" "$R" "cd $W && git add leak.json && git commit -m x" deny "leak.json"
  # proof (ii): the same absolute -C on every add record and on the commit
  _sx "G10d proof (ii) 'git -C <abs> add clean.txt && git -C <abs> commit', unrelated leak -> allow" "$R" \
    "git -C $W add clean.txt && git -C $W commit -m x" allow
  _t "G10d2 ... an EXACT replay" "adds=$(_sim_adds)" _exact_add clean.txt
  _sx "G10d3 deny twin: 'git -C <abs> add leak.json && git -C <abs> commit' -> deny" "$R" \
    "git -C $W add leak.json && git -C $W commit -m x" deny "leak.json"
  # proof (i): no cd / -C anywhere and a payload .cwd that is an absolute existing directory
  _sx "G10e proof (i) payload cwd present, no cd: 'git add clean.txt && git commit', unrelated leak -> allow" "$W" "git add clean.txt && git commit -m x" allow
  _t "G10e2 ... an EXACT replay" "adds=$(_sim_adds)" _exact_add clean.txt

  # 10b: commands whose cd does NOT take effect (or is undone) before the add. The leak is at the repo
  # root; a replay that trusts the named directory would scan docs/ instead. A clean docs/leak.json
  # is present, then absent: the exact-replay outcome differs, the verdict must not.
  U=$(_mk_leaky_repo untracked); D="$U/docs"; assert_fixture_dir "$D"
  for state in present absent; do
    if [[ "$state" == present ]]; then echo clean > "$D/leak.json"; else rm -f "$D/leak.json"; fi
    for cmd in "false && cd $D; git add leak.json && git commit -m x" \
               "(cd $D); git add leak.json && git commit -m x" \
               "pushd $D && popd && git add leak.json && git commit -m x"; do
      _sx "G10b wrong-directory command (docs/leak.json $state), leak at the repo root -> deny: $cmd" "$U" "$cmd" deny "Locations: leak.json"
    done
  done
  rm -f "$D/leak.json"
  _sx "G10b wrong-directory command (the cd FAILS, || true): leak at the repo root -> deny" "$U" \
    "cd $SUITE_TMP/no-such-dir-10b || true; git add leak.json && git commit -m x" deny "Locations: leak.json"
  # an unproven directory goes to the superset
  NO_PAYLOAD_CWD=1 RUN_PROJECT_DIR="$U" _sx "G10f a payload WITHOUT .cwd (CLAUDE_PROJECT_DIR set): the directory is unproven -> superset -> deny" "$U" \
    "git add clean.txt && git commit -m x" deny "leak.json"
  _t "G10f2 ... the shim shows add -A" "adds=$(_sim_adds)" _superset_add
  _sx "G10g a relative single target: 'cd docs && git add ../clean.txt && git commit' -> superset -> deny" "$U" \
    "cd docs && git add ../clean.txt && git commit -m x" deny "leak.json"
  _t "G10g2 ... the shim shows add -A" "adds=$(_sim_adds)" _superset_add
}

# ---- group 11: failure posture (no `ask`, ADR-165) ---------------------------------------------
_t_sim_failures() {
  _sim_init
  [[ -n "$SIM_PD" ]] || SIM_PD=$(_mk_sim_path)
  local C U Cc pd2 pd3 pdn cp msg xs r start
  C=$(_mk_leaky_repo clean); U=$(_mk_leaky_repo untracked)

  # a. a path that does not exist cannot be scanned: ALWAYS a deny (decision-challenges row 25). Under `&&` the real
  # add would fail anyway; under `;` or `||` it is the bypass shape. The text names the path git named.
  _sx "G11a 'git add no-such-file && git commit' -> deny naming the missing path" "$C" "git add no-such-file && git commit -m x" deny \
    "does not exist" "no-such-file" "earlier call"
  _rows_since_mark git-commit-secret-scan-sim-deny
  _t "G11a2 ... one sim-deny row, cause pathspec-missing" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "cause=pathspec-missing"
  _sx "G11a3 the commit trailer's '>' makes no difference: the same deny" "$C" \
    'git add no-such-file && git commit -m "x" -m "Co-Authored-By: A <a@b.c>"' deny "does not exist" "no-such-file"
  _sx "G11a4 twin: 'git add clean.txt && git commit' (the path exists) -> allow, no sim-deny row" "$C" "git add clean.txt && git commit -m x" allow
  _rows_since_mark git-commit-secret-scan-sim-deny
  _t "G11a5 ... no row" "n=$ROWS_N" _row_has 0
  _sx "G11b a typo under ';' (the bypass shape) -> deny" "$C" "git add no-such-file; git commit -m x" deny "does not exist"
  _sx "G11b2 a file the same command writes, then adds -> deny (a missing path cannot be scanned)" "$C" \
    "printf x > leak.json && git add leak.json && git commit -m x" deny "does not exist" "leak.json"

  # c. any OTHER replay failure abandons the exact replay and rebuilds with the superset
  SIM_ENV=("SHIM_FAIL=replay" "SHIM_RC=128" "SHIM_MSG=fatal: shim-injected replay failure")
  _sx "G11c exact replay add exits 128 with another message, untracked leak -> the superset is scanned -> deny" "$U" \
    "git add clean.txt && git commit -m x" deny "leak.json"
  r=$(_sim_adds)
  _t "G11c2 ... the failed exact add (clean.txt) was followed by add -A" "adds=$r" _contains "$r" " -A "
  _rows_since_mark git-commit-secret-scan-sim-failed
  _t "G11c3 ... and no sim-failed bypass row exists any more" "n=$ROWS_N" _row_has 0
  _sx "G11c4 twin on a clean repo -> allow after the superset" "$C" "git add clean.txt && git commit -m x" allow
  _t "G11c5 ... the superset ran" "adds=$(_sim_adds)" _superset_add
  SIM_ENV=()

  # d. a failed superset DENIES (never allows), quoting the sanitised first error line
  SIM_ENV=("SHIM_FAIL=addA")
  _sx "G11d a failed superset ('add -A' fails) -> deny with 'run git add as its own call' and the git error" "$C" \
    "git add -A && git commit -m x" deny "its own call" "shim-injected"
  SIM_ENV=()

  # e. temp dir / index copy / ':' in the objects path
  pd2=$(_mk_sim_path); assert_fixture_dir "$pd2"; rm -f "$pd2/cp"; printf '#!/bin/sh\nexit 1\n' > "$pd2/cp"; chmod +x "$pd2/cp"
  _with_pd "$pd2" _sx "G11e the index copy fails (cp fails) -> deny" "$C" "git add -A && git commit -m x" deny "its own call"
  pd3=$(_mk_sim_path); assert_fixture_dir "$pd3"; rm -f "$pd3/mktemp"
  printf '#!/bin/sh\nfor a in "$@"; do case "$a" in *commit-sim-*) exit 1 ;; esac; done\nexec %s "$@"\n' "$(command -v mktemp)" > "$pd3/mktemp"
  chmod +x "$pd3/mktemp"
  _with_pd "$pd3" _sx "G11f the sim directory cannot be allocated (mktemp fails for commit-sim-*) -> deny" "$C" "git add -A && git commit -m x" deny "its own call"
  Cc="$SUITE_TMP/co:lon.repo"; rm -rf "$Cc"; mv "$(_mk_leaky_repo clean)" "$Cc"
  _sx "G11g a ':' in the objects path (GIT_ALTERNATE_OBJECT_DIRECTORIES is colon separated) -> deny" "$Cc" "git add -A && git commit -m x" deny "its own call"

  # f. the deadline: expiry always DENIES, never bypasses (CIS_DEADLINE_SECONDS can only LOWER the 30 s ceiling).
  # The bound is one perl fork/waitpid/kill program on every host; the default stub PATH has no timeout(1) at all.
  if [[ -e "$SIM_PD/timeout" || -e "$SIM_PD/gtimeout" ]]; then
    _report "G11h0 fixture PATH has no timeout" fail "the stub PATH carries a timeout binary: the arm would not prove the perl bound"
  fi
  SIM_ENV=("CIS_DEADLINE_SECONDS=2" "GL_REC_SLEEP=61"); start=$SECONDS
  _sx "G11h the gitleaks scan outlives the (test-shortened) deadline -> deny" "$C" "git add -A && git commit -m x" deny
  _t "G11h2 ... bounded: ended near the deadline, not after the stub's 61 s" "elapsed=$((SECONDS - start)) s" test $((SECONDS - start)) -lt 20
  _rows_since_mark git-commit-secret-scan-sim-deny
  _t "G11h3 ... one sim-deny row, cause sim-timeout" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "cause=sim-timeout"
  _t "G11h4 ... and no gitleaks child (the stub's sleep) is left running: the whole process group was killed" \
    "left: $(ps -eo args= | awk '$1 == "sleep" && $2 == "61"' | head -c 100)" _no_sleep61
  SIM_ENV=("CIS_DEADLINE_SECONDS=0")
  _sx "G11i no time remaining (deadline 0) before the first call -> deny" "$C" "git add -A && git commit -m x" deny
  SIM_ENV=()

  # g. the sim library missing: a strict commit is DENIED (a lazy fail-open source would skip the scan)
  cp=$(mktemp -d "$SUITE_TMP/hookcopy5.XXXXXX"); mkdir -p "$cp/.claude"
  cp -R "$REPO_ROOT/.claude/hooks" "$cp/.claude/hooks"
  rm -f "$cp/.claude/hooks/lib/commit-index-sim.sh"
  HOOK_OVERRIDE="$cp/.claude/hooks/git-commit-secret-scan.sh" \
    _sx "G11l sim library missing: a CHAINED commit is denied through the lib repair" "$C" "git add -A && git commit -m x" deny "git checkout -- .claude/hooks/lib"
  HOOK_OVERRIDE="$cp/.claude/hooks/git-commit-secret-scan.sh" \
    _sx "G11m sim library missing: a PLAIN strict commit is denied too" "$C" "git commit -m x" deny "git checkout -- .claude/hooks/lib"
  HOOK_OVERRIDE="$cp/.claude/hooks/git-commit-secret-scan.sh" \
    _sx "G11n sim library missing leaves a non-commit call alone" "$C" "git status" allow

  # h. perl absent: a chained add-then-commit now needs the lexer, so the tooling deny applies, with the repair that fits
  pdn=$(_mk_stub_path record)
  if [[ -e "$pdn/perl" ]]; then _report "G11o fixture PATH has no perl" fail "the stub PATH carries perl"
  else
    _sim_run "$C" "git add -A && git commit -m x" "$pdn"
    _verdict "G11o no perl: a chained add-then-commit is denied (tooling), repair says add in one call, commit in the next" deny \
      "cannot determine" "perl" "the commit in the next"
  fi

  # i. hostile text in a quoted git error line never reaches the deny reason unsanitised
  msg=$(printf "fatal: unable to stat 'a\xe2\x80\xa8b%s'\nSECONDLINE" "$(printf 'x%.0s' $(seq 1 300))")
  SIM_ENV=("SHIM_FAIL=addA" "SHIM_MSG=$msg")
  _sx "G11p a failed superset quoting a hostile git error line (U+2028, 300 characters, a second line) -> deny" "$C" "git add -A && git commit -m x" deny "unable to stat"
  r="$SIM_R"; xs=$(printf 'x%.0s' $(seq 1 201))
  _t "G11p2 ... no U+2028 reaches the reason" "reason=${r:0:300}" _nlacks "$r" $'\xe2\x80\xa8'
  _t "G11p3 ... no newline reaches the reason" "reason=${r:0:300}" _nlacks "$r" $'\n'
  _t "G11p4 ... the quoted line is capped (no 201-character run)" "len=${#r}" _nlacks "$r" "$xs"
  _t "G11p5 ... only the FIRST error line is quoted" "reason=${r:0:300}" _nlacks "$r" "SECONDLINE"
  SIM_ENV=()
}

# ---- config-transforming staging arguments, filter / fsmonitor pins (CTO rows 17, 18) -----------
_t_sim_pins() {
  _sim_init
  [[ -n "$SIM_PD" ]] || SIM_PD=$(_mk_sim_path)
  local U F FM mk fm cl rc cmd
  U=$(_mk_leaky_repo untracked); mk="$SUITE_TMP/fsmon.mark"; rm -f "$mk"
  _sx "G12a '-c core.fsmonitor=<command> add' is REFUSED (stage in its own call)" "$U" \
    "git -c 'core.fsmonitor=touch $mk' add clean.txt && git commit -m x" deny "its own call"
  _t "G12a2 ... and the command never ran (the marker file does not exist)" "marker $mk exists" test ! -e "$mk"
  for cmd in "git -c filter.x.clean=cat add clean.txt && git commit -m x" \
             "git --config-env=core.fsmonitor=V add clean.txt && git commit -m x" \
             "git --namespace n add clean.txt && git commit -m x" \
             "git --attr-source HEAD add clean.txt && git commit -m x" \
             "HOME=/x git add clean.txt && git commit -m x"; do
    _sx "G12a3 refused (stage in its own call): $cmd" "$U" "$cmd" deny "its own call"
  done
  # GIT_EDITOR is on the environment allowlist: an exact replay, no refusal.
  _sx "G12a4 'GIT_EDITOR=true git add clean.txt && git commit' is replayed exactly, not refused -> allow" "$U" \
    "GIT_EDITOR=true git add clean.txt && git commit -m x" allow
  _t "G12a5 ... an exact add of clean.txt" "adds=$(_sim_adds)" _exact_add clean.txt

  # A configured clean filter must never run at hook time: git add on the temp index would execute it.
  F=$(_mk_leaky_repo untracked); fm="$SUITE_TMP/filter.mark"; rm -f "$fm"
  git -C "${F:?}" config filter.mark.clean "touch $fm; cat"
  assert_fixture_dir "$F"; printf '* filter=mark\n' > "$F/.gitattributes"
  cl=$(mktemp -d "$SUITE_TMP/filterctl.XXXXXX"); cp -a "$F/." "$cl/"
  git -C "${cl:?}" add clean.txt
  _t "G12b fixture control: the configured filter DOES fire on a plain git add" "no marker after a real add" test -e "$fm"
  rm -f "$fm"
  _sx "G12b2 a configured clean filter, 'git add -A && git commit' -> deny (the sim index holds the raw bytes)" "$F" "git add -A && git commit -m x" deny "leak.json"
  _t "G12b3 ... the simulation really ran" "sim adds=$(_sim_add_n)" test "$(_sim_add_n)" -ge 1
  _t "G12b4 ... and the filter never ran at hook time (the marker was not created)" "marker $fm exists" test ! -e "$fm"
  _t "G12b5 ... every sim add neutralised the configured filter (clean, process, smudge, required=false)" "adds=$(_sim_adds)" _adds_neutralise_filter mark

  # core.fsmonitor=true / core.untrackedCache / core.splitIndex are pinned OFF on every sim `add`, the
  # locale is C, and every configured filter is neutralised. (A whole-hook "no daemon" assertion is NOT
  # possible: scan_root's own unpinned `git diff --cached` / `check-attr` already start the builtin
  # fsmonitor daemon in a core.fsmonitor=true repository on the UNMODIFIED hook, measured; the plan
  # row is therefore pinned at the sim's own git calls, which is where the sim can act.)
  FM=$(_mk_leaky_repo untracked); git -C "${FM:?}" config core.fsmonitor true
  _sx "G12c core.fsmonitor=true configured: 'git add -A && git commit' -> deny" "$FM" "git add -A && git commit -m x" deny "leak.json"
  _t "G12c2 ... the simulation really ran" "sim adds=$(_sim_add_n)" test "$(_sim_add_n)" -ge 1
  _t "G12c3 ... every sim add carries -c core.fsmonitor=false -c core.untrackedCache=false -c core.splitIndex=false -c core.hooksPath=/dev/null, LC_ALL=C and GIT_OPTIONAL_LOCKS=0" "adds=$(_sim_adds)" _adds_pinned
  git -C "$FM" fsmonitor--daemon stop >/dev/null 2>&1 || true
}
_adds_neutralise_filter() {  # <filter name>...: every sim add carries all four neutralising -c settings for each
  local a l n; a=$(_sim_adds); [[ -n "$a" ]] || return 1
  while IFS= read -r l; do
    for n in "$@"; do
      [[ "$l" == *"filter.$n.clean="* && "$l" == *"filter.$n.process="* && "$l" == *"filter.$n.smudge="* && "$l" == *"filter.$n.required=false"* ]] || return 1
    done
  done <<<"$a"
}
_adds_pinned() {  # at least one sim add; every one carries the pins (the verb is the literal add)
  local a l; a=$(_sim_adds); [[ -n "$a" ]] || return 1
  while IFS= read -r l; do
    [[ "$l" == *"LC_ALL=C "* && "$l" == *"OPTLOCKS=0 "* && "$l" == *"core.fsmonitor=false"* && "$l" == *"core.untrackedCache=false"* \
       && "$l" == *"core.splitIndex=false"* && "$l" == *"core.hooksPath=/dev/null"* ]] || return 1
  done <<<"$a"
}

# ---- group 12: linked worktree and symlinks ----------------------------------------------------
_t_sim_worktree() {
  _sim_init
  [[ -n "$SIM_PD" ]] || SIM_PD=$(_mk_sim_path)
  local R W gd L SL tomlreal i o a
  _mk_bare_root_with_worktree untracked; R="$FX_ROOT"; W="$FX_WT"
  gd=$(git -C "$W" rev-parse --absolute-git-dir)
  _sx "G12 linked worktree: 'git add -A && git commit' from the worktree -> deny naming leak.json" "$W" "git add -A && git commit -m x" deny "leak.json"
  i=$(_rec_field 1 3); o=$(_rec_field 1 4); a=$(_rec_field 1 5)
  _t "G12d the sim index is an ABSOLUTE path, not the worktree's own index ($gd/index)" "idx=$i" test "${i:0:1}" = / -a "$i" != "$gd/index"
  _t "G12e the sim objects path and alternates are ABSOLUTE and are not the real objects directory" "obj=$o alt=$a" test "${o:0:1}" = / -a "${a:0:1}" = / -a "$o" != "$gd/objects"
  _t "G12f the sim index file and the quarantine directory existed while gitleaks ran" "idx/obj existence markers missing" _sim_resolves
  _t "G12g a blob that lives only in the COMMON object store resolved (HEAD:seed.txt is a blob)" "headblob=$(cat "$SIM_REC"/headblob.* 2>/dev/null)" _cat_has headblob blob
  _sx "G12 gap witness: plain commit from the worktree allows" "$W" "git commit -m x" allow
  if _needs_gl "G12h real-gitleaks linked worktree"; then
    _sxr "G12h [gitleaks] linked worktree: 'git add -A && git commit' -> deny naming leak.json" "$W" "git add -A && git commit -m x" deny "leak.json"
  fi

  # symlinks: a symlinked directory and file are added as links; 'beyond a symbolic link' is NOT the trusted missing-pathspec error
  L=$(_mk_leaky_repo clean); ln -s docs "$L/linkdir"; ln -s clean.txt "$L/linkfile"
  _sx "G12i untracked symlinked directory + file in a clean repo: 'git add -A && git commit' -> allow" "$L" "git add -A && git commit -m x" allow
  _t "G12j ... the sim index records the links as symlinks (mode 120000), not their targets" \
    "linkdir=$(_rec_mode_of linkdir) linkfile=$(_rec_mode_of linkfile)" test "$(_rec_mode_of linkdir)" = 120000 -a "$(_rec_mode_of linkfile)" = 120000
  _sx "G12k 'git add linkdir/f.txt' is beyond a symbolic link: not the trusted error -> superset -> allow" "$L" "git add linkdir/f.txt && git commit -m x" allow
  _t "G12k2 ... the superset ran" "adds=$(_sim_adds)" _superset_add
  _rows_since_mark git-commit-secret-scan-sim-failed
  _t "G12k3 ... and it is NOT recorded as the benign pathspec-missing bypass" "n=$ROWS_N txt=$ROWS_TXT" _row_has 0
  # a symlinked .gitleaks.toml still configures the scan
  SL=$(_mk_leaky_repo untracked); tomlreal="$SUITE_TMP/toml.real.$SIM_N"
  mv "$SL/.gitleaks.toml" "$tomlreal"; ln -s "$tomlreal" "$SL/.gitleaks.toml"
  _sx "G12l a symlinked .gitleaks.toml: the config is found and the scan runs -> deny" "$SL" "git add -A && git commit -m x" deny "leak.json"
}
_sim_resolves() { _cat_has idxexists yes && _cat_has objexists yes; }

# ---- the rest: roots, force-add, rm/mv, residuals, consumer, oracle, check-attr -----------------
_t_sim_extra() {
  _sim_init
  [[ -n "$SIM_PD" ]] || SIM_PD=$(_mk_sim_path)
  local A B U I RM S T Cn a
  A=$(_mk_leaky_repo clean); B=$(_mk_leaky_repo untracked); U=$(_mk_leaky_repo untracked)

  # two scanned roots: the walker keeps a UNION of targets, so a misapplied replay would hide B's leak
  _sx "X1 two scanned roots (A clean, B holds the untracked leak): superset in every root -> deny naming B" "$A" \
    "cd $A && cd $B && git add clean.txt && git commit -m x" deny "leak.json" "$B"
  _t "X1b every sim add is the superset" "adds=$(_sim_adds)" _all_adds_superset
  _t "X1c one sim index per root (two distinct GIT_INDEX_FILE values seen by gitleaks)" "calls=$(cat "$SIM_REC/calls.log" 2>/dev/null | head -c 400)" _distinct_idx 2
  _sx "X1 gap witness: 'cd A && cd B && git commit -m x' allows" "$A" "cd $A && cd $B && git commit -m x" allow
  _sx "X1d mixed directories: 'git -C docs add f.txt && git add clean.txt && git commit' -> superset -> deny" "$U" \
    "git -C docs add f.txt && git add clean.txt && git commit -m x" deny "leak.json"
  _t "X1e ... every sim add is the superset" "adds=$(_sim_adds)" _all_adds_superset
  # Two roots with NO cd / -C: the process cwd is repo B (an untracked leak), the payload cwd is repo A (clean). The
  # directory proof (i) names A, so the command stages in A only (CTO row 33): A is replayed exactly and B, a fallback
  # root the command cannot stage into, is scanned against its REAL index (the untracked leak is not staged: allow).
  PAYLOAD_CWD="$A" _sx "X1f process cwd = repo B (untracked leak), payload cwd = clean repo A, 'git add clean.txt && git commit' -> allow (B is not staged)" "$B" \
    "git add clean.txt && git commit -m x" allow
  _t "X1g ... A was replayed exactly (add clean.txt) and B received no sim add at all" "adds=$(_sim_adds)" test "$(_sim_add_n)" = 1 -a "$(_exact_add clean.txt && echo y)" = y
  # ... and a fallback root's REAL staged content is still scanned
  S=$(_mk_staged_repo)
  PAYLOAD_CWD="$A" _sx "X1h process cwd = repo with a STAGED leak, payload cwd = clean repo A -> deny naming the staged repo (real-index scan)" "$S" \
    "git add clean.txt && git commit -m x" deny "leak.json" "$S"
  # the hole row 33 must not open: a -C in a non-commit segment names A, the add runs in the process cwd B
  PAYLOAD_CWD="$A" _sx "X1i hole closure: 'git -C B status; git add -A && git commit' with the shell in clean repo A and B holding an untracked leak -> deny (the directory is unproven: superset in every root)" "$A" \
    "git -C $B status; git add -A && git commit -m x" deny "leak.json" "$B"
  _t "X1j ... every sim add is the superset" "adds=$(_sim_adds)" _all_adds_superset

  # force-add: add -A never sees an ignored file
  I=$(_mk_leaky_repo ignored)
  _sx "X2 'git add -f ignored.pem && git commit' -> deny (the exact replay finds the force-added file)" "$I" "git add -f ignored.pem && git commit -m x" deny "ignored.pem"
  a=$(_sim_adds)
  _t "X2b ... an exact add -f naming ignored.pem, no add -A" "adds=$a" test "$([[ "$a" == *" -f "* && "$a" == *" ignored.pem "* && "$a" != *" -A "* ]] && echo yes)" = yes
  _sx "X2c must-PASS: 'git add -A && git commit' on the same shape allows (an ignored file is not added)" "$I" "git add -A && git commit -m x" allow
  _sx "X2d a NON-literal force-add is denied with the own-call repair" "$I" 'F=ignored.pem; git add -f $F && git commit -m x' deny "force-add" "its own call"
  _sx "X2e a force-add behind an unknown launcher: the superset plus a literal-word add -f finds it -> deny" "$I" \
    "mise exec -- git add -f ignored.pem && git commit -m x" deny "ignored.pem"
  a=$(_sim_adds)
  _t "X2f ... both a superset add and an add -f of the literal word ran" "adds=$a" test "$([[ "$a" == *" -A "* && "$a" == *" -f "* && "$a" == *" ignored.pem "* ]] && echo yes)" = yes

  # rm / mv act on the working tree and add no blob: recognised, ignored, NEVER executed
  RM=$(_mk_leaky_repo clean)
  ( cd "$RM" && echo a > a.txt && echo b > b.txt && git add a.txt b.txt && git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m files )
  _sx "X3 'git rm a.txt && git mv b.txt c.txt && git commit -m x' allows" "$RM" "git rm a.txt && git mv b.txt c.txt && git commit -m x" allow
  _t "X3b ... and runs no simulation" "log=$(_log_n) adds=$(_sim_add_n)" _no_sim
  _t "X3c ... and both working-tree files are still where they were (nothing was executed)" "a=$(test -f "$RM/a.txt" && echo y) b=$(test -f "$RM/b.txt" && echo y) c=$(test -e "$RM/c.txt" && echo y)" \
    test -f "$RM/a.txt" -a -f "$RM/b.txt" -a ! -e "$RM/c.txt"
  S=$(_mk_staged_repo)
  _sx "X3d 'git rm --cached .gitleaks.toml && git commit' still reaches the existing scan (staged leak) -> deny" "$S" "git rm --cached .gitleaks.toml && git commit -m x" deny "leak.json"
  _t "X3e ... with no simulation" "log=$(_log_n) adds=$(_sim_add_n)" _no_sim

  # named residuals (the hook header lists them): pinned so a change is noticed, not claimed as coverage
  T=$(_mk_leaky_repo tracked-modified); Cn=$(_mk_leaky_repo clean)
  _sx "X4 residual: 'sed -i' before 'commit -a' is invisible (the scan sees the pre-execution state) -> allow" "$Cn" \
    "sed -i s/v1/v2/ tracked.json && git commit -am x" allow
  _sx "X4b a positional pathspec AFTER -m is covered now (perl lexes every strict commit) -> deny" "$T" "git commit -m x tracked.json" deny "tracked.json"
}

# ---- repair texts (CTO row 34): chosen from the facts, and every recipe replayed through the hook -----------------
_t_sim_repair() {
  _sim_init
  [[ -n "$SIM_PD" ]] || SIM_PD=$(_mk_sim_path)
  local U T S A B Cn r name long
  U=$(_mk_leaky_repo untracked); T=$(_mk_leaky_repo tracked-modified); S=$(_mk_staged_repo)
  A=$(_mk_leaky_repo clean); B=$(_mk_leaky_repo untracked); Cn=$(_mk_leaky_repo clean)

  # a simulation FAILURE (deadline 0) names the retry that fits the command's own staging style
  SIM_ENV=("CIS_DEADLINE_SECONDS=0")
  _sx "R1 'git commit -am x', simulation failed -> the retry drops -a (git add -u first)" "$T" "git commit -am x" deny "git add -u" "WITHOUT -a" "!load condition"
  _sx "R2 'git commit -m x -- tracked.json', simulation failed -> add the path, check the staged list, commit without paths" "$T" "git commit -m x -- tracked.json" deny \
    "git diff --cached --name-only" "WITHOUT the paths" "!load condition"
  _sx "R3 'git add clean.txt && git commit', simulation failed -> add as its own call, commit as a second call" "$U" "git add clean.txt && git commit -m x" deny \
    "as its own call, then run the commit as a second call" "!load condition"
  SIM_ENV=()

  # a finding: the recovery is chosen from where the file is, not from the command's shape
  _sx "R4 a TRACKED modified file named by an add record -> scrub in place, never delete, .gitignore does not help" "$T" "git add tracked.json && git commit -m x" deny \
    "tracked.json" "TRACKED" "do not delete a tracked file" "a .gitignore entry does not help" "!or delete the file" "!Nothing is staged yet"
  _rows_since_mark git-commit-secret-scan
  _t "R4b ... the ledger row is the base rule id with cause=finding" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "cause=finding"
  _sx "R5 a file ALREADY staged in the real index (chained add -A) -> restore --staged as its OWN call, never 'nothing is staged'" "$S" "git add -A && git commit -m x" deny \
    "already staged" "git restore --staged <path>' as its OWN call" "!Nothing is staged yet"
  _sx "R6 the finding root is one the command does not name -> the 'cd <target>' recipe" "$B" "git -C $A status; git add -A && git commit -m x" deny \
    "leak.json" "does not name" "run 'cd $A' as its own call"
  _sx "R7 inexact-word cause (glob) -> say why the full tree was scanned and ask for literal paths" "$U" "git add *.txt && git commit -m x" deny "leak.json" "write literal paths" "!this same command"
  _sx "R7b loop cause -> the command cannot be replayed: split it" "$U" "for f in clean.txt; do git add \$f; done; git commit -m x" deny "leak.json" "cannot replay"
  _sx "R7c unproven-dir cause -> name the directory" "$U" "git -C docs add f.txt && git add clean.txt && git commit -m x" deny "leak.json" "cd /abs/path &&"
  _sx "R7d untracked finding -> the .gitignore / separate-call recovery" "$U" "git add -A && git commit -m x" deny "leak.json" "untracked" ".gitignore" "separate call" "!restore --staged"

  # file names are data: control characters, line separators and bidi overrides are replaced and the length is capped
  U=$(_mk_leaky_repo untracked); assert_fixture_dir "$U"
  name=$'bad\nname\xe2\x80\xa8\xe2\x80\xaeevil\xc2\x85.json'
  cp "$U/leak.json" "$U/$name"; rm -f "$U/leak.json"
  _sxr "R8 a hostile file name in a finding (newline, U+2028, U+202E) is sanitised in the deny text" "$U" "git add -A && git commit -m x" deny "Locations: bad?name"
  r="$SIM_R"
  _t "R8b ... no raw newline, U+0085, U+2028 or U+202E reaches the reason" "reason=${r:0:200}" test "$([[ "$r" != *$'\n'* && "$r" != *$'\xe2\x80\xa8'* && "$r" != *$'\xe2\x80\xae'* && "$r" != *$'\xc2\x85'* ]] && echo y)" = y
  U=$(_mk_leaky_repo untracked); assert_fixture_dir "$U"
  long=$(printf 'n%.0s' $(seq 1 250))
  cp "$U/leak.json" "$U/$long.json"; rm -f "$U/leak.json"
  _sxr "R8c a 250-character file name is cut" "$U" "git add -A && git commit -m x" deny "Locations: nnnn"
  r="$SIM_R"
  _t "R8d ... the full name is not in the reason" "len=${#r}" test "$([[ "$r" != *"${long:0:130}"* ]] && echo y)" = y

  # the same for the `-diff` re-scan list: a hostile name there is sanitised too
  U=$(_mk_leaky_repo untracked); assert_fixture_dir "$U"
  printf '*.dat -diff\n' > "$U/.gitattributes"
  name=$'ev\nil\xe2\x80\xa8.dat'
  cp "$U/leak.json" "$U/$name"; rm -f "$U/leak.json"
  _sxr "R8e a hostile name in the -diff re-scan list is sanitised" "$U" "git add -A && git commit -m x" deny "carrying a \`-diff\` gitattribute: ev?il?.dat"
  r="$SIM_R"
  _t "R8f ... no raw newline or U+2028 reaches that reason either" "reason=${r:0:200}" test "$([[ "$r" != *$'\n'* && "$r" != *$'\xe2\x80\xa8'* ]] && echo y)" = y

  U=$(_mk_leaky_repo untracked); assert_fixture_dir "$U"
  printf '*.dat -diff\n' > "$U/.gitattributes"
  for name in 1 2 3 4 5 6 7; do cp "$U/leak.json" "$U/f$name.dat"; done; rm -f "$U/leak.json"
  _sxr "R8g seven -diff files: the deny text names five and counts the rest" "$U" "git add -A && git commit -m x" deny "and 2 more" "f1.dat" "f5.dat" "!f6.dat" "!f7.dat"

  # every recipe above is replayed: its first step is applied to the fixture, then the hook judges the second step
  Cn=$(_mk_leaky_repo tracked-modified); assert_fixture_dir "$Cn"
  printf '{"k":"v2"}\n' > "$Cn/tracked.json"   # scrubbed: a clean change
  git -C "$Cn" add -u
  _sx "R9 recipe (-a): 'git add -u' as its own call, then 'git commit -m x' without -a -> allow" "$Cn" "git commit -m x" allow
  Cn=$(_mk_leaky_repo tracked-modified); assert_fixture_dir "$Cn"
  printf '{"k":"v2"}\n' > "$Cn/tracked.json"   # scrubbed: a clean change
  git -C "$Cn" add tracked.json
  _sx "R9b recipe (pathspec): 'git add tracked.json', the staged list is only that, then 'git commit -m x' -> allow" "$Cn" "git commit -m x" allow
  _t "R9c ... the staged list the recipe asks to check holds exactly that file" "list=$(git -C "$Cn" diff --cached --name-only)" test "$(git -C "$Cn" diff --cached --name-only)" = "tracked.json"
  Cn=$(_mk_leaky_repo untracked); assert_fixture_dir "$Cn"
  git -C "$Cn" add clean.txt
  _sx "R9d recipe (untracked leak): stage only the intended file, then 'git commit -m x' -> allow" "$Cn" "git commit -m x" allow
  Cn=$(_mk_staged_repo); assert_fixture_dir "$Cn"
  git -C "$Cn" restore --staged leak.json; rm -f "$Cn/leak.json"
  _sx "R9e recipe (staged): 'git restore --staged' as its own call, scrub, then 'git commit -m x' -> allow" "$Cn" "git commit -m x" allow
  _sx "R9f recipe (cd <target>): the payload cwd is the target, the same command -> allow" "$A" "git -C $A status; git add -A && git commit -m x" allow
  Cn=$(_mk_leaky_repo tracked-modified); assert_fixture_dir "$Cn"
  printf '{"k":"v2"}\n' > "$Cn/tracked.json"   # scrubbed: a clean change
  _sx "R9g recipe (tracked): scrub in place, then the SAME command again -> allow" "$Cn" "git add tracked.json && git commit -m x" allow
  _sx "R9h recipe (literal paths): the inexact glob rewritten as a literal path -> allow" "$(_mk_leaky_repo untracked)" "git add clean.txt && git commit -m x" allow
}

# ---- fidelity: the replay must read what the COMMAND reads (review round, rows 26 and 27) ---------
# A repo with an IGNORED .env at the root (content per $1: benign | secret) and an ignored sub/.env holding the
# synthetic secret. `git add -f .env` reads whichever file is in the directory the command is in.
_mk_force_repo() {  # <benign|secret> -> prints the repo
  local d; d=$(_mk_leaky_repo clean)
  assert_fixture_dir "$d"
  (
    cd "$d" || exit 1
    printf 'ignored.pem\n.env\n' > .gitignore; mkdir -p sub; echo keep > sub/keep.txt
    git add .gitignore sub/keep.txt
    git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m ignore
    if [[ "$1" == secret ]]; then _mk_pem "$_SIM_BODY" > .env; else echo BENIGN_ROOT > .env; fi
    _mk_pem "$_SIM_BODY" > sub/.env
  )
  printf '%s\n' "$d"
}

_t_sim_fidelity() {
  _sim_init
  [[ -n "$SIM_PD" ]] || SIM_PD=$(_mk_sim_path)
  local F A B T I cmd
  F=$(_mk_force_repo benign); A=$(_mk_force_repo secret); B=$(_mk_force_repo benign); T=$(_mk_leaky_repo tracked-modified)
  I=$(_mk_leaky_repo ignored)

  # L1: a force-add in the SUPERSET must read the file in the directory the command is in, not the payload cwd.
  _sx "L1 a relative cd: 'cd sub && git add -f .env && git commit' (a benign .env at the cwd) -> deny, the secret is in sub/" "$F" \
    "cd sub && git add -f .env && git commit -m x" deny "force-add" "its own call"
  _sx "L1b positive control: the same command with an ABSOLUTE first cd is replayed in sub/ and finds the secret" "$F" \
    "cd $F/sub && git add -f .env && git commit -m x" deny "sub/.env"
  _sx "L1c benign control: 'git add -f .env && git commit' at the root scans the root .env -> allow" "$F" \
    "git add -f .env && git commit -m x" allow
  _sx "L1d cross-repo: 'cd <A> && git add -f .env && git commit' from repo B -> deny (A's secret is scanned, not B's .env)" "$B" \
    "cd $A && git add -f .env && git commit -m x" deny
  _sx "L1e cross-repo, a '\$' in the text defeats the cd-first proof: still deny, never the wrong repo's file" "$B" \
    "cd $A && git add -f .env && git commit -m \"\$(cat <<'EOF'
x
EOF
)\"" deny
  _sx "L1f a relative -C: 'git -C sub add -f .env && git commit' -> deny (the directory is not proven)" "$F" \
    "git -C sub add -f .env && git commit -m x" deny "force-add"
  _rows_since_mark git-commit-secret-scan-sim-deny
  _t "L1f2 ... one sim-deny row, cause force-unproven-dir" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "cause=force-unproven-dir"

  # L2: the commit step ALWAYS runs. A dry-run add stages nothing, and an exact add before `commit -a` still
  # leaves every tracked change to the commit. (tracked.json holds the secret, unstaged; clean.txt is untracked.)
  for cmd in "git add clean.txt && git commit -am x" \
             "git add -A -- docs && git commit -am x" \
             "git add -n -A && git commit -am x" \
             "git add -A -n && git commit -am x" \
             "git add --dry-run -A && git commit -am x" \
             "git add -nA && git commit -am x" \
             "git add -An && git commit -am x" \
             "git add -n -A && git commit -m x -- tracked.json" \
             "git add clean.txt && git commit -m x -- tracked.json"; do
    _sx "L2 the commit step runs after an exact add: $cmd" "$T" "$cmd" deny "tracked.json"
  done
  # A force-add whose paths come from stdin or a file has no literal path word to re-run: deny, never skip.
  _sx "L1g force-add with its paths on stdin ('xargs git add -f') -> deny force-add (no literal path to scan)" "$I" \
    "printf 'ignored.pem\\n' | xargs git add -f && git commit -m x" deny "force-add" "its own call"
  _sx "L1h force-add with --pathspec-from-file -> deny force-add" "$I" \
    "git add -f --pathspec-from-file=paths.txt && git commit -m x" deny "force-add" "its own call"
  _rows_since_mark git-commit-secret-scan-sim-deny
  _t "L1i ... one sim-deny row, cause force-nonliteral" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "cause=force-nonliteral"
  _sx "L2 control: a dry-run add with NO commit -a stages nothing -> allow" "$T" "git add -n -A && git commit -m x" allow
  _sx "L2 control: an exact add of a clean path with NO commit -a stages only that path -> allow" "$T" "git add clean.txt && git commit -m x" allow
}

# ---- fail-open seams, the bound, and scan_root's own pins (review round, rows 28 to 32) -------------------
# A mktemp that misbehaves for one template (fail: exit 1; badpath: prints a path that cannot be written).
_mk_mktemp_wrapper() {  # <stub PATH dir> <template glob> <fail|badpath>
  local d="$1" glob="$2" mode="$3" real
  real=$(command -v mktemp); assert_fixture_dir "$d"; rm -f "$d/mktemp"
  if [[ "$mode" == fail ]]; then
    printf '#!/bin/sh\nfor a in "$@"; do case "$a" in %s) exit 1 ;; esac; done\nexec %s "$@"\n' "$glob" "$real" > "$d/mktemp"
  else
    printf '#!/bin/sh\nfor a in "$@"; do case "$a" in %s) echo /no/such/dir/for/the/hook/report.json; exit 0 ;; esac; done\nexec %s "$@"\n' "$glob" "$real" > "$d/mktemp"
  fi
  chmod +x "$d/mktemp"
}
# A copy of the hooks tree with one edit, for the torn-install arms.
_mk_hooks_copy() {  # <sed expression> <relative file> -> prints the copied hook script
  local cp; cp=$(mktemp -d "$SUITE_TMP/hookcopy.XXXXXX"); assert_fixture_dir "$cp"
  mkdir -p "$cp/.claude" "$cp/plugins/soleur/hooks"; cp -R "$REPO_ROOT/.claude/hooks" "$cp/.claude/hooks"
  cp -R "$REPO_ROOT/plugins/soleur/hooks/lib" "$cp/plugins/soleur/hooks/lib"
  sed "$1" "$cp/.claude/hooks/$2" > "$cp/.claude/hooks/$2.new" && mv "$cp/.claude/hooks/$2.new" "$cp/.claude/hooks/$2"
  printf '%s\n' "$cp/.claude/hooks/git-commit-secret-scan.sh"
}
_no_json() { [[ -z "$OUT" ]]; }

_t_sim_seams() {
  _sim_init
  [[ -n "$SIM_PD" ]] || SIM_PD=$(_mk_sim_path)
  local C U S A B C3 hk pd mk i out rc start fx fsm D lib walk
  C=$(_mk_leaky_repo clean); U=$(_mk_leaky_repo untracked); S=$(_mk_staged_repo)
  lib="$REPO_ROOT/.claude/hooks/lib/commit-index-sim.sh"; walk="$REPO_ROOT/.claude/hooks/lib/commit-target-roots.sh"

  # --- torn install (row 32): a walker or lib that does not announce its API denies every strict commit ---
  hk=$(_mk_hooks_copy 's/^  CTR_STAGE_API=1$/  :/' lib/commit-target-roots.sh)
  _t "S1 fixture: the edited walker copy really lacks CTR_STAGE_API=1" "still present" bash -c '! grep -q "^  CTR_STAGE_API=1" "$1"' _ "$(dirname "$hk")/lib/commit-target-roots.sh"
  HOOK_OVERRIDE="$hk" _sx "S1a a walker without CTR_STAGE_API: a CHAINED commit is denied through the lib repair" "$C" "git add -A && git commit -m x" deny "git checkout -- .claude/hooks/lib"
  HOOK_OVERRIDE="$hk" _sx "S1b ... and a PLAIN strict commit is denied too (never a silent revert to the pre-run index)" "$C" "git commit -m x" deny "git checkout -- .claude/hooks/lib"
  hk=$(_mk_hooks_copy 's/^CIS_API=1$/CIS_API=0/' lib/commit-index-sim.sh)
  HOOK_OVERRIDE="$hk" _sx "S1c a sim lib announcing another API version is denied the same way" "$C" "git add -A && git commit -m x" deny "git checkout -- .claude/hooks/lib"
  hk=$(_mk_hooks_copy 's/^  CTR_STAGE_API=1$/  CTR_STAGE_API=1/' lib/commit-target-roots.sh)
  HOOK_OVERRIDE="$hk" _sx "S1d control: an unedited copy of the tree still works (clean repo, chained commit -> allow)" "$C" "git add -A && git commit -m x" allow

  # --- an unexpected error inside the simulated scan DENIES (set -E + the ERR trap); with the sim off nothing changes ---
  pd=$(_mk_sim_path); _mk_mktemp_wrapper "$pd" '*gitleaks-staged-*' badpath
  _with_pd "$pd" _sx "S2 an unwritable report file under 'git add -A && git commit' -> deny, not a silent exit 1" "$C" "git add -A && git commit -m x" deny "unexpected error"
  _rows_since_mark git-commit-secret-scan-sim-deny
  _t "S2b ... one sim-deny row, cause internal-error" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "cause=internal-error"
  _with_pd "$pd" _sim_run "$C" "git commit -m x"
  _t "S2c control: the same broken mktemp under a PLAIN commit keeps the old behaviour (exit 1, no JSON)" "out=${OUT:0:100}" _no_json
  pd=$(_mk_sim_path); _mk_mktemp_wrapper "$pd" '*gitleaks-nodiff-*' fail
  _with_pd "$pd" _sx "S3 a failed mktemp for the report files under a would-be-index scan -> deny temp-dir" "$C" "git add -A && git commit -m x" deny "temporary file"
  _rows_since_mark git-commit-secret-scan-sim-deny
  _t "S3b ... cause temp-dir" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "cause=temp-dir"

  # --- a gitleaks that errors in sim mode is a deny (row 31); the plain-mode bypass is unchanged ---
  SIM_ENV=("GL_REC_RC=2")
  _sx "S4 gitleaks exits 2 on the simulated index -> deny scan-error" "$C" "git add -A && git commit -m x" deny "did not complete"
  _rows_since_mark git-commit-secret-scan-sim-deny
  _t "S4b ... cause scan-error" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "cause=scan-error"
  SIM_ENV=("GL_REC_RC=2" "GL_REC_RC_REPORT=1")
  _sx "S4e gitleaks writes a finding and then exits 2: an ERROR first (the label is scan-error, not finding)" "$U" "git add -A && git commit -m x" deny "did not complete"
  _rows_since_mark git-commit-secret-scan-sim-deny
  _t "S4f ... cause scan-error" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "cause=scan-error"
  SIM_ENV=("GL_REC_RC=1")
  _sx "S4c gitleaks exits 1 with NO report on the simulated index -> deny scan-error" "$C" "git add -A && git commit -m x" deny "did not complete"
  SIM_ENV=("GL_REC_RC=2")
  _sx "S4d control: the same gitleaks error on a PLAIN commit is still the old bypass -> allow" "$C" "git commit -m x" allow
  SIM_ENV=()
  # the -diff re-scan: a failing detect, and a blob that cannot be read
  D=$(_mk_leaky_repo clean); assert_fixture_dir "$D"; mkdir -p "$D/.git/info"; echo 'clean.txt -diff' > "$D/.git/info/attributes"
  SIM_ENV=("GL_REC_DETECT_RC=2")
  _sx "S5 the -diff re-scan (detect --no-git) exits 2 in sim mode -> deny scan-error" "$D" "git add clean.txt && git commit -m x" deny "did not complete"
  SIM_ENV=("GL_REC_DETECT_RC=0")
  _sx "S5b control: the same fixture with a healthy re-scan -> allow" "$D" "git add clean.txt && git commit -m x" allow
  _t "S5c ... and the re-scan really saw clean.txt (checkout-index wrote the blob)" "nodiff=$(cat "$SIM_REC"/nodiff.* 2>/dev/null)" _contains "$(cat "$SIM_REC"/nodiff.* 2>/dev/null)" "clean.txt"
  SIM_ENV=("SHIM_FAILV=checkout-index")
  _sx "S5d a blob that cannot be read for the -diff re-scan -> deny scan-error (never an empty file read as clean)" "$D" "git add clean.txt && git commit -m x" deny "did not complete"
  SIM_ENV=("SHIM_FAILV=check-attr")
  _sx "S6 the batched check-attr fails in sim mode -> deny check-attr-failed" "$C" "git add -A && git commit -m x" deny "attribute guard could not run"
  _rows_since_mark git-commit-secret-scan-sim-deny
  _t "S6b ... cause check-attr-failed" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "cause=check-attr-failed"
  _sx "S6c control: the same failure on a PLAIN commit warns and allows" "$C" "git commit -m x" allow
  SIM_ENV=()

  # --- scan_root pins core.fsmonitor off (row 29): stub-tier proof of WHERE, real-tier proof of WHAT ---
  _sx "S7 a chained commit: gitleaks and the three direct git calls carry core.fsmonitor=false" "$U" "git add -A && git commit -m x" deny "leak.json"
  _t "S7b ... gitleaks saw core.fsmonitor=false in GIT_CONFIG_COUNT/KEY/VALUE and in GIT_CONFIG_PARAMETERS" "env=$(cat "$SIM_REC"/env.* 2>/dev/null | head -c 400)" _gitleaks_env_pinned
  _t "S7c ... check-attr and diff --cached carry -c core.fsmonitor=false" "log=$(grep -E 'VERB=(diff|check-attr) ' "$SIM_LOG" | head -c 300)" _scan_git_pinned
  fsm="$SUITE_TMP/fsm-malformed.sh"; printf '#!/bin/sh\nprintf "\\0"\n' > "$fsm"; chmod +x "$fsm"; assert_fixture_dir "$S"
  git -C "${S:?}" config core.fsmonitor "$fsm"
  if _needs_gl "S8 malformed-token core.fsmonitor on a staged secret"; then
    # The fixture control is informational: on a gitleaks where a bare `gitleaks git --staged` is NOT blinded by the
    # config the hook-level assertion below still has to hold; where it IS blinded (8.30.1, measured) it is the proof.
    rc=0; ( cd "$S" && gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1 --report-format json --report-path "$SUITE_TMP/fsm-ctl.json" >/dev/null 2>&1 ) || rc=$?
    _sxr "S8 [gitleaks] a core.fsmonitor program answering with a malformed token must not blind the scan of a staged secret (bare gitleaks rc=$rc) -> deny" "$S" "git commit -m x" deny "leak.json"
  fi

  # --- 4,000 untracked `*.dat binary` files: the -diff re-scan is one checkout-index call, not 4,000 forks ---
  D=$(_mk_leaky_repo clean); assert_fixture_dir "$D"
  ( cd "$D" && printf '*.dat binary\n' > .gitattributes && mkdir -p dat && i=0 && while [ "$i" -lt 4000 ]; do echo "x$i" > "dat/f$i.dat"; i=$((i + 1)); done )
  start=$SECONDS
  _sx "S9 4,000 untracked '*.dat binary' files + 'git add -A && git commit' -> allow (no load deny)" "$D" "git add -A && git commit -m x" allow
  _t "S9b ... well inside the deadline (the old per-path loop took 42 s)" "elapsed=$((SECONDS - start)) s" test $((SECONDS - start)) -lt 15
  _t "S9c ... and the re-scan was given all 4,000 blobs" "n=$(tr -cd '|' < "$(ls "$SIM_REC"/nodiff.* | head -n 1)" | wc -c | tr -d ' ')" _nodiff_has_4000

  # --- the sim's git calls run no repository hook and leave a dirty submodule's real index alone (row 28) ---
  D=$(_mk_leaky_repo clean); assert_fixture_dir "$D"
  mk="$SUITE_TMP/hook.marker"; rm -f "$mk"
  mkdir -p "$D/.git/hooks"; printf '#!/bin/sh\necho ran >> "%s"\n' "$mk" > "$D/.git/hooks/post-index-change"; chmod +x "$D/.git/hooks/post-index-change"
  cl=$(mktemp -d "$SUITE_TMP/hookctl.XXXXXX"); cp -a "$D/." "$cl/"; git -C "${cl:?}" add clean.txt
  _t "S10 fixture control: a plain 'git add' DOES run the post-index-change hook" "no marker" test -e "$mk"
  rm -f "$mk"
  _sx "S10b 'git add -A && git commit' on that repo -> allow" "$D" "git add -A && git commit -m x" allow
  _t "S10c ... and the repository's post-index-change hook never ran at hook time" "marker exists" test ! -e "$mk"
  _make_dirty_submodule_repo
  _sx "S11 a repo with a DIRTY submodule that has its own hook: 'git add -A && git commit' -> allow" "$SM" "git add -A && git commit -m x" allow
  _t "S11b ... the submodule's own hook never ran" "markers: $(cat "$SM_MARK" 2>/dev/null)" test ! -e "$SM_MARK"
  _t "S11c ... and the submodule's REAL index was not rewritten (mtime unchanged)" "before=$SM_IDX_MT after=$(_mtime "$SM_IDX")" test "$(_mtime "$SM_IDX")" = "$SM_IDX_MT"

  # --- a RELATIVE TMPDIR must not turn the guard's exit 2 into a hook that blocks every staging commit ---
  D=$(_mk_leaky_repo clean); assert_fixture_dir "$D"; mkdir -p "$D/rel-tmp"
  SIM_ENV=("TMPDIR=rel-tmp")
  _sx "S15 TMPDIR=rel-tmp (relative): 'git add -A && git commit' on a clean repo -> allow (the sim directory is canonicalised once)" "$D" "git add -A && git commit -m x" allow
  _t "S15b ... and the relative TMPDIR is empty afterwards" "left: $(ls -A "$D/rel-tmp")" test -z "$(ls -A "$D/rel-tmp")"
  SIM_ENV=()
  # --- a TMPDIR that cannot hold the report files (it does not exist) is a deny, never an exit 1 that lets the commit through ---
  D=$(_mk_leaky_repo clean); assert_fixture_dir "$D"
  SIM_ENV=("TMPDIR=$SUITE_TMP/no/such/dir")
  _sx "S16 TMPDIR names a directory that does not exist: 'git add -A && git commit' -> deny (temp-dir), never allow" "$D" "git add -A && git commit -m x" deny "temporary file could not be created"
  _rows_since_mark git-commit-secret-scan-sim-deny
  _t "S16b ... one sim-deny row, cause temp-dir" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "cause=temp-dir"
  SIM_ENV=()

  # --- more than two roots, and one clock for ALL of them ---
  A=$(_mk_leaky_repo clean); B=$(_mk_leaky_repo clean); C3=$(_mk_leaky_repo untracked)
  _sx "S12 three roots (the leak is in the THIRD): 'cd A && cd B && cd C && git add clean.txt && git commit' -> superset in every root -> deny" "$A" \
    "cd $A && cd $B && cd $C3 && git add clean.txt && git commit -m x" deny "leak.json" "$C3"
  _t "S12b ... one sim index per root (three distinct GIT_INDEX_FILE values)" "calls=$(cat "$SIM_REC/calls.log" 2>/dev/null | head -c 300)" _distinct_idx 3
  SIM_ENV=("CIS_DEADLINE_SECONDS=5" "GL_REC_SLEEP=3")
  _sx "S13 two roots whose scans take 3 s each under a 5 s TOTAL deadline -> deny (one clock, not one per root)" "$A" \
    "cd $A && cd $B && git add clean.txt && git commit -m x" deny
  _rows_since_mark git-commit-secret-scan-sim-deny
  _t "S13b ... cause sim-timeout" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "cause=sim-timeout"
  SIM_ENV=()

  # --- every configured filter is neutralised: all four settings, for every filter (a dotted name included) ---
  fx=$(_mk_leaky_repo untracked); assert_fixture_dir "$fx"; rm -f "$SUITE_TMP/f1.mark" "$SUITE_TMP/f2.mark"
  git -C "${fx:?}" config filter.mark.clean "touch $SUITE_TMP/f1.mark; cat"; git -C "$fx" config filter.mark.smudge cat
  git -C "$fx" config filter.mark.process cat; git -C "$fx" config filter.mark.required true
  git -C "$fx" config filter.a.b.clean "touch $SUITE_TMP/f2.mark; cat"
  printf '*.json filter=mark\n*.txt filter=a.b\n' > "$fx/.gitattributes"
  _sx "S14 two configured filters, one required=true: 'git add -A && git commit' -> deny on the leak (the add did not die)" "$fx" "git add -A && git commit -m x" deny "leak.json"
  _t "S14b ... both filters neutralised on every sim add (clean, process, smudge, required=false)" "adds=$(_sim_adds)" _adds_neutralise_filter mark a.b
  _t "S14c ... and neither filter ran at hook time" "markers: $(ls "$SUITE_TMP"/f?.mark 2>/dev/null)" _no_filter_markers
}
_gitleaks_env_pinned() {
  local e; e=$(cat "$SIM_REC"/env.* 2>/dev/null) || return 1
  [[ "$e" == *"core.fsmonitor"* && "$e" == *"'core.fsmonitor'='false'"* ]]
}
_scan_git_pinned() {
  local l n=0
  while IFS= read -r l; do
    n=$((n + 1)); [[ "$l" == *"core.fsmonitor=false"* ]] || return 1
  done < <(grep -E 'VERB=(diff|check-attr) ' "$SIM_LOG")
  [[ "$n" -ge 2 ]]
}
_nodiff_has_4000() { local c; c=$(tr -cd '|' < "$(ls "$SIM_REC"/nodiff.* | head -n 1)" | wc -c | tr -d ' '); [[ "$c" -eq 4000 ]]; }
_no_filter_markers() { [[ ! -e "$SUITE_TMP/f1.mark" && ! -e "$SUITE_TMP/f2.mark" ]]; }
_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
# A clean repo with a submodule whose working tree is DIRTY, whose own gitdir carries a post-index-change hook, and
# whose real index has an old mtime. Sets SM (the repo), SM_MARK (the hook's marker), SM_IDX and SM_IDX_MT.
_make_dirty_submodule_repo() {
  local src
  src=$(mktemp -d "$SUITE_TMP/subsrc.XXXXXX"); assert_fixture_dir "$src"
  ( cd "$src" && git init -q -b main && git config user.email t@t && git config user.name t && echo s > s.txt && git add s.txt \
      && git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m s )
  SM=$(_mk_leaky_repo clean); assert_fixture_dir "$SM"
  ( cd "$SM" && git -c protocol.file.allow=always submodule add -q "$src" sub >/dev/null 2>&1 \
      && git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m addsub )
  SM_MARK="$SUITE_TMP/sub.marker"; rm -f "$SM_MARK"
  SM_IDX=$(git -C "$SM/sub" rev-parse --absolute-git-dir)/index
  mkdir -p "$(dirname "$SM_IDX")/hooks"
  printf '#!/bin/sh\necho ran >> "%s"\n' "$SM_MARK" > "$(dirname "$SM_IDX")/hooks/post-index-change"; chmod +x "$(dirname "$SM_IDX")/hooks/post-index-change"
  echo more >> "$SM/sub/s.txt"; sleep 1; touch "$SM/sub/s.txt"
  touch -t 200101010000 "$SM_IDX"
  SM_IDX_MT=$(_mtime "$SM_IDX")
}

# ---- unit C through the hook: unknown is opaque, refused environments, content from outside the tree -------------
_t_sim_walkc() {
  _sim_init
  [[ -n "$SIM_PD" ]] || SIM_PD=$(_mk_sim_path)
  local Cn U T cmd lib="$REPO_ROOT/.claude/hooks/lib/commit-target-roots.sh" long
  Cn=$(_mk_leaky_repo clean); U=$(_mk_leaky_repo untracked); T=$(_mk_leaky_repo tracked-modified)

  # row 26: content that comes from outside the working tree cannot be scanned: deny, with no simulation at all
  for cmd in "git update-index --add --cacheinfo 100644,0123456789012345678901234567890123456789,clean.txt && git commit -m x" \
             "git apply --cached p.diff && git commit -m x" \
             "git apply --index p.diff && git commit -m x"; do
    _sx "W1 content from outside the tree is denied (stage-unsimulable): $cmd" "$Cn" "$cmd" deny "outside the working tree" "its own call"
  done
  _t "W1b ... no simulation ran" "adds=$(_sim_adds)" test "$(_sim_add_n)" = 0
  _rows_since_mark git-commit-secret-scan-sim-deny
  _t "W1c ... a sim-deny row with cause stage-unsimulable" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "cause=stage-unsimulable"
  _sx "W1d a plain update-index --refresh is opaque, not denied: the superset finds the untracked leak" "$U" "git update-index --refresh && git commit -m x" deny "leak.json"
  _sx "W1e ... and a clean repo allows" "$Cn" "git update-index --refresh && git commit -m x" allow

  # row 22: an unknown staging form is the superset, never an exact replay or nothing
  for cmd in "make add && git commit -m x" \
             "git-add clean.txt && git commit -m x" \
             "/usr/lib/git-core/git-add clean.txt && git commit -m x" \
             'git "$S" clean.txt && git commit -m x' \
             "git commit -N -m x"; do
    _sx "W2 unknown staging form -> the superset: $cmd" "$U" "$cmd" deny "leak.json"
    _t "W2b ... a full add -A ran" "adds=$(_sim_adds)" _superset_add
  done
  _sx "W2c a dashed git-commit is a commit: 'git-commit -a -m x' with a modified tracked leak -> deny" "$T" "git-commit -a -m x" deny "tracked.json"
  _sx "W2d a non-git command without a staging verb stays exact: 'echo hi && git add clean.txt && git commit' (an unrelated untracked leak) -> allow" "$U" \
    "echo hi && git add clean.txt && git commit -m x" allow
  _t "W2e ... an exact replay" "adds=$(_sim_adds)" _exact_add clean.txt
  _sx "W2f an inline alias.* key on the staging record is refused" "$U" "git -c alias.add=status add clean.txt && git commit -m x" deny "its own call"

  # row 23: the environment allowlist
  for cmd in "HOME=/x git add clean.txt && git commit -m x" \
             "env HOME=/x git add clean.txt && git commit -m x" \
             "env -i git add clean.txt && git commit -m x" \
             "env -u HOME git add clean.txt && git commit -m x" \
             "sudo git add clean.txt && git commit -m x" \
             "export HOME=/x; git add clean.txt && git commit -m x" \
             "unset HOME; git add clean.txt && git commit -m x" \
             "HOME=/x; git add clean.txt && git commit -m x"; do
    _sx "W3 an environment the replay cannot reproduce is refused (stage in its own call): $cmd" "$U" "$cmd" deny "its own call"
  done
  _rows_since_mark git-commit-secret-scan-sim-deny
  _t "W3b ... the last one is a sim-deny row with cause config-refused" "n=$ROWS_N txt=$ROWS_TXT" _row_has 1 "cause=config-refused"
  for cmd in "LC_ALL=C git add clean.txt && git commit -m x" \
             "export LC_ALL=C; git add clean.txt && git commit -m x" \
             "env CI=1 git add clean.txt && git commit -m x" \
             "GIT_AUTHOR_NAME=a GIT_COMMITTER_NAME=b git add clean.txt && git commit -m x"; do
    _sx "W3c an allowlisted environment is replayed exactly -> allow: $cmd" "$U" "$cmd" allow
    _t "W3d ... an exact add of clean.txt" "adds=$(_sim_adds)" _exact_add clean.txt
  done
  _sx "W3e an export in a command that stages nothing is untouched" "$Cn" "export HOME=/x; git commit -m x" allow
  _t "W3f ... no simulation" "adds=$(_sim_adds)" test "$(_sim_add_n)" = 0

  # row 24: a commit record that stages is refused under the same conditions
  for cmd in "HOME=/x git commit -a -m x" \
             "git -c core.hooksPath=/x commit -a -m x" \
             "git --namespace n commit -a -m x" \
             "sudo git commit -o tracked.json -m x"; do
    _sx "W4 a staging commit under a config or environment the replay cannot honour is refused: $cmd" "$T" "$cmd" deny "its own call"
  done
  _sx "W4a ... and the retry for a commit -a drops the -a (git add -u first)" "$T" "HOME=/x git commit -a -m x" deny "git add -u" "WITHOUT -a"
  _sx "W4b a commit that stages nothing is untouched by the same prefix" "$Cn" "HOME=/x git commit -m x" allow
  _t "W4c ... no simulation" "adds=$(_sim_adds)" test "$(_sim_add_n)" = 0

  # row 22: the perl-less pre-filter is capped
  long=$(printf 'x%.0s' $(seq 1 16400))
  # a payload cwd that is in no work tree cannot hold the replay: the superset, not an unscanned command
  PAYLOAD_CWD="$SUITE_TMP" _sx "W6 payload cwd outside any work tree, process cwd = repo with an untracked leak: 'git add -A && git commit' -> deny (dir-not-root superset)" "$U" \
    "git add -A && git commit -m x" deny "leak.json" "$U"
  _t "W6b ... a superset add ran" "adds=$(_sim_adds)" _superset_add
  _t "W5 ctr_wants_lex: a command over 16384 characters is always lexed (perl-less hosts)" "returned false" \
    bash -c 'source "$1" && ctr_wants_lex "git commit -m $2"' _ "$lib" "$long"
  _t "W5b ... and a short plain commit is still not" "returned true" \
    bash -c 'source "$1" && ! ctr_wants_lex "git commit -m x"' _ "$lib"
}

# ---- the library's clock and bound, driven directly --------------------------------------------------------
_t_sim_lib_unit() {
  local lib="$REPO_ROOT/.claude/hooks/lib/commit-index-sim.sh" walk="$REPO_ROOT/.claude/hooks/lib/commit-target-roots.sh" v out rc t0
  for v in 999 abc 08 5 0 -5; do
    out=$(env CIS_DEADLINE_SECONDS="$v" bash -c 'source "$1" || exit 9; source "$2" || exit 9; cis_clock_start; cis_remaining; echo "$CIS_REMAINING"' _ "$walk" "$lib" 2>&1) || out="ERR"
    case "$v" in
      999|abc|-5) _t "U1 CIS_DEADLINE_SECONDS=$v cannot raise the ceiling: at most 30 s, at least 28" "got $out" test "$out" -le 30 -a "$out" -ge 28 ;;
      08) _t "U1 CIS_DEADLINE_SECONDS=08 is read as decimal 8 (not a bad octal): between 6 and 8" "got $out" test "$out" -le 8 -a "$out" -ge 6 ;;
      5) _t "U1 CIS_DEADLINE_SECONDS=5 lowers it: between 3 and 5" "got $out" test "$out" -le 5 -a "$out" -ge 3 ;;
      0) _t "U1 CIS_DEADLINE_SECONDS=0 leaves no time (deny, never more)" "got $out" test "$out" -le 0 ;;
    esac
  done
  out=$(bash -c 'source "$1" || exit 9; source "$2" || exit 9; cis_remaining; echo "$CIS_REMAINING"; cis_bound_argv; echo "rc=$?"' _ "$walk" "$lib" 2>&1) || out="ERR"
  _t "U2 a consumer that never started the clock has no time left (fail closed), and cis_bound_argv says so" "got $out" _contains "$out" "rc=1"
  # the bound program: expiry kills the WHOLE group (rc 124), a child's own status passes through, a signal death is 128+n
  t0=$SECONDS
  out=$(bash -c 'source "$1" || exit 9; source "$2" || exit 9; perl -e "$CIS_BOUND_PL" 1 sh -c "sleep 62 >/dev/null 2>&1 & wait"; echo "rc=$?"' _ "$walk" "$lib" 2>&1) || out="ERR"
  _t "U3 the bound program ends a command that outlives it: rc 124, within a few seconds" "got $out after $((SECONDS - t0)) s" _contains "$out" "rc=124"
  _t "U3b ... and its grandchild (the sleep) is gone too" "left: $(ps -eo args= | awk '$1 == "sleep" && $2 == "62"' | head -c 100)" _no_sleep62
  out=$(bash -c 'source "$1" || exit 9; source "$2" || exit 9; perl -e "$CIS_BOUND_PL" 5 sh -c "exit 7"; echo "rc=$?"' _ "$walk" "$lib" 2>&1) || out="ERR"
  _t "U3c the child's own exit status passes through" "got $out" _contains "$out" "rc=7"
  out=$(bash -c 'source "$1" || exit 9; source "$2" || exit 9; perl -e "$CIS_BOUND_PL" 5 sh -c "kill -9 \$\$"; echo "rc=$?"' _ "$walk" "$lib" 2>&1) || out="ERR"
  _t "U3d a child killed by a signal reports 128+n" "got $out" _contains "$out" "rc=137"
  rc=0; out=$(bash -c 'source "$1" || exit 9; source "$2" || exit 9; perl -e "$CIS_BOUND_PL" 5 /no/such/program-xyz; echo "rc=$?"' _ "$walk" "$lib" 2>&1) || rc=$?
  _t "U3e a command that cannot be executed is a non-zero status, never a silent 0" "got $out" _contains "$out" "rc=127"
}
_no_sleep62() { [[ -z "$(ps -eo args= | awk '$1 == "sleep" && $2 == "62"')" ]]; }

# ---- consumer stub: proves property 5 (the brand-hex gate, #10793, reuses construction) ----------
_t_sim_consumer() {
  local lib="$REPO_ROOT/.claude/hooks/lib/commit-index-sim.sh" ctr="$REPO_ROOT/.claude/hooks/lib/commit-target-roots.sh" U wd out out2
  _sim_init
  U=$(_mk_leaky_repo untracked); wd=$(mktemp -d "$SUITE_TMP/cis.XXXXXX")
  out=$(env -u GIT_DIR -u GIT_INDEX_FILE bash -c '
    set -u
    source "$1" || exit 90
    source "$2" || exit 91
    ctr_collect "git add -A && git commit -m x"
    cis_plan "$3"
    cis_clock_start
    rc=0; cis_build "$3" "$3" "$4" || rc=$?
    echo "build-rc=$rc"
    env "${CIS_ENV[@]}" git -C "$3" diff --cached --name-only
  ' _ "$ctr" "$lib" "$U" "$wd" 2>&1) || true
  _t "X5 consumer stub: sourcing the library and cis_build exist and build the would-be index (rc 0)" "out=${out:0:300}" _contains "$out" "build-rc=0"
  _t "X5b ... 'env \"\${CIS_ENV[@]}\" git diff --cached' lists the untracked leak.json the superset staged" "out=${out:0:300}" _contains "$out" "leak.json"
  _t "X5c ... and clean.txt" "out=${out:0:300}" _contains "$out" "clean.txt"
  # A consumer that forgot the clock has no time left: it must FAIL (rc 20, cause sim-timeout), never run unbounded.
  wd=$(mktemp -d "$SUITE_TMP/cis.XXXXXX")
  out2=$(env -u GIT_DIR -u GIT_INDEX_FILE bash -c '
    source "$1" || exit 90
    source "$2" || exit 91
    ctr_collect "git add -A && git commit -m x"
    cis_plan "$3"
    rc=0; cis_build "$3" "$3" "$4" || rc=$?
    echo "build-rc=$rc why=$CIS_WHY"
  ' _ "$ctr" "$lib" "$U" "$wd" 2>&1) || true
  _t "X5e a consumer that never started the clock fails closed (rc 20, sim-timeout), not unbounded" "out=${out2:0:200}" _contains "$out2" "build-rc=20 why=sim-timeout"
  # A consumer that never planned must fail closed too: it cannot assume the replay is valid for this root.
  wd=$(mktemp -d "$SUITE_TMP/cis.XXXXXX")
  out2=$(env -u GIT_DIR -u GIT_INDEX_FILE bash -c '
    source "$1" || exit 90
    source "$2" || exit 91
    ctr_collect "git add -A && git commit -m x"
    cis_clock_start
    rc=0; cis_build "$3" "$3" "$4" || rc=$?
    echo "build-rc=$rc why=$CIS_WHY"
  ' _ "$ctr" "$lib" "$U" "$wd" 2>&1) || true
  _t "X5f a consumer that never called cis_plan fails closed (rc 20, not-planned)" "out=${out2:0:200}" _contains "$out2" "build-rc=20 why=not-planned"
  # The plan is made once: a root other than the one the proven directory belongs to is never replayed in that directory.
  wd=$(mktemp -d "$SUITE_TMP/cis.XXXXXX")
  out2=$(env -u GIT_DIR -u GIT_INDEX_FILE bash -c '
    source "$1" || exit 90
    source "$2" || exit 91
    ctr_collect "git add clean.txt && git commit -m x"
    cis_plan "$3"
    echo "plan=$CIS_MODE top=$CIS_TOP"
    cis_clock_start
    rc=0; cis_build "$5" "$3" "$4" || rc=$?
    echo "build-rc=$rc mode=$CIS_MODE why=$CIS_WHY"
  ' _ "$ctr" "$lib" "$U" "$wd" "$(_mk_leaky_repo clean)" 2>&1) || true
  _t "X5g a plan that is exact for one toplevel is not trusted for another root (superset, dir-not-root)" "out=${out2:0:300}" \
    test "$([[ "$out2" == *"plan=exact top=$U"* && "$out2" == *"mode=superset why=dir-not-root"* ]] && echo y)" = y
  _t "X5d ... while the REAL index still holds nothing new (no secret-scan code ran here)" "build/real: ${out:0:120} / $(git -C "$U" diff --cached --name-only)" \
    test -z "$(git -C "$U" diff --cached --name-only)" -a "$([[ "$out" == *build-rc=0* ]] && echo y)" = y
}

# ---- the differential oracle: the sim stages a SUPERSET of what the command stages --------------
# For each row, real git applies the command's literal staging words to a CLONE of the fixture; every
# (mode, blob, stage, path) entry of that real index must appear in the sim index the recording stub
# was handed. No real gitleaks. A row the unmodified hook cannot satisfy is RED because the index it
# scans is the real one, which lacks the working-tree content.
_oracle_stage() {  # <clone> <shell command>: real git applies what the command's staging does
  ( cd "$1" && bash -c "$2" ) >/dev/null 2>&1 || true
}
_t_sim_oracle() {
  _sim_init
  [[ -n "$SIM_PD" ]] || SIM_PD=$(_mk_sim_path)
  local U T I row mode rest hookcmd stage fx clone n=0 merged missing
  U=$(_mk_leaky_repo untracked); T=$(_mk_leaky_repo tracked-modified); I=$(_mk_leaky_repo ignored)
  # mode | the command the hook sees | what real git does for that command's staging
  local rows=(
    'untracked|git add -A && git commit -m x|git add -A'
    'untracked|git add . && git commit -m x|git add .'
    'untracked|git add clean.txt && git commit -m x|git add clean.txt'
    "untracked|git add 'my file.md' clean.txt && git commit -m x|git add 'my file.md' clean.txt"
    'untracked|git add leak.json clean.txt && git commit -m x|git add leak.json clean.txt'
    'untracked|git add --all && git commit -m x|git add --all'
    'tracked-modified|git commit -am x|git add -u'
    'tracked-modified|git commit -m x -- tracked.json|git add -u -- tracked.json'
    'tracked-modified|git commit -o other.json -m x|git add -u -- other.json'
    'tracked-modified|git add -A && git commit -m x|git add -A'
    'tracked-modified|git add tracked.json && git commit -m x|git add tracked.json'
    'tracked-modified|git add clean.txt && git commit -am x|git add clean.txt; git add -u'
    'tracked-modified|git add -n -A && git commit -am x|git add -u'
    'tracked-modified|git add -A -- docs && git commit -am x|git add -A -- docs; git add -u'
    'ignored|git add -f ignored.pem && git commit -m x|git add -f ignored.pem'
    'ignored|git add -A && git commit -m x|git add -A'
  )
  for row in "${rows[@]}"; do
    n=$((n + 1)); mode="${row%%|*}"; rest="${row#*|}"; hookcmd="${rest%|*}"; stage="${rest##*|}"
    case "$mode" in untracked) fx="$U" ;; tracked-modified) fx="$T" ;; ignored) fx="$I" ;; esac
    clone="$SUITE_TMP/oracle.$n"; cp -a "$fx" "$clone"
    git -C "$fx" ls-files -s > "$clone.before"
    _oracle_stage "$clone" "$stage"
    git -C "$clone" ls-files -s > "$clone.exp"
    _sim_run "$fx" "$hookcmd"
    merged="$SUITE_TMP/oracle.$n.sim"; _rec_ls > "$merged"
    missing=$(grep -v -x -F -f "$merged" "$clone.exp" || true)
    # A row that stages nothing proves nothing: the real staging must have CHANGED the clone's index.
    if cmp -s "$clone.before" "$clone.exp"; then
      _report "oracle[$mode]: precondition: '$stage' changes the clone's index (for: $hookcmd)" fail "the real staging added nothing: the row is vacuous"
    elif [[ -z "$missing" && -s "$merged" && "$(_sim_add_n)" -ge 1 ]]; then _report "oracle[$mode]: sim index ⊇ the index of '$stage' for: $hookcmd" ok
    else _report "oracle[$mode]: sim index ⊇ the index of '$stage' for: $hookcmd" fail "sim adds=$(_sim_add_n); sim index lacks: ${missing//$'\n'/ ; }"; fi
  done
}

# ---- scan_root's batched check-attr pass keeps the per-path loop's verdict ----------------------
# Paths with spaces, a quote and a newline; attribute unset (-diff: re-scanned), set, valued and
# unspecified (not re-scanned). The recording stub logs what the `detect --no-git` re-scan was given.
_t_sim_checkattr() {
  _sim_init
  [[ -n "$SIM_PD" ]] || SIM_PD=$(_mk_sim_path)
  local R f bad="" want got exp
  local names=('unset.txt' 'sp ace.txt' 'qu"ote.txt' $'nl\nname.txt' 'set.txt' 'valued.txt' 'unspec.txt')
  R=$(mktemp -d "$SUITE_TMP/attr.XXXXXX"); assert_fixture_dir "$R"
  (
    cd "$R" || exit 1
    git init -q -b main; git config user.email t@t; git config user.name t
    cp "$GITLEAKS_TOML" .gitleaks.toml
    for f in "${names[@]}"; do printf 'content of %s\n' "x" > "$R/$f"; done
    mkdir -p .git/info
    printf '%s\n' 'unset.txt -diff' '"sp ace.txt" -diff' '"qu\"ote.txt" -diff' 'nl?name.txt -diff' 'set.txt diff' 'valued.txt diff=foo' > .git/info/attributes
    git add -A
  )
  for f in 'unset.txt' 'sp ace.txt' 'qu"ote.txt' $'nl\nname.txt'; do
    want=$(git -C "$R" check-attr diff -- "$f" 2>/dev/null) || want=""
    [[ "$want" == *": diff: unset" ]] || bad+=" [$f: $want]"
  done
  [[ "$(git -C "$R" check-attr diff -- set.txt)" == *": diff: set" ]] || bad+=" [set.txt]"
  [[ "$(git -C "$R" check-attr diff -- valued.txt)" == *": diff: foo" ]] || bad+=" [valued.txt]"
  [[ "$(git -C "$R" check-attr diff -- unspec.txt)" == *": diff: unspecified" ]] || bad+=" [unspec.txt]"
  if [[ -n "$bad" ]]; then _report "X6 check-attr fixture control" fail "FIXTURE BROKEN: attribute states are not what the arm assumes:$bad"; return 0; fi
  _sx "X6 plain staged commit with -diff paths (spaces, quote, newline) -> allow" "$R" "git commit -m x" allow
  got=$(cat "$SIM_REC"/nodiff.* 2>/dev/null || true)
  exp=$(printf '%s\0' './nl'$'\n''name.txt' './qu"ote.txt' './sp ace.txt' './unset.txt' | sort -z | tr '\0' '|')
  _t "X6b exactly the four -diff (unset) paths were re-scanned from their staged blobs; set / valued / unspecified were not" \
    "got='${got//$'\n'/\\n}' want='${exp//$'\n'/\\n}'" test "$got" = "$exp"
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
  local body rc min
  body=$(awk '/^# >>> assertion-floor$/{f=1;next} /^# <<< assertion-floor$/{f=0} f' "${BASH_SOURCE[0]}")
  if [[ -z "${body//[[:space:]]/}" ]]; then
    _report "floor contract" fail "floor markers matched nothing — the extraction is broken, not the floor"; return
  fi
  # row 1: below the floor and nothing skipped -> the REAL block must exit 1
  rc=0; ( set +e; eval 'pass=1; fail=0; SKIPPED_ARMS=()'"
$body" ) >/dev/null 2>&1 || rc=$?
  if [[ "$rc" != 1 ]]; then _report "floor contract: below the floor exits 1" fail "rc=$rc (MIN in the file: $(grep -m1 '^MIN_ASSERTIONS=' "${BASH_SOURCE[0]}"))"; return; fi
  # row 2: at the floor -> must NOT exit 1
  # (the boundary itself: exactly the MIN in the file, read from it, so raising the floor never breaks this row)
  min=$(sed -n 's/^MIN_ASSERTIONS=\([0-9][0-9]*\)$/\1/p' "${BASH_SOURCE[0]}" | head -n 1)
  case "$min" in ''|*[!0-9]*) _report "floor contract: at or above the floor passes" fail "could not read MIN_ASSERTIONS from the file"; return ;; esac
  rc=0; ( set +e; eval "pass=$min; fail=0; SKIPPED_ARMS=()""
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

# #10696 (the would-be index). After _t_lexer_contract and before _t_ci_contract, outside the T20
# priming (these arms advance _JOURNAL_MARK through _run_cmd as well).
_t_sim_selftest
_t_sim_fixtures
_t_sim_prefilter
_t_sim_dump
_t_sim_core
_t_sim_canary
_t_sim_invariants
_t_sim_term
_t_sim_dirproof
_t_sim_failures
_t_sim_pins
_t_sim_worktree
_t_sim_extra
_t_sim_fidelity
_t_sim_repair
_t_sim_seams
_t_sim_walkc
_t_sim_lib_unit
_t_sim_consumer
_t_sim_oracle
_t_sim_checkattr

_t_ci_contract
_t_floor_contract

# >>> assertion-floor
# Assertion-count FLOOR (not equality: every added row would otherwise need a bump). A helper
# that goes silent still counts nothing, so deleting the calls — or neutering the helpers —
# drops the total below this and the suite cannot exit 0 having asserted nothing. Skip-aware:
# a host with no runnable gitleaks skips whole arms (reported, and failed under CI=true by the
# epilogue), so the floor only binds when nothing was skipped. Reported by printf + exit,
# never through the helpers it backstops. Raise it in the same edit that adds rows.
MIN_ASSERTIONS=1128
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
