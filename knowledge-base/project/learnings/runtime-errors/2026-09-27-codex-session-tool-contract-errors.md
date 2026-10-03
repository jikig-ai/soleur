---
title: Use the active Codex tool schema and project wrapper when invoking deferred actions
date: 2026-09-27
category: runtime-errors
module: Codex session tooling
---

## Problem

Two session calls used the wrong invocation surface: the async question tool
rejected a `question` field (it accepts `title` and `options`), and the project
`db:status` wrapper returned 127 because the Supabase CLI was not on `PATH`.
The standalone `npx supabase status` fallback then correctly reported that the
project's local container had not been started.

## Prevention

Use the exact active tool schema rather than translating field names from
another harness. For local Supabase tasks, expose the CLI through `npm exec
--package=supabase` while invoking `scripts/supabase-local.sh`; that wrapper
preserves the repository's loopback-bound Docker network. A missing CLI is an
environment/setup result, not a database verdict.
