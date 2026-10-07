---
feature: cursor-harness-support
issue: 9608
related_issues: [9611, 9610, 9609]
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec
date: 2026-10-06
brainstorm: knowledge-base/project/brainstorms/archive/20261006-142814-2026-10-06-cursor-harness-support-brainstorm.md
---

# Feature: Cursor CLI harness support

In this spec, **harness** means a host agent runtime named by the `Harness` union in `plugins/soleur/lib/harness.ts`. The word is not in `knowledge-base/project/glossary.md`. It does not mean a test harness.

## Problem Statement

An operator who already runs Soleur in Codex, Devin, or Grok Build cannot run the same lifecycle in the Cursor CLI. `Harness` is `"claude" | "grok" | "codex" | "devin" | "unknown"`. There is no Cursor plugin manifest, instructions file, command entry, agent projection, or hook registry. A session on that CLI falls through as `unknown` and is told to use tools that CLI does not have.

Cursor's `/` menu is one list. `/plan`, `/help`, `/review`, and `/shell` are built-ins. `/go` and `/sync` are not. A copied Claude or Devin `hooks.json` would look installed and run nothing.

## Goals

- The operator installs the plugin from this repository and runs it in the Cursor CLI. A second machine can install from the git repository.
- `/go` and `/sync` are the bare names. Every other skill and agent is `soleur-` prefixed.
- The canonical skill tree stays the source. Cursor names and agents are generated. There is no second copy of skill descriptions.
- Step 1 ships the plugin, the names, and the harness arm, and states that hooks do not run.
- Step 2 ports the full guard set. The plugin is called supported only when step 2 is green: `/go` classifies, one pipeline skill finishes its gates, one agent spawn runs or is explicitly refused, and each guard in the set can be shown to fire.
- Public README, getting-started, comparison, FAQ, and battlecard copy stay unchanged until that bar is green.

## Non-Goals

- The Cursor IDE editor agent (deferred).
- Cloud Agents, and any legal sentence that names that path.
- A cursor.com marketplace listing.
- A hand-copied skill tree.
- Reopening #6320 or #8299.
- An Anysphere processor row, DPA row, or logo.
- A README or getting-started block in either step.
- Editing the comparison page or the battlecard.
- Storing a Cursor token, or calling Cursor from the Web Platform.

## Functional Requirements

### FR1: Local install

A setup step adds the plugin from the local path, the same idea as the Codex and Devin setup scripts. A second machine installs from the git repository. The install does not submit anything to cursor.com.

### FR2: Entry names

On the Cursor CLI, the operator types `/go` and `/sync` with no prefix. Help is `/soleur-help`, because `/help` is a Cursor built-in.

### FR3: Prefixed catalogue

Every other skill and every agent is invoked as `/soleur-<name>` (for example `/soleur-plan`, `/soleur-review`, `/soleur-engineering-cto`). The map is generated from the canonical tree. Skill `description:` lines under `plugins/soleur/skills/*/SKILL.md` are not duplicated.

### FR4: Recognized session

When the Cursor CLI marker has been measured, `detectHarness` returns `cursor` for that session. Instructions for that session name Cursor's own invoke and spawn forms. They do not tell the model to call the Skill tool, the Task tool, `run_subagent`, or AwaitShell.

### FR5: Honest step 1

Until the hook port is proven, the plugin text says hooks do not run. The tree must not present a Claude-shaped `hooks.json` as a live Cursor registry.

### FR6: Support bar

Step 2 is green only when `/go` classifies, one pipeline skill finishes its gates, one agent spawn runs or is explicitly refused, and the full guard set fires on the Cursor CLI protocol. If a guard cannot be shown to fire, the plugin is not called supported.

### FR7: Silence on public surfaces

Neither step edits the README install blocks, getting-started, the comparison FAQ, the blog post, or the battlecard.

## Technical Requirements

### TR1: Measure before binding

The env marker, the hook envelope, the wait primitive, and the `skills`-key load rule are measured on the Cursor CLI before any of them is written into code or instructions. A guessed `CURSOR_*` name, a copied poll sentence, or a copied Codex `skills` array is a failed step.

### TR2: Generator, not a hand port

Adding Cursor adds a `Harness` member and a generator (ADR-245). Agents are generated into a directory only the Cursor manifest names. Claude's `plugins/soleur/agents/` tree is left as it is. A `--check` drift gate fails when a generated file is hand-edited or when a new canonical agent has no stub.

### TR3: Hook registry

Cursor gets its own hook registry and a disposition ledger (ADR-223). Claude matchers stay in place. `${PLUGIN_ROOT:-…}` is not introduced (ADR-179).

### TR4: Loader proof

A green copy of `harness-tool-map`, `harness-parity`, or the additive `components.test.ts` skills model is not proof the Cursor loader lists the canonical skills once. The plan names a check that fails when the canonical root is hidden or when `/go` is registered twice.

### TR5: Model tier

The Cursor model tier inherits, as Codex and Devin do. No Cursor model id is invented.

### TR6: Discovery CI

A listing job is added only when a pinned Cursor CLI can list skills headlessly. It is non-required and `continue-on-error` until a soak (ADR-245). It is not hung off the required `grok-fidelity` job.

### TR7: Legal lockstep

`soleur:gdpr-gate` is not required while the diff stays off the regulated-path regex and stores no Cursor token. The Terms parenthetical that lists harnesses changes only after `harness.ts` contains the `cursor` arm, as a Tier 2 PATCH with CLO sign-off. Wording is "a Soleur plugin that runs in Cursor" and "not affiliated with or endorsed by Anysphere."

### TR8: Architecture decision before code

Planning runs `/architecture create 'Add a Cursor CLI plugin adapter'` before implementation. The title does not say supported. Support is the end of slice 2.

## Slice order

1. Plugin, names, harness arm. Hooks stated as not running. No public sentence.
2. Full guard port, measured first. Support is this slice, when it is green.
