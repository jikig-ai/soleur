---
title: "feat: ci-head-verdict.sh required subcommand (required-context set check)"
date: 2026-10-29
slug: ci-head-verdict-required-set
branch: feat-one-shot-ci-head-verdict-required-set
issue: 9927
type: feat
lane: cross-domain
pr: 11542
brand_survival_threshold: none
---

# feat: `ci-head-verdict.sh required <pr>` (required-context set check)

Spec lacks valid `lane:` (no `spec.md` for this branch): defaulted to `cross-domain` (TR2 fail-closed). The domain sweep below found engineering only.

## Overview

A green `ci-head-verdict.sh verdict` plus an armed auto-merge did not prove that every ruleset-required context exists on the PR head. PR #11254 sat un-enqueued for about 70 minutes because one required context (`cla-evidence`) never reported: its `pull_request_target` run had been cancelled during a push. `verdict` reads only the `test` row of `ci.yml` pull_request runs, so it could not see a context owned by another workflow (learning `knowledge-base/project/learnings/workflow-issues/2026-10-28-a-green-verdict-and-an-armed-auto-merge-do-not-prove-a-required-context-exists.md`).

Add an additive, read-only subcommand `ci-head-verdict.sh required <pr>`. It reads the PR head SHA, runs `admin-merge-ready.sh <pr> <head-sha>` without `--wait`, parses that script's marker (`absent` / `pending` / `failed` arrays), and prints one new marker line `SOLEUR_CI_REQUIRED_SET`. For an absent context it also prints (never runs) the `gh run rerun <id>` line for the cancelled run that owns it. The `verdict` state set stays closed; no ruleset logic is copied.

Binding input: CTO ruling 2026-10-29 (Ruled by CTO agent) plus the sub-fork rulings F1 to F7 recorded in `knowledge-base/project/specs/feat-one-shot-ci-head-verdict-required-set/decision-challenges.md`. Epic #9927 stays open; this gap leaves the epic's LUKS scope (stated in the PR body, `Ref #9927`, never `Closes`).

## Research Insights

### Premise Validation (Phase 0.6)

Checked: epic #9927 is OPEN (the hold "the ci-head-verdict.sh gap" is in its Operator Holds list, Class `technical`); draft PR #11542 is this branch's PR; `plugins/soleur/scripts/ci-head-verdict.sh` (411 lines) and `admin-merge-ready.sh` (545 lines) exist on this branch and match the brief (read in full). The collision pre-check found no open PR naming #9927 and only unrelated foreign `test-all.sh` processes. Held: the brief's claim that `verdict` reads only `ci.yml` pull_request runs (`read_test_row` and `read_newest_run`), that `admin-merge-ready.sh` iterates the ruleset-required set (its `$req` reduction over every `required_status_checks` rule), and that it never merges (no `gh pr merge` in the script; `--wait` only polls). Stale or corrected: nothing stale. ADR corpus check: ADR-276 owns `ci-head-verdict.sh`; the new marker does not change its decision (no `required` mechanism sits in any Alternatives table). Corrections to the brief are in the reconciliation table below.

### Property List (Phase 0.6b)

1. P1: one read-only command tells a reader whether every ruleset-required context is present and green on a PR head.
2. P2: an absent required context is told apart from a pending or failed one, by name.
3. P3: no read failure, and no marker the parser cannot prove, ever reads as `complete`.
4. P4: the `verdict` state set, its marker and every consumer whitelist stay unchanged.
5. P5: the required-set logic exists once (in `admin-merge-ready.sh`); no second copy.
6. P6: a reader is told which cancelled run to re-run, and the script never re-runs it.

### Cut List

| Mechanism | Property | Disposition |
|-----------|----------|-------------|
| Delegate to `admin-merge-ready.sh` without `--wait` | P1, P2, P5 | Kept. Grepped the authority (`admin-merge-ready.sh`, `check_once`): it already unions every `required_status_checks` rule, pins app ids, and reads absent as ABSENT. |
| New marker `SOLEUR_CI_REQUIRED_SET` | P2, P3, P4 | Kept. Extending `SOLEUR_CI_HEAD_VERDICT` is forbidden (closed set, consumers whitelist it). |
| Cancelled-run lookup for the recovery line | P6 | Kept as TWO tiers (CTO F5', after plan review): one runs-list read, unique normalized workflow-name match, else candidates. The job-name tier and its up-to-10 jobs reads are cut. |
| Per-run jobs reads (`actions/runs/<id>/jobs`) | P6 | Cut (CTO F5'): an ABSENT context has no check run, so it is unlikely to appear in any jobs list; no evidence tier (a) ever matches. |
| Wiring `monitor-pr-checks.sh` and the Phase 7 poll in this PR | P1 (reach) | Cut to a tracked follow-up (CTO F1). |
| A `--wait` form of `required` | none | Cut: the brief excludes it, and `admin-merge-ready.sh --wait` already exists for the merge path. |
| Running `gh run rerun` | none | Cut: the brief says print only. |
| A new test file | none | Cut: extend `ci-head-verdict.test.sh` (owns the stub, mutation harness and floors; a new file needs a shard-ledger row and CODEOWNERS line). |
| Copying ruleset parsing into `ci-head-verdict.sh` | none | Cut (P5). |

### Institutional learnings applied

- The motivating learning above (diff required vs latest rollup per name; re-run the cancelled owner; do not sync or re-arm). Its Session Error 1 names this exact fix: reuse `admin-merge-ready.sh`, add no second copy.
- `2026-10-10-an-error-must-not-borrow-a-success-states-vocabulary-and-every-consumer-stub-hid-it.md`: an error marker must not borrow `[]` or `complete` vocabulary. Applied: error markers print `-` for unknown scalars and arrays (F3 extension).
- `2026-09-25-gh-stub-must-mirror-real-cli-flags.md` (cited in the suite header): the gh stub is keyed on the full real argv and refuses the rest with `STUB-MISS`.
- `2026-10-23-a-reversed-fixture-order-closes-the-first-element-survivor-only.md`: fixtures that put the interesting member second (second absent context, third non-empty array).
- `cq-test-fixtures-synthesized-only`: all fixtures synthesized (the required set `{test, cla-evidence}` is built by the test, not captured).
- AGENTS.md `hr-verify-repo-capability-claim-before-assert`: the "never merges" and "reads only `ci.yml`" claims were grepped in the authority files, not assumed.

### Evidence for the owner lookup (read-only, 2026-10-29)

`gh api "repos/{owner}/{repo}/actions/runs?head_sha=<PR #11254 head>"` returns, at that exact head, the `pull_request_target` run 40656550847 (workflow `cla-evidence`, `run_attempt: 2`, now success after the re-run) AND a stale cancelled `pull_request` run 40656555862 (workflow `CI`). So the `head_sha` filter does reach `pull_request_target` runs (plan review flagged this as unverified), the workflow name equals the required context `cla-evidence`, and a cancelled run of an unrelated workflow sits beside it, which is why a unique-name match, not "any cancelled run", is the only single-line hint. Job-name matching was dropped (CTO F5'): an absent context has no check run, so it is not expected in a jobs list.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|-------------|---------|---------------|
| "calls `admin-merge-ready.sh <pr> <head-sha>`" | `admin-merge-ready.sh` needs the full 40-hex head SHA as its second argument; `ci-head-verdict.sh` has `read_pr` (head SHA, draft flag) but `required` needs no ready event | Reuse `read_pr` for the SHA (pinned to the argv `api -i repos/{owner}/{repo}/pulls/<pr>` the stub already serves); the child re-checks that the head still equals it (rc 4 `head-moved` becomes `error`) |
| "parses its absent/pending/failed arrays" | On `untrusted-ci`, `base-mismatch` and early errors the three arrays are always `[]` because classification never ran (`check_once` returns before the classifier) | `not-ready` with no populated array is `error`, never a state; this covers `untrusted-ci` (CTO F6) without a special branch |
| "it never merges in that form" | `admin-merge-ready.sh` never merges in any form; `--wait` only polls (grep: no `gh pr merge` line) | Say so in the header; the plan does not add `--wait` |
| "`gh run rerun <id>` for the cancelled run owning the absent context" | No code maps context to run; an absent context has no check run at the head | New lookup: one runs-list read at the head, unique normalized workflow-name match, else candidates (F5') |
| Marker `... pr= sha= absent=[..]` | CTO F3 fixed the order: `state pr sha required reason absent pending failed` (arrays last, since names hold spaces) | Follow F3; the consumer-visible prefix `state pr sha` is as briefed |
| `--repo` | `admin-merge-ready.sh` has no `--repo`; it resolves `{owner}/{repo}` from the cwd or `GH_REPO` | `required` honours `--repo` by the existing `export GH_REPO`, which the child inherits |
| (implicit) the child defaults to `--base main` | A PR on another base would always read `base-mismatch`, i.e. `error` | `read_pr` additionally captures `.base.ref` and `required` passes `--base` |
| The hold says the gap is in the epic's scope | It is not a LUKS item | PR body states it moves out of the LUKS scope; `Ref #9927` |

## Problem Statement

A reader (the monitor, the ship Phase 7 poll) that sees a green `verdict`, an armed auto-merge and a PR that does not enter the merge queue cannot tell "waiting for the queue" from "a required context never reported". `gh pr checks` lists only checks that exist, so an absent required context is invisible. The resolver for "is the required set complete" already exists (`admin-merge-ready.sh`) but is reachable only as a merge gate, not as a read-only diagnostic with a recovery hint.

## Proposed Solution

### CLI contract

```text
ci-head-verdict.sh required <pr> [--repo OWNER/REPO]
```

Last stdout line, always (one marker, nothing after it):

```text
SOLEUR_CI_REQUIRED_SET state=<complete|absent|pending|failed|error> pr=<N> sha=<H|-> required=<n|-> reason=<token> absent=<json|-> pending=<json|-> failed=<json|->
```

Arrays are compact JSON on one line and come last (context names contain spaces, parentheses, `#` and `:`). On `state=error` every unknown scalar (`sha` before the PR read, `required`) and all three arrays print `-`, never `unknown` or `[]` (F3). Exit: 0 for any decided state (`complete`, `absent`, `pending`, `failed`), 3 for `state=error`, 2 for usage (no marker, no gh call). **Callers must read the marker, not the exit code**: `absent`, `pending` and `failed` all exit 0, so an `&&` chain reads them as success. Recovery lines print BEFORE the marker, prefixed `RECOVERY `.

Reason vocabulary. Tokens `required` itself emits (closed list, stated in the header and in `ready-run-wait.md`): `api-error`, `missing-tool`, `mktemp`, `no-admin-merge-ready`, `no-marker`, `child-rc-<n>`, `marker-mismatch`, `marker-unparseable`, `rc-mismatch`, `ready-with-gaps`, `required-unknown`, `no-culprit`. Tokens passed through from the child, informational only (a consumer must not switch on them): `all-green`, `not-green`, `stalled`, `awaiting-approval`, `untrusted-ci`, `base-mismatch`, `empty-required`, `unsupported-rule`, `unpinned`, `incomplete-files`, `head-moved`, `not-open`, `interrupted`.

Test seams: `ADMIN_MERGE_READY_BIN` (default: `admin-merge-ready.sh` next to this script; mirrors `CI_HEAD_VERDICT_BIN` in the other direction). No other new env.

### State mapping (one function, one emit point)

Evaluated top to bottom; the first match decides.

| # | Check | Result |
|---|---|---|
| 1 | child not readable | `error` `no-admin-merge-ready` |
| 2 | child exit code outside `{0,1,3,4}` (usage 2, interrupted 130, crash 124 to 127 and the like), even with a marker | `error` `child-rc-<n>` |
| 3 | no stdout line starting with the marker prefix | `error` `no-marker` |
| 4 | not exactly one such line, or it is not the last stdout line, or it does not start with the strict ordered prefix `verdict=<tok> pr=<our PR> sha=<our SHA> base=<tok> reason=<tok> required=<int> absent=`, or the tail does not split into `absent=A pending=P failed=F` that re-joins byte for byte, or A/P/F is not a JSON array of strings, or their total length exceeds `required` | `error` `marker-unparseable` (`marker-mismatch` when only `pr=`/`sha=` differ from ours) |
| 5 | (rc, verdict) pair not in `{(0,ready), (1,not-ready), (3,error), (4,stale)}` | `error` `rc-mismatch` |
| 6 | rc 3 or 4 | `error`, child reason passed through when it matches `^[a-z][a-z0-9-]*$` |
| 7 | rc 0, `required` > 0, three empty arrays | `complete`, child reason (`all-green`) |
| 8 | rc 0, `required` is 0 | `error` `required-unknown` |
| 9 | rc 0, any array non-empty | `error` `ready-with-gaps` |
| 10 | rc 1 and `required` is 0 | `error` `required-unknown` |
| 11 | rc 1, at least one array non-empty | `failed` if `failed` non-empty, else `absent` if `absent` non-empty, else `pending` (F2) |
| 12 | rc 1, three empty arrays (`untrusted-ci`, `base-mismatch`, bare `not-green`) | `error`, child reason passed through (`no-culprit` replaces bare `not-green`) |

`reason=untrusted-ci` is therefore `error` unless an array is provably populated (F6), in which case row 11 maps it like any other `not-ready`; the populated case cannot occur in today's `admin-merge-ready.sh` and is fixtured so a future change cannot silently flip it. A PR whose base is not `main` is handled by passing `--base <PR base>` (captured by `read_pr`), not by an error.

### Recovery text (decision already made; read failures degrade the text only)

- `absent`, reason not `stalled` / `awaiting-approval`: read `actions/runs?head_sha=<sha>&per_page=100` ONCE (paginated, all workflows, no per-run reads). Keep runs with `conclusion == "cancelled"` at that exact SHA, newest id first. For each absent context (F5', stricter than F5): if EXACTLY ONE cancelled run's workflow name, lowercased with non-alphanumerics stripped (in jq, for bash 3.2 portability), equals the context normalized the same way, print `RECOVERY rerun ctx=<json> run=<id> basis=workflow wf=<json>`. Otherwise print one `RECOVERY rerun ctx=<json> run=<id> basis=candidate wf=<json>` line for every cancelled run at the head and the sentence "owner not determined, read the run before re-running". No cancelled run: say so and print no rerun line. `ctx` and `wf` go through jq `@json` (`wf` cut to 80 characters); `run` is a validated integer; no PR-controlled free text reaches the output.
- `absent` with reason `stalled` / `awaiting-approval` (the draft run's `test` row, set by `soften_test_row`): no lookup; print the pointer to `ship/references/ready-run-wait.md`.
- `failed` / `pending` (F7): one `RECOVERY` pointer naming the context names and `gh pr checks <pr>`; no rerun command.
- A failed runs-list read prints `owner not determined (read failed)`; the state does not change.

### Implementation sketch (names, not code to paste)

In `plugins/soleur/scripts/ci-head-verdict.sh`: `readonly REQUIRED_MARKER`; extend the subcommand `case` and `usage()`; `read_pr` also captures `.base.ref` into `PR_BASE` (`// ""`, validated only by `required`, so `verdict` behaves exactly as before); ONE shared `req_marker` function holds the only `printf` of `REQUIRED_MARKER` (both `emit_required` and `fail_api`'s `required` branch call it, so there is one emit point; its format string is written without the literal `state=error pr=%s`, which existing mutant M19 requires to occur exactly once); new `cmd_required` (read PR, locate child, run it with its rc captured on its own line, classify, recover, emit), `amr_parse`, `classify_required` (pure, jq for lengths and the round trip), `resolve_owners`. Portability: bash 3.2 and BSD userland (jq does the lowercasing; no `mapfile`, associative arrays, `${x,,}` or an empty `"${a[@]}"` under `set -u`). New jq is spelled differently from the existing mutant literals (`sort_by(.id)` over a pre-filtered list, not `sort_by([.ts, .id])`). Header gains the contract, the reason vocabulary, the F-rulings, the seam and the untrusted-ci note.

## Implementation Phases

TDD order (`cq-write-failing-tests-before`): the R-rows go red against the unmodified script first.

### Phase 1 — Failing tests (extend `plugins/soleur/test/ci-head-verdict.test.sh`)

1. Extend the gh stub, keyed on the full argv (the catch-all already refuses everything else, including any `run rerun`, with `STUB-MISS`): `api --paginate --slurp repos/{owner}/{repo}/actions/runs?head_sha=$STUB_H&per_page=100`; for the real-child rows `pr view $STUB_PR --json state,headRefOid,baseRefName,changedFiles` (its own `prview.json` fixture: `state OPEN`, `headRefOid`, `baseRefName`, `changedFiles`; the REST `pr.json` of `mkrow` has another shape), `api --paginate --slurp repos/{owner}/{repo}/pulls/$STUB_PR/files?per_page=100`, `.../rules/branches/main`, `.../commits/$STUB_H/check-runs?per_page=100&filter=all`. The real-child rows keep `test` green or absent so the child never recurses into `ci-head-verdict.sh verdict`.
2. Child stub for unit rows: a generated script under the row dir that prints a fixture marker and exits with a fixture rc, selected through `ADMIN_MERGE_READY_BIN`. **Real-child rows must set `ADMIN_MERGE_READY_BIN=$REPO_ROOT/plugins/soleur/scripts/admin-merge-ready.sh` through `VRUN_ENV`**: `mutant_run` copies the SUT to `$SANDBOX/mut-*.sh`, so the default "next to this script" would not resolve there and an `error` expectation would pass against every mutant for the wrong reason. A row proves a missing seam is `error no-admin-merge-ready`.
3. Add rows R1 to R11 and R-E1 (Test Scenarios), table-driven where the cases differ by one fixture line, with synthesized fixtures: a required context absent from another workflow, a cancelled owner run, an API error.
4. Extend V19 with the `required` usage rows.

### Phase 2 — Implement `required` until the R-rows are green

Per the sketch. Before the first run, check that each existing mutant's `old` literal (`M1` to `M49`) still occurs exactly once in the new SUT; the suite fails a mutant whose edit no longer lands exactly once.

### Phase 3 — Mutants, floors, docs

1. Add mutants M50 onward (matrix under Guard Contract) with kill rows; raise `MIN_ASSERTIONS` and `MIN_MUTANTS` to the measured counts in the same edit.
2. Add a section to `plugins/soleur/skills/ship/references/ready-run-wait.md`: when to call `required` (verdict `full-decided`, auto-merge armed, not enqueued after about 10 minutes), the state table and the action for each, the reason vocabulary, how to read a rerun hint (a `basis=workflow` line names one run; `basis=candidate` lines are for a human or agent to pick by `wf=`), a snippet that extracts the run ids from `RECOVERY rerun` lines, "printed, not run: confirm the run is the owner, then `gh run rerun <id>`", do not sync or re-arm for an absent context, callers read the marker not the exit code, and `state=error` (including `untrusted-ci`) means keep the current reading. The section must not contain a second `ready-count ... wait-ready-run` chain (row L2 reads this file).
3. Run `bash plugins/soleur/test/ci-head-verdict.test.sh`, `bash plugins/soleur/scripts/admin-merge-ready.test.sh`, `bash plugins/soleur/test/admin-merge-ready-wiring.test.sh`, `bash plugins/soleur/test/monitor-pr-checks.test.sh`, `shellcheck` on the SUT and the suite.

### Phase 4 — Ship-time actions (not code)

PR body: `## Changelog`, the sentence that this gap moves out of the epic's LUKS scope, `Ref #9927` and the follow-up issue; a comment (not a body edit) on #9927 linking the PR under its Operator Holds; label `semver:patch`.

## Files to Edit

- `plugins/soleur/scripts/ci-head-verdict.sh` — add `required` (header contract, `usage()`, arg `case`, `fail_api` branch, `cmd_required` and helpers, dispatch).
- `plugins/soleur/test/ci-head-verdict.test.sh` — stub cases, child stub, rows R1 to R11 and R-E1, V19 usage rows, mutants, raised floors.
- `plugins/soleur/skills/ship/references/ready-run-wait.md` — new section for the not-queued case and the `required` states.

## Files to Create

- None in source. (`knowledge-base/project/specs/feat-one-shot-ci-head-verdict-required-set/{decision-challenges.md,tasks.md}` are planning artifacts.)

Glob check: all three edit paths exist on `origin/main` (`git ls-files` match); `.github/CODEOWNERS` already lists the script and its suite (lines 257 and 258), so no CODEOWNERS edit.

## Open Code-Review Overlap

None. Queried open `code-review` issues for each of the three files above; no body names any of them.

## Deferral Tracking

| Deferred | Why | Re-evaluation | Tracking |
|----------|-----|---------------|----------|
| Wire `monitor-pr-checks.sh` (BLOCKED terminal path, `monitor-pr-checks.sh:472`) and the ship Phase 7 poll to call `required` | CTO F1: the Phase 7 poll is a dense loop with a 2400-line fixture suite; wiring it here would exceed size M | First PR touching either file after this merges, or 2026-11-30 | #11544 (filed 2026-10-29, `Ref #9927`, milestone Post-MVP / Later) |

## User-Brand Impact

- **If this lands broken, the user experiences:** a stuck PR is reported as `complete` while a required context is absent (the operator keeps waiting on a PR that will never enqueue), or a healthy PR is reported `absent` and a needless `gh run rerun` is suggested. The operator-facing cost is wasted minutes or one redundant CI run; nothing merges or changes because the command is read-only.
- **If this leaks, the user's workflow is exposed via:** no data surface. The command reads GitHub rulesets, check runs and run lists of the PR's own repo with the caller's existing `gh` credentials, prints only context names from the ruleset and numeric run ids, and writes nothing.
- **Brand-survival threshold:** none
- threshold: none, reason: read-only diagnostic over the caller's own repo, no credential, no user data, no mutation; a wrong answer costs minutes, not user data.

## Observability

Files-to-Edit include `plugins/*/scripts/`, so the 5-field contract applies.

```yaml
liveness_signal:
  what: the SOLEUR_CI_REQUIRED_SET marker line printed on every `required` invocation (state=complete|absent|pending|failed|error)
  cadence: per invocation, called by a person or agent when a green PR is not enqueued after about 10 minutes (consumers wired in the follow-up issue)
  alert_target: the invoking session's tool result (layer 7, cli-stdout-artifact); no Soleur-side sink by design
  configured_in: plugins/soleur/scripts/ci-head-verdict.sh (REQUIRED_MARKER, emit_required)
error_reporting:
  destination: state=error marker with a closed reason token on stdout, human line on stderr; exit 3
  fail_loud: true
failure_modes:
  - mode: GitHub API read fails (PR read, ruleset, check runs)
    detection: layer 7 cli-stdout-artifact - state=error reason=api-error (own read) or the passed-through child reason, exit 3
    alert_route: the invoking session sees exit 3 and the marker; the consumer keeps its own reading
  - mode: child marker drifts (field renamed, reordered) so the parser cannot prove a state
    detection: layer 7 cli-stdout-artifact - state=error reason=marker-unparseable; and the suite pins the child's marker printf format
    alert_route: red suite on the PR that changes admin-merge-ready.sh, otherwise the error marker at run time
  - mode: untrusted-ci or base-mismatch hides the required set (arrays empty)
    detection: layer 7 cli-stdout-artifact - state=error reason=untrusted-ci / base-mismatch
    alert_route: invoking session; the operator merges such a PR by hand (existing admin-merge-ready.sh policy)
  - mode: the owner lookup cannot read or cannot decide
    detection: layer 7 cli-stdout-artifact - RECOVERY line says "owner not determined" with candidates or "read failed"; state unchanged
    alert_route: invoking session
logs:
  where: stdout of the invoking session (tool result); nothing is written to disk by the script
  retention: the session transcript; the command is idempotent and recomputes from GitHub, so no committed artifact is needed (layer 7's pairing rule exists because stdout dies with the session; here the authoritative state is server-side and re-readable at any time)
discoverability_test:
  command: bash plugins/soleur/scripts/ci-head-verdict.sh --help
  expected_output: SOLEUR_CI_REQUIRED_SET
```

Execution-surface note (layer 7 is a property of the execution surface): the same file runs hosted when the platform's agent executes ship; no Soleur-side marker registry names `SOLEUR_CI_HEAD_VERDICT` either (grep of `apps/` returns none), so the hosted path gets the same tool-result stdout and needs no registration.

## Guard Contract

### Guard 1 — `complete` is emitted only on a proven-complete required set

**Property.** `SOLEUR_CI_REQUIRED_SET state=complete` is printed only when the child `admin-merge-ready.sh` exited 0 with verdict `ready`, its marker is the single, last stdout line and names our PR and head SHA, `required` is a positive integer, and all three arrays parse as empty JSON arrays of strings; every other input, including every read failure, prints `state=error` or a non-complete state.

**Assembly.** Every marker is printed by `req_marker`, the only `printf` of `REQUIRED_MARKER`; `emit_required` (decided states) and `fail_api`'s `required` branch (pre-decision failures, which can only print `state=error`) both call it. The inputs the property quantifies over: (1) our own PR read (`read_pr`, incl. `.base.ref`); (2) the child's presence and readability; (3) the child's exit code (allow-list `{0,1,3,4}`); (4) the child's stdout (marker present, single, last, strict prefix); (5) marker integrity (`pr`, `sha`, (rc, verdict) pair, byte-exact array round trip, array total versus `required`); (6) the three arrays (parse, element type, emptiness of EACH of the three, not only `absent`); (7) `required`; (8) the child's `reason` (`untrusted-ci`, `base-mismatch`, `not-green`); (9) the recovery lookup read (which must not change the state). A new input path that skips `classify_required` is the defect, not a partial fix.

**Mutation matrix.**

| # | Edit (to the SUT) | Must go RED | Kill row |
|---|---|---|---|
| 1 | Drop the `failed`-array emptiness test from the `complete` condition (leave `absent` and `pending`) | a ready marker whose only populated array is `failed` (the third array, after two compliant empty ones) must be `error`, not `complete` | R8 |
| 2 | `not-ready` with three empty arrays maps to a state instead of `error` | `untrusted-ci`, `base-mismatch` and bare `not-green` fixtures must be `error` | R7 |
| 3 | Swap the precedence so `absent` outranks `failed` | a marker with both populated must be `failed` | R5 |
| 4 | Accept the first marker-prefixed line instead of requiring exactly one and last | a child that prints a forged marker first and the real one last must be `error` | R6 |
| 5 | Stop checking `sha=` equality | a marker for another head must be `error` | R6 |
| 6 | Treat `required=0` as positive | ready and not-ready markers with `required=0` must be `error` | R8, R7 |
| 7 | Execute the rerun instead of printing it | the stub refuses any `run rerun` argv; the row asserts no `STUB-MISS` and no such request | R2 |
| 8 | Widen the exit-code allow-list to accept rc 2 / 130 with a marker | a child exiting 2 or 130 while printing a marker must be `error child-rc-<n>` | R6 |
| 9 | Drop the byte-exact round trip of the split arrays | a context name embedding ` pending=` (mis-split) must be `error marker-unparseable` | R6 |
| 10 | Let a failed runs-list read set `state=error` | the state must stay `absent` with the "read failed" text | R4 |

**Harness rows.** (H1) Edit the SUITE, not the SUT: in R-E1 make the absent context present in the check-run fixture; the same real-child row must flip from `absent` to `complete` (proves the stub can see the difference). (H2) A must-PASS input that is not the canonical: context names with spaces, parentheses, `#`, `:` and a JSON-escaped control character (folded into R2) parse and print correctly. (H3) A must-PASS parse of the REAL child's marker (R9, produced by running the real `admin-merge-ready.sh` against a failing gh stub), so a hand-written child marker is not the only canonical. (H4) The drift pin anchors on the child's field-name tokens (`verdict= pr= sha= base= reason= required= absent= pending= failed=` in that order in its `marker()` function), not on its whole `printf` format string (`cq-assert-anchor-not-bare-token`), and R9's behavioural parse of the real child backs it.

**Anchor.** None: the guard compares no stored value (no hash, count floor or registry); the anti-vacuity floors (`MIN_ASSERTIONS`, `MIN_MUTANTS`) are raised in the same edit and are lower bounds that a later weakening PR must visibly lower.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add an additive, read-only subcommand `ci-head-verdict.sh required <pr>` (plugins/soleur/scripts/ci-head-verdict.sh)" [brief] | Files to Edit entry 1, Phase 2 | mapped |
| 2 | "calls `admin-merge-ready.sh <pr> <head-sha>` WITHOUT --wait ... and parses its absent/pending/failed arrays" [brief] | Phase 2, State mapping | mapped |
| 3 | "Emit a new marker line `SOLEUR_CI_REQUIRED_SET state=<complete\|absent\|pending\|failed\|error> pr= sha= absent=[..]`" [brief] | CLI contract (field order per CTO F3) | mapped |
| 4 | "Do NOT change the existing `verdict` state set ... and do NOT copy the ruleset logic" [brief] | Cut List, Guard 1 Assembly, AC4/AC5 | mapped |
| 5 | "Any read failure is state=error, never complete; reason=untrusted-ci is also error unless the arrays are provably populated (test it)" [brief] | State mapping, rows R6 to R8 | mapped |
| 6 | "Consumers (the monitor, ship Phase 7 poll) call it when verdict is full-decided but the PR is not queued after about 10 minutes" [brief] | `ready-run-wait.md` section (Phase 3); consumer wiring deferred (CTO F1) | mapped (docs now, wiring tracked) |
| 7 | "Recovery text prints `gh run rerun <id>` for the cancelled run owning the absent context and only prints it, never runs it" [brief] | Recovery text, rows R2 to R4 | mapped |
| 8 | "Tests use synthesized fixtures only: a required context absent from another workflow, a cancelled owner run, an API error" [brief] | Phase 1, rows R2, R-E1, R6 | mapped |
| 9 | "Read-only rules apply: no production mutation, no merge-queue or ruleset changes" [brief] | Files to Edit (three files), Guard 1 matrix row 8 | mapped |
| 10 | "Record in the PR body that this gap moves out of the epic's LUKS scope; epic #9927 stays open" [brief] | Phase 4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `ci-head-verdict.sh` edit | "add an additive, read-only subcommand" | asked |
| Suite edits (rows, mutants, floors) | "Tests use synthesized fixtures only" | asked |
| `ready-run-wait.md` section | "Consumers (the monitor, ship Phase 7 poll) call it when verdict is full-decided but the PR is not queued after about 10 minutes" | asked (the consumer contract lives in the shared reference both consumers read) |
| Recovery lookup (one runs-list read, 2 tiers) | "prints `gh run rerun <id>` for the cancelled run owning the absent context" | asked |
| Raising `MIN_ASSERTIONS` / `MIN_MUTANTS` | — | inferred — justification: the suite's own header says the floors are lower bounds raised in the same edit as a new row, or the anti-vacuity gate rots |
| `ADMIN_MERGE_READY_BIN` seam | — | inferred — justification: unit rows need a synthesized child marker; `CI_HEAD_VERDICT_BIN` is the precedent in the opposite direction |
| Deferral issue for consumer wiring | — | inferred — justification: `wg-when-deferring-a-capability-create-a` and the deferral-tracking check require an issue for a deferred capability |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur/scripts` and `plugins/soleur/test` (plus one reference doc under `plugins/soleur/skills/ship/references`)
- Planned files: 3 | Estimated changed lines: about 380 (about 130 SUT, about 220 suite, about 30 doc)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `bash plugins/soleur/scripts/ci-head-verdict.sh required <pr>` prints exactly one `SOLEUR_CI_REQUIRED_SET` marker as the last stdout line, field order `state pr sha required reason absent pending failed` (`ci-head-verdict.sh:req_marker`; rows R1, R6).
- [ ] AC2: `complete` appears only for child rc 0 + verdict `ready` + `required` > 0 + all three arrays empty (`classify_required`; rows R1, R8, mutants 1 and 6).
- [ ] AC3: a required context absent from another workflow reads `absent`, with the context name in `absent=[..]` (R2, and R-E1 against the REAL `admin-merge-ready.sh`).
- [ ] AC4: the `verdict` marker, its closed six-state set and its tests are unchanged: `git diff origin/main -- plugins/soleur/scripts/ci-head-verdict.sh` shows no change inside `cmd_verdict`, `classify_run` or the `SOLEUR_CI_HEAD_VERDICT` printf, and the only change in `read_pr` is the added `PR_BASE` capture; the existing V/W/L rows pass unmodified apart from V19's added usage cases.
- [ ] AC5: no ruleset parsing in `ci-head-verdict.sh`: `grep -nE 'rules/branches|required_status_checks|integration_id' plugins/soleur/scripts/ci-head-verdict.sh` returns only header/comment lines.
- [ ] AC6: every read failure is `state=error` with exit 3 and `-` for unknown scalars (including `sha=` before the PR read) and arrays: own PR read, missing child, child crash, no marker, rc 2/3/4/130, marker integrity failures (R6).
- [ ] AC7: `untrusted-ci` and `base-mismatch` with three empty arrays are `error`; `untrusted-ci` with a populated array maps by precedence (R7).
- [ ] AC8: the recovery prints `gh run rerun`-bearing hints only; the gh stub's catch-all refuses any `run rerun` argv and every row asserts no `STUB-MISS` (R2, mutant 7).
- [ ] AC9: owner resolution follows F5' exactly: one runs-list read; a single unique normalized workflow-name match prints `basis=workflow`; otherwise every cancelled run at the head prints `basis=candidate`; no per-run jobs reads exist (R2, R3).
- [ ] AC10: a failed runs-list read leaves the state `absent` (R4); `stalled` / `awaiting-approval` skip the lookup (R4).
- [ ] AC11: failed > absent > pending precedence (R5, mutant 3).
- [ ] AC12: the child's marker field order is pinned by field-name tokens and the real child's marker parses (R9, H3, H4); a missing `ADMIN_MERGE_READY_BIN` seam is `error no-admin-merge-ready` (R9).
- [ ] AC13: `ready-run-wait.md` carries the new section naming `ci-head-verdict.sh required`, `SOLEUR_CI_REQUIRED_SET`, all five states and the reason vocabulary, consistent with `--help`; its run-id extraction snippet works on a sample `RECOVERY rerun` line (R11).
- [ ] AC14: suite green with raised floors; each of the existing mutants M1 to M49 still lands exactly once; `shellcheck` clean on the SUT and the suite; `admin-merge-ready.test.sh`, `admin-merge-ready-wiring.test.sh` and `monitor-pr-checks.test.sh` unchanged and green.
- [ ] AC15: PR body has `## Changelog`, states the gap moves out of the epic's LUKS scope, uses `Ref #9927` (not `Closes`), links the follow-up issue; a comment (not a body edit) is added on #9927.

## Test Scenarios

Rows added to `plugins/soleur/test/ci-head-verdict.test.sh` (each asserts `nomiss`, one marker, marker last; R5 to R8 are table-driven):

- R1: complete (child ready, `required=26`, arrays `[]`) -> `state=complete`, rc 0.
- R2: required context absent from another workflow; a cancelled run whose workflow name matches -> `state=absent`, one `basis=workflow` line, no `run rerun` request; variants folded in: context names with spaces, parentheses, `#`, `:` and a JSON-escaped control character; no cancelled run at the head -> "no cancelled run" text and no rerun line.
- R3: no unique name match (two cancelled runs match the same name, or none match) -> `basis=candidate` for every cancelled run, with the "owner not determined" sentence; the stale unrelated `CI` run is listed, not chosen.
- R4: runs-list read fails -> state still `absent`, "read failed" text; `reason=stalled` / `awaiting-approval` -> no runs request, pointer text.
- R5: precedence matrix (failed+absent, absent+pending, failed+pending, pending only, failed only).
- R6: errors: no child, child crash (no output), rc 2 and 130 each with a marker, rc 3 with each passed-through reason, rc 4, no marker, forged marker first (two prefix lines), marker not last, `pr`/`sha` mismatch, (rc, verdict) outside the allow-list, unparseable arrays, a non-string element, an array element embedding ` pending=` (round trip), array total above `required`, own PR read failure, missing tool; `sha=-` before the PR read; all error markers print `-` for unknown scalars and arrays.
- R7: `not-ready` with empty arrays: `untrusted-ci` / `base-mismatch` / bare `not-green` -> `error`; `untrusted-ci` with a populated array -> precedence state; `required=0` -> `error required-unknown`.
- R8: `ready` with a populated array (each array in turn, third-only included) -> `error ready-with-gaps`; `required=0` or missing -> `error required-unknown`.
- R9: real-child contract, via `VRUN_ENV ADMIN_MERGE_READY_BIN=<real script>`: the field-name token order pin on the child's `marker()`; the real `admin-merge-ready.sh` against a failing gh stub parses to `error api-error`; a missing seam -> `error no-admin-merge-ready`.
- R10: usage: `required`, `required abc`, `required 7 8`, `required 7 --before-count 1`, `required 7 --timeout 5` exit 2 with no gh call (V19 loop); `--repo` exports `GH_REPO`; the PR's base is passed to the child as `--base` (child stub logs argv).
- R11: `ready-run-wait.md` names the subcommand, the marker, all five states and the reason vocabulary from `--help`; the run-id extraction snippet works on a sample line.
- R-E1: end to end against the REAL `admin-merge-ready.sh` with a synthesized required set `{test, cla-evidence}` (both app 15368): `cla-evidence` absent from the check-run fixture, a cancelled owner run in the runs fixture -> `absent` + rerun hint; H1 flip (make it present) -> `complete`.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent ruled the shape on 2026-10-29 (additive subcommand, delegation, closed `verdict` set), the seven sub-forks F1 to F7 during this plan and a re-ruling F5' after plan review (decision-challenges.md). The plan-review panel (DHH, Kieran, code-simplicity, CTO devex) ran 2026-10-29; mechanical findings were applied (exhaustive exit-code allow-list, strict prefix parse with round trip, real-child rows pinned to the real script through `VRUN_ENV`, single marker emit point, `--base` pass-through, `sha=-`, closed reason vocabulary, jobs-tier cut, trimmed rows and mutants). No product, UX, marketing, legal, finance, sales or support surface is touched; no GDPR surface (no personal data, schema or auth route; the command prints ruleset context names, workflow names via `@json` and numeric run ids); no encryption posture surface (no store, no new connection); no new infrastructure; no architectural decision (a diagnostic subcommand on an existing resolver; ADR-276 is unchanged, and no `.c4` actor, system or relationship changes). Product/UX gate: none (no UI surface file in the Files lists).

## Sharp Edges

- Every existing mutant asserts its `old` literal occurs exactly once in the SUT. New code must not duplicate them. Known traps: `state=error pr=%s` (M19), `reason="${2:-api-error}"` (M14), `fail_api() {` (M15), `read_newest_run "$PR_SHA" "$t_epoch" || fail_api` (M2), `select(.head_sha == $h and .event == "pull_request")` (M1), `sort_by([.ts, .id])` (M26/M27), `(min | tostring)` (M38/M47/M48), `.app.id == 15368` (M18), `st=stalled` (M9) and `elif [[ "$CMD" == wait-ready-run ]]; then` (M33). Run the exact `count == 1` check for M1 to M49 before writing any row.
- `mutant_run` copies the SUT to the sandbox, so anything resolved "next to the script" (the child default) breaks in mutants; real-child rows set `ADMIN_MERGE_READY_BIN` explicitly.
- Capture the child's exit code on its own line (`rc=$?`), never behind a pipe or `|| true`.
- `read_pr` needs no `Date` header for `required`; do not route through `server_now`.
- The child prints human lines before its marker on stdout, and a ruleset context name containing a newline could print a forged second marker-prefixed line: require exactly one prefixed line and that it is last.
- Exit 0 for `absent` / `pending` / `failed` is deliberate (matches `verdict`); document that callers parse the marker.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares threshold `none` with its reason.
- The consumer hold stays open until the follow-up lands: until then the new marker is documented, not polled.

## References

- Learning: `knowledge-base/project/learnings/workflow-issues/2026-10-28-a-green-verdict-and-an-armed-auto-merge-do-not-prove-a-required-context-exists.md`
- Authority: `plugins/soleur/scripts/admin-merge-ready.sh` (#8500), resolver `plugins/soleur/scripts/ci-head-verdict.sh` (ADR-276 S3, #9728)
- Endpoint (GitHub REST, list workflow runs): `https://docs.github.com/en/rest/actions/workflow-runs` <!-- verified: 2026-10-29 source: live read-only gh api call against actions/runs?head_sha=<PR #11254 head> -->
- Epic #9927, draft PR #11542
