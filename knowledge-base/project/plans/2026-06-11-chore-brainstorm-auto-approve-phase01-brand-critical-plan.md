---
title: "chore(brainstorm): auto-approve Phase 0.1 user-impact gate (always brand-critical, no prompt)"
issue: 5175
branch: feat-one-shot-5175-phase01-auto-brand-critical
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# chore(brainstorm): Auto-approve Phase 0.1 user-impact gate — always brand-critical, no prompt 🛠️

## Overview

The brainstorm skill's **Phase 0.1: User-Impact Framing** currently presents an `AskUserQuestion` prompt on every brainstorm, parses the operator's free-text answer for trigger keywords, and conditionally sets `USER_BRAND_CRITICAL=true`/`false`. Operator feedback from the **#5085 brainstorm** (captured in issue #5175 on 2026-06-11): they **always answer "all of them"**, so the prompt is pure friction and never changes the posture.

This change makes Phase 0.1 **unconditional**:

1. Skip the `AskUserQuestion` framing prompt entirely (delete Step 1's interactive call and the Step 2 keyword-parse branch).
2. Set `USER_BRAND_CRITICAL=true` unconditionally.
3. Synthesize a generic `## User-Brand Impact` block (artifact = the feature's named surface; vector = generic; threshold = `single-user incident`) so Phase 3.5 still persists it for plan-time carry-forward.
4. **Keep** the telemetry emit (`emit_incident hr-weigh-every-decision-against-target-user-impact applied`) — the rule still records when it fires; the now-constant "fired vs asked" ratio is an accepted tradeoff.
5. Lane auto-sets to `cross-domain` (this is **existing** behavior — Phase 0.4 already forces `LANE=cross-domain` when `USER_BRAND_CRITICAL=true`; no new logic).

**This is a focused prose edit to ONE file** (`plugins/soleur/skills/brainstorm/SKILL.md`, Phase 0.1, plus the one-line cross-reference at Phase 0.4). There is no application source code or test to write — the "tests" are the skill's own self-consistency. The plan is deliberately proportionate to a prose edit.

**Type:** chore (skill-instruction change). **Semver:** `patch` (behavior change to an existing skill, no new component, no breaking API). **Why patch not minor:** no new skill/agent/command is added; this is a default-flip on an existing skill.

## Research Reconciliation — Spec vs. Codebase

The issue/ARGUMENTS say to edit Phase 0.1 "**and any spec references under `knowledge-base/project/specs/feat-agents-md-*` or the brainstorm references dir**." Repo research found those references do **not** describe the Phase 0.1 mechanism and must **NOT** be edited.

| ARGUMENTS claim | Codebase reality | Plan response |
|---|---|---|
| "spec references under `feat-agents-md-*` … so that [Phase 0.1 changes]" | `feat-agents-md-change-class-loader/spec.md:7` (`**Brand-survival threshold:** single-user incident (USER_BRAND_CRITICAL=true)`) and `:195` (AC: `user-impact-reviewer` sign-off) merely **annotate that feature's own** brand-survival posture. They do not prescribe or describe the Phase 0.1 gate. `feat-agents-md-shrink/spec.md` has **zero** Phase 0.1 / USER_BRAND_CRITICAL references. | **Do NOT edit either spec.** Editing them would corrupt an unrelated feature's recorded threshold. Documented as an explicit no-op (see Non-Goals). |
| "or the brainstorm references dir" | `brainstorm-domain-config.md` `## User-Brand-Critical Tag Processing` + `## Lane Inference` already handle `USER_BRAND_CRITICAL=true` correctly (triad always fires, lane forced `cross-domain`, fail-closed-expand is a no-op). The triad/lane logic is **functionally inert** under the unconditional flag — it already works. | **Light prose touch only** (optional, see Phase 2): reword "When brainstorm Phase 0.1 *sets* `USER_BRAND_CRITICAL=true`" → reflect that it is now *always* set. No structural change. If the wording already reads correctly under always-true, leave it. |
| Telemetry comment is fine as-is | `SKILL.md:103` says *"Do NOT emit telemetry when `USER_BRAND_CRITICAL=false` — the gate only records when it activates. The aggregate ratio of 'fired vs. asked' is itself a signal worth tracking."* Once the flag is always-true there is no `false` branch and no "asked" path — this comment becomes a **lie**. | **Update line 103's comment** so it stops describing a "fired vs asked" distinction that no longer exists. The emit itself is KEPT (per issue requirement 4). This is a real touch point the bare ARGUMENTS did not name. |

## User-Brand Impact

**If this lands broken, the user experiences:** No direct end-user-facing artifact. This edits an internal authoring-workflow skill (`brainstorm`). The worst realistic failure is a malformed Phase 0.1 that (a) fails to set `USER_BRAND_CRITICAL=true`, silently **weakening** the user-impact gate (the opposite of the intended direction), or (b) skips persisting the `## User-Brand Impact` block, so plan Phase 2.6 carry-forward finds nothing. Both are caught by the skill's own self-consistency and by the existing downstream gates (deepen-plan Phase 4.6 halt, preflight Check 6).

**If this leaks:** N/A — no data, credentials, or user workflow are processed by this skill change.

**Brand-survival threshold:** `none`, reason: this is a meta-workflow prose edit to an internal skill that processes no user data and ships no user-facing surface; the change's *direction* is to strengthen (always-on) the user-impact gate, not weaken it. The diff touches no sensitive path (no schema, migration, auth flow, API route, `.sql`, infra, or Doppler surface — it is a single `.md` skill-instruction file under `plugins/soleur/skills/`), so preflight Check 6 will pass on the `threshold: none, reason: …` scope-out bullet above.

> **Note on the irony:** this very change makes *future* brainstorms always brand-critical. This plan's own threshold is `none` because the plan itself is the meta-edit, not a user-facing feature — assessed on its own merits per the standard plan-time gate.

## Background — what Phase 0.1 protects (do not weaken)

The gate originates from **#2887**: dev and prd Doppler configs both pointed at the *same* Supabase project — a single-user data breach that shipped for months because no workflow step ever asked "what is the worst thing the target user experiences if this fails?" (origin: `knowledge-base/project/brainstorms/2026-04-24-target-user-impact-gate-brainstorm.md`). The original design (#2887 Decision #2) made the question **mandatory and interactive on every brainstorm** — "the whole point is to force the framing."

This change does **not** weaken the gate — it makes it **unconditionally on** (fail-safe / over-protect direction, consistent with `knowledge-base/project/learnings/2026-06-03-self-heal-on-brand-path-only-acts-on-safe-symptom.md`). The operator's "all of them" answer already produced `USER_BRAND_CRITICAL=true` every time; this removes the friction of asking while preserving the always-protective posture. The one guard to keep in mind: the always-on default must not become a **rubber-stamp** that suppresses real per-feature user-impact reasoning. Mitigation: the synthesized `## User-Brand Impact` block must still name the **feature's actual surface** as the artifact (not a static literal), so plan-time carry-forward and the `user-impact-reviewer` at PR time still have a concrete artifact to reason against.

## Files to Edit

- **`plugins/soleur/skills/brainstorm/SKILL.md`** (lines 63–107, the `### Phase 0.1: User-Impact Framing` section) — the sole substantive edit. Rewrite per Phase 1 below.
  - Also: the cross-reference clause at **line 113** (Phase 0.4 `**Skip if** USER_BRAND_CRITICAL=true … "The framing question was already answered; avoid double-prompting."`) — update the rationale so it no longer implies a "framing *question*" was asked (it is now always-set, not answered). Functionally the skip already fires; only the rationale wording needs a light touch.
- **`plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`** (lines 16–18, `## User-Brand-Critical Tag Processing` opening sentence) — OPTIONAL light prose touch: "When brainstorm Phase 0.1 *sets* `USER_BRAND_CRITICAL=true`" → reflect that Phase 0.1 now *always* sets it. **No structural/logic change** — the triad + cross-domain + fail-closed-expand behavior is already correct under always-true (verified: `## Lane Inference` "USER_BRAND_CRITICAL × lane composition" paragraph). Skip this edit if the existing wording reads correctly under unconditional setting; it is documentation polish, not a correctness fix.

## Files to Create

None.

## Files NOT to Edit (explicit no-ops — guard against scope creep)

- `knowledge-base/project/specs/feat-agents-md-change-class-loader/spec.md` — annotates a *different* feature's threshold (see Reconciliation table). Editing it corrupts that feature's record.
- `knowledge-base/project/specs/feat-agents-md-shrink/spec.md` — zero Phase 0.1 references.
- `plugins/soleur/skills/plan/SKILL.md` Phase 2.6, `deepen-plan/SKILL.md` Phase 4.6, `preflight/SKILL.md` Check 6, `review/SKILL.md` user-impact-reviewer block — all **consume** `USER_BRAND_CRITICAL` / `## User-Brand Impact` correctly and require no change. An always-true flag means these gates fire more often (intended), not differently.
- `plugins/soleur/test/components.test.ts` — validates only the SKILL.md `description:` frontmatter field; this edit touches Phase 0.1 **body prose**, not the description. Not triggered. (`cq-skill-description-budget-headroom` likewise not triggered.)
- **`feat-operator-weekly-digest` (#5085) branch** — MUST NOT be touched. This is its own PR per the issue.

## Implementation Phases

### Phase 1 — Rewrite Phase 0.1 in `brainstorm/SKILL.md` (the substantive edit)

Replace the current Step 1 (ask) + Step 2 (keyword-parse branch) + the `if no keyword matches` branch with an unconditional set. Target shape (prose, not literal — author at edit time):

- **Drop:** Step 1's `AskUserQuestion` framing call (Header "User impact", the question text, the multi-select=false note, the 6-preset options list). With it goes the only consumer of the 4-option-cap preset constraints — confirm no later Phase 0.1 prose references the menu after the edit (per `knowledge-base/project/learnings/2026-05-04-askuserquestion-4-option-cap.md`).
- **Drop:** Step 2's keyword tables (user-data/auth lens + infra/data-store lens) and the `If any keyword matches / If no keyword matches` branch. There is no longer a branch — the flag is always set.
- **Replace with** a single unconditional block:
  1. `Set USER_BRAND_CRITICAL=true` for the rest of the brainstorm session (no prompt, no parse). One-line rationale: operator decision per #5175 — they always answered "all of them," so the prompt is pure friction. Cite #5175.
  2. **Synthesize the `## User-Brand Impact` block** with: **artifact = the feature's named surface** (derive from the feature description / `$ARGUMENTS` — the concrete thing being built, e.g. "the X endpoint", "the Y skill"; NOT a static literal — this preserves a real artifact for downstream reasoning per the rubber-stamp guard in Background), **vector = generic** (a single generic exposure-vector sentence), **threshold = `single-user incident`**. This is what Phase 3.5 persists and plan Phase 2.6 carries forward.
  3. **Announce** (keep the existing announce intent): "Tagged as **user-brand-critical** (auto, per #5175). CPO + CLO + CTO will be spawned in parallel at Phase 0.5 before other specialists. The plan derived from this brainstorm will inherit `Brand-survival threshold: single-user incident` unless overridden."
- **KEEP Step 3 (telemetry emit) verbatim** — the `emit_incident hr-weigh-every-decision-against-target-user-impact applied` bash block stays unchanged (issue requirement 4). It now fires on every brainstorm.
- **UPDATE the line-103 comment** (currently *"Do NOT emit telemetry when `USER_BRAND_CRITICAL=false` — the gate only records when it activates. The aggregate ratio of 'fired vs. asked' is itself a signal worth tracking."*). Since there is no `=false` branch anymore, rewrite to reflect reality: the gate now fires on every brainstorm by design (per #5175); the emit records *every* application of the rule. State the accepted tradeoff explicitly: the "fired vs asked" ratio is now constant — that signal was traded away for zero operator friction (issue "Tradeoff (accepted)" section). Do **not** delete the emit; only correct the comment that lies about a distinction that no longer exists.
- **KEEP Step 4** (Phase 3.5 persist contract) — it already says the brainstorm capture MUST include the `## User-Brand Impact` section when `USER_BRAND_CRITICAL=true`; now always true, so always persisted. Light touch: reword any "reflecting the operator's answer" phrasing → "reflecting the synthesized framing (artifact = feature surface, vector = generic, threshold = single-user incident)" since there is no operator answer to reflect.
- **KEEP the `**Why:**` #2887 paragraph** — the origin rationale is still accurate; optionally append one sentence noting #5175 made the gate unconditional to remove operator friction while preserving the always-protective posture.

### Phase 2 — Update the Phase 0.4 cross-reference rationale (`brainstorm/SKILL.md` line 113) and optional domain-config polish

- **Phase 0.4 line 113:** the `**Skip if** USER_BRAND_CRITICAL=true … set LANE=cross-domain` clause is functionally correct (the skip already fires). Update only the trailing rationale "The framing question was already answered; avoid double-prompting." → it was never "answered" now; reword to "Phase 0.1 unconditionally sets it; lane is fixed to cross-domain — no prompt." Confirms lane auto-set is **existing** behavior (issue requirement 5), not new logic.
- **`brainstorm-domain-config.md` lines 16–18 (optional):** reword "When brainstorm Phase 0.1 *sets*…" → "Brainstorm Phase 0.1 always sets `USER_BRAND_CRITICAL=true` (per #5175); …". Verify the `## Lane Inference` "USER_BRAND_CRITICAL × lane composition" paragraph still reads correctly (it does — the cross-domain force + no-op fail-closed-expand are unchanged). No logic edit.

### Phase 3 — Self-consistency verification (the "tests")

There is no automated test for Phase 0.1 prose. Verify by reading:

1. **Grep for dangling `false` references:** `grep -n "USER_BRAND_CRITICAL=false\|no keyword matches\|If any keyword" plugins/soleur/skills/brainstorm/SKILL.md` → MUST return zero hits after the edit (the conditional branch is gone).
2. **Grep the telemetry emit survived:** `grep -n "emit_incident hr-weigh-every-decision-against-target-user-impact applied" plugins/soleur/skills/brainstorm/SKILL.md` → MUST return exactly 1 hit (Step 3 kept).
3. **Grep the persist contract survived:** `grep -n "## User-Brand Impact" plugins/soleur/skills/brainstorm/SKILL.md` → Step 2 synthesis + Step 4 persist must both reference it.
4. **Read Phase 0.1 + Phase 0.4 (lines ~63–127) top to bottom** and confirm: no "ask the question" prose remains; the unconditional set is unambiguous; the lane skip rationale matches reality; the synthesized artifact is described as "the feature's named surface" (dynamic), not a static literal.
5. **Run the brainstorm-adjacent tests as a smoke check** (they don't assert Phase 0.1 but read the file): `bun test plugins/soleur/test/mandatory-wireframes-hardening.test.ts` and `bash plugins/soleur/test/lane-frontmatter.test.sh` → MUST still pass (no regression in Phase 3.55 / lane logic). Reference `package.json scripts.test` for the canonical runner if `bun` is not the configured runner.
6. **`components.test.ts` sanity:** `bun test plugins/soleur/test/components.test.ts` → MUST pass (description field unchanged; this confirms no accidental frontmatter edit).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] Phase 0.1 in `brainstorm/SKILL.md` no longer contains an `AskUserQuestion` framing prompt for user-impact (grep for the removed question text returns zero).
- [ ] `grep -cE "USER_BRAND_CRITICAL=false" plugins/soleur/skills/brainstorm/SKILL.md` returns `0` (no false branch remains).
- [ ] `grep -c "emit_incident hr-weigh-every-decision-against-target-user-impact applied" plugins/soleur/skills/brainstorm/SKILL.md` returns `1` (telemetry emit KEPT, issue req. 4).
- [ ] Phase 0.1 synthesizes a `## User-Brand Impact` block with artifact = the feature's named surface (described as dynamic, derived from the feature description — NOT a static literal), vector = generic, threshold = `single-user incident`.
- [ ] Phase 0.1 sets `USER_BRAND_CRITICAL=true` unconditionally (no keyword parse, no branch).
- [ ] The line-103 telemetry comment is corrected so it no longer claims a "fired vs asked" distinction that no longer exists; the accepted constant-ratio tradeoff is stated.
- [ ] Phase 0.4 line-113 skip rationale reworded so it no longer says "the framing question was already answered"; lane auto-set to `cross-domain` confirmed as existing behavior.
- [ ] No edit was made to `knowledge-base/project/specs/feat-agents-md-change-class-loader/spec.md` or `feat-agents-md-shrink/spec.md` (verify via `git diff --name-only` — these paths absent).
- [ ] No file under the `feat-operator-weekly-digest` (#5085) scope is touched (verify `git diff --name-only` contains only `brainstorm/SKILL.md`, optionally `brainstorm-domain-config.md`, and this plan/spec/tasks).
- [ ] `bun test plugins/soleur/test/components.test.ts` passes (description-field budget untouched).
- [ ] `bash plugins/soleur/test/lane-frontmatter.test.sh` and `bun test plugins/soleur/test/mandatory-wireframes-hardening.test.ts` pass (no Phase 0.4 / 3.55 regression).
- [ ] PR body uses `Closes #5175` and includes a `## Changelog` section with `semver:patch`.

### Post-merge (operator)
- None. Pure prose edit; merge IS the delivery. No migration, no infra, no external-service config.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal authoring-workflow (skill-instruction) prose change. No UI surface (no path under `components/**`, `app/**/page.tsx`, or the UI-surface term list — the only files edited are `.md` skill-instruction files under `plugins/soleur/skills/`). Product/UX Gate mechanical override does not fire. No regulated-data surface (GDPR gate 2.7 skipped). No new infrastructure (2.8 skipped). No code-class file under `apps/*/server|src|infra` or `plugins/*/scripts/` (Observability gate 2.9 skipped — pure-docs/skill-prose).

## Non-Goals / Out of Scope

- **Editing the `feat-agents-md-*` specs.** They annotate a different feature's threshold; not the Phase 0.1 mechanism. (Documented no-op, not a deferral — there is nothing to defer.)
- **Changing the triad / lane / Phase 0.5 logic.** Already correct under always-true; only optional prose polish in domain-config.
- **Touching downstream consumers** (plan 2.6, deepen-plan 4.6, preflight Check 6, review user-impact-reviewer). They consume the flag/section correctly; firing more often is the intended effect.
- **Re-introducing a low-stakes escape hatch.** The operator explicitly accepted the tradeoff (issue "Tradeoff (accepted)"): full CPO+CLO+CTO triad on every brainstorm including pure infra/CI, for zero prompts. This plan does NOT add a "skip triad for trivial brainstorms" path — that would re-introduce the friction the operator asked to remove. (Noted here so a reviewer doesn't read the always-on triad as an oversight; it is the explicit decision.)
- **`feat-operator-weekly-digest` / #5085** — separate PR, not bundled.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with a concrete `threshold: none, reason: …` scope-out (the diff touches no sensitive path), which satisfies preflight Check 6.
- **Do not over-edit.** The single load-bearing edit is the Phase 0.1 rewrite in `brainstorm/SKILL.md`. Everything else (line-113 rationale, domain-config opener) is light prose alignment. Resist editing downstream consumer skills — they are correct.
- **The synthesized artifact must be dynamic.** If the edit hard-codes a static literal as the `## User-Brand Impact` artifact (e.g. "the feature surface" verbatim), every brainstorm produces an identical, content-free block — exactly the rubber-stamp the gate's origin (#2887) warns against. The artifact MUST be derived from the feature description so plan Phase 2.6 carry-forward and the PR-time `user-impact-reviewer` have a real surface to reason against.
- **Telemetry comment is a real touch point.** The bare ARGUMENTS named only the emit ("KEEP it") but not its surrounding comment. Leaving line 103 unchanged ships a comment that lies. Update it; keep the emit.

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Keep the prompt but pre-select "all of them" as default | Still a prompt = still friction. Operator asked for **zero** prompts. |
| Remove the telemetry emit too (since the ratio is now constant) | Issue explicitly requires KEEPING the emit (req. 4) so the rule still records when it fires. Constant ratio is the accepted tradeoff, not a reason to drop the emit. |
| Add a "low-stakes brainstorm → skip triad" escape hatch | Re-introduces friction and a branch; operator accepted the always-on triad cost. Out of scope (see Non-Goals). |
| Edit the `feat-agents-md-*` specs as ARGUMENTS literally suggested | Those specs annotate a different feature's threshold; editing them is wrong. Research confirmed they do not describe the Phase 0.1 mechanism. |
