#!/usr/bin/env bash
# Fixture tests for the inngest-bootstrap tag-driven workflow_dispatch invariant (#4692).
#
# Two groups:
#   1. YAML shape gates — structural assertions on
#      `.github/workflows/build-inngest-bootstrap-image.yml` (RED before the
#      workflow edit, GREEN after).
#   2. resolve-tag behavior — runs the extracted guard against synthetic
#      (event, github_ref, inputs_ref) triples. workflow_dispatch cannot be
#      live-triggered on a feature branch (it resolves on the default branch
#      only), so this unit test is the pre-merge verification of the invariant.
#
# Plus a producer/consumer parity gate: the guard's post-strip regex MUST be
# byte-identical to the consumer drift-guard's regex in
# `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` (#4676 AC6),
# so the two cannot silently drift apart.

set -uo pipefail
export LC_ALL=C

SCRIPT_DIR=$(cd "$(dirname "$0")/../../.." && pwd)
GUARD="$SCRIPT_DIR/.github/scripts/inngest-bootstrap-tag-guard.sh"
WORKFLOW="$SCRIPT_DIR/.github/workflows/build-inngest-bootstrap-image.yml"
CONSUMER="$SCRIPT_DIR/apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh"
[[ -f "$GUARD" ]]    || { echo "FAIL: $GUARD not found"; exit 1; }
[[ -f "$WORKFLOW" ]] || { echo "FAIL: $WORKFLOW not found"; exit 1; }
[[ -f "$CONSUMER" ]] || { echo "FAIL: $CONSUMER not found"; exit 1; }

# Canonical stripped-tag regex literal — the single source of truth that the
# guard's resolve-tag check AND the consumer drift-guard must both contain.
STRIPPED_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'
# Canonical full-ref validator literal — the workflow's inline pre-checkout
# validate step (the trusted-tree gate) must contain this verbatim.
INLINE_RE='^vinngest-v[0-9]+\.[0-9]+\.[0-9]+$'

PASS=0
FAIL=0

check_yaml_token() {
  # PASS when the workflow contains the literal token (grep -F).
  local name="$1" needle="$2"
  if grep -F -q -- "$needle" "$WORKFLOW"; then
    echo "PASS [$name]"
    PASS=$((PASS + 1))
  else
    echo "FAIL [$name]: workflow does not contain literal token: $needle"
    FAIL=$((FAIL + 1))
  fi
}

check_yaml_absent() {
  # PASS when the workflow does NOT contain the literal token.
  local name="$1" needle="$2"
  if grep -F -q -- "$needle" "$WORKFLOW"; then
    echo "FAIL [$name]: workflow still contains forbidden token: $needle"
    FAIL=$((FAIL + 1))
  else
    echo "PASS [$name]"
    PASS=$((PASS + 1))
  fi
}

assert_resolve() {
  # Args: <name> <event> <github_ref> <inputs_ref> <expected|FAIL>
  local name="$1" event="$2" gh_ref="$3" in_ref="$4" expected="$5" actual rc
  actual=$(bash "$GUARD" resolve-tag "$event" "$gh_ref" "$in_ref" 2>/dev/null) && rc=0 || rc=$?
  if [[ "$expected" == "FAIL" ]]; then
    if [[ "$rc" -ne 0 ]]; then
      echo "PASS [$name]: rejected (rc=$rc)"
      PASS=$((PASS + 1))
    else
      echo "FAIL [$name]: expected rejection, got tag '$actual' (rc=0)"
      FAIL=$((FAIL + 1))
    fi
  else
    if [[ "$rc" -eq 0 && "$actual" == "$expected" ]]; then
      echo "PASS [$name]: got '$actual'"
      PASS=$((PASS + 1))
    else
      echo "FAIL [$name]: expected '$expected', got '$actual' (rc=$rc)"
      FAIL=$((FAIL + 1))
    fi
  fi
}

# ---------------------------------------------------------------------------
# Group 1: YAML structural gates on build-inngest-bootstrap-image.yml (AC3/AC4).
# ---------------------------------------------------------------------------
check_yaml_token  'yaml:permissions-contents-read' 'contents: read'
check_yaml_absent 'yaml:no-contents-write'         'contents: write'
check_yaml_token  'yaml:dispatch-input-ref'        'inputs.ref'
check_yaml_absent 'yaml:no-free-form-tag-input'    'inputs.tag'
check_yaml_token  'yaml:inline-validate-regex'     "$INLINE_RE"
check_yaml_token  'yaml:resolve-via-guard'         'inngest-bootstrap-tag-guard.sh resolve-tag'

# ---------------------------------------------------------------------------
# Group 2: resolve-tag behavior (synthetic triples).
# ---------------------------------------------------------------------------
assert_resolve 'resolve:dispatch-valid'   'workflow_dispatch' ''                              'vinngest-v1.1.11'        'v1.1.11'
assert_resolve 'resolve:push-valid'       'push'              'refs/tags/vinngest-v1.1.11'    ''                        'v1.1.11'
assert_resolve 'resolve:dispatch-empty'   'workflow_dispatch' ''                              ''                        'FAIL'
assert_resolve 'resolve:push-non-vinngest' 'push'             'refs/tags/web-v0.1.0'          ''                        'FAIL'
assert_resolve 'resolve:push-prerelease'  'push'              'refs/tags/vinngest-v1.1.11-rc1' ''                       'FAIL'
assert_resolve 'resolve:push-branch-ref'  'push'              'refs/heads/main'               ''                        'FAIL'
assert_resolve 'resolve:dispatch-double-prefix' 'workflow_dispatch' ''                        'vinngest-vinngest-v1.2.3' 'FAIL'

# ---------------------------------------------------------------------------
# Parity gate (AC5): guard resolve-tag regex == consumer drift-guard regex.
# Both files must contain the identical stripped-tag literal; if either edits
# its regex without the other, this fails.
# ---------------------------------------------------------------------------
if grep -F -q -- "$STRIPPED_RE" "$GUARD" && grep -F -q -- "$STRIPPED_RE" "$CONSUMER"; then
  echo "PASS [parity:guard==consumer-stripped-regex]: '$STRIPPED_RE' in both"
  PASS=$((PASS + 1))
else
  echo "FAIL [parity:guard==consumer-stripped-regex]: '$STRIPPED_RE' missing from guard or consumer"
  echo "  guard:    $GUARD"
  echo "  consumer: $CONSUMER"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]]
