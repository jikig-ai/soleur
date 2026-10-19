#!/usr/bin/env bash
#
# Assertion pin for the `Verify peer deploy completion` step in
# .github/workflows/web-platform-release.yml (#8743, plan
# 2026-10-19-fix-web2-plugin-mount-fchmodat2 Phase 3 / Guard 1 / AC5).
#
# The step is the fail-closed gate that delivers a `deploy-peer` host's ASYNC
# verdict into the release run result: it polls the same
# deploy.soleur.ai/hooks/deploy-status endpoint on the same STATUS_POLL_*
# budget and requires every EXPECTED peer — WEB_HOST_PRIVATE_IPS minus the
# 10.0.1.10 deploy. ingress host — to report .peers["<ip>"].exit_code == 0
# with .tag == v$VERSION. The assertions below pin, against the extracted step
# block (never the whole file, so a token elsewhere cannot produce a green
# read):
#   * the step exists and sits AFTER `Verify deploy script completion`;
#   * the expected-peer derivation reads "$WEB_HOST_PRIVATE_IPS" and subtracts
#     exactly the 10.0.1.10 ingress literal — no other 10.0.1.* literal may
#     appear (a hardcoded peer IP means the list stopped deriving);
#   * the jq field paths consumed: .peers → .[$ip] → .exit_code / .tag /
#     .error / .reason, plus the object-shape guard on the slot;
#   * the sanctioned async-poll contract: -1/-2/-3/-99 keep polling,
#     exit_code==0 on a stale tag keeps polling, everything else exits 1;
#   * the FAIL-CLOSED arms (::error::peer … + exit 1, and the budget-exhausted
#     "did not report completion" red) — a warn-only arm reproduces the exact
#     silent-failure class this gate exists to kill (CTO ruling 2026-10-19).
#
# Scope boundary: the VALUE of WEB_HOST_PRIVATE_IPS is bound to var.web_hosts
# by web-hosts-fanout-parity.test.sh — this suite does not re-assert that.
# What it pins is (a) that exactly ONE env-shaped declaration exists in the
# file and sits at job-env indentation (a second copy desyncs the expected-peer
# derivation and also breaks cutover-inngest-workflow.test.sh's dedup-less
# CANON_RELEASE extraction), and (b) that the step derives from it.
#
# A self-test block re-invokes this suite on mutated workflow copies through
# the PRG_WORKFLOW seam and requires each RED row to be red for its NAMED
# reason (the Guard-1 mutation matrix). A row that does not LAND is a harness
# failure, never a pass.
#
# Run: bash apps/web-platform/infra/web-platform-release-peer-gate.test.sh
# Registered in .github/workflows/infra-validation.yml (filesystem registration:
# presence under apps/web-platform/infra/**.test.sh is the roster).

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PRG_* are seams of the SUITE (the self-test rows below feed mutated copies through them).
WORKFLOW="${PRG_WORKFLOW:-${DIR}/../../../.github/workflows/web-platform-release.yml}"

passes=0
fails=0
checks=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

[ -f "$WORKFLOW" ] || { echo "FAIL: workflow not found at $WORKFLOW" >&2; exit 1; }

# --- The step block, extracted by step-name: from `- name: Verify peer deploy
# completion` through the next same-indent `- name:` (or EOF). ---
STEP="$(awk '
  /^      - name: Verify peer deploy completion$/ {in_step=1}
  in_step && /^      - name: / && $0 !~ /Verify peer deploy completion/ {in_step=0}
  in_step {print}
' "$WORKFLOW")"

assert_step() { # assert_step <name> <fixed string that must appear in the step block>
  checks=$((checks + 1))
  if grep -qF -- "$2" <<<"$STEP"; then pass; else fail "$1 (missing from the Verify peer deploy completion step: $2)"; fi
}
assert_step_re() { # assert_step_re <name> <ERE that must match the step block>
  checks=$((checks + 1))
  if grep -qE -- "$2" <<<"$STEP"; then pass; else fail "$1 (missing from the Verify peer deploy completion step: /$2/)"; fi
}

# --- File-level pins -------------------------------------------------------

checks=$((checks + 1))
if [ -n "$STEP" ]; then pass
else fail "step 'Verify peer deploy completion' not found in $WORKFLOW (empty extraction — renamed or deleted)"; fi

# Exactly ONE env-shaped declaration in the file: the job-level copy shared by
# `Deploy via webhook` (peers payload) and this step (expected-peer derivation).
checks=$((checks + 1))
copies="$(grep -cE 'WEB_HOST_PRIVATE_IPS:[[:space:]]*"' "$WORKFLOW" || true)"
if [ "$copies" -eq 1 ]; then pass
else fail "expected exactly 1 WEB_HOST_PRIVATE_IPS declaration in web-platform-release.yml (the job-level canonical copy), found $copies — a second copy desyncs the peer-gate derivation and breaks cutover-inngest-workflow.test.sh's dedup-less CANON_RELEASE extraction"; fi

# The declaration must sit at JOB-env indentation (6 spaces). A step-level
# re-declaration would shadow it for one step only.
checks=$((checks + 1))
if grep -qE '^      WEB_HOST_PRIVATE_IPS:[[:space:]]*"' "$WORKFLOW"; then pass
else fail "WEB_HOST_PRIVATE_IPS is not declared at job-env indentation — the peer gate must inherit it from the deploy job's env"; fi

# Ordering: the gate must poll AFTER `Verify deploy script completion` — the
# peer's deploy starts when web-1's ends, so polling earlier can only burn
# budget on the pre-fan-out state.
checks=$((checks + 1))
script_ln="$(grep -nF -- '- name: Verify deploy script completion' "$WORKFLOW" | head -1 | cut -d: -f1)"
peer_ln="$(grep -nF -- '- name: Verify peer deploy completion' "$WORKFLOW" | head -1 | cut -d: -f1)"
if [ -n "$script_ln" ] && [ -n "$peer_ln" ] && [ "$peer_ln" -gt "$script_ln" ]; then pass
else fail "ordering: 'Verify peer deploy completion' (line ${peer_ln:-absent}) must follow 'Verify deploy script completion' (line ${script_ln:-absent})"; fi

# --- Step-level pins -------------------------------------------------------

assert_step "superseded gate" "if: steps.ordering.outputs.superseded != 'true'"
assert_step "expected-peer derivation reads the shared env" '"$WEB_HOST_PRIVATE_IPS"'
assert_step "ingress exclusion" "grep -vxF '10.0.1.10'"

# Anti-hardcode: the only 10.0.1.* literal allowed inside the step is the
# ingress IP it subtracts. Any second literal is a hardcoded peer.
checks=$((checks + 1))
ip_literals="$(grep -oE '10\.0\.1\.[0-9]+' <<<"$STEP" | sort -u | paste -sd, - || true)"
if [ "$ip_literals" = "10.0.1.10" ]; then pass
else fail "expected-peer derivation: the step may contain exactly one 10.0.1.* literal (the 10.0.1.10 ingress exclusion); found [$ip_literals] — a hardcoded peer IP means the list no longer derives from WEB_HOST_PRIVATE_IPS"; fi

# The jq field paths the step consumes (the .peers["<ip>"] contract of
# cat-deploy-state.sh's merge): slot extraction, then per-slot fields.
assert_step "jq .peers map read" '.peers |'
assert_step "jq per-IP slot read" '.[$ip]'
assert_step "jq --arg ip binding" '--arg ip'
assert_step "jq slot shape guard" 'type == "object"'
assert_step "jq .error slot consumed" '.error // ""'
assert_step "jq .exit_code slot consumed" '.exit_code // -99'
assert_step "jq .tag slot consumed" '.tag // ""'
assert_step "jq .reason slot consumed" '.reason // "unknown"'

# Same endpoint, same budget as the sibling step.
assert_step "polls the deploy-status endpoint" 'https://deploy.soleur.ai/hooks/deploy-status'
assert_step "polls on the shared STATUS budget" 'seq 1 "$STATUS_POLL_MAX_ATTEMPTS"'
assert_step "poll interval" 'sleep "$STATUS_POLL_INTERVAL_S"'

# The async-poll contract: in-flight / no-prior / corrupt / verdict-absent are
# NEVER terminal; a peer exit 0 on an older tag keeps polling; only a non-zero
# exit or an error slot fails — and the failure is CLOSED (::error:: + exit 1).
assert_step "sanctioned async-poll sentinels" '-1|-2|-3|-99)'
assert_step "pass requires the peer's tag to be this release" '= "v$VERSION"'
assert_step "fail-closed peer annotation" '::error::peer '
assert_step "budget-exhaustion annotation" 'did not report completion for v$VERSION'
assert_step "terminal exit" 'exit 1'
assert_step "vacuous-green single-host arm" 'no expected peers'

# Vacuity floor: deleting rows must not read as a pass. Direct printf + exit 1,
# NEVER through fail() (ADR-193): a floor enforced through the machinery it
# detects cannot witness that machinery neutered — this is the shape
# scripts/guard-vacuity-floor.test.sh scores FIRES.
if [[ "$checks" -lt 20 ]]; then
  printf 'FAIL: vacuity floor: only %s assertions ran (expected >= 20) — the step extraction or assertion helpers lost rows\n' "$checks" >&2
  exit 1
fi

# --- Self-test: the pins above must go RED on the edits they exist to catch.
# Each mutant is a COPY of the real workflow fed through the PRG_WORKFLOW seam;
# the suite re-invokes itself with PRG_SELFTEST=1 so rows cannot recurse. ---
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
if [ -z "${PRG_SELFTEST:-}" ]; then
  MUT="$(mktemp -d "${TMPDIR:-/var/tmp}/prg-mut.XXXXXXXX")" || { echo "FAIL: mktemp for the self-test" >&2; exit 2; }
  assert_fixture_dir "$MUT"
  trap 'rm -rf "$MUT"' EXIT
  # prg_row <name> <expect red|green> <sed-script> [<message the RED run must print>]
  rows_run=0
  prg_row() {
    local name="$1" expect="$2" script="$3" want="${4:-}" rc
    rows_run=$((rows_run + 1))
    assert_fixture_dir "$MUT"
    cp "$WORKFLOW" "$MUT/wf.yml" || { fail "self-test $name: could not copy the workflow"; return; }
    cp "$MUT/wf.yml" "$MUT/pristine"
    sed -E -i "$script" "$MUT/wf.yml"
    if cmp -s "$MUT/wf.yml" "$MUT/pristine"; then fail "self-test $name: the mutation did not land"; return; fi
    PRG_SELFTEST=1 PRG_WORKFLOW="$MUT/wf.yml" \
      bash "${BASH_SOURCE[0]}" > "$MUT/out" 2>&1
    rc=$?
    # A RED row must be red for the reason it names: a harness fault also exits non-zero.
    if [ "$expect" = red ] && [ "$rc" -ne 0 ] && [ -n "$want" ] && ! grep -qF -- "$want" "$MUT/out"; then
      fail "self-test $name: red, but not for the named reason [$want] ($(head -c 200 "$MUT/out" | tr '\n' ' '))"
    elif { [ "$expect" = red ] && [ "$rc" -ne 0 ]; } || { [ "$expect" = green ] && [ "$rc" -eq 0 ]; }; then pass
    else fail "self-test $name: expected $expect, the suite exited $rc ($(head -c 200 "$MUT/out" | tr '\n' ' '))"; fi
  }
  # M1: the gate renamed — the step extraction must empty, never silently match nothing.
  prg_row "step-renamed" red 's/Verify peer deploy completion/Verify peer verdict/' 'not found'
  # M2: the .peers map renamed — the jq-path pin must catch it.
  prg_row "peers-path-renamed" red 's/\.peers \|/.peer_status |/' '.peers'
  # M3: the ingress subtraction removed — the expected set would silently become the whole fleet.
  prg_row "ingress-exclusion-removed" red "s/grep -vxF '10\\.0\\.1\\.10'/cat/" '10.0.1.10'
  # M4: the verdict demoted to a warning — the fail-open class the gate exists to kill.
  prg_row "fail-open" red 's/::error::peer /::warning::peer /g' '::error::peer'
  # M5: the budget-exhaustion arm reworded away.
  prg_row "budget-arm-neutered" red 's/did not report completion/reported completion/' 'did not report completion'
  # M6: the sanctioned sentinels narrowed — -2/-3 would become terminal-fail.
  prg_row "sentinels-narrowed" red 's/-1\|-2\|-3\|-99\)/-1|-99)/' '-1|-2|-3|-99)'
  # M7: an unpinned log string may change freely — GREEN control.
  prg_row "unpinned-text" green 's/endpoint not ready/endpoint warming/'
  # The self-test's own floor: deleting rows must not read as a pass.
  [ "$rows_run" -eq 7 ] || fail "self-test: $rows_run rows ran, expected exactly 7 — a row was deleted or added without restating the floor"
fi

total=$((passes + fails))
echo "web-platform-release-peer-gate: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
