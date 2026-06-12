# Learning: the require-milestone guardrail false-matches `gh issue create` inside a commit-message body

## Problem

While committing the operator-digest feature (#5085), a `git commit -m "…"` whose
message documented the workflow's security boundary ("narrowed allowlist without
`gh issue create`…") was **blocked twice** by a PreToolUse hook:

```
BLOCKED: gh issue create must include --milestone. Default to 'Post-MVP / Later' …
```

The command was `git commit`, not `gh issue create` — the hook false-matched the
phrase inside the multi-line `-m` body. The first failure also took down a
preceding `git add …` chained with `&&` (the whole Bash tool call is rejected).

## Root cause

`.claude/hooks/guardrails.sh:121` detects the command with:

```bash
echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*gh\s+issue\s+create'
```

`grep` matches per line, and `^` matches the start of **any** line in the command
string. A `git commit -m "…"` body that wraps `gh issue create` onto its own line
presents a line beginning `gh issue create`, so the gate fires even though no
issue is being created. Unlike `pre-merge-rebase.sh` (which strips `git commit
-m/-F` message bodies and heredocs before its own command detection — see
[[2026-05-29-command-detection-hook-self-interception-and-heredoc-fp]]), the
require-milestone gate does **no** commit-message-context stripping.

This is a recurring foot-gun precisely for the PRs most likely to mention the
command in prose: security/allowlist/automation work documenting that an agent
allowlist *omits* `gh issue create`.

## Solution (this session)

Reworded the commit body to avoid the literal token ("allowlist that omits the
agent issue-create capability"). The fix unblocks the commit but does not address
the hook defect — a future PR documenting the same boundary will hit it again.

The hook defect itself is a **different subsystem** (`.claude/hooks/`) from this
feature branch, so per scope discipline it is **file-tracked as its own issue**
([#5192](https://github.com/jikig-ai/soleur/issues/5192)), not bundled into the
operator-digest PR.

## Key insight

Command-detection PreToolUse hooks that scan `$COMMAND` with a line-anchored regex
(`^|&&|\|\||;`) must strip `git commit -m/-F` message bodies and heredocs FIRST —
otherwise they self-intercept any commit whose message merely *mentions* the
detected command. The `pre-merge-rebase.sh` quote-strip is the canonical precedent;
`guardrails.sh`'s require-milestone gate is missing the same guard. When fixing one
command-detection hook's self-interception, sweep ALL sibling hooks with the same
`(^|&&|\|\||;)` anchor for the same defect.

## Session Errors

- **require-milestone gate false-matched `gh issue create` in a `git commit -m` body (blocked twice).**
  Recovery: reworded the commit body to drop the literal token.
  Prevention: strip commit-message bodies/heredocs before command detection in
  `guardrails.sh` (mirror `pre-merge-rebase.sh`). Filed as a tracked issue (different subsystem).
- **CWD does not persist across Bash tool calls; bun's cwd defaults to `plugins/soleur`.**
  `bun test plugins/soleur/test/components.test.ts` failed ("filters did not match")
  because bun was already rooted at `plugins/soleur` — the correct path was
  `test/components.test.ts`. Recovery: chain `cd <worktree-root> && …` per call.
  Prevention: already covered by the work skill's CWD-drift pitfall; one-off.
- **A review agent (code-quality) prescribed a hallucinated `gh workflow view --json state` flag.**
  Recovery: verified via `gh workflow view --help` before applying (the flag does
  not exist); used `gh workflow list --json path,state` instead.
  Prevention: the review skill's "verify reviewer-prescribed CLI flags before
  applying" sharp-edge already covers this; one-off (caught as designed).
- **A stale `/tmp/digest-sample.md` from a prior session blocked the Write tool.**
  Recovery: `rm` then re-Write. One-off.
- **shellcheck SC2034 (unused loop var) + SC1090 (non-constant source).**
  Recovery: `for _ in …` + a top-of-file `# shellcheck disable=SC1090` directive. One-off, fixed inline.

## Tags
category: workflow-issues
module: .claude/hooks/guardrails.sh
