---
title: "Backport API-budget operator preamble to autonomous-loop skills"
date: 2026-05-15
status: plan
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: docs-backport
classification: skill-authoring
related_issues: [3819]
parent_pr: 3809
draft_pr: 3839
brainstorm: knowledge-base/project/brainstorms/2026-05-15-api-budget-preamble-backport-brainstorm.md
spec: knowledge-base/project/specs/feat-api-budget-preamble-backport-3819/spec.md
---

# Plan: Backport API-budget operator preamble to autonomous-loop skills

**Issue:** [#3819](https://github.com/jikig-ai/soleur/issues/3819)
**Draft PR:** [#3839](https://github.com/jikig-ai/soleur/pull/3839)
**Branch:** `feat-api-budget-preamble-backport-3819`
**Worktree:** `.worktrees/feat-api-budget-preamble-backport-3819/`
**Brainstorm:** [2026-05-15-api-budget-preamble-backport-brainstorm.md](../brainstorms/2026-05-15-api-budget-preamble-backport-brainstorm.md)
**Spec:** [spec.md](../specs/feat-api-budget-preamble-backport-3819/spec.md)
**Parent PR (canonical disclosure source):** [#3809](https://github.com/jikig-ai/soleur/pull/3809) (merged 2026-05-15)

## Overview

Backport the API-budget operator disclosure paragraph introduced on the `/goal` docs page (`plugins/soleur/docs/pages/goal-primitive.md` §"What it consumes") to the six pre-existing autonomous-loop skills that consume operator API budget but currently disclose nothing:

1. `plugins/soleur/skills/test-fix-loop/SKILL.md`
2. `plugins/soleur/skills/drain-labeled-backlog/SKILL.md`
3. `plugins/soleur/skills/resolve-todo-parallel/SKILL.md`
4. `plugins/soleur/skills/resolve-pr-parallel/SKILL.md`
5. `plugins/soleur/skills/work/SKILL.md`
6. `plugins/soleur/skills/one-shot/SKILL.md`

The backport uses a uniform fenced `<decision_gate>` block (matching test-fix-loop's existing pre-flight pattern), reuses the Soleur/Anthropic billing split + BSL 1.1 disclaimer prose verbatim from `goal-primitive.md`, and tailors each block's cost-model paragraph to the skill's cost shape (bounded iterations vs. parallel agent fan-out vs. wall-clock pipeline). A companion `hr-*` AGENTS.md rule + CI assertion closes the door for the next autonomous-loop skill.

## User-Brand Impact (carry-forward from brainstorm)

**If this lands broken, the user experiences:** an operator running one of the six autonomous-loop skills against an unfamiliar dataset (a 50-issue label backlog, a 30-comment PR, a long test-fix iteration tree) burns through Anthropic credit without the per-iteration / per-agent cost model ever being surfaced. The disclosure is the gate that prevents the surprise invoice — if the prose drifts, is missing, or is removed, the operator gets the surprise.

**If this leaks, the user's money is exposed via:** Anthropic API invoice spike against the operator's session key. Soleur does not proxy or bill these calls.

**Brand-survival threshold:** `single-user incident`. One operator surprise invoice in the hundreds-to-thousands range is a brand-survival event for a tool whose value proposition is autonomous operator-trust. Carry-forward from parent plan #3809.

CPO sign-off requirement: covered by carry-forward from #3809 brainstorm + plan (CPO + CLO + CTO all signed the framing for the source disclosure; this PR extends the same disclosure to siblings under identical threshold).

Review-time enforcement: `user-impact-reviewer` agent invoked at PR review per `requires_cpo_signoff: true` frontmatter; review skill picks it up automatically.

## Domain Review

**Domains relevant:** Engineering (carry-forward from parent brainstorm/plan #3809; no fresh spawn per brainstorm Phase 0.5 "In-flight feature refresh" option).

### Carry-forward summary

CPO, CLO, and CTO signed off on the user-brand framing for the source disclosure (`/goal` docs page) in the parent brainstorm + plan. Backport scope here is strictly narrower (no new mechanism, no new surface, no new data movement — propagating the existing disclosure pattern to siblings under the same threshold). Load-bearing PR-time enforcement remains the `user-impact-reviewer` conditional agent.

### Product/UX Gate

**Tier:** NONE.

No new `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files in this PR. Edits are operator-facing SKILL.md prose only — not user-facing UI. Mechanical escalation does not fire.

## GDPR / Compliance Gate (Phase 2.7) — skipped

Skipped. Edits are static disclosure prose with zero new data flow, processing activity, or schema/auth touch. The brand-survival threshold trigger (b) fires from the frontmatter, but the gate's purpose is to catch regulated-data surfaces — none of which are touched here. If work-phase surfaces an unexpected data-touch during implementation, re-evaluate.

## Research Insights

### Brainstorm decisions (locked, carried forward)

| Decision | Choice | Source |
|----------|--------|--------|
| Disclosure surface | Fenced `<decision_gate>` block | Brainstorm §"Key Decisions" |
| Uniformity | Same shape across 6 skills | Brainstorm §"Key Decisions" |
| Per-skill cost-model tailoring | Block body adapts to bounded/parallel/wall-clock cost shape | Brainstorm §"Key Decisions" |
| Soleur/Anthropic + BSL 1.1 prose | Verbatim reuse from `goal-primitive.md` | Brainstorm §"Why This Approach" |
| PR shape | Single bundled PR | Brainstorm §"Why This Approach" |
| Rule binding | New `hr-*` rule + CI assertion in same PR | Brainstorm §"Why This Approach" |
| Brand-survival threshold | `single-user incident` (carry-forward from #3809) | Brainstorm §"User-Brand Impact" |

### Resolved open questions

| OQ | Plan resolution |
|----|-----------------|
| **OQ1 — rule slug** | `hr-autonomous-loop-skill-api-budget-disclosure`. 46-char id within typical range (40-50 chars; longest existing index slug is `hr-weigh-every-decision-against-target-user-impact` at 50 chars). Index line = 67 bytes (measured). |
| **OQ2 — sidecar tier** | `AGENTS.docs.md` (NOT `rest` as the spec OQ2 originally noted — see Research Reconciliation below). Editing `plugins/soleur/skills/*/SKILL.md` matches `DOCS_RE` in `session-rules-loader.sh` lines 99-101 → `HAS_DOCS=1` → `CLASSES="core docs-only"` (lines 115-119). `AGENTS.rest.md` does NOT load on docs-only sessions; placing the rule there would be silent no-op. `AGENTS.docs.md` is the canonical home for skill-authoring rules (`cq-rule-ids-are-immutable`, `cq-agents-md-why-single-line`, `cq-agents-md-tier-gate`, `cq-skill-description-budget-headroom`, `cq-eleventy-critical-css-screenshot-gate` all live there). |
| **OQ3 — test-fix-loop two-blocks-vs-merge** | **Merge.** Extend the existing `<decision_gate>` block at lines 42-46 with an API-budget preamble at the top of the gate body. Rationale: two adjacent `<decision_gate>` blocks could confuse the LLM agent about whether two separate operator confirmations are needed (the existing block is the *only* approval gate in the skill — see line 44 "This is the only approval gate"). Merging preserves "one operator interaction, two pieces of content." Sentinel grep still passes because the API-budget disclosure prose lands inside the merged gate. |
| **OQ4 — CI assertion: hardcoded vs. marker discovery** | **Hardcoded list of 6 skill basenames** in the test constant. Simpler, more readable, explicit change-tracked diff when a new autonomous-loop skill is added. The new `hr-*` rule text instructs future skill authors to also add the basename to the test's `AUTONOMOUS_LOOP_SKILLS` constant — same friction as a frontmatter field but with no schema-extension surface. |

### Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|------------|---------|---------------|
| Spec OQ2 says "rest.md is natural home unless it also belongs in change-class load for docs-only and rest tiers" | Loader-class verification (session-rules-loader.sh lines 99-119) confirms docs-only sessions load `core + docs-only` ONLY, not rest. Placing rule in rest is silent no-op on skill-authoring sessions. | Plan resolves OQ2 to `AGENTS.docs.md`, citing loader-class fit. Spec OQ2 was authored on incomplete reading; plan supersedes. |
| Spec FR4 says "the new API-budget `<decision_gate>` block sits separately from the existing pre-flight confirmation `<decision_gate>` block" | The existing block at lines 42-46 explicitly says "This is the only approval gate -- no per-iteration approval." Two distinct gates would semantically contradict that line. | Plan resolves OQ3 to merge (single gate with two-section body). Spec FR4 explicitly noted plan-phase decision; plan picks merge. |
| Spec TR3 says CI assertion needs "a disambiguating sentinel inside the block" | Confirmed. Selected sentinel: `disclaims warranty for runtime cost`. Short (5 words), distinctive (legal disclaimer phrasing unique to this disclosure), verbatim across all 6 disclosures. | Plan adopts `disclaims warranty for runtime cost` as the CI sentinel. |
| Spec OQ2 mentioned demoting a `wg-*` or retiring a rule | B_ALWAYS = 22687 (pre-PR, measured 2026-05-15) already exceeds the 22000 critical threshold. Adding the new index line (67 bytes) takes B_ALWAYS to 22754. The new rule body lands in `AGENTS.docs.md` (not always-loaded), so only the index line counts. | Plan prescribes a body-trim of ≥67 bytes from an existing `AGENTS.core.md` rule's `Why:` line to net-shrink B_ALWAYS to the pre-PR baseline or below. Trim site identified at work-phase via grep over the 5 longest core rule lines (current top: 582 bytes — near the 600-byte cap). |

### AGENTS.md byte budget (measured 2026-05-15)

```
B_INDEX (AGENTS.md)        = 4721 bytes  (always-loaded index)
B_CORE  (AGENTS.core.md)   = 17966 bytes (always-loaded sidecar)
B_ALWAYS = B_INDEX + B_CORE = 22687 bytes  [CRITICAL: > 22000 threshold]
```

Post-PR projection (before trim):
```
B_INDEX_new = 4721 + 67 (new index line) = 4788
B_ALWAYS_new = 4788 + 17966 = 22754  [still CRITICAL]
```

Post-PR projection (after trim of ≥67 bytes from AGENTS.core.md):
```
B_INDEX_new   = 4788
B_CORE_new    ≤ 17899
B_ALWAYS_new ≤ 22687  [net-flat or slight shrink vs. pre-PR baseline of 22687]
```

The shrink offsets the new index line but does NOT bring B_ALWAYS under the 22000 critical threshold. That is a pre-existing condition, scope-out for this PR — see Open Questions / Follow-ups for the tracking issue.

### Skill description budget (measured 2026-05-15)

No `description:` frontmatter changes in this PR (edits are body-only). Skill description budget unaffected. `cq-skill-description-budget-headroom` does not fire.

### Open Code-Review Overlap (Phase 1.7.5)

Five open code-review issues reference `AGENTS.md` in their bodies (#3392, #3373, #3372, #3160, #3002) and one references `plugins/soleur/test/components.test.ts` (#3750). **All Acknowledge — no overlap.** Each issue's actual scope is a specific code review finding elsewhere (recovery patterns, integration test wiring, service worker error handling, jwt-mint extraction); they cite the AGENTS.md or components.test.ts paths only as part of "could-add-rule-or-test" prose, not because they conflict with this PR's edits.

Verified via `jq` substring match against `gh issue list --label code-review --state open` body bodies. Re-verify at work-phase before committing if any of these issues land first.

## Files to Edit

### 1. `plugins/soleur/skills/test-fix-loop/SKILL.md`

Extend the existing `<decision_gate>` block at lines 42-46. New form:

```markdown
<decision_gate>
**API budget.** Each iteration of this loop consumes one main-model turn (parse failures → cluster → fix → re-run) against the Anthropic API key in your Claude Code session. The `max iterations` cap (default 5, configurable via `$ARGUMENTS`) is the only cost ceiling — a runaway against a perpetually-flaky test command or an infinite-regression chain runs up to the cap before terminating. Soleur does not bill or proxy these calls — Anthropic does, against the key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.

Show the user: detected test command, max iterations, current branch.
Get one confirmation before starting the loop. This is the only approval gate --
no per-iteration approval.
</decision_gate>
```

### 2. `plugins/soleur/skills/drain-labeled-backlog/SKILL.md`

Insert a new `<decision_gate>` block immediately after the `## When to use` section, before `## Prerequisites`:

```markdown
<decision_gate>
**API budget.** This skill delegates each selected cluster to `/soleur:one-shot`, which runs a full plan→work→review→ship pipeline (30–90 min wall-clock per cluster; non-trivial Anthropic credit per run scaling with plan complexity and review-cycle count). With `--top-n N`, the cost multiplies by N. The `--dry-run` flag previews scope without delegating. Soleur does not bill or proxy these calls — Anthropic does, against the key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.

Confirm cluster scope (size, `--top-n`, milestone) before allowing the skill to fan out.
</decision_gate>
```

### 3. `plugins/soleur/skills/resolve-todo-parallel/SKILL.md`

Insert a new `<decision_gate>` block after the legacy-note quote block (before `## Workflow`):

```markdown
<decision_gate>
**API budget.** This skill spawns one `pr-comment-resolver` agent in parallel per unresolved TODO (N TODOs = N agents). Each agent runs an independent task with its own context window and token cost; parallel fan-out compresses wall-clock but not aggregate token consumption. Soleur does not bill or proxy these calls — Anthropic does, against the key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.

Confirm the TODO count before allowing the fan-out. A pending backlog of 30 TODOs spawns 30 parallel agents.
</decision_gate>
```

### 4. `plugins/soleur/skills/resolve-pr-parallel/SKILL.md`

Insert a new `<decision_gate>` block after the intro paragraph (before `## Workflow`):

```markdown
<decision_gate>
**API budget.** This skill spawns one `pr-comment-resolver` agent in parallel per unresolved PR comment (N comments = N agents). Each agent runs an independent task with its own context window and token cost; parallel fan-out compresses wall-clock but not aggregate token consumption. Soleur does not bill or proxy these calls — Anthropic does, against the key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.

Confirm the unresolved-comment count before allowing the fan-out. A PR with 40 unresolved threads spawns 40 parallel agents.
</decision_gate>
```

### 5. `plugins/soleur/skills/work/SKILL.md`

Insert a new `<decision_gate>` block after the `## Input Document` section, before `## Execution Workflow`:

```markdown
<decision_gate>
**API budget.** This skill executes a work plan iteratively across many phases. Tier A (Agent Teams) carries ~7x per-task token cost; Tier B (Subagent Fan-Out) is moderate; Tier C is single-agent. Total cost scales with plan length, chosen tier, and per-task RED/GREEN/REFACTOR cycles. Soleur does not bill or proxy these calls — Anthropic does, against the key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.

The tier offer fires inline at the right phase. Decline if running an unfamiliar plan against a tight budget.
</decision_gate>
```

### 6. `plugins/soleur/skills/one-shot/SKILL.md`

Insert a new `<decision_gate>` block immediately before Step 0a (Linear context preflight), at the top of the run-these-steps-in-order body:

```markdown
<decision_gate>
**API budget.** This skill runs the full autonomous engineering pipeline: plan → work → review → resolve-pr-parallel → ship. Typical wall-clock 30–90 min; per-run Anthropic credit cost is non-trivial and scales with plan complexity, review-cycle count, and PR comment volume. The pipeline runs autonomously once Step 0a/0a.5 collision checks pass — there are no per-phase approval gates after that. Soleur does not bill or proxy these calls — Anthropic does, against the key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.

If running against a tight budget, run `/soleur:plan` instead and review the plan before invoking `/soleur:work` separately.
</decision_gate>
```

### 7. `AGENTS.md` — index entry

Add to the `## Hard Rules` section (in slug-alphabetical position; falls between `hr-all-infrastructure-provisioning-servers` and `hr-before-asserting-github-issue-status`):

```markdown
- [id: hr-autonomous-loop-skill-api-budget-disclosure] → docs-only
```

### 8. `AGENTS.docs.md` — new rule body

Append to the `## Hard Rules` section of `AGENTS.docs.md` (one new bullet, ≤500 bytes):

```markdown
- When authoring or modifying an autonomous-loop Soleur skill (stop-hook-bounded iteration loop, parallel N-agent fan-out, or chained plan→work→review→ship pipeline), include an API-budget operator disclosure as a `<decision_gate>` block containing the sentinel `disclaims warranty for runtime cost` along with a per-iteration cost-model paragraph and the verbatim Soleur/Anthropic billing split [id: hr-autonomous-loop-skill-api-budget-disclosure] [skill-enforced: plan §1.8, test: `plugins/soleur/test/components.test.ts` autonomous-loop-disclosure assertion]. New autonomous-loop skills must add their basename to the test's `AUTONOMOUS_LOOP_SKILLS` constant. **Why:** #3819 backport closing the disclosure asymmetry left by #3809.
```

**Pre-write byte check (per `hr-when-a-plan-specifies-relative-paths-e-g` cousin in plan sharp edges):**
- `awk` length probe: the bullet above is ~536 bytes (under the 600-byte per-rule cap; comfortable headroom).

### 9. `AGENTS.core.md` — body-trim ≥67 bytes

Identify and trim one redundant `Why:` line clause from an existing core rule to offset the +67-byte index addition. Trim site selection at work-phase via:
- `awk '/^- /' AGENTS.core.md | awk '{print length, $0}' | sort -rn | head -5` (top 5 longest, currently 535-582 bytes — near-cap, but each likely has redundant prose)
- Prefer trimming `Why:` line prose that duplicates information already in the rule body or learning-file citation. Per `cq-agents-md-why-single-line` sharp edge "preserve per-issue mechanism labels (text after each `#N`); strip redundant prose only."

Concrete net-flat acceptance: post-trim `B_ALWAYS ≤ 22687` bytes (pre-PR baseline). Strict net-shrink target: `B_ALWAYS ≤ 22500` (modest progress toward 22000, leaves headroom).

### 10. `plugins/soleur/test/components.test.ts` — new assertion

Add a new `describe()` block near the end of the file (after the existing "Convention: Kebab-case filenames" block, before the closing of the file):

```typescript
// ---------------------------------------------------------------------------
// Autonomous-loop skills must disclose API budget (#3819)
// ---------------------------------------------------------------------------

describe("Autonomous-loop API-budget disclosure", () => {
  const AUTONOMOUS_LOOP_SKILLS = [
    "test-fix-loop",
    "drain-labeled-backlog",
    "resolve-todo-parallel",
    "resolve-pr-parallel",
    "work",
    "one-shot",
  ];

  // Sentinel chosen for distinctiveness + verbatim across all 6 disclosures.
  // Tracks the BSL 1.1 disclaimer carried over from `goal-primitive.md`.
  const SENTINEL = "disclaims warranty for runtime cost";

  for (const skillName of AUTONOMOUS_LOOP_SKILLS) {
    test(`${skillName} carries API-budget <decision_gate> disclosure`, () => {
      const skillPath = `plugins/soleur/skills/${skillName}/SKILL.md`;
      const raw = readFileSync(skillPath, "utf-8");

      // Find all <decision_gate>...</decision_gate> blocks.
      const gateBlocks = raw.match(/<decision_gate>[\s\S]*?<\/decision_gate>/g) ?? [];

      expect(
        gateBlocks.length,
        `${skillName} has no <decision_gate> block`,
      ).toBeGreaterThan(0);

      // At least one block must contain the sentinel.
      const hasDisclosure = gateBlocks.some((b) => b.includes(SENTINEL));
      expect(
        hasDisclosure,
        `${skillName} <decision_gate> blocks do not contain API-budget sentinel "${SENTINEL}". ` +
          `Each autonomous-loop skill must disclose the per-iteration cost model and Soleur/Anthropic billing split.`,
      ).toBe(true);
    });
  }
});
```

Also add at the top of the file (alongside other imports):

```typescript
import { readFileSync } from "node:fs";
```

If `readFileSync` is already imported via the helpers module, omit the new import line — work-phase grep at first edit.

## Files to Create

None.

## Phases

### Phase 0 — Preconditions

**Read-only verification before any edit:**

0.1. Re-measure B_ALWAYS at work-start (plan-quoted numbers can drift if parallel branches land):
```bash
B_INDEX=$(wc -c < AGENTS.md); B_CORE=$(wc -c < AGENTS.core.md); B_ALWAYS=$((B_INDEX + B_CORE))
echo "B_ALWAYS = $B_ALWAYS"
```
Record the actual baseline. Trim site selection in Phase 3 must produce `B_ALWAYS_post ≤ B_ALWAYS_pre`.

0.2. Verify the canonical disclosure prose lives at `plugins/soleur/docs/pages/goal-primitive.md` lines 53-59 (or equivalent §"What it consumes" section). If the file path or section has moved, re-anchor before drafting the six skill edits.

0.3. Verify `<decision_gate>` is not used elsewhere in the 6 target skills (other than test-fix-loop's existing block):
```bash
grep -l "<decision_gate>" plugins/soleur/skills/{drain-labeled-backlog,resolve-todo-parallel,resolve-pr-parallel,work,one-shot}/SKILL.md
```
Expected: zero matches. If non-zero, the new block insertion site needs re-evaluation per skill.

0.4. Re-run code-review overlap check (`jq` against `gh issue list --label code-review --state open --json number,title,body --limit 200`) to confirm the 6 issues identified at plan-time remain Acknowledge (no scope conflict).

### Phase 1 — Update 6 SKILL.md files (consumer compliance first)

Edit each skill in order. The rule (Phase 2) declares the contract; placing consumer edits first means the CI assertion (Phase 4) ships green on its first run.

1.1. `test-fix-loop/SKILL.md` — merge API-budget preamble into existing `<decision_gate>` at lines 42-46 (form per Files to Edit §1).

1.2. `drain-labeled-backlog/SKILL.md` — insert new `<decision_gate>` after `## When to use`, before `## Prerequisites` (form per §2).

1.3. `resolve-todo-parallel/SKILL.md` — insert new `<decision_gate>` after the legacy-note `> **Note:** ...` blockquote (form per §3).

1.4. `resolve-pr-parallel/SKILL.md` — insert new `<decision_gate>` after the intro paragraph (form per §4).

1.5. `work/SKILL.md` — insert new `<decision_gate>` after `## Input Document`, before `## Execution Workflow` (form per §5).

1.6. `one-shot/SKILL.md` — insert new `<decision_gate>` at the top of the body (before Step 0a) (form per §6).

After each edit, re-read the affected file's first 60 lines to verify the block landed correctly inside the worktree (per `cm-when-proposing-to-clear-context-or` cousin and the Edit-tool-vs-bare-root learning).

### Phase 2 — Add new `hr-*` rule + index entry

2.1. Add the new rule body to `AGENTS.docs.md` (per Files to Edit §8).

2.2. Add the index line to `AGENTS.md` `## Hard Rules` section in slug-alphabetical position (per §7).

2.3. Verify the rule's `[id: ...]` is not in `scripts/retired-rule-ids.txt`:
```bash
grep -F "hr-autonomous-loop-skill-api-budget-disclosure" scripts/retired-rule-ids.txt
```
Expected: zero matches.

2.4. Run `lefthook` lints. Both MUST pass — do not suppress failures:
```bash
python3 scripts/lint-rule-ids.py
python3 scripts/lint-agents-rule-budget.py
```
If `lint-agents-rule-budget.py` rejects on B_ALWAYS, that is expected — defer the rejection to Phase 3 trim and re-run after trim. Any other failure surfaces a real issue.

### Phase 3 — Body-trim `AGENTS.core.md` to net-flat B_ALWAYS

3.1. Identify the trim site:
```bash
awk '/^- /' AGENTS.core.md | awk '{print length, NR, $0}' | sort -rn | head -10
```
Choose a rule whose `Why:` line contains prose redundant with information already in the body or in a linked learning file (per `cq-agents-md-why-single-line` sharp edge).

3.2. Trim ≥67 bytes of redundant prose. Preserve per-issue mechanism labels (text after each `#N`).

3.3. Re-measure B_ALWAYS:
```bash
B_INDEX=$(wc -c < AGENTS.md); B_CORE=$(wc -c < AGENTS.core.md); B_ALWAYS=$((B_INDEX + B_CORE))
echo "post-trim B_ALWAYS = $B_ALWAYS (baseline was $B_ALWAYS_PRE)"
```
Verify `B_ALWAYS_post ≤ B_ALWAYS_pre`. If not, trim more.

3.4. Run `python3 scripts/lint-agents-rule-budget.py` to confirm no rejection.

### Phase 4 — Add CI assertion

4.1. Edit `plugins/soleur/test/components.test.ts` per Files to Edit §10.

4.2. Run the test suite locally:
```bash
bun test plugins/soleur/test/components.test.ts
```
Expected: all existing tests pass + 6 new `Autonomous-loop API-budget disclosure` tests pass.

### Phase 5 — Verification + commit

5.1. Full test run:
```bash
bun test plugins/soleur/test/components.test.ts
```

5.2. Visual confirmation: read each of the 6 SKILL.md files and confirm the disclosure renders as intended.

5.3. Stage and commit (single commit, single PR — brainstorm decision):
```bash
git add plugins/soleur/skills/{test-fix-loop,drain-labeled-backlog,resolve-todo-parallel,resolve-pr-parallel,work,one-shot}/SKILL.md \
        AGENTS.md AGENTS.docs.md AGENTS.core.md \
        plugins/soleur/test/components.test.ts
git status --short
git commit -m "feat: backport API-budget operator preamble to autonomous-loop skills"
git push
```

5.4. Convert draft PR #3839 to ready when review-cycle is complete (out of this plan's scope — handled by `/soleur:ship`).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1:** All six target SKILL.md files carry a `<decision_gate>` block whose body contains the literal string `disclaims warranty for runtime cost`.
- [ ] **AC2:** The Soleur/Anthropic billing-split prose ("Soleur does not bill or proxy these calls — Anthropic does, against the key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.") appears verbatim in each of the six skills' disclosure blocks.
- [ ] **AC3:** Each block's cost-model paragraph is tailored per skill:
  - `test-fix-loop`: cites `max iterations` cap (default 5) as the cost ceiling.
  - `drain-labeled-backlog`: cites cluster × `/soleur:one-shot` multiplier; cites `--top-n N` and `--dry-run`.
  - `resolve-todo-parallel`: cites N TODOs = N parallel agents.
  - `resolve-pr-parallel`: cites N PR comments = N parallel agents.
  - `work`: cites Tier A (~7x), Tier B (moderate), Tier C (single-agent) cost framing.
  - `one-shot`: cites 30–90 min wall-clock pipeline; cites collision-check Step 0a/0a.5 as the last approval point.
- [ ] **AC4:** `AGENTS.docs.md` contains the new `hr-autonomous-loop-skill-api-budget-disclosure` rule body with `**Why:**` line and `[skill-enforced: ...]` / `[id: ...]` tags.
- [ ] **AC5:** `AGENTS.md` index has a new entry `[id: hr-autonomous-loop-skill-api-budget-disclosure] → docs-only` in slug-alphabetical position within the `## Hard Rules` section.
- [ ] **AC6:** `plugins/soleur/test/components.test.ts` contains the new `Autonomous-loop API-budget disclosure` describe block with hardcoded list of 6 skills and sentinel `disclaims warranty for runtime cost`. The test fails when any one of the 6 skills' `<decision_gate>` blocks is missing the sentinel (self-evident from the `gateBlocks.some(b => b.includes(SENTINEL))` shape).
- [ ] **AC7:** `bun test plugins/soleur/test/components.test.ts` passes (all existing assertions + 6 new autonomous-loop assertions).
- [ ] **AC8:** Post-trim B_ALWAYS ≤ Phase 0.1 captured pre-PR baseline. Measured by `B_INDEX=$(wc -c < AGENTS.md); B_CORE=$(wc -c < AGENTS.core.md); echo $((B_INDEX + B_CORE))`.
- [ ] **AC9:** `python3 scripts/lint-rule-ids.py` and `python3 scripts/lint-agents-rule-budget.py` pass.
- [ ] **AC10:** PR body carries `## Changelog` section and `semver:patch` label (docs/rule-only change).
- [ ] **AC11:** PR body uses `Closes #3819`. `requires_cpo_signoff: true` frontmatter automatically fires `user-impact-reviewer` at PR review — review passes with no Critical findings.

### Post-merge (operator)

None. CI passing on the merge commit is sufficient evidence; `Closes #3819` auto-closes the issue.

## Test Strategy

- **Automated (Bun):** `plugins/soleur/test/components.test.ts` adds 6 new tests (one per autonomous-loop skill) asserting presence of a `<decision_gate>` block + the sentinel string. Test shape `gateBlocks.some(b => b.includes(SENTINEL))` is self-evidently correct against the failure case it's designed for.
- **Existing CI:** `lefthook` pre-commit lints (`lint-rule-ids.py`, `lint-agents-rule-budget.py`) gate the AGENTS sidecar changes. `bun test plugins/soleur/test/components.test.ts` runs in CI.
- **Manual:** Visual read-through of each SKILL.md to confirm placement + prose rendering. (Single human pass — sanity check, not a substitute for the CI assertion.)
- **No new test framework dependencies.** All test work happens in the existing `plugins/soleur/test/components.test.ts` using existing `bun:test` conventions.

## Risks

| Risk | Mitigation |
|------|------------|
| Disclosure prose drifts from `goal-primitive.md` over time | CI sentinel `disclaims warranty for runtime cost` is a load-bearing literal; any reword of the source disclosure that drops the BSL 1.1 phrase breaks the sentinel match. Goal-primitive.md is the canonical source; if its prose changes, the sentinel + 6 SKILL.md disclosures + rule body must update in lockstep. |
| B_ALWAYS budget pressure remains pre-existing | This PR is net-flat for B_ALWAYS via Phase 3 trim, but the pre-existing condition (22687 > 22000) is unresolved. Tracked as a separate follow-up (see Open Questions). |
| Merging into test-fix-loop's existing `<decision_gate>` changes its operator-confirmation semantics | Verified low-impact: the existing block is the *only* approval gate (`test-fix-loop/SKILL.md:44`). Adding a preamble to its body does not duplicate or override the confirmation logic — it adds context the operator should read before confirming. |

## Open Questions / Follow-ups

1. **B_ALWAYS shrink-under-threshold follow-up.** Pre-PR baseline is 22687 (over 22000 critical). This PR is net-flat. A separate plan should bring B_ALWAYS under 22000 by demoting `wg-*` rules from core to rest/docs-only (per the loader-class-fit verification sharp edge — only `wg-*` demotable, never `hr-*`). **File a deferred-scope-out issue at work-phase** with milestone `Post-MVP / Later`, label `deferred-scope-out`, title `chore: shrink AGENTS.md always-loaded payload under 22000 critical threshold`.
2. **Per-skill empirical cost numbers.** The disclosures use qualitative framing ("non-trivial Anthropic credit", "30–90 min wall-clock"). If operator-survey or telemetry data emerges showing typical per-run costs, refine the prose in a follow-up.
3. **Sentinel evolution.** If the canonical `goal-primitive.md` prose changes such that `disclaims warranty for runtime cost` is no longer a stable substring, update the CI test's `SENTINEL` constant + the rule body in lockstep. The brainstorm decision was "verbatim reuse"; any reword must propagate to all 6 skills.
4. **DHH dissent on rule-and-test ceremony (recorded for future override).** Plan-review DHH agent argued that adding an `hr-*` rule + CI test for a 6-file prose change is overengineering — "a tautology with extra steps" since the test's hardcoded `AUTONOMOUS_LOOP_SKILLS` list is itself a second list to keep in sync with the first. The brainstorm explicitly locked this decision (user picked "Yes — add hr-* rule"), so this plan preserves the rule + test. If, after shipping, the rule + test prove non-load-bearing (e.g., no future autonomous-loop skill gets added in 6 months), reconsider removal in a follow-up. Recording DHH's reasoning here so the conversation can be revisited with the receipts in hand.

## Sharp Edges

- The brainstorm's `## Open Questions` OQ3 (test-fix-loop two-blocks-vs-merge) is **resolved as merge** in this plan. Resist a reviewer push to split into two `<decision_gate>` blocks unless they cite a concrete LLM-semantic harm — the merge preserves "only approval gate" semantics from the existing block.
- The spec's OQ2 originally pointed to `AGENTS.rest.md`. This plan supersedes that with `AGENTS.docs.md` per loader-class fit. If a reviewer suggests `rest.md`, point them to `session-rules-loader.sh` lines 99-119: docs-only sessions do not load rest.
- Per `cq-agents-md-tier-gate`, the new rule is **cross-cutting session invariant** (fires on any skill-authoring session, no single-file trigger). AGENTS-md-eligible by the placement gate. The `[skill-enforced: ...]` tag points to the test file as the canonical mechanical enforcement — this rule is enforced-via-CI-and-prose, not enforced-via-hook.
- A plan whose `## User-Brand Impact` section is empty or contains only `TBD`/`TODO`/placeholder text will fail `deepen-plan` Phase 4.6. This plan's section is fully populated via brainstorm carry-forward.

## Domain Review Trigger Log

- Phase 0.5 brainstorm: USER_BRAND_CRITICAL=true triggered (matched on "billing surprise", "payment", "trust breach" keywords).
- Phase 2.5 plan: Domain leaders carry-forward from parent plan #3809 (no fresh spawn). Product/UX Gate: NONE.
- Phase 2.6 plan: `## User-Brand Impact` section populated via brainstorm carry-forward.
- Phase 2.7 plan: GDPR/Compliance Gate invoked-as-no-op due to threshold trigger (b); expected zero findings.
