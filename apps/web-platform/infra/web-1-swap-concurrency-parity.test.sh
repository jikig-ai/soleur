#!/usr/bin/env bash
#
# Drift guard: the THREE GitHub Actions jobs that MUTATE web-1 (two swap the web-1
# container via `command: deploy web-platform …` → /hooks/deploy → ci-deploy.sh; the
# third, #6604, attaches the encrypted volume to web-1) MUST share ONE job-level
# `web-1-swap` concurrency group so GitHub's scheduler serializes them across
# pipelines — at most one web-1 mutation in flight at a time (#6060 item (c) /
# FINDING 1 from #6051's review). A FOURTH member — the #6604 freeze workflow — carries
# the group at WORKFLOW scope (it is a dedicated dispatch, not a job in a shared
# workflow), asserted separately below.
#
# reason: 5 job-level members -> 3. The `warm_standby` and `web_2_recreate` members were
# DELETED with the web-2 dispatch sweep (#6575, 2026-07-20).
#
# The three job-level members (allow-list — an explicit named list so a DELIBERATE
# future member is a visible allow-list edit, while a silently-dropped copy OR an
# accidentally-enrolled job both fail loud):
#   1. web-platform-release.yml        job `deploy`                 (tagged-release deploy)
#   2. apply-deploy-pipeline-fix.yml   job `apply`                  (POSTs deploy at :607)
#   3. apply-web-platform-infra.yml    job `workspaces_luks_cutover` (#6604 attaches the LUKS volume to web-1)
# Plus the WORKFLOW-level member: workspaces-luks-cutover.yml (#6604 freeze — stops/repoints web-1's /mnt/data).
#
# NOT a member (negative assertion): the routine `apply` job in
# apply-web-platform-infra.yml runs terraform but does NOT POST /hooks/deploy
# (does not swap web-1) — enrolling it would over-serialize every routine release
# behind every routine infra apply.
#
# Invariants asserted:
#   - each named member carries a job-level `concurrency.group: web-1-swap` with
#     `cancel-in-progress: false` (a killed in-progress swap would widen a 521 window);
#   - the TOTAL count of `group: web-1-swap` across the three workflows == 3
#     (allow-list length — NOT head -1, NOT >= 3: a dropped OR an unlisted member fails);
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
FREEZE_WF="${WF_DIR}/workspaces-luks-cutover.yml"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

for f in "$RELEASE_WF" "$APPLY_INFRA_WF" "$PIPELINE_FIX_WF" "$FREEZE_WF"; do
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
  # #6178: use a here-string, NOT `printf "$block" | grep -q`. Under `set -o pipefail`
  # a matching `grep -q` closes the pipe early → printf gets SIGPIPE (141) → the pipeline
  # exits non-zero even on a MATCH → the `if` spuriously takes the else branch. The race
  # only bites LARGE blocks (printf still writing when grep exits), so it flaked on the
  # big pipeline-fix `apply` job in CI while passing locally. A here-string has no pipe.
  if grep -qE '^[[:space:]]+group:[[:space:]]*web-1-swap[[:space:]]*$' <<<"$block"; then
    pass
  else
    fail "$label: job '$job' missing job-level concurrency.group: web-1-swap"
  fi
  if grep -qE '^[[:space:]]+cancel-in-progress:[[:space:]]*false[[:space:]]*$' <<<"$block"; then
    pass
  else
    fail "$label: job '$job' missing cancel-in-progress: false"
  fi
}

# --- The three named members (allow-list) ---
assert_member "$RELEASE_WF"      "deploy"                 "release-deploy"
assert_member "$PIPELINE_FIX_WF" "apply"                  "pipeline-fix-apply"
assert_member "$APPLY_INFRA_WF"  "workspaces_luks_cutover" "workspaces-luks-cutover"

# --- The #6604 freeze workflow (workspaces-luks-cutover.yml) carries web-1-swap at
# WORKFLOW scope (it is a dedicated dispatch, not a job in a shared workflow), so it
# is asserted directly, not via job_block. It stops/repoints web-1's /mnt/data and MUST
# serialize against the container-swap jobs. ---
if grep -qE '^[[:space:]]*group:[[:space:]]*web-1-swap[[:space:]]*$' "$FREEZE_WF"; then
  pass
else
  fail "workspaces-luks-cutover.yml (freeze): workflow-level 'group: web-1-swap' missing"
fi
if grep -qE '^[[:space:]]*cancel-in-progress:[[:space:]]*false[[:space:]]*$' "$FREEZE_WF"; then
  pass
else
  fail "workspaces-luks-cutover.yml (freeze): 'cancel-in-progress: false' missing"
fi

# --- Total count of job-level `group: web-1-swap` across the three shared workflows
# == 3. reason: 5 -> 3. The warm_standby and web_2_recreate members were DELETED with
# the web-2 dispatch sweep (#6575, 2026-07-20); the remaining members are the release
# deploy, pipeline-fix apply, and the #6604 volume-attach job. A silently-dropped member
# drops below 3; an accidentally-enrolled or duplicated job pushes above 3.
# NOTE the pre-existing header above said 4 while the real count was 5 — that stale
# figure is corrected to 3 here rather than carried forward. Either fails loud. The
# freeze workflow's workflow-level group is asserted above and NOT part of this count. ---
web1_count=$(grep -rhE '^[[:space:]]+group:[[:space:]]*web-1-swap[[:space:]]*$' \
  "$RELEASE_WF" "$APPLY_INFRA_WF" "$PIPELINE_FIX_WF" | grep -c .)
if [ "$web1_count" -eq 3 ]; then
  pass
else
  fail "expected exactly 3 'group: web-1-swap' occurrences (allow-list length), found $web1_count"
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
elif grep -qE '^[[:space:]]+group:[[:space:]]*web-1-swap[[:space:]]*$' <<<"$routine_apply_block"; then
  fail "routine 'apply' job in apply-web-platform-infra.yml is enrolled in web-1-swap (over-serialization trap)"
else
  pass
fi

total=$((passes + fails))
echo "web-1-swap-concurrency-parity: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
