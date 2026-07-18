---
name: postmerge
description: "This skill should be used when verifying a merged PR deployed correctly and production is healthy."
---

# postmerge Skill

<!-- postmerge-harness-protocol:start -->
## Harness adapter (Claude vs Grok Build)

Invoke via **Claude:** `soleur:postmerge <PR>` | **Grok:** `/postmerge <PR>`.

**Polling CI / health checks without asking the operator:**
- **Claude Code:** Monitor tool for Phase 2 main CI and Phase 3 health retries.
- **Grok Build:** AwaitShell with `pattern` (`completed success`, `postmerge verification complete`) or Shell with `block_until_ms`.

Canonical: `plugins/soleur/lib/harness.ts` → `pollInstructions()`. Parent skills (`ship` Step 3.8, `one-shot` Step 8) MUST invoke postmerge before `<promise>DONE</promise>`.
<!-- postmerge-harness-protocol:end -->

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

Find the run matching the merge commit SHA. If no matching run yet, poll with the harness adapter (max 5 minutes) — **Claude:** Monitor tool; **Grok:** AwaitShell/Shell per `pollInstructions()`. Do NOT ask the operator to watch CI. Do NOT use Bash `run_in_background`:

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

### Inngest liveness awareness (#6374)

Surface any OPEN inngest-down alarm so the operator is never told "prod is healthy" while the durable trigger layer (armed reminders + all `server/inngest/functions/` crons) is dark. The external watchdog (`scheduled-inngest-health.yml`) files `[ci/inngest-down]` on a confirmed down; this is a cheap read that needs no Sentry token:

```bash
gh issue list --label ci/inngest-down --state open \
  --json number,title,createdAt --jq '.[] | "#\(.number) \(.title) (opened \(.createdAt))"'
```

- If it prints an open issue: surface a one-line advisory — "ADVISORY: inngest reports down (`#<n>`) — armed reminders and scheduled crons may not be firing; the external watchdog is auto-restarting / escalating. Do not assume scheduled work ran." Include it prominently in the Phase 7 report.
- If empty: silent (no line needed).

**Advisory only — never hard-block the turn.** inngest-down does not block all work; the operator retains agency. (An optional deeper probe — `curl` the `/hooks/inngest-liveness` HMAC+CF-Access hook — is available for a live verdict but is not required here; the open-issue read is the cheap default.)

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

## Phase 3.8: Feature-Tweet Draft (verify + display)

The draft is now generated **pre-merge by `/ship`** (Phase 6 "Feature-Tweet
Draft (pre-merge bundle)") and committed to the feature branch, so for the
normal `/one-shot` / `/ship` flow it ALREADY landed on `main` with this PR —
where `content-publisher.sh` reads from. This phase **verifies** that on-`main`
draft, **displays** it for approval, and warns when deploy health is unverified.
It only *generates* a draft as a catch-up when `/ship` was hand-rolled and the
draft never landed.

```bash
bash scripts/lib/tweet-eligibility.sh <merged-pr-number>
```

Branch on eligibility, then on whether the draft is already on `main`:

- **Ineligible** (exit non-zero, `excluded: <reason>`) → **silent no-op.** Most
  PRs land here (fixes, infra, non-product); exclusion is the designed outcome,
  not a fault. Do not surface it in the report.
- **Eligible AND a draft for this PR is on `main`** (the `/ship` pre-merge
  bundle worked — detect via
  `git grep -l 'pr_reference: "#<merged-pr-number>"' origin/main -- knowledge-base/marketing/distribution-content/`):
  **display the draft's full content** (title + every X tweet + the Bluesky
  post) inline for operator approval — read it back from `main`
  (`git show origin/main:<path>`), never reproduce from memory. Then:
  - `HEALTH_VERIFIED=true` → operator instruction: "the draft is on `main`; set
    BOTH `publish_date` and `status: scheduled` to publish."
  - `HEALTH_VERIFIED=false` → **warn, do not block:** "the draft is on `main`
    but production health was NOT verified — do NOT set `status: scheduled`
    until you confirm the deploy is live." (The draft is inert until then.)

  The display-for-approval contract is owned by `feature-tweet` SKILL.md
  §Output; the path alone is insufficient (the operator cannot approve copy they
  cannot see).
- **Eligible BUT no draft on `main`** (a hand-rolled `/ship` skipped the
  pre-merge bundle) → catch-up: invoke the draft generator, display it, and note
  it needs a follow-up commit to reach `main`:

  ```
  /soleur:feature-tweet #<merged-pr-number>
  ```

  > Eligible PR #N had no feature-tweet draft on `main` (the `/ship` pre-merge
  > bundle was skipped). Generated a catch-up draft — commit it to `main` via a
  > follow-up PR so `content-publisher.sh` can drain it, then set `publish_date`
  > + `status: scheduled` once the deploy is confirmed.

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

If Playwright MCP is unavailable, do NOT warn-and-skip — **fall through to the
committed harness path** (Phase 5.5 below), which drives the deployed app via the
chromium bundled in `@playwright/test` with no MCP-browser dependency. The
warn-and-skip punt is exactly what let the #5391/#5421/#5436 broken fixes pass
green. Record `Browser verification: DELEGATED-TO-LIVE-VERIFY` and proceed.

## Phase 5.5: Live Verification (path-triggered, REPORT-ONLY)

Verifies the **deployed artifact** for the PR classes where the mock-hermetic e2e
suite structurally lies (realtime / server-commit-timing / session-auth /
DOM-server-timing — the #5391→#5421→#5436 class). The harness
(`apps/web-platform/scripts/live-verify/run.ts`, #5452 / ADR-064) signs in as a
dedicated **synthetic prod principal** (never an operator/real-user session),
drives the deployed UI, and asserts a freshly-started conversation appears in the
Recent Conversations rail.

**Dark-launch posture (`wg-dark-launch-deploy-gates`):** this gate ships
**REPORT-ONLY**. It records and surfaces a tri-state result but does **NOT** block
"done". The empty→FAIL-closed + FAIL-blocks-done flip is tracked in **#5463**, and
that flip **also requires re-homing the harness into a GitHub Action /
`workflow_dispatch` with a Sentry-observable result** (ADR-033 Option C) — a
boolean flip inside this agent-driven skill is NOT acceptable for a blocking gate
(it would recreate the #4932 non-deterministic-blocking-gate class).

**1. Path trigger (FR7).** The trigger set is the committed source-of-truth
`apps/web-platform/scripts/live-verify/trigger-paths.txt` (not SKILL.md prose).
Reuse Phase 4's changed-file list and match:

```bash
changed=$(gh pr diff <number> --name-only)
patterns=$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' \
  apps/web-platform/scripts/live-verify/trigger-paths.txt)
if printf '%s\n' "$changed" | grep -qE -f <(printf '%s\n' "$patterns"); then
  TRIGGERED=1
else
  TRIGGERED=0   # pure logic/docs/copy/config → skip (fail-open; the drift
                # canary test guards against an un-listed new realtime dir)
fi
```

If `TRIGGERED=0`: record `Live verification: SKIPPED (no triggering paths)` and
continue to Phase 6.

**2. Run the harness (report-only).** The harness needs Doppler `prd` secrets
(`LIVE_VERIFY_USER_PASSWORD`, `LIVE_VERIFY_EXPECTED_UID/REF`, the Supabase
anon-key, `PRODUCTION_URL`). It is service-role-free (AC2b) and message-minimal
(I-action-send-free). Run from the app dir under `prd`:

```bash
cd apps/web-platform && \
  doppler run -p soleur -c prd -- bun run scripts/live-verify/run.ts \
  2>&1 | grep -E '^RESULT: '
```

**Runner browser (#5485).** If this host's OS does not support the bundled
`@playwright/test` chromium (`chromium.launch()` → `CANT-RUN:browser-launch:…`),
prepend a system-browser override — `LIVE_VERIFY_BROWSER_CHANNEL=chrome` (or
`LIVE_VERIFY_BROWSER_PATH=/path/to/chrome`) — to the `doppler run` line. Unset on
ubuntu-latest (bundled chromium works); see ADR-064 §"Runner browser + cookie
shape". The terminal substrate for the blocking flip is the GH-Action re-home
(#5463 item 3), not this override.

The harness emits exactly one structured line: `RESULT: PASS`,
`RESULT: FAIL — <redacted detail>`, or `RESULT: CANT-RUN:<reason>`. Empty output
is treated as `CANT-RUN:no-result-line` (fail-closed semantics for the result
*recording*, even though the gate is report-only for "done"). If the harness
cannot bootstrap (synthetic principal not yet seeded — see
`apps/web-platform/scripts/bootstrap-live-verify.sh`), expect `CANT-RUN:CONFIG:…`.

**3. Record + surface the tri-state.** Always surface the result; never silently
drop it:

- `PASS` → record `Live verification: PASS`.
- `FAIL` → record `Live verification: FAIL — <detail>` and **surface prominently**
  (this is the regression the gate exists to catch). Report-only: it does not
  block "done" on this PR, but it is the signal the #5463 flip will gate on.
- `CANT-RUN:<reason>` → record `Live verification: CANT-RUN:<reason>` and
  **auto-file a tracking issue** (`wg-when-deferring-a-capability`):

```bash
gh issue create --label type/chore \
  --title "live-verify CANT-RUN: <reason> (PR #<number>)" \
  --body "deferred-automation backlog item; the live-verify harness could not complete.
reason: <reason>
re-evaluate when: synthetic principal seeded / deploy URL reachable / teardown invariant restored.
Tracks the #5463 blocking-flip precondition."
```

A `CANT-RUN:CANT-TEARDOWN-has-action-sends` reason is an invariant breach (the
synthetic principal acquired a WORM `action_sends` row) — escalate it, do NOT
reap-next-run.

## Phase 6: Update Issue and Compound

If the PR body contained `Closes #N`, update the linked issue with verification results:

```bash
gh issue comment <issue-number> --body "Post-merge verification complete for PR #<pr-number>.

- CI on main: PASSED
- Production health: <PASSED/SKIPPED/FAILED>
- Sentry monitors: <HEALTHY/WARNING/SKIPPED>
- Sentry error-count delta: <AUTO-RESOLVED/STOPPED/STILL-FIRING/SKIPPED>
- File freshness: <PASSED/N files checked>
- Browser verification: <PASSED/SKIPPED/DELEGATED-TO-LIVE-VERIFY>
- Live verification: <PASS/FAIL/CANT-RUN:reason/SKIPPED> (report-only, #5463)
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
Browser verification: <PASSED/SKIPPED/DELEGATED-TO-LIVE-VERIFY>
Live verification: <PASS/FAIL/CANT-RUN:reason/SKIPPED> (report-only, #5463)
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

- For production debugging use Sentry API (`SENTRY_API_TOKEN` in Doppler `prd`), Better Stack, or `/health` — never SSH for logs. SSH is for infra provisioning only. (ex-`cq-for-production-debugging-use`) To read a Sentry issue/event by id inline, use `doppler run -p soleur -c prd -- scripts/sentry-issue.sh <id>` (runbook `knowledge-base/engineering/operations/runbooks/sentry-issue-read.md`); for host/app logs use [betterstack-query.sh](../../../../scripts/betterstack-query.sh) (runbook `betterstack-log-query.md`).
- For deploy webhook debugging, fetch `WEBHOOK_DEPLOY_SECRET`/`CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET` from Doppler `prd_terraform` (not `prd`). GET `https://deploy.soleur.ai/hooks/deploy-status` with CF Access headers + HMAC-sha256 over empty body. Full runbook: [deploy-status-debugging.md](./references/deploy-status-debugging.md). (ex-`cq-deploy-webhook-observability-debug`)
- Doppler env values on prd are baked into the container at start via `--env-file` (cloud-init.yml). Flipping a flag in Doppler does NOT affect the running container — POST-X gates that depend on a freshly-flipped flag must redeploy the current image tag (POST to `/hooks/deploy`) between the flip and the verification smoke. Full context: [2026-05-19-doppler-env-hot-reload-limitation.md](../../../../knowledge-base/project/learnings/2026-05-19-doppler-env-hot-reload-limitation.md).
