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
Next.js build worker exited with code: 1
ERROR: process "/bin/sh -c npm run build" did not complete successfully: exit code: 1
```

`apps/web-platform/vitest.config.ts` imports `./test/repo-wide-suites`; `apps/web-platform/tsconfig.json`
type-checks it (`include: ["**/*.ts", …]`); and `apps/web-platform/.dockerignore` strips `test/`
from the build context, so the module is not there when `next build` runs inside the image.

**The issue's stated root cause is a misdiagnosis and this plan does not act on it.** The
`@anthropic-ai/claude-agent-sdk` ESM line and the `cron-ux-audit.ts` critical-dependency trace are
webpack **warnings**, present verbatim in the last green build that deployed to production. They
are not the breaker and never were. The evidence is in Research Reconciliation below.

Two deliverables follow from that: unfreeze the release (a one-line `.dockerignore` re-include,
empirically verified), and close the recurrence gap — this is the **fifth** occurrence of the
"a file exists in git but not in the Docker build context" class, and the two guards that exist
today each miss it for a specific, nameable reason.

---

## Research Reconciliation — Issue #7395 vs. Codebase

Issue #7395 was filed 2026-08-10 against a *different* failure than the one now live. Sixteen days
of drift separate its body from reality. Every row below was measured on 2026-08-26.

| Issue #7395 claims | Measured reality | Plan response |
|---|---|---|
| Root cause is `Module not found: ESM packages (@anthropic-ai/claude-agent-sdk)` from `server/sandbox-startup-classifier.ts` | That line appears under `⚠ Compiled with warnings in 107s`. It is present **1×** in the last GREEN run (`32414879638`, `dc201e75`) which deployed to production successfully. A warning cannot be the breaker of a build that succeeded with it. | **Cut.** Non-causal; no work. |
| Fix by adding the package to `serverExternalPackages` in `next.config.ts` | `next.config.ts` has listed `"@anthropic-ai/claude-agent-sdk"` in `serverExternalPackages` since the MVP commit `5b8e24206`. The proposed fix has been in the tree the entire time. | **Cut.** Already present. |
| Second trace: `cron-ux-audit.ts` → `app/api/inngest/route.ts` "Critical dependency: the request of a dependency is an expression" — same root or separate? | Neither. It appears **3×** in the same GREEN run `32414879638`. It is a warning about a dynamic `require` expression, orthogonal to the break. | **Answered: separate, and non-blocking.** Recorded, not fixed. |
| Deploy has not run since **2026-08-07**; 19 days stale; every completed run back through 08-07 is a failure | False. Eleven consecutive runs succeeded on 08-20 between 00:41Z and 20:35Z. The last fully green run is `32414879638` / `dc201e75` / **2026-08-20T20:35Z** (`release`, `migrate`, `verify-migrations`, `deploy`, `live-verify` all success). Production is **~6 days** stale, not 19. Independently corroborated by the drift alerter, which reports `prod build_sha dc201e757f63…`. | **Correct the record** (Phase 4). |
| Six consecutive failures, all one cause | Three unrelated causes were conflated. `31374522264` (`b3754369`, 08-10 — the run the issue itself cites) built the image **successfully** and died at the zot mirror: `DIGEST_INVALID: provided digest did not match uploaded content`, then `PATCH …/blobs/uploads/…: unexpected status code 500`, then `##[error]zot mirror FAILED at stage 'copy_v'`. `32293304541` (`2d3bb0e5`, 08-19) failed at `verify-migrations`. The current class began at `32418522892` (`8eb87747`, 08-20T21:16Z). | **Correct the record** (Phase 4). |
| `release / release` fails silently; decide whether it should page | It is not silent. Three independent channels fired: (a) `release-outcome` emailed on every failure — run `32860030881` logs `Release-failure email sent to ops@jikigai.com (HTTP 200) for: release=failure`; (b) `scheduled-prod-version-drift.yml` has returned `DRIFT_VERDICT=DRIFT_SUSTAINED` on every ~30–60 min run; (c) that alerter filed **#7676**, `priority/p0-critical` + `action-required`, open since 08-21 and updated through today. | **Cut.** The property is bought three times over. Building more alerting adds mechanism and no property. |
| Post-merge verification must not rely on `--commit` filtering alone | Confirmed, with a sharper cause than "the filter does not surface this workflow". `gh run list --commit 924994b2f… -L 200` returns **exactly 200** rows — it saturates the cap — and `web-platform-release` is absent from that page while the query reports `failures: 1`. | **In scope** (PR-2). |

Two further corrections to my own working assumptions, recorded because they nearly became plan premises:

- An early `gh run list --workflow web-platform-release.yml --branch main` in this session returned
  results ~5 days stale (newest row `2026-08-20`, while 08-25 and 08-26 runs existed) and
  self-corrected minutes later. A single filtered query is not a reliable enumerator in either
  direction. Not a deliverable — recorded so a future reader does not treat one green query as proof.
- The zot-mirror failure class (08-07…08-10) is **not** verified as fixed. It stopped recurring,
  which is not the same statement. Out of scope here; noted so the record does not imply otherwise.

---

## Research Insights

### Premise Validation (Phase 0.6)

- `#7395` — **OPEN**, no closing PR. Premise holds as an issue; its *body* is stale (table above).
- `#7666` (`8eb877477`, "perf(test-all): split the repo-wide parity guards out of `unit`") — merged;
  it is the commit that introduced the import. Verified via `git log -L4,4:apps/web-platform/vitest.config.ts`.
- `#7676` — **OPEN**, `priority/p0-critical` + `action-required`, the standing drift issue for this
  very outage. It is not a duplicate to be closed directly: it self-closes on the next `CLEAN` drift
  run, which is the correct post-deploy signal.
- `apps/web-platform/test/repo-wide-suites.ts` — exists, git-tracked, 84 lines, **zero imports**
  (a single `export const REPO_WIDE_SUITES: readonly string[]`). A dependency-free leaf, which is
  what makes the re-include fix safe.
- Mechanism-vs-ADR grep: `.dockerignore` / build-context appears in ADR-079, ADR-080, ADR-122,
  ADR-171. None decides the import-boundary rule; the boundary lives in the guard's own header
  comment. No rejected-alternative collision.

### Property List (Phase 0.6b)

- **P1** — A merge to `main` produces an image that builds, so `deploy` runs.
- **P2** — "A type-checked file imports a path the Docker build context excludes" cannot recur silently.
- **P3** — In-session post-merge verification cannot report healthy while an expected release workflow is red or absent.
- **P4** — The fact that production is frozen reaches a human channel.
- **P5** — The issue record is accurate.

### Cut List (Phase 0.6b)

| Mechanism the ask proposes | Property it would buy | What already buys it |
|---|---|---|
| Dynamic `await import()` / `serverExternalPackages` for the agent SDK | P1 | Nothing to buy — the ESM line is a warning present in the GREEN run `32414879638`. `serverExternalPackages` already lists the package (`next.config.ts`, since `5b8e24206`). |
| Resolve the `cron-ux-audit` critical-dependency trace | P1 | Same green-run evidence, 3 occurrences. Not release-blocking. |
| Make `release / release` page on failure | P4 | `release-outcome` job (`.github/workflows/web-platform-release.yml`) — measured `HTTP 200` email delivery on run `32860030881`. |
| Add an N-consecutive-release-failure escalation | P4 | `.github/workflows/scheduled-prod-version-drift.yml` (built by #7091 for exactly this failure mode) — `DRIFT_SUSTAINED`, plus the standing P0 `action-required` issue #7676. |
| Write a new guard for the dockerignored-import class | P2 | `apps/web-platform/scripts/lib/no-cross-context-import.test.sh` already has the chokepoint, the import extraction, the `realpath -m` resolution, and a vacuity floor. Only its **predicate** is wrong. And `plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts` already contains a fail-loud `.dockerignore` evaluator. P2 is one predicate swap plus reuse, not a new mechanism. |

Three of the issue's six scope items are cut as non-causal or already-bought, and the guard
collapses from "new guard" to "one predicate".

### Value-Proposition Measurement (Phase 0.6c)

The plan's justification is an outage, not a saving, so 0.6c does not gate it. One measurement is
still load-bearing and was taken: `gh run list --commit <merge-sha> -L 200 --json workflowName | jq length`
returns `200` on `924994b2f9666e6a57dc500db5187e08c56dc297`, and
`jq '.[]|select(.workflowName|test("elease"))'` over that page returns **empty**. The cap is
saturated and the release workflow is beyond it. That is the number PR-2 exists to fix.

### The failure class — five occurrences

| # | Date | Issue/PR | File that went missing | Mechanism |
|---|---|---|---|---|
| 1 | 2026-04-29 | #3045 / commit `1edf7a622` | `_plugin-vendored/` tree | COPY-time |
| 2 | 2026-07-02 | #5875 / PR #5890, #5894 | `scripts/sandbox-canary.mjs`, `infra/sandbox-canary-argv.json` | COPY-time |
| 3 | 2026-07-03 | #5922 / PR #5939 | 25 `infra/` host-bootstrap scripts | COPY-time |
| 4 | 2026-07-23 | #6794 / PR #6852, #6875 | repo-root `scripts/lib/frontmatter-strip/strip.ts` | import-resolution, cross-**root** |
| 5 | 2026-08-20 | #7666 → **this issue** | `apps/web-platform/test/repo-wide-suites.ts` | import-resolution, cross-**exclusion** |

Post-mortem of record for #3:
`knowledge-base/engineering/operations/post-mortems/2026-07-03-web-platform-release-dockerignore-host-scripts-postmortem.md`.
Learnings: `.../build-errors/2026-07-02-dockerfile-copy-of-dockerignored-path-breaks-release-build.md`,
`.../2026-07-23-cross-root-import-passes-local-next-build-fails-docker-context.md`,
`.../2026-03-20-dockerignore-nextjs-vs-bun-patterns.md`.

### Why the two existing guards both miss occurrence #5

- **`apps/web-platform/scripts/lib/no-cross-context-import.test.sh`** (PR #6877, built for occurrence #4).
  Its header states the invariant correctly — "the Next.js Docker build context copies only
  apps/web-platform/ … NOT repo-root scripts/" — but its predicate is:

  ```bash
  case "$resolved" in
    "$APP"/*) : ;;  # resolves within web-platform — in the Docker build context
  ```

  The trailing comment is **false** for `$APP/test/`, `$APP/scripts/`, `$APP/supabase/` and
  `$APP/infra/`, all of which `.dockerignore` strips. The guard asserts a **proxy** ("inside the app
  directory") for the **property** ("inside the build context"), and `.dockerignore` is exactly where
  the two diverge. `./test/repo-wide-suites` resolves inside `$APP`, so the guard passed.

- **`plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts`** (PR #5943, built for
  occurrences #2–#3). It models Dockerfile `COPY --from=<stage>` sources and builder-stage `RUN`
  script invocations against `.dockerignore`. A TypeScript import is neither, so it never looked.
  Its `.dockerignore` evaluator is, however, exactly the component PR-1 needs: it models literal
  directory-prefix excludes and exact `!` re-includes precisely, over-approximates globs so an
  unmodeled shape is **flagged loud rather than silently skipped**, and documents its one residual
  boundary (pattern order — Docker is last-match-wins, the model is not).

Between them these two guards cover (a) imports escaping the app directory and (b) Dockerfile COPY
of excluded paths. The uncovered third quadrant — **imports that stay inside the app directory but
land in a `.dockerignore`-excluded subtree** — is precisely where this outage lives.

### Empirical verification of the fix mechanism

Executed against `apps/web-platform` with Docker 29.4.3, using the busybox context probe established
by the #5890 hotfix:

```
printf 'FROM busybox\nCOPY <path> /x\nRUN ls -l /x\n' | docker build -q -f - -t dockerignore-probe .
```

| Path | Result | What it establishes |
|---|---|---|
| `scripts/assert-dev-signin-eliminated.sh` | **PRESENT** | A bare-directory exclude (`scripts/`) plus a file-level `!` re-include **does** survive Docker's context filter. This is the exact construction PR-1 proposes, already load-bearing in this repo's own green releases. |
| `test/repo-wide-suites.ts` | **ABSENT** | Reproduces the root cause at the context layer, independent of any CI log. |
| `next.config.ts` | PRESENT | Control — proves the probe discriminates. |

This settles the fix on measurement rather than on reading Docker's pattern semantics. It also
refutes a plausible-sounding objection drawn from this file's own `_plugin-vendored` comment
("children of an excluded dir are reachable only when the dir itself is also banged back in") —
that comment describes the `_plugin-vendored/**` construction (contents excluded), not the `test/`
construction (directory excluded), and does not generalise.

### Exposure surface today

```
git ls-files -- '*.ts' '*.tsx' | grep -v '^test/' \
  | xargs grep -ln 'from "[./]*\(test\|supabase\|scripts\|infra\)/'
→ vitest.config.ts
```

`vitest.config.ts` is the **only** tracked non-test file in `apps/web-platform` importing into a
dockerignored directory. After PR-1 the widened guard is clean at zero violations, so it ships green
rather than needing grandfathering.

### The `-L 200` saturation mechanism (input to PR-2)

`cla.yml` and `cla-evidence.yml` trigger on `pull_request_target`. Such runs carry the **base
branch's** HEAD SHA, and their job-level `if:` gates make most conclude `skipped` rather than not
existing. So every PR opened against `main` while it sat at a given commit attaches skipped runs to
**that** commit. `gh run list --commit` filters on `head_sha` and returns **newest-first**, so
accumulating CLA noise occupies the top of the page and evicts the oldest runs — which are exactly
the `push`-triggered `CI` and `web-platform-release` runs that fired at merge time.

Two consequences the plan must encode:

1. `plugins/soleur/skills/ship/SKILL.md:2045` — the empty-result fallback re-queries the total and
   treats a steady total as proof the set finished filling. At saturation that total is pinned at
   `200`, reads as "steady", and **certifies completeness**. It is fail-open, not merely unhelpful.
2. `plugins/soleur/skills/ship/SKILL.md:2040` already specifies the fix and defers it: *"The durable
   check is a SET comparison, not a count … Until that lands, never accept a `pending: 0` from a
   single query."* PR-2 implements an already-documented, already-deferred design.

Precedent for the target shape: `scripts/audit-bot-codeql-coverage.sh` — enumerates an expected set
from `.github/workflows/*.yml`, queries `gh api repos/<repo>/commits/<sha>/check-runs`, treats
**`missing` as a first-class verdict distinct from `failure`**, and carries a sanity floor that
refuses to proceed if the enumeration collapses to zero. It needs `--paginate` added if reused
(ship:1938 already documents that lesson for the sibling jobs endpoint).

Hazard PR-2 must model: `web-platform-release.yml`'s outer `on.push.paths` uses the **GitHub Actions
glob dialect**, while the inner `check_changed` gate in `reusable-release.yml` uses the **git-pathspec
dialect**. `plugins/soleur/test/web-platform-runtime-plugin-trigger.test.ts:7-12` already documents
that the two dialects are deliberately different. A naive expected-set deriver gets
`web-platform-release` wrong on `plugins/soleur/**` denylist edits.

### Detection latency, stated honestly

P3 is **not** an uncovered property. `scheduled-prod-version-drift.yml` caught this exact outage
correctly and continuously, from 08-21 onward. What PR-2 buys is **latency**: a verdict inside the
session, before the pipeline emits `DONE`, instead of a ~5h wait on the alerter's cron cadence.
That is the justification for the PR split below, and it is why PR-2 must not delay PR-1.

### Open Code-Review Overlap

Checked all five planned file paths against the 64 open `code-review` issues via
`gh issue list --label code-review --state open --json number,title,body` piped to standalone
`jq --arg path`. **None.**

---

## User-Brand Impact

**If this lands broken, the user experiences:** production continues serving the 2026-08-20 image.
Every behaviour change merged since is absent regardless of what its PR body claims — including
`#7653` ("close four fail-open gates that reported success while doing nothing"), a correctness fix
now sitting undeployed. A user who reports a bug, is told it is fixed, and still hits it is the
concrete artifact.

**If this leaks, the user's data/workflow is exposed via:** no new exposure vector — this change adds
no data path, no store, no endpoint. The standing exposure is temporal: a security or correctness fix
merged into `main` is not running in production, so the window between "merged" and "live" is
unbounded while the freeze holds. That is the exposure this plan closes.

**Brand-survival threshold:** `single-user incident`.

Justification for the threshold rather than `aggregate pattern`: one user encountering a defect the
team believes is deployed is sufficient brand damage, and the deploy-freeze applies equally to
security fixes. `requires_cpo_signoff: true` is set accordingly, and `user-impact-reviewer` runs at
review time.

---

## Implementation

The work splits across two PRs. **The split is deliberate and the rationale is load-bearing**:
production is frozen now, PR-1 is a one-line fix plus a predicate swap that can merge today, and
PR-2 is a design problem (expected-set derivation across two glob dialects, pagination, presence-vs-
truncation) that must not hold the outage fix hostage. The split is safe because P3 already has a
standing backstop outside the session — the drift alerter, which demonstrably caught this incident.

### PR-1 — Unfreeze the release, and close the guard gap (P1, P2, P5)

**Phase 1 — Restore the build context.**

`apps/web-platform/.dockerignore`: add a file-level re-include immediately after the `test/`
exclusion, with a comment naming the coupling and citing this issue, matching the convention the
`!scripts/…` and `!infra/…` blocks already use:

```
test/
# Re-include the ONE test-tree file a type-checked build file imports (#7395). `next build`
# type-checks vitest.config.ts (tsconfig include: **/*.ts), and it imports ./test/repo-wide-suites.
# Without this line the builder stage cannot resolve the module and EVERY release fails.
# Verified with the busybox context probe; the sibling !scripts/ re-include below is the same
# construction. Guarded by no-cross-context-import.test.sh.
!test/repo-wide-suites.ts
```

Ordering matters: place the `!` line **after** `test/`. The parity evaluator's one documented model
boundary is pattern order, and Docker itself is last-match-wins; putting the re-include after the
exclude is correct under both.

**Phase 2 — Widen the guard's predicate (must land in the same PR as Phase 1).**

Phase 1 alone is the fifth reactive fix for this class. Phase 2 is why this is the last one.

Change `apps/web-platform/scripts/lib/no-cross-context-import.test.sh`'s membership test from
"resolves inside `apps/web-platform/`" to "**resolves to a path present in the Docker build
context**". The widened predicate strictly subsumes the old one — a repo-root path is outside the app
*and* outside the context — so no coverage is lost and the #6852 regression stays guarded.

The `.dockerignore` evaluation must **not** be reimplemented in bash. Reuse the evaluator in
`plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts`, which already has the required
fail-loud semantics. Two viable shapes; pick at `/work` time on the smaller diff:

- **2a (preferred)** — extract the evaluator to a shared module and add a second `describe` block to
  the parity test that enumerates context-present, type-checked app files and resolves their relative
  imports. The bash guard then either delegates or is retired as subsumed. One evaluator, one
  language, no drift surface.
- **2b** — keep the bash guard and have it shell out to a small node/bun entrypoint exposing the same
  evaluator. Avoids touching the parity suite; adds a process boundary.

Do **not** duplicate the matcher. Two `.dockerignore` models that can disagree is the failure this
guard exists to prevent, re-created one layer up.

The guard must retain the existing vacuity floor (`checked -eq 0` → FAIL) and gain one for the
context-membership side, per the Guard Contract below.

**Phase 3 — Verify the fix against the real build.** See Acceptance Criteria (post-merge).

**Phase 4 — Correct the record (P5).** Comment on #7395 with the Research Reconciliation table:
the real cause, the corrected 08-20 start date, the three conflated failure classes, and the
already-bought alerting. `Closes #7395` goes in the PR body. Leave #7676 alone — it self-closes on
the next `CLEAN` drift run, which is the honest post-deploy signal.

### PR-2 — Presence-aware post-merge verification (P3)

Tracked separately; the follow-up issue is filed during PR-1 so the deferral is visible, carrying the
measured saturation evidence and the dialect hazard from Research Insights.

1. `plugins/soleur/skills/ship/SKILL.md:2016-2060` (Phase 7 Step 2) — replace the count-with-cap with
   an expected-set presence assertion, implementing the design already written at `:2040`. Model on
   `scripts/audit-bot-codeql-coverage.sh`; add `--paginate`; make `missing` a verdict distinct from
   `failure`; keep a sanity floor so a collapsed enumeration cannot read as all-clear.
2. `plugins/soleur/skills/ship/SKILL.md:2045` — delete the "steady total" heuristic outright. At
   saturation it certifies completeness; a bigger `-L` does not fix it.
3. `plugins/soleur/skills/ship/SKILL.md:1934` — same cap on the PR-head query.
4. `plugins/soleur/skills/postmerge/SKILL.md:49` (Phase 2, `--limit 3` on `--branch main`, degrading
   to warn-and-proceed) and the Phase 7 report template, which currently prints `CI on main: PASSED`
   with **no release/deploy line at all** — so the artifact of a green postmerge run cannot express
   "the release workflow was red". Add that line.
5. Add the regression test. Nothing under `plugins/soleur/test/` or `tests/` asserts the Phase 7
   query shape today, so without one the fix ships unguarded.

---

## Guard Contract

### Guard 1 — Docker-build-context import closure

**Property.** Every relative import in a file that is both **present in the Docker build context**
and **type-checked by `next build`** resolves to a path that is also present in the Docker build
context.

**Assembly.** Three chokepoints, named structurally rather than by their current members:

1. **Context membership** — `apps/web-platform/.dockerignore` is the single authority. Evaluated by
   the shared evaluator from `dockerfile-copy-dockerignore-parity.test.ts`, never by a second model.
2. **The type-checked set** — the `include`/`exclude` globs in `apps/web-platform/tsconfig.json`
   (`include: ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"]`, `exclude: ["node_modules"]`),
   intersected with chokepoint 1. Files stripped from the context are not type-checked inside the
   image and are correctly out of scope; the guard must derive this intersection, not hardcode
   "everything except `test/`".
3. **Import extraction** — every relative specifier (`from`, `import(`, `require(`) in that set,
   resolved with `realpath -m` against the importing file's directory.

The Dockerfile `COPY`/`RUN` chokepoint is already covered by the sibling `describe` block in the
same suite; this guard is the import-side quadrant, and the two together span the class.

Members drift — `vitest.config.ts` is today's only importer and `test/` is today's only excluded
target — so neither is part of the assembly. The chokepoints are.

**Mutation matrix.** Every row must drive the guard RED. Derived from the design, written before the
guard.

| # | Mutation | Why it must redden |
|---|---|---|
| 1 | Add `import { X } from "./test/other-helper"` to `vitest.config.ts` (post-fix) | Reproduces the actual incident. A guard that passes here is the current guard. |
| 2 | Add the same import to a **second** type-checked file (`playwright.config.ts`) while `vitest.config.ts` stays compliant | Second-member row — catches a guard that stops at the first violation or the first file. |
| 3 | Delete the `!test/repo-wide-suites.ts` re-include from `.dockerignore` | The other side of the coupling. Catches a guard that reads imports but never actually consults `.dockerignore`. |
| 4 | Point the type-checked-file enumeration at a nonexistent glob so it returns zero files | **Own-dispatch / vacuity row.** A guard reporting "0 checked" and exiting 0 asserts nothing. The existing bash guard already has this floor; the widened guard must keep it *and* add one for the context-membership side. |
| 5 | Add a `.dockerignore` pattern shape the evaluator does not model (e.g. a bracketed or negated-glob form) | Must fail **loud**, not silently skip — the semantics the parity evaluator already documents, and the discipline of `.../best-practices/2026-07-03-parity-guard-unmodeled-input-must-fail-loud-not-skip.md`. |
| 6 | Add `COPY --from=builder /app/test/repo-wide-suites.ts ./` to the Dockerfile with the re-include removed | Confirms the COPY-side quadrant still reddens after the refactor — the extraction must not regress the existing parity assertions. |

**Harness rows.** Mutating only the system under test cannot see a vacuous harness.

| # | Mutation / input | Expected |
|---|---|---|
| H1 | Stub the violation collector to always return an empty list | Suite **RED** (a guard that reports nothing must not read as pass) |
| H2 | Stub the context evaluator to report every path as present | Suite **RED** |
| H3 | **Must-PASS, non-canonical:** a type-checked file importing from a **non-excluded** directory (`./lib/…`, `./server/…`) | **PASS** — proves the guard is not simply rejecting everything |
| H4 | **Must-PASS, non-canonical:** a file under `test/` importing another file under `test/` | **PASS** — `test/` files are absent from the context and therefore not type-checked in the image; flagging them would be a false positive that forces grandfathering |

H3 and H4 are the rows that distinguish a working guard from one that fails closed on everything —
the failure mode a RED-only battery cannot detect.

---

## Observability

```yaml
liveness_signal:
  what: "web-platform-release.yml `deploy` job reaches `success`, and prod /health build_sha advances"
  cadence: "per merge to main touching the release path filter"
  alert_target: "ops@jikigai.com (release-outcome email) + issue label ci/prod-version-drift"
  configured_in: ".github/workflows/web-platform-release.yml (release-outcome job); .github/workflows/scheduled-prod-version-drift.yml"

error_reporting:
  destination: "GitHub Actions job failure -> release-outcome classifier -> Resend email; drift alerter -> P0 action-required issue"
  fail_loud: true

failure_modes:
  - mode: "A type-checked file imports a dockerignored path (this outage, class occurrence #5)"
    detection: "no-cross-context-import guard, widened predicate — pre-merge, scripts shard"
    alert_route: "red required check on the PR; never reaches main"
  - mode: "Dockerfile COPY/RUN of a dockerignored path (occurrences #1-#3)"
    detection: "dockerfile-copy-dockerignore-parity.test.ts — pre-merge"
    alert_route: "red required check on the PR"
  - mode: "Release build fails for any other reason and deploy is skipped"
    detection: "release-outcome classifier (needs: every job, if: always())"
    alert_route: "email to ops@jikigai.com — measured HTTP 200 on run 32860030881"
  - mode: "Prod serves a stale build for any reason, including a silently skipped deploy"
    detection: "scheduled-prod-version-drift.yml compares live /health build_sha against origin/main over the release path filter"
    alert_route: "P0 action-required issue labelled ci/prod-version-drift (currently #7676); self-closes on CLEAN"
  - mode: "In-session post-merge verification reports healthy while the release run is red or absent"
    detection: "NOT COVERED IN-SESSION — deferred to PR-2. Backstopped by the drift alerter on its cron cadence, ~5h latency."
    alert_route: "drift alerter only, until PR-2 lands"

logs:
  where: "GitHub Actions run logs; the drift alerter's step summary and issue body"
  retention: "GitHub default (90 days for run logs)"

discoverability_test:
  command: "bash apps/web-platform/scripts/lib/no-cross-context-import.test.sh"
  expected_output: "OK: <N> relative import(s) scanned; none resolve outside the Docker build context"
  # No credentials required; runs locally, no ssh, no network.
```

A second, deeper probe verifies context membership directly, using the technique from the #5890
hotfix (first token `printf`, no ssh, no credentials):

```
printf 'FROM busybox\nCOPY test/repo-wide-suites.ts /x\nRUN ls -l /x\n' \
  | docker build -q -f - -t dockerignore-probe apps/web-platform
```

Expected post-fix: exit 0. Pre-fix it exits non-zero with `not found` — which is how the root cause
was confirmed for this plan.

---

## Architecture Decision (ADR/C4)

### ADR

**PR-1: none.** The invariant it enforces — "an import from a build-time-type-checked file must
resolve inside the Docker build context" — is not a new decision. It is the invariant PR #6877
already recorded in `no-cross-context-import.test.sh`'s header; PR-1 corrects that guard's predicate
to match the invariant its own comment states. Writing an ADR for a bug fix that makes a guard honest
would be ADR inflation.

**PR-2: an ADR is required.** "Post-merge verification asserts the **presence of an expected workflow
set**, not the **absence of failures** in a truncatable page" is a genuine architectural decision
about how the pipeline establishes merge health, it reverses the current count-based contract, and
`ship/SKILL.md:2040` has been carrying it as an undecided deferral. Author it in PR-2, not here.
The ordinal is chosen at PR-2 time and re-verified against freshly-fetched `origin/main` immediately
before merge — this repo collided ADR ordinals twice in one session on #7418.

### C4 views

**No C4 impact**, and here is what was checked rather than an unsupported "None". All three model
files were read (`model.c4` 691 lines, `views.c4` 74, `spec.c4` 54), and the change was enumerated
against each of the four categories the completeness mandate requires:

- **External human actors** — none added or changed. No new correspondent, reviewer, or recipient;
  no role's relationship to the release pipeline moves.
- **External systems / vendors** — none added. `github` (modelled at `model.c4:234` as source control
  and CI/CD), `ghcr` (`:280`), `projectZot` (`:284`) and `zotRegistry` (`:288`) are all already
  modelled, and this change adds no edge to any of them. No new webhook, API, or third-party store.
- **Containers / data stores** — none. `.dockerignore` governs what enters an existing build context;
  it creates no store and changes no volume, registry, or database.
- **Actor↔surface access relationships** — none. No ownership, sharing, or permission boundary moves.

PR-2 edits skill markdown and a verification query — also no C4 surface. If PR-2's expected-set
deriver ends up reading `.github/workflows/*.yml` as a new authority, re-run this enumeration then;
it does not change the answer for PR-1.

---

## Acceptance Criteria

### Pre-merge (PR-1)

- **AC1** — `apps/web-platform/.dockerignore` contains `!test/repo-wide-suites.ts` positioned after
  the `test/` exclusion, with a comment citing #7395.
  `awk '/^test\/$/{f=1} f&&/^!test\/repo-wide-suites\.ts$/{print "OK";exit}' apps/web-platform/.dockerignore`
  prints `OK`.
- **AC2** — The busybox context probe returns exit 0 for `test/repo-wide-suites.ts`:
  `printf 'FROM busybox\nCOPY test/repo-wide-suites.ts /x\nRUN ls -l /x\n' | docker build -q -f - -t dockerignore-probe apps/web-platform`.
  This is the authoritative context-membership check; a `.dockerignore` grep alone is not.
- **AC3** — The widened guard passes clean on the real repo with a non-zero scan count:
  `bash apps/web-platform/scripts/lib/no-cross-context-import.test.sh` exits 0 and reports
  `N > 0` imports scanned.
- **AC4** — Every mutation-matrix row 1–6 drives the guard RED, and every harness row H1–H4 behaves
  as specified. Record the observed output per row in the PR body. Rows H3 and H4 must **PASS**;
  a matrix where every row reddens has not demonstrated the guard discriminates.
- **AC5** — The widened predicate subsumes the old one: re-introducing the #6852 shape (a production
  file importing repo-root `scripts/lib/…`) still reddens. Verifies no coverage was traded away.
- **AC6** — The `.dockerignore` evaluator exists in exactly one place; no second implementation is
  introduced, and the parity suite's existing assertions still pass.
- **AC7** — Full battery green: `bash scripts/test-all.sh` (or the shards the diff touches plus the
  `scripts` and `bun` shards, since the guard and the parity suite live in different shards — the
  parity test is an orphan suite relative to a diff that touches only `.dockerignore`, so it must be
  invoked explicitly).
- **AC8** — PR body carries `Closes #7395` and a link to this plan.

### Post-merge (automated)

- **AC9** — The release run for the merge commit reaches `release: success` **and** `deploy: success`
  — not skipped. Verified by workflow name, never by `--commit`:
  `gh run list --workflow web-platform-release.yml --branch main --limit 3 --json headSha,conclusion`
  then `gh run view <id> --json jobs --jq '.jobs[]|"\(.conclusion) \(.name)"'`.
- **AC10** — **The deployed bytes actually changed.** A green run is not proof.
  `curl -fsS https://app.soleur.ai/health | jq -r .build_sha` returns the new merge SHA and **not**
  `dc201e757f63faa2001b4cf3e4ae4d8e6748bb38`. This is the criterion the issue explicitly asked for,
  and it is what distinguishes "the pipeline went green" from "production is serving it".
- **AC11** — The image digest advanced. Capture the digest published by the release run and assert it
  differs from the digest previously served, rather than inferring it from the tag.
- **AC12** — `scheduled-prod-version-drift.yml` reports `DRIFT_VERDICT=CLEAN` on its next run, and
  **#7676 closes itself**. `gh issue view 7676 --json state` returns `CLOSED`. Closing it directly
  would assert the very outcome the alerter exists to measure.
- **AC13** — #7395 carries the correction comment (real cause, corrected 08-20 date, three conflated
  classes) and is closed by the PR.
- **AC14** — The PR-2 follow-up issue exists, labelled, and carries the measured `-L 200` saturation
  evidence plus the two-glob-dialect hazard.

---

## Test Scenarios

Framework check: `apps/web-platform` runs **vitest** (`scripts.test = vitest`), not bun test;
`plugins/soleur/test/*.test.ts` runs under **bun:test**; `apps/web-platform/scripts/lib/*.test.sh`
runs as bash in the **scripts** shard. Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
— never `npm run -w`, which aborts because the repo root declares no `workspaces` field.

| # | Scenario | Expected |
|---|---|---|
| T1 | Busybox probe on `test/repo-wide-suites.ts`, pre-fix | non-zero, `not found` |
| T2 | Same probe, post-fix | exit 0 |
| T3 | Same probe on `scripts/assert-dev-signin-eliminated.sh` (control) | exit 0 both before and after |
| T4 | Widened guard on clean repo | exit 0, `N > 0` scanned |
| T5–T10 | Mutation matrix rows 1–6 | RED each |
| T11–T14 | Harness rows H1–H4 | H1/H2 RED, H3/H4 PASS |
| T15 | `tsc --noEmit` in `apps/web-platform` | 0 errors (the guard change must not alter type-checked scope locally) |
| T16 | Parity suite's pre-existing assertions after the evaluator extraction | unchanged, green |

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The `!` re-include does not survive Docker's filter in the release environment | Already measured (busybox probe, PRESENT for the identical `scripts/` construction), and AC2 re-runs it. The `!scripts/assert-dev-signin-eliminated.sh` line is load-bearing in every green release this repo has shipped, so the construction is proven in production, not only locally. |
| Extracting the evaluator regresses the parity suite | AC6 + T16 assert the existing assertions still pass. Prefer shape 2b if the extraction diff grows. |
| The widened guard produces false positives requiring grandfathering | Measured: `vitest.config.ts` is the only importer into a dockerignored directory, so post-fix the guard is clean at zero. Harness row H4 pins the `test/`-imports-`test/` case as must-PASS so it cannot drift into a false positive. |
| The guard lives in a shard the touched-file set does not reach | Explicitly called out in AC7. Since #7352 `/work` Phase 2 runs only touched shards, and a diff touching only `.dockerignore` reaches neither the scripts shard nor the bun shard. Both must be invoked explicitly. |
| PR-1 merges and the release fails for a *different* reason | AC9–AC11 assert deploy and digest, not just a green conclusion. The zot-mirror class from 08-07…08-10 is unverified-as-fixed and is the most likely such reason; if it recurs, that is a separate issue, not a PR-1 regression. |
| Splitting PR-2 out leaves P3 uncovered | It does not leave it uncovered — the drift alerter covers it on a cron cadence at ~5h latency, and demonstrably caught this incident. Stated in Research Insights so the deferral is an evidenced decision, not a punt. |

---

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Move `REPO_WIDE_SUITES` out of `test/` into `lib/` or a new top-level dir | Semantically wrong — it is test infrastructure — and it would ship into the runtime image. It also fixes only this instance, leaving the class open. The re-include is smaller and the guard is what actually closes the class. |
| Add `vitest.config.ts` to `tsconfig.json`'s `exclude` | Silently drops a real config file from `tsc --noEmit` coverage everywhere, and fixes only this instance. The next config file importing from `test/` breaks the release again. |
| Set `typescript.ignoreBuildErrors` in `next.config.ts` | Disables type-checking for the entire production build to route around one missing file. Trades a loud release failure for a silent class of shipped type errors. |
| Remove the `test/` exclusion from `.dockerignore` | Ships the whole test tree into the build context, growing it for no benefit, and abandons the size discipline the file is built around. |
| Reimplement `.dockerignore` matching in the bash guard | Creates a second model that can disagree with the parity suite's. Two disagreeing models of the same authority is the failure mode the guard exists to prevent. |
| Build an N-consecutive-release-failure pager | Cut at Phase 0.6b. P4 is already bought three times (email, drift alerter, standing P0 issue #7676) and all three fired here. The gap was response, not detection. |
| Fold PR-2 into PR-1 | Production is frozen now. PR-2 needs expected-set derivation across two deliberately different glob dialects plus pagination — days of design against a one-line outage fix. |

---

## Domain Review

**Domains relevant:** engineering

Lane defaulted to `cross-domain` (fail-closed): no `spec.md` exists for this branch, so no `lane:`
could be carried forward.

### Engineering

**Status:** reviewed
**Assessment:** CI/release-pipeline bug fix plus a pre-merge guard widening. The architecturally
interesting finding is that the existing guard asserted a proxy ("inside `apps/web-platform/`") for
its stated property ("inside the Docker build context"), and its own inline comment asserts the
proxy *is* the property — the two diverge exactly at `.dockerignore`. The correct fix is a predicate
change reusing the `.dockerignore` evaluator that already exists in the sibling parity suite, not a
third guard. No new infrastructure, no new dependency, no schema change, no data path.

### Product/UX Gate

Not applicable — no file in `## Files to Edit` matches the UI-surface term list or glob superset.
`.dockerignore`, a bash guard, a bun test, and skill markdown create no user-facing surface.
**Tier:** none.

---

## Files to Edit

**PR-1**
- `apps/web-platform/.dockerignore` — add `!test/repo-wide-suites.ts` after `test/`
- `apps/web-platform/scripts/lib/no-cross-context-import.test.sh` — widen the membership predicate
- `plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts` — extract/expose the evaluator; add the import-quadrant `describe`

**PR-2** (separate PR, tracked by a follow-up issue filed during PR-1)
- `plugins/soleur/skills/ship/SKILL.md` — lines ~1934, ~2016-2060, ~2045
- `plugins/soleur/skills/postmerge/SKILL.md` — line ~49 and the Phase 7 report template
- new regression test under `plugins/soleur/test/`
- new ADR (ordinal chosen and re-verified at PR-2 merge time)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-7395-release-esm-build-failure/tasks.md`
- Possibly a shared evaluator module, if shape 2a is chosen at `/work` time
