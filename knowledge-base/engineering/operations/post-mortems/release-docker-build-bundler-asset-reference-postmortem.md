---
title: "Web Platform Release red after #8074: the cron hook joined the server bundle and its taxonomy path was a bundler asset reference the Docker context could not resolve"
date: 2026-09-13
incident_pr: 8136
incident_window: "2026-09-13 17:56 UTC (#8074 merged as 0f649dbfb; release run 34773058045 failed at `Build and push Docker image`) — 2026-09-13 ~20:30 UTC (PR #8136 opened with the fix; production stayed on ef8b987f4 until it merged)"
recovery_at: "2026-09-13 (PR #8136 merge → Web Platform Release green on the merge commit; the gate that could not see the class now builds the release's own Docker stage on every PR and blocks the merge)"
suspected_change: "PR #8074 — `server/cron-filing-deny-marker.ts` imported `filingShape` from the cron containment hook `cron-bash-allowlist-hook.mjs`, pulling a standalone CLI into the Next.js (Turbopack) server bundle for the first time; the hook resolved its taxonomy file as `new URL(\"../../../../.claude/hooks/lib/user-surface-taxonomy.txt\", import.meta.url)`, which the bundler treats as a static asset reference, and the file sits four levels above the Docker build context."
brand_survival_threshold: none
status: resolved
triggers:
  []
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — an availability-of-delivery incident; no personal data was involved and no user-facing surface changed (production kept serving the prior image)"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The post-merge release for #8074 failed at the Docker image build with
`Module not found: Can't resolve '../../../../.claude/hooks/lib/user-surface-taxonomy.txt'`.
Every pre-merge check was green, including `web-platform-build` — the job created after
#2347/#2401 to catch exactly "builds locally, fails in the image". Production stayed on the
prior image (`ef8b987f4`) for roughly two and a half hours; a `workflow_run`-triggered release
(34773906413) re-deployed that prior image with `deploy: success`, so the site was never
down — it was not receiving #8074's changes.

## Status

resolved — mirrors the `status:` frontmatter above.

## Symptom

`Web Platform Release` run 34773058045: job `release / release` failed at step
`Build and push Docker image`; `verify-doppler-secrets`, `resolve-target`, `migrate`,
`deploy`, `live-verify` all skipped. The release's own failure e-mail fired
(`[BLOCKED] Soleur Web Platform release failed — nothing was shipped`).

## Incident Timeline

- **Start time (detected):** 2026-09-13 ~20:00 UTC (post-merge verification monitor on the #8074 merge commit reported `failed=[Web Platform Release]`)
- **End time (recovered):** 2026-09-13 (merge of PR #8136 — see `recovery_at`)
- **Duration (MTTR):** ~2.5 h from the red run to the fix PR; recovery completes at #8136's release

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 17:56 | #8074 merged as `0f649dbfb`; release run 34773058045 started. |
| agent | 18:00 | Release red at `Build and push Docker image` (`Module not found`). |
| agent | 18:12 | `workflow_run` release 34773906413 re-deployed the prior image `ef8b987f4` (deploy + live-verify green) — production unchanged, not broken. |
| agent | ~20:00 | Post-merge monitor reported the failure; log read; failing step classified as a real red (the diff introduced the import). |
| agent | 20:05 | Fix drafted; first two repro attempts (rsync copy + symlinked/hardlinked `node_modules`) were unfaithful to the Docker context; the real `docker build --target builder` reproduced rc=1 with the exact error and rc=0 with the fix. |
| agent | 20:13 | PR #8136 opened: path spelling fix, tripwire test, `web-platform-build` re-pointed at the Dockerfile `builder` stage. |
| agent | 20:32 | `web-platform-build` on the PR built the builder stage green (1m52s cold). |
| agent | 21:15 | Ten-seat review; class guard extended; `web-platform-build` made the 4th leg of the `test` aggregator. |

## Participants and Systems Involved

Next.js 16 (Turbopack) server bundle; `apps/web-platform/Dockerfile` builder stage; the
`web-platform-build` CI job; the `test` required-check aggregator; the cron containment hook
`server/inngest/cron-bash-allowlist-hook.mjs` and its new bundle-side consumer
`server/cron-filing-deny-marker.ts`.

## Detection (+ MTTD)

- **How detected:** the ship pipeline's own post-merge release watch (`wg-after-a-pr-merges-to-main-verify-all`), plus the release workflow's failure e-mail.
- **MTTD (mean time to detect):** ~4 min from the red step to the failure notification; ~2 h until the watching session acted on it (the watch's shell was `cd`'d into a worktree another session reaped, so it died mid-watch and was re-armed).

## Triggered by

system — a merge whose pre-merge gate ran in an environment richer than the one it certified.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The hook's `new URL(…, import.meta.url)` is read by the bundler as a static asset reference, and the target is outside the Docker context | the exact `Module not found` path; the file exists in every full checkout; swapping the spelling for `resolve(dirname(fileURLToPath(import.meta.url)), …)` took the real builder stage from rc=1 to rc=0 | — | confirmed |
| `.dockerignore` excludes the file | the path is above `apps/web-platform`, which `.dockerignore` cannot even name | — | superseded (same effect, wrong mechanism) |

## Resolution

PR #8136: (1) the hook computes the taxonomy path lazily with `path.resolve` — opaque to
the bundler, never evaluated in the bundle; (2) `web-platform-build` builds the Dockerfile
`builder` stage from the `apps/web-platform` context with `plugins/soleur` vendored as the
release does; (3) that job is the 4th leg of the `test` aggregator, so a red build blocks
auto-merge; (4) `test/docker-context-import-containment.test.ts` walks `.mjs`, extracts the
`new URL(…, import.meta.url)` form and flags any target above the app root.

## Recovery verification

`Web Platform Release` on #8136's merge commit: `release / release` green through
`deploy` and `live-verify`; `/health` 200 on the new image. Locally: `docker build
--target builder` rc=0 on the fixed hook, rc=1 with main's hook (the exact release error).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did the release fail? `next build` could not resolve a file the hook referenced.
2. Why did `next build` try to resolve it? `new URL("<rel>", import.meta.url)` is the
   bundler's static asset-reference syntax; Turbopack resolves it like an import.
3. Why was the hook in the bundle at all? #8074 made the deny-marker import `filingShape`
   from it — the first bundle-side consumer of a standalone CLI. The review accepted
   "importing it runs nothing" as if load-time behaviour covered the bundler's reading.
4. Why did no pre-merge gate catch it? `web-platform-build` ran `npm run build` on a full
   checkout, where the file exists; the Docker context is `apps/web-platform`. A gate that
   runs in a richer environment than the one it certifies cannot see a context difference.
5. Why would a red gate not have mattered anyway? `web-platform-build` had been advisory
   since creation — in neither the CI Required ruleset nor the `test` aggregator's `needs:`.

## Versions of Components

- **Version(s) that triggered the outage:** main at `0f649dbfb` (#8074)
- **Version(s) that restored the service:** main at #8136's merge commit

## Impact details

### Services Impacted

Release delivery only. The web platform kept serving `ef8b987f4` (the release before #8074); #8074's cron-substrate changes did not reach production until #8136 merged.

### Customer Impact (by role)

- **Operator:** none visible — the site served the prior image; the only effect was #8074's run-report exit not being live for the crons that fire before #8136 merged.
- **Workspace member / end user:** none — no user-facing surface changed in either image.
- **Data subjects:** none — no personal data touched.

## Lessons Learned

A gate that certifies a build must build the same artifact from the same context the release
builds, and must be a required leg of the merge gate; "advisory since creation" is invisible
because green-and-advisory looks identical to green-and-required. When a file changes WHO
compiles it, re-review it as if it were new. This was the fourth instance of the class
(#5890, #6860, #7666/`1edf7a62`, #8074); the 2026-07-23 learning's "guard the boundary
mechanically at PR time" defense had been written and never built. See
`knowledge-base/project/learnings/2026-09-13-the-gate-built-to-catch-docker-only-failures-never-ran-in-docker.md`.

## Action Items & Follow-ups

_No action items — incident fully resolved by PR #8136 (path fix, context-faithful required build gate, class guard closed); nothing remains open._
