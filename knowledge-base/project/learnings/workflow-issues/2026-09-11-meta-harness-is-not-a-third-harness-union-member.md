---
module: Development Workflow
date: 2026-09-11
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "an untracked meta-harness (Omnigent) re-opened 'add a third Harness union member / port the plugin'"
  - "Omnigent writes a stub .claude-plugin/plugin.json + --plugin-dir for YAML bundles, which reads as marketplace fit"
  - "CPO seated it in Tier 3 next to Paperclip/Multica; CMO: that shelf is 'runs your company' and manufactures substitution"
root_cause: inadequate_documentation
resolution_type: documentation_update
severity: medium
rule_id: wg-architecture-decision-is-a-plan-deliverable
tags: [omnigent, meta-harness, harness-adapter, plugin-fit, competitive-intelligence, watch-only]
synced_to: [brainstorm]
---

# A meta-harness is not a third `Harness` union member, and a stub `plugin.json` is not marketplace fit

**Date:** 2026-09-11 · **PR:** #8060 · **Issue:** #8062 · **CI:** [competitive-intelligence.md](../../../product/competitive-intelligence.md) Tier 4 Omnigent row · **Brainstorm:** [2026-09-11-omnigent-meta-harness-eval-brainstorm.md](../../brainstorms/2026-09-11-omnigent-meta-harness-eval-brainstorm.md)

## Problem

`/go analyze if soleur could make use of Omnigent` looked like a third-harness / plugin-port question. `plugins/soleur/lib/harness.ts` is an **invocation-surface discriminator** (`claude | grok | unknown`: Skill/Task vs slash/`spawn_subagent`). Omnigent is a **supervisor over those two surfaces** (Claude-native wrapper + Grok ACP `grok agent stdio`). Treating it as a union member is a category error: `detectHarness` would steal a Claude- or Grok-shaped process into a switch arm with no Skill/slash API.

## Environment

- Module: Development Workflow (harness adapter + CI watch seating)
- Affected components: `plugins/soleur/lib/harness.ts`, `plugins/soleur/.claude-plugin/plugin.json`, `knowledge-base/product/competitive-intelligence.md`
- Date: 2026-09-11
- Snapshot: Omnigent HEAD `be5cae72d9a96ee2cd8ddf6bb6fb0c306f80387a`, ~9,844 stars, Apache-2.0, alpha

## Symptoms

- `git grep -i omnigent` on the worktree was empty, so the next session had no "seen, not adopted" record
- Omnigent `bundle_skills.py` writes a stub `.claude-plugin/plugin.json` (`name` + `description`) and passes `--plugin-dir <tmp-bundle>` — that is YAML-agent skills, not loading Soleur's marketplace plugin (`engines.claude-code >= 2.1.139`)
- Seating a CLI switchboard in Tier 3 (CaaS / "runs your company") invites comparison pages and "Soleur runs on Omnigent" copy CMO forbade

## What Didn't Work

**Attempted: treat Omnigent as a third `Harness` / YAML port of the plugin.** Category error. No distinct Skill/Task/slash surface. YAML `claude-sdk` agents would leave Soleur skills that say "invoke via Skill tool / spawn_subagent" as dead letters.

**Attempted: seat next to Paperclip/Multica (Tier 3).** Same *class* as Multica's 14-provider daemon, but Tier 3 is the CaaS shelf. CMO: parking it there *creates* the narrative substitution we refuse.

**Attempted: Tier 5 Openship-only watch.** Under-weights a productized meta-harness that already has a Grok ACP row.

## Session Errors

**Compound ran after merge, so it aborted on main.**

- **Recovery:** Follow-up worktree `feat-omnigent-eval-learning` (this file). The CI row + brainstorm on `main` via #8060 already hold the decision.
- **Prevention:** Run `/compound` on the feature branch **before** presenting merge/ship as a next-step option. Compound cannot run on `main`.

**First `cleanup-merged` skipped the merged worktree (`active lease`).**

- **Recovery:** `bash plugins/soleur/scripts/lib/session-state.sh release_lease feat-omnigent-harness-eval` then re-run cleanup-merged.
- **Prevention:** Release this session's lease before `cleanup-merged` when the session created the worktree.

**Post-merge watch used `gh run watch`, which reprints every job every 3s.**

- **Recovery:** Killed the noisy monitor; replaced with a quiet `conclusion` poll that prints only `DONE`/`FAILED`.
- **Prevention:** Follow `long-running-background-tasks` — stdout of a `monitor` is a main-agent wake; do not pipe `gh run watch` into it.

## Solution

Watch-only. Operator-closed 2026-09-11: no dogfood, no plugin port, no Concierge runtime. Seat **Tier 4 + New Entrants** (CrewAI class: productized DIY/control-plane). Encode in the CI row:

- Do **not** add `"omnigent"` to `export type Harness` / `detectHarness`
- Plugin-fit is **false as first-class**; piggyback-only on the inner Claude/Grok CLI (`omnigent claude` with no bundle uses host `~/.claude`, then injects AskUserQuestion / SessionStart hooks — collision, not dogfooded)
- Do **not** claim "Soleur runs on Omnigent" / "plugin compatible"
- Stars do not reopen; triggers are in the CI row
- Telemetry on by default from v0.6.0 is **their** claim; ingest processor unnamed — blocker for any later install (no Art. 28 from a markdown row)

Same door as Multica 2026-07-04 (do not adopt a 14-provider runtime).

## Why This Works

`Harness` names **how Soleur invokes skills and agents**, not **which process launched the CLI**. A wrapper that tmux/ACP-attaches Claude or Grok is still `claude` or `grok` once `CLAUDECODE` / `GROK_*` are set. A stub plugin manifest exists so Claude will list bundled YAML skills; it is not a marketplace that honors `engines.claude-code` or Soleur hooks.

Tier 4 is the DIY/framework shelf. That is the job Omnigent actually sells. Tier 3 is the company-ops shelf.

## Prevention

- Before adding a `Harness` union member, name the **invocation surface** (Skill tool, slash command, Task, `spawn_subagent`). If there isn't one, it is not a harness.
- `--plugin-dir` + a generated `plugin.json` is not "our plugin loads." Read whether host Claude/Grok config is used (`bundle_dir=None`) vs a tmp bundle.
- Meta-harness / multi-CLI wrappers: default seat **Tier 4**, not Tier 3, unless they ship business-domain agents or "run your company" copy.
- `peer-plugin-audit` is for skill libraries. Zero `SKILL.md` (or only example/dev skills) → category mismatch, not an overlap matrix.

## Related Issues

- See also: [2026-07-05-external-framework-brainstorm-audit-existing-primitives-before-greenfield.md](../2026-07-05-external-framework-brainstorm-audit-existing-primitives-before-greenfield.md) — audit existing primitives before greenfield
- See also: [2026-05-09-evaluating-vendor-branded-claude-code-skills.md](../2026-05-09-evaluating-vendor-branded-claude-code-skills.md) — vendor surface in SKILL.md
- See also: [2026-04-21-peer-plugin-audit-brainstorm-patterns.md](../2026-04-21-peer-plugin-audit-brainstorm-patterns.md) — skill-library audits, not meta-harnesses
- Similar to: Openship watch/decline — [2026-07-26-openship-adoption-eval-brainstorm.md](../../brainstorms/2026-07-26-openship-adoption-eval-brainstorm.md)
- Similar to: Multica "do not adopt 14-provider runtime" — [2026-07-04-multica-primitives-adaptation-brainstorm.md](../../brainstorms/2026-07-04-multica-primitives-adaptation-brainstorm.md)
