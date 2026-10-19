#!/usr/bin/env bash
#
# Item 5 of the Inngest LUKS arc: an OFFLINE, LOCAL-STATE rehearsal of recovering the Redis LUKS
# passphrase's Terraform state after state loss. It replaces the sentence "State-loss recovery remains
# UNVERIFIED" (ADR-282, loss-mode table) with a measured result, and it pins that result so a later edit
# to the resource, the provider or the recipe turns this suite red instead of silently falsifying the
# claim.
#
# What it does, in a scratch directory with LOCAL state and a SYNTHETIC passphrase minted at run time:
#   1. extracts the real passphrase resource from the production .tf (shared lexer block_of) and
#      asserts the three attributes the recipe depends on inside that one block;
#   2. mints a value, records its digest, deletes the state (the loss), imports the value through an
#      environment variable (never argv), and asserts what the owner would see: the plan is a
#      replacement that prevent_destroy turns into a hard error, and an apply is refused with the key
#      unchanged;
#   3. applies the documented repair (state pull, special=false, serial+1, state push) and asserts the
#      plan reports no changes with the digest equal to the pre-loss digest;
#   4. runs a negative control (the same fixture without prevent_destroy mints a different key), a
#      characterization of the import-block route (it plans the same replacement; it does NOT plan as a
#      no-op), and feeds the repo's REAL destroy-guard filter the state-loss plan and the repaired plan;
#   5. runs an in-suite mutation battery: each mutation is a child run of this suite that must exit 1
#      with the expected failing assertion NAME, after a pristine child run that must exit 0.
#
# Properties (P1-P4):
#   P1 after state loss, import + the documented repair leaves "no changes" and the value byte-identical
#   P2 until the repair is applied, no plan or apply can replace the passphrase
#   P3 the synthetic value never reaches terraform's argv, this suite's stdout/stderr or any surviving file
#   P4 the claim is tied to its evidence, and the evidence runs where CI runs
#
# NOT claimed (the ADR records each as UNVERIFIED): R2-backed state, the per-merge destroy-guard on the
# full production plan, any other passphrase, other terraform or provider versions than the ones run, the
# relation to the Doppler copy.
#
# Tool policy: terraform and jq are required. With CI=true or GITHUB_ACTIONS=true a missing tool or
# provider is FATAL (exit 1); locally the dynamic section is skipped LOUDLY with a counted marker.
# An emergency edit to the production passphrase block that merges with [skip-web-platform-apply] is
# EXPECTED to turn the advisory leg that owns this suite red: re-review the recovery claim in ADR-282 and
# the runbook row, do not just re-pin.
#
# Private argv (selectable on the command line only, never by a leaked environment variable): --child,
# --src-tf <file>, --plugin-dir <dir>, --scratch-parent <dir>, --mut <name>. Anything else exits 2. The provider
# package directory may additionally come from SOLEUR_TF_PLUGIN_DIR / TF_PLUGIN_CACHE_DIR; that only chooses
# where the locked provider is read from.

set -uo pipefail
umask 077

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
HCL_LIB="$REPO_ROOT/tests/scripts/lib/hcl-effective-text.sh"
[ -f "$HCL_LIB" ] || { printf 'FATAL: shared HCL lexer not found at %s\n' "$HCL_LIB" >&2; exit 2; }
# shellcheck source=../../../tests/scripts/lib/hcl-effective-text.sh
. "$HCL_LIB" || { printf 'FATAL: could not source %s\n' "$HCL_LIB" >&2; exit 2; }

CHILD=0
SRC_OVERRIDE=""
PLUGIN_OVERRIDE=""
SCRATCH_OVERRIDE=""
MUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --child) CHILD=1; shift ;;
    --src-tf) [ $# -ge 2 ] || exit 2; SRC_OVERRIDE="$2"; shift 2 ;;
    --plugin-dir) [ $# -ge 2 ] || exit 2; PLUGIN_OVERRIDE="$2"; shift 2 ;;
    --scratch-parent) [ $# -ge 2 ] || exit 2; SCRATCH_OVERRIDE="$2"; shift 2 ;;
    --mut) [ $# -ge 2 ] || exit 2; MUT="$2"; shift 2 ;;
    *) printf 'FATAL: unknown argument\n' >&2; exit 2 ;;
  esac
done
if [ "$CHILD" = 0 ] && { [ -n "$SRC_OVERRIDE" ] || [ -n "$PLUGIN_OVERRIDE" ] || [ -n "$SCRATCH_OVERRIDE" ] || [ -n "$MUT" ]; }; then
  printf 'FATAL: --src-tf/--plugin-dir/--scratch-parent/--mut are child-only\n' >&2
  exit 2
fi
# An unknown mutation name would silently run as a pristine child, so the allowlist is closed.
case "$MUT" in
  ""|positional-import|no-shim|skip-repair|zero-match-selector|no-serial-bump|repaired-uses-loss-plan|no-canary) : ;;
  *) printf 'FATAL: unknown --mut name\n' >&2; exit 2 ;;
esac

CI_MODE=0
if [ "${CI:-}" = "true" ] || [ "${GITHUB_ACTIONS:-}" = "true" ]; then CI_MODE=1; fi

LUKS_TF="${SRC_OVERRIDE:-$DIR/inngest-redis-luks.tf}"
ADR_REL="knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md"
RUNBOOK_REL="knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md"
FILTER="$REPO_ROOT/tests/scripts/lib/destroy-guard-filter-web-platform.jq"
SUITE_NAME="inngest-redis-luks-import-rehearsal.test.sh"
ADDR="random_password.inngest_redis_luks"

# ---------------------------------------------------------------------------------------------------
# Counters, verdict helpers and the pre-print funnel. `cases` is the INDEPENDENT case counter: it is
# incremented at every chk call site and never inside pass()/fail(), so a neutered verdict helper cannot
# also neuter the accounting that notices it.
# ---------------------------------------------------------------------------------------------------
passes=0
fails=0
cases=0
dyn_cases=0
VALUE=""
LEAKED=0

# Every emission goes through _emit: a message containing the synthetic value is replaced, never printed
# (a pre-print check, so there is no tee/flush race).
_emit() {
  local msg="$1"
  if [ -n "$VALUE" ]; then
    case "$msg" in
      *"$VALUE"*) LEAKED=1; msg="[message withheld: it contained the synthetic value]" ;;
    esac
  fi
  printf '%s\n' "$msg" >&2
}
say() { _emit "$1"; }
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); _emit "FAIL: $1"; }
# chk NAME CMD...: runs CMD (no pipes), passes when it exits 0.
chk() {
  local name="$1"
  shift
  cases=$((cases + 1))
  if "$@"; then pass; else fail "$name"; fi
}
child_handoff_ok() {
  [ -z "$SCRATCH_OVERRIDE" ] && return 0
  [ -s "${SCRATCH_OVERRIDE}.value" ] || return 1
  case "$SCR" in "$SCRATCH_OVERRIDE"/*) return 0 ;; *) return 1 ;; esac
}
dchk() {
  dyn_cases=$((dyn_cases + 1))
  chk "$@"
}

# Reporter self-test in a SUBSET shell: one pass() adds one pass and no fail, one fail() one fail and no
# pass. Reports through printf + exit 2, never through fail(), the function under suspicion.
selftest_got="$( passes=0; fails=0; pass; fail selftest 2>/dev/null; printf '%s/%s' "$passes" "$fails" )"
if [ "$selftest_got" != "1/1" ]; then
  printf 'INSTRUMENT FAIL - %s: pass()/fail() self-test got %s, want 1/1\n' "$SUITE_NAME" "$selftest_got" >&2
  exit 2
fi

# chk owns its own verdict, so the pass/fail control above cannot see it going silent: drive it once with a
# command that must fail and once with one that must pass, and require both counters and the case tally to move.
chk_got="$( passes=0; fails=0; cases=0; chk selftest false 2>/dev/null; chk selftest true; printf '%s/%s/%s' "$passes" "$fails" "$cases" )"
if [ "$chk_got" != "1/1/2" ]; then
  printf 'INSTRUMENT FAIL - %s: chk() self-test got passes/fails/cases=%s, want 1/1/2\n' "$SUITE_NAME" "$chk_got" >&2
  exit 2
fi

# xtrace would write the synthetic value to stderr: refuse to go any further if it is on.
case "$-" in
  *x*) fail "secret: xtrace is off"; exit 1 ;;
  *) chk "secret: xtrace is off" true ;;
esac

# _emit must withhold a message that contains the value: drive it once in a subshell (VALUE is set only there).
emit_got="$( VALUE=selftestvalue; LEAKED=0; _emit 'prefix selftestvalue suffix' 2>&1; printf '|%s' "$LEAKED" )"
case "$emit_got" in
  *selftestvalue*) emit_bad=1 ;;
  *) emit_bad=0 ;;
esac
if [ "$emit_bad" = 1 ] || [ "${emit_got##*|}" != "1" ]; then
  printf 'INSTRUMENT FAIL - %s: _emit did not withhold a message carrying the value\n' "$SUITE_NAME" >&2
  exit 2
fi

# A stray bare `terraform` call must fail loudly; the real binary is only reached by absolute path in tf().
terraform() { printf 'FATAL: bare terraform call\n' >&2; return 97; }

# Canonical fixture-dir guard (byte-identical to the tracked copies; plugins/soleur/test/fixture-dir-operand-assert.test.sh
# pins that). Every function below that writes under the scratch root asserts it is absolute first.
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

# ---------------------------------------------------------------------------------------------------
# STATIC SECTION (no terraform needed)
# ---------------------------------------------------------------------------------------------------
block="$(block_of "$LUKS_TF" random_password inngest_redis_luks)"
n_blocks="$(printf '%s\n' "$block" | grep -c '^resource[[:space:]]')"
chk "static: exactly one random_password.inngest_redis_luks block extracted" [ "$n_blocks" = "1" ]
if [ "$n_blocks" != "1" ]; then
  say "FATAL: no block to rehearse; fix the extraction before reading any further row"
  exit 1
fi
chk "static: length = 40 inside the extracted block" grep -Eq "^[[:space:]]+length[[:space:]]*=[[:space:]]*40${B4_TAIL}" <<<"$block"
chk "static: special = false inside the extracted block" grep -Eq "^[[:space:]]+special[[:space:]]*=[[:space:]]*false${B4_TAIL}" <<<"$block"
chk "static: prevent_destroy = true inside the extracted block" grep -Eq "^[[:space:]]+prevent_destroy[[:space:]]*=[[:space:]]*true${B4_TAIL}" <<<"$block"

# CLOSED SET: the rehearsal models exactly this attribute set imported with the provider's defaults, so any other
# line (another attribute, create_before_destroy, ignore_changes, count/for_each, a heredoc, a second lifecycle
# key) changes what the measurement means. If this fails, re-review the recovery claim in ADR-282 and the runbook row.
shape_rx="^[[:space:]]*$|^resource[[:space:]]+\"random_password\"[[:space:]]+\"inngest_redis_luks\"[[:space:]]*\{${B4_TAIL}"
shape_rx="$shape_rx|^[[:space:]]*length[[:space:]]*=[[:space:]]*40${B4_TAIL}|^[[:space:]]*special[[:space:]]*=[[:space:]]*false${B4_TAIL}"
shape_rx="$shape_rx|^[[:space:]]*lifecycle[[:space:]]*\{${B4_TAIL}|^[[:space:]]*prevent_destroy[[:space:]]*=[[:space:]]*true${B4_TAIL}|^[[:space:]]*\}${B4_TAIL}"
offshape="$(printf '%s\n' "$block" | grep -Ev -- "$shape_rx" || true)"
chk "static: the extracted block holds only the rehearsed attributes" [ -z "$offshape" ]

PARENT_LOCK="$DIR/.terraform.lock.hcl"
lock_entry="$(awk '/^provider "registry.terraform.io\/hashicorp\/random"/{p=1} p{print} p&&/^}/{exit}' "$PARENT_LOCK")"
LOCKED_VERSION="$(printf '%s\n' "$lock_entry" | sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\([0-9.]*\)".*/\1/p' | head -n 1)"
chk "static: the parent root lock pins hashicorp/random to an exact version" [ -n "$LOCKED_VERSION" ]
random_constraint="$(awk '/source[[:space:]]*=[[:space:]]*"hashicorp\/random"/{f=1;next} f&&/version/{print;exit}' "$DIR/main.tf" | sed -n 's/.*"\(.*\)".*/\1/p')"
chk "static: main.tf constrains hashicorp/random" [ -n "$random_constraint" ]

PIN_TF_VERSION="$(sed -n 's/^[[:space:]]*TERRAFORM_VERSION:[[:space:]]*"\([0-9.]*\)".*/\1/p' "$REPO_ROOT/.github/workflows/infra-validation.yml" | head -n 1)"
chk "static: the terraform pin is readable from infra-validation.yml" [ -n "$PIN_TF_VERSION" ]

adr_has_addendum() {
  grep -qF -- '## Addendum — 2026-10-19 (#9927 item 5' "$REPO_ROOT/$ADR_REL" \
    && grep -qF -- '**UNVERIFIED first.**' "$REPO_ROOT/$ADR_REL"
}
row_has_scope() { # ROW
  grep -qiF -- 'rehearsed' <<<"$1" && grep -qF -- 'local state' <<<"$1" && grep -qF -- 'R2-backed state' <<<"$1"
}
if [ "$CHILD" = 0 ]; then
  # The claim names its evidence: the ADR row and the runbook row each cite this suite, and neither keeps
  # the sentences this suite falsified. Anchored on the row start, never a line number.
  for doc in "$ADR_REL" "$RUNBOOK_REL"; do
    row="$(grep -F '| Terraform state entry lost |' "$REPO_ROOT/$doc" | head -n 1)"
    chk "doc: $(basename "$doc") loss-mode row exists" [ -n "$row" ]
    chk "doc: $(basename "$doc") row names $SUITE_NAME" grep -qF -- "$SUITE_NAME" <<<"$row"
    chk "doc: $(basename "$doc") row states its scope (rehearsed, local state, R2-backed state)" row_has_scope "$row"
    if grep -Eqi -- 'State-loss recovery (is|remains) UNVERIFIED|CANDIDATE recipe|NOT rehearsed|passes the HALT|not (yet )?(been )?(rehearsed|verified)|still unverified' <<<"$row"; then
      cases=$((cases + 1)); fail "doc: $(basename "$doc") row no longer carries the falsified sentences"
    else
      chk "doc: $(basename "$doc") row no longer carries the falsified sentences" true
    fi
  done
  chk "doc: the ADR carries the 2026-10-19 addendum with UNVERIFIED stated first" adr_has_addendum
fi

# ---------------------------------------------------------------------------------------------------
# TOOL GATE + PROVIDER ACQUISITION
# ---------------------------------------------------------------------------------------------------
SKIP_REASON=""
TF_BIN="$(command -v terraform 2>/dev/null || true)"
# command -v can return the stub function name; require an absolute executable path
case "$TF_BIN" in /*) : ;; *) TF_BIN="$(PATH="$PATH" type -P terraform 2>/dev/null || true)" ;; esac
JQ_BIN="$(type -P jq 2>/dev/null || true)"
if [ -z "$TF_BIN" ] || [ -z "$JQ_BIN" ]; then
  SKIP_REASON="terraform or jq not found"
else
  for need in timeout sha256sum stat cut find; do
    if ! type -P "$need" >/dev/null 2>&1; then SKIP_REASON="required tool not found: $need"; break; fi
  done
fi

SCR=""
CHILD_ROOT=""
cleanup() {
  [ -n "$SCR" ] && rm -rf -- "$SCR"
  [ -n "$CHILD_ROOT" ] && rm -rf -- "$CHILD_ROOT" "$CHILD_ROOT.value"
  return 0
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

TF_VERSION=""
PLATFORM=""
if [ -z "$SKIP_REASON" ]; then
  tf_version_out="$("$TF_BIN" version 2>/dev/null)"
  TF_VERSION="$(printf '%s\n' "$tf_version_out" | sed -n '1s/^Terraform v\([0-9.]*\).*/\1/p')"
  PLATFORM="$(printf '%s\n' "$tf_version_out" | sed -n 's/^on \(.*\)$/\1/p' | head -n 1)"
  if [ "$CI_MODE" = 1 ] && [ -n "$PIN_TF_VERSION" ] && [ "$TF_VERSION" != "$PIN_TF_VERSION" ]; then
    printf '[FATAL] CI terraform is %s but infra-validation.yml pins %s: the claim is scoped to the pinned version\n' "$TF_VERSION" "$PIN_TF_VERSION" >&2
    exit 1
  fi
  if [ "$CI_MODE" = 0 ] && [ -n "$PIN_TF_VERSION" ] && [ "$TF_VERSION" != "$PIN_TF_VERSION" ]; then
    say "note: local terraform $TF_VERSION differs from the CI pin $PIN_TF_VERSION"
  fi
fi

PLUGIN_DIR=""
REGISTRY_INIT=0
if [ -z "$SKIP_REASON" ]; then
  candidate="${PLUGIN_OVERRIDE:-${SOLEUR_TF_PLUGIN_DIR:-${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}}}"
  if [ -d "$candidate/registry.terraform.io/hashicorp/random/$LOCKED_VERSION/$PLATFORM" ]; then
    PLUGIN_DIR="$candidate"
  elif [ "$CI_MODE" = 1 ]; then
    REGISTRY_INIT=1
  else
    SKIP_REASON="no local hashicorp/random $LOCKED_VERSION package under $candidate"
  fi
fi

if [ -n "$SKIP_REASON" ] && [ "$CI_MODE" = 1 ]; then
  printf '[FATAL] %s and CI is set: refusing to skip the dynamic section silently\n' "$SKIP_REASON" >&2
  exit 1
fi
if [ -n "$SKIP_REASON" ] && [ "$CHILD" = 1 ]; then
  # A skipped child exits 0 like a healthy one, which would void every battery row that reads its verdict.
  printf '[FATAL] a child run cannot skip the dynamic section (%s)\n' "$SKIP_REASON" >&2
  exit 1
fi

# ---------------------------------------------------------------------------------------------------
# DYNAMIC SECTION
# ---------------------------------------------------------------------------------------------------
BLOCKED=""
RAN_DYNAMIC=0
FILTER_LOSS=""
FILTER_REPAIRED=""

# tf_env ARGS...: the one scrubbed environment every terraform-bearing process runs in (extra VAR=value
# words and the command follow). TMPDIR is a short path: the provider's unix socket lives under it.
tf_env() {
  env -i PATH="$PATH" HOME="$SCR/home" TMPDIR="$SCR/t" TF_IN_AUTOMATION=1 CHECKPOINT_DISABLE=1 \
    TF_LOG= TF_CLI_ARGS=-no-color SHIM_LOG="$SCR/argv.log" REAL_TF="$TF_BIN" "$@"
}

# tfd DIR ARGS...: run the shimmed terraform in DIR with a dead-port proxy (no network), no color and a bound.
# Output is redirected by the caller into files that are never printed.
tfd() {
  assert_fixture_dir "$SCR"
  local d="$1"
  shift
  ( cd "$d" && tf_env HTTPS_PROXY=http://127.0.0.1:9 timeout -k 5 120 "$TF_SHIM" "$@" )
}
tf() { tfd "$SCR/w" "$@"; }

build_root() { # DIR BLOCKTEXT
  mkdir -p "$1"
  {
    printf 'terraform {\n  required_providers {\n    random = {\n      source  = "hashicorp/random"\n      version = "%s"\n    }\n  }\n}\n\n' "$random_constraint"
    printf '%s\n' "$2"
  } > "$1/main.tf"
  printf '%s\n' "$lock_entry" > "$1/.terraform.lock.hcl"
}

init_root() { # DIR
  assert_fixture_dir "$SCR"
  if [ "$REGISTRY_INIT" = 1 ]; then
    # The registry is the only network touch. Three bounded attempts (60 s each, a sleep only BETWEEN attempts).
    local i
    for i in 1 2 3; do
      ( cd "$1" && tf_env timeout -k 5 60 "$TF_SHIM" init -backend=false -input=false -lockfile=readonly ) >"$SCR/out/init-$(basename "$1").out" 2>&1 && return 0
      [ "$i" -lt 3 ] && sleep $((i * 3))
    done
    return 1
  fi
  tfd "$1" init -backend=false -input=false -lockfile=readonly -plugin-dir="$PLUGIN_DIR" >"$SCR/out/init-$(basename "$1").out" 2>&1
}

digest_of_state() { # DIR -> 12 hex of sha256(result), never the value
  assert_fixture_dir "$SCR"
  tfd "$1" state pull >"$SCR/pull.json" 2>/dev/null
  jq -r '.resources[] | select(.type == "random_password") | .instances[0].attributes.result' "$SCR/pull.json" | sha256sum | cut -c1-12
}

# Env-route import: the value is read inside the child shell from the 0600 file and placed in
# TF_CLI_ARGS_import together with ALL the flags; it is never an argument of env(1) or of terraform.
do_import() { # DIR OUTFILE
  assert_fixture_dir "$SCR"
  if [ "$MUT" = "positional-import" ]; then
    ( cd "$1" && tf_env VF="$SCR/value" TF_SHIM="$TF_SHIM" \
        bash -c 'exec "$TF_SHIM" import -input=false random_password.inngest_redis_luks "$(<"$VF")"' ) >"$2" 2>&1
    return $?
  fi
  ( cd "$1" && tf_env VF="$SCR/value" TF_SHIM="$TF_SHIM" \
      bash -c 'TF_CLI_ARGS_import="-input=false random_password.inngest_redis_luks $(<"$VF")" exec "$TF_SHIM" import' ) >"$2" 2>&1
}

# repair_state NAME BUMP: state pull, special=false on the matching instance, serial += BUMP, push.
repair_state() {
  assert_fixture_dir "$SCR"
  local name="$1" bump="$2"
  tf state pull >"$SCR/cur.json" 2>"$SCR/out/pull.err"
  REPAIR_MATCHES="$(jq --arg n "$name" '[.resources[] | select(.type == "random_password" and .name == $n and .module == null)] | length' "$SCR/cur.json")"
  jq --arg n "$name" --argjson b "$bump" \
    '.serial += $b | (.resources[] | select(.type == "random_password" and .name == $n and .module == null) | .instances[0].attributes.special) = false' \
    "$SCR/cur.json" >"$SCR/fixed.json"
  tf state push "$SCR/fixed.json" >"$SCR/out/push.out" 2>&1
}

abs_paths() { [[ "$TF_BIN" == /* && "$TF_SHIM" == /* ]]; }

dynamic_section() {
  assert_fixture_dir "$SCR"
  mkdir -p "$SCR/w" "$SCR/out" "$SCR/shim" "$SCR/home" "$SCR/t"
  TF_SHIM="$SCR/shim/tfshim"
  if [ "$MUT" = "no-shim" ]; then
    TF_SHIM="$TF_BIN"
  else
    cat >"$SCR/shim/tfshim" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SHIM_LOG"
exec "$REAL_TF" "$@"
SHIM
    chmod 0700 "$SCR/shim/tfshim"
  fi
  : >"$SCR/argv.log"

  build_root "$SCR/w" "$block"
  init_root "$SCR/w"
  rc=$?
  dchk "dynamic: the provider installs from the lock" [ "$rc" = 0 ]
  if [ "$rc" != 0 ]; then BLOCKED="init"; return; fi
  if [ "$REGISTRY_INIT" = 1 ]; then
    # The registry was reached once; every later root and every battery child reads the package it installed.
    PLUGIN_DIR="$SCR/w/.terraform/providers"
    REGISTRY_INIT=0
  fi
  tf version >"$SCR/out/version.out" 2>&1
  dchk "dynamic: the resolved provider version equals the lock entry" grep -qF -- "v$LOCKED_VERSION" "$SCR/out/version.out"

  # --- mint ---------------------------------------------------------------------------------------
  tf apply -auto-approve -input=false >"$SCR/out/mint.out" 2>&1
  rc=$?
  dchk "dynamic: a synthetic value mints on local state" [ "$rc" = 0 ]
  if [ "$rc" != 0 ]; then
    # Nothing has been minted yet, so this output cannot carry the value.
    printf 'mint diagnostic (rc=%s, scratch path length %s):\n' "$rc" "${#SCR}" >&2
    head -n 15 "$SCR/out/mint.out" | cut -c1-240 >&2
  fi
  [ "$rc" = 0 ] || { BLOCKED="mint"; return; }
  tf state pull >"$SCR/pull.json" 2>/dev/null
  jq -r '.resources[] | select(.type == "random_password") | .instances[0].attributes.result' "$SCR/pull.json" >"$SCR/value"
  VALUE="$(<"$SCR/value")"
  # A battery child leaves its value where the parent can scan that child's own output for it.
  if [ -n "$SCRATCH_OVERRIDE" ]; then cp "$SCR/value" "${SCRATCH_OVERRIDE}.value"; fi
  # Without these two rows the leak scan and the leftover check can go inert while every row stays green.
  dchk "secret: the in-memory value is 40 characters (the withholding funnel has something to withhold)" [ "${#VALUE}" = 40 ]
  dchk "secret: a battery child handed its value to the parent and scratched under the parent's directory" child_handoff_ok
  dchk "dynamic: the minted value is 40 alphanumerics" grep -Eq '^[A-Za-z0-9]{40}$' "$SCR/value"
  PRE_DIGEST="$(digest_of_state "$SCR/w")"

  # --- loss ---------------------------------------------------------------------------------------
  rm -f "$SCR"/w/terraform.tfstate*
  dchk "dynamic: state loss leaves no state file" test ! -e "$SCR/w/terraform.tfstate"
  tf plan -detailed-exitcode -input=false -out="$SCR/loss.plan" >"$SCR/out/loss-plan.out" 2>&1
  rc=$?
  dchk "dynamic: the empty-state plan is plannable and wants to add one resource (control)" [ "$rc" = 2 ]
  tf show -json "$SCR/loss.plan" >"$SCR/loss.json" 2>/dev/null
  FILTER_LOSS="$(jq -f "$FILTER" "$SCR/loss.json" 2>/dev/null | jq -r '.luks_passphrase_rotations' 2>/dev/null)"
  dchk "dynamic: the real destroy-guard filter scores the state-loss plan >= 1" test "${FILTER_LOSS:-0}" -ge 1

  # --- import, not repaired ----------------------------------------------------------------------
  do_import "$SCR/w" "$SCR/out/import.out"
  rc=$?
  dchk "dynamic: the env-route import succeeds" [ "$rc" = 0 ]
  tf state pull >"$SCR/pull.json" 2>/dev/null
  special_imported="$(jq -r '.resources[] | select(.type == "random_password") | .instances[0].attributes.special' "$SCR/pull.json")"
  dchk "dynamic: import sets special = true (the provider hard-codes it)" [ "$special_imported" = "true" ]
  tf plan -detailed-exitcode -input=false >"$SCR/out/plan-imported.out" 2>&1
  rc=$?
  dchk "dynamic: plan after a plain import exits 1 (replacement refused)" [ "$rc" = 1 ]
  dchk "dynamic: plan after a plain import is refused by prevent_destroy" grep -qF -- 'Instance cannot be destroyed' "$SCR/out/plan-imported.out"
  if grep -qF -- 'forces replacement' "$SCR/out/plan-imported.out"; then say "note: plan_marks_special_forces_replacement=yes"; else say "note: plan_marks_special_forces_replacement=no"; fi
  tf apply -auto-approve -input=false >"$SCR/out/apply-imported.out" 2>&1
  rc=$?
  dchk "dynamic: apply on the imported state is refused" [ "$rc" = 1 ]
  dchk "dynamic: the refusal is prevent_destroy, not another failure" grep -qF -- 'Instance cannot be destroyed' "$SCR/out/apply-imported.out"
  dchk "dynamic: the key is unchanged after the refused apply" [ "$(digest_of_state "$SCR/w")" = "$PRE_DIGEST" ]

  # --- repair -------------------------------------------------------------------------------------
  tf state pull >"$SCR/stale.json" 2>/dev/null
  if [ "$MUT" != "skip-repair" ]; then
    sel="inngest_redis_luks"
    bump=1
    [ "$MUT" = "zero-match-selector" ] && sel="no_such_resource"
    [ "$MUT" = "no-serial-bump" ] && bump=0
    repair_state "$sel" "$bump"
    rc=$?
    dchk "dynamic: the repair selector matches exactly one instance" [ "${REPAIR_MATCHES:-0}" = "1" ]
    dchk "dynamic: the repaired state push is accepted" [ "$rc" = 0 ]
  fi
  tf plan -detailed-exitcode -input=false -out="$SCR/repaired.plan" >"$SCR/out/plan-repaired.out" 2>&1
  rc=$?
  dchk "dynamic: plan after the repair reports no changes" [ "$rc" = 0 ]
  dchk "dynamic: the value digest after the repair equals the pre-loss digest" [ "$(digest_of_state "$SCR/w")" = "$PRE_DIGEST" ]
  tf show -json "$SCR/repaired.plan" >"$SCR/repaired.json" 2>/dev/null
  filter_input="$SCR/repaired.json"
  [ "$MUT" = "repaired-uses-loss-plan" ] && filter_input="$SCR/loss.json"
  FILTER_REPAIRED="$(jq -f "$FILTER" "$filter_input" 2>/dev/null | jq -r '.luks_passphrase_rotations' 2>/dev/null)"
  dchk "dynamic: the real destroy-guard filter scores the repaired plan 0" [ "${FILTER_REPAIRED:-x}" = "0" ]
  tf state push "$SCR/stale.json" >"$SCR/out/push-stale.out" 2>&1
  rc=$?
  dchk "dynamic: a stale-serial push is refused without -force" test "$rc" != 0
  dchk "dynamic: the stale-serial refusal names the serial" grep -qiF -- 'serial' "$SCR/out/push-stale.out"
  tf plan -detailed-exitcode -input=false >"$SCR/out/plan-after-stale.out" 2>&1
  dchk "dynamic: the repaired state is intact after the refused stale push" test "$?" = 0

  # --- negative control: without prevent_destroy the same sequence mints a NEW key ---------------
  nc_block="$(printf '%s\n' "$block" | awk '/^[[:space:]]*lifecycle[[:space:]]*\{/{skip=1} !skip{print} skip&&/^[[:space:]]*\}/{skip=0}')"
  build_root "$SCR/nc" "$nc_block"
  init_root "$SCR/nc"
  dchk "dynamic: the negative-control fixture initialises" test "$?" = 0
  tfd "$SCR/nc" validate >"$SCR/out/nc-validate.out" 2>&1
  dchk "dynamic: the negative-control fixture is well formed" test "$?" = 0
  dchk "dynamic: the negative-control fixture has no prevent_destroy" test -z "$(printf '%s\n' "$nc_block" | grep -F prevent_destroy)"
  tfd "$SCR/nc" apply -auto-approve -input=false >"$SCR/out/nc-mint.out" 2>&1
  rc=$?
  dchk "dynamic: the negative-control fixture mints" [ "$rc" = 0 ]
  rm -f "$SCR"/nc/terraform.tfstate*
  do_import "$SCR/nc" "$SCR/out/nc-import.out"
  rc=$?
  dchk "dynamic: the negative-control import succeeds" [ "$rc" = 0 ]
  # The fixture imports the value minted in the main root, so its imported key must equal PRE_DIGEST; without this
  # the later "the key CHANGES" row would hold even if the apply did nothing.
  dchk "dynamic: the negative-control import holds the imported key" [ "$(digest_of_state "$SCR/nc")" = "$PRE_DIGEST" ]
  tfd "$SCR/nc" apply -auto-approve -input=false >"$SCR/out/nc-apply.out" 2>&1
  rc=$?
  dchk "dynamic: without prevent_destroy the imported state applies" [ "$rc" = 0 ]
  dchk "dynamic: without prevent_destroy the key CHANGES (prevent_destroy is the backstop)" test "$(digest_of_state "$SCR/nc")" != "$PRE_DIGEST"

  # --- import {} block route (characterization) ---------------------------------------------------
  ib_block="$(printf '%s\n\nvariable "recovery_passphrase" {\n  type      = string\n  sensitive = true\n}\n\nimport {\n  to = %s\n  id = var.recovery_passphrase\n}\n' "$block" "$ADDR")"
  build_root "$SCR/ib" "$ib_block"
  init_root "$SCR/ib"
  ( cd "$SCR/ib" && tf_env VF="$SCR/value" TF_SHIM="$TF_SHIM" \
      bash -c 'TF_VAR_recovery_passphrase="$(<"$VF")" exec timeout -k 5 120 "$TF_SHIM" plan -input=false' ) >"$SCR/out/ib-plan.out" 2>&1
  rc=$?
  dchk "dynamic: an import block plans a replacement and errors (it does NOT plan as a no-op)" [ "$rc" = 1 ]
  dchk "dynamic: the import block plan reports an import" grep -qF -- '1 to import' "$SCR/out/ib-plan.out"
  dchk "dynamic: the import block plan is refused by prevent_destroy" grep -qF -- 'Instance cannot be destroyed' "$SCR/out/ib-plan.out"

  # --- secret hygiene -----------------------------------------------------------------------------
  printf '%s' "canary-$$-$RANDOM" >"$SCR/canary.value"
  [ "$MUT" = "no-canary" ] || cp "$SCR/canary.value" "$SCR/out/canary.out"
  dchk "secret: the scan finds a known canary written through the same path (positive control)" grep -rqF -f "$SCR/canary.value" "$SCR/out"
  # Terraform echoes the id on import and an import block prints it in the plan: those captures hold the value by
  # design and are never printed. Reported as observations on THIS terraform version, not asserted.
  if grep -qF -f "$SCR/value" "$SCR/out/import.out"; then say "note: terraform_import_echoes_the_value=yes"; else say "note: terraform_import_echoes_the_value=no"; fi
  if grep -qF -f "$SCR/value" "$SCR/out/ib-plan.out"; then say "note: import_block_plan_prints_value=yes"; else say "note: import_block_plan_prints_value=no"; fi
  dchk "secret: no other terraform output capture contains the synthetic value" \
    test "$(grep -rlF -f "$SCR/value" "$SCR/out" --exclude=import.out --exclude=nc-import.out --exclude=ib-plan.out | wc -l)" = "0"
  dchk "secret: the argv shim log exists and is non-empty" test -s "$SCR/argv.log"
  if [ -s "$SCR/argv.log" ]; then
    dchk "secret: shim argv log never contains the synthetic value" test "$(grep -cF -f "$SCR/value" "$SCR/argv.log")" = "0"
  else
    dchk "secret: shim argv log never contains the synthetic value" false
  fi
  dchk "secret: the value file is mode 0600" test "$(stat -c '%a' "$SCR/value")" = "600"
  dchk "secret: terraform and the argv shim are reached by absolute path only" abs_paths
  RAN_DYNAMIC=1
}

SCR_PARENT="${SCRATCH_OVERRIDE:-${TMPDIR:-/tmp}}"
# The provider's unix socket path lives under the scratch tree and is limited to about 108 bytes.
if [ -z "$SCRATCH_OVERRIDE" ] && [ "${#SCR_PARENT}" -gt 40 ]; then SCR_PARENT=/tmp; fi
if [ -z "$SKIP_REASON" ]; then
  assert_fixture_dir "$SCR_PARENT"
  # sweep stale scratch of our own prefix (SIGKILL and timeout kills never run the trap); the parent only
  if [ "$CHILD" = 0 ]; then
    find "$SCR_PARENT" -maxdepth 1 -type d -name 'inngest-luks-import-rehearsal.*' -mmin +30 -exec rm -rf {} + 2>/dev/null
  fi
  SCR="$(mktemp -d "$SCR_PARENT/inngest-luks-import-rehearsal.XXXXXXXX")"
  dynamic_section
fi

# ---------------------------------------------------------------------------------------------------
# MUTATION BATTERY (parent only)
# ---------------------------------------------------------------------------------------------------
if [ "$CHILD" = 0 ] && [ "$RAN_DYNAMIC" = 1 ]; then
  RESOLVED_PLUGIN="$PLUGIN_DIR"
  mkdir -p "$SCR/mut"
  # A child nests its own scratch tree, and the provider's unix socket under it is limited to about 108 bytes, so
  # the children get a short root outside the (possibly long) parent scratch path.
  CHILD_ROOT="$(mktemp -d /tmp/irl-c.XXXXXX)"
  assert_fixture_dir "$CHILD_ROOT"
  CHILD_LEFTOVER=0
  CHILD_LEAK=0

  # Every child scratches under $CHILD_ROOT, so a child that failed to clean up after itself is visible here.
  run_child() { # OUTNAME ARGS...
    local out="$SCR/mut/$1.out"
    shift
    timeout -k 5 240 bash "$SELF" --child --plugin-dir "$RESOLVED_PLUGIN" --scratch-parent "$CHILD_ROOT" "$@" >"$out" 2>&1
    CHILD_RC=$?
    # A healthy-control child that fails must say why: its output is already scanned for the value and withheld by _emit.
    case "$out" in
      */pristine-*.out|*/reordered.out)
        if [ "$CHILD_RC" != 0 ]; then
          printf 'child diagnostic (%s, rc=%s):\n' "${out##*/}" "$CHILD_RC" >&2
          head -n 12 "$out" | cut -c1-240 >&2
        fi ;;
    esac
    if [ -n "$(ls -A "$CHILD_ROOT" 2>/dev/null)" ]; then CHILD_LEFTOVER=1; fi
    if [ -s "$CHILD_ROOT.value" ]; then
      if grep -qF -f "$CHILD_ROOT.value" "$out"; then CHILD_LEAK=1; fi
      rm -f "$CHILD_ROOT.value"
    fi
  }
  wellformed() { # FILE: the mutated block must still parse, or a RED is a syntax error, not evidence
    tfd "$SCR/w" fmt -write=false -list=false - <"$1" >/dev/null 2>&1
  }
  # The pristine control brackets the battery (one child before the first row, one after the last): the
  # per-row cost is a full terraform sequence and the suite shares a 360 s per-suite bound.
  PRISTINE_STATE=""
  pristine_ok() {
    run_child "pristine-$1"
    PRISTINE_STATE="$CHILD_RC"
    # rc 0 alone is not a control: it must also have RUN the whole dynamic section (a skipped child exits 0 too).
    if [ "$CHILD_RC" = 0 ] && grep -qF -- "RAN $dyn_cases dynamic assertions" "$SCR/mut/pristine-$1.out"; then return 0; fi
    PRISTINE_STATE=1
    return 1
  }
  # The verdict a battery row turns on, kept pure so it can be driven with synthetic inputs below.
  child_caught() { # RC OUTFILE WANT
    [ "$1" = 1 ] && grep -qF -- "FAIL: $3" "$2"
  }
  probe_child_caught() {
    printf 'FAIL: right name\n' >"$SCR/mut/probe.out"
    child_caught 1 "$SCR/mut/probe.out" "right name" \
      && ! child_caught 1 "$SCR/mut/probe.out" "other name" \
      && ! child_caught 2 "$SCR/mut/probe.out" "right name" \
      && ! child_caught 0 "$SCR/mut/probe.out" "right name"
  }
  # caught NAME EXPECTED_FAILING_ASSERTION ARGS...
  caught() {
    local name="$1" want="$2"
    shift 2
    cases=$((cases + 1))
    if [ "$PRISTINE_STATE" != 0 ]; then fail "battery $name: the pristine control child did not exit 0"; return; fi
    run_child "$name" "$@"
    if child_caught "$CHILD_RC" "$SCR/mut/$name.out" "$want"; then pass; else fail "battery $name: want exit 1 with FAIL: $want (got rc=$CHILD_RC)"; fi
  }

  printf '%s\n' "$block" | sed '/prevent_destroy/d' >"$SCR/mut/no-pd.tf"
  printf '%s\n' "$block" | sed 's/special\([[:space:]]*\)=[[:space:]]*false/special\1= true/' >"$SCR/mut/special-true.tf"
  { sed '$d' <<<"$block"; printf '  upper = true\n}\n'; } >"$SCR/mut/extra-attr.tf"
  cat >"$SCR/mut/reordered.tf" <<'HCL'
resource "random_password" "inngest_redis_luks" {
  # reordered, commented and re-indented: the guard must not depend on the canonical text
  lifecycle {
      prevent_destroy = true
  }

  special = false
  length  = 40
}
HCL
  for f in no-pd special-true extra-attr reordered; do
    cases=$((cases + 1))
    if wellformed "$SCR/mut/$f.tf"; then pass; else fail "battery fixture $f is not well formed HCL"; fi
  done

  cases=$((cases + 1))
  if pristine_ok before; then pass; else fail "battery: the opening pristine control child did not exit 0 (rc=$CHILD_RC)"; fi
  caught drop-prevent-destroy "static: prevent_destroy = true inside the extracted block" --src-tf "$SCR/mut/no-pd.tf"
  caught special-true "static: special = false inside the extracted block" --src-tf "$SCR/mut/special-true.tf"
  caught extra-attribute "static: the extracted block holds only the rehearsed attributes" --src-tf "$SCR/mut/extra-attr.tf"
  caught skip-repair "dynamic: plan after the repair reports no changes" --mut skip-repair
  caught no-serial-bump "dynamic: the repaired state push is accepted" --mut no-serial-bump
  caught zero-match-selector "dynamic: the repair selector matches exactly one instance" --mut zero-match-selector
  caught positional-import "secret: shim argv log never contains the synthetic value" --mut positional-import
  caught no-canary "secret: the scan finds a known canary written through the same path (positive control)" --mut no-canary
  caught no-shim "secret: the argv shim log exists and is non-empty" --mut no-shim
  caught repaired-uses-loss-plan "dynamic: the real destroy-guard filter scores the repaired plan 0" --mut repaired-uses-loss-plan

  chk "battery: the caught verdict accepts only rc 1 with the named FAIL line" probe_child_caught

  cases=$((cases + 1))
  run_child reordered --src-tf "$SCR/mut/reordered.tf"
  if [ "$CHILD_RC" = 0 ]; then pass; else fail "battery reordered: the non-canonical but valid block must still pass (rc=$CHILD_RC)"; fi

  cases=$((cases + 1))
  timeout -k 5 120 bash -x "$SELF" --child --plugin-dir "$RESOLVED_PLUGIN" >"$SCR/mut/xtrace.out" 2>&1
  xrc=$?
  # The child must refuse BEFORE minting: no RAN line and no traced assignment of a 40-character value.
  # It must be the xtrace guard that stopped it, not the _emit self-test tripping over a traced value.
  if [ "$xrc" = 1 ] && grep -qF -- 'FAIL: secret: xtrace is off' "$SCR/mut/xtrace.out" \
    && ! grep -qF -- 'INSTRUMENT FAIL' "$SCR/mut/xtrace.out" \
    && ! grep -qE '^RAN [0-9]+ dynamic|VALUE=[A-Za-z0-9]{40}' "$SCR/mut/xtrace.out"; then pass; else fail "battery xtrace: want exit 1 with FAIL: secret: xtrace is off (got rc=$xrc)"; fi

  # Positive control for the child-leak scan: the same grep must fire on a planted copy of the value.
  printf 'planted %s\n' "$(<"$SCR/value")" >"$SCR/mut/planted.out"
  chk "battery: the child-leak scan detects a planted value (positive control)" grep -qF -f "$SCR/value" "$SCR/mut/planted.out"

  cases=$((cases + 1))
  if pristine_ok after; then pass; else fail "battery: the closing pristine control child did not exit 0 (rc=$CHILD_RC)"; fi

  chk "secret: no battery child left its scratch directory behind" [ "$CHILD_LEFTOVER" = "0" ]
  chk "secret: no battery child printed its own synthetic value" [ "$CHILD_LEAK" = "0" ]
fi

# ---------------------------------------------------------------------------------------------------
# VERDICT
# ---------------------------------------------------------------------------------------------------
if [ "$CHILD" = 0 ] && [ -n "$SKIP_REASON" ]; then
  say "SKIPPED the dynamic section: $SKIP_REASON (static section ran: $cases cases)"
fi
if [ "$RAN_DYNAMIC" = 1 ]; then
  printf 'RAN %s dynamic assertions\n' "$dyn_cases"
fi
if [ "$CI_MODE" = 1 ] && [ "$RAN_DYNAMIC" != 1 ]; then
  printf '[FATAL] CI is set but the dynamic section did not run (blocked by: %s)\n' "${BLOCKED:-unknown}" >&2
  exit 1
fi
if [ -n "$BLOCKED" ]; then
  say "dynamic section blocked by: $BLOCKED"
  cases=$((cases + 1))
  fails=$((fails + 1))
fi
if [ "$LEAKED" != 0 ]; then
  printf 'FAIL: the synthetic value reached this suite output\n' >&2
  cases=$((cases + 1))
  fails=$((fails + 1))
fi
# Accounting identity, reported through printf + exit (never through fail): a verdict helper that drops a
# verdict leaves passes + fails short of the independently counted cases.
if [ $((passes + fails)) -ne "$cases" ]; then
  printf '[FATAL] accounting: passes (%s) + fails (%s) != cases (%s): a verdict was dropped\n' "$passes" "$fails" "$cases" >&2
  exit 1
fi
# The dynamic assertion count is pinned exactly: a deleted dynamic row must not read as a healthy run.
DYN_EXPECTED=41
if [ "$RAN_DYNAMIC" = 1 ] && [ "$dyn_cases" -ne "$DYN_EXPECTED" ]; then
  printf '[FATAL] dynamic count drift: %s dynamic assertions ran but DYN_EXPECTED is %s\n' "$dyn_cases" "$DYN_EXPECTED" >&2
  exit 1
fi

# Floor, pinned EXACTLY to the measured count of the parent run (a loose floor is attack budget).
if [ "$CHILD" = 0 ] && [ "$RAN_DYNAMIC" = 1 ]; then
  MIN_CASES=81
  if [ "$cases" -ne "$MIN_CASES" ]; then
    printf '[FATAL] floor drift: %s cases ran but MIN_CASES is %s - re-measure and set MIN_CASES=%s\n' "$cases" "$MIN_CASES" "$cases" >&2
    exit 1
  fi
fi

printf '%s: %s passed, %s failed (%s cases)\n' "$SUITE_NAME" "$passes" "$fails" "$cases"
[ "$fails" = 0 ]
