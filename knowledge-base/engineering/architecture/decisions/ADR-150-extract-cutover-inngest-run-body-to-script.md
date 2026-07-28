# ADR-150: Extract the cutover-inngest run body to a checked-in script

- **Status:** Accepted
- **Date:** 2026-07-28
- **Deciders:** engineering (CTO consult at plan Phase 2.5; six-agent plan-review panel)
- **Issue:** #7002
- **Supersedes:** none
- **Related:** ADR-030 (Inngest as the durable-trigger layer), ADR-149 (git-data host birth
  route and readiness interlock), #6997, #7042, #7044, #7045

## Context

`.github/workflows/cutover-inngest.yml` carried its entire cutover orchestrator — a
`set -euo pipefail` preamble, three helper functions communicating through an
`FSM_FAIL_REASON` global, and a `case` with 13 mutually exclusive arms — as **one `run:`
step of 118,722 bytes / 1,596 lines**.

`actionlint` pipes each `run:` body into `shellcheck` over a pipe. Above the pipe buffer,
actionlint blocks writing while shellcheck blocks reading, and the process never returns.
Measured on this repo at actionlint 1.7.7 / shellcheck 0.10.0:

- `timeout 25 actionlint .github/workflows/cutover-inngest.yml` → **rc=124**
- `actionlint -shellcheck= …` → **rc=0 instantly** (isolating the shellcheck integration)
- bisection: **65,043 bytes completes; 65,564 bytes hangs**
- `F_GETPIPE_SZ` on this host → **65,536**

The threshold is exactly the pipe buffer, and the unit is the **step**: one 117,954-byte
body hung, while the same content as 2 × 58,986 and 3 × 39,954 both returned rc=0.

The consequence was not "one file is unlinted". A bare `actionlint` invocation over the
workflow directory never terminated, so **the repo's only workflow linter reported nothing
at all, on every file**. That is the same shape as the two other defects fixed alongside
it: a check that cannot report is indistinguishable from one that passed.

Two constraints shaped the decision:

1. **The cutover is live and failing.** `cutover-inngest.yml` was dispatched twice on
   2026-07-24 and both runs concluded `failure`; #6940, #6921, #6753 and #6488 are open
   against it.
2. **It is `workflow_dispatch`-only.** No CI signal exists that could detect a defect
   introduced by restructuring it — a bad change surfaces at the next cutover attempt.

## Decision

**Move the `run:` body verbatim into `scripts/cutover-inngest.sh` and reduce the step to
`run: bash "${GITHUB_WORKSPACE}/scripts/cutover-inngest.sh"`.**

The move is provably verbatim: the body contains **zero `${{ }}` GitHub expressions** and
**zero heredocs** (its only `<<` occurrences are five herestrings, `<<<`), so it reads
nothing but process environment, which a child `bash` inherits from the step's `env:` map.
The extraction is verified by parsing the `run:` block scalar with PyYAML and comparing it
byte-for-byte against the script minus its shebang, **with no whitespace normalization** —
normalization is precisely the transform that would hide a dedent error.

**Home is `scripts/`, not `.github/scripts/`.** `.github/scripts/` holds six `check-*`
PR-quality guards fed to a required check via `test/run-all.sh`, and is swept by nothing in
`scripts/test-all.sh`. Six existing workflow-invoked scripts already use exactly this shape
from `scripts/` (`apply-web-platform-infra.yml:1968, :2196`; `apply-sentry-infra.yml:308,
:321, :407, :621`).

**A `ci.yml` step guards the deadlock directly.** It installs a pinned, SHA-verified
actionlint and runs `timeout 120 actionlint .github/workflows/`, failing **only on
`rc=124`**. It asserts *not hung* and nothing else, which is what lets it land while 93
pre-existing findings remain open (#7042) — the objection that kept actionlint out of CI.

## Consequences

### `scripts/cutover-inngest.sh` is now a runtime dependency of a production cutover path

The workflow's `actions/checkout` step was already unconditional, but its name and comment
read `Checkout (for betterstack-query.sh — op=arm/rollback FSM confirm)` and described
itself as *"Harmless (no-op source read) for the webhook ops"* — an open invitation to gate
it `if: inputs.op == 'arm' || …`. Post-extraction that would break **every** op, on a path
with no CI signal. The step's name and comment are rewritten in this change to state that
checkout is required by all ops. **No CI signal exists here; the in-file wording is the
mitigation.**

### The extracted script ships without a companion test suite

Every other workflow-invoked script in `scripts/` has a `tests/scripts/test-<name>.sh`
registered in `scripts/test-all.sh` (`:380` for `registry-pull-path-health`, `:418` for
`sentry-create-gate`). `scripts/cutover-inngest.sh` does not — a suite for a 1,596-line
cutover orchestrator is its own project, tracked in #6753's refactor census.

This is still a strict improvement: the body had **no test and could not be linted at all**
before. `shellcheck scripts/cutover-inngest.sh` now completes and covers it directly.

### A retracted claim, recorded rather than deleted

An earlier revision of this decision asserted that extraction was *"strictly more
fail-closed"*, because the script would carry an explicit `set -euo pipefail` where the
inline step merely inherited GitHub's default `bash -e {0}`. **That is false** — the run
body's own first line already was `set -euo pipefail`. **Extraction is posture-neutral.**
The two real wins are that actionlint terminates and that shellcheck lints the body
directly.

It is recorded rather than quietly corrected because asserting an unmeasured safety
improvement is the defect class this change exists to fix.

Similarly: the plan for this work asserted the body contained no `::add-mask::`. It contains
**four live `printf '::add-mask::%s\n'` calls**. Extraction is still safe — workflow
commands are parsed from the **step's stdout**, which a child process inherits — but the
claim was wrong and the reason it is safe is a different reason than the one asserted.

### `tests/scripts/lib/` is a production runtime path

Recorded here because the companion change in this PR (#6997) takes
`tests/scripts/lib/plan-gate-preamble.sh` from **1 consumer to 9**. One file in a directory
named `tests/` now governs whether every destructive-infrastructure gate can fail closed,
and it is sourced at production runtime by `apply-web-platform-infra.yml`.

**A future `tests/` reorganisation, or a sparse checkout that excludes `tests/`, would
disarm all nine gates at once.** No mechanical guard exists for this; naming it here is the
mitigation.

### The CI hang guard is advisory, not blocking

It is hosted in the `lint-bot-statuses` job, which is absent from both
`scripts/required-checks.txt` and the CI-Required Terraform ruleset — so a PR can merge
with it red. This is stated rather than left implied: a gate that claims teeth it lacks is
worse than one that does not, because it stops people looking. Promoting it is a deliberate
follow-up requiring the job to be added to `required-checks.txt` **and** the ruleset
together.

## Rejected alternatives

### Split the `run:` body across multiple steps

This was #7002's own suggested fix and the plan's original direction. Rejected because
**every failure mode of the split fails OPEN**, in the same direction as the three defects
this work closes:

- an `if: inputs.op == …` typo makes an op run **nothing** while the job reports success;
- GitHub's default shell is `bash -e {0}`, so a dropped `set -o pipefail` silently converts
  a fail-closed pipeline to a fail-open one;
- `confirm_flip_state` is called from both the `arm` and `rollback` arms; duplicating it
  across steps lets the two drift undetectably until rollback day;
- the three helpers communicate through an `FSM_FAIL_REASON` global that does not survive a
  step boundary.

None of these is detectable by CI on a `workflow_dispatch`-only workflow. Extraction
achieves the same size reduction and **pays none of these costs** — the body stays in one
step and one process, so cross-step state loss, `set -o` inheritance, `if:`-arm
completeness and helper drift all cease to exist as risks rather than being mitigated.

### `exit 1` instead of `return 1` inside `plan-gate-preamble.sh`

Proposed to immunise gates against a caller that suppresses the return code. Rejected:
it would require a test-mode environment variable or a subshell invocation in every one of
the nine gate suites — pervasive test-harness complexity for a narrow risk. All 20 gate
call sites in `apply-web-platform-infra.yml` are non-suppressing today; a lint for the call
site is tracked separately in #7045.

### A run-block byte-count linter

Rejected in favour of the `rc=124` guard. A byte count is a **proxy** for a defect that has
a **direct** exit-code signal; it would need PyYAML, a threshold to re-tune as the buffer or
the tool changes, and a permanent exclusion for the very file that exposed the bug.
