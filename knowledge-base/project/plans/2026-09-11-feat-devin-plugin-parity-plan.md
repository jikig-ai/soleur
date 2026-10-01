---
title: "feat: Add Devin plugin scaffolding parity with Codex/Grok harnesses"
date: 2026-09-11
slug: devin-plugin-parity
branch: feat-devin-plugin-parity
---

## Overview

Add the Devin-specific scaffolding currently missing from `plugins/soleur/.devin-plugin/plugin.json` and the repo root so that the Devin install path matches the Claude, Codex, and Grok paths in discoverability, local-dev setup, session context injection, and test coverage.

The canonical skills and agents already exist; this change only adds harness-specific entry points and glue.

## Research Insights

- `.devin-plugin/plugin.json` is a bare metadata + MCP-servers manifest. It lacks the `skills` root mapping that Codex uses to expose both canonical workflow skills and harness-specific command wrappers.
- Codex ships `codex/skills/{go,help,sync}` wrappers so `$soleur:go`, `$soleur:help`, and `$soleur:sync` are native skill mentions. Devin has no `devin/skills/*` wrappers, so `/soleur:go` is not a first-class Devin skill even though `devin/INSTRUCTIONS.md` documents it.
- Codex has `.codex/config.toml` + `scripts/setup-codex.sh` for local development setup. Grok has `.grok/config.toml`. Devin has neither a `.devin/config.json` nor a `scripts/setup-devin.sh`.
- Codex has `plugins/soleur/hooks/codex-session-start.sh` to inject compatibility instructions at session start. Devin has no equivalent session-start hook.
- Test coverage: Codex has `codex-plugin.test.ts` and `codex-setup.test.ts`; Devin only has `devin-harness.test.ts`. Need `devin-plugin.test.ts` and `devin-setup.test.ts`.
- `devin/INSTRUCTIONS.md` already exists and provides the tool/agent mapping for Devin. The wrappers will link to it and then to the canonical `commands/{go,help,sync}.md`.
- Project conventions that constrain the implementation:
  - No `version` key in `plugin.json` (manifest versioning rule).
  - Canonical skills live flat under `skills/`; harness-specific wrappers live under `<harness>/skills/`.
  - Setup scripts are bash with `set -euo pipefail`.
  - Tests use `bun:test` and mirror the structure of existing harness tests.

## Files to Create

- `plugins/soleur/devin/skills/go/SKILL.md`
- `plugins/soleur/devin/skills/help/SKILL.md`
- `plugins/soleur/devin/skills/sync/SKILL.md`
- `plugins/soleur/hooks/devin-session-start.sh`
- `.devin/config.json`
- `scripts/setup-devin.sh`
- `plugins/soleur/test/devin-plugin.test.ts`
- `plugins/soleur/test/devin-setup.test.ts`

## Files to Edit

- `plugins/soleur/.devin-plugin/plugin.json` — add `skills: ["./skills", "./devin/skills"]`.
- `plugins/soleur/README.md` — update Devin quick-start to mention the local setup script.
- `plugins/soleur/devin/INSTRUCTIONS.md` — keep root-resolution guidance; verify it still works once wrappers route through it.

## Implementation Phases

1. **Manifest update.** Add the `skills` array to `.devin-plugin/plugin.json`.
2. **Skill wrappers.** Create the three `devin/skills/{go,help,sync}/SKILL.md` files. Each frontmatter uses `name: {go,help,sync}` and `description:` in the standard third-person form, then points to `devin/INSTRUCTIONS.md` and the canonical `commands/{go,help,sync}.md`.
3. **Session-start hook.** Create `plugins/soleur/hooks/devin-session-start.sh` modeled on `codex-session-start.sh`: compute the plugin root from `BASH_SOURCE[0]`, read `devin/INSTRUCTIONS.md`, and emit `additionalContext` when a Devin session marker is present.
4. **Project config.** Create `.devin/config.json` at the repo root, registering:
   - `SessionStart`: run `.claude/hooks/session-rules-loader.sh` then `plugins/soleur/hooks/devin-session-start.sh`.
   - `PreToolUse`: run `.claude/hooks/guardrails.sh` for `exec` and for `write|edit` matchers.
5. **Setup script.** Create `scripts/setup-devin.sh` that:
   - Verifies the repo layout.
   - Installs the local plugin with `devin plugins install --local ./plugins/soleur -y`.
   - Installs `.devin/config.json` from the source tree if it does not exist or matches; refuses to overwrite a modified config.
6. **Tests.** Add `devin-plugin.test.ts` and `devin-setup.test.ts` mirroring the Codex tests:
   - manifest `skills` roots exist,
   - wrapper SKILL.md links resolve,
   - every `/soleur:go` route uses the Devin adapter,
   - setup script is idempotent and safe against modified config.
7. **Verification.** Run `bun test plugins/soleur/test/devin-*.test.ts` and the existing harness suite; fix failures.
8. **Docs lint.** Run the markdown lint script; fix any issues.

## Acceptance Criteria

- `.devin-plugin/plugin.json` contains `skills: ["./skills", "./devin/skills"]` and still has no `version` key.
- The three wrapper `SKILL.md` files exist and reference `devin/INSTRUCTIONS.md` and the canonical commands.
- `.devin/config.json` is valid JSON, registers `SessionStart` and `PreToolUse` hooks, and references only repo-relative paths.
- `scripts/setup-devin.sh` uses `set -euo pipefail`, installs the local plugin, and refuses to overwrite a modified `.devin/config.json`.
- `plugins/soleur/test/devin-plugin.test.ts` and `plugins/soleur/test/devin-setup.test.ts` pass.
- Existing `devin-harness.test.ts` and other harness tests still pass.
- README Devin section accurately describes the install path.
- README component counts remain unchanged (no new canonical skills/agents/commands).

## Domain Review

**Domains relevant:** Engineering

- Engineering: this is a harness/distribution change. No new business logic.
- Product/UX Gate: **NONE** — developer-facing tooling, no user-facing surface.

## User-Brand Impact

- **If this lands broken, the user experiences:** a Devin plugin install that appears to succeed but lacks the `/soleur:go`, `/soleur:help`, and `/soleur:sync` skills or session guardrails, causing the agent to improvise workflows or skip gates.
- **If this leaks, the user's data/workflow/money is exposed via:** not applicable — no new data surface.
- **Brand-survival threshold:** none — this change adds existing guardrails to a harness that currently lacks them; it does not introduce a new user-facing failure mode.
