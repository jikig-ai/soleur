---
name: postmerge
description: "This skill should be used when verifying a merged PR deployed correctly and production is healthy."
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# postmerge Skill

<!-- postmerge-harness-protocol:start -->
## Harness adapter (Claude vs Grok Build)

Invoke via **Claude:** `soleur:postmerge <PR>` | **Grok:** `soleur:postmerge <PR>`.

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
STOPPED: PR #<number> is not merged (state: <state>). Run soleur:merge-pr first.
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

Ship refuses post-deploy actions on `CI=failure` too. Still run Phase 3's `find`: a `MATCH=descendant DEPLOY=success` line means production carries the merge via `<DEPLOYED_SHA>` — say so.

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

Use `/health` (the public, middleware-/CSP-bypassed health route returning `{"status":"ok","version","build_sha","supabase","sentry",...}`), NOT `/api/health` — the latter is an authenticated API route that 307-redirects an unauthenticated probe to `/login`, so `curl -sf` fails and `HEALTH_VERIFIED` is left `false` even when production is healthy. For this repo, `build_sha` is judged by `deploy-arm.sh` below.

**This repo (`web-platform-release.yml` present):** identify the deploy and what production serves, with literal arguments (no command substitution) and the FULL 40-hex merge sha (a short one matches nothing, #8135). First wait for `find` — it polls about once a minute for up to 120 polls and prints one line; watch it with the harness poller (**Claude:** Monitor tool, matching `^ARM=`; **Grok:** AwaitShell), never Bash `run_in_background`. Only once that line has arrived with rc ≠ 4, run `served`:

```bash
bash plugins/soleur/scripts/deploy-arm.sh find --wait <full-merge-sha>
bash plugins/soleur/scripts/deploy-arm.sh served <full-merge-sha>
```

First matching row wins:

| `find` | `served` | result |
|---|---|---|
| any | `UNRESOLVED` | could-not-measure, never a mismatch |
| rc 2 (`REASON=error`) | any | could-not-measure; report `CAUSE` |
| `DEPLOY=skipped` | any | not deployed by design (`CI=failure` → CI red, Phase 2) |
| `DEPLOY=success\|superseded`, or rc 3 `ARM=none` (incl. `timeout`) | `CONTAINS` | verified — `MATCH=descendant`/`superseded`/`ARM=none` mean a later deploy (or a manual redeploy) delivered it |
| `DEPLOY=failure\|blocked` | `CONTAINS` | verified via a later deploy; still report this merge's own failed deploy and name the job |
| any other | `NOT_CONTAINED` | not verified — report the `find` line; if it said `DEPLOY=success`, production does not serve the merge (lagging host or rollback): report prominently |

**If health check succeeds:** HTTP 200 alone is NOT success — `/health` returns 200 with `status: "ok"` whatever the database state, and only `.supabase` flips to `"error"`. Require `jq -e '.supabase == "connected"'` (and, here, the table above) before recording the response and setting `HEALTH_VERIFIED=true`. A 200 with `supabase: "error"` is a production database outage: set `HEALTH_VERIFIED=false`, report it prominently, and diagnose per §Production Debugging (2026-09-15 post-mortem `prd-supabase-database-unreachable-2026-09-15-postmortem.md`).

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

When a Sentry issue is identified, read [sentry-error-count-delta.md](./references/sentry-error-count-delta.md) now and run it; otherwise skip silently. It holds the prerequisites, the issue GET, the interpretation and the guarded auto-resolve PUT.

Report vocabulary for this phase (Phase 7 reads it): `AUTO-RESOLVED` (write succeeded) / `STOPPED` (stopped firing, no token or already resolved) / `STILL-FIRING` / `SKIPPED`. All outcomes are WARN-only, never a merge blocker.

## Phase 3.7: First-Deploy-After-Pipeline-Change Watch

Enforces `wg-dark-launch-deploy-gates`. A change to deploy-*gating* logic cannot be validated by the same deploy it gates: if the changed gate is itself broken, the *first* post-merge deploy rolls back, and the rollback looks like a bad app deploy rather than a bad gate. This phase makes that case explicit so the gating change — not the app — is suspected first.

**Trigger (skip the phase if none match).** Check whether the merged PR touched deploy-gating logic:

```bash
# Did this PR change a gate that can roll back / block a deploy?
gh pr diff <number> --name-only | grep -qE 'apps/web-platform/infra/ci-deploy\.sh|apps/web-platform/infra/ci-deploy-wrapper\.sh' && PIPELINE_GATE_CHANGE=1
# Also treat changes to the gating phases of the ship/postmerge skills as pipeline-gate changes.
gh pr diff <number> --name-only | grep -qE 'plugins/soleur/skills/(ship|postmerge)/SKILL\.md|plugins/soleur/scripts/deploy-arm\.sh' && PIPELINE_GATE_CHANGE=1
```

If `PIPELINE_GATE_CHANGE` is unset, skip to Phase 4.

**Watch the first post-merge release run** (the one Phase 2/3 already identified) for a canary rollback.

**Select the DEPLOY arm, not "the latest run".** Since #5806 / ADR-217 `web-platform-release.yml` is split across two triggers, so every merge produces **two** runs of it:

| arm | trigger | jobs |
|---|---|---|
| push arm | `on: push` to `main` | `release` only (build + publish) |
| deploy arm | `on: workflow_run` (CI completed) | `resolve-target`, `migrate`, `verify-migrations`, `verify-doppler-secrets`, `deploy`, `live-verify`, `notify-gated`, `release-outcome` |

`--limit 1` with no event filter lands on the push arm roughly half the time, where `deploy` exists only as a `skipped` job — a false green against an empty log. **Identify the deploy arm by what its `resolve-target` checks out, never by `head_sha`:** a `workflow_run` run's `head_sha` is `main`'s tip when it fired, so a `head_sha=<merge>` query misses your arm on a busy `main` (#8297) and returns the previous merge's arm (#8391). `deploy-arm.sh find` reads each candidate's checked-out SHA and accepts your merge or a descendant (#8492).

Reuse Phase 3's `find` line (run `bash plugins/soleur/scripts/deploy-arm.sh find <full-merge-sha>` if Phase 3 did not). Copy the digits after `ARM=` literally into the next call; `ARM=none` means there is no run — never pass `none` to `gh run view`. Rollback reason:

```bash
gh run view <ARM digits> --log 2>/dev/null | grep -oE 'reason=(canary_sandbox_failed|production_start_failed|canary_[a-z_]+)' | head -1
```

**A green `live-verify` is not evidence it ran:** it can be `success` with the harness and every
substantive step `skipped` by its changed-file gate — read the step list. **Probe
`app.soleur.ai/health`** (`web-platform-release.yml:1288`); the apex returns an EMPTY body —
could-not-measure, reported UNRESOLVED, never a mismatch. **Why:** #8265, #8297, #8391 — each a
selector that returned another merge's arm, or none, while the real arm had deployed.

**Interpretation** (by `MATCH` and `DEPLOY`):

- `exact` + `success` → `GATE-VALIDATED`. `descendant` + `success` → `GATE-VALIDATED (via <DEPLOYED_SHA>, run <ARM>)`.
- `DEPLOY=skipped` → `GATE-NOT-EXERCISED`: the arm clean-skipped (docs-only; `CI=failure` → `ci_not_green`) — the `workflow_run` trigger inherits neither `on.push.paths` nor `check_changed` (ADR-217). Neither a failure nor a validation; the watch stays open until a merge that deploys.
- `DEPLOY=superseded|blocked` → `GATE-INDETERMINATE — <DEPLOY>` (lock-queue cancellation; a resolve/migrate/verify job failed).
- `DEPLOY=blocked` from `resolve-target`: read its reason, which the annotation carries (job outputs are not readable through the API): `gh run view <ARM> --json jobs --jq '.jobs[] | select(.name=="resolve-target") | .databaseId'`, then `gh api repos/jikig-ai/soleur/check-runs/<id>/annotations --jq '.[].message'` and match `[skip_reason=<reason>]`. For `release_run_missing` or `github_api_unavailable` (a lookup failure, not a broken release) recover yourself: `gh run rerun <ARM> --failed` once, then re-arm `deploy-arm.sh find --wait`; if it fails the same way, wait ~15 minutes and retry once more. Never re-run the push-arm run. Any other reason (`release_failed`, `identity_mismatch`, `schema_mismatch`, …) is not a re-run case — report it.
- rc 2/3 `ARM=none` (incl. `timeout`, `error`) → `GATE-INDETERMINATE — <REASON> <CAUSE>`: absence of evidence, never a pass. rc 4 → still pending; poll.
- `descendant` + `failure` → `GATE-SUSPECT`: list `git log --oneline <merge>..<DEPLOYED_SHA>` beside this PR's gate diff — the failure may be the later merge's, so do not recommend an immediate revert.
- `exact` + `failure` with a canary/sandbox rollback reason AND this PR changed gating logic: **suspect the gate, not the app.** A gating check that diverged from production reality (e.g. a synthetic probe that does not match what runs in prod) blocks every deploy. Recommended action: **revert the gating change immediately** (it is unvalidated by definition — its first real deploy rolled back), restore the prior known-good gate, and re-deploy; investigate the probe separately and re-introduce it NON-BLOCKING per `wg-dark-launch-deploy-gates`. Report `GATE-SUSPECT — revert recommended` and surface it at the top of the Phase 7 report.
- Release failed with a non-gate reason (build, migration, unrelated infra): ordinary deploy failure — investigate normally; do not assume the gate.

**Why a watch and not a pre-merge block:** the only faithful validation of a deploy gate is a real deploy, which by definition happens post-merge. The pre-merge half of the rule — ship the gate non-blocking first — lives in `wg-dark-launch-deploy-gates`; this phase is the safety net that catches a gate shipped blocking-first anyway, turning "every deploy silently rolls back" into a named, one-revert recovery. **Why:** #4932 — a canary bwrap probe validated only against an always-succeeding test mock failed on a healthy host and rolled back every web-platform deploy until reverted (#4941).

## Phase 3.8: Feature-Tweet Draft (verify + display)

The draft is now generated **pre-merge by `soleur:ship`** (Phase 6 "Feature-Tweet
Draft (pre-merge bundle)") and committed to the feature branch, so for the
normal `soleur:one-shot` / `soleur:ship` flow it ALREADY landed on `main` with this PR —
where `content-publisher.sh` reads from. This phase **verifies** that on-`main`
draft, **displays** it for approval, and warns when deploy health is unverified.
It only *generates* a draft as a catch-up when `soleur:ship` was hand-rolled and the
draft never landed.

```bash
bash scripts/lib/tweet-eligibility.sh <merged-pr-number>
```

Branch on eligibility, then on whether the draft is already on `main`:

- **Ineligible** (exit non-zero, `excluded: <reason>`) → **silent no-op.** Most
  PRs land here (fixes, infra, non-product); exclusion is the designed outcome,
  not a fault. Do not surface it in the report.
- **Eligible AND a draft for this PR is on `main`** (the `soleur:ship` pre-merge
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
- **Eligible BUT no draft on `main`** (a hand-rolled `soleur:ship` skipped the
  pre-merge bundle) → catch-up: invoke the draft generator, display it, and note
  it needs a follow-up commit to reach `main`:

  ```
  soleur:feature-tweet #<merged-pr-number>
  ```

  > Eligible PR #N had no feature-tweet draft on `main` (the `soleur:ship` pre-merge
  > bundle was skipped). Generated a catch-up draft — commit it to `main` via a
  > follow-up PR so `content-publisher.sh` can drain it, then set both
  > `publish_date` and `status: scheduled` once the deploy is confirmed.

**Multi-PR contract (explicit v1):** one tweet per eligible PR, using postmerge's
single bound PR number. If a deploy bundled multiple PRs, only the bound PR is
drafted — note in the Phase 7 report that other eligible PRs need the standalone
catch-up path. `soleur:merge-pr`-only flows bypass this hook by design; the
recovery is standalone `soleur:feature-tweet #N`.

## Phase 4: Verify File Freshness

Read key files from the merged commit to verify they match expectations -- NOT from the bare repo filesystem which may contain stale content.

For each file changed in the PR:

```bash
gh pr diff <number> --name-only
```

**Fetch first.** The merge commit was created on the remote; nothing pulls it into a
local worktree as a side effect of the merge, so run `git fetch origin main` before the
first `git show`. Skipping this produces a false MISSING on every spot-checked file —
see the two-message table below, which is the tell.

Spot-check up to 5 files by reading from **the merge commit recorded in Phase 1** — not from the `main` ref:

```bash
git fetch origin main
git show <merge-commit-sha-from-phase-1>:<filepath>
```

**Read the failure message precisely — two of them are one word apart and mean opposite
things.** Measured against a real merge commit, with an all-zeros SHA as the control:

| message | what it actually means |
|---|---|
| `fatal: path 'X' does not exist in '<sha>'` | genuine answer: the file is NOT in that tree |
| `fatal: path 'X' exists on disk, but not in '<sha>'` | **git does not have that object** — it never read a tree |

The second is not a statement about the merge's contents. It is what git prints when the
commit is unknown to this repository, and it names the path anyway, so it reads exactly
like a content verdict. If Phase 4 reports files MISSING with that second wording, you
have an unfetched commit, not a bad merge — fetch and re-run before reporting anything.

**Query `actions/runs?head_sha=` with the FULL 40-char SHA, and refuse a verdict when `total_count` is below the
runs you expect.** A short SHA matches zero runs, and a poll that reports "0 pending" over an empty set reads as
`ALL_RUNS_COMPLETE` — a set must be proven non-empty before it can be reported drained. **Why:** PR #8135 — a
9-char `head_sha` returned `total_count:0` on the first tick and the Monitor declared all 15 post-merge runs
complete before any had started.

**Do NOT use `git show main:<path>` here.** `main` is a LOCAL ref and it lags: in a worktree or bare-repo layout nothing fast-forwards it as a side effect of the merge, so it routinely points at a commit from before this PR landed. Reading a file that this PR ADDED through a stale `main` returns `fatal: path ... does not exist`, and the phase whose entire job is answering *"did the merge land?"* then reports **MISSING** for a file that is present in the merge commit. The failure is silent and inverted — it manufactures a false alarm about the thing it is verifying, and it gets worse the busier the repo is.

`git rev-parse --short main` next to `git rev-parse --short origin/main` is the cheap tell when a result looks wrong. Prefer the merge SHA unconditionally: it is immutable, it is the exact tree that merged, and it cannot drift while the phase runs. `origin/main` is an acceptable second choice only immediately after a fetch, and even then a sibling merge can move it mid-phase.

Compare against expectations from the PR description and review. Flag if any file content seems stale or doesn't reflect the PR changes. **Why:** PR #7240 — Phase 4 read `git show main:` while local `main` sat 2 commits behind, reported the PR's own new learning file as MISSING, and the same stale ref undercounted `blkid` occurrences 2-vs-8 in a file the PR had rewritten. **And PR #7770** — Phase 4 addressed the merge SHA correctly, as the paragraphs above instruct, and still reported all 5 spot-checked files MISSING: the worktree had not fetched the merge commit, and git's `exists on disk, but not in <sha>` wording was read as a verdict about the tree. One `git fetch` made all 5 read correctly. Both failures are the same shape — Phase 4 manufacturing a false alarm about the merge it exists to confirm — reached by two different routes, which is why the fetch and the message table above are both load-bearing.

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
  **auto-file a tracking issue** (`wg-when-deferring-a-capability-create-a`):

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

## Phase 5.6: Registry-host delivery verdict (path-triggered, REPORT-ONLY)

When the merged diff touched `apps/web-platform/infra/cloud-init-registry.yml` or
`.github/workflows/registry-host-replace-dispatch.yml`, the merge fired the
registry-host-replace dispatcher (#7555, #8279), and its verdict is the delivery's
own record — read it rather than inferring delivery from a green merge:

```bash
run=$(gh run list --workflow=registry-host-replace-dispatch.yml --branch main --limit 1 \
  --json databaseId,conclusion --jq '.[0] | "\(.databaseId) \(.conclusion)"')
gh run view "${run%% *}" --log | grep -E 'Z (range|prs|summary|targets)=|Z Nothing since the watermark'
gh api --paginate --slurp "repos/jikig-ai/soleur/issues/<number>/comments?per_page=100" \
  | jq -r '[.[][] | select(.body | test("<!-- registry-delivery run=[0-9]+ kind="))] | last | .body // "no verdict"'
```

`deliver=false` (a registration-only or comment-only push) and a green run with no verdict is
the expected case. Any `kind=` other than none is reported verbatim with the runbook's next
action (`knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md`);
this phase reports, it does not block "done".

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
Feature-tweet draft: <path + "flip publish_date + status: scheduled to publish" / CATCH-UP: run soleur:feature-tweet #N / NONE — ineligible>
```

## Graceful Degradation

When a prerequisite is missing, read
[references/graceful-degradation.md](./references/graceful-degradation.md) for the
per-prerequisite behaviour (skip / warn / poll).

## Notes

- Always read merged files out of git rather than off the bare repo filesystem — but address them by the **merge commit SHA** (`git show <merge-sha>:<path>`), never by the local `main` ref. `main` is not fast-forwarded as a side effect of a merge, so in a worktree/bare layout it lags and a file the PR ADDED reads as absent. `git fetch origin main` FIRST: the merge SHA is correct but useless if the worktree does not have that object yet, and git reports the shortfall in wording (`exists on disk, but not in <sha>`) that looks like a verdict about the file. See Phase 4.
- MCP tools resolve paths from the repo root. Use absolute paths when in a worktree.
- This skill is designed to run after `soleur:merge-pr` completes. It can also be invoked standalone with a PR number.

## Production Debugging

- **A deploy-arm database step failing on an auth/connect timeout is a production database signal, not an isolated flake: read readiness before rerunning.** `/health` returns HTTP 200 `status: ok` whatever the database state (only `.supabase` flips to `error`), the Management API project `status` can read `ACTIVE_HEALTHY` while Postgres is down, and a rerun's `migrate` can go green through the pooler. Read `curl -sS <prod>/health | jq -r .supabase` and `GET /v1/projects/<ref>/health?services=db&services=auth&services=rest&services=pooler` first — the latter carries the account-level admin PAT, so call it the way [supabase-logs-query.sh](../../../../scripts/supabase-logs-query.sh) does (header on stdin via `--header @-`, `--disable --noproxy '*'`, under `doppler run`), never with the token in argv. **Why:** 2026-09-15 — prd Postgres was unreachable 89 min; a rerun looped on health verification and `/health` was read directly only ~16 min later (post-mortem `prd-supabase-database-unreachable-2026-09-15-postmortem.md`).
- For production debugging use Sentry API (`SENTRY_API_TOKEN` in Doppler `prd`), Better Stack, or `/health` — never SSH for logs. SSH is for infra provisioning only. (ex-`cq-for-production-debugging-use`) To read a Sentry issue/event by id inline, use `doppler run -p soleur -c prd -- scripts/sentry-issue.sh <id>` (runbook `knowledge-base/engineering/operations/runbooks/sentry-issue-read.md`); for host/app logs use [betterstack-query.sh](../../../../scripts/betterstack-query.sh) (runbook `betterstack-log-query.md`).
- For deploy webhook debugging, fetch `WEBHOOK_DEPLOY_SECRET`/`CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET` from Doppler `prd_terraform` (not `prd`). GET `https://deploy.soleur.ai/hooks/deploy-status` with CF Access headers + HMAC-sha256 over empty body. Full runbook: [deploy-status-debugging.md](./references/deploy-status-debugging.md). (ex-`cq-deploy-webhook-observability-debug`)
- Doppler env values on prd are baked into the container at start via `--env-file` (cloud-init.yml). Flipping a flag in Doppler does NOT affect the running container — POST-X gates that depend on a freshly-flipped flag must redeploy the current image tag (POST to `/hooks/deploy`) between the flip and the verification smoke. Full context: [2026-05-19-doppler-env-hot-reload-limitation.md](../../../../knowledge-base/project/learnings/2026-05-19-doppler-env-hot-reload-limitation.md).
