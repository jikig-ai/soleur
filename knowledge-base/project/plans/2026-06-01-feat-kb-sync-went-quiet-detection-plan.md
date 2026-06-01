<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: no infrastructure provisioning. KB_WENT_QUIET_MAX_GAP_DAYS is a
     non-secret optional tuning constant (default 3), documented in .env.example exactly like
     the existing WORKSPACE_RECONCILE_IGNORE_REPOS — no Doppler, no .tf, no server/service/cron.
     The hook matched "operator" (alert-fatigue prose) and "manual-trigger" (the existing Inngest
     event name cron/workspace-sync-health.manual-trigger), neither of which is manual provisioning. -->
---
title: "feat(kb-sync): went-quiet detection (time-based / push-correlation stale arm)"
type: feat
feature: feat-kb-sync-went-quiet-detection
issue: 4717
parent_issue: 4706
predecessor_issue: 4712
branch: feat-kb-sync-went-quiet-detection
pr: 4726
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-06-01
status: draft
revised: 2026-06-01 (plan-review pivot — see Plan-Review Resolutions)
---

# Plan — feat(kb-sync): went-quiet detection (#4717)

## Overview

Add a **third arm** to the existing daily `cron-workspace-sync-health` Inngest
function that detects the **went-quiet** class: a `repo_status='ready'` **and**
`github_installation_id IS NOT NULL` user whose webhook pushes have stopped
arriving. Because no push to the synced (default) branch arrives, the reconcile
writes **zero** new `kb_sync_history` rows; the latest row stays `ok:true` forever
and the connection looks healthy while the KB silently goes stale (the parent
#4706 incident — a KB froze ~5 weeks, no error shown).

The defining signal cannot come from `kb_sync_history` (went-quiet erases its own
record). It comes from GitHub: the **default branch's HEAD commit date**
(`GET /repos/{owner}/{repo}/commits?per_page=1` → `[0].commit.committer.date`),
correlated against the user's last `ok:true` sync. Fire when **both** hold:

```
headCommitAt > lastOkSyncAt + FRESHNESS_SLACK_MS   AND   now − lastOkSyncAt > N days
```

The first clause (out-of-band default-branch activity) suppresses the idle-repo
false positive; the second bounds staleness. Read-only, ops-only Sentry, no
migration, no new function, no UI. Extends the cron in-place.

**Scan source = `users`, mirroring arm 2 (#4712).** `users` carries `repo_url`,
`github_installation_id`, `repo_status`, **and** `kb_sync_history` on the SAME row
(migration `011_repo_connection.sql:5-11`; not dropped by 079's UP migration —
arm 2 already scans `users` for exactly these columns). `kb_sync_history` is
**per-user** (the reconcile attributes rows to the workspace owner via
`appendKbSyncRow(ownerId, …)`), so the user row is the correct, complete unit for
both arm 2 and arm 3 — no `workspace_members` join, no per-workspace
`workspace_id` discriminator needed.

**Mutual exclusivity — genuinely by construction.** Arm 2 fires iff
`users.kb_sync_history.at(-1).ok === false`; arm 3 fires iff `.at(-1).ok === true`
(plus the GitHub + N-day conditions). Same table, same row, same history array,
opposite polarity of the same field → the two can never report the same user in
one run. (Arm 3 uses its own `users` query with the identical WHERE clause as arm
2 — kept as a separate `step.run`, matching the existing arm-1/arm-2 structure and
avoiding any edit to shipped arm-2 code.)

## Plan-Review Resolutions (v1 → v2)

v1 was workspace-centric on a **false premise** ("`users` has no `repo_url`"). The
DHH/Kieran/Simplicity panel corrected it. v2 changes:

| Finding | Resolution |
|---|---|
| **Kieran P0-1** — `users` HAS `repo_url` (mig 011); the v1 premise was fabricated | v2 scans `users` (verified: mig 011 adds the cols; written at `app/api/repo/setup/route.ts:75`; arm 2 reads them). |
| **Kieran P0-2** — v1 "mutual exclusivity by construction" was false (arm 2 scans `users`/`userId`; v1 arm 3 scanned `workspaces`/`workspaceId` — different keys, can diverge under ADR-044) | v2 arm 3 scans `users`, reports `userId` → genuine same-row polarity partition. |
| **Kieran P0-3** — `@octokit/core` is not a dependency; v1 hand-waved token→HTTP | v2 reuses the `githubFetch` GET pattern (`checkRepoAccess`, `github-app.ts:600-637`) via a small sibling helper; no new dep. |
| **Kieran P2-1** — `pushed_at` is any-branch → **false positives** on feature-branch activity with a quiet main (the brainstorm's "false-negative-leaning" claim was backwards) | v2 probes the **default branch** HEAD commit (`GET /commits?per_page=1`), eliminating the feature-branch false-positive class. |
| **DHH P2-a / Simplicity (a)** — return-shape widening is ceremony; arm 2 explicitly does NOT widen (`cron-workspace-sync-health.ts:96`) | v2 reports in-place; no `ScanResult` widening. Tests assert the `reportSilentFallback` spy (arm-2 test pattern). |
| **Simplicity (b)** — token dedup re-implements `generateInstallationToken`'s existing `tokenCache` | v2 calls it inline; no dedup machinery (and users-centric has one repo per user anyway). |
| **Simplicity / DHH on `FRESHNESS_SLACK_MS`** — DHH said drop it; Simplicity said keep | **KEEP.** It guards the cross-clock boundary (GitHub `committer.date` vs our `lastOkSyncAt`). DHH's "N-days dwarfs it" conflates clock domains — the skew lives in clause 1 (cross-clock), which the N-day clause (our-clock-vs-our-clock) does not touch. |
| **Simplicity (e)** — GDPR prose disproportionate | Trimmed to one line. |
| **Simplicity hidden-assumption** — `Number.isFinite` guard admits `0`/`""` → 0-day firehose | v2 guard: `Number.isFinite(n) && n > 0 ? n : 3`. |
| **Kieran P1-2** — `lastOkSyncAt` fallback is defensive dead code; `at(-1)` = write-order | Documented as defensive; `at(-1)` write-order assumption cited (RPC row lock `session-sync.ts:349-355`; arm 2 relies on it too). |
| **DHH P1-a / Kieran P2-4** — single-workspace-owner cut | **Dissolved.** Users-centric needs no such cut; arm 3 covers every ready+installed user, same as arm 2. #4728 (per-workspace `workspace_id`) remains valid orthogonal future work, no longer a worked-around blocker. |

## Files to Edit

- `apps/web-platform/server/github-app.ts` — add an exported helper
  `getDefaultBranchHeadCommitAt(installationId, owner, repo)` mirroring
  `checkRepoAccess` (token via `generateInstallationToken`; `githubFetch(GET
  /repos/{owner}/{repo}/commits?per_page=1)`; returns the HEAD commit's
  `committer.date` as epoch ms, `null` for an empty repo (`[]`), and **throws** on
  token/network/non-200 so the caller classifies it as a probe error).
- `apps/web-platform/server/inngest/functions/cron-workspace-sync-health.ts` —
  add `step.run("scan-went-quiet")` AFTER the arm-2 step, BEFORE the heartbeat.
  Import `getDefaultBranchHeadCommitAt`. The whole step body is wrapped so it
  **never throws** (returns on any error) — the heartbeat must always post. No
  `ScanResult`/return widening.
- `apps/web-platform/test/server/inngest/cron-workspace-sync-health.test.ts` —
  add arm-3 rows to the existing `users` mock branch (now selecting `repo_url`,
  `github_installation_id`); `vi.mock("@/server/github-app")` for
  `getDefaultBranchHeadCommitAt`; add the TR5 cases. (No `workspace_members`
  branch, no `@octokit/core`.)
- `apps/web-platform/.env.example` — add commented `# KB_WENT_QUIET_MAX_GAP_DAYS=3`
  near line 176 (beside `WORKSPACE_RECONCILE_IGNORE_REPOS`).

## Files to Create

None.

## Implementation Phases

**Phase 1 — `github-app.ts` helper.** Add `getDefaultBranchHeadCommitAt`
(sibling to `checkRepoAccess`). `GET /commits?per_page=1` with no `sha` defaults
to the repo's default branch. Parse `body[0].commit.committer.date`; `[]` →
`null`. Throw on non-200 / network / token failure (caller catches).

**Phase 2 — RED tests (TR5).** Write the failing cases first, modeled on the
arm-2 cases. Extend the `users` mock rows + `vi.mock` the new helper. Confirm they
fail because `went-quiet` op never fires.

**Phase 3 — Arm-3 scan step.** Add `step.run("scan-went-quiet")`:
1. Query `users`: `.select("id, repo_url, github_installation_id, kb_sync_history").eq("repo_status","ready").not("github_installation_id","is",null)` (same WHERE as arm 2). On DB error → `reportSilentFallback(op:"scan-went-quiet")`, return.
2. For each user: `history = Array.isArray(kb_sync_history) ? … : []`; `latest = history.at(-1)`; require `latest && typeof latest === "object" && "ok" in latest && latest.ok === true` (else skip — empty/legacy/arm-2). `lastOkSyncAt = Date.parse(latest.at)`; if `Number.isNaN` → skip (defensive; `at` is required). If `now − lastOkSyncAt <= N days` → skip (fresh).
3. Parse `owner/repo` from `user.repo_url` (mirror `workspace-reconcile-on-push.ts:92` `repoSlug` + split; malformed → skip). `headCommitAt = await getDefaultBranchHeadCommitAt(user.github_installation_id, owner, repo)` inside try/catch → on throw, `reportSilentFallback(op:"went-quiet-probe", extra:{userId})` and `continue`. `null` (empty repo) → skip.
4. Fire when `headCommitAt > lastOkSyncAt + FRESHNESS_SLACK_MS` **AND** `now − lastOkSyncAt > N days` → `reportSilentFallback(new Error("ready+installed user went quiet — default-branch commits since last sync but no new kb_sync_history row"), {feature:"workspace-sync-health", op:"went-quiet", extra:{userId}})`. **userId only** (no repo name/path/handle in message or extra; `reportSilentFallback` hashes `extra.userId` → `userIdHash`, matching arm 2).
5. `logger.info({fn, wentQuiet: <count>}, …)`. Return nothing structured (in-place reporting, like arm 2). The entire body is inside try/catch so any unexpected throw → `reportSilentFallback(op:"scan-went-quiet")` and a clean return — the heartbeat step always runs.

**Phase 4 — Constants + env doc.**
- `const FRESHNESS_SLACK_MS = 5 * 60 * 1000;` (cross-clock guard: GitHub
  `committer.date` vs our `lastOkSyncAt`; must exceed GitHub↔our NTP skew — sub-second
  in practice, 5 min is generous headroom).
- `const n = Number(process.env.KB_WENT_QUIET_MAX_GAP_DAYS); const KB_WENT_QUIET_MAX_GAP_DAYS = Number.isFinite(n) && n > 0 ? n : 3;`
- Add commented `# KB_WENT_QUIET_MAX_GAP_DAYS=3` to `.env.example`.

**Phase 5 — GREEN + typecheck.** `./node_modules/.bin/vitest run test/server/inngest/cron-workspace-sync-health.test.ts` green; `tsc --noEmit` clean in `apps/web-platform`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Arm-3 reports each went-quiet ready+installed user via `reportSilentFallback`
  (op `went-quiet`, `extra:{userId}` only); emits nothing for: idle
  (`headCommitAt <= lastOkSyncAt`), fresh (`now − lastOkSyncAt <= N`), latest
  `ok:false` (arm 2), NULL-install (filtered out / arm 1), empty-repo, empty/legacy
  history.
- [ ] Default-branch HEAD commit read via `getDefaultBranchHeadCommitAt`
  (`githubFetch` GET `/commits?per_page=1`, token from
  `generateInstallationToken(user.github_installation_id)`), owner/repo parsed
  from `user.repo_url` — NOT `_cron-shared` `REPO_OWNER/REPO_NAME`. Both
  AND-conditions enforced; threshold from `KB_WENT_QUIET_MAX_GAP_DAYS` (guarded `> 0`, default 3).
- [ ] Failure isolation: users-scan DB error reports once (op `scan-went-quiet`)
  and returns; per-user probe error reports (op `went-quiet-probe`) and continues;
  any unexpected throw in the arm-3 step is caught so the **heartbeat still posts**;
  arms 1 & 2 unaffected.
- [ ] No `ScanResult`/return widening (in-place reporting, like arm 2); heartbeat
  `ok` stays `scan.ok` (arm-1 result; scan-ran, not findings-present — explicitly a
  weaker liveness signal for arm 3's DB error, matching arm 2). No `repo_status`
  mutation; no migration; no new Inngest function; no new npm dependency; no UI.
- [ ] `# KB_WENT_QUIET_MAX_GAP_DAYS=3` documented in `.env.example`.
- [ ] `vitest run <test>` green + `tsc --noEmit` clean in `apps/web-platform`.
- [ ] PR body uses `Closes #4717`. #4728 (per-workspace `workspace_id`) remains open.

## Test Scenarios (TR5)

| # | Setup | Expect |
|---|---|---|
| 1 | ready+installed user, latest `ok:true`, `lastOk` 10d ago, default-branch HEAD commit 1d ago | fires `went-quiet` once (`userId`) |
| 2 | same but HEAD commit 30d ago (≤ `lastOk`) — idle | no fire |
| 3 | same but `lastOk` 1d ago (≤ N) | no fire (fresh) |
| 4 | latest `ok:false` | no fire (arm 2 owns) |
| 5 | NULL-install (filtered by `.not`) | not in arm-3 set; no fire |
| 6 | `getDefaultBranchHeadCommitAt` returns `null` (empty repo) | no fire |
| 7 | empty / legacy `{date,count}` history | no fire |
| 8 | helper throws (token fail / non-200 / network) | reports `went-quiet-probe` once, continues; arm-3 step returns; **heartbeat still posts** |
| 9 | `users` scan DB error | reports `scan-went-quiet` once, no throw; heartbeat still posts |
| 10 | `now − lastOkSyncAt` exactly == N (strict `> N`) | no fire (boundary) |

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm `## Domain Assessments`; design source corrected at plan-review to users-centric)

### Engineering (CTO — brainstorm focused refresh, amended by plan-review)

**Status:** reviewed
**Assessment:** Extend the cron in-place; default-branch HEAD-commit correlation
via a `github-app.ts` helper (mirrors `checkRepoAccess`); scan `users` (mirrors
arm 2 → genuine mutual exclusivity); ops-only Sentry; N=3 env-overridable; all IO
in `step.run`, the arm-3 step never throws so the heartbeat always posts. No ADR,
no new dependency, ~hours of work.

### Product/UX Gate

**Tier:** none — ops-only Sentry, no user-facing surface (the #4712 item-1
reconnect affordance already covers in-product remediation). No new
`components/`/`page.tsx`/`layout.tsx`. spec-flow/ux-design-lead not required.

### Legal (CLO — carry-forward, brainstorm)

**Status:** reviewed
**Assessment:** No statutory clock / DPA trigger. The default-branch commit date is
already-authorized repo metadata via the existing installation token. Sentry
logging stays `userId`-hashed only (via `reportSilentFallback`).

## User-Brand Impact

**If this lands broken, the user experiences:** a went-quiet connection is **not**
caught → their Knowledge Base silently stays stale for weeks and they act on
outdated context (the #4706 class) — OR the detector over-fires (e.g. the
any-branch false positive v1 would have shipped), the alert is learned-ignored,
and a real freeze is buried in noise.

**If this leaks, the user's data is exposed via:** nothing new — reads are internal
(`users` columns incl. `kb_sync_history`); the only external call sends
already-authorized `owner/repo` to GitHub; Sentry receives a hashed `userId` only
(no repo name/path/owner handle).

**Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true`
(CPO covered by brainstorm carry-forward). `user-impact-reviewer` runs at PR review.

## GDPR / Compliance (assessed inline)

Read-only, no new processor (GitHub/Sentry already authorized), Sentry `extra` is
hashed-`userId` only — same posture as arms 1 & 2; no regulated-data write surface,
so full `gdpr-gate` not triggered. CLO carry-forward holds.

## Observability

```yaml
liveness_signal:
  what: cron-workspace-sync-health daily run (now covers arm 3)
  cadence: "23 6 * * *" (daily) + cron/workspace-sync-health.manual-trigger event
  alert_target: Sentry cron monitor slug "cron-workspace-sync-health" (existing)
  configured_in: apps/web-platform/server/inngest/functions/cron-workspace-sync-health.ts (postSentryHeartbeat)
error_reporting:
  destination: Sentry via reportSilentFallback (feature "workspace-sync-health")
  fail_loud: true — DB-scan + per-user-probe failures both mirror to Sentry; arm-3 step never throws so heartbeat always posts
failure_modes:
  - {mode: "users scan DB error", detection: "reportSilentFallback op=scan-went-quiet", alert_route: "Sentry issue"}
  - {mode: "token mint / GET /commits failure (revoked install, deleted repo)", detection: "reportSilentFallback op=went-quiet-probe", alert_route: "Sentry issue (per user)"}
  - {mode: "went-quiet finding (the signal)", detection: "reportSilentFallback op=went-quiet", alert_route: "Sentry issue (hashed userId)"}
logs:
  where: Better Stack (pino) for cron run + wentQuiet count; Sentry for findings/errors
  retention: existing Better Stack / Sentry retention (unchanged)
discoverability_test:
  command: "Fire cron/workspace-sync-health.manual-trigger via the Inngest dev console, then query Sentry for op:went-quiet in feature:workspace-sync-health"
  expected_output: "went-quiet issues for any seeded stale-but-pushed user; zero for idle/fresh/healthy"
```

## Open Code-Review Overlap

1 open scope-out touches a referenced file: **#2246** (low-severity kb polish
from PR #2235 — types/dead-props/banner components, mentions `github-app.ts`).
**Acknowledge:** different concern (UI/type polish); arm 3 only *adds* a helper to
`github-app.ts` and does not touch the banner/type surfaces #2246 covers.
Scope-out remains open.

## Infrastructure (IaC)

None. `KB_WENT_QUIET_MAX_GAP_DAYS` is a non-secret optional tuning constant with a
default (mirrors `WORKSPACE_RECONCILE_IGNORE_REPOS` — `.env.example`, not Doppler).
No new server/service/cron/vendor/secret/dependency. Phase 2.8 reviewed (see
`iac-routing-ack` at top of file).

## Risks & Sharp Edges

- **Cross-clock comparison:** `headCommitAt` is GitHub `committer.date`;
  `lastOkSyncAt` is our reconcile clock. `FRESHNESS_SLACK_MS` (5 min) absorbs skew;
  the `now − lastOkSyncAt > N` clause uses our clock on both sides. (DHH argued to
  drop the slack; rejected — the slack guards clause 1's cross-clock boundary,
  which the N-day clause does not touch.)
- **`committer.date` vs `pushed_at`:** v2 reads the default-branch HEAD commit date,
  not repo `pushed_at`, specifically to avoid the feature-branch false-positive
  (Kieran P2-1). A force-push that rewrites old committer dates could in theory mask
  a real change — rare and acceptable for a p3.
- **`at(-1)` = last *appended* row, not max-by-timestamp:** array order = write
  order (`append_kb_sync_row` RPC under a row lock, `session-sync.ts:349-355`); arm
  2 relies on the same assumption.
- **`lastOkSyncAt` fallback is defensive:** `at` is a required `KbSyncRow` field; a
  `NaN` parse only happens on a corrupt row → skip.
- **Mutual exclusivity holds only because arm 3 mirrors arm 2's table/key.** Do not
  refactor arm 3 to scan `workspaces` without re-proving the partition (the v1
  mistake).
- A plan whose `## User-Brand Impact` section is empty or placeholder fails
  `deepen-plan` Phase 4.6 — this one is filled (single-user incident).
