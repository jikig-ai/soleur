---
issue: 5796
type: fix
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix: `test-webplat` shard `vi.waitFor` 1s-default flake silently gates prod deploys (#5796)

## Overview

The `apps/web-platform` vitest component suite intermittently goes red on async-wait
**timeouts under CPU contention** — not assertion logic, not a code regression. Because
`web-platform-release.yml`'s `await-ci` job fail-closes the `deploy` + `live-verify` jobs
on a non-`success` CI `test` aggregator, a single flaky shard **silently blocks the
production deploy of every PR**.

Investigation shows the flake is **two distinct mechanisms**, and the existing fixes
(#4128: `testTimeout` 5s→16s; #5113: RTL `asyncUtilTimeout` 1s→10s) closed only part of it:

1. **`vi.waitFor` 1s-default gap (the proven CI-red culprit).** #5113 raised the
   *React Testing Library* async-util ceiling via `configure({ asyncUtilTimeout: 10_000 })`
   in `apps/web-platform/test/setup-dom.ts`. It did **not** touch vitest's own
   `vi.waitFor`, which has **no global config knob** and still defaults to **1000ms**.
   `vi.waitFor` is used in **47 sites across 9 files**, of which only **5 sites in one
   file** (`live-repo-badge.test.tsx`, hardened piecemeal by #5113/#5234) carry an explicit
   `{ timeout: 10_000 }`. The remaining ~42 sites are at the 1s default. The merge-commit CI
   failure (`live-repo-badge.test.tsx:192`, `vi.waitFor.timeout AssertionError`, shard
   wall-clock 114941ms) is exactly this class. Raising `vi.waitFor`'s floor is **not** a
   timeout treadmill — this flavor was *never* raised; it is an uncovered gap left by #5113.

2. **Render-under-contention timeout (no waitFor at all).** Two of the locally-observed
   failing files use **zero** `vi.waitFor`/`waitFor`/`findBy`:
   `dashboard-layout-sidebar-settings.test.tsx` and `chat-surface-sidebar-wrap.test.tsx`.
   Both do a **heavy dynamic `import()`** inside the render helper
   (`await import("@/app/(dashboard)/layout")` / `await import("@/components/chat/chat-surface")`)
   then render a large module graph (ThemeProvider + supabase mocks; markdown renderer +
   syntax highlighter). Under `scripts/test-all.sh`'s **unsharded** full-suite run, the
   `pool: 'forks'` + `isolate: true` config spawns one heavy process per file competing for
   CPU; the import+render of a single `it()` exceeds the 16s `testTimeout` (observed
   ~20s-shaped) with no async-wait util in the stack. Raising timeouts cannot fix this — the
   lever is **reducing per-runner worker contention**.

**Strategy:** close the `vi.waitFor` floor systematically (Phase 1, high-confidence, fixes
the CI-deploy-gating flake and the issue's re-eval criterion), then reduce component-project
worker contention behind a measurement gate (Phase 2, addresses the local full-suite
render-contention sub-class; descopable if Phase 1 alone stabilizes the suite). **Do not
touch the already-correct RTL `asyncUtilTimeout: 10_000` or `testTimeout: 16_000`.**

## Premise Validation

- **Issue #5796** — `gh issue view 5796`: OPEN, labels `type/chore` + `deferred-scope-out`.
  Premise holds; not already resolved.
- **`vi.waitFor` 47 sites / 9 files** — verified via `grep -rln "vi\.waitFor"` +
  per-file counts (see Root Cause). Confirmed.
- **#5113 RTL fix present** — `setup-dom.ts:11` `configure({ asyncUtilTimeout: 10_000 })`
  and its guard `setup-dom-leak-guard.test.ts:27`. Confirmed present; this plan does NOT
  duplicate or alter it.
- **`live-repo-badge.test.tsx:192`** is a `vi.waitFor(() => expect(queryByTestId(...))
  .toBeNull(), { timeout: 10_000 })` — already hardened piecemeal; the file still has 2
  bare `vi.waitFor` sites. Confirms piecemeal patching is the recurrence vector.
- **Deploy-gating chain** — `web-platform-release.yml`: `await-ci` (waits for CI `test`
  check-run, fail-closed) → `deploy` `needs:[...,await-ci]` with
  `needs.await-ci.result == 'success'`; `live-verify` `needs:[deploy]`. Confirmed: a flaky
  `test` skips deploy + live-verify for the affected SHA.
- **No external premises** beyond the above; vitest `^4.1.0` (`apps/web-platform/package.json`).

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (one-shot path). Issue body claims reconciled against
codebase:

| Issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| "`vi.waitFor`/`waitFor` calls exceed their 1s default" | RTL `waitFor` is already 10s (#5113); only `vi.waitFor` is still 1s | Phase 1 targets `vi.waitFor` specifically; leaves RTL config untouched |
| Direction (a): "raise the RTL/vitest async timeout floor (`testTimeout`/`asyncUtilTimeout`)" | `testTimeout`=16s and `asyncUtilTimeout`=10s already raised | Re-scoped to the **uncovered** `vi.waitFor` floor — the only un-raised knob |
| 3 named local files "all ~20s timeout-shaped" | `cc-routing-panel…` uses RTL waitFor (covered by 10s); `dashboard-layout…` + `chat-surface-sidebar-wrap…` use **no** waitFor (render-contention) | Split into Phase 1 (waitFor) + Phase 2 (contention) |
| Direction (b): "split into more shards / smaller worker pools" | CI already 2-way sharded (`ci.yml` `shard: ["1/2","2/2"]`); no `poolOptions` cap exists | Phase 2 caps `poolOptions.forks.maxForks` (config, no new CI jobs/cost) rather than adding shards |

## Institutional Learnings (applied)

- **`knowledge-base/project/learnings/test-failures/2026-06-10-parallel-load-flake-two-mechanisms-and-vacuous-absence-waits.md`** —
  the canonical learning for this exact class: vitest has **two independent** timeout
  mechanisms (`vi.waitFor` default 1000ms vs RTL `asyncUtilTimeout` 1000ms); `vi.waitFor`
  does **not** read RTL's `configure()`. A global RTL bump alone leaves the 47 `vi.waitFor`
  sites at 1s. Timeout hierarchy is load-bearing: per-hook (20s) > `testTimeout` (16s) >
  intra-wait ceiling (10s) — the 10s < 16s nesting lets the wait throw its own diagnostic
  before the generic test timeout, preserving error attribution. **This learning establishes
  the team convention: explicit `{ timeout: 10_000 }` per `vi.waitFor` site** (Approach D).
- **`…/test-failures/2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md`** —
  cleanup/config must live at **file boundaries / top-level module load**, never in a
  `beforeAll`/`beforeEach` that overwrites globals. **Constraint:** the Phase-1 wrapper
  (Approach A) must be installed at setup-file top-level (exactly where `configure({...})`
  sits), not in a hook.
- **`…/test-failures/2026-05-15-kb-chat-sidebar-chat-page-flake-recurrence.md`** —
  full-suite forked-worker CPU contention is the render-timeout mechanism for the
  no-waitFor files; `isolate: true` closes the *aliasing* vector but not the *contention*
  vector. (The config already defaults to `pool: 'forks'` per #3817 — Phase 2 caps the
  fork **count**, it does not flip the pool.)
- **`…/test-failures/2026-06-18-render-null-state-transition-proof-via-fetch-call-count.md`**
  + **`…/2026-05-20-happy-dom-ws-fetch-blockade.md`** — reinforce the positive-settle-anchor
  pattern (direction (c)) for `live-repo-badge`-style absence waits and explain why an
  unmocked path surfaces only after the full `testTimeout`.

## Root Cause Analysis

### `vi.waitFor` distribution (verified)

| File | project | `vi.waitFor` sites | with explicit `{ timeout }` |
| --- | --- | --- | --- |
| `cc-dispatcher.test.ts` | **node** | 15 | 0 |
| `org-switcher-container.test.tsx` | component | 7 | 0 |
| `live-repo-badge.test.tsx` | component | 7 | 5 |
| `use-active-repo-poll.test.tsx` | component | 6 | 0 |
| `invite-member-modal.test.tsx` | component | 3 | 0 |
| `debug-stream-panel.test.tsx` | component | 3 | 0 |
| `server/templates/is-template-authorized.test.ts` | **node** | 3 | 0 |
| `transfer-ownership-dialog.test.tsx` | component | 2 | 0 |
| `invite-actions-gating.test.tsx` | component | 1 | 0 |

**Load-bearing:** `vi.waitFor` is used in **both** the `node` and `component` vitest
projects (`cc-dispatcher.test.ts` + `is-template-authorized.test.ts` are `.test.ts` → node;
the 7 `.test.tsx` are component). A setup-file fix must therefore land in **both**
`test/setup-node.ts` and `test/setup-dom.ts`.

### Render-under-contention (no waitFor)

`dashboard-layout-sidebar-settings.test.tsx` and `chat-surface-sidebar-wrap.test.tsx` have
zero async-wait utils; each `it()` awaits a dynamic `import()` of a heavy component module
then renders it. Under `pool: 'forks'` + `isolate: true` + unsharded full-suite, the
per-`it()` wall-clock exceeds `testTimeout: 16_000` on a CPU-starved worker. The diminishing
returns of raising `testTimeout` again (already 16s; failures are ~20s-shaped and would need
30s+) make **contention reduction** the correct lever.

## Implementation Phases

### Phase 0 — Approach spike (decides Phase 1 shape)

`vi.waitFor` has **no** vitest config knob, so the floor must be raised either by (A) a
global wrapper installed in the setup files, or (D) a per-site `{ timeout }` sweep. **The
established team convention (per the 2026-06-10 learning + #5113/#5234) is Approach D —
explicit `{ timeout: 10_000 }` per site.** Approach A is a novel single-knob alternative
that is *recurrence-proof* (every future `vi.waitFor`, not just existing ones, inherits the
floor — directly countering the learning's warning that "every new `vi.waitFor` re-arms the
flake"), at the cost of monkeypatching the `vi` singleton. Phase 0 runs a ~15-minute spike
to settle the tradeoff (final A-vs-D call confirmed at deepen-plan / plan-review):

1. In a scratch `setup` file, verify that reassigning `vi.waitFor` to a wrapper is
   (a) permitted at runtime in vitest `4.1.0` (the `vi` singleton property is writable,
   not frozen), and (b) **visible to test files** that `import { vi } from "vitest"`
   (same module-singleton object within a worker). Confirm the type shape:
   `setup-node/dom` would do
   ```ts
   const _waitFor = vi.waitFor.bind(vi);
   vi.waitFor = ((cb, options) => {
     const opts = typeof options === "number"
       ? { timeout: options }
       : { timeout: 10_000, ...options };
     return _waitFor(cb, opts);
   }) as typeof vi.waitFor;
   ```
   This is **non-destructive**: explicit per-site timeouts (incl. the 5 existing sites in
   `live-repo-badge.test.tsx` and any future `{ timeout: N }`) win because they spread over
   the injected default.
2. Confirm the wrapper does NOT break `vi.useFakeTimers()` + `vi.waitFor` interaction
   (the wrapper only changes the *default* timeout; it does not alter polling/timer
   behavior). Grep for files combining fake timers with `vi.waitFor` and smoke-run one.

**Decision rule:** if reassignment is frozen/not visible → **Approach D** (the established
convention: per-site `{ timeout: 10_000 }` sweep across the 42 bare sites + a source-grep
guard that rejects bare `vi.waitFor(`). If (1a)+(1b) hold, **Approach A** is viable and
preferred for recurrence-proofing — adopt it only if deepen-plan / plan-review accept the
novel single-knob over the established per-site convention; otherwise default to D. Either
way the wrapper/sweep must be installed at **setup-file top-level module load** (exactly
where `configure({ asyncUtilTimeout })` sits), never in a `beforeAll`/`beforeEach`
(`2026-04-22-vitest-cross-file-leaks` constraint). Record the decision + spike evidence in
the PR body.

### Phase 1 — Raise the `vi.waitFor` floor systematically (core)

**Approach A (preferred):**
- Add the wrapper block (above) to **both** `apps/web-platform/test/setup-dom.ts` and
  `apps/web-platform/test/setup-node.ts`, with a `// #5796 — vi.waitFor 1s-default floor;
  mirrors the #5113 asyncUtilTimeout fix for RTL. vi.waitFor has no global config knob.`
  comment.
- Extend the drift guard `setup-dom-leak-guard.test.ts` (and add a sibling assertion for
  `setup-node.ts`) with a source-token row asserting the wrapper is present, mirroring the
  existing `["asyncUtilTimeout config", "asyncUtilTimeout: 10_000"]` row.

**Approach D (fallback):**
- Sweep `{ timeout: 10_000 }` onto the 42 bare `vi.waitFor` sites (do NOT alter the 5
  already-explicit sites). Add a guard test that greps all `apps/web-platform/test/**/*.test.{ts,tsx}`
  and fails if any `vi.waitFor(` lacks a timeout option (regex over the call + next 3 lines).

**Optional micro-hardening (direction (c), only where cheap during the sweep):** for any
bare `vi.waitFor(() => expect(queryBy…).toBeNull())` *absence-wait* encountered, add a
positive settle anchor first (`await screen.findBy…(...)` for the pre-state) per the
`live-repo-badge.test.tsx:188` pattern (vacuous-absence-wait class, #5234). This is not a
separate deliverable; do it inline only where a bare absence-wait is touched.

> **APPLIED (direction (c) — root-caused, not just hardened).** During verification the
> `live-repo-badge.test.tsx` J5 dismiss-wait flaked ~10% even with explicit 10s timeouts
> (so the floor-raise could not fix it). Traced to a **component** race, not a timeout:
> `LiveRepoBadge`'s re-arm effect fired `setDismissed(false)` on the initial mount
> (`undefined→true`), and React running that passive effect *after* the dismiss click
> undid the dismissal. Fixed at the component (`components/dashboard/live-repo-badge.tsx`):
> gate the re-arm on a genuine `false→true` transition via a `prevValue` ref (behavior-
> preserving — the mount reset was a no-op on already-false `dismissed`). Also de-fragiled
> the J5 test: phase-driven mutable response (read at `.json()` time) instead of an
> order-fragile `mockResolvedValueOnce` queue, and delta-based call-count gates. Result:
> 25/25 deterministic (was ~10% red), full file green ×6. This expands the PR scope to one
> production component file — covered by the existing (now deterministic) J5 test.

### Phase 2 — Reduce component-project worker contention (evidence-gated, descopable)

> **DECISION (applied): DESCOPED.** Phase 0 spike confirmed Approach A is viable in
> vitest 4.1.0 (writable `vi.waitFor` singleton, setup-file patch visible to test
> files, fake-timers interaction preserved). With Phase 1 (Approach A) applied, the
> full **unsharded** `TEST_GROUP=webplat` suite ran green **×3 consecutive**
> (906 files / 11225 tests, 0 failed; ~207s / ~235s / ~248s) with **no
> `vi.waitFor.timeout` and no >16s render timeout** on the previously-flaky
> no-waitFor files (`dashboard-layout-sidebar-settings`, `chat-surface-sidebar-wrap`,
> `cc-routing-panel-concierge`). Per the descope criterion below, Phase 1 alone
> stabilizes the suite, so the `maxForks` cap is NOT applied (no `vitest.config.ts`
> change). Re-open Phase 2 only if a future full-suite run reintroduces a >16s
> render timeout on a no-waitFor file.

1. **Measure first.** Run `TEST_GROUP=webplat bash scripts/test-all.sh` (unsharded, with
   Phase 1 applied) and capture per-file timing via `TEST_TIMING_LOG`. Confirm the
   no-waitFor files (`dashboard-layout-sidebar-settings`, `chat-surface-sidebar-wrap`) still
   exhibit >16s render timeouts under load. **If Phase 1 alone stabilizes the suite (no
   >16s render timeouts across 3 consecutive full runs), descope Phase 2** and record the
   descope in the PR body.
2. **If contention confirmed:** add a `poolOptions.forks.maxForks` cap to the **component**
   project in `vitest.config.ts` (verify the exact key against vitest `4.1.0` config types
   at work time). Choose a conservative cap that bounds concurrent heavy processes on a
   4-core CI runner (e.g. `maxForks: Math.max(2, Math.floor(os.cpus().length / 2))`),
   documented inline with the same "acceptable for a reliable suite" tradeoff language as
   the existing `isolate`/`forks` comments. Re-measure: confirm the render-timeouts clear
   and record the wall-clock delta (cap trades wall-clock for reliability).
3. Do **not** add CI shards (extra GH jobs = cost); the config cap covers both the local
   unsharded run and each CI shard runner.

## Files to Edit

- `apps/web-platform/test/setup-dom.ts` — Approach A: add `vi.waitFor` wrapper (component project).
- `apps/web-platform/test/setup-node.ts` — Approach A: add `vi.waitFor` wrapper (node project).
- `apps/web-platform/test/setup-dom-leak-guard.test.ts` — add drift-guard row(s) for the wrapper.
- `apps/web-platform/vitest.config.ts` — Phase 2 only: `poolOptions.forks.maxForks` cap on the component project (if contention confirmed).
- **Approach D fallback only** — the 8 files with bare `vi.waitFor` sites:
  `cc-dispatcher.test.ts`, `org-switcher-container.test.tsx`, `use-active-repo-poll.test.tsx`,
  `invite-member-modal.test.tsx`, `debug-stream-panel.test.tsx`,
  `server/templates/is-template-authorized.test.ts`, `transfer-ownership-dialog.test.tsx`,
  `invite-actions-gating.test.tsx` (+ the 2 bare sites in `live-repo-badge.test.tsx`).

## Files to Create

- (Approach D fallback only) `apps/web-platform/test/vi-waitfor-floor-guard.test.ts` — source-grep guard rejecting bare `vi.waitFor(` without a timeout.

## User-Brand Impact

**If this lands broken, the user experiences:** continued silent prod-deploy gating — a
flaky `test-webplat` shard fail-closes `await-ci`, so `deploy` + `live-verify` are skipped
and a merged fix (security patch, bug fix) never reaches production for that SHA, with no
red signal on the deploy itself.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this change
touches only test setup files, the vitest config, and test files; no runtime code path,
schema, auth, or API surface. No data-exposure vector.

**Brand-survival threshold:** `aggregate pattern` — the defect silently degrades the deploy
pipeline for *every* PR (not a single user's data), so the blast radius is an aggregate
deploy-reliability regression rather than a single-user incident. No CPO sign-off required.
No sensitive path touched (no migrations/auth/API routes/`.sql`), so no `threshold: none`
scope-out bullet is needed.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 — `grep -rn "vi\.waitFor" apps/web-platform/test/` shows every site routes
      through the Phase-1 wrapper (Approach A); zero sites rely on the 1000ms default.
      (Approach A: all 47 sites inherit the wrapped default; verified by the floor
      behavioral tests + the guard-test rows.)
- [x] AC2 — `setup-dom-leak-guard.test.ts` contains a token row asserting the `vi.waitFor`
      wrapper is present in `setup-dom.ts`, and an equivalent `describe` block covers
      `setup-node.ts` (Approach A). Deleting either wrapper fails this guard.
- [x] AC3 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes (the wrapper
      cast preserves the `typeof waitFor` overload). TSC_EXIT=0.
- [x] AC4 — the previously-bare-site files pass: all 9 `vi.waitFor` files (live-repo-badge,
      cc-dispatcher, org-switcher-container, use-active-repo-poll, is-template-authorized,
      invite-member-modal, invite-actions-gating, transfer-ownership-dialog,
      debug-stream-panel) → 113 tests, 0 failed.
- [x] AC5 — Full webplat suite green ×3 consecutive runs:
      `TEST_GROUP=webplat bash scripts/test-all.sh` exited 0 three times (906 files /
      11225 tests passed each), with no `vi.waitFor.timeout` and no >16s render timeout on
      `dashboard-layout-sidebar-settings` / `chat-surface-sidebar-wrap`.
- [x] AC6 — RTL `asyncUtilTimeout: 10_000` (#5113) and `testTimeout: 16_000` (#4128) are
      **unchanged** (the diff touches only the new wrapper blocks + test files; vitest.config.ts
      untouched).
- [ ] AC7 — PR body records the Phase-0 A/D decision + spike evidence, and the Phase-2
      descope decision (filled at ship).
- [ ] AC8 — `Ref #5796` in the PR body (this is a chore/test-infra fix; close the issue
      after the next clean `test-webplat` CI run confirms the re-eval criterion is satisfied —
      see Soak note below).

### Re-eval / soak (issue-close criterion)

- [ ] Per the issue's `Re-eval by: event-grep`, close #5796 only after a post-merge
      `test-webplat` CI run completes green with **no** `vi.waitFor`/`waitFor` timeout. This
      is a one-shot observation, not a recurring soak probe; no `scripts/followthroughs/`
      enrollment is required (the close is a single manual confirmation against the next CI run).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI test-infrastructure / tooling change. Files touched
are vitest setup files, the vitest config, and test files. No user-facing surface (no
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` created/modified), so the
Product/UX gate resolves **NONE**. No regulated-data surface (GDPR gate skipped). No new
infrastructure (IaC gate skipped). No server/src/infra runtime code (Observability gate
skipped). No architectural decision — the test-timeout philosophy is documented inline in
`vitest.config.ts` consistent with #4128/#5113; no ADR/C4 impact.

## Open Code-Review Overlap

3 open code-review issues substring-match `cc-dispatcher`, but all reference the
`cc-dispatcher.ts` **source module**, not the `cc-dispatcher.test.ts` timeout config this plan
edits:

- #3243 (arch: decompose `cc-dispatcher.ts` into focused modules) — **Acknowledge**: source
  decomposition, orthogonal to raising `vi.waitFor` timeouts in its test file.
- #3242 (review: `tool_use` WS event lacks raw name field) — **Acknowledge**: runtime WS
  contract, unrelated to test timeouts.
- #4254 (test: `template_id` NOT NULL fixture drift breaks tenant-iso suites) — **Acknowledge**:
  fixture-shape drift in a different suite family; not a timeout concern.
- #3820 (safe-bash allowlist) — **Acknowledge**: tooling allowlist, unrelated.

No overlap on `vitest.config`, `setup-dom`, `setup-node`, `asyncUtilTimeout`, or
`live-repo-badge`. No fold-in or defer action required.

## Test Scenarios

1. **Bare `vi.waitFor` under simulated starvation** — a test whose `vi.waitFor` condition
   resolves at ~1.5s (artificially delayed) passes after Phase 1 (would have failed at the
   1s default). Verified implicitly by AC4/AC5 under real full-suite load.
2. **Explicit per-site timeout preserved** — a `vi.waitFor(cb, { timeout: 500 })` still
   times out at 500ms after the wrapper lands (wrapper spreads the explicit value over the
   default). Add a unit assertion in the spike / guard.
3. **Number-form options** — `vi.waitFor(cb, 2000)` is honored as a 2000ms timeout by the
   wrapper (the `typeof options === "number"` branch).
4. **Render-contention file** — `dashboard-layout-sidebar-settings.test.tsx` no longer times
   out under `TEST_GROUP=webplat` full run after Phase 2 (or Phase 1 alone if it suffices).
5. **Drift guard bites** — deleting the wrapper line from `setup-dom.ts` fails
   `setup-dom-leak-guard.test.ts` (negative-space test).

## Risks & Mitigations

- **`vi.waitFor` reassignment frozen/invisible in vitest 4.1** → Phase 0 spike gates this;
  fall back to Approach D (per-site sweep + guard). The plan ships either way.
- **Wrapper interferes with fake timers** → wrapper changes only the default timeout, not
  polling/timer mechanics; Phase 0 step 2 smoke-tests a fake-timers + `vi.waitFor` file.
- **`maxForks` cap regresses CI wall-clock** → Phase 2 is evidence-gated and re-measured;
  cap is chosen relative to runner core count; the existing config already accepts the
  reliability/wall-clock tradeoff for `isolate`/`forks`.
- **Slower genuinely-failing waits** → raising the floor to 10s makes a *failing* `vi.waitFor`
  take 10s instead of 1s (same tradeoff #5113 documents for RTL). Passing waits are
  unaffected (they resolve when the condition is met). Acceptable for a reliable suite.
- **Timeout treadmill perception** → explicitly NOT raising `testTimeout`/`asyncUtilTimeout`
  again; Phase 1 closes an *un-raised* knob, Phase 2 reduces load instead of raising ceilings.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, placeholder, or omits the threshold
  fails `deepen-plan` Phase 4.6 — this section is filled with `aggregate pattern`.
- `vi.waitFor` is a **vitest** util distinct from RTL `waitFor`; do not "fix" it by editing
  `configure({ asyncUtilTimeout })` — that knob has no effect on `vi.waitFor`.
- The fix must touch **both** `setup-node.ts` and `setup-dom.ts` — `vi.waitFor` is used in
  the node project (`cc-dispatcher.test.ts`, `is-template-authorized.test.ts`), not only the
  component project. A setup-dom-only fix leaves 18 node-project sites at the 1s default.
- Approach D's guard regex must tolerate multi-line `vi.waitFor(\n  cb,\n  { timeout })`
  forms (scan the call + following ~3 lines), or it will false-fail the already-explicit
  `live-repo-badge.test.tsx` sites.
- Verify `poolOptions.forks.maxForks` is the correct vitest `4.1.0` key (vs `maxWorkers` /
  `--max-workers`) before editing the config — the `.d.ts` did not surface it in a quick
  grep; confirm against the installed version's config types or docs at work time.

## Alternatives Considered

| Approach | Verdict |
| --- | --- |
| Raise `testTimeout` again (16s→30s) | **Rejected.** Treadmill; render-contention failures are ~20s-shaped and would creep further; doesn't fix the `vi.waitFor` 1s gap at all. |
| Migrate `vi.waitFor` → RTL `waitFor` to inherit the 10s `asyncUtilTimeout` | **Rejected as sole fix.** RTL `waitFor` needs DOM/RTL; the 18 node-project sites (`cc-dispatcher`, `is-template-authorized`) have no DOM and cannot use it. Would also change act-wrapping semantics per site. |
| Add CI shards (2-way → 3/4-way) | **Rejected.** Adds GH jobs/cost; a `poolOptions` cap reduces per-runner contention for both the local unsharded run and each CI shard without new jobs. |
| Per-site `{ timeout }` sweep (Approach D) | **Held as fallback.** Lowest risk of breaking vitest internals, but verbose (42 sites) and needs its own guard; preferred only if the global wrapper proves infeasible in Phase 0. |
