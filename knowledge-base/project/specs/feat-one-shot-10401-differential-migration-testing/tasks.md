# Tasks — feat: differential-migration-testing technique for users (#10401)

Plan: `knowledge-base/project/plans/2026-10-20-feat-differential-migration-testing-plan.md`
Branch: `feat-one-shot-10401-differential-migration-testing` | Issue: #10401 | Epic: #10397

## Phase 1 — Author the reference doc (RED-adjacent: write doc, then verify AC greps)

- [ ] 1.1 Create `plugins/soleur/skills/plan/references/differential-migration-testing.md` (~200 lines) per the plan's Technical Approach outline: plain `# Title`, no frontmatter, markdown links, ASCII, self-contained for plugin users (no `knowledge-base/`, `scripts/lib/`, or `apps/` paths — AC8 enforces). Sections: when-this-applies (rewrites/ports, explicitly not schema migrations); old-system-as-oracle / control arm; inputs (random + replayed live traffic; generator-entropy caution); normalize-before-compare (plus the over-normalization trap); whole-output-set bijection comparison; approved-changes ledger; the iterate-fix-diff loop (fast + deterministic); two harness shapes ("CLI diff" + "recorded-fixture replay" — AC2 anchors); incremental migrations (per-surface scoping); exit = delete the old system; sharp edges (mock below the seam; replayed traffic is production data — sanitize; recorded not resynthesized inputs; sampled-once corpus is not coverage). May name shipped siblings (`eval-harness`) and the article URL (`https://addyo.substack.com/p/agentic-verification`). Prose mention of property-based testing only — no link to `property-testing.md` unless `git show origin/main:plugins/soleur/skills/work/references/property-testing.md` resolves at work time.
- [ ] 1.2 Run markdownlint on the new file (`npx markdownlint-cli2 plugins/soleur/skills/plan/references/differential-migration-testing.md`).

## Phase 2 — Pointer edits

- [ ] 2.1 In `plugins/soleur/skills/plan/references/plan-issue-templates.md`, append the identical pointer sentence after the pyramid-layer line in each of the three `## Test Scenarios` blocks (near lines ~211, ~445, ~701). Exact line per plan §Edit surface 2 (uses the `${CLAUDE_PLUGIN_ROOT}`-form link). Do NOT add headings, reuse `pyramid layer`/`pyramid-justified` tokens, or match `^- \*\*If this (lands broken|leaks)`.
- [ ] 2.2 Run markdownlint on `plan-issue-templates.md`.

## Phase 3 — Verification

- [ ] 3.1 AC battery: run every grep/count in the plan's `## Acceptance Criteria` (AC1–AC4, AC6, AC8) and record outputs.
- [ ] 3.2 `bash plugins/soleur/test/test-pyramid-fixtures.test.sh` — exits 0 (AC5).
- [ ] 3.3 `bun test plugins/soleur/test/components.test.ts plugins/soleur/test/observability-schema-parity.test.ts plugins/soleur/test/plan-skeleton-checkpoint.test.ts` — green (AC3 census + AC5 pins).
- [ ] 3.4 Negative control: on a scratch copy, remove the three pointer lines and confirm the reachability census reds naming `plan/references/differential-migration-testing.md` (plan Test Scenarios, "coverage-negative control").
- [ ] 3.5 Run the affected-suite gate (`scripts/test-all.sh --affected` or the declared-edge consumer suites) and markdownlint across the diff.

## Phase 4 — Ship

- [ ] 4.1 PR body `Closes #10401`; labels `semver:patch` (plugin docs change), `type/feature`, `domain/engineering`; watch for merge race with #10400's `plan-issue-templates.md` edits (trivial textual conflict if both land; re-resolve pointers on rebase).
