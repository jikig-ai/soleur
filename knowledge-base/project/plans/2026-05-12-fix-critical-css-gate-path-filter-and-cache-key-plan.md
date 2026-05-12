---
type: bug-fix
classification: ci-workflow
issue: 3624
branch: feat-one-shot-3624-critical-css-gate
priority: p2-medium
domain: engineering
requires_cpo_signoff: false
---

# fix: scope critical-css-gate to docs/CSS changes + fix stale Playwright cache (#3624)

## Overview

`critical-css-gate` in `.github/workflows/ci.yml` runs unconditionally on every PR and fails on most of them with `browserType.launch: Executable doesn't exist at /home/runner/.cache/ms-playwright/chromium_headless_shell-1223/chrome-headless-shell-linux64/chrome-headless-shell`. PR #3602 (a server-only diff touching only `apps/web-platform/server/cc-dispatcher.ts`) tripped this on 2026-05-12 and was blocked from auto-merge by `/soleur:ship` Phase 7, which correctly refuses to bypass a failing check even when the failure is orthogonal to the PR diff.

There are **two independent root causes** to fix in the same PR:

1. **No path filter on the job.** The gate is only meaningful for changes under `plugins/soleur/docs/**`, root-level Eleventy config, or scripts/templates that affect the docs site's above-fold CSS. Every other PR runs the job for nothing — paying ~50 s of CI time and (now) eating a false-negative failure. Fix: scope the job with a per-job `paths`-style gate using `dorny/paths-filter` or a `git diff --name-only`-driven conditional (the workflow-level `on.pull_request.paths` is not viable because the workflow houses other jobs the repo does require on every PR).

2. **Cache key is invariant to Playwright version.** The job's cache key is `playwright-critical-css-gate-${{ hashFiles('plugins/soleur/docs/scripts/screenshot-gate.mjs') }}`. The screenshot-gate script never references the Playwright version; Playwright's browser binary versioning is decoupled from npm versioning (`chromium_headless_shell-1223` is the chromium revision, not the npm version). On a cache hit, the "(cache hit)" branch runs only `npx playwright install-deps chromium` (OS deps) — it does NOT re-fetch the browser binary. When upstream Playwright ships a new chromium revision (every ~6 weeks), the cached binary path goes stale and the gate fails until someone busts the cache by editing `screenshot-gate.mjs`. The working pattern lives 50 lines above in the same file: the `e2e` job keys cache on `apps/web-platform/bun.lock`, which advances with every Playwright version bump. Even simpler: `deploy-docs.yml` runs the same screenshot-gate flow with NO caching at all (~15 s extra wall-clock) and never has this failure mode.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #3624) | Codebase reality | Plan response |
|---|---|---|
| "Add a path filter to the gate workflow" (single-job filter) | `ci.yml` houses 11+ jobs (test, e2e, lint-*, etc.); `on.pull_request.paths` at workflow level would gate ALL of them, not just `critical-css-gate`. | Use a per-job conditional (`dorny/paths-filter` action emitting an output, then `if: needs.changes.outputs.docs == 'true'` on the job) — NOT workflow-level `paths`. |
| "Add `npx playwright install` step" | The job already has two install branches (cache-hit + cache-miss); cache-miss runs `npx playwright install --with-deps chromium`. The problem is the cache-hit branch reusing a stale binary. | Reroute past the broken cache (option chosen: align cache key with `package-lock.json` so a Playwright pin bump busts the cache) — OR drop the cache entirely to match `deploy-docs.yml`. Both work; align-the-key is preferred because it preserves the ~30-40 s wall-clock savings on the hot path. |
| "`critical-css-gate` blocked the PR" | Ruleset `CI Required` (id 14145388) lists only `test`, `dependency-review`, `e2e`, `CodeQL`, `skill-security-scan PR gate` — `critical-css-gate` is NOT required by branch protection. | The block came from `/soleur:ship` Phase 7's all-checks-must-pass safety rule, not from branch protection. Both fixes still warranted, because `/soleur:ship`'s safety rule is correct — the gate's noise is the bug. |

Verified via `gh api repos/jikig-ai/soleur/rulesets/14145388` on 2026-05-12.

## User-Brand Impact

**If this lands broken, the user experiences:** docs-site PRs that DO touch above-fold CSS skip the gate silently and a FOUC regression ships to docs.soleur.ai — the exact regression class the `cq-eleventy-critical-css-screenshot-gate` rule was created to prevent (PRs #2904, #2960 shipped this twice in 8h).

**If this leaks, the user's data is exposed via:** N/A — no regulated data, no user-facing surface touched. This is a CI orchestration change.

**Brand-survival threshold:** none — failure mode is "the gate stops gating", which the static `check-critical-css-coverage.mjs` step still partially covers (selector-presence check) and `deploy-docs.yml` still runs the full gate post-merge before publishing to GitHub Pages. The pre-merge gate is the cheap-to-fix layer; deploy-time is the load-bearing layer.

**Reason for threshold=none on a CI surface:** No production traffic depends on this workflow. The only customer-facing risk is delayed FOUC detection by ~5 minutes (until `deploy-docs.yml` runs post-merge) — a noticeable but not brand-survival regression. Static coverage check (`check-critical-css-coverage.mjs`) continues to run on every CSS/template change regardless of Playwright outcome, providing fail-fast feedback on the most common bug class.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `critical-css-gate` job uses a per-job conditional that evaluates true ONLY when the PR's changed file set intersects with `plugins/soleur/docs/**`, `plugins/soleur/skills/**`, `plugins/soleur/agents/**`, `plugins/soleur/commands/**`, `eleventy.config.js`, or `*.css` / `*.html` / `*.njk` anywhere under `plugins/soleur/`.
- [ ] The change set mirrors `deploy-docs.yml`'s `on.push.paths` (same prefix list, plus screenshot baselines + the gate scripts themselves so changes to the gate run the gate).
- [ ] Cache key is changed from `playwright-critical-css-gate-${{ hashFiles('plugins/soleur/docs/scripts/screenshot-gate.mjs') }}` to `playwright-critical-css-gate-${{ hashFiles('package-lock.json') }}` (root lockfile — that's where the gate's `npm install --no-save playwright@1` resolves transitively against the root `node_modules`).
- [ ] Verification grep: `git ls-files .github/workflows/ | xargs grep -l "ms-playwright"` shows ≤2 files (ci.yml + deploy-docs.yml). Confirm both files' Playwright install paths can refresh the browser binary on Playwright version bump.
- [ ] Test the negative path: a PR touching `apps/web-platform/server/**` only (the PR-A1 shape from #3602) does NOT run `critical-css-gate`. Verified by inspecting the PR-checks list after push — the job appears as "skipped" or absent.
- [ ] Test the positive path: a PR touching `plugins/soleur/docs/_includes/base.njk` (smoke-edit a comment) DOES run `critical-css-gate` and it passes. Verified by inspecting the same PR-checks list.
- [ ] Verification of cache-key drift: run `gh cache list --key playwright-critical-css-gate` on the repo and confirm the new cache entry is created under the lockfile hash. Old caches expire naturally per GH's 7-day LRU.
- [ ] Static `check-critical-css-coverage.mjs` step runs UNCONDITIONALLY whenever the job runs (already the case today — no change here). The path-filter governs whether the job runs at all, not which steps within it run.

### Post-merge (operator / monitoring)

- [ ] After merge, watch the first 5 PRs to `main` that DON'T touch the docs scope. Confirm `critical-css-gate` is skipped on each (visible in the GH PR checks tab as "Skipped" or absent from the list, depending on the conditional implementation).
- [ ] After merge, watch the next PR that DOES touch `plugins/soleur/docs/**`. Confirm the gate runs to green with a cache hit OR with a clean cache-miss install path. If cache hit ships a stale binary again, escalate to "drop cache entirely" fallback (see Alternatives).

## Implementation Phases

### Phase 1 — Add path-filter conditional to `critical-css-gate`

**File:** `.github/workflows/ci.yml`

**Approach A (preferred — `dorny/paths-filter`):** Introduce a top-level `changes` job that runs `dorny/paths-filter@v3` (pinned by SHA per `vendor-pin-verify.yml`) and exposes a `docs` output. Wire `critical-css-gate` with `needs: changes` and `if: needs.changes.outputs.docs == 'true'`.

**Approach B (no new dependency — `git diff` driven):** Add a single inline step at the top of `critical-css-gate` that runs `git diff --name-only origin/${{ github.event.pull_request.base.ref }}..HEAD` against an `egrep -q` of the path patterns, sets a step-output `should_run`, and the remaining steps each guard `if: steps.path-check.outputs.should_run == 'true'`.

**Recommendation: A.** Lower noise, declarative, matches the `paths`-as-data convention of `deploy-docs.yml`. A new `actions/` dependency requires `vendor-pin-verify.yml` pinning (action repo + SHA + tag in `.github/dependabot.yml`-style format) — verify the pin pattern by reading two sibling workflows that already use third-party actions.

**Pattern source — same prefix list as `deploy-docs.yml` lines 6-11:**
```yaml
filters: |
  docs:
    - 'plugins/soleur/docs/**'
    - 'plugins/soleur/skills/**'
    - 'plugins/soleur/agents/**'
    - 'plugins/soleur/commands/**'
    - 'eleventy.config.js'
    - '.github/workflows/ci.yml'      # so gate-job edits self-trigger
    - '.github/workflows/deploy-docs.yml'
```

The two workflow-file self-references prevent a class of silent-failure where someone edits the gate logic and the gate doesn't re-run on its own PR.

### Phase 2 — Realign Playwright cache key to lockfile-hash

**File:** `.github/workflows/ci.yml` (same job)

Single-line edit:
```yaml
# BEFORE
key: playwright-critical-css-gate-${{ hashFiles('plugins/soleur/docs/scripts/screenshot-gate.mjs') }}
# AFTER
key: playwright-critical-css-gate-${{ hashFiles('package-lock.json') }}
```

**Why `package-lock.json` not `bun.lock`:** the gate installs Playwright via `npm install --no-save playwright@1` at the root, against root `node_modules`. The root project uses npm (root `package-lock.json` is present); only `apps/web-platform/` uses bun. The gate's Playwright install is npm-mediated, so npm's lockfile is the right cache discriminator.

**Verification step (add to AC):** after the change lands, run `grep -A 2 "Cache Playwright browsers" .github/workflows/ci.yml | grep "key:"` and confirm both caches (critical-css-gate + e2e) now key on per-lockfile content.

### Phase 3 — Documentation / learning capture

**File:** `knowledge-base/project/learnings/best-practices/2026-05-12-ci-playwright-cache-key-must-track-npm-version-not-script-hash.md` (new)

Capture two cross-cutting lessons:

1. Workflow-job conditional patterns: workflow-level `on.pull_request.paths` gates ALL jobs in the workflow; per-job conditionals (via `paths-filter` action) are the right tool when one workflow houses multiple unrelated jobs.
2. Playwright cache invariants: cache key must include something that advances with Playwright version. Use `package-lock.json` (npm) or `bun.lock` (bun) — never the consumer script's hash.

## Files to Edit

- `.github/workflows/ci.yml` — add `changes` job using `dorny/paths-filter@v3`, add `needs: changes` and `if:` guard to `critical-css-gate`, swap cache key to `hashFiles('package-lock.json')`.

## Files to Create

- `knowledge-base/project/learnings/best-practices/2026-05-12-ci-playwright-cache-key-must-track-npm-version-not-script-hash.md` — learning capture.

## Files Verified (no changes needed)

- `.github/workflows/deploy-docs.yml` — already runs the same screenshot-gate flow without caching; serves as the post-merge load-bearing safeguard.
- `plugins/soleur/docs/scripts/screenshot-gate.mjs` — gate script unchanged.
- `plugins/soleur/docs/scripts/check-critical-css-coverage.mjs` — static check unchanged; still runs whenever the job runs.

## Alternatives Considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Drop cache entirely (match `deploy-docs.yml`) | Single-line change, zero invariant drift risk | +30-40 s wall-clock per relevant PR | **Fallback** if Approach A or cache-key change show residual stale-binary failures within 14 days. |
| Bump cache key on chromium revision string | Most aligned with the actual binary versioning | No clean way to read the revision at `key:` evaluation time (it's inside Playwright's source) | Rejected — fragile. |
| Workflow-level `on.pull_request.paths` filter | Simplest YAML edit | Would gate ALL of `ci.yml` jobs, breaking required-checks (`test`, `e2e`, `CodeQL`, etc.) on non-docs PRs | **Rejected** — would orphan required status checks. |
| Add `npx playwright install` to the cache-hit branch unconditionally | Closes the binary-staleness symptom | Defeats the cache (full re-download each time) — equivalent to dropping the cache, but with more YAML | Rejected in favor of the cache-key realignment. |
| Skip the gate via `continue-on-error: true` | Removes the noise | Defeats the gate's purpose entirely; `/soleur:ship` Phase 7 still surfaces it | **Rejected.** |

## Risks

- **Path-filter false negative.** If `docs` filter doesn't include a path that affects above-fold CSS (e.g., a CSS file added under a new subdirectory), the gate skips and a FOUC ships pre-merge. Mitigation: mirror `deploy-docs.yml`'s prefix list verbatim — `deploy-docs.yml` already has 9 months of production experience with the same patterns. Add `.github/workflows/{ci,deploy-docs}.yml` to the filter so self-edits to the gate logic trigger the gate.
- **Cache invalidation tax on lockfile change.** Bumping the cache key to `package-lock.json` means the cache misses every time root `package-lock.json` changes — even when Playwright wasn't bumped. Cost: ~40 s download per first-hit PR after any lockfile edit. Acceptable; the e2e job already pays this and lockfile churn is low.
- **`dorny/paths-filter` action dependency.** Adds a third-party action. Mitigation: pin by SHA per repo convention; the action has 4500+ stars and ships from a maintained org. Alternative: use Approach B (inline `git diff`) which adds no dependency but reads less cleanly.
- **Self-referential `.github/workflows/ci.yml` in the filter.** Listing `ci.yml` in `docs:` means ANY ci.yml edit (job adds, lint changes) triggers the gate. Cost: trivial — gate runs are ~50 s. Benefit: prevents a class of silent gate-bypass where someone edits the gate and the gate doesn't run on its own change.
- **Test-runner-vs-gate disagreement.** Both `e2e` (apps/web-platform Playwright tests) and `critical-css-gate` (docs FOUC) now key cache on different lockfiles (`bun.lock` vs `package-lock.json`). Acceptable — they install different Playwright trees against different `node_modules` roots.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`. (This plan's threshold is `none` with explicit reason — preflight Check 6 will pass.)
- If `dorny/paths-filter@v3` is the chosen approach, verify the PIN convention (SHA + comment with version tag) matches sibling third-party action pins in the same file BEFORE writing the pin line. Different repos use slightly different formats; the `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1` style at line 16 is the canonical reference.
- If after Phase 2 the gate still fails with the same chromium-binary error on a docs-touching PR within 14 days post-merge, switch to the Alternatives fallback (drop cache entirely). Do NOT iterate on cache-key heuristics — `deploy-docs.yml` proves the no-cache path works.
- Do NOT change `cq-eleventy-critical-css-screenshot-gate` (AGENTS.md docs sidecar). The rule's content is correct; only the workflow plumbing changes.

## Open Code-Review Overlap

1 open scope-out touches files in this plan's scope:

- **#2965** (`review: evaluate build-time critical-CSS extractor for Eleventy docs (deferred from #2960)`) — names `screenshot-gate.mjs` and `check-critical-css-coverage.mjs` in its body. **Disposition: Acknowledge.** This issue is about replacing the hand-extracted critical CSS with a build-time extractor (`beasties`, `critical`, `penthouse`); the gate scripts would still exist as a behavioral guard. Different concern, different cycle. The path-filter + cache-key fix here is orthogonal to the extractor evaluation and does not affect #2965's re-evaluation criteria (9 KB gzipped or 3rd FOUC). Scope-out remains open.

## Domain Review

**Domains relevant:** Engineering (CI/CD)

### Engineering (CTO)

**Status:** reviewed (auto — single-domain plan)
**Assessment:** This is a pure CI plumbing fix. Two independent root causes (path filter, cache invariant) addressed in the minimum-edit shape. No production code touched, no user-facing surface modified, no schema changes. The static `check-critical-css-coverage.mjs` step remains unconditional whenever the job runs, preserving the cheapest layer of FOUC defense even if Playwright tooling drifts. The Engineering risk is bounded by `deploy-docs.yml` continuing to run the same gate post-merge — pre-merge gate becoming a no-op on irrelevant PRs is the desired state, not a regression. No Product/UX, no Legal, no Marketing implications.

No cross-domain implications detected — infrastructure/tooling change.

## Test Scenarios

1. **PR touches `apps/web-platform/server/**` only.** Expected: `critical-css-gate` does not appear (or appears as "skipped") in PR checks. Static coverage check is NOT run (the job didn't start).
2. **PR touches `plugins/soleur/docs/_includes/base.njk`.** Expected: gate runs, static coverage check passes, Playwright install runs (cache hit on lockfile-key, no binary staleness), screenshot gate passes, stylesheet-swap gate passes. Wall-clock <60 s on cache hit.
3. **PR touches `plugins/soleur/docs/css/style.css`.** Expected: same as scenario 2.
4. **PR touches `.github/workflows/ci.yml` only.** Expected: gate runs (self-trigger covers gate-logic edits).
5. **PR touches `package-lock.json` only (e.g., dependabot Playwright bump).** Expected: gate is path-filtered out (lockfile not in `docs:` filter unless we add it — DECISION: do not add, dependabot updates run their own validation). Cache key still advances on next docs-touching PR.
6. **Playwright version bump in a future PR.** Expected: cache key invariant advances via `package-lock.json` hash; cache-miss path runs `npx playwright install --with-deps chromium` and refreshes the binary. No stale-binary failure.

## Research Insights

- **Issue body:** #3624 (verified via `gh issue view 3624` on 2026-05-12).
- **Failing run inspected:** `gh run view 25718834192 --log` (PR check ID 75514819305) — error string `screenshot-gate: failed to launch chromium: browserType.launch: Executable doesn't exist at /home/runner/.cache/ms-playwright/chromium_headless_shell-1223/chrome-headless-shell-linux64/chrome-headless-shell` confirmed at `2026-05-12T07:01:12.6677077Z`.
- **Cache-hit branch identified at `ci.yml:242-246`:** runs only `npm install --no-save playwright@1 http-server@14` and `npx playwright install-deps chromium`. The latter installs OS libraries, not the chromium binary. Confirmed via `npx playwright install --help` semantics: `install-deps` is OS-only; `install` is browser-binary.
- **Working sibling pattern at `ci.yml:170-175` (e2e job):** `key: playwright-${{ hashFiles('apps/web-platform/bun.lock') }}` — lockfile-keyed, advances with Playwright bumps.
- **Working no-cache pattern at `deploy-docs.yml:91-94`:** always runs `npm install --no-save playwright@1 http-server@14 && npx playwright install --with-deps chromium`. ~40 s slower per run, zero staleness risk.
- **Branch-protection ruleset state:** `gh api repos/jikig-ai/soleur/rulesets/14145388` confirms required checks are `test`, `dependency-review`, `e2e`, `CodeQL`, `skill-security-scan PR gate`. `critical-css-gate` is NOT required, so path-filtering it does not orphan a required check.
- **AGENTS.md rule alignment:** `cq-eleventy-critical-css-screenshot-gate` (in `AGENTS.docs.md`) points at the two gate scripts. This plan preserves both scripts and the gate's behavior on relevant PRs; only the trigger condition changes. Rule unaffected.

## CLI-Verification Gate

No new CLI invocations land in user-facing docs from this plan. The `dorny/paths-filter@v3` and `actions/cache@v4.2.3` invocations live in `.github/workflows/ci.yml` (CI surface, not docs). Pin SHAs follow `vendor-pin-verify.yml` convention.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-12-fix-critical-css-gate-path-filter-and-cache-key-plan.md. Branch: feat-one-shot-3624-critical-css-gate. Worktree: .worktrees/feat-one-shot-3624-critical-css-gate/. Issue: #3624. Plan reviewed, implementation next.
```
