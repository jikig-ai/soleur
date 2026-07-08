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
---

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

2. **Preserve the EXACT original fallback anchor per site — never homogenize.** Three anchor classes,
   each with a verbatim precedent:
   - git-root (the 3 redaction gates: legal-generate, incident, linear-fetch) →
     `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}` (precedent `compound/SKILL.md:289`), **quote the whole expansion**;
   - `./` anchor → `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` (precedent `brainstorm/SKILL.md:608`);
   - bare → `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` (precedent `brainstorm/SKILL.md:431`).
   The Slice C drift-guard (`plugin-root-list-carveout-coupling.test.ts`) and the migration convention key on
   preserved anchors; a homogenized default is a defect. Non-`skills/` plugin scripts keep their shape
   (`plan:329` → `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/scripts/taste-profile-update.sh`, no `/skills/`).

3. **Redaction gates get the git-root fallback + a fail-closed `[[ -r ]]` pre-check.** legal-generate already
   had `[[ -r "$SENTINEL" ]] || exit 2`; incident (which *owns* redact-sentinel.sh) did not — a review-caught
   asymmetry. On a redaction gate, mirror the pre-check so a missing script maps to the documented exit-2 halt
   rather than an undocumented 127. All three gates fail closed, so a broken migration degrades safely.

4. **Server-safety invariant (why the `$(…)` fallback is safe):** `CLAUDE_PLUGIN_ROOT` is always injected on
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
