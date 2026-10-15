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
#      usage-table position (a comment-only mention does NOT count). Delegated
#      `--affected`, or `--full` under this script's `--full`. A foreign script
#      of that name is NEVER invoked with Soleur flags — it falls through to 3.
#   3. Stack adapters, in order: nx/turbo, JS/TS (vitest `related` SUBCOMMAND /
#      jest --findRelatedTests), Python (pytest + testmon/xdist), Go (`go list`
#      reverse-dependency closure).
#
# Exit contract — produced ONLY by finish() in lib/affected-tests/common.sh,
# the single exit site for the whole gate:
#   0  every selected test passed, OR NO_TESTS_AFFECTED for an all-inert diff
#   1  a selected test failed, or the delegated runner was signal-killed (rc 3
#      maps to 1 reason=runner-signal); a failure seen before budget expiry
#      wins over deferral
#   4  AFFECTED_GATE_REFUSED — no-stack, bad-config key=<k>,
#      vacuous-test-command, no-base-ref, toolchain-missing, runner-refused,
#      foreign-runner (a foreign scripts/test-all.sh AND no adapter resolves)
#   6  AFFECTED_GATE_BUDGET_DEFERRED — budget expired AND a CI test workflow was
#      detected; CI stays the authoritative gate
#   7  no test suite detected at all — disclosed note, never labelled passed
#
# Output contract:
#   human:  `Ran X of N test files affected by this change: passed.` —
#           never the words "tests verified"; beside it the literal verdict
#           `affected-suite gate passed.`
#   inert:  `NO_TESTS_AFFECTED inert_rule=<pat>` + `No tests ran: docs-only change.`
#   marker: `AFFECTED_GATE ran=<X> of=<N> skipped=<Y> mode=<selected|full|custom>
#           reason=<…> stack=<…> ci=<file|none>` on every path including
#           refusals; counts are `-` on paths that produce no honest count
#           (delegated runner, opaque test_command, refusals).
#
# `.soleur-test-gate.json` (repo root, committed, every key optional; unknown
# key / malformed JSON / wrong type → rc 4 reason=bad-config key=<k>):
#   test_command   string   full-run command; true/`:`/`exit 0`/bare `echo` →
#                           rc 4 reason=vacuous-test-command
#   global_paths   string[] REPLACES built-ins; any hit forces the full command
#   inert_paths    string[] REPLACES built-ins (`**/*.md` default); an all-inert
#                           diff → rc 0 NO_TESTS_AFFECTED; a mixed diff is never
#                           inert
#   budget_seconds number   wall-clock cap, enforced ONLY when a CI test
#                           workflow is detected; default 900 (unmeasured)
#   max_workers    number   overrides the width formula
#   budget_ci      boolean  forces CI-deferral eligibility without a workflow
#
# Base-ref order: --base > @{upstream} > origin/HEAD > origin/main >
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
# Cloud (Devin): CLAUDE_PLUGIN_ROOT unset → the identity-based plugin-root
# resolver from commands/go.md (ADR-179, three arms) emits
# SOLEUR_PLUGIN_ROOT_RESOLVE for diagnosis; the gate itself resolves its libs
# by BASH_SOURCE and needs no root. A detected stack with no runnable
# toolchain → rc 4 reason=toolchain-missing.

set -euo pipefail

GATE_PROG="affected-tests.sh"
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

# --- soleur plugin-root resolver (ADR-179 pattern, copied shape from
# commands/go.md; same three arms, same identity preflight, diagnostic only —
# the gate runs from its own BASH_SOURCE either way). -------------------------
ROOT="${CLAUDE_PLUGIN_ROOT:-}"; SRC=plugin-root-token
if [ -z "$ROOT" ] && [ -n "${GROK_PLUGIN_ROOT:-}" ]; then
  ROOT="$GROK_PLUGIN_ROOT"; SRC=grok-env
fi
VERIFIED=false
if [ -n "$ROOT" ] \
   && [ -f "${ROOT}/.claude-plugin/plugin.json" ] \
   && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${ROOT}/.claude-plugin/plugin.json"; then
  VERIFIED=true
fi
PRIOR_SRC="$SRC"
PRIOR_ROOT="$ROOT"
if [ "$VERIFIED" != true ]; then
  ROOT=""; SRC=none
  for d in "$HOME/.local/share/devin/cli/plugins/cache" "${SOLEUR_DEVIN_CACHE_OPT:-/opt/.devin/plugins}"; do
    [ -d "$d" ] || continue
    [ "$SRC" = none ] && SRC=devin-cache-nomatch
    MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' \
      -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"
    if [ -n "$MANIFEST" ]; then
      ROOT="${MANIFEST%/.claude-plugin/plugin.json}"; SRC=devin-cache; VERIFIED=true
      break
    fi
  done
  if [ "$VERIFIED" != true ] && [ -n "$PRIOR_ROOT" ]; then
    SRC="$PRIOR_SRC"
  fi
fi
echo "SOLEUR_PLUGIN_ROOT_RESOLVE gate=affected-tests source=${SRC} verified=${VERIFIED}"
# --- end resolver -------------------------------------------------------------

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
    -h|--help) usage; finish 0 none help - none - - - ;;
    *) echo "affected-tests: unknown argument '$1' (try --help)" >&2
       finish 4 none bad-usage - none - - - ;;
  esac
  shift
done

# --- repository root ------------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  finish 4 none no-base-ref - none - - -
fi
cd "$REPO_ROOT"

# --- CI detection (needed early: it arms the budget and fills ci=) ----------------
CI_NAME=none
affected_detect_ci() {
  local f
  for f in .github/workflows/*.yml .github/workflows/*.yaml; do
    [[ -f "$f" ]] || continue
    # pull_request or push trigger AND a test-command shape in the same file —
    # a workflow that merely exists is not a gate to defer to.
    grep -qE 'pull_request|push' "$f" || continue
    if grep -qE 'test-all\.sh|npm[[:space:]]+(run[[:space:]]+)?test|yarn[[:space:]]+test|pnpm[[:space:]]+(run[[:space:]]+)?test|bun[[:space:]]+test|vitest|jest|pytest|go[[:space:]]+test|cargo[[:space:]]+test|ctest|make[[:space:]]+test|deno[[:space:]]+test' "$f"; then
      CI_NAME="$f"
      return 0
    fi
  done
  return 1
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

# Dump the JSON object as NUL-separated KEY\0TYPE\0VALUE\0 triples on stdout —
# array elements arrive as one `elem:<type>` record each, an empty array as a
# bare `array` record so present-but-empty stays distinct from absent. The
# SCHEMA is validated by the caller; these emitters only decode. rc 3 = the
# file is not a JSON object (malformed).
_affected_json_dump() {
  local f="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$f" <<'PYEOF'
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
    jq -j '
      to_entries[] | .key as $k | (.value | type) as $t |
      if $t == "array" then
        if (.value | length) == 0 then ($k, " ", "array", " ", " ")
        else (.value[] | ($k, " ", ("elem:" + (. | type)), " ",
             (if (. | type) == "string" then . else tojson end), " "))
        end
      else ($k, " ", $t, " ",
            (if $t == "string" then .value else (.value | tojson) end), " ")
      end' "$f" 2>/dev/null
    return $?
  fi
  # No JSON engine: a present config we cannot parse is a toolchain fact, and
  # the fail direction is CLOSED.
  return 2
}

# Load and validate. Fail-closed everywhere: malformed, unknown key, or wrong
# type → rc 4 reason=bad-config key=<k>; a vacuous test_command →
# reason=vacuous-test-command.
affected_load_config() {
  local cfg=".soleur-test-gate.json"
  [[ -f "$cfg" ]] || return 0
  local tmp rc=0
  tmp="$(mktemp "${TMPDIR:-/tmp}/affected-cfg.XXXXXX")"
  _affected_json_dump "$cfg" >"$tmp" || rc=$?
  if (( rc == 2 )); then
    rm -f "$tmp"
    finish 4 none "toolchain-missing" config "$CI_NAME" - - -
  fi
  if (( rc != 0 )); then
    rm -f "$tmp"
    finish 4 none "bad-config key=$cfg" config "$CI_NAME" - - -
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
        CFG_BUDGET_SECONDS="${v%%.*}" ;;
      max_workers)
        [[ "$t" == number ]] || { badkey="$k"; break; }
        CFG_MAX_WORKERS="${v%%.*}" ;;
      budget_ci)
        [[ "$t" == boolean ]] || { badkey="$k"; break; }
        CFG_BUDGET_CI="$v" ;;
      *) badkey="$k"; break ;;
    esac
  done <"$tmp"
  rm -f "$tmp"
  if [[ -n "$badkey" ]]; then
    finish 4 none "bad-config key=$badkey" config "$CI_NAME" - - -
  fi

  if [[ -n "$CFG_TEST_COMMAND" ]]; then
    # Vacuous escape hatches are refused — `true`, `:`, `exit 0`, a bare echo:
    # each is the natural repair for a stuck rc 4 and each would certify
    # nothing. Normalise whitespace before comparing so ` exit 0 ` cannot slip.
    local norm
    norm="$(printf '%s' "$CFG_TEST_COMMAND" | tr '\n\t' '  ' | tr -s ' ' | sed 's/^ //; s/ *;*$//; s/ $//')"
    case "$norm" in
      ""|true|:|exit|"exit 0"|echo|"sh -c true"|"bash -c true")
        finish 4 custom vacuous-test-command custom "$CI_NAME" - - - ;;
      echo\ *)
        # A bare echo — the whole command is one `echo`, no composition.
        case "$norm" in
          *"&&"*|*"||"*|*\;*|*\|*) ;;
          *) finish 4 custom vacuous-test-command custom "$CI_NAME" - - - ;;
        esac ;;
    esac
  fi
}
affected_detect_ci || true   # a miss is the common case; never fatal
affected_load_config
if [[ "$CI_NAME" == none && "$CFG_BUDGET_CI" == true ]]; then
  CI_NAME="config:budget_ci"
fi

# --- self-check -------------------------------------------------------------------
if (( ARG_SELFCHECK )); then
  # Config load + toolchain probe only; never runs tests. Under 15 s by
  # construction — every probe below is `command -v` or a bounded --version.
  command -v git >/dev/null 2>&1 || finish 4 none toolchain-missing config "$CI_NAME" - - -
  # Probe each detected stack's toolchain: detection is free, and each tool()
  # --version probe is already bounded.
  _sc_trc=0
  for _sc_stack in nxt js py go; do
    if "affected_${_sc_stack}_detect"; then
      _sc_trc=0
      "affected_${_sc_stack}_tool" || _sc_trc=$?
      case "$_sc_trc" in
        0) echo "AFFECTED_GATE_SELF_CHECK stack=${_sc_stack} toolchain=ok" ;;
        2) echo "AFFECTED_GATE_SELF_CHECK stack=${_sc_stack} toolchain=no-test-tool" ;;
        *) echo "AFFECTED_GATE_SELF_CHECK stack=${_sc_stack} toolchain=missing" ;;
      esac
    fi
  done
  echo "AFFECTED_GATE_SELF_CHECK ok"
  finish 0 none ok - "$CI_NAME" - - -
fi

# --- the custom-command arm -------------------------------------------------------
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
      if [[ "$CI_NAME" != none ]]; then
        finish 6 custom budget-deferred custom "$CI_NAME" - - -
      fi
      finish 1 custom "ok" custom "$CI_NAME" - - - ;;
    *)     finish 1 custom failed custom "$CI_NAME" - - - ;;
  esac
fi

# --- base ref + changed set ---------------------------------------------------------
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
    affected_timeout 60 git fetch --deepen=200 >/dev/null 2>&1 || true
    affected_resolve_base || finish 4 none no-base-ref - "$CI_NAME" - - -
  else
    finish 4 none no-base-ref - "$CI_NAME" - - -
  fi
}

# Changed set: committed-vs-base ∪ staged ∪ unstaged ∪ untracked. Rename-aware
# (-M): the new path is what exists on disk.
AFFECTED_CHANGED=()
_affected_collect_changed() {
  {
    git diff --name-only -M "${BASE}...HEAD" -- 2>/dev/null
    git diff --name-only --cached -M -- 2>/dev/null
    git diff --name-only -M -- 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | grep -v '^[[:space:]]*$' | sort -u
}
CHANGED_TMP="$(mktemp "${TMPDIR:-/tmp}/affected-changed.XXXXXX")"
_affected_collect_changed >"$CHANGED_TMP" || true
# The committed arm is the one that can fail outright (unresolvable base);
# probe it explicitly so a bad --base fails closed rather than reading as an
# empty diff.
if ! git diff --name-only -M "${BASE}...HEAD" -- >/dev/null 2>&1; then
  if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null || true)" == "true" ]]; then
    affected_timeout 60 git fetch --deepen=200 >/dev/null 2>&1 || true
  fi
  if ! git diff --name-only -M "${BASE}...HEAD" -- >/dev/null 2>&1; then
    rm -f "$CHANGED_TMP"
    finish 4 none no-base-ref - "$CI_NAME" - - -
  fi
  _affected_collect_changed >"$CHANGED_TMP" || true
fi
while IFS= read -r _p; do
  [[ -n "$_p" ]] && AFFECTED_CHANGED+=("$_p")
done <"$CHANGED_TMP"
rm -f "$CHANGED_TMP"

# --- classifiers ---------------------------------------------------------------------
# A pattern containing `/` matches the whole path; `**/` also matches zero
# directories (its `**/` prefix is stripped for the second try). A bare
# pattern matches the basename.
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
(( CFG_INERT_SET )) && INERT_PATHS=(${CFG_INERT_PATHS[@]+"${CFG_INERT_PATHS[@]}"})

GLOBAL_HIT=""
GLOBAL_RULE="-"
ALL_INERT=1
INERT_RULE="-"
for _p in ${AFFECTED_CHANGED[@]+"${AFFECTED_CHANGED[@]}"}; do
  _hit=0
  for _g in ${GLOBAL_PATHS[@]+"${GLOBAL_PATHS[@]}"}; do
    if affected_glob_match "$_p" "$_g"; then
      GLOBAL_HIT="$_p"; GLOBAL_RULE="$_g"; _hit=1; break
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
  for _p in ${AFFECTED_CHANGED[@]+"${AFFECTED_CHANGED[@]}"}; do
    _cls=changed; _rule=-
    for _g in ${GLOBAL_PATHS[@]+"${GLOBAL_PATHS[@]}"}; do
      affected_glob_match "$_p" "$_g" && { _cls=global; _rule="$_g"; break; }
    done
    if [[ "$_cls" == changed ]]; then
      for _i in ${INERT_PATHS[@]+"${INERT_PATHS[@]}"}; do
        affected_glob_match "$_p" "$_i" && { _cls=inert; _rule="$_i"; break; }
      done
    fi
    echo "PATH ${_p} class=${_cls} rule=${_rule}"
  done
fi

# --- verdicts that need no runner ----------------------------------------------------
if (( ${#AFFECTED_CHANGED[@]} == 0 )); then
  # An empty diff is an undecidable selection — coverage-favoring, not a pass.
  (( ARG_EXPLAIN )) && echo "SELECTION mode=full reason=empty-diff"
  ARG_FULL=1
  EMPTY_REASON="empty-diff"
else
  EMPTY_REASON=""
fi

if (( ALL_INERT )) && (( ${#AFFECTED_CHANGED[@]} > 0 )) && (( ARG_FULL == 0 )) && [[ -z "$GLOBAL_HIT" ]]; then
  (( ARG_EXPLAIN )) && echo "SELECTION mode=none reason=inert inert_rule=${INERT_RULE}"
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
  echo "SELECTION mode=${MODE} reason=${REASON} global_hit=${GLOBAL_HIT:--} ci=${CI_NAME}"
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

# --- dispatch 2: the capability-positive repo runner -----------------------------------
# The probe reads the REGISTRATION, not the filename and never a comment: the
# flag must sit at a case-label or usage-table position — first token on the
# line (optionally inside a `a|b)` alternation) followed by a flag-table
# terminator.
RUNNER=""
if [[ -f scripts/test-all.sh ]] \
   && grep -Eq '^[[:space:]]*(--[[:alnum:]_-]+\|)*--print-selection([])|,[:space:]])' scripts/test-all.sh; then
  RUNNER="scripts/test-all.sh"
fi

if [[ -n "$RUNNER" ]]; then
  _flag=--affected
  [[ "$MODE" == full ]] && _flag=--full
  rc=0
  affected_bound bash "$RUNNER" "$_flag" || rc=$?
  # Delegated-runner rc mapping: 4 (REFUSED — nothing ran) → 4
  # reason=runner-refused; 3 (UNRESOLVED — killed/declined suites) → 1
  # reason=runner-signal; 2 (usage) → 4 runner-refused; the rest pass through
  # as a plain verdict. rc 124/137 means OUR bound expired — deferral only
  # ever applies with a detected CI, which is the armed-budget condition.
  case "$rc" in
    0)   finish 0 "$MODE" delegated runner "$CI_NAME" - - - ;;
    124|137)
      if [[ "$AFFECTED_BUDGET_ACTIVE" == 1 ]]; then
        finish 6 "$MODE" budget-deferred runner "$CI_NAME" - - -
      fi
      finish 1 "$MODE" failed runner "$CI_NAME" - - - ;;
    3)   finish 1 "$MODE" runner-signal runner "$CI_NAME" - - - ;;
    2|4) finish 4 "$MODE" runner-refused runner "$CI_NAME" - - - ;;
    *)   finish 1 "$MODE" failed runner "$CI_NAME" - - - ;;
  esac
fi

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

# try_adapter <fn-name> [label] — detect, toolchain-check, select, run,
# retry-full on a vacuous selection (the empty-selection arm), then aggregate.
# <fn-name> is the suffix in affected_<fn-name>_* (hyphen-free, bash-3.2);
# <label> is what the marker prints.
try_adapter() {
  local name="$1" label="${2:-$1}"
  if ! "affected_${name}_detect"; then
    return 0
  fi
  local tool_rc=0
  "affected_${name}_tool" || tool_rc=$?
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
  _affected_add_counts "${ADP_RAN:--}" "${ADP_OF:--}"
  case "$arc" in
    0)   _affected_aggregate 0 ;;
    124|137)
      if [[ "$AFFECTED_BUDGET_ACTIVE" == 1 ]]; then
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
# JS selection, so a resolved nx/turbo tool suppresses the js adapter arm.
NXT_SUPPRESS=0
if affected_nxt_detect; then
  _trc=0
  affected_nxt_tool || _trc=$?
  if (( _trc == 0 )); then
    NXT_SUPPRESS=1
    try_adapter nxt nx-turbo
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
  if find . \( -name .git -o -name node_modules -o -name vendor -o -name .venv \) -prune \
      -o -type f \( -name '*.test.*' -o -name '*.spec.*' -o -name 'test_*.py' \
                    -o -name '*_test.py' -o -name '*_test.go' \) -print -quit 2>/dev/null \
      | grep -q .; then
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
if (( RAN_KNOWN && OF_KNOWN )) && (( OF_SUM >= RAN_SUM )); then
  SKIP_SUM=$((OF_SUM - RAN_SUM))
fi
case "$WORST" in
  0) finish 0 "$MODE" "$REASON" "${STACKS:--}" "$CI_NAME" "$OUT_RAN" "$OUT_OF" "$SKIP_SUM" ;;
  4) finish 4 "$MODE" "${AGG_REASON:-failed}" "${STACKS:--}" "$CI_NAME" \
       "$OUT_RAN" "$OUT_OF" "$SKIP_SUM" ;;
  6) finish 6 "$MODE" budget-deferred "${STACKS:--}" "$CI_NAME" "$OUT_RAN" "$OUT_OF" "$SKIP_SUM" ;;
  *) finish 1 "$MODE" failed "${STACKS:--}" "$CI_NAME" "$OUT_RAN" "$OUT_OF" "$SKIP_SUM" ;;
esac
