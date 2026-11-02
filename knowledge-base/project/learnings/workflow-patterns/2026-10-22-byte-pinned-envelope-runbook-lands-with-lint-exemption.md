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

> **Addendum — 2026-10-27 (#11181 AC2 archival, PR #11348, ruling F2):** the class recurred on the second envelope-archival PR, and Session Errors line 15's "Prevention: none; the hook is the gate" is **measurably wrong for squash-merged PRs**. The `markdown-lint` CI job (`.github/workflows/pr-quality-guards.yml`) runs `--repo-sweep` over the whole tracked corpus as a REQUIRED context — it sweeps every tracked `*.md` regardless of what the branch staged, so no commit hook sees it coming, and lefthook never runs on the squash. This PR's plan phase ran 8+ measured probes and still missed the exemption; two review seats caught the omission (MD034:5, MD032:18, MD032:27 on the byte-pinned file) and the same-PR fix was exactly the 10789 pattern: one exact-path line under the `# DELEGATED-ACT ENVELOPES (#9757)` block in `.markdownlintignore`. **Prevention:** any plan that commits a lint-frozen/byte-pinned file must pre-run `bash scripts/markdown-lint.sh <path>` at plan time and reconcile the result against `.markdownlintignore` coverage BEFORE writing the ACs — the CI repo-sweep, not the hook, is the gate.
>
> **Second class in the same instance (AC self-reference at archival time):** the archival plan's AC-5 pinned "exactly one tracked copy" via a NAME-grep over `knowledge-base/` — measured clean at plan time only because the plan itself was still untracked. After the plan commit rode the branch, the same grep returned two lines: the envelope and the plan, whose filename shares the subject token. An AC whose predicate greps by NAME must be written against the file set that will exist at VERIFY time, including the pipeline artifacts the same branch commits; amend the predicate explicitly (two name-matches, exactly one `cmp` content match) rather than quietly satisfying a looser check. Related GFM-table trap: inside a table cell's code span only `\|` is an escape — writing `\^`/`\$` to be safe ships a regex that matches no path ever, and the review gate PASSes the row shape while the copied command cannot pass.

## Tags
category: workflow-patterns
module: delegation-envelopes
