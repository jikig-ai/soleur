# KB Blueprint Manifest — a single source of truth for "what a Soleur knowledge base contains"

**Date:** 2026-08-06
**Status:** Decided
**Branch:** feat-alpha-onboarding-motion
**PR:** #7328
**Lane:** cross-domain
**Brand-survival threshold:** single-user incident

## What We're Building

A canonical, plugin-owned **blueprint manifest** that enumerates every artifact a
Soleur knowledge base is expected to contain — path, domain, producer, owning
agent/skill, tier, and an optional `when` predicate. It becomes the single source
of truth for three surfaces that today each hardcode their own partial answer:

1. `/soleur:sync` reads it to know what to generate.
2. The web dashboard reads it instead of two hardcoded path lists.
3. Onboarding diffs it against the connected repo to emit a **KB coverage report**.

Inciting context: onboarding `2my8r9ry2t-wq/Skouer` as the first alpha tester.
`/soleur:sync` produced a technically-correct but narrow knowledge base, missing
the architecture artifacts Soleur itself now depends on (notably the C4 model).

## Why This Approach

The root cause is not that sync is missing a feature. It is that **four separate
declarations of "what a KB should contain" exist and none of them agree**:

| # | Declaration | Location | Scope |
|---|---|---|---|
| 1 | sync's Output Locations table | `plugins/soleur/commands/sync.md` (Output Locations) | 6 types, all under `project/` |
| 2 | Dashboard statted path set | `apps/web-platform/lib/kb-constants.ts` (`DASHBOARD_FOUNDATION_KB_PATHS`) | 10 paths, all business |
| 3 | Dashboard card metadata | `apps/web-platform/app/(dashboard)/dashboard/page.tsx` (`FOUNDATION_PATHS`, `OPERATIONAL_TASKS`) | same 10, duplicated |
| 4 | Soleur's own KB shape | `knowledge-base/` | 10 domains, ~8.4k files |

(2) and (3) are reconciled only by a coverage test asserting
`page.kbPaths ⊆ constants`. (1) and (2) share **zero** paths — sync writes only
`project/*`; the dashboard watches only business domains. Nothing produces the
`engineering/` artifacts that make up the bulk of Soleur's own KB.

A manifest collapses all four into one declaration. Adding a KB artifact type
becomes a one-line manifest edit rather than a coordinated change across a
markdown command, two TypeScript constants, and a coverage test.

### Empirical confirmation

`Skouer`'s synced `knowledge-base/` contains exactly **23 entries, 100% under
`project/`**: `README.md`, 7 component docs, `constitution.md`, 4
`learnings/architecture/`, 4 `learnings/technical-debt/`. Zero ADRs, zero C4,
zero business domains. This matches sync's declared output surface exactly, which
confirms the gap is structural rather than a sync bug.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Shape | Canonical blueprint manifest | Collapses four disagreeing declarations into one. Chosen over extending sync's areas (leaves the four lists) and over a separate `/soleur:onboard` skill (adds a fifth). |
| Manifest ownership | **Plugin-owned, committed in the Soleur repo**; server imports it as a build-time module | A manifest read per-workspace from customer content would make `/api/dashboard/foundation-status` parse untrusted JSON and stat an unbounded path set — re-creating the whole-tree walk ADR-067 removed. |
| Predicate results | Evaluated in the CLI at sync time; persisted to a committed `blueprint-status.json` in the customer repo | The CLI is the only place with the repo. Server does one file read, joins by `id` against the trusted manifest, and **discards any id not in the manifest**. No new DB column, so no CLI→server write channel or auth surface. |
| `done`-ness | Keep `statKnownPaths` against the filesystem | Ground truth — a hand-written file still flips a card without a re-sync. The status artifact only narrows *which* entries are in scope. |
| Seed scope | Generate technical artifacts where derivable **+ stub READMEs for all 10 domains + business gap list** | Operator decision, reaffirmed after the CPO's objection was presented (see Domain Assessments → Product for the recorded dissent). |
| Stub README wording | Structural only — "documents of this type belong here; owned by the `<agent>` agent". **Never normative** ("you need a privacy policy"). `legal/` and `finance/` carry the `recommended-tools.md` disclaimer verbatim | CLO: a generated README telling a customer what legal documents they need creates an advice-implication risk. |
| v1 producers | **C4 model** (from the component-doc dependency graph) + **domain-model register** (promote the existing opt-in area) + **coverage report** | Both are genuinely derivable from artifacts sync already produces. |
| ADRs from git history | **Cut entirely.** No follow-up issue filed | Operator: "we can avoid ADRs given that we will have the C4 model and domain-register." The derivable artifacts cover the context need without the fabrication risk or the CLO control set. |
| Runbooks / checklists / policies | Remain **declared** manifest entries owned by agents; **not** sync-generated | CTO: operational truth, not code-derivable — a fabricated runbook is an active hazard. They appear in the coverage report; nothing is synthesized. |
| Per-project variance | `when` predicates on entries; **hardcode 3–4 predicates, no DSL** in v1 | CTO and CPO independently: a predicate DSL before the shapes are known is speculative. |
| Coverage report framing | Titled as **KB coverage**, listing what the manifest expects vs. what exists. Never asserts what the business lacks | CLO: a committed, timestamped, git-blamed record that a customer lacks a privacy policy is discoverable and reads as knowledge of non-compliance. Prefer "no `privacy-policy.md` present in this knowledge base". |
| Coverage report location | In-repo (customer-controlled). Do not mirror gap text into Soleur-side storage or dashboard cards beyond a count | CLO. |
| C4 flag | **Flip `c4-visualizer` for alpha testers first**, via existing `flag-set-role` / `user-set-role` tooling. Generate unconditionally | `resolveC4FlagEnabled` resolves any `users.role != "dev"` to `"prd"`, so a tester would generate a diagram they cannot open. Gating *generation* on a *viewing* flag would leave the repo permanently poorer. |
| Surfaces | CLI output at end of sync + dashboard cards (blueprint-driven) + committed coverage file | Operator selected all three. |
| Visual design | See Phase 3.55 wireframes (linked below) | The dashboard rewire touches `app/(dashboard)/dashboard/page.tsx`, matching the UI-surface glob superset. |

### The C4 feasibility correction (load-bearing)

The CTO assessment concluded C4 was **not** derivable and should be deferred:
sync's Component Detection Heuristics are top-level-directory and index-file
heuristics, which yield **nodes only**. That much is correct.

It is not the whole picture. Sync's *Project Analysis* step separately instructs
extraction of "**Data flow**: How information moves between components" and
"**Dependencies**: Internal and external dependencies per component" — and
Skouer's already-synced component docs contain exactly that, in a consistent
machine-parseable form:

```text
database.md     → **Internal**: [web-server](web-server.md) …; [core-infra](core-infra.md) …
frontend-app.md → **Internal**: [web-server](web-server.md) for every byte of data
data-agents.md  → **Internal**: [core-infra](core-infra.md) …; [database](database.md) for schema
core-infra.md   → **Internal**: [database](database.md)
web-server.md   → **Internal**: [database](database.md) …
```

5/5 component docs checked, consistent `[name](name.md)` link convention under a
`## Dependencies` heading, plus a prose `## Data Flow` line. **That is a parseable
directed graph.** The C4 producer's input is therefore the *generated component
docs*, not the raw directory scan — which makes the operator's headline ask
feasible in v1, on the alpha tester's existing output.

The CTO's second C4 finding is independent and stands: the `c4-visualizer` flag
gates viewing for non-`dev` roles. That is addressed by the flag decision above.

## Open Questions

1. **`## Data Flow` prose is not machine-parseable** the way the `## Dependencies`
   links are. v1 should build the C4 edge set from the dependency links only, and
   treat the data-flow line as human context. Worth confirming the resulting model
   is useful without flow-direction nuance.
2. **Edge semantics.** `**Internal**: [database](database.md) for schema` carries a
   relationship *label* after the link. Whether v1 parses that label into the C4
   relationship description or drops it is unresolved.
3. **Which 3–4 `when` predicates** ship in v1. `has:migrations` is confirmed useful
   (Skouer is PLpgSQL-heavy). The rest should be chosen from what the manifest
   actually needs, not anticipated.
4. **Component-doc freshness.** The C4 model derives from component docs, which are
   themselves generated. A stale component doc yields a stale diagram. Whether the
   C4 producer should refuse to run against component docs older than some
   threshold is open.
5. **`blueprint-status.json` staleness.** It is written at sync time; the dashboard
   reads it later. There is no signal today for "this status predates the current
   repo state".

## User-Brand Impact

- **Artifact:** the KB blueprint manifest and the `/soleur:sync` producers that
  read it — specifically the artifacts written into a connected customer
  repository during onboarding.
- **Vector:** sync writes generated content into a customer's private repository
  under automation, on a fire-and-forget trigger at connect time
  (`apps/web-platform/app/api/repo/setup/route.ts` → `triggerHeadlessSync`).
  A generated artifact that is wrong, fabricated, or normatively worded is
  committed to a repo the customer owns and is discoverable in their git history.
  The coverage report specifically risks recording a customer's compliance gaps
  in their own tree.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** The dominant technical risk is letting customer-controlled content
reach a server render path — a per-workspace manifest would make
`/api/dashboard/foundation-status` parse untrusted JSON and stat an unbounded
path set, undoing ADR-067. Resolution is two artifacts, one trusted: a
plugin-owned manifest imported at build time, plus a per-repo
`blueprint-status.json` whose ids are joined against the manifest and discarded
if unknown. Entry schema needs an immutable `id` (rule-id discipline) plus the
presentation fields currently living in `OPERATIONAL_TASKS`, or the dashboard
needs a second lookup.

### Product

**Summary:** The central risk is that the manifest converts onboarding from
"Soleur did work for you" into an itemized inventory of what the company is
missing — the produced-to-demanded ratio inverts on day 1. The durable
contribution is a taxonomy rule adopted into the design: *a card is a request for
founder input; anything an agent can complete unattended is not a card, it is
work that should already have run.* Applied, technical output becomes evidence
rather than homework and the card grid does not double.

**Recorded dissent:** the CPO recommended against stub READMEs for all 10 domains
(directory litter; reads as colonizing a tester's repo that already has `docs/`,
`.agents/`, and `skills/`). The objection was presented to the operator, who
reaffirmed the original decision. Proceeding with stubs under the CLO wording
constraints. The CPO also recommended `alternate_paths` on manifest entries with a
path-probe-only adopt-vs-declare check ("we looked in X, Y, Z") — not adopted in
v1, retained here as a candidate refinement.

### Legal

**Summary:** No threshold row in `recommended-tools.md` fires; this is
founder-grade compliance helping. Two concrete controls are adopted into the
design: stub README wording is constrained to structural (never normative), with
the `recommended-tools.md` disclaimer carried verbatim in `legal/` and `finance/`;
and the gap file is reframed as a **KB coverage** report that states what the
manifest expects versus what is present, never what the business lacks, and stays
in-repo rather than being mirrored Soleur-side.

The CLO's blocker-level finding concerned ADR-mining specifically — that it is a
new processing activity requiring its own Article 30 entry (PA-17's display-only
carve-out was retired by the `[2026-07-31 CORRECTION (#7100)]`), a re-asserted
commit-author-email redaction (PA-22's `sanitizePromptString` TOM is explicitly
not inherited), dropping `%ae`/`%an` at extraction, key-posture confirmation, and
three legal documents updated in lockstep. **ADR-mining was subsequently cut from
scope entirely, so this control set is not required.** It is recorded here so
that any future revival of ADR-mining inherits the analysis rather than
re-deriving it.

## Capability Gaps

| Gap | Domain | Evidence | Why needed |
|---|---|---|---|
| No C4 bootstrap path | Engineering | `plugins/soleur/skills/architecture/SKILL.md` sub-commands are `create`, `list`, `supersede`, `diagram`, `add-container`, `add-component`, `add-relationship`, `render`, `assess`, `principle list` — all incremental hand-authoring. Read in full; no bootstrap-from-codebase step exists. | v1's C4 producer needs a generate-first-model path that does not exist today. |
| Dashboard path set declared twice | Engineering | `apps/web-platform/lib/kb-constants.ts` (`DASHBOARD_FOUNDATION_KB_PATHS`) and `apps/web-platform/app/(dashboard)/dashboard/page.tsx` (`FOUNDATION_PATHS` + `OPERATIONAL_TASKS`); reconciled only by a coverage test asserting `page.kbPaths ⊆ constants`. | The manifest must replace both, not one. |
| Coverage test scrapes source text | Engineering | The dashboard foundation-status test matches `kbPath: "…"` against `page.tsx` **source text**. Once cards derive from the manifest it will silently match nothing rather than fail. | Must be rewritten as manifest→card derivation before the rewire lands. |
| E2E seeds a fixed foundation set | Engineering | `apps/web-platform/e2e/start-fresh-onboarding.e2e.ts` mocks `{paths:{…}}` with `size: 1000` and asserts an all-complete state. | A manifest-driven seed helper is needed or the all-complete state stops triggering. |
| C4 viewing gated for non-`dev` roles | Engineering / Product | `apps/web-platform/lib/c4-constants.ts` defines `C4_VISUALIZER_FLAG`; `apps/web-platform/server/resolve-c4-eligible.ts` resolves `users.role != "dev"` to `"prd"`. | Alpha testers cannot view generated diagrams without a flag flip. |

## Session Errors

1. **CTO leader claim required correction.** The CTO assessment concluded C4 edges
   were not derivable and recommended deferring C4 — the operator's headline ask.
   The claim was accurate about the mechanical Component Detection Heuristics but
   missed that sync's Project Analysis step already extracts per-component
   dependencies, and that the alpha tester's synced output contains them in a
   consistent parseable form. Caught by checking the actual generated artifact
   (`gh api .../contents/knowledge-base/project/components/*.md`) rather than
   reasoning from the sync command's heuristics section alone. **Pattern: when a
   leader declares a generated artifact's content insufficient, read the generated
   artifact, not the generator's spec.**
2. **CPO premise required an empirical check.** The CPO flagged that Skouer was
   created 2026-08-04 and warned ADR-mining could return nothing against a
   squashed import. The repo in fact carries **5,351 commits** with ~100 in the
   preceding 28 hours — deep genuine history, migrated rather than squashed. The
   concern was well-formed but the premise was falsifiable in one API call, and
   it would have mis-sequenced the cut had it been accepted.
3. **Operator answers landed in the wrong question slot.** The ADR decision arrived
   as a note on the stub-README question, leaving the stub fork unanswered for a
   round. Re-asked in isolation rather than inferred.
