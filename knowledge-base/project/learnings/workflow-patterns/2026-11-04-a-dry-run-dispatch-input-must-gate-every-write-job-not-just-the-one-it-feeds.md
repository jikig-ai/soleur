---
title: A dry_run dispatch input must gate every write job, not just the one it feeds
date: 2026-11-04
category: workflow-patterns
---

#12065/#12066 review round: two seats independently caught that a new
`dry_run` boolean input on `codeql-to-issues.yml` was mirrored only into
the filer step's env — the downstream `close-orphans` job (`needs:`) still
ran its real `gh issue close` writes on a green dry dispatch. The ruling
rationale ("sole zero-write verification path") was undercut by the run,
not the step.

Fix pattern: `if: inputs.dry_run != true` on the write job — needs-failure
still skips (no `always()`), schedule sees `null != true` → runs. Use the
TYPED `inputs` context: `github.event.inputs.dry_run` is the string
`'false'`, truthy either way (the permanently-gating failure class
documented in `main-health-monitor-workflow.test.sh`). Pin it: the
parsed-YAML suite evaluates the `if` per dispatch scenario (B28) plus a
delete-mutant. Description-only disclosure was rejected: document the
boundary in the input description AND enforce it with the `if:`.

Sibling learning: verbatim-copied helper logic across self-contained
fixtures needs an AST-extracted parity guard, not a "keep identical"
comment (three seats converged; repo convention for workflow scripts
applies by analogy).
