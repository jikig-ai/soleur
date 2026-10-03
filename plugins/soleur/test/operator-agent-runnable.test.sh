#!/usr/bin/env bash
# Guard 1 — a generated operator script runs without a TTY and gates every write (ADR-264).
#
# THE PROPERTY (the operator's product direction: Soleur serves people with no
# terminal, so an agent must be able to run every stage): for every discovered v2
# generated operator script, every declared stage reaches a DEFINED outcome with
# stdin closed and no TTY; no stage reaches a mutating call without a valid harness
# receipt or a real TTY ack; and no stage blocks, demands a terminal, or calls the
# legacy typed-yes ack (soleur_op_ack_or_die).
#
# ASSEMBLY (every chokepoint a stage leaves through):
#   1. the `# SOLEUR-STAGE` table behind `--list`,
#   2. each stage's plan path (no mutating call, ever),
#   3. each stage's apply path, which must go through soleur_op_stage_gate,
#   4. the class-1 value helper (a skip variable the script itself names).
# The guard ITERATES every `--list` entry — never a hard-coded count and never only the
# first stage — with `</dev/null`, a `timeout`, SOLEUR_OP_LIB forced to the worktree
# library (the baked path points at the primary checkout, which only gains the staged
# gate after merge), and PATH-stubbed doppler/gh/curl/openssl/jq that log every call and
# classify it read or mutating by verb.
#
# POPULATION is re-derived from the tree at test time (not stored). A file with the v2
# header must satisfy this guard. A file with the v1 header (the legacy typed-yes
# contract) must be one of exactly three hard-coded legacy paths, and that inline list
# may only SHRINK relative to the merge base: every listed path must already be a v1
# script at the merge base, so one diff cannot add a legacy path and bless it in the
# same commit. The guard FAILS (never skips) when there is no merge base or the clone
# is shallow.
#
# EVERY mutation row is proven to LAND (md5 against its pristine source, and `bash -n`)
# before it is asked to drive the guard red: a mutation that does not land re-runs the
# baseline, and a baseline pass is indistinguishable from a real one.
set -uo pipefail

# The body below is a COPY of the canonical definition in plugins/soleur/test/test-helpers.sh
# (fixture-dir-operand-assert.test.sh asserts it is byte-equal). Every writing window below calls
# it first, so a bad root refuses before any write instead of retargeting it.
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

export TMPDIR="${TMPDIR:-/var/tmp}"
export LC_ALL=C

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SUITE_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_ROOT}/../.." && pwd)"
LIB="${PLUGIN_ROOT}/scripts/lib/operator-script.sh"
TEMPLATE="${PLUGIN_ROOT}/skills/operator-bootstrap/template.sh"
SCRIPT9321="${REPO_ROOT}/knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh"

# The three finished generated scripts that still carry the v1 (typed yes) contract. The
# list may only SHRINK; each entry must already be a v1 script at the merge base (checked
# below). Follow-up: migrate them to the staged contract (tracked in the PR body).
# The paths are spelled as SPEC-DIR names plus a shared prefix and suffix, not as three full path literals:
# the battery's tag-authorship closure (scripts/battery-tag-authorship.test.sh) follows a path literal
# into the file it names, and the finished legacy scripts run `git fetch origin main` (they are never
# executed here; this guard only reads their header line). A guard that merely names a legacy script
# must not drag its commands into the battery.
LEGACY_V1_SPEC_DIRS=(
  "feat-8450-ci-concurrency"
  "feat-linkedin-token-renewal"
  "feat-one-shot-8609-evict-runtime-app-key-prd"
)
LEGACY_V1=()
for _d in "${LEGACY_V1_SPEC_DIRS[@]}"; do LEGACY_V1[${#LEGACY_V1[@]}]="knowledge-base/project/specs/${_d}/boot""strap.sh"; done
unset _d

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  [ok] $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  [FAIL] $1" >&2; }

assert_red() {
  local guard="$1" label="$2"; shift 2
  local out rc
  out="$("$guard" "$@" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then pass "${label}: drove ${guard} RED"; else fail "${label}: ${guard} stayed GREEN over the mutation — the guard does not see it"; fi
}
assert_green() {
  local guard="$1" label="$2"; shift 2
  local out rc
  out="$("$guard" "$@" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then pass "${label}: ${guard} GREEN"; else fail "${label}: ${guard} unexpectedly RED: ${out}"; fi
}
# assert_red_for <guard> <label> <regex> <args...> — RED, and for the NAMED reason.
assert_red_for() {
  local guard="$1" label="$2" want="$3"; shift 3
  local out rc
  out="$("$guard" "$@" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then fail "${label}: ${guard} stayed GREEN over the mutation — the guard does not see it"; return; fi
  if grep -qE "$want" <<<"$out"; then pass "${label}: drove ${guard} RED for the named reason"; else fail "${label}: RED for a different reason than /${want}/: ${out}"; fi
}

# Instrument self-test (ADR-193 shape): drive both helpers once each and refuse to continue
# unless BOTH counters moved. A neutered pass()/fail() otherwise reports 0 failures.
_p="$PASS_COUNT"; _f="$FAIL_COUNT"
assert_red false "instrument self-test known-negative" >/dev/null 2>&1
assert_green true "instrument self-test known-positive" >/dev/null 2>&1
if [[ "$PASS_COUNT" -ne $((_p + 2)) || "$FAIL_COUNT" -ne "$_f" ]]; then
  printf 'INSTRUMENT SELF-TEST FAILED: assert_red/assert_green did not both register a pass (pass %s->%s fail %s->%s)\n' "$_p" "$PASS_COUNT" "$_f" "$FAIL_COUNT" >&2
  exit 2
fi
PASS_COUNT=1; FAIL_COUNT=0
echo "  [ok] instrument self-test: pass/fail dispatch; assert_red/assert_green each register a known-negative"

for bin in timeout md5sum perl python3 jq git; do
  command -v "$bin" >/dev/null 2>&1 || { printf 'HARNESS: %s is required\n' "$bin" >&2; exit 2; }
done
[[ -r "$LIB" && -r "$TEMPLATE" ]] || { printf 'HARNESS: library or template missing\n' >&2; exit 2; }

SB="$(mktemp -d -t operator-agent-runnable.XXXXXXXX)" || { printf 'HARNESS: mktemp failed\n' >&2; exit 2; }
trap 'chmod -R u+rwx "$SB" 2>/dev/null; rm -rf "$SB"' EXIT
mkdir -p "$SB/mut" "$SB/fx" || { printf 'HARNESS: mkdir failed\n' >&2; exit 2; }

# shellcheck source=./lib/operator-stub-world.sh
source "${SUITE_DIR}/lib/operator-stub-world.sh"
# shellcheck source=./lib/git-fixture-env.sh
source "${SUITE_DIR}/lib/git-fixture-env.sh"

md5_of() { md5sum "$1" | cut -d' ' -f1; }

# mutate_copy <label> <src> <dst> — perl program on stdin; PROVES the edit landed and still parses.
mutate_copy() {
  local label="$1" src="$2" dst="$3" prog
  prog="$(cat)"
  assert_fixture_dir "$dst"
  cp "$src" "$dst"
  perl -0777 -pi -e "$prog" "$dst"
  if [[ "$(md5_of "$dst")" == "$(md5_of "$src")" ]]; then fail "mutation '${label}' did NOT land (md5 identical to its source) — the row below would have re-run the baseline"; return 1; fi
  if ! bash -n "$dst" 2>/dev/null; then fail "mutation '${label}' produced a script that fails bash -n"; return 1; fi
  pass "mutation '${label}' landed (md5 differs from its source; bash -n clean)"
  return 0
}

strip_comments() { grep -vE '^[[:space:]]*#' "$1"; }

# --- fixtures, generated from the template at test time (so they cannot drift from it) -----
bake() { sed "s#__SOLEUR_OP_LIB_BAKED__#${LIB}#" "$1"; }
bake "$TEMPLATE" > "$SB/fx/template-baked.sh"

# Write-fixture: the template with an apply that performs a MUTATING vendor call, so a gate
# that is missing is observable as a mutating stub call (the template's own apply writes a
# local .env only).
perl -0777 -pe '
  s{  # \.\.\. the write goes here \(stdin for a secret, never argv\) \.\.\.}{  doppler secrets set DEMO_KEY -p demo -c prd </dev/null >/dev/null}
' "$SB/fx/template-baked.sh" > "$SB/fx/write-fixture.sh"

# Non-canonical dispatch (P1, must PASS): a stage reached through a `case` table and a
# differently named function, plus a read stage that uses a class-1 value whose skip
# variable the script itself names. Behaviour, not naming.
perl -0777 -pe '
  s{# SOLEUR-STAGE account\|read\|[^\n]*\n}{# SOLEUR-STAGE install-keys|read|Nothing changes: this records one non-secret value.|None needed.\n};
  s{    read\)\n      "read_\$\{fn\}"}{    read)\n      case "\$stage" in install-keys) stage_install_keys ;; *) "read_\${fn}" ;; esac};
  s{read_account\(\) \{}{stage_install_keys() {\n  local v=""\n  soleur_op_value SOLEUR_BOOTSTRAP_INSTALL_KEYS_NAME "  Name: " v\n  soleur_op_env_upsert "\$ENV_FILE" INSTALL_KEYS "\$v"\n}\nread_account_unused() \{};
' "$SB/fx/write-fixture.sh" > "$SB/fx/case-table.sh"

# --- the driver -------------------------------------------------------------------------------
# g1_run <script> <args...> — runs one script invocation in the stub world: stdin closed, a
# timeout, the worktree library forced, every escape variable the script itself names set to a
# harmless non-secret value. Output in G1_OUT, status in G1_RC, mutating-call count in G1_MUT.
G1_OUT=""; G1_RC=0; G1_MUT=0
g1_world() { # <name>
  local d="$SB/world/$1"; rm -rf "$d"
  stub_world_init "$d" >/dev/null 2>&1 || return 1
  G1_ROOT="$d"
}
g1_skipvars() { # <script> — every class-1/class-3 skip variable the script names (quoted or not)
  grep -ohE "soleur_op_(barrier|value)[[:space:]]+[\"']?SOLEUR_BOOTSTRAP_[A-Z0-9_]+" "$1" 2>/dev/null | grep -oE 'SOLEUR_BOOTSTRAP_[A-Z0-9_]+' | sort -u
}
# g1_bypassvars <script> — every name the script mentions that LOOKS like an approval / force / skip
# switch, plus the fixed set an agent might try. The no-receipt apply is driven with ALL of them set:
# a gate wrapped in `if [[ "${SOLEUR_BOOTSTRAP_FORCE:-}" != 1 ]]` is invisible to a drive that never
# sets the variable the bypass reads.
g1_bypassvars() {
  { grep -ohE '[A-Z][A-Z0-9_]*(YES|FORCE|CONFIRM|APPROVE|ASSUME|BYPASS|NONINTERACTIVE|AUTOMATION|ACKED)[A-Z0-9_]*' "$1" 2>/dev/null
    printf '%s\n' SOLEUR_BOOTSTRAP_YES SOLEUR_BOOTSTRAP_ASSUME_YES SOLEUR_BOOTSTRAP_CONFIRM SOLEUR_BOOTSTRAP_FORCE SOLEUR_OP_ACKED CI; } | sort -u
}
G1_BYPASS=0
g1_run() {
  local script="$1" v envs=(); shift
  for v in $(g1_skipvars "$script"); do envs[${#envs[@]}]="$v=g1-guard-value"; done
  if [[ "$G1_BYPASS" == "1" ]]; then for v in $(g1_bypassvars "$script"); do envs[${#envs[@]}]="$v=1"; done; fi
  assert_fixture_dir "$STUB_LOG"
  : > "$STUB_LOG"; rm -f "$STUB_SNAP" "$STUB_SNAP.nonce"
  G1_OUT="$(env "PATH=${G1_ROOT}/bin:${PATH}" "SOLEUR_OP_LIB=$LIB" "ENV_FILE=${G1_ROOT}/.env" "SOLEUR_BOOTSTRAP_LEDGER=${G1_ROOT}/ledger.jsonl" \
    "STUB_REAL_JQ=$STUB_REAL_JQ" "${envs[@]+"${envs[@]}"}" timeout 30 bash "$script" "$@" </dev/null 2>&1)"; G1_RC=$?
  G1_MUT="$(stub_calls mutating)"
}

# g1_stages <script> — "name class" lines from --list, or empty.
g1_stages() {
  g1_run "$1" --list
  [[ "$G1_RC" -eq 0 ]] || return 0
  sed -n 's/^SOLEUR_BOOTSTRAP_STAGE_DECL stage=\([^ ]*\) class=\([^ ]*\)$/\1 \2/p' <<<"$G1_OUT"
}

# g1_check <script> [<expect-v2 1|0>] — the property, for ONE script. Prints every violation.
g1_check() {
  local script="$1" v=0 stages name class plan_digest ops stripped table fn
  [[ -r "$script" ]] || { echo "g1: ${script} is not readable"; return 1; }
  # Population membership: the caller says what it expects; a stripped v2 header is a population miss.
  if ! sed -n '2p' "$script" | grep -qx '# SOLEUR-GENERATED-OPERATOR-SCRIPT v2'; then
    echo "g1: ${script}: population != expected — line 2 is not the v2 header (a v1 script must be one of the legacy paths, not driven here)"; return 1
  fi
  g1_world "run-$(basename "$(dirname "$script")")-$$-$RANDOM" || { echo "g1: stub world failed"; return 1; }
  stages="$(g1_stages "$script")"
  if [[ -z "$stages" ]]; then echo "g1: ${script}: zero stages observed behind --list (rc ${G1_RC}: $(printf '%s' "$G1_OUT" | head -2 | tr '\n' ' '))"; return 1; fi
  stripped="$(strip_comments "$script")"

  # --- static: no typed-yes ack, no raw prompt, no TTY demand ----------------------------------
  if grep -qE '(^|[^A-Za-z_])soleur_op_ack_or_die([^A-Za-z_]|$)' <<<"$stripped"; then echo "g1: ${script}: calls the legacy typed-yes ack soleur_op_ack_or_die (needs a terminal)"; v=1; fi
  if grep -qE '(^|[;&|[:space:]])read[[:space:]]+-[a-z]*p|(^|[;&|])[[:space:]]*read[[:space:]]+[a-z_]+[[:space:]]*$' <<<"$stripped"; then echo "g1: ${script}: a raw read prompt outside the class-1 helper"; v=1; fi
  if grep -qE '\[\[ -t [012] \]\]|/dev/tty' <<<"$stripped"; then echo "g1: ${script}: tests for or opens a terminal"; v=1; fi
  # --- static: the gate sits in the write path, before any apply dispatch --------------------
  if ! grep -qE '^[[:space:]]*soleur_op_stage_gate ' <<<"$stripped"; then
    echo "g1: ${script}: no soleur_op_stage_gate call — no write stage is gated"; v=1
  else
    local gate_ln apply_ln
    gate_ln="$(grep -nE '^[[:space:]]*soleur_op_stage_gate ' <<<"$stripped" | head -1 | cut -d: -f1)"
    apply_ln="$(grep -nE '"apply_\$\{?[a-z]+\}?"' <<<"$stripped" | head -1 | cut -d: -f1)"
    if [[ -n "$apply_ln" && "$gate_ln" -ge "$apply_ln" ]]; then echo "g1: ${script}: the apply dispatch (line ${apply_ln}) is not preceded by the gate (line ${gate_ln})"; v=1; fi
  fi
  # --- static: every dispatched function and case label is declared in the stage table ------
  table="$(sed -n 's/^# SOLEUR-STAGE \([^|]*\)|.*$/\1/p' "$script")"
  while IFS= read -r fn; do
    [[ -n "$fn" ]] || continue
    name="${fn#*_}"; name="${name//_/-}"
    if ! grep -qxF "$name" <<<"$table"; then echo "g1: ${script}: function ${fn} is dispatched by --stage but '${name}' is absent from the stage table"; v=1; fi
  done < <(grep -oE '^(read|plan|apply)_[a-z0-9_]+\(\)' <<<"$stripped" | sed 's/()$//' | grep -vE '_unused$')
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if ! grep -qxF "$name" <<<"$table"; then echo "g1: ${script}: case label '${name}' dispatches a stage that is absent from the stage table"; v=1; fi
  done < <(grep -oE '^[[:space:]]*[a-z][a-z0-9-]*\)[[:space:]]+(stage|read|plan|apply)_' <<<"$stripped" | sed -E 's/^[[:space:]]*([a-z0-9-]+)\).*/\1/')
  # --- static: a WRITE stage declares non-empty impact and rollback text -----------------------
  while IFS='|' read -r name class impact rollback; do
    [[ "$class" == "write" ]] || continue
    if [[ -z "${impact// /}" || -z "${rollback// /}" ]]; then echo "g1: ${script}: write stage '${name}' declares an empty impact or rollback line (the person approves what they can read)"; v=1; fi
  done < <(sed -n 's/^# SOLEUR-STAGE //p' "$script")

  # --- behaviour: iterate EVERY stage ---------------------------------------------------------
  local driven=0
  while read -r name class; do
    [[ -n "$name" ]] || continue
    driven=$((driven + 1))
    g1_run "$script" --stage "$name"
    if [[ "$G1_RC" -eq 124 ]]; then echo "g1: ${script}: stage ${name} BLOCKED (timeout with stdin closed)"; v=1; continue; fi
    if grep -qE 'SOLEUR_BOOTSTRAP_INPUT_REQUIRED[^\n]*tty=0' <<<"$G1_OUT"; then echo "g1: ${script}: stage ${name} demands a terminal (INPUT_REQUIRED tty=0 although every named skip variable was set)"; v=1; fi
    [[ "$G1_RC" -ne 78 && "$G1_RC" -ne 127 ]] || { echo "g1: ${script}: stage ${name} exited ${G1_RC} (xtrace refusal or a missing command), not a defined outcome"; v=1; }
    if [[ "$class" == "read" ]]; then
      if [[ "$G1_MUT" -ne 0 ]]; then echo "g1: ${script}: stage ${name} is declared read but made ${G1_MUT} mutating call(s)"; v=1; fi
      if [[ "$G1_RC" -eq 0 ]]; then
        grep -qF "SOLEUR_BOOTSTRAP_STAGE_OK stage=${name}" <<<"$G1_OUT" || { echo "g1: ${script}: read stage ${name} exited 0 without STAGE_OK"; v=1; }
      elif [[ "$G1_RC" -eq 1 ]]; then
        grep -qF "SOLEUR_BOOTSTRAP_STAGE_FAILED stage=${name}" <<<"$G1_OUT" || { echo "g1: ${script}: read stage ${name} exited 1 without STAGE_FAILED"; v=1; }
      else
        echo "g1: ${script}: read stage ${name} exited ${G1_RC}, not a defined outcome (0 ok, 1 failed with STAGE_FAILED)"; v=1
      fi
    elif [[ "$class" == "write" ]]; then
      # the plan path
      if [[ "$G1_MUT" -ne 0 ]]; then echo "g1: ${script}: the PLAN of stage ${name} made ${G1_MUT} mutating call(s)"; v=1; fi
      plan_digest="$(sed -n 's/^SOLEUR_BOOTSTRAP_PLAN stage=[^ ]* operations=[0-9]* digest=\([0-9a-f]*\)$/\1/p' <<<"$G1_OUT")"
      ops="$(sed -n 's/^SOLEUR_BOOTSTRAP_PLAN stage=[^ ]* operations=\([0-9]*\) digest=.*$/\1/p' <<<"$G1_OUT")"
      if [[ -z "$plan_digest" ]]; then
        # a defined refusal (a precondition not met in this world) is acceptable, a bare crash is not
        grep -qF "SOLEUR_BOOTSTRAP_PRECONDITION_FAILED stage=${name}" <<<"$G1_OUT" || { echo "g1: ${script}: write stage ${name} printed neither a PLAN nor PRECONDITION_FAILED (rc ${G1_RC}): $(printf '%s' "$G1_OUT" | head -3 | tr '\n' ' ')"; v=1; }
        continue
      fi
      grep -qF "SOLEUR_BOOTSTRAP_IMPACT stage=${name}" <<<"$G1_OUT" && grep -qF "SOLEUR_BOOTSTRAP_ROLLBACK stage=${name}" <<<"$G1_OUT" || { echo "g1: ${script}: the plan of ${name} prints no impact/rollback lines"; v=1; }
      # the apply path with NO receipt, with every bypass-shaped variable set to 1
      G1_BYPASS=1 g1_run "$script" --stage "$name" --apply --plan-digest "$plan_digest"
      if [[ "${ops:-0}" -eq 0 ]]; then
        # P2: nothing to change => changed=0, no approval, no prompt, no write
        if [[ "$G1_RC" -ne 0 || "$G1_MUT" -ne 0 ]] || ! grep -qF "SOLEUR_BOOTSTRAP_STAGE_OK stage=${name} changed=0" <<<"$G1_OUT"; then
          echo "g1: ${script}: a satisfied write stage (${name}) did not return changed=0 without approval (rc ${G1_RC}, ${G1_MUT} mutating)"; v=1
        fi
      else
        if [[ "$G1_MUT" -ne 0 ]]; then echo "g1: ${script}: stage ${name} reached ${G1_MUT} MUTATING call(s) with no receipt and no TTY"; v=1; fi
        if [[ "$G1_RC" -ne 75 ]] || ! grep -qF "SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED stage=${name}" <<<"$G1_OUT"; then
          echo "g1: ${script}: stage ${name} --apply with no receipt did not exit 75 APPROVAL_REQUIRED (rc ${G1_RC}): $(printf '%s' "$G1_OUT" | head -3 | tr '\n' ' ')"; v=1
        fi
      fi
    else
      echo "g1: ${script}: stage ${name} has class '${class}' (expected read or write)"; v=1
    fi
  done <<<"$stages"
  if [[ "$driven" -eq 0 ]]; then echo "g1: ${script}: zero stages were driven"; v=1; fi
  # --- behaviour: a stage the table does NOT list must be refused, whatever the dispatcher contains ---
  local probe
  for probe in sneaky hidden debug all run-all apply admin test x "g1-undeclared-$RANDOM"; do
    grep -qxF "$probe" <<<"$table" && continue
    g1_run "$script" --stage "$probe"
    if [[ "$G1_RC" -ne 64 ]] || ! grep -qF "SOLEUR_BOOTSTRAP_UNKNOWN_STAGE stage=${probe}" <<<"$G1_OUT" || [[ "$G1_MUT" -ne 0 || "$(grep -c . "$STUB_LOG")" -ne 0 ]]; then
      echo "g1: ${script}: an UNDECLARED stage '${probe}' was not refused with exit 64 UNKNOWN_STAGE and no vendor call (rc ${G1_RC}, ${G1_MUT} mutating): $(printf '%s' "$G1_OUT" | head -2 | tr '\n' ' ')"; v=1
    fi
  done
  # assert_green/assert_red run this in a command substitution, so a variable would be lost: count in a file.
  printf '%s\n' "$driven" >> "$SB/driven.count"
  return "$v"
}

# A fixture repository, built through the shell fixture-env builder (ceiling, identity, config
# hermeticity), in a subshell so nothing it exports leaks into the suite.
g1_git_init() {
  (
    git_fixture_env "$1" || exit 1
    cd "$1" && git init -q .
  ) >/dev/null 2>&1
}

# --- population ---------------------------------------------------------------------------------
# g1_population <repo-root> <legacy-list-file> <base-v1-list-file> — prints violations, rc 1 on any.
# Files: every tracked-or-untracked-unignored file that carries the header as a whole line, with no
# directory exclusion and no extension filter (a header on any other line is a violation, not a miss).
g1_discover() { # <repo-root> — every file CARRYING the header line anywhere (any extension, any directory)
  ( cd "$1" && git grep -l --untracked -E '^# SOLEUR-GENERATED-OPERATOR-SCRIPT v[0-9]+$' 2>/dev/null )
}
g1_population() {
  local root="$1" legacy_file="$2" base_file="$3" v=0 f ver listed
  local found; found="$(g1_discover "$root")"
  if [[ -z "$found" ]]; then echo "g1: the population is EMPTY — nothing was checked"; return 1; fi
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if ! sed -n '2p' "$root/$f" | grep -qE '^# SOLEUR-GENERATED-OPERATOR-SCRIPT v[0-9]+$'; then
      echo "g1: ${f}: carries the generated-script header but NOT on line 2 — the approval hook and this guard recognise line 2 only"; v=1; continue
    fi
    ver="$(sed -n '2p' "$root/$f" | sed -E 's/.* v([0-9]+)$/\1/')"
    case "$ver" in
      2) : ;;
      1) case "$f" in knowledge-base/project/specs/archive/*) continue ;; esac   # archived (archive-kb moves spec dirs): history, not guidance
         grep -qxF "$f" "$legacy_file" || { echo "g1: ${f}: a v1 (typed-yes) generated script outside the legacy list — new generated scripts are v2"; v=1; } ;;
      *) echo "g1: ${f}: unknown generated-script version v${ver}"; v=1 ;;
    esac
  done <<<"$found"
  # The legacy list may only shrink: every entry must be a v1 script at the merge base.
  while IFS= read -r listed; do
    [[ -n "$listed" ]] || continue
    grep -qxF "$listed" "$base_file" || { echo "g1: legacy list entry ${listed} is not a v1 generated script at the merge base — the list may only shrink"; v=1; }
  done < "$legacy_file"
  return "$v"
}

# base-v1 set: the v1 generated scripts at the merge base. FAILS (never skips) with no merge base or a shallow clone.
g1_base_v1() { # <outfile>
  local base ref f
  if [[ "$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then echo "g1: the clone is SHALLOW — the merge-base subset check cannot run (fetch full history)"; return 1; fi
  for ref in origin/main main; do
    git -C "$REPO_ROOT" rev-parse --verify -q "$ref" >/dev/null 2>&1 || continue
    base="$(git -C "$REPO_ROOT" merge-base HEAD "$ref" 2>/dev/null)" && [[ -n "$base" ]] && break
  done
  G1_BASE="${base:-}"
  [[ -n "${base:-}" ]] || { echo "g1: no merge base with origin/main or main — the legacy list cannot be anchored"; return 1; }
  : > "$1"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    case "$f" in *test/*|*.test.sh|*fixtures/*) continue ;; esac
    if git -C "$REPO_ROOT" show "${base}:${f}" 2>/dev/null | sed -n '2p' | grep -qx '# SOLEUR-GENERATED-OPERATOR-SCRIPT v1'; then printf '%s\n' "$f" >> "$1"; fi
  done < <(git -C "$REPO_ROOT" ls-tree -r --name-only "$base" -- knowledge-base plugins 2>/dev/null | grep -E '\.sh$')
  return 0
}

echo "== Guard 1 — population =="
printf '%s\n' "${LEGACY_V1[@]}" > "$SB/legacy.txt"
if g1_base_v1 "$SB/base-v1.txt" >"$SB/base-v1.err" 2>&1; then
  pass "the merge-base v1 set was derived ($(grep -c . "$SB/base-v1.txt") v1 script(s) at the base)"
  assert_green g1_population "population: every v1 script is a legacy path; every legacy path is a v1 script at the base" "$REPO_ROOT" "$SB/legacy.txt" "$SB/base-v1.txt"
else
  fail "the merge-base v1 set could not be derived: $(cat "$SB/base-v1.err")"
fi
FOUND="$(g1_discover "$REPO_ROOT")"
V2_COUNT="$(grep -c . < <(for f in $FOUND; do sed -n '2p' "$REPO_ROOT/$f" | grep -qx '# SOLEUR-GENERATED-OPERATOR-SCRIPT v2' && echo "$f"; done) || true)"
if [[ "$V2_COUNT" -ge 2 ]] && grep -qxF 'plugins/soleur/skills/operator-bootstrap/template.sh' <<<"$FOUND" && grep -qxF 'knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh' <<<"$FOUND"; then
  pass "the discovered v2 population holds the template and the re-cut 9321 script (${V2_COUNT} v2 script(s))"
else
  fail "the discovered v2 population is missing the template or the 9321 script (found: $(tr '\n' ' ' <<<"$FOUND"))"
fi

echo "== Guard 1 — every discovered v2 script =="
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  sed -n '2p' "$REPO_ROOT/$f" | grep -qx '# SOLEUR-GENERATED-OPERATOR-SCRIPT v2' || continue
  script="$REPO_ROOT/$f"
  # the template is driven from its baked copy (the placeholder is not a path)
  [[ "$f" == "plugins/soleur/skills/operator-bootstrap/template.sh" ]] && script="$SB/fx/template-baked.sh"
  assert_green g1_check "population member ${f}" "$script"
done <<<"$FOUND"

echo "== Guard 1 — must-PASS non-canonical inputs =="
# P1: a case-table dispatch, a differently named stage function and a class-1 value whose skip
# variable the script names — behaviour, not naming.
assert_green g1_check "P1 case-table dispatch with a class-1 value" "$SB/fx/case-table.sh"
# P2 (write stage with zero operations => changed=0, no approval) is exercised inside g1_check on
# every population member whose write stage is satisfied in the default world; assert it directly:
g1_p2() {
  g1_world p2 || return 1
  # the 9321 copy-app-values stage is satisfied once the destination equals the source
  g1_run "$SCRIPT9321" --stage copy-app-values
  local d; d="$(sed -n 's/^SOLEUR_BOOTSTRAP_PLAN stage=[^ ]* operations=[0-9]* digest=\([0-9a-f]*\)$/\1/p' <<<"$G1_OUT")"
  [[ -n "$d" ]] || { echo "p2: no plan in the default world: ${G1_OUT}"; return 1; }
  # make the destination equal the source, as an earlier approved apply would have
  assert_fixture_dir "$STUB_ROOT"
  cp "$STUB_ROOT/doppler/val/soleur-infra-privileged/"* "$STUB_ROOT/doppler/val/soleur-infra-app/"
  g1_run "$SCRIPT9321" --stage copy-app-values --apply --plan-digest "$d"
  [[ "$G1_RC" -eq 0 && "$G1_MUT" -eq 0 ]] && grep -qF 'SOLEUR_BOOTSTRAP_STAGE_OK stage=copy-app-values changed=0' <<<"$G1_OUT" || { echo "p2: a satisfied write stage asked for approval or wrote (rc ${G1_RC}, ${G1_MUT} mutating): ${G1_OUT}"; return 1; }
  grep -qF 'SOLEUR_BOOTSTRAP_PLAN_DRIFT' <<<"$G1_OUT" && { echo "p2: a satisfied stage reported plan drift"; return 1; }
  return 0
}
assert_green g1_p2 "P2 a satisfied write stage returns changed=0 with no approval and no write"

echo "== Guard 1 — mutation matrix =="
# 1. an unconditional TTY demand on a read stage
mutate_copy "g1-1 read stage demands a terminal" "$SB/fx/template-baked.sh" "$SB/mut/m1.sh" <<'PERL' && assert_red_for g1_check "g1-1 [[ -t 0 ]] || exit 64 on a read stage" 'demands a terminal|not a defined outcome' "$SB/mut/m1.sh"
s{(read_account\(\) \{\n)}{$1  [[ -t 0 ]] \|\| \{ printf 'SOLEUR_BOOTSTRAP_INPUT_REQUIRED var=tty tty=0\\n'; exit 64; \}\n}
PERL
# 2. a SECOND stage after a compliant first that calls the legacy ack
mutate_copy "g1-2 second stage calls the typed-yes ack" "$SB/fx/template-baked.sh" "$SB/mut/m2.sh" <<'PERL' && assert_red_for g1_check "g1-2 a second stage calls soleur_op_ack_or_die" 'soleur_op_ack_or_die|second' "$SB/mut/m2.sh"
s{(\# SOLEUR-STAGE provision\|[^\n]*\n)}{$1\# SOLEUR-STAGE second|read|Nothing changes.|None needed.\n};
s{(\# --- the dispatcher:)}{read_second() \{ soleur_op_ack_or_die "Continue? "; \}\n\n$1}
PERL
# 3. the gate removed from the write path (observed as a mutating call with no receipt)
mutate_copy "g1-3 stage gate removed" "$SB/fx/write-fixture.sh" "$SB/mut/m3.sh" <<'PERL' && assert_red_for g1_check "g1-3 soleur_op_stage_gate removed from a write stage" 'MUTATING call|no soleur_op_stage_gate' "$SB/mut/m3.sh"
s{\n        soleur_op_stage_gate [^\n]*\n}{\n}
PERL
assert_green g1_check "g1-3 control: the write-fixture before the mutation" "$SB/fx/write-fixture.sh"
# 4. the guard's own dispatch: a stripped v2 header, and a --list that prints nothing
mutate_copy "g1-4a v2 header stripped" "$SB/fx/template-baked.sh" "$SB/mut/m4a.sh" <<'PERL' && assert_red_for g1_check "g1-4a header stripped" 'population != expected' "$SB/mut/m4a.sh"
s{SOLEUR-GENERATED-OPERATOR-SCRIPT v2}{generated operator script}
PERL
mutate_copy "g1-4b --list prints nothing" "$SB/fx/template-baked.sh" "$SB/mut/m4b.sh" <<'PERL' && assert_red_for g1_check "g1-4b --list prints nothing" 'zero stages observed' "$SB/mut/m4b.sh"
s{(\nif \[\[ "\$\{1:-\}" == "--list" \]\]; then\n)[^\n]*\n}{$1  :\n}
PERL
# 5. a stage declared read that makes a mutating call (on the REAL 9321 script)
mutate_copy "g1-5 read stage mutates" "$SCRIPT9321" "$SB/mut/m5.sh" <<'PERL' && assert_red_for g1_check "g1-5 read stage makes a mutating call" 'declared read but made' "$SB/mut/m5.sh"
s{(read_preflight\(\) \{\n)}{$1  doppler secrets set SNEAKY -p soleur-infra-app -c prd </dev/null >/dev/null\n}
PERL
# 6. a NEW v1-header script outside the legacy list
g1_mut6() {
  local r="$SB/pop6"; rm -rf "$r"; mkdir -p "$r/knowledge-base/project/specs/feat-new"
  g1_git_init "$r"
  printf '#!/usr/bin/env bash\n# SOLEUR-GENERATED-OPERATOR-SCRIPT v1\n' > "$r/knowledge-base/project/specs/feat-new/bootstrap.sh"
  : > "$SB/empty-legacy.txt"
  g1_population "$r" "$SB/empty-legacy.txt" "$SB/empty-legacy.txt"
}
assert_red_for g1_mut6 "g1-6 a new v1 script outside the legacy list" 'outside the legacy list'
# 6b. blessing: adding a path to the inline list that was NOT a v1 script at the base
g1_mut6b() {
  local r="$SB/pop6b"; rm -rf "$r"; mkdir -p "$r/knowledge-base/project/specs/feat-new"
  g1_git_init "$r"
  printf '#!/usr/bin/env bash\n# SOLEUR-GENERATED-OPERATOR-SCRIPT v1\n' > "$r/knowledge-base/project/specs/feat-new/bootstrap.sh"
  printf 'knowledge-base/project/specs/feat-new/bootstrap.sh\n' > "$SB/blessed-legacy.txt"
  : > "$SB/empty-base.txt"
  g1_population "$r" "$SB/blessed-legacy.txt" "$SB/empty-base.txt"
}
assert_red_for g1_mut6b "g1-6b blessing a new legacy path in the same diff" 'may only shrink'
# 7. a function dispatched by --stage but absent from the table
mutate_copy "g1-7 undeclared stage function" "$SB/fx/template-baked.sh" "$SB/mut/m7.sh" <<'PERL' && assert_red_for g1_check "g1-7 a dispatched function is absent from the stage table" 'absent from the stage table' "$SB/mut/m7.sh"
s{(\# --- the dispatcher:)}{read_sneaky() \{ :; \}\n\n$1}
PERL
# 8. a write stage whose declared impact or rollback is empty
mutate_copy "g1-8 empty rollback line" "$SB/fx/template-baked.sh" "$SB/mut/m8.sh" <<'PERL' && assert_red_for g1_check "g1-8 a write stage with an empty rollback" 'empty impact or rollback' "$SB/mut/m8.sh"
s{(\# SOLEUR-STAGE provision\|write\|[^|\n]*)\|[^\n]*\n}{$1|\n}
PERL

# 10. an ENVIRONMENT-VARIABLE bypass of the gate (the hard-rule shape): the gate runs only unless a
#     force variable is set. A drive that never sets the variable the bypass reads sees nothing.
mutate_copy "g1-10 gate skipped when SOLEUR_BOOTSTRAP_FORCE=1" "$SB/fx/write-fixture.sh" "$SB/mut/m10.sh" <<'PERL' && assert_red_for g1_check "g1-10 an env-var bypass of the stage gate" 'MUTATING call' "$SB/mut/m10.sh"
s{\n(        )(soleur_op_stage_gate [^\n]*)\n}{\n$1if [[ "\$\{SOLEUR_BOOTSTRAP_FORCE:-\}" != "1" ]]; then $2; fi\n}
PERL
# 11. a stage that is NOT in the table, reached through the dispatcher (the table is self-declared)
mutate_copy "g1-11 undeclared stage in the dispatcher" "$SB/fx/write-fixture.sh" "$SB/mut/m11.sh" <<'PERL' && assert_red_for g1_check "g1-11 a hidden stage performs a write with no gate and is not listed" 'UNDECLARED stage' "$SB/mut/m11.sh"
s{(dispatch_stage\(\) \{\n  local stage="\$1"[^\n]*\n)}{$1  case "\$stage" in sneaky) doppler secrets set HIDDEN -p demo -c prd </dev/null >/dev/null; exit 0 ;; esac\n}
PERL
# 12. the header on line 3 is a population violation (the hook and this guard recognise line 2 only)
g1_mut12() {
  local r="$SB/pop12"; rm -rf "$r"; mkdir -p "$r/knowledge-base/project/specs/feat-new"
  g1_git_init "$r"
  printf '#!/usr/bin/env bash\n# a second comment line\n# SOLEUR-GENERATED-OPERATOR-SCRIPT v2\n' > "$r/knowledge-base/project/specs/feat-new/bootstrap"
  : > "$SB/empty-legacy12.txt"
  g1_population "$r" "$SB/empty-legacy12.txt" "$SB/empty-legacy12.txt"
}
# 12b. a legacy v1 script moved by archive-kb under specs/archive/ is not a violation
g1_mut12b() {
  local r="$SB/pop12b"; rm -rf "$r"; mkdir -p "$r/knowledge-base/project/specs/archive/20261001-feat-old"
  g1_git_init "$r"
  printf '#!/usr/bin/env bash\n# SOLEUR-GENERATED-OPERATOR-SCRIPT v1\n' > "$r/knowledge-base/project/specs/archive/20261001-feat-old/bootstrap.sh"
  : > "$SB/empty-legacy12b.txt"
  g1_population "$r" "$SB/empty-legacy12b.txt" "$SB/empty-legacy12b.txt"
}
assert_green g1_mut12b "g1-12b must-PASS: an archived v1 script (archive-kb moved its spec dir) is not flagged"
assert_red_for g1_mut12 "g1-12 a header-bearing file with no extension and the header on line 3" 'NOT on line 2'
# 13-15. reads that write: the stub classifies by an allowlist of READ verbs, so each of these is seen
for m in "13|gh api -X DELETE repos/jikig-ai/soleur/environments/x|gh api -X DELETE" "14|gh variable set X --body 1 -R jikig-ai/soleur|gh variable set" "15|curl -XPOST https://api.github.com/app|curl -XPOST"; do
  n="${m%%|*}"; rest="${m#*|}"; body="${rest%%|*}"; what="${rest#*|}"
  cp "$SCRIPT9321" "$SB/mut/m${n}.sh"
  perl -0777 -pi -e 's{(read_preflight\(\) \{\n)}{$1  '"${body//\//\\/}"' </dev/null >/dev/null 2>&1 \|\| true\n}' "$SB/mut/m${n}.sh"
  if [[ "$(md5_of "$SB/mut/m${n}.sh")" != "$(md5_of "$SCRIPT9321")" ]] && bash -n "$SB/mut/m${n}.sh" 2>/dev/null; then
    pass "mutation 'g1-${n} read stage runs ${what}' landed (md5 differs from its source; bash -n clean)"
    assert_red_for g1_check "g1-${n} a read stage that runs ${what}" 'declared read but made' "$SB/mut/m${n}.sh"
  else
    fail "mutation 'g1-${n}' did not land"
  fi
done
# 16. a PLAN that writes
mutate_copy "g1-16 plan function mutates" "$SCRIPT9321" "$SB/mut/m16.sh" <<'PERL' && assert_red_for g1_check "g1-16 a plan_ function makes a mutating call" 'PLAN of stage' "$SB/mut/m16.sh"
s{(plan_copy_app_values\(\) \{\n)}{$1  gh secret delete SNEAKY -R jikig-ai/soleur </dev/null >/dev/null 2>\&1 \|\| true\n}
PERL
# 17. must-PASS: a class-1 skip variable named in QUOTES is still found and set (no false RED)
sed 's/soleur_op_value SOLEUR_BOOTSTRAP_INSTALL_KEYS_NAME/soleur_op_value "SOLEUR_BOOTSTRAP_INSTALL_KEYS_NAME"/' "$SB/fx/case-table.sh" > "$SB/fx/case-table-quoted.sh"
if grep -qF 'soleur_op_value "SOLEUR_BOOTSTRAP_INSTALL_KEYS_NAME"' "$SB/fx/case-table-quoted.sh"; then
  pass "fixture 'g1-17 quoted skip variable' landed"
  assert_green g1_check "g1-17 must-PASS: a quoted class-1 skip variable" "$SB/fx/case-table-quoted.sh"
else
  fail "fixture 'g1-17' did not land"
fi

# 9. THE ORIGINAL DEFECT: the pre-ADR-264 template (every write needs a typed `yes` at a terminal,
#    no stages), merely re-labelled v2, is a script that cannot run without a TTY. The guard must
#    fail it. Taken from the merge base, so it is the real old artifact and not a re-typed one.
if [[ -n "${G1_BASE:-}" ]] && git -C "$REPO_ROOT" show "${G1_BASE}:plugins/soleur/skills/operator-bootstrap/template.sh" > "$SB/old-template.raw" 2>/dev/null \
   && sed -n '2p' "$SB/old-template.raw" | grep -qx '# SOLEUR-GENERATED-OPERATOR-SCRIPT v1'; then
  sed '2s/ v1$/ v2/' "$SB/old-template.raw" | sed "s#__SOLEUR_OP_LIB_BAKED__#${LIB}#" > "$SB/mut/m9.sh"
  if [[ "$(md5_of "$SB/mut/m9.sh")" != "$(md5_of "$SB/old-template.raw")" ]] && bash -n "$SB/mut/m9.sh" 2>/dev/null; then
    pass "mutation 'g1-9 the typed-yes template relabelled v2' landed (md5 differs from the merge-base template; bash -n clean)"
    assert_red_for g1_check "g1-9 the pre-ADR-264 template (typed yes, no stages)" 'zero stages observed|soleur_op_ack_or_die|no soleur_op_stage_gate' "$SB/mut/m9.sh"
  else
    fail "mutation 'g1-9' did not land"
  fi
  git -C "$REPO_ROOT" show "${G1_BASE}:knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh" > "$SB/old-9321.raw" 2>/dev/null || true
  if sed -n '2p' "$SB/old-9321.raw" 2>/dev/null | grep -qx '# SOLEUR-GENERATED-OPERATOR-SCRIPT v1'; then
    sed '2s/ v1$/ v2/' "$SB/old-9321.raw" > "$SB/mut/m9b.sh"
    assert_red_for g1_check "g1-9b the pre-ADR-264 9321 script (typed yes at every write) relabelled v2" 'zero stages observed|soleur_op_ack_or_die|no soleur_op_stage_gate' "$SB/mut/m9b.sh"
  else
    pass "g1-9b: the merge base no longer carries the v1 9321 script (the row's subject has been retired)"
  fi
else
  # The merge-base template is already v2 (a later PR): the row's subject is gone. Do not skip silently.
  pass "g1-9: the merge-base template is not the v1 typed-yes template any more (the row's subject has been retired)"
fi

# --- anti-vacuity floor (reported directly, never through fail(): ADR-193) -----------------------
ASSERT_TOTAL=$((PASS_COUNT + FAIL_COUNT))
# 44 = the count measured on main, where the merge-base template is already v2 so row g1-9 takes its
# single-assertion "retired" arm. The floor was 46 while the v1 template was still the base (g1-9 and
# g1-9b each ran extra assertions), which reddened every run once #9386 itself became the base.
FLOOR=44
G1_DRIVEN_TOTAL="$(awk '{ s += $1 } END { print s + 0 }' "$SB/driven.count" 2>/dev/null)"
if [[ "${G1_DRIVEN_TOTAL:-0}" -lt 1 ]]; then
  printf '  [FAIL] anti-vacuity: the guard drove ZERO stages across the whole run\n' >&2
  printf 'Total: %s assertions, %s failed\n' "$ASSERT_TOTAL" "$((FAIL_COUNT + 1))"
  exit 1
fi
if [[ "$ASSERT_TOTAL" -lt "$FLOOR" ]]; then
  printf '  [FAIL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$ASSERT_TOTAL" "$FLOOR" >&2
  printf 'Total: %s assertions, %s failed\n' "$ASSERT_TOTAL" "$((FAIL_COUNT + 1))"
  exit 1
fi
echo "Total: ${ASSERT_TOTAL} assertions, ${FAIL_COUNT} failed (stages driven: ${G1_DRIVEN_TOTAL})"
[[ "$FAIL_COUNT" -eq 0 ]]
