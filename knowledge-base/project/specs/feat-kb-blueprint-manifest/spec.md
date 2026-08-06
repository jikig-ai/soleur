---
title: "KB blueprint manifest — single source of truth for knowledge-base composition"
date: 2026-08-06
feature: feat-kb-blueprint-manifest
branch: feat-kb-blueprint-manifest
issue: "#7332"
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
brainstorm: knowledge-base/project/brainstorms/2026-08-06-kb-blueprint-manifest-brainstorm.md
design:
  - knowledge-base/product/design/dashboard/blueprint-cards-variant-a-two-zones.pen
  - knowledge-base/product/design/dashboard/blueprint-cards-variant-b-enriched-chips.pen
---

# KB Blueprint Manifest

## Problem Statement

Four separate declarations of "what a Soleur knowledge base should contain" exist
in the codebase and none of them agree:

1. `/soleur:sync`'s Output Locations table — 6 artifact types, all under `knowledge-base/project/`
2. `apps/web-platform/lib/kb-constants.ts` `DASHBOARD_FOUNDATION_KB_PATHS` — 10 business paths
3. `apps/web-platform/app/(dashboard)/dashboard/page.tsx` `FOUNDATION_PATHS` + `OPERATIONAL_TASKS` — the same 10, duplicated
4. Soleur's own `knowledge-base/` — 10 domains, ~8.4k files

(1) and (2) share zero paths. Nothing produces the `engineering/` artifacts —
C4 diagrams, domain-model register, ADRs — that constitute the bulk of Soleur's
own knowledge base and that Soleur's agents depend on.

The consequence is measurable on the first alpha tester. `2my8r9ry2t-wq/Skouer`'s
synced knowledge base contains exactly 23 entries, 100% under `project/`: a
README, 7 component docs, a constitution, 4 architecture learnings, and 4
tech-debt learnings. No C4 model, no domain-model register, no business domains.

Adding a KB artifact type today requires a coordinated change across a markdown
command, two TypeScript constants, and a coverage test.

## Goals

- One canonical, plugin-owned manifest declaring every expected KB artifact.
- `/soleur:sync` generates the technical artifacts that are genuinely derivable.
- The dashboard derives its card set from the manifest instead of hardcoded lists.
- Onboarding emits a KB coverage report naming what the manifest expects versus
  what is present.
- The first alpha tester's onboarding visibly improves: a C4 architecture model
  and a domain-model register they can open.

## Non-Goals

- **ADRs mined from git history.** Cut entirely; not deferred, no follow-up issue.
  The C4 model and domain-model register cover the context need without the
  fabrication risk.
- **Synthesizing runbooks, checklists, or policies.** These remain declared
  manifest entries owned by agents. Operational truth is not code-derivable and a
  fabricated runbook is an active hazard.
- **A `when` predicate DSL.** v1 hardcodes 3–4 predicates.
- **Detect-and-adopt of existing project docs** (`docs/`, `.agents/`). Retained as
  a candidate refinement, not v1 scope.
- **Mirroring coverage-report content into Soleur-side storage.** The report stays
  in the customer's repo; the dashboard reads counts only.
- **Corner-radius migration.** The Solar Forge brand guide specifies 0px corners
  and the shipped component uses `rounded-xl`/`rounded-lg`. The approved wireframe
  keeps the shipped radius. Reconciling them is separate work.
- **Manifest-driven dynamic card ordering.** The visible/collapsed split follows
  the existing foundation-vs-operational distinction, not a manifest priority
  field. Dynamic ordering is a system-design change beyond this feature.
- **Card copy changes.** The manifest carries display copy (FR1), but seeded from
  the strings that ship today. No rewording rides along with the rewire.

## Functional Requirements

**FR1 — Blueprint manifest.** A committed manifest in the Soleur repo enumerates
KB entries. Each entry carries an immutable `id`, `path`, `domain`, `producer`,
`owner` (agent or skill), `tier`, an optional `when` predicate, and the
presentation fields the dashboard needs (`title`, `description`, `cta`).

**FR2 — Manifest is trusted input.** The Next.js server imports the manifest as a
build-time module. It is never read from customer repository content.

**FR3 — Predicate evaluation in the CLI.** `/soleur:sync` evaluates each entry's
`when` predicate against the connected repo and writes the results to a committed
`blueprint-status.json` in that repo: `{generated_at, entries:[{id, applicable}]}`.

**FR4 — Server join discards unknown ids.** The dashboard reads
`blueprint-status.json` once and joins by `id` against the trusted manifest. Any
id not present in the manifest is discarded.

**FR5 — `done`-ness stays filesystem-derived.** Card completion continues to use
`statKnownPaths` against the KB root, so a hand-authored file flips a card without
requiring a re-sync. `blueprint-status.json` narrows which entries are in scope,
nothing more.

**FR6 — C4 producer.** `/soleur:sync` generates `spec.c4`, `model.c4`, and
`views.c4` under `knowledge-base/engineering/architecture/diagrams/`, deriving
the element set from the generated component docs and the relationship set from
their `## Dependencies` → `**Internal**: [name](name.md)` links. The compiled
`model.likec4.json` is rendered from those sources.

**FR7 — Domain-model producer.** The existing opt-in `domain-model` sync area is
promoted into the manifest as a default seed entry, gated on a `has:migrations`
predicate. Its existing `domain-model-drift.sh write-row` safety properties are
preserved unchanged.

**FR8 — Domain stub READMEs.** Each of the 10 domains receives a README stating
structurally what belongs there and which agent owns it. Wording is constrained to
structural statements; normative statements are prohibited. `legal/` and
`finance/` carry the `recommended-tools.md` disclaimer verbatim.

**FR9 — KB coverage report.** A committed report lists, per domain, which manifest
entries have a corresponding file and which do not. It states what the manifest
expects versus what is present and never asserts what the business lacks.

**FR10 — CLI coverage output.** `/soleur:sync` prints the coverage summary at the
end of a run, naming the skill or agent that owns each absent entry.

**FR11 — Dashboard derives from the manifest.** `FOUNDATION_PATHS`,
`OPERATIONAL_TASKS`, and `DASHBOARD_FOUNDATION_KB_PATHS` are replaced by manifest
derivation. Per the adopted taxonomy, entries an agent can complete unattended do
not render as actionable cards.

**FR12 — Two-zone card layout (approved wireframe: Variant A).** The zone renders
an evidence group ("Soleur built this for you") above a rule, then an
input-request group ("Needs your input"). Evidence tiles carry a concrete metric
and an `Open →` link styled as a read affordance, not a task. The input-request
group shows the 4 foundations with the 6 operational items collapsed behind
`Show 6 more`. The coverage-report entry point sits inside the evidence zone.
Shipped corner radii, the existing foundation/operational split, and the existing
card copy are preserved — see Non-Goals.

Design source: `knowledge-base/product/design/dashboard/blueprint-cards-variant-a-two-zones.pen`
(frames: alpha state, expanded actionable zone, coverage drill-in).

**FR13 — C4 flag prerequisite.** `c4-visualizer` is enabled for alpha-tester roles
via the existing `flag-set-role` / `user-set-role` tooling before C4 generation
ships. Generation is not gated on flag state.

## Technical Requirements

**TR1 — ADR-067 preservation.** The dashboard must not regain a whole-KB
`buildTree()` walk. Applicable manifest entries are capped (~40) with the cap
asserted in a test.

**TR2 — No new CLI→server write channel.** Predicate results travel as a committed
repo artifact, not a database column.

**TR3 — Coverage test rewrite.** The dashboard foundation-status test currently
matches `kbPath: "…"` against `page.tsx` source text. It must be rewritten as
manifest→card derivation before the rewire lands, or it will silently match
nothing instead of failing.

**TR4 — E2E seed helper.** `apps/web-platform/e2e/start-fresh-onboarding.e2e.ts`
mocks a fixed foundation path set with `size: 1000`. It needs a manifest-driven
seed helper so the all-complete assertion continues to trigger.

**TR5 — First-run sentinel preserved.** `overview/vision.md` gates the first-run
experience. It must remain a named manifest entry and must not be diluted by
technical entries.

**TR6 — Entry ids are immutable.** Manifest `id` values follow the same
immutability discipline as rule ids, since `blueprint-status.json` joins on them.

**TR7 — C4 edge parsing.** The relationship extractor parses
`## Dependencies` → `**Internal**: [name](name.md)` links. Verified consistent
across 5/5 of the alpha tester's component docs. The prose `## Data Flow` line is
human context and is not parsed in v1.

**TR8 — Headless contract preserved.** Generation runs under the existing headless
sync contract: commit locally, never push a protected default branch, treat a
push rejection as degraded rather than failed.

## Acceptance Criteria

1. A single manifest edit adds a KB artifact type end-to-end — sync generation,
   dashboard card, and coverage report — with no other declaration touched.
2. Re-syncing `2my8r9ry2t-wq/Skouer` produces a C4 model whose elements are its
   7 components and whose relationships match their `## Dependencies` links.
3. The tester can open the generated diagram in the KB viewer.
4. The coverage report names absent entries without asserting the business lacks
   anything.
5. `/api/dashboard/foundation-status` performs no whole-tree walk.
6. The dashboard coverage test fails, rather than silently matching nothing, if
   card derivation breaks.
