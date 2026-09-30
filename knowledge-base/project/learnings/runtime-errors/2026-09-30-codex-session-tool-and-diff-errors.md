---
title: Verify Codex tool surfaces and git comparison direction before acting
date: 2026-09-30
category: runtime-errors
module: Codex session and Git workflow
---

## Problem

This session recovered from several interface mistakes: an `exec` script used
the unavailable `functions` global instead of `tools`; a tool call used the
wrong question schema; a multiline `exec` call had a JavaScript syntax error;
an embedded Python heredoc was compiled together with its shell wrapper; a
shell probe ended in a dangling `&&`; an inspection guessed a source path that
did not exist; one patch hunk did not match; and a `jq` status summary applied
`group_by` at the wrong pipeline level and rejected the GitHub CLI's check-run
shape. I also read `git diff HEAD..origin/main` as main removing feature code;
that direction showed branch-only additions as deletions because main had not
merged them.

## Prevention

Use `tools.*` inside `functions.exec`; call collaboration tools directly with
their namespace. Check the active question schema. Resolve paths with `rg
--files` before opening them. Re-read exact source after a patch mismatch and
split the edit into smaller hunks. For shell wrappers with embedded
languages, run the native syntax check and compile only the extracted
heredoc. Avoid trailing command separators in shell probes. Before calling a
diff intentional, record its direction and the merge base; compare both
`<merge-base>..origin/main` and `<merge-base>..HEAD` to separate upstream work
from feature-only changes. For check status summaries, first materialize the
check-run list as an array, then group or map it.

The pre-commit hook also started `test-all.sh --affected` despite the operator's
authorization to rely on CI; it was interrupted and rerun with only the
`bun-test` hook excluded. The first typecheck caught an RPC fixture typed too
narrowly for the boolean acknowledgment response; its result type was widened.
The GitHub job-log endpoint returned plain text despite the `logs` suffix, so
the download needed `file` inspection before treating it as an archive.

Two resumed-session probes repeated those shape mistakes: the embedded-Python
extractor searched for a double-quoted heredoc marker and failed before
compiling anything, and one `exec_command` omitted the worktree argument and
read the project root on a different branch. Use a regex over the exact
single-quoted heredoc marker, and always pass the feature worktree as the
command's `workdir`; a failed lookup is not evidence that a file is absent.
An attempted learning-file patch copied context from a different learning and
was rejected without a write; re-read the target tail and patch its exact
content rather than borrowing nearby prose.
