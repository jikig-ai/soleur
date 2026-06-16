---
name: postmerge
description: "This skill should be used when verifying a merged PR deployed correctly and production is healthy."
---

# postmerge Skill

**Purpose:** Enforce post-merge verification so bugs that only appear in production context are caught immediately after merge -- not days later. This closes the "last mile" gap where QA passes locally but production diverges (stale files, unapplied migrations, CSP violations from injected scripts).

**CRITICAL: No command substitution.** Never use `$()` in Bash commands. When a step says "get value X, then use it in command Y", run them as **two separate Bash tool calls** -- first get the value, then use it literally in the next call.

## Arguments

`$ARGUMENTS` should contain the PR number. If omitted, detect from the most recently merged PR on the current branch.

## Phase 1: Verify PR is Merged

Confirm the PR reached MERGED state:

```bash
gh pr view <number> --json state,mergeCommit,headRefName --jq '{state, mergeCommit: .mergeCommit.oid, branch: .headRefName}'
```

If state is not `MERGED`, stop:

```text
STOPPED: PR #<number> is not merged (state: <state>). Run /soleur:merge-pr first.
```

Record the merge commit SHA for later verification.

## Phase 2: Wait for CI on Main

Check the latest CI run on main triggered by the merge:

```bash
gh run list --branch main --limit 3 --json databaseId,status,conclusion,headSha
```

Find the run matching the merge commit SHA. If no matching run yet, use the **Monitor tool** with a polling loop (max 5 minutes). Do NOT use foreground `sleep`:

```bash
for i in $(seq 1 20); do
  result=$(gh run view <run-id> --json status,conclusion --jq '{status, conclusion}')
  echo "$(date +%H:%M:%S) $result"
  echo "$result" | grep -q '"completed"' && break
  sleep 15
done
```

React to the final status from the Monitor output.

**If CI passes:** Proceed to Phase 3.

**If CI fails:** Report the failure with details:

```bash
gh run view <run-id> --log-failed 2>&1 | tail -50
```

Stop:

```text
STOPPED: CI failed on main after merge.

Run ID: <run-id>
Conclusion: <conclusion>

Failed log tail:
<last 50 lines>

Investigate before proceeding. The merge is complete but production may not deploy.
```

## Phase 3: Verify Production Deployment

Check if a health endpoint is configured. Look for deployment URLs in environment or project config:

```bash
# Check for DEPLOY_URL or PRODUCTION_URL in environment
echo "${DEPLOY_URL:-not_set}"
echo "${PRODUCTION_URL:-not_set}"
```

If a production URL is available, verify the deployment:

```bash
curl -sf --max-time 10 "<production-url>/health" | jq .
```

Use `/health` (the public, middleware-/CSP-bypassed health route returning `{"status":"ok","version","build_sha","supabase","sentry",...}`), NOT `/api/health` — the latter is an authenticated API route that 307-redirects an unauthenticated probe to `/login`, so `curl -sf` fails and `HEALTH_VERIFIED` is left `false` even when production is healthy. The `build_sha` field also confirms the merge commit is the live build.

**If health check succeeds:** Record the response, set `HEALTH_VERIFIED=true`, and proceed.

**If health check fails or no URL configured:** set `HEALTH_VERIFIED=false`, warn, and proceed (not all PRs trigger deployments):

```text
WARNING: No production health check available. Skipping deployment verification.
```

`HEALTH_VERIFIED` is the explicit signal Phase 3.8 gates the feature-tweet draft
on — a ship tweet must only be drafted for a feature confirmed live. Track it as
a literal `true`/`false`; do NOT infer "verified" from "reached this line" (the
warn-and-proceed branch also falls through to the next phase).

## Phase 3.5: Sentry Cron Monitor Health

Verify scheduled functions are healthy post-deploy by querying Sentry cron monitors.

**Prerequisites:** `SENTRY_AUTH_TOKEN` (or `SENTRY_API_TOKEN` fallback) must be available. If missing, warn and skip:

```text
WARNING: SENTRY_AUTH_TOKEN not set. Skipping Sentry health verification.
```

Query cron monitors:

```bash
SENTRY_TOKEN=$(doppler secrets get SENTRY_AUTH_TOKEN -p soleur -c prd --plain 2>/dev/null || \
  doppler secrets get SENTRY_API_TOKEN -p soleur -c prd --plain)
SENTRY_ORG=$(doppler secrets get SENTRY_ORG -p soleur -c prd --plain 2>/dev/null || echo "jikigai")
API_HOST="${SENTRY_ORG}.sentry.io"

curl -sfS -H "Authorization: Bearer ${SENTRY_TOKEN}" \
  "https://${API_HOST}/api/0/organizations/${SENTRY_ORG}/monitors/?per_page=100" \
  | jq '[.[] | {slug: .slug, status: .status}] | map(select(.status != "ok" and .status != "active"))'
```

- If all monitors report `ok` or `active`: "Sentry cron monitors: all healthy"
- If any monitor reports `error` or `missed`: flag with monitor name and status. This is a WARNING, not a blocker — the monitor may have been unhealthy before this deploy.
- If Sentry API is unreachable or returns non-200: warn and skip (do not block on Sentry outages).

**Graceful degradation:** This check is advisory. A Sentry API failure does not block the postmerge pipeline.

## Phase 3.6: Sentry Error-Count Delta (Fix Efficacy)

A merged-and-deployed fix can pass every gate above and still not work — the deploy is healthy, monitors are alive, files are fresh, but the error keeps firing because the fix addressed the wrong root cause (the KB-sync / oauth-probe failure class). Phase 3.5 proves the *monitor* is alive; this phase asks the harder question: **did the error this PR claims to fix actually stop?**

**Run only when** the PR body or linked issue names a specific Sentry issue (a `*.sentry.io/issues/<id>` URL, a `SENTRY-<SHORTID>`, or a `Closes #N` whose issue references one). If no Sentry issue is identified, skip silently — there is no error to measure.

**Prerequisites:** same `SENTRY_AUTH_TOKEN` resolution as Phase 3.5 for the aggregate Discover count. **The single-issue GET below, however, requires the write-scoped `SENTRY_ISSUE_RW_TOKEN`** — the `/organizations/<org>/issues/<id>/` endpoint returns `403` on the read-only `SENTRY_AUTH_TOKEN`/`SENTRY_API_TOKEN` (they carry Discover/ingest scope, not `event:read` on the issue resource). Using the read token here makes the `curl -sfS` GET exit non-zero, leaving `ISSUE_JSON` empty → `ISSUE_STOPPED` stuck `false` → auto-resolve never fires. Resolve the RW token first; if it is absent, skip this phase (warn) since the GET cannot succeed without it.

```bash
# ISSUE_ID = the Sentry issue short-id or numeric id from the PR/issue body
# (a bare token: letters, digits, `-`, `_`). DEPLOY_TS = the merge commit's
# committer date (Phase 1 recorded the merge SHA) — the reference point for
# "did the error stop firing post-deploy?".
DEPLOY_TS=$(git show -s --format=%cI "<merge-commit-sha-from-phase-1>")
# The single-issue endpoint needs the write-scoped token (read tokens 403 here).
# Reused by the auto-resolve PUT below, so resolve it once. Absent → skip phase.
SENTRY_RW_TOKEN=$(doppler secrets get SENTRY_ISSUE_RW_TOKEN -p soleur -c prd --plain 2>/dev/null || true)
if [[ -z "$SENTRY_RW_TOKEN" ]]; then
  echo "WARNING: SENTRY_ISSUE_RW_TOKEN not set — cannot read the issue (read tokens 403 on /issues/<id>/). Skipping error-count delta + auto-resolve."
fi
# Query the issue; capture the response so the auto-resolve guard below can
# read status + lastSeen without a second GET.
ISSUE_JSON=$(curl -sfS -H "Authorization: Bearer ${SENTRY_RW_TOKEN}" \
  "https://${API_HOST}/api/0/organizations/${SENTRY_ORG}/issues/${ISSUE_ID}/")
echo "$ISSUE_JSON" | jq '{shortId, status, count, lastSeen}'
ISSUE_STATUS=$(echo "$ISSUE_JSON" | jq -r '.status')
ISSUE_LASTSEEN=$(echo "$ISSUE_JSON" | jq -r '.lastSeen')
# Mechanical stopped-firing signal — this boolean, NOT the prose below, gates
# the auto-resolve PUT. True only when the issue is already resolved/ignored OR
# lastSeen predates the deploy. Any parse failure leaves it false (fail-safe:
# never auto-resolve on ambiguous data).
ISSUE_STOPPED=false
if [[ "$ISSUE_STATUS" == "resolved" || "$ISSUE_STATUS" == "ignored" ]]; then
  ISSUE_STOPPED=true
elif [[ -n "$ISSUE_LASTSEEN" && "$ISSUE_LASTSEEN" != "null" ]]; then
  LASTSEEN_EPOCH=$(date -d "$ISSUE_LASTSEEN" +%s 2>/dev/null || echo 9999999999)
  DEPLOY_EPOCH=$(date -d "$DEPLOY_TS" +%s 2>/dev/null || echo 0)
  (( LASTSEEN_EPOCH < DEPLOY_EPOCH )) && ISSUE_STOPPED=true
fi
```

Interpretation (all outcomes are **WARN-only — never a merge blocker**):

- `lastSeen` is older than the deploy timestamp **or** `status` is `resolved`/`ignored` (`ISSUE_STOPPED=true`): "Sentry error-count delta: error appears to have stopped firing post-deploy." — the expected good outcome; report `STOPPED` (or `AUTO-RESOLVED` if the write below succeeds). **Auto-resolve runs in this branch only** (see below).
- `lastSeen` is after the deploy timestamp (`ISSUE_STOPPED=false`): "WARNING: Sentry issue `<shortId>` is still firing after the deploy (lastSeen <ts>). The fix may be ineffective or the root cause may differ from the diagnosis — recommend re-opening for investigation rather than closing." Report `STILL-FIRING` and surface it prominently in the Phase 7 report. **Never auto-resolve in this branch.**
- Sentry API unreachable / issue not found / non-200: warn and report `SKIPPED`.

**Auto-resolve (expected-good-outcome branch only).** When the GET above shows the error has stopped firing (`lastSeen` older than the deploy **or** `status` already `resolved`/`ignored`) **and** the issue is not already `resolved`, PUT `status:"resolved"` so the historical issue leaves the active list automatically. This requires a dedicated write-scoped token — the `SENTRY_AUTH_TOKEN`/`SENTRY_API_TOKEN` read tokens lack `event:write`/`event:admin` and return 403 on the write endpoint, so resolve a separate token and **skip (do NOT fall back to a read token)** when it is absent:

```bash
# SENTRY_RW_TOKEN was already resolved in Phase 3.6 above (the issue GET needs
# it too). Reused here for the PUT.

# Fire ONLY when the mechanical ISSUE_STOPPED signal is true (the still-firing
# branch is structurally unreachable here, never prose-gated), a write token is
# present, the issue is not already resolved, and ISSUE_ID is a bare token (the
# regex blocks a crafted id with `/`/`?` from retargeting a different issue on
# this state-mutating PUT). Body is discarded (-o /dev/null) — it returns the
# full issue object, which can carry production event data; only the HTTP code
# is load-bearing.
if [[ -n "$SENTRY_RW_TOKEN" && "$ISSUE_STOPPED" == "true" && "$ISSUE_STATUS" != "resolved" \
      && "$ISSUE_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
  RESOLVE_HTTP=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
    -H "Authorization: Bearer ${SENTRY_RW_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"status":"resolved"}' \
    "https://${API_HOST}/api/0/organizations/${SENTRY_ORG}/issues/${ISSUE_ID}/")
  if [[ "$RESOLVE_HTTP" == "200" ]]; then
    echo "Sentry error-count delta: AUTO-RESOLVED issue ${ISSUE_ID}."
  else
    echo "WARNING: Sentry issue auto-resolve failed (${RESOLVE_HTTP}): verify SENTRY_ISSUE_RW_TOKEN has event:admin on ${SENTRY_ORG}; resolve manually in the UI."
  fi
fi
```

The PUT reuses the SAME `API_HOST`/`SENTRY_ORG` resolution as the GET above, so it inherits the env-correct `jikigai-eu` host from Doppler `prd`. On any non-200 (403 under-scoped, transient) it emits a WARN and continues — **never blocks**. Report vocabulary for this phase is `AUTO-RESOLVED` (write succeeded) / `STOPPED` (stopped firing, no token or already resolved) / `STILL-FIRING` / `SKIPPED`.

**Why WARN-only, not a blocker:** a true pre/post delta needs the original error to actually re-fire in the brief post-merge window. Low-frequency bugs (daily-cron failures, rare-path exceptions) legitimately show zero events for hours after a correct fix, so a hard gate here would produce noisy false negatives that erode trust in the pipeline. The signal is a prompt to *look*, not a verdict. For high-frequency errors a continued-firing signal is strong evidence the fix missed; consider a `/loop` re-check 15–30 min out before marking the linked issue resolved.

## Phase 3.7: First-Deploy-After-Pipeline-Change Watch

Enforces `wg-dark-launch-deploy-gates`. A change to deploy-*gating* logic cannot be validated by the same deploy it gates: if the changed gate is itself broken, the *first* post-merge deploy rolls back, and the rollback looks like a bad app deploy rather than a bad gate. This phase makes that case explicit so the gating change — not the app — is suspected first.

**Trigger (skip the phase if none match).** Check whether the merged PR touched deploy-gating logic:

```bash
# Did this PR change a gate that can roll back / block a deploy?
gh pr diff <number> --name-only | grep -qE 'apps/web-platform/infra/ci-deploy\.sh|apps/web-platform/infra/ci-deploy-wrapper\.sh' && PIPELINE_GATE_CHANGE=1
# Also treat changes to the gating phases of the ship/postmerge skills as pipeline-gate changes.
gh pr diff <number> --name-only | grep -qE 'plugins/soleur/skills/(ship|postmerge)/SKILL\.md' && PIPELINE_GATE_CHANGE=1
```

If `PIPELINE_GATE_CHANGE` is unset, skip to Phase 4.

**Watch the first post-merge release run** (the one Phase 2/3 already identified) for a canary rollback:

```bash
# The release run triggered by this merge (apps/web-platform/** path filter).
RELEASE_RUN_ID=$(gh run list --branch main --workflow web-platform-release.yml \
  --limit 1 --json databaseId --jq '.[0].databaseId')
# REASON is written by ci-deploy.sh's final_write_state. A canary gate that
# rejected a HEALTHY host surfaces as one of these.
RUN_CONCLUSION=$(gh run view "$RELEASE_RUN_ID" --json conclusion --jq '.conclusion')
ROLLBACK_REASON=$(gh run view "$RELEASE_RUN_ID" --log 2>/dev/null \
  | grep -oE 'reason=(canary_sandbox_failed|production_start_failed|canary_[a-z_]+)' | head -1)
```

**Interpretation:**

- Release **succeeded**: the changed gate passed on a real deploy — the dark-launch observation is satisfied. Report `GATE-VALIDATED`.
- Release **failed with a canary/sandbox rollback reason** AND this PR changed gating logic: **suspect the gate, not the app.** A gating check that diverged from production reality (e.g. a synthetic probe that does not match what runs in prod) blocks every deploy. Recommended action: **revert the gating change immediately** (it is unvalidated by definition — its first real deploy rolled back), restore the prior known-good gate, and re-deploy; investigate the probe separately and re-introduce it NON-BLOCKING per `wg-dark-launch-deploy-gates`. Report `GATE-SUSPECT — revert recommended` and surface it at the top of the Phase 7 report.
- Release failed with a non-gate reason (build, migration, unrelated infra): ordinary deploy failure — investigate normally; do not assume the gate.

**Why a watch and not a pre-merge block:** the only faithful validation of a deploy gate is a real deploy, which by definition happens post-merge. The pre-merge half of the rule — ship the gate non-blocking first — lives in `wg-dark-launch-deploy-gates`; this phase is the safety net that catches a gate shipped blocking-first anyway, turning "every deploy silently rolls back" into a named, one-revert recovery. **Why:** #4932 — a canary bwrap probe validated only against an always-succeeding test mock failed on a healthy host and rolled back every web-platform deploy until reverted (#4941).

## Phase 3.8: Feature-Tweet Draft (green-gated)

Convert a feature **confirmed live** into a draft short-form X post. Runs
eligibility FIRST, then gates the draft on `HEALTH_VERIFIED` (set in Phase 3).

```bash
bash scripts/lib/tweet-eligibility.sh <merged-pr-number>
```

Branch on the result:

- **Ineligible** (exit non-zero, `excluded: <reason>`) → **silent no-op.** Most
  PRs land here (fixes, infra, non-product); exclusion is the designed outcome,
  not a fault. Do not surface it in the report.
- **Eligible AND `HEALTH_VERIFIED=true`** → invoke the draft generator:

  ```
  /soleur:feature-tweet #<merged-pr-number>
  ```

  Display the resulting draft's **full content** (title + every X tweet + the
  Bluesky post) inline for operator approval — not just the path — then surface
  the path in the Phase 7 report with the operator instruction: "set BOTH
  `publish_date` and `status: scheduled` to publish." The path alone is
  insufficient: the operator cannot approve copy they cannot see, and a
  worktree-resident draft can be discarded by cleanup before they open it
  (`feature-tweet` SKILL.md §Output owns the display-for-approval contract).
- **Eligible AND `HEALTH_VERIFIED=false`** → do NOT draft (no verified-live
  signal). Print a catch-up instruction instead of silently skipping:

  > Eligible PR #N shipped but no production-health signal was verified — no
  > draft written. After confirming the deploy, run `/soleur:feature-tweet #N`.

**Multi-PR contract (explicit v1):** one tweet per eligible PR, using postmerge's
single bound PR number. If a deploy bundled multiple PRs, only the bound PR is
drafted — note in the Phase 7 report that other eligible PRs need the standalone
catch-up path. `/soleur:merge-pr`-only flows bypass this hook by design; the
recovery is standalone `/soleur:feature-tweet #N`.

## Phase 4: Verify File Freshness

Read key files from the merged commit to verify they match expectations -- NOT from the bare repo filesystem which may contain stale content.

For each file changed in the PR:

```bash
gh pr diff <number> --name-only
```

Spot-check up to 5 files by reading from the merged main:

```bash
git show main:<filepath>
```

Compare against expectations from the PR description and review. Flag if any file content seems stale or doesn't reflect the PR changes.

## Phase 5: Browser Verification (Conditional)

**Skip if:** The PR has no UI changes (no `.tsx`, `.css`, `.html` files in the diff).

**If UI changes exist:**

1. Start the dev server if not running (or use the production URL if available)
2. Use Playwright MCP to navigate to affected pages
3. Take screenshots of key states
4. Check browser console for errors (especially CSP violations)
5. Verify no broken resources or layout regressions

If Playwright MCP is unavailable, warn and skip:

```text
WARNING: Playwright MCP unavailable. Skipping browser verification.
```

## Phase 6: Update Issue and Compound

If the PR body contained `Closes #N`, update the linked issue with verification results:

```bash
gh issue comment <issue-number> --body "Post-merge verification complete for PR #<pr-number>.

- CI on main: PASSED
- Production health: <PASSED/SKIPPED/FAILED>
- Sentry monitors: <HEALTHY/WARNING/SKIPPED>
- Sentry error-count delta: <AUTO-RESOLVED/STOPPED/STILL-FIRING/SKIPPED>
- File freshness: <PASSED/N files checked>
- Browser verification: <PASSED/SKIPPED>
"
```

Run compound to capture any learnings from the merge:

```
skill: soleur:compound
```

## Phase 7: Report

Print a summary:

```text
postmerge verification complete!

PR: #<number>
Merge commit: <sha>
CI on main: PASSED
Production health: <PASSED/SKIPPED/FAILED>
Sentry monitors: <HEALTHY/WARNING/SKIPPED>
Sentry error-count delta: <AUTO-RESOLVED/STOPPED/STILL-FIRING/SKIPPED>
File freshness: <N files verified>
Browser verification: <PASSED/SKIPPED>
Feature-tweet draft: <path + "flip publish_date + status: scheduled to publish" / CATCH-UP: run /soleur:feature-tweet #N / NONE — ineligible>
```

## Graceful Degradation

| Missing Prerequisite | Behavior |
|---------------------|----------|
| No production URL | Skip health check with warning |
| No `SENTRY_AUTH_TOKEN` | Skip Sentry cron monitor check AND error-count delta with warning |
| No `SENTRY_ISSUE_RW_TOKEN` | Skip the entire error-count-delta + auto-resolve phase (the single-issue GET 403s on read tokens); recommend manual resolution as today |
| Sentry API unreachable | Skip Sentry cron monitor check with warning |
| No Sentry issue identified in PR/linked issue | Skip error-count delta silently (nothing to measure) |
| Sentry issue not found via API | Skip error-count delta with warning |
| Playwright MCP unavailable | Skip browser verification with warning |
| CI run not found | Poll up to 5 minutes, then warn and proceed |
| No UI files in diff | Skip browser verification entirely |
| No linked issue | Skip issue comment |

## Notes

- Always use `git show main:<path>` to read merged files -- never read from the bare repo filesystem directly.
- MCP tools resolve paths from the repo root. Use absolute paths when in a worktree.
- This skill is designed to run after `/soleur:merge-pr` completes. It can also be invoked standalone with a PR number.

## Production Debugging

- For production debugging use Sentry API (`SENTRY_API_TOKEN` in Doppler `prd`), Better Stack, or `/health` — never SSH for logs. SSH is for infra provisioning only. (ex-`cq-for-production-debugging-use`)
- For deploy webhook debugging, fetch `WEBHOOK_DEPLOY_SECRET`/`CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET` from Doppler `prd_terraform` (not `prd`). GET `https://deploy.soleur.ai/hooks/deploy-status` with CF Access headers + HMAC-sha256 over empty body. Full runbook: [deploy-status-debugging.md](./references/deploy-status-debugging.md). (ex-`cq-deploy-webhook-observability-debug`)
- Doppler env values on prd are baked into the container at start via `--env-file` (cloud-init.yml). Flipping a flag in Doppler does NOT affect the running container — POST-X gates that depend on a freshly-flipped flag must redeploy the current image tag (POST to `/hooks/deploy`) between the flip and the verification smoke. Full context: [2026-05-19-doppler-env-hot-reload-limitation.md](../../../../knowledge-base/project/learnings/2026-05-19-doppler-env-hot-reload-limitation.md).
