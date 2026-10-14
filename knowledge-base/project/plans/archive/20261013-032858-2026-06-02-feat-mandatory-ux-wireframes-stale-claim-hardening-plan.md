---
title: Mandatory UX Wireframes + Stale-Claim Hardening
feature: feat-mandatory-ux-wireframes
date: 2026-06-02
type: feat
status: planned
lane: cross-domain
brand_survival_threshold: none
brainstorm: knowledge-base/project/brainstorms/2026-06-02-mandatory-ux-wireframes-and-stale-claim-hardening-brainstorm.md
spec: knowledge-base/project/specs/feat-mandatory-ux-wireframes/spec.md
related_issues: [4819, 4817]
pr: 4817
plan_review: 5-agent panel applied (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow) 2026-06-02
---

# Plan: Mandatory UX Wireframes + Stale-Claim Hardening ✨

Two coupled hardening changes to the soleur brainstorm/plan/work workflow, bundled in one PR
(#4817) because they edit the same files and both fell out of the same session failure.

- **Feature A — Mandatory UX wireframes.** ux-design-lead `.pen` wireframes become a
  **non-skippable** deliverable for any new/changed UI surface. The design phase may end in
  exactly **two** terminal states: `.pen` committed, or a hard-block with a single actionable
  instruction. "Skipped" is removed as a permitted outcome.
- **Feature B — Stale-claim hardening.** **One** new AGENTS.md hard rule (merged from spec FR7+FR8
  per plan review) forbids asserting unverified limiting/negative claims about repo state — covering
  both the orchestrator's own output AND premises injected into subagent prompts — with a
  **semantic** trigger. Premise-validation phases gain a one-line cross-reference to it.

This plan implements orchestration/docs changes only (SKILL.md bodies, AGENTS.md sidecars,
constitution, one learning, one test). **It discusses UI concepts but ships zero user-facing
runtime UI → Product/UX Gate tier NONE (no recursion).**

## Plan-Review Decisions (5-agent panel, 2026-06-02)

| Finding | Source | Disposition |
|---|---|---|
| deepen-plan "Phase 4.8" already taken (PAT halt at `:445`) | Kieran P0, arch P0-1 | **Fixed** → new halt is **Phase 4.9** |
| Budget add ≈1066 B (not 865); ~350 B trim still REJECTs | Kieran P0 | **Fixed** → merge rules (below) cuts add to ~600 B; trim one tail |
| Merge FR7+FR8 into one hard rule (one rule, two surfaces) | DHH P2-6 | **Adopted** — dissolves budget blast-radius |
| FR8 hedge-word trigger misses confident false claims ("X is GUI-only") | spec-flow P1-1 | **Fixed** → trigger is **semantic**; hedge words = examples only |
| Plan 2.5 gate skipped wholesale when subjective sweep judges Product NONE | spec-flow P0-1 | **Fixed** → mechanical UI-surface override forces Product-relevant+BLOCKING |
| work Check-9 glob `.tsx/.jsx` only; bypassed if no Gate subsection | spec-flow P0-2, arch P1-2 | **Fixed** → widen glob to shared term-list; add no-subsection-fails arm |
| `plan/SKILL.md:302` enforcement clause still lets ux-design-lead be skipped | Kieran P1 | **Fixed** → added to edit sites |
| FR9 redundant w/ brainstorm `:235` + the always-loaded rule; wrong "brainstorm 0.6" cite | code-simplicity, spec-flow | **Fixed** → FR9 = one-line cross-ref; cite brainstorm **1.0.5/1.1** |
| Test file "(optional)" hedge | code-simplicity Q1 | **Fixed** → committed separate file `mandatory-wireframes-hardening.test.ts` |
| 3-row trim table over-specified | code-simplicity Q3, arch P2-1 | **Fixed** → trim observability-tail only (illustrative); GDPR/SSH untouched |
| ACs LARP ("producer language present") | DHH P2 | **Fixed** → concrete greps + exit codes |
| bunfig 72h `minimumReleaseAge` blocks npm auto-install | arch P2-2 | **Dropped** — bun-only; `check_deps.sh` uses system `npm` |
| Cut FR4 (deepen-plan halt) as 4th redundant layer | DHH P0-1 | **Kept (operator's brainstorm decision = 4-layer DiD)**; arch P2-3 confirms it's the live verifier on the one-shot path, not dead weight. DHH dissent recorded. |
| Cut FR5 (new term-list file), inline instead | DHH P1-3 | **Kept + strengthened** — spec-flow P2-1 shows 3 layers currently use 3 different UI globs; the file is the single source of truth all 4 layers cite. DHH dissent recorded. |

## Resolved Open Questions (from brainstorm/spec)

1. **`PENCIL_CLI_KEY` config (OQ#1):** Verified present in Doppler `soleur/dev` (the config
   `pencil-setup/SKILL.md:108` reads); absent in `prd`. Auto-install→auth succeeds today, so the
   hard-block stays dormant. **Decision: keep dev-only, no provisioning task** (operator-confirmed).
2. **AGENTS loader-class fit (OQ#2):** The merged stale-claim rule is `hr-*` → MUST live in
   `AGENTS.core.md` (residency invariant, `lint-rule-ids.py:366`). The wireframe `wg-*` must fire
   when plan/spec/brainstorm `.md` files are authored = **docs-only** class → body in
   `AGENTS.docs.md` (off the always-loaded `B_ALWAYS` budget; `lint-rule-ids.py` imposes no
   prefix→class restriction, so a `wg-*` in docs-only is allowed). **Decision: wg-* → docs-only**
   (operator-confirmed). The docs-only gate does NOT load on a code-only `/work` session — the
   `work/SKILL.md` Check-9 edit is the code-class backstop (see Phase 2).
3. **Empirical headless authoring (OQ#3):** Not a plan blocker — **/work Phase 0** precondition.
   Failure surfaces but does NOT block Phases 1-5 (pure docs/test).
4. **Hedge-word false positives (OQ#4):** Scoped to claims about *this repo's* artifacts only
   (NG4); hedge words are non-exhaustive examples, not the matcher. The trigger is semantic.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Constitution at `knowledge-base/overview/constitution.md` (per CC memory index) | File is `knowledge-base/project/constitution.md`; lines **147** + **177** confirmed | Cite `project/constitution.md`; FR6 edits line 177 there |
| "9 distinct skip sites (3 brainstorm + 6 plan)" | brainstorm `:406/419/421`; plan `:302/321/324/326-331/358/359`; **also** work `:102/104` | Scope includes `plan:302` + `work/SKILL.md` Check-9 (superset, not just 9) |
| TR2: respect the "1800-word description cap" | Budget is **1984 words** (`components.test.ts:15`) AND applies to `description:` *frontmatter* — this feature edits **bodies** → cap **N/A** | Real budget risk is **AGENTS `B_ALWAYS`** (next row) |
| FR6: "promote line 177 to a new immutable `wg-*` ID" | Retired id `wg-for-user-facing-pages-with-a-product-ux` is in `retired-rule-ids.txt:96`; reintroduction-guard (`lint-rule-ids.py:113`) rejects reuse | Use fresh slug `wg-ui-feature-requires-pen-wireframe` |
| Auto-install ("pencil-setup can't auto-install" — the false premise) | **FALSE.** `check_deps.sh:419` `attempt_headless_install()` runs `npm install --prefix ~/.local @pencil.dev/cli` (system npm, not bun); auth at `:402`; Node-22 via `find_node22` | Feature A's "auto-install then block" is real; this false premise is Feature B's motivating incident (FR10) |
| AGENTS `B_ALWAYS` has room for new rules | **22458/23000 — 542 B left**; one merged hr body (~480 B) + 2 index pointers (~120 B) ≈ **600 B add** | Trim observability-citation tail (~250 B) → `B_ALWAYS ≈ 22808 < 23000` |
| deepen-plan halt slot "4.8" | **4.8 is taken** (PAT-Shaped Variable Halt, `deepen-plan/SKILL.md:445`); 4.6=`:350`, 4.7=`:395` | New wireframe halt = **Phase 4.9** |
| brainstorm premise phases at "0.6 + 1.1" | brainstorm has **no 0.6/1.0.5** heading; the premise-verification block is at `SKILL.md:235` under "### Phase 1: Understand the Idea" and already covers "your own reasoning". plan's is `### 0.6` at `:101` | FR9 = one-line cross-ref at brainstorm `:235` + plan `0.6` |

## Open Code-Review Overlap

2 open scope-outs touch files this plan edits — both **Acknowledged** (different concern, no fold-in):

- **#4133** (Observability schema-parity test) — touches `plan/SKILL.md`, `deepen-plan/SKILL.md`,
  `AGENTS.core.md`. We edit the wireframe/premise sections, not the observability block.
- **#2348** (vitest mock-factory drift) — touches `constitution.md`. We only edit line 177.

## User-Brand Impact

**If this lands broken, the user experiences:** a UI feature that ships with no wireframe (silent
skip persists) — or a brainstorm/plan that hard-blocks and dead-ends a non-technical user when
`PENCIL_CLI_KEY` is missing. Mitigated: key verified present in `soleur/dev`; auto-install runs
first; block fires only on genuine auth/Node failure, with an actionable single-instruction
message (Phase 2, specified).

**If this leaks, the user's data is exposed via:** N/A — no user data, PII, or runtime credential
surface. `PENCIL_CLI_KEY` is read-only from Doppler, never committed.

**Brand-survival threshold:** none, reason: pure orchestration/docs change (SKILL.md + AGENTS.md
sidecars + constitution + one learning + one test); no sensitive runtime path
(schemas/migrations/auth/API/`.sql` untouched), so preflight Check 6's sensitive-path arm does not fire.

## Domain Review

**Domains relevant:** Engineering (CTO — assessed in brainstorm, carried forward), Product
(operator-decided).

### Engineering (CTO) — carried forward from brainstorm

**Status:** reviewed (brainstorm `## Domain Assessments`)
**Assessment:** Feasible, medium complexity. Headless auto-install is real; the only block is
`PENCIL_CLI_KEY` or Node < 22.9.0, so "auto-install then block" does not degrade to "always
block." Gate asserts **artifact-on-disk**, not "specialist ran." Enforced across brainstorm
(producer) + plan 2.5 (producer+verifier, sole producer on the one-shot path) + deepen-plan halt
+ AGENTS `wg-*`. The first CTO pass carried the false "Pencil is GUI-only" premise and
self-corrected — the direct motivation for Feature B.

### Product/UX Gate

**Tier:** none
**Decision:** N/A — plan *discusses* UI concepts but *implements* orchestration/docs changes. Per
`plan/SKILL.md:312`, tier NONE. No ux-design-lead / spec-flow / CPO recursion (the plan that
mandates wireframes does not itself ship a UI surface).

## Infrastructure (IaC)

**None.** No new server, secret, vendor, cron, DNS, or process. `PENCIL_CLI_KEY` pre-exists in
`soleur/dev`, kept as-is. Phase 2.8 gate: skip.

## Observability

**N/A (pure-docs/test).** Files-to-Edit touch `plugins/soleur/skills/**/SKILL.md`, `AGENTS.*.md`,
`constitution.md`, one learning, and `plugins/soleur/test/*.test.ts` — none under the Phase 2.9
trigger globs (`apps/*/server`, `apps/*/src`, `apps/*/infra`, `plugins/*/scripts`); no runtime
surface. Gate: skip. *(The feature's own observability is the brainstorm/plan/deepen halts +
`emit_incident` rule-fire telemetry — Phases 2-4.)*

## GDPR / Compliance Gate

**Skip.** No regulated-data surface; none of the (a)-(d) expansion triggers fire.

## Implementation Phases

> Phase order is load-bearing: budget trim + the merged hard rule (Phase 1) land before the rule
> is referenced; tests are RED-first per `cq-write-failing-tests-before`.

### Phase 0 — /work preconditions (no commits)

- P0.1 `cd` into the worktree; confirm branch `feat-mandatory-ux-wireframes`; never read the bare
  repo (`hr-when-in-a-worktree-never-read-from-bare`).
- P0.2 **Re-measure `B_ALWAYS`**: `echo $(( $(wc -c < AGENTS.md) + $(wc -c < AGENTS.core.md) ))`
  + `python3 scripts/lint-agents-rule-budget.py` (plan baseline 22458).
- P0.3 **Empirical headless authoring (OQ#3)**: `bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --auto`,
  then confirm `mcp__pencil__*` resolves and a trivial `batch_design`+`save` yields a non-zero-byte
  `.pen`. **Surfaces but does NOT block** Phases 1-5 (those are pure docs/test) — a failure is an
  environment finding to report, plus existing tests (`pencil-save-gate.test.ts`,
  `pencil-adapter-auth-hard-fail.test.sh`) already cover the install/auth/save path.
- P0.4 Confirm key present: `doppler secrets --project soleur --config dev --only-names | grep -i pencil` (names only).

### Phase 1 — Feature B: one merged hard rule + premise cross-ref + budget trim (FR7+FR8, FR9, TR1, TR2)

**1a. Budget trim (must precede adding the rule; same commit).** Free ~250 B from `AGENTS.core.md`
so `B_ALWAYS` lands < 23000 with margin after the ~600 B add. **Illustrative** safest target
(verified: enforcement is keyed by rule ID in the hook/skill, not by body text, so trimming the
body tail cannot break a citation):

- `hr-observability-layer-citation` (core, ~504 B): drop the five-layer enumeration tail — it is
  duplicated verbatim at `agents/engineering/review/observability-coverage-reviewer.md:15-17`.
  Keep the citation requirement. (~250-300 B freed.)

Leave `hr-no-ssh-fallback-in-runbooks` and `hr-gdpr-gate` **untouched** (GDPR carries the
single-user regulatory rationale; do not weaken in-context). Re-run `lint-agents-rule-budget.py`
after; target `B_ALWAYS ≤ ~22800`. No `hr-*` demotion; no retire without `retired-rule-ids.txt`.

**1b. One new hard rule** in `AGENTS.core.md` (+ index pointer in `AGENTS.md` `## Hard Rules`, `→ core`):

- `[id: hr-verify-repo-capability-claim-before-assert]`: Before asserting — **in your own output OR
  in a subagent prompt** — a limiting/negative claim about *this repo's* tools/scripts/skills/flags
  ("X is GUI-only", "Y doesn't exist", "Z only does W"), grep/read the source to verify, OR phrase
  it as a question for the agent to verify. **Trigger is semantic**: any asserted limiting/negative
  capability claim about a repo artifact — hedge words (`only/doesn't/can't/no longer/to my
  knowledge/I believe/likely`) are non-exhaustive examples, not the matcher; a confident false
  claim ("Pencil is GUI-only") with no hedge word still trips it. Scope: this-repo artifacts, not
  general facts (NG4). **Why:** #4819; the "Pencil is GUI-only" CTO-prompt incident; generalizes
  paraphrase-without-verification to the orchestrator's own claims.

  Verify slug passes `^(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]{3,60}$`, not in `retired-rule-ids.txt`, body
  ≤ 600 B.

**1c. Premise-phase cross-reference (FR9, one line each — do not restate logic):** add to the
brainstorm premise-verification block at `SKILL.md:235` (under "### Phase 1: Understand the Idea",
which already covers "your own reasoning") and to plan **Phase 0.6** (`SKILL.md:101`):
"…this also applies to your own option-bounding capability claims — see
`hr-verify-repo-capability-claim-before-assert`." (No third copy of verify-or-ask prose.)

### Phase 2 — Feature A: close skip outcomes across brainstorm + plan + work (FR1, FR2, FR3)

**2a. brainstorm Phase 3.55 (`SKILL.md:404-421`):** keep `:406` UI-detection as the **trigger**
(no-UI → genuine skip is correct). Replace `:419` (HEADLESS skip) and `:421` (Pencil-unavailable
skip) with the **auto-install-then-block** sequence: detect `mcp__pencil__*` → if absent run
`pencil-setup --auto` (sources `PENCIL_CLI_KEY` from `dev`) → re-check → author `.pen` on success;
**hard-block** with ONE instruction only if auth/Node ≥ 22.9.0 unsatisfiable. Remove the
`Phase 3.55: skipped (...)` echo strings. Cite the shared term-list (Phase 3).

**2b. plan Phase 2.5 — mechanical UI override (spec-flow P0-1, the critical fix):** at the **top of
Step 1** (before the subjective Product-relevance sweep can return NONE), add a mechanical
override: if Files-to-Create/Edit match the shared UI-surface term-list **or** the glob superset
(`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, `*.njk/*.html/*.vue/*.svelte/*.astro`,
email templates), **force Product-relevant + tier=BLOCKING** regardless of the sweep. This closes
the "subjective sweep judged NONE → gate skipped wholesale" third silent state on the
one-shot/direct-plan paths.

**2c. plan Phase 2.5 — close the skip branches:**
- `:302` enforcement clause: exclude `ux-design-lead` from the "Skip with acknowledgment" specialist
  set for a UI feature.
- `:321`: remove "agent self-stopped → add `ux-design-lead` to **Skipped specialists:** and
  proceed." Replace with: run `pencil-setup --auto`, re-invoke; on genuine failure **hard-block**
  (no skip record). On the **one-shot/pipeline path** Phase 2.5 is the *sole producer* — it must
  *generate* the `.pen`.
- `:324` step 7: remove option (b) "Skip with acknowledgment" **for ux-design-lead specifically**
  (other specialists keep it). Reconcile with `:321` so a ux-design-lead failure is never offered
  (b) downstream (spec-flow P2-3).
- `:358-359` Heading Contract: `ux-design-lead` may never appear in `Skipped specialists:` for a UI
  feature; assert `Pencil available: yes` or a hard-block record.
- **Verifier asserts the invariant:** `.pen` exists on disk, non-empty, under
  `knowledge-base/product/design/{domain}/`, referenced in the spec FRs — not "specialist done."

**2d. work Check-9 (`SKILL.md:102/104`) — code-class backstop (spec-flow P0-2, arch P1-2):**
- **Widen the glob** from `.tsx/.jsx` to the shared term-list superset (include
  `.njk/.html/.vue/.svelte/.astro` + email templates) so it matches the producers' UI definition.
- **Add an arm:** a plan whose Files match the UI superset but has **no `### Product/UX Gate`
  subsection at all** → FAIL (not only the recorded-skip case). Require a committed `.pen` reference
  or a hard-block record.

### Phase 3 — Shared UI-surface term-list (FR5) consumed by all four layers

Create `plugins/soleur/skills/brainstorm/references/ui-surface-terms.md` (single source of truth:
new/modified pages, components, modals, banners, nav/layout, flows; excludes pure copy/style and
backend-only). **Cite it from all four layers** — brainstorm 3.55, plan 2.5 (override + escalation),
deepen-plan 4.9, work Check-9 — so every layer agrees on "what is UI" (fixes spec-flow P2-1's
three-divergent-globs bug). Plan keeps its mechanical glob escalation as a superset.

### Phase 4 — deepen-plan Phase 4.9 halt (FR4) + constitution/`wg-*` promotion (FR6)

- **deepen-plan `### 4.9. UI-Wireframe Artifact Halt`** (AFTER the existing 4.8 PAT halt at `:445`),
  mirroring 4.6/4.7: when the plan's Files indicate a UI surface (shared term-list / glob superset),
  grep the plan body for a committed `.pen` reference (`knowledge-base/product/design/**/*.pen`,
  `git ls-files`-verifiable). If absent → **HALT** +
  `emit_incident wg-ui-feature-requires-pen-wireframe applied "<60-char>"`. Skip for non-UI plans.
  (Live verifier on the one-shot path: `one-shot/SKILL.md:66-78` chains plan→deepen-plan, arch P2-3.)
- **`wg-ui-feature-requires-pen-wireframe`** body in `AGENTS.docs.md` + index pointer in `AGENTS.md`
  `## Workflow Gates` (`→ docs-only`). Body: a UI-surface feature must end its design phase with a
  committed `.pen` or a hard-block — never a skip; `[skill-enforced: brainstorm 3.55 + plan 2.5 +
  deepen-plan 4.9]`. **Why:** #4819; re-activates the demoted constitution line 177 gate.
- Annotate `constitution.md:177` noting the principle is now a live gate
  (`→ wg-ui-feature-requires-pen-wireframe`), keeping the retired `ex-wg-...` text immutable.

### Phase 5 — Tests (TR4, RED-first) + learning (FR10)

- **RED first**, new file `plugins/soleur/test/mandatory-wireframes-hardening.test.ts` (separate
  from metadata-only `components.test.ts`), failing on current `main`:
  - `grep -c 'Phase 3.55: skipped' brainstorm/SKILL.md` → **0**.
  - plan SKILL.md: the `:321` self-stop "add ux-design-lead to Skipped specialists" phrase absent;
    the hard-block phrase present; the mechanical-override phrase present.
  - `AGENTS.md` + `AGENTS.core.md` contain `hr-verify-repo-capability-claim-before-assert`;
    `AGENTS.docs.md` + `AGENTS.md` contain `wg-ui-feature-requires-pen-wireframe`.
  - deepen-plan SKILL.md contains `### 4.9. UI-Wireframe Artifact Halt` (and still exactly one
    `### 4.8.`).
- Make GREEN via Phases 1-4. Run lints as ACs: `python3 scripts/lint-rule-ids.py` (exit 0),
  `python3 scripts/lint-agents-rule-budget.py` (exit 0, `B_ALWAYS < 23000`).
- **Learning** (FR10): `knowledge-base/project/learnings/bug-fixes/<topic>.md` (author dates at
  write-time — no hardcoded filename). Capture the false "pencil-setup can't auto-install" /
  "Pencil is GUI-only" premise, its injection into a CTO subagent prompt, how `check_deps.sh:419`
  falsifies it, and the merged hard rule it produced. Link
  `[[2026-04-19-ux-design-lead-headless-stub-fabrication]]` and
  `[[2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification]]`.

## Files to Edit

- `AGENTS.md` — 2 new index pointers (1 `→ core` hard rule, 1 `→ docs-only` wg-*); trim if needed.
- `AGENTS.core.md` — +1 merged hard-rule body; trim observability-citation tail (~250 B).
- `AGENTS.docs.md` — +1 `wg-ui-feature-requires-pen-wireframe` body.
- `plugins/soleur/skills/brainstorm/SKILL.md` — Phase 3.55 rewrite (FR1/FR3); 1.0.5/1.1 cross-ref (FR9); cite term-list.
- `plugins/soleur/skills/plan/SKILL.md` — Phase 2.5 mechanical override + skip closures at `:302/321/324/358/359` (FR2); Phase 0.6 cross-ref (FR9); cite term-list.
- `plugins/soleur/skills/work/SKILL.md` — Check-9 `:102/104` glob widen + no-subsection arm (FR2); cite term-list.
- `plugins/soleur/skills/deepen-plan/SKILL.md` — new Phase **4.9** wireframe halt (FR4).
- `knowledge-base/project/constitution.md` — annotate line 177 as promoted (FR6).

## Files to Create

- `plugins/soleur/skills/brainstorm/references/ui-surface-terms.md` — shared UI-surface term list (FR5).
- `plugins/soleur/test/mandatory-wireframes-hardening.test.ts` — skip-clause + rule-presence + 4.9 assertions (TR4).
- `knowledge-base/project/learnings/bug-fixes/<topic>.md` — false-claim incident learning (FR10).

## Acceptance Criteria

### Pre-merge (PR)

- AC1. `grep -c 'Phase 3.55: skipped' plugins/soleur/skills/brainstorm/SKILL.md` returns **0**;
  documented Phase-3.55 outcomes for a UI feature are `.pen committed` or `hard-block` only.
- AC2. plan SKILL.md: `grep -c 'add `ux-design-lead` to .*Skipped specialists' ` at the `:321`
  self-stop branch returns **0**; the mechanical-override phrase and the one-shot "sole producer …
  generate" phrase are present (each `grep -c ≥ 1`). work Check-9: a synthetic UI plan (UI-superset
  files) with **no `### Product/UX Gate` subsection** fails the gate (exit ≠ 0 from the Check-9
  harness).
- AC3. `grep -l hr-verify-repo-capability-claim-before-assert AGENTS.md AGENTS.core.md` returns both;
  `grep -l wg-ui-feature-requires-pen-wireframe AGENTS.md AGENTS.docs.md` returns both;
  `python3 scripts/lint-rule-ids.py` exits 0.
- AC4. `python3 scripts/lint-agents-rule-budget.py` exits 0 with `B_ALWAYS < 23000` (target ≤ ~22800).
- AC5. deepen-plan: exactly one `### 4.8.` and one `### 4.9.` (`grep -c` each = 1). Phase 4.9 HALTs
  on a synthetic UI plan with no `.pen` reference (RED fixture) and passes one with a
  `git ls-files`-verifiable `.pen` (GREEN fixture) — both fixtures committed, asserted by exit code.
- AC6. Learning file exists under `knowledge-base/project/learnings/bug-fixes/` linking the two
  related learnings.
- AC7. `cd <worktree> && bun test plugins/soleur/test/mandatory-wireframes-hardening.test.ts` and
  `... components.test.ts` green (run from inside the worktree — `bunfig.toml` ignores `.worktrees/**`).

### Post-merge (operator)

- None. Pure docs/orchestration change; `PENCIL_CLI_KEY` already in `soleur/dev`.

## Test Scenarios

- Brainstorm UI feature, Pencil absent, key present → `--auto` installs → `.pen` authored (no skip).
- Brainstorm UI feature, key absent + Node < 22.9.0 → single actionable hard-block message
  (names the concrete action, e.g. "Node 22.9+ required — this is an environment limit; escalate to
  your operator"), no `.pen`, no "skipped".
- **one-shot UI feature whose subjective sweep would judge Product NONE** → mechanical override
  forces BLOCKING → plan Phase 2.5 generates the `.pen` (spec-flow P0-1 regression test).
- **UI feature shipping only a `.njk` / email template** (no `.tsx`) via `/work` → Check-9 fails it
  (spec-flow P0-2 regression test).
- deepen-plan on a UI plan missing a `.pen` reference → HALT + telemetry; with a committed `.pen` → pass.
- Orchestrator about to assert "X is GUI-only" (no hedge word) about a repo artifact → semantic
  trigger requires a grep first (encoded in the learning example).

## Sharp Edges

- **Phase 4.8 is already taken** (PAT-Shaped Variable Halt, `deepen-plan/SKILL.md:445`). The
  wireframe halt is **4.9**. Assert exactly one `### 4.8.` survives.
- **Do not reuse the retired id** `wg-for-user-facing-pages-with-a-product-ux` (in
  `retired-rule-ids.txt`); use `wg-ui-feature-requires-pen-wireframe`.
- **FR8's trigger is semantic, not a word-list.** A confident false claim ("Pencil is GUI-only")
  has no hedge word — the rule must still fire. Hedge words are examples only.
- **The mechanical UI override (Phase 2b) is load-bearing.** Without it, a UI feature whose
  subjective Product sweep returns NONE skips the gate entirely — the third silent state.
- **work Check-9 glob must equal the producers' UI definition.** A `.tsx`-only glob lets `.njk`/
  email-template UI surfaces slip the code-class backstop.
- **`B_ALWAYS` is at-cap** (542 B headroom). Adding the rule WITHOUT trimming first breaks
  `lint-agents-rule-budget.py` at GREEN. Trim observability-tail (~250 B) first; re-measure.
- **wg-* in docs-only is intentional** — fires on plan/spec/brainstorm `.md` authoring (where the
  gate operates). The `/work` code-class backstop is Check-9 (Phase 2d), which does NOT depend on
  the sidecar class.
- **Verifier asserts the artifact, not the proxy** (`.pen` on disk + spec reference, never
  "specialist reported done").
- **Constitution path is `knowledge-base/project/constitution.md`** — not `overview/` (CC memory stale).
- **Run tests from inside the worktree** (`bunfig.toml` `pathIgnorePatterns` excludes `.worktrees/**`).
- **Learning filename: directory + topic only** in `tasks.md`; author dates it at write-time.
- A plan whose `## User-Brand Impact` section is empty/placeholder fails `deepen-plan` Phase 4.6.
  (This plan's is filled.)

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Non-Pencil (Markdown/ASCII) wireframe fallback | Headless `.pen` works; a fallback re-introduces split-pipeline + silent-skip (NG1) |
| Two separate stale-claim rules (spec FR7 + FR8) | Same remedy on two surfaces; merging to one rule saves ~510 B and dissolves the at-cap budget surgery (DHH P2-6; both surfaces kept via two clauses) |
| Wireframe `wg-*` in `AGENTS.core.md` (both-class coverage) | ~350 extra always-loaded bytes → larger trim; gate operates at plan/brainstorm (docs) time; Check-9 is the code-class backstop (operator-confirmed docs-only) |
| Cut FR4 deepen-plan halt (DHH) | Operator chose 4-layer defense-in-depth; arch confirms 4.9 is the live verifier on the one-shot path, not dead weight |
| Inline FR5 term-list instead of a file (DHH) | 4 layers currently use 3 different UI globs (spec-flow P2-1); a single SoT file is the fix |
| Reuse retired `wg-for-user-facing-pages...` id | reintroduction guard rejects it |
| Provision `PENCIL_CLI_KEY` to `prd` | Key already in `dev` (the config the skill reads); prd mirror dormant (operator-confirmed keep dev-only) |
