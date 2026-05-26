---
title: "Tasks: /goal Primitive as Operator Escape Hatch"
status: ready
date: 2026-05-15
lane: cross-domain
related_plan: knowledge-base/project/plans/2026-05-15-feat-goal-primitive-operator-escape-hatch-plan.md
related_issue: 3813
related_pr: 3809
---

# Tasks: /goal Primitive as Operator Escape Hatch

## Phase 0 — Spike: /goal across Skill-tool sub-invocation (≤10 min)

- 0.1 In a fresh CC interactive shell, run `/goal echo "spike-marker" appears in transcript or stop after 3 turns`, then `/goal` (no args). Confirm status block shows the active condition.
- 0.2 In the same session, invoke `/soleur:help` (or any trivial Soleur skill via the Skill tool). After the skill returns, re-run `/goal` and confirm the goal is still active.
- 0.3 Record one-sentence outcome in the engineer's scratch notes (not committed). The recipe library is shell-level regardless of outcome; this spike confirms the operator-set-then-invoke pattern is viable.

## Phase 1 — Write `plugins/soleur/docs/pages/goal-primitive.md` (FR1.1–1.5, TR3)

- 1.1 Create the file with frontmatter `title`, `description`, `layout: base.njk`, `permalink: goal-primitive/`.
- 1.2 Write hero section (matches `pages/legal/disclaimer.md` shape) and one-paragraph summary.
- 1.3 Write "What `/goal` is" section (2 paragraphs from the upstream CC docs, paraphrased).
- 1.4 Write "When to use /goal vs. Soleur skills" decision matrix table (FR1.1) — 4+ rows, columns Situation / Use / Why.
- 1.5 Write "Transcript-only evaluator gotchas" section (FR1.2) — leads with the transcript-only constraint, cites `hr-when-a-workflow-concludes-with-an` by id, quotes the canonical body from `AGENTS.core.md`, references Soleur's documented pseudo-handoff incidents at high level. Land the practical rule: every condition names a structured marker.
- 1.6 Write "What it consumes" API-budget disclosure paragraph (FR1.4) — operator-supplied Anthropic key, billed by Anthropic not Soleur, recipes carry hardcoded caps for this reason. Cite BSL 1.1 AS-IS line for completeness.
- 1.7 Write "Vetted condition recipes" section (FR1.3) — 6 recipes per the table in the plan. Each as a fenced code block + 2-3 lines of explanation. Each recipe names a transcript-verifiable marker (exit-code echo, JSON literal, command silence, file existence + size) and ends with `or stop after N turns` with N ≤ 40.
- 1.8 Write "Soleur-native alternative" section (FR1.5) — cross-references `plugins/soleur/hooks/stop-hook.sh:1-316` (ralph-loop heritage: Jaccard / hash-repetition / idle-classifier / `<promise>DONE</promise>` reader) and `plugins/soleur/skills/one-shot/SKILL.md:151` (marker emission). Positions `/goal` as the secondary, manual layer for ad-hoc work outside skills.
- 1.9 Write "Headless / CI usage" section — `claude -p "/goal <condition>"` example using one of the recipes; Ctrl+C interrupt note.
- 1.10 Write "Requirements" section (FR3.2) — Claude Code v2.1.139+. References `engines.claude-code` in plugin.json.
- 1.11 Write "Spike outcome" section (FR4) — single paragraph reflecting Phase 0 result.

## Phase 2 — `plugins/soleur/AGENTS.md` routing paragraph (FR2, TR4)

- 2.1 Locate `## Command and Skill Naming Convention` (currently at line ≈74).
- 2.2 Append new H3 `### Primitive Choice: /goal vs. Soleur Skills` under that H2.
- 2.3 Write paragraph body (50–120 words) per the template in plan §Phase 2. Soft pointer; no new rule id; points operators at `/goal-primitive/`.
- 2.4 Verify with the AC awk command: `awk '/^### Primitive Choice: \/goal/{flag=1; next} /^### /{flag=0} /^## /{flag=0} flag' plugins/soleur/AGENTS.md | wc -w` returns a value in [50, 120].

## Phase 3 — `plugin.json` engines field (FR3.1)

- 3.1 Edit `plugins/soleur/.claude-plugin/plugin.json` to add `"engines": { "claude-code": ">=2.1.139" }` after the `license` key.
- 3.2 Verify JSON validity: `jq -e . plugins/soleur/.claude-plugin/plugin.json > /dev/null`.
- 3.3 Verify field value: `jq -r '.engines."claude-code"' plugins/soleur/.claude-plugin/plugin.json` returns `>=2.1.139`.

## Phase 4 — Recipe headless verification (TR2)

- 4.1 For recipe #1 (test gate): run against the known-true setup from plan §Phase 4 table, row 1. Confirm `/goal` resolves in ≤2 turns. Record outcome.
- 4.2 For recipe #2 (label-empty backlog): same; row 2 of the table.
- 4.3 For recipe #3 (API migration sweep): same; row 3.
- 4.4 For recipe #4 (lint clean): same; row 4.
- 4.5 For recipe #5 (size budget): same; row 5.
- 4.6 For recipe #6 (file assembled): same; row 6 (includes the `printf` padding command).
- 4.7 If any recipe fails to converge in ≤2 turns, rewrite the recipe in `goal-primitive.md` and re-verify. If unfixable, drop it (FR1.3 allows 4–6).

## Phase 5 — Build verification + ship

- 5.1 `npm install` in the worktree (per docs-site authoring learning).
- 5.2 `cd <repo-root> && npx @11ty/eleventy` to build the docs site.
- 5.3 Confirm `_site/goal-primitive/index.html` exists with non-zero size.
- 5.4 Open the rendered page locally; verify hero + body sections render under `base.njk` layout.
- 5.5 Single visual review covering FR1.2 (gotchas section + rule citation), FR1.4 (API-budget paragraph), FR1.5 (cross-ref to stop-hook.sh + `<promise>DONE</promise>`).
- 5.6 Verify all acceptance criteria from the plan.
- 5.7 File the deferred follow-up issue: "Backport API-budget operator preamble to autonomous-loop skills" — milestone Post-MVP / Later.
- 5.8 Mark PR #3809 ready for review; trigger `/soleur:ship`.
