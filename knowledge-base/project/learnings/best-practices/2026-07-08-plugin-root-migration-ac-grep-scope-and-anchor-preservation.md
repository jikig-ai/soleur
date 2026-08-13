---
module: plugins/soleur/skills
date: 2026-07-08
problem_type: workflow_gap
component: skill_definitions
symptoms:
  - "migration-completeness AC-grep false-positives on reference/test docs"
  - "plan-prose count (files vs families) drifts off-by-one"
severity: low
root_cause: verification_scope_and_count_derivation
tags: [plugin-root, migration, ac-grep-scope, anchor-preservation, adr-093, slice-d]
synced_to: [work, plan]
issue: 6154
superseded_by: 7450
superseded_date: 2026-08-12
---

> ## ⛔ SUPERSEDED 2026-08-12 by #7450 / ADR-179 — read this before item 2
>
> **The anchor guidance below is REVERSED. Do not follow items 2, 3 or 4.**
>
> This file is `synced_to: [work, plan]`, so an agent retrieves it mid-task. Item 2 says
> *"Preserve the EXACT original fallback anchor per site — never homogenize"* and names
> `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}` as the correct
> form **for the three redaction gates specifically**. That construct is the #7450 vector:
> `review/SKILL.md` instructs `gh pr checkout`, so on the review path the git root is the
> **contributor's** tree, and the gate whose exit code decides whether secrets are emitted
> resolved its own scanner from there.
>
> **The canonical form is now the bare, quoted `${CLAUDE_PLUGIN_ROOT}/<payload-relative-path>`
> with NO fallback arm at all**, plus the ADR-179 decision-2 identity preflight. `:-` and
> `:?` are both rejected. See ADR-179 and its 2026-08-12 amendment.
>
> Item 4's server-safety argument is sound and was never the issue — it reasons about the
> hosted Concierge factory, where `CLAUDE_PLUGIN_ROOT` is always injected. The vector is the
> **local CLI review path**, which item 4 does not consider.
>
> The body is retained unedited as the record of what was believed and why. The plan for
> #7450 flagged this file as superseded and predicted this exact failure; it was not
> updated at the time, which is the gap this banner closes.


# Learning: `${CLAUDE_PLUGIN_ROOT}` family-migration — AC-grep scope, anchor preservation, files-vs-families counts

## Problem

Slice D of ADR-093 (#6154) migrated 14 residual agent-run skill families off CWD-relative
`bash ./plugins/soleur/…/<script>.sh` (and `python3 …/x.py`) shell-outs to the deployment-anchored
`${CLAUDE_PLUGIN_ROOT:-<preserved-anchor>}/…` form. The migration itself is mechanical, but three
non-obvious traps surfaced — two at multi-agent review, one at verification time.

## Solution / Reusable Insights

1. **Scope the migration-completeness grep to SKILL.md invocation sites, not the whole family dir.**
   A naive `git grep -nE '(bash|python3?|sh)[[:space:]]+…/scripts/…\.(sh|py)' -- <family-dirs>` (the
   plan's AC1-EXT as literally written) false-positives on:
   - `skills/skill-creator/references/*.md` — upstream teaching-doc examples like `python scripts/validate.py`
     (illustrative, NOT the skill's own operational invocations; `python` matches `python3?`);
   - `*.test.sh`, internal `scripts/*.sh` calling sibling scripts, and `workflows/*.workflow.js` prose.
   Restrict the verification grep to `plugins/soleur/skills/*/SKILL.md` (or filter `-v /references/ -v /test/
   -v '/scripts/[^:]*:' -v /workflows/`). The plan is authoritative for the AC's *intent*, never its exact
   command (`hr-when-a-plan-specifies-relative-paths-e-g`).

2. **[SUPERSEDED by #7450 — see the banner. This instruction is now REVERSED.]** **Preserve the EXACT original fallback anchor per site — never homogenize.** Three anchor classes,
   each with a verbatim precedent:
   - git-root (the 3 redaction gates: legal-generate, incident, linear-fetch) →
     `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}` (precedent `compound/SKILL.md:289`), **quote the whole expansion**;
   - `./` anchor → `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` (precedent `brainstorm/SKILL.md:608`);
   - bare → `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` (precedent `brainstorm/SKILL.md:431`).
   The Slice C drift-guard (`plugin-root-list-carveout-coupling.test.ts`) and the migration convention key on
   preserved anchors; a homogenized default is a defect. Non-`skills/` plugin scripts keep their shape
   (`plan:329` → `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/scripts/taste-profile-update.sh`, no `/skills/`).

3. **[SUPERSEDED by #7450 — the git-root fallback is removed entirely; the `[[ -r ]]` pre-check survives and was extended with an identity preflight.]** **Redaction gates get the git-root fallback + a fail-closed `[[ -r ]]` pre-check.** legal-generate already
   had `[[ -r "$SENTINEL" ]] || exit 2`; incident (which *owns* redact-sentinel.sh) did not — a review-caught
   asymmetry. On a redaction gate, mirror the pre-check so a missing script maps to the documented exit-2 halt
   rather than an undocumented 127. All three gates fail closed, so a broken migration degrades safely.

4. **[SCOPED by #7450 — true for the hosted Concierge factory, and it is not the threat surface. The vector is the local CLI review path.]** **Server-safety invariant (why the `$(…)` fallback is safe):** `CLAUDE_PLUGIN_ROOT` is always injected on
   both Concierge factories (`agent-env.ts`; `assertTrustedPluginPath` chokepoint), so `${CLAUDE_PLUGIN_ROOT:-…}`
   → the deployed root on-server and the `$(git rev-parse …)` default **never executes there**. It also never
   needs a `safe-bash.ts` carve-out — both `$(` and `${` trip `SHELL_METACHAR_DENYLIST` and route through the
   review gate. Zero `safe-bash.ts` change is the correct outcome.

5. **`${CLAUDE_PLUGIN_ROOT}` cannot anchor repo-root `scripts/`.** `generate-kb-index.sh` (repo-root, not
   plugin-deployed) is a decoy — leave it untouched; scope the ADR "CLOSED" claim to plugin-deployed shell-outs
   in the enumerated families and file the residual repo-root class + `taste-profile-update.sh` siblings as a
   tracked follow-up (#6222), never implied-closed.

## Session Errors

1. **Plan/ADR count drift "15" vs actual 14 families.** The plan prose and the ADR amendment carried "15 SKILL.md
   files / 15 enumerated families"; the enumerated set is **14 families** (15 = 14 family SKILL.md + 1 ADR = 15
   *files*). Caught at review by `code-quality-analyst` (P2); fixed in the ADR, the plan (7 sites), and issue #6222.
   **Prevention:** derive counts written into artifacts from the as-written file, not plan-prose estimates
   (existing work-skill rule; a `git diff --name-only origin/main | wc -l` at ship time would have caught it).
2. **incident redaction gate lacked the `[[ -r ]]` fail-closed pre-check** its sibling legal-generate has.
   **Prevention:** when migrating a redaction/secret gate, sweep sibling gates for guard parity (see insight 3).
3. **AC1-EXT grep, scoped to the whole family dir, false-positived** on `references/*.md` teaching examples.
   **Prevention:** scope migration-completeness greps to SKILL.md invocation sites (see insight 1).

## Cross-references

- [[2026-07-07-drift-guard-extraction-must-mirror-production-checker-boundaries-and-all-emission-shapes]] — Slice C precedent (the drift-guard extraction boundaries).
- ADR-093 (Slices A–D) — the SDK-plugin-source-is-platform-deployed decision this migration completes.
- Follow-up #6222 — the two residual vectors this PR does not close.
