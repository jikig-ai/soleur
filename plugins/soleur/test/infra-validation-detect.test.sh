#!/usr/bin/env bash

# Tests for the detect-changes pipeline in .github/workflows/infra-validation.yml.
# Run: bash plugins/soleur/test/infra-validation-detect.test.sh
#
# Defect class: git pathspec `*` does not cross `/` in default semantics, so
# `'apps/*/infra/'` (single `*`, trailing slash, no `**`) returns empty for
# every changed infra file. The pipeline silently emits `[]`, the gated
# `validate` matrix fans out to zero jobs, and GitHub Actions reports
# `success`. See #4012 and learning 2026-03-21-lefthook-gobwas-glob-double-star.md
# for the sibling class (Lefthook gobwas glob `**` semantics).
#
# Test isolation: detect_infra_dirs() reads stdin (synthetic `git diff
# --name-only` output) so the test is hermetic — no real git invocation,
# no version-of-git dependency.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# The detect_infra_dirs() function under test is byte-identical to the shell
# pipeline body inside .github/workflows/infra-validation.yml's detect-changes
# job (modulo the `git diff` call, which the workflow pipes in upstream).
# Pathspec → regex translation per learning
# 2026-05-09-pathspec-regex-translation-and-classifier-piggyback.md.
detect_infra_dirs() {
  { grep -E '^(apps/[^/]+/infra|infra/[^/]+)/' || true; } \
    | sed -E 's|^(apps/[^/]+/infra)/.*|\1|; s|^(infra/[^/]+)/.*|\1|' \
    | sort -u \
    | jq -R -s -c 'split("\n") | map(select(. != ""))'
}

echo "=== infra-validation-detect tests ==="
echo ""

# --- TS1: apps/<x>/infra/ direct child ---
echo "TS1: apps/<x>/infra/ direct child collapses to single-ancestor dir"
OUT=$(printf '%s\n' "apps/web-platform/infra/uptime-alerts.tf" | detect_infra_dirs)
assert_eq '["apps/web-platform/infra"]' "$OUT" "direct child → [apps/web-platform/infra]"
echo ""

# --- TS2: apps/<x>/infra/ single-ancestor nested ---
echo "TS2: apps/<x>/infra/<sub>/file collapses to single-ancestor dir"
OUT=$(printf '%s\n' "apps/web-platform/infra/sentry/uptime-monitors.tf" | detect_infra_dirs)
assert_eq '["apps/web-platform/infra"]' "$OUT" "single-ancestor nested → [apps/web-platform/infra]"
echo ""

# --- TS3: apps/<x>/infra/ deep-nested ---
echo "TS3: apps/<x>/infra/a/b/c/file collapses to single-ancestor dir"
OUT=$(printf '%s\n' "apps/web-platform/infra/test-fixtures/audit-bwrap/foo.tf" | detect_infra_dirs)
assert_eq '["apps/web-platform/infra"]' "$OUT" "deep-nested → [apps/web-platform/infra]"
echo ""

# --- TS4: infra/<x>/ direct child ---
echo "TS4: infra/<x>/file collapses to single-ancestor dir"
OUT=$(printf '%s\n' "infra/github/main.tf" | detect_infra_dirs)
assert_eq '["infra/github"]' "$OUT" "direct child → [infra/github]"
echo ""

# --- TS5: infra/<x>/ deep-nested ---
echo "TS5: infra/<x>/a/b/file collapses to single-ancestor dir"
OUT=$(printf '%s\n' "infra/github/deeply/nested/foo.tf" | detect_infra_dirs)
assert_eq '["infra/github"]' "$OUT" "deep-nested → [infra/github]"
echo ""

# --- TS6: mixed + non-infra controls ---
echo "TS6: mixed infra paths and non-infra controls → sorted, deduped, non-infra filtered"
OUT=$(printf '%s\n' \
  "apps/web-platform/infra/uptime-alerts.tf" \
  "apps/cla-evidence/infra/main.tf" \
  "infra/github/main.tf" \
  "apps/web-platform/server/route.ts" \
  "knowledge-base/project/plans/foo.md" \
  | detect_infra_dirs)
assert_eq '["apps/cla-evidence/infra","apps/web-platform/infra","infra/github"]' "$OUT" \
  "mixed input → 3 sorted infra dirs, non-infra filtered"
echo ""

# --- TS7: empty / zero-match (non-infra only) ---
echo "TS7: non-infra-only input → empty matrix [] (no failure under bash -e)"
OUT=$(printf '%s\n' "apps/web-platform/server/route.ts" | detect_infra_dirs)
assert_eq '[]' "$OUT" "non-infra only → []"
echo ""

# --- TS8: real-commit baseline (pathspec→regex equivalence per learning 2026-05-09) ---
# Skip gracefully on shallow clones (commit absent); TS1-TS7 cover the shape matrix.
echo "TS8: real-commit baseline against 7e6f6726 (uptime-alerting motivating commit)"
REPO_ROOT="$SCRIPT_DIR/../../.."
if git -C "$REPO_ROOT" rev-parse --verify --quiet '7e6f6726^{commit}' >/dev/null; then
  EXPECTED='["apps/web-platform/infra"]'
  ACTUAL=$(git -C "$REPO_ROOT" diff --name-only 7e6f6726^..7e6f6726 | detect_infra_dirs)
  assert_eq "$EXPECTED" "$ACTUAL" "real-commit 7e6f6726 → [apps/web-platform/infra]"
else
  echo "  SKIP: commit 7e6f6726 not present (shallow clone) — TS1-TS7 cover the shape matrix"
  PASS=$((PASS + 1))
fi
echo ""

# ============================================================================
# Event routing (#6766). detect_infra_dirs() above models only the pathspec
# collapse; it says nothing about WHICH input that pipeline is fed, which is
# the half that #6766 is about.
#
# detect_event_route() mirrors the branch selection in detect-changes. It
# returns the ROUTE the workflow takes rather than the diff itself, because the
# defect being guarded is a routing defect: on `merge_group`, github.base_ref
# is the empty string, so falling through to the diff arm runs
# `git diff origin/...HEAD` — a fatal git error that reds detect-changes and,
# through it, the required aggregator on EVERY merge-queue candidate. Both
# sibling required workflows (tenant-integration.yml detect-changes and
# apply-sentry-infra.yml) branch on merge_group as an explicit FIRST arm for
# exactly this reason; this mirror pins the same shape here.
#
# `push` routes to enumerate-all rather than a diff: #6766's complaint is that
# main can be red INDEFINITELY from an earlier cause, and only a full
# enumeration detects that. A `github.event.before` diff would only catch
# redness the current merge introduced.
detect_event_route() {
  local event_name="$1" base_ref="${2:-}"
  if [[ "$event_name" == "merge_group" ]]; then
    printf 'route=none directories=[] suite_relevant=false\n'
    return 0
  fi
  if [[ "$event_name" == "workflow_dispatch" || "$event_name" == "push" ]]; then
    printf 'route=enumerate-all directories=<all-infra-roots> suite_relevant=true\n'
    return 0
  fi
  printf 'route=diff cmd=git diff --name-only origin/%s...HEAD\n' "$base_ref"
}

echo "TS9: detect_event_route — merge_group is the explicit FIRST branch"
OUT=$(detect_event_route merge_group "")
assert_contains "$OUT" 'directories=[]' "merge_group → empty matrix"
assert_contains "$OUT" 'suite_relevant=false' "merge_group → suite_relevant=false"
# The load-bearing negative: base_ref is empty on merge_group, so ANY
# origin/...HEAD in this route is the F3 fatal-git-diff defect.
if [[ "$OUT" == *"origin/"* ]]; then
  echo "  FAIL: merge_group route must never emit an origin/...HEAD diff"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: merge_group route emits no origin/...HEAD diff"
  PASS=$((PASS + 1))
fi
echo ""

echo "TS10: detect_event_route — push enumerates all roots, never diffs"
OUT=$(detect_event_route push "")
assert_contains "$OUT" 'route=enumerate-all' "push → enumerate-all"
assert_contains "$OUT" 'suite_relevant=true' "push → suite_relevant=true"
if [[ "$OUT" == *"origin/"* ]]; then
  echo "  FAIL: push route must never emit an origin/...HEAD diff (base_ref is empty on push)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: push route emits no origin/...HEAD diff"
  PASS=$((PASS + 1))
fi
echo ""

echo "TS11: detect_event_route — workflow_dispatch unchanged (enumerate-all)"
OUT=$(detect_event_route workflow_dispatch "")
assert_contains "$OUT" 'route=enumerate-all' "workflow_dispatch → enumerate-all (pre-#6766 behaviour)"
echo ""

echo "TS12: detect_event_route — pull_request still diffs against the base ref"
OUT=$(detect_event_route pull_request main)
assert_contains "$OUT" 'route=diff' "pull_request → diff route"
assert_contains "$OUT" 'origin/main...HEAD' "pull_request → diffs origin/main...HEAD"
echo ""

# ============================================================================
# suite_relevant (#6766, R3). `directories` enumerates TERRAFORM ROOTS ONLY.
# The workflow-level `paths:` filter that this change removes deliberately
# listed several NON-infra paths, because deploy-script-tests runs cross-file
# drift guards over them. Deriving the gate from `directories` alone would
# silently disable every one of those guards — an under-trigger that produces
# a green check for an unrun suite, which is the same defect class #6766 names.
#
# SUITE_RE is the full union of the paths that were in that `paths:` block. It
# is byte-identical to the SUITE_RE in .github/workflows/infra-validation.yml's
# detect-changes step. The per-path rationale lives beside that copy (it was
# moved there verbatim from the deleted `paths:` block); it is not duplicated
# here so the two cannot drift in prose.
SUITE_RE='^(apps/[^/]+/infra/|infra/|\.github/scripts/validate-infra-templates\.sh$|\.github/scripts/test/fixtures-validate-infra-templates\.sh$|\.github/workflows/(infra-validation|restart-inngest-server|apply-inngest-rls|apply-inngest-rls-dev|scheduled-supabase-advisor-scan|apply-sentry-infra)\.yml$|scripts/supabase-advisor-scan\.sh$|apps/web-platform/server/inngest/functions/cron-supabase-advisor-scan\.ts$|knowledge-base/engineering/architecture/diagrams/model\.c4$)'

# Reads the changed-file list on stdin into a variable, then matches with a
# here-string. NOT `producer | grep -q`: under `set -o pipefail` grep -q exits
# on first match, SIGPIPEs the producer (141), and the pipeline reports failure
# — a false negative in exactly the arm that should have said "true".
detect_suite_relevant() {
  local changed
  changed=$(cat)
  if grep -Eq "$SUITE_RE" <<<"$changed"; then echo "true"; else echo "false"; fi
}

echo "TS13: detect_suite_relevant — restart-inngest-server.yml ONLY → true"
# The R3 under-trigger trap, and the headline case of #6766. This file is not a
# terraform root, so directories='[]' and the validate matrix fans to zero —
# but ci-deploy.test.sh's cross-file drift guard (#5145) reads this workflow's
# poll budget, so deploy-script-tests MUST run. If this case ever returns
# false, that guard stops firing on the only edits it exists to catch.
OUT=$(printf '%s\n' ".github/workflows/restart-inngest-server.yml" | detect_suite_relevant)
assert_eq 'true' "$OUT" "restart-inngest-server.yml only → suite_relevant=true"
echo ""

echo "TS14: detect_suite_relevant — every non-infra guarded path individually → true"
# Each of these was its own line in the deleted `paths:` block. Asserted one by
# one, not as a batch: a batch assertion passes if a SINGLE alternation branch
# survives a botched regex edit.
for p in \
  ".github/scripts/validate-infra-templates.sh" \
  ".github/scripts/test/fixtures-validate-infra-templates.sh" \
  ".github/workflows/infra-validation.yml" \
  ".github/workflows/apply-inngest-rls.yml" \
  ".github/workflows/apply-inngest-rls-dev.yml" \
  ".github/workflows/scheduled-supabase-advisor-scan.yml" \
  ".github/workflows/apply-sentry-infra.yml" \
  "scripts/supabase-advisor-scan.sh" \
  "apps/web-platform/server/inngest/functions/cron-supabase-advisor-scan.ts" \
  "knowledge-base/engineering/architecture/diagrams/model.c4"
do
  OUT=$(printf '%s\n' "$p" | detect_suite_relevant)
  assert_eq 'true' "$OUT" "$p → suite_relevant=true"
done
echo ""

echo "TS15: detect_suite_relevant — terraform roots → true"
OUT=$(printf '%s\n' "apps/web-platform/infra/uptime-alerts.tf" | detect_suite_relevant)
assert_eq 'true' "$OUT" "apps/<x>/infra/ → suite_relevant=true"
OUT=$(printf '%s\n' "infra/github/main.tf" | detect_suite_relevant)
assert_eq 'true' "$OUT" "infra/<x>/ → suite_relevant=true"
echo ""

echo "TS16: detect_suite_relevant — docs-only diff → false"
# The control for the other direction: dropping `paths:` must NOT put the
# 12-minute deploy-script-tests build on every docs-only PR.
OUT=$(printf '%s\n' \
  "knowledge-base/project/plans/foo.md" \
  "README.md" \
  "docs/index.md" \
  | detect_suite_relevant)
assert_eq 'false' "$OUT" "docs-only diff → suite_relevant=false"
echo ""

echo "TS17: detect_suite_relevant — near-miss paths must NOT match"
# Anchoring controls. A regex that lost its `^` or its `$` would green these,
# and the gate would run on unrelated files while still looking correct.
for p in \
  "docs/infra/notes.md" \
  ".github/workflows/apply-inngest-rls-prd.yml" \
  "apps/web-platform/infrastructure/main.tf" \
  "scripts/supabase-advisor-scan.sh.bak"
do
  OUT=$(printf '%s\n' "$p" | detect_suite_relevant)
  assert_eq 'false' "$OUT" "$p → suite_relevant=false (near-miss, must not match)"
done
echo ""

echo "TS18: detect_suite_relevant — empty diff → false"
OUT=$(printf '%s' "" | detect_suite_relevant)
assert_eq 'false' "$OUT" "empty diff → suite_relevant=false"
echo ""

# ============================================================================
# Mirror parity. TS9-TS18 test COPIES of the workflow's logic; a copy that has
# drifted from the original is a guard that certifies nothing — the very defect
# class #6766 names. These assertions anchor the mirrors to the real file by
# the SYNTAX each construct requires, not by a bare token a comment could also
# supply.
echo "TS19: the workflow's detect-changes matches the mirrors above"
WORKFLOW="$SCRIPT_DIR/../../../.github/workflows/infra-validation.yml"
WF_BODY=$(cat "$WORKFLOW")

# `merge_group` must be a real branch condition, not a mention in prose.
# shellcheck disable=SC2016  # single quotes are intentional — the pattern must match the LITERAL text "$EVENT_NAME" in the workflow, not this shell's expansion of it
if grep -Eq '\[\[[[:space:]]*"\$EVENT_NAME"[[:space:]]*==[[:space:]]*"merge_group"[[:space:]]*\]\]' <<<"$WF_BODY"; then
  echo "  PASS: workflow branches on EVENT_NAME == merge_group"; PASS=$((PASS + 1))
else
  echo "  FAIL: workflow has no [[ \"\$EVENT_NAME\" == \"merge_group\" ]] branch"; FAIL=$((FAIL + 1))
fi

# `push` must reach the enumerate-all arm, i.e. appear in a test against
# EVENT_NAME — not merely in the `on:` block.
# shellcheck disable=SC2016  # single quotes are intentional — literal "$EVENT_NAME" text match, see above
if grep -Eq '\$EVENT_NAME"[[:space:]]*==[[:space:]]*"push"' <<<"$WF_BODY"; then
  echo "  PASS: workflow routes EVENT_NAME == push"; PASS=$((PASS + 1))
else
  echo "  FAIL: workflow does not route EVENT_NAME == push"; FAIL=$((FAIL + 1))
fi

# The suite_relevant regex in the workflow must be byte-identical to SUITE_RE
# here. A prose-only sync would let the two diverge silently.
if grep -Fq "$SUITE_RE" <<<"$WF_BODY"; then
  echo "  PASS: workflow SUITE_RE is byte-identical to the mirror"; PASS=$((PASS + 1))
else
  echo "  FAIL: workflow SUITE_RE has drifted from this mirror"; FAIL=$((FAIL + 1))
fi

# detect-changes must publish suite_relevant as a JOB OUTPUT — computing it and
# not exporting it would leave every consumer reading the empty string.
if grep -Eq '^[[:space:]]+suite_relevant:[[:space:]]*\$\{\{[[:space:]]*steps\.' <<<"$WF_BODY"; then
  echo "  PASS: suite_relevant is declared as a job output"; PASS=$((PASS + 1))
else
  echo "  FAIL: suite_relevant is not declared as a job output"; FAIL=$((FAIL + 1))
fi

# The workflow-level `paths:` filter must be gone: while it is present, a
# non-infra PR posts no context at all and a required check waits forever.
ON_BLOCK=$(awk '/^on:/{f=1} f&&/^[a-z]/&&!/^on:/{exit} f' "$WORKFLOW")
if grep -Eq '^[[:space:]]+paths:' <<<"$ON_BLOCK"; then
  echo "  FAIL: workflow-level paths: filter is still present in on:"; FAIL=$((FAIL + 1))
else
  echo "  PASS: workflow-level paths: filter removed from on:"; PASS=$((PASS + 1))
fi
echo ""

print_results
