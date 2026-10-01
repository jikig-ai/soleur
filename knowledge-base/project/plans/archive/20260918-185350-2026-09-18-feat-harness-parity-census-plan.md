---
title: "feat(harness): cross-harness parity census for skill invocation forms"
date: 2026-09-18
slug: feat-harness-parity-census
branch: feat-harness-parity-gate-8299
issue: 8299
closes: 8299
lane: cross-domain
type: feature
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-09-18-cross-harness-parity-gate-brainstorm.md
spec: knowledge-base/project/specs/feat-harness-parity-gate-8299/spec.md
---

## Overview

> **Plan of record is v3** (`# PLAN v3 — allowlist predicate over the name index`, near the end of
> this file). v1 and v2 below are retained as the review record; each is marked SUPERSEDED at its
> boundary. Read `## v2 review complete (3 of 3)` before v3 — it is the derivation of v3's predicate.

Soleur ships one skill tree to four harnesses that resolve invocation forms differently.
Nothing today requires a skill which instructs an agent to invoke another skill or agent to
name the form for each harness, and nothing detects a forgotten one — so a Claude-only slash
form reaches a Grok, Codex or Devin operator as a dead command.

This plan adds a born-blocking census over the skill tree that classifies every skill as
qualified, auto-exempt or unclassified, backfills the unqualified ones, and subsumes the
hand-listed marker array that the anti-vacuity ADR forbids.

## Research Insights

### Carry-forward, not re-run

Five agents (CPO, CLO, CTO, repo-research, learnings-research) ran on this exact question
earlier today; their findings are recorded in the brainstorm and are carried forward rather
than re-dispatched. Phase 1 here was one scoped agent covering only what those five did not:
CI registration, per-skill insertion anchors, `harness.ts` blast radius, `components.test.ts`
interaction, ledger placement, and existing count assertions.

### Premise Validation (Phase 0.6)

| Cited | Probe | Result |
| --- | --- | --- |
| #8299 | `gh issue view` | OPEN; body re-scoped in place with measured corrections |
| #7453 | `gh issue view` | OPEN — owns the ~105 `:-` sites. **Not** re-filed |
| #8306 / #8307 / #8308 | filed this session | OPEN; carry the out-of-scope axes |
| ADR-179 | read firsthand | `:-` default IS the vector; bare anchor canonical |
| ADR-193 | read firsthand | **Partially applicable — see reconciliation below** |
| ADR-224 §1 | read firsthand | Forbids an unqualified cross-harness rule → NG4 stands |
| ADR-223 §5 | read via ledger | `devin-dispositions.tsv` is the ledger shape precedent |
| `scripts/test-all.sh:2634` | `sed -n` | `run_suite "plugins/soleur" bun test plugins/soleur/` ✓ |
| `.github/workflows/ci.yml:942` | `grep -n` | `bash scripts/test-all.sh bun` — no shard/filter args |
| `devin-cloud-mode.test.ts:450` | read | marker fleet describe; `UNION` 20 names; `toBe(67)` |
| C4 count parity | ran the gate | 10/10 PASS; no gated cardinality concerns skills or harnesses |
| GDPR gate | ran on plan+spec | `2 examined, 0 matched` — no regulated surface |

### Property List (Phase 0.6b)

- **P1** A skill that instructs an agent to invoke another skill or agent names the invocation
  form for each supported harness, or cites the adapter that resolves them.
- **P2** A skill failing P1 is detected before merge, not by operator eyeball.
- **P3** A deliberate exception is recorded with a dated, falsifiable reason.
- **P4** The detector cannot go quietly blind — neither by an empty population nor by a
  trigger pattern that stops matching.
- **P5** A newly added skill is not silently exempt.

### Cut List (Phase 0.6b)

| Cut mechanism | Property it claimed | What already covers it |
| --- | --- | --- |
| Marker-block stripping before trigger scan | P2 accuracy | Nothing — **measured as a no-op**: stripping moves the population 38→38 and 46→46, and a block-only skill is qualified anyway, so it can never produce a false RED |
| Renaming `grok-harness-invoke` → `harness-invoke` | none | Buys no property. Would dirty 2 knowledge-base docs and create a migration surface for cosmetics. The misnomer is recorded in a test comment instead |
| A single convergent rule bullet across 6 skill-authoring skills | P1 prevention | **Forbidden** by ADR-224 §1 — an unqualified cross-harness rule is the anti-pattern it names |
| A new `AGENTS.rules.md` rule | P1 prevention | `cq-agents-md-tier-gate` — single-file trigger ⇒ domain-scoped ⇒ owning skills |
| Diff-scoped detection | P2 | Cut: shallow `actions/checkout` breaks `git merge-base`, yielding an empty changed set and a vacuous exit 0 |
| ~~Separate floors file~~ **— cut, then reinstated** | P4 anchoring | Reinstated on constitution L142: *"a declared number cannot catch its own reduction, so the assertion must be external to the declaration."* Recorded because the reversal is the informative part |

### Measurements (re-derived 2026-09-18, `origin/main`)

| Quantity | Value | Command |
| --- | --- | --- |
| Tracked skills (population) | **98** | `git ls-files 'plugins/soleur/skills/*/SKILL.md' \| wc -l` |
| Trigger-bearing (widened pattern) | **46** | python scan, 12 alternatives |
| Trigger-bearing (narrow 6-alt pattern) | 38 | the spec's original pattern — **8 short** |
| Qualified (`grok-harness-invoke`) | **12** | `git grep -l 'grok-harness-invoke:start'` |
| Unclassified → backfill | **34** | 46 − 12 |
| Auto-exempt | **52** | 98 − 46 |
| `soleur-cloud-mode` blocks | 64 skills + 3 devin shims = **67** | matches the existing pin exactly |

### Key mechanics the scoped agent established

- **Zero CI registration.** `bun test plugins/soleur/` recurses and auto-discovers. `lefthook.yml`
  already fires twice (`plugin-component-test` glob `plugins/soleur/**/*.md`; `bun-test` glob
  `*.{ts,tsx,js,jsx}`). `SUITE_GLOBS` and `lint-orphan-test-suites.sh` are `.test.sh`-suffix-keyed,
  so a `.test.ts` is outside the orphan check by construction.
- **Insertion anchor is per-skill, not uniform.** 24 of 34 already carry a `soleur-cloud-mode`
  block first; the new block goes strictly **after** its `:end`. `markerBlock()` uses a non-greedy
  `[\s\S]*?`, so inserting *inside* would break byte-identity for all 24. The 10 without a
  cloud-mode block anchor on frontmatter.
- **`marked.length` does not move.** `MARKER_START`/`MARKER_END` are the literal
  `soleur-cloud-mode` comments, so a `grok-harness-invoke` block is invisible to that census.
- **`harness.ts` has 3 importers**, all under `plugins/soleur/lib/` (`harness-model-map.ts`,
  `pr-merge-poll.ts`, `workflow-fidelity.ts`); zero under `apps/**`. Deriving `Harness` from a
  runtime array yields the identical 5-member union **provided `| "unknown"` is kept** — dropping
  it breaks `detectHarness` (`:80`) and the `unknown` branch (`:465`).
- **`SKILL_DESCRIPTION_WORD_BUDGET = 2442` sums `description:` words only** — body lines are not
  measured, so 34 × ~3 lines cannot move it. But `components.test.ts:238` asserts no backticked
  path beginning `scripts/`, `references/` or `assets/` appears in a skill body; the canonical
  block's `plugins/soleur/lib/harness.ts` citation is safe and must stay that shape.
- **No runtime harness list exists to reuse.** `TIER_MAPS` is keyed `claude`/`grok` only (2 of 4).
  Two ad-hoc 4-harness literals exist in tests and become consumers of the new const.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (as first written) | Codebase reality | Plan response |
| --- | --- | --- |
| Population = trigger-derived, 38 members | A 6-alternative pattern misses 8 skills; population-by-regex makes the gate's own scope depend on a guess | **Population is now all 98, directory-derived.** The widened 12-alternative pattern decides only whether a block is *required*. Spec FR1 corrected |
| 26 skills to backfill | 34 under the widened pattern | Spec FR8 + ACs corrected |
| TR4: floor mechanics per ADR-193 — `printf >&2` + `exit 1`, counter at call site | ADR-193's Context is bash suites; its enforcing guard `guard-vacuity-floor.test.sh` enumerates tracked `*.test.sh`, so a bun test is **outside its population**. There is no "suite's own verdict helper" to bypass where `expect()` *is* the reporting mechanism | Spec TR4 rewritten: Decision **5** binds (population derived, never listed); Decision **1** does not. Because the corpus guard cannot police this suite's floor, TR6's mutation test is **mandatory**, not optional |
| FR7: the `toBe(67)` pin moves with the backfill | It does not — that census keys on the `soleur-cloud-mode` literal and cannot see a `grok-harness-invoke` block | Spec FR7 corrected; an AC now asserts it stays 67 |
| FR9 (implied): insert after frontmatter | Wrong for 24 of 34 — the anchor is after `soleur-cloud-mode:end` | Spec FR9 added with the measured 24/10 split and the 10 names |
| Single inverted `.highwater` on population size | A population *floor* cannot catch a trigger-pattern regression that silently moves skills into auto-exempt | Spec FR6 rewritten as four assertions incl. an **auto-exempt ceiling** and a **trigger-count floor** |

## Open Code-Review Overlap

65 open `code-review` issues queried. **No overlap with this plan's Files to Edit.** Three
matched on the broad `plugins/soleur/skills` substring only:

- **#4133** — schema parity test for the `## Observability` block. *Disposition: **acknowledge**.*
  A sibling parity gate over a different population (plan documents, not skills) and a different
  block. Folding it in would widen this PR across two unrelated block families; the census pattern
  this plan establishes is the natural template for it later.
- **#3531** — `marketing-content-drift.test.ts` hook-timeout flake. *Disposition: **acknowledge**.*
  Unrelated subsystem.
- **#2592** — force download disposition for committed SVGs. *Disposition: **acknowledge**.*
  Unrelated subsystem.

## Files to Create

- `plugins/soleur/test/harness-parity.test.ts` — the census.
- `plugins/soleur/test/harness-parity-exempt.tsv` — the exemption ledger. Flat beside the test,
  matching the `fixture-*-assert.baseline.txt` precedent. **Not** under `fixtures/`, which is
  synthesized test input per `cq-test-fixtures-synthesized-only`; a real ledger is neither.
- `plugins/soleur/test/harness-parity-floors.txt` — the four floors, external to the assertion.
- `knowledge-base/engineering/architecture/decisions/ADR-226-harness-parity-census-derives-its-population-and-its-harness-set.md`

## Files to Edit

- `plugins/soleur/lib/harness.ts` — add `export const SUPPORTED_HARNESSES = ["claude","grok","codex","devin"] as const;`
  and derive `export type Harness = typeof SUPPORTED_HARNESSES[number] | "unknown";` (keep `"unknown"`).
- `plugins/soleur/test/devin-cloud-mode.test.ts` — delete the 20-name `UNION` array; re-express its
  "every union member is marked" assertion against a derived population.
- **46 × `plugins/soleur/skills/*/SKILL.md`** — 34 gain the block; 12 have theirs extended to name
  Codex and Devin. `one-shot`'s drifted wording is normalised within that 12.
- `plugins/soleur/test/harness-model-map.test.ts` (~`:76`) and
  `plugins/soleur/test/workflow-fidelity.test.ts` (~`:373`) — replace ad-hoc 4-harness literals with
  `SUPPORTED_HARNESSES`, so this PR does not leave a third hand-list behind.
- `knowledge-base/project/specs/feat-harness-parity-gate-8299/spec.md` — already corrected.
- `knowledge-base/project/brainstorms/2026-09-18-cross-harness-parity-gate-brainstorm.md` and
  `knowledge-base/project/learnings/2026-09-18-a-census-cell-naming-two-markers-reports-the-union-as-each-member.md`
  — update the 26 → 34 and 38 → 46 figures so the record matches the shipped gate.

## Implementation Phases

Phase order is dependency-directed: the contract (the harness set) lands before its consumers,
and the guard's mutation matrix is written before the guard.

### Phase 0 — Preconditions (no product code)

1. Re-verify the population, trigger and qualified counts (98 / 46 / 12) from inside the worktree.
2. Confirm `bun test plugins/soleur/` is green at HEAD (baseline).
3. Re-probe the ADR ordinal across **all** `origin/*` refs. ADR-226 measured free; ADR-225 is taken
   on a remote ref but absent locally, which is exactly why the probe is ref-wide and must be
   repeated immediately before merge.

### Phase 1 — Write the mutation matrix (before the guard)

Author `## Guard Contract` below into the test file as a header comment. Phase 2.12 is explicit
that a matrix derived from finished code tests the code that exists, not the property.

### Phase 2 — The harness set becomes runtime (contract first)

1. Add `SUPPORTED_HARNESSES` to `harness.ts`; derive `Harness` from it, retaining `| "unknown"`.
2. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is **not** the right check here —
   `harness.ts` is plugin code. Run the plugin suite and confirm the 3 importers still typecheck.
3. Repoint the two ad-hoc test literals at the new const.

### Phase 3 — The census (RED first)

Write `harness-parity.test.ts`. On today's tree it must report **34 unclassified** and FAIL,
naming every path. A green first run means the classifier is wrong.

### Phase 4 — Ledger and floors

Create the TSV and the floors file. Strict, fail-closed parsing per constitution L139/L140: a
missing, unreadable or malformed ledger, or an unrecognised disposition, is RED — never a silently
empty exemption set.

### Phase 5 — Backfill (GREEN)

1. Extend the canonical block to name all four harnesses.
2. Apply it to the 34, respecting the measured per-skill anchor (24 after `soleur-cloud-mode:end`,
   10 after frontmatter).
3. Extend the 12 existing blocks; normalise `one-shot`.
4. Confirm `devin-cloud-mode.test.ts` still reports `marked.length == 67`.

### Phase 6 — Subsume the `UNION` array

Delete it and re-express its assertion derived. This is the ADR-193 §5 obligation and the reason
the census supersedes rather than sits beside the existing guard.

### Phase 7 — ADR-226 + record sync

Author the ADR. Update the brainstorm and learning figures. Run the full battery.

## Guard Contract — v1 (SUPERSEDED; retained as review record)

### Guard 1 — cross-harness invocation-form census

**Property.** Every tracked skill under `plugins/soleur/skills/` either names the invocation form
for all four supported harnesses (or cites the adapter that resolves them), or carries a dated,
issue-linked exemption. No skill is silently unclassified, and the detector cannot report a
clean verdict over a population it failed to enumerate.

**Assembly.** Not a list of the skills that exist today. The chokepoints the property quantifies
over are: (1) the population — `git ls-files 'plugins/soleur/skills/*/SKILL.md'`, derived from the
git index, never enumerated; (2) the required harness set — `SUPPORTED_HARNESSES` in
`plugins/soleur/lib/harness.ts`, the single runtime source, so a fifth harness widens the
obligation without touching this test; (3) the qualification carrier — the
`grok-harness-invoke` marker block, instantiated per skill name; (4) the exemption channel — one
TSV, strictly parsed; (5) the four floors, in a file external to the assertion. There is more than
one chokepoint, and the gate is scoped to all five.

**Mutation matrix.** Each row MUST drive the suite RED.

| # | Mutation | Targets |
| --- | --- | --- |
| M1 | Delete the `grok-harness-invoke` block from any one qualified skill | the core property |
| M2 | Add a new skill directory with a `SKILL.md` containing `Skill tool` and no block | **second member after a compliant first** — a check that stops at the first skill passes M1 but fails here |
| M3 | Neuter the population glob so it resolves to zero files | **the guard's own dispatch** — `0 checked` must FAIL, not pass vacuously |
| M4 | Remove one alternative from the trigger pattern | a silent migration of skills into auto-exempt; caught by the trigger-count floor, not by the unclassified assertion |
| M5 | Add a fifth member to `SUPPORTED_HARNESSES` | the requirement must widen and RED until blocks are updated |
| M6 | Add a new skill with neither block nor trigger | auto-exempt ceiling — RED-by-default for anything newly added |
| M7 | Replace a ledger row's disposition with an unrecognised token | fail-closed parsing |
| M8 | Delete the ledger file entirely | fail-closed on a missing input, not "zero exemptions" |
| M9 | Copy a block verbatim from another skill (wrong skill name inside) | template instantiation, not mere presence |

**Harness rows.** Mutations of the *suite*, not the system under test.

| # | Mutation | Must |
| --- | --- | --- |
| H1 | Delete the body of the unclassified assertion, leaving the describe | **RED.** If the suite stays green with its own assertion gone, it pins nothing (TR6) |
| H2 | Point the census at an empty temp directory | **RED** via the `0 checked` floor |
| H3 | A skill qualified via an **adapter citation** rather than a marker block | **PASS.** A non-canonical input the contract explicitly permits — without this row the matrix cannot detect a classifier that rejects everything |
| H4 | A ledger row that is well-formed but for a skill that *does* carry a block | **PASS**, and the skill counts as QUALIFIED, not EXEMPT — the ledger must not mask a satisfied obligation |

**Anchor.** The floors are a stored value compared against a derived one, so they prove
consistency, not integrity: one diff can lower a floor and remove the skills it protected. Stated
rather than papered over. What limits it: the population denominator is `git ls-files`-derived, not
credential-scoped, so the silent-narrowing failure constitution L142 guards against is structurally
absent here — a narrowing is a visible file deletion in the diff. The floors live in a file separate
from the assertion so any weakening is a distinct, reviewable diff hunk. They are not, and are not
claimed to be, tamper-proof.

## Architecture Decision (ADR/C4)

Phase 2.10 fires: this establishes a cross-cutting authoring invariant every skill must honour, and
single-sources the supported-harness set in code.

### ADR

**ADR-226 — A harness-parity census derives its population from the tree and its harness set from
code; an unclassified skill is RED.** Records: population derived not listed (ADR-193 §5 applied to
a TS suite, with the explicit finding that ADR-193's Decision 1 is bash-scoped and does not bind);
the three-verdict model with auto-exempt derived so the ledger stays load-bearing; the auto-exempt
**ceiling** as the RED-by-default mechanism for newly added skills; and `SUPPORTED_HARNESSES` as the
single runtime source, superseding the type-only union.

Alternatives to record as considered and rejected: a universal 98-skill marker requirement (~60
ledger rows asserting nothing real); a trigger-derived *population* (the gate's scope depends on a
regex guess — the defect that produced the 38-vs-46 gap); an advisory phase (zero-for-N in this
repo); and mirror completeness for the hand-ported trees (deferred to #8306, gated on a product
decision `lib/harness.ts` cannot make).

**The ordinal is provisional.** ADR-226 measured free across all `origin/*` refs; ADR-225 is taken
on a remote ref and absent locally, which is precisely the collision shape the Sharp Edge warns
about. Re-derive immediately before merge and sweep this plan, the spec and any AC naming the
ordinal in the same edit if it moves.

### C4 views

**No C4 edit required**, and here is the enumeration that conclusion rests on — a bare "None" is a
reject condition.

- **External human actors:** `founder` (`model.c4:30`), `contributor` (`:69`). No new actor; no
  actor gains or loses access.
- **External systems — all four harnesses are already modelled:** `codex` (`:8`),
  `devin` (`:22`), `grokBuild` (`:211`). Claude Code is represented through
  `founder -> soleurMarketplace` (`:518`) and the `platform.plugin` system rather than as a
  discrete element — a pre-existing asymmetry this change neither creates nor worsens, recorded as
  an observation for #8306 rather than fixed here.
- **Containers / data stores:** `skillloader` (`:102`) already describes discovering and loading
  skills. No new container; no store.
- **Access relationships:** `grokBuild -> plugin` (`:422`) already records the
  `GROK_PLUGIN_ROOT` then `CLAUDE_PLUGIN_ROOT` precedence; `codex -> platform.plugin` (`:14`) and
  `devin -> platform.plugin` (`:28`) already record canonical-skill sharing. This plan changes no
  modelled relationship — it constrains prose *inside* skills the `skillloader` already loads.
- **Derived cardinalities:** `plugins/soleur/test/c4-count-parity.test.sh` run green, **10/10**.
  All gated counts concern cron monitors, Sentry check-ins and Resend emitters; none is a skill or
  harness count, so nothing this plan moves is gated.

### Sequencing

The ADR is true the moment the census merges. No soak, no `status: adopting`.

## User-Brand Impact

**If this lands broken, the user experiences:** a census that reports green over a skill tree it
failed to enumerate — the same blind spot as today, now wearing a passing check. Or, if the
classifier over-fires, a blocked merge queue on a compliant tree.

**If this leaks, the user's workflow is exposed via:** no new data surface. The exposure this
prevents is a self-hosted operator on Grok, Codex or Devin following plugin-shipped prose that
names a Claude-only form, hitting a dead command at the moment they are trying to act, concluding
the plugin is broken, and uninstalling without filing anything. The harm is **silent churn** — no
error surfaced, no signal back.

**Brand-survival threshold:** `single-user incident`. Carried forward from the brainstorm;
confirmed by CPO and CLO. ADR-179's own frontmatter carries the same threshold for this class.

`requires_cpo_signoff: true`. CPO reviewed this at brainstorm Phase 0.5 and its framing is carried
forward verbatim. `user-impact-reviewer` runs at review time and should be told to enumerate
**uninstall-without-report** paths — the failure mode here is quiet, not a visible incident.

## Observability

This is plugin code executing on a customer's self-hosted CLI — **observability layer 7**.

```yaml
liveness_signal:
  what: the harness-parity census result in the `test-bun` CI job
  cadence: every push and every PR (ci.yml:942 `bash scripts/test-all.sh bun`)
  alert_target: the failing required check on the PR
  configured_in: .github/workflows/ci.yml (no new registration — bun auto-discovery)
error_reporting:
  destination: CI job output; the test names every offending skill path on failure
  fail_loud: true — born blocking; a census that cannot enumerate its population FAILS
failure_modes:
  - mode: a skill loses its block
    detection: the unclassified assertion names the path
    alert_route: failing required check
  - mode: the trigger pattern silently stops matching
    detection: the trigger-count floor (the unclassified assertion would pass vacuously)
    alert_route: failing required check
  - mode: the population glob resolves to zero
    detection: the `0 checked` floor
    alert_route: failing required check
  - mode: a newly added skill is neither qualified nor triggered
    detection: the auto-exempt ceiling
    alert_route: failing required check
logs:
  where: CI job logs; no runtime emission (this is a build-time gate, not a runtime path)
  retention: GitHub Actions default
discoverability_test:
  command: bun test plugins/soleur/test/harness-parity.test.ts
  expected_output: "0 unclassified; 98 skills examined; 46 trigger-bearing; 12 -> 46 qualified"
```

No `credentials_required`: the gate reads only tracked files. No SSH anywhere
(`hr-no-ssh-fallback-in-runbooks`).

## Domain Review

**Domains relevant:** Product, Legal, Engineering

Carried forward from brainstorm Phase 0.5 (`## Domain Assessments`). CMO omitted per
`hr-new-skills-agents-or-user-facing`'s one-line-rationale allowance: operator-facing dev tooling
with no user-facing surface to amplify.

### Product (CPO)

**Status:** reviewed
**Assessment:** A hand-listed harness set reproduces the reported bug one level up. The floor is
zero unclassified, not 98/98 markers — "the registry does the real work." The user is a self-hosted
installer on a non-Claude harness; the operator is the detector, not the user.

### Legal (CLO)

**Status:** reviewed
**Assessment:** No material legal surface — no personal data, no processing activity, no Article 30
row, no DPIA. GDPR gate re-run on this plan and spec: `2 examined, 0 matched`. One watch-item
carried forward: the two vendored MIT works (`LICENSES/hallmark.MIT.txt`,
`LICENSES/skill-security-auditor.MIT.txt`) backing `frontend-anti-slop` and `skill-security-scan`
are not mirrored today; if a future change widens the mirrors to either skill, MIT notice must
travel with the copy. Binding on this plan: do not bless a `:-` form.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Host resolves to TypeScript; whole-tree, never diff-scoped; the classifier is the
design, not the regex (`Skill tool` appears in 14 skills, `/soleur:` in 32). `devin-cloud-mode.test.ts:450`
is the extension point, not greenfield. The 105 `:-` sites are standing ADR-179 violations and must
stay their own issue (#7453). Blast radius of a miss: all operators on non-Claude harnesses.

### Product/UX Gate

**Tier:** none — no UI surface. No path in Files to Create/Edit matches the UI-surface glob
superset (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`); the deliverable is a CI
test, a TSV, a floors file, an ADR and markdown prose inside skill documents.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `bun test plugins/soleur/test/harness-parity.test.ts` FAILS on the pre-backfill tree,
      reporting exactly **34** unclassified and naming each path.
- [ ] AC2 After backfill: PASSES with `0` unclassified, `98` examined, `46` trigger-bearing,
      `46` qualified, `52` auto-exempt. `46 + 52 == 98`.
- [ ] AC3 Every mutation row M1–M9 drives the suite RED (evidence: one line per row).
- [ ] AC4 Every harness row H1–H4 behaves as specified — H1/H2 RED, H3/H4 PASS.
- [ ] AC5 `bun test plugins/soleur/test/devin-cloud-mode.test.ts` green, with
      `marked.length == 67` **unchanged**.
- [ ] AC6 `UNION` array absent: `grep -c 'UNION' plugins/soleur/test/devin-cloud-mode.test.ts` == 0.
- [ ] AC7 `SUPPORTED_HARNESSES` is the only 4-harness literal in the plugin:
      `git grep -c '"codex"' -- 'plugins/soleur/lib' 'plugins/soleur/test' | grep -v harness.ts` shows
      no surviving ad-hoc list.
- [ ] AC8 `Harness` union unchanged for all 3 importers — `"unknown"` retained; plugin suite green.
- [ ] AC9 `SKILL_DESCRIPTION_WORD_BUDGET` unmoved (description words only; body lines unmeasured).
- [ ] AC10 `components.test.ts:238` still green — the block introduces no backticked path beginning
      `scripts/`, `references/` or `assets/`.
- [ ] AC11 No `${CLAUDE_PLUGIN_ROOT:-` and no `${GROK_PLUGIN_ROOT:-` introduced by this PR:
      `git diff origin/main...HEAD | grep -c 'PLUGIN_ROOT:-'` == 0.
- [ ] AC12 The 24/10 insertion split holds: no new block lands inside a `soleur-cloud-mode` block.
- [ ] AC13 `bash scripts/test-all.sh` full battery green.
- [ ] AC14 ADR-226 exists, ordinal re-verified against freshly-fetched `origin/*` refs; if it moved,
      this plan, the spec and every AC naming it were swept in the same edit.
- [ ] AC15 `python3 scripts/lint-guard-contract.py` green on this plan.
- [ ] AC16 Brainstorm and learning figures updated (26 → 34, 38 → 46) so the record matches the gate.
- [ ] AC17 `Ref #8306`, `Ref #8307`, `Ref #8308`, `Ref #7453` — none folded in, none closed.

### Post-merge

- [ ] AC18 `postmerge` confirms the `test-bun` job ran the new suite on the merge commit.
      No operator action: the gate is a CI test with no deploy surface.

## Risks

| Risk | Mitigation |
| --- | --- |
| Block inserted inside a `soleur-cloud-mode` block breaks byte-identity for 24 skills | FR9 — anchor strictly after `:end`; AC12 |
| Deriving `Harness` from the array drops `"unknown"` and breaks `detectHarness` | Keep `\| "unknown"`; AC8. The 5-member union stays type-identical for all 3 importers |
| The widened trigger pattern is still incomplete | Unfalsifiable by construction — no regex can be proven complete. Mitigated by the auto-exempt **ceiling** (a new unmatched skill REDs), the trigger-count floor, and M4/M6 |
| A floor is lowered in the same diff that removes what it protected | Named in the Guard Contract Anchor, not papered over. Separate file ⇒ separate reviewable hunk; denominator is index-derived so it cannot silently narrow |
| ADR-226 collides during the pipeline | Ordinal probed ref-wide, re-probed before merge, swept across plan + spec + ACs if it moves (AC14) |
| Scope creep into #7453's 105 `:-` sites | NG2 + AC11 |

## Plan Review — BLOCKING finding (P0). This plan requires a v2 before `/work`.

**The qualification carrier does not carry the property.** Raised by `dhh-rails-reviewer`,
verified firsthand before acceptance.

`grok-harness-invoke` is a **self-invocation preamble**: it tells an agent that has already
landed in this SKILL.md how it should have arrived. It asserts nothing about how the file
instructs invocation of *other* skills — which is exactly what property P1 is about.

Verified instance — `plugins/soleur/skills/ship/SKILL.md` carries the block, so the census scores
it **QUALIFIED**, and its Phase 5.4 (`:504`) reads:

```
Invoke the preflight skill via the **Skill tool**:
- If `HEADLESS_MODE=true`: `skill: soleur:preflight`, args: `--headless`
```

Grok has no Skill tool. A Grok operator running `/ship` reaches Phase 5.4 and hits a dead
instruction. **That is the originating defect of #8299, and AC2 goes green over it.**

Scale of the class, measured two ways that disagree on magnitude but not on direction: the
reviewer counted ~71 such body lines across the 12 qualified skills; a broader line-based scan
here counted **106** (ship 25, plan 20, brainstorm 16, work 11). Both are prose heuristics, so
the true figure needs a real classifier — but every method agrees the qualified set is riddled.

**Why every mutation row missed it.** M1–M9 and H1–H4 all test *enumeration* — is the block
present, is the population derived, does the floor fire. Not one row tests the *implication*
("a skill carries a valid block AND still dispatches via a Claude-only form"). Adding that row
fails the plan against its own matrix, which is how this should have been caught before 454 lines.

### Consequences for v2

- A **presence** census is the wrong shape. The candidate replacement is a **negative-space**
  assertion over a closed token set: a SKILL.md body names no harness-specific invocation token
  (`Skill tool`, `Task tool`, `/soleur:`, `$soleur:`, `spawn_subagent`, `run_subagent`) and instead
  names the canonical `soleur:<skill>`, which each harness's mapping document resolves. That
  predicate is **provable complete** against `plugins/soleur/lib/harness.ts`, where the forms are
  defined — where the trigger pattern was admittedly unprovable.
- **Gap that blocks the replacement:** `plugins/soleur/codex/INSTRUCTIONS.md` and
  `plugins/soleur/devin/INSTRUCTIONS.md` exist; **`plugins/soleur/grok/INSTRUCTIONS.md` does
  not** (verified). So "cite the adapter" is not yet a real path on Grok. Writing that one file
  is a prerequisite of the inversion.
- The floors file, the AUTO-EXEMPT verdict, the ceiling, the trigger-count floor and rows
  M4/M6 are all struts for an unprovable predicate. They come out with it.
- **Self-inflicted contradiction, conceded:** the Cut List reinstated the floors file on
  constitution L142 while the Guard Contract Anchor simultaneously measured L142's
  credential-scoped precondition as *structurally absent*. Both halves were written into the same
  document. The reinstatement was compliance, not judgment.

Consolidation with the five remaining panel agents is pending; `tasks.md` is deliberately not
generated, because a task breakdown derived from these phases would be stale on arrival.

### Consolidated panel findings (4 of 6 returned; all four say do not implement)

Both **simplification** agents (DHH, code-simplicity) and both **correctness/strategy** agents
(Kieran, CTO) fired on the same scope. Per `plan-review`'s own rule — *when both panels fire on
the same scope, prefer delete over fix* — the mechanism is the problem, not its parameters.

**Verified independently by me before acceptance. Each row is a command I ran.**

| # | Finding | Status |
| --- | --- | --- |
| F1 | **The originating defect passes the gate.** `/soleur:trigger-cron` — the exact Claude-only form that motivated #8299 — lives in `gdpr-gate:270`, `incident:39`, `product-roadmap:36`. All three are trigger-bearing with no block, so all three are in the 34 backfill, gain a block, and score **QUALIFIED**. The offending line is never examined | **CONFIRMED** |
| F2 | **`ship/SKILL.md` scores QUALIFIED while dispatching Claude-only** at `:504` (`skill: soleur:preflight` via the Skill tool). The block is an *inbound* self-invocation contract; P1 quantifies over *outbound* instructions. Different things | **CONFIRMED** |
| F3 | **Three spawn-site skills score AUTO-EXEMPT.** `plan-review` (5 `@agent-` spawns), `resolve-parallel`, `resolve-pr-parallel` all match **0** of the 12 trigger alternatives. They ship silently exempt on day one — P1 violated on merge day by the gate's own output | **CONFIRMED** |
| F4 | **`invokeSkill` as a trigger alternative is circular** — it matches *exactly* the 12 blocked skills, because the block text contains `` `invokeSkill()` ``. Post-backfill the trigger set becomes a function of the census's own output | **CONFIRMED** (`diff` of the two sets is empty) |
| F5 | **`UNION` is not subsumable.** Only **2 of 20** UNION members carry a `grok-harness-invoke` block; 18 do not. The two markers are near-disjoint populations, and "these 20 skills need cloud-mode" is derivable from nothing in this plan. Phase 6 would delete a live property and AC5 would not notice | **CONFIRMED** |
| F6 | **`harness-model-map.test.ts:76` is `["claude","grok"]` — two-harness by design**, because `TIER_MAPS` has only those keys. Repointing it at `SUPPORTED_HARNESSES` would route codex/devin through a fallback and assert nothing. My own Research Insights said `TIER_MAPS` is claude/grok-only *two lines before* calling this a 4-harness literal. Exactly **one** real 4-harness literal exists (`workflow-fidelity.test.ts`) | **CONFIRMED** |
| F7 | **AC11 already fails on its own prose.** `git diff origin/main...HEAD \| grep -c 'PLUGIN_ROOT:-'` → **9**, because this plan, the spec, the brainstorm and the learning all discuss the banned form (NG2 requires them to). Two of the nine are AC11's own lines. Also `grep -c` exits 1 on no match, breaking any `&&` chain | **CONFIRMED** |
| F8 | **AC7 is not an assertion.** `git grep -c` over multiple pathspecs emits `path:count` per file with no total, and the AC has no comparison operator. `"codex"` is a bare token (`cq-assert-anchor-not-bare-token`) that legitimately appears in four single-harness test files | **CONFIRMED** |
| F9 | **The mutation matrix asserts the exit code, not the reason.** ADR-193's highest-value section is titled *"Why the mutation oracle asserts the REASON, not the exit code."* M2/M6 add a skill directory, which independently reddens `components.test.ts` and the manifest — so AC3's "one line per row" is satisfiable by a red caused entirely by an unrelated gate | **CONFIRMED** |
| F10 | **I scoped ADR-193 out for Decision 1 and in for Decision 5 using the same argument.** If out-of-population defeats Decision 1, it defeats Decision 5 identically — and Decision 5 was the sole cited authority for the `UNION` deletion | **CONCEDED** |
| F11 | **`cq-test-fixtures-synthesized-only` is miscited.** It is a *secret-scan* rule over three specific globs, and `plugins/soleur/test/fixtures/` is not among them. I borrowed a rule id for its name rather than its text — the same inherited-framing habit this session's learning is about. The placement conclusion still stands on the real `fixture-*-assert.baseline.txt` precedent | **CONCEDED** |
| F12 | **`harness.ts` has 4 lib importers, not 3** — I missed `lib/go-routing.ts`, which imports `invokeSkill`/`spawnAgent` as *values*. "3" was true of the `Harness` **type** only, plus 8 test files | **CONFIRMED** |
| F13 | **ADR-225 is double-booked on TWO remote refs** (`feat-one-shot-adr142-…` and `feat-pluggable-web-agent-engines`). Whichever lands second must retake 226 and will collide with this plan | **CONFIRMED** |
| F14 | **The floors collapse algebraically.** With POPULATION exact and `QUALIFIED ⊆ TRIGGER` (measured: zero block-without-trigger skills), the auto-exempt ceiling **≡** the trigger-count floor, and the QUALIFIED floor reduces to *"the ledger is empty."* Four floors are two assertions; one exact snapshot catches M1/M2/M3/M6/M9 **and** over-matching, which no floor does | **CONFIRMED** |
| F15 | **The ledger ships with zero rows** — AC2 enumerates 46 + 52 = 98 with no EXEMPT bucket. A TSV, a strict fail-closed parser, a floor, M7, M8 and H4 all exist to represent nothing | **CONFIRMED** |
| F16 | **The block has a measured 8.3% born-drift rate.** `git log -S` dates all 12 blocks to one commit, `949872534` (2026-09-12) — and `one-shot` diverged *in that same commit*, one author, full attention. Extrapolated to 46 hand-written copies: ~4 divergences at authoring time. The generator pattern (`sync-grok-agent-compat.ts` + `--check`, already CI-gated in this very test directory) is the established alternative | **CONFIRMED** |
| F17 | **`## Observability` cites layer 7 for a CI-only gate.** Layer 7 is a property of the *execution* surface and requires a stdout marker paired with a durable committed artifact; this census runs in Soleur's CI. All four listed failure modes are gate-self-failures. The one genuine layer-7 mode — *the block names a Codex or Devin form that does not resolve* — appears in `## User-Brand Impact` and **nowhere** in `failure_modes:`, because nothing detects it: only grok (`ci.yml:1320 grok-fidelity`) and claude have live verification | **CONFIRMED** |
| F18 | **P1's own disjunct makes the harness apparatus dead.** P1 says "names each form **or cites the adapter**." All **12/12** blocks cite `lib/harness.ts`. So either adapter-citation suffices — and `SUPPORTED_HARNESSES`-as-census-input, M5, H3 and "extend the 12" all buy nothing — or enumeration is required, and 0 skills are qualified and every count in the plan is wrong. The plan wants it both ways | **CONFIRMED** |

**What survives review:** born-blocking (zero-for-N is measured and binding); population = `git ls-files`
over all 98; whole-tree never diff-scoped; `SUPPORTED_HARNESSES` as a two-site union dedup on its own
merits; and the measurement discipline itself — Kieran independently reproduced 13 of 13 counts.

**What does not:** the carrier, the trigger pattern, the three-verdict model, all four floors, the
floors file, the ledger, the `UNION` deletion, 8 of 13 matrix rows, and three of the four
shell-prescribing ACs.

### Architecture-strategist findings (5 of 6 returned; verdict unanimous)

| # | Finding | Status |
| --- | --- | --- |
| F19 | **The auto-exempt ceiling is a net-count identity, not a RED-by-default mechanism.** A PR that adds one non-triggering skill AND deletes one auto-exempt skill lands every floor exactly on its threshold — `pop 98≥98, trig 46≥46, auto 52≤52, unc 0` — **GREEN**, with the new skill silently exempt. This is the same shape ADR-193's own Consequences record having shipped and falsified: *"deriving `deferred` as 'everything not covered' makes the two sets a partition of one list, so the sum always equals the total and the arm can never fail."* Reproduced one level up, in the plan that cites the ADR | **CONFIRMED** (arithmetic run) |
| F20 | **The population excludes the front door.** `plugins/soleur/commands/go.md` — the router, first command of every session — is outside the glob and **has the defect today**: `:122` names Claude and Grok only; Codex appears **3** times in the whole file against Claude 17, Grok 19, Devin 9. A Codex operator running `/soleur:go` hits an incomplete routing table the census reports GREEN over. Also outside: 68 agent docs, **8** of which carry Claude-only spawn prose | **CONFIRMED** |
| F21 | **Nothing typechecks `plugins/`.** `grep -c tsc scripts/test-all.sh` → **0**; the only tracked tsconfig is `apps/web-platform/tsconfig.json` and `ci.yml:907` runs tsc with `working-directory: apps/web-platform`. So `typeof SUPPORTED_HARNESSES[number]` written **without `as const`** silently degrades `Harness` to `string`, destroying every narrowing in `harness.ts` — and bun strips types, so the suite stays green. **AC8 is unverifiable by the means the plan prescribes** | **CONFIRMED** |
| F22 | The `markerBlock()` mechanism sentence is wrong: `:491` already pins exactly one `MARKER_END`, so non-greediness is irrelevant. The break is span inclusion. Conclusion holds, stated cause does not | **CONCEDED** |

**The anchor argument is self-serving, and now demonstrably so.** It defends the *population* denominator (`git ls-files`, index-derived, narrowing visible) — but the denominator that actually carries the property is the **trigger** count, which is regex-derived from prose. A skill narrows out of it by rewording, which is invisible and looks editorial. F19's GREEN sequence needs no floor edit at all.

What L142 actually prescribes is *"pin it with a repo-internal test against a **committed inventory**."* The plan implements a **number**, not an inventory. A committed list of the 52 auto-exempt names turns every F19 sequence RED, and costs 52 lines — not the "~60 ledger rows asserting nothing real" the ADR alternatives list rejects, which was a strawman for this.

### Spec-flow findings (6 of 6 returned — panel complete, verdict unanimous)

| # | Finding | Status |
| --- | --- | --- |
| F23 | **After the backfill the trigger floor is inert — and the gate can be made fully vacuous while reporting perfect compliance.** The canonical block contains `Skill tool` *and* `invokeSkill`, so every skill obliged to carry it becomes trigger-bearing **by the block**. Leave-one-out on the pattern: **6 of 12** alternatives unreachable today, **12 of 12** after Phase 5. Reduce the pattern to the single alternative `invokeSkill` and the post-backfill census reports trigger 46, qualified 46, unclassified 0, auto-exempt 52 — **all four floors green.** The exact failure ADR-193 exists to prevent, inside the guard written to honour it | **CONFIRMED** |
| F24 | **My Cut List measured stripping on the pre-state of the transformation it was cutting.** "Stripping is a no-op (46→46)" is true *today*, because only 12 skills carry the block and all 12 trigger independently for other reasons. It is false the moment Phase 5 runs. The cut also aimed at the wrong risk — it argued stripping "can never produce a false RED," when the reason to strip is to prevent a false **GREEN** | **CONCEDED** |
| F25 | **24 of the 52 auto-exempt skills carry a missed invocation form** — `@agent-<name>` (3), `Spawn agent:` (3), `Task <name>(arg)` (3), bare `soleur:<name>` (21). Among them: `trigger-cron/SKILL.md:26-27` itself, the skill named in the spec's own Problem Statement. AC2's pinned 46/52 would **freeze all 24 in as a committed baseline** | **CONFIRMED** |
| F26 | **spec FR2 and plan H3 are mutually unimplementable.** FR2: QUALIFIED means "carries the block." H3: "qualified via an adapter citation rather than a marker block — PASS," and AC4 makes H3 a merge gate. An author citing the adapter is QUALIFIED under the plan and UNCLASSIFIED under the spec | **CONFIRMED** |
| F27 | **Adding a fifth harness compiles clean and silently degrades the adapter.** `routingInstructions` (`harness.ts:411-467`) and `pollInstructions` (`:393`) both have `default:` arms and there is no `never` exhaustiveness check anywhere in the file. So the census would compel 46 markdown edits documenting a harness the adapter *those very blocks cite* does not implement | **CONFIRMED** |
| F28 | **No phase implements TR6 or TR7.** Phase 1 writes the matrix as a *header comment*. There is no decoy fixture in `## Files to Create`, and M2/M6/M9/H2/H3 need a population the `git ls-files` derivation cannot produce. Given TR4's finding that no corpus guard polices a `.test.ts`, an unimplemented TR6 means the gate ships with **no proof it is non-vacuous** | **CONFIRMED** |
| F29 | **FR7's "re-express `UNION` derived" is not implementable.** Its population is property-defined ("spawn sites ∪ secrets/prod ∪ pipeline ∪ devin shims") and needs a classifier that does not exist. Population = all 98 → the assertion is false (only 64 are marked). Population = marked skills → tautology. Test 2 is the *only* anti-omission guard in that describe; AC6 would certify its loss as a pass | **CONFIRMED** |
| F30 | Phase 3 commits a `.ts` file that is RED by design, but `lefthook.yml:311-332` runs the full battery on any `.ts`. Phase 3 and the 34 Phase-5 commits are uncommittable without repeated `--no-verify`, which the plan never states | **CONFIRMED** |

**The whole class, stated once:** every mechanism in the plan was validated against *today's* tree and is wrong against the tree Phase 5 produces. The trigger floor, the auto-exempt ceiling, M4, M6, M7 and the stripping cut are each correct now and dead after.

---

# PLAN v1 SUPERSEDED — see v2 below

Direction chosen by the operator after the panel: **invert to negative space.** v1's design
sections above are retained as the review record; they are not the plan of record.

# PLAN v2 — negative-space assertion (plan of record)

## v2 Overview

Invert the gate. Instead of asserting a block is **present** (which certifies how the agent
*arrived* and says nothing about how the doc *dispatches*), assert that a harness-specific
invocation token is **absent** — and that skills name the canonical `soleur:<name>` that the
adapter resolves on every harness.

The predicate becomes **provable complete**, because its token set is not a guess: it is read
off `plugins/soleur/lib/harness.ts`, which is where the forms are *defined*.

## v2 Measurements (re-derived 2026-09-18; every number has its command)

| Quantity | Value | Derivation |
| --- | --- | --- |
| Population | **101** docs | `git ls-files 'plugins/soleur/skills/*/SKILL.md'` (98) + `'plugins/soleur/commands/*.md'` (3) |
| In violation (blocks + fences stripped) | **45** | python scan, token set below |
| Occurrences | **175** | same |
| Compliant today | **56** | 101 − 45 |
| In-fence occurrences (excluded, pinned) | **38** | 213 − 175 |
| `/soleur:<name>` total | 205 | of which **57** name a command (`go`/`help`/`sync`) → legitimate per ADR-224; **135** name a skill → violation; 0 unrecognised |
| Agent docs (deferred) | 68, **8** with Claude-only spawn prose | `git grep -l 'Task tool\|Skill tool' -- plugins/soleur/agents` |

**The gate catches every instance the panel named that v1 missed:** `go.md` (25),
`gdpr-gate` (17), `ship` (14), `plan-review` (9). `trigger-cron` correctly shows **0** — its
references are already bare `soleur:cron-list` / `soleur:trigger-cron`, i.e. the canonical form.
Spec-flow listed bare `soleur:<name>` among "missed triggers"; under negative space it is the
**target** form, not a defect.

## v2 Token set — derived, not guessed

From `formatSkillInvocation` (`harness.ts:120-140`) and `formatAgentSpawn` (`:212-245`):

| Token | Harness it is specific to |
| --- | --- |
| `$soleur:<name>` | codex |
| `/soleur:<name>` where `<name>` is a **skill** | devin (and Claude's slash surface) |
| `Skill tool`, `Task tool`, `@agent-`, `subagent_type` | claude |
| `spawn_subagent` | grok |
| `run_subagent` | devin |
| `spawn_agent` | codex |
| **`soleur:<name>` (bare)** | **none — this is the canonical form the adapter resolves** |

**Exempt by construction:** `/soleur:go`, `/soleur:help`, `/soleur:sync`. Those are *commands*,
not skills, and ADR-224 records that the command surface owns its slash name.

## v2 Requirements

- **V1** Population is `git ls-files` over `plugins/soleur/{skills/*/SKILL.md,commands/*.md}` — 101
  docs. No regex participates in scoping.
- **V2** For each doc: strip sanctioned marker blocks (`<!-- x:start -->…<!-- x:end -->`) and
  fenced code, then assert **zero** harness-specific skill-invocation tokens in the remainder.
- **V3** The token set is imported from a single exported constant in `harness.ts`, adjacent to
  the `format*` functions that define the forms. One source; a new form added there widens the gate.
- **V4** An exemption ledger with **real rows**: the `go.md` Step 2.0 adapter table and the
  per-harness `INSTRUCTIONS.md` files legitimately enumerate harness forms — that is their job.
  Measured need: a small number of rows, not zero. This answers v1's "ledger ships empty" defect.
- **V5** One exact-snapshot assertion, not four floors:
  `expect(census).toEqual({ population: 101, violations: 0, exempt: <n>, inFence: 38 })`.
  It catches removal, addition, over-matching and under-matching in one line, which no floor did.
  The `inFence` pin stops fenced examples becoming a laundering channel.
- **V6** `SUPPORTED_HARNESSES` in `harness.ts` with `Harness` derived from it, `| "unknown"`
  retained, **and `as const`** — without it the type silently degrades to `string` and nothing
  would catch it, because nothing typechecks `plugins/` (F21).
- **V7** A `never` exhaustiveness arm on `routingInstructions` and `pollInstructions`, so adding
  a harness to `SUPPORTED_HARNESSES` fails to compile until the adapter implements it. Closes F27:
  today both have `default:` arms, so a fifth harness would silently map to Claude conventions
  while the gate compelled docs to advertise it.
- **V8** Repoint **only** `workflow-fidelity.test.ts:373` at `SUPPORTED_HARNESSES`. Leave
  `harness-model-map.test.ts:76` alone — its `["claude","grok"]` is deliberate, matches
  `TIER_MAPS`' two keys, and widening it would pass vacuously via the unmapped fallback (F6/F11b).
- **V9** Write `plugins/soleur/grok/INSTRUCTIONS.md`. `codex/` and `devin/` have one; grok does
  not, so "the adapter resolves it" is not yet true on all four. One file; it is the prerequisite
  that makes the canonical form honest rather than aspirational.
- **V10** One authoring line in `plugins/soleur/skills/skill-creator/SKILL.md`. v1's NG3 and NG4
  closed the `AGENTS.rules.md` and convergent-bullet routes without opening any other, leaving the
  RED test as the only teaching surface (CTO #1 / spec-flow A1).
- **V11** The failure message names, per offending doc: the token, its line, the harness it is
  specific to, and the canonical replacement. A path list is a scoreboard, not a remediation.

## v2 Non-Goals

- **NG1** Agent docs (68, 8 offenders). Same defect class, separate population → **new issue**.
- **NG2** `#7453`'s ~105 `${CLAUDE_PLUGIN_ROOT:-…}` sites. Unchanged.
- **NG3** Mirror completeness (`#8306`). Unchanged.
- **NG4** Helper extraction (`#8307`). Unchanged — and v2's single-assertion shape removes the
  floors/ledger triple that made this a fourth bespoke instance.
- **NG5** **Deleting the `UNION` array.** Dropped from scope on three independent findings: its
  population is near-disjoint from the block set (2 of 20), it is property-defined with no
  classifier available, and it is the only anti-omission guard in its describe (F5/F29).
- **NG6** No `AGENTS.rules.md` rule (`cq-agents-md-tier-gate`, unchanged from v1).

## v2 Implementation Phases

### Phase 1 — Prerequisites (no gate yet)

1. Write `plugins/soleur/grok/INSTRUCTIONS.md` (V9), mirroring the `codex/` table's shape.
2. Add `SUPPORTED_HARNESSES` + `as const` + derived `Harness` (V6) and the `never` arms (V7).
3. Repoint `workflow-fidelity.test.ts:373` only (V8).

### Phase 2 — The mutation matrix, then the gate

Write the matrix into the test file, then the census. It must be RED on today's tree with
**45 docs / 175 occurrences**, each named with its token and line. A green first run means the
token set is wrong.

### Phase 3 — Ledger + fixtures

Create the ledger with its real rows (V4) and the decoy fixtures TR6/TR7 require. The population
function takes an **injectable root** (default: `git ls-files`) so the matrix is runnable — v1's
matrix was not (F28/D4).

### Phase 4 — Canonicalise (GREEN)

Rewrite the 175 occurrences across 45 docs to the canonical form. This is a **deletion** of
harness-specific prefixes, not an insertion of boilerplate.

### Phase 5 — Authoring surface + ADR

V10's skill-creator line, then ADR-226.

## Guard Contract — v2 (plan of record)

### Guard 2 — harness-specific invocation tokens are absent

**Property.** No doc under `plugins/soleur/{skills,commands}` instructs an agent to invoke a
skill using a form specific to one harness. Skills are named canonically and the adapter resolves
them per harness. The detector cannot report clean over a population it failed to enumerate, nor
over a token set narrower than the forms `harness.ts` defines.

**Assembly.** Five chokepoints, none a member list: (1) population — `git ls-files` over two
globs, injectable for tests; (2) the token set — one exported constant beside the `format*`
functions that define the forms; (3) the strip step — sanctioned marker blocks and fenced code;
(4) the exemption ledger — strictly parsed, real rows; (5) one exact-snapshot assertion.

**Mutation matrix.** Each row must drive the suite RED **with the census's own sentinel on
stdout**, not merely a non-zero exit — ADR-193's highest-value section is *"Why the mutation
oracle asserts the REASON, not the exit code"*, and v1's matrix violated it (F9).

| # | Mutation | Targets |
| --- | --- | --- |
| N1 | Reintroduce `skill: soleur:preflight` via the Skill tool in `ship/SKILL.md` | the core property, at the exact site v1 passed green |
| N2 | Reintroduce `/soleur:trigger-cron` in `gdpr-gate/SKILL.md` | the originating defect of #8299 |
| N3 | Add a **second** violating doc after a compliant first | a classifier that stops at the first hit |
| N4 | Neuter the population glob to zero files | the guard's own dispatch — `0 checked` must FAIL |
| N5 | Remove one token from the exported set | the set is load-bearing and single-sourced |
| N6 | Move a violation **into** a fenced block | the `inFence` pin — fences must not launder |
| N7 | Add a ledger row for a path not in the population | stale-row rot (F/B4) |
| N8 | Delete the ledger file | fail-closed on a missing input, not "zero exemptions" |
| N9 | Add a fifth member to `SUPPORTED_HARNESSES` without an adapter arm | **must fail to compile** (V7) |

**Harness rows.**

| # | Mutation | Must |
| --- | --- | --- |
| H1 | Delete the assertion body, keep the describe | **RED** — otherwise it pins nothing |
| H2 | A doc whose only harness token is inside a sanctioned marker block | **PASS** — the permitted non-canonical input; without this row the matrix cannot detect a classifier that rejects everything |
| H3 | `go.md`'s adapter table, ledger-exempt | **PASS**, counted EXEMPT not VIOLATION |
| H4 | After N9, add the adapter arm | **PASS** — the green counterpart v1's M5 lacked (F/E2) |

**Anchor.** V5 is a single exact snapshot, so there is no floor to lower separately: weakening it
means editing the one number the assertion compares, in the same hunk as the assertion. That is
strictly more visible than v1's four floors in a fifth file — and v1's separate-file argument was
conceded as compliance rather than judgment (F14/L142's precondition is absent for an index-derived
denominator). The honest limit: this proves consistency, not integrity, and is not claimed otherwise.

## v2 User-Brand Impact

Unchanged threshold: **`single-user incident`**, `requires_cpo_signoff: true`.

**If this lands broken:** the gate reports green over a doc that still dispatches Claude-only —
which is exactly what v1 would have done, now with a passing check attached.

**If this leaks:** no new data surface. The exposure prevented is a self-hosted operator on Grok,
Codex or Devin following plugin-shipped prose naming a form their harness does not have, hitting a
dead command, and uninstalling without filing. **Silent churn.** v2 closes the three concrete
instances v1 left open, including `go.md` — the first command of every session.

## v2 Observability

Restructured per CTO F17: the **gate** has no observability layer; the **deliverable** is layer 7.

```yaml
gate:                       # build-time, no layer — it never runs on a customer machine
  ci: .github/workflows/ci.yml:942 (test-bun) — no registration needed
  precommit: lefthook.yml:333 (plugin-component-test, glob plugins/soleur/**/*.md)
              -- the faster loop, unclaimed in v1
  failure_modes:
    - a doc reintroduces a harness-specific token -> named with token + line + harness
    - the token set narrows                       -> N5
    - the population resolves to zero             -> N4 (0 checked FAILS)
    - a fenced block is used to launder           -> the inFence pin
deliverable:                # the canonicalised prose, layer 7
  artifact: the 101 docs in the customer's installed plugin tree, read in-session
  failure_modes:
    - mode: the canonical `soleur:<name>` does not resolve on a harness
      detection: grok has ci.yml:1320 (grok-fidelity); claude is the dev harness;
                 codex and devin have NO live invocation-form verification
      alert_route: none today -- declared uncovered, tracked by #8306
discoverability_test:
  command: bun test plugins/soleur/test/harness-parity.test.ts
  expected_output: "101 examined, 0 violations, <n> exempt, 38 in-fence"
```

The uncovered mode is **declared** rather than omitted — v1 listed only gate-self-failures and
left the one real layer-7 mode in User-Brand Impact with no detection row.

## v2 Acceptance Criteria

### Pre-merge

- [ ] V-AC1 RED on today's tree: **45 docs / 175 occurrences**, each named with token, line, harness.
- [ ] V-AC2 After Phase 4: `{population: 101, violations: 0, exempt: <n>, inFence: 38}`.
- [ ] V-AC3 N1–N9 each RED **with the census sentinel on stdout** (not merely non-zero exit).
- [ ] V-AC4 H1–H4 behave as specified; H2/H3/H4 PASS.
- [ ] V-AC5 N9 fails **at compile time**: `cd plugins/soleur && npx tsc --noEmit -p <minimal tsconfig>`.
      Nothing typechecks `plugins/` today (F21), so this AC also asserts `as const` is present.
- [ ] V-AC6 `devin-cloud-mode.test.ts` green, `marked.length == 67` unchanged, **`UNION` intact**.
- [ ] V-AC7 `harness-model-map.test.ts:76` unchanged — still `["claude","grok"]`.
- [ ] V-AC8 Exactly one 4-harness array literal outside `harness.ts`:
      `[ "$(git grep -lE '\[[^]]*"codex"[^]]*"devin"[^]]*\]' -- plugins/soleur/lib plugins/soleur/test | grep -vx plugins/soleur/lib/harness.ts | wc -l)" -eq 0 ]`
- [ ] V-AC9 No banned plugin-root form introduced, added lines only, code paths only:
      `! git diff origin/main...HEAD -- plugins/ scripts/ .github/ .claude/ | grep -E '^\+' | grep -q 'PLUGIN_ROOT:-'`
      (v1's AC11 counted context and deletion lines and failed on its own prose — F7.)
- [ ] V-AC10 `plugins/soleur/grok/INSTRUCTIONS.md` exists and names the canonical token.
- [ ] V-AC11 `skill-creator/SKILL.md` names the obligation (V10).
- [ ] V-AC12 `git fetch origin main && bash scripts/test-all.sh` green, with
      `SOLEUR_ALLOW_FULL_GATE=1` so a sibling worktree cannot flip it (spec-flow §8 on AC13).
- [ ] V-AC13 ADR-226 ordinal re-derived ref-wide immediately before merge. **Two branches already
      claim ADR-225** (`feat-one-shot-adr142-…`, `feat-pluggable-web-agent-engines`), so 226 is
      contended; if it moves, sweep plan + spec + every AC naming it in the same edit (F13).
- [ ] V-AC14 `Ref #7453`, `Ref #8306`, `Ref #8307`, `Ref #8308` + the new agent-docs issue —
      none folded in, none closed.

## v2 Risks

| Risk | Mitigation |
| --- | --- |
| The token set is incomplete | It is read off the `format*` functions that *define* the forms, and N5 asserts it is load-bearing. This is the one thing v1 could not claim |
| Fenced examples launder violations | The `inFence` pin (38) + N6 |
| `as const` omitted → `Harness` degrades to `string` silently | V-AC5's real `tsc` run, since nothing typechecks `plugins/` today |
| A fifth harness compels docs to advertise an unimplemented adapter | V7's `never` arms + N9/H4 |
| 175 edits across 45 docs drift | They are deletions of a prefix, not 46 instantiations of a template — the 8.3% born-drift rate CTO measured applies to templates, not removals |
| Canonicalising breaks a genuine command reference | 57 `/soleur:{go,help,sync}` hits are exempt by construction (ADR-224); H3 pins the adapter table |

## v2 review — BLOCKING (code-simplicity, 1 of 3 returned). v2 needs a v3.

Verified firsthand before acceptance.

| # | Finding | Status |
| --- | --- | --- |
| G1 | **The token set fires on REFERENCE prose, not just DISPATCH instructions — and that is the dimension the property lives on.** In `gdpr-gate/SKILL.md`, of 13 token hits exactly **one** (`:270`, "dispatch the cron manually via `/soleur:trigger-cron`") is the property. L12/18/19/24 are cross-references to another skill's phase ("fires inline during `/soleur:plan` Phase 2.7") and are **correct as written**. L20/21/38 document what the **operator types** (`/soleur:gdpr-gate "<scope>"`); rewriting those to bare `soleur:gdpr-gate` makes them *wrong*, because that form is agent-facing and no operator can type it on any harness. Reviewer's site inspection: ~2 of 42 occurrences across the three largest offenders are the property | **CONFIRMED** |
| G2 | **So v2's "these are deletions of a prefix, not insertions" is false**, and the born-drift exemption it bought does not apply. The honest edit at a reference site is a *rewording* into harness-neutral prose, not a strip — ~174 rewordings at sites whose current text is correct, which is its own risk class | **CONCEDED** |
| G3 | **v2 loses the one real property v1 had.** `git grep -ln 'grok-harness-invoke' -- plugins/soleur/test plugins/soleur/scripts .github lefthook.yml scripts` → **exit 1, no hits**. Nothing pins the 12 blocks. v2 *strips* them and asserts nothing, so deleting a block makes the census **greener** while Grok loses its instruction. Needs one line: pin the count at 12, beside `devin-cloud-mode.test.ts:496` | **CONFIRMED** |
| G4 | **`plugins/soleur/grok/` does not exist**, and no harness is shown to read such a file. V9/V-AC10 assert existence, not loading. Grok's real surfaces are `.grok/agents/` at repo root and the 12 in-doc blocks — so G3's pin is the cheaper honest move | **CONFIRMED** |
| G5 | **My `inFence: 38` is arithmetically wrong.** I derived it as `213 − 175`, but raw = body + in-fence + **in-marker-block**, and the blocks hold ~21 tokens — so the subtraction over-counts in-fence by the block population. Reviewer measured 22–26 under four readings, never 38 | **CONCEDED** |
| G6 | **V-AC1's `45 docs / 175 occurrences` cannot both be true of one implementation.** Sweeping four readings of the unspecified details: the reading yielding 175 occurrences yields **43** docs; the reading yielding 45 docs yields **185**. `population 101` reproduces exactly | **CONCEDED** |
| G7 | **N5 passes vacuously — the same defect class I cut from v1.** After Phase 4 `violations: 0`; remove a token from the exported set and it is still 0, so the snapshot still matches. N5 only moves `inFence`, meaning that pin was load-bearing by accident. Restate as one mutation: remove the token **and** reintroduce a violation in that form | **CONFIRMED by inspection** |
| G8 | **`go.md`'s 12 hits are all inside the Step 2.0 adapter table and per-harness paragraphs** — i.e. exactly what V4/H3 declare exempt. So the "marquee catch" the plan headlines is a ledger row, not a fix. And because the ledger is **per-path**, exempting `go.md` also exempts `:122` ("delegate to `soleur:work`. **Claude:** Skill tool") — a genuine dispatch instruction in the router | **CONFIRMED** |
| G9 | Items 5+6+7 (`as const` → `never` arms → a new tsconfig) are a mutually-justifying triangle: each exists to make the next observable, and none is required by the property. A runtime `expect(SUPPORTED_HARNESSES).toEqual([...])` buys what matters without a new build surface | **CONCEDED** |

### The pattern across three iterations, stated plainly

v1's **carrier** tested the wrong thing (inbound arrival vs outbound dispatch). v2's **classifier** tests the wrong *linguistic role* (any token occurrence vs a dispatch instruction). Both were measured correctly and both measured the wrong predicate. A token scan cannot distinguish "this doc tells an agent to dispatch" from "this doc mentions another skill" — and the property only lives on the former.

**Implication for v3:** the population is not 45 docs / 175 occurrences. It is the dispatch sites only — a far smaller set — and the gate cannot be a pure token scan. Two panel agents are still out; v3 waits for them rather than being written reflexively, because writing a third design before the review of the second has landed is how the first two got here.

## v2 review complete (3 of 3). v2 is BLOCKED. The predicate SHAPE was wrong.

All three reviewers refuted the load-bearing claim independently. Verified firsthand.

| # | Finding | Status |
| --- | --- | --- |
| H1 | **`formatSkillInvocation` has FOUR branches and I dropped one.** `harness.ts:128-130` returns `` `/${name}` `` for grok — a bare slash, no `soleur:` prefix. v2's token table assigns grok only `spawn_subagent`, an *agent-spawn* token, so grok has **no skill-invocation token at all**. I read the function that defines the forms and omitted a quarter of it — the entire basis of "provable complete" | **CONFIRMED** |
| H2 | **The blind spot is large.** Measured 225 bare-slash occurrences across 26 docs (a reviewer's stricter boundary regex found 264 in 39 — ~1.4× v2's *entire* violation set). **5 docs violate ONLY via this form and v2 certifies them clean:** `compound-capture`, `file-todos`, `heal-skill`, `kb-search`, `test-fix-loop`. `kb-search:16-21` publishes its whole "Accepted forms" list as `/kb-search …` — #8299's defect, inverted | **CONFIRMED** |
| H3 | **My own `/soleur:` row does not sum to its own total.** I published 205 = 57 commands + 135 skills. `57 + 135 = 192`. The real occurrence count is **208**, and "0 unrecognised" is false — 13 hits are metavariable forms (`/soleur:<skill>`, `/soleur:<SKILL_NAME>`) in `go.md`, `help.md`, `go/SKILL.md`, `schedule/SKILL.md`, five of them dispatch prose a `[a-z-]+` classifier skips silently | **CONFIRMED** |
| H4 | **V-AC5 passes vacuously.** `npx --yes tsc --version` installs the deprecated registry squatter `tsc@2.0.4`, prints *"This is not the tsc command you are looking for"*, and **exits 0**. Worse, a real tsc over `lib/harness.ts` already emits **7–13 errors** (`Cannot find module 'bun'`, `ImportMeta.dir`, no `@types/node`), so exit code cannot distinguish N9's induced error from the standing baseline — the exact oracle defect ADR-193 forbids, in the AC written to honour it | **CONFIRMED** |
| H5 | **The "fenced = illustration" premise is false, and the counter-example is mine.** `brainstorm/SKILL.md:604` and `:617` are fenced blocks whose body IS the mandatory resume prompt — `/soleur:plan #<issue-number> …` — which `wg-end-of-work-emit-resume-prompt` fires at every session end. 16 fenced blocks are dispatch **payloads**, not examples. A fence is a syntax, not a semantics | **CONFIRMED** |
| H6 | **The marker strip has no allowlist.** 93 blocks, 15 distinct names, and v2's pattern wildcards the name — so any author can hide prose in `<!-- anything:start -->…<!-- anything:end -->`, and `soleur-cloud-mode` already appears in 64 of 101 docs so one more looks routine. 21 tokens + 71 bare-slash occurrences sit inside stripped blocks today, and the snapshot has no `inBlock` field | **CONFIRMED** |
| H7 | **The `inFence` pin is defeated by compensation.** Doc A gains a fenced token (+1), doc B loses one (−1) → `{101, 0, n, 38}` → GREEN, and doc A ships Claude-only dispatch. Same net-count identity as v1's auto-exempt ceiling, one level down — in the design that replaced it | **CONFIRMED** |
| H8 | **V4 and N7 directly contradict.** V4 names the per-harness `INSTRUCTIONS.md` files as ledger rows; they are **outside the population** (`skills/*/SKILL.md` + `commands/*.md`), so N7 ("a row for a path not in the population → RED") would reject them. V4 therefore reduces to **one** row — a whole-file exemption for the router — restoring the exact hole v2 was built to close | **CONFIRMED** |
| H9 | **V10's authoring line would itself violate the gate.** `skill-creator/SKILL.md` already carries `subagent_type` and is in the 45. A line teaching "never write `Task tool`/`subagent_type`" contains those tokens. v2 neither cites `cq-assert-anchor-not-bare-token` nor declares that for an *absence* assertion the rule's failure mode inverts | **CONFIRMED** |
| H10 | **ADR-226 is consumed, not contended.** Two branches claim 225; the loser renumbers to 226. First free ordinal is **227** | **CONFIRMED** |
| H11 | V7 needs an explicit `case "unknown":` arm or Phase 1 will not compile (`TS2322: Type '"unknown"' is not assignable to type 'never'`). And V7 covers only the two *doc-emitting* switches — seven *dispatch* functions are if-chains with a trailing Claude fallback, so a fifth harness silently inherits Claude's forms from all seven | **CONFIRMED** |
| H12 | Forms are defined in **six** places, not two: `workflow-fidelity.ts:132-141` (`formatSkillList`), `:144-160`, `pipelineInvocationSuffix` (harness-agnostic — emits grok's form on *every* harness), `harness.ts` `pollInstructions`/`routingInstructions`, plus the two `INSTRUCTIONS.md`. "Single-sourced" is a two-function crop | **CONFIRMED** |

### The actual root cause, and it is in the repo's own principle register

**AP-025 / ADR-202**, verified firsthand — §"Why the state predicate wins":

> `case "$-" in *x*)` asks *is tracing on*. It is **complete by construction**. [Enumerating the forms that enable it] cannot be proven complete. Measured on bash 5.3.9, eight forms enable tracing.

My token set is a **blocklist of forms** — a list of ways to reach the state. AP-025 says that shape cannot be proven complete, and H1 is the proof: I missed a form defined 8 lines from one I captured.

**The complete-by-construction predicate is the inverse.** Instead of "does this doc contain any of N harness-specific forms?", ask **"does every skill reference in this doc match the canonical shape `soleur:<known-name>`?"** — an allowlist of *one* form, checked against the 98-name index the population already enumerates. That is complete by construction over the index, and it would have caught grok's bare slash without anyone knowing the form existed.

I never consulted `knowledge-base/engineering/architecture/principles-register.md`. The refutation of my headline claim was sitting in it.

### Three iterations, one repeating shape

| | what it tested | what the property is |
| --- | --- | --- |
| v1 | marker **presence** (inbound arrival) | outbound dispatch |
| v2 | token **occurrence** (any mention) | dispatch *role* |
| v2's predicate | a **blocklist** of forms | a state question, answerable by allowlist |

Each was measured carefully — Kieran reproduced 13/13 of v1's counts and 6 of 9 of v2's per-doc cells exactly — and each measured the wrong predicate. The failure was never arithmetic; it was validating the instrument instead of interrogating the predicate.

**v3 is not written here.** Writing a third design in the same session that produced two refuted ones, immediately after the review landed, is the pattern rather than the fix. What v3 must be is now known and narrow: an allowlist predicate over the name index; population `skills/*/SKILL.md` + `commands/*.md`; a per-doc census vector rather than scalar pins; an anchor-scoped exemption for adapter-teaching regions (or generate `go.md`'s table from `routingInstructions()` so the ledger is genuinely empty); ADR-**227**.

---

# PLAN v2 SUPERSEDED — see v3 below

v2's design sections above are the review record, not the plan of record.

# PLAN v3 — allowlist predicate over the name index (plan of record; revised after the 7-agent panel + advisor consult, 2026-09-18)

## v3 Overview

v1 asserted a marker was **present** (it certified how an agent arrived, not what the doc told it
to invoke next). v2 asserted a **blocklist** of harness-specific tokens was absent — and omitted
`formatSkillInvocation`'s grok branch, defined eight lines from a form it captured (H1). Both
measured the instrument carefully and the predicate wrongly.

v3 asks the state question AP-025 / ADR-202 prescribes. The repo already enumerates every name a
doc can legitimately invoke: 98 skill directories, 3 command files, 67 registry agents. The
canonical reference to any of them has exactly one shape — `soleur:<name>` — and every harness
adapter already resolves that shape (`codex/INSTRUCTIONS.md:29`, `devin/INSTRUCTIONS.md:76`,
go.md Step 2.0, Claude natively). The predicate:

> **Every token that names a known skill or command is the canonical `soleur:<name>` at a prose
> boundary, a bare name in prose, or a path component; every token that names a known agent is
> the canonical registry id at a prose boundary or a path component. Anything else is
> non-canonical.**

That is an allowlist of permitted contexts over a closed index, not a list of forbidden forms.
**Stated honestly (DHH #1): the gate proves "no sigil-prefixed known name and no bare agent leaf
in plugin docs" — a syntax invariant that the adapters make resolvable — not "harness parity".**
What it does not prove is listed in §Not gated, with counts.

Measured on the tree: **1029 non-canonical sites in 62 docs**. 488 are bare agent leaves
(`Task git-history-analyzer(…)`, dead on Grok because `agentIdToGrokSubagentType` has no stub for
a bare leaf — CPO #1, gated at the operator's choice), 339 grok `/name`, 187 `/soleur:`, 8
`@agent-soleur:…`, 3 `@agent-<leaf>`, 2 `$soleur:`, 1 grok stem, 1 unrecognised sigil.

Deliverables: the classifier and its fixture self-test; a tree census with no committed baseline
(the property is absolute and the anti-vacuity is an index invariant plus permanent fixtures — the
per-doc vector was deleted at the operator's decision after both panels fired on it); `--fix` for
the mechanical rows; remediation of the 1029 sites; one exempt-region kind in `commands/`;
emit-time rendering for operator-pasted prompts; the adapter's own fidelity strings rendered per
harness; three authoring-surface lines; ADR-226.

## v3 Research Insights (delta over v1/v2)

### Premise Validation (v3)

| Cited | Probe | Result |
| --- | --- | --- |
| AP-025 / ADR-202 | read `principles-register.md:35` | "A state predicate is complete by construction; a list of ways to reach it cannot be proven complete." v3 is built on it |
| `harness.ts` skill forms | read `:120-140` + `:145-200` | four branches: codex `$soleur:<n>`, grok `/<n>`, devin `/soleur:<n>`, claude `soleur:<n>` |
| `harness.ts` agent forms | read `:212-312`; `agent-registry.ts:37-47,107-109` | canonical id from `pathToAgentId`; registry = `discoverAgentPaths()` which **excludes `README*` and `/references/`** → `EXPECTED_SOLEUR_AGENT_COUNT = 67`, `.grok/agents` has 67 stubs. A raw `git ls-files 'agents/**/*.md'` returns 68 — the phantom `soleur:operations:references:service-deep-links` (arch F1, Kieran #3). **The index reads the registry, not the glob** |
| Canonical shape resolves | `grep -n 'soleur:' plugins/soleur/{codex,devin}/INSTRUCTIONS.md`; go.md `:147` | codex `:29`, devin `:76` carry the `Skill soleur:<name> → form` row; go.md's routing contract covers `/go`-entered sessions. **A `/ship`-entered Grok session has only the preamble in context** (spec-flow #1) — so the preamble carries the general rule (W7) |
| `routingInstructions()` is a received surface | `grep -rn routingInstructions` outside `lib/` | tests, prose citations, one bootstrap checklist string — **no runtime emitter** (arch F2). It is test/eval-only; W8's grok-arm sentence is kept for the eval harness, not claimed as delivery |
| First free ADR ordinal | `git for-each-ref` + `ls-tree` over every `origin/*` after `git fetch` | 225 on three branches, 227 on `feat-one-shot-8287-operator-bootstrap`, **no ref carries `ADR-226-*`** (8287 yielded it to this feature's v1). **226**, re-derived at `/ship` |
| Preambles byte-identical modulo name | `awk` + `md5sum` over the 12 | 11 identical; `one-shot` drifted. `workflow-fidelity.test.ts:402-415` Guard 1 already pins all 12 carriers (adapter cite + "in this process" + `SKILL.md`) — no template pin needed (simplicity F1) |
| go.md `:122` dual-voice is required | `workflow-fidelity.test.ts:459-468` | pins "in this process", `work/SKILL.md`, `Skill tool` in Step 1; `:417-436` pins one-shot Steps 3-8 dual voice. **The dual-voice lines stay** (spec-flow #2); F20 is closed by canonicalising `:124`'s `/one-shot`, not by deleting the enumeration |
| Description budget | node one-liner over `description:` | 2442 / 2442, zero headroom; the two `description:` hits are token-for-token |
| Pathspec width | `git ls-files 'plugins/soleur/skills/*/*.md' \| grep -c references/` → 106; with `:(glob)` → 0 | plain pathspec `*` crosses `/` (arch F5). `POPULATION_GLOBS` uses `:(glob)` |
| Firing rate | `git log --since=30.days` over the population | 113 commits, **81 added lines with a slash form** in 30 days (CTO #2) — recovery cost is what authors will feel; hence `--fix` |
| `lefthook.yml` `.ts` trigger | read `:311-332` | any staged `.ts` runs the full battery — no commit may be RED (F30); Phase 1 is one GREEN commit |
| Open code-review overlap | `gh issue list --label code-review` (65) × planned paths | #4133 names `plan/SKILL.md` — different concern, acknowledged |
| Leaf/skill name collisions | `comm` over 98+3 skill names vs 67 agent leaves | **none**; leaves are unique → leaf→id is a function (Kieran, spec-flow #4, CPO) |

### Measurements (v3 predicate as revised; every number from `census4.py`, transcribed to Phase 1)

| Quantity | Value | Derivation |
| --- | --- | --- |
| Population examined | **106** | `:(glob)` over `skills/*/SKILL.md` (98) + `commands/*.md` (3) + `{codex,devin}/skills/*/SKILL.md` (6, arch F6) − `commands/help.md` (excluded by path, DHH #5) |
| Index: canonical ids | **165** distinct | 98 + 3 + 67; `go`/`help`/`sync` are both skill and command |
| **NONCANONICAL** today | **1029 across 62 docs** | the RED baseline |
| — bare agent leaf | 488 | R6b (operator decision) |
| — grok `/<name>` | 339 | includes `rclone:33` `"$d"/rclone-*` — a shell glob; false positive #2 |
| — claude/devin `/soleur:<name>` | 187 | includes 13 `/soleur:<metavariable>` (H3) |
| — claude `@agent-soleur:…` | 8 | R4 |
| — claude `@agent-<leaf>` | 3 | R9 (`plan-review:14`) |
| — codex `$soleur:<name>` | 2 | R1 |
| — grok hyphen stem | 1 | R5 (`go.md:149`, inside the region after W7) |
| — unrecognised sigil | 1 | `work:1359` `"$work"` → `"${work}"` (`{` ∈ BOUNDARY; CTO #5). False positive #1 |
| CANONICAL / BARE / PATH | 250 / 3903 / 530 | permitted |
| UNKNOWN-NS | 20 | reported; **diffed** pre/post remediation (spec-flow #4) |
| Top docs | review 218, plan 163, work 81, ship 72, go.md 47, brainstorm 40, one-shot 39, gdpr-gate 28 | the list is `--report` output, not a plan table (Kieran #7) |
| Dual-voice `**Grok:** Read <path>` lines | 20 in 7 docs | PATH by design; declared, not gated (Kieran #2) |
| Mechanism-word lines | 82 / 29 docs | NG-M |
| Resume-prompt / paste templates carrying a slash form | 9 lines in 13 docs | W9 emit-time rendering |

### Property List (unchanged) and Cut List (v3)

P1–P5 stand as written in v1. v3 cuts, with the finding that cut each:

| Cut mechanism | Claimed property | Why cut |
| --- | --- | --- |
| Token blocklist (v2 V3) | P4 | AP-025; H1 |
| Fence stripping (v2 V2) | noise | 16 fenced blocks are dispatch payloads (H5) |
| Name-wildcard marker stripping (v2 V2) | noise | laundering (H6) |
| Scalar snapshot (v2 V5) | P4 | compensation (H7) |
| **Per-doc vector TSV + `--update`/`--check`** (v3 draft) | P4/P5 | both panels: the property is absolute, membership is caught by the index invariant, exemptions reduce to one region in one file. Operator chose delete |
| **Preamble template pin + `grok-harness-invoke` exemption** (v3 draft) | G3 | Guard 1 already pins the carriers; dropping the `/plan` clause leaves nothing to exempt (simplicity F1) |
| `SUPPORTED_HARNESSES` + `Harness` re-derivation (v2 V6, v3 W5) | P4 | never decides a verdict; attribution is a local map (simplicity F3, DHH #6) |
| `grok/INSTRUCTIONS.md` (v2 V9) | honest canonical form | no harness reads it (G4) |
| Path-keyed ledger (v2 V4) | P3 | H8/G8 |
| C4 description edit (v3 draft) | record | ADR is the record; a test filename in a container description is the wrong layer (simplicity F8) |
| "Delete the dual-voice enumeration" rewrite (v3 draft) | F20 | the lines are pinned as REQUIRED by `workflow-fidelity.test.ts:417-468` and are classifier-clean (spec-flow #2) |
| Dispatch-role classification | P1 precision | the canonical shape is correct in every role; v3 is role-agnostic |

## v3 Predicate — the design, stated so it can be refuted

### Index (read from the registry, never listed)

```
SKILLS   = basename(dirname(p)) for p in git ls-files --full-name ':(glob)plugins/soleur/skills/*/SKILL.md'   # 98
COMMANDS = basename(p, '.md')   for p in git ls-files --full-name ':(glob)plugins/soleur/commands/*.md'       # 3
AGENTS   = discoverAgentPaths().map(pathToAgentId)          # 67 — agent-registry.ts:37-47; excludes README*, references/
CANONICAL_IDS = {`soleur:${n}` for n in SKILLS ∪ COMMANDS} ∪ AGENTS                                            # 165 distinct
SKILL_NAMES   = SKILLS ∪ COMMANDS
AGENT_LEAVES  = {last(':') segment of id for id in AGENTS}                                                    # unique; asserted
GROK_STEMS    = {agentIdToGrokSubagentType(id) for id in AGENTS}                                              # agent-registry.ts:107
```

`INDEX_GLOBS` and `POPULATION_GLOBS` are **separate constants** (spec-flow #7b), so emptying the
population fires N4's "0 docs examined" rather than the index invariant. All `git ls-files` calls
run with `cwd: PLUGIN_ROOT` and `--full-name` so `bun test` from the plugin directory (its
`bunfig.toml` invites it) does not resolve to an empty set (spec-flow #7d).

### Population

```
POPULATION_GLOBS = [
  ':(glob)plugins/soleur/skills/*/SKILL.md',          # 98 — regionPolicy: skill
  ':(glob)plugins/soleur/commands/*.md',              # 3  — regionPolicy: command
  ':(glob)plugins/soleur/codex/skills/*/SKILL.md',    # 3  — the Codex front door (F20's shape, one harness over)
  ':(glob)plugins/soleur/devin/skills/*/SKILL.md',    # 3  — the Devin front door
]
EXCLUDED_BY_PATH = { 'plugins/soleur/commands/help.md': 'its subject is the per-harness typed forms; 117 of 155 lines would be region-exempt, which is a whole-file exemption wearing markers (DHH #5)' }
```

`regionPolicy` is derived from **which glob matched**, so one constant carries both membership and
policy (arch F5). `census(docs, index)` is pure; `readPopulation()` is the only I/O. Widening is
one line (NG-P; residue measured).

### Tokenisation and the boundary allowlist

A **token** is a maximal run of `[A-Za-z0-9_:-]`. For index lookup the token is stripped of
trailing `[:_-]+` (Kieran #1: `/ship:` and `/work:` glued the colon and escaped); the **raw**
token is kept for R1 and R4 so `/soleur:<skill>` still trips the namespace sentinel.

`BOUNDARY` — the allowlist of characters permitted immediately before a reference: whitespace,
line start, and `` ` " ' ( [ { * < > | , ; . = + & ? # → — – ``. Each member has a measured prose
reason (delimiters and emphasis; `.` for `` `.go` ``; `=` for `KEY=value`; `+`/`→` for
`plan+work`/`plan→work`; `&`/`?` for URLs and shell; `#` for markdown anchors and `#NNNN` issue
refs — simplicity F6). No harness uses any of them as an invocation sigil (all four
`formatSkillInvocation` branches and `formatAgentSpawn` read). Anything **not** in the set —
`/`, `$`, `@`, `!`, `%`, `~`, `\`, and any character nobody has thought of — is a sigil. Authors
who collide with the set (a shell variable `$work`, a glob `"$d"/rclone-*`) brace or rename the
identifier; **BOUNDARY is never widened to admit a sigil** (W6 teaches this).

### Classification (per token; `t` = stripped, `raw` = as matched, `c` = the character before it)

`atb` = `c` is line-start or ∈ BOUNDARY. `pathctx` = `c == '/'` and the character before the `/`
matches `[A-Za-z0-9_./]` — the **second** verdict-deciding allowlist (its own fixtures and rows).

| Rule | Condition | Verdict |
| --- | --- | --- |
| R1 | `raw` starts with `soleur:` and not `atb` | **NONCANONICAL** — namespace sentinel: `/soleur:x`, `$soleur:x`, `/soleur:<metavar>`, typos |
| R2 | `raw` starts with `soleur:`, `atb`, `t ∈ CANONICAL_IDS` | CANONICAL |
| R3 | `raw` starts with `soleur:`, `atb`, `t ∉ CANONICAL_IDS` | UNKNOWN-NS — reported, not gated; the **set** is diffed pre/post remediation by AC (spec-flow #4), so a hand rewrite to `soleur:tigger-cron` cannot go quietly green |
| R4 | `raw` contains `soleur:` not at its start | **NONCANONICAL** — `@agent-soleur:product:cpo` |
| R5 | `t ∈ GROK_STEMS`, not `pathctx` | **NONCANONICAL** — `soleur-product-cpo`; derived by the adapter's own function |
| R6 | `t ∈ SKILL_NAMES`, `atb` | BARE — skill names are English words ("the plan file") |
| R6b | `t ∈ AGENT_LEAVES`, not `pathctx` | **NONCANONICAL** — `Task git-history-analyzer(…)`, "the `cpo`". Agent leaves are never prose words and a bare leaf maps to no Grok stub (`agentIdToGrokSubagentType("cpo") → "cpo"`); canonical is the registry id (**operator decision, CPO #1**) |
| R7 | `t ∈ SKILL_NAMES ∪ AGENT_LEAVES ∪ GROK_STEMS`, `pathctx` | PATH — `skills/plan/SKILL.md`, `agents/product/cpo.md`, `.grok/agents/soleur-product-cpo.md`, `./plan`, `https://…/plan` |
| R8 | `t ∈ SKILL_NAMES`, otherwise | **NONCANONICAL** — `/plan`, `$plan`, `%plan` |
| R9 | not `atb`, **not `pathctx`** (CTO #1, Kieran #5), `t ∉` any set, and some hyphen-suffix `t.split('-')[i:]`, i ≥ 1, ∈ `SKILL_NAMES ∪ AGENT_LEAVES ∪ GROK_STEMS` | **NONCANONICAL** — `@agent-cpo`, `@agent-kieran-rails-reviewer`, `$x-plan`. Path components (`…-feature-plan.md`, `lint-agents-compound-sync.sh`) are excluded by the `pathctx` clause; prose compounds after whitespace (`deepen-plan`, `re-plan`) never reach R9 |
| — | anything else | not a reference |

Fenced code is classified like prose (H5). Marker lines are handled by the region grammar below.

The **harness attribution** in the message (`/x` → grok, `/soleur:x` → claude/devin, `$soleur:x`
→ codex, `@agent-` → claude, hyphen stem → grok, bare leaf → "dead on grok", else "unrecognised
sigil") is a local lookup that decorates the message; it never participates in the verdict, so an
incomplete attribution table cannot blind the gate. The **fix hint** resolves to the full id:
leaf → registry id, stem → id, skill → `soleur:<skill>` (spec-flow #4, CTO #5). The printed site
is `c + raw` so found and fix never read identically (spec-flow #6); the "unrecognised sigil"
and bare-leaf tails add *"— or, if this is not a component reference, brace/rename the
identifier"*.

### Exempt region — one kind, one file

`<!-- harness-forms:start -->…<!-- harness-forms:end -->`, honoured **only** where `regionPolicy`
is `command`. Its subject is the per-harness forms themselves: go.md Step 2.0's table and
paragraphs (`:128-157`), the Devin/Grok lines of Step 2.1, and the Sharp Edge "Grok entry is
`/go`" (`:207`). `help.md` is excluded by path instead of wrapped. `sync.md` carries no
harness-teaching prose and gets no region (Kieran #6).

**Marker grammar** (arch F4, spec-flow #7a, Kieran #9): a marker is a whole line that after
`trim()` equals `<!-- harness-forms:(start|end) -->` byte-for-byte. A line matching the loose
`/<!--\s*harness-forms\s*:\s*(start|end)\s*-->/i` that fails the strict match is RED
"malformed marker" (case, CRLF, inline text). A stray `:end`, a `:start` while the region is open,
or a `:start` never closed is RED for the doc. Markers with any **other** name are transparent —
they are ordinary content lines and never open or close anything — so a `harness-forms` region
may sit inside `<!-- workflow-fidelity:block:go-post-route:start -->` (go.md `:176-185`). Fenced
markers are honoured.

**Preambles are not exempt.** The 12 `grok-harness-invoke` blocks lose their `/plan` clause and
gain the general rule, which is the surface a `/ship`-entered Grok session actually has in context
(spec-flow #1):

> **Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this
> process and run it to completion. Any `soleur:<name>` in this document names a skill — on Grok
> Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested
> tool_use. **Claude Code:** Skill tool (`soleur:<name>`). Forbidden is executing a subset, not
> the Read.

Classifier-clean (`soleur:<name>` is R3, the path is R7). Guard 1 in `workflow-fidelity.test.ts`
gains one regex (`/any `soleur:<name>` in this document names a skill/i`) so the sentence is pinned
where the carriers already are; `one-shot`'s "of these steps" drift is aligned in the same edit.
The 86 non-carrier skills entered directly on Grok have no in-context mapping — declared in
ADR-226 as "`/go` is the Grok entry" (the go.md Sharp Edge already says so).

### Anti-vacuity without a baseline

The gated property is absolute — `NONCANONICAL == []` for every doc — so there is no number to
pin and no compensating swap to defend against. What can go quietly blind is the **instrument**,
and each blindness has a permanent, independent check:

- **Index invariant** (in the tree test, from its **own literal** pathspecs, never importing
  `INDEX_GLOBS`): every `skills/*/SKILL.md` dir → `soleur:<dir>` ∈ `CANONICAL_IDS`; every
  `commands/*.md` → `soleur:<base>` ∈ `CANONICAL_IDS`; `|AGENTS| === EXPECTED_SOLEUR_AGENT_COUNT`
  (67, from `agent-registry.ts:16`); `AGENT_LEAVES` are unique and disjoint from `SKILL_NAMES`;
  `|CANONICAL_IDS|` equals the independently counted distinct total. `readIndex() → []` fails
  this naming the first missing id, before any doc is examined. `pathToAgentId` itself is pinned
  by `agent-registry.test.ts:13-21` (not re-pinned here — simplicity F5).
- **Empty population** throws `harness-parity: 0 docs examined` (N4).
- **Permanent fixtures** (Phase 2) pin every rule, both allowlists, the token class, the
  trailing-punctuation strip, the region grammar and the policy, and run on every CI pass — so
  N5-class weakenings are RED on the same run that would have certified them.
- **Cross-file sentinel**: the fixture suite lives in `harness-parity.test.ts`; the tree census in
  `harness-parity-tree.test.ts`; the fixture suite asserts the tree file contains the literal
  `expect(noncanonical).toEqual([])` — genuinely cross-file, as ADR-224 §Verification does it
  (spec-flow #5, simplicity F4).

**Honest limit:** moving go.md's region markers to enclose a dispatch line is visible only in diff
review — one file, one region kind, markers in the diff. No hash is claimed to catch it; the
2026-09-14 learning says a registry that carries its own hash certifies itself, and a hash pinned
beside the classifier would be that.

### Operator-typed prompts render at emit time (DHH #4, arch F2, spec-flow #3, CTO #4 — converged)

A resume prompt (`brainstorm:604,617`, `plan:1009`, `work`'s resume block, `product-roadmap:46`)
and "dispatch the cron manually via …" (`gdpr-gate:270`) are text the **operator pastes into a
fresh session** where no routing contract is in context. `/soleur:plan #N` is a deterministic
slash dispatch on Claude and Devin today; a bare `soleur:plan #N` would be model-discretion on all
four. So the doc stays canonical and the **emitting step renders**: each site gains one sentence —
*render the entry as the active harness's operator-typed form per `formatSkillInvocation`
(`plugins/soleur/lib/harness.ts`) before printing; the operator types it, no agent reads it.* The
template shows `soleur:plan #<issue>`; the agent prints `/soleur:plan #123` on Claude, `/plan #123`
on Grok, `$soleur:plan #123` on Codex. Deterministic on all four, and the doc is R2-clean. AC asserts
the anchored phrase `operator-typed form` at every site `git grep -nlE 'Resume prompt|paste this|copy-paste' <population>` returns.

### The adapter's own fidelity strings render per harness (arch F3 — folded, was NG-F)

`pipelineInvocationSuffix(skill)` (`workflow-fidelity.ts:192`) and the harness-agnostic lines of
`workflowFidelityInstructions` (`:166-178`) emit `/postmerge`, `/ship`, `/work`, `/soleur:review`
on **every** harness — `invokeSkill("ship")` on Codex returns "invoke /postmerge after /ship".
That is the #8299 class emitted by the module ADR-226 names as the renderer. The fold is small
because the rendering already exists: `formatSkillList(skills, harness)` (`:130`); the suffix
gains the `harness` argument its only caller (`harness.ts:150`) already holds. Every existing pin
(`workflow-fidelity.test.ts:130,165,173,180,181,202,267`) exercises the **grok** arm and stays
green; `:235` (pins `plan/SKILL.md` contains `/work`) is repointed to `soleur:work` — today it
would survive remediation only because the doc contains the substring inside a path (CTO #6a).
One new assertion: `invokeSkill("ship")` under a codex env contains `$soleur:postmerge` and not
`/postmerge`.

### Not gated — the completeness claim, with counts

| Not gated | Why | Residue | Disposition |
| --- | --- | --- | --- |
| **NG-M** bare mechanism nouns (`Skill tool`, `Task tool`, `subagent_type`, …) **not** carrying a name through a sigil | no canonical word to allowlist against; a mechanism check is a blocklist. The adapters translate the noun themselves (`codex/INSTRUCTIONS.md:29-30`, `devin/INSTRUCTIONS.md:76-77`, `routingInstructions("grok")` "do not invent a nested Skill tool") — CPO confirmed resolvable | 82 lines / 29 docs | follow-up issue; W6 teaches the canonical phrasing |
| Dual-voice `**Grok:** Read plugins/soleur/skills/<x>/SKILL.md in this process` | PATH by design: a file path resolves on every harness, and `workflow-fidelity.test.ts:417-468` **requires** these lines | 20 lines / 7 docs | declared; the answer to "can Grok's exact form of a known name pass?" is **yes, this one, on purpose** (Kieran #2) |
| `soleur:<unknown>` (R3) | a typo is a different defect | 20 sites | reported; the set is diffed by AC |
| Case variants (`/Plan`) and HTML entities (`&#47;plan`) | harness slash commands are case-sensitive; agents read raw markdown | 0 | listed so they are not rediscovered (Kieran #10) |
| Other agent-read docs | one glob each; bounded diff | agents 35 / 15, `skills/*/references/**` 44 / 19 | **NG-P** follow-up, P1 `single-user incident`. Scoped to agent-read docs: `README.md`, `docs/**`, `CHANGELOG.md` are human-read surfaces where the slash form is right (CTO #6b). Note for NG-P: `codex/INSTRUCTIONS.md` / `devin/INSTRUCTIONS.md` need a region or path policy when the population widens |
| Human-typed entry points in README / docs / `llms.txt` | a human types them; enumerated per harness by design | — | ADR-226 §Decision says so (CPO #5) |
| `AGENTS.rules.md`'s nine slash-form examples | outside the population, but the pattern every agent imitates | 9 | **W11**: canonicalised in this PR (docs-only, −1 byte each, no new rule) |

## v3 disposition of every v2 finding

| # | v3 answer |
| --- | --- |
| G1 | Role is not classified; the canonical shape is correct in every role. Operator-typed lines are rendered at emit time, not canonicalised for the operator |
| G2 | Conceded and priced: prefix substitutions are `--fix`-generated and verified by re-classification; hand edits are the residual the reviewer reads |
| G3 | Guard 1 (`workflow-fidelity.test.ts:402`) pins the 12 carriers; the preamble gains the general rule and one more Guard 1 regex |
| G4 | V9 dropped |
| G5–G6 | One classifier, one number: 1029 / 62, reproduced independently before any doc edit |
| G7 | No token set exists to remove; blindness rows are permanent fixtures |
| G8 | go.md's Step 2.0 is a region; help.md is excluded by path with the reason stated, not hashed |
| G9 | No `as const`/`never`/tsconfig; no `SUPPORTED_HARNESSES` at all |
| H1 | No form list decides anything; `/kb-search` is R8 |
| H2 | The five blind docs are RED |
| H3 | R1 catches `/soleur:<skill>` |
| H4 | No `tsc` AC |
| H5 | Fences classified; resume prompts stay canonical in the doc and render at emit time |
| H6 | One region name; unknown markers transparent; strict grammar; skills have no exemption |
| H7 | No pin to compensate against |
| H8 | No ledger |
| H9 | W6 shows only the canonical form and describes the forbidden shapes in words |
| H10 | 226 — every ref probed |
| H11 | No `never` arms |
| H12 | Folded: the fidelity strings render per harness (arch F3) |

v1's F1–F30 refuted a mechanism v3 no longer contains; the survivors (born-blocking, derived
population, whole-tree) are retained.

## v3 Requirements

- **W1 Classifier.** `plugins/soleur/lib/harness-parity.ts`: `readIndex()`, `readPopulation()`,
  `classifyDoc(text, index, regionPolicy)`, `census(docs, index)`, `fixDoc(text, index)` (the
  mechanical inverse for R1/R4/R8 slash-and-dollar forms and `@agent-soleur:` mentions; never for
  R6b/R9 leaf rewrites, regions or prose). Rules R1–R9, BOUNDARY, the path class, the token class,
  the strip rule and the marker grammar are constants with a rationale comment beside each.
- **W2 Fixture self-test.** `plugins/soleur/test/harness-parity.test.ts` runs `classifyDoc` and
  `census` over synthesized docs under `plugins/soleur/test/fixtures/harness-parity/{skills,commands}/`
  (the subdirectory selects `regionPolicy`, so the path→policy mapping has a permanent fixture —
  Kieran #8, spec-flow #7c) and asserts each expected verdict and message (Phase 2 table).
- **W3 Tree census.** `plugins/soleur/test/harness-parity-tree.test.ts`: index invariant; `census`
  over `readPopulation()`; `expect(noncanonical).toEqual([])` per doc with the per-site message;
  UNKNOWN-NS reported. The fixture file asserts this file contains that literal (cross-file).
- **W4 CLI.** `plugins/soleur/scripts/harness-parity-census.ts --report | --fix`. `--fix` applies
  `fixDoc` in place and is idempotent (H4). The failure message names `--fix`.
- **W5** *(deleted — no `SUPPORTED_HARNESSES`.)*
- **W6 Authoring lines.** The same one bullet in `skill-creator/SKILL.md` §Sharp Edges,
  `compound-capture/SKILL.md` Step 8 (before the write), and `heal-skill/SKILL.md`'s change step:
  *name a skill or command as `soleur:<name>` and an agent by its registry id, nothing else — no
  slash, dollar or at-sign prefix, no bare agent leaf; the adapter renders the harness form. If a
  shell variable or glob collides with a skill name, brace or rename it — never widen the gate's
  boundary set. `harness-parity-tree.test.ts` is the gate; `harness-parity-census.ts --fix`
  repairs the mechanical shapes.* Step 8.1's skill row becomes `soleur:foo` (CTO #3). Shows only
  canonical examples (H9).
- **W7 Remediation.** `--fix` for the mechanical shapes, then hand edits: 488 leaf → registry id
  (mechanical by the leaf→id function, but reviewed per site because the surrounding sentence
  changes), the three go.md regions, `go.md:124`, the 12 preambles, `one-shot`'s alignment, the two
  false positives, the `description:` substitutions.
- **W8 Routing-contract sentence.** go.md `:147` widened from "a table row" to "any `soleur:<name>`
  in any Soleur doc"; the same sentence in `routingInstructions("grok")` (`harness.ts:436-446`) for
  the eval harness — **not** claimed as a delivered surface (arch F2).
- **W9 Emit-time rendering** at every resume/paste site (§above), anchored phrase `operator-typed form`.
- **W10 Fidelity strings render per harness** (§above): `pipelineInvocationSuffix(skill, harness)`;
  `formatSkillList` in the harness-agnostic lines; `:235` repointed; codex assertion.
- **W11** `AGENTS.rules.md`: nine slash-form examples canonicalised (`/soleur:work` → `soleur:work`,
  `/one-shot` → `soleur:one-shot`, …). `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1`
  stays `[OK]` (each edit is −1 byte or neutral).
- **W12 ADR-226** (§Architecture Decision). No C4 edit.
- **W13** Description budget stays 2442/2442; the two substitutions are token-for-token, and they
  render on soleur.ai via `docs/_data/skills.js:23` ("delegates to soleur:one-shot" on a public page
  — acceptable, stated).

## v3 Non-Goals

- **NG-M** bare mechanism nouns (82 / 29) — **#8318**.
- **NG-P** other agent-read docs (agents 35 / 15, references 44 / 19) — **#8317** (P1) with the
  glob lines to add, the human-read exclusions, and the INSTRUCTIONS.md region note.
- **NG-U** gating `soleur:<unknown>` — reported and diffed only.
- v2's NG1–NG6 stand (`#7453`; `#8306`; `#8307`; `UNION` kept; no `AGENTS.rules.md` rule — W11
  edits examples inside existing rules, it adds none).

## v3 Files to Create

| Path | Purpose |
| --- | --- |
| `plugins/soleur/lib/harness-parity.ts` | W1 |
| `plugins/soleur/test/harness-parity.test.ts` | W2 fixtures + the cross-file sentinel |
| `plugins/soleur/test/harness-parity-tree.test.ts` | W3 tree census + index invariant |
| `plugins/soleur/test/fixtures/harness-parity/{skills,commands}/*.md` | Phase 2 fixtures (synthesized) |
| `plugins/soleur/scripts/harness-parity-census.ts` | W4 |
| `knowledge-base/engineering/architecture/decisions/ADR-226-canonical-component-references-in-plugin-docs.md` | W12 (ordinal provisional) |

## v3 Files to Edit

| Path | Edit |
| --- | --- |
| `plugins/soleur/lib/workflow-fidelity.ts:166-178,192-225` | W10 |
| `plugins/soleur/test/workflow-fidelity.test.ts` | `:235` → `soleur:work`; Guard 1 (`:402-415`) gains the preamble-rule regex; one codex assertion for W10 |
| `plugins/soleur/lib/harness.ts:436-446` | W8 grok-arm sentence |
| `plugins/soleur/commands/go.md` | three `harness-forms` regions; `:147` W8; `:124` canonical; 47 sites |
| `plugins/soleur/commands/sync.md` | 15 sites |
| 12 preamble carriers (`LOCKED_PIPELINE_SKILLS`, `workflow-fidelity.test.ts:388-400`) | preamble text (W7) |
| ~60 `plugins/soleur/skills/*/SKILL.md` | sites = `--report` output; top: review 218, plan 163, work 81, ship 72 |
| `plugins/soleur/skills/{skill-creator,compound-capture,heal-skill}/SKILL.md` | W6 |
| `plugins/soleur/skills/{brainstorm,plan,work,product-roadmap,gdpr-gate}/SKILL.md` resume/paste sites | W9 |
| `plugins/soleur/skills/{drain-labeled-backlog,product-roadmap}/SKILL.md:3` | `description:` (W13) |
| `plugins/soleur/skills/work/SKILL.md:1359` | `"$work"` → `"${work}"`; `rclone/SKILL.md:33` glob braced likewise |
| `AGENTS.rules.md` | W11 |
| `knowledge-base/project/specs/feat-harness-parity-gate-8299/{spec,tasks}.md` | re-based on v3 |

Diff-scope note (Sharp Edge #8207): the pipeline also writes `knowledge-base/INDEX.md`,
`specs/<branch>/session-state.md`, learning files and this plan.

## v3 Implementation Phases

No commit is RED: `lefthook.yml:311` runs the full battery on any staged `.ts` (F30), and
`lefthook.yml:333` runs `bun test plugins/soleur/test/` on any staged `.md` — which includes
`workflow-fidelity.test.ts`'s doc pins (spec-flow #2).

### Phase 1 — Classifier, fixtures, fidelity fold, preambles (commit 1, GREEN, `.ts`+`.md`)

1. Write the Phase 2 expected-verdict table **first**, then W1.
2. W2 fixtures + `harness-parity.test.ts` (fixture suite only; the cross-file sentinel lands in Phase 4).
3. W4 CLI. W10 fold + its test edits. W8 grok-arm sentence.
4. The 12 preambles rewritten + Guard 1's new regex — in this commit, so Guard 1 is never RED.
5. **Local RED checkpoint (not committed):** `bun plugins/soleur/scripts/harness-parity-census.ts --report`
   prints **1029 sites / 62 docs** with the attribution split in §Measurements. A different
   number means the port diverged from the measured predicate — reconcile against
   `census4.py`'s rules before touching a doc. Known method-sensitive cells: none; every cell is
   a rule.

### Phase 2 — Fixture table (written in Phase 1 step 1)

| Fixture | Content | Expected |
| --- | --- | --- |
| `skills/canonical.md` | `` `soleur:plan` ``, `Skill(soleur:go)`, `skill: soleur:preflight`, `` `soleur:product:cpo` `` | 4 CANONICAL, 0 NONCANONICAL — must-PASS |
| `skills/bare-prose.md` | "the plan file", `` `plan` ``, "(review)", "**work**" | BARE only — must-PASS |
| `skills/path.md` | `plugins/soleur/skills/plan/SKILL.md`, `agents/product/cpo.md`, `.grok/agents/soleur-product-cpo.md`, `./plan/x`, `https://a/b/plan`, `references/foo-plan.md` | PATH only — must-PASS |
| `skills/path-compound.md` | `plans/2026-01-01-feat-x-plan.md`, `references/discord-community.md`, `scripts/lint-agents-compound-sync.sh` | not-a-reference — must-PASS (R9 path exclusion) |
| `skills/boundary-punctuation.md` | `KEY=plan`, `plan+work`, `plan→work`, `` `.go` ``, `?plan`, `#plan-heading`, `(#breach-notice-triage)`, and `--plan`, `deepen-plan`, `re-plan`, `post-review` after whitespace | BARE / not-a-reference — must-PASS; pins each BOUNDARY member and the token class |
| `skills/grok-slash.md` | `` `/plan` ``, `(/plan)`, `"/plan"`, `/plan` at line start | 4 NONCANONICAL, grok; message ends `write soleur:plan` |
| `skills/claude-devin-slash.md` | `/soleur:plan`, `` `/soleur:work` `` | 2 NONCANONICAL, claude/devin |
| `skills/codex-dollar.md` | `$soleur:plan` | 1 NONCANONICAL, codex |
| `skills/claude-agent-mention.md` | `@agent-soleur:product:cpo` | 1 NONCANONICAL, claude; hint `soleur:product:cpo` |
| `skills/claude-agent-leaf-mention.md` | `@agent-cpo`, `@agent-kieran-rails-reviewer`, `@agent-soleur-product-cpo` | 3 NONCANONICAL, claude; hints resolve to registry ids |
| `skills/bare-agent-leaf.md` | `Task cpo(…)`, "the `git-history-analyzer`", `security-sentinel` at line start | 3 NONCANONICAL, "bare agent leaf — dead on grok"; hint = registry id |
| `skills/grok-stem.md` | `soleur-product-cpo` | 1 NONCANONICAL, grok |
| `skills/trailing-punctuation.md` | `/plan:`, `/work-`, `@agent-cpo:`, `soleur-product-cpo:` | 4 NONCANONICAL (Kieran #1) |
| `skills/metavariable.md` | `soleur:<skill>` and `/soleur:<skill>` | 1 UNKNOWN-NS, 1 NONCANONICAL |
| `skills/novel-sigil.md` | `%plan`, `!plan`, `~plan` | 3 NONCANONICAL, "unrecognised sigil" with the brace/rename tail |
| `skills/unknown-name.md` | `/frobnicate`, `$soleur:frobnicate` | 0 + 1 (R1) — the index bound |
| `skills/fenced.md` | `/soleur:work` inside a fence | 1 NONCANONICAL (H5) |
| `skills/region-forms-in-skill.md` | `/go` inside `harness-forms` | 1 NONCANONICAL — not honoured under `skills/` |
| `commands/region-forms.md` | `/go` inside `harness-forms` | EXEMPT 1 — must-PASS |
| `commands/region-unknown-name.md` | `/plan` inside `<!-- not-an-allowed-region:start -->` | 1 NONCANONICAL; the unknown markers are content |
| `commands/region-nested-unknown.md` | `harness-forms` opened inside an unknown-named block | EXEMPT — must-PASS (unknown markers transparent) |
| `commands/region-malformed.md` | `<!-- Harness-Forms:start -->`, CRLF marker, `<!-- harness-forms:end --> run /plan` | RED "malformed marker" ×3 |
| `commands/region-stray-end.md`, `region-unterminated.md`, `region-double-start.md` | as named | RED each |
| `skills/two-violations.md` | canonical line, `/plan`, `$soleur:work` | 2 NONCANONICAL, both line numbers |
| `skills/frontmatter.md` | `description: "… delegates to /soleur:one-shot"` | 1 NONCANONICAL — frontmatter is not exempt |
| `skills/fix-roundtrip.md` | the mechanical shapes | `fixDoc` output classifies clean; `fixDoc(fixDoc(x)) == fixDoc(x)`; leaves and regions untouched |
| empty population | `census([], index)` | throws `harness-parity: 0 docs examined` |
| nested SKILL.md | `skills/x/references/SKILL.md` under a plain pathspec | present → the `:(glob)` row (N12) |

### Phase 3 — Remediation (commits 2…n, `.md`-only, each GREEN under `plugin-component-test`)

1. **Commit 2 = `--fix` on the base, nothing else.** `git diff` against a fresh `--fix` run is
   empty (CTO #2) — reviewers read only the hand edits that follow.
2. Hand edits, one commit per doc group, verifying with `--report` after each:

| Found | Write |
| --- | --- |
| bare agent leaf | the registry id (`git-history-analyzer` → `soleur:engineering:research:git-history-analyzer`) |
| `@agent-<leaf>` | the registry id |
| `soleur-a-b` stem in prose | `soleur:a:b` (outside regions) |
| `/soleur:<metavar>` | `soleur:<metavar>` |
| go.md `:124` `/one-shot` (Grok) or `soleur:one-shot` (Claude) | "route through `soleur:one-shot`" — the dual-voice `:122` **stays** |
| per-harness *teaching* prose in `commands/go.md` | wrap in `harness-forms` |
| resume/paste templates | canonical + the emit-time sentence (W9) |
| `"$work"`, `"$d"/rclone-*` | brace: `"${work}"`, `"$d"/{rclone}-*` or reword |

### Phase 4 — Tree census (commit n+1, GREEN)

`harness-parity-tree.test.ts`; the cross-file sentinel added to the fixture suite; `--report`
prints `0 sites` and the UNKNOWN-NS set equals the Phase 1 set. Run the Guard 3 matrix against a
pristine copy; record each observed message in the PR body.

### Phase 5 — Authoring surfaces, ADR, spec (commit n+2)

W6 (three skills), W11, ADR-226, spec.md FRs re-based, tasks.md regenerated, follow-up issues
(NG-M, NG-P) filed and referenced.

## Guard Contract — v3 (plan of record)

### Guard 3 — every known-name reference in a plugin doc is canonical

**Property.** For every doc in the population and every token that names a known skill,
command or agent, the token is the canonical id at a prose boundary, a bare **skill** name in
prose, or a path component — and the detector cannot report clean over a population it failed to
enumerate, an index it failed to read, a boundary/path/token class wider than the one committed,
or a region policy looser than "one name, commands only".

**Assembly.** Four chokepoints, none a member list: (1) the population — `POPULATION_GLOBS` with
`:(glob)` magic, carrying `regionPolicy`, injectable; (2) the index — `INDEX_GLOBS` plus
`discoverAgentPaths()`/`pathToAgentId`/`agentIdToGrokSubagentType`, a separate constant from (1);
(3) the classifier — `classifyDoc`, the single verdict site, holding BOUNDARY, the path class,
the token class, the strip rule and the marker grammar; (4) the tree test's own literal pathspecs
for the index invariant. `census` and `fixDoc` only fold and invert; neither decides.

**Mutation matrix.** Each row must drive the suite RED **with the census's own message**
(ADR-193). Fixture-backed rows run on every CI pass; N-rows are hand-run against a pristine copy.

| # | Mutation | Must produce |
| --- | --- | --- |
| N1 | Reintroduce `/soleur:trigger-cron` in `gdpr-gate/SKILL.md` | `gdpr-gate/SKILL.md:<l>: /soleur:trigger-cron — claude/devin; write soleur:trigger-cron` |
| N2 | Reintroduce `/kb-search <keyword>` in `kb-search/SKILL.md` | `… /kb-search — grok; write soleur:kb-search` |
| N3 | `git add` a new `skills/zz-fixture/SKILL.md` containing `/plan` after a compliant doc | RED naming the new path — the classifier does not stop at the first doc |
| N4 | Empty `POPULATION_GLOBS` | `harness-parity: 0 docs examined` — and **not** the index invariant, because `INDEX_GLOBS` is separate |
| N5 | Add `/` to BOUNDARY | `grok-slash.md` RED: expected NONCANONICAL, got BARE |
| N5b | Add `` ` `` to the path class | `grok-slash.md` RED: expected NONCANONICAL, got PATH |
| N5c | Remove `-` from the token class | `boundary-punctuation.md` RED: `deepen-plan` reports a reference |
| N5d | Delete R9 | `claude-agent-leaf-mention.md` RED |
| N5e | Remove the trailing-punctuation strip | `trailing-punctuation.md` RED |
| N5f | Remove R9's path exclusion | `path-compound.md` RED |
| N5g | Make R6b permit bare leaves | `bare-agent-leaf.md` RED |
| N6 | Honour `harness-forms` under `skills/` | `region-forms-in-skill.md` RED |
| N7 | Add `not-an-allowed-region` to the honoured names | `region-unknown-name.md` RED |
| N8 | Make the marker match case-insensitive | `region-malformed.md` RED |
| N9 | Reintroduce `Task cto(…)` in `review/SKILL.md` | `review/SKILL.md:<l>: cto — bare agent leaf, dead on grok; write soleur:engineering:cto` |
| N10 | `readIndex() → []` | index invariant RED naming the first missing id, before any doc is examined |
| N11 | Delete the tree `describe` | fixture suite RED: cross-file literal missing |
| N12 | Replace `:(glob)` with a plain pathspec | nested-SKILL.md fixture RED (a `skills/x/references/SKILL.md` is enumerated and mis-named) |
| N13 | Revert `pipelineInvocationSuffix` to the harness-agnostic form | codex assertion RED: instruction contains `/postmerge` |

**Harness rows.**

| # | Mutation / input | Must |
| --- | --- | --- |
| H1 | Delete every `expect` in the tree `describe`, keep the `describe` | RED — the fixture suite asserts the tree file contains the literal `expect(noncanonical).toEqual([])` |
| H2 | `bare-prose.md`, `path.md`, `path-compound.md`, `boundary-punctuation.md` | **PASS** — the permitted non-canonical inputs |
| H3 | `commands/region-forms.md`, `commands/region-nested-unknown.md` | **PASS** — the sanctioned exemption exercised green |
| H4 | `--fix` twice on the pre-remediation tree | second run changes nothing; `fix-roundtrip.md` pins the same at unit level |
| H5 | `POPULATION_GLOBS` pointed at the fixtures dir (env override) | RED on exactly the violating fixtures — the tree census and the fixture suite share one classifier |

**Anchor.** There is no stored value: the property is absolute and the instrument is pinned by
fixtures that live outside the classifier and outside the docs. Weakening the gate means editing a
rule constant **and** the fixture that pins it, in one reviewable diff. Honest limit: one commit
can edit both; this proves consistency against the committed fixtures, not integrity against a
determined author, and the go.md region is review-only (§Anti-vacuity).

## v3 Architecture Decision (ADR/C4)

### ADR

**ADR-226 — Component references in plugin docs are canonical `soleur:<name>`; harness forms are
the adapter's to render.** Ordinal re-derived across every `origin/*` ref at `/ship` (rule stated
verbatim in AC13: first N with no `decisions/ADR-N-*` on any `origin/*` ref); on renumber, sweep
plan + spec + tasks + ACs. Rich shape (AP-011: reverses two refuted designs). Decision: (1) the
canonical shapes and the permitted contexts (R2/R6/R7), with agents by registry id; (2) population
and index derived — `git ls-files` with `:(glob)` and `discoverAgentPaths()` — never listed; (3)
one exempt region kind, commands only, strict grammar; `help.md` excluded by path with the reason;
(4) **agent-read prose is canonical; human-typed entry points** (README, docs, `llms.txt`, help.md)
**are enumerated per harness by design** (CPO #5); operator-pasted prompts emitted by a skill render
at emit time via `formatSkillInvocation`; (5) `/go` is the Grok entry — a skill entered directly on
Grok has only its preamble in context, and the 12 carriers carry the general rule; (6) born-blocking,
no baseline. Alternatives Considered: v1 presence census, v2 token blocklist (AP-025; H1), fence
stripping, path ledger, scalar snapshot, per-doc vector (both panels; operator decision), preamble
template pin (Guard 1 already pins). Consequences: NG-M and NG-P as declared gaps with issues; the
dual-voice Grok-Read lines as PATH by design; the 81-lines/month firing rate and `--fix`. Canonical
source AP-025; no new AP row.

### C4 views

All three model files read (`model.c4` 785 lines, `views.c4` 96, `spec.c4` 54). External actors:
the founder (modeled). External systems: Codex (`model.c4:8`), Devin (`:22`), Grok Build
(`platform.grokBuild`), Claude Code (`:96-99`) — all modeled with `-> platform.plugin` edges.
Container touched: `platform.plugin` (`:112`) only; no new element, edge, access relationship or
view include. **No C4 edit**: a doc-shape invariant and its test belong in the ADR, not in a
container description (simplicity F8). `c4-count-parity.test.sh` stays 10/10 (nothing in
`model.c4` changes). Advisory, pre-existing and unregistered: `model.c4:118` says "65 domain agents"
against a registry of 67 — noted in the NG-P issue, not fixed here.

### Sequencing

True at merge; no `adopting` status.

## v3 User-Brand Impact

Threshold **`single-user incident`**, `requires_cpo_signoff: true` (CPO reviewed the brainstorm
and this plan; carry-forward). `user-impact-reviewer` at review time.

**If this lands broken, the user experiences:** a green check beside a doc that still names a
form their harness does not have. The blind-green shapes each have a permanent fixture (a
boundary with `/` in it, a path class with a backtick in it, a token class without `-`, a
tolerant marker grammar, a region honoured in a skill, an index that resolves nothing, an empty
population), so the instrument is RED on the same run that would have certified it.

**If this leaks, the user's workflow is exposed via:** no new data surface. The exposure prevented
is a self-hosted operator on a non-Claude harness following plugin prose naming a dead form,
hitting nothing, and uninstalling without filing.

**Residual exposure after merge (CPO #2):** (a) bare mechanism nouns (82 lines / 29 docs) — the
adapters translate them and CPO judged the line resolvable; (b) agent bodies (35 sites / 15 docs)
and skill references (44 / 19) are still read by every spawned subagent on every harness until
NG-P lands — P1; (c) a skill entered directly on Grok resolves `soleur:<name>` only through its
preamble (12 carriers) — the other 86 rely on `/go` having run; (d) "canonical resolves on every
harness" is verified on Grok (`ci.yml:1320`) and Claude, **uncovered on Codex and Devin** (#8306).
The gate's promise is "no harness-specific form in skill/command prose", not "resolves everywhere".

- `threshold: single-user incident` — no regulated surface (GDPR gate on v1: `2 examined, 0 matched`;
  v3's file set adds none).

## v3 Observability

```yaml
gate:
  ci: .github/workflows/ci.yml:942 (test-bun via scripts/test-all.sh:2634) — auto-discovered
  precommit: lefthook.yml:333 plugin-component-test on any plugins/soleur/**/*.md; lefthook.yml:311 on any .ts
  failure_modes:
    - mode: a doc reintroduces a harness form or a bare agent leaf ; detection: tree test, per-site message naming --fix ; alert_route: CI red
    - mode: the population resolves to zero                        ; detection: N4 throw                                   ; alert_route: CI red
    - mode: the index resolves to zero or to the wrong registry     ; detection: index invariant, first missing id (N10)     ; alert_route: CI red
    - mode: BOUNDARY / path class / token class / grammar widened   ; detection: permanent fixtures (N5–N8)                  ; alert_route: CI red
    - mode: the adapter emits a grok form on another harness        ; detection: codex assertion (N13)                       ; alert_route: CI red
deliverable:
  artifact: the 106 docs in the installed plugin tree, read in-session
  failure_modes:
    - mode: canonical soleur:<name> does not resolve on a harness
      detection: grok — ci.yml:1320 grok-fidelity; claude — dev harness; codex/devin — declared UNCOVERED, #8306
      alert_route: none today (declared)
liveness_signal: the tree test itself — 0 docs examined throws; no cadence beyond CI
error_reporting: bun test stdout; fail_loud — every reason printed, never only an exit code
logs: CI job log, GitHub Actions default retention
discoverability_test:
  command: bun test plugins/soleur/test/harness-parity-tree.test.ts
  expected_output: "106 docs examined, 0 non-canonical, <n> canonical, <m> unknown-ns"
```

## v3 Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from the brainstorm; the panel's
CTO and CPO reviewed v3 directly — findings folded above).

### Engineering (CTO)

**Status:** reviewed. **Assessment:** the classifier is the design; `--fix` because 81 slash
lines/month enter the population; the authoring line belongs on the high-frequency surfaces
(compound-capture Step 8, heal-skill), not only skill-creator; one PR, proof-by-`--fix`.

### Product (CPO)

**Status:** reviewed. **Assessment:** allowlist shape protects the non-Claude user; bare agent
leaves are a dead Grok spawn and were a scope choice (operator: gate now); residual exposure must
be stated (done); agent-read vs human-typed boundary belongs in the ADR (done).

### Legal (CLO)

**Status:** reviewed (carry-forward). No legal surface; no `:-` form blessed (AC9).

### Product/UX Gate

**Tier:** none — no UI-surface file. **Brainstorm-recommended specialists:** none.

## v3 Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** Phase 1 RED checkpoint: `bun plugins/soleur/scripts/harness-parity-census.ts --report`
      on the pre-remediation tree prints `1029 sites in 62 docs` with attribution bare-leaf 488 /
      grok 339 / claude-devin 187 / claude-agent 8 / claude-leaf 3 / codex 2 / grok-stem 1 /
      unrecognised 1, and 20 UNKNOWN-NS sites (the set saved). Output in the PR body.
- [ ] **AC2** Post-remediation: `--report` prints `0 sites`; the UNKNOWN-NS set equals AC1's set
      (`diff`, not count); `--fix` on the post-remediation tree changes nothing.
- [ ] **AC3** Commit 2 is reproducible: `git checkout <base> && … --fix && git diff <commit-2>` is empty.
- [ ] **AC4** Every Phase 2 fixture asserts its stated verdict **and message**; the fixture suite has
      ≥ 30 tests; `bun test plugins/soleur/test/harness-parity.test.ts plugins/soleur/test/harness-parity-tree.test.ts` GREEN.
- [ ] **AC5** N1–N13 (incl. N5b–N5g) each observed RED with the stated message against a pristine
      copy; H1–H5 as stated; recorded in the PR body.
- [ ] **AC6** Spot-check independent of the classifier:
      `git grep -nE '(^|[^A-Za-z0-9_:./-])[/$@](soleur:)?(plan|work|ship|review|go|kb-search|trigger-cron)\b' -- ':(glob)plugins/soleur/skills/*/SKILL.md' ':(glob)plugins/soleur/commands/*.md'`
      returns only lines inside go.md's `harness-forms` regions or in `help.md`; and
      `git grep -nE '\bTask [a-z-]+\(' -- ':(glob)plugins/soleur/skills/*/SKILL.md'` returns 0.
- [ ] **AC7** `bun test plugins/soleur/test/components.test.ts` GREEN, `SKILL_DESCRIPTION_WORD_BUDGET` 2442 unchanged.
- [ ] **AC8** `bun test plugins/soleur/test/devin-cloud-mode.test.ts` GREEN (67, `UNION` intact);
      `bun test plugins/soleur/test/workflow-fidelity.test.ts` GREEN with Guard 1's new regex and
      `:235` reading `soleur:work`; `harness-model-map.test.ts:76` unchanged.
- [ ] **AC9** `! git diff origin/main...HEAD -- plugins/ scripts/ .github/ .claude/ | grep -E '^\+' | grep -q 'PLUGIN_ROOT:-'`.
- [ ] **AC10** The three W6 surfaces contain the anchored phrase `the adapter renders the harness form`
      and `harness-parity-census.ts --fix`; `compound-capture` Step 8.1's skill row reads `soleur:foo`;
      the census reports all three at 0 sites (H9).
- [ ] **AC11** Every doc `git grep -nlE 'Resume prompt|paste this|copy-paste' <population>` returns
      contains the anchored phrase `operator-typed form` within 5 lines of the template (W9);
      `gdpr-gate/SKILL.md:270` likewise.
- [ ] **AC12** All 12 `LOCKED_PIPELINE_SKILLS` preambles contain `names a skill` and no `/`-prefixed
      known name; go.md `:122` still contains `in this process`, `work/SKILL.md`, `Skill tool`;
      `:124` names `soleur:one-shot` only.
- [ ] **AC13** `ADR-226-*.md` exists; immediately before merge, `for r in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin/); do git ls-tree --name-only "$r" knowledge-base/engineering/architecture/decisions/; done | grep -c 'ADR-226-'` returns 1 (this branch only);
      on renumber, `grep -rn 'ADR-226' knowledge-base/project/{plans,specs}/` swept in the same edit.
      `model.c4` unchanged; `c4-count-parity.test.sh` 10/10.
- [ ] **AC14** `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` prints `[OK]`
      after W11, and `git grep -cE '/(soleur:)?(work|one-shot|ship|plan|review|loop)\b' AGENTS.rules.md` is
      lower than on `origin/main` by exactly the number of W11 substitutions (`/loop` is a Claude
      built-in, not a Soleur skill — it stays).
- [ ] **AC15** `git fetch origin main && SOLEUR_ALLOW_FULL_GATE=1 bash scripts/test-all.sh` GREEN.
- [ ] **AC16** `Ref #8318` (NG-M) and `Ref #8317` (NG-P) in the PR body — filed at plan time: NG-M (82 / 29 + the dual-voice
      declaration), NG-P (P1, `single-user incident`, glob lines, human-read exclusions, INSTRUCTIONS.md
      note, `model.c4:118`). `Ref #7453`, `#8306`, `#8307`, `#8308` — none folded, none closed.
      `Closes #8299`.
- [ ] **AC17** spec.md FR/TR sections re-based on v3; tasks.md regenerated with the BLOCKED banner removed.

### Post-merge

- [ ] `soleur:postmerge` on the merge SHA; `git ls-tree <release-tag> plugins/soleur/test/harness-parity-tree.test.ts` present.

## v3 Risks

| Risk | Mitigation |
| --- | --- |
| A BOUNDARY member is a harness sigil somewhere | none of the four harnesses uses one (all form-defining branches read); each member documented; pinned by `boundary-punctuation.md`; W6 forbids widening |
| `--fix` rewrites the wrong site | it inverts only R1/R4/R8 sigil-plus-known-name shapes; leaves, regions and prose are hand edits; every site is re-classified; commit 2 is reproducible (AC3) |
| 488 leaf → id rewrites change sentence shape | leaf→id is a function (uniqueness asserted); reviewed per doc group; `--report` after each |
| Emit-time rendering is forgotten at a new resume site | AC11 greps for the template shape; W6 names it |
| A `/ship`-entered Grok session on a non-carrier skill | declared in ADR-226 §5; `/go` is the Grok entry per go.md's Sharp Edge |
| ADR ordinal moves | provisional; AC13 rule + sweep |
| Region moves in go.md launder a dispatch | review-only, one file; stated as the honest limit |
| The `description:` substitutions render on soleur.ai | acceptable and stated (W13) |

## v3 Open Code-Review Overlap

`#4133` names `plugins/soleur/skills/plan/SKILL.md` — **Acknowledge**: concerns the
`## Observability` template shape, not this plan's reference-form edits. Remains open.

## v3 Plan Review — 7 of 7 returned, all PROCEED-WITH-CHANGES; every finding folded or dispositioned

The v3 **draft** (committed as `c5033d6ff`) was reviewed by DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow (eng panel, single-user-incident escalation), CTO (devex) and
CPO (product), after an `advisor`-tier consult. No reviewer blocked. Kieran reproduced the draft's
561/51 exactly. The plan of record above is the draft with every row below applied. Two findings
changed the operator's stated direction and were put to the operator (ADR-084 User-Challenge);
both answers are recorded.

| Source | Finding | Class | Disposition |
| --- | --- | --- | --- |
| advisor 1 | `@agent-<leaf>` hyphen-absorbed sigil passes R1–R8 (`plan-review:14`, live) | mechanical | R9 |
| advisor 2 | R7's path class is a second verdict allowlist with no row | mechanical | N5b + realistic `grok-slash.md` |
| advisor 3 | `canonical` column taxes every cross-reference edit; buys only N11 | mechanical | dropped; index invariant |
| advisor 4 | `exempt` count blind to a same-count marker move | mechanical | superseded by vector deletion; declared review-only |
| advisor 5 | tokenisation claims unpinned | mechanical | `boundary-punctuation.md` compounds + N5c |
| advisor 6 | NG-M boundary: a noun carrying a name through a sigil is a name form | mechanical | stated |
| DHH 1 | the gate is a syntax invariant, not "harness parity"; `brainstorm:80`-class lines stay green | mechanical | property restated in Overview, Guard 3, ADR, User-Brand Impact |
| DHH 2, simplicity F2 | delete the per-doc vector (both panels on one scope) | **user-challenge** | **operator: delete** |
| DHH 3 | stale `R1–R8` / 557 / 51 / ~17 mentions | mechanical | section rewritten |
| DHH 4, arch F2, spec-flow 3, CTO 4 | canonicalising operator-pasted prompts regresses Claude/Devin; no routing contract in a fresh session | mechanical | W9 emit-time rendering |
| DHH 5 | help.md's region is a whole-file exemption wearing markers | mechanical | excluded by path with the reason |
| DHH 6, simplicity F3 | delete `SUPPORTED_HARNESSES`, CLI `--check`/`--update`, same-file sentinel | mechanical | deleted; sentinel moved cross-file |
| DHH 7, Kieran 6 | AC2 arithmetic (sync.md has no region; awk counted the header) | mechanical | moot — no TSV |
| DHH 8, CTO 5 | W6 must teach brace/rename, never widen BOUNDARY | mechanical | W6 |
| simplicity F1 | Guard 1 already pins the 12 carriers; drop the `/plan` clause, no template pin | mechanical | preamble rewritten; one Guard 1 regex |
| simplicity F4, spec-flow 5 | same-file sentinel is self-certifying and RED at commit 1 | mechanical | two test files; sentinel lands in Phase 4 |
| simplicity F5 | N11's `pathToAgentId` half is vacuous | mechanical | N10 = `readIndex → []` only; `agent-registry.test.ts` cited |
| simplicity F6 | `#` belongs in BOUNDARY (anchors, `#NNNN`) | mechanical | added; no heading rename |
| simplicity F7 | R3 report has no consumer | mechanical | given one: the UNKNOWN-NS set is diffed by AC2 (spec-flow 4) |
| simplicity F8 | C4 description edit is the wrong layer | mechanical | no C4 edit |
| arch F1, Kieran 3 | index must be the registry (67), not the glob (68) | mechanical | `discoverAgentPaths()` |
| arch F3 | NG-F deferral rests on a false premise; pins are grok-arm | mechanical | folded as W10 |
| arch F4, spec-flow 7a, Kieran 9 | marker grammar unspecified | mechanical | strict grammar; unknown markers transparent |
| arch F5 | plain pathspec crosses `/`; policy is a second path decision | mechanical | `:(glob)`; policy from the matching glob; N12 |
| arch F6 | Codex/Devin entry wrappers are the front door one harness over | mechanical | 6 wrappers added to the population |
| arch F7 | 226 is free on every ref | mechanical | ADR-226; AC13 rule stated verbatim |
| spec-flow 1 | `/ship`-entered Grok session has only the preamble in context; `routingInstructions` has no emitter | mechanical | preamble carries the general rule; W8 demoted to eval-only; ADR §5 |
| spec-flow 2 | deleting go.md `:122` / one-shot dual voice REDs `workflow-fidelity.test.ts:417-468` | mechanical | dual voice stays; only `:124` canonicalised |
| spec-flow 4 | fix hint `write soleur:<leaf>` lands in the ungated R3 hole | mechanical | hint resolves to registry id; UNKNOWN-NS diffed |
| spec-flow 6 | printed site == fix for `/soleur:x`; wrong hint on false positives | mechanical | site printed as `c + raw`; brace/rename tail |
| spec-flow 7b–d | `INDEX_GLOBS` separate; policy fixture; `--full-name` + `cwd` | mechanical | done |
| spec-flow 8 | cost statement / observability line stale | mechanical | rewritten |
| CTO 1, Kieran 5 | R9 needs the explicit path-context exclusion (literal reading → 606/56) | mechanical | R9 text; `path-compound.md`; N5f |
| CTO 2 | no `--fix`; 81 slash lines/month; one PR with proof-by-`--fix` | taste → adopted | W4 `--fix`; AC3 |
| CTO 3 | authoring line on the high-frequency surfaces; Step 8.1 row; AGENTS.rules.md examples | taste → adopted | W6 on three skills; W11 |
| CTO 6a | `:235` survives remediation by accident | mechanical | repointed |
| CTO 6b | NG-P must exclude human-read surfaces; `description:` renders on soleur.ai | taste → adopted | NG-P scope; W13 |
| CTO 6c | new-skill baseline regen | — | moot — no baseline |
| CPO 1 | bare agent leaves are dead Grok spawns; NG-M's justification is false for them | **user-challenge** | **operator: gate now** — R6b, +488 sites |
| CPO 2 | state residual exposure, not only prevented | taste → adopted | User-Brand Impact §Residual |
| CPO 3 | brace/rename, never widen | taste → adopted | W6 |
| CPO 4 | pull agent bodies into this PR | taste → **declined** | the operator already doubled scope with R6b; agents (35 / 15) stay NG-P as P1 with the reason recorded here |
| CPO 5 | agent-read vs human-typed boundary in the ADR | taste → adopted | ADR §4 |
| Kieran 1 | trailing `:`/`-`/`_` glue escapes the index (`/ship:`, `/work:`) | mechanical | strip rule; `trailing-punctuation.md`; N5e |
| Kieran 2 | Grok's `Read <path>` form of a known name passes by design | mechanical | declared in §Not gated with the 20/7 count and the pin that requires it |
| Kieran 4 | 561 in **51** docs, not 52 | mechanical | re-measured under v3.1: 1029 / 62 |
| Kieran 7 | per-doc top list did not reproduce | mechanical | numbers from `census4.py`; list = `--report` |
| Kieran 8 | N3 needs `git add`; policy must derive from path | mechanical | done |
| Kieran 10 | case / HTML-entity not-gated rows | mechanical | listed |

**Declined, with reason:** CPO 4 only (above). Everything else is in the plan of record.

## Appendix — the measurement classifier (`census4.py`, produced the 1029 / 62 baseline)

Scratch Python, not shipped; `/work` Phase 1 ports it to TypeScript and must reproduce its output before any doc edit. Region handling here is the loose scratch form; the plan's strict marker grammar supersedes it.

```python
#!/usr/bin/env python3
"""v3.1 predicate: post-panel. Index from discoverAgentPaths() rule (67), trailing-punct strip, R9 path
exclusion, '#' in BOUNDARY, bare agent leaves gated, help.md excluded by path, harness-forms only in commands/."""
import re, subprocess, sys, collections, json
def ls(*pats): return subprocess.check_output(['git','ls-files','--full-name',*pats]).decode().split()
skills=[p.split('/')[-2] for p in ls(':(glob)plugins/soleur/skills/*/SKILL.md')]
cmds=[p.split('/')[-1][:-3] for p in ls(':(glob)plugins/soleur/commands/*.md')]
agent_paths=[p for p in ls('plugins/soleur/agents/**/*.md') if '/references/' not in p and not p.split('/')[-1].startswith('README')]
agents=['soleur:'+p[len('plugins/soleur/agents/'):-3].replace('/',':') for p in agent_paths]
CANON=set('soleur:'+n for n in skills+cmds)|set(agents)
SKILLNAMES=set(skills+cmds); LEAVES=set(a.split(':')[-1] for a in agents)
STEMS=set(a.replace(':','-') for a in agents)
BOUNDARY=set(' \t`"\'([{*<>|,;.=+&?→—–#'); PATHPREV=re.compile(r'[A-Za-z0-9_./]'); TOK=re.compile(r'[A-Za-z0-9_:-]+')
POP=ls(':(glob)plugins/soleur/skills/*/SKILL.md',':(glob)plugins/soleur/commands/*.md',':(glob)plugins/soleur/codex/skills/*/SKILL.md',':(glob)plugins/soleur/devin/skills/*/SKILL.md')
EXCLUDED_BY_PATH={'plugins/soleur/commands/help.md'}
MARK=re.compile(r'^\s*<!-- ([a-z0-9-]+):(start|end) -->\s*$')
def classify(line,m,policy):
    raw=m.group(0); s=m.start(); c=line[s-1] if s>0 else '^'
    t=raw.rstrip(':_-')                     # trailing punctuation glue (Kieran #1); raw kept for R1/R4
    atb=(c=='^' or c in BOUNDARY)
    pathctx=(c=='/' and s>=2 and PATHPREV.match(line[s-2]))
    if raw.startswith('soleur:'):
        if not atb: return 'NONCANONICAL','ns-sigil'
        return ('CANONICAL','') if t in CANON else ('UNKNOWN-NS','')
    if 'soleur:' in raw: return 'NONCANONICAL','agent-mention'
    if t in STEMS: return ('PATH','') if pathctx else ('NONCANONICAL','grok-stem')
    if t in SKILLNAMES:
        if atb: return 'BARE',''
        if pathctx: return 'PATH',''
        return 'NONCANONICAL','sigil-skill'
    if t in LEAVES:
        if pathctx: return 'PATH',''
        return 'NONCANONICAL',('bare-agent-leaf' if atb else 'sigil-agent-leaf')
    if not atb and not pathctx:
        parts=t.split('-')
        for i in range(1,len(parts)):
            suf='-'.join(parts[i:])
            if suf in SKILLNAMES or suf in LEAVES or suf in STEMS: return 'NONCANONICAL','hyphen-absorbed'
    return None,''
per=collections.defaultdict(collections.Counter); shape=collections.Counter(); hits=[]
for p in POP:
    if p in EXCLUDED_BY_PATH: continue
    policy='command' if p.startswith('plugins/soleur/commands/') else 'skill'
    inreg=None
    for ln,line in enumerate(open(p,encoding='utf-8'),1):
        mm=MARK.match(line)
        if mm: inreg=mm.group(1) if mm.group(2)=='start' else None; continue
        for m in TOK.finditer(line):
            v,sh=classify(line,m,policy)
            if v is None: continue
            if inreg=='harness-forms' and policy=='command': v='EXEMPT'
            per[p][v]+=1
            if v=='NONCANONICAL': shape[sh]+=1; hits.append((p,ln,m.group(0),sh,line[m.start()-1] if m.start()>0 else '^'))
tot=collections.Counter()
for p in per: tot.update(per[p])
print('population',len(POP)-len(EXCLUDED_BY_PATH),'(+help.md excluded) | canonical ids',len(CANON),'| agents',len(agents))
print(dict(tot)); print('docs with NONCANONICAL:',sum(1 for p in per if per[p]['NONCANONICAL'])); print('shapes:',dict(shape))
json.dump({'per':{p:dict(per[p]) for p in per},'hits':hits},open(sys.argv[1],'w'),indent=1) if len(sys.argv)>1 else None
```
