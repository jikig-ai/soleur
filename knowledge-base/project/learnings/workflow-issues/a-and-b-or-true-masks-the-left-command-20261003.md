---
title: "`git push && incr || true` masks the push failure — `|| true` belongs on the LAST arm only, or inside braces"
date: 2026-10-03
category: engineering
tags: [shell, pipefail, fail-open, ci, pipeline-tally]
symptoms: [three `git push && bash tally incr || true` call-outs silently proceeded on a failed push — the executor treated a red push as success and, in test-fix-loop, queued auto-merge on unpushed commits]
module: skill call-out shell snippets
synced_to: []
component: process
problem_type: workflow_issue
resolution_type: process-correction
root_cause: `&&` and `||` are left-associative in POSIX shells — `a && b || true` parses as `(a && b) || true`, so the `|| true` swallows failures from BOTH sides, not just the arm it visually attaches to
---

# Learning: `a && b || true` is `(a && b) || true` — the fail-open suffix swallows the left command too

## Problem

To keep a fail-open counter increment from dying under `set -e`, the ship/merge-pr/test-fix-loop call-outs were written:

```bash
git push && bash "$SYNC_ROOT/scripts/pipeline-tally.sh" incr ci_cycles || true
```

The intent was "push must succeed; the tally increment may not." The parse is `(git push && incr) || true`: a failed push exits non-zero, `|| true` eats it, and the snippet — and any prose step after it — proceeds as though the push landed. In test-fix-loop's auto-sync arm the next step queued GitHub auto-merge on commits that were never pushed. A verification seat caught it; no test arm could see it, because the failure mode needs `git push` to actually fail.

Sibling instance, same class: `tr` inside a `$()` capture vs outside. `slug="$(git branch --show-current | tr -c 'A-Za-z0-9._-' '-')"` maps the command's trailing newline to a literal `-` — `specs/feat-x-` — because tr runs INSIDE the substitution before the strip. `printf '%s' "$(cmd)" | tr …` (strip first, then tr) emits the clean token.

## Solution

Preserve the left arm's failure semantics; fail-open only the arm that needs it:

```bash
git push && bash "$SYNC_ROOT/scripts/pipeline-tally.sh" incr ci_cycles
# or, when the right arm genuinely can fail:
git push && { bash "$SYNC_ROOT/scripts/pipeline-tally.sh" incr ci_cycles || true; }
```

Here the increment already exits 0 contractually (every `pipeline-tally.sh` mutating op is fail-open by design), so the bare `&&` chain is correct AND the `|| true` was dead weight — doubly wrong: redundant AND masking.

## Key Insight

`cmd && failopen_cmd || true` is the footgun shape — scan for `&& … || true` chains in every prose snippet before shipping; the `||` binds the whole left chain, never just the nearest command. When both sides need different error semantics, use braces to scope the `|| true` — or better, give the fail-open command a contractual exit-0 so the suffix is unnecessary. Same family: `$()` strips the trailing newline AFTER the inner command runs — a `tr -c` inside the capture sees bytes the caller thinks are already gone.
