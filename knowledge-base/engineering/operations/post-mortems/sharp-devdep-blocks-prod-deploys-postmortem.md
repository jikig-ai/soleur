---
title: "A Dependabot sharp bump moved sharp dev-only and blocked every prod deploy for ~21h"
date: 2026-07-30
incident_pr: 7092
incident_window: "2026-07-30T11:07:51Z — 2026-07-30T14:20:00Z (deploy-blocking); prod last updated 2026-07-29T15:18:56Z"
recovery_at: "pending — this PR"
suspected_change: "PR #7082 (chore(deps): consolidate the open Dependabot backlog into one bump) raised apps/web-platform devDependency sharp ^0.34.5 -> ^0.35.0"
brand_survival_threshold: aggregate pattern
status: ongoing
triggers:
  - Web Platform Release `release / release` job failed on `Build and push Docker image`
  - `deploy` job SKIPPED on 2 consecutive main commits, so prod kept serving the prior image
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

A Dependabot consolidation PR raised `apps/web-platform`'s **devDependency** `sharp` from `^0.34.5`
to `^0.35.0`. Next.js declares `sharp` as an **optionalDependency at `^0.34.3`**, so `0.35.x` no
longer satisfies it. npm could no longer dedupe a single `sharp` serving both Next's production
optional dep and the repo's devDep, and resolved it as **dev-only**
(`node_modules/sharp` → `{"version": "0.35.3", "dev": true}`).

The runner stage of `apps/web-platform/Dockerfile` installs with `npm ci --omit=dev`, which
therefore installed no `sharp`. A build-time assertion added by #3422 —
`RUN node -e "require.resolve('pdfjs-dist/legacy/build/pdf.mjs'); require.resolve('sharp')"` —
fired with `Error: Cannot find module 'sharp'`, failing the Docker build, skipping the `deploy`
job, and leaving production on the image from `34654d7ab`.

**The guard did its job.** Its own comment states the intent: *"sharp is transitive via Next.js —
if Next ever drops it, this assertion fires loudly instead of breaking kb-share image previews
silently."* Without it, `sharp` would have been absent at runtime and the failure would have
surfaced only as a WARN Sentry breadcrumb from a `try/catch` in `pdf-text-extract.ts` /
`kb-preview-metadata.ts`. The visible outage is the designed-for outcome; a silent one was the
alternative.

## Status

`ongoing` — the fix is in this PR and not yet merged. Flip to `resolved` once a release run on the
merge commit reaches `deploy: success` and `/health` serves the new version.

## Symptom

`Web Platform Release` → `release / release` → `Build and push Docker image`:

```
#20 0.688 Error: Cannot find module 'sharp'
#20 ERROR: process "/bin/sh -c node -e \"require.resolve('pdfjs-dist/legacy/build/pdf.mjs'); require.resolve('sharp')\"" did not complete successfully: exit code: 1
ERROR: failed to build: failed to solve: ...
##[error]buildx failed with: ...
```

Job outcome: `await-ci` success, `verify-doppler-secrets` success, `release / release` **failure**,
`migrate` success, and `verify-migrations` / `live-verify` / `deploy` / `notify-gated` all
**skipped**. A skipped `deploy` is the silent half: the release run is red, but nothing pages, and
production simply keeps serving the previous image.

## Incident Timeline

- **Prod last successfully updated:** 2026-07-29T15:18:56Z (`34654d7ab`)
- **First deploy-blocking failure of THIS cause:** 2026-07-30T11:07:51Z (`3d9817134`, PR #7082)
- **Second occurrence:** 2026-07-30T11:57:53Z (`dc6dd1f70`, PR #7072 — an unrelated CI-registration PR that merged into the broken state and inherited it)
- **Detected:** 2026-07-30T~14:07Z — `agent`, while running `/ship`'s mandatory post-merge release verification (`wg-after-a-pr-merges-to-main-verify-all`) for PR #7072
- **Diagnosed:** 2026-07-30T~14:15Z — `agent`
- **Fix authored + verified:** 2026-07-30T~14:20Z — `agent` (this PR)

Note the two earlier main-branch release failures (`11674a1ab` at 15:53Z on 07-29,
`3c7a39809` at 21:54Z) have **different** failing steps — `[deploy] Verify deploy script
completion` and `[await-ci] Wait for CI test check-run` respectively. They are not this incident
and are not addressed here; they are why prod's last good image predates this cause. See Action
Items.

## Participants and Systems Involved

`apps/web-platform` Docker build (runner stage), npm dependency resolution, Next.js
optionalDependencies, GitHub Actions `web-platform-release.yml`.

## Detection (+ MTTD)

**MTTD ≈ 3h** from the first deploy-blocking failure (11:07Z) to detection (14:07Z) — and detection
was **incidental**: it came from a different PR's post-merge verification step, not from an alert.
Nothing paged on the first occurrence. This is the finding with the most leverage in this PIR.

## Triggered by

PR #7082 — `chore(deps): consolidate the open Dependabot backlog into one bump`. Its
`apps/web-platform/package.json` diff was 8 lines: `next ^15.5.18→^15.5.21`,
`postcss ^8.5.10→^8.5.18`, `sharp ^0.34.5→^0.35.0`, `protobufjs ^7.6.4→^7.6.5`. Only the `sharp`
line matters here; `next`'s own `optionalDependencies.sharp` range was `^0.34.3` both before and
after, so Next did not change.

## Root-cause hypothesis (triage)

Confirmed, not hypothesised — the resolution chain was verified end to end:

1. `next@15.5.22` declares `optionalDependencies.sharp: ^0.34.3` (unchanged by the bump).
2. The repo's own devDependency moved to `^0.35.0`, which does not satisfy `^0.34.3`.
3. npm therefore could not hoist one `sharp` to serve both, and the regenerated lockfile carried a
   single `node_modules/sharp@0.35.3` flagged `dev: true`.
4. `npm ci --omit=dev` in the runner stage installs no dev packages → no `sharp`.
5. The #3422 assertion resolves `sharp` and fails.

## Resolution

Promote `sharp` from `devDependencies` to `dependencies` at `^0.35.0` (operator decision,
2026-07-30), and regenerate both lockfiles. This makes the production requirement **explicit**
rather than leaning on Next.js's transitive optional dependency — the arrangement that just proved
fragile, and the one the assertion's own comment anticipated breaking.

Rejected alternatives, recorded so the next person does not re-litigate:

- **Revert to `^0.34.5`.** Smallest diff and restores dedupe, but keeps prod dependent on a
  transitive optional dep that breaks again on the next Next.js or sharp major, and re-opens
  whatever advisory prompted the bump.
- **Promote and pin to `^0.34.x`.** Most conservative on runtime behaviour, but defers the 0.35
  upgrade without removing the fragility.

## Recovery verification

**Baseline measured from prod, not inferred.** At 2026-07-30T~16:20Z, `GET https://app.soleur.ai/health`
returned 200 with:

```json
{"status":"ok","version":"0.244.0","build_sha":"34654d7ab11b2c28ed08f559ac5af1ef59042cb3","supabase":"connected","sentry":"configured","uptime":60619,"memory":348}
```

`build_sha` is exactly `34654d7ab` — the last release that reached `deploy: success` — and `uptime`
60619s ≈ **16.8h**. That is the outage stated as a measurement rather than an inference, and it gives
the recovery test a precise form: after this PR deploys, `/health`'s `build_sha` must equal the merge
commit. Note `/api/health` is NOT the surface — it 307-redirects to `/login`; an earlier draft of
this PIR cited it, which would have sent the next reader to a redirect.


Verified pre-merge by reproducing the failing assertion rather than reasoning about it. In a clean
temp dir containing only the new `package.json` + `package-lock.json`:

```
npm ci --omit=dev --ignore-scripts   -> RC=0
node -e "require.resolve('sharp')"                              -> OK
node -e "require.resolve('pdfjs-dist/legacy/build/pdf.mjs')"     -> OK
```

That is the Dockerfile guard's exact command passing. Also confirmed: `node_modules/sharp` no
longer carries `dev: true`; 32 `@img/sharp-linux*` / `@img/sharp-libvips-linux*` packages present
with **0** dev-only; `bun install --frozen-lockfile` reports no changes; `npm ci --dry-run` clean;
`sharp` still resolves in the full (dev-inclusive) install so dev tooling is unaffected.

Post-merge, recovery is confirmed by the release run on the merge commit reaching
`deploy: success` and `/health` serving the new version.

## Root Cause(s) — 5-Whys

1. **Why was prod stale?** The `deploy` job was skipped. **Why?** The Docker build failed.
2. **Why did the build fail?** The runner image had no `sharp`, and a build-time assertion caught it.
3. **Why was `sharp` missing?** `npm ci --omit=dev` strips dev packages, and `sharp` resolved dev-only.
4. **Why did it resolve dev-only?** Its declared range (`^0.35.0`) stopped intersecting Next.js's `optionalDependencies.sharp` range (`^0.34.3`), so npm could not dedupe one copy across the dev and prod trees.
5. **Why did a range change flip a production dependency?** Because `sharp`'s presence in the production image was **implicit** — inherited from a transitive optional dependency and only pinned, not declared, by the repo. A version bump was sufficient to remove it.

## Versions of Components

- `next` 15.5.22 (`optionalDependencies.sharp: ^0.34.3`)
- `sharp` 0.35.3 resolved (declared `^0.35.0`)
- npm 11 (the version the `lockfile-sync` gate pins)
- Node 22 (`node:22-slim` base image)

## Impact details

**No user-visible regression, and no data exposure.** Production continued serving the previous
image throughout; the blocked deploys meant new work did not reach users, not that existing
behaviour broke. `art_33_triggered` / `art_34_triggered` are both `false`: no personal data was
accessed, altered, lost, or disclosed — this is an availability-of-deployment incident with no
processing consequence, so the GDPR Art. 33 72h clock does not start.

Threshold is `aggregate pattern` rather than `single-user incident`: no individual user was at
risk. The realistic harm is second-order and cumulative — every PR merged during the window
(including #7072 and #7088) silently did not reach production, and the longer that persists the
larger the eventual cutover and the harder attribution becomes.

Had the #3422 assertion not existed, the same bump would instead have shipped an image whose
`sharp` was absent at runtime, degrading kb-share image previews and PDF text extraction behind a
`try/catch` that emits only a WARN breadcrumb. That counterfactual is worse, and it is the reason
this PIR treats a red build as the good outcome.

## Lessons Learned

1. **A dependency that production needs must be declared in `dependencies`, not merely pinned in
   `devDependencies` and inherited transitively.** A pin constrains a version; it does not assert
   presence. `npm ci --omit=dev` reads the block, not the intent.
2. **A range bump can silently relocate a package between the dev and prod trees.** Dependency
   review for a version bump should ask "does this range still intersect every consumer's range?",
   because a non-intersection does not error — it duplicates or reassigns.
3. **A skipped `deploy` job is a silent outage in the same way a green-with-no-artifact run is.**
   The release workflow was RED for ~3h across two commits and nothing paged; it was found by
   another PR's post-merge verification. `wg-after-a-pr-merges-to-main-verify-all` is currently the
   only thing standing between this class and an indefinite stale prod.
4. **Build-time assertions on lazily-imported runtime deps pay for themselves.** #3422's guard
   converted a silent runtime degradation into a loud build failure. Keep the pattern; extend it
   when a new lazily-imported dep lands.

## Action Items & Follow-ups

| Issue | Action | Owner |
|---|---|---|
| #7091 | Alert on a red `Web Platform Release` / skipped `deploy` on `main`, so this class pages instead of waiting for an unrelated PR's post-merge check. Prefers a "deployed version != main HEAD" check over a per-mechanism notifier | agent |

Deliberately **not** filed: the two earlier, differently-caused main release failures
(`11674a1ab` — `[deploy] Verify deploy script completion`; `3c7a39809` — `[await-ci] Wait for CI
test check-run`). Both are plausibly transient, and the discriminator is free: if the release run on
this PR's merge commit reaches `deploy: success`, they self-resolved and need no action. If it fails
on either of those steps instead, THEN file — with that run as evidence rather than a guess. Filing
now would be filing against an unmeasured hypothesis.
