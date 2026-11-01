---
title: "chore(registry): correct the retry advice in the restore job's exit-3 and exit-4 arms"
date: 2026-11-01
slug: registry-restore-arm-wording
branch: feat-one-shot-11667-registry-restore-arm-wording
issue: 11667
type: chore
lane: cross-domain
---

## Overview

The `registry_store_restore` job in `.github/workflows/apply-web-platform-infra.yml` prints one `::error::` line per engine exit code. Two of those lines contradict the engine's own exit-code table in `scripts/registry-restore-from-ghcr.sh` (the header block that labels exit 3 `RETRYABLE` and exit 4 `NOT retryable`):

- the exit-3 arm says the store is EMPTY and blames a tunnel that "did not converge", but exit 3 can also fire mid-run (after some entries were copied) and covers a registry that would not serve a request as well as one that would not accept a write;
- the exit-4 arm tells the reader to "re-run this job", but exit 4 is documented NOT retryable.

This plan rewrites those two echo strings and the matching cell of the runbook exit-code table, and nothing else. The operator lifted, for this one edit only, the standing constraint against editing the apply workflow (2026-11-01); the CTO's wording ruling is binding and is recorded in `knowledge-base/project/specs/feat-one-shot-11667-registry-restore-arm-wording/decision-challenges.md`. The engine script and every test stay untouched, because an engine edit arms the roughly 860 s registry mutation battery.

The PR is a partial step on #11667: the issue stays open and the PR body uses `Ref`.

Lane: the spec directory held no `spec.md` (this branch started from a one-shot brief), so `lane:` is defaulted to `cross-domain` (fail-closed, TR2).

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality (command) | Plan response |
|---|---|---|
| Net change is -4 bytes, 489,204 to 489,200 (CTO-measured). | Dry-run replacement of both strings on the real file: exit-3 string -7, exit-4 string -5, net **-12**; 489,204 to **489,192** (`python3 -I` read, `.replace`, `len(.encode())`; each old string occurs exactly once). | The ruling's constraint is "negative, add nothing else", and -12 satisfies it. ACs assert the exact measured value 489,192 and the weaker `< 489,204`; the post-merge size check expects about 489,192, not 489,200. Report the discrepancy in the PR body so nobody chases a phantom 8-byte gap. |
| Issue #11667 body lists items (a) test logic, (b) engine wording, (c) stale comments, all battery-armed. | Open issue; none of (a)-(c) is in this brief. The brief narrows to two workflow strings plus one runbook cell. | Out of scope by operator direction. PR uses `Ref #11667`; the issue is not closed, and the three items stay open. |
| Exit 3 "The store is EMPTY". | Engine header (`scripts/registry-restore-from-ghcr.sh`, rows 3 and 4 of the exit table) labels exit 3 RETRYABLE; arms at its `die 3` sites fire while copying and while reading a signature back, i.e. after earlier entries may be in the sink. | New wording says "EMPTY or only partly refilled" and "accept or serve a request". |
| Runbook row 4 says "Re-run the job and read the per-entry lines". | The same cell continues "; a repeat means the copy is landing wrong, not that it was interrupted." and, further on, "For those SHAPE failures 're-run the job' is the wrong advice". | Substitute the ruled phrase literally. The trailing clause is not covered by the ruling; it is left alone (taste row in `decision-challenges.md`) and listed on the #11667 comment. |
| A test or doc anchors on the old arm text. | `git grep -n 'per-entry lines\|SINK unavailable\|VERIFICATION mismatch' -- . ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'` (repo-wide; the plan and spec files quote the old strings, so they are excluded): the only hits are the workflow, the engine header, the exit-code runbook, the rationale runbook (`apply-web-platform-infra-job-rationale.md`, line 737, prose only) and an unrelated comment in `scripts/tmpfs-guard.test.sh`; no test asserts the exit-3 or exit-4 text (the wiring suite only mutates the exit-78 arm). `scripts/registry-pull-path-health.sh:578` carries a sibling phrase for the rehearsal harness, a different script. | No test edit is needed. The wording is not pinned anywhere; the new wording is pinned by the ACs below (grep of the literals). |

## Research Insights

**Premise validation (Phase 0.6).** Checked: #11667 is OPEN (`gh issue view 11667 --json state,title,body`), draft PR #11787 is OPEN; both cited old strings exist exactly once on the branch (lines 3637 and 3638 of the workflow); the runbook row text exists at line 507; the three out-of-scope strings exist (`### The store is EMPTY` at line 3475, `The store is EMPTY and this job cannot refill it` at line 3592, exit-78 arm `the store is still EMPTY` at line 3643). Stale: only the byte figure (see reconciliation). The closed parent tracker named in the brief is cited only in the PR body, by instruction. ADR corpus: the mechanism is a string edit and no ADR proposes or rejects it; not applicable.

**Property List (Phase 0.6b).**

1. An operator reading the exit-3 error learns the store may be partly refilled (not only empty) and that the registry may have failed to serve as well as to accept.
2. An operator reading the exit-4 error is not told to re-run the job.
3. The runbook's exit-code table gives the same retry advice for exit 4 as the workflow and the engine header.
4. The workflow file does not grow (it stays under the 490,000-byte gate with headroom, and no new text is added).
5. The engine, the tests and the apply behaviour of the next push are unchanged.

**Cut List.** Each row: mechanism, property, what already covers it.

- Engine header or `die` wording edit (issue item b) -> property 1 and 2 -> already covered by the engine header, which says RETRYABLE / NOT retryable on rows 3 and 4 (`scripts/registry-restore-from-ghcr.sh`, the exit-code comment block; this was the file grepped, not a consumer). Editing it would arm the battery. Cut.
- A new test pinning the arm text -> property 1 and 2 -> the ACs' grep checks cover it for this PR; a new test edit touches `tests/` and the brief forbids it. Cut.
- Extra rationale prose in the workflow or a rationale-runbook paragraph -> none -> the byte budget forbids new text. Cut.
- Rewording the exit-78 arm, the line-3592 abort and the line-3475 summary -> out of scope by direction; recorded on #11667 instead.

**Institutional learnings applied.** `2026-09-19-a-sibling-merge-took-the-apply-workflow-over-githubs-byte-limit-and-nothing-in-repo-said-so.md` (the file's byte ceiling is a real run-start limit, so the net delta is asserted, not assumed); `2026-09-23-compressing-prose-to-fit-a-byte-ceiling-dropped-the-conditions-that-made-it-correct.md` (the new exit-3 text keeps the "Verify the registry host is serving, then re-run this job" condition, which is what makes the retry advice correct for a retryable code).

**Local test baseline (measured 2026-11-01, before any edit).** `bash tests/scripts/test-registry-d10-workflow-wiring.sh` finished in about 45 s with `=== 91 passed, 0 failed ===`; `bun test test/workflow-file-size.test.ts` (run from `plugins/soleur`) printed `9 pass`, `0 fail`. These are local runs; CI's required `test` context is the gate, and a local run that hits a time or memory budget is never reported as passed.

**Merge consequences (CTO-verified, carried from the brief).** The workflow's own path is in the `on.push.paths` filter, so merging fires a push apply run on `main`: `preflight`, then `apply` (environment `infra-privileged`, no required reviewers). The plan is expected to be a no-op, because no `.tf` file changes. The `registry_store_restore` job runs only behind the `registry_luks_recut` dispatch path, so it does not execute on this push. A commit-message line that is exactly `[skip-web-platform-apply]` skips the apply; none may be added (the squash commit body is the PR body, so the PR body must not carry that token or `[ack-destroy]` on a line of its own).

## Open Code-Review Overlap

None. Queried 98 open `code-review` issues on 2026-11-01 (`gh issue list --label code-review --state open --json number,title,body --limit 200`, then standalone `jq --arg path ... contains($path)`) for both planned paths; zero bodies name either file. Phase 4 task 4.1 re-runs the query at ship time in case one is filed in between.

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml`: currently lines 3637-3638 (the `old_string` anchors in "Exact edits" win if the numbers drift), only the two `echo` strings inside the `case "$rc"` block of `registry_store_restore`. Line count must not change (two lines in, two lines out). Net bytes -12.
- `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`: currently line 507 (anchor text wins if it drifts), only the "What to do" cell of the exit-code table row `4`: "Re-run the job and read the per-entry lines" becomes "NOT retryable; read the per-entry lines".

## Files to Create

Planning artifacts only (all under `knowledge-base/project/`): this plan, `specs/feat-one-shot-11667-registry-restore-arm-wording/tasks.md`, `specs/feat-one-shot-11667-registry-restore-arm-wording/decision-challenges.md`. No source file is created.

Paths verified to exist: `git ls-files .github/workflows/apply-web-platform-infra.yml knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` returns both.

## Exact edits (the whole change)

Use the Edit tool with these exact, unique `old_string` / `new_string` substrings (each old string occurs exactly once in its file; read the file first per `hr-always-read-a-file-before-editing-it`).

Workflow, exit-3 arm (line 3637):

- old: `the rebuilt registry did not accept the write and the tunnel did not converge within the backoff. The store is EMPTY. Verify the registry host is serving, then re-run this job.`
- new: `the registry did not accept or serve a request within the backoff. The store is EMPTY or only partly refilled. Verify the registry host is serving, then re-run this job.`

Workflow, exit-4 arm (line 3638):

- old: `Do not deploy; re-run this job and read the per-entry lines above.`
- new: `Do not deploy. NOT retryable: read the per-entry lines above.`

Runbook, row 4 (line 507):

- old: `Re-run the job and read the per-entry lines; a repeat means`
- new: `NOT retryable; read the per-entry lines; a repeat means`

(The runbook `old_string` keeps its tail, `; a repeat means`, only to make it unique and to show the trailing clause is deliberately left in place. The lowercase "do not deploy" sentence before it is untouched.)

## Implementation Phases

TDD note (`cq-write-failing-tests-before`): exempt. This is an operator-facing message-text change with no behaviour; nothing in `tests/`, `plugins/soleur/test/`, `scripts/` or `apps/` asserts on these strings (grep above), and the brief forbids test edits. The existing suites are the regression net and the ACs are the new assertions.

### Phase 1 — Edit the workflow

- 1.1 Read lines 3630-3640 of the workflow, then apply the two Edit calls above.
- 1.2 Do not touch any other line, comment or whitespace in the file. Preserve the trailing `" ;;` on each arm.

### Phase 2 — Edit the runbook

- 2.1 Read line 507 of the runbook, then apply the one Edit call above. Keep the "do not deploy" sentence.

### Phase 3 — Verify locally (cheap, before any push)

- 3.1 Run the AC1-AC5 commands (they are the Phase 3 checks; they are not restated here).
- 3.2 `wc -l` on the workflow equals the pre-edit line count.
- 3.3 Run AC6 after committing (three-dot diff is empty before the commit); before committing use `git status --short`.
- 3.4 Run `cd plugins/soleur && bun test test/workflow-file-size.test.ts` and `bash tests/scripts/test-registry-d10-workflow-wiring.sh` (expect `91 passed, 0 failed`). If either hits a time or memory budget, say so; do not call it passed.

### Phase 4 — Ship (ship skill drives this; listed so the constraints are not lost)

- 4.1 Open code-review overlap query (two-stage `gh ... --json` then `jq --arg`, per the plan skill) for both edited paths; record the result in the PR body.
- 4.2 Run `bash plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh` before any push.
- 4.3 Commit message: no `[skip-web-platform-apply]` line, no `[ack-destroy]` line, no operator-checklist text.
- 4.4 PR body (the existing draft is #11787): contains the line `Ref #11667` and a second `Ref` line naming the closed parent tracker from the brief (hash sign followed by 9757, written only in the PR body, never in a tool argument other than the PR-body write, never in a title). No close / fix / resolve wording anywhere, even negated. State the measured -12 byte delta and that exit-3 and exit-4 wording follows the engine's exit-code table.
- 4.5 Post a comment on #11667 listing, by string, what this PR deliberately did not change: (1) `The store is EMPTY and this job cannot refill it` (workflow, near line 3592); (2) the exit-78 arm text `the store is still EMPTY` (near line 3643); (3) the summary heading `### The store is EMPTY` (near line 3475); (4) planner-added, runbook row 4's trailing clause `a repeat means the copy is landing wrong, not that it was interrupted`; (5) planner-added, runbook row 3's `the registry did not accept the write`, against the engine header's "accept or serve". Items 4 and 5 are labelled as additions beyond the brief.
- 4.6 Mark ready and merge with `gh pr merge 11787 --squash --auto` (one `gh pr merge` per Bash call, never `--delete-branch`, no admin merge). A multi-hour merge-queue stall is reported, not bypassed.
- 4.7 Do not touch issues 11312, 11379, 10924.

### Phase 5 — Post-merge verification

- 5.1 Find the push run for the merge commit with the AC10 command (the brief's `gh run list --workflow apply-web-platform-infra.yml --limit 1` can return a different or still-running run, so select by `headSha`); wait for it with the repo's watch mechanism, not a poll loop in the background.
- 5.2 The `apply` job's `Pre-apply entrypoint gate` and `terraform apply` steps are green and the plan reports no changes.
- 5.3 Run AC11: the merge commit shrinks the file by exactly 12 bytes against its parent (the size on main is then about 489192, but a sibling merge in between can move it, so the delta is what is compared).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "exit 3: replace `the rebuilt registry did not accept the write and the tunnel did not converge within the backoff. The store is EMPTY. Verify the registry host is serving, then re-run this job.` with `the registry did not accept or serve a request within the backoff. The store is EMPTY or only partly refilled. Verify the registry host is serving, then re-run this job.`" [brief] | Files to Edit entry 1; Phase 1 | mapped |
| 2 | "exit 4: replace `Do not deploy; re-run this job and read the per-entry lines above.` with `Do not deploy. NOT retryable: read the per-entry lines above.`" [brief] | Files to Edit entry 1; Phase 1 | mapped |
| 3 | "Net change must be negative in bytes" / "Add no other text to the file." / "Do not touch the engine script or tests" [brief] | Phase 3 tasks 3.1-3.3; Cut List | mapped |
| 4 | "exit-code table row 4 (around line 507) says \"Re-run the job and read the per-entry lines\"; change to \"NOT retryable; read the per-entry lines\", keeping the \"do not deploy\" part." [brief] | Files to Edit entry 2; Phase 2 | mapped |
| 5 | "Out of scope; record on #11667 as a comment by string (not fixed here)" [brief] | Phase 4 task 4.5 | mapped |
| 6 | "PR body uses `Ref #11667`" ... "never close/fix/resolve wording, even negated" ... "Merge with `gh pr merge <N> --squash --auto`" [brief] | Phase 4 tasks 4.3-4.6 | mapped |
| 7 | "After merge verify: `gh run list --workflow apply-web-platform-infra.yml --limit 1`, apply job steps (pre-apply entrypoint gate, terraform apply) green with no-change plan, file size on main about 489,200." [brief] | Phase 5 | mapped (size figure corrected to 489,192, see reconciliation) |
| 8 | "Run the workflow-file size test ... and tests/scripts/test-registry-d10-workflow-wiring.sh (expect 91 passed)" [brief] | Phase 3 task 3.4 | mapped |
| 9 | "Record the CTO's binding ruling for the two arm strings (exit-3 and exit-4 wording, byte budget, runbook row) as a `technical` row" [brief] | `decision-challenges.md` rows 1-4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit workflow lines 3637-3638 | "change only two echo strings" | asked |
| Edit runbook row 4 | "change to \"NOT retryable; read the per-entry lines\"" | asked |
| `decision-challenges.md` | "Persist decisions as rows of the `\| Item \| Class \| Ruling \|` table in knowledge-base/project/specs/feat-one-shot-11667-registry-restore-arm-wording/decision-challenges.md" | asked |
| `tasks.md` and this plan | — | inferred — justification: the plan skill's output contract (tasks derive from the plan; the work phase reads them) |
| Comment items 4 and 5 (runbook trailing clause, runbook row 3) | — | inferred — justification: both strings go stale against the new wording and are cheaper to record on the tracker now than to rediscover; they are comment text only, no file edit |
| Dry-run byte measurement and corrected size figure | "Net change must be negative in bytes (CTO measured -4" | asked (the measurement is how the negativity is shown; it found -12) |

### Split Assessment

- Subsystems touched: 2 — `.github`, `knowledge-base`
- Planned files: 2 edited (plus 3 planning artifacts) | Estimated changed lines: 3 changed lines in source, about 90 in planning artifacts
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

Shell variables used by every command below (set them in the same Bash call as the command): `WF=.github/workflows/apply-web-platform-infra.yml`, `RB=knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`, `BASE=$(git merge-base origin/main HEAD)`. Diffs run against `$BASE`, not the moving `origin/main` tip, so a sibling merge cannot falsify them.

- [ ] AC1: `wc -c < $WF` equals `git show $BASE:$WF | wc -c` minus 12 (489192 when the base is the 489204-byte tree measured on 2026-11-01), is strictly below the base size, and is `<= 490000`.
- [ ] AC2: `git diff --numstat $BASE -- $WF | awk '{print $1","$2}'` prints `2,2`, the same command on `$RB` prints `1,1`, and `wc -l < $WF` equals `git show $BASE:$WF | wc -l`.
- [ ] AC3: `grep -c 'the registry did not accept or serve a request within the backoff. The store is EMPTY or only partly refilled. Verify the registry host is serving, then re-run this job.' $WF` prints `1`, and `grep -c 'Do not deploy. NOT retryable: read the per-entry lines above.' $WF` prints `1`.
- [ ] AC4: the old literals are gone: `grep -c 'the rebuilt registry did not accept the write' $WF` and `grep -c 're-run this job and read the per-entry lines above' $WF` both print `0` (AC3 and AC4 are one pair: new present once, old absent).
- [ ] AC5: row 4 of the runbook carries the new phrase and keeps "do not deploy": `grep -n '^| .4. |' $RB | grep -c 'NOT retryable; read the per-entry lines; a repeat means'` prints `1`; `grep -n '^| .4. |' $RB | grep -c 'do not deploy'` prints `1`; `grep -c 'Re-run the job and read the per-entry lines' $RB` prints `0`. The `.4.` pattern matches the backticked cell without embedding backticks.
- [ ] AC6: after committing (the diff against `$BASE` is empty before the commit), `git diff --name-only $BASE..HEAD | grep -vE '^(\.github/workflows/apply-web-platform-infra\.yml|knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929\.md|knowledge-base/project/(plans|specs|learnings)/)'` prints nothing, and `git diff --name-only $BASE..HEAD | wc -l` is at least `2` (positive control: the diff is not empty). The allow-list includes `learnings/` because the ship pipeline may write one; any path under `scripts/`, `tests/`, `plugins/` or `apps/` fails it.
- [ ] AC7: `bash tests/scripts/test-registry-d10-workflow-wiring.sh` ends with `=== 91 passed, 0 failed ===` and `cd plugins/soleur && bun test test/workflow-file-size.test.ts` reports `9 pass`, `0 fail`; both locally and in CI's required `test` context (the CI context is the gate; a local run that hit a budget is reported as such, never as passed).
- [ ] AC8: PR body check, run in one Bash call: `B=$(gh pr view 11787 --json body --jq .body); printf '%s' "$B" | grep -c 'Ref #11667'` prints `1` (an empty body fails), and `printf '%s' "$B" | grep -ciE '\b(clos(e|es|ed|ing)|fix(es|ed|ing)?|resolv(e|es|ed|ing))\b|\[skip-web-platform-apply\]|\[ack-destroy\]'` prints `0`. The body also carries the parent-tracker `Ref` line from the brief and the measured -12 byte delta; the commit message has no `[skip-web-platform-apply]` or `[ack-destroy]` line.
- [ ] AC9: A comment on #11667 lists the three brief strings and the two planner-added strings (task 4.5); `gh issue view 11667 --json comments --jq '.comments[].body' | grep -c 'cannot refill it'` prints at least `1`.

### Post-merge (operator-free, run by the ship/postmerge phase)

- [ ] AC10: `sha=$(gh pr view 11787 --json mergeCommit --jq .mergeCommit.oid)` is non-empty, and `gh run list --workflow apply-web-platform-infra.yml --branch main --event push --limit 10 --json headSha,status,conclusion --jq ".[] | select(.headSha==\"$sha\")"` shows `"status":"completed"` and `"conclusion":"success"` (a run still `in_progress` is waited on, not counted as passed). Its `apply` job's pre-apply entrypoint gate and `terraform apply` steps are green and the plan reports no changes.
- [ ] AC11: with `sha` from AC10, `git fetch origin main` then `echo $(( $(git show ${sha}^:.github/workflows/apply-web-platform-infra.yml | wc -c) - $(git show ${sha}:.github/workflows/apply-web-platform-infra.yml | wc -c) ))` prints `12` (the squash commit has one parent; this holds without a pinned baseline, and the file size on main is about 489,192).

## User-Brand Impact

- **If this lands broken, the user experiences:** an operator reading a failed restore run still sees the old advice (re-run after a verification mismatch), or sees a garbled `::error::` line. No end-user surface changes: the restore job only runs behind the registry recut dispatch.
- **If this leaks, the user's workflow is exposed via:** nothing; the change adds no secret, URL, credential or data, only two error sentences and one runbook cell.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, because the edit is wording-only on an operator-facing error path; the next tier would need a user-visible failure or a data path, and neither exists.

`threshold: none, reason: the touched path (.github/workflows/apply-web-platform-infra.yml) is only edited in two echo strings of an operator-facing error arm; no step, condition, secret, permission or trigger changes, and the registry_store_restore job does not execute on the push that the merge triggers.`

## Observability

```yaml
liveness_signal:
  what: the apply workflow's push run on main for the merge commit concludes success with a no-change plan
  cadence: once per merge touching the workflow path (event-driven, not scheduled)
  alert_target: notify-apply-failure job in the same workflow (emails the failing run's cause to the operator) plus the run's annotations
  configured_in: .github/workflows/apply-web-platform-infra.yml (jobs preflight, apply, notify-apply-failure)
error_reporting:
  destination: GitHub Actions run annotations (::error:: lines) and the notify-apply-failure email; no application Sentry path is involved
  fail_loud: true - the restore step ends with `exit "$rc"` after printing its arm, so a wrong arm cannot mask the exit code
failure_modes:
  - mode: an edit leaves the YAML invalid or the file over the byte limit, so the run does not start (zero jobs)
    detection: plugins/soleur/test/workflow-file-size.test.ts and the YAML-parsing suites in CI's required test context fail before merge; post-merge, the run list shows startup_failure or no jobs
    alert_route: CI required check on the PR; post-merge gh run list check in AC10
  - mode: the push apply run reports a non-empty plan
    detection: the apply job's plan step and destroy guard
    alert_route: notify-apply-failure email and the run's red status
logs:
  where: GitHub Actions run logs for apply-web-platform-infra.yml
  retention: GitHub's default Actions log retention for the repository
discoverability_test:
  command: grep -c "Do not deploy. NOT retryable: read the per-entry lines above." .github/workflows/apply-web-platform-infra.yml
  expected_output: 1
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling wording change on an operator-facing error path. Engineering ruling for the wording is already recorded (CTO, binding, per the brief), so no domain leader is spawned.

## Test Scenarios

- Given the edited workflow, when `bash tests/scripts/test-registry-d10-workflow-wiring.sh` runs, then it ends `=== 91 passed, 0 failed ===` (same as the pre-edit baseline).
- Given the edited workflow, when `bun test test/workflow-file-size.test.ts` runs from `plugins/soleur`, then all 9 tests pass.
- Given the edited files, when AC3-AC5 greps run, then the new literals each occur once and the old ones zero times.
- Given a restore run that ends in exit 4, when the operator reads the `::error::` line, then it says NOT retryable and does not say re-run.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan fills it with `none` and the sensitive-path scope-out bullet (the workflow path is in the preflight sensitive-path set).
- The workflow path is in its own `on.push.paths`, so the merge is not a no-op for CI: it fires a production-environment apply run. Do not add `[skip-web-platform-apply]` or `[ack-destroy]` to the commit message or the PR body.
- The squash commit body is the PR body, and the skip token is matched on its own line. Keep the PR body free of both tokens.
- The `Edit` `old_string` values are unique per file today; if a sibling PR changes either line before this one merges, re-read the file and re-measure the byte delta rather than reusing -12.
- The runbook edit must not touch the lowercase "do not deploy" sentence; AC5 checks it survives.
- The parent-tracker reference (hash sign followed by 9757) is to be typed only in the PR body write; this plan deliberately does not spell it with the hash.
