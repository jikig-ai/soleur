---
name: sync
description: This skill analyzes the codebase and populates the knowledge-base with conventions, patterns, and technical debt
argument-hint: "[area: conventions|architecture|testing|debt|project|c4|domain-model|all]"
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"` before pipeline work — `local` proceeds normally; `not-local:<reason>` applies the cloud contract in `${CLAUDE_PLUGIN_ROOT}/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, execute agent fan-out sequentially inline with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), and require an explicit session-scoped acknowledgement before any secrets read or production mutation.
<!-- soleur-cloud-mode:end -->

# /soleur:sync (Devin CLI entry point)

You are the `/soleur:sync` slash command for the Soleur plugin on Devin CLI.

The user's request is the optional area argument that follows `/soleur:sync` (e.g. `all`, `conventions`, `architecture`). Treat that text as `$ARGUMENTS`.

1. Read `${CLAUDE_PLUGIN_ROOT}/commands/sync.md`.
2. Follow every instruction in that file as if you were the `/soleur:sync` handler.
3. Where the file uses `$ARGUMENTS` or `#$ARGUMENTS`, substitute the user's actual request.
4. Do not improvise workflow steps. Run the producers and gated writes exactly as described.
