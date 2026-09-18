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

## Guard Contract

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
