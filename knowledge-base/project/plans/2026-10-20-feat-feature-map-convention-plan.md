---
title: "feat: feature-map artifact convention for user codebases (Epic #10397 child 5)"
date: 2026-10-20
slug: feat-feature-map-convention
branch: feat-one-shot-10402-feature-map-convention
issue: 10402
closes: 10402
type: feat
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-20
**Passes applied (in-process, sequential per harness):** halt gates §4.6–4.12 (all pass — User-Brand section valid at `none`, Observability schema valid, PAT grep clean, lint-guard-contract green 3/3, Scope Check 1 unfenced + compliant), precedent-diff §4.4 (convention doc follows the plan/references canonical form from #10401; map schema follows the #10666 artifact — no novel pattern), verify-the-negative §4.45 (all negative claims re-probed and confirmed), spec-flow gap pass, in-process review panel (DHH/Kieran/simplicity/CTO-devex).

### Key findings applied by the deepen pass

1. **Partial-map fallback semantics** — a maintained map is authoritative *per-route*, never a reason to skip an unmapped route; §3's fallback sentence now names the file→route table as fallback for repos without a map AND for routes a partial map does not cover.
2. **Uniform citation shape** — ux-audit/reproduce-bug edits now prescribe the identical parenthetical as the qa line so all four citations share one sweepable phrasing.
3. **`discoverability_test` made deterministic** — the `grep -c`/literal-"2" pair (count nondeterministic vs substring-matching) replaced with `grep -q … && echo map-convention-wired`.
4. **Plan-review findings applied** — fenced-example copy warning in the doc outline; §5b reports `written`/`refreshed`/`skipped`+reason in the Step 8 summary. One taste finding (trim the five-arm lint sketch) persisted to `decision-challenges.md`, kept.

### New considerations discovered

- `qa` is the only byte-capped file in the edit set (36,900/37,000 B) — its pointer must be an in-place line generalization, verified by `lint-skill-body-budget.py` at work time.
- `test-browser/` gains its first `references/` member — the census is the enforcement, proven by AC6's negative control.

## Overview

Ship a feature-map convention to plugin users: a canonical, committed `docs/feature-map.md` that navigation-driven skills (`test-browser`, `qa`) read as their navigation source of truth — with a write-or-refresh-on-run producer inside `test-browser` and file-to-route mapping as the fallback when no map exists. The artifact shape and durability lessons mirror the self-side implementation delivered for `apps/web-platform/test/feature-map.md` (#10399, PR #10666), generalized to a framework-tolerant user-repo convention rather than a shipped route scanner.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 10402` → `OPEN`, `enhancement`/`type:feature`/`domain:engineering`/`p3-low`. Premise live.
- Epic #10397 `OPEN`; children: #10398 CLOSED (#10624), #10399 CLOSED (#10666), #10400 OPEN, #10401 CLOSED (#10727), #10402 OPEN (this), #10403 OPEN, #10404 OPEN. No sibling covers the user-side feature map — #10404 (`verification-scaffold`) ships generic lint/hook gates, a disjoint surface.
- Self-side pattern verified on `origin/main`: `apps/web-platform/test/feature-map.md` (260 lines, `## \`/route\`` entries + `## Deliberately unmapped`), `scripts/lint-feature-map-coverage.sh` (282 lines, five arms + anti-vacuity + fixture seam `SOLEUR_FEATURE_MAP_ROOT`), both merged 2026-10-20 via #10666; consumer wiring merged same day via #10726 (`qa`, `ux-audit`, `reproduce-bug` SKILL.md one-line citations; `test-browser` §3 "Repo feature map first" shipped in #10666).
- Issue's cited files confirmed: `test-browser` §3 `file_to_route_mapping` exists (SKILL.md:129-156) and already prefers a map when present; the soleur-path mention is hardcoded in four skills — a user repo carrying `docs/feature-map.md` would currently be unrecognized (the gap this plan closes).
- ADR-corpus check for the proposed mechanism (grep `feature.map|feature-map` over `knowledge-base/engineering/architecture/decisions/`): zero hits — no ADR claims or rejects this ground. A skill-reference convention is packaging below ADR altitude.
- Cited issue #10399 is closed by a merged PR — that is the *pattern source*, not a stale premise: #10402 explicitly builds on it ("Sibling gap #10399 covers Soleur's own map" — now delivered).

### Property List (Phase 0.6b)

1. A plugin user's repo ends up with a committed feature map — a user-POV route inventory (route / entry / selectors / expects / auth / gotchas + reasoned exemptions) that agents read before browser runs.
2. `test-browser`/`qa` cite the map as navigation source when present and fall back to file→route mapping when absent (the AC verbatim).
3. The map does not silently rot — drift guidance exists (regenerate-on-run producer and/or lint hint), per the AC.
4. The convention is framework-tolerant: user repos are not all Next.js `app/**/page.tsx` — route enumeration is the agent's job against the repo's own route-file shapes, not a shipped glob.
5. README component counts and the skill description budget are unchanged — a reference doc is not a component.

### Cut List (Phase 0.6b)

- **Standalone scaffold skill** (`plugins/soleur/skills/feature-map/SKILL.md` or a `constraint-scaffold` sibling) — buys a named invocation for scaffold-once, but its producer (scan route files → emit a skeleton map) is framework-bound, violating Property 4: a shipped CLI cannot discover routes in arbitrary stacks, while the agent inside `test-browser` enumerates them by reading the repo. A new skill also costs `docs/_data/skills.js` registration + `SKILL_DESCRIPTION_WORD_BUDGET` + component-table churn for zero added property — the same ruling #10401 recorded for "reference doc vs slim skill" (`2026-10-20-copied-template-links-and-coverage-negative-controls.md`). Cut; the issue's own "~1 file + SKILL.md edits (~150 lines)" sizing agrees.
- **Generator CLI / shipped generic lint script** — the self-side lint's coverage direction is bound to `apps/web-platform/app`/`page.tsx`; a portable version can only check map grammar (shape arms), not route↔map coverage, which is where the drift risk lives. The convention doc instead teaches refresh-on-run (producer covers exercised routes) + the update contract + describes the five-arm lint pattern for users to adapt with their own route glob — the AC's "lint hint". Cut.
- **A new `description:` edit to any SKILL.md** — no candidate; `SKILL_DESCRIPTION_WORD_BUDGET` untouched.
- **Editing `plan`/`work`/`review`/`ship` SKILL.md** — measured ceilings (`plugins/soleur/test/skill-body-budget.json`): `qa` 36,900/37,000 B (~100 B headroom — its pointer edit must fit inside it or carry a delta-neutral trim); `test-browser`, `ux-audit`, `reproduce-bug` are uncapped. The AC names only `test-browser`/`qa` — no lifecycle-skill edits proposed.

### Repo Research

- **`plugins/soleur/skills/test-browser/SKILL.md`** (15,284 B, uncapped) — §3 "Map Files to Routes" carries the `file_to_route_mapping` block with "Repo feature map first … this repo keeps one at `apps/web-platform/test/feature-map.md` … the generic table below is the fallback" (lines 131-154). The map-first arm exists; the user-repo path and the write/refresh producer are what's missing.
- **`plugins/soleur/skills/qa/SKILL.md`** (36,900/37,000 B capped — ~100 B headroom) — line 132 "Route lookup: when the repository carries a maintained feature map (this repo: `apps/web-platform/test/feature-map.md`)…". A generalization of ~43 added bytes fits.
- **`plugins/soleur/skills/ux-audit/SKILL.md`** (16,658 B, uncapped) — line 67 cites the soleur map path. **`plugins/soleur/skills/reproduce-bug/SKILL.md`** (37,299 B, uncapped) — line 143 same. Both edits are inferred scope (consistency of the #10726 wiring), flagged in Scope Check.
- **`plugins/soleur/test/components.test.ts`** — two relevant suites: "references/ files are reachable from their skill" (every `references/*.md` must be named by basename from another file in its skill dir — a new `test-browser/references/feature-map.md` requires a pointer, and `test-browser/` has no `references/` dir today) and "No backtick file references in skills" (markdown-link form mandatory). `components.test.ts` is the suite the #10401 sibling's AC3 cited; it runs on plugin diffs.
- **`scripts/lib/test-affected-paths.sh`** — declares edges on touched plugin files; `lint-feature-map-coverage-live` is ALWAYS_ON (the self-side guard's liveness arm) — untouched by this diff.
- **Self-side artifact shape** (`apps/web-platform/test/feature-map.md`): `## \`/route\`` heading + field bullets `route/entry/selectors/expects/auth/gotchas`; `## Deliberately unmapped` reasoned exemptions (`- \`/route\` — <reason>`, em-dash + non-empty reason); header states the update contract (same-PR map edit on route add/rename/delete) and documents "no fenced code blocks" (line-anchored consumers). `auth` enum: `anonymous|bot|admin` — user-facing doc generalizes to "the session state the route needs".
- **`constraint-scaffold`** exists as the heavyweight ship-a-gate-into-user-CI precedent (script + 6 templates + 4 test files) — its size confirms a scaffold skill is the wrong weight class for ~150 lines of convention.

### Internal Analogue — #10399 CTO rulings (precedent to inherit)

From `specs/archive/20261020-171633-feat-one-shot-10399-webplat-feature-map/decision-challenges.md`: markdown map over extending `route-list.yaml`; whole-tree coverage; bidirectional consistency (tombstones red); exemption registry inside the map, not a separate allowlist. The user-side convention inherits all four as *documented conventions* (no self-side enforcement ships).

### Learnings / Conventions Applied

- `2026-10-20-copied-template-links-and-coverage-negative-controls.md` (#10401, merged today) — "reference doc, not a slim skill" ruling; placement follows capped-byte headroom; `${CLAUDE_PLUGIN_ROOT}`-form links inside copy-through text; a coverage claim needs a negative control (the AC battery must drive the reachability census red on a scratch copy missing the pointer).
- `2026-10-20-a-census-guard-under-counts-on-both-enumerators.md` (#10399, merged today) — the line-anchored-consumer constraints the convention doc must teach users: `- selectors:`/`- expects:` bullet-shape (prose mentions don't conform), no fenced code blocks, one verdict channel, prefix-pathspec + suffix-filter over `**/` globs.
- `2026-09-18-a-plan-prescribed-probe-must-be-portable-to-the-hosts-it-ships-to.md` — any command the shipped doc prescribes to user hosts must be macOS-safe (no GNU-only flags; `sed -i`/`date -d` traps). The convention doc's lint sketch is prose-shaped, but the map-authoring commands it shows (`git ls-files '<prefix>' | grep -E '<suffix>$'`) must stay POSIX.
- `2026-06-30-constraint-scaffold-verify-every-assumed-capability-*.md` — verify assumed capabilities before documenting as load-bearing: every command the convention doc embeds is verified runnable (git built-ins only).
- Constitution: reference files take no frontmatter; markdown links for file refs; kebab-case filenames; skill descriptions third-person (untouched).

### Community Discovery (Phase 1.5) + Functional Overlap (Phase 1.5b)

- Stack scan: no `Cargo.toml`/`mix.exs`/`go.mod`/`Package.swift`/`build.gradle`/`composer.json`/`pubspec.yaml` at repo root — no uncovered stacks; agent-finder skipped.
- Functional overlap (in-process — no Task spawn in subagent context), query `feature map` across api.claude-plugins.dev, claudepluginhub.com, anthropics marketplace:
  - `thedotmack/claude-mem/pathfinder` — codebase→feature-grouped *flowcharts* for refactor audits; adjacent vocabulary, different artifact (not a route inventory for browser navigation).
  - `atris`, `mockup-extraction`, `pm-*` hubs, Anthropic registry — unrelated senses.
  - **Verdict: no community artifact ships a maintained user-POV route map for browser-skill navigation.** The convention is the soleur-side artifact the epic prescribes.

### External Research Decision (Phase 1.6)

Skipped — strong local context: the artifact shape exists on `origin/main` (#10666), the sibling ruling settles placement (#10401), the AC is fully specified, and the issue's own source (the Osmani article's poteto note) is quoted in the issue body. Docs-only change.

### Skill Description Budget (Phase 1.8)

No `description:` edit is candidate in any `plugins/soleur/skills/*/SKILL.md` — the check's trigger never fires. Recorded so the next planner sees it ran.

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (one-shot path; no brainstorm ran). Reconciling the *issue's* claims against the tree:

| Issue claim | Reality on `origin/main` | Plan response |
|---|---|---|
| "either a section in `test-browser` (write `docs/feature-map.md`, refresh on each run) or a small standalone skill" | Both options evaluated at 0.6b; the scaffold skill's producer is framework-bound and a new skill costs registration + description budget for zero added property (the #10401 ruling's exact shape) | test-browser-embedded convention: 1 new `references/` doc + SKILL.md edits |
| "`test-browser`/`qa` cite the map as the navigation source when present, fall back to file→route mapping when absent" | Both cite a map *when present* but hardcode the soleur path `apps/web-platform/test/feature-map.md`; a user repo carrying `docs/feature-map.md` is unrecognized | Generalize each citation to name the conventional path first, soleur path as the noted exception |
| "Sibling gap #10399 covers Soleur's own map" | Delivered 2026-10-20 via #10666 (+ #10726 consumer wiring) — verified on `origin/main` | Mirror its artifact shape, in-map exemption registry, and update contract in the user-facing doc |
| "~1 file + SKILL.md edits (~150 lines)" | Holds: 1 new reference (~150 lines) + 4 small SKILL.md edits | Honored |
| "decide skill-vs-convention at plan time" | Ruled in-process (CTO Rule interface) — convention | Recorded in `decision-challenges.md` |

## Open Code-Review Overlap

`gh issue list --label code-review --state open` (96 issues) → searched each planned path (`test-browser/SKILL.md`, `qa/SKILL.md`, `ux-audit/SKILL.md`, `reproduce-bug/SKILL.md`, `test-browser/references/feature-map.md`, `docs/feature-map.md`) against issue bodies → **None.**

## Problem Statement

Soleur ships browser-verification skills (`test-browser`, `qa`, `ux-audit`, `reproduce-bug`) whose agents navigate user apps by re-deriving file→route mappings at runtime — ad hoc, per run, discarded at session end. The Osmani *Agentic Verification* article's poteto note names the fix: a maintained **feature map** — a committed, user-POV inventory of features, entry paths, selectors, expected outcomes, and gotchas — is what turns browser testing from flailing into navigation. Soleur built exactly this for itself (#10399 → `apps/web-platform/test/feature-map.md` + a five-arm drift lint, merged via #10666, wired into all four consumers via #10726) but ships nothing that lets a *user's* repo carry the same artifact: the four consumer skills hardcode the soleur-internal path, so a user map would go unread, and no producer writes or refreshes one.

## Proposed Solution

Two deliverables inside `plugins/soleur/`:

1. **FR-1 — `plugins/soleur/skills/test-browser/references/feature-map.md`** (new, ~150 lines) — the shipped convention doc: canonical path `docs/feature-map.md` at repo root; the entry schema (`## \`/route\`` heading + `- route:`/`- entry:`/`- selectors:`/`- expects:`/`- auth:`/`- gotchas:` bullets) and the `## Deliberately unmapped` reasoned-exemption registry, both mirrored from the self-side shape; the same-PR update contract; map-authoring guidance (agent enumerates the repo's own route-file shapes — Next `app`/`pages`, Rails `config/routes.rb`/`app/views`, SPA router configs — no shipped glob); consumer-parse constraints (line-anchored `## \`/route\`` + field bullets, **no fenced code blocks in the map**); and drift guidance (refresh-on-run producer + how to adapt the five-arm lint with the user's own route glob).
2. **FR-2 — SKILL.md pointer/behavior edits:**
   - `test-browser/SKILL.md` — §3's "Repo feature map first" generalized to check the conventional `docs/feature-map.md` (soleur's own path named as the noted exception); a new `### 5b.` step writes a seed map (routes actually exercised, observed fields only) when absent, field-refreshes contradicted entries and appends newly-exercised routes when present, and skips non-web repos / zero-route runs. Includes the `[feature-map.md](./references/feature-map.md)` markdown link that satisfies the reachability census.
   - `qa/SKILL.md` — the line-132 route-lookup citation generalized identically, inside its ~100 B byte-ceiling headroom.
   - `ux-audit/SKILL.md` + `reproduce-bug/SKILL.md` — the same one-line generalization of their soleur-path citations (inferred scope — see Scope Check).

## Technical Approach

### Edit surface 1 — `plugins/soleur/skills/test-browser/references/feature-map.md` (new)

Doc outline (~150 lines, plain `# Title`, no frontmatter, kebab-case, markdown links, ASCII, self-contained — **no `knowledge-base/`, `scripts/`, or `apps/` paths**: they do not exist on user machines; the article URL `[Agentic Verification](https://addyo.substack.com/p/agentic-verification)` may be cited):

1. **What a feature map is** — committed, user-POV inventory of navigable features; each entry names how to reach the route, stable selectors, the expected outcome, session state, and gotchas. The thing that turns browser testing from flailing into navigation.
2. **Canonical location** — `docs/feature-map.md` at the repo root. One path keeps every consumer's check trivial. Note: `docs/` is the right home even when the repo publishes a docs site — the map is internal agent tooling; mark it so if the site builds from `docs/`.
3. **Entry schema** — `## \`/route\`` heading, then field bullets `- route:` `- entry:` `- selectors:` `- expects:` `- auth:` `- gotchas:`. Dynamic segments stay literal (`[id]`, `[...path]`). `entry` = how an agent reaches the route (nav link, direct URL, redirect). `selectors` prefer `data-testid`, then role/text anchors. `expects` = user-POV outcome. `auth` = the session state the route needs (anonymous / signed-in fixture / role-gated). One complete worked example in a fenced block, with the warning that the fence markers are display-only and must never be copied into the map itself (the map's grammar arm bans fences).
4. **`## Deliberately unmapped`** — bullets of the exact shape `- \`/route\` — <reason>` (em-dash + non-empty reason); an exemption is a recorded decision, not silent absorption.
5. **Consumer-parse constraints** — consumers anchor on lines: `^## \`` + backtick-slash for entries, `^- selectors:`/`^- expects:` bullets for field conformance. Prose mentions of the field names do not conform; **fenced code blocks are forbidden inside the map itself** (a `## \`/route\`` line inside a fence reads as a real entry to every line-anchored consumer).
6. **Update contract** — adding, renaming, or deleting a route surface requires an edit to the map (or to `## Deliberately unmapped`) in the same change. The contract is stated in the map's own header.
7. **Authoring the map** — the agent enumerates route surfaces from the repo's own shapes: `git ls-files '<app dir>' | grep -E '/page\.tsx$'` for a Next app-router tree (prefix pathspec + suffix filter — never a `**/` glob, which silently drops zero-directory roots on some git versions), `config/routes.rb`/`app/views` for Rails, the router config for SPAs. Fill `selectors`/`expects`/`gotchas` only from observed navigation or read page source — an unvisited entry that asserts unverified selectors is worse than no entry.
8. **Keeping it fresh** — (a) `test-browser` writes/refreshes the map on each run (see the skill); (b) the update contract makes human route changes carry map edits; (c) optional lint: the five-arm shape — coverage (route set vs mapped∪exempted), staleness (mapped∪exempted vs route set), completeness (`- selectors:`/`- expects:` bullets present per entry), contradiction (route in both sets), grammar (no fences) — plus an anti-vacuity check that the producer derived >0 routes; the coverage/staleness arms need the repo's own route-file glob, the rest are portable. Commands shown stay POSIX-safe (stock macOS).
9. **Edge cases** — non-web repos carry no map (nothing to inventory); zero exercised routes means no seed is written (a vacuous map certifies nothing); a partial map is valid — the contract and lint keep uncovered routes visible; preserve operator annotations — refresh is field-scoped, never a wholesale rewrite.

### Edit surface 2 — `plugins/soleur/skills/test-browser/SKILL.md`

Two changes inside `<file_to_route_mapping>` / `<test_pages>`:

1. **§3 "Repo feature map first"** — replace the soleur-only mention with the conventional path: "When the repository carries a maintained feature map — convention: `docs/feature-map.md` (soleur's own lives at `apps/web-platform/test/feature-map.md`; the entry schema and update contract are in [feature-map.md](./references/feature-map.md)) — its route entries are the navigation source of truth." Extend the fallback sentence: the generic file→route table is the fallback for repos without a map **AND for routes a partial map does not cover** — a map is authoritative per-route, never a reason to skip testing an unmapped route (deepen-pass spec-flow finding; partial maps are legal per the convention doc's edge cases).
2. **New `### 5b. Write or refresh the feature map`** (after `</test_pages>`, before `### 6.`): after all affected routes are tested —
   - **Absent + web app + ≥1 route exercised:** write `docs/feature-map.md` seeded with the exercised routes only — real observed `selectors`/`expects`/`gotchas`, the update-contract header, a `## Deliberately unmapped` section (empty is fine). Do not enumerate unvisited routes as entries.
   - **Present:** refresh only the fields a run contradicted; append `## \`/route\`` entries for exercised routes that were missing; leave every untouched entry and the header byte-identical (operator annotations survive).
   - **Skip:** non-web repos (no route surfaces found) and runs that exercised zero routes — never write a vacuous map.
   - The map is a working-tree edit that lands with the feature's PR — same change, per the update contract.
   - **Report:** the Step 8 test summary names the map action taken — `written`, `refreshed`, or `skipped` + one-word reason (`non-web`, `no-routes`) — so a silently-absent map is never mistaken for a maintained one.

### Edit surface 3 — `plugins/soleur/skills/qa/SKILL.md`

Line 132 becomes (verbatim replacement):

```text
- **Route lookup:** when the repository carries a maintained feature map (`docs/feature-map.md` by convention; soleur's own: `apps/web-platform/test/feature-map.md`), resolve Browser-step targets against its `## \`/route\`` entries — selectors, expected outcome, auth, gotchas — before navigating
```

Delta ≈ +45 B against a 36,900/37,000 B ceiling — fits inside headroom; verify `wc -c` delta at work time and re-check `python3 scripts/lint-skill-body-budget.py --base origin/main`.

### Edit surface 4 — `plugins/soleur/skills/ux-audit/SKILL.md` + `plugins/soleur/skills/reproduce-bug/SKILL.md`

Same one-line generalization of each soleur-path citation (uncapped files; inferred scope for consumer consistency — all four navigation skills should read the same map contract). Use the identical parenthetical shape as the qa line — `(docs/feature-map.md` by convention; soleur's own: `apps/web-platform/test/feature-map.md`) — so all four citations share one phrasing a future edit can sweep.

## Observability

The shipped surface is documentation consumed by agents; "observability" is whether the landed convention is mechanically discoverable in the tree — the references-reachability census and the body-budget lint are the enforcement layer and this block is the declared probe.

```yaml
liveness_signal:
  what: "`test-browser/references/feature-map.md` exists and is named (markdown link) from `test-browser/SKILL.md`; `qa` route-lookup cites `docs/feature-map.md`"
  cadence: "per-PR: components.test.ts references-reachability census + lint-skill-body-budget.py on plugin diffs"
  alert_target: "CI check failure (plugin test shard / lint)"
  configured_in: "plugins/soleur/test/components.test.ts + scripts/lint-skill-body-budget.py (pre-existing — no new guard added by this diff)"
error_reporting:
  destination: "CI job log — census failure names the orphaned reference path; budget lint names the over-ceiling file"
  fail_loud: "yes — orphan references and budget overruns are suite failures, not warnings"
failure_modes:
  - mode: "reference file orphaned (the SKILL.md pointer deleted later)"
    detection: "components.test.ts references-reachability census"
    alert_route: "CI red on the next diff touching the plugin shard"
  - mode: "qa/SKILL.md edit pushes the body over its 37,000 B ceiling"
    detection: "scripts/lint-skill-body-budget.py --base <merge-base>"
    alert_route: "CI red"
  - mode: "convention doc drifts from the shipped consumer citations (skills rename the canonical path)"
    detection: "AC grep battery — `docs/feature-map.md` literal present in the doc and all four consumers"
    alert_route: "review-time AC check"
logs:
  where: "CI job log (suite assertion lines)"
  retention: "GitHub Actions retention"
discoverability_test:
  command: "grep -q 'docs/feature-map.md' plugins/soleur/skills/test-browser/SKILL.md && grep -q 'references/feature-map.md' plugins/soleur/skills/test-browser/SKILL.md && echo map-convention-wired"
  expected_output: "map-convention-wired"
```

## Guard Contract

This plan ships no new guard; its diff is made safe by three **pre-existing** enforcement surfaces plus one plan-defined check. Each is recorded because the plan's correctness claims stand on them — the convention doc also *describes* a lint shape to users, but no executable guard ships in this diff (the five-arm sketch is documentation, so it is not a Guard entry here).

### Guard 1 — References-reachability census (`plugins/soleur/test/components.test.ts`)

**Property.** Every `references/*.md` inside a skill directory is named (by basename substring) from another file in the same skill directory — the new `test-browser/references/feature-map.md` can never ship orphaned.

**Assembly.** The suite walks every skill directory's `references/` (depth < 2) and asserts each basename appears in a same-skill sibling file — a census over the live tree, not a pinned name list. `test-browser/` gains its first `references/` member via this diff; the `[feature-map.md](./references/feature-map.md)` link in SKILL.md is the naming surface.

**Mutation matrix:**

| Mutation | Expected result |
|---|---|
| Create `references/feature-map.md` with no SKILL.md link | RED — census reports the orphan reference |
| Rename the file so the basename no longer matches the link text | RED — census reports the orphan |
| Add a second `references/*.md` later with no naming surface | RED — same census, second member |

### Guard 2 — SKILL body-budget lint (`scripts/lint-skill-body-budget.py` + `plugins/soleur/test/skill-body-budget.json`)

**Property.** `qa/SKILL.md` body stays ≤ 37,000 B — the pointer generalization must fit inside the ~100 B headroom or carry a delta-neutral trim.

**Assembly.** The lint compares the working-tree byte count of every ceiling-keyed lifecycle SKILL.md against the merge-base-anchored ceilings table; `qa` is a ceiling key (36,900 B today). `test-browser`, `ux-audit`, `reproduce-bug` are NOT keyed — edits there are unbounded by this guard.

**Mutation matrix:**

| Mutation | Expected result |
|---|---|
| `qa` line grows by > ~100 B with no offsetting trim | RED — body exceeds ceiling |
| Pointer written as a new paragraph instead of in-place generalization | RED — byte delta exceeds headroom |
| Ceiling table hand-edited upward to fit the edit | RED at review — the table ratchets down only; a raise is a separate reviewed PR |

### Guard 3 — Canonical-path consistency check (this plan's AC battery)

**Property.** The literal `docs/feature-map.md` is the single canonical path named by the convention doc and every consumer citation — no edit reintroduces a second user-facing path.

**Assembly.** `grep -c 'docs/feature-map.md'` over `test-browser/references/feature-map.md` (≥1), `test-browser/SKILL.md` (≥1), `qa/SKILL.md` (1), `ux-audit/SKILL.md` (1), `reproduce-bug/SKILL.md` (1) in this diff's verification battery.

**Mutation matrix:**

| Mutation | Expected result |
|---|---|
| Convention doc names `test/feature-map.md` instead | RED — canonical literal absent from doc |
| One consumer edit names a different path (`docs/feature-map.md` vs `feature-map.md`) | RED — per-file counts miss |
| A consumer citation dropped entirely | RED — that file's count is 0 |

**Must-pass row:** the full affected suite (`components.test.ts` census + budget lint + AC greps) green on the final tree, plus the negative control — on a scratch copy with the SKILL.md link removed, the census reds naming `test-browser/references/feature-map.md`.

## User-Brand Impact

- **If this lands broken, the user experiences:** either the convention never reaches their repo (the gap persists silently — same as today), or a misprescribed one — e.g. a convention doc that teaches fabricating map entries for unvisited routes, or a `test-browser` producer that rewrites the map wholesale and destroys the operator's annotations on every run.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — docs-only change inside shipped skill text; the map artifact itself inventories routes and selectors, not secrets; no credentials, no user data, no runtime behavior.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** the blast radius is prose and one working-tree write into the user's own repo — a wrong convention degrades navigation quality, it cannot breach data or production, so `none` not `single-user incident`.

## Files to Create

- `plugins/soleur/skills/test-browser/references/feature-map.md` — the shipped feature-map convention (~150 lines).

## Files to Edit

- `plugins/soleur/skills/test-browser/SKILL.md` — §3 map-path generalization + `[feature-map.md](./references/feature-map.md)` link; new `### 5b.` write/refresh step (~40 lines).
- `plugins/soleur/skills/qa/SKILL.md` — line-132 route-lookup generalization (~45 B net).
- `plugins/soleur/skills/ux-audit/SKILL.md` — line-67 citation generalization.
- `plugins/soleur/skills/reproduce-bug/SKILL.md` — line-143 citation generalization.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "A generator/maintainer convention: either a section in `test-browser` (write `docs/feature-map.md`, refresh on each run) or a small standalone skill that scaffolds the map from route files + a drift check." [issue #10402] | FR-1 `references/feature-map.md` + FR-2 `test-browser` §3/§5b | mapped (the skill alternative descoped — Cut List) |
| 2 | "Users end up with a committed feature map their agents read before browser runs." [issue #10402] | FR-2 §5b seed-write + FR-1 update contract | mapped |
| 3 | "`test-browser`/`qa` cite the map as the navigation source when present, fall back to file→route mapping when absent." [issue #10402] | FR-2 `test-browser` §3 + `qa` line-132 edits | mapped |
| 4 | "Drift guidance: how the map stays fresh (regenerate-on-run or lint hint)." [issue #10402] | FR-1 §"Keeping it fresh" (refresh-on-run + five-arm lint sketch) | mapped |
| 5 | "~1 file + SKILL.md edits (~150 lines)" [issue #10402] | Constraint — honored: 1 new file + 4 SKILL.md edits | mapped |
| 6 | "Decide skill-vs-convention at plan time." [issue #10402] | Ruled (CTO, in-process) → convention; recorded in `decision-challenges.md` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `test-browser/references/feature-map.md` | ask 1, 2, 4 | asked |
| `test-browser/SKILL.md` §3 + §5b edits | ask 1, 2, 3 | asked |
| `qa/SKILL.md` line-132 edit | ask 3 | asked |
| `ux-audit/SKILL.md` + `reproduce-bug/SKILL.md` edits | — | inferred — justification: #10726 wired all four consumers to the same citation shape; generalizing only the two named in the AC leaves two skills teaching a soleur-only path inside the user-facing convention, which is the inconsistency the convention exists to remove |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur`
- Planned files: 5 | Estimated changed lines: ~210
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — `plugins/soleur/skills/test-browser/references/feature-map.md` exists and names all convention elements: `grep -c 'docs/feature-map.md' <file>` >= 1, `grep -c 'Deliberately unmapped' <file>` >= 1, `grep -c 'selectors:' <file>` >= 1, `grep -c 'expects:' <file>` >= 1, and `grep -ci 'update contract' <file>` >= 1.
- [ ] AC2 — the doc carries the drift guidance: `grep -ci 'lint' <file>` >= 1 and `grep -ci 'refresh' <file>` >= 1, plus the parse-constraint rules: `grep -ci 'fenced' <file>` >= 1.
- [ ] AC3 — `test-browser/SKILL.md` cites the conventional path (`grep -c 'docs/feature-map.md' plugins/soleur/skills/test-browser/SKILL.md` >= 1), links the reference (`grep -c 'references/feature-map.md' plugins/soleur/skills/test-browser/SKILL.md` >= 1, markdown-link form — no `` `references/`` backtick ref), and contains the write/refresh step (`grep -n 'Write or refresh' plugins/soleur/skills/test-browser/SKILL.md` hits).
- [ ] AC4 — `grep -c 'docs/feature-map.md' plugins/soleur/skills/qa/SKILL.md` returns `1` and `wc -c < qa/SKILL.md` <= 37000; `python3 scripts/lint-skill-body-budget.py --base origin/main` exits 0.
- [ ] AC5 — `grep -c 'docs/feature-map.md' plugins/soleur/skills/ux-audit/SKILL.md plugins/soleur/skills/reproduce-bug/SKILL.md` returns `1` each.
- [ ] AC6 — `bun test plugins/soleur/test/components.test.ts` passes the references-reachability census (the basename `feature-map.md` is named from `test-browser/SKILL.md`); **negative control:** on a scratch copy with the SKILL.md link removed, the census reds naming `test-browser/references/feature-map.md` as orphaned.
- [ ] AC7 — self-containment: `grep -nE 'knowledge-base/|scripts/lib/|apps/web-platform' plugins/soleur/skills/test-browser/references/feature-map.md` returns nothing (shipped doc carries no repo-internal paths).
- [ ] AC8 — `git diff origin/main...HEAD -- plugins/soleur/docs/_data/skills.js 'plugins/soleur/skills/*/SKILL.md'` shows no `description:` frontmatter delta and no skills.js change (a reference is not a component; SKILL_DESCRIPTION_WORD_BUDGET untouched).
- [ ] AC9 — markdownlint clean on all touched `.md` files via the repo's single invoker (`bash scripts/markdown-lint.sh`, verified 2026-10-20: `scripts/markdown-lint.sh` wraps the pinned `markdownlint-cli@0.49.1` from `package.json`).

## Test Scenarios

Label each scenario's pyramid layer — `unit`, `integration`, or `e2e` — and prefer the lowest layer that exercises the behavior.

- **AC verification battery (unit — grep asserts):** Given the merged diff, when the AC1–AC5/AC7/AC8 grep commands run, then each returns its expected count/absence.
- **Census (unit):** Given the new reference file, when `bun test plugins/soleur/test/components.test.ts` runs, then the "every references/*.md is named from its skill" test passes.
- **Coverage negative control (unit):** Given a scratch copy where the `test-browser/SKILL.md` link is removed, when the census runs, then it reds with `test-browser/references/feature-map.md` in the orphan list — the enforcement is real, not presumed.
- **Budget regression (unit):** Given the `qa` edit, when `lint-skill-body-budget.py --base origin/main` runs, then `qa` stays <= 37,000 B and the lint exits 0.
- **Docs hygiene (unit):** markdownlint on touched files; no `description:` frontmatter delta (skill description budget untouched); the four edited SKILL.mds still parse (frontmatter `name`/`description` unchanged).
- **Producer-semantics review (integration — prose review):** Given a repo with (a) no map + web routes exercised, (b) a map with one stale entry, (c) a non-web repo — the §5b text prescribes seed-write, field-scoped refresh, and skip respectively; verified by review of the shipped wording, not by execution.

## Domain Review

**Domains relevant:** Engineering, Product (fail-closed expansion — Product/UX tier resolved NONE below)

### Engineering

**Status:** reviewed (inline — subagent context, no Task spawn; CTO Rule interface executed for the placement fork)
**Assessment:** Blast radius is prose plus one agent-side working-tree write into the user's own repo. The technical risks are all convention mechanics: the qa byte ceiling (~100 B headroom, verified against `skill-body-budget.json`), the references-reachability census over a first-ever `test-browser/references/` member, and the map's line-anchored parse contract (which the shipped doc must teach honestly — bullets not prose mentions, no fences). The placement fork (test-browser-embedded convention vs standalone scaffold skill vs generator CLI) was ruled technically — recorded in `decision-challenges.md`.

### Product/UX Gate

**Tier:** none — no UI surface in Files to Create/Edit (all paths are `plugins/soleur/skills/**/*.md`; the glob superset contains no `*.md` member; the change is agent-guidance prose). The mechanical UI-surface override does not fire.

No Product/UX pipeline runs at NONE tier.

## Non-Goals

- No standalone `feature-map` skill — ruled at plan time (CTO, `decision-challenges.md`); a skill adds registration + description-budget cost for zero added property.
- No shipped generic lint script or generator CLI — the coverage direction is framework-bound; the convention doc teaches the lint *shape* for users to adapt with their own route glob.
- No `plan`/`work`/`review`/`ship` SKILL.md edits — byte-ceiling headroom aside, the AC names `test-browser`/`qa`; lifecycle-skill pointers are a legal follow-up if demand shows.
- No changes to `apps/web-platform/test/feature-map.md`, `scripts/lint-feature-map-coverage.sh`, or their CI wiring — the self-side implementation is the pattern source, untouched.
- No `docs/feature-map.md` created *in this repo* — this repo's map already lives at `apps/web-platform/test/feature-map.md` and stays the noted exception.

## Success Metrics

- `git grep -l 'docs/feature-map.md' plugins/soleur/skills/` returns the convention doc + all four consumer SKILL.mds post-merge (today: zero hits — the conventional path is named nowhere).
- First user repo carrying `docs/feature-map.md` read by `test-browser` is unmeasurable internally — proxy: the §3 generalization + §5b producer exist (AC3) and the census holds (AC6).

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| `qa` edit exceeds its 37,000 B ceiling | Line-level in-place generalization (~+45 B), `wc -c` delta check + `lint-skill-body-budget.py` at work time (AC4) |
| Convention doc links repo-internal paths users lack | AC8's self-containment grep (`knowledge-base/`, `scripts/lib/`, `apps/web-platform` all banned from the shipped doc) |
| Producer semantics misfire (vacuous map, wholesale rewrite destroying annotations, fabricated unvisited entries) | §5b's three-arm contract (write seed only when ≥1 route exercised; field-scoped refresh; skip non-web) + convention doc's edge-case section + spec-flow gap pass applied |
| Reference file orphans silently | components.test.ts reachability census (pre-existing) + negative-control scenario |
| A second canonical path creeps in (`test/feature-map.md` etc.) | AC battery counts the `docs/feature-map.md` literal per file; Guard 3 |

## Dependencies & Risks

- Depends on the merged self-side pattern (#10666, #10726) — verified on `origin/main`.
- No issue dependencies; #10400/#10403/#10404 siblings are independent (no shared files).
- Merge-order sensitivity: none identified — the four SKILL.md files touched here have no open sibling PRs (verified against #10401's shipped file list and #10400's scope, which touch `plan`/`work` surfaces).

## References & Research

- Self-side implementation: `apps/web-platform/test/feature-map.md`, `scripts/lint-feature-map-coverage.sh` (#10399 → PR #10666); consumer wiring PR #10726.
- Sibling shipped pattern: `plugins/soleur/skills/plan/references/differential-migration-testing.md` (#10401 → PR #10727).
- CTO rulings inherited: `knowledge-base/project/specs/archive/20261020-171633-feat-one-shot-10399-webplat-feature-map/decision-challenges.md`.
- Source article: [Agentic Verification](https://addyo.substack.com/p/agentic-verification) (Addy Osmani, 2026-10-14) — the poteto note's feature-map prescription.
- Epic: #10397; this plan closes #10402.
