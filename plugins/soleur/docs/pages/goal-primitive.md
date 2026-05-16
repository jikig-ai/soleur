---
title: "/goal — Operator Escape Hatch for Ad-Hoc Autonomous Work"
description: "When to use Claude Code's /goal primitive vs. a Soleur skill, the transcript-only evaluator gotchas, and six vetted condition recipes with built-in turn caps."
layout: base.njk
permalink: goal-primitive/
---

<section class="page-hero">
  <div class="container">
    <h1>/goal — Operator Escape Hatch</h1>
    <p>For ad-hoc autonomous work that doesn't have a dedicated Soleur skill.</p>
  </div>
</section>

<section class="content">
  <div class="container">
    <div class="prose">

**Requires Claude Code v2.1.139 or later.** The `engines.claude-code` field in `plugins/soleur/.claude-plugin/plugin.json` declares this floor.

## What `/goal` is

`/goal <condition>` is a Claude Code built-in that keeps your current session running turns until a fresh small-model evaluator (defaults to Haiku) decides your condition holds. After every turn, the evaluator reads the conversation transcript and returns yes/no plus a short reason. "No" starts another turn with the reason as guidance. "Yes" clears the goal and records the outcome in the transcript. You can clear early with `/goal clear` or `/clear`; the goal also clears when you exit the session.

It is a session-scoped wrapper around a prompt-based Stop hook. One goal can be active per session. Setting a new goal replaces the old one. The full upstream documentation lives at <https://code.claude.com/docs/en/goal>.

## When to use `/goal` vs. a Soleur skill

Soleur's autonomous skills already own the stricter, structurally-verifiable completion mechanisms for recurring engineering workflows. Reach for them first. Use `/goal` for **one-off autonomous work that doesn't have a dedicated skill**.

| Situation | Use | Why |
|---|---|---|
| Recurring workflow with a verifiable end state — passing tests after a refactor, draining a labeled backlog, resolving every PR comment, draining a TODO queue | `soleur:one-shot`, `soleur:test-fix-loop`, `soleur:drain-labeled-backlog`, `soleur:resolve-todo-parallel`, `soleur:resolve-pr-parallel` | Each ships an exit-code-based gate, a structured `<promise>DONE</promise>` marker, or a CLI-output-empty check. Stricter than a transcript-judging evaluator. |
| One-off autonomous work without a dedicated skill — sweeping a CHANGELOG, enforcing a file-size budget, draining a triage queue against a specific label you don't run often | `/goal` from your top-level Claude Code shell | A dedicated skill would be overkill. The recipes below give you copy-paste conditions with built-in turn caps. |
| Headless / CI autonomous loop with a verifiable condition | `claude -p "/goal <condition>"` | Works in non-interactive mode. Interrupt with Ctrl+C. |
| Pre-existing Soleur autonomous skill that you want to bound with an outer turn cap | The skill's own iteration cap; do **not** layer `/goal` | Two Stop hooks competing on the same workflow is unnecessary. See "Soleur-native alternative" below. |
| Operator-typed ad-hoc condition you don't want to commit as a skill | `/goal` once at your shell, with a turn cap clause | Recipes encode common shapes; you can adapt them inline. |

## The transcript-only evaluator gotcha

**`/goal`'s evaluator reads only what the main agent has surfaced in the conversation transcript.** It cannot run tools, read files, or grep. Conditions written against tool-accessible evidence that the main agent never explicitly surfaces will silently never resolve `yes`, and the loop will burn turns until the cap fires or you Ctrl+C.

This is the same failure class Soleur has paid for four documented times under hard rule [`hr-when-a-workflow-concludes-with-an`](../AGENTS.md):

> **When a workflow concludes with an actionable next step, execute it — don't list it as "next action" and stop.** Use Playwright MCP, `xdg-open`, CLI tools, or APIs to drive completion. Only hand off for credentials/payment at the exact page.

In our incidents, the main agent said "Implementation complete" / "Announce to user" / "next action: deploy" / "and stop" and the parent orchestrator treated the conclusive-sounding text as a stopping signal. A `/goal` evaluator reading the same kind of text can do the inverse: rule the goal achieved when the work was only described as done.

**The practical rule:** every condition must name a *structured marker* the agent has to surface explicitly in the transcript — an exit code, a JSON array shape, a literal command output, a file-existence check with byte count. Never a fuzzy outcome like "the migration is complete" or "all callers updated." If the evaluator can interpret the marker either way, it will eventually pick the wrong way.

If you're tempted to write a marker that conjoins a structured signal with a literal-summary line ("`exit=0` AND `output contains '0 errors'`"), grep every implementation's actual output first. ESLint clean emits nothing. Biome says "No fixes applied." Prettier says "All matched files use Prettier code style!" pytest says "N passed in 0.03s." None of those contain "0 errors" — and a recipe that requires them will burn turns against a clean codebase. Use the exit-code echo alone.

## What it consumes

Each turn the loop continues, you are billed for one main-model turn plus one Haiku evaluator turn against the Anthropic API key in your Claude Code session. A goal that never resolves `yes` will run until you Ctrl+C or the turn cap fires.

The recipes below ship with hardcoded `or stop after N turns` caps for exactly this reason. **Do not remove the cap when you adapt a recipe.** A single runaway loop against a poorly-bounded condition can spike spending into the hundreds of dollars before you notice.

Soleur does not bill or proxy these calls — Anthropic does, against the key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate `/goal` against your own budget.

## Vetted condition recipes

Each recipe is meant to be copy-pasted, optionally adapted to your file paths / labels / test commands, and run at your top-level Claude Code shell. Every recipe ends with `or stop after N turns` where N ≤ 40. The marker each recipe relies on is named in the comment.

### Recipe 1 — Test gate

```text
/goal the most recent test command exited with code 0 (confirmed by an explicit 'echo "exit=$?"' showing exit=0 in the transcript after the test ran), or stop after 15 turns
```

**Marker:** literal `exit=0` echo in the transcript. Works across `npm test`, `bun test`, `pytest`, `cargo test`, `go test`, `bin/rails test`, and any other runner — none are required to emit a specific summary string. Make sure your shell runs `echo "exit=$?"` immediately after the test command so the exit code lands as a literal line in the transcript.

### Recipe 2 — Label-empty backlog drain

```text
/goal the output of 'gh issue list --label needs-triage --state open --limit 100 --json number' is the literal "[]" (empty JSON array), or stop after 30 turns
```

**Marker:** literal `[]` in transcript. Substitute the label name for your actual triage label. The `--limit 100` cap is defensive; you can raise it if you know the backlog is larger. Pair with one-shot or your manual fix flow inside the loop.

### Recipe 3 — API migration sweep

```text
/goal 'rg -n "oldApi\(" src/ test/' produced no matches AND the most recent test command's 'echo "exit=$?"' showed exit=0, or stop after 40 turns
```

**Marker:** ripgrep silence (the agent reports "no matches found" or an empty result) AND the test exit-code echo. Substitute `oldApi` and the directory scope for your actual symbol. Two clauses both verifiable from transcript output; both are structured, not literal-summary.

### Recipe 4 — Lint clean

```text
/goal the most recent lint command exited with code 0 (confirmed by an explicit 'echo "exit=$?"' showing exit=0 in the transcript), or stop after 10 turns
```

**Marker:** literal `exit=0` echo. Works across ESLint, Biome, Prettier `--check`, ruff, rubocop, golangci-lint, and any other linter — same reason as recipe 1. Do **not** add a "AND output contains '0 errors'" clause; ESLint clean emits nothing, Biome says "No fixes applied," Prettier says "All matched files use Prettier code style!" Adding the literal-summary clause guarantees the goal never resolves on a clean codebase.

### Recipe 5 — Size budget enforcement

```text
/goal 'wc -l src/feature/*.ts | awk "$1 > 200 {print}"' produced no output (all files under 200 LOC), or stop after 25 turns
```

**Marker:** awk silence — empty output means every file is under 200 lines. Substitute the path glob and LOC threshold. Pair with a refactor task inside the loop ("when a file exceeds budget, split it into focused modules and re-run the wc check").

### Recipe 6 — File assembled

```text
/goal the file knowledge-base/community/digests/$(date +%Y-W%V).md exists (confirmed by 'ls' showing its path) AND 'wc -c' of that file shows a byte count greater than 500, or stop after 12 turns
```

**Marker:** `ls` output containing the file path, plus a `wc -c` byte count surfaced in the transcript. Substitute the file path for whatever artifact the loop is supposed to assemble. The byte threshold prevents the goal from resolving on a stub or empty file.

### Why these six

They cover the canonical "ad-hoc autonomous work" shapes — passing tests, draining a queue, sweeping a refactor, lint-cleaning, enforcing a size budget, assembling a missing file. Recipes 1, 3, and 4 share the exit-code-echo pattern at different command surfaces (test runner, ripgrep + test runner, lint runner) — this is cookbook variety, not pattern bloat. Recipes 2, 5, and 6 each demonstrate a distinct marker shape (JSON array literal, command silent-on-success, file existence + size).

## Soleur-native alternative

Soleur skills already use a session-scoped Stop hook at [`plugins/soleur/hooks/stop-hook.sh`](https://github.com/jikig-ai/soleur/blob/main/plugins/soleur/hooks/stop-hook.sh) (316 lines, ralph-loop heritage). It does what `/goal` does and more:

- **Structured completion marker.** Skills emit `<promise>DONE</promise>` as a literal token in the transcript ([`one-shot/SKILL.md`](https://github.com/jikig-ai/soleur/blob/main/plugins/soleur/skills/one-shot/SKILL.md) line 151). The hook reads `last_assistant_message` from the Stop-hook API contract — no transcript reparsing required.
- **Stuck-detection.** Jaccard word-set similarity (≥80% over three turns), MD5 hash repetition (three-turn threshold), three-tier idle-classifier with content-pattern regex.
- **Crash-orphan TTL.** Stale state files from crashed sessions auto-delete after the TTL.
- **PPID scoping.** State files keyed by `$PPID` so parallel sessions don't trample each other.

`/goal` is the **secondary, manual layer** for ad-hoc work outside dedicated skills. Both Stop hooks can coexist on the same session (the one that returns `decision: block` wins), but you should not deliberately layer them on the same workflow.

## Headless / CI usage

The same recipes work in non-interactive mode — paste the recipe condition (including its `or stop after N turns` cap) inside a `claude -p` invocation:

```bash
claude -p "/goal <paste recipe condition here, including the cap>"
```

For example, the Recipe 1 test gate condition becomes a one-liner suitable for cron, GitHub Actions, or any CI step. Ctrl+C interrupts the loop before the condition resolves. Use this shape inside scheduled GitHub Actions, nightly cron, or any CI job that needs an autonomous-loop bounded by a transcript-verifiable condition.

## Spike outcome: setting `/goal` from inside a Soleur skill

A short verification (`Claude Code v2.1.142`, plan Phase 0 spike) confirmed that **slash commands like `/goal` are processed by the Claude Code frontend before they reach the model's turn loop.** This means:

- Setting `/goal` from inside a Soleur skill invoked via the Skill tool is **not supported**. Skill bodies execute inside the model's turn loop and emit tool calls + text; they cannot emit slash commands the frontend interprets.
- An operator-set goal at the top-level shell **does** persist across subsequent Skill-tool invocations within the same session.

The recommended pattern is therefore **operator-set-then-invoke**: type `/goal <condition>` at your shell, then invoke whatever Soleur skill or do whatever ad-hoc work you want bounded by that goal. The evaluator checks after every turn regardless of which skill produced the turn.

If you want a Soleur skill to *suggest* a `/goal` condition (e.g., as part of its handoff text), that is supported — but the operator must type the suggested command themselves.

## Requirements

- **Claude Code v2.1.139 or later.** This is declared in [`plugins/soleur/.claude-plugin/plugin.json`](https://github.com/jikig-ai/soleur/blob/main/plugins/soleur/.claude-plugin/plugin.json) via the `engines.claude-code` field. Earlier CC versions do not have `/goal`.
- A reachable Anthropic API key (configured in your CC session). All evaluator and main-turn calls are billed against this key.

## Further reading

- Upstream `/goal` documentation: <https://code.claude.com/docs/en/goal>
- Soleur ralph-loop Stop hook source: [`plugins/soleur/hooks/stop-hook.sh`](https://github.com/jikig-ai/soleur/blob/main/plugins/soleur/hooks/stop-hook.sh)
- Soleur one-shot completion marker: [`plugins/soleur/skills/one-shot/SKILL.md`](https://github.com/jikig-ai/soleur/blob/main/plugins/soleur/skills/one-shot/SKILL.md)
- AGENTS.md hard rule [`hr-when-a-workflow-concludes-with-an`](https://github.com/jikig-ai/soleur/blob/main/AGENTS.md) — the documented pseudo-handoff failure class.

</div>
  </div>
</section>
