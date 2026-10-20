---
title: "feat: differential-migration-testing technique for users (Epic #10397 child 4)"
date: 2026-10-20
slug: feat-differential-migration-testing
branch: feat-one-shot-10401-differential-migration-testing
issue: 10401
closes: 10401
type: feat
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

## Overview

Ship the differential-migration-testing technique to Soleur plugin users: a reference doc teaching the old-system-as-oracle loop for rewrites/migrations (normalize non-semantic diffs, random plus replayed inputs, approved-changes ledger, iterate-fix-diff cycle, delete-the-old exit criterion) plus pointer edits so `plan`/`work` migration-type features cite it. The pattern is practiced internally (`*-drift` workflows, rehearsal harnesses, eval-harness control-vs-treatment arms) but nothing shipped teaches it for user code.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 10401 --json state` → `OPEN`; `closedByPullRequestsReferences` empty. Premise live.
- Epic #10397 `OPEN`; siblings: #10398 `CLOSED` via PR #10624 (merged 2026-10-20), #10399 `CLOSED` via PR #10666 (merged 2026-10-20), #10400 `OPEN` with in-flight PR #10718 — matches the pipeline brief exactly.
- Issue evidence claim verified on `origin/main`: `eval-harness` (`plugins/soleur/skills/eval-harness/SKILL.md`) is a promptfoo control-vs-treatment grid over **skill/agent prompt edits** — its configs (`promptfooconfig-*.yaml`), baselines (`prompts/*-baseline.txt`), and golden tasks (`tasks/*.jsonl`) all target Soleur classifier prose, never user codebases. The "skill edits only" claim holds.
- Repo-internal analogues verified on `origin/main`: nine `*-drift*` workflows under `.github/workflows/` (terraform, marketplace, dev-migration, domain-model, sentry-alert, prod-version, kb-drift-walker, devin-docs, inngest-config), plus rehearsal machinery (`git-data-rung2-rehearsal`, `inngest-provision-rehearsal`, `rung2-rehearsal/` Terraform roots). The old-vs-new comparison pattern exists internally — it is simply not packaged.
- Gap claim verified: `grep -rln -i "differential" plugins/soleur/skills/` hits only `preflight/scripts/parse-form-a.awk`, `review/SKILL.md` (a different sense — diff *review*), and `plan/references/plan-sharp-edges.md`. No shipped artifact teaches the technique. `review/references/generated-input-oracle-surfaces.md` (merged via #10398) covers generated-input *oracle extraction* for test review — adjacent vocabulary, different subject (it reviews a test's coverage of its input set; it does not teach running two systems side-by-side).
- ADR-corpus check for the proposed mechanism (grep `differential|migration test|oracle` over `knowledge-base/engineering/architecture/decisions/`): no ADR rejects or claims this ground. ADR-293 sanctions generated-input testing generally; a reference doc is a packaging decision below ADR altitude. No mechanism conflict.
- Primary source fetched: the cited Addy Osmani *Agentic Verification* article (2026-10-14) — the differential-testing section confirms the four technique elements verbatim: old system as oracle, random + replayed-live-traffic inputs, approved-changes list ("keeps 'different' from becoming an acceptable state"), and delete-the-old ("the diff harness gives you the confidence to wipe the old system away; keeping both systems running is twice the work").
- **Terminology hedge (glossary):** `glossary.md` has no entry for "migration" in the rewrite sense; the repo's dominant sense is DB schema migrations (`supabase/migrations/*.sql`, `defect-classes-migrations.md`). The doc must disambiguate itself: it covers system rewrites/ports, not schema migrations. Hedge carried into the doc's "when this applies" section.

### Property List (Phase 0.6b)

Discrete properties the ask decomposes to (observable outcomes):

1. A shipped artifact prescribes the differential loop with **concrete harness shapes** — a CLI-diff harness and a recorded-fixture-replay harness (the issue's two named shapes).
2. `plan`/`work` migration-type features can cite the technique — the issue names the mechanism: a pointer in plan's references surface.
3. The approved-changes-list convention is included, so "different" never silently becomes acceptable.
4. The doc is self-contained for plugin users — no repo-internal links (`knowledge-base/`, `scripts/`, `apps/` do not ship); shipped siblings (`eval-harness`, the #10400 `property-testing` reference once merged) may be named by skill/file name.
5. README component counts unchanged — a reference file is not a component.

### Cut List (Phase 0.6b)

- **A dedicated slim skill** (`plugins/soleur/skills/differential-migration-testing/SKILL.md`) — buys discoverability-by-description over a reference, but the issue itself sizes this as "new reference (or a slim skill) … ~1 new file + pointer edits (~200 lines)", and a skill adds registration (`plugins/soleur/docs/_data/skills.js` SKILL_CATEGORIES), a `description:` against `SKILL_DESCRIPTION_WORD_BUDGET`, and component-table churn for zero added property: the technique is guidance text a migration plan cites, not an orchestrated procedure an agent invokes. Reference doc is the first minimalism-ladder rung that holds. Cut.
- **Extending `eval-harness` to cover user-code migrations** — its substrate is promptfoo arms over classifier prompts; retrofitting arbitrary user repos is a different product. The issue says "reuse the eval-harness arm pattern where applicable" — the *pattern* (control vs treatment arm, the old system playing the control role) is carried into the doc's harness shapes; the harness itself is not extended. Cut as mechanism, kept as pattern.
- **A `work/SKILL.md` or `plan/SKILL.md` pointer line** — measured headroom (2026-10-20, `lint-skill-body-budget.py --base <merge-base>` + `plugins/soleur/test/skill-body-budget.json`): `work` 359,071/359,189 B → **118 B** and already ~fully claimed by in-flight sibling #10400's planned edit (~110 B); `plan` 119,966/120,000 B → **34 B**; `review` 475,921/475,921 B → **0 B**. A SKILL.md pointer cannot fit without a delta-neutral trim and would contend with the sibling's claim. Cut — the uncapped `plan/references/plan-issue-templates.md` pointer satisfies the issue's named surface literally.
- **A drift pin on the pointer lines** — redundant: `components.test.ts`'s references-reachability census already fails CI if `differential-migration-testing.md` is named from nowhere, and it is the naming (the pointer itself) that the pin would guard. The guard exists; adding a second one is gold-plating. Cut.

### Repo Research

- **`plugins/soleur/skills/plan/references/`** — plan-time reference docs live here; `plan/SKILL.md` loads them via `Read … now` directives. `plan-issue-templates.md` is the unconditional one (plan Step 4 reads it on every run) and carries the three `## Test Scenarios` template blocks — the surface where a migration feature's test strategy is authored.
- **Pin surface over `plan-issue-templates.md`** (verified, none block an in-block sentence):
  - `plugins/soleur/test/test-pyramid-fixtures.test.sh` — asserts exactly 3 `^## Test Scenarios` blocks, `pyramid layer` count == 3, per-block `pyramid-justified` marker. A new sentence inside each block is safe; it must not introduce a `## ` heading, contain `pyramid layer`/`pyramid-justified` tokens, or add a 4th block.
  - `plugins/soleur/test/observability-schema-parity.test.ts` — pins the 3 `## Observability` yaml blocks key-set-equal to canonical; untouched.
  - `plugins/soleur/test/preflight-discoverability-test.test.ts` — pins a verbatim `credentials_required:` comment line; untouched.
  - `plugins/soleur/test/ship-incident-pir-gate.test.ts` — reads `^- \*\*If this (lands broken|leaks)` trigger lines and asserts exactly 2; the pointer line must NOT match that regex (it doesn't — different prefix).
  - `plugins/soleur/test/plan-skeleton-checkpoint.test.ts` — slices the file on `^## [A-Z ]+` template-tier headings; a bullet line adds no heading. Safe.
  - `scripts/lint-encryption-posture.py --check-templates` — validates encryption yaml blocks; untouched.
- **Reachability census** (`plugins/soleur/test/components.test.ts` "references/ files are reachable from their skill", #8302): every `references/*.md` must be named by basename from at least one other file in the same skill directory (walks depth < 2 — sibling `references/` files count). Naming `differential-migration-testing.md` from `plan-issue-templates.md` satisfies it with zero capped bytes.
- **`components.test.ts` "No backtick file references in skills"** — `` `references/…` `` in backticks reds the lint on SKILL.md files; the pointer uses markdown-link form (`[differential-migration-testing.md](./differential-migration-testing.md)`) regardless.
- **Affected-suite derivation** (`scripts/lib/test-affected-paths.sh`): `plan-issue-templates.md` is a declared edge of `test-pyramid-fixtures.test.sh` — editing it re-selects that suite automatically. New `plan/references/*.md` files are reached by the `components.test.ts` census suite.
- **Reference-file conventions** (from `work/references/` and `plan/references/` corpus): plain `# Title` opener, no frontmatter, kebab-case filename, markdown links, ASCII-preferred.
- **Sibling precedent (#10400, PR #10718 open):** `work/references/property-testing.md` + `plan-issue-templates.md` Test-Scenarios pointer lines + `work/SKILL.md` vocabulary edit + pin extension. This plan mirrors the "doc + templates pointer" half and drops the capped-SKILL.md half.
- **Merge-order sensitivity with #10400:** if #10401 lands first, `property-testing.md` does not yet exist on main — the new doc must not hard-link it. If #10400 lands first, a see-also link becomes legal at work time. Resolution: prose mention of the sibling technique by name, no file link; an optional link is a work-phase refinement gated on `git show origin/main:plugins/soleur/skills/work/references/property-testing.md` resolving.

### Internal Analogues (the pattern practiced, not packaged)

- `.github/workflows/scheduled-dev-migration-drift.yml` + `scheduled-terraform-drift.yml` et al. — scheduled comparison of a derived surface against its source; the "diff what should agree" instinct, infra-shaped.
- `apps/web-platform/infra/rung2-rehearsal/` + `git-data-rung2-rehearsal` workflow — provision a replica and exercise it before cutover; the rehearsal arm.
- `eval-harness` — control-vs-treatment arm pair measuring a delta; in the user-facing technique the old system plays the control-arm role verbatim.

### Learnings / Conventions Applied

- `knowledge-base/project/learnings/best-practices/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md` — the in-repo instance of the exact failure class the technique prevents: a TS normalizer and its SQL backfill twin diverged on operator precedence (`.git/` stripping order) and on idempotence; four review agents caught what a side-by-side diff over generated inputs would have caught mechanically. Concrete "why this pays" evidence — cite the *shape* of the incident in the doc without repo-internal links (the doc is shipped).
- `knowledge-base/project/learnings/2026-10-02-a-subset-replay-proof-certifies-a-merge-that-reverts.md` — a replay/diff proof must be a **bijection, not a subset**: proving "new ⊆ old" leaves deletions invisible; compare outputs as equal sets, and `comm`-vs-locale and rename-detection traps apply to any diff harness. Carries directly into the doc's "compare the whole output set" guidance.
- `knowledge-base/project/learnings/test-failures/2026-10-20-generated-input-oracle-extraction-window-and-bash-random-outvar.md` (merged via #10398) — generated-input oracles fail open through three surfaces: extractor grammar coverage, member validity, and generator entropy (bash `$RANDOM` across `$( )` boundaries draws one value forever). The doc's "random inputs" section inherits all three cautions in user-facing form.
- `knowledge-base/project/learnings/best-practices/2026-10-20-fastcheck-v4-substitutions-and-json-canonical-oracle.md` — canonicalized-JSON comparison is the proven normalizer shape for structured outputs (sorted keys, stable stringify before diff).
- Constitution: reference files take no frontmatter; markdown links for file references; kebab-case filenames; plan filename `YYYY-MM-DD-<type>-<name>-plan.md`.

### Community Discovery (Phase 1.5) + Functional Overlap (Phase 1.5b)

- Stack scan: no `Cargo.toml`/`mix.exs`/`go.mod`/`Package.swift`/`build.gradle`/`composer.json`/`pubspec.yaml` at repo root — no uncovered stacks; agent-finder skipped.
- Functional overlap (inline — no Task spawn in subagent context), queries `differential testing` / `migration testing` across api.claude-plugins.dev, claudepluginhub.com, anthropics marketplace, and the trailofbits/skills plugin listing:
  - `trailofbits/skills` `differential-review` — **different sense**: security review OF a git diff (blast radius, callers, coverage of changed lines), not old-vs-new system output comparison.
  - `homologia` — pinned-manifest Solidity vector checker; "the comparison step is not built yet"; niche single-domain.
  - `migrate-to-shoehorn`, `migration-helper`, `migration-wizard`, `migration-patterns-plugin` — codemod/framework-migration executors; none teaches a verification loop.
  - **Verdict: no community artifact covers the old-system-as-oracle migration loop.** The technique is assembled from named practices, not shipped as a plugin anywhere found.

### External Research Decision (Phase 1.6)

Skipped beyond the primary source — the technique's authoritative content is the article the issue cites (fetched and quoted above); local context is strong (sibling machinery + learnings on disk). A docs-only change; further external research adds nothing.

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (one-shot path; no brainstorm ran). Reconciling the *issue's* claims against the tree:

| Issue claim | Reality on `origin/main` | Plan response |
|---|---|---|
| "`eval-harness` does control-vs-treatment for skill edits only" | Holds — promptfoo arms over classifier prompts; zero user-code scope | Reuse the arm *pattern* (old system = control arm) in the doc; do not extend the harness |
| "Repo-internal analogues exist (`*-drift` workflows, `git-data-rung2-rehearsal`)" | Holds — 9 drift workflows + rehearsal roots verified | Cited as internal proof in Research Insights; NOT linked from the shipped doc (repo-internal) |
| "New reference (or a slim skill) … ~1 new file + pointer edits (~200 lines)" | Slim skill cut at 0.6b; reference is the minimal rung | 1 new reference + 3 identical pointer lines in `plan-issue-templates.md` |
| "pointer in plan references" | `plan-issue-templates.md` IS the unconditionally-read plan references surface; capped SKILL.md files cannot host a pointer (34 B / 118 B contested headroom) | Pointer lands in the templates file's three `## Test Scenarios` blocks |

## Open Code-Review Overlap

`gh issue list --label code-review --state open` against the touched paths → one hit:

- **#4133 — follow-through(#4116): Schema parity test for `## Observability` block** — **Acknowledge.** Same file (`plan-issue-templates.md`), disjoint concern (it proposes a parity test over the `## Observability` 5-field schema; this plan edits only `## Test Scenarios` prose and adds no schema fields). Same disposition sibling #10400 recorded; the issue stays open for its own cycle.

## Problem Statement

Soleur's shipped workflow has no answer for the highest-risk class of feature an agent can be handed: *replace a running system*. Example tests say what should happen on cases a human imagined; a rewrite's classic failure is passing the new suite while diverging from the old system in many small, undocumented ways — the spec-vs-behavior gap users actually depend on. The fix is a named, boring technique — run old and new side-by-side on generated and replayed inputs, normalize non-semantic diffs, ledger every intended divergence, and delete the old system when the diff is clean — which Soleur practices internally (drift workflows, rehearsals, eval arms) but does not ship. A plugin user planning a migration today gets no pointer to it.

## Proposed Solution

Two documentation deliverables inside `plugins/soleur/`:

1. **FR-1 — `plugins/soleur/skills/plan/references/differential-migration-testing.md`** (~200 lines) — the technique doc: when it applies (rewrite/port/replacement of a runnable system — explicitly not schema migrations); the old-system-as-oracle framing (the old system is the control arm); input strategy (random generation + replayed live-traffic sample; property = "new outputs equal old outputs"); normalization rules (only what carries no semantic weight — ordering, timestamps, generated IDs, whitespace — and never so much that real divergence is normalized away); the approved-changes ledger (every intentional divergence recorded with a reason); the iterate-fix-diff loop; and the exit criterion (delete the old system — the harness is the confidence to wipe it; running both forever is twice the work with two failure modes). Concrete harness shapes: a CLI-diff harness (run both commands over a generated corpus, normalize, compare the full output set as a bijection) and a recorded-fixture replay (captured request/traffic fixtures replayed against both systems). Loop must be fast and deterministic — a flaky or slow loop teaches the agent to retry rather than fix.
2. **FR-2 — Pointer lines in `plan-issue-templates.md`** — one identical conditional sentence appended after the pyramid-layer line in each of the three `## Test Scenarios` template blocks: when the feature rewrites, ports, or replaces a running system, the plan's scenarios prescribe the differential loop and cite the doc. The templates file is read at plan Step 4 on every `soleur:plan` run, so the pointer reaches every migration-type plan; the generated plan carries the citation into `soleur:work`.

## Technical Approach

### Edit surface 1 — `plugins/soleur/skills/plan/references/differential-migration-testing.md` (new)

Doc outline (~200 lines, plain `# Title`, no frontmatter, markdown links, self-contained — no `knowledge-base/`, `scripts/`, `apps/` paths; may name shipped siblings `eval-harness` and the article URL):

1. **When this applies** — rewrites/ports/replacements where the old system still runs; NOT schema migrations (disambiguation the glossary lacks).
2. **The oracle** — old system is the control arm; a mismatch is a bug in the new system or an intended change that must land in the ledger. The article's framing: equivalent to property-based testing where the property is output equivalence.
3. **Inputs** — random generation across the input domain PLUS replayed live-traffic samples; hand-picked cases miss rare edges. Generated-input cautions: generator entropy (do not draw through a boundary that freezes the stream), input validity, full-domain coverage — in user-facing form.
4. **Normalize before comparing** — ordering without semantic weight, timestamps, generated IDs, whitespace; the inverse trap: over-normalization hides real divergence, so normalize only categories a human has declared non-semantic.
5. **Compare the whole output set** — bijection, not subset; a dropped output reads as clean under a subset check.
6. **Approved-changes ledger** — every accepted divergence recorded with its reason; the ledger is what keeps "different" from becoming silently acceptable, and it becomes the migration's release-note/breaking-change list.
7. **The loop** — tweak → run → review mismatches → fix or ledger → repeat; keep it fast and deterministic.
8. **Two harness shapes** — (a) CLI diff: both systems callable as commands, corpus through both, normalize, `diff`; (b) recorded-fixture replay: captured traffic/requests replayed against both, outputs compared. Both are the eval-harness control-vs-treatment shape with the old system as control.
9. **Exit: delete the old system** — when the diff is clean modulo the ledger and every behavior is moved, remove the old system and the harness with it; keeping both is twice the work and two ways to break.
10. **Incremental migrations** — when the migration is partial (strangler-fig, per-endpoint cutover), scope the harness per migrated surface: the diff compares only the slices the new system owns, and each cut slice retires its old-system path.
11. **Sharp edges** — mocks must sit below the comparison seam (a mock above it makes its own output the fixture); replayed traffic is production data — sanitize or scope the replay corpus before it leaves the capture environment; replay inputs must be recorded, not resynthesized; a green diff over a sampled-once corpus is not coverage.

### Edit surface 2 — `plugins/soleur/skills/plan/references/plan-issue-templates.md`

Append ONE identical sentence after the pyramid-layer line in each of the three `## Test Scenarios` blocks (lines ~211, ~445, ~701), so all three detail levels carry it:

```text
If the feature rewrites, ports, or replaces a running system, prescribe the differential loop — run old and new side-by-side on generated and replayed inputs with the old system as oracle — and cite [differential-migration-testing.md](${CLAUDE_PLUGIN_ROOT}/skills/plan/references/differential-migration-testing.md).
```

The link uses the `${CLAUDE_PLUGIN_ROOT}` form — the canonical citation form inside skill content (asserted by `plan-skeleton-checkpoint.test.ts` for `plan-founder-check.md`) — because these template blocks are fenced and copied verbatim into generated plans: a `./` relative link would resolve nowhere from `knowledge-base/project/plans/` in the user's repo, while `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin install for the consuming agent. The basename substring still satisfies the reachability census.

Constraints honored by this placement: inside existing blocks (no new `## ` heading, no `pyramid layer`/`pyramid-justified` token reuse, no `^- \*\*If this (lands broken|leaks)` prefix match, no `^#\d` line-start); markdown-link form, no backtick path; identical ×3 keeps per-block marker symmetry the pin suite measures.

## Observability

The shipped surface is documentation consumed by agents; "observability" is whether the landed guidance is mechanically discoverable in the tree — the references-reachability census is the enforcement layer and this block is the declared probe.

```yaml
liveness_signal:
  what: "`differential-migration-testing.md` exists under plugins/soleur/skills/plan/references/ and is named from plan-issue-templates.md (the pointer)"
  cadence: "per-PR: components.test.ts references-reachability census runs on every diff touching plugins/soleur/"
  alert_target: "CI check failure (plugin test shard)"
  configured_in: "plugins/soleur/test/components.test.ts (pre-existing census — no new guard added by this diff)"
error_reporting:
  destination: "CI job log — census failure names the orphaned reference path"
  fail_loud: "yes — orphan references are a suite failure, not a warning"
failure_modes:
  - mode: "reference file orphaned (pointer line deleted from all three blocks later)"
    detection: "components.test.ts references-reachability census"
    alert_route: "CI red on the next diff touching the plugin shard"
  - mode: "a Test Scenarios block loses the migration pointer while another keeps it"
    detection: "AC3 grep count == 3 verified in this diff's own verification battery"
    alert_route: "review-time AC check"
  - mode: "templates edit silently breaks a pinned marker (block count, pyramid lines, Observability yaml keys)"
    detection: "test-pyramid-fixtures.test.sh + observability-schema-parity.test.ts + plan-skeleton-checkpoint.test.ts, all re-selected by the affected gate"
    alert_route: "CI red"
logs:
  where: "CI job log (suite assertion lines)"
  retention: "GitHub Actions retention"
discoverability_test:
  command: "grep -c 'differential-migration-testing.md' plugins/soleur/skills/plan/references/plan-issue-templates.md"
  expected_output: "3"
```

## User-Brand Impact

- **If this lands broken, the user experiences:** a migration-type plan either never learns the technique exists (the gap persists silently — same as today) or learns a misprescribed version — e.g. advice that over-normalizes diffs, teaching the user's agent to normalize real behavioral divergence away and ship a rewrite whose spec-vs-behavior drift was invisible by construction.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — docs-only change inside shipped skill references; no credentials, no user data, no runtime behavior.
- **Brand-survival threshold:** none

## Files to Create

- `plugins/soleur/skills/plan/references/differential-migration-testing.md` — the shipped technique reference (~200 lines).

## Files to Edit

- `plugins/soleur/skills/plan/references/plan-issue-templates.md` — one identical conditional pointer sentence appended after the pyramid-layer line in each of the three `## Test Scenarios` blocks (~3 lines added).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "New reference (or a slim skill) covering: normalize non-semantic diffs, random + replayed-live-traffic inputs, approved-changes ledger, iterate-fix-diff loop, and the \"delete the old system\" exit criterion." [issue #10401] | FR-1 / Files-to-Create `differential-migration-testing.md` | mapped |
| 2 | "Reuse the eval-harness arm pattern where applicable." [issue #10401] | FR-1 doc §harness shapes (control-vs-treatment arm pattern; old system as control) | mapped |
| 3 | "A shipped artifact prescribes the differential loop with concrete harness shapes (CLI diff, recorded-fixture replay)." [issue #10401] | FR-1 doc §"Two harness shapes" / AC1, AC2 | mapped |
| 4 | "`plan`/`work` migration-type features can cite it (pointer in plan references)." [issue #10401] | FR-2 / Files-to-Edit `plan-issue-templates.md` / AC3 | mapped |
| 5 | "Includes the approved-changes-list convention so \"different\" never becomes acceptable silently." [issue #10401] | FR-1 doc §ledger / AC4 | mapped |
| 6 | "~1 new file + pointer edits (~200 lines)" [issue #10401] | Constraint — honored: 1 new file + 3 pointer lines | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `plan/references/differential-migration-testing.md` | asks 1, 2, 3, 5 | asked |
| `plan-issue-templates.md` pointer lines ×3 | ask 4 | asked |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur`
- Planned files: 2 | Estimated changed lines: ~210
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — `plugins/soleur/skills/plan/references/differential-migration-testing.md` exists and names all five technique elements: `grep -ci 'oracle' <file>` >= 1, `grep -ci 'normaliz' <file>` >= 1, `grep -ci 'approved' <file>` >= 1, and `grep -i 'old system' <file>` hits the delete-the-old exit criterion.
- [ ] AC2 — the doc prescribes both concrete harness shapes by their named anchors: `grep -c 'CLI diff' <file>` >= 1 and `grep -c 'recorded-fixture replay' <file>` >= 1, and the control-vs-treatment arm pattern is named (`grep -c 'control' <file>` >= 1 with the old system as the control arm).
- [ ] AC3 — `grep -c 'differential-migration-testing.md' plugins/soleur/skills/plan/references/plan-issue-templates.md` returns `3` (one pointer per `## Test Scenarios` block), and `bun test plugins/soleur/test/components.test.ts` passes the references-reachability census.
- [ ] AC4 — the approved-changes convention is load-bearing, not decorative: the doc states that every accepted divergence is recorded with a reason, and that "different" without a ledger entry is a bug in the new system.
- [ ] AC5 — template pins intact: `bash plugins/soleur/test/test-pyramid-fixtures.test.sh` exits 0; `^## Test Scenarios` count in `plan-issue-templates.md` remains `3`; `pyramid layer` count remains `3`; `bun test plugins/soleur/test/observability-schema-parity.test.ts plugins/soleur/test/plan-skeleton-checkpoint.test.ts` green.
- [ ] AC6 — `git diff origin/main...HEAD -- plugins/soleur/skills/plan/SKILL.md plugins/soleur/skills/work/SKILL.md plugins/soleur/skills/review/SKILL.md plugins/soleur/docs/_data/skills.js` is empty (no capped-file edits, no component registration — a reference is not a component).
- [ ] AC7 — markdownlint clean on all touched `.md` files.
- [ ] AC8 — self-containment: `grep -nE 'knowledge-base/|scripts/lib/|apps/web-platform' plugins/soleur/skills/plan/references/differential-migration-testing.md` returns nothing (the shipped doc carries no repo-internal links).

## Test Scenarios

Label each scenario's pyramid layer — `unit`, `integration`, or `e2e` — and prefer the lowest layer that exercises the behavior.

- **AC verification battery (unit — grep asserts):** Given the merged diff, when the AC1–AC4/AC6/AC8 grep commands run, then each returns its expected hit/count/absence.
- **Pin regression (unit):** Given the templates edit, when `test-pyramid-fixtures.test.sh` runs, then it exits 0 with the `## Test Scenarios` count, `pyramid layer` count, and per-block `pyramid-justified` marker assertions all green.
- **Census (unit):** Given the new reference file, when `bun test plugins/soleur/test/components.test.ts` runs, then the "every references/*.md is named from its skill" test passes (the basename appears in `plan-issue-templates.md`).
- **Coverage-negative control (unit):** Given a scratch copy where the three pointer lines are removed, when the census runs, then it reds with `plan/references/differential-migration-testing.md` in the orphan list — the enforcement is real, not presumed.
- **Docs hygiene (unit):** markdownlint on touched files; no `description:` frontmatter delta (skill description budget untouched).

## Domain Review

**Domains relevant:** Engineering, Product (fail-closed expansion — Product/UX tier resolved NONE below)

### Engineering

**Status:** reviewed (inline — subagent context, no Task spawn; CTO Rule interface executed for the placement fork)
**Assessment:** Blast radius is prose-only: one new reference file plus three identical sentences inside existing template blocks. The structural risks are all pin/census mechanics — the five pins over `plan-issue-templates.md` are enumerated in Research Insights and every one is compatible with an in-block sentence (no new `## ` heading, no pinned token reuse, no trigger-regex prefix match). The placement fork (doc home + pointer surface) was ruled technically: `plan/references/` because the issue names "pointer in plan references", the templates file is the unconditionally-read plan surface, and every capped SKILL.md lacks headroom (34 B / 118 B contested / 0 B). Recorded in `decision-challenges.md`.

### Product/UX Gate

**Tier:** none — no UI surface in Files to Create/Edit (all paths are `plugins/soleur/skills/plan/references/*.md`; the glob superset contains no `*.md` member; the change is agent-guidance prose)

No Product/UX pipeline runs at NONE tier.

## Non-Goals

- No `work/SKILL.md`, `plan/SKILL.md`, or `review/SKILL.md` edits — byte-ceiling headroom makes them infeasible without a delta-neutral trim, and the issue's named pointer surface is plan references. (A work-surface pointer is a legal follow-up once #10400's headroom claim resolves.)
- No extension of `eval-harness`, the drift workflows, or the rehearsal machinery — the arm *pattern* is reused, the machinery is not generalized to user repos.
- No review-skill check that migration diffs cite the technique — zero headroom in `review/SKILL.md`; discovery flows through plan-time citation.
- No schema-migration (Supabase/`*.sql`) guidance — the doc covers system rewrites; schema migrations already have `defect-classes-migrations.md` and the migration runbooks.

## Success Metrics

- `git grep -l 'differential' plugins/soleur/skills/plan/references/` returns `differential-migration-testing.md` post-merge (today: the only `differential` hits under `plugins/soleur/skills/` are the unrelated diff-*review* senses).
- First plugin-user migration plan citing the doc is unmeasurable internally — proxy: the pointer sentence exists in all three template blocks (AC3) and the census holds (AC3).

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| Pointer line breaks a templates pin (block count, `pyramid layer` count, per-block markers, section slicing, trigger regex) | Pin surface enumerated in Research Insights; the line carries no `## ` heading, no `pyramid layer`/`pyramid-justified` tokens, no `^- \*\*If this` prefix; AC5 runs the suites. |
| New reference orphaned (census failure) | AC3 asserts the basename is named 3× from a same-skill file; the negative-control scenario proves the census actually catches the orphan. |
| Doc teaches over-normalization (real divergence normalized away) | Content rule in the doc: normalize only categories a human declares non-semantic; the ledger is the escape valve for everything else; advisor consult + review panel weigh the wording. |
| Doc links `#10400`'s `property-testing.md` before it merges | Hard rule: prose mention only, no file link; work-phase check `git show origin/main:plugins/soleur/skills/work/references/property-testing.md` before adding a see-also. |
| "Migration" read as schema migration | Doc opens with the disambiguation; glossary hedge recorded in Premise Validation. |
| Merge-order race with #10400 on `plan-issue-templates.md` (both append inside the same three blocks) | Different line positions (theirs attaches to the property-guidance wording; this appends after the pyramid-layer line); conflict is trivially resolvable — noted for the ship phase. |

## Documentation Plan

The deliverable IS documentation. No README/`AGENTS.md` component-count changes (AC6 asserts the diff is empty there); no `docs/_data/skills.js` registration (references are not components); no CHANGELOG entry authored in this plan (the release flow owns it).

## References & Research

### Internal References

- Issue: #10401; epic #10397; siblings #10398 (PR #10624, merged), #10399 (PR #10666, merged), #10400 (PR #10718, in-flight).
- Pin surfaces: `plugins/soleur/test/test-pyramid-fixtures.test.sh`, `components.test.ts` (reachability census + backtick-ref lint), `observability-schema-parity.test.ts`, `plan-skeleton-checkpoint.test.ts`, `preflight-discoverability-test.test.ts`, `ship-incident-pir-gate.test.ts`.
- Byte ceilings: `plugins/soleur/test/skill-body-budget.json` + `scripts/lint-skill-body-budget.py`.
- Learnings: `2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md`, `2026-10-02-a-subset-replay-proof-certifies-a-merge-that-reverts.md`, `2026-10-20-generated-input-oracle-extraction-window-and-bash-random-outvar.md`, `2026-10-20-fastcheck-v4-substitutions-and-json-canonical-oracle.md`.

### External References

- Addy Osmani, "Agentic Verification" (2026-10-14): differential-testing section — old system as oracle, random + replayed inputs, approved-changes list, delete-the-old exit. `https://addyo.substack.com/p/agentic-verification` (fetched 2026-10-20; section quoted in Premise Validation).
- Community registry scan (functional overlap): no covering artifact; closest neighbors are different senses (`differential-review` = security diff-review; `homologia` = pinned Solidity vectors).
