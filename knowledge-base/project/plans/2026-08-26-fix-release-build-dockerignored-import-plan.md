---
title: "fix(release): the web-platform image build fails on a type-checked import of a dockerignored file"
date: 2026-08-26
slug: fix-release-build-dockerignored-import
branch: feat-one-shot-7395-release-esm-build-failure
issue: 7395
closes: 7395
lane: cross-domain
type: bug
priority: p0-critical
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Every merge to `main` since 2026-08-20T21:16Z has produced a failing `web-platform-release.yml`
image build. `deploy` is gated on that build, so it is skipped, and production keeps serving the
image from the last green run — `dc201e75`, built 2026-08-20T20:35Z. Seven consecutive releases
have failed the same way; the eighth (`a05ae1f7`, today) had already failed its `release` job when
this plan was written.

The fatal error is a TypeScript resolution failure inside the Docker builder stage:

```
Failed to compile.
./vitest.config.ts:4:34
Type error: Cannot find module './test/repo-wide-suites' or its corresponding type declarations.
ERROR: process "/bin/sh -c npm run build" did not complete successfully: exit code: 1
```

`apps/web-platform/vitest.config.ts` imports `./test/repo-wide-suites`, and
`apps/web-platform/.dockerignore` strips `test/` from the build context, so the module is not there
when `next build` runs inside the image.

**The issue's stated root cause is a misdiagnosis and this plan does not act on it.** The
`@anthropic-ai/claude-agent-sdk` ESM line and the `cron-ux-audit.ts` critical-dependency trace are
webpack **warnings**, present verbatim in the last green build that deployed to production.

The fix is to **move the imported file out of the excluded directory**, deleting the cross-boundary
edge rather than creating a guarded exception to it. A separate PR then widens the guard that should
have caught this — the fifth occurrence of the class, and the second whose fix was a `git mv`.

---

## Research Reconciliation — Issue #7395 vs. Codebase

Issue #7395 was filed 2026-08-10 against a *different* failure than the one now live. Every row was
measured on 2026-08-26.

| Issue #7395 claims | Measured reality | Plan response |
|---|---|---|
| Root cause is `Module not found: ESM packages (@anthropic-ai/claude-agent-sdk)` from `server/sandbox-startup-classifier.ts` | That line appears under `⚠ Compiled with warnings in 107s`. It is present **1×** in the last GREEN run (`32414879638`, `dc201e75`) which deployed to production successfully. A warning cannot be the breaker of a build that succeeded with it. | **Cut.** Non-causal. |
| Fix by adding the package to `serverExternalPackages` | `next.config.ts` has listed `"@anthropic-ai/claude-agent-sdk"` there since the MVP commit `5b8e24206`. The proposed fix was in the tree the whole time. | **Cut.** Already present. |
| Second trace: `cron-ux-audit.ts` → `app/api/inngest/route.ts` "Critical dependency" — same root or separate? | Neither. **3×** in the same GREEN run. A dynamic-`require` warning, orthogonal to the break. | **Answered: separate, non-blocking.** |
| Deploy has not run since **2026-08-07**; 19 days stale | False. Eleven consecutive runs succeeded on 08-20 between 00:41Z and 20:35Z. Last fully green run: `32414879638` / `dc201e75` / **2026-08-20T20:35Z**. Production is **~6 days** stale. Corroborated independently by the drift alerter (`prod build_sha dc201e757f63…`). | **Correct the record.** |
| Six consecutive failures, all one cause | Three unrelated causes conflated. `31374522264` (`b3754369`, 08-10 — the run the issue cites) built the image **successfully** and died at the zot mirror: `DIGEST_INVALID`, then `500`, then `##[error]zot mirror FAILED at stage 'copy_v'`. `32293304541` (08-19) failed at `verify-migrations`. The current class began at `32418522892` (`8eb87747`, 08-20T21:16Z). | **Correct the record.** |
| `release / release` fails silently; decide whether it should page | Not silent. Three channels fired: `release-outcome` emailed on every failure (run `32860030881`: `Release-failure email sent to ops@jikigai.com (HTTP 200)`); `scheduled-prod-version-drift.yml` returned `DRIFT_SUSTAINED` every ~30–60 min; it filed **#7676**, `p0-critical` + `action-required`, open since 08-21. | **Cut.** Bought three times over. |
| Post-merge verification must not rely on `--commit` filtering alone | Confirmed, with a sharper cause. `gh run list --commit 924994b2f… -L 200` returns **exactly 200** rows — it saturates the cap — and `web-platform-release` is absent from that page while the query reports `failures: 1`. | **In scope** (PR-2, issue only). |

Corrections to my own working assumptions, recorded because they nearly became premises:

- An early `gh run list --workflow … --branch main` returned results ~5 days stale and self-corrected
  minutes later. A single filtered query is not a reliable enumerator. **This directly constrains
  AC9** — see there.
- The zot-mirror class (08-07…08-10) is **not** verified as fixed. It stopped recurring, which is a
  different statement. Out of scope; noted so the record does not imply otherwise.

---

## Research Insights

### Premise Validation

- `#7395` — **OPEN**, no closing PR. Its *body* is stale (table above).
- `#7666` (`8eb877477`) — merged; introduced the import (`git log -L4,4:apps/web-platform/vitest.config.ts`).
- `#7676` — **OPEN**, the standing drift issue. It self-closes on the next `CLEAN` run.
- `apps/web-platform/test/repo-wide-suites.ts` — tracked, 84 lines, **zero imports**, a single
  `export const REPO_WIDE_SUITES: readonly string[]` of 55 entries.
- ADR grep (`.dockerignore` / build-context): ADR-079, ADR-080, ADR-122, ADR-171. None decides the
  import-boundary rule. No rejected-alternative collision.

### Property List

- **P1** — A merge to `main` produces an image that builds, so `deploy` runs.
- **P2** — "A type-checked file imports a path the Docker build context excludes" cannot recur silently.
- **P3** — In-session post-merge verification cannot report healthy while an expected release workflow is red or absent.
- **P4** — The fact that production is frozen reaches a human channel.
- **P5** — The issue record is accurate.

### Cut List

| Mechanism the ask proposes | Property | What already buys it |
|---|---|---|
| `await import()` / `serverExternalPackages` for the agent SDK | P1 | Nothing to buy — warning, present in the GREEN run; already configured since `5b8e24206`. |
| Resolve the `cron-ux-audit` critical-dependency trace | P1 | Same green-run evidence, 3 occurrences. |
| Make `release / release` page | P4 | `release-outcome` job — measured `HTTP 200` on run `32860030881`. |
| N-consecutive-failure escalation | P4 | `scheduled-prod-version-drift.yml` (#7091) + standing P0 issue #7676. All fired here. |
| A new guard for the import class | P2 | `no-cross-context-import.test.sh` already has the chokepoint, extraction, resolution and a vacuity floor. Only its **predicate** is wrong. |
| **A shared `.dockerignore` evaluator module** | P2 | **Cut at review.** Two models already exist (`dockerfile-copy-dockerignore-parity.test.ts`, and `cloud-init-user-data-size.test.ts:1173` `dockerignoreInfraReincludes()` whose comment reads *"If you edit either parser, update both."*). A third consumer of a twice-modelled concept is the wrong direction, and the chosen fix removes the need for `!` modelling of our own change entirely. |

### The failure class — five occurrences

| # | Date | Issue/PR | File | Mechanism | Fix shape |
|---|---|---|---|---|---|
| 1 | 2026-04-29 | #3045 / `1edf7a622` | `_plugin-vendored/` | COPY-time | re-include |
| 2 | 2026-07-02 | #5875 / #5890, #5894 | sandbox-canary payloads | COPY-time | re-include |
| 3 | 2026-07-03 | #5922 / #5939 | 25 `infra/` scripts | COPY-time | re-include |
| 4 | 2026-07-23 | #6794 / #6852, #6875 | repo-root `scripts/lib/frontmatter-strip/strip.ts` | import, cross-**root** | **inline — the edge was removed, not re-included** |
| 5 | 2026-08-20 | #7666 → this issue | `apps/web-platform/test/repo-wide-suites.ts` | import, cross-**exclusion** | **move — same principle as #4** |

Occurrence #4 is the precedent that matters. The three COPY-time cases were genuinely
re-include-shaped: the Dockerfile *needs* those files in the image. The two import-time cases are
not — the right move is to remove the edge. An earlier draft of this plan proposed a re-include and
was corrected at review.

### Why the two existing guards both miss occurrence #5

- **`apps/web-platform/scripts/lib/no-cross-context-import.test.sh`** (PR #6877, built for #4). Its
  header states the invariant correctly, but its predicate is:

  ```bash
  case "$resolved" in
    "$APP"/*) : ;;  # resolves within web-platform — in the Docker build context
  ```

  The trailing comment is **false** for `$APP/test/`, `$APP/scripts/`, `$APP/supabase/` and
  `$APP/infra/`, all of which `.dockerignore` strips. The guard asserts the **proxy** ("inside the app
  directory") for the **property** ("inside the build context"). `./test/repo-wide-suites` resolves
  inside `$APP`, so it passed. Its success message — `"Docker build context intact"` — asserts a
  cause it never measured, which is an AP-021 diagnostic-honesty instance in its own right and must
  be corrected alongside the predicate.
- **`plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts`** (PR #5943, for #2–#3). Models
  Dockerfile `COPY --from=<stage>` sources and builder-stage `RUN` scripts. A TypeScript import is
  neither. (Note its own coverage gap: `parseBuilderCopySources` requires `--from=<stage>`, so
  `Dockerfile:154`'s context-sourced `COPY _plugin-vendored /opt/soleur/plugin` is unmodelled — the
  two guards do **not** fully span the class, contrary to an earlier draft of this plan.)

### Empirical verification (Docker 29.4.3, busybox context probe, technique from #5890)

```
printf 'FROM busybox\nCOPY <path> /x\nRUN ls -l /x\n' | docker build -q -f - -t dockerignore-probe .
```

| Path | Result | Establishes |
|---|---|---|
| `test/repo-wide-suites.ts` | **ABSENT** | Reproduces the root cause at the context layer, independent of any CI log. |
| `next.config.ts` | PRESENT | App-root files are in the context — the move target is valid. |
| `scripts/assert-dev-signin-eliminated.sh` | PRESENT | A `dir/` exclude plus a `!dir/file` re-include does survive Docker's filter (relevant only to the rejected alternative). |
| `lib/feature-flags/identity.test.ts` | PRESENT | Co-located test files are **not** dockerignored. |
| `test/helpers/mock-supabase.ts` | ABSENT | The target of that file's `@/test/…` import. |

The last two rows drove a hypothesis I raised and then refuted — recorded below.

### The runtime image does not receive app-root files (this corrects a false claim)

An earlier draft rejected moving the file because it "would ship into the runtime image." **That is
false, and the Dockerfile disproves it.** The `runner` stage copies only:

```
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/dist/server ./dist/server
COPY --from=builder /app/scripts/sandbox-canary.mjs …
COPY --from=builder /app/infra/sandbox-canary-argv.json …
COPY --from=builder /app/next.config.mjs ./next.config.mjs
```

Nothing at app root ships except the compiled `next.config.mjs`. `vitest.config.ts` and
`playwright.config.ts` are living proof: both are test infrastructure, both sit at app root, both
are in the build context, neither is in the runtime image. The "semantically wrong — it is test
infrastructure" objection dies to the same counterexample.

### A hypothesis I raised and then refuted

`lib/feature-flags/identity.test.ts` is context-**present** and its line 9 is
`import { mockQueryChain } from "@/test/helpers/mock-supabase";` — a target that is context-**absent**.
Under the naive rule "tsconfig `include: ["**/*.ts"]` means everything is type-checked", that file
should break the build too, making any single-file fix insufficient.

**Refuted by the green run.** `git show dc201e75:…/identity.test.ts | sed -n '9p'` returns that exact
line. `dc201e75` is the last GREEN run — the one that deployed. So the file, the import and the
absent target were all present in a build that passed. The same command shows `vitest.config.ts:4`
was empty at `dc201e75`, confirming the break really did arrive with #7666.

**What it exposes.** The assertion "`next build` type-checks the tsconfig `include` set" is
**falsified**: two context-present files matching `**/*.ts`, both importing an absent module, one
fails the build and one does not. Guard Contract chokepoint 2 must therefore be calibrated
empirically, not derived from tsconfig. Chokepoint 2 also **under-approximates** in a second,
opposite direction: `next-env.d.ts` and `.next/types/**/*.ts` are both tsconfig-included and both
`.dockerignore`-excluded, yet both are **generated by `next build` inside the builder** and are
type-checked there. "Tracked ∩ context" is a subset of the real population plus a generated set.

**Open question PR-1b must settle**, with the experiment named in AC3.

### Exposure re-measured (the first measurement was wrong twice)

The original scan looked only at the **target** specifier and only at **relative** form. Both
narrowings hid real populations.

**Alias imports.** `apps/web-platform/tsconfig.json` maps `"@/*": ["./*"]`, so `@/test/x` is exactly
as build-breaking as `./test/x`, and the existing extraction regex (`['\"]\.\.?/`) cannot see it.
There is a **live production instance**:

```
app/internal/github-app-init/page.tsx:3
  import manifestRaw from "@/infra/github-app-manifest.json";
```

A type-checked production file importing into an excluded directory, alive only because of
`!infra/github-app-manifest.json` (added by #4115 with a comment naming this page). Deleting that
re-include breaks the release exactly as #7395 did — and a relative-only guard stays **green**. So
the guard's coverage would be member-specific: catching today's `test/` member while structurally
unable to catch today's `infra/` member.

**Importer-side filtering.** The predicate must be **two-sided**. Filtering the guard's own pathspec
to importers that themselves live in excluded subtrees yields **12 files / 17 import lines**, all
under `scripts/` (`cla-evidence/*.ts`, `live-verify/*.ts`, `spike/*.ts`, `hash-user-id.ts`, …), each
importing a sibling via `./`. Those importers are context-absent, so they are correctly out of
scope — but only if the guard checks the **importer's** membership too. A one-sided
"resolved target is absent → FAIL" rule flags all 17 as false positives.

### The IaC/code split-brain — the freeze is not uniform

The plan initially assumed the freeze means "code is stale, uniformly." It does not.
`apply-web-platform-infra.yml` and `apply-sentry-infra.yml` both fire
`on: push: branches: [main]` with `paths: apps/web-platform/infra/**` — they **auto-apply on merge,
independent of the image release.** Terraform advanced; the container did not.

Verified instance in the newest undeployed commit, `a05ae1f77`:

- `apps/web-platform/infra/sentry/cron-monitors.tf` sets `enabled = false` on the
  `scheduled-gh-pages-cert-state` monitor — **applied live today**.
- `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-state.ts` loses its
  `{ cron: "0 3 * * *" }` trigger — **frozen in the undeployed image**.
- The `.tf` comment states the coupling explicitly: *"Flip `enabled` back to true ONLY in the same PR
  that restores the cron trigger in `cron-gh-pages-cert-state.ts`."*

The PR author designed those two halves to land atomically. **The freeze split them.** The new
remediation function `cron-gh-pages-cert-reissue.ts` is also undeployed. This generalises: *any* PR
touching both `infra/**` and image code has been silently split for six days. It is the strongest
argument for urgency and it is why PR-1a must not wait on PR-1b.

### Undeployed change set (measured)

Eight commits: `8eb877477` (broke it), `ff8ac47f7`, `f2f3cc4bc`, `42df7d416`, `dd8683701`,
`c33e7d88a`, `924994b2f`, `a05ae1f77`.

**Zero undeployed Supabase migrations** —
`git diff --name-only dc201e75..origin/main -- apps/web-platform/supabase/migrations/` is empty, and
the newest migration (`135_statutory_repin_send.sql`) predates the last green deploy by a month. The
release pipeline runs `migrate` before `deploy`, so six days of batched DDL would have been a real
first-deploy risk. Measured as zero: closed by evidence. **Re-run at `/work` time** — more commits
will have landed.

**#7653 is the wrong headline example.** Of its 20 files, 18 are `.github/workflows/**`,
`.claude/hooks/**`, repo-root `scripts/` and knowledge-base — none ship in the image, and workflows
run from `main`, so they are **already live**. Only `plugins/soleur/skills/review/SKILL.md` (+2 lines)
and `skill-security-scan/scripts/run-scan.sh` are in the deployed path. An earlier draft named it as
"a correctness fix now sitting undeployed"; that is corrected in User-Brand Impact.

### The `-L 200` saturation mechanism (PR-2 input; carried into the issue, not built here)

`cla.yml` and `cla-evidence.yml` trigger on `pull_request_target`, whose runs carry the **base
branch's** HEAD SHA and mostly conclude `skipped`. `gh run list --commit` filters on `head_sha` and
returns **newest-first**, so accumulating CLA noise evicts the oldest runs — exactly the
`push`-triggered `CI` and `web-platform-release` runs that fired at merge time. `ship/SKILL.md:2045`'s
fallback re-queries the total and reads a cap-pinned `200` as "steady", **certifying completeness**;
it is fail-open. `ship/SKILL.md:2040` already specifies the fix and defers it.

### Open Code-Review Overlap

Checked all planned paths against the 64 open `code-review` issues. **None.**

---

## User-Brand Impact

**If this lands broken, the user experiences:** an anonymous visitor to `soleur.ai` meeting a browser
TLS interstitial on an HSTS-preloaded apex — a complete, self-contained brand-ending impression with
no http fallback and no aggregation required. The mechanism is the split-brain above, not staleness
in general: the cert-state monitor was disarmed **live** while the producer change that makes
disarming safe is frozen, and the 2026-08-16 precedent for a wedged apex cert was an 8h15m outage.

**Secondary artifact:** the runtime-plugin host mount. Per `web-platform-release.yml`'s own `paths:`
header, `plugins/soleur/**` changes "must rebuild+deploy the image so the host mount re-seeds", so six
days of skill edits reach every user session **at once** on the first deploy — including `c33e7d88a`,
whose merge title is literally `WIP: feat-one-shot-7580-7553-vacuity-floor-subagent-gate (#7616)`.
The rollback unit is the whole eight-commit image, not a commit.

**If this leaks:** PR-1a's diff adds no data path, store or endpoint. The honest exposure is the
**freeze itself** — live infrastructure now disagrees with the code designed to accompany it.

**Brand-survival threshold:** `single-user incident`. An earlier draft justified this as "one user
encountering a defect the team believes is deployed", which describes a uniform all-users condition —
the textbook `aggregate pattern` shape, not support for the verdict it was attached to. The argument
that **does** hold is the apex-TLS artifact: one visitor, one interstitial, complete damage, no
aggregation. Threshold retained; justification replaced.

**Knowingly unaddressed — response latency.** All three alert channels fired continuously for 144
hours and no action followed. Neither PR fixes that; PR-2 improves *detection* latency, which the Cut
List already establishes was never the binding constraint. Named here rather than left implied by the
PR-2 deferral. The shape that would address it — an escalation with a deadline on unacknowledged P0
`action-required` issues — is out of scope and belongs in its own issue.

---

## Implementation

Three PRs. The seam is drawn so the **one-line unfreeze is hostage to nothing**: an earlier draft
required the guard widening to land in the same PR, which made a P0 outage fix wait on the harder of
the two design problems in this plan.

### PR-1a — Unfreeze production (P1). Mergeable today.

**Phase 1 — Move the file out of the excluded directory.**

```
git mv apps/web-platform/test/repo-wide-suites.ts apps/web-platform/repo-wide-suites.ts
```

Then update the complete reference set (five sites, enumerated by `git grep repo-wide-suites`):

| Site | Change |
|---|---|
| `apps/web-platform/vitest.config.ts:4` | `"./test/repo-wide-suites"` → `"./repo-wide-suites"` |
| `apps/web-platform/test/repo-wide-containment.test.ts:42` | `"./repo-wide-suites"` → `"../repo-wide-suites"` |
| `apps/web-platform/test/repo-wide-containment.test.ts:210` | prose: `test/repo-wide-suites.ts` → `repo-wide-suites.ts` |
| `apps/web-platform/test/repo-wide-containment.test.ts:232` | same prose fix |
| `scripts/lib/test-relevance-paths.sh:248` | comment: same prose fix |

**Why the move rather than a `.dockerignore` re-include** — this is the plan's central decision and
an earlier draft got it wrong:

- The move **deletes** the cross-boundary edge; a re-include **creates a permanent exception that
  then needs guarding forever**. The draft's own proposed comment said as much ("Guarded by
  no-cross-context-import.test.sh"). Fewer invariants beats better-guarded invariants.
- It matches occurrence #4's fix (#6875 removed the edge; it did not re-include).
- It removes the whole Phase-2 cascade: no `!` modelling for our change, no evaluator extraction, no
  cross-language boundary.
- A re-include would place a one-file `test/` directory inside the image, type-checked via `**/*.ts`,
  safe **only** while that file has zero imports — an unenforced assumption the draft recorded as a
  fact and installed nothing to preserve.
- It touches `.ts` files, so `scripts/test-all.sh`'s relevance filter routes the diff correctly. A
  `.dockerignore`-only diff is an orphan relative to every shard, which the draft papered over with a
  manual full-battery clause.

No test-runner blast radius: nothing at app root is globbed by any vitest project (`unit` =
`test/**` + `lib/**`, `component` = `test/**/*.test.tsx`, `repo-wide` = the explicit list).

**Phase 2 — Prove the containerized build actually passes.**

`next build`'s TS pass reports the **first** error and exits, so "the CI log named one file" is not
evidence there is only one — and `test/` has been context-absent since the exclusion was added, which
could have masked further failures behind `vitest.config.ts:4`. Build the builder stage in a
throwaway copy (`docker build --target builder`) and record the outcome. This is AC3 and it is what
makes "PR-1a is sufficient" a measured claim instead of an inference.

**Phase 3 — Correct the record (P5).** Comment on #7395 with the Reconciliation table, the corrected
08-20 date, the three conflated classes, and the already-bought alerting. `Closes #7395` in the PR
body. Leave #7676 alone — it self-closes on the next `CLEAN` drift run. File the PR-1b and PR-2
issues.

### PR-1b — Widen the guard (P2)

Change `no-cross-context-import.test.sh`'s membership test from "resolves inside `apps/web-platform/`"
to a **two-sided** Docker-build-context rule, and fix its success message (AP-021: it currently claims
"Docker build context intact", a cause it never measured).

**Home it in the `repo-wide` vitest project.** `scripts/test-all.sh` runs that project
unconditionally and documents why: *"That guard runs in the repo-wide project, so it is never gated by
the thing it guards."* That dissolves the shard problem with no manual-invocation clause — and the
registry for that project is `repo-wide-suites.ts`, the very file at the centre of this outage.

**Do not extract a shared `.dockerignore` evaluator.** Two models already exist and their own comment
says "If you edit either parser, update both." Parse the exclusion set inside the guard from
`.dockerignore` at runtime (single authority, no drift), handling exact `!<path>` re-includes — needed
for the live `@/infra/github-app-manifest.json` case — and **failing loud** on any re-include shape not
modelled.

### PR-2 — Presence-aware post-merge verification (P3)

Issue only; no plan text. It carries the measured saturation evidence, the `ship/SKILL.md:2040`
design already written, `scripts/audit-bot-codeql-coverage.sh` as the template (enumerate → 
`commits/<sha>/check-runs` → `missing` as a first-class verdict → sanity floor; add `--paginate`), and
the hazard that `web-platform-release.yml`'s outer `on.push.paths` uses the **Actions glob dialect**
while `reusable-release.yml`'s inner `check_changed` uses the **git-pathspec dialect**.

P3 is **not uncovered** — `scheduled-prod-version-drift.yml` caught this incident correctly and
continuously. PR-2 buys detection *latency*, which is why it does not gate anything here.

---

## Guard Contract

### Guard 1 — Docker-build-context import closure

**Property.** For every file that is **present in the Docker build context** and **type-checked
inside the builder**, every module specifier it resolves to a repo path is **also present in the
Docker build context**.

**Assembly** — chokepoints, not members:

1. **Context membership** — `.dockerignore`, the single authority, parsed at runtime. Exact `!<path>`
   re-includes honoured; any unmodelled shape **fails loud**.
2. **The type-checked population** — calibrated empirically (see the refuted hypothesis), not read off
   tsconfig. It is neither a subset nor a superset of "tracked ∩ context": `identity.test.ts` is in
   both and is apparently not checked, while `next-env.d.ts` and `.next/types/**` are tsconfig-included,
   context-**absent**, and *generated then checked* inside the builder.
3. **Two-sided predicate** — flag only when the **importer** is context-present **and** the resolved
   target is not. One-sided rules produce 17 false positives from `scripts/`-internal imports.
4. **Import extraction** — every specifier that can resolve to a repo path, under **every** mechanism
   the app uses: relative (`./`, `../`) **and** `tsconfig.paths` aliases (`@/*` → `./*`, read from
   tsconfig, never hardcoded). Must cover `import type` (erased at emit but resolved at type-check),
   `export … from` re-exports, and **every** specifier on a line — the current implementation pipes
   through `head -1` and silently drops the second.
5. **Specifier → path resolution** — mirror `moduleResolution: "bundler"`: probe `.ts`, `.tsx`,
   `.d.ts`, `.js`, `/index.*`. `vitest.config.ts` imports **without** an extension, so `realpath` alone
   resolves to a path in no re-include set. An unresolvable specifier must **fail loud, never skip** —
   "probe on disk, else skip" is fail-open. Use `realpath -ms` (no-symlinks): Docker matches the
   **literal** context path and does not follow symlinks out of the context.
6. **Preserve the outside-`$APP` branch explicitly, before any context evaluation.** The widened
   predicate subsumes the old one *logically*, but the obvious implementation does not: a
   context-relative evaluator fed `../../scripts/lib/frontmatter-strip/strip.ts` matches no
   `excludedDirPrefixes` and no `^`-anchored glob, so `isStripped` returns false and the #6852 shape
   passes. Subsumption is a constraint on the implementation, not a property of the predicate.

**Mutation matrix** — derived from the design, written before the guard.

| # | Mutation | Why it must redden |
|---|---|---|
| 1 | Add a relative import into an excluded directory from a type-checked file | Reproduces the incident. |
| 2 | The same import in **alias** form (`@/test/…`) | The shape the current regex cannot see, and the one already live via `@/infra/…`. A guard reddening on 1 but not 2 has reproduced the proxy-vs-property error in its extraction step. |
| 3 | Delete `!infra/github-app-manifest.json`, leaving `page.tsx`'s `@/infra/…` import dangling | Proves the guard consults `.dockerignore` **and** handles aliases, against a real production importer. Asserted as a **pair** with H2 below — same repo state, re-include present → GREEN, absent → RED. Neither half alone discriminates. |
| 4 | Import into a **second** excluded directory (`./supabase/…` or `./scripts/…`) from a context-present file | Kills every `test/`-hardcoding implementation. The draft's six rows all perturbed one axis. |
| 5 | Point the population enumeration at a nonexistent glob so it returns zero files | **Vacuity floor.** Write it `-lt 1`, not `-eq 0`: `scripts/guard-vacuity-floor.test.sh` derives its population by matching `-lt|-le|-ge`, so an `-eq` floor is invisible to the meta-guard. |
| 6 | Re-import the #6852 shape (production file → repo-root `scripts/lib/…`) | Chokepoint 6. Proves no coverage was traded away. |

**Harness rows** — mutating only the system under test cannot see a vacuous harness.

| # | Input | Expected |
|---|---|---|
| H1 | Stub the violation collector to return an empty list | **RED** |
| H2 | **Must-PASS:** an import into an excluded directory **with** a matching `!` re-include (`page.tsx` → `@/infra/github-app-manifest.json`) | **PASS** — the only row separating "consults `.dockerignore`" from "pattern-matches a directory name". Pairs with row 3. |
| H3 | **Must-PASS:** a type-checked file importing a non-excluded path (`./lib/…`) | **PASS** — proves the guard is not rejecting everything. |
| H4 | **Must-PASS:** a `scripts/`-internal `./sibling` import (one of the 17) | **PASS** — pins the two-sided predicate. A one-sided guard fails here. |

Deliberately **not** included, and why: a "second file" row (the guard is a `while` loop with `fail=1`
accumulation and no `break` — that row tests bash); a `test/`→`test/` must-PASS row (the pathspec
already excludes `test/**`, so it is a tautology); and pattern-order and unmodelled-glob rows (they
existed only to service the re-include the plan no longer makes — order remains a documented limit of
the parsers, now out of this PR's scope).

---

## Observability

```yaml
liveness_signal:
  what: "web-platform-release.yml `deploy` reaches success, and prod /health build_sha advances"
  cadence: "per merge to main touching the release path filter"
  alert_target: "ops@jikigai.com (release-outcome email) + issue label ci/prod-version-drift"
  configured_in: ".github/workflows/web-platform-release.yml; .github/workflows/scheduled-prod-version-drift.yml"

error_reporting:
  destination: "job failure -> release-outcome classifier -> Resend email; drift alerter -> P0 action-required issue"
  fail_loud: true

failure_modes:
  - mode: "A type-checked, context-present file imports a context-absent path (this class)"
    detection: "no-cross-context-import guard, two-sided predicate, homed in the repo-wide vitest project (runs unconditionally)"
    alert_route: "red required check on the PR; never reaches main"
  - mode: "In-session post-merge verification reports healthy while the release run is red or absent"
    detection: "NOT COVERED IN-SESSION — PR-2. Covered by the drift alerter on its cron cadence, ~5h."
    alert_route: "drift alerter only, until PR-2 lands"
  - mode: "A PR splits across auto-applied infra/** and the frozen image (the split-brain)"
    detection: "NOT COVERED — surfaced by this plan's review, no mechanism watches it"
    alert_route: "none; filed as a follow-up issue"

logs:
  where: "GitHub Actions run logs; the drift alerter's step summary and issue body"
  retention: "GitHub default (90 days)"

discoverability_test:
  command: "bash apps/web-platform/scripts/lib/no-cross-context-import.test.sh"
  expected_output: "OK: <N> import(s) scanned; none resolve outside the Docker build context"
  # No credentials, no ssh, no network.
```

---

## Architecture Decision (ADR/C4)

**PR-1a: no ADR.** A file move plus reference updates.

**PR-1b: no ADR, given the design above.** The invariant is the one PR #6877 already recorded; PR-1b
corrects the predicate to match the invariant the guard's own comment states. *An ADR would be
required if PR-1b instead extracted a shared evaluator across the `apps/` ↔ `plugins/` boundary — that
would overturn the parity suite's stated inline-no-lib convention and deepen an `apps/` → `plugins/`
dependency for an app-owned config file. The design above avoids it.*

**PR-2: an ADR is required** — "post-merge verification asserts the presence of an expected workflow
set, not the absence of failures in a truncatable page" reverses the current count-based contract.
Authored there; ordinal re-verified against freshly-fetched `origin/main` immediately before merge.

**C4: no impact.** All three model files were read. No external human actor, external system/vendor,
container/data store, or actor↔surface access relationship changes — `github`, `ghcr`, `projectZot`
and `zotRegistry` are already modelled and gain no edge.

---

## Acceptance Criteria

### Pre-merge (PR-1a)

- **AC1** — `apps/web-platform/repo-wide-suites.ts` exists, `apps/web-platform/test/repo-wide-suites.ts`
  does not, and `git grep -c 'test/repo-wide-suites'` over the repo (excluding `knowledge-base/`)
  returns 0.
- **AC2** — Busybox probe: `repo-wide-suites.ts` is **PRESENT** in the build context.
- **AC3** — **`docker build --target builder` completes** on a throwaway copy carrying the fix.
  A PR that has not run this cannot claim the fix is sufficient: `next build` reports only the first
  type error, so the CI log naming one file is not evidence there is only one.
- **AC4** — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — 0 errors. (Never `npm run -w`;
  the repo root declares no `workspaces` field.)
- **AC5** — `bash scripts/test-all.sh` green, including the `repo-wide` project, which validates the
  moved constant against `repo-wide-containment.test.ts`.
- **AC6** — PR body carries `Closes #7395`, links this plan, and links the PR-1b and PR-2 issues.

### Pre-merge (PR-1b)

- **AC7** — Guard passes clean on the real repo with a non-zero scan count, and its success message no
  longer asserts an unmeasured cause.
- **AC8** — Mutation rows 1–6 RED; harness rows H1 RED and **H2/H3/H4 PASS**. Observed output per row
  in the PR body. A matrix where every row reddens has not shown the guard discriminates.
- **AC9** — Exposure re-measured **after** the predicate change, alias-aware and two-sided, and
  reported as an explicit count rather than asserted as "zero".
- **AC10** — No second `.dockerignore` model is introduced. (The claim "exactly one place" is already
  false — `cloud-init-user-data-size.test.ts:1173` is the second — so the criterion is *no new one*.)

### Post-merge (automated)

- **AC11** — **Primary.** `curl -fsS https://app.soleur.ai/health | jq -r .build_sha` returns the new
  merge SHA and **not** `dc201e757f63faa2001b4cf3e4ae4d8e6748bb38`. This is the criterion the issue
  asked for, and it subsumes any digest check — the old digest cannot serve a new `build_sha`.
- **AC12** — Corroboration only: the release run shows `release: success` and `deploy: success`, not
  skipped. Enumerated by workflow name. **Explicitly secondary**, because this plan documents that the
  workflow-and-branch-filtered query returned 5-day-stale results in this very session; PR-1a's
  delivery evidence must not rest on a query the plan itself declares unreliable.
- **AC13** — `scheduled-prod-version-drift.yml` reports `CLEAN` and **#7676 closes itself**. Closing it
  directly would assert the outcome the alerter exists to measure.
- **AC14** — Re-check that no Supabase migrations accumulated between planning and merge.
- **AC15** — The split-brain follow-up issue exists, naming the `cron-gh-pages-cert-state` monitor/producer
  divergence and the general class (a PR spanning auto-applied `infra/**` and the frozen image).

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The move breaks a consumer not in the enumerated set | `git grep repo-wide-suites` returns exactly 5 sites; AC1 asserts zero stale references and AC5 runs the containment guard that reads the constant. |
| A second masked type error surfaces once the first is fixed | AC3 builds the builder stage pre-merge. This is the whole reason AC3 exists. |
| PR-1a merges and the release fails for a different reason | AC11 asserts served bytes, not a green conclusion. The zot-mirror class is unverified-as-fixed and is the likeliest such reason; that would be a separate issue. |
| Six days of batched migrations land at once | Measured zero; AC14 re-checks at merge time. |
| The widened guard produces false positives | AC9 re-measures rather than asserting; H2/H3/H4 pin the three must-PASS shapes (re-include honoured, non-excluded target, `scripts/`-internal sibling). |
| Widening the guard makes `!<path>` the cheapest way to go green, and `test/` holds credential-shaped fixtures | The move sets the opposite precedent — remove the edge, do not except it. PR-1b adds no re-include. If a future re-include is proposed, the `!` set should be bounded by review. |

---

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| **`.dockerignore` re-include (`!test/repo-wide-suites.ts`)** — the original proposal | **Rejected at review.** Mechanically works (busybox-verified), but creates a permanent exception needing permanent guarding, leaves a one-file `test/` dir in the image whose safety depends on an unenforced zero-imports property, and produces a `.dockerignore`-only diff that is an orphan to every test shard. The move removes all three. |
| **Inline the 55-entry constant into `vitest.config.ts`** — the #6875 shape | **Rejected on measurement.** #6875 inlined a ~6-line pure function with one consumer. `REPO_WIDE_SUITES` has a second consumer that is *the guard for its own correctness*: `test/repo-wide-containment.test.ts` recomputes the set from disk and fails on drift (`"REPO_WIDE_SUITES has drifted from what is on disk."`). Inlining forces that test to import a vitest config to read a constant, or duplicates 55 entries. Worse dependency shape than the one being fixed. |
| Add `vitest.config.ts` to `tsconfig.json`'s `exclude` | Drops a real config file from `tsc --noEmit` coverage everywhere, and fixes only this instance. |
| `typescript.ignoreBuildErrors` in `next.config.ts` | Disables type-checking for the entire production build to route around one missing file. |
| Remove the `test/` exclusion from `.dockerignore` | Ships the whole test tree into the build context for no benefit. |
| Extract a shared `.dockerignore` evaluator module | Two models already exist ("update both"); a third consumer deepens an `apps/` → `plugins/` dependency for an app-owned file and overturns the parity suite's stated inline-no-lib convention. Cut. |
| Build an N-consecutive-failure pager | P4 is bought three times and all three fired. The gap was response, not detection. |
| Fold PR-1b into PR-1a | An earlier draft required exactly this and it was the plan's worst structural choice — it made a one-line P0 unfreeze wait on the harder design problem. |

---

## Domain Review

**Domains relevant:** engineering. Lane defaulted to `cross-domain` (fail-closed): no `spec.md`
exists for this branch.

### Engineering

**Status:** reviewed (architecture-strategist, test-design-reviewer, code-simplicity-reviewer,
user-impact-reviewer)
**Assessment:** The review pass changed the plan materially and in three independent directions. The
fix mechanism flipped from a `.dockerignore` re-include to a `git mv`, after the draft's rejection of
the move was falsified against the Dockerfile's runner stage. The guard predicate gained three
chokepoints it was missing — alias extraction, two-sided membership, and specifier resolution — each
backed by a live counterexample in the tree. And the freeze was shown not to be uniform: auto-applied
Terraform has been advancing while the image stayed frozen, splitting PRs their authors designed to
land atomically. The original draft's central diagnosis (the issue's ESM root cause is a
misdiagnosis; the existing guard asserts a proxy for its own stated property) survived review intact.

### Product/UX Gate

Not applicable — no UI surface. **Tier:** none.

---

## Files to Edit

**PR-1a**
- `apps/web-platform/test/repo-wide-suites.ts` → `apps/web-platform/repo-wide-suites.ts` (`git mv`)
- `apps/web-platform/vitest.config.ts` (line 4)
- `apps/web-platform/test/repo-wide-containment.test.ts` (lines 42, 210, 232)
- `scripts/lib/test-relevance-paths.sh` (line 248, comment)

**PR-1b**
- `apps/web-platform/scripts/lib/no-cross-context-import.test.sh` — two-sided predicate, alias
  extraction, resolution probing, outside-`$APP` branch, `-lt 1` vacuity floor, corrected success
  message; rehomed into the `repo-wide` vitest project
- `apps/web-platform/vitest.config.ts` / `apps/web-platform/repo-wide-suites.ts` — register the guard
  in the `repo-wide` project

**PR-2** — issue only; no files in this plan.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-7395-release-esm-build-failure/tasks.md`
