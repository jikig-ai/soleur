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

## Enhancement Summary

**Deepened on:** 2026-05-12
**Sections enhanced:** Implementation Phases (1, 2), Alternatives, Risks, Files to Edit, Acceptance Criteria, CLI-Verification Gate
**Research artifacts consulted:** `ci.yml` (full file), `deploy-docs.yml`, `infra-validation.yml`, `vendor-pin-verify.yml`, `gh api repos/dorny/paths-filter/git/{refs,tags}`, `gh api repos/jikig-ai/soleur/rulesets/14145388`, `gh pr checks 3602`, `gh run view 25718834192 --log`, `AGENTS.docs.md` (cq-eleventy-critical-css-screenshot-gate rule body).

### Key Improvements

1. **Flipped recommendation from `dorny/paths-filter@v3` to a hand-rolled `git diff` + `if:` filter.** `infra-validation.yml:24-52` already uses this exact pattern in production with `fetch-depth: 0`. No new third-party action dependency, no first-time vendor-pin obligation, no `vendor-pin-verify.yml` co-edit. The plan's original Approach A is downgraded to "Alternative (rejected)" and Approach B is promoted to the implementation path.
2. **Cache key realignment verified against live mechanism.** The cache-hit branch at `ci.yml:242-246` runs only `npx playwright install-deps chromium` (OS deps, not the binary). The cache-miss branch at `ci.yml:236-240` runs `npx playwright install --with-deps chromium` (binary + OS deps). So a bumped cache key DOES refresh the binary on first miss after a Playwright pin bump. Confirmed.
3. **Explicit `fetch-depth: 0` requirement surfaced.** Without it, `git diff --name-only "origin/${BASE_REF}...HEAD"` returns nothing on a shallow clone — the filter would silently always-skip on push events. Added as a Sharp Edge.
4. **`dorny/paths-filter@v3` resolved live SHA captured** even though the action is no longer the chosen path — kept in the Alternatives column in case Approach B's `git diff` form proves brittle in practice. SHA: `d1c1ffe0248fe513906c8e24db8ea791d46f8590` (peeled commit of annotated tag `v3` → release `v3.0.3`).
5. **Required-check independence reverified.** `gh api repos/jikig-ai/soleur/rulesets/14145388` confirms `critical-css-gate` is NOT in the required-status-checks set. Path-filtering it cannot orphan a required check.
6. **Self-trigger pattern confirmed.** `infra-validation.yml:14-15` includes the workflow file itself in its own `paths:` filter — same pattern adopted in the plan's filter list. Prevents gate-self-edit silent bypass.

### New Considerations Discovered

- **Action-pin-first-usage cost.** Adding `dorny/paths-filter@v3` to the repo would be the first usage of this action, triggering a vendor-pin-verify obligation. Hand-rolled `git diff` avoids it entirely.
- **`infra-validation.yml`'s `if:` form lands jobs as "Skipped" (not absent) in the PR checks UI** when the changed-paths set is empty (`directories == '[]'`). The same UX will apply to `critical-css-gate` post-fix — `/soleur:ship` Phase 7 must treat "Skipped" as pass, which it already does (confirmed by `infra-validation` PRs not blocking ship today).
- **`bash -n` is NOT the right syntax check for YAML-embedded shell** (per the Sharp Edges precedent from #3543). Verification of the new conditional steps must use `actionlint` for YAML and `bash -c '<extracted snippet>'` for the embedded shell.
- **The static `check-critical-css-coverage.mjs` step is npm-only** (no Playwright dependency) — even on a docs-touching PR where the Playwright gate fails for any reason, the static selector-presence check still catches the most common bug class (missing rule for a new template selector). This is now reflected in the Risks section as the "depth defense" continues to hold.

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

- [ ] A new `detect-changes` job at the top of `ci.yml jobs:` block runs `actions/checkout@<pinned-SHA>` with `fetch-depth: 0`, then `git diff --name-only "origin/${BASE_REF}...HEAD"` filtered through the regex anchor list in Phase 1, emitting `outputs.docs` as `'true'` or `'false'`. `push` to main short-circuits to `'true'`.
- [ ] `critical-css-gate` declares `needs: detect-changes` and `if: needs.detect-changes.outputs.docs == 'true'`.
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

**Chosen approach: hand-rolled `git diff`-driven `detect-changes` job + `needs:` + `if:` gate.** This is the canonical in-repo precedent (`infra-validation.yml:24-52`) and adds zero new third-party dependencies. The previously-preferred `dorny/paths-filter@v3` is downgraded to Alternatives.

**Why the flip:** Adding `dorny/paths-filter` to the repo would be the first usage of that action, triggering a vendor-pin obligation. The hand-rolled pattern is already in production for `infra-validation.yml` and produces the same effective behavior (jobs land as "Skipped" in PR checks when the path filter misses). Less surface area, less novelty, zero new external trust.

**Implementation shape (mirrors `infra-validation.yml:24-52` verbatim):**

```yaml
  # detect-changes: drives the if:-gate on critical-css-gate. Mirrors the
  # infra-validation.yml pattern. Cheap (one checkout + one git diff).
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      docs: ${{ steps.filter.outputs.docs }}
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          fetch-depth: 0
      - id: filter
        env:
          EVENT_NAME: ${{ github.event_name }}
          BASE_REF: ${{ github.base_ref }}
        run: |
          if [[ "$EVENT_NAME" == "push" ]]; then
            # push to main: always run (cheapest path; main is the source-of-truth)
            printf 'docs=true\n' >> "$GITHUB_OUTPUT"
            exit 0
          fi
          CHANGED=$(git diff --name-only "origin/${BASE_REF}...HEAD")
          if printf '%s\n' "$CHANGED" | grep -E '^(plugins/soleur/(docs|skills|agents|commands)/|eleventy\.config\.js$|\.github/workflows/(ci|deploy-docs)\.yml$)' -q; then
            printf 'docs=true\n' >> "$GITHUB_OUTPUT"
          else
            printf 'docs=false\n' >> "$GITHUB_OUTPUT"
          fi
```

Then add to `critical-css-gate`:

```yaml
  critical-css-gate:
    needs: detect-changes
    if: needs.detect-changes.outputs.docs == 'true'
    runs-on: ubuntu-latest
    # ... existing steps unchanged
```

**Path-prefix list source — same prefixes as `deploy-docs.yml:6-11`, translated from glob to regex anchor:**

| `deploy-docs.yml` glob | Regex anchor | Why |
|---|---|---|
| `plugins/soleur/docs/**` | `^plugins/soleur/docs/` | Docs site sources — primary signal. |
| `plugins/soleur/skills/**` | `^plugins/soleur/skills/` | Skill SKILL.md files render into the docs site. |
| `plugins/soleur/agents/**` | `^plugins/soleur/agents/` | Agent docs render into the docs site. |
| `plugins/soleur/commands/**` | `^plugins/soleur/commands/` | Command docs render into the docs site. |
| `eleventy.config.js` | `^eleventy\.config\.js$` | Build config — affects every page. |
| `.github/workflows/ci.yml` | `^\.github/workflows/ci\.yml$` | Self-trigger: gate-edit runs the gate. |
| `.github/workflows/deploy-docs.yml` | `^\.github/workflows/deploy-docs\.yml$` | Sister workflow; alignment-by-co-edit precedent. |

**Verification of regex translation against glob semantics:** Per AGENTS.md `cq-pathspec-to-regex-translation`-class learning (#3492 — pathspec `*` crosses `/`, regex `*` does not), all path prefixes here are directory-rooted with explicit `/` boundaries. No `*` glob is translated to `*` regex — only literal prefixes and end-anchors. Three-shape fixture test (top-level path, single-ancestor path, deep-nested path) before merging:

```bash
# fixture verification (run as ad-hoc preflight, NOT as a workflow step):
echo "plugins/soleur/docs/_includes/base.njk" | grep -qE '^(plugins/soleur/(docs|skills|agents|commands)/|eleventy\.config\.js$|\.github/workflows/(ci|deploy-docs)\.yml$)' && echo PASS:deep || echo FAIL
echo "eleventy.config.js"                       | grep -qE '^(plugins/soleur/(docs|skills|agents|commands)/|eleventy\.config\.js$|\.github/workflows/(ci|deploy-docs)\.yml$)' && echo PASS:root || echo FAIL
echo "apps/web-platform/server/cc-dispatcher.ts" | grep -qE '^(plugins/soleur/(docs|skills|agents|commands)/|eleventy\.config\.js$|\.github/workflows/(ci|deploy-docs)\.yml$)' && echo FAIL:negative || echo PASS:negative
```

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
| **Hand-rolled `git diff` + `if:` filter (in-repo precedent: `infra-validation.yml`)** | Zero new dependencies, zero vendor-pin obligation, matches in-repo convention | Slightly more YAML than declarative `paths-filter` | **CHOSEN** (deepen-plan flip). |
| `dorny/paths-filter@v3` (SHA `d1c1ffe0248fe513906c8e24db8ea791d46f8590`, peeled from annotated tag v3 → release v3.0.3 — verified 2026-05-12 via `gh api repos/dorny/paths-filter/git/tags/...`) | Declarative, more readable | First-time vendor pin (vendor-pin-verify obligation), new external trust surface | **Alternative** (only if `git diff` approach proves brittle in practice — e.g., `fetch-depth: 0` interacts badly with another workflow change). |
| Drop cache entirely (match `deploy-docs.yml`) | Single-line change, zero invariant drift risk | +30-40 s wall-clock per relevant PR | **Fallback** if cache-key realignment shows residual stale-binary failures within 14 days. |
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
- **`fetch-depth: 0` is mandatory on the `detect-changes` job's checkout.** Default `fetch-depth: 1` makes `git diff --name-only "origin/${BASE_REF}...HEAD"` return nothing, which would silently always-skip the gate. Confirmed by reading `infra-validation.yml:30-32` (the precedent).
- **YAML-embedded shell verification.** Per the #3543 Sharp Edges precedent (multi-word required check exposes strip-all-whitespace bug), DO NOT use `bash -n .github/workflows/ci.yml` to syntax-check the new conditional. Use `actionlint` for the YAML and `bash -c '<extracted snippet>'` against the embedded shell of `detect-changes`.
- If after Phase 2 the gate still fails with the same chromium-binary error on a docs-touching PR within 14 days post-merge, switch to the Alternatives fallback (drop cache entirely). Do NOT iterate on cache-key heuristics — `deploy-docs.yml` proves the no-cache path works.
- Do NOT change `cq-eleventy-critical-css-screenshot-gate` (AGENTS.md docs sidecar). The rule's content is correct; only the workflow plumbing changes.
- **The push-to-main path always runs the gate.** The implementation snippet treats `github.event_name == "push"` as an unconditional pass-through to `docs=true`. Rationale: main is the source of truth and a post-merge regression at the gate level is the canonical detection path; we want signal on main even if path-filter is too loose or too tight on a transient branch.
- **In-repo precedent for hand-rolled per-job filter:** `.github/workflows/infra-validation.yml:24-52` (`detect-changes` job emitting matrix-shaped `directories` output) is the load-bearing example. The plan mirrors structure but emits a single boolean output instead of a matrix.
- **Pathspec-to-regex translation safety:** All regex anchors in the filter are directory-rooted with explicit boundaries — no `*` wildcards that could cross `/` semantics. Sanity-tested with three-shape fixture (root file, single-ancestor, deep-nested) before commit. See generalized AGENTS.md rule class (#3492 — pathspec/regex parity).

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

No new CLI invocations land in user-facing docs from this plan. All changes live in `.github/workflows/ci.yml` (CI surface, not docs).

**Live-resolved references (deepen-plan, 2026-05-12):**

- `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1` — reused, already pinned at `ci.yml:16` and 9 other sites. Verified by `grep -c "actions/checkout@34e114876b" .github/workflows/ci.yml` ≥ 10.
- `actions/cache@5a3ec84eff668545956fd18022155c47e93e2684 # v4.2.3` — reused, already pinned at `ci.yml:230`. No change.
- `dorny/paths-filter@d1c1ffe0248fe513906c8e24db8ea791d46f8590 # v3.0.3` — NOT adopted in chosen path; kept here for the Alternatives row only. SHA resolved live via:

  ```bash
  gh api repos/dorny/paths-filter/git/refs/tags/v3 --jq '.object.sha'
  # → 6852f92c20ea7fd3b0c25de3b5112db3a98da050 (annotated tag object)
  gh api repos/dorny/paths-filter/git/tags/6852f92c20ea7fd3b0c25de3b5112db3a98da050 --jq '.object.sha'
  # → d1c1ffe0248fe513906c8e24db8ea791d46f8590 (peeled commit — v3.0.3 release)
  ```

**Branch-protection ruleset state (verified 2026-05-12 via `gh api repos/jikig-ai/soleur/rulesets/14145388`):** required checks are `test`, `dependency-review`, `e2e`, `CodeQL`, `skill-security-scan PR gate`. `critical-css-gate` is NOT in the list — path-filtering it does not orphan a required check.

**AGENTS.md rule citations verified active (2026-05-12 via `grep -qE "\[id: <id>\]" AGENTS*.md`):**

- `cq-eleventy-critical-css-screenshot-gate` → active in `AGENTS.docs.md`.
- `hr-weigh-every-decision-against-target-user-impact` → active in `AGENTS.core.md`.
- `wg-use-closes-n-in-pr-body-not-title-to` → active in `AGENTS.core.md`.

No retired or fabricated rule IDs cited in this plan.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-12-fix-critical-css-gate-path-filter-and-cache-key-plan.md. Branch: feat-one-shot-3624-critical-css-gate. Worktree: .worktrees/feat-one-shot-3624-critical-css-gate/. Issue: #3624. Plan reviewed, implementation next.
```
