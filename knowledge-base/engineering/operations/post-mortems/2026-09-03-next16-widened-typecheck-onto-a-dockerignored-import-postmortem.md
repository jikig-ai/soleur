---
title: "Next 16 widened what next build type-checks onto a .dockerignored import — releases blocked, prod stale"
date: 2026-09-03
incident_pr: 7756
incident_window: "2026-09-03 11:57Z (#7756 merge) → 2026-09-03 15:05Z (prod serving the fix)"
recovery_at: "2026-09-03T15:05Z — prod on 0.257.2 / 511638e24, main tip, zero merges undeployed"
suspected_change: "PR #7756 landed Next 16, which widened the set of files `next build` type-checks to include colocated lib/**/*.test.ts"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - availability (web-platform release/deploy pipeline)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: availability-only. A failing image build blocked the
# DEPLOY of already-merged app code; prod continued serving the last good build.
# No personal-data breach, no confidentiality or integrity loss, no unauthorised
# access. GDPR Art. 33/34 do not apply (n/a).
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

From PR #7756's merge onward, the **Web Platform Release** workflow's `release / release`
job failed at "Build and push Docker image":

```
lib/feature-flags/identity.test.ts(9,32): error TS2307:
  Cannot find module '@/test/helpers/mock-supabase' or its corresponding type declarations.
Failed to type check.
ERROR: process "/bin/sh -c npm run build" did not complete successfully: exit code: 1
```

Every subsequent merge inherited the same failure, so the blast radius grew with each
merge rather than staying with the causing PR.

## Detection

Not detected by an alarm. Found while running `/soleur:ship`'s post-merge release
verification (`wg-after-a-pr-merges-to-main-verify-all`) for an unrelated PR (#7774,
the Fable 5.1 model-launch sweep). That PR's own release run failed, and the job-level
inspection showed the failing step was inherited rather than introduced.

The release job DOES send a `[BLOCKED] Soleur Web Platform release failed — nothing was
shipped` email, so the signal existed; the gap is that nothing correlates *consecutive*
failures into an escalating "prod is N merges stale" signal.

## Impact (measured, not inferred)

```
$ curl https://app.soleur.ai/health
{"status":"ok","version":"0.257.1",
 "build_sha":"171338cd78d1042a94dfff7784b4138485b2b6c9", ...}
```

`171338cd7` is the commit **before** #7756. Measured DURING the incident, three merges were
undeployed:

| commit | PR | deployed? |
|---|---|---|
| `2d5d19088` | #7756 land next 16 | no — deployed 15:04 in `511638e24` |
| `6bc762c66` | #7774 Fable 5.1 model-launch | no — deployed 15:04 in `511638e24` |
| `428e1ec78` | #7780 apex shrink PR4a | no — deployed 15:04 in `511638e24` |

Availability was unaffected — prod kept serving the last good build. The cost is that
merged work was not live, and that the window widened with every merge until the pipeline
was repaired. All three landed in the single deploy that closed the incident; see
**Recovery (measured)** below.

## Root cause

`.dockerignore` prunes `test/`. `lib/feature-flags/identity.test.ts` lives under `lib/`,
so it is **inside** the build context, and it imports `@/test/helpers/mock-supabase`,
which is **outside** it.

That mismatch existed since #4331 and was harmless because `next build` did not
type-check colocated `lib/**/*.test.ts`. **Next 16 widened the type-check set.** Nothing
about the import changed; what changed is which files the image build compiles.

The asymmetry that makes this class invisible pre-merge: local `tsc`, the CI `test` job
and `vitest` all see the **unpruned** tree and pass. Only the image build sees the pruned
one.

## Why the guard did not catch it

`apps/web-platform/test/docker-context-import-containment.test.ts` exists precisely for
this class — it was written after #7666. It stayed green because its **window was
narrower than the property it names**, on two axes simultaneously:

| axis | guard covered | this break needed |
|---|---|---|
| population | context-root `*.config.ts` only (`contextRootConfigs()`) | a file under `lib/` |
| import form | relative `./` specifiers only (`relativeImports()`) | a `@/` alias |

Either axis alone would have caught it. Needing both is what let it through.

This is the same defect shape recorded the same day in
`2026-09-03-every-check-i-shipped-was-narrower-than-the-name-it-carried.md`: a check that
certifies something narrower than its name, where the green is indistinguishable from
coverage.

## Third instance of the class

| # | PR | excluded module | cost |
|---|---|---|---|
| 1 | #5890 | `scripts/sandbox-canary.mjs` | release break |
| 2 | #7666 | `test/repo-wide-suites.ts` | 8 consecutive failed releases, 6 days stale prod |
| 3 | #7756 | `test/helpers/mock-supabase.ts` | this incident |

The remedy has been identical each time (a `!` re-include). The guard added after #2 did
not generalise to #3.

## Resolution

PR #7785:

1. `!test/helpers/mock-supabase.ts` — the exact-path re-include. `mock-supabase.ts`
   imports only `vitest`, so it cannot cascade.
2. The containment guard widened to every build-included source in the context, and to the
   `@/` alias form as well as relative specifiers. The set of roots is **derived** from the
   context root by running each entry through the guard's own `.dockerignore` matcher — not
   hand-listed — so it cannot drift as directories are added. Coverage is pinned by a per-root
   conservation check against an independent `fs.readdirSync({recursive: true})` enumeration, a
   named-member control on the file that broke this release, and an assertion that alias
   resolution is total.

Verified by a real `docker build --target builder` (rc=0, zero TS2307) rather than by the
guard alone, and mutation-proven: removing the re-include reddens the guard naming the
exact offender.

### Recovery (measured)

PR #7785 merged as `511638e24` at 14:31:56Z. The release run it triggered
(`33767400469`) completed **success** at 15:04:46Z — including the `release / release`
job whose "Build and push Docker image" step had failed on every merge since 11:57Z —
with `migrate`, `verify-migrations`, `deploy` and `live-verify` all green.

```
$ curl https://app.soleur.ai/health
{"status":"ok","version":"0.257.2",
 "build_sha":"511638e244f352e957bd4e40a675ce15be700cad",
 "supabase":"connected","sentry":"configured","uptime":87}

$ git log --oneline 511638e24..origin/main
(empty)
```

All three previously-undeployed merges went live in that single deploy: #7756, #7774
(the Fable 5.1 model-launch sweep) and #7780. First failed release to prod serving the
fix: **3h08m**.

### The fix's own review found this class again, inside the fix

#7785's first draft opened its widened guard with a hand-maintained
`BUILD_INCLUDED_DIRS = ["app","components","hooks","lib","server"]`. That array omitted
`e2e/` (16 files, no `.dockerignore` line, therefore in-context and type-checked) and the
root files `middleware.ts` / `instrumentation.ts`. One `@/test/helpers/…` import added to
an e2e file would have reproduced this incident **past a green guard**.

Review found two of the new anti-vacuity controls were themselves vacuous: a flat `> 200`
floor against **843** real files (measured: `app` 165, `components` 220, `server` 316, `lib`
106, `e2e` 16, `hooks` 13, `docs` 0, `public` 0, plus 7 root files) tolerated dropping
`server/` — the largest root, 316 files — and still passing,
and `expect(offenders).toEqual([])` was satisfied by a resolver that returned `null` for 18
real edges because it omitted `index.tsx` — an unresolvable specifier is an *unchecked*
one, and the green looks identical either way. Both survived the author's first mutation
battery; a second battery that enumerated the AXES rather than mutating one shape caught
them.

The remedy each time was to stop restating the system and derive from it. Recorded here
because it is the strongest evidence available for this PIR's own thesis: the author had
this defect class written down in three places — this document, a same-day learning, and
the guard's own header — and still shipped it. What caught it was an adversarial reader on
the diff, not recall.

### A near-miss worth recording

The first draft of the fix added a bare `!test/helpers/` directory bang alongside the
exact-path line. `.dockerignore`'s own `_plugin-vendored` block already records that a
bare bang is **recursive**; it would have re-included all 26 files in `test/helpers/`,
including four `*.test.ts` and helpers importing `esbuild` and
`@anthropic-ai/claude-agent-sdk`, which `next build` would then type-check inside the
image — reproducing the same class in a new place.

It was caught by measuring rather than reasoning: a minimal `docker build` showed the
exact-path form alone puts the file in context while its siblings stay pruned. That
measurement is recorded inline in `.dockerignore` so the next reader does not "fix" the
directory bang back in.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #7788 | Consecutive release failures produce no escalating signal — prod can go N merges stale with only per-run emails | agent |
| #7789 | `lib/**/*.test.ts` (9 files) are type-checked inside the production image build; excluding test files from the image type-check would remove the class rather than patch instances | agent |

## Timeline

Times are UTC. Rows marked `~` are reconstructed from surrounding anchors; every other row
is a GitHub API timestamp (`mergedAt`, run `updatedAt`) or a measured HTTP response.

| Time (UTC) | Actor | Event |
|---|---|---|
| 11:57:00 | agent | #7756 merges as `2d5d19088`; its `release / release` fails at "Build and push Docker image" |
| 12:39:49 | agent | #7774 merges as `6bc762c66`; release fails identically (inherited, not caused) |
| ~13:0x | agent | `/ship` post-merge verification on #7774 finds `release / release` = failure |
| ~13:1x | agent | Job-STEP inspection isolates TS2307; attribution walk shows `171338cd7` green, `2d5d19088` failed |
| ~13:1x | agent | `/health` measured: prod on `171338cd7`, three merges behind |
| 13:22:17 | agent | #7780 merges as `428e1ec78`; release fails identically |
| ~13:2x | agent | Fix drafted; a bare `!test/helpers/` directory bang caught and removed after a minimal `docker build` |
| 13:28:17 | agent | Real image build verifies rc=0, zero TS2307; PR #7785 opened |
| ~14:0x | agent | Review of #7785 returns SHIP with no P1 but finds the widened guard is itself a narrow window and two of its assertions unfalsifiable; all fixed inline and mutation-proven |
| 14:31:56 | agent | #7785 merges as `511638e24` (squash, auto-merge) |
| 15:04:46 | agent | Release run `33767400469` completes **success** — `release / release`, `migrate`, `verify-migrations`, `deploy`, `live-verify` all green |
| ~15:05 | agent | `/health` reports `0.257.2` / `511638e24`; `git log 511638e24..origin/main` empty — **recovered**; all three stale merges live |

Total window, first failed release to prod serving the fix: **3h08m**.

An earlier revision of this table placed detection and the fix at ~15:05–15:25, which is
after the merge that resolved the incident. Those were estimates written while the incident
was still open and never re-derived; the API timestamps above replace them. Recording the
correction rather than silently overwriting it — a post-mortem whose timeline cannot be
ordered is not evidence of anything.
