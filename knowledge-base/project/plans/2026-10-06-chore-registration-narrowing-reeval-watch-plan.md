---
title: "chore: watch the #9564 re-evaluation trigger and notify once (never close)"
date: 2026-10-06
slug: registration-narrowing-reeval-watch
branch: feat-one-shot-9564-followthrough-enrollment
issue: 9564
type: chore
lane: cross-domain
---

# chore: watch the #9564 re-evaluation trigger and notify once (never close)

## Overview

#9564 (registration-only second-stage narrowing) was brainstormed and kept deferred. Its
re-evaluation trigger (spec `knowledge-base/project/specs/feat-runner-sut-registration-narrowing/spec.md`,
section "Re-evaluation trigger") has two parts: (a) at least 3 registration-only runner runs observed
after ADR-242 decision 20 (commit `2cfef66506`, 2026-10-06), and (b) the two PR-gated batteries
(~10.9 min) exceeding 20% of the median observed wait. Today nothing watches either; the trigger lives
in a comment and a spec.

This plan enrolls part (a) in an automated check and turns part (b) into an explicit hand-off.
The check counts commits on the default branch since `2cfef66506` that touch
`scripts/test-all.sh` or `scripts/lib/test-affected-paths.sh` with zero deleted lines across both files (a registration-shaped edit is purely additive; any deletion or rewrite is a semantic edit that took the full battery), and when the count first reaches 3 it
posts ONE comment on #9564 naming the count and the commits, asking a contributor to decide whether to
re-open the design, and stating that part (b) needs a human measurement. #9564 is never closed,
relabelled or reopened by the check.

**Mechanism decision (verified, see Research Insights):** the follow-through sweeper CAN express
"do not close" (exit 2/3/5 is a registered notify-only vocabulary) but it CANNOT express "comment once":
it posts a comment on every non-0/1 verdict with no dedup. A notify-only probe would therefore post a
"NOT YET" comment every day until the threshold, then an "ACTION REQUIRED" comment every day forever.
The convention itself says to use a dedicated scheduled workflow plus a back-reference for that shape.
So the deliverable is a small repo-scoped GitHub Actions cron watcher (same shape as
`.github/workflows/live-verify-pass-watch.yml` + `scripts/watch-live-verify-pass.sh`), not a
`scripts/followthroughs/` probe, and #9564 gets a plain-text pointer note instead of the
`follow-through` label and directive.

## Research Reconciliation — Spec/Brief vs. Codebase

| Brief or spec claim | Reality (checked on `origin/main`) | Plan response |
|---|---|---|
| "The sweeper treats exit 0 as PASS and may auto-close" | True: `run_one` exit 0 posts the PASS block then `gh issue close` (`scripts/sweep-followthroughs.sh`, `0) verdict="PASS" ... action="close"`). | Probe would never exit 0; moot because of the next row. |
| Implied: a followthrough probe + directive + label is the default fit | Exit 1 comments and leaves open; exit 2/3/5 comment under headings NOT YET / CANNOT ESTABLISH / ACTION REQUIRED and leave open (case `$rc` block). Every non-0/1 verdict posts a comment, always. Convention: "the sweeper comments on EVERY non-0/1 verdict with no dedup ... use a dedicated `scheduled-*-drift.yml` workflow + `Ref #N` for that shape instead." `sweep-followthroughs.sh` carries its own note: "A general per-verdict dedup is tracked separately". | Notify-only is expressible; once-per-crossing is not. Use the dedicated-workflow shape the convention prescribes. |
| "`earliest=` / `secrets=` fit a probe needing only git/gh read access" | `earliest=` is a wall-clock gate before the script runs (filing date is the convention). `secrets=GH_TOKEN` is mandatory for any gh-using probe because the sweeper runs probes under `env -i`. A git-log count needs neither. The sweeper checkout is `fetch-depth: 0`, `persist-credentials: false`. | Moot for the chosen mechanism; recorded so a later switch back to the sweeper does not re-derive it. |
| "Part (a) approximated by counting commits since `2cfef66506` touching the two runner files" | Holds. At plan time `git log --no-merges 2cfef66506..origin/main -- scripts/test-all.sh scripts/lib/test-affected-paths.sh` returns 1 commit (`6215e5a3fd`, #9594; `+15/-0` across the two files: a `run_suite` line with its comment block in `test-all.sh` and one edge array in `test-affected-paths.sh`, so purely additive). The brainstorm comment said zero; one landed since. Rate context: `git log --since=2026-09-01 -- scripts/test-all.sh` returns 122 commits (~3.4/day). | Counting every touching commit measures noise (review: Kieran P1, DHH P0). Counting only commits with ZERO deletions across both files is still an upper bound on registration-only runs (the classifier admits only added registration lines, so a deletion rules a commit out) but never undercounts them. The notice reports how many other touching commits were excluded. |
| "Local gate runs are not recorded" | Holds, checked as a set of sinks rather than one: `scripts/test-all.sh` writes per-suite durable logs and an opt-in `TEST_TIMING_LOG` on the contributor's machine (`_durable_log_dir`, default `/var/tmp/soleur-test-all-logs/<repo>-<pid>-<epoch>`, 14-day GC); `.github/workflows/ci.yml` sets `TEST_TIMING_LOG` only for CI runs (full battery, not the local bounded wait); `scripts/suite-durations*.tsv` are manifest weights, not observed waits; no `plugins/soleur/skills` consumer persists a local wall time (grep of `TEST_TIMING_LOG` and `AFFECTED_SUMMARY` outside the runner and its own suites). Nothing a CI job can read. | Part (b) stays a human measurement; the notice tells the reader where the local timing data lives (verify exact wording at /work). |
| "Two PR-gated batteries ~10.9 min" | 491 s (`registry-gate-mutation-battery`) + 162 s (`cf-tunnel-liveness-gate-mutations`) = 653 s = 10.9 min; bounded selection is 58.6 min at manifest weights, so 10.9 / 58.6 = 18.6%, which is BELOW the 20% bar. (b) can only hold if the median observed wait is under ~54.4 min (653 s / 0.20 = 3265 s). | Put this arithmetic in the notice: it tells the reader exactly what measurement flips (b). |

## Research Insights

**Premise validation (Phase 0.6).** #9564: OPEN, labels `priority/p3-low`, `type/chore`,
`domain/engineering`, `meta/machinery`, 2 comments (brainstorm result + correction), no `follow-through`
label, no directive. `2cfef66506` exists on `origin/main` (2026-10-06T10:11:21Z, #9552). Spec and brainstorm
exist on main. Draft PR #9660 is this branch's WIP PR; #9621 (the brainstorm PR) is merged. ADR corpus
grep (follow-through / notify-only / dedup): no ADR rejects a watcher workflow; ADR-033 (repo-scoped
GitHub Actions, default token) is the placement authority and ADR-270's `codeql-1537-revisit-watch.yml` is
the closest "notify once, never close, silent below the condition" precedent.

**Property List (Phase 0.6b).**

- P1. The count of registration-only runner edits since decision 20 is measured on a schedule without a human remembering.
- P2. A contributor is told exactly once when part (a) first holds, with the count and the commits.
- P3. #9564 is never closed, reopened or relabelled by the check.
- P4. The notice states that part (b) (and the "slowest step of a suite-adding PR" arm) need a human measurement, and says what to measure.
- P5. Retiring the check when #9564 is built or abandoned is one grep.

**Cut List.**

- `scripts/followthroughs/` probe + unfenced directive + `follow-through` label -> buys P1/P4, breaks P2 (no per-verdict dedup; daily comment for as long as the label stays on) -> cut as the transport; the workflow covers P1-P4.
- Generic reminder primitive (`event-scheduled-reminder`) -> one-shot at a fixed time; the count must be computed at fire time and a new `CHECK_REGISTRY` entry is a server deploy -> cut.
- `soleur:schedule` / `claude-code-action` wrapper -> wrapper-vs-curl check: the whole job is ~40 lines of bash plus one `gh issue comment`; an agent loop adds cost and a token-revoking post-step for nothing -> cut. (The workflow is still hand-written in the `soleur:schedule` shape: cron + `workflow_dispatch` + concurrency + `issues: write`.)
- A mechanical source for part (b) -> no recorded data exists -> cut; handled by P4 as an explicit hand-off.
- Self-disable counter, per-increment re-notification, a re-arm mode, or a second threshold -> one firing is the property (P2); the sentinel carries the threshold value only so a later edit to the constant is visible, and re-arming is not a supported feature.
- Env seams `WATCH_REPO_DIR` and `WATCH_THRESHOLD`, subject sanitization, `+/-` columns and the 20-line cap (plan-review, simplicity seat: each buys no listed property). `WATCH_BASE_SHA` stays because a fixture repo cannot contain the real base commit.

**Institutional learnings applied.** Convention sharp edges on public-repo forgery of control strings (any GitHub user can post the sentinel string; read it only from `github-actions`-authored comments, as `closed_precheck` does); "a probe that exits 0/1 on a notify-only tracker is a defect" (never-close asserted in a suite, not prose); "it didn't comment is indistinguishable from it worked" (the `--print-count` mode and the run-conclusion discoverability command exist for this); workflow `issues: write` scope lint (`scripts/lint-workflow-issue-write-scope.py`).

**Commands run once at plan time** (plan-sharp-edges: a plan that cites a probe has not verified it): `git merge-base --is-ancestor 2cfef66506... HEAD` (ancestor ok); the exact `git log --no-merges --format='%h%x09%cs%x09%s' <base>..HEAD -- <two paths>` (1 row, `6215e5a3fd`); the `--numstat` awk sum (`+15/-0`); and the dedup jq filter (`.author.login` is `github-actions` or `github-actions[bot]`, body contains the sentinel) against #9564's live comments (0 matches, field path `.comments[].author.login` present, value `deruelle` for the two human comments).

**Open Code-Review Overlap.** Open `code-review` issues naming planned files: #8659 and #7942 (`scripts/test-all.sh`), #8800 (`scripts/lib/test-affected-paths.sh`). Disposition: **Acknowledge** all three. They concern test-helper EXIT traps, unrun `*.mutation.sh` batteries and a census sandbox hazard; this plan adds one `run_suite` line and one edge array and touches none of those concerns. They remain open.

## Scope Check

| Ask | Mapped to |
|---|---|
| Enroll #9564 in an automated check | Phase 1 (script + workflow), Phase 3 (issue pointer note) |
| Part (a) mechanical | `scripts/watch-registration-narrowing-9564.sh` count |
| Part (b) cannot be mechanical | Notice text states it and the measurement; no code |
| Must NOT auto-close | Script's only `gh` writes are `issue comment`; asserted in the suite (Guard 1) |
| Comment once per crossing | Per-threshold sentinel read from bot-authored comments |
| Probe under `scripts/followthroughs/` + directive + label | Replaced with justification (Overview; Cut List); recorded for the PR body |
| Say why in the PR body if the sweeper is not used | AC9 |

Inferred items: none beyond registering the new suite in the test runner (mechanically required, Phase 2). Split assessment: single PR.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. The failure is a missed or repeated internal notice on a p3 maintenance issue; no product surface, billing, auth or data path is touched.

**If this leaks, the user's data / workflow / money is exposed via:** no vector. The workflow holds the default `GITHUB_TOKEN` with `issues: write` and `contents: read`, reads public git history and one issue's comments, and writes one comment containing commit SHAs and subjects that are already public.

**Brand-survival threshold:** none

threshold: none, reason: a repo-maintenance watcher with no user-facing surface and no secret beyond the default workflow token; the touched paths (`.github/workflows/registration-narrowing-watch.yml`, `scripts/`) are not in the sensitive-path set.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: infrastructure/tooling change confined to repo maintenance machinery. No UI-surface file in Files to Create/Edit (mechanical override did not fire), no regulated-data surface (GDPR gate skipped), no new persistent store or network connection (encryption posture skipped), no Terraform-managed resource (the cron is a GitHub Actions schedule, the repo's existing pattern for pure-GitHub-ops, so the IaC routing gate does not apply).

## Architecture Decision (ADR/C4)

No ADR: the plan makes no architectural decision. Choosing a watcher workflow over a sweeper probe applies the existing convention and ADR-033 placement; it does not reverse or extend an ADR. No C4 impact, checked against all three of `model.c4`, `views.c4`, `spec.c4`: external human actors (none added; the existing founder/contributor actors are unchanged); external systems (GitHub is already modeled; no new vendor); containers/data stores (none touched); actor-to-surface access relationships (unchanged). Embedded cardinalities: the new workflow does not use `actions/sentry-heartbeat`, adds no `monitor-slug`, no `sentry_cron_monitor` and no Resend emitter, so none of the counts `c4-count-parity` derives move; `bash plugins/soleur/test/c4-count-parity.test.sh` is green today (13/13) and is re-run as AC8.

## Observability

```yaml
liveness_signal:
  what: scheduled run of registration-narrowing-watch.yml (conclusion success on every run, comment or not)
  cadence: weekly (Mon 09:17 UTC) plus workflow_dispatch
  alert_target: GitHub Actions failed-run notification to repo watchers (a red run IS the alert; there is no Sentry surface for a repo-ops workflow)
  configured_in: .github/workflows/registration-narrowing-watch.yml
error_reporting:
  destination: workflow run conclusion (exit 3 CANNOT ESTABLISH or exit 1 comment-post failure) with ::error:: annotations
  fail_loud: true
failure_modes:
  - mode: baseline commit missing or not an ancestor of HEAD (shallow checkout, force-push)
    detection: script exits 3 with ::error:: naming the base SHA
    alert_route: red scheduled run
  - mode: gh read of issue state or comments fails
    detection: script exits 3 and posts nothing (never risks a duplicate)
    alert_route: red scheduled run, retried next week
  - mode: comment post fails at the crossing
    detection: script exits 1; sentinel is only ever written by the comment itself, so the next run retries
    alert_route: red scheduled run
  - mode: forged sentinel comment by a non-bot account
    detection: ignored by the author filter (suite scenario S4)
    alert_route: n/a, no suppression occurs
logs:
  where: GitHub Actions run log (stdout of the script, one summary line per run)
  retention: GitHub default (90 days)
discoverability_test:
  command: bash scripts/watch-registration-narrowing-9564.sh --print-count
  expected_output: threshold=3
```

## Guard Contract

### Guard 1 — never close, notify once

**Property.** The watcher posts at most one comment on #9564 for its `THRESHOLD`, only when the count of registration-shaped commits is at least that threshold, and never issues any write to #9564 other than that comment.

**Assembly.** The property quantifies over every `gh` invocation in `scripts/watch-registration-narrowing-9564.sh` (one chokepoint: the script is the only code the workflow runs) and over the one comment read that decides "already notified" (one jq filter). The suite derives the allowed call set from a recording mock `gh` (observed argv), never from a list of current call sites, and a source grep for the write verbs covers a branch no fixture reaches.

**Mutation matrix.**

| # | Edit (must drive the suite RED) | Scenario that reds | Targets |
|---|---|---|---|
| M1 | delete the sentinel check before posting | S3 (bot sentinel present, expect no comment) | dedup |
| M2 | change `>=` to `>` (off-by-one at the threshold) | S2 (count exactly 3 must post) | threshold |
| M3 | append `gh issue close "$ISSUE"` in a branch no fixture reaches | S9 source grep | never-close |
| M4 | drop the `github-actions` author filter on the sentinel read | S4 (non-bot forged sentinel must NOT suppress) | forgery |
| M5 | make the count always 0 so the run reports "below threshold" and exits 0 | S2 (must post at 3) plus the suite's scenario-count floor | the guard's own dispatch |
| M6 | key the dedup on the first comment only, or on the count instead of the threshold (count 5 with a threshold-3 bot sentinel present must stay silent) | S5 | second member after a compliant first; once, not per increment |
| M7 | treat a failed comments read as "no sentinel" and post | S7 | fail toward silence, never toward a duplicate |
| M8 | drop the zero-deletion filter from the count | S10 (a commit with a deleted line must not count) | registration-shaped population |

**Harness rows.** (H1) Break the recorder: make the mock `gh` stop appending to its call log; the self-check scenario (a known `gh issue view` must appear in the log) must red, otherwise "no write calls" passes vacuously. (H2) Must-PASS non-canonical input: a count of 4 with no sentinel posts exactly once, with commit subjects containing `#123` and a 300-char line. The suite's success is never `fail == 0` alone: it asserts `PASS + FAIL >= <scenario count>` so a run that executes zero scenarios cannot exit 0.

**Anchor.** The stored values are the `BASE_SHA` and `THRESHOLD` constants. One diff can edit both the constant and the suite, so the suite proves consistency, not integrity; acceptable because the watcher makes no integrity claim (advisory reminder). Forgery of the sentinel by a non-bot account is covered by M4.

## Files to Create

- `scripts/watch-registration-narrowing-9564.sh` — the watcher (default act mode, `--print-count` read-only mode). Not under `scripts/followthroughs/`: that directory is the sweeper's, and a file there is expected to be a probe with a tracker and directive.
- `scripts/watch-registration-narrowing-9564.test.sh` — mock-`gh` + fixture-git-history suite (scenarios below).
- `.github/workflows/registration-narrowing-watch.yml` — weekly cron + `workflow_dispatch`, `concurrency: {group: registration-narrowing-watch, cancel-in-progress: false}` (a dispatch racing the cron must not double-post; mirrors `codeql-1537-revisit-watch.yml`), `contents: read`, `issues: write`, `actions/checkout` pinned to the same SHA as siblings with `fetch-depth: 0` and `persist-credentials: false`, `timeout-minutes: 5`, one step running the script with `GH_TOKEN: ${{ github.token }}`, `GH_REPO`. Header carries a `RETIREMENT:` block.

## Files to Edit

- `scripts/test-all.sh` — one `run_suite "scripts/watch-registration-narrowing-9564" bash scripts/watch-registration-narrowing-9564.test.sh` line beside its siblings (`scripts/watch-live-verify-pass`). `scripts/*.test.sh` is not auto-globbed; an unregistered suite is the orphan class.
- `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv` — one row each for the new suite (copy the sibling row shape; durations `floor`; pick the shard leg the way the sibling rows document and run the shard totality/parity tests the registration touches before committing). Registration PRs routinely touch these; they are arms of `PR_GATE_MACHINERY_PATHS`, so this PR's local gate run will also take the PR-gated batteries.
- `scripts/lib/test-affected-paths.sh` — CONDITIONAL, expected NOT needed. Classification is EDGE, and the file's own header says to declare an `AFFECTED_<LABEL>_PATHS` array only when derivation (argv-literal self-edge, source closure, the `<x>.test.sh -> <x>.sh` name-stem convention) misses a real dependency. The consumers that decide are `scripts/lint-orphan-test-suites.sh` (census: UNCLASSIFIED is red) and the `--print-selection` pre-pass in `scripts/test-all.sh`; add `AFFECTED_SCRIPTS_WATCH_REGISTRATION_NARROWING_9564_PATHS` only if the census names the suite unclassified (the derivation claim is unverified until that run). Never `ALWAYS_ON_SUITES` (that would charge every contributor's local run).
- Issue #9564 (GitHub, not a repo file) — one new comment pointing at the workflow (Phase 3). No body edit (a body round-trip can race a human edit), no `follow-through` label, no directive.

Glob verification at /work time: `git ls-files | grep -E '^scripts/watch-.*9564'` must show exactly the two new scripts after `git add`; `git ls-files .github/workflows | grep registration-narrowing` exactly the workflow.

## Implementation Phases

### Phase 1 — Watcher script and workflow

1. Write the failing suite first (cq-write-failing-tests-before): scenarios S1-S11 below, against a not-yet-written script.
2. `scripts/watch-registration-narrowing-9564.sh`, `set -uo pipefail` (not `-e`: every failure path is an explicit code), xtrace refusal in the prologue (matches the repo's probe prologue). Constants: `ISSUE=9564`, `BASE_SHA=2cfef66506c67207fc65b4250689842ff5ea20ba`, `THRESHOLD=3`, the two paths. One test seam: `WATCH_BASE_SHA` (the fixture repo cannot contain the real base commit); tests run the script with cwd inside the fixture repo.
3. Flow, in this order (state first, so a retired watcher cannot go red on a history rewrite):
   - `--print-count`: print `threshold=3 base=<short>` first, then `count=<N>` or `count=unknown (<reason>)`; exit 0 always (read-only; the declared discoverability probe).
   - `gh issue view 9564 --json state,comments`: read failure -> exit 3, post nothing; state not `OPEN` -> exit 0 (self-disable).
   - Resolve the measurement: `git cat-file -e "$BASE^{commit}"` and `git merge-base --is-ancestor "$BASE" HEAD`, else `::error::` and exit 3 (CANNOT ESTABLISH, never a quiet green). On an OPEN tracker a broken base is a broken watcher and a red weekly run is the intended loud signal; closing #9564 retires it.
   - `git log --no-merges --numstat --format='C %h %cs %s' "$BASE..HEAD" -- <two paths>`: group by commit, sum added and deleted per commit (a `-` numstat field for a binary file counts as a deletion, failing toward not counting); the count is commits with zero deletions; also keep the number of excluded touching commits.
   - Count below `THRESHOLD`: print `count=N below threshold=3; no action`, exit 0 (silent green).
   - Dedup: jq select comments whose `.author.login` is `github-actions` or `github-actions[bot]` (both spellings: GraphQL vs REST) and whose body contains `<!-- registration-narrowing-watch:v1 threshold=3 -->`. Present -> exit 0. (A human deleting the notice causes one re-post; accepted.) `gh issue view --json comments` returns all comments for an issue this size; #9564 has 2.
   - Compose and post one comment via `gh issue comment 9564 --body-file -`; failure -> exit 1. The body ends with the sentinel. The only `gh` verbs in the file are `issue view` and `issue comment`.
4. Notice body (text authored in the script; subjects truncated to 100 chars; no closing keyword anywhere):
   - Heading: `### Re-evaluation watch: part (a) reached (N registration-shaped runner commits since 2cfef66506)`.
   - The qualifying commits (`sha date subject`), and "K other commits touched the two runner files with deletions and were not counted". State it is still an upper bound on registration-only runs.
   - What it does NOT show: part (b) and the "gate is again the slowest step of a suite-adding PR" arm have no recorded data. Measurement to take: wall time of the next registration-only local runs (the `[affected]` summary line and the per-suite timing on the contributor's machine); compare the two PR-gated batteries (653 s) with the median observed wait. At manifest weights 653 / 3516 s = 18.6%, so (b) holds only if the median observed wait is under about 54.4 min.
   - Ask: a contributor decides whether to re-open the design (spec FR1/FR2, brainstorm alternatives) or leave it deferred. Posted once; the issue stays open; delete the workflow per its RETIREMENT block to stop it.
5. Workflow YAML as in Files to Create; header documents WHY a dedicated workflow (sweeper has no per-verdict dedup; convention directs here), self-disable on #9564 not OPEN, and `RETIREMENT:` listing every site: the workflow, the script, the suite, the `run_suite` line, the two TSV rows, the #9564 pointer comment.

### Phase 2 — Register the suite

Census by sibling: `git grep -n 'watch-live-verify-pass' -- scripts` enumerates the registration sites (note `watch-live-verify-pass` sits in `ALWAYS_ON_SUITES` because its subject is a live scanner; this suite is not one, so do not copy that line); add the `run_suite` line and the two TSV rows, then run `bash scripts/test-all.sh --print-selection` against this diff and confirm the new suite is selected (`AFFECTED_SELECTED` value `1`) and nothing else unexpected is. Run the orphan linter and shard-leg parity checks that the registration touches (names found by that grep). This PR's own registration is a genuine registration-only runner edit (a purely additive commit, so it counts toward (a)): note its local wall time in the PR body as the first part-(b) datapoint.

### Phase 3 — Point #9564 at the watch (post-merge step, scripted)

After merge, `gh issue comment 9564` with one paragraph: what watches the trigger, where (workflow + script paths), that part (b) is a human measurement, and that it is deliberately NOT a sweeper tracker (no follow-through label, no directive: the sweeper would comment daily). The comment must not contain an HTML-comment opener or the directive token. Then `gh workflow run registration-narrowing-watch.yml` once and read the run log: count line present, run green (the convention's "it didn't comment is indistinguishable from it worked" check). If the count is already 3 or more, that manual run posts the single notice, which is the intended first firing; confirm exactly one new bot comment and #9564 still OPEN.

## Test Scenarios (suite `scripts/watch-registration-narrowing-9564.test.sh`)

Fixture: temp git repo with a base commit (passed via `WATCH_BASE_SHA`), commits that touch / do not touch the two paths, one merge commit; PATH-prepended mock `gh` recording every argv to a call log and serving per-scenario issue JSON; the script runs with cwd in the fixture.

- S1 two qualifying commits -> exit 0, zero `gh issue comment` calls.
- S2 exactly three -> exit 0, exactly one comment; body names `3`, every SHA, `part (b)`, states the issue stays open.
- S3 three + bot-authored sentinel -> no comment.
- S4 three + sentinel from a non-bot author -> comment still posted (forgery does not suppress).
- S5 five + bot sentinel -> no comment (once, not per increment).
- S6 issue state `CLOSED` -> exit 0, no comment, and no base-commit check (a missing base on a closed issue does not go red).
- S7 comments/issue read fails -> exit 3, no comment.
- S8 base SHA absent on an OPEN issue -> exit 3, no comment, `::error::` on stderr; comment post fails -> exit 1.
- S9 the call-log set is a subset of `{issue view, issue comment}` in every scenario, and a source grep finds none of `gh issue (close|edit|reopen|delete|lock|transfer)` or a mutating `gh api`.
- S10 commits touching only other paths, merge commits, and a touching commit with a deleted line are not counted; the excluded count is reported.
- S11 `--print-count` prints a `threshold=3` line even when the base is unresolvable and exits 0; H1 recorder self-check; H2 (count 4, no sentinel, `#123` and a 300-char subject) posts exactly once; scenario-count floor asserted.

## Acceptance Criteria

### Pre-merge (PR)

- AC1. `bash scripts/watch-registration-narrowing-9564.test.sh` exits 0 with all of S1-S11 executed (the suite asserts its own scenario floor).
- AC2. Each Guard 1 mutation M1-M8 and harness row H1 was applied once to the script/suite and the suite went RED (record the matrix result in the PR body); reverting restores green.
- AC3. `bash scripts/watch-registration-narrowing-9564.sh --print-count` prints a line containing `threshold=3` (the declared discoverability_test).
- AC4. `grep -nE 'gh +issue +(close|edit|reopen|delete|lock|transfer)' scripts/watch-registration-narrowing-9564.sh` returns nothing, and the workflow YAML has no `run:` step other than the script call.
- AC5. The workflow passes `python3 scripts/lint-workflow-issue-write-scope.py` (its own invocation, run over the workflow tree), `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (CI's form, so every changed doc is scanned, plan and tasks included), and `bash scripts/lint-workflows.sh` reports no new finding for the new file; `permissions` lists only `contents: read` and `issues: write`; the YAML declares the `concurrency` group.
- AC6. The suite is registered and classified: `bash scripts/test-all.sh --print-selection` on this diff prints `AFFECTED_SELECTED` with value `1` for `scripts/watch-registration-narrowing-9564`; `bash scripts/lint-orphan-test-suites.sh` reports it classified (no UNCLASSIFIED) and the shard totality/parity checks are green. If either names it unclassified, add the edge array described under Files to Edit.
- AC7. No file under `scripts/followthroughs/` is added or edited, and no `follow-through` label or directive is applied to #9564.
- AC8. `bash plugins/soleur/test/c4-count-parity.test.sh` is still green (13/13).
- AC9. The PR body says why the sweeper was not used (no per-verdict dedup; exit 2/3/5 would post a comment every sweep; the convention directs this shape to a dedicated workflow), uses `Ref #9564` and no closing keyword for it, and records this PR's own local-gate wall time as the first part-(b) datapoint.

### Post-merge (agent-run via `gh`; automation feasible, no human gate)

- AC10. `gh workflow run registration-narrowing-watch.yml` completes green; its log shows the `count=` line. If count >= 3, exactly one bot comment containing the sentinel exists on #9564 and the issue is OPEN with unchanged labels. A second manual run posts nothing.
- AC11. #9564 carries the pointer comment (Phase 3).

## Risks and Sharp Edges

- **The count will likely cross 3 within about a day of merge** (1 commit already; this PR is a second; ~3.4 runner-file commits per day measured before the zero-deletion filter, which will lower it). The first notice is effectively "part (a) is met, go measure (b)". That is the intended behaviour and says something true: 3 is a low bar, the real gate is (b). `THRESHOLD` is one constant if the first measurement says to revise it (the spec calls the numbers proposed). Reviewers (DHH, CTO, code-simplicity) argued this makes the whole watcher near-vacuous and recommended dropping the suite or the code; see `decision-challenges.md`.
- A brand-new suite registration edits `scripts/test-all.sh`, so this PR itself counts toward (a). It is a legitimate registration-only run; do not special-case it.
- Weekly cadence means up to a 7-day delay after the condition first holds; acceptable for a p3 deferred issue and cheaper than daily.
- Sentinel forgery: any account can paste the sentinel; only `github-actions`-authored comments count (both author spellings).
- Pre-merge verification of the NEW workflow via `workflow_dispatch --ref <branch>` is impossible (a workflow must exist on the default branch first, learning `2026-04-21-workflow-dispatch-requires-default-branch`), so the logic lives in the script (locally testable with a mock `gh`, option 2 of that learning) and the live run is the post-merge AC10.
- A plan whose `## User-Brand Impact` is empty fails deepen-plan; this one carries the threshold and the scope-out bullet.
- Do not move the script under `scripts/followthroughs/` later "for tidiness": lints there assume a sweeper tracker, and the directive gate would then be expected.
