---
title: Discover review inputs before reading source-bound diagnostic artifacts
date: 2026-10-20
category: workflow-patterns
pr: 9051
---

During the bounded redirect diagnostic review, broad combined inspection output
was truncated. Narrow reads to individual symbols or small line windows and
inspect every result before making a review claim. Avoid reprinting large skill
files already loaded in the current workflow.

A reviewer guessed `binding.py` and `preparation.py`; discovery instead identified
`prepare.py`. After compaction, the coordinator also guessed a branch `spec.md`
and received an explicit missing-file error. The actual handler-wiring plan
states that this branch has no such spec. Use `rg --files` to discover artifacts
before reading them; the operative diagnostic scope lives in
`prebuild-acquisition-2026-10-16.md`. These failed reads made no mutations or
network requests. Clear failures make a learning sufficient; no new global rule
is needed.

The actual-manifest reviewer initially projected a yielded shell result to its
output field, losing the process session identifier. That invocation's result
was not claimed. The reviewer repeated the file-only validation while retaining
the complete tool result and session identifier. Preserve process IDs until
completion, inspect exit status, and never infer success from empty output.
Its first final-check script also had an unmatched parenthesis and stopped
with SyntaxError before imports or actions. The corrected final check passed;
only completed successful checks support the review verdict.

Uncommitted review records must stay distinguishable from the source-bound
manifest: keep tracked HEAD fixed through approval and execution, then include
sanitized review and evidence records in the next source change. Any source,
input, CA, platform, or private-output identity change requires fresh bindings
and review rather than reuse of the approved command.

## Proposal-resume addendum — 2026-10-20

The Config proposal resume repeated overlarge skill/script reads and a learning
path guess that omitted `workflow-patterns/`. Delegated exploration also guessed
`spec.md` and `role_admission.py`; discovery found `test_role_admission.py` and
`image_observations.py`. A stray inspection targeted a nonexistent temporary
probe and failed before any action. Discover exact paths first and keep each
read bounded; a failed read supplies no evidence. A process search matched its
own sandbox wrapper, producing noisy output rather than useful ownership data.
Prefer retained tool session identifiers for liveness. Docker documentation's
Edit link returned a web-tool internal error; the official documentation page
itself loaded successfully and supplies the cited exact-host listing. No failed
probe is used as a successful check or as origin/ownership evidence.

Git staging and the workflow tally initially encountered read-only Git metadata
in the sandbox; rerunning the necessary operation through the approval tool
resolved it. A commit hook evaluated the ambient bare-root context despite the
shell tool's workdir argument and blocked the attempt as a main-branch commit.
Verified the feature branch, then used an explicit `cd <worktree> && git commit`
so hook and shell resolved the same location; the commit succeeded. The first
hook-source lookup also guessed the installed plugin's path; discovery located
the project's `.claude/hooks/guardrails.sh`. These refusals were not commits.

Security proposal review found two design omissions before implementation:
OCI's normative optional-null rule disagrees with its supplied schema, and a
promise to define a receipt later leaves its disclosure boundary undefined.
The proposal now states prose precedence and the exact closed receipt contract.
Its future validator must pair omitted/null/invalid-type tests and reject all
unlisted receipt fields rather than exporting validator messages.

The final read-only PR-scope probe hit a mise `gh` installation attempt against
read-only tool storage. Repeating that exact read through the approval tool
succeeded and returned the PR's linked issue numbers. Treat shim-install
failure as a tool-resolution failure, not as a GitHub result; keep the Git
cleanliness probe separate so a failed first command cannot hide its status.
