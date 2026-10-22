# Learning: a byte-pinned envelope runbook lands by copy plus a lint exemption, never a reformat

## Problem
A delegated-merge Production Envelope (`delegated-merge-10789-envelope.md`) was authored on a scratch branch and never reached `main`. Its sha256 is bound into a receipt comment on the epic, and `delegation-verify.sh` parses its layout, so markdownlint "fixes" (a URL in angle brackets, an extra blank line) would change the hash and void the receipt.

## Solution
Copy the byte-identical backup into the PR branch, check `sha256sum` against the pinned value before and after every lint or commit step, and add the exact file path to `.markdownlintignore` under the existing envelope comment block. Land it as a docs-only PR that says `Ref #<epic>` so the umbrella stays open.

## Key Insight
Committing the envelope to `main` grants no authority: `delegation-verify.sh` binds authority to the admin-authored, unexpired, unedited issue comment, and reads the envelope from the caller's checkout. The risk in this class is the hash, not the file.

## Session Errors
- **Planning subagent invented the decision class `mechanical`.** Recovery: the technical-ruling gate rejected it (rc 1) and one batched CTO spawn ruled the three rows. Prevention: none beyond the gate, which worked; the subagent prompt already lists the three allowed classes.
- **Tally commands ran in the new worktree before `init`.** Recovery: ran `pipeline-tally.sh init` there. Prevention: run `init` as the first tally call after `cd` into the worktree (one-shot Step 0d already says so).
- **No local markdownlint binary found.** Recovery: relied on the commit hook, which lints staged Markdown and exempts the listed path. Prevention: none; the hook is the gate.
- **Closing line promised a next step and the Stop hook blocked it.** Recovery: ended with a `Paused:` sentence naming the wait. Prevention: already hook-enforced.

## Tags
category: workflow-patterns
module: delegation-envelopes
