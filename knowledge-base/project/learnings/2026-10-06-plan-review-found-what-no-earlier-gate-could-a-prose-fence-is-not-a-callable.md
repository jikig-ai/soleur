---
title: Plan review found four holes no earlier gate could see, and a prose fence is not a callable
date: 2026-10-06
category: workflow-patterns
module: plugins/soleur/skills/plan
tags: [plan-review, preflight, check-10, skill-body-budget, eleventy, self-certification, subagent-claims, issue-9578, issue-9577]
issue: 9578
---

# Learning: plan review found four holes no earlier gate could see

## Problem

Planning #9578 (founder-stated acceptance check) and #9577 (homepage fan-out demo) produced two plans whose first drafts each carried a hole that research, spec-flow and the scope gate all passed. The six-seat plan-review panel found them. Four are reusable.

## Solution and key insights

1. **Every lifecycle SKILL.md body sits at its ceiling, so new prompt text cannot go in the body.** `plugins/soleur/test/skill-body-budget.json` leaves brainstorm 125 B, plan 136 B, qa 8 B, work 240 B and ship 5 B of headroom, and ceilings only ratchet down in a separate reviewed PR. New prompt text goes in a `references/` file with a one-line pointer; a new gate goes in an uncapped skill (preflight). The description budget (`SKILL_DESCRIPTION_WORD_BUDGET`, 2413/2413) is a different budget that counts only frontmatter `description:` words, so a body edit does not spend it. Measure both at plan time.
2. **"Reuse the sandbox" is not a function call.** Preflight Step 10.5 is a prose fence an agent follows, with its own `exit 0` branches, a Check 10 sentinel string and no rc/stdout hand-off. To reuse it from a second check, run the fence inside `OUT=$( … )` so its exits end only the subshell, append the rc and stdout, map the output, and drop the Check 10-labelled sentinel lines so fleet telemetry does not count the second check's dark runs as Check 10's. Never copy `BWRAP_ARGS=(`: a second assembly is the chokepoint-narrower-than-property class.
3. **An approved check that runs a script the agent writes during the work is the agent certifying itself.** Freezing the command string with a hash does not see it: `bash scripts/new-check.sh` is accepted by the verb allowlist, the script is absent at the baseline for the right-looking reason, and the work then writes a script that prints the expected string. Interpreter verbs need the script's blob hash pinned at freeze, and "will be created" paths are only allowed with non-interpreter verbs.
4. **A new check that is not path-gated widens the execution trigger.** Check 10 is gated on sensitive-path diffs; a new check that runs on every diff would execute a contributor's PR-head plan on the operator's machine with no prompt. Anchor authorship to the local operator (freeze commit author email, PR author login) and show-before-run otherwise. A self-consistent hash proves nothing when the same diff writes both sides.
5. **An Eleventy data module must be default-export-only.** Eleventy unwraps the default export only when it is the module's sole export; a second named export (for a shared validator) makes the template receive the export object, skips the function and its throw, and renders an empty section on a green build. Put shared code in a non-data module and test by calling the default export.

## Session Errors

1. **Research subagent asserted "no spec or brainstorm exists for #9578" and gave wrong line numbers (types.ts status union at "~220", real 634)** — Recovery: re-verified every cited fact against the code before use — Prevention: treat a research subagent's specifics (paths, line numbers, absence claims) as leads, not facts; verify each one that the plan will cite. Same class as `2026-10-06-a-researcher-named-the-hosted-app-as-the-self-hosted-surface-and-agent-written-docs-reached-ci-unlinted.md`.
2. **Plan text claimed an overlap-check result before the query was run** — Recovery: ran the query and rewrote the sentence — Prevention: write a result sentence only after the command that produces it has run; a skeleton line that says "results are recorded in X" is a claim.
3. **First plan draft prose tripped `lint-infra-no-human-steps.py` (a founder-actor word beside "mount"/"exec" wording)** — Recovery: reworded the guard text — Prevention: run the plan lints (`lint-guard-contract.py`, `lint-infra-no-human-steps.py`, markdownlint) before committing a plan, not after.
4. **`gh issue create` was refused by the filing hook (no consequence line) and again when wrapped in `$(…)`** — Recovery: added `Mandated-By: wg-when-deferring-a-capability-create-a` on its own line and ran each filing as its own call — Prevention: deferral filings carry the `Mandated-By` line from the first attempt.
5. **A foreground `sleep` to wait for background agents was blocked, and ending a turn with "waiting for X" tripped the unkept-promise stop hook** — Recovery: waited on task notifications and acted in-turn — Prevention: do not poll with sleep; when waiting on notifications, do the independent work first.
6. **Plan v1 (#9578) assumed Step 10.5 could be run "unchanged with CMD set", that `creates:` was safe, and that freeze ordering by directory list would hold on real branches** — Recovery: plan-review found all three; the plan was revised — Prevention: for any "reuse X" claim, read X's exits and inputs before writing it; for any frozen-text design, enumerate who can write the text the frozen command points at.
