# Learning: a "newest wins" reference picked my own unpushed work, and a filtered test run hid an import error

## Problem

Slice 2 of #10331 (user-mode lint ratchet, PR #10514) went through an 11-seat review, a 9-seat fix round and a 1-seat verification pass. Each round found defects in the previous round's fix:

- Round 0 (panel, ~100 findings): false greens from a symlink planted at the script path, a tag named like a base ref, nested ruff configs nobody fingerprinted, an exit 1 when `CLAUDE_PLUGIN_ROOT` was unset.
- Round 1 (fix round): the fix for "a stale `origin/HEAD` hides growth" changed the base choice from first-wins to "newest rung that carries the baseline wins". That made a local `main` with unpushed commits the newest rung, so growth was judged against the user's own unpushed work and passed. The old ladder caught it; the fix made it green.
- A second slip: removing a vacuous assertion from a test left an empty method body. I ran `python3 -m unittest … | grep -E '^(FAIL|ERROR)|^Ran|^OK|^FAILED'` and the empty output read as "nothing failed". It was an `IndentationError` at import, which the filter does not match.

## Solution

- Base choice among rungs: prefer remote rungs; use a local branch only when no remote rung carries the baseline. Judging against what the user has not pushed is judging against yourself.
- Always capture the exit code of a test run (`cmd > file 2>&1; echo RC=$?`) and read the verdict from the rc; a filter that matches only the lines you expect cannot report the lines you did not expect.

## Key Insight

A selector that picks "the best reference" by recency or similarity needs a fixture where the best candidate is the one you are checking. The reviewers (and I) tested stale-versus-current, never current-versus-own-unpushed. When a fix changes how a reference is chosen, enumerate which candidates can be the subject itself.

Second, the review loop is only as strong as its last pass: the verification seat existed for exactly this and found the one P2 that the fix round's nine seats did not, because it was asked "did any fix introduce a defect in its own area" rather than "what is wrong".

## Session Errors

- **Wrong tool name `bash` (case)** — Recovery: re-issued as `Bash`. **Prevention:** none needed (one-off).
- **`rm -rf "$(dirname …)"` blocked by the command-substitution safety check** — Recovery: ran in the session scratchpad and left cleanup to it. **Prevention:** use a literal path or the scratchpad; never remove through `$(...)`.
- **First fix commit introduced the local-main reference defect** — Recovery: verification pass found it; remote rungs now win. **Prevention:** a fixture where the subject is its own best reference (test added).
- **Empty test body plus a filtered run hid an `IndentationError`** — Recovery: re-ran with an explicit RC. **Prevention:** capture the rc and read the verdict from it (existing work-skill rule on verdicts and rc); never grep a test run for only the success shapes.
- **New ruff findings in tests I added (S110, F841)** — Recovery: fixed before commit; the shrink-only ratchet caught them as designed. **Prevention:** none needed.
- **A fix-round seat ran in another seat's sandbox via a shared fixed-name pointer file, and ran a pip install there** — Recovery: the seat re-ran its results in its own sandbox. **Prevention:** seat briefs say not to write fixed-name pointer files in the shared scratchpad (bullet added to `risk-tier-and-fix-rounds.md`).

## Tags
category: logic-errors
module: plugins/soleur/scripts/lint-ratchet.py
