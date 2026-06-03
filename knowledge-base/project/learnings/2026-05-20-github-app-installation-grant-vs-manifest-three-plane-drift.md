---
title: GitHub App three-plane permission drift — installation grant lags manifest + App declaration
date: 2026-05-20
category: integration-issues
module: apps/web-platform/infra/github-app
tags: [github-app, installation-token, terraform, drift-guard, operator-only-step]
related_issues: [4173, 4179, 4136, 4137, 4150, 4161, 4144]
---

# Learning: GitHub App three-plane permission drift

## Problem

`apply-web-platform-infra.yml` failed at the terraform apply step with:

```
Error: GET https://api.github.com/repos/jikig-ai/soleur/actions/secrets/public-key:
       403 Resource not accessible by integration []
```

This blocked `github_actions_secret.doppler_token_kb_drift` creation and every
subsequent push to `main` that touched `apps/web-platform/infra/**`.

The `integrations/github` Terraform provider uses GitHub App-installation auth
(post-#4150 migration from PAT). The installation token gates `actions/secrets/public-key`
behind the `secrets:write` permission scope.

## Root Cause

GitHub Apps have **three independent permission planes** that can drift silently:

| Plane | Source of truth | API |
|-------|-----------------|-----|
| (a) App-level declaration | App settings page | `GET /apps/{slug}` |
| (b) Committed manifest JSON | `github-app-manifest.json` in repo | (text file) |
| (c) Installation-level grant | Installation settings page | `GET /orgs/{org}/installations` |

At incident time:
- (a) declared 8 permissions including `secrets:write`
- (b) declared 7 (no `secrets`)
- (c) granted 7 (no `secrets`)

Terraform apply uses the **installation token** from plane (c) — so the request
to `actions/secrets/public-key` 403'd despite plane (a) declaring the permission.

The drift-guard cron (`scheduled-github-app-drift-guard.yml`) compares (a) vs (b)
only. The bug at plane (c) was invisible.

## Solution

**Three coordinated steps:**

1. **Operator UI click (plane c → 8):** the founder navigated to
   `https://github.com/organizations/jikig-ai/settings/installations/122213433`,
   clicked "Review request" → "Accept new permissions". Verified via
   `gh api /orgs/jikig-ai/installations --jq '.installations[]
   | select(.app_slug=="soleur-ai") | .permissions.secrets'` → `"write"`.

   GitHub has no API for accepting installation permissions. This is the
   vendor-authorization-scope class of the operator-only canonical list
   (`knowledge-base/project/learnings/2026-05-15-operator-only-step-canonical-list.md`).

2. **Manifest sync (plane b → 8):** added `"secrets": "write"` to
   `apps/web-platform/infra/github-app-manifest.json`. Updated the parity test's
   `EXPECTED_PERMISSION_KEYS` lock list. Validated via the drift script
   (`bin/diff-github-app-manifest.sh`) — exit 0, no drift.

3. **Runbook codification:** added `Step 2.1 — Re-accept App installation when
   permissions widen` to `knowledge-base/engineering/operations/runbooks/github-app-provisioning.md`
   so the next permission widening doesn't repeat #4173.

## Key Insight

**A three-plane source-of-truth model needs three pairwise drift checks, not
one.** The drift-guard's name implies it detects any divergence; the runtime
fault lives at the layer the guard doesn't read. The fix wasn't to extend the
guard inline (that's #4179, a separate PR) but to acknowledge the gap honestly
in the code comment (`apps/web-platform/infra/github-app.tf` post-#4173 block)
AND file the extension as tracked work.

A second insight: **the operator UI click is automatable via Playwright MCP.**
The vendor limit is "no API"; the UI is reachable. The agent navigated, clicked
through the consent screen, and verified post-conditions via `gh api` — closing
the operator-handoff cost while preserving the operator's audit trail
(the click happened under their authenticated browser session).

## Session Errors

1. **Planning subagent hit Anthropic session limit mid-Session-Summary emission.**
   Recovery: detected the partial plan artifact on disk (`knowledge-base/project/plans/2026-05-20-fix-apply-web-platform-infra-secrets-write-installation-grant-4173-plan.md`)
   and reconstructed `session-state.md` from on-disk content per the one-shot
   partial-artifact recovery pattern.
   Prevention: already documented — `2026-05-15-subagent-crash-recovery-via-on-disk-artifacts.md`.

2. **Process substitution `<(gh api ...)` failed against `bin/diff-github-app-manifest.sh`.**
   The script reads `$RESPONSE_FILE` twice (response-shape check + permissions
   diff). A bash fifo can only be read once → second read returns empty → script
   exits with `response_shape_unparseable:response.permissions=object response.events=`.
   Recovery: switched to `RESP=$(mktemp); gh api ... > "$RESP"`.
   Prevention: `bin/diff-github-app-manifest.sh` should either (a) slurp the
   response into a single `jq` invocation, (b) document in its header that
   `RESPONSE_FILE` must be a regular file, or (c) detect fifo via
   `[[ -p "$RESPONSE_FILE" ]]` and reject with a clear message. The plan
   prescribed `<(...)` invocation; the prescription propagates the bug.

3. **Plan AC4 named `bun test` but `apps/web-platform/bunfig.toml` blocks bun
   discovery** (`pathIgnorePatterns = ["**"]`). The actual runner is vitest
   (`package.json scripts.test = "vitest"`).
   Recovery: ran via `./node_modules/.bin/vitest run test/...`.
   Prevention: plan AC commands should be derived from the package's actual
   `test` script (`jq -r .scripts.test < package.json`), not author-recall.

4. **Plan AC4 named the wrong test file** (`github-app-manifest-drift-guard.test.ts`,
   not the parity-test file actually modified by this PR). Both files exist in
   the same directory which made the misdirection silent.
   Recovery: ran the parity test directly; updated AC4 inline.
   Prevention: AC4 should derive the test-file path from the diff (`git diff
   --name-only origin/main...HEAD | grep '\.test\.ts$'`) at plan-write time.

5. **Plan claimed "6/6 cases" but actual count is 7** — plan-prose tally
   drifted from the real test count.
   Recovery: ran the test, confirmed 7, updated plan.
   Prevention: per the work-skill rule (`Counts written into the artifact ...
   must be derived from the as-written file, not from plan-prose estimates.`)
   — same class as PR #4122's "68 explicit targets" drift.

6. **Plan body cited `learnings/best-practices/2026-05-15-operator-only-step-canonical-list.md`**
   three times; file is at `learnings/2026-05-15-...` (no `best-practices/`
   segment). Caught by `architecture-strategist` review.
   Recovery: corrected all citations + adjacent runbook reference.
   Prevention: file-path citations in plans + comments should be Glob-verified
   at plan-write time. The /soleur:plan skill could add a "Cross-reference
   validation" step: `git ls-files <every-cited-path> | wc -l` must equal
   the count of citations.

7. **Plan's "Files to Edit" missed `apps/web-platform/test/github-app-manifest-parity.test.ts`.**
   That test holds a hardcoded `EXPECTED_PERMISSION_KEYS` lock list; adding
   `secrets` to the manifest broke the test. Caught at test-run, not plan time.
   Recovery: added to the edit set.
   Prevention: when editing a manifest/schema/config JSON, /work should grep for
   tests that lock against constants in that file. Heuristic: `git grep -lE
   '(EXPECTED|FROZEN|ALLOWED)_[A-Z_]+' apps/*/test/` before declaring "Files to Edit"
   complete.

8. **`code-simplicity-reviewer` first invocation gave free-form simplicity
   suggestions, not CONCUR/DISSENT.** When I subsequently needed CONCUR/DISSENT
   for the scope-out gate, I had to re-invoke with explicit format requirements.
   Recovery: re-invoked with the exact 4-criteria definitions + first-line
   CONCUR/DISSENT mandate.
   Prevention: when /soleur:review's spawn loop has more than one role for
   the same agent (general review + scope-out gate), use distinct prompt
   templates per role. The review skill already has the CONCUR/DISSENT prompt
   template; the simplicity-review spawn should use a free-form template.

9. **`gh issue create --label area/infra` failed** — label doesn't exist in
   this repo. Recovery: ran `gh label list --limit 200 | grep -iE
   "(infra|security)"`; used `domain/engineering` instead.
   Prevention: when creating issues with new labels, validate against
   `gh label list` first. The /soleur:review issue-filing flow could
   canonicalize label aliases ("infra" → "domain/engineering").

10. **Operator-mediated step happened mid-pipeline.** Phase 1 of the plan
    required clicking "Accept new permissions" in GitHub UI; the agent drove
    it via Playwright MCP under the operator's authenticated browser session.
    Worked first try with no operator handoff. Not strictly an error but
    notable that Playwright + persistent browser session collapses what the
    plan classified as "operator-only" into "agent-with-operator-browser".
    Same pattern as PR #3946 vendor-support-tickets (`2026-05-17-vendor-support-tickets-are-playwright-driveable.md`).

## Tags

category: integration-issues
module: apps/web-platform/infra/github-app
