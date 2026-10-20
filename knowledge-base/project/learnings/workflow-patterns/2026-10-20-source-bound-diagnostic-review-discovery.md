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

## Approved source/offline implementation addendum — 2026-10-20

The operator approved transport source and synthesized offline tests only.
Initial coordinator, transport and schema imports failed before implementation.
The coordinator's deadline regression then failed because gate time was outside
the budget; the clock now starts before the gate and execution passes the same
absolute deadline through preflight and collection. Failed coordinator results
are raised outside exception handlers to avoid retaining decoder context.

Harness corrections: the fake destination initially emitted body observations
for an error status the real transport refuses header-only; restrict its events
to the real path. Importing a TestCase directly duplicated unrelated discovery;
import its fixture module instead. A multiline with statement lacked a
continuation, an insertion displaced the output-replacement test tail, and a
synthetic preparation Namespace omitted two explicit paths. Each failure was
inspected and corrected before the successful run. Mutation oracles now require
a pristine pass and assertion failures rather than accepting instrument errors.
The schema BOM mutation originally removed only one of two independent guards;
its coupled mutant removes both and demonstrates the refusal boundary.

The first full offline run hit sandbox-denied local socket binds and resulting
fixture cleanup warnings; it was not a source/runtime verdict. The approved
rerun with local fixture access passed all 381 tests. Ruff initially scanned
only 115 tracked files because the seven new files were untracked; stage exact
paths before interpreting its coverage. It then found one unused test import,
which was removed; all 122 files pass at the existing 44-finding baseline.
The transport worker's guessed lint-script glob matched nothing; exact lefthook
discovery found the ratchet. Semgrep auto config rejects metrics-off; explicit
`p/python`, one worker and metrics off scanned all seven files with 151 rules,
zero findings and no JSON errors. No operational preparation or acquisition ran.

Independent source review reproduced a contradictory refused receipt: it claimed
Config validation without a destination send. New rehashed negative cases failed
first; validation now requires destination send/status/peer/TLS evidence for any
Config observation, and full length/digest evidence before the validation stage.
Each new invariant has a behavioral guard-removal oracle.

Test review found refusal rows whose incomplete event traces could fail later
for the wrong reason. Rebuild a valid trace with exactly one edited event and
assert refusal at that event, not merely eventual failure. The transport battery
now has exact pristine controls and explicit forbidden mutant outcomes; unrelated
internal errors are not mutation evidence. Real execution tests keep binding
verification connected while mocking only lower-level source inputs. They cover
binding drift before consumption and after token return, persisted fixed failure
receipts, CLI canaries, publication failure and a shrinking cross-stage budget.

Those execution tests found a raw receipt-write OSError escaping the direct API;
the new public execution wrapper raises a fixed refusal outside the handler.
They also exposed source-binding refusal misclassified as output failure; the
composite callback now preserves fixed binding/deadline categories. Moving that
callback into a handler changed its indentation, so mutation targets were updated
only after their explicit anchor-count failure; pristine controls still must pass.
The first receipt mutant was redundantly blocked by the schema-stage invariant;
its fixture now isolates length/digest observations from schema observations.

The execution-test worker guessed `config_transport.py`; discovery identified
`config_https.py`. The independent test reviewer's extra workspace mutation
allocator refused unavailable disk-backed bases; it performed no fallback
mutation and did not claim one. Committed test batteries use synthesized temporary
module fixtures and expose their own pristine/failure controls.

The approved file-only Config preparation preflight found the operational
contract's fixed component census still omitted all eight new Config files.
The downstream dependency gate would refuse before creating its directory;
no operational manifest was created. A synthesized prepared-contract regression
failed at that exact binding check first. The census and fixture now include
those files, and the behavioral test passes the generated contract through the
real dependency verifier before requiring refusal for each omitted reference.
The existing missing-committed-component battery also covers all eight files.
Review pure preparation across producer and consumer before requesting an
operational approval; isolated component coverage did not prove their integration.
The scoped Semgrep rerun initially refused its settings write in the sandbox;
the approved rerun must complete before any scan verdict is recorded.

The approved Config execution exited with its fixed refusal, while the private
output still contained only the reviewed manifest. Independent source review
confirmed the one-use marker is created before the first request and has no
removal path, so this attempt did not reach DNS or HTTP; the actual failing
local predicate remains unknown. A later read-only pre-consumption probe passed
current checks but cannot prove which historical check failed. The approval is
spent despite the absent marker. Preserve the failed directory, never retry it
or infer a network cause, and use only fixed allowlisted failure-stage labels
after a later separately approved attempt. Offline synthetic execution reached
the mocked request boundary with marker and transport mocked, and the real
marker writer passed in a separate synthesized private directory; neither
reconstructs the historical failure.

One diagnostic probe initially compared the manifest with a literal backslash
and `n` instead of a newline; its check failed locally, then passed after using
`bytes([10])`. A combined tool wrapper also returned `functions is not defined`
after the patch had landed; the diff was inspected and the focused test was run
separately. A scoped `sed` lookup used a repository-relative path while already
in the component directory; it read no file and was corrected by reading from
the worktree root. None of these results support an acquisition verdict.

## Resume diagnostic follow-through — 2026-10-20

A read-only probe ran branch-relative KB paths from the bare repository root and
received a missing-file error; repeat branch-content reads from the linked
worktree, whose paths are authoritative. The first installed go-command lookup
also used the wrong plugin subdirectory; resolve with `rg --files` under the
verified plugin root before reading. The required session-start merged-worktree
cleanup ran from the bare root but its lock files were outside the writable
filesystem boundary, so cleanup was skipped with an explicit warning. Do not
claim cleanup completed; if the gate must be retried, request the prescribed
filesystem escalation rather than bypassing the lock. These failures made no
repository or acquisition changes.

The first combined append patch did not match the learning's exact tail and
applied no hunks; re-read both file tails and applied the records against their
actual anchors. Confirm the final diff before committing multi-file notes.

The worktree `.git/info/exclude` lookup failed because `.git` is a gitfile here;
exclude configuration is not readable by that path. A guessed test helper name
also had no match. Use `rg --files` / symbol discovery before path or function
reads, and treat non-matches as no evidence rather than a repository result.
