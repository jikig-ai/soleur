---
title: Pause for Operator Feedback on UX Wireframes After Screenshot Review
feature: feat-one-shot-pause-wireframe-feedback
date: 2026-06-16
type: feat
status: planned
lane: cross-domain
brand_survival_threshold: none
spec: knowledge-base/project/specs/feat-one-shot-pause-wireframe-feedback/spec.md
plan_review: pending
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan edits only SKILL.md / agent-body / test prose. It introduces no
     server, systemd service, cron, vendor account, DNS record, TLS cert, secret, firewall rule,
     or persistent runtime process. No IaC routing applies. The "operator"/"manual" tokens the
     scanner matched are about interactive-vs-headless workflow ergonomics, not infra provisioning. -->

# Plan: Pause for Operator Feedback on UX Wireframes ✨

After `ux-design-lead` generates wireframe screenshots and opens the screenshots folder
(`xdg-open`) for review, the **interactive** workflow should PAUSE via `AskUserQuestion`
so the operator can review the wireframes and either **approve** (continue) or **request
changes** (re-invoke `ux-design-lead` with the feedback). In **headless/pipeline** mode the
gate auto-proceeds and logs — it never pauses.

This is an **orchestration/docs-only** change: SKILL.md prose in `brainstorm` (Phase 3.55)
and `plan` (Phase 2.5) plus one agent-body cross-reference and one test. It **discusses UI
but ships zero user-facing runtime UI → Product/UX Gate tier NONE** (no recursion into the
wireframe workflow it documents).

## Overview

### The gap

`ux-design-lead.md:83` (Step 3 item 5) runs `xdg-open <screenshots-directory>` and says "the
founder must visually review wireframes before proceeding." But this happens **inside the
ux-design-lead subagent**, which structurally cannot pause for operator `AskUserQuestion`
input (`2026-05-12-task-subagent-prompt-text-only.md`: Task subagents inherit prompt text
only; they have no operator-interaction channel and return control to the orchestrator when
done). So today: the subagent opens the folder, says "review this," then immediately returns,
and the orchestrator (`brainstorm` Phase 3.55 / `plan` Phase 2.5) barrels straight into the
next phase (spec creation / Domain Review write) with **no actual pause and no feedback loop**.

### The fix

The pause must live in the **orchestrator**, right after the ux-design-lead subagent returns
(the subagent keeps the `xdg-open` so the folder is already open when control comes back). This
is the established **Phase N.5 defense-in-depth gate** pattern (`2026-03-27-skill-defense-in-depth-gate-pattern.md`):
always runs, branches on headless/interactive mode, includes a `**Why:**` rationale.

- **Interactive mode** (operator present): `AskUserQuestion` — "Wireframes are open for review at
  `<dir>`. Approve and continue, or request changes?" Options: **Approve** (proceed) /
  **Request changes** (collect a free-text note, re-invoke `ux-design-lead` with the feedback,
  re-open, re-ask — loop until approved). This is the operator-in-the-loop checkpoint the feature
  asks for, in a session where the human is at the keyboard.
- **Headless/pipeline mode** (`one-shot`, `--headless`, no TTY): **do NOT pause.** Echo a
  `wireframes ready for async review: <dir>` line to the operator terminal and continue. This
  honors `one-shot/SKILL.md:11` ("no per-phase approval gates after Step 0a.5") and the
  mid-plan-pause anti-pattern (`2026-05-12-mid-plan-pause-gates-and-operator-step-pushback.md`).

### Why this is NOT the mid-pipeline-pause anti-pattern

The learnings warn against (a) pausing *mid-`/work` implementation* between committed phases and
(b) pseudo-handoff summary blocks that stall *autonomous* runs. This gate is neither: it fires
**only in interactive sessions**, at a natural human-review boundary (wireframes are a visual
artifact the operator must eyeball — code is regenerable, wireframes are not, per
`2026-03-29-ux-gate-commit-checkpoints.md`), and it is **suppressed entirely in headless mode**.
The mode branch is the whole point.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| "the workflow opens the screenshots folder" | `xdg-open` is at `ux-design-lead.md:83`, inside the **subagent**, not the orchestrator | Pause goes in the **orchestrator** after the subagent returns; subagent keeps `xdg-open` |
| "pause the workflow to request feedback" (implies all paths) | `one-shot` is explicitly autonomous, "no per-phase approval gates" (`one-shot/SKILL.md:11`); learnings forbid mid-pipeline pauses in headless runs | Gate is **mode-conditional**: pause interactive, auto-proceed headless |
| Add a new workflow-gate rule for this | `B_ALWAYS = 22994/23000` bytes — 6 bytes headroom; a new `AGENTS.md` pointer (~50-60 B) cannot land without a demotion (`2026-06-15-agents-budget-at-cap-descopes-planned-rule...`) | **No new rule.** Extend existing `wg-ui-feature-requires-pen-wireframe` enforcement via SKILL.md prose only |
| One generic "the workflow" producer | Three orchestrators invoke ux-design-lead in the wireframe-creation path: `brainstorm` 3.55, `plan` 2.5; `work` Phase 246 invokes it for an *implementation brief* (no new wireframes), and `ux-audit` invokes it in `mode: audit` | Pause added to the **two wireframe-creation orchestrators** (brainstorm 3.55, plan 2.5); `work` brief + `ux-audit` are out of scope (no new screenshots generated) |

## User-Brand Impact

**If this lands broken, the user experiences:** an interactive brainstorm/plan session that
either (a) never pauses (no behavior change — same as today, a silent no-op) or (b) pauses in
headless one-shot and hangs the autonomous pipeline. The headless-suppression branch (FR3) is
the load-bearing guard against (b).

**If this leaks, the user's data is exposed via:** N/A — no data surface. This edits SKILL.md
prose and an agent body; it touches no schema, auth, API, secret, or user data.

**Brand-survival threshold:** none — a workflow-ergonomics change to interactive design review.
No sensitive path is touched (the diff is `plugins/soleur/skills/*/SKILL.md`,
`plugins/soleur/agents/**/*.md`, `plugins/soleur/test/*.test.ts`).
threshold: none, reason: orchestration/docs-only change with no runtime, data, or infra surface.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — interactive pause exists (brainstorm).** `brainstorm/SKILL.md` Phase 3.55, in the
  "After the agent completes" block, contains an interactive `AskUserQuestion` review gate with
  **Approve** and **Request changes** options. Verify:
  `grep -nA2 'After the agent completes' plugins/soleur/skills/brainstorm/SKILL.md | grep -qiE 'AskUserQuestion.*(approve|request changes)|review gate'` → exit 0.
- [ ] **AC2 — interactive pause exists (plan).** `plan/SKILL.md` Phase 2.5, after the ux-design-lead
  step-4 invocation, contains the same interactive `AskUserQuestion` review gate. Verify a
  `grep -niE 'wireframe.*(approve|request changes)|AskUserQuestion.*wireframe' plugins/soleur/skills/plan/SKILL.md`
  returns ≥1 line.
- [ ] **AC3 — headless suppression is explicit in BOTH skills.** Each gate's prose names the
  headless/pipeline branch and says it does NOT pause. Verify both files:
  `grep -niE 'headless|pipeline|no TTY' <file>` within the new gate block returns a "do not pause /
  auto-proceed / continue" arm. (Manual read confirms the branch is co-located with the gate, not
  elsewhere in the file.)
- [ ] **AC4 — request-changes loop re-invokes the producer.** The "Request changes" arm prose
  explicitly re-invokes `ux-design-lead` with the operator's feedback note and loops until approve.
  Verify: `grep -niE 're-?invoke.*ux-design-lead|loop until approv' <file>` in both gate blocks.
- [ ] **AC5 — subagent keeps xdg-open; agent body cross-references the orchestrator pause.**
  `ux-design-lead.md:83` retains `xdg-open`; item 5 (or item 6) gains a one-sentence note that the
  *orchestrator* (brainstorm 3.55 / plan 2.5) is where the interactive review pause lives, since the
  subagent cannot pause. Verify: `grep -niE 'orchestrator|brainstorm.*3.55|plan.*Phase 2.5' plugins/soleur/agents/product/design/ux-design-lead.md` → exit 0, AND `grep -c 'xdg-open' plugins/soleur/agents/product/design/ux-design-lead.md` ≥ 1.
- [ ] **AC6 — no new AGENTS.md rule was added.** `B_ALWAYS` unchanged: `git diff --stat origin/main -- AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` shows no rule-pointer additions (the change reuses `wg-ui-feature-requires-pen-wireframe`). If any sidecar is touched, `python3 scripts/lint-agents-rule-budget.py` passes.
- [ ] **AC7 — test asserts the end-state.** New tests in
  `plugins/soleur/test/wireframe-feedback-pause.test.ts` assert AC1–AC5 (grep-shaped, reading the
  SKILL.md / agent files). They FAIL on pre-feature `origin/main` (RED) and PASS on the branch.
  Verify: `cd plugins/soleur && bash scripts/test-all.sh` (the runner from `package.json` `scripts.test`) is green.
- [ ] **AC8 — skill description budget unaffected.** No `description:` frontmatter changed; if any did,
  `bun test plugins/soleur/test/components.test.ts` passes (< 1800 words).

### Post-merge (operator)

- None. Pure docs/prose change; the `web-platform-release.yml` path filter does not fire (no
  `apps/web-platform/**` edits); no migration, no infra, no deploy. Automation feasibility: N/A.

## Implementation Phases

### Phase 1 — RED: write the failing test

1. Create `plugins/soleur/test/wireframe-feedback-pause.test.ts` (mirror the structure of
   `plugins/soleur/test/mandatory-wireframes-hardening.test.ts`: `bun:test`, `readFileSync`,
   `REPO_ROOT = resolve(import.meta.dir, "../../..")`). Assertions:
   - brainstorm Phase 3.55 "After the agent completes" block contains the interactive review gate
     (AskUserQuestion + approve/request-changes) — AC1.
   - plan Phase 2.5 contains the same gate after the step-4 invocation — AC2.
   - both gates name a headless/pipeline no-pause branch — AC3.
   - both gates' request-changes arm re-invokes ux-design-lead and loops — AC4.
   - ux-design-lead body still has `xdg-open` AND cross-references the orchestrator pause — AC5.
   - the retired/absent state: assert the *current* main does NOT already contain the gate (so the
     test is a real RED, not vacuous).
2. Run the suite, confirm the new tests FAIL on the unmodified prose (RED).

### Phase 2 — GREEN: brainstorm Phase 3.55 gate

Edit `plugins/soleur/skills/brainstorm/SKILL.md` Phase 3.55, immediately after line 411
("After the agent completes …"). Insert a new sub-block **Phase 3.55b — Wireframe review pause**:

- **Interactive arm:** `AskUserQuestion`: "Wireframes are open for review at `<screenshots-dir>`
  (the design agent ran `xdg-open`). Approve to continue, or request changes?" Options:
  **Approve** → proceed to Phase 3.6. **Request changes** → collect a free-text note, re-invoke
  `ux-design-lead` (Agent tool) with `feedback: <note>` + the existing `.pen` path, re-open the
  folder, re-ask. Loop until Approve.
- **Headless arm:** detect via the existing pattern (`HEADLESS_MODE=true`, no TTY,
  `/soleur:one-shot`, `/soleur:go --headless` — same predicate as Phase 0.4 at brainstorm:101).
  Do NOT pause. Echo `Phase 3.55b: pipeline mode — wireframes ready for async review at <dir>` and
  continue.
- One-line `**Why:**` citing `2026-03-27-skill-defense-in-depth-gate-pattern.md` (Phase N.5
  mode-branch) and `2026-05-12-mid-plan-pause-gates-and-operator-step-pushback.md` (headless
  no-pause). Keep ≤ ~120 words of prose.

### Phase 3 — GREEN: plan Phase 2.5 gate

Edit `plugins/soleur/skills/plan/SKILL.md` Phase 2.5, immediately after step 4 (the ux-design-lead
invocation at `:327`). Insert **step 4b — Wireframe review pause** with the same two-arm structure:

- **Interactive arm:** same AskUserQuestion approve / request-changes loop; on approve continue to
  step 5 (Content Review Gate); on request-changes re-invoke ux-design-lead with feedback, re-ask.
- **Headless/pipeline arm:** plan Phase 2.5 already auto-accepts in pipeline context (e.g., ADVISORY
  auto-accept at `:340`). Mirror that: when the plan was invoked as a subagent / file-path argument
  / `--headless`, do NOT pause — record `wireframes ready for async review at <dir>` and continue.
  **Load-bearing:** the one-shot path chains plan inside a Task subagent (`one-shot/SKILL.md:70`),
  which is itself non-interactive — the headless arm MUST fire there or the autonomous pipeline
  hangs.
- One-line `**Why:**` cross-reference (same two learnings).

### Phase 4 — GREEN: ux-design-lead body cross-reference

Edit `plugins/soleur/agents/product/design/ux-design-lead.md` Step 3. Keep item 5 (`xdg-open`)
verbatim. Append to item 5 (or as a new sub-note under item 6) one sentence: "The interactive
**approve / request-changes** pause lives in the *orchestrator* (brainstorm Phase 3.55b / plan
Phase 2.5 step 4b), not in this agent — a Task subagent cannot pause for operator input
(`2026-05-12-task-subagent-prompt-text-only.md`); this agent's job ends at opening the folder."
This is the discoverability anchor so a future editor of the agent does not re-add a pause here.

### Phase 5 — verify

1. Run the full plugin test suite (`cd plugins/soleur && bash scripts/test-all.sh` per
   `package.json` `scripts.test`). Confirm GREEN including the new file.
2. `python3 scripts/lint-agents-rule-budget.py` and `python3 scripts/lint-rule-ids.py` pass
   (defensive — only relevant if a sidecar was incidentally touched; the plan touches none).
3. Manual read-through: confirm both gates co-locate their headless branch and that no prose
   instructs a headless pause anywhere.

## Files to Edit

- `plugins/soleur/skills/brainstorm/SKILL.md` — add Phase 3.55b wireframe review pause (Phase 2).
- `plugins/soleur/skills/plan/SKILL.md` — add Phase 2.5 step 4b wireframe review pause (Phase 3).
- `plugins/soleur/agents/product/design/ux-design-lead.md` — Step 3 cross-reference note (Phase 4).

## Files to Create

- `plugins/soleur/test/wireframe-feedback-pause.test.ts` — RED→GREEN end-state assertions (Phase 1).

## Out of Scope / Non-Goals

- **`work` Phase Design Artifact Gate (`work/SKILL.md:246`)** — invokes ux-design-lead for an
  *implementation brief*, not new wireframe generation; no `xdg-open`, nothing to review/approve.
  No gate. (Not deferred — genuinely out of scope, no review artifact produced.)
- **`ux-audit` `mode: audit`** — emits JSON findings, no review screenshots. No gate.
- **A new `wg-*` AGENTS.md rule** — descoped: `B_ALWAYS` at 22994/23000 leaves no room for a new
  always-loaded pointer without a demotion (`2026-06-15-agents-budget-at-cap-descopes-planned-rule-and-harvest-md-exclusion.md`). The behavior rides the existing `wg-ui-feature-requires-pen-wireframe`
  enforcement as SKILL.md prose. No deferral issue needed — the principle is fully captured in the
  skill bodies + test.
- **Image-based feedback** — the operator's free-text note is text; passing annotated-screenshot
  feedback into the re-invoked subagent is impossible (`2026-05-12-task-subagent-prompt-text-only.md`:
  subagents inherit prompt text only). Request-changes carries a text note only.

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** none
**Decision:** N/A — the mechanical UI-surface override does NOT fire: `## Files to Create` and
`## Files to Edit` contain only `plugins/soleur/skills/*/SKILL.md`, `plugins/soleur/agents/**/*.md`,
and `plugins/soleur/test/*.test.ts` — no path matches the UI-surface term list / glob superset
(no `*.tsx`, `*.njk`, `app/**/page.tsx`, `components/**`, etc.). This plan *discusses* the wireframe
review UX but *implements* orchestration prose — per the Phase 2.5 NONE carve-out ("A plan that
discusses UI concepts but implements orchestration changes … is NONE"), no wireframes are required
for this plan itself (no recursion).
**Agents invoked:** none
**Skipped specialists:** none — `ux-design-lead` is N/A (no UI surface in this plan's own Files).
**Pencil available:** N/A (no UI surface)

#### Findings

No user-facing runtime surface. The change improves the *interactive design-review ergonomics* of
the brainstorm/plan workflows. CPO/spec-flow review is valuable at plan-review time to confirm the
interactive-vs-headless branch is the right resolution of the feature's literal "pause" ask —
plan-review (DHH/Kieran/simplicity) will check that, plus spec-flow for the request-changes loop
having a defined exit (approve) and no dead end.

## Observability

Skip — pure-docs/prose change. No Files-to-Edit under `apps/*/server/`, `apps/*/src/`,
`apps/*/infra/`, or `plugins/*/scripts/`; introduces no new infrastructure surface. (Phase 2.9
skip-condition: pure-docs, no code/infra surface.)

## Open Code-Review Overlap

None — no open `code-review` issues touch `brainstorm/SKILL.md`, `plan/SKILL.md`,
`ux-design-lead.md`, or the new test file (verify at /work time via the Phase 1.7.5 query before
freezing).

## Test Scenarios

- **Interactive approve:** operator runs `/soleur:brainstorm` on a UI feature → ux-design-lead
  generates wireframes + opens folder → gate asks → operator picks Approve → brainstorm proceeds to
  Phase 3.6. (Asserted via prose-grep AC1; behavioral assertion is manual.)
- **Interactive request-changes:** operator picks Request changes, types "make the CTA bigger" →
  ux-design-lead re-invoked with that note → folder re-opens → gate re-asks → operator approves →
  proceeds. (AC4 asserts the loop prose; exit is the Approve branch.)
- **Headless one-shot:** `/soleur:one-shot "<UI feature>"` → plan Phase 2.5 generates wireframes →
  gate detects pipeline/subagent context → logs `wireframes ready for async review` → continues
  without pause → pipeline completes. (AC3 asserts the headless branch; the load-bearing guard
  against a hung autonomous run.)

## Risks & Mitigations

- **Risk: headless arm doesn't fire on the one-shot path → autonomous pipeline hangs on
  AskUserQuestion.** Mitigation: the headless predicate reuses the exact pattern already proven at
  brainstorm Phase 0.4 (`:101`) and plan Phase 2.5 ADVISORY auto-accept (`:340`); plan runs inside a
  Task subagent under one-shot (`:70`), which is inherently non-interactive. AC3 + the headless test
  scenario gate this. **Plan-review must confirm the predicate covers the subagent-context case**,
  not just `--headless`.
- **Risk: gate misread as a pseudo-handoff that stalls even interactive runs after approval.**
  Mitigation: the Approve arm explicitly continues to the next phase in-prose (no summary-block
  handoff); cross-ref `2026-05-07-one-shot-stops-on-review-summary-as-pseudo-handoff.md`.
- **Risk: future editor re-adds a pause inside ux-design-lead.** Mitigation: Phase 4 cross-reference
  note + AC5 anchor it as the orchestrator's job.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder, or
  omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with a
  `threshold: none, reason: …` scope-out bullet.
- **Do NOT add a new `wg-*` rule** — `B_ALWAYS` is at 22994/23000 (6 bytes). Any new always-loaded
  pointer forces a `wg-*` demotion (and a demotion must pass the loader-class-fit check: this gate's
  trigger surface is `.md` skill edits = docs-only, and `AGENTS.rest.md` does NOT load on docs-only).
  Keep the behavior in SKILL.md prose under the existing wireframe gate.
- The headless/pipeline detection predicate is duplicated across brainstorm 3.55b and plan 2.5 step
  4b. Keep both copies' wording identical to the canonical predicate at brainstorm `:101` so a future
  change to mode-detection updates both. Note the coupling inline (per the Phase N.5 learning's
  "document the coupling inline" guidance).
- The request-changes loop must have a defined exit (Approve) — an unbounded loop with no exit arm is
  a dead end spec-flow will flag. The exit is the Approve branch; state it explicitly.
