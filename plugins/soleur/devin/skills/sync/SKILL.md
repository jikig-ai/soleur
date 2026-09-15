---
name: sync
description: Populate your company knowledge base from the existing codebase.
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"` — if `CLAUDE_PLUGIN_ROOT` is unset (measured: cloud exec shells do not export it), resolve the script via `find /opt/.devin/plugins -name cloud-detect.sh | head -1`. `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies the cloud contract in `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, execute agent fan-out sequentially inline with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), require an explicit session-scoped acknowledgement (`message_user`) before any secrets read or production mutation, and run `precommit-guard.sh` (same plugin `scripts/` dir, same `find` recipe) before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

Read and follow [Devin compatibility instructions](../../INSTRUCTIONS.md).
Then read and execute the canonical [sync command](../../../commands/sync.md).
Treat the user's text following this skill invocation as `$ARGUMENTS`.
Resolve these paths relative to this SKILL.md, not the working directory.
