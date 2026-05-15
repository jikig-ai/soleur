---
title: "feat: /goal Primitive as Operator Escape Hatch"
status: ready-for-work
date: 2026-05-15
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_brainstorm: knowledge-base/project/brainstorms/2026-05-15-goal-primitive-operator-escape-hatch-brainstorm.md
related_spec: knowledge-base/project/specs/feat-goal-primitive-wiring/spec.md
related_issue: 3813
related_pr: 3809
---

# Plan: /goal Primitive as Operator Escape Hatch

## Overview

A docs-only deliverable that positions Claude Code's `/goal` primitive (v2.1.139+) as Soleur's recommended escape hatch for ad-hoc autonomous work outside dedicated Soleur skills. One new markdown page (`plugins/soleur/docs/pages/goal-primitive.md`), one soft-pointer paragraph appended to `plugins/soleur/AGENTS.md`, and a `engines.claude-code` floor declaration in `plugins/soleur/.claude-plugin/plugin.json`. A 30-minute pre-implementation spike verifies whether `/goal` can be set from inside a Skill-tool-invoked Soleur skill — the spike's outcome determines a single paragraph in the docs page, not its overall shape. **No new skill, hook, script, or wrapper.**

## User-Brand Impact (carry-forward)

**If this lands broken, the user experiences:** their own Anthropic API budget burned through by a Soleur-suggested `/goal` condition that the transcript-only evaluator never rules "yes" on — a runaway loop continuing turn after turn until the operator notices and Ctrl+C's it.

**If this leaks, the user's API budget is exposed via:** a published condition recipe whose marker is not actually verifiable from transcript (e.g., the marker depends on tool output the agent never surfaces, or names a fuzzy outcome the Haiku evaluator can interpret either way), or via a recipe shipped without a `or stop after N turns` cap.

**Brand-survival threshold:** single-user incident — one operator's multi-hundred-dollar runaway spike following a Soleur-suggested condition pattern is enough to break the trust contract. `requires_cpo_signoff: true` in this plan's frontmatter; CPO sign-off carried forward from brainstorm Phase 0.5 (single-user-incident triad: CPO + CLO + CTO all assessed).

**Defenses encoded in the plan:**
1. Every recipe (FR1.3) carries a hardcoded `or stop after N turns` clause with N ≤ 40.
2. The transcript-only evaluator gotchas section (FR1.2) appears BEFORE the recipe library — operator reads the failure-mode warning before reaching copy-paste recipes.
3. The API-budget disclosure (FR1.4) is mandatory and net-new for Soleur (no existing autonomous-skill SKILL.md ships this disclosure today; see Research Insights).
4. The AGENTS.md routing paragraph (FR2) prevents agents from proposing `/goal` retrofits into skills with existing stricter completion mechanisms — preventing future regression of this brainstorm's findings.
5. TR2 requires every recipe to be exercised in headless mode (`claude -p "/goal …"`) before merge — failure to converge in real use means the recipe is unshippable regardless of how good it reads.

## Domain Review (carry-forward from brainstorm)

**Domains relevant:** Engineering (CTO), Product (CPO), Legal (CLO).

### Engineering (CTO)

**Status:** reviewed (carry-forward from brainstorm Phase 0.5).
**Assessment:** Originally recommended retrofit of `test-fix-loop` as pilot. Brainstorm-time research falsified — `test-fix-loop` already has a deterministic exit-code gate that `/goal` would duplicate at higher cost. Still-load-bearing CTO contributions: (a) `/goal` should be treated as circuit-breaker / turn-cap, never as primary done-detection — encoded in FR1.3's "every recipe ends with `or stop after N turns`" requirement; (b) Skill-tool-invocation semantics are an unverified load-bearing assumption — encoded as FR4 spike. (c) hardcode condition templates per recipe, never expose `--goal "<custom>"` to operators — the recipe library IS the hardcoded-template set.

### Product (CPO) + Legal (CLO)

**Status:** reviewed (carry-forward from brainstorm Phase 0.5). CPO sign-off carried forward; no re-invocation at plan time per `requires_cpo_signoff` staging in plan skill Phase 2.6.

**Assessment (combined):** CPO requires operator-facing pre-flight disclosure before any autonomous loop — the docs page IS that disclosure surface (FR1.4). CLO confirms thin legal exposure under BSL 1.1 OSS distribution (operator-supplied API key, no merchant-of-record); the API-budget paragraph (FR1.4) is norms hygiene, not legal compliance. Both translate into a single FR1.4 requirement; no additional plan-time work.

## Open Code-Review Overlap

**None.** Queried `gh issue list --label code-review --state open` for matches against `plugins/soleur/AGENTS.md`, `plugin.json`, and `goal-primitive` — no open scope-outs touch the files this plan modifies.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| FR3.1: "declare CC min-version in `plugin.json` description field" | `description` is the marketing tagline used in plugin listings; polluting it with min-version is awkward. npm-convention `engines` field is forward-compatible and zero-surprise — but no sibling `.claude-plugin/plugin.json` in this repo declares an `engines` key. | **Pivot:** use `"engines": { "claude-code": ">=2.1.139" }` as a new top-level key. Note in PR body that this introduces a new (non-prior-art) convention; if CC ever validates `engines`, we are aligned. The docs page (FR3.2) still carries the human-readable requirement. |
| FR1: docs page path is `plugins/soleur/docs/pages/goal-primitive.md` | Eleventy templateFormats include both `md` and `njk`; existing pages mix conventions — `pages/legal/disclaimer.md` uses `permalink: legal/disclaimer/` (trailing-slash), `pages/getting-started.md` uses `permalink: pages/getting-started.html` (with `pages/` prefix + `.html`). A new `.md` page without explicit `permalink:` defaults to `/pages/goal-primitive/index.html`. | **Pin:** set explicit `permalink: goal-primitive/` (trailing-slash, no prefix) to mirror the `legal/` convention. Sibling pages with `pages/...html` permalinks are not retroactively fixed in this PR. |
| FR1.2: cite `hr-when-a-workflow-concludes-with-an` and quote canonical body | `AGENTS.md` index references the rule with `→ core`; body lives in `AGENTS.core.md` line ≈21 (verified via grep at plan time): "When a workflow concludes with an actionable next step, execute it — don't list it as 'next action' and stop. Use Playwright MCP, `xdg-open`, CLI tools, or APIs to drive completion. Only hand off for credentials/payment at the exact page." | **Quote verbatim** in the docs page's "Transcript-evaluator gotchas" section. Link by rule id, not by file path (so the cite survives if the sidecar split changes). |
| FR1.5: cross-ref `<promise>DONE</promise>` marker as Soleur-native | Confirmed via repo-research: `plugins/soleur/skills/one-shot/SKILL.md:151` references the marker; `plugins/soleur/hooks/stop-hook.sh:1-316` reads it from `last_assistant_message`. | Cite both file:line refs in the cross-reference paragraph. |

## Files to Create

- `plugins/soleur/docs/pages/goal-primitive.md` — the docs page (FR1, ~400–600 lines including all recipes).

## Files to Edit

- `plugins/soleur/AGENTS.md` — append soft-pointer H3 "Primitive Choice: /goal vs. Soleur Skills" under existing `## Command and Skill Naming Convention` H2 (line 74). ≤120 words. No new rule id. (FR2, TR4 — soft-pointer not hard rule.)
- `plugins/soleur/.claude-plugin/plugin.json` — add top-level `"engines": { "claude-code": ">=2.1.139" }` key. **Do NOT touch `description`** despite spec FR3.1's wording; reconciled in §Research Reconciliation. (FR3.1.)

**Files deliberately NOT edited:**
- `plugins/soleur/docs/_data/site.json` — verified at plan time: `site.nav` and `site.footerLegal` are marketing-site nav. The `/goal-primitive/` page is developer-tooling reachable via the AGENTS.md soft pointer; adding it to top-level marketing nav would clutter the homepage with no acquisition value. Consistent with `legal/*` page handling (most are footer-linked, not nav-linked).

## Implementation Phases

### Phase 0 — Spike: /goal from sub-skill semantics (≤10 min, FR4)

**Question:** does typing `/goal …` activate a goal that persists across a subsequent Skill-tool invocation of a Soleur skill?

**Pass/fail predicate:** after `/goal echo "spike-marker" appears in transcript or stop after 3 turns` in a fresh CC interactive shell, run `/goal` (no args). PASS if the status block shows the active condition; FAIL otherwise. Then invoke a trivial Soleur skill (`/soleur:help`) and re-run `/goal` — confirm the goal still shows. This proves the parent-session goal survives sub-skill invocation, which is what the docs need to be able to recommend.

**Why this is the right test, not the "can a sub-skill SET a goal" framing:** slash commands are frontend-processed, so a sub-skill body cannot itself emit `/goal`. The useful question is the inverse: can an operator set a goal at their top-level shell that bounds work done inside a Skill-tool-invoked Soleur skill? If yes (very likely), the docs recommend the operator-set-then-invoke pattern.

Record the outcome in one sentence; update §Recipe Set with shell-level invocations only. The plan does not commit to a "from-inside-skill set" pattern under any spike outcome.

### Phase 1 — Write docs page (FR1.1–1.5, TR3)

Create `plugins/soleur/docs/pages/goal-primitive.md` with this frontmatter:

```yaml
---
title: "/goal — Operator Escape Hatch for Ad-Hoc Autonomous Work"
description: "When to use Claude Code's /goal primitive vs. a Soleur skill, the transcript-only evaluator gotchas, and 6 vetted condition recipes with built-in turn caps."
layout: base.njk
permalink: goal-primitive/
---
```

Body structure:

1. **Hero** (matches existing `pages/legal/disclaimer.md` shape) — title + one-paragraph summary.
2. **What `/goal` is** — 2-paragraph summary distilled from https://code.claude.com/docs/en/goal: session-scoped, one active per session, Haiku evaluator after each turn reads transcript only (no tool access), cleared on `/goal clear` or `/clear`.
3. **When to use `/goal` vs. Soleur skills** (FR1.1) — decision matrix (markdown table). Three columns: "Situation" / "Use" / "Why". Rows include:
   - Recurring autonomous workflow with a verifiable end state → existing Soleur skill (`one-shot`, `test-fix-loop`, `drain-labeled-backlog`, etc.) → these have stricter completion mechanisms (exit codes, `<promise>DONE</promise>`, CLI-output checks).
   - One-off autonomous work without a dedicated skill (CHANGELOG drain, ad-hoc lint run, file-count budget enforcement) → `/goal` from your top-level shell.
   - Headless / CI autonomous loop with a verifiable condition → `claude -p "/goal …"`.
   - Pre-existing autonomous skill that you want to bound with an outer turn cap → the skill's own iteration cap; don't layer `/goal` (two stop hooks competing, see §Soleur-Native Alternative).
4. **The transcript-only evaluator gotchas** (FR1.2) — half-page section. Lead with: "`/goal`'s evaluator reads only what the main agent has surfaced in the conversation transcript. It cannot run tools, read files, or grep. Conditions written for tool-accessible evidence will silently never resolve `yes`." Then enumerate the failure class: cite Soleur's hard rule `hr-when-a-workflow-concludes-with-an` and quote: "When a workflow concludes with an actionable next step, execute it — don't list it as 'next action' and stop. Use Playwright MCP, `xdg-open`, CLI tools, or APIs to drive completion." Explain why this matters for `/goal`: a transcript-judging fast model reading "next action: deploy the build" can rule the goal achieved when nothing was deployed. Reference Soleur's documented incidents at high level (link to the brainstorm doc + learnings on pseudo-handoff). Land the practical rule: **every condition must name a structured marker (exit code, JSON array shape, file-existence/size, regex on captured CLI output) — never a fuzzy outcome.**
5. **What it consumes** (FR1.4) — API-budget disclosure paragraph. Single short paragraph: "Each turn the loop continues, you are billed for one main-model turn plus one Haiku evaluator turn against your Anthropic API key. A goal that never resolves `yes` will burn turns until you Ctrl+C. The recipes below ship with hardcoded `or stop after N turns` caps for this reason. Soleur does not bill or proxy these calls — Anthropic does, against the key in your Claude Code session." Cite Soleur LICENSE (BSL 1.1) AS-IS line for completeness.
6. **Vetted condition recipes** (FR1.3) — 6 recipes. Each as a fenced code block followed by 2–3 lines of explanation. See §Recipe Set below for exact text.
7. **Soleur-native alternative** (FR1.5) — half-page section explaining that Soleur skills already use `plugins/soleur/hooks/stop-hook.sh` (the ralph-loop Stop hook — Jaccard / hash-repetition / idle-classifier / `<promise>DONE</promise>` reader, cite `:316` and `last_assistant_message`) for in-skill completion. `/goal` is the SECONDARY, manual layer for ad-hoc work outside skills. Two stop hooks may coexist (the one that returns `decision: block` wins) but you should not layer them on the same workflow.
8. **Headless / CI usage** — `claude -p "/goal <condition>"` example with a real recipe. Interrupt-via-Ctrl+C note.
9. **Requirements** (FR3.2) — "Claude Code v2.1.139 or later. The `engines.claude-code` field in `plugins/soleur/.claude-plugin/plugin.json` declares this floor."
10. **Spike outcome** (FR4) — one paragraph reflecting Phase 0's actual result.

#### Recipe Set (FR1.3)

Each recipe MUST:
- Name a structured marker the Haiku evaluator can verify from transcript (exit code paired with a literal command output line, JSON array shape, file-existence/size, regex against captured stdout).
- Carry a hardcoded `or stop after N turns` clause with N ≤ 40.
- Be re-exercisable in headless mode (`claude -p "/goal <condition>"`) — Phase 4 verifies this.

| # | Name | Condition | Cap | Marker the evaluator reads |
|---|------|-----------|-----|----------------------------|
| 1 | Test gate | `the most recent test command exited with code 0 (confirmed by an explicit 'echo "exit=$?"' showing exit=0 in the transcript after the test ran), or stop after 15 turns` | 15 | Literal `exit=0` echo |
| 2 | Label-empty backlog | `the output of 'gh issue list --label needs-triage --state open --limit 100 --json number' is the literal "[]" (empty JSON array), or stop after 30 turns` | 30 | Literal `[]` in transcript |
| 3 | API migration sweep | `'rg -n "oldApi\(" src/ test/' produced no matches AND the most recent test command's 'echo "exit=$?"' showed exit=0, or stop after 40 turns` | 40 | grep silence + `exit=0` echo |
| 4 | Lint clean | `the most recent lint command exited with code 0 (confirmed by an explicit 'echo "exit=$?"' showing exit=0 in the transcript), or stop after 10 turns` | 10 | Literal `exit=0` echo |
| 5 | Size budget | `'wc -l src/feature/*.ts \| awk "$1 > 200 {print}"' produced no output (all files under 200 LOC), or stop after 25 turns` | 25 | awk empty output |
| 6 | File assembled | `the file knowledge-base/community/digests/$(date +%Y-W%V).md exists (confirmed by 'ls' showing its path) AND 'wc -c' of that file shows a byte count greater than 500, or stop after 12 turns` | 12 | ls listing + wc -c byte count |

**Why exit-code-only for recipes 1, 3, 4** (Kieran plan-review fix): real-world test runners and linters emit incompatible summary lines — ESLint default formatter on clean produces NO output, Biome clean is "No fixes applied", Prettier `--check` clean is "All matched files use Prettier code style!", pytest is "N passed in Xs" (no "0 failed"), bun test is "X pass / Y fail". A literal-summary clause that requires "0 failed" or "0 errors" will never match on these tools, causing the goal to burn through its cap on a clean codebase — the exact brand-survival failure mode the plan warns about. The canonical signal across all runners is the process exit code; `echo "exit=$?"` surfaces it as a structured literal the evaluator can verify.

**Why six recipes, not three or four** (DHH plan-review acknowledged): three of the six (#1, #3, #4) share the exit-code-echo pattern instantiated at different command surfaces. This is cookbook variety — copy-pasteable per use-case — not pattern repetition for its own sake. Recipes #2, #5, #6 each demonstrate a distinct marker shape (JSON array shape, command silent-on-success, file existence + size). Operators benefit from seeing the test/lint/sweep variants explicitly.

**Recipes deliberately NOT included:**
- "CHANGELOG has an entry for every PR merged this week" — requires the evaluator to cross-reference two pieces of evidence (a `gh pr list --search "merged:>YYYY-MM-DD"` JSON array AND the CHANGELOG content). Too easy to write a condition that doesn't produce both pieces in transcript every turn. Drop.

### Phase 2 — `plugins/soleur/AGENTS.md` routing paragraph (FR2, TR4)

Append under `## Command and Skill Naming Convention` (line 74), as a new H3:

```markdown
### Primitive Choice: /goal vs. Soleur Skills

Claude Code's `/goal` primitive (v2.1.139+) is a session-scoped completion-condition stop hook with a Haiku evaluator that reads only the conversation transcript. It is the right tool for **ad-hoc autonomous work outside dedicated Soleur skills** — operator-typed conditions, headless CI, one-off loops not worth building a skill for.

Do NOT propose `/goal` retrofits into existing autonomous Soleur skills (`one-shot`, `test-fix-loop`, `drain-labeled-backlog`, `resolve-todo-parallel`, `resolve-pr-parallel`, `work`). Each already uses a stricter, structurally-verifiable completion mechanism (exit codes, the `<promise>DONE</promise>` marker via `plugins/soleur/hooks/stop-hook.sh`, CLI-output checks). A transcript-only evaluator on top of those would duplicate at higher cost and reintroduce the pseudo-handoff failure class codified by hard rule `hr-when-a-workflow-concludes-with-an`. Operator-facing docs: `/goal-primitive/`.
```

Soft pointer; no new rule id (per spec TR4). This is gotcha-only content under the existing H2's purview (naming/identity disambiguation between Anthropic primitives and Soleur skills).

### Phase 3 — `plugin.json` engines field (FR3.1)

Edit `plugins/soleur/.claude-plugin/plugin.json` to add a top-level `engines` key after `license`:

```json
"license": "BUSL-1.1",
"engines": {
  "claude-code": ">=2.1.139"
},
"keywords": [
```

Do NOT modify the `description` field. Note the new convention in the PR body — no other `.claude-plugin/plugin.json` in this repo declares `engines` today.

### Phase 4 — Recipe headless verification (TR2)

For each recipe, run `claude -p "/goal <condition>"` in headless mode against the specific known-true setup named below. The goal must resolve `yes` within ≤2 turns. >2 turns means the marker is not transcript-verifiable as written.

| # | Known-true setup |
|---|------------------|
| 1 | Use a test directory known to pass: e.g., `bun test plugins/soleur/test/components.test.ts && echo "exit=$?"`. Recipe must resolve after the first test+echo turn. |
| 2 | Pick a label known to have zero open issues: verify `gh issue list --label <label> --json number` returns `[]` before the spike. Throwaway labels (`spike-test`) work; pre-create and ensure empty. |
| 3 | Substitute `oldApi` with a unique-prefix string guaranteed-absent from the codebase (e.g., `__GOAL_SPIKE_NEVER_EXISTS__`); pair with a known-passing test. |
| 4 | Pick a small directory known to be lint-clean (e.g., `plugins/soleur/skills/help/`) and scope the project's lint command to it. |
| 5 | Use `wc -l plugins/soleur/skills/help/SKILL.md \| awk '$1 > 200 {print}'` — `help/SKILL.md` is small enough that awk emits nothing. |
| 6 | Pre-create the marker file: `mkdir -p /tmp/spike-test && printf '%501s\n' "x" > /tmp/spike-test/file.md` (pads to ≥501 bytes); adjust recipe path to `/tmp/spike-test/file.md` for the spike. |

Record outcomes inline (not committed). If a recipe fails to converge in ≤2 turns on its setup, fix the recipe text. If unfixable, drop it — spec FR1.3 requires 4–6, so shipping 5 is acceptable.

### Phase 5 — Build verification + ship

1. From the worktree, `npm install` (per docs-site authoring learning — worktrees can be missing `node_modules`).
2. `cd <repo-root> && npx @11ty/eleventy` (per `plugins/soleur/docs/package.json` build script).
3. Confirm `_site/goal-primitive/index.html` exists.
4. Open the rendered page locally; verify hero + 10 body sections render under `base.njk` layout.
5. `git status` and commit per the Plan-skill `Save Tasks` flow.

## Acceptance Criteria

### Pre-merge (PR)

Reviewer-mandated load-bearing gates only — pure-substring spec-by-grep ACs were dropped during plan review as theater (DHH + Simplicity converged). The ACs below each correspond to a real failure mode the operator could trip.

- [ ] **(FR1.3, Phase 1 + Phase 4)** Docs page ships 4–6 recipes, each with `or stop after N turns` where N ≤ 40, AND each recipe converges in ≤2 turns on its Phase 4 known-true setup. Verified by `n=$(grep -cE 'or stop after [0-9]+ turns' plugins/soleur/docs/pages/goal-primitive.md); test "$n" -ge 4 && test "$n" -le 6 && test "$(grep -oE 'stop after [0-9]+' plugins/soleur/docs/pages/goal-primitive.md | grep -oE '[0-9]+' | sort -n | tail -1)" -le 40` AND Phase 4 convergence recorded in PR body checklist (one line per recipe).
- [ ] **(FR1.2, FR1.4, FR1.5, Phase 1 + Phase 5)** Docs page contains, in order: (i) transcript-evaluator gotchas section citing `hr-when-a-workflow-concludes-with-an` with the canonical rule body quote, (ii) API-budget disclosure paragraph (Anthropic API + your key + billed-by-Anthropic-not-Soleur), (iii) Soleur-native cross-reference to `plugins/soleur/hooks/stop-hook.sh` and the `<promise>DONE</promise>` marker. Verified by single visual checklist during Phase 5 review (one human read beats three brittle grep ACs).
- [ ] **(FR2, Phase 2)** `plugins/soleur/AGENTS.md` contains the new H3 routing paragraph with body 50–120 words. Verified by `awk '/^### Primitive Choice: \/goal/{flag=1; next} /^### /{flag=0} /^## /{flag=0} flag' plugins/soleur/AGENTS.md | wc -w` returning a value in [50, 120]. (Range pattern anchored to terminate on the next H3 or H2, not the start-of-range line — fixes the awk bug surfaced at plan review.)
- [ ] **(FR3.1, Phase 3)** `plugins/soleur/.claude-plugin/plugin.json` parses as valid JSON AND declares the CC min-version floor. Verified by `jq -r '.engines."claude-code"' plugins/soleur/.claude-plugin/plugin.json` returning exactly `>=2.1.139`.
- [ ] **(TR1)** No new code/hook/script/wrapper lands. Verified by `git diff --name-status origin/main..HEAD | grep -E '^A.*\.(sh|ts|js|py|rb)$'` returning empty.
- [ ] **(TR3, Phase 5)** Docs page renders. Verified by `test -s _site/goal-primitive/index.html` after `npx @11ty/eleventy`.

### Post-merge (operator)

- [ ] **None required.** Docs land at merge; no Terraform apply, no migration, no external-service config. (Per plan-skill automation-feasibility gate: docs deployment is handled by the existing `deploy-docs.yml` GitHub Action on push to main; no operator action needed.)

## Test Strategy

- **Docs page rendering:** Phase 5 build verification gates merge. No unit tests.
- **Recipe validity:** Phase 4 headless verification gates merge. Each recipe is exercised against a controlled known-true scenario.
- **AGENTS.md edit byte budget:** Phase 2 enforces ≤120 words inline (AC verifies). `plugins/soleur/AGENTS.md` is 11,707 bytes pre-edit (per plan-time `wc -c`); the routing paragraph adds ≈100 words ≈ 700 bytes → post-edit ≈12,400 bytes. Well under any plausible budget.
- **`plugin.json` JSON validity:** Phase 3's jq AC enforces this. A bad JSON would also break plugin loading at session start.
- **No regression to existing autonomous skills:** TR1 forbids edits to `plugins/soleur/skills/*/SKILL.md` for autonomous skills. Verified by `git diff --stat origin/main..HEAD -- 'plugins/soleur/skills/{one-shot,test-fix-loop,drain-labeled-backlog,resolve-todo-parallel,resolve-pr-parallel,work}/'` returning empty.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| One or more recipes fail Phase 4 verification (marker not readable from transcript as written — Kieran identified this against earlier "0 errors" literal-summary form). | Medium | Low-medium | Phase 4 gates merge on per-recipe convergence with explicit known-true setups (table). Failure → rewrite or drop; FR1.3 allows 4–6, so shipping 5 is acceptable. |
| Operators read the recipe library, write their own conditions in the same shape, omit the turn cap, and burn API budget. | Medium | High (single-user incident) | This IS the brand-survival threshold. Mitigations baked in: (a) gotchas section precedes the recipe library; (b) every shipped recipe ships with a hardcoded cap; (c) API-budget disclosure mandatory and net-new for Soleur. Residual risk accepted — docs can only inform; cannot prevent operator copy-modify-without-cap. |

## Sharp Edges

- When updating `plugins/soleur/AGENTS.md`, do not rename or relocate the H2 `## Command and Skill Naming Convention` heading; the FR2 routing paragraph is sited beneath it. If H2 reorganization happens, re-anchor.
- The `engines.claude-code` key (Phase 3) is non-prior-art. If a reviewer requests a different shape (e.g., a top-level `claudeCodeMinVersion` string), apply the change and propagate to the docs page (FR3.2) AND to the FR3.1 AC (the `jq` query needs to match).
- Recipes must use single-quoted shell strings inside the goal condition where they include shell-fragile characters (`$`, `\`, `*`) — `claude -p "/goal '...'"` with appropriate shell escaping. Verify under Phase 4.
- A reviewer might propose adding a `--goal "<custom>"` escape-hatch argument to one of the existing autonomous skills. **This violates the spec's Non-Goal.** Decline with: "We're shipping `/goal` as the escape hatch FOR ad-hoc work that doesn't fit a skill; layering it onto a skill that already has a stricter mechanism is the retrofit pattern this brainstorm rejected."
- Phase 4 (recipe headless verification) is an in-session test with the known-true setups named in the table, not a committed artifact. If the verifying engineer skips it ("recipes look right"), the brand-survival defense layer is compromised. Treat Phase 4 as a merge gate.
- Recipe condition strings emit `echo "exit=$?"` as a structured signal — the `exit=0` literal IS the marker. Do NOT rewrite recipes to require an additional literal-summary line ("0 errors", "0 failed") — real-world runners (ESLint clean → empty, Biome → "No fixes applied", pytest → "N passed", bun test → "X pass / Y fail") emit incompatible summaries, and the conjunction would cause the goal to burn its cap on a clean codebase. Exit code is the only canonical signal across runners.

## Research Insights

**From brainstorm Phase 0.5 + 1.1** (carry-forward — see `knowledge-base/project/brainstorms/2026-05-15-goal-primitive-operator-escape-hatch-brainstorm.md`):
- `plugins/soleur/hooks/stop-hook.sh` is a 316-line ralph-loop Stop hook (Jaccard, hash-repetition, idle-classifier, crash-orphan TTL, PPID scoping) — Soleur's existing equivalent of `/goal`.
- `one-shot` uses `<promise>DONE</promise>` marker (`SKILL.md:151`) read via `last_assistant_message` hook API.
- `test-fix-loop` uses deterministic exit codes (`SKILL.md:48-104`); rollback via checkpoint commits.
- 4 documented Soleur pseudo-handoff incidents codify hard rule `hr-when-a-workflow-concludes-with-an` (canonical citation for FR1.2 quote).

**From plan-time research** (this session):
- `plugins/soleur/AGENTS.md` insertion anchor: under `## Command and Skill Naming Convention` (line 74) as new H3.
- `plugin.json` has no prior `engines`-style key in any sibling `.claude-plugin/plugin.json` — Phase 3 introduces a new convention; flag in PR body.
- Eleventy permalink convention is inconsistent (`pages/legal/*.md` uses `permalink: legal/<name>/`; `pages/getting-started.md` uses `permalink: pages/getting-started.html`). New page pins to the `legal/`-style convention with `permalink: goal-primitive/`.
- Hard rule body for `hr-when-a-workflow-concludes-with-an` is at `AGENTS.core.md:21` (grep'd at plan time).
- API-budget disclosure is net-new for Soleur — only `one-shot` (`SKILL.md:25`, wall-clock duration) and `work` (`SKILL.md:210-216`, tier-cost framing) come close. File follow-up issue to backport an API-budget operator preamble to the five autonomous-loop skills lacking it; out of scope for this PR.

**From functional-discovery**:
- No community registry plugin solves "curated `/goal` condition recipes with built-in caps" — the niche is unoccupied. Wrapper-skills exist (`chrischabot/claude-code-goal`, `itsuzef/goalkeeper`) but they compete with `/goal` rather than document it. Ship our own.

**From learnings-researcher**:
- Eleventy worktree gotchas: `_data/agents.js` uses a relative path that doubles in worktrees — verify by reading + grep rather than running a full build inside the worktree, or `cd <repo-root>` first. Encoded in Phase 5.
- Run `npm install` in the worktree before building — encoded in Phase 5.

## Deferred Items / Follow-up Issues

Filed as a separate GitHub issue at PR-ready time:

1. **Backport API-budget operator preamble to autonomous-loop skills** — `test-fix-loop`, `drain-labeled-backlog`, `resolve-todo-parallel`, `resolve-pr-parallel`, `work`, `one-shot` (the last has wall-clock duration only). Each should gain a one-paragraph "this consumes your Anthropic API key" disclosure aligned with the convention this PR establishes for `/goal`. Milestone: Post-MVP / Later.

(Earlier draft included two more deferred items — permalink-convention reconciliation and CC engines-validation in ship preflight — both dropped during plan review as "let's not forget" notes that don't warrant their own issue.)
