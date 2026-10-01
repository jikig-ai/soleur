---
title: Verify Codex plugin discovery against the installed CLI
date: 2026-09-11
category: integration-issues
tags: [codex, plugin, discovery, hooks]
---

# Codex discovery must be measured

Codex 0.154.0 accepts a versionless `.codex-plugin/plugin.json` and a
`skills` array. A manifest naming only `./codex/skills` installed successfully
but exposed just the three wrappers. Listing both `./skills` and
`./codex/skills` exposed all 98 skills. Native skill metadata uses qualified
names such as `soleur:go`, not bare `go`.

The local scaffold validator required a version and accepted only a string
skill path; current native behavior and repository version policy differ.
Use the native discovery smoke test as the loadability check. Installation
success alone is insufficient.

Count actual SKILL.md files, not directories: `flag-bootstrap/` is a
setup-only folder. The initial smoke test incorrectly counted it as a skill.
Test installed-path fixtures by invoking the copied hook, not its source path.

Codex deliberately reads hooks from the shared repository root in linked
worktrees. Putting either inline hooks or hooks.json only in a feature
worktree exposes no project hooks, even when that worktree is trusted.
The official `hooks_list_uses_root_repo_hooks_for_linked_worktrees` test
confirms this. The setup script installs the reviewed config at the shared
root without overwriting differing settings. Native validation then lists
both project hooks and the six plugin hooks.

Welcome-hook fixtures must clear inherited Codex markers when simulating
Claude. An initial regression run otherwise skipped the welcome sentinel
under a Codex-launched test process.

Codex marketplace CLI accepts one path per `--sparse`; repeat the flag for
each path. Do not copy Claude's multi-value flag syntax.

Sandbox observations: CLI help can print a PATH-alias warning while succeeding.
App-server discovery additionally needs writable Codex SQLite state. Worktree
cleanup returned zero after a read-only lock failure, so its log had to be
inspected and the prescribed action rerun with permission. Cleanup also reported
an unrelated protected orphan directory; it was not treated as cleaned.

Documentation markdown was available through curl when web retrieval rejected
its content type. Check current navigation links before guessing documentation
or repository filenames; bounded search prevents missing-file detours.

Use npm for the root package-lock.json: Bun's frozen install rejects the
nested overrides. The unchanged lockfile reports existing js-yaml and
liquidjs advisories, tracked in [#8065](https://github.com/jikig-ai/soleur/issues/8065).
