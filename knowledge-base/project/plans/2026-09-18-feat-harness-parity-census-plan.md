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
