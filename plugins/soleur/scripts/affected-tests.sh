#!/usr/bin/env bash
# affected-tests.sh — the plugin-generic, stack-detecting affected-only test
# gate (#9307 deliverable 2). One entry point for soleur:work Phase 2,
# soleur:ship Phase 4, soleur:review's lead gate and grok-pre-push-gate.sh, in
# ANY repository — including ones with no scripts/test-all.sh.
#
# Usage:
#   bash affected-tests.sh [--full] [--base <ref>] [--explain] [--self-check]
#
# Dispatch precedence (exactly this order):
#   1. `test_command` in repo-root `.soleur-test-gate.json` — run via `bash -c`
#      from the repo root; bypasses selection entirely.
#   2. A repo runner ADVERTISING the Soleur capability — `scripts/test-all.sh`
#      whose `--print-selection` flag is registered at a case-label or
#      usage-table position (a comment-only mention does NOT count). The probe
#      runs BEFORE any gate-side classification: a capability-positive runner
#      owns the diff decision (its own inert/global/empty handling is strictly
#      better informed), so a resolved runner is ALWAYS delegated to —
#      `--affected`, or `--full` only under this script's `--full`. A foreign
#      script of that name is NEVER invoked with Soleur flags — it falls
#      through to 3.
#   3. Stack adapters, in order: nx/turbo, JS/TS (vitest `related` SUBCOMMAND /
#      jest --findRelatedTests), Python (pytest + testmon/xdist), Go (`go list`
#      reverse-dependency closure). The gate's own base resolution, changed-set
#      census and global/inert classification apply ONLY to this arm — under
#      delegation the runner resolves its own base and classification, and
#      `--base` steers the adapters alone.
#
# Exit contract — produced ONLY by finish() in lib/affected-tests/common.sh,
# the single exit site for the whole gate:
#   0  every selected test passed, OR NO_TESTS_AFFECTED for an all-inert diff
#   1  a selected test failed, the delegated runner was signal-killed (rc 3
#      maps to 1 reason=runner-signal), or the content-trigger command failed
#      (reason=content-trigger-failed); a failure seen before budget expiry
#      wins over deferral
#   4  AFFECTED_GATE_REFUSED — no-stack, bad-config key=<k>,
#      vacuous-test-command, no-base-ref, not-a-repo (--self-check outside a
#      repository), toolchain-missing, runner-refused,
#      foreign-runner (a foreign scripts/test-all.sh AND no adapter resolves)
#   6  AFFECTED_GATE_BUDGET_DEFERRED — budget expired AND a CI test workflow was
#      detected; CI stays the authoritative gate
#   7  no test suite detected at all — disclosed note, never labelled passed
#
# Output contract:
#   human:  `Ran X of the repo's N test files affected by this change:
#           passed.` (N is the repo-wide census, not the affected subset) —
#           never the words "tests verified"; beside it the literal verdict
#           `affected-suite gate passed.`
#   inert:  `NO_TESTS_AFFECTED inert_rule=<pat>` + `No tests ran: docs-only change.`
#   marker: `AFFECTED_GATE ran=<X> of=<N> skipped=<Y>
#           mode=<selected|full|custom|explain|none|help> reason=<…> stack=<…>
#           ci=<file|none>` on every verdict path including refusals; counts
#           are `-` on paths that produce no honest count (delegated runner,
#           opaque test_command, refusals) — a delegated or custom rc 0 still
#           prints `affected-suite gate passed.`
#
# `.soleur-test-gate.json` (repo root, committed, every key optional; unknown
# key / malformed JSON / wrong type → rc 4 reason=bad-config key=<k>):
#   test_command   string   full-run command; true/`:`/`exit 0`/bare `echo`,
#                           or any command whose LAST ;/&&/||/| segment is a
#                           vacuous primitive (`cmd || true`, `cmd ; exit 0`,
#                           `bash -c 'exit 0'`) → rc 4 reason=vacuous-test-command
#                           (a documented denylist, not a proof)
#   global_paths   string[] REPLACES built-ins; any hit forces the full command
#   inert_paths    string[] REPLACES built-ins (`**/*.md` default); an all-inert
#                           diff → rc 0 NO_TESTS_AFFECTED; a mixed diff is never
#                           inert. A match-everything pattern (`*`, `**`,
#                           `**/*`, anything matching an arbitrary path) is a
#                           permanent green → rc 4 bad-config key=inert_paths
#   budget_seconds number   wall-clock cap, enforced ONLY when a CI test
#                           workflow is detected; default 900 (unmeasured);
#                           must be a positive integer
#   max_workers    number   overrides the width formula; positive integer
#   budget_ci      boolean  forces CI-deferral eligibility without a workflow
#   content_trigger_pattern / content_trigger_paths / content_trigger_command
#                  string / string[] / string   ALL THREE or none (a partial or
#                           empty group → rc 4 bad-config naming the key, as do a
#                           match-everything glob, a glob that can never match
#                           (`./x/*`, `/x/*`, `x/`) and a vacuous command). When a
#                           diff ADDS a line (tracked) or holds a line (untracked)
#                           containing the fixed string in a file under the globs,
#                           a passing run — selected, inert, or a gate-side
#                           escalation to full — ALSO runs the command (via
#                           `bash -c`, same trust as test_command). An operator's
#                           own --full, test_command and --explain never run it.
#                           A scan that cannot decide runs it; a failing primary
#                           skips it. The marker gains a trailing
#                           `content_trigger=<clear|ran|failed|deferred|skipped|
#                           scan-error>`; --explain prints `CONTENT_TRIGGER
#                           armed=1 state=…`. Lib: content-trigger.sh
#
# Base-ref order (adapter arm only — a delegated runner resolves its own):
# --base > @{upstream} > origin/HEAD > origin/main >
# origin/master > merge-base over every remote-tracking ref (newest wins).
# Changed set = committed-vs-base ∪ staged ∪ unstaged ∪ untracked. A shallow
# clone gets ONE bounded deepen, then rc 4 reason=no-base-ref — never a silent
# full, never a silent empty.
#
# CI detection: `.github/workflows/*.yml|*.yaml` carrying a pull_request/push
# trigger AND a test-command shape, or `budget_ci: true`. No CI → the budget is
# ignored, run to completion, an upfront line says so.
#
# Worker width (unmeasured heuristic): max(1, ncpu/2) / (1 + other running
# affected-tests.sh processes) — counted on the argv SLOT, never pgrep -f or
# ps|grep; max_workers overrides. Maps to vitest/jest --maxWorkers, pytest -n,
# go test -p, nx --parallel, turbo --concurrency.
#
# Portability contract (asserted by affected-tests.test.sh): no bare `timeout`
# (timeout→gtimeout→bounded-watchdog in lib common.sh), no `nproc` outside the
# ncpu fallback chain, no `sed -i`, `date -d`, `readlink -f`, `stat -c`. Bash
# 3.2-safe: no `declare -A`, no `mapfile`, `${arr[@]+"${arr[@]}"}` under set -u.
#
# External binaries invoked across this script and its lib:
#   core:     bash git grep find sort tr cut head tail awk sed cat date sleep
#             kill ps getconf sysctl nproc mktemp rm wc
#   config:   python3 node jq (first resolvable, schema is validated in bash)
#   runners:  scripts/test-all.sh (capability-probed), vitest jest npx npm pnpm
#             yarn bun pytest go nx turbo
#   bounds:   timeout gtimeout (either may be absent — watchdog covers)
#
# Cloud (Devin): the gate resolves its libs by BASH_SOURCE and needs no plugin
# root — CLAUDE_PLUGIN_ROOT may be unset. A detected stack with no runnable
# toolchain → rc 4 reason=toolchain-missing.

set -euo pipefail

GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=plugins/soleur/scripts/lib/affected-tests/common.sh
source "$GATE_DIR/lib/affected-tests/common.sh"
# shellcheck source=plugins/soleur/scripts/lib/affected-tests/nx-turbo.sh
source "$GATE_DIR/lib/affected-tests/nx-turbo.sh"
# shellcheck source=plugins/soleur/scripts/lib/affected-tests/js.sh
source "$GATE_DIR/lib/affected-tests/js.sh"
# shellcheck source=plugins/soleur/scripts/lib/affected-tests/python.sh
source "$GATE_DIR/lib/affected-tests/python.sh"
# shellcheck source=plugins/soleur/scripts/lib/affected-tests/go.sh
source "$GATE_DIR/lib/affected-tests/go.sh"
# shellcheck source=plugins/soleur/scripts/lib/affected-tests/content-trigger.sh
source "$GATE_DIR/lib/affected-tests/content-trigger.sh"

# Scratch files (config dump, changed-set census, adapter logs) are registered
# in AFFECTED_SCRATCH by affected_mktemp — remove them on every exit shape,
# including the early refusal paths that never reach an adapter's own rm.
# EXIT alone leaves signal semantics intact — trapping INT/TERM on the same
# handler would swallow the signal and resume at the interrupted statement.
trap 'affected_scratch_clean' EXIT
trap 'affected_scratch_clean; exit 130' INT
trap 'affected_scratch_clean; exit 143' TERM

usage() {
  sed -n '1,20p' "$0" | grep -E '^#' | sed 's/^# \{0,1\}//'
  cat <<'EOF'
Usage:
  bash affected-tests.sh [--full] [--base <ref>] [--explain] [--self-check]

  --full        bypass selection; run the detected full command
  --base <ref>  override base-ref resolution for the changed set
  --explain     print the selection and per-path reasons; run nothing
  --self-check  validate config + toolchain probe only; never runs tests
EOF
}

# --- args ---------------------------------------------------------------------
ARG_FULL=0
ARG_BASE=""
ARG_EXPLAIN=0
ARG_SELFCHECK=0
while (( $# > 0 )); do
  case "$1" in
    --full) ARG_FULL=1 ;;
    --base) shift
            (( $# > 0 )) || { echo "affected-tests: --base needs a ref" >&2
                             finish 4 none bad-usage - none - - -; }
            ARG_BASE="$1" ;;
    --explain) ARG_EXPLAIN=1 ;;
    --self-check) ARG_SELFCHECK=1 ;;
    -h|--help) usage; finish 0 help help - none - - - ;;
    *) echo "affected-tests: unknown argument '$1' (try --help)" >&2
       finish 4 none bad-usage - none - - - ;;
  esac
  shift
done

# The operator's own --full, captured before any arm can escalate ARG_FULL: the
# content trigger skips only an explicit --full, never a gate-side escalation.
ARG_FULL_REQUESTED=$ARG_FULL

# --- repository root ------------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  # Outside a repository the cause is not a missing base ref — name it.
  (( ARG_SELFCHECK )) && finish 4 none not-a-repo - none - - -
  finish 4 none no-base-ref - none - - -
fi
cd "$REPO_ROOT" || finish 4 none no-base-ref - none - - -

# --- CI detection (needed early: it arms the budget and fills ci=) ----------------
CI_NAME=none
affected_detect_ci() {
  local f
  for f in .github/workflows/*.yml .github/workflows/*.yaml; do
    [[ -f "$f" ]] || continue
    # pull_request or push trigger AND a test-command shape in the same file —
    # a workflow that merely exists is not a gate to defer to. `#` comments are
    # stripped BEFORE matching: a deploy workflow that only TALKS about tests
    # in a comment is not a test gate to defer to.
    #
    # The trigger must be a yaml DECLARATION, not a substring — a bare
    # `pull_request|push` grep reads `run: git push` or `pushd deploy/` inside a
    # step as a CI test gate. Accepted shapes, tracked inside the `on:` block:
    #   on: push            on: [push, pull_request]      on: {push: …}
    #   on:\n  push:        on:\n  pull_request:          on:\n  - push
    sed 's/#.*//' "$f" | awk '
      # `on:` is a TOP-LEVEL yaml key — column 0 only. An indented `on:` inside a
      # `run: |` block scalar is script text, not a trigger declaration.
      /^on[[:space:]]*:/ {
        rest = $0
        sub(/^on[[:space:]]*:[[:space:]]*/, "", rest)
        # Scalar / flow sequence / flow map on the on: line itself.
        if (rest ~ /(^|[][{},[:space:]])(pull_request|push)([]},:[:space:]]|$)/) found = 1
        inon = 1
        next
      }
      # The block ends at the next top-level (column-0) key; blank lines do not.
      inon && /^[^[:space:]]/ { inon = 0 }
      # Block-map key (`push:`/`pull_request:`) or sequence entry (`- push`).
      inon && /^[[:space:]]*-?[[:space:]]*(pull_request|push)[[:space:]]*:/ { found = 1 }
      inon && /^[[:space:]]*-[[:space:]]*(pull_request|push)[[:space:]]*$/   { found = 1 }
      END { exit(!found) }
    ' || continue
    if grep -qE 'test-all\.sh|npm[[:space:]]+(run[[:space:]]+)?test|yarn[[:space:]]+test|pnpm[[:space:]]+(run[[:space:]]+)?test|bun[[:space:]]+test|vitest|jest|pytest|go[[:space:]]+test|cargo[[:space:]]+test|ctest|make[[:space:]]+test|deno[[:space:]]+test' < <(sed 's/#.*//' "$f"); then
      CI_NAME="$(affected_marker_field "$f")"
      return 0
    fi
  done
  return 1
}

# --- glob matcher ---------------------------------------------------------------------
# A pattern containing `/` matches the whole path; `**/` also matches zero
# directories (its `**/` prefix is stripped for the second try). A bare
# pattern matches the basename. Defined before the config block: the
# match-everything probes and the content trigger both call it.
affected_glob_match() {
  local p="$1" pat="$2" alt
  if [[ "$pat" == */* ]]; then
    [[ "$p" == $pat ]] && return 0
    alt="${pat//\*\//}"
    [[ "$alt" != "$pat" && "$p" == $alt ]] && return 0
    return 1
  fi
  [[ "${p##*/}" == $pat ]]
}

# --- config: .soleur-test-gate.json ------------------------------------------------
CFG_TEST_COMMAND=""
CFG_BUDGET_SECONDS=900     # default, unmeasured
CFG_MAX_WORKERS=""
CFG_BUDGET_CI=false
CFG_GLOBAL_SET=0
CFG_INERT_SET=0
CFG_GLOBAL_PATHS=()
CFG_INERT_PATHS=()
# Content trigger (lib content-trigger.sh): three flat keys, all or none. Values
# land directly in AFFECTED_CT_PATTERN/_PATHS/_COMMAND; this flag records that any
# of the three appeared, so a partial group is refused rather than silently ignored.
CFG_CT_SET=0

# Dump the JSON object as NUL-separated KEY\0TYPE\0VALUE\0 triples on stdout —
# array elements arrive as one `elem:<type>` record each, an empty array as a
# bare `array` record so present-but-empty stays distinct from absent. The
# SCHEMA is validated by the caller; these emitters only decode. rc 3 = the
# file is not a JSON object (malformed).
_affected_json_dump() {
  local f="$1"
  if command -v python3 >/dev/null 2>&1; then
    # -I: isolated mode keeps the repo's cwd OFF sys.path — a repo-controlled
    # pytest.py/sitecustomize.py must never execute during a config read.
    python3 -I - "$f" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(3)
if not isinstance(d, dict):
    sys.exit(3)
def jt(v):
    if isinstance(v, bool): return 'boolean'
    if isinstance(v, (int, float)): return 'number'
    if isinstance(v, str): return 'string'
    if isinstance(v, list): return 'array'
    if v is None: return 'null'
    return 'object'
out = sys.stdout
for k, v in d.items():
    if isinstance(v, list):
        if not v:
            out.write(k + '\0array\0\0')
        for e in v:
            out.write(k + '\0elem:' + jt(e) + '\0' + (e if isinstance(e, str) else json.dumps(e)) + '\0')
    else:
        out.write(k + '\0' + jt(v) + '\0' + (v if isinstance(v, str) else json.dumps(v)) + '\0')
PYEOF
    return $?
  fi
  if command -v node >/dev/null 2>&1; then
    node - "$f" <<'JSEOF'
const fs = require('fs');
let d;
try { d = JSON.parse(fs.readFileSync(process.argv[2], 'utf8')); } catch (e) { process.exit(3); }
if (typeof d !== 'object' || d === null || Array.isArray(d)) process.exit(3);
const jt = v => v === null ? 'null' : Array.isArray(v) ? 'array' : typeof v;
for (const [k, v] of Object.entries(d)) {
  if (Array.isArray(v)) {
    if (!v.length) process.stdout.write(k + '\0array\0\0');
    for (const e of v) process.stdout.write(k + '\0elem:' + jt(e) + '\0' + (typeof e === 'string' ? e : JSON.stringify(e)) + '\0');
  } else {
    process.stdout.write(k + '\0' + jt(v) + '\0' + (typeof v === 'string' ? v : JSON.stringify(v)) + '\0');
  }
}
JSEOF
    return $?
  fi
  if command -v jq >/dev/null 2>&1; then
    # Same contract as the py/node emitters: a non-object top level is not a
    # config — `[]` decodes to ZERO records here (silent accept) while py/node
    # exit 3. Refuse it identically before the dump.
    jq -e 'type == "object"' "$f" >/dev/null 2>&1 || return 3
    jq -j '
      to_entries[] | .key as $k | (.value | type) as $t |
      if $t == "array" then
        if (.value | length) == 0 then ($k, "\u0000", "array", "\u0000", "\u0000")
        else (.value[] | ($k, "\u0000", ("elem:" + (. | type)), "\u0000",
             (if (. | type) == "string" then . else tojson end), "\u0000"))
        end
      else ($k, "\u0000", $t, "\u0000",
            (if $t == "string" then .value else (.value | tojson) end), "\u0000")
      end' "$f" 2>/dev/null
    return $?
  fi
  # No JSON engine: a present config we cannot parse is a toolchain fact, and
  # the fail direction is CLOSED.
  return 2
}

# Refusal of a content-trigger key: names the offending key (a missing key and an empty one
# are the same refusal).
_affected_ct_bad() { finish 4 none "bad-config key=$1" config "$CI_NAME" - - -; }

# Load and validate. Fail-closed everywhere: malformed, unknown key, or wrong
# type → rc 4 reason=bad-config key=<k>; a vacuous test_command →
# reason=vacuous-test-command.
affected_load_config() {
  local cfg=".soleur-test-gate.json"
  [[ -f "$cfg" ]] || return 0
  local tmp rc=0
  affected_mktemp cfg || finish 4 none mktemp-failed - "$CI_NAME" - - -; tmp="$AFFECTED_TMP"
  _affected_json_dump "$cfg" >"$tmp" || rc=$?
  if (( rc == 2 )); then
    finish 4 none "toolchain-missing" config "$CI_NAME" - - -
  fi
  if (( rc != 0 )); then
    finish 4 none "bad-config key=$(affected_marker_field "$cfg")" config "$CI_NAME" - - -
  fi

  local k t v badkey=""
  while IFS= read -r -d '' k && IFS= read -r -d '' t && IFS= read -r -d '' v; do
    case "$k" in
      test_command)
        [[ "$t" == string ]] || { badkey="$k"; break; }
        CFG_TEST_COMMAND="$v" ;;
      global_paths|inert_paths)
        if [[ "$t" == array ]]; then
          [[ "$k" == global_paths ]] && CFG_GLOBAL_SET=1 || CFG_INERT_SET=1
        elif [[ "$t" == elem:string ]]; then
          [[ "$k" == global_paths ]] && { CFG_GLOBAL_SET=1; CFG_GLOBAL_PATHS+=("$v"); } \
                                   || { CFG_INERT_SET=1; CFG_INERT_PATHS+=("$v"); }
        else
          badkey="$k"; break
        fi ;;
      budget_seconds)
        [[ "$t" == number ]] || { badkey="$k"; break; }
        v="${v%%.*}"
        # Clamped: a zero/negative/decimal-floor-0 budget would defer instantly
        # or arm a nonsense deadline — that is a config error, fail closed.
        [[ "$v" =~ ^[0-9]+$ ]] && (( v >= 1 )) || { badkey="$k"; break; }
        CFG_BUDGET_SECONDS="$v" ;;
      max_workers)
        [[ "$t" == number ]] || { badkey="$k"; break; }
        v="${v%%.*}"
        [[ "$v" =~ ^[0-9]+$ ]] && (( v >= 1 )) || { badkey="$k"; break; }
        CFG_MAX_WORKERS="$v" ;;
      budget_ci)
        [[ "$t" == boolean ]] || { badkey="$k"; break; }
        CFG_BUDGET_CI="$v" ;;
      content_trigger_pattern)
        [[ "$t" == string ]] || { badkey="$k"; break; }
        CFG_CT_SET=1
        AFFECTED_CT_PATTERN="$v" ;;
      content_trigger_command)
        [[ "$t" == string ]] || { badkey="$k"; break; }
        CFG_CT_SET=1
        AFFECTED_CT_COMMAND="$v" ;;
      content_trigger_paths)
        if [[ "$t" == array ]]; then
          CFG_CT_SET=1
        elif [[ "$t" == elem:string ]]; then
          CFG_CT_SET=1
          AFFECTED_CT_PATHS+=("$v")
        else
          badkey="$k"; break
        fi ;;
      *) badkey="$k"; break ;;
    esac
  done <"$tmp"
  if [[ -n "$badkey" ]]; then
    finish 4 none "bad-config key=$(affected_marker_field "$badkey")" config "$CI_NAME" - - -
  fi

  # Content trigger: all three keys or none, each refused naming ITS key (a missing
  # key and an empty one are the same refusal). A half-declared trigger that silently
  # never fires is exactly the failure it exists to prevent.
  if (( CFG_CT_SET )); then
    if [[ -z "$AFFECTED_CT_PATTERN" || "$AFFECTED_CT_PATTERN" == *$'\n'* ]]; then
      _affected_ct_bad content_trigger_pattern
    fi
    ((${#AFFECTED_CT_PATHS[@]} > 0)) || _affected_ct_bad content_trigger_paths
    local _ct_g _ct_probe
    for _ct_g in "${AFFECTED_CT_PATHS[@]}"; do
      # Refused: empty, multi-line or whitespace-bearing globs; shapes that can never match
      # a repo-relative path in `[[ == ]]` (leading `./`, `/` or `!`, trailing `/`, `//`, a
      # `.`/`..` segment, `{a,b}` which is not expanded); and a match-everything glob (the
      # scan would be unbounded and the command near-permanent, as for inert_paths): any
      # glob that matches one of a handful of improbable probe paths.
      if [[ -z "$_ct_g" || "$_ct_g" == *$'\n'* || "$_ct_g" == *[[:space:]]* \
            || "$_ct_g" == ./* || "$_ct_g" == /* || "$_ct_g" == '!'* || "$_ct_g" == */ \
            || "$_ct_g" == *//* || "$_ct_g" == */./* || "$_ct_g" == *..* || "$_ct_g" == *[{}]* ]]; then
        _affected_ct_bad content_trigger_paths
      fi
      for _ct_probe in "zz9q8/probe.nonexistent" "a" ".hidden" "x/y.z" "Q9"; do
        if affected_glob_match "$_ct_probe" "$_ct_g"; then _affected_ct_bad content_trigger_paths; fi
      done
    done
    # A vacuous command (`true`, `cmd || true`) would certify nothing: same denylist
    # as test_command, but the refusal names THIS key.
    if [[ -z "$AFFECTED_CT_COMMAND" ]] || _affected_cmd_vacuous "$AFFECTED_CT_COMMAND"; then
      _affected_ct_bad content_trigger_command
    fi
    AFFECTED_CT_ARMED=1
  fi

  if [[ -n "$CFG_TEST_COMMAND" ]]; then
    # Vacuous escape hatches are refused — `true`, `:`, `exit 0`, a bare echo,
    # and every composition that ends in a swallower: `cmd || true`,
    # `cmd ; exit 0`, `cmd && true`, `cmd | true`, `bash -c 'exit 0'`,
    # `true # comment`. The check is a documented DENYLIST (common.sh
    # _affected_cmd_vacuous): comments are stripped, whitespace normalised, the
    # command split on ;/&&/||/| — a vacuous LAST segment decides the whole
    # command's rc, so it fails closed. What is not listed still runs verbatim.
    if _affected_cmd_vacuous "$CFG_TEST_COMMAND"; then
      finish 4 custom vacuous-test-command custom "$CI_NAME" - - -
    fi
  fi
}
affected_detect_ci || true   # a miss is the common case; never fatal
affected_load_config
if [[ "$CI_NAME" == none && "$CFG_BUDGET_CI" == true ]]; then
  CI_NAME="config:budget_ci"
fi

# --- self-check -------------------------------------------------------------------
if (( ARG_SELFCHECK )); then
  # Config load + toolchain probe only; never runs tests. Bounded, not instant:
  # every probe is `command -v` or a bounded --version, so the worst case is
  # the per-stack timeout sum (~80 s over 4 stacks), the happy path seconds.
  command -v git >/dev/null 2>&1 || finish 4 none toolchain-missing config "$CI_NAME" - - -
  # A capability-positive runner owns the run under delegation — adapter
  # toolchains are then unreachable, so a missing one is informational only.
  _sc_runner=0
  if [[ -f scripts/test-all.sh ]] \
     && grep -Eq '^[[:space:]]*(--[[:alnum:]_-]+\|)*--print-selection([])|,[:space:]])' scripts/test-all.sh; then
    _sc_runner=1
  fi
  # Probe each detected stack's toolchain: detection is free, and each tool()
  # --version probe is already bounded.
  _sc_trc=0; _sc_missing=0
  for _sc_stack in nxt js py go; do
    if "affected_${_sc_stack}_detect"; then
      _sc_trc=0
      "affected_${_sc_stack}_tool" || _sc_trc=$?
      case "$_sc_trc" in
        0) echo "AFFECTED_GATE_SELF_CHECK stack=${_sc_stack} toolchain=ok" ;;
        2) echo "AFFECTED_GATE_SELF_CHECK stack=${_sc_stack} toolchain=no-test-tool" ;;
        *) echo "AFFECTED_GATE_SELF_CHECK stack=${_sc_stack} toolchain=missing"
           _sc_missing=1 ;;
      esac
    fi
  done
  # A detected stack whose toolchain cannot run is not "ok" WHEN IT CAN GATE —
  # under delegation the adapters never run, so the gap is disclosed per-stack
  # above but does not refuse the check.
  if (( _sc_missing && _sc_runner == 0 )); then
    echo "AFFECTED_GATE_SELF_CHECK toolchain-missing"
    finish 4 none toolchain-missing - "$CI_NAME" - - -
  fi
  echo "AFFECTED_GATE_SELF_CHECK ok"
  finish 0 none ok - "$CI_NAME" - - -
fi

# --- the custom-command arm -------------------------------------------------------
# --explain under test_command answers BEFORE the arm can run it: the custom
# command IS the whole selection, so explain emits mode=custom + the command.
if (( ARG_EXPLAIN )) && [[ -n "$CFG_TEST_COMMAND" ]]; then
  echo "SELECTION mode=custom reason=custom-command"
  printf 'COMMAND %s\n' "$CFG_TEST_COMMAND"
  finish 0 explain custom-command custom "$CI_NAME" - - -
fi
if [[ -n "$CFG_TEST_COMMAND" ]]; then
  if [[ "$CI_NAME" != none ]]; then
    AFFECTED_BUDGET_ACTIVE=1
    AFFECTED_DEADLINE=$(( $(affected_now) + CFG_BUDGET_SECONDS ))
  else
    echo "affected-tests: no CI test workflow detected — wall-clock budget not enforced; running to completion."
  fi
  rc=0
  affected_bound bash -c "$CFG_TEST_COMMAND" || rc=$?
  case "$rc" in
    0)     finish 0 custom custom-command custom "$CI_NAME" - - - ;;
    124|137)
      (( rc == 137 )) && echo "affected-tests: the command exited 137 (SIGKILL — OOM or kill escalation), not necessarily budget expiry; deferral still applies." >&2
      if [[ "$CI_NAME" != none ]]; then
        finish 6 custom budget-deferred custom "$CI_NAME" - - -
      fi
      finish 1 custom failed custom "$CI_NAME" - - - ;;
    *)     finish 1 custom failed custom "$CI_NAME" - - - ;;
  esac
fi

# --- dispatch 2: the capability-positive repo runner -----------------------------------
# The probe reads the REGISTRATION, not the filename and never a comment: the
# flag must sit at a case-label or usage-table position — first token on the
# line (optionally inside a `a|b)` alternation) followed by a flag-table
# terminator.
#
# ORDERING IS THE CONTRACT: the probe runs BEFORE the gate's own base
# resolution, changed-set census and global/inert classification. A runner that
# registers --print-selection computes all of those itself, better informed —
# so a resolved runner is ALWAYS delegated to (--affected; --full only when the
# operator asked). Delegating an all-inert or global-paths diff is not waste:
# the runner's own classifier decides, and in this repo the always-on ratchets
# are live edges the gate's built-ins cannot see. Gate-side classification
# below is the adapter arm's alone.
RUNNER=""
if [[ -f scripts/test-all.sh ]] \
   && grep -Eq '^[[:space:]]*(--[[:alnum:]_-]+\|)*--print-selection([])|,[:space:]])' scripts/test-all.sh; then
  RUNNER="scripts/test-all.sh"
fi

if [[ -n "$RUNNER" ]]; then
  _flag=--affected
  (( ARG_FULL )) && _flag=--full
  _dmode=selected
  (( ARG_FULL )) && _dmode=full
  if (( ARG_EXPLAIN )); then
    # The runner owns the selection; invoking --print-selection here is left to
    # the operator (it can cost real time), so explain reports the delegation.
    echo "SELECTION mode=delegated runner=$RUNNER flag=$_flag"
    echo "runner owns selection — inspect with: bash $RUNNER --print-selection"
    (( ARG_FULL_REQUESTED )) || AFFECTED_CT_ELIGIBLE=1
    finish 0 explain delegated runner "$CI_NAME" - - -
  fi
  if [[ "$CI_NAME" != none ]]; then
    AFFECTED_BUDGET_ACTIVE=1
    AFFECTED_DEADLINE=$(( $(affected_now) + CFG_BUDGET_SECONDS ))
  else
    echo "affected-tests: no CI test workflow detected — wall-clock budget not enforced; running to completion."
  fi
  rc=0
  affected_bound bash "$RUNNER" "$_flag" || rc=$?
  # A delegated verdict is eligible for the content trigger unless the operator
  # passed --full; finish() runs it only when this run passed.
  (( ARG_FULL_REQUESTED )) || AFFECTED_CT_ELIGIBLE=1
  # Delegated-runner rc mapping: 4 (REFUSED — nothing ran) → 4
  # reason=runner-refused; 3 (UNRESOLVED — killed/declined suites) → 1
  # reason=runner-signal; 2 (usage) → 4 runner-refused; the rest pass through
  # as a plain verdict. rc 124/137 means OUR bound expired — deferral only
  # ever applies with a detected CI, which is the armed-budget condition.
  case "$rc" in
    0)   finish 0 "$_dmode" delegated runner "$CI_NAME" - - - ;;
    124|137)
      (( rc == 137 )) && echo "affected-tests: the runner exited 137 (SIGKILL — OOM or kill escalation), not necessarily budget expiry; deferral still applies." >&2
      if [[ "$AFFECTED_BUDGET_ACTIVE" == 1 && "$CI_NAME" != none ]]; then
        finish 6 "$_dmode" budget-deferred runner "$CI_NAME" - - -
      fi
      finish 1 "$_dmode" failed runner "$CI_NAME" - - - ;;
    3)   finish 1 "$_dmode" runner-signal runner "$CI_NAME" - - - ;;
    2|4) finish 4 "$_dmode" runner-refused runner "$CI_NAME" - - - ;;
    *)   finish 1 "$_dmode" failed runner "$CI_NAME" - - - ;;
  esac
fi

# --- adapter arm: base ref + changed set (delegated runners never reach here) ---------
BASE=""
BASE_SRC=""
affected_resolve_base() {
  if [[ -n "$ARG_BASE" ]]; then BASE="$ARG_BASE"; BASE_SRC="--base"; return 0; fi
  if git rev-parse --verify --quiet '@{upstream}' >/dev/null 2>&1; then
    BASE='@{upstream}'; BASE_SRC="upstream"; return 0
  fi
  if git rev-parse --verify --quiet 'origin/HEAD' >/dev/null 2>&1; then
    BASE='origin/HEAD'; BASE_SRC="origin/HEAD"; return 0
  fi
  local b
  for b in origin/main origin/master; do
    if git rev-parse --verify --quiet "$b" >/dev/null 2>&1; then
      BASE="$b"; BASE_SRC="$b"; return 0
    fi
  done
  # merge-base fallback: newest fork point over every remote-tracking ref.
  local best="" best_ts=0 ref mb ts
  while IFS= read -r ref; do
    mb="$(git merge-base HEAD "$ref" 2>/dev/null || true)"
    [[ -n "$mb" ]] || continue
    ts="$(git show -s --format=%ct "$mb" 2>/dev/null || true)"
    [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
    if (( ts >= best_ts )); then best="$mb"; best_ts=$ts; fi
  done < <(git for-each-ref --format='%(refname)' refs/remotes 2>/dev/null | head -n 50)
  if [[ -n "$best" ]]; then BASE="$best"; BASE_SRC="merge-base"; return 0; fi
  return 1
}

affected_resolve_base || {
  # One bounded deepen on a shallow clone — then refuse, never a silent
  # full and never a silent empty.
  if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null || true)" == "true" ]]; then
    # --no-tags: the deepen buys commit history for the merge-base, never tag
    # objects — and a bare `git fetch` in the battery closure is a tag-write
    # surface the repo-write-boundary census refuses (battery-tag-authorship).
    affected_timeout 60 git fetch --no-tags --deepen=200 >/dev/null 2>&1 || true
    affected_resolve_base || finish 4 none no-base-ref - "$CI_NAME" - - -
  else
    finish 4 none no-base-ref - "$CI_NAME" - - -
  fi
}

# Changed set: committed-vs-base ∪ staged ∪ unstaged ∪ untracked. Rename-aware
# (-M): the new path is what exists on disk. The committed arm is the one that
# can fail outright (unresolvable base) — it is captured ONCE: its rc is the
# fail-closed probe and its stdout the first leg of the union, so a bad --base
# refuses rather than reading as an empty diff and no diff runs twice.
AFFECTED_CHANGED=()
affected_mktemp changed || finish 4 none mktemp-failed - "$CI_NAME" - - -; CHANGED_TMP="$AFFECTED_TMP"
_base_rc=0
# -c core.quotePath=false: without it git emits non-ASCII paths C-quoted
# ("dir/\303\251.txt"), which never matches a glob and misses the file system.
_base_diff="$(git -c core.quotePath=false diff --name-only -M "${BASE}...HEAD" -- 2>/dev/null)" || _base_rc=$?
if (( _base_rc != 0 )); then
  if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null || true)" == "true" ]]; then
    affected_timeout 60 git fetch --no-tags --deepen=200 >/dev/null 2>&1 || true
    _base_rc=0
    _base_diff="$(git -c core.quotePath=false diff --name-only -M "${BASE}...HEAD" -- 2>/dev/null)" || _base_rc=$?
  fi
  if (( _base_rc != 0 )); then
    finish 4 none no-base-ref - "$CI_NAME" - - -
  fi
fi
# Each census leg's rc is captured — never `|| true`. A leg that fails toward
# empty silently NARROWS the selection, and the untracked leg is the worst case
# (a failed `ls-files --others` drops every NEW test file from the union). Any
# failed leg makes the changed set undecidable → coverage-favoring forced full
# (reason=census-degraded), the same contract as an empty diff — never a silent
# narrow, never a refusal for a recoverable shape.
_census_rc=0
_leg_staged="$(git -c core.quotePath=false diff --name-only --cached -M -- 2>/dev/null)" \
  || _census_rc=$?
_leg_unstaged="$(git -c core.quotePath=false diff --name-only -M -- 2>/dev/null)" \
  || _census_rc=$?
_leg_untracked="$(git -c core.quotePath=false ls-files --others --exclude-standard 2>/dev/null)" \
  || _census_rc=$?
{
  printf '%s\n' "$_base_diff"
  printf '%s\n' "$_leg_staged"
  printf '%s\n' "$_leg_unstaged"
  printf '%s\n' "$_leg_untracked"
} | grep -v '^[[:space:]]*$' | sort -u >"$CHANGED_TMP" || true
unset _base_rc _base_diff _leg_staged _leg_unstaged _leg_untracked
while IFS= read -r _p; do
  [[ -n "$_p" ]] && AFFECTED_CHANGED+=("$_p")
done <"$CHANGED_TMP"

# --- classifiers ---------------------------------------------------------------------
# (affected_glob_match is defined above the config block: config validation and
# the content trigger need it before this point.)
GLOBAL_PATHS_BUILTIN=(
  # manifests + lockfiles (any depth — a monorepo's nested manifests count too)
  package.json package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml
  pnpm-workspace.yaml bun.lock bun.lockb bunfig.toml
  pyproject.toml poetry.lock Pipfile Pipfile.lock uv.lock requirements.txt
  go.mod go.sum Cargo.toml Cargo.lock Gemfile Gemfile.lock composer.json
  composer.lock
  tsconfig tsconfig.json 'tsconfig.*' 'tsconfig*'
  'vitest.config.*' 'jest.config.*' conftest.py '.github/workflows/**'
)
INERT_PATHS_BUILTIN=('**/*.md')

GLOBAL_PATHS=("${GLOBAL_PATHS_BUILTIN[@]}")
INERT_PATHS=("${INERT_PATHS_BUILTIN[@]}")
(( CFG_GLOBAL_SET )) && GLOBAL_PATHS=(${CFG_GLOBAL_PATHS[@]+"${CFG_GLOBAL_PATHS[@]}"})
if (( CFG_INERT_SET )); then
  # A match-everything inert pattern (`*`, `**`, `**/*` — anything matching an
  # arbitrary path) is a PERMANENT green: every diff would classify all-inert
  # and exit 0. Refuse the config rather than certify nothing. Probe with an
  # improbable nested path through the same matcher the classifier uses.
  for _ip in ${CFG_INERT_PATHS[@]+"${CFG_INERT_PATHS[@]}"}; do
    if affected_glob_match "zz9q8/probe.nonexistent" "$_ip"; then
      finish 4 none "bad-config key=inert_paths" config "$CI_NAME" - - -
    fi
  done
  INERT_PATHS=(${CFG_INERT_PATHS[@]+"${CFG_INERT_PATHS[@]}"})
fi

GLOBAL_HIT=""
ALL_INERT=1
INERT_RULE="-"
for _p in ${AFFECTED_CHANGED[@]+"${AFFECTED_CHANGED[@]}"}; do
  _hit=0
  for _g in ${GLOBAL_PATHS[@]+"${GLOBAL_PATHS[@]}"}; do
    if affected_glob_match "$_p" "$_g"; then
      GLOBAL_HIT="$_p"; _hit=1; break
    fi
  done
  if (( _hit == 0 )); then
    _inert=0
    for _i in ${INERT_PATHS[@]+"${INERT_PATHS[@]}"}; do
      if affected_glob_match "$_p" "$_i"; then _inert=1; INERT_RULE="$_i"; break; fi
    done
    (( _inert )) || ALL_INERT=0
  else
    ALL_INERT=0
  fi
done

# --- explain -------------------------------------------------------------------------
if (( ARG_EXPLAIN )); then
  echo "AFFECTED_EXPLAIN base=${BASE:-none} base_source=${BASE_SRC:-none} changed=${#AFFECTED_CHANGED[@]}"
  _xn=0
  for _p in ${AFFECTED_CHANGED[@]+"${AFFECTED_CHANGED[@]}"}; do
    _xn=$((_xn + 1))
    if (( _xn > 200 )); then
      # The PATH dump is capped — a giant diff gets the verdict and a count,
      # not an unbounded listing.
      echo "PATH … and $(( ${#AFFECTED_CHANGED[@]} - 200 )) more"
      break
    fi
    _cls=changed; _rule=-
    for _g in ${GLOBAL_PATHS[@]+"${GLOBAL_PATHS[@]}"}; do
      affected_glob_match "$_p" "$_g" && { _cls=global; _rule="$_g"; break; }
    done
    if [[ "$_cls" == changed ]]; then
      for _i in ${INERT_PATHS[@]+"${INERT_PATHS[@]}"}; do
        affected_glob_match "$_p" "$_i" && { _cls=inert; _rule="$_i"; break; }
      done
    fi
    echo "PATH $(affected_marker_field "$_p") class=${_cls} rule=$(affected_marker_field "$_rule")"
  done
fi

# --- verdicts that need no runner ----------------------------------------------------
if (( _census_rc != 0 )); then
  # A census leg failed — the partial union cannot be trusted for selection OR
  # for inert/global classification. Coverage-favoring: forced full.
  echo "affected-tests: a changed-set census leg failed (rc=$_census_rc) — the selection cannot be trusted; running the full command (reason=census-degraded)." >&2
  ARG_FULL=1
  EMPTY_REASON="census-degraded"
elif (( ${#AFFECTED_CHANGED[@]} == 0 )); then
  # An empty diff is an undecidable selection — coverage-favoring, not a pass.
  # (explain emits ONE SELECTION line at the block below; nothing extra here.)
  ARG_FULL=1
  EMPTY_REASON="empty-diff"
else
  EMPTY_REASON=""
fi
unset _census_rc

if (( ALL_INERT )) && (( ${#AFFECTED_CHANGED[@]} > 0 )) && (( ARG_FULL == 0 )) && [[ -z "$GLOBAL_HIT" ]]; then
  (( ARG_EXPLAIN )) && echo "SELECTION mode=none reason=inert inert_rule=$(affected_marker_field "$INERT_RULE")"
  # UNIT NOTE: on this path of= counts CHANGED files (all inert), not the
  # repo test-file census other paths emit — units differ by design here.
  AFFECTED_CT_ELIGIBLE=1   # under --explain the hook only reports; it runs nothing
  finish 0 none inert - "$CI_NAME" 0 "${#AFFECTED_CHANGED[@]}" "${#AFFECTED_CHANGED[@]}"
fi

MODE=selected
REASON=ok
if (( ARG_FULL )); then
  MODE=full
  REASON="${EMPTY_REASON:-full-requested}"
fi
if [[ -n "$GLOBAL_HIT" && "$ARG_FULL" == 0 ]]; then
  MODE=full
  REASON="global-paths"
fi

if (( ARG_EXPLAIN )); then
  echo "SELECTION mode=${MODE} reason=${REASON} global_hit=$(affected_marker_field "${GLOBAL_HIT:--}") ci=${CI_NAME}"
  (( ARG_FULL_REQUESTED )) || AFFECTED_CT_ELIGIBLE=1
  finish 0 explain "$REASON" - "$CI_NAME" - - -
fi

# --- budget arming -----------------------------------------------------------------
if [[ "$CI_NAME" != none ]]; then
  AFFECTED_BUDGET_ACTIVE=1
  AFFECTED_DEADLINE=$(( $(affected_now) + CFG_BUDGET_SECONDS ))
else
  echo "affected-tests: no CI test workflow detected — wall-clock budget not enforced; running to completion."
fi

WIDTH="$(affected_workers "$CFG_MAX_WORKERS")"

# --- dispatch 3: stack adapters ---------------------------------------------------------
# Worst-of aggregation with precedence 1 > 4 > 6 > 0; rc 7 only when every
# detected adapter reports no suite AND nothing else resolved the gate.
WORST=0
SAW_SUITE=0
STACKS=""
RAN_SUM=0
OF_SUM=0
RAN_KNOWN=1
OF_KNOWN=1
GATE_ESCALATED_FULL=0

_affected_rank() {  # rank <rc> → precedence weight
  case "$1" in
    1) echo 4 ;; 4) echo 3 ;; 6) echo 2 ;; 0) echo 1 ;; *) echo 4 ;;
  esac
}
_affected_aggregate() {  # aggregate <rc>
  local rc="$1" cw ww
  cw="$(_affected_rank "$WORST")"
  ww="$(_affected_rank "$rc")"
  (( ww > cw )) && WORST="$rc"
  return 0
}
_affected_add_counts() {  # add ran/of independently — each keeps `-` honesty
  local r="$1" o="$2"
  if [[ "$r" =~ ^[0-9]+$ ]]; then RAN_SUM=$((RAN_SUM + r)); else RAN_KNOWN=0; fi
  if [[ "$o" =~ ^[0-9]+$ ]]; then OF_SUM=$((OF_SUM + o)); else OF_KNOWN=0; fi
}

# try_adapter <fn-name> [label] [precomputed-tool-rc] — detect, toolchain-check,
# select, run, retry-full on a vacuous selection (the empty-selection arm), then
# aggregate. <fn-name> is the suffix in affected_<fn-name>_* (hyphen-free,
# bash-3.2); <label> is what the marker prints. The optional third argument is a
# tool() rc the caller already probed — passing it skips a second bounded
# --version probe (nx/turbo's detect-probe needs the rc before deciding whether
# to fall through to js).
try_adapter() {
  local name="$1" label="${2:-$1}"
  # Per-adapter output flags reset HERE, not only inside adapters that set
  # them — a js escalation must never stain a later adapter's marker.
  ADP_ESCALATED_FULL=0
  ADP_VACUOUS=0
  if ! "affected_${name}_detect"; then
    return 0
  fi
  local tool_rc="${3:-}"
  if [[ -z "$tool_rc" ]]; then
    tool_rc=0
    "affected_${name}_tool" || tool_rc=$?
  fi
  if (( tool_rc == 2 )); then
    return 0  # stack marker present but no test tool configured — not a suite
  fi
  if (( tool_rc != 0 )); then
    echo "affected-tests: stack=$label detected but its toolchain is missing or unrunnable." >&2
    _affected_aggregate 4
    STACKS="${STACKS:+$STACKS+}$label"
    AGG_REASON="toolchain-missing"
    return 0
  fi
  STACKS="${STACKS:+$STACKS+}$label"

  local run_mode="$MODE" arc=0
  if [[ "$run_mode" == selected ]]; then
    "affected_${name}_run" selected "$WIDTH" "$BASE" || arc=$?
    if (( arc == 5 )) || [[ "${ADP_VACUOUS:-0}" == 1 ]]; then
      # Empty native selection on a non-inert diff → the full command, loudly.
      echo "affected-tests: stack=$label selected nothing for this diff — falling back to the full suite (reason=empty-selection)." >&2
      arc=0
      "affected_${name}_run" full "$WIDTH" "$BASE" || arc=$?
      if (( arc == 5 )) || [[ "${ADP_VACUOUS:-0}" == 1 ]]; then
        # A stack that runs nothing even in full mode has no suite here.
        return 0
      fi
      REASON=empty-selection
      run_mode=full
    fi
  else
    "affected_${name}_run" full "$WIDTH" "$BASE" || arc=$?
    if (( arc == 5 )) || [[ "${ADP_VACUOUS:-0}" == 1 ]]; then
      return 0
    fi
  fi

  SAW_SUITE=1
  # An adapter that could not select (e.g. js scripts.test) ran FULL instead —
  # the marker must not call that `mode=selected`.
  (( ${ADP_ESCALATED_FULL:-0} )) && GATE_ESCALATED_FULL=1
  _affected_add_counts "${ADP_RAN:--}" "${ADP_OF:--}"
  case "$arc" in
    0)   _affected_aggregate 0 ;;
    124|137)
      (( arc == 137 )) && echo "affected-tests: stack=$label exited 137 (SIGKILL — OOM or kill escalation), not necessarily budget expiry; deferral still applies." >&2
      if [[ "$AFFECTED_BUDGET_ACTIVE" == 1 && "$CI_NAME" != none ]]; then
        _affected_aggregate 6
      else
        _affected_aggregate 1
      fi ;;
    *)   _affected_aggregate 1 ;;
  esac
  return 0
}

AGG_REASON=""
# nx/turbo FIRST: a workspace scheduler's affected graph subsumes per-package
# JS selection — but only when it actually RAN a suite. A resolved tool whose
# affected graph produced nothing (vacuous in both selected and full) must not
# suppress the js adapter that could still find tests.
NXT_SUPPRESS=0
if affected_nxt_detect; then
  _trc=0
  affected_nxt_tool || _trc=$?
  if (( _trc == 0 )); then
    _saw_before=$SAW_SUITE
    try_adapter nxt nx-turbo 0  # tool already resolved — skip the re-probe
    (( SAW_SUITE > _saw_before )) && NXT_SUPPRESS=1
  elif (( _trc == 4 )); then
    echo "affected-tests: stack=nx-turbo detected but its toolchain is missing or unrunnable; falling through to js." >&2
  fi
fi
(( NXT_SUPPRESS )) || try_adapter js
try_adapter py
try_adapter go

if (( SAW_SUITE == 0 )); then
  # Nothing ran. Distinguish the refusals from the disclosed no-suite verdict:
  # a toolchain-missing aggregate is already a refusal; a repo with test files
  # but no resolvable stack refuses; no test files at all is rc 7.
  if (( WORST == 4 )); then
    finish 4 "$MODE" "${AGG_REASON:-toolchain-missing}" "${STACKS:--}" "$CI_NAME" - - -
  fi
  _tests_exist=0
  # Process substitution, not `… | grep -q .`: under pipefail grep's early exit
  # SIGPIPEs the producer and a match can read as a miss (#9217).
  if grep -q . < <(affected_find_files any '*.test.*' '*.spec.*' 'test_*.py' '*_test.py' '*_test.go'); then
    _tests_exist=1
  fi
  if (( _tests_exist )); then
    # Tests exist but no runner resolved. A present-but-foreign
    # scripts/test-all.sh gets the more actionable reason.
    if [[ -f scripts/test-all.sh ]]; then
      finish 4 "$MODE" foreign-runner - "$CI_NAME" - - -
    fi
    finish 4 "$MODE" no-stack - "$CI_NAME" - - -
  fi
  finish 7 none no-tests - "$CI_NAME" 0 0 0
fi

OUT_RAN="-"; OUT_OF="-"; SKIP_SUM="-"
(( RAN_KNOWN )) && OUT_RAN="$RAN_SUM"
(( OF_KNOWN )) && OUT_OF="$OF_SUM"
if (( RAN_KNOWN && OF_KNOWN )); then
  if (( OF_SUM >= RAN_SUM )); then
    SKIP_SUM=$((OF_SUM - RAN_SUM))
  else
    # ran>of can only mean the two counts use different units (an adapter
    # counted items/packages where of counted files). Never emit a negative
    # skipped — disclose the divergence instead.
    SKIP_SUM="-"
    echo "affected-tests: ran=$RAN_SUM exceeds the repo census of=$OF_SUM — count units diverged; skipped is not derivable." >&2
  fi
fi
# Marker honesty: an adapter that escalated selected→full (no native selector)
# makes the emitted mode full with a named reason — never a selected claim
# over a whole-suite run. MODE itself is untouched: a later adapter's own
# selection is still scoped.
OUT_MODE="$MODE"
if (( GATE_ESCALATED_FULL )) && [[ "$OUT_MODE" == selected ]]; then
  OUT_MODE=full
  [[ "$REASON" == ok ]] && REASON=no-selector
fi
# Eligible unless the operator passed --full. A gate-side escalation to full
# (global paths, empty diff, degraded census, no selector) is still eligible: the
# stack adapter's full run never runs the repo-declared command.
(( ARG_FULL_REQUESTED )) || AFFECTED_CT_ELIGIBLE=1
case "$WORST" in
  0) finish 0 "$OUT_MODE" "$REASON" "${STACKS:--}" "$CI_NAME" "$OUT_RAN" "$OUT_OF" "$SKIP_SUM" ;;
  4) finish 4 "$OUT_MODE" "${AGG_REASON:-failed}" "${STACKS:--}" "$CI_NAME" \
       "$OUT_RAN" "$OUT_OF" "$SKIP_SUM" ;;
  6) finish 6 "$OUT_MODE" budget-deferred "${STACKS:--}" "$CI_NAME" "$OUT_RAN" "$OUT_OF" "$SKIP_SUM" ;;
  *) finish 1 "$OUT_MODE" failed "${STACKS:--}" "$CI_NAME" "$OUT_RAN" "$OUT_OF" "$SKIP_SUM" ;;
esac
