#!/usr/bin/env bash
# Fixture tests for the inngest-bootstrap tag-driven workflow_dispatch invariant
# (#4692; resolve made inline in #4700).
#
# The tag-resolution logic lives INLINE in build-inngest-bootstrap-image.yml's
# `Resolve image tag` step — NOT in a checked-out helper script. This is
# load-bearing: the workflow checks out `inputs.ref` (an EXISTING tag's tree,
# which predates the workflow), so a `.github/scripts/*.sh` helper would not
# exist there and the step would die with exit 127 (the #4700 regression). The
# workflow file is always read from the default branch, so inline logic is
# current regardless of which tag tree is checked out.
#
# This test mirrors test-tag-filter.sh: it (1) asserts the workflow's YAML shape
# and (2) reimplements the resolve pipeline inline and runs it against synthetic
# (event, github_ref, inputs_ref) triples — the pre-merge verification of the
# invariant, since workflow_dispatch can't be live-triggered on a feature branch.

set -uo pipefail
export LC_ALL=C

SCRIPT_DIR=$(cd "$(dirname "$0")/../../.." && pwd)
WORKFLOW="$SCRIPT_DIR/.github/workflows/build-inngest-bootstrap-image.yml"
CONSUMER="$SCRIPT_DIR/apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh"
[[ -f "$WORKFLOW" ]] || { echo "FAIL: $WORKFLOW not found"; exit 1; }
[[ -f "$CONSUMER" ]] || { echo "FAIL: $CONSUMER not found"; exit 1; }

# Canonical literals the workflow + consumer must both carry.
STRIPPED_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'                 # post-strip image-tag regex (== consumer)
INLINE_RE='^vinngest-v[0-9]+\.[0-9]+\.[0-9]+$'          # pre-checkout full-ref validator

PASS=0
FAIL=0

check_yaml_token() {
  local name="$1" needle="$2"
  if grep -F -q -- "$needle" "$WORKFLOW"; then echo "PASS [$name]"; PASS=$((PASS+1))
  else echo "FAIL [$name]: workflow lacks literal: $needle"; FAIL=$((FAIL+1)); fi
}
check_yaml_absent() {
  local name="$1" needle="$2"
  if grep -F -q -- "$needle" "$WORKFLOW"; then echo "FAIL [$name]: workflow still contains forbidden literal: $needle"; FAIL=$((FAIL+1))
  else echo "PASS [$name]"; PASS=$((PASS+1)); fi
}

# resolve() — an exact mirror of the workflow's inline `Resolve image tag` bash.
# Behavior parity is tested here; the YAML-shape gates above lock the workflow to
# the same literals so the two can't silently drift.
resolve() {
  local event="$1" github_ref="$2" inputs_ref="$3" src tag
  if [[ "$event" == "workflow_dispatch" ]]; then src="$inputs_ref"; else src="$github_ref"; fi
  tag="${src#refs/tags/}"
  tag="${tag#vinngest-}"
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s\n' "$tag"
}

assert_resolve() {
  local name="$1" event="$2" gh_ref="$3" in_ref="$4" expected="$5" actual rc
  actual=$(resolve "$event" "$gh_ref" "$in_ref") && rc=0 || rc=$?
  if [[ "$expected" == "FAIL" ]]; then
    if [[ "$rc" -ne 0 ]]; then echo "PASS [$name]: rejected (rc=$rc)"; PASS=$((PASS+1))
    else echo "FAIL [$name]: expected rejection, got '$actual'"; FAIL=$((FAIL+1)); fi
  else
    if [[ "$rc" -eq 0 && "$actual" == "$expected" ]]; then echo "PASS [$name]: got '$actual'"; PASS=$((PASS+1))
    else echo "FAIL [$name]: expected '$expected', got '$actual' (rc=$rc)"; FAIL=$((FAIL+1)); fi
  fi
}

# ---------------------------------------------------------------------------
# Group 1: YAML structural gates on build-inngest-bootstrap-image.yml.
# ---------------------------------------------------------------------------
check_yaml_token  'yaml:permissions-contents-read' 'contents: read'
check_yaml_absent 'yaml:no-contents-write'         'contents: write'
check_yaml_token  'yaml:dispatch-input-ref'        'inputs.ref'
check_yaml_absent 'yaml:no-free-form-tag-input'    'inputs.tag'
check_yaml_token  'yaml:inline-validate-regex'     "$INLINE_RE"
# Regression gate (#4700): resolve must be INLINE, never a checked-out script —
# a `.github/scripts/*.sh` helper is absent from existing tag trees (exit 127).
check_yaml_absent 'yaml:resolve-not-checked-out-script' 'inngest-bootstrap-tag-guard.sh'
check_yaml_token  'yaml:inline-resolve-strip'      'tag="${tag#vinngest-}"'
check_yaml_token  'yaml:inline-resolve-regex'      "$STRIPPED_RE"

# ---------------------------------------------------------------------------
# Group 2: inline-resolve behavior (synthetic triples).
# ---------------------------------------------------------------------------
assert_resolve 'resolve:dispatch-valid'         'workflow_dispatch' ''                               'vinngest-v1.1.11'         'v1.1.11'
assert_resolve 'resolve:push-valid'             'push'              'refs/tags/vinngest-v1.1.11'     ''                         'v1.1.11'
assert_resolve 'resolve:dispatch-empty'         'workflow_dispatch' ''                               ''                         'FAIL'
assert_resolve 'resolve:push-non-vinngest'      'push'              'refs/tags/web-v0.1.0'           ''                         'FAIL'
assert_resolve 'resolve:push-prerelease'        'push'              'refs/tags/vinngest-v1.1.11-rc1' ''                         'FAIL'
assert_resolve 'resolve:push-branch-ref'        'push'              'refs/heads/main'                ''                         'FAIL'
assert_resolve 'resolve:dispatch-double-prefix' 'workflow_dispatch' ''                               'vinngest-vinngest-v1.2.3' 'FAIL'

# ---------------------------------------------------------------------------
# Parity gate: the workflow's inline post-strip regex == the consumer
# drift-guard's regex (cloud-init-inngest-bootstrap.test.sh). Both files must
# carry the identical literal.
# ---------------------------------------------------------------------------
if grep -F -q -- "$STRIPPED_RE" "$WORKFLOW" && grep -F -q -- "$STRIPPED_RE" "$CONSUMER"; then
  echo "PASS [parity:workflow==consumer-stripped-regex]: '$STRIPPED_RE' in both"
  PASS=$((PASS+1))
else
  echo "FAIL [parity:workflow==consumer-stripped-regex]: '$STRIPPED_RE' missing from workflow or consumer"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Results: $PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]]
