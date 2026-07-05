#!/usr/bin/env bash
#
# Drift guard: the FOUR GitHub Actions jobs that swap the web-1 container (each
# POSTs `command: deploy web-platform …` to /hooks/deploy, then ci-deploy.sh swaps
# web-1 and fans out to peers) MUST share ONE job-level `web-1-swap` concurrency
# group so GitHub's scheduler serializes them across pipelines — at most one web-1
# swap in flight at a time (#6060 item (c) / FINDING 1 from #6051's review).
#
# The four members (allow-list — an explicit named list so a DELIBERATE future
# member is a visible allow-list edit, while a silently-dropped copy OR an
# accidentally-enrolled job both fail loud):
#   1. web-platform-release.yml        job `deploy`         (tagged-release deploy)
#   2. apply-web-platform-infra.yml    job `web_2_recreate` (#6030 operator recreate)
#   3. apply-web-platform-infra.yml    job `warm_standby`   (ADR-068 warm-standby)
#   4. apply-deploy-pipeline-fix.yml   job `apply`          (POSTs deploy at :607)
#
# NOT a member (negative assertion): the routine `apply` job in
# apply-web-platform-infra.yml runs terraform but does NOT POST /hooks/deploy
# (does not swap web-1) — enrolling it would over-serialize every routine release
# behind every routine infra apply.
#
# Invariants asserted:
#   - each named member carries a job-level `concurrency.group: web-1-swap` with
#     `cancel-in-progress: false` (a killed in-progress swap would widen a 521 window);
#   - the TOTAL count of `group: web-1-swap` across the three workflows == 4
#     (allow-list length — NOT head -1, NOT >= 4: a dropped OR an unlisted member fails);
#   - the workflow-level `terraform-apply-web-platform-host` R2 serializer literal is
#     still present in BOTH apply-web-platform-infra.yml AND apply-deploy-pipeline-fix.yml
#     (job-level web-1-swap coexists with, does not replace, the R2 state serializer);
#   - no stale `deploy-web-platform` group name remains anywhere (the release deploy
#     job's old group was renamed to web-1-swap);
#   - the routine `apply` job in apply-web-platform-infra.yml is NOT a web-1-swap member.
#
# Run: bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh
# Registered in .github/workflows/infra-validation.yml.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WF_DIR="${DIR}/../../../.github/workflows"
RELEASE_WF="${WF_DIR}/web-platform-release.yml"
APPLY_INFRA_WF="${WF_DIR}/apply-web-platform-infra.yml"
PIPELINE_FIX_WF="${WF_DIR}/apply-deploy-pipeline-fix.yml"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

for f in "$RELEASE_WF" "$APPLY_INFRA_WF" "$PIPELINE_FIX_WF"; do
  [ -f "$f" ] || { echo "FAIL: workflow not found at $f" >&2; exit 1; }
done

# Extract a single top-level job's block: from its `^  <job>:` header (2-space
# indent) up to (but not including) the next 2-space-indented job header, a
# top-level key, or EOF. Job sub-keys are 4-space-indented and stay inside the
# block; sibling job headers and top-level keys close it.
job_block() {
  local file="$1" job="$2"
  awk -v job="$job" '
    $0 ~ "^  " job ":([[:space:]]|$)" { inblock = 1; print; next }
    inblock && /^  [A-Za-z_]/ { inblock = 0 }
    inblock && /^[A-Za-z]/    { inblock = 0 }
    inblock { print }
  ' "$file"
}

# Assert a named member job carries job-level web-1-swap + cancel-in-progress: false.
assert_member() {
  local file="$1" job="$2" label="$3" block
  block="$(job_block "$file" "$job")"
  if [ -z "$block" ]; then
    fail "$label: job '$job' not found in $(basename "$file")"
    return
  fi
  if printf '%s\n' "$block" | grep -qE '^[[:space:]]+group:[[:space:]]*web-1-swap[[:space:]]*$'; then
    pass
  else
    fail "$label: job '$job' missing job-level concurrency.group: web-1-swap"
  fi
  if printf '%s\n' "$block" | grep -qE '^[[:space:]]+cancel-in-progress:[[:space:]]*false[[:space:]]*$'; then
    pass
  else
    fail "$label: job '$job' missing cancel-in-progress: false"
  fi
}

# --- The four named members (allow-list) ---
assert_member "$RELEASE_WF"      "deploy"         "release-deploy"
assert_member "$APPLY_INFRA_WF"  "web_2_recreate" "web-2-recreate"
assert_member "$APPLY_INFRA_WF"  "warm_standby"   "warm-standby"
assert_member "$PIPELINE_FIX_WF" "apply"          "pipeline-fix-apply"

# --- Total count of `group: web-1-swap` across the workflows == 4 (allow-list
# length). A silently-dropped member drops below 4; an accidentally-enrolled or
# duplicated job pushes above 4. Either fails loud. ---
web1_count=$(grep -rhE '^[[:space:]]+group:[[:space:]]*web-1-swap[[:space:]]*$' \
  "$RELEASE_WF" "$APPLY_INFRA_WF" "$PIPELINE_FIX_WF" | grep -c .)
if [ "$web1_count" -eq 4 ]; then
  pass
else
  fail "expected exactly 4 'group: web-1-swap' occurrences (allow-list length), found $web1_count"
fi

# --- Workflow-level R2 serializer preserved in BOTH apply workflows (coexists
# with the new job-level group; must NOT be replaced by it). ---
for f in "$APPLY_INFRA_WF" "$PIPELINE_FIX_WF"; do
  if grep -qE '^[[:space:]]*group:[[:space:]]*terraform-apply-web-platform-host[[:space:]]*$' "$f"; then
    pass
  else
    fail "$(basename "$f"): workflow-level 'group: terraform-apply-web-platform-host' R2 serializer missing"
  fi
done

# --- No stale `deploy-web-platform` group NAME remains anywhere (the release
# deploy job's old group was renamed to web-1-swap). Anchor to the `group:` key
# shape so this asserts on a resurrected group DECLARATION only — a future
# comment documenting the rename (e.g. "was deploy-web-platform") must not
# false-FAIL this guard. ---
if grep -rqE '^[[:space:]]*group:[[:space:]]*deploy-web-platform[[:space:]]*$' \
  "$RELEASE_WF" "$APPLY_INFRA_WF" "$PIPELINE_FIX_WF"; then
  fail "stale 'deploy-web-platform' concurrency group remains (should be renamed to web-1-swap)"
else
  pass
fi

# --- Negative: the routine `apply` job in apply-web-platform-infra.yml must NOT
# be a web-1-swap member (it does not POST /hooks/deploy / swap web-1). Guard
# the block-non-empty precondition first, else a renamed/removed job or an awk
# extractor regression would vacuously PASS this negative check (grep -q on
# empty input → non-zero → else-pass). ---
routine_apply_block="$(job_block "$APPLY_INFRA_WF" "apply")"
if [ -z "$routine_apply_block" ]; then
  fail "routine 'apply' job not found in apply-web-platform-infra.yml — negative assertion cannot run (extractor regressed or job renamed)"
elif printf '%s\n' "$routine_apply_block" | grep -qE '^[[:space:]]+group:[[:space:]]*web-1-swap[[:space:]]*$'; then
  fail "routine 'apply' job in apply-web-platform-infra.yml is enrolled in web-1-swap (over-serialization trap)"
else
  pass
fi

total=$((passes + fails))
echo "web-1-swap-concurrency-parity: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
