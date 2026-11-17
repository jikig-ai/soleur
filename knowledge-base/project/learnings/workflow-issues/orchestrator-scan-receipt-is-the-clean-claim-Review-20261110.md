---
module: Review
date: 2026-11-10
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "A review seat reported zero SAST findings without a readable scan receipt"
  - "SOLEUR_REVIEW_SCAN_GATE refuse stopped the phase when the receipt could not be read"
  - "A short path list could still print ok findings=0 for a subset of the range"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: high
tags: [review, sast, semgrep, shellcheck, fail-closed]
---

# Learning: A clean review scan is the orchestrator's receipt

## Problem

`soleur:review` asked `semgrep-sast` to scan and then believed that seat's zero-finding report. A skipped scan and a lost log looked the same as a clean diff. Issue #12530.

## Environment

- Module: Review
- Affected Component: `plugins/soleur/skills/review`
- Date: 2026-11-10

## Symptoms

- A zero-finding SAST claim had no stdout line a later step could read back.
- The public HephaestusNG description runs a scan before the review agent. It does not document rejecting an unread clean result. That fail-closed property is Soleur's, from the hole and in-repo learnings.
- On the fix range the receipt was `SOLEUR_REVIEW_SCAN_GATE ok engine=shellcheck files=1 rules=0 findings=0`.

## What Didn't Work

**Attempted Solution 1:** Keep the scan inside `semgrep-sast` and treat its report as the evidence.

- **Why it failed:** The seat's own report is the thing that can be skipped. The orchestrator never saw a receipt.

**Attempted Solution 2:** Reuse `prepush-secret-scan.sh` as the gate.

- **Why it failed:** That script's exits 0 and 43 continue. This gate must stop on anything other than a parsed `ok` or `skip`.

**Attempted Solution 3:** A second read of a findings file, or a port into `review.workflow.js`.

- **Why it failed:** The CTO cut is one script and one stdout receipt. The workflow prototype stays unwired. The skill is the authority.

## Session Errors

**Hermetic suite could not find bash**

- **Recovery:** `run_gate` uses `env -i PATH="$arm/bin" HOME="$arm" /bin/bash`, and the arm symlinks `bash`.
- **Prevention:** A hermetic `PATH` must include every external binary the script calls. `pwd` stays a builtin. Do not symlink it.

**Hermetic suite could not find dirname**

- **Recovery:** Symlink `dirname` into the arm. After that, `cd` had a directory.
- **Prevention:** When a stub arm returns `command not found`, add that binary before debugging the scan result.

**A stub concatenated two scanned paths into one JSON string**

- **Recovery:** The stub appends paths with `printf '%s\n'` and Python reads that file. Command substitution had stripped the newlines.
- **Prevention:** Do not pass a multi-line path list through an unquoted command substitution.

**markdownlint MD012 after a deleted block**

- **Recovery:** Collapse the double blank lines. Do not run markdownlint `--fix` on MD037, MD038, MD049, or MD050.
- **Prevention:** After deleting a paragraph, check the blank lines on either side.

**shellcheck treated a comment as a directive**

- **Recovery:** Reword so no comment line begins with `shellcheck`.
- **Prevention:** A line that starts with `shellcheck` is a directive even inside a comment.

**shellcheck SC2329 on the cleanup function**

- **Recovery:** The only caller is `trap`. Add `# shellcheck disable=SC2329` with that reason. The re-scan was `findings=0`.
- **Prevention:** A function used only from `trap` is an indirect call. Silence that info finding in the function's own comment.

**git exit 128 in the bare checkout**

- **Recovery:** Later commands `cd` the feature worktree.
- **Prevention:** This host's primary checkout is bare. Run git from the worktree.

**gh issue view rejected authorAssociation, and 12530 is not a PR**

- **Recovery:** Drop the unknown field. Treat `gh pr view 12530` as "not a pull request".
- **Prevention:** Confirm the number is a PR before `gh pr view`. Do not request `authorAssociation` from `gh issue view`.

**Two plan-review seats returned HTTP 500**

- **Recovery:** Retry the same seats. The retries finished. Do not spawn that panel again.
- **Prevention:** A 500 on spawn is a retry, not a missing review.

**The forged-stub suite stayed green when the body-line filter was disabled**

- **Recovery:** The stub now returns the targets in `paths.scanned`. The row expects an exact `refuse` with `rules=0`. A `.js` file and two `test/` files have their own rows. Commit `fcc094ffe9`.
- **Prevention:** A refusal can come from a second cause. Disable the predicate under test and require that row to go green, not merely to stay red.

**Review seats were still running after a 540s wait**

- **Recovery:** Wait again. All eleven panel seats returned. Do not kill a seat because a wait returned.
- **Prevention:** A wait timeout is not a seat failure.

**The issue's Hephaestus fail-closed sentence was stronger than the public description**

- **Recovery:** Functional discovery recorded that the public description only runs a scan before the review agent. The fail-closed property is written as Soleur's.
- **Prevention:** For every causal or universal claim copied from an issue or a sibling artifact, name the command that would falsify it and run it before the plan treats the claim as the competitor's behavior.

**fixture-relative-assert failed two rows that are not in this diff**

- **Recovery:** `git diff origin/main` for `scripts/ci-oracle-review.sh` and the baseline file was empty. Left them. Did not rewrite the baseline.
- **Prevention:** A red row outside `git diff origin/main` is not this PR's failure. Do not `--write-baseline` to clear it.

**A sibling worktree held the test-all lock**

- **Recovery:** Did not start `scripts/test-all.sh`. Fast suite `review-scan-gate.test.sh` was 32 passed, 0 failed. CI's required `test` check is the full battery.
- **Prevention:** When `scripts/test-all.sh --capacity` prints `CAPACITY_CONTENDED`, do not queue a second full run. The standing waiver uses CI's required test check.

## Solution

The orchestrator runs `plugins/soleur/skills/review/scripts/review-scan-gate.sh` on the path list for the range under review, before every seat, including a fix round and an inline review that spawns no seat.

Continue only when that script's own tool result has `ok` or `skip` on a `SOLEUR_REVIEW_SCAN_GATE` line. `probe`, `refuse`, any other token, a non-zero exit, or a missing line stops the phase.

A zero-finding SAST claim is valid only when that line is `ok`, `findings=0`, and `files` equals the classified source-and-shell count of the path list. `skip` is not a clean claim. Findings stay on stdout and do not stop the phase.

```bash
# Receipt shape (status token, then counts, then finding lines):
SOLEUR_REVIEW_SCAN_GATE ok engine=mixed files=3 rules=218 findings=0
```

`files` counts classified source and shell targets. A lockfile or a deletion does not increment it. Semgrep `ok` needs a `Ran N rule(s)` summary with N>0 and `paths.scanned` mapped onto every source target. Shellcheck `ok` needs the binary to have run with every shell target on argv. `rules=0` is legal only after that execution.

## Why This Works

1. The evidence is a line the orchestrator produced, not a sentence the seat composed.
2. `files` binds the receipt to the range. A short argv can still print `ok findings=0`, and that line is not a clean claim for the range.
3. One stdout receipt avoids a second findings file and a second scanner. `semgrep-sast` quotes the line and does not invoke semgrep or shellcheck.

## Prevention

- Run the script and parse its line before any review seat, including `--fix-round`.
- Quote `files`, `rules`, and `findings` from that line. Do not accept a seat's "0 findings" without it.
- Keep the hermetic suite's refusal rows exact. A prefix match of `refuse` can be a different failure.
- Do not wire this gate into `review.workflow.js`. The suite fails if the script appears there.

## Related Issues

- Issue: #12530
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-324-review-scan-evidence-is-the-orchestrator-read.md`
- See also: `knowledge-base/project/learnings/2026-08-06-i-shipped-two-unmeasured-causal-claims-inside-the-lint-that-forbids-them.md`
