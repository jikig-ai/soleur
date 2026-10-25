# Learning: English-text matches on git stderr, and fix-round work that existed only in a worktree

## Problem

PR #10893 (issue #10696, simulate the would-be index in `git-commit-secret-scan.sh`) took three fix rounds.
Two process failures and one code defect recurred in them:

1. Fix-round-3 work done by an implementer agent was uncommitted when the agent hit a weekly rate limit, and when
   the worktree directory was reaped mid-session. The round was redone from scratch; one more reap hit the
   replacement agent (it recreated the worktree from the pushed branch and lost only a few small edits).
2. The final verification pass found a false deny on a routine `cd <repo> && git add f && git commit`: the new
   "repository git cannot read" check matched git's English `not a git repository` wording, and the hook ran
   `git rev-parse --show-toplevel` without `LC_ALL=C`. With `LANGUAGE=de` the non-repo hook cwd read as
   unreadable and the commit was blocked. Before round 3 the same probe was `2>/dev/null || echo ""`, so this was
   a regression introduced by closing a fail-open seam.
3. The round-2 brief claimed "an arithmetic error becomes a deny" through the ERR trap. Bash abandons the command
   on an arithmetic error with no ERR trap and no non-zero exit, so the claim was false and had reached the hook
   header and the ADR.

## Solution

- Pin `LC_ALL=C` on both rev-parse probes (`add_root_of` in the hook, `ctr_resolve_roots` in the walker lib) and
  add rows R3 L1-L3 (translated git, non-repo hook cwd, repo target, three command shapes). Mutation-proved: removing
  the pin turns all three RED.
- Brief files live in the session scratchpad; implementers commit and push after every logical unit.
- Compute `GIT_CONFIG_COUNT` pins in decimal and length-cap them, and delete the "arithmetic error becomes deny" claim.
- The CTO's row 56 stopping rule ended the open-ended recogniser tail: after round 3 only a regression of a shipped
  claim, a false deny on a routine command, or a failed verification pass blocks ship; everything else is a
  documented ADR-301 residual.

## Key Insight

A fix that converts a silent allow into a deny must be audited for the inputs it now denies by accident. The
trigger here was not an attacker input but the user's locale. Any `case` over git's own message text needs the C
locale on the call that produced it, and the test for it needs a translated-git row (a hook suite run under
`LANG=C` can never see it).

Work that exists only in a worktree directory or an agent's context is not durable. The unit of durability is a pushed
commit; the brief for the next agent must be a file, not a conversation.

## Session Errors

- **Implementer agent hit a weekly rate limit mid-round; its uncommitted round-3 work was lost** — Recovery: fresh
  agent redid the round from the brief file — Prevention: brief implementers to commit and push after every logical unit
  (done in the second brief); keep the work list in a scratchpad file.
- **Worktree directory reaped mid-session (twice), losing uncommitted edits** — Recovery: `git worktree add` from the pushed
  branch — Prevention: commit and push per unit; tracker #11099 filed to find the reaper path.
- **Final verification found the LC_ALL gap (false deny under a translated git)** — Recovery: pinned `LC_ALL=C`, added rows,
  mutation-proved — Prevention: `.claude/hooks/README.md` hook-contract note; translated-git rows in the suite.
- **False claim "an arithmetic error becomes a deny" in the hook header and ADR** — Recovery: removed; decimal pin computed
  instead — Prevention: run the command that falsifies a causal claim before writing it into a header.
- **`shellcheck` glob over `.claude/hooks/lib/*.sh` matched unrelated suites and reported their findings** — Recovery: re-ran on
  the four files in the diff — Prevention: name the changed files, not a directory glob.

## Tags

category: logic-errors
module: .claude/hooks/git-commit-secret-scan.sh
