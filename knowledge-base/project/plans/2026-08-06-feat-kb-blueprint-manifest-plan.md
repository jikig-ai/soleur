---
title: "feat: KB blueprint manifest — one source of truth for knowledge-base composition"
date: 2026-08-06
branch: feat-kb-blueprint-manifest
issue: "#7332"
pr: 7336
type: enhancement
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
brainstorm: knowledge-base/project/brainstorms/2026-08-06-kb-blueprint-manifest-brainstorm.md
spec: knowledge-base/project/specs/feat-kb-blueprint-manifest/spec.md
design:
  - knowledge-base/product/design/dashboard/blueprint-cards-variant-a-two-zones.pen
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed: this plan provisions NO infrastructure. No server, systemd
  unit, cron, vendor account, DNS record, TLS cert, firewall rule, or Terraform
  resource. The one non-code change is flipping an EXISTING Flagsmith runtime flag
  (`c4-visualizer`) for alpha-tester roles, which routes through the existing
  `/soleur:flag-set-role` skill — a runtime-flag flip, not provisioning. No
  Terraform root is touched.
-->

# feat: KB blueprint manifest

## Overview

Four declarations of "what a Soleur knowledge base contains" exist and none agree.
Replace them with one plugin-owned manifest that `/soleur:sync`, the web dashboard,
and a new KB coverage report all read.

Measured on the first alpha tester (`2my8r9ry2t-wq/Skouer`): its synced
`knowledge-base/` holds **23 entries, 100% under `project/`** — no C4 model, no
domain-model register, no business domains. That is exactly sync's declared output
surface, so the gap is structural, not a sync bug.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| "Four hardcoded declarations" | Three are **in code** (`kb-constants.ts:59`, `page.tsx:42`, `page.tsx:86`); the fourth is sync's Output Locations table in `plugins/soleur/commands/sync.md` (markdown, not code) | Keep "four" — sync.md IS the authoritative declaration of what sync writes. Plan states which three are code and which is prose, since only the code ones need a compile-time replacement. |
| "10 KB domains" | **Confirmed: 10** tracked top-level dirs (`git ls-tree -d HEAD knowledge-base/`). Research reported 11 by counting `project/specs`, which is not top-level. | FR8 stands at 10. |
| `FOUNDATION_PATHS` has 5 entries | **4** (re-derived via awk over the literal block). Research said 5. | Plan uses 4. |
| `OPERATIONAL_TASKS` has 5 entries | **6** (re-derived). Research said 5. | Plan uses 6. Total `kbPath` literals in `page.tsx` = **10**. |
| Drift guard asserts the card set | Asserts `kbPaths.length >= 9` against **10** actual (`dashboard-foundation-status.test.ts:115`) | Loose bound — would not catch dropping one card. Phase 5 replaces it with an exact manifest-derived assertion, not a lower bound. |
| "ADR-067 preserved" (my earlier framing) | **ADR-067 is `adopt-swr-client-cache`.** The targeted-stat design is recorded in `knowledge-base/project/plans/2026-07-07-perf-dashboard-load-and-conversation-list-plan.md`, not an ADR. | Both constraints are real and distinct; both must survive. See TR1. |
| `statKnownPaths` fan-out is unbounded | Already bounded by `MAX_CONCURRENT_STAT` (`kb-reader.ts:374`), with a comment anticipating a large future caller | The ~40-entry cap is defense-in-depth, not the sole guard. Lowers the risk of the manifest-driven path set. |
| Web app can import from `plugins/` | **No precedent.** Zero TypeScript imports from `plugins/` in `apps/web-platform/`. `plugins/soleur/lib/heartbeat-manifest.ts` is the shape precedent but is not cross-imported. | Do NOT introduce a novel cross-boundary build import. Use a generated mirror + drift gate (see Phase 1). |
| `domain-model` is default-seed | Still **excluded** from `all` dispatch (`sync.md`) | Phase 4 promotes it. |
| C4 generation exists | No generation code. `architecture` skill only hand-authors; `c4-render.ts` renders `.c4` → JSON | Phase 3 builds the generator; reuses `c4-render.ts`'s validation discipline. |

## Architecture Decision (ADR/C4)

### ADR

**ADR-171 — KB composition is declared by a plugin-owned manifest.** Create via
`/soleur:architecture`. This is a new cross-boundary data contract between the CLI
plugin and the Next.js server, and the ADR corpus governs nothing about KB
composition today (`git grep -ril 'blueprint|kb.?manifest|foundation.?card'` over
`knowledge-base/engineering/architecture/decisions/` returns zero).

The decision records: the manifest is the single source of truth; it is
**plugin-owned and trusted** (never read from customer repo content); per-repo
applicability travels as a committed `blueprint-status.json` whose ids are joined
against the trusted manifest and discarded if unknown; and `done`-ness stays
filesystem-derived so a hand-authored file still completes a card without a re-sync.

Ordinal is **provisional** — highest existing is ADR-170. `/ship` re-verifies the
next free ordinal against freshly-fetched `origin/main`; if it moves, sweep
`plans/`, `specs/`, and every AC naming the ordinal in the same edit.

### C4 views

All three `.c4` files were read (not grepped). Enumeration per the completeness
mandate:

- **External human actors:** `founder`, `emailSender`, `betaContact`, `contributor`.
  No new actor — the alpha tester is a `founder`. **No change.**
- **External systems/vendors:** `github`, `connectedRepoPlugin`, and the rest of the
  `#external` set. No new vendor. **No change.**
- **Containers / data stores:** `platform.plugin.kb` (`model.c4:85`, `database
  "Knowledge Base"`). The **connected repo's knowledge-base is unmodeled** —
  `connectedRepoPlugin` (`:320`) models only the customer's `plugins/soleur/` dir,
  yet the customer KB is this feature's entire write target.
- **Access relationships:** `sync` has **no relationship edge anywhere in
  `model.c4`**, while every sibling skill has one (`brainstorm -> kb` `:625`,
  `plan -> kb` `:626`, `work -> kb` `:627`, `compound -> kb` `:628`,
  `architecture -> kb` `:629`). `dashboard` has no edge to the plugin or KB.

Concrete `.c4` edits (in-scope plan tasks, Phase 6):

1. `model.c4` — add `connectedRepoKb` as an `#external` database (the customer's
   `knowledge-base/`), the artifact sync writes and the dashboard stats.
2. `model.c4` — add `blueprint = component "KB Blueprint Manifest"` under
   `platform.plugin`.
3. `model.c4` — add edges: `sync -> connectedRepoKb`, `sync -> blueprint` (reads),
   `dashboard -> blueprint` (reads the generated mirror), `dashboard ->
   connectedRepoKb` (stats via `statKnownPaths`).
4. `model.c4:87` — update the `kb` description; it omits diagrams, the
   domain-model register, and the coverage report.
5. `views.c4` — add `blueprint` to the `components` include list (`:49-58`) and
   `connectedRepoKb` to `containers` (`:26-37`), or they will not render.
6. Regenerate `model.likec4.json` via `bash scripts/regenerate-c4-model.sh` and
   commit it — it is a lockfile, and `c4-model-freshness.test.sh` is an **orphan
   suite** only exercised by full-suite `test-all.sh`.

### Sequencing

The ADR is authored in Phase 6 alongside the C4 edits, describing the target state.
No `status: adopting` deferral is needed — the contract is fully true once Phase 1
lands.

## Implementation Phases

### Phase 1 — The manifest and its contract

**Design decision: generated mirror, not cross-boundary import.**

The CTO recommended the server import the manifest as a build-time module. Research
found **zero** precedent for `apps/web-platform/` importing from `plugins/`, making
that a novel build-graph change. The repo instead has two proven regenerate-and-diff
precedents: `lockfile-sync` in `ci.yml` and `c4-model-freshness.test.sh`.

So: manifest source is `plugins/soleur/kb-blueprint.json`; a generated TypeScript
mirror lands at `apps/web-platform/lib/kb-blueprint.generated.ts`; a CI gate
regenerates and `git diff --exit-code`s it. Single source of truth preserved, trust
property preserved (server never reads customer content), no novel build import.

Entry schema — every field load-bearing:

```jsonc
{
  "id": "engineering.c4-model",        // immutable; blueprint-status.json joins on it
  "path": "engineering/architecture/diagrams/model.c4",
  "domain": "engineering",
  "producer": "sync:c4",               // sync:* | agent:* | operator
  "owner": "soleur:architecture",      // skill or agent that can create it
  "tier": "seed",                      // seed | grown
  "when": "has:components",            // optional predicate; absent = always applicable
  "card": null                         // null = never renders as a card (see taxonomy)
}
```

`card` encodes the CPO's taxonomy directly: **a card is a request for founder
input; anything an agent completes unattended is not a card.** Entries with
`producer: sync:*` carry `card: null`. Business entries carry
`{ title, description, cta }` — seeded verbatim from today's strings, no rewording.

**Predicates.** Four hardcoded, no DSL: `has:migrations`, `has:components`,
`has:ci-workflows`, `has:web-ui`. Evaluated CLI-side against the synced repo.

**`blueprint-status.json`** — written by sync into the customer's KB:

```jsonc
{ "schema_version": 1, "generated_at": "<iso>", "entries": [{ "id": "...", "applicable": true }] }
```

Server reads it once, joins by `id`, **discards any id absent from the trusted
manifest**. Schema is declared as a shared TypeScript type and **runtime-validated**
on the server consumer — a silent field-name drift between CLI writer and server
reader produces no error, only wrong output.

Files: `plugins/soleur/kb-blueprint.json` (new),
`plugins/soleur/lib/kb-blueprint.ts` (types + loader, new),
`scripts/generate-kb-blueprint-mirror.sh` (new),
`apps/web-platform/lib/kb-blueprint.generated.ts` (generated),
`.github/workflows/ci.yml` (drift gate).

### Phase 2 — Coverage report + CLI output

Compute applicable-entry set → stat the KB → emit
`knowledge-base/project/kb-coverage.md` and print the same summary at end of sync.

**Wording is a hard constraint, not a preference.** The report states what the
manifest expects versus what is present. It never asserts what the business lacks:
"no `privacy-policy.md` present in this knowledge base", never "missing: privacy
policy". A committed, timestamped, git-blamed record that a customer lacks a privacy
policy is discoverable and reads as knowledge of non-compliance.

Files: `plugins/soleur/commands/sync.md` (new `coverage` area + `all` dispatch),
`plugins/soleur/lib/kb-coverage.ts` (new).

### Phase 3 — C4 producer

Parse each generated component doc's `## Dependencies` → `**Internal**:
[name](name.md)` links into an edge set; component docs are the element set. Emit
`spec.c4` / `model.c4` / `views.c4` into the customer's
`knowledge-base/engineering/architecture/diagrams/`, then render + validate.

**Validation gates on the diagnostic stream, not the exit code.** `likec4` exits 0
on broken sources and still emits a partial model, so an element-count check alone
silently publishes a broken diagram. Mirror `c4-render.ts`: grep the diagnostics for
`^Invalid |Could not resolve|^[[:space:]]+Line [0-9]+:` **and** assert
`.elements | length > 0`. Pin `likec4@1.50.0` (the version already pinned in
`regenerate-c4-model.sh` and `c4-render.ts`).

**`## Data Flow` prose is not parsed in v1** — the dependency links are the graph;
the flow line is human context.

Refuse to run when component docs are absent — a C4 model with no elements is worse
than none.

Files: `plugins/soleur/lib/c4-from-components.ts` (new), `sync.md` (new `c4` area).

### Phase 4 — domain-model promotion + stub READMEs

Promote the existing `domain-model` area from opt-in into the manifest as a seed
entry gated on `has:migrations`. Its `write-row` safety properties are preserved
**unchanged** — appends only to `## Auto-inferred (unreviewed)`, never mints a
`BR-*` id, refuses secret-shaped content fail-closed, dedups by content anchor,
writes atomically.

Stub READMEs for all 10 domains. **Wording constraint:** structural only
("documents of this type belong here; owned by the `clo` agent"), never normative
("you need a privacy policy"). `legal/` and `finance/` carry the
`recommended-tools.md` disclaimer verbatim — Soleur is a developer tool, not a law
firm / accountancy; output is draft material requiring professional review.

### Phase 5 — Dashboard rewire (approved wireframe: Variant A)

Delete `FOUNDATION_PATHS`, `OPERATIONAL_TASKS`, and `DASHBOARD_FOUNDATION_KB_PATHS`;
derive all three from the generated mirror. Render the two-zone layout: evidence
group above a rule, input-request group below capped at the 4 foundations with the
6 operational items behind `Show 6 more`. Coverage entry point sits in the evidence
zone.

Preserve: shipped corner radii, the existing foundation/operational split, existing
card copy, `overview/vision.md` as the first-run sentinel, and the targeted-stat
(no `buildTree()`) property.

**Test work is not optional cleanup — it is the phase's main risk.** Three suites
assert on the current shape, and the first one *fails open*:

- `test/api/dashboard-foundation-status.test.ts:114` regexes `page.tsx` **source
  text**. Once cards derive from the manifest it matches nothing and silently
  passes — a source-grep assertion cannot fail when its target disappears. Rewrite
  as manifest→card derivation with an **exact** count, not `>= 9`.
- `test/command-center.test.tsx:140` mocks foundation-status responses.
- `e2e/start-fresh-onboarding.e2e.ts:15` seeds a fixed path set at `size: 1000`.
  Needs a manifest-driven seed helper or its all-complete state stops triggering.

### Phase 6 — ADR-171 + C4 model edits

Per the Architecture Decision section. Regenerate and commit `model.likec4.json`.

### Phase 7 — c4-visualizer flag flip

Enable `c4-visualizer` for alpha-tester roles via `/soleur:flag-set-role`.
Generation is **not** gated on flag state — coupling an artifact decision to a
viewing feature leaves the repo permanently poorer. But do not ship Phase 3 to a
tester before this lands: generating a diagram the tester cannot open is worse than
not generating it.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_KB_BLUEPRINT_SYNC marker on stdout at end of every sync run,
        carrying {applicable, present, generated} counts
  cadence: per sync invocation (headless on repo connect, manual thereafter)
  alert_target: Better Stack (SOLEUR_* marker stream)
  configured_in: plugins/soleur/lib/kb-coverage.ts
error_reporting:
  destination: Sentry via reportSilentFallback, feature "kb-blueprint"
  fail_loud: true — a producer that cannot write its artifact reports; it does not
             silently emit a smaller coverage report
failure_modes:
  - mode: C4 render produces a broken/partial model (likec4 exits 0 on syntax error)
    detection: diagnostic-stream grep + .elements length assertion, both in-process
    alert_route: Sentry op "kb-blueprint.c4-render", and the run reports degraded
  - mode: blueprint-status.json schema drift between CLI writer and server reader
    detection: runtime schema validation on the server consumer; unknown ids discarded
               and counted
    alert_route: Sentry op "kb-blueprint.status-parse" when discarded > 0
  - mode: generated mirror drifts from the manifest source
    detection: CI regenerate + git diff --exit-code (lockfile-sync precedent)
    alert_route: CI failure — blocks merge
  - mode: predicate evaluates true but the producer emits nothing
    detection: coverage report shows applicable-but-absent for a sync:* producer,
               which is by definition a producer bug
    alert_route: SOLEUR_KB_BLUEPRINT_SYNC counts diverge; queryable without SSH
logs:
  where: sync stdout (Better Stack via the SOLEUR_* marker stream); Sentry for errors
  retention: per existing Better Stack + Sentry retention
discoverability_test:
  command: bash scripts/betterstack-query.sh 'SOLEUR_KB_BLUEPRINT_SYNC'
  expected_output: one line per sync run with applicable/present/generated counts
```

No SSH anywhere in the diagnostic path.

## Encryption Posture

Not applicable — this plan introduces no persistent data store and no new
cross-component network connection. `blueprint-status.json` and `kb-coverage.md` are
committed files in the customer's own git repository, written through the existing
headless-sync commit path; they add no new store, credential, or transport.

## User-Brand Impact

**If this lands broken, the user experiences:** a knowledge base in their own
repository containing generated files that are wrong — a C4 diagram whose edges
misrepresent their architecture, or a coverage report naming artifacts that do not
apply to their project. For the alpha tester this is the first substantive thing
Soleur produces for them.

**If this leaks, the user's data is exposed via:** sync writes generated content into
a private customer repository on a fire-and-forget trigger at connect time
(`auto-sync-trigger.ts:106`, `triggerHeadlessSync`). A producer that emits content
derived from a place it should not read, or a coverage report that records the
customer's compliance gaps in their own git history, is committed and permanent —
git history is not erasable.

**Brand-survival threshold:** `single-user incident`.

CPO sign-off is required and is carried forward from the brainstorm's Domain
Assessments (Product). `user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** Product, Engineering, Legal

Carried forward from
`knowledge-base/project/brainstorms/2026-08-06-kb-blueprint-manifest-brainstorm.md`
`## Domain Assessments` — CPO, CTO, and CLO were spawned in parallel at brainstorm
Phase 0.5 with verified-fact prompts.

### Engineering

**Status:** reviewed
**Assessment:** Dominant risk is letting customer-controlled content reach a server
render path. Resolved by a trusted plugin-owned manifest plus a per-repo status
artifact whose ids are joined and discarded-if-unknown. Entry schema needs an
immutable `id` plus the presentation fields currently in `OPERATIONAL_TASKS`.
**Plan divergence:** the CTO recommended a build-time cross-boundary import; the plan
uses a generated mirror + drift gate instead, because research found zero precedent
for `apps/web-platform/` importing from `plugins/`. Same trust property, proven
mechanism.

### Product

**Status:** reviewed
**Assessment:** Central risk is inverting the produced-to-demanded ratio on day 1 —
onboarding becoming an itemized inventory of what the company lacks. Adopted: the
taxonomy rule that a card is a request for founder input and agent-completable work
is not a card, encoded directly in the manifest's `card` field.
**Recorded dissent:** the CPO recommended against stub READMEs for all 10 domains.
The objection was put to the operator, who reaffirmed stubs. Proceeding under CLO
wording constraints (Phase 4).

### Legal

**Status:** reviewed
**Assessment:** No threshold row in `recommended-tools.md` fires; founder-grade
compliance helping. Two controls adopted into the plan: stub README wording
constrained to structural with the disclaimer verbatim in `legal/` and `finance/`
(Phase 4), and the coverage report reframed to state manifest expectation versus
presence, never business deficiency (Phase 2). The CLO's blocker-level finding
concerned ADR-mining, which was **cut from scope**, so its four-control set does not
apply. It is recorded in the brainstorm so a future revival inherits the analysis.

**Brainstorm-recommended specialists:** `ux-design-lead` — invoked at brainstorm
Phase 3.55; Variant A approved by the operator; `.pen` committed.

## Open Code-Review Overlap

Scanned 64 open `code-review` issues against the finalized file list. **One match.**

- **#2590** — `refactor(dashboard): extract useFirstRunAttachments + FirstRunComposer
  from DashboardPage`. Touches `app/(dashboard)/dashboard/page.tsx`, which Phase 5
  rewrites.
  **Disposition: acknowledge.** Different concern — #2590 targets the first-run
  attachment state and composer; Phase 5 touches the card-derivation block and the
  three hardcoded arrays. The two edits do not overlap line-wise, and folding a
  component extraction into an already-large PR would widen it for no shared
  benefit. Phase 5 removes ~60 lines from `page.tsx`, so #2590 stays valid and gets
  marginally easier afterward. Issue remains open.

No other planned file appears in any open code-review issue body.

## Acceptance Criteria

### Pre-merge (PR)

1. `plugins/soleur/kb-blueprint.json` exists; every entry has `id`, `path`,
   `domain`, `producer`, `owner`, `tier`.
2. Regenerating the mirror produces no diff:
   `bash scripts/generate-kb-blueprint-mirror.sh && git diff --exit-code apps/web-platform/lib/kb-blueprint.generated.ts`.
3. `git grep -n 'DASHBOARD_FOUNDATION_KB_PATHS\|FOUNDATION_PATHS\|OPERATIONAL_TASKS' apps/` returns **zero** matches outside the generated mirror and its tests.
4. The rewritten drift guard asserts an **exact** manifest-derived card count and
   **fails** when a card is removed. Verify by deleting one card entry locally and
   confirming a red test — a source-grep assertion that matches nothing must not
   pass.
5. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
6. `bash scripts/test-all.sh` green — required, not optional: `c4-model-freshness.test.sh`
   is an orphan suite that the touched-file loop does not reach.
7. `model.likec4.json` byte-identical to a fresh render of the edited `.c4` sources.
8. `views.c4` includes every element added to `model.c4`; a view referencing an
   undefined element fails the C4 tests, not `tsc`.
9. `ADR-171-*.md` exists and its ordinal is free on freshly-fetched `origin/main`.
10. Stub READMEs for all 10 domains contain no normative sentence; `legal/` and
    `finance/` contain the `recommended-tools.md` disclaimer verbatim.
11. `kb-coverage.md` output contains no string asserting a business deficiency.
    Assert the guardrail's **presence** (the expectation-vs-presence phrasing), not
    the absence of a forbidden token — the generator's own prohibition comment
    legitimately contains the token.
12. `blueprint-status.json` schema validated at the server consumer; a fixture with
    an unknown `id` is discarded and counted, not thrown on.

### Post-merge (operator)

13. `c4-visualizer` enabled for alpha-tester roles via `/soleur:flag-set-role`.
    *Automation: feasible* — runs in-session through the existing skill, not a
    dashboard click.
14. Re-sync `2my8r9ry2t-wq/Skouer`; confirm the generated C4 model's elements are
    its 7 components and its relationships match their `## Dependencies` links.
15. Confirm the tester can open the diagram in the KB viewer.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The drift-guard rewrite fails open — a source-grep test that matches nothing passes | AC4 requires demonstrating a red test by removing a card. Do not accept "the suite is green" as evidence the guard works. |
| `likec4` exits 0 on broken `.c4` sources and emits a partial model | Gate on the diagnostic stream **and** element count, mirroring `c4-render.ts`. Never gate on exit code alone. |
| `model.likec4.json` ships stale | It is a lockfile. Regenerate + commit in the same edit; full-suite is the backstop. |
| Generated mirror drifts from manifest source | CI regenerate + `git diff --exit-code`, the `lockfile-sync` precedent. |
| Scope is large for one PR | Phases 1–2 are independently shippable and already improve the tester's onboarding. If plan-review judges the PR too large, cut at Phase 2 and carry 3–7 into a follow-up; the manifest contract is the part everything else depends on. |
| Learning `2026-03-02-github-actions-auto-push-vs-pr-for-bot-content` recommends direct push for machine-generated content | **Does not apply.** `sync.md`'s Headless Execution Contract §2 explicitly forbids pushing the protected default branch and mandates the worktree→PR path, treating a push rejection as degraded rather than failed. The contract is the more specific constraint for this exact code path and wins. Recorded so the conflict is not silently re-litigated. |
