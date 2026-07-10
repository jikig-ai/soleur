---
title: "Self-referential Grok fidelity (Phase C #6323 / epic #6320): using /go under Grok to harden go.md routing contract + spawn_subagent + eval-harness Grok arm"
date: 2026-07-11
category: workflow-patterns
tags: [grok-build, harness-adapter, self-referential, one-shot, go-routing, eval-gate, spawn_subagent, slash-command, workflow-self-hosting, fidelity, compound, worktree, 6320, 6323, 6329]
source_issue: "#6323"
source_pr: "#6329"
related_epic: "#6320"
---

# Self-referential Grok fidelity: /go (Grok harness) ships the Grok arm for /go + spawn_subagent contract

## Problem

Phase C of the Grok Build fidelity epic (#6320, feature #6323) required reinforcing the "never improvise" rule, making the Grok slash-command entrypoint (`/go`, not `/soleur:go`) and `spawn_subagent` (not Task) contract explicit in `plugins/soleur/commands/go.md`, plus adding Grok arm documentation to the eval-harness (SKILL.md + promptfooconfig.go-routing.yaml). 

Critically, this work was executed self-referentially: the changes were planned, implemented, and documented by invoking `/go 6320 implement and ship the next open feature` (resolving to Phase C #6323) inside the `feat-one-shot-6323-grok-phase-c` worktree under the Grok Build harness (draft PR #6329). The routing contract being hardened was the exact mechanism used to produce the hardening.

Without strict adherence, this creates a bootstrap paradox and risk of divergence (Claude surfaces leaking into Grok sessions or vice-versa). The session also surfaced a P3 review item around plan vs. landed scope (adapter fidelity was pre-existing from Phase B; this phase was prose + docs arm).

## Root cause / Insight

- **Harness adapter contract** (`plugins/soleur/lib/harness.ts`): `detectHarness()` (GROK_* env markers + process.title/argv heuristics, guarded to avoid test false-positives) drives `invokeSkill` → slash_command + `spawnAgent` → spawn_subagent for Grok. `routingInstructions()` emits the exact table text embedded in go.md. Hardcoding `soleur:` or `Task` under Grok is the silent failure mode.

- **.grok/plugins distinction**: `.grok/plugins/soleur` is a *symlink* (`../../plugins/soleur`) + project config in `.grok/config.toml` (paths + enabled). Sources of truth are always under `plugins/soleur/`; `gated-skills.json` and projection scripts reference canonical `plugins/` paths. `.grok/` provides the Grok-native plugin loading surface (analogous to `claude --plugin-dir`), not a parallel source tree. Editing under `.grok/` would be overwritten or diverge.

- **Eval-gate + self-ref pattern**: The routing table lives behind `<!-- eval-gate:block:go-routing:start -->` ... `:end` sentinels in go.md. This is mechanically projected into skill-arm prompts for promptfoo (via extract/gen). The Grok arm doc + self-ref paragraph ("This document + the eval-harness Grok arm were produced and shipped by invoking `/go ...` inside worktree `feat-...` (draft PR #6329)") makes the contract live and verifiable. Edits to the block are now gated.

- **Workflow self-hosting**: Using the fidelity feature to ship the fidelity feature exercises the "never improvise" + harness dispatch loop in production (the agent's own session). This is only safe because go.md Step 0/1 gates (repo readiness, worktree, bare-repo guards), Step 2.0 harness adapter, and AGENTS.md rules (hr-*, wg-at-session-start-*, never read bare in worktree, use absolute paths) were already in place or reinforced.

- **Plan reconciliation gotcha**: Self-produced plans must be updated post-review for accuracy (see landed-scope note in the 2026-07-11 plan). Overclaiming functional deltas (e.g., "new harness changes") when only prose + arm docs landed triggers P3s.

- Framework insight: fidelity between harnesses is not "add a column" — it is an enforceable routing contract + projection + test arm + living self-reference + compound capture.

Root cause of prior divergence: implicit "Claude is default" in docs + routing sites + lack of Grok-specific golden assertions.

## Fix / Pattern

1. **Explicit contract in go.md** (Step 2.0 Harness adapter):
   - Table: Grok row uses `/<skill>` + `spawn_subagent` + entry `/go`.
   - "Routing contract (never improvise)": always delegate via adapter; "Do NOT improvise workflow steps, explore the filesystem as a substitute..."
   - Grok-specific bullets + self-ref paragraph.
   - Invocation rules: map `soleur:` → bare for Grok slash; agents always via harness helper.

2. **Use the adapter everywhere**: Skills/go.md callers must import + call `invokeSkill`/`spawnAgent`/`routingInstructions` (or follow emitted instructions) instead of string literals. See `lib/harness.ts:detectHarness`, `format*`, `spawnAgent`.

3. **Eval-harness Grok arm**:
   - Document in SKILL.md: "Grok Build arm (Phase C #6323)... golden assertions and regression tests exercise the adapter contract... (detect via GROK_* markers or argv)."
   - Note in promptfooconfig.go-routing.yaml description.
   - (Future: dedicated Grok fixture rows exercising slash/spawn expectations.)

4. **.grok handling**: Always treat `plugins/soleur` as source. Verify symlinks + config when adding Grok support. Use worktree-absolute paths for any edit (per AGENTS).

5. **Self-referential hygiene**:
   - Embed exact invocation, CWD, branch, PR in go.md, plans, and learnings.
   - Post-review: add explicit "Landed scope reconciliation" notes (plan + commits).
   - Run full compound logic (error inventory, deviation analyst, route-to-definition) even in one-shot/automated pipelines.

6. **Worktree + session guards** (exercised here): cd to worktree first, `pwd`, branch checks, no bare reads, cleanup-merged at session start, etc.

7. For compound: this learning itself is the output of running soleur:compound logic on the feat session.

## Verification

- Git: `cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-6323-grok-phase-c && pwd` (first action, confirmed worktree).
- Commits landed: f396bf5d4 (feat(grok): Phase C — go.md hardening + eval-harness Grok arm (#6323, epic #6320)) + 8c2873e70 (docs: include pipeline plan artifact + landed-scope reconciliation note).
- Diff minimal/targeted: only go.md (6 lines), eval-harness/SKILL.md (2), promptfooconfig (1 comment). No harness.ts source change (already capable).
- Self-ref text present and accurate in go.md:75 and plan frontmatter + body.
- Plan now carries "Landed scope note (post-review P3 resolution)".
- Review: clean (P3 only, addressed inline).
- Harness: `detectHarness` + routingInstructions exercised by this /go session.
- Eval-gate sentinel protects the routing block; projection round-trips tested.
- No bare-repo reads; all ops via worktree paths + cd prefix.
- Compound verification gate: read-back of this learning will confirm sections + errors.
- Future: `npx promptfoo ...` under GROK_* env or fixture will assert /go slash + spawn paths.

Session error inventory (compound Phase 0.5 mandatory):
- P3 review item on plan scope vs. delivered (plan overstated adapter changes).
- No other errors, failed commands, path confusion, or hook rejections in this execution (review confirmed; self-referential /go succeeded cleanly).
- Recurring vs one-off triage: the scope mismatch is recurring (self-carved artifacts often need reconciliation); disposition = fix-now-inline (addressed by adding note + commit).

Recurring-vs-one-off: addressed. No new tech-debt filed.

Post-documentation verification: this file will be read back immediately after write.

## References

- Epic: #6320 Grok Build fidelity — /go routes to Soleur workflows without improvisation
- Feature: #6323 (Phase C)
- PR: #6329 (feat-one-shot-6323-grok-phase-c)
- Plan artifact: knowledge-base/project/plans/2026-07-11-feat-grok-phase-c-go-md-eval-harness-plan.md (self-referential, includes landed scope)
- Code: plugins/soleur/commands/go.md (harness table + self-ref + eval-gate block), plugins/soleur/lib/harness.ts (detect / invoke / spawn / routingInstructions), plugins/soleur/skills/eval-harness/SKILL.md + promptfooconfig.go-routing.yaml + gated-skills.json + scripts/
- Bootstrap: scripts/grok-fidelity-bootstrap.sh
- Compound: plugins/soleur/skills/compound/SKILL.md (this run), AGENTS.md (hr-*, wg-*, cq-* especially worktree, bare, paths, observability, verify-repo-capability)
- Prior: Phase A/B (onboarding + harness adapter), workflow-patterns learnings on similar (e.g. self-pull-observability, plan-persisting-record, concurrent-session, issue-claims-external-verify-grep)
- Hard rules exercised: hr-when-in-a-worktree-never-read-from-bare, hr-always-read-a-file-before-editing, hr-verify-repo-capability-claim-before-assert, hr-observability-as-plan-quality-gate, etc.

This compounds the knowledge for future Grok fidelity work, harness adapter changes, or any self-referential workflow feature.
