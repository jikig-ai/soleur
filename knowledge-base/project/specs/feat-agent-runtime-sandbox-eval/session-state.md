# Session state: feat-agent-runtime-sandbox-eval (2026-11-10)

Plan: `knowledge-base/project/plans/2026-11-09-feat-agent-runtime-sandbox-eval-injector-first-plan.md`. Tasks: `tasks.md` here. CTO rulings: `decision-challenges.md` here (F-a..F-g, R1..R42, D1..D4; R36..R42 are the review rulings).

## Where it stands

- Verdict **GO** on run 42880042135 (head f33a8c7b58), measured after the PR review and its fix round (run 42871893115, an earlier GO, predates the fix round). The earlier GO (run 42823659776) was withdrawn by CTO R40; runs 42864371897 and 42868332624 read NO-GO on harness judges the review's changes broke (fixed, the mechanism unchanged).
- Review (13 seats, rulings R36 to R42) fixed inline; every new hook/policy guard mutation-proven (17/17). Results note, results JSON, ADR-325 measured outcome and the ADR-311 addendum rewritten from run 42880042135.

## Next

1. Re-merge main (#12594 landed the ADR-276 MD032 fix; #12562, the inngest pin, is still open), then `soleur:ship`: the PR body's first line names both merge effects (CTO R41); issue lines from `print-verdict.sh` (GO: `Closes #12517`, `Closes #12467` with ADR-325's reopen triggers); on merge, the #11637 comment.
