---
title: "chore: trigger fresh prod build after Doppler correction (issue #3015)"
date: 2026-04-29
issue: 3015
type: ops-remediation
classification: ops-only-prod-write
branch: feat-one-shot-3015-trigger-prod-build
requires_cpo_signoff: false
deepened_on: 2026-04-29
---

# chore: trigger fresh prod build after Doppler correction (issue #3015)

## Enhancement Summary

**Deepened on:** 2026-04-29
**Sections enhanced:** Implementation Phases, Acceptance Criteria, Sharp Edges, Research Insights
**Lenses applied (inline, agent definitions read):** deployment-verification-agent (pre/post invariants + rollback), code-simplicity-reviewer (YAGNI on the trigger contingency), architecture-strategist (workflow trigger semantics, observability gaps), pattern-recognition-specialist (auto-trigger via push-paths filter is the standing pattern, not workflow_dispatch). User-impact-reviewer was NOT invoked — threshold is `none` per the plan section, which is the documented exit criterion for that agent.

### Key Improvements

1. **Inverted the framing** from "trigger build" → "verify recovery, trigger contingently" — Phase 1 now writes its findings to the runbook FIRST, so Phase 2's go/no-go is auditable. (deployment-verification-agent lens.)
2. **Added a no-op exit gate** between Phase 1 and Phase 2 — if Sentry is clean and the claim-check passes, Phase 2 is explicitly skipped and the plan jumps to Phase 3 verification + Phase 4 close-out. Previously the contingency was implicit. (code-simplicity-reviewer lens — removed the implicit "always trigger" assumption.)
3. **Documented why `workflow_dispatch` vs auto-trigger matters here** — the workflow's `paths: ['apps/web-platform/**']` push filter means PRs #3016 and #3017 already auto-built (PR #3018 was knowledge-base-only and did NOT auto-build); a manual dispatch with no code change would produce a no-op release-bump path. Operator must confirm a code/secret change preceded the dispatch, OR explicitly accept the no-op. (architecture-strategist lens.)
4. **Added rollback procedure** — a fresh build that itself ships broken is not unprecedented (#3007 was the originating case). Rollback is via `gh workflow run` against the previous known-good commit's release-tag.
5. **Hardened the claim-check invocation** — verified the script exists at `apps/web-platform/infra/canary-bundle-claim-check.sh` (3187 bytes, executable, wired into `ci-deploy.sh`), confirmed signature matches the runbook (`<base-url>` arg, returns 0 on pass, non-zero on any violation including SKIP outcomes — fail-closed by design).

### New Considerations Discovered

- **The `workflow_dispatch` path bumps the version** (per `reusable-release.yml` `force_run: ${{ github.event_name == 'workflow_dispatch' }}`). A no-change dispatch creates a release tag with no diff — adds noise to the release history. Phase 2.3 must either accompany a real change (Phase 2.1 / 2.2) or use the `bump_type: patch` input deliberately and document the no-change rationale in the release notes.
- **The push-trigger path is hash-gated by the path filter.** A change to `apps/web-platform/**` auto-builds; a change to `knowledge-base/**` (this plan) does NOT. The follow-through close-out (Phase 4) does not require a build trigger if Phase 1 passes clean.

## Overview

Issue #3015 is a follow-through item filed by `/ship` Phase 7 Step 3.5 from PR
#3014's postmortem (`knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md`).
The postmortem prescribed two phases:

- **Phase 1** — Diagnose root cause of the `/dashboard` error.tsx outage (read-only,
  agent-with-ack).
- **Phase 2** — Hot-fix prod by triggering a fresh build via
  `gh workflow run web-platform-release.yml --ref main` so the new bundle picks up
  any corrected Doppler/secret values and re-asserts the JWT-claims guardrails
  shipped in PR #3007.

This issue (#3015) tracks **Phase 2's trigger step** specifically. It is an
ops-remediation task — the "fix" is operator-driven via `gh workflow run` against
prod (with per-command ack per AGENTS.md `hr-menu-option-ack-not-prod-write-auth`).
The PR for this issue's plan exists primarily to:

1. Document the trigger procedure with audit-trail entries (run ID, commit SHA,
   canary outcome, render verification).
2. Let `/ship` Phase 7 close out the follow-through cleanly via `gh issue close 3015`
   once the build + canary swap + Playwright sign-off succeed.

**Crucial reality check (verified at plan time):**

```
gh run list --workflow=web-platform-release.yml --limit 5 \
  --json status,conclusion,headSha,createdAt,event,headBranch
```

returned five consecutive `success`/`completed` runs on `main` between
2026-04-28 20:12Z and 22:31Z, covering commits `7d556531` (PR #3007 — the
original suspect), `f8b2a5c4` (#3009), `b2fed080` (#3014), `a1f229c5`
(#3016), and `92e8b3d5` (#3017). PR #3014 already shipped. PRs #3016
and #3017 each triggered fresh release builds via the `paths:
['apps/web-platform/**']` push filter (PR #3018 merged later but only
touched `knowledge-base/`, so it did NOT auto-trigger). The latest
deployed bundle on `app.soleur.ai` is `92e8b3d5` (HEAD of `main`'s
`apps/web-platform/**` history as of plan-time).

A live `curl -I https://app.soleur.ai/dashboard` returns `HTTP 307` (auth
redirect), not the error-boundary response, which is consistent with — but
does NOT prove — recovery. Definitive verification requires a signed-in
Playwright session per Phase 2.4 of the runbook.

**Therefore, this plan's primary action is not "trigger a build" — it is
"verify recovery is real, decide whether an additional manual trigger is
warranted, and close the follow-through with evidence."** The trigger step
remains in the plan as a contingent action gated on Phase 1 Sentry/render
diagnosis, so the audit trail captures the decision either way.

## User-Brand Impact

**If this lands broken, the user experiences:** every authenticated visitor
to `app.soleur.ai/dashboard` continues to see the Next.js error boundary
("Something went wrong / An unexpected error occurred / Try again") instead
of the Command Center. Sign-in succeeds; the post-auth landing fails.

**If this leaks, the user's data is exposed via:** N/A — this is a
read-mostly operator workflow (status check + optional `gh workflow run`).
The build itself uses Doppler `prd` secrets that are already provisioned;
no new credentials are introduced or persisted.

**Brand-survival threshold:** none — but with a sharp edge: the *underlying
incident* (PR #3014 postmortem) was `single-user incident` (#2887 class).
The trigger step itself is recovery, not the originating risk. The recovery
verification step IS load-bearing — a false "verified" claim leaves real
users on the error boundary. Justification for `none` on the recovery
action: the worst case is a no-op (build re-runs successfully, prod
unchanged) or a build failure (caught by CI Validate, never reaches prod).

`threshold: none, reason: ops follow-through; the load-bearing decision
(does prod still serve the error boundary) is verified via Playwright +
Sentry digest, not by triggering a build.`

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| "Trigger fresh prod build via `gh workflow run web-platform-release.yml`" | 2 prod builds (#3016 and #3017) auto-shipped post-#3014 via push trigger; #3018 is knowledge-base-only and did NOT path-trigger. HEAD of prod's apps/web-platform tree = `92e8b3d5`. | Verify which build delivered the recovery before deciding whether to trigger an additional one. Default action: verify, don't re-trigger. |
| Postmortem Phase 2 prescribes a build trigger as the fix | The trigger is contingent on Phase 1 finding (`Doppler prd correct vs wrong vs GH secret wrong vs Sentry DSN missing`). | Plan executes Phase 1 diagnosis first; only triggers if Phase 1 finds Doppler/secret was indeed corrected post-#3014 AND the auto-built bundle from #3016/#3017 still ships the broken value. |
| "Awaiting verification" | No verification artifacts (Sentry digest, Playwright screenshot, JWT claim re-check) recorded in the runbook's "Recovery Verification" section. | This plan's primary deliverable is filling in that section. |

## Hypotheses

(N/A — not a network-outage diagnosis; trigger pattern doesn't match SSH/network
keywords from `plan-network-outage-checklist`.)

## Open Code-Review Overlap

None. (Verified via `gh issue list --label code-review --state open --json
number,title,body --limit 200` — zero open code-review issues touch
`.github/workflows/web-platform-release.yml`,
`apps/web-platform/lib/supabase/client.ts`, or
`knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md`.)

## Implementation Phases

### Phase 1 — Pre-trigger verification (read-only)

Operate per AGENTS.md `hr-exhaust-all-automated-options-before` (Doppler →
MCP → CLIs → REST → Playwright → manual handoff).

#### 1.1 Confirm prod HEAD and last build

```bash
gh run list --workflow=web-platform-release.yml --limit 3 \
  --json status,conclusion,headSha,createdAt,event,headBranch
```

Expect: top entry conclusion=`success`, headBranch=`main`, headSha = current
`git rev-parse origin/main`. If conclusion is anything else, do NOT trigger
an additional build — stop and escalate.

#### 1.2 Check Sentry for live `/dashboard` boundary errors (Doppler → REST)

```bash
SENTRY_API_TOKEN=$(doppler secrets get SENTRY_API_TOKEN -p soleur -c prd --plain)
curl -fsS --max-time 30 \
  -H "Authorization: Bearer $SENTRY_API_TOKEN" \
  "https://sentry.io/api/0/projects/jikig-ai/soleur-web-platform/events/?statsPeriod=24h&query=feature:dashboard-error-boundary%20OR%20feature:supabase-validator-throw"
```

Capture: event count, first-seen, last-seen.

- **Zero events in the last 24h** → recovery is real; skip Phase 2 trigger;
  proceed to Phase 3 verification.
- **Events present, last-seen ≥ ~22:31Z 2026-04-28** (the `92e8b3d5` build
  time) → the latest auto-built bundle still carries the regression;
  proceed to Phase 1.3.
- **Token unavailable in Doppler `prd`** → fall back to web-UI digest
  review per runbook step 1.1 fallback (operator-only).

#### 1.3 Re-validate inlined JWT claims in the deployed bundle

```bash
bash apps/web-platform/infra/canary-bundle-claim-check.sh https://app.soleur.ai
```

(Path verified: this script was added by PR #3014 — see runbook "D5 — Landed
in #3014".) The script asserts that the inlined `NEXT_PUBLIC_SUPABASE_ANON_KEY`
in the served HTML/JS satisfies the 3-segment JWT shape, `iss=supabase`,
`role=anon`, canonical 20-char ref, and the placeholder-prefix denylist.

- **Pass** → bundle is fine; skip Phase 2.
- **Fail** → proceed to Phase 2; record which assertion failed (this maps
  to runbook H1/H1a/H1b/H2/H3).

### Phase 1.4 — No-op exit gate (deepen-pass addition)

If BOTH Phase 1.2 (Sentry digest, last-seen ≤ 22:31Z 2026-04-28 OR zero
events in 24h) AND Phase 1.3 (`canary-bundle-claim-check.sh` returns 0)
pass, jump directly to Phase 3 — Phase 2 is skipped.

Record in the runbook's Recovery Verification block:

> Phase 2 not executed — `92e8b3d5` already-deployed bundle passes
> claim-check, no boundary errors in Sentry post-deploy. Recovery
> attributed to PRs #3016/#3017's auto-trigger via
> `paths: ['apps/web-platform/**']`.

Why this gate matters (architecture-strategist lens): the original issue
body assumed a manual trigger was the fix. Plan-time reality check showed
3 prod builds already shipped after #3014. Triggering an additional build
now would either be a no-op release-bump (adds release-history noise) OR
mask a still-extant bug behind a fresh deploy without diagnosis. The
no-op exit makes the absence of action auditable.

### Phase 2 — Trigger build (contingent on Phase 1 finding)

Run only if Phase 1.2 OR Phase 1.3 indicates the live bundle is still broken.

**Decision matrix (deepen-pass addition):**

| Phase 1.2 Sentry events | Phase 1.3 claim-check | Action |
|---|---|---|
| 0 events / last-seen pre-#3014 | pass | Skip Phase 2 (Phase 1.4 exit). |
| Events present, last-seen ≥ 22:31Z 2026-04-28 | pass | Bundle passes shape-check but live errors remain → likely DSN / network / runtime issue. STOP and re-open Phase 1 hypothesis matrix (H3 / H6); do NOT trigger a build blindly. |
| 0 events / pre-#3014 | fail | Stale CDN edge OR claim-check false negative. Run `cloudflare cache purge` for `/_next/static/*` BEFORE re-running 1.3; only proceed to Phase 2 if claim-check still fails after purge. |
| Events present | fail | Genuine regression — proceed to Phase 2 with a Phase 1.3 stderr capture indicating WHICH assertion failed (iss / role / ref / placeholder-prefix / shape). |

Per AGENTS.md `hr-menu-option-ack-not-prod-write-auth`, this command writes
to shared prod (deploy on success). Show the exact command, wait for
explicit per-command operator ack, then run.

#### 2.1 If Phase 1 finding is "Doppler `prd` is wrong"

```bash
# Operator MUST review the canonical value before this runs.
doppler secrets set NEXT_PUBLIC_SUPABASE_ANON_KEY=<canonical> -p soleur -c prd
```

#### 2.2 If Phase 1 finding is "GitHub repo secret is wrong"

```bash
gh secret set NEXT_PUBLIC_SUPABASE_ANON_KEY -R jikig-ai/soleur < /dev/stdin
```

(Inline-value pattern — supersedes the `--body` form per learning
`knowledge-base/project/learnings/bug-fixes/<topic>.md` from #2993/#3018.)

#### 2.3 Trigger the release workflow

If Phase 2.1 OR 2.2 ran (Doppler / GH secret was actually wrong), the new
Doppler/secret value is picked up automatically by the `paths:
['apps/web-platform/**']` push trigger ONLY if a code change in
`apps/web-platform/` lands. For a secret-only change with no code diff, an
explicit `workflow_dispatch` is required:

```bash
# Verified the workflow accepts dispatch with no inputs:
# `bump_type: ${{ inputs.bump_type || '' }}` (defaults to empty when
# dispatched without explicit input).
gh workflow run web-platform-release.yml --ref main
sleep 5
RUN_ID=$(gh run list --workflow=web-platform-release.yml --limit 1 \
  --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN_ID" --exit-status
```

**Dispatch noise warning (deepen-pass):** `force_run: ${{ github.event_name
== 'workflow_dispatch' }}` in `web-platform-release.yml` means a manual
dispatch always proceeds through the release path even with no code diff.
This produces a release tag with empty diff. Acceptable for a hot-fix
secret rotation; document the no-change rationale in the release notes
(or the runbook Recovery Verification block) so future operators auditing
the release history understand why the tag exists.

Record `RUN_ID` in the runbook's "Recovery Verification" table.

#### 2.4 Rollback procedure (deepen-pass addition)

If the new build itself ships broken (#3007 class — CI Validate passes
but client bundle still throws at hydration), rollback is via redeploying
the previous known-good release tag:

```bash
# Identify the previous-good tag (most recent green release before today's window).
PREV_TAG=$(gh api repos/jikig-ai/soleur/releases \
  --jq '.[] | select(.tag_name | startswith("web-v")) | .tag_name' | sed -n '2p')
echo "Rollback target: $PREV_TAG"

# Re-trigger the build for that tag's underlying SHA.
PREV_SHA=$(gh api repos/jikig-ai/soleur/git/refs/tags/$PREV_TAG --jq .object.sha)
gh workflow run web-platform-release.yml --ref "$PREV_SHA"
```

**Constraint (verified):** `gh workflow run --ref` requires the ref to
exist on the default branch's history. A tag SHA that descends from main
satisfies this. Per AGENTS.md `hr-menu-option-ack-not-prod-write-auth`,
the rollback dispatch is a destructive prod write — show the exact
command and wait for explicit per-command operator ack before execution.

**Why rollback is in scope:** the originating incident (#3014 postmortem)
proved that "fresh build" alone is not a guaranteed fix. If Phase 3.1's
canary swap log shows `canary_failed`, the new layered probe set caught
the regression and prod was NOT swapped — the rollback target is whatever
the canary's `last-known-good` was. If `final_write_state 0 "ok"` shows
but Phase 3.2 Playwright still finds `data-error-boundary=`, the bundle
shipped to prod IS broken and rollback is mandatory.

### Phase 3 — Render-time verification (always runs)

Whether or not Phase 2 ran, this phase fills the runbook's "Recovery
Verification" section with concrete evidence.

#### 3.1 Canary swap log line

```bash
ssh prod-web journalctl -u docker -n 200 | grep DEPLOY | tail -20
```

Look for `final_write_state 0 "ok"`. If `canary_failed`, the new layered
probe set caught a regression — re-open Phase 1.

#### 3.2 Playwright signed-in render check (per AGENTS.md `hr-mcp-tools-playwright-etc-resolve-paths` use absolute paths)

Use Playwright MCP via the existing test-fixture path (Doppler-stored test
JWT — see runbook D2). For this issue, an unauthenticated check is
acceptable as a first signal:

- `mcp__playwright__browser_navigate https://app.soleur.ai/dashboard`
- `mcp__playwright__browser_take_screenshot path=/tmp/3015-dashboard.png`
- Assert: rendered HTML must NOT contain `data-error-boundary=` (the
  structured marker emitted by `apps/web-platform/components/error-boundary-view.tsx`).

For a signed-in check, Phase 3.2b: navigate to `/login`, complete the test
fixture flow, then re-snapshot `/dashboard`.

#### 3.3 Re-run Phase 1 step 1.3

`bash apps/web-platform/infra/canary-bundle-claim-check.sh https://app.soleur.ai` — must pass.

#### 3.4 Update the runbook's Recovery Verification section

Edit `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md`
"Recovery Verification" block (lines ~243–250). Replace each `TBD` with
concrete evidence: release tag (e.g., `web-vX.Y.Z`), canary swap log line,
Playwright screenshot path, claim-check pass output. Set the frontmatter
`status:` from `open` to `closed: 2026-04-29`.

### Phase 4 — Close the follow-through

```bash
gh issue close 3015 --comment "Closed by /one-shot pipeline. Phase 1 verification: <findings>. Phase 2 trigger: <ran|skipped>. Phase 3 evidence: release tag <tag>, canary <ok|...>, Playwright screenshot <path>, claim-check <pass>."
```

Per AGENTS.md `wg-when-moving-github-issues-between` and the
ops-remediation extension of `wg-use-closes-n-in-pr-body-not-title-to`,
the PR body for this plan uses `Ref #3015` (NOT `Closes #3015`) — the
actual close happens here, after evidence is recorded.

## Files to Edit

- `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md`
  — fill in Recovery Verification section, flip frontmatter `status` to
  closed.

## Files to Create

- `knowledge-base/project/plans/2026-04-29-chore-trigger-prod-build-after-doppler-correction-plan.md`
  (this file).
- `knowledge-base/project/specs/feat-one-shot-3015-trigger-prod-build/tasks.md`
  (Save Tasks step).

## Acceptance Criteria

### Pre-merge (PR)

- [x] Plan file committed under `knowledge-base/project/plans/`.
- [x] `tasks.md` committed under
  `knowledge-base/project/specs/feat-one-shot-3015-trigger-prod-build/`.
- [x] PR body uses `Ref #3015` (NOT `Closes #3015`).
- [x] Phase 1 verification commands enumerated with exact flags (not
  paraphrased from the runbook).

### Post-merge (operator) — completed 2026-04-29 by /one-shot

- [x] Phase 1.2 Sentry digest captured: 0 events for
  `feature:dashboard-error-boundary OR feature:supabase-validator-throw`
  in last 24h. Pre-fix events: `a3edfa6f` and `87ba1b0f` at 22:22:24Z
  (TypeError: Unknown encoding: base64url, v0.58.1, fixed in #3017).
- [x] Phase 1.3 `canary-bundle-claim-check.sh` result recorded: FAIL
  (`no JWT found in login chunk`) — false negative from the script's
  stale bundle-layout assumption. Tracked by #3033.
- [x] Phase 1.4 no-op exit gate decision recorded: exit triggered,
  Phase 2 skipped. Recovery attributed to PR #3017's auto-build
  (run completed 2026-04-28 22:31:40Z, headSha `92e8b3d5`, swap at
  22:37:08Z).
- [x] If Phase 2 ran: N/A (Phase 1.4 exit, Phase 2 skipped).
- [x] If Phase 2.4 rollback ran: N/A (no Phase 2).
- [x] Phase 3.1 canary swap log: `Canary OK` + `Canary passed,
  swapping to production` + `Deploy succeeded` + deploy-status
  `{"exit_code":0,"reason":"ok","tag":"v0.58.2"}` at 2026-04-28
  22:37:08Z (deploy harness equivalent of `final_write_state 0 "ok"`).
- [x] Phase 3.2 Playwright screenshot exists
  (`.playwright-mcp/3015-dashboard-redirect-login.png`) and does NOT
  contain `data-error-boundary=`. /dashboard → /login redirect
  (auth gate); login renders cleanly, zero console errors.
- [x] Phase 3.3 re-run of `canary-bundle-claim-check.sh` — substituted
  by manual JWT decode of the post-#3017 chunk
  `/_next/static/chunks/8237-323358398e5e7317.js`:
  `iss=supabase, role=anon, ref=ifsccnjhymdmidffkzhl (20 chars,
  no placeholder prefix)`. Script-broadening fix tracked by #3033.
- [x] `dashboard-error-postmortem.md` Recovery Verification section
  filled; frontmatter `status` flipped to
  `closed: 2026-04-29`.
- [ ] `gh issue close 3015` ran with evidence comment — deferred to
  post-merge (per Phase 4 of this plan; the close happens after the
  PR for this work merges so the issue can reference the merged
  artifacts).
- [x] Operator IP is in the Hetzner SSH allow-list — verified via
  successful `ssh root@135.181.45.178 'hostname'` returning
  `soleur-web-platform`; egress IP `82.67.29.121`.

## Test Scenarios

This is an ops-remediation task with no production code changes. The "tests"
are the Phase 1 + Phase 3 verifications. No vitest/bun-test scaffolding is
added — exempt per AGENTS.md `cq-write-failing-tests-before` (infrastructure-
only task).

## Domain Review

**Domains relevant:** Engineering (CTO).

The trigger is a CI/ops action against the existing `web-platform-release.yml`
workflow. No new product surface, no new copy, no marketing artifact. The
underlying postmortem (#3014) already received CPO sign-off via its
`brand_threshold: single-user incident` framing; this follow-through is
recovery verification, not a new product decision.

CTO assessment: the workflow exists, has run successfully five times in the
last 90 minutes, and the canary-bundle-claim-check script (PR #3014) is the
deterministic gate for the underlying invariant. The plan correctly inverts
the issue framing from "trigger a build" to "verify recovery, then trigger
contingently" — this is the cheaper and lower-risk default.

No Product/UX Gate triggered (no UI changes, no new components).

## Risks

- **R1 — False negative on Phase 1.3 claim-check.** If the live bundle's
  hash hasn't changed but the inlined value has (cache-busting), the
  script's URL probe could report a stale cached asset. Mitigation:
  Phase 1.3 hits the live origin directly; the script's behavior on
  PR #3014 was validated in CI. If a stale CDN edge is suspected, a
  Cloudflare cache purge of `/_next/static/*` is the next step (not in
  scope here — file as follow-up if it materializes).
- **R2 — `workflow_dispatch` trigger semantics on a default-branch
  workflow.** Per the sharp edge in `plugins/soleur/skills/plan/SKILL.md`:
  `gh workflow run` against a workflow not on default branch returns 404.
  This plan dispatches against `--ref main`, where the workflow has
  existed for months — no risk.
- **R3 — Operator IP drift breaks Phase 3.1's SSH step.** Verified via
  AGENTS.md `hr-ssh-diagnosis-verify-firewall` — if `journalctl` SSH
  fails with kex/timeout, run `/soleur:admin-ip-refresh` BEFORE proposing
  any sshd-side fix.
- **R4 — Build-arg vs runtime-env confusion.** The validators are
  build-time inlined into the client bundle. A `docker restart` does NOT
  fix the deployed bundle (already documented in the runbook Phase 2
  preamble). This plan calls out the constraint explicitly so the operator
  doesn't reach for `docker restart` as a shortcut.

## Sharp Edges

- **Empty `## User-Brand Impact` blocks fail `deepen-plan` Phase 4.6.**
  This plan's section is filled with concrete artifacts and a justified
  `threshold: none, reason: ...` — do not strip the reason at deepen-plan.
- **`Closes #3015` in the PR body would auto-close the issue at merge,
  before Phase 3 verification runs.** Use `Ref #3015` per
  AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to` and the
  ops-remediation extension. The actual `gh issue close 3015` is a
  Phase 4 step, not a merge-time action.
- **Per-command ack is load-bearing for every Phase 2 / Phase 3.1
  command.** Agent shells have no TTY; the Bash tool runs non-interactively.
  The exact command must be displayed and acked before each run, even if a
  prior command was acked — menu acks do NOT stretch to new commands per
  AGENTS.md `hr-menu-option-ack-not-prod-write-auth`.
- **Sentry token resolution order:** Doppler `prd` first
  (`SENTRY_API_TOKEN`), then `prd_terraform`, then web-UI fallback. Don't
  prompt the operator for the token until all three are exhausted.
- **`gh secret set ... < /dev/stdin` (Phase 2.2):** the inline-value form
  supersedes `--body` (PR #2993/#3018 retired the `--body -` shape). If a
  future GH CLI release flips the default, re-verify with `gh secret set
  --help` before invoking.

## Research Insights

**Verified at plan-time:**

- `gh run list --workflow=web-platform-release.yml --limit 5 --json
  status,conclusion,headSha,createdAt,event,headBranch` — 5 consecutive
  successes 2026-04-28 20:12Z – 22:31Z, headBranch=main, top sha
  `92e8b3d5` (HEAD of `origin/main`).
- `curl -I https://app.soleur.ai/dashboard` — `HTTP/2 307` (auth redirect),
  not the error-boundary path.
- `cat .github/workflows/web-platform-release.yml` — workflow has both a
  `push: paths: ['apps/web-platform/**']` trigger AND a `workflow_dispatch`
  trigger; bumping `bump_type` is optional (defaults to `''` for path-trigger
  flow).
- `ls apps/web-platform/infra/canary-bundle-claim-check.sh` — exists (PR
  #3014); used in CI as the Layer-3 canary probe.
- `gh issue list --label code-review --state open --limit 200 | wc -l` —
  zero open code-review issues touching the affected paths.

**External docs:**

- `gh workflow run` reference:
  <https://cli.github.com/manual/gh_workflow_run> (verified 2026-04-29 —
  `--ref` accepts a branch or tag; default repo is current).
- GitHub Actions `workflow_dispatch`:
  <https://docs.github.com/en/actions/using-workflows/manually-running-a-workflow>
  (workflow MUST be on the default branch; this plan uses `--ref main`,
  which IS the default branch).

**Institutional learnings consulted:**

- `knowledge-base/project/learnings/integration-issues/2026-04-21-workflow-dispatch-requires-default-branch.md`
  — confirms `--ref main` is the safe form (this plan satisfies it).
- `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md`
  — context for why the canary-bundle-claim-check exists; relevant to
  Phase 1.3.

### Deepen-Pass Verifications (2026-04-29)

**Live-verified at deepen time:**

- `ls -la apps/web-platform/infra/canary-bundle-claim-check.sh` →
  exists, 3187 bytes, executable. Header comment confirms it is "Canary
  Layer 3 — assert the inlined Supabase anon-key JWT in the deployed
  /login chunk has canonical claims (iss=supabase, role=anon,
  ref=^[a-z0-9]{20}$)." Usage signature: `<base-url>` arg; returns 0 on
  pass, non-zero on any violation (including SKIP outcomes — fail-closed
  by design). Matches the runbook reference.
- `grep -l "canary-bundle-claim" apps/web-platform/infra/ci-deploy.sh` →
  match found. The Layer-3 wiring referenced in the runbook is real.
- `cat .github/workflows/web-platform-release.yml` → confirms
  `paths: ['apps/web-platform/**']` push trigger AND
  `workflow_dispatch` trigger; reusable-release.yml passes
  `force_run: ${{ github.event_name == 'workflow_dispatch' }}` (the
  dispatch-noise constraint cited in Phase 2.3 is verified, not assumed).
- `gh issue list --label code-review --state open --limit 200 --json
  number,title,body | jq '. | length'` → 0 open code-review issues
  touching plan paths. Open Code-Review Overlap section's "None" claim
  is verified.

**Architecture-strategist concerns surfaced and addressed inline:**

- The originating issue assumed a manual trigger was the fix. Plan-time
  reality (5 successful auto-triggered builds) inverts that assumption.
  The deepen pass codified the inversion via Phase 1.4 no-op exit gate.
- `force_run: true` on `workflow_dispatch` means a manual dispatch with
  no underlying change creates a release tag with empty diff — adds
  long-term release-history noise that auditors will hit later. Phase
  2.3 now requires either a real code/secret change OR an explicit
  no-change rationale recorded in the runbook.
- The plan's `Closes vs Ref` discipline matches `wg-use-closes-n-in-pr-body-not-title-to`
  ops-remediation extension and PR #2880's precedent; verified by
  reading both the AGENTS.md rule and the recent commit history.

**Code-simplicity-reviewer concerns surfaced and addressed inline:**

- The original Phase 2 had an implicit "always trigger" path; the
  deepen pass added Phase 1.4 no-op exit gate to make the no-op
  explicit. YAGNI satisfied — Phase 2's body is now only reachable
  on demonstrated need.

**Deployment-verification-agent concerns surfaced and addressed inline:**

- Pre-deploy invariants: declared via Phase 1's three checks (run
  status, Sentry, claim-check). Each has a recorded artifact.
- Rollback procedure: was missing in v1; added as Phase 2.4 with a
  verified `gh workflow run --ref <prev-good-sha>` form.
- Post-deploy monitoring: Phase 3.1 (canary swap log), Phase 3.2
  (Playwright render), Phase 3.3 (claim-check re-run) form the
  three-layered post-deploy gate. The runbook's "Recovery Verification"
  block is the audit artifact.

## Test Strategy

No new tests. Verification is operator-driven via the procedures in
Phases 1 + 3.
