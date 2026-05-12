---
title: "CI test-job speedup — bun-vs-bash matrix split with synthetic aggregator"
date: 2026-05-12
status: brainstorm-complete
worktree: .worktrees/feat-ci-test-job-speedup
branch: feat-ci-test-job-speedup
pr: 3672
issue: 3680
brand_survival_threshold: single-user incident
---

# CI test-job speedup brainstorm

## What we're building

Cut the `test` job in `.github/workflows/ci.yml` from ~199s wall-clock to <130s on 50% of runs (stretch <100s). Bundle Playwright `--shard=2` for the secondary `e2e` job (111s → ~65s slow-side) and a `bun install` action cache. Defer a Bun version probe to a separate follow-up PR so its risk doesn't confound the speedup measurement.

The mechanism: split `bash scripts/test-all.sh` execution across **two matrix jobs** (bun suites vs bash suites) and reconstruct the existing `test` required check via a **synthetic aggregator job** that `needs:` both shards. Branch-protection ruleset 14145388 remains untouched.

## Why this approach

Phase 0.5 + 1.1 surfaced three load-bearing constraints that ruled out the alternatives:

1. **`scripts/test-all.sh` runs serially by design** to defend against a Bun FPE/SIGFPE crash that scales with subprocess spawn count (`knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`). Even though `.bun-version` is now 1.3.11 (six patches past the crashy 1.3.5), the sequential runner is documented as defense-in-depth. **Approach D (`bun test --max-pool-size`) is therefore rejected** — it directly re-creates the spawn-pressure pattern that triggers the FPE. The Bun version probe (separate PR) will test whether the constraint can be relaxed.

2. **In-script `xargs -P` parallelization (Approach B) hits three confirmed sharp edges** on this codebase:
   - `apps/web-platform/test/workspace.test.ts:2-3` writes `process.env.WORKSPACES_ROOT` at module load with no `afterEach` restore — safe under per-suite-process isolation, broken under shared `xargs` parent.
   - `plugins/soleur/test/seo-aeo-drift-guard.test.ts` rebuilds repo-root `_site/`; `scripts/validate-blog-links.sh` reads from it. Parallel races corrupt the build.
   - `apps/telegram-bridge/test/health.test.ts:23` is the only suite that actually `.listen()`s a port — single-runner port collision risk.

3. **Branch-protection ruleset 14145388 requires the literal context `test`** alongside four externally-configured checks (`e2e`, `dependency-review`, `CodeQL`, `skill-security-scan PR gate`). Renaming `test` orphans the merge gate; recovery requires either ruleset edit (live ammo) or a synthetic aggregator (precedent at `2026-03-20-github-required-checks-skip-ci-synthetic-status.md`). The aggregator wins on reversibility — no ruleset drift if someone reverts the CI later.

**Why bun-vs-bash split (A′) instead of indexed shards (A):** the 29 suites cleave naturally on runner type. Bash tests don't need `bun install`, don't touch the FPE crash class, and can run in their own job without paying setup overhead twice. Indexed sharding would need a shard-list generator that re-uses `test-all.sh`'s discovery logic to preserve the orphan-suite invariant (PR #3512/#3533) — extra complexity for marginal additional savings.

## User-Brand Impact

**Artifact at risk:** the `test` required status check on branch-protection ruleset 14145388, which is the load-bearing merge gate for every PR including those touching regulated surfaces (GDPR transcripts in #3603, payment flows, auth boundaries).

**Vector:** three failure modes endorsed by operator framing:

1. *Trust breach / CI gate bypass* — sharded execution introduces a flake class (e.g., `_site/` race, env-leak under unexpected co-location) that goes intermittent before going red. Engineers/agents stop trusting red signals, a real regression eventually merges. If that regression lands during a compliance-sensitive window (GDPR transcript persistence, payment retry, auth boundary), it crosses from dev-velocity concern to brand-survival.
2. *Data loss / corruption* — parallel `_site/` writes corrupt the Eleventy build, link validation silently passes against stale output, blog/docs ship with broken links visible to prospects.
3. *Branch-protection orphan* — synthetic aggregator job naming drifts from the ruleset's required context, every PR becomes unmergeable for the team until the ruleset or the aggregator is fixed.

**Threshold:** single-user incident. Trust-breach probability is low but the regulated-surface blast radius is non-trivial; orphan-check is time-bound but high-visibility and team-blocking; data-loss has low probability under the chosen approach but a separate compound learning will capture the `_site/` EACCES class encountered in PR #3654 (no existing learning yet — gap).

## Key decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Approach A′ — bun-job + bash-job matrix split** | Natural cleavage; FPE-safe (separate runners); preserves orphan-suite invariant; lowest sharp-edge surface. |
| 2 | **Synthetic aggregator job named `test`** | Keeps branch-protection ruleset 14145388 untouched; reversible; standard GH pattern; pairs with synthetic-status learning. |
| 3 | **Fail-closed aggregator** | Per `2026-03-19-ci-squash-fallback-bypasses-merge-gates.md`, the aggregator MUST require all shards green (no `\|\|` fallback). Any missing shard fails the gate. |
| 4 | **Co-locate `_site/` builders in one shard** | `seo-aeo-drift-guard.test.ts` (bun, builds `_site/`) and `validate-blog-links.sh` (bash, reads `_site/`) must land in the SAME job or be sequenced. Decision: keep `validate-blog-links.sh` in the bun job (run after `seo-aeo-drift-guard`), NOT in the bash job. Override the natural bash-glob split for this single suite. |
| 5 | **Each shard runs `bun install --frozen-lockfile`** | Per `2026-03-18-bun-test-segfault-missing-deps.md`, missing deps segfault Bun. No assumption that cached `node_modules/` survives matrix splits. |
| 6 | **Bun-install `actions/cache` keyed on `bun.lockb` hash** | Caches `~/.bun/install/cache` + `node_modules/`. ~5-10s savings per shard, compounds under matrix. Mechanical, well-trodden. |
| 7 | **Playwright `--shard=2` for `e2e` job** | Secondary target. Native Playwright support, ~65s slow-side. N=2 not N=3 to keep setup overhead bounded. |
| 8 | **Phase 0 measurement mandatory** | Instrument `test-all.sh`'s `run_suite` with `date +%s.%N` boundaries; record per-suite wall-clock; classify top-5 by independence. Plan ships only after measurement confirms the bun-vs-bash split balances. |
| 9 | **Bun version probe deferred to follow-up PR** | Bumping `.bun-version` while restructuring the matrix would mask which change caused any regression. Probe runs in isolation later. |
| 10 | **Don't edit ruleset 14145388** | Synthetic aggregator wins on reversibility. Ruleset edit requires admin scope and leaves drift if the CI is later reverted. |

## Alternatives considered

- **Approach A (indexed N-way matrix sharding)** — Rejected for v1. More setup overhead, requires shard-list generator re-using `test-all.sh` discovery, marginal savings over A′. Revisit if Phase 0 measurement reveals bun-vs-bash is unbalanced.
- **Approach B (in-script `xargs -P`)** — Rejected. Three confirmed sharp edges on this codebase (env-leak, `_site/` race, port collision); single-runner OOM risk per FPE learning's 1.1 GB pre-crash spike.
- **Approach C (trim slowest suite)** — Bounded ceiling, useful only as complement. If Phase 0 reveals `apps/web-platform` dominates at ~80s, this becomes a follow-up: split `apps/web-platform/test/` into sub-directories (auth, kb, sandbox) so each is its own `run_suite` line and bin-packs across shards.
- **Approach D (`bun test --max-pool-size N`)** — Rejected outright. Re-creates the FPE spawn-pressure pattern that the sequential runner was built to mitigate.
- **GitHub-hosted larger runner (`ubuntu-latest-4-cores`)** — Rejected. Paid runners shift cost without changing the serial bottleneck for any single suite.
- **Touched-file-aware test selection** — Rejected for v1. Violates the orphan-suite invariant (PR #3512/#3533) if applied naively; full sweep on `push: main` could preserve it but adds complexity. Worth a follow-up issue.

## Open questions

1. **Will Phase 0 confirm bun-vs-bash balance?** Hypothesis: bun-side ≈ 100-120s (dominated by `apps/web-platform`), bash-side ≈ 40-60s (22 small `.test.sh` files). If bash-side ≪ bun-side, A′ doesn't hit the <130s target — pivot to A indexed or split `apps/web-platform/` internally.
2. **Does the Bun 1.3.11 FPE class still trigger?** Probe PR will answer. If gone, Approach D unlocks for future use.
3. **`_site/` EACCES class (PR #3654)** — no existing learning. Capture as a compound during this work if encountered.
4. **5-run flake check** — acceptance criterion is "no new flake class introduced." Measurement protocol: rerun the matrix-sharded `test` job 5 times on the PR branch and require 5/5 green.

## Capability gaps

None. All required tooling is in use elsewhere in the repo:
- `strategy.matrix` precedent: `.github/workflows/infra-validation.yml:54-57` and `:122-125`.
- `actions/cache` is in the repo's permitted-actions allowlist (used in other workflows for Playwright caches).
- `gh api repos/$REPO/statuses/$SHA` synthetic-status pattern documented in `knowledge-base/project/learnings/2026-03-20-github-required-checks-skip-ci-synthetic-status.md`.
- The synthetic-aggregator pattern itself has **no in-repo template** — Phase 1 introduces it (minor novelty, well-documented in GitHub Actions docs).

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO). Marketing, Operations, Sales, Finance, Support — not relevant (internal CI infra, no product/customer/financial surface).

### Engineering (CTO)

**Summary:** Recommends Approach A with synthetic aggregator; ruled out D (FPE re-trigger); validated that Bun 1.3.11 still treats sequential isolation as defense-in-depth. Flagged that hitting stretch <100s requires either suite-internal split of `apps/web-platform/` or a higher shard count — A′ alone is bounded by `max(bun-side, bash-side) + ~15s setup`.

### Product (CPO)

**Summary:** No direct product angle; defers to CTO. Highlighted one carry-forward: a flaky CI gate during a compliance-sensitive window (GDPR transcripts, payments) crosses from dev-velocity into brand-survival territory. Probability low, blast radius non-trivial. Treats this as a hard non-regression constraint, not a product gate.

### Legal (CLO)

**Summary:** No legal hooks. Test execution touches synthesized fixtures only (per `cq-test-fixtures-synthesized-only`); no DPA/Privacy Policy/SOC 2 commitment references a specific CI job name; ruleset 14145388 is internal engineering guardrail, not a binding compliance control. Aggregator-rename strategy is legally invisible.

## Next: implementation plan

Run `/soleur:plan` (or stay in worktree and proceed directly) to produce the phased plan. The plan should:

- **Phase 0**: Instrument `test-all.sh` with timing boundaries, run locally, record per-suite wall-clock for all 29 suites, classify top-5. Decide pivot to indexed sharding only if bun-vs-bash split is unbalanced.
- **Phase 1**: Implement A′ — refactor `ci.yml`'s `test` job into `test-bun` + `test-bash` + synthetic `test` aggregator. Move `validate-blog-links.sh` into the bun job to co-locate with `seo-aeo-drift-guard.test.ts`. Add `actions/cache` for `bun install`.
- **Phase 2**: Add Playwright `--shard=2` matrix to the `e2e` job + synthetic `e2e` aggregator (same pattern, separate job).
- **Phase 3**: Validation. Run the `test` and `e2e` jobs 5 times each on the PR branch; require 5/5 green and median wall-clock <130s for `test`, <80s for `e2e`.
- **Phase 4**: Capture `_site/` EACCES compound learning if encountered. Open follow-up issues for (a) Bun version probe, (b) optional `apps/web-platform/` internal split if A′ doesn't hit the <130s target.
