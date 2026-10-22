---
title: "fix: ci-head-verdict.sh measures its stall clock from the head, not only the original ready event"
type: fix
date: 2026-10-22
slug: ci-head-verdict-stall-clock
branch: feat-one-shot-9757-item3-cto-followups
issue: 9757
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix: ci-head-verdict.sh measures its stall clock from the head, not only the original ready event

Umbrella #9757 stays open. The PR body says `Ref #9757` and carries no closing keyword. Merge through the queue
(`gh pr merge <N> --squash --auto`), never `--admin`. Spec lacks a valid `lane:` (no spec.md exists for this
branch), so `lane: cross-domain` is the fail-closed default.

## Overview

Item 3 of umbrella #9757 is the set of CTO follow-ups ruled on 2026-10-22 (the list is not in the issue body or
its comments; see Research Reconciliation). This run implements only **P3**: `plugins/soleur/scripts/ci-head-verdict.sh`
decides `stalled` by comparing server time with the PR's latest ready event T. A head pushed more than 120 minutes
after T therefore reads `stalled` at once, either as `pending-full` for a run that started a minute ago or as
`no-run` in the seconds before CI creates the run. Every consumer answers `stalled` with `gh pr ready --undo` then
ready, which would cancel a healthy fresh run and restart the whole battery.

The fix measures the stall clock from `max(T, A)`: A is the newest kept run's own `created_at` when a run exists, and otherwise the
earliest `created_at` among the head's check suites (the server-assigned moment CI first saw this head). The CTO ruled this design on
2026-10-22, refined after plan review (see `Decision Classes` in `decision-challenges.md`). The P4 items and P2 are listed below as separate follow-up PRs and
are NOT implemented here.

## Research Insights

**Premise validation (2026-10-22).** #9757 is OPEN (so `Ref`). Draft PR #10873 is OPEN. `plugins/soleur/scripts/ci-head-verdict.sh`
exists on `origin/main` and the stall test is the final `elif` of `cmd_verdict` (`NOW_EPOCH - t_epoch > STALL_MINUTES * 60`), so the
CTO's "~line 289" holds (lines 288-289). No open PR touches the script (`gh pr list` file filter returned nothing) and no open
`code-review` issue names any planned file. ADR corpus: the mechanism is ADR-276's own Decision 4 supersession (line ~392: "no
deciding run N minutes after the ready event, N fixed at 120"); no ADR rejects a head-anchored clock, but the sentence is
the thing the fix changes, so an addendum is a deliverable (Architecture Decision section).

**Property List.**

1. A head pushed after the ready event never reads `stalled` until 120 minutes after that head first appeared in CI.
2. A head that really is stuck (old push, old ready event) still reads `stalled` exactly as today.
3. A failed or empty read of the head's CI history is `state=error` (exit 3), never a closed-set state and never a guess.
4. The common paths (green, fresh, conflicting, awaiting-approval, never-ready, draft) cost no extra API call, and a head that has a
   kept run costs none either (the run is its own anchor).
5. Named residual (an accepted trade, not a property): a head with no kept run AND no visible check suites for a long time reads
   `state=error` rather than `stalled`.

**Cut List.** A `head_sha` filter inside the suites jq (the endpoint is keyed by sha; a mismatch is asserted in the shape check instead,
so a server fault fails closed); Re-deriving the stall threshold N (120 is unchanged); a PR `updated_at` or commit-date anchor (client-controlled
or reset by comments); an always-read suite lookup (extra paginated call on every verdict); changes to `wait-ready-run`
(T is fresh by construction there); any change to the dirty/conflicting rule or to `awaiting-approval`; editing the
`ABSENT  test (stalled: no full CI run decided after the ready event)` line (still literally true, and test-pinned at
`admin-merge-ready.test.sh` row S6). Each is covered by the CTO ruling or by an existing mechanism.

**Measured anchor (live, PR #10873, head 5b3f5af68a, 2026-10-22).** Commit committer date 20:48:25Z (client-authored);
check suites at the head sha `created_at` 20:48:29Z to 20:48:36Z across apps `claude`, `soleur-ai`, `entire`, `github-actions`
(present before any `ci.yml` run); the `ci.yml` pull_request run `created_at` 20:48:36Z. Research probe on another sha: committer
17:14:49Z but suite 19:30:29Z, so commit dates are not push time. Record lifetime (measured the same day): the listing is still
populated for a commit 200 days old (7 suites, earliest 2026-04-05T20:48:55Z) and returns 100 of 161 suites on page 1 for a merged
commit 100 days old, so `--paginate --slurp` is required and the oldest probed record is not gone. Command:
`gh api repos/jikig-ai/soleur/commits/<sha>/check-suites?per_page=100 --jq '[.total_count,(.check_suites|length)]|@tsv'`. GraphQL `Commit` has no `pushedDate` (introspection). Command:
`gh api repos/jikig-ai/soleur/commits/<sha>/check-suites?per_page=100 --jq '.check_suites[] | [.app.slug,.created_at]|@tsv'`.

**Learnings applied.**

- `2026-10-06-a-non-completed-verdict-on-one-clock-false-pages-two-ways.md`: a non-completed verdict is several clocks; give
  the anchor per case and keep a floor so a just-created run cannot trip it. Here the anchor is `max(T, A)` and a push can
  only move the clock later, never earlier.
- `2026-10-10-an-error-must-not-borrow-a-success-states-vocabulary-and-every-consumer-stub-hid-it.md`: the error marker stays
  outside the closed state set; the new read's failure uses the same `fail_api` path.
- `2026-09-25-gh-stub-must-mirror-real-cli-flags.md`: the new stub route must use the real argv (`api --paginate --slurp ...`).
- `2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill-and-the-fixture-stacked-x-on-x.md`: every new mutation row is landed
  exactly once and must not crash; keep `st=stalled` unique in the script (mutant M9 edits it).
- `2026-10-14-a-guard-that-reads-run-records-inherits-their-lifetime-and-i-assumed-it.md`: a re-run keeps the original run's
  `created_at`, so a re-run does not reset the clock (named residual).

**CTO ruling carried in** (verbatim record in `specs/feat-one-shot-9757-item3-cto-followups/decision-challenges.md`): anchor (B) read
lazily; failure, malformed body and empty list are `state=error` exit 3 (empty gets `reason=no-check-suites`); dirty and
awaiting-approval paths unchanged. Residuals to name in the header: a manual re-run of an old run does not reset the clock; a
force-push back to a previously pushed sha reuses its old suites (A is old, the clock falls back to T); the suite list is consulted
only after T-based staleness.

## Research Reconciliation: Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| The brief says the CTO P2/P3/P4 list is in the #9757 body, comments, or a plan/spec | It is in none of them. The body is the argv-bearer S2 checklist; the comments hold delegations and receipts and only name "P2 merge-effect-class classifier, P3 `ci-head-verdict.sh` staleness, the P4 small PRs". The definitions are in the CTO ruling of the 2026-10-22 held-merge session (session transcript, not durable) | The definitions are restated verbatim in "Follow-up PRs" below, and Phase 4 files tracking issues (P2, and one checklist for P4) so the list stops living in a transcript |
| CTO: "measure staleness from max(ready event, head push or run-creation time)" (directional, "I did not read their code") | A run-creation time alone leaves the no-run window right after a push open, and the repo exposes no server-assigned push time | Refined by CTO rulings to a hybrid: the kept run's `created_at` when a run exists, else the earliest check-suite `created_at` at the head sha, read lazily |
| Header/prose say "stall window counts from the ready event" | True only for a head that has not moved since T; false after the fix | Phase 3 updates the prose in the script header, `monitor-pr-checks.sh`, `admin-merge-ready.sh`, `ready-run-wait.md`, and adds an ADR-276 addendum |

## Proposed Solution

In `cmd_verdict`, the final stall decision becomes two-step. Names below are content anchors, not line numbers. The anchor design is
the CTO's hybrid ruling (2026-10-22, after plan review): a kept run is its own anchor; only a head with no kept run needs the
check-suites read.

1. Keep the existing test as a lazy gate: `st` is `pending-full` or `no-run` (and not the `conflicting` branch) and
   `NOW_EPOCH - t_epoch > STALL_MINUTES * 60`. Nothing else changes before this point, so the green, fresh, conflicting,
   awaiting-approval, never-ready, draft and `n/a` paths make no new call.
2. Inside that branch, pick A:
   - **A kept run exists** (`RUN_ID` non-empty, any status or conclusion): A is that run's `created_at`. `read_newest_run` already
     holds the row, so it also sets `RUN_TS` (epoch seconds, from `created_at`); no extra API call and no new failure mode.
   - **No kept run** (`no-run-after-ready`): call a new `read_head_anchor "$PR_SHA"`, which runs
     `gh api --paginate --slurp "repos/{owner}/{repo}/commits/$1/check-suites?per_page=100"`. The `jq -e` shape check requires an array
     of objects each holding a `check_suites` array whose every element has `head_sha` equal to the head and a string `created_at`;
     anything else is `fail_api` (reason `api-error`, exit 3). The anchor is the minimum `created_at` via `fromdateiso8601`, written
     so an empty list is an explicit error (`min` of an empty array is `null` with exit 0, which bash arithmetic would read as 0 and
     silently fall back to T): an empty list is `fail_api` with reason `no-check-suites` and the stderr text
     `no check suites visible at <sha>; cannot place the stall clock (a head with no CI history is not judged stalled)`.
     `ANCHOR_REASON` is reset to `api-error` on entry to `read_head_anchor`, and the call site passes `fail_api "$ERRMSG" "$ANCHOR_REASON"`.
3. `stalled` stands only if `NOW_EPOCH - max(t_epoch, A) > STALL_MINUTES * 60`; otherwise the original `st` and `rs`
   (`pending-full run-in-progress`, `no-run run-<conclusion>`, or `no-run no-run-after-ready`) are emitted. The stalled reason token
   stays `undecided-after-120m` (consumers and tests key on it). Keep `>` (strict): A+7200 is still pending, A+7201 is stalled.

`st=stalled` stays a single occurrence in the file (mutant M9 replaces it) and the in-test assertion in Phase 1 pins that. The lines
mutants M2, M3, M4, M5, M13, M34-M36 edit stay as written. `wait-ready-run`, `ready-count`, the applicability read and the closed state
set are untouched. `gh --paginate --slurp` is already used by `read_test_row`, so no new `gh` version floor.

Verified live on 2026-10-22 against PR #10873 (head 5b3f5af68a): the shape check passes and the program prints `1792702109`, equal to
`date -u -d 2026-10-22T20:48:29Z +%s`, the earliest suite time.

## Implementation Phases

### Phase 1 - Failing tests first (`cq-write-failing-tests-before`)

Edit `plugins/soleur/test/ci-head-verdict.test.sh` before the script:

1. Stub: add a `gh` route for the exact argv `api --paginate --slurp repos/{owner}/{repo}/commits/$STUB_H/check-suites?per_page=100`.
   It serves `$FX/suites.json` (wrapped as `[{total_count, check_suites: [...]}]`) when present, and otherwise a built-in default of ONE
   suite at `iso_at -3600` (the head existed before the ready event), so `mkrow` and every existing stalled row (V6) are untouched.
   It honours `suites.fail` and `suites.raw` like the other routes. Add helper `setsuites <dir> <offset-from-T>...` that REPLACES the
   default (no offsets writes an empty list); suites carry `head_sha` H unless a row overrides it. Comment the default at the stub.
2. `addrun` already records `created_at`; no change. Existing rows V5, V9, V17, V23 run with a kept run at `+2` and now anchor on it:
   V5's boundary rows become 5220 pending, 7202 pending (A+7200 exact), 7203 stalled, 7800 stalled; V9, V17, V23 read at 7800 and keep
   their expectations. V6 (no run) keeps its expectation through the default suite.
3. New rows (named V24-V27 so existing ids stay stable; each stalled-branch row reads at an old-enough now so it is not vacuous):
   - V24 fresh push after T, run anchor: ready at T, run created T+7500 in flight, now T+7560: `pending-full run-in-progress` (was
     `stalled`). Boundary: now = T+7500+7200 pending, +7201 stalled. Same for a cancelled newest run (`no-run run-cancelled`).
   - V25 fresh push, suite anchor: no run, `setsuites $d 7500`, now T+7560: `no-run no-run-after-ready` (was `stalled`); T+14700
     pending, T+14701 stalled. Earliest-of-many: `setsuites $d 7500 7900`, now T+14701: stalled (min), not pending (a max would give
     6801 s). Default suite (older than T): the clock stays T.
   - V26 suite read failures, all at now = T+7800 with no kept run: `suites.fail`, HTML body, `check_suites` not an array, a suite with
     null or garbage `created_at` on a head-H suite, and a suite whose `head_sha` is `$OTHER_H` each give rc 3, `state=error` outside the
     closed set, one marker, `api-error`; an empty list gives rc 3 `reason=no-check-suites`; none gives a closed-set state; `nomiss`.
   - V27 laziness: at now = T+7800 (old enough that the gate would pass if the read were hoisted) NO suite request is logged for
     green-test, `dirty` (conflicting), awaiting-approval, and a kept run (pending-full); at a fresh now (T+600) none for no-run; the
     request IS logged exactly when no kept run exists and the T-based test says stalled. Never-ready, draft and `n/a` rows already
     assert no later reads and gain a `notcalled check-suites`.
   - A suite-self check: `[[ $(grep -c 'st=stalled' "$REAL_SUT") == 1 ]]` so a refactor fails loudly instead of killing M9 by crashing.
4. Mutation rows (each lands exactly once, killed by the named rows; the harness flags crashes):
   - M37 run anchor ignored (clock stays `t_epoch` when a run exists): `row_V24 row_V5`.
   - M38 earliest becomes latest suite (`min` to `max`): `row_V25`.
   - M39 drops T from the `max` on the suite path (anchor only): `row_V25` (default suite at T-3600 would stall early).
   - M40 empty list falls back to T instead of erroring: `row_V26`.
   - M41 lazy gate opened (`NOW_EPOCH - t_epoch > STALL_MINUTES * 60` becomes `> 0`): `row_V27`.
   - M42 suite read failure ignored (continues with T): `row_V26`.
   - M43 `head_sha` equality assertion dropped from the shape check: `row_V26`.
5. Raise `MIN_ASSERTIONS` to the new measured total and `MIN_MUTANTS` to the new measured count (35 plus the 7 above); both are lower
   bounds, so say so in the suite header comment next to the floors. Update `plugins/soleur/test/fixture-relative-assert.baseline.txt`
   only if `fixture-relative-assert.test.sh` reports a changed count for this file.

Run the suite red first (V24, V25 and the shifted V5 rows must fail against the unmodified script), then proceed.

### Phase 2 - The fix in `plugins/soleur/scripts/ci-head-verdict.sh`

1. `read_newest_run`: also set `RUN_TS` from the chosen run's `created_at` (the jq already computes `ts`).
2. Add `ANCHOR_EPOCH` / `ANCHOR_REASON` globals and `read_head_anchor` next to the other reads, following the `read_test_row` /
   `read_newest_run` error-message pattern (`head -c 200 "$WORK/err" | tr '\n' ' '`). The jq program stays inside the function.
3. Replace the final `elif` of `cmd_verdict` with the two-step decision from "Proposed Solution", keeping the dirty/`conflicting`
   branch first and unchanged. Add comments at the `read_head_anchor` call site naming the residuals (a re-run keeps the original
   `created_at`; a force-push back to a previously pushed sha reuses its old anchor).
4. Header comment (the single source of the rule): rewrite the rule-5 paragraph ("pending-full and no-run become `stalled` once more
   than N=120 minutes have passed since T") to "since max(T, A)", define A for both paths (the kept run's `created_at`; else the
   earliest check-suite `created_at` at the head, read only when T alone would already say stalled), add `no-check-suites` to the
   documented reasons, and name the residuals: a manual re-run does not reset the clock; a force-push back to a previously pushed sha
   reuses its old suites (A is old, the clock falls back to T); a head that stays suite-less AND run-less long-term reads `state=error`
   instead of `stalled` (the empty-list choice; the CTO ruling names the flip). Do not write the literal `STALL_MINUTES=120`
   (mutants M4/M5 replace it exactly once). Keep "every time comes from the SERVER" true.
5. `usage()` text: unchanged; the closed state set is unchanged.

### Phase 3 - Prose that goes stale with the fix (sentence-level only; the rule is defined once, in the script header)

- `plugins/soleur/scripts/monitor-pr-checks.sh` (the `stalled)` message) and `plugins/soleur/scripts/admin-merge-ready.sh` (the
  `STALLED:` message): replace the parenthetical "the stall window counts from the ready event" with "see ci-head-verdict.sh for the
  stall clock", so the sentence cannot go stale again. The test-pinned `ABSENT  test (stalled: ...)` line is untouched. Header comments in
  the two scripts are edited only where `grep -n "ready event"` shows they restate the 120-minute rule.
- `plugins/soleur/skills/ship/references/ready-run-wait.md` (the `stalled` clause of the six-state sentence): one clause pointing at
  the verdict script's header.
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`:
  a two-sentence dated addendum bullet after the Supersession bullet (the ADR keeps originals unedited): the stall clock is
  `max(T, A)` and where the full rule lives (the script header). The residuals and error semantics are not restated.
- Acknowledged, not edited: `scripts/followthroughs/ci-draft-light-soak-9728.sh` and its test restate "120 minutes after the ready
  event" for the soak census and retire with #9728; its test pins that probe N equals the resolver N, which stays 120.

### Phase 4 - Verify and ship

- `bash plugins/soleur/test/ci-head-verdict.test.sh`, `plugins/soleur/scripts/admin-merge-ready.test.sh`,
  `plugins/soleur/test/monitor-pr-checks.test.sh`, `plugins/soleur/test/admin-merge-ready-wiring.test.sh`,
  `plugins/soleur/test/drain-prs.test.sh` (it reaches the real script at its line ~177), `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`
  and `scripts/followthroughs/ci-draft-light-soak-9728.test.sh` all green (each launched detached per ship's rc-file recipe, long
  suites under `setsid nohup`, and no kill-by-command-line: use `plugins/soleur/scripts/lib/proc.sh`). `shellcheck` clean on the script and the test.
- `plugins/soleur/test/c4-count-parity.test.sh` green (the C4 gate for a "no C4 impact" conclusion).
- The PR is `Ref #9757`, plugin and docs only: no `.github/workflows/**`, no `apps/*/infra/**`, so it fires no production apply. The
  script and test are `@deruelle` in `.github/CODEOWNERS` (lines 256-257); if the merge is held for code-owner review, ask the operator
  ONE plain delegation question per `plugins/soleur/skills/ship/references/operator-holds.md` section 3 (the standing delegation on
  #9757 does not cover a new PR). Merge via queue only.
- File the tracking issues (CTO-ruled shape: one issue for P2 and ONE checklist issue for P4a-P4d, labels `priority/p3-low`
  `domain/engineering`, milestone `Post-MVP / Later`, body `Ref #9757` and the table below verbatim), through the filing hook's body-file
  recipe.
- Live check after merge (read-only): `bash plugins/soleur/scripts/ci-head-verdict.sh verdict <a currently open ready PR>` prints one
  marker whose state is in the closed set or `state=error`.

## Follow-up PRs (separate, one each, NOT in this PR)

Source: CTO ruling of the 2026-10-22 held-merge session, restated from the ruling text (the CTO noted the P3 and P4 mechanisms are
"directional; I did not read their code", so each PR starts with a read and may re-scope).

| ID | PR | Definition | Notes |
|---|---|---|---|
| P2 | needs an ADR, own PR | Add `merge-effect-class.sh`: infra, migration or main-push-triggered production workflow paths mean production-effecting; unknown path means production-effecting (stricter default). Optionally a delegation Scope class "merge changes referencing epic #N" with a verifier test row; edit `standing-delegation.md` sections 1-2 | Genuine founder fork (the authority class widens): out of scope for this run |
| P4a | own PR | Add a gitleaks per-commit pre-push check (`origin/main..HEAD`) to ship Phase 6.4 (Unpushed-Commits Gate in `plugins/soleur/skills/ship/SKILL.md`) | |
| P4b | own PR | Make `plugins/soleur/scripts/affected-tests.sh` select the kb-consumers suite when a new fixture contains `knowledge-base/` | |
| P4c | own PR | Add a per-PR monitor lock so there is one monitor per purpose | Start from `plugins/soleur/scripts/monitor-pr-checks.sh` |
| P4d | own PR | On a local battery refusal (rc=4), wait a bounded time, then record "CI is the gate" and continue rather than stopping | ship `SKILL.md` documents rc=4 as REFUSED (nothing ran) around the detached-battery recipe |

Each follow-up PR uses `Ref #9757` only, merges through the queue (no `--admin`), and asks one delegation question if its merge is
held. The apply-workflow annotations (item 2) are not touched by any of them.

## Files to Edit

- `plugins/soleur/scripts/ci-head-verdict.sh` (new `read_head_anchor`, two-step stall decision, header)
- `plugins/soleur/test/ci-head-verdict.test.sh` (stub route, `mkrow` default suite, `addsuite`, rows V24-V27, mutants M37-M42, floors)
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` (only if the checker reports a changed count)
- `plugins/soleur/scripts/monitor-pr-checks.sh` (message and header wording)
- `plugins/soleur/scripts/admin-merge-ready.sh` (message and header wording)
- `plugins/soleur/skills/ship/references/ready-run-wait.md` (one sentence)
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` (addendum)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9757-item3-cto-followups/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9757-item3-cto-followups/decision-challenges.md` (already written by the plan run)

## Open Code-Review Overlap

None. Queried open `code-review` issues for the script, its test, `monitor-pr-checks.sh`, `admin-merge-ready.sh` and ADR-276: no body names any of them.

## Architecture Decision (ADR/C4)

### ADR

Extension of an existing ADR: amend **ADR-276** with a dated addendum (not a new ADR, no new ordinal): the stall clock of Decision 4
(supersession (2)) is `max(T, A)` with A the earliest check-suite `created_at` at the head sha, read lazily; empty or failed read is
`state=error`. Authored via `soleur:architecture` conventions as a Phase 3 task of THIS PR, not a follow-up issue.

### C4 views

No C4 impact. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`): (a) external human actors: none added; (b)
external systems: GitHub is already modeled (`model.c4`, `github = system "GitHub"`) and this reads another route of the same REST API;
(c) containers/data stores: none touched (a plugin script with no store); (d) actor-to-surface access relationships: unchanged. A grep for
`ci-head-verdict|draft-light|wait-ready-run` returns 0 in all three files, so no element description is falsified. `plugins/soleur/test/c4-count-parity.test.sh`
runs green in Phase 4 to back the conclusion for derived cardinalities.

### Sequencing

The ADR text is true as soon as the PR merges (no soak). No `adopting` status.

## User-Brand Impact

- **If this lands broken, the user experiences:** a ready PR that is wrongly reported `stalled` (an unneeded `gh pr ready --undo` that cancels a healthy CI run and costs a full battery restart), or a truly stuck PR that is reported `pending-full` forever instead of `stalled`.
- **If this leaks, the user's workflow is exposed via:** no vector; the change reads public check-suite timestamps through the caller's existing `gh` login and prints one marker line. No credential, personal data or write path is added.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** the script grades CI state and never merges or writes; the worst case is a delayed or spuriously restarted CI run. threshold: none, reason: the diff touches no path in the canonical sensitive-path regex (checked: the script, test, two sibling scripts, one reference and the ADR all return "no" against `SENSITIVE_PATH_RE`).

## Observability

```yaml
liveness_signal:
  what: the verdict command prints exactly one SOLEUR_CI_HEAD_VERDICT marker as its last stdout line on every decided path, and state=error with exit 3 on every read failure (including the new check-suites read)
  cadence: per invocation (every ship Phase 7 poll tick, monitor-pr-checks.sh tick, admin-merge-ready.sh call, drain-prs triage)
  alert_target: the invoking agent or operator reads the marker in the tool result; monitor-pr-checks.sh and admin-merge-ready.sh turn stalled and error into an explicit terminal message
  configured_in: plugins/soleur/scripts/ci-head-verdict.sh (emit and fail_api)
error_reporting:
  destination: stderr line "ci-head-verdict: <cause>" plus the state=error marker on stdout; layer 7 (self-hosted CLI synchronous consumer, cli-stdout-artifact), no Sentry path exists or is added because the script runs on the operator's or customer's own machine
  fail_loud: exit 3 with state=error and a reason token (api-error, no-check-suites, no-server-time, missing-tool, too-many-events)
failure_modes:
  - mode: the check-suites read fails or returns a malformed body at the moment staleness is being decided
    detection: layer 7 cli-stdout-artifact - exit 3 and state=error reason=api-error on the marker line (readers keep their own reading)
    alert_route: the invoking agent sees the marker in the tool result; the poll retries on the next tick
  - mode: a freshly pushed head has no kept run and no visible check suites yet while T is old
    detection: layer 7 cli-stdout-artifact - exit 3, state=error reason=no-check-suites and a stderr line naming the sha, never a spurious stalled
    alert_route: the invoking agent sees the marker and stderr in the tool result; the next poll resolves it once suites appear
  - mode: a truly stuck ready PR is hidden as pending-full by a wrong anchor
    detection: layer 7 cli-stdout-artifact - mutants M37/M39 and rows V25 pin the boundary; the live read-only check in Phase 4 compares the marker to the PR's actual run list; mutants M37/M39 and rows V24/V25 pin the two anchor paths
    alert_route: the invoking agent; the existing stalled terminal message in monitor-pr-checks.sh / admin-merge-ready.sh
logs:
  where: the tool-result stdout/stderr of the invoking session (no host log; the script keeps no state)
  retention: the session transcript
discoverability_test:
  command: bash plugins/soleur/scripts/ci-head-verdict.sh --help
  expected_output: SOLEUR_CI_HEAD_VERDICT
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Start with the P3 fix: ci-head-verdict.sh staleness." [brief] | Phases 1-4 | mapped |
| 2 | "Then the P4 small PRs, one PR each." [brief] | Follow-up PRs table; Phase 4 tracking issues | descoped - justification: the scoping note says "Scope this pipeline run to the P3 fix only ... the plan should list the P4 items as follow-up PRs, one each, without implementing them in this PR" |
| 3 | "P2 needs an ADR and is out of scope for this run." [brief] | Follow-up PRs table (P2 row only) | mapped |
| 4 | "Locate the exact CTO follow-up list and the P3/P4 definitions" [brief] | Research Reconciliation row 1; Follow-up PRs table | mapped |
| 5 | "PR bodies use `Ref #9757` only (never Closes), merge via the merge queue, no --admin, and one delegation question per new PR." [brief] | Header paragraph; Phase 4 | mapped |
| 6 | "Do not touch the apply-workflow annotations (item 2)" [brief] | Follow-up PRs closing paragraph; Phase 4 (no `.github/workflows/**` edit) | mapped |
| 7 | "the plan should list the P4 items as follow-up PRs, one each, without implementing them in this PR" [brief] | Follow-up PRs table | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `read_head_anchor` + two-step stall decision | "measure staleness from max(ready event, head push/run creation)" | asked |
| Test rows V24-V27 and mutants M37-M42 | - | inferred - justification: `cq-write-failing-tests-before` and the suite's own mutation-row convention require a failing test per behaviour change |
| Prose edits in `monitor-pr-checks.sh`, `admin-merge-ready.sh`, `ready-run-wait.md` | - | inferred - justification: each states "the stall window counts from the ready event", which the fix makes false; sentence-level only, no logic |
| ADR-276 addendum | - | inferred - justification: plan Phase 2.10 makes the ADR update for an extension of an existing ADR a deliverable of the same plan |
| Tracking issues (P2, and one checklist for P4a-P4d), Phase 4 | - | inferred - justification: `wg-when-deferring-a-capability-create-a` requires a tracking issue for a deferral; the CTO ruled the shape (one P2 issue, one P4 checklist issue) |
| Hybrid anchor (run `created_at` when a run exists) | - | inferred - justification: plan-review (DHH) and the CTO ruled it: it removes the extra read and the new failure mode from the pending-full path |

### Split Assessment

- Subsystems touched: 4 - `plugins/soleur/scripts`, `plugins/soleur/test`, `plugins/soleur/skills/ship/references`, `knowledge-base/engineering/architecture/decisions`
- Planned files: 7 | Estimated changed lines: about 220 (script about 45, test about 150, prose about 25)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the four roots all serve one behaviour and its documentation; the nominal root-count threshold is met only because the prose and the ADR sentence are in separate directories, and splitting them would ship a false sentence

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Before the script edit, rows V24, V25 and the shifted V5 boundary rows FAIL against the unmodified script (record the failing output in the PR body's test plan).
- [ ] `bash plugins/soleur/test/ci-head-verdict.test.sh` reports 0 failed, all new mutants killed, and the raised `MIN_ASSERTIONS` / `MIN_MUTANTS` floors are the measured counts.
- [ ] `grep -c 'st=stalled' plugins/soleur/scripts/ci-head-verdict.sh` prints `1` (also asserted inside the suite).
- [ ] `grep -c 'check-suites' plugins/soleur/scripts/ci-head-verdict.sh` is at least 1 and the string appears only inside `read_head_anchor` and the header comment.
- [ ] A fresh-push fixture yields `pending-full` or `no-run`, never `stalled` (run created T+7500 or suite at T+7500, now T+7560); a stuck fixture (default suite at T-3600 and no run, or a run at T+2, now past the 120-minute boundary) still yields `stalled undecided-after-120m`; the boundary is strict (A+7200 pending, A+7201 stalled).
- [ ] Failed, malformed, null-`created_at` and empty suite reads each exit 3 with `state=error` outside the closed set.
- [ ] No suite request appears in the stub log for green, fresh, conflicting, awaiting-approval, never-ready, draft, `n/a` and kept-run fixtures (the stalled-gate rows read at T+7800 so the assertion is not vacuous).
- [ ] `admin-merge-ready.test.sh`, `monitor-pr-checks.test.sh`, `admin-merge-ready-wiring.test.sh`, `drain-prs.test.sh`, `ship-phase-7-poll-fixtures.test.sh`, `ci-draft-light-soak-9728.test.sh` and `c4-count-parity.test.sh` pass; `shellcheck` is clean on the script and test.
- [ ] `git diff origin/main...HEAD --name-only` contains no path under `.github/workflows/` or `apps/` and does not touch `scripts/followthroughs/`.
- [ ] ADR-276 carries the dated addendum; `grep -rn "counts from the ready event" plugins/` prints nothing and `grep -c "see ci-head-verdict.sh for the stall clock" plugins/soleur/scripts/monitor-pr-checks.sh plugins/soleur/scripts/admin-merge-ready.sh` prints 1 for each file.
- [ ] PR body has `Ref #9757` and no `Closes`/`Fixes`/`Resolves`; `gh issue view 9757 --json state` is still OPEN after merge.
- [ ] Merged through the queue (`gh pr merge <N> --squash --auto`), no `--admin`; any held merge asked exactly one delegation question.

### Post-merge (operator-free)

- [ ] Two tracking issues exist (P2; and one checklist for P4a-P4d), both `Ref #9757`, both quoting the Follow-up PRs table.
- [ ] A read-only `ci-head-verdict.sh verdict <open ready PR>` prints one marker whose state is in the closed set or `state=error`.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent ruled the anchor fork, the failure behaviour, and that dirty/awaiting-approval/`wait-ready-run` stay unchanged (all rows in `decision-challenges.md`, class `technical`). No Product/UX surface (mechanical UI-surface override checked: no component, page or layout path in the file lists), no GDPR surface (no store, no personal data, no schema/API/auth path), no new infrastructure (Phase 2.8 skipped: no server, secret, vendor or cron), no new store or connection (encryption posture skipped), and no guard is introduced as a deliverable (the mutation rows test the resolver; Guard Contract skipped).

## Test Scenarios

- Ready at T, head pushed at T+7500, run created T+7500 and in flight, now T+7560: `pending-full run-in-progress` (was `stalled`); at T+14700 still pending, at T+14701 `stalled undecided-after-120m`.
- Same push, a cancelled newest run: `no-run run-cancelled` until A+7200, then `stalled`.
- Same push, no run yet (suite at T+7500), now T+7560: `no-run no-run-after-ready` (was `stalled`); T+14701 stalled.
- Head unchanged since before the ready event (suite at T-3600), now T+7201: `stalled` as today.
- No kept run, suites endpoint 502 / HTML / not-an-array / null `created_at` / a suite with another `head_sha`, while T is old: exit 3, `state=error reason=api-error`.
- Suites list empty while T is old: exit 3, `state=error reason=no-check-suites`.
- Two suites (T+7500 and T+7900), no run: anchor is the earlier one.
- Green `test`, fresh T, `dirty` PR, `action_required` run, a kept in-flight run, never-ready, draft: no suite request in the log.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This one is filled (threshold `none` with a stated reason).
- Existing V5 boundary rows move: with the run as anchor (created T+2) the old 7201 stalled row is now pending; the boundary is exactly 7202/7203. Update the rows, never loosen an assertion to make them pass.
- `min` of an empty jq array is `null` with exit 0, which bash arithmetic reads as 0: the empty-list error must be explicit or M40's defect passes unseen.
- The stub is keyed on the full argv; a route written with a flag the real `gh` lacks (or the wrong query string) turns the new code into dead code that looks green. Copy the exact `check-suites?per_page=100` string from the script into the stub.
- Mutants are applied by exact-string replacement that must match once. Do not restructure the lines the existing M4, M5, M9, M13 edit (`STALL_MINUTES=120`, `st=stalled`, `NOW_EPOCH=$(server_now)`), and keep `st=stalled` a single occurrence.
- The stub's built-in default suite must predate T (`-3600`) so the existing no-run stalled row (V6) keeps its meaning; `setsuites` REPLACES the default, so a new row's suites are never masked by it (an appended suite would leave the earliest at T-3600 and make V25 unsatisfiable).
- `scripts/ci-pr-affected-preactivation.sh` expects the literal `full-verified` in this script, which it never had: pre-existing and unrelated, do not attribute it to this change.
- `ci-draft-light-soak-9728.sh` restates the 120-minute rule for its own census and is deliberately left alone; do not "fix" it here.
- The empty-list-is-an-error choice trades a possible long-lived `state=error` on a suite-less head for never advising an undo on a healthy fresh run; if live evidence shows suite-less heads persisting for hours, the CTO ruling names the flip (fall back to T with a distinct reason).
