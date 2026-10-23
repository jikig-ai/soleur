---
title: "sync-pr-behind.sh: base branch hard-coded to main at the merge-queue rules read; triplicated bound/sanitise helpers"
type: fix
date: 2026-10-23
slug: sync-pr-behind-base-branch-rules-and-bounds-helper
branch: feat-one-shot-10832-sync-pr-behind-base-and-helpers
issue: 10832
lane: cross-domain
brand_survival_threshold: none
---

# sync-pr-behind.sh: base branch hard-coded to main at the merge-queue rules read; triplicated bound/sanitise helpers

Spec lacks valid lane: defaulted to cross-domain (TR2 fail-closed). The work is single-domain engineering tooling; the default only widens review, never narrows it.

## Overview

Two residuals in `plugins/soleur/scripts/sync-pr-behind.sh`, both left open by PR #10655 (ADR-270, accepted residual 6) under epic #9454 and tracked as #10832:

1. **Base hard-coded to `main`.** `queue_wait_eval` reads `repos/$o/$r/rules/branches/main?per_page=100`, so a PR whose base is another branch is judged against `main`'s rules. Fix: carry the PR's own `baseRefName` into `queue_wait_eval` from each of its three callers and read that branch's rules. Because that moves one class of PR from a safe refusal to the script's existing `origin/main` merge, the change also adds one interim refusal for a non-`main` base (plan-review finding, CTO F7; see Proposed Solution).
2. **Triplicated bound/sanitise helpers.** The `PR_QUEUE_TIMEOUT` / `PR_QUEUE_ATTEMPTS` / `PR_QUEUE_RETRY_SLEEP` clamping block and the `tr -c '[:alnum:] ._:/=-' '?'` sanitiser are repeated across `queue_state_read`, `queue_wait_eval` and `qw_snapshot` (the nap clamp has a fourth copy in `queue_read_settled`). Fix: one bounds helper and one sanitiser filter.

Behaviour for PRs based on `main` stays byte-identical, including the request string `repos/o/r/rules/branches/main?per_page=100`. Tests are written first (RED), including non-main-base cases, then the refactor (behaviour-preserving, GREEN), then the base change (GREEN).

This is Ref #9454 and Ref #10832 only. No closing keyword anywhere; #10832 is closed by hand after merge verification and #9454 stays open.

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality (verified) | Plan response |
|---|---|---|
| "fixture suite plugins/soleur/scripts/sync-pr-behind.test.sh" | That file (252 lines, 10 rows) covers only the regenerable-conflict arm of the standalone loop. The merge-queue and queue-wait rows live in `plugins/soleur/test/sync-pr-behind.test.sh` (1710 lines, 172 rows, baseline green in ~64 s). | Both suites are edited; the queue-wait suite carries the new rows. The scripts-side suite needs a stub-only change (see next row). |
| "make qw_snapshot also read baseRefName ... every mock in the test suite change with it" | `qw_snapshot` serves only the flagless `--step` guard and `--queue-wait`. The standalone loop reaches `queue_wait_eval` through `queue_wait_gate` with only `<STATE> <MERGESTATE>` and the armed bit from the queue GraphQL read, and has no snapshot. | The loop needs its own base source: widen its one pre-loop `headRefName` read (CTO F1, no extra `gh` call). |
| The snapshot is mocked in "the test suite" | Three suites mock the snapshot: `plugins/soleur/test/sync-pr-behind.test.sh`, `.claude/hooks/pre-merge-rebase.test.sh` (~l.905-930) and `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (~l.1712-1718). A fourth stub, `plugins/soleur/scripts/sync-pr-behind.test.sh`, matches the exact argument `headRefName` and would STUB-MISS on the widened loop read. | All four are edited, request-shape-compatible first (they serve the base only when the SUT asks for it), so they stay green against the old SUT during RED. |
| "three copies of the clamping block" | The three copies differ: `queue_state_read` and `queue_wait_eval` clamp timeout, attempts and nap; `qw_snapshot` clamps only the timeout; `queue_read_settled` holds a fourth nap clamp. | One helper sets all three values; `qw_snapshot` ignores the two it does not need; `queue_read_settled` calls it too (CTO F2). |
| `main` is hard-coded only in the rules read | `sync_step` also fetches and merges `origin/main` (l.501-509); the hook's `--queue-wait` consumer then does its own `origin/main` merge; the Phase 7 fences and `plugins/soleur/lib/pr-merge-poll.ts` keep inline `rules/branches/main` reads. | Making the rules read base-aware changes what `proceed` means for a non-`main` base (it would now lead to a wrong `origin/main` merge where the old read refused). Interim refusal added in this PR (CTO F7); the shared merge path, the fences and the hook's own merge stay out of scope with a tracking issue that must exist before merge. |
| Mutation rows pin the script text | `plugins/soleur/test/sync-pr-behind.test.sh` mutates the SUT by literal anchor (`qw_mutant`, `consume_mutant`, each requiring the whole anchor to occur exactly once); two anchors sit on lines this change rewrites (the `tr -c` sanitiser line and the snapshot answer-regex line) and the file ends in a `PASS -eq 172` pin. | Anchors and the pin move in the same commit as the code that moves them; new mutants anchor on unique fragments. |

## Research Insights

### Premise validation (Phase 0.6)

Checked: #10832 is OPEN with no closing PR; #9454 is OPEN; the cited residual is ADR-270 line 724 ("(6) The base is `main`, as everywhere in the script") and line 755 ("hard-coded base, triplicated helpers ... tracked on #10832"). `git grep` on the worktree confirms one non-comment `rules/branches/main` literal in the script, three `tr -c` sanitiser lines, three timeout clamps, two attempts clamps and three nap clamps. ADR corpus check for the mechanism: ADR-270 only; no alternatives-table entry rejects reading the base's rules. Stale premise found: the fixture-suite path (see Reconciliation). Read-only measurement (2026-10-23): `gh pr list --state all --limit 300 --json baseRefName` shows 299 PRs on `main` and 1 on a stacked branch, so non-`main` bases are rare; the change is correct but near-dormant, which is why the test volume is kept proportionate (see Phase 0).

### Property list and cut list (Phase 0.6b)

Properties:

1. An armed BEHIND/UNKNOWN PR is judged against the merge-queue rule of its own base branch, from every caller (flagless `--step`, `--queue-wait`, standalone loop).
2. A base that is empty or outside a conservative name set fails closed (`kind=gh`, rc 4) and never reaches the rules URL; paths that do not reach the rules read are unaffected by an unusual (non-empty) base.
3. For `main`-based PRs nothing observable changes: same request string, same refusal text, same exit codes.
4. Each env clamp and the stderr sanitiser exist once, and every reader goes through them.
5. A future copy-paste of either block, or a bypassing call site, turns a test red.
6. An armed BEHIND PR with a validated non-`main` base and no queue rule is never handed to a sync that merges `origin/main` by the guarded callers (flagless `--step`, standalone loop, `--queue-wait`).

Cut list (mechanism, property, what already covers it):

- A separate lazy `gh pr view --json baseRefName` read inside `queue_wait_eval` - property 1 for the loop - covered by widening the loop's existing head read at no extra call (CTO F1, option A).
- Appending the base to the per-attempt `state_line` - property 1 - rejected: a base such as `fix-DIRTY` corrupts the `*DIRTY*` glob tests.
- A general percent-encoder for base names - property 2 - cut: a conservative allowlist plus `/` to `%2F` covers every base this repo uses and fails closed otherwise (CTO F3).
- Folding the `timeout`/`gtimeout` wrapper selection and the `PR_QUEUE_REPO` parse into the helper - property 4 - cut (CTO F2).
- Making `sync_step` merge `origin/<base>` - property 6 - cut: it touches the shared merge/push path the fences use (CTO F7 option (c)); the interim refusal covers the guarded callers.
- Plan-review cuts applied: the six-row sentinel set collapses to one looped row; harness meta-mutants and duplicate mutants are dropped (kept: one harness row and one must-pass row per guard, which the Guard Contract rules require); characterization tables shrink; the legacy single-token loop row folds into the unsupported-base table; mock stubs read the base from a runtime file so one fixture serves a table; `QB_*` values are used directly instead of being copied into locals.

### Rulings (CTO, 2026-10-23)

Recorded in `knowledge-base/project/specs/feat-one-shot-10832-sync-pr-behind-base-and-helpers/decision-challenges.md` (rows F1-F6 and the F5 amendment, F7). The first batch also served as the plan's scoped strong-model consult (Step 4.5: same decision gate, curated payload, no separate advisor spawn); the plan-review panel (DHH, Kieran, code-simplicity, CTO devex lens) then reviewed the finished plan, and its one correctness convergence (the `sync_step` regression) went back to the CTO as a second ruling.

### Files and call sites measured

- `plugins/soleur/scripts/sync-pr-behind.sh` (647 lines): clamps at l.195-199, l.270-271, l.290-297, l.338; sanitiser at l.240, l.317, l.352; rules read at l.305; snapshot at l.331-356; loop head read at l.567; `step_guard` at l.376-385; `queue_wait_gate` at l.472-481; `--queue-wait` mode at l.361-370; refusal and unreadable texts at l.323-329.
- Callers of the three reads: `.claude/hooks/pre-merge-rebase.sh` l.757-790 (`--queue-wait` with `PR_QUEUE_ATTEMPTS=1 PR_QUEUE_TIMEOUT=5`; on `proceed` it runs its own `origin/main` merge), `monitor-pr-checks.sh` and the fences (`--queue-state`), the fences (`--step --fence`, guard skipped). No `apps/` file references the script (`git grep -n sync-pr-behind -- apps/` is empty), so there is no hosted caller.
- Verified read-only on 2026-10-23: `gh pr view 10939 --json baseRefName --jq .baseRefName` prints `main`; `gh api "repos/jikig-ai/soleur/rules/branches/main?per_page=100" --jq length` prints `5`; the same call for the nonexistent branches `feat%2Fx` and `feat/x` prints `0` (a branch without rules answers an empty array, not an error, and both slash spellings are accepted - so the `%2F` encoding is adopted on the `plugins/soleur/scripts/admin-merge-ready.sh` l.414 precedent, `jq @uri`, whose test l.310 expects `rules/branches/feat%2Fx`, not because the live API distinguishes them); `baseRefName` is a valid `gh pr view --json` field (`plugins/soleur/test/pr-overlap-preflight.test.sh` l.118 field list).
- Helper behaviour run under bash 5.3 before prescribing it (`qw_base_path` over `main develop release/1.x feat/x/y - -x a. .h x.lock a..b a//b a?b feat%2Fx '' é rel+1 a.lock/b v1.lockx` under `LC_ALL=en_US.UTF-8`): accepts `main`, `develop`, `release/1.x` (to `release%2F1.x`), `feat/x/y` (to `feat%2Fx%2Fy`), `a.`, `v1.lockx`; rejects every other entry including `-`, `é` and `rel+1`. `local LC_ALL=C` inside the helper is what rejects `é`; without it `[A-Za-z]` accepts it in `en_US.UTF-8`. bash 3.2 itself was not available to run.
- Baselines before any edit: `bash plugins/soleur/test/sync-pr-behind.test.sh` ends `=== 172 passed, 0 failed ===` (64 s); `bash plugins/soleur/scripts/sync-pr-behind.test.sh` ends `all 10 assertions passed`; `shellcheck -x plugins/soleur/scripts/sync-pr-behind.sh` is clean; floors `EXPECTED_CASES=77` (`.claude/hooks/pre-merge-rebase.test.sh`) and `MIN_VERDICTS=1123` (`plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`).
- Documentation that names the main-only base (update): script header l.53, `--help` l.99, l.118-119, l.135, `queue_wait_eval` comment l.281-287, `.claude/hooks/pre-merge-rebase.sh` l.757-758 (comment), `plugins/soleur/skills/ship/references/queue-mode.md` l.7, stale comments quoting the three-field snapshot (`.claude/hooks/pre-merge-rebase.test.sh` l.912 and l.2117, `plugins/soleur/test/sync-pr-behind.test.sh` l.1301), ADR-270 (new addendum; the 2026-10-09, 2026-10-20 and 2026-10-22 addenda are dated records and stay). Leave but name in the addendum (they keep saying "main has a merge queue" by design): fence prose in `ship/SKILL.md` and `merge-pr/SKILL.md`, `monitor-pr-checks.sh` l.405, `plugins/soleur/lib/harness.ts`, `antigravity/INSTRUCTIONS.md`, `infra/github/README.md`, `AGENTS.rules.md` (pinned by `workflow-fidelity.test.ts` and the rule-body hashes), `pr-merge-poll.ts`.
- CI selection (read from `scripts/test-all.sh` by the research pass): the stem rule selects both sync-pr-behind suites from a script edit; `.claude/hooks/pre-merge-rebase.test.sh` and `plugins/soleur/test/monitor-pr-checks.test.sh` are NOT selected by a script-only diff, but this plan edits the hook suite and the hook file, which selects them. `scripts/lib/test-affected-paths.sh` and the shard manifests stay untouched per the brief.

### Learnings applied

- `knowledge-base/project/learnings/2026-10-19-a-per-area-drawdown-cannot-satisfy-a-live-census-gate-and-reindenting-breaks-text-anchored-mutants.md` - grep the suites for the changed text before editing; run the unmutated control first.
- `knowledge-base/project/learnings/2026-09-25-gh-stub-must-mirror-real-cli-flags.md` - stubs serve fields by request shape and refuse the rest; no invented flags.
- `knowledge-base/project/learnings/2026-10-07-a-sync-that-defers-to-a-queue-needs-a-bounded-wait-and-a-reset-that-a-deleted-read-took-with-it.md` - list what a removed or moved read also did; every unreadable answer keeps the old safe arm.
- `knowledge-base/project/learnings/2026-10-22-a-verdict-function-inside-command-substitution-cannot-exit-and-an-echoing-stub-inflated-my-counts.md` - the helpers must not `exit`; `queue_wait_eval` keeps returning 0 and reporting through `QW_VERDICT`.

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open` (213 KB) and matched each planned path with `jq --arg`: no issue body names `plugins/soleur/scripts/sync-pr-behind.sh`, `plugins/soleur/test/sync-pr-behind.test.sh`, `plugins/soleur/scripts/sync-pr-behind.test.sh`, `.claude/hooks/pre-merge-rebase.test.sh` or `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`. One substring hit on `sync-pr-behind`: #8659 ("33 test suites replace test-helpers' composed EXIT trap and leak the incident sandbox on direct runs"). Disposition: **Acknowledge** - a different concern (EXIT-trap composition in test suites); the queue-wait suite already installs its owning trap before sourcing `test-helpers.sh`, and the new rows reuse that arrangement. The issue stays open.

## Problem Statement / Motivation

A non-`main`-based PR armed on a queue repo is judged against `main`'s rules, so the wait-versus-sync decision can be wrong in both directions: a PR on a branch with no queue rule is refused a sync it needs, or a PR on a queue-ruled branch is synced when the queue should make it current. The duplicated clamp and sanitiser blocks mean any future change to a bound or to the sanitiser must be made three or four times, and the suite pins only one of the sanitiser copies. Re-evaluation criteria from #10832: take both together the next time the script is edited, or when a non-main-base PR is armed on a queue repo.

## Proposed Solution

### Prescribed source shape (tests in Phase 0 anchor on these lines, so they are specified here; normative only where a literal anchor depends on it)

Helpers, defined once before `queue_state_read`:

```bash
qb_bounds() {
  QB_TIMEOUT="${PR_QUEUE_TIMEOUT:-10}"; QB_ATTEMPTS="${PR_QUEUE_ATTEMPTS:-2}"; QB_NAP="${PR_QUEUE_RETRY_SLEEP:-2}"
  [[ "$QB_TIMEOUT" =~ ^[1-9][0-9]{0,3}$ ]] || QB_TIMEOUT=10
  [[ "$QB_ATTEMPTS" =~ ^[1-9]$ ]] || QB_ATTEMPTS=2
  [[ "$QB_NAP" =~ ^[0-9]{1,3}$ ]] || QB_NAP=2
}
qb_clean() { tr -c '[:alnum:] ._:/=-' '?'; }
qw_base_path() {  # <base> -> prints the rules-URL path segment; returns 1 for an empty or unsupported name
  local LC_ALL=C b="${1:-}"
  [[ "$b" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$ ]] || return 1
  [[ "$b" != *..* && "$b" != *.lock && "$b" != *.lock/* ]] || return 1
  printf '%s' "${b//\//%2F}"
}
qw_base_foreign() { [[ -n "$QW_BASE" && "$QW_BASE" != main ]]; }
```

Call sites: `queue_state_read` and `queue_wait_eval` call `qb_bounds` and use `QB_TIMEOUT` / `QB_ATTEMPTS` / `QB_NAP` directly; `qw_snapshot` uses `QB_TIMEOUT`; `queue_read_settled` uses `QB_NAP`. The three sanitised strings become `... | qb_clean)"` with their distinguishing prefixes unchanged (`QS_DETAIL=`, `detail=`, `pvd=`). The helpers set globals (no array return, bash 3.2), never `exit`, and always return 0 except `qw_base_path` / `qw_base_foreign`, which are used only as `if` / `||` conditions.

Base plumbing:

- `qw_snapshot` asks `--json state,mergeStateStatus,autoMergeRequest,baseRefName` (base appended last so mocks that glob `mergeStateStatus,autoMergeRequest` still match) with `--jq` producing `<STATE> <MERGESTATE> <armed|disarmed> <base>` (base via `.baseRefName // ""`). The strict regex becomes `^(OPEN|CLOSED|MERGED)\ [A-Z_]+\ (armed|disarmed)\ [^[:space:]]+$`; the base token is deliberately loose (CTO F4) so an unusual-but-legal base never fails a path that does not reach the rules read. An empty base fails the regex on every path (`kind=gh`, rc 4): GitHub never returns an empty `baseRefName`, so this is a fail-closed arm, not a behaviour a real PR meets. The answer is split with `read -r`; outputs are `QW_STATE`, `QW_ARMED` and `QW_BASEREF`.
- `queue_wait_eval <state_line> <armed|disarmed|-> <base>`: `QW_BASE` is reset to empty at the top and set only on the success path; after the existing OPEN, BEHIND/UNKNOWN-not-DIRTY and `armed` checks (order preserved: an unarmed or non-BEHIND PR never touches the base), validate the base with `qw_base_path`; failure sets `QW_VERDICT=unreadable` with a detail naming the base after `qb_clean` and a 60-character truncation, returning 0. On success set `QW_BASE`, then build the read as `gh api "repos/$1/$2/rules/branches/$4?per_page=100" --jq "$3"` with `$4` the encoded base. For base `main` the string is byte-identical to today's.
- Standalone loop: the pre-loop read becomes `--json headRefName,baseRefName --jq '"\(.headRefName) \(.baseRefName // "")"'` and the answer is split with `read -r head_ref LOOP_BASE <<<"$head_out"` (branch names contain no whitespace). A single-token answer leaves `LOOP_BASE` empty and `head_ref` as today; an empty base is fatal only when `queue_wait_eval` reaches the rules read (armed BEHIND/UNKNOWN), where it is `unreadable` (`kind=gh`, rc 4). The base is resolved once per run; a mid-loop retarget is judged against the old base, bounded by `MAX_ATTEMPTS`, and a code comment says so. A gh stderr warning on an exit-0 answer yields a first line that is not the branch, so the run ends in `wrong_branch` exactly as it does today.
- **Interim non-`main` refusal (CTO F7).** After `queue_wait_eval` returns `proceed` with `qw_base_foreign` true (so the PR is OPEN, BEHIND/UNKNOWN, armed, its base validated and its base's rules read with zero merge_queue rules, and the base is not `main`): flagless `--step` (`step_guard`) and the standalone loop (`queue_wait_gate`) print `kind=gh` rc 4 and exit 4 with nothing fetched, merged or pushed, with text saying the PR's base is `<base>`, not `main`, that `sync_step` only merges `origin/main`, and to sync by hand or retarget; the `--queue-wait` mode prints `queue_wait` and exits 0 (read-only, the stricter direction, matches the pre-change answer for this class; `kind=gh` would make the hook fall through to its own sync). Not in `--fence`, `sync_step` or `queue_wait_eval`. No new kind, no new exit code, no `--help` row.
- `qw_refusal` and `qw_unreadable` interpolate `QW_BASE` where they say "main" (`${QW_BASE:-its base branch}` in `qw_unreadable`, where the base may be unknown). Text is byte-identical for `main`.
- Documentation: header l.53, `--help` l.99 / l.118-119 / l.135 and the `queue_wait_eval` comment say "the PR's own base branch" and name `baseRefName` in the snapshot field list; the substrings the suite and the fences pin in `--help` (`--fence`, `--queue-wait`, `^  14 .*kind=queue_wait`, `^  11 .*kind=noop`, `^  4 .*kind=gh`, `should a sync be skipped`, `is the PR in the queue`, `nobody else`, `merge queue`) stay.

## Non-Goals

- `sync_step` still fetches and merges `origin/main`, the hook still does its own `origin/main` merge after `proceed`, and the Phase 7 fences (`ship/SKILL.md`, `merge-pr/SKILL.md`) and `plugins/soleur/lib/pr-merge-poll.ts` keep their inline `rules/branches/main` reads. Honest framing (CTO F7): these were already wrong for the unarmed, no-queue-rule and fence-expiry classes; this PR refuses the armed class at the three guarded callers rather than moving it into that set, but does not fix the shared merge path (option (c): it needs its own design and tests against the fence rows). One tracking issue for all of it must exist and be linked in the ADR addendum before merge (the work phase files it with `gh issue create`, labels verified with `gh label list --limit 200` first, milestone from `knowledge-base/product/roadmap.md`), referencing #9454 and #10832 as Ref only. Re-evaluation criterion: the first non-main-base PR armed on a queue repo, or the next edit of `sync_step`.
- The hook's `queue_wait` context text ("the queue makes it current") is inaccurate for a non-`main` PR whose base has no queue rule (it now also gets `queue_wait` through the interim refusal). Rare (1 of the last 300 PRs is non-main-based); recorded in the same tracking issue.
- `.claude/hooks/pre-merge-rebase.test.sh`'s selection gap: a script-only diff does not select the hook suite or `monitor-pr-checks.test.sh`; fixing the mapping means editing `scripts/lib/test-affected-paths.sh`, which the brief forbids. Recorded only as a Sharp Edge.
- The hash-pinned AGENTS rule line, `.claude/rule-weakening-acks.txt`, `scripts/lib/test-affected-paths.sh`, the shard manifests (`scripts/suite-*.tsv*`), #9482, #10245, #5840: untouched.

## Technical Considerations

- **bash 3.2 portability** (the script runs on customer macOS hosts): no `mapfile`, no `${x,,}`, no associative arrays; `[[ =~ ]]` with the regex written inline is 3.2-safe (the script already relies on it); `local LC_ALL=C` and `read -r` are 3.2-safe. The new code adds no external binary beyond the `tr` already used.
- **`set -euo pipefail`**: `queue_wait_eval` keeps returning 0 and reports through `QW_VERDICT`; `qb_clean` runs in a pipeline stage, so it must not rely on `exit`. Globals `QW_BASE`, `QW_BASEREF`, `LOOP_BASE` are initialised at the top (`set -u`).
- **Fail-closed**: an unreadable, empty or unsupported base is `kind=gh` rc 4, never `proceed`; the single place that already fails closed on an unknown rules answer (ADR-270 addendum 2026-10-09) keeps that meaning.
- **Sanitising**: the base value is untrusted text (an attacker-editable branch name); it is validated against the allowlist before any use in a URL and, when echoed in a detail, passed through `qb_clean` and truncated to 60 characters.
- **No extra `gh` call on any path**: the flagless `--step` still makes one `pr view` and one rules read; `--queue-wait` the same; the loop adds none (CTO F1).
- NFR impact: none beyond reliability of an operator tool; no NFR register change.

## Implementation Phases

Order is dependency-first: tests define the contract before the code moves. Commits are RED, GREEN-refactor, GREEN-base so the history shows the tests-first order (a review aid only: the repo squash-merges).

### Phase 0 - RED tests and request-shape-compatible mock widening

Edit `plugins/soleur/test/sync-pr-behind.test.sh`. Stub widening is green (every pre-existing row stays green against the old SUT because stubs answer the old request shape exactly as today and serve the new fields only when the SUT asks for them); the new rows are RED.

- 0.1 Stubs read the base from a runtime file so one fixture serves a whole table. `install_gh` and `install_gh_wait` write `$bin/pr-base` (default `main`; the value `__none__` makes the head read answer the head alone). The `*headRefName*` arm answers `"<head> <base>"` when argv names `baseRefName`, else `"<head>"`. `install_gh_wait`'s `ok:<STATE MERGESTATE>:<armed|disarmed>` mode is unchanged (the `IFS=: read -r _ st arm` split must not gain a fourth field); the raw JSON body gets `baseRefName` from `pr-base` and the existing "delete the fields `--json` did not name" loop covers it. `install_rules`: the stub parses the requested branch out of the path (between `rules/branches/` and `?`), decodes `%2F`, and applies its mode only to the branch named in a `rules-branch` file (default `main`); any other branch answers `[]` (a branch without rules, as measured). Every call still appends its argv to `rules-calls`.
- 0.2 Recording `timeout` and `sleep` shims (the `install_git_shim` pattern: resolve the real binary to an absolute path first, log the numeric argument to `timeout-calls` / `sleep-calls`) live in a separate `bin` used only by the characterization fixtures. They must never sit in a fixture that uses a hang mode: the hang stubs `exec sleep 8` / `exec sleep 5` through PATH and an instant `sleep` would make the existing hang rows and the `hang` mutation scenario go red or pass vacuously. Nap rows set `PR_QUEUE_RETRY_SLEEP` explicitly per case (the suite exports `0` globally) and `unset` it for the default case.
- 0.3 Characterization rows (green before and after; they pin today's behaviour through the refactor), 7 rows: three tables, each looped inside one row with bad cases reported by name, through one site each - timeout (`--queue-state`: unset, `7`, `0`, `abc` expect logged `10 / 7 / 10 / 10`), attempts (a failing rules read: unset, `1`, `3`, `0`, `abc` expect call counts `2 / 1 / 3 / 2 / 2`), nap (`queue_wait_eval` on a failing rules read: unset, `5`, `0`, `abc` expect logged sleeps `2 / 5 / 0 / 2`) - plus one non-default-value row per remaining site proving it reaches the helper: timeout through `--queue-wait` (pr view) and through the rules read, attempts through `queue_state_read` (`gqlfail`), nap through `queue_read_settled` (marker-dequeue run).
- 0.4 One sentinel row (RED now for the clamps and sanitiser, the `rules/branches/main == 0` clause turns green only in Phase 2), counted over the SUT with whole-line comments (`^[[:space:]]*#`) and the `USAGE` heredoc stripped, using exact `== N` comparisons (never `<=` or a negated `grep -q`): the `tr -c '[:alnum:] ._:/=-'` spelling `== 1`; each of `${PR_QUEUE_TIMEOUT:-`, `${PR_QUEUE_ATTEMPTS:-`, `${PR_QUEUE_RETRY_SLEEP:-` `== 1` counted with `grep -o ... | wc -l` (not `grep -c`, which counts lines and would miss a second read on `qb_bounds`' single line); `rules/branches/main` `== 0`. Baselines today: 3, then timeout 3 / attempts 2 / nap 3, then 1. One anti-vacuity check on the shared counting function against an empty file (it must report failure).
- 0.5 Base rows (RED now; about 13), via `fw_run` (flagless `--step`, `wait`) and `qw_run` (loop), asserting the exact request recorded in `rules-calls` and, on refusal arms, that nothing was fetched, merged or pushed:
  - N1 base `develop`, queue rule on `develop` only: flagless `--step` exits 14 `kind=queue_wait` with `repos/o/r/rules/branches/develop?per_page=100`, one `pr view`, one rules read; `--queue-wait` prints `queue_wait`.
  - N2 base `develop`, queue rule on `main` only (the rules the old script would have read): flagless `--step` exits 4 `kind=gh` with the non-`main` refusal text, nothing fetched, merged or pushed; `--queue-wait` prints `queue_wait`; the standalone loop exits 4 with the same text; the path read is `develop`, not `main`. (Under the old script the same fixture exits 14 / prints `queue_wait` / `kind=queue_wait`, so the rc and text discriminate.)
  - N3 base `release/1.x` with the queue on that branch: refused (14), path `release%2F1.x?per_page=100`; base `feat/x/y` likewise (`feat%2Fx%2Fy`).
  - N4 unsupported-base table, one looping row: `feat%2Fx`, `a?b`, `a..b`, `x.lock`, an empty base (the snapshot answer has no fourth token after `armed`) and the loop with a head read that answers the head alone (`__none__`): each `kind=gh rc=4`, zero rules calls, nothing moved, no ESC byte, the raw base not echoed beyond the sanitised 60-character detail.
  - N5 non-`main` bases outside the refusal still behave as today: base `develop`, PR disarmed (and base `rel+1` disarmed): flagless `--step` syncs and pushes (rc 0), `--queue-wait` prints `proceed`, zero rules calls.
  - N6 standalone loop with head read `feat develop`, armed BEHIND, queue on `develop`: `kind=queue_wait rc=0`, path `develop`; the same loop with `feat main` is unchanged (the existing Q1 rows).
  - N7 `qw_refusal` / `qw_unreadable` golden texts: for base `main` each equals the pre-change text byte for byte (golden literals captured from the pre-change SUT in this phase); for `develop` the refusal names `develop` where the text says `main`.
  - N8 snapshot answers without a base token or with extra tokens: `kind=gh rc=4` (strict regex), covering the old three-token mock shape.
- 0.6 Mutation and harness rows (RED now: "anchor absent" until Phases 1-2 land the prescribed lines): see the Guard Contract matrices. The two anchors this change rewrites (the `tr -c` line and the snapshot regex line) are re-pointed at the new lines; every new anchor is a fragment that occurs exactly once (for example the full `... --repo "$3" --json ...baseRefName --jq "$2"; else gh pr view "$1" ...` fragment, not the repeated `--json` list; the name-regex line, not the repeated `|| return 1`).
- 0.7 Mock widening in the three other suites, request-shape-compatible: `.claude/hooks/pre-merge-rebase.test.sh` (`mss-<N>` gains an optional fourth token, default `main`; the body carries `baseRefName`; the "delete fields not in `--json`" loop lists it; the two comments quoting the three-field shape are updated); `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (the snapshot `data` JSON gains `"baseRefName":"main"`); `plugins/soleur/scripts/sync-pr-behind.test.sh` (the `headRefName` arm matches `headRefName*` and answers `feature main` when `baseRefName` is named, `feature` otherwise). The stale snapshot comment at `plugins/soleur/test/sync-pr-behind.test.sh` l.1301 is updated.
- 0.8 Run each edited suite against the unchanged SUT: pre-existing rows stay green (control first - a red unmutated control voids every row below it) and the new base, sentinel and mutation rows are the only red ones. Record the failing row names (the RED evidence). Commit as test-only.

### Phase 1 - GREEN: one bounds helper, one sanitiser (behaviour-preserving)

- 1.1 Add `qb_bounds` and `qb_clean` exactly as specified; replace the four clamp copies and the three `tr -c` copies. No other change in this phase.
- 1.2 Characterization rows stay green throughout; the sentinel row's clamp, env-read and sanitiser clauses turn green (its `rules/branches/main == 0` clause and the re-pointed snapshot-regex anchor stay red until Phase 2); add and green the helper mutants.
- 1.3 `shellcheck -x` stays clean; `bash plugins/soleur/test/sync-pr-behind.test.sh` is green except the base rows, the `rules/branches/main == 0` clause and the snapshot-regex mutant.

### Phase 2 - GREEN: base plumbing and the interim refusal

- 2.1 Snapshot, `queue_wait_eval`, `qw_base_path`, `qw_base_foreign`, loop head read, the three-caller refusal, `QW_BASE` in the two texts, `--help` / header / comment edits, as specified. Update the pass-count pin deliberately to the measured number (baseline 172 plus the listed new rows; list the new row ids in the commit message and in `tasks.md`).
- 2.2 All suites green: `bash plugins/soleur/test/sync-pr-behind.test.sh`, `bash plugins/soleur/scripts/sync-pr-behind.test.sh`, `bash .claude/hooks/pre-merge-rebase.test.sh` (`EXPECTED_CASES` unchanged: no case added there), `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (`MIN_VERDICTS` unchanged), plus `bash plugins/soleur/test/monitor-pr-checks.test.sh` as a control.

### Phase 3 - Documentation, ADR addendum, tracking issue

- 3.1 `.claude/hooks/pre-merge-rebase.sh` l.757-758 comment and `plugins/soleur/skills/ship/references/queue-mode.md` l.7: say the PR's own base branch. `queue-mode.md` l.5 (the fence reads `main`) is left as is.
- 3.2 ADR-270: append a short addendum (via `soleur:architecture`, about five lines) closing residual 6 and the helper residual: the rules read uses `baseRefName`, snapshot field list now four, the interim non-`main` refusal at the three guarded callers, `sync_step`, the fences and the hook's own merge still read `main` (naming the places that keep saying "main has a merge queue"), and the tracking issue number. No C4 change (no actor, system, container, data store or access relationship changes; the script already talks only to GitHub through `gh`, as ADR-270's 2026-10-22 addendum states for this residual).
- 3.3 File the tracking issue (see Non-Goals) before the PR is marked ready, and link it in the ADR addendum.

## Files to Edit

- `plugins/soleur/scripts/sync-pr-behind.sh` - helpers, call sites, snapshot, `queue_wait_eval`, loop head read, interim refusal, texts, header/`--help`/comments.
- `plugins/soleur/test/sync-pr-behind.test.sh` - stubs, characterization, sentinel, base, mutation and harness rows, anchors, pin, stale comment.
- `plugins/soleur/scripts/sync-pr-behind.test.sh` - `headRefName` stub arm only.
- `.claude/hooks/pre-merge-rebase.test.sh` - snapshot stub and two comments only.
- `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` - snapshot data JSON only.
- `.claude/hooks/pre-merge-rebase.sh` - comment only.
- `plugins/soleur/skills/ship/references/queue-mode.md` - one sentence.
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` - appended addendum.

Every path above is a literal checked with `git ls-files`; no glob is prescribed.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10832-sync-pr-behind-base-and-helpers/tasks.md` (and this plan, and the already written `decision-challenges.md`).

## User-Brand Impact

- **If this lands broken, the user experiences:** an armed BEHIND pull request that is refused a sync it needs (stuck BEHIND until re-armed) or is pushed to when the queue should make it current (every required check restarts for nothing), or - the case the interim refusal exists for - a non-`main`-based PR that gets `origin/main` merged into it; a stalled or slower merge of the operator's own PR, with a tagged `kind=queue_wait` or `kind=gh rc=4` line naming the next action. No end-user data or money path is involved.
- **If this leaks, the user's workflow is exposed via:** no credential or data path; the only new untrusted input is a branch name, which is validated against an allowlist before it reaches a URL and sanitised before it is echoed.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** operator-facing merge tooling with fail-closed arms and no user data; none of the diff's paths matches the preflight sensitive-path regex, so no scope-out bullet is needed.

## Observability

```yaml
liveness_signal:
  what: "tagged stdout lines [pr-behind-sync] kind=queue_wait, kind=gh rc=4 and the --queue-wait verdict line; local developer-machine CLI tooling, no daemon (layer 7, cli-stdout-artifact)"
  cadence: "per invocation (per Phase 7 poll tick that reaches the guard; per gh pr merge for the pre-merge hook)"
  alert_target: "the invoking agent session (a Monitor streams stdout); the line names the next action"
  configured_in: "plugins/soleur/scripts/sync-pr-behind.sh (tag, qw_refusal, qw_unreadable, the non-main refusal text)"

error_reporting:
  destination: "stdout tagged lines only; no Soleur-side sink by design (self-hosted CLI output must not be routed to Soleur infrastructure)"
  fail_loud: "an empty, unsupported or unreadable base, a non-main base on an armed BEHIND PR, and every unreadable rules or pr view answer print kind=gh rc=4 and exit 4 (--queue-wait prints queue_wait for the non-main case); the pre-merge hook turns an unreadable answer into a named queue_wait_unreadable note, never a silent proceed"

failure_modes:
  - mode: "base branch read wrongly (field missing, garbled answer, unsupported name)"
    detection: "kind=gh rc=4 line from the strict answer regex or from qw_base_path, layer cli-stdout-artifact; covered by rows N4 and N8 of the committed fixture suite"
    alert_route: "agent session output; the hook's queue_wait_unreadable note names the cause"
  - mode: "rules read judged against the wrong branch (regression to a literal main)"
    detection: "rows N1-N3 and N6 fail pre-merge in the committed suite, which asserts the exact rules path recorded per request; layer cli-stdout-artifact (committed artifact: plugins/soleur/test/sync-pr-behind.test.sh)"
    alert_route: "CI (test shard) and the work-phase exit gate"
  - mode: "a non-main base reaches the origin/main merge (refusal removed from a caller)"
    detection: "row N2 asserts exit 4 / queue_wait / exit 4 per caller and per-caller mutation rows; layer cli-stdout-artifact (committed artifact: the same suite)"
    alert_route: "CI (test shard)"
  - mode: "clamp or sanitiser re-forked, or a call site bypasses the helper"
    detection: "the sentinel row counts each block and each env read, and per-call-site mutation rows; layer cli-stdout-artifact (committed artifact: the same suite)"
    alert_route: "CI (test shard)"

logs:
  where: "stdout of the invoking Monitor or Bash call; hook output in the session transcript"
  retention: "session transcript lifetime; the committed fixture suite is the durable record of every line's shape"

discoverability_test:
  command: bash plugins/soleur/scripts/sync-pr-behind.sh --help
  expected_output: "baseRefName"
```

Hosted path: no `apps/` file invokes the script (`git grep -n sync-pr-behind -- apps/` is empty), so layers 1-6 have nothing to cover; the only hosted occurrence is the vendored plugin tree being present in the image. The discoverability command reads the committed script text and prints the new field name only after Phase 2 (it prints nothing for `baseRefName` today).

## Guard Contract

### Guard 1 - Base-branch binding of the rules read, and no merge of `origin/main` into a non-`main` base

**Property.** For an armed BEHIND or UNKNOWN PR, the merge_queue rule is read from the rules endpoint of that PR's own `baseRefName` from every guarded caller, an empty, unreadable or unsupported base fails closed (`kind=gh`, rc 4) before any rules request is made, and a validated non-`main` base with no queue rule is never given a sync by the flagless `--step`, the standalone loop or the `--queue-wait` verdict.

**Assembly.** `queue_wait_eval` is the one chokepoint for the rules read and has three callers: `step_guard` (flagless `--step`, fed by `qw_snapshot`), the `--queue-wait` mode (fed by `qw_snapshot`) and `queue_wait_gate` (standalone loop, fed by the widened pre-loop head read via `LOOP_BASE`); the `--step --fence` path skips the guard by design and is not a member. The members that must agree: the snapshot `--json` / `--jq` / regex triple, the head-read triple, the third argument at the three call sites, the single `rules/branches/` occurrence and its `$4` operand, `qw_base_path`, the three `qw_base_foreign` refusal sites (one per caller, each with its own outcome: exit 4, exit 4, `queue_wait`), and the two message texts that interpolate `QW_BASE`. Order is part of the property: the base is validated only after the OPEN, BEHIND/UNKNOWN and armed checks, and `QW_BASE` is reset at the top and set only after a successful rules read, so unarmed paths never read the base and the refusal cannot fire on them.

**Mutation matrix.**

| # | Mutation (each must drive the suite RED) | Expected |
|---|---|---|
| 1 | Replace the base segment of the rules URL with the literal `main` (anchor: the `rules/branches/$4?per_page=100` fragment) | RED - N1 (queue only on `develop`) and N2 (queue only on `main`: exit 14 instead of 4) |
| 2 | Own dispatch: pass an empty base at all three callers, so the rules read is never reached | RED - the existing main-based Q1 rows fail closed with rc 4 instead of `kind=queue_wait`, and N1 finds zero recorded rules calls |
| 3 | Second member: pass the base at the snapshot callers but the literal `main` at `queue_wait_gate` | RED - N6 (loop, base `develop`) |
| 4 | Second member: pass the base at `step_guard` but an empty string in the `--queue-wait` mode | RED - N1 (`--queue-wait` prints `queue_wait`) and N5 (`--queue-wait` must print `proceed`) |
| 5 | Drop the `/` to `%2F` encoding (anchor: the `printf '%s' "${b//\//%2F}"` line) | RED - N3 (`release%2F1.x` request) |
| 6 | Drop the allowlist (anchor: the full name-regex line including its `\|\| return 1`) | RED - N4 (an unsupported base reaches a rules request) |
| 7 | Reorder: validate the base before the `armed` check | RED - N5 (an `rel+1` or empty-base disarmed PR must make zero rules calls and sync) |
| 8 | Remove the non-`main` refusal at `step_guard` only | RED - N2 (flagless `--step` syncs instead of exit 4) |
| 9 | Remove the non-`main` refusal at `queue_wait_gate` only | RED - N2 (standalone loop syncs instead of exit 4) |
| 10 | Remove the non-`main` refusal in the `--queue-wait` mode only | RED - N2 (`--queue-wait` prints `proceed` instead of `queue_wait`) |
| 11 | Harness: the rules stub ignores the requested branch and applies its mode to any path | RED - N2 (the suite must notice the stub stopped discriminating) |
| 12 | Must-PASS input that differs from the canonical: base `feat/x/y` (three components) on a queue-ruled branch, and base `rel+1` on an unarmed PR | PASS - refused with the encoded path; syncs with zero rules calls |

**Anchor.** No stored value is compared to the thing it protects. The suite's `PASS -eq N` pin is a count floor and survives an add-one-delete-one substitution, so the mutation rows above (each fails when its targeted behaviour regresses) and the exact-path assertions are the identity check; the pin is bumped deliberately with the new row ids listed.

### Guard 2 - Single bounds helper and single sanitiser

**Property.** Each of the three env clamps and the stderr sanitiser exists in exactly one place in `sync-pr-behind.sh`, and every reader of `PR_QUEUE_TIMEOUT`, `PR_QUEUE_ATTEMPTS` and `PR_QUEUE_RETRY_SLEEP` and every sanitised `gh` stderr string goes through them.

**Assembly.** Readers: `queue_state_read`, `queue_read_settled`, `queue_wait_eval`, `qw_snapshot` (the chokepoints are `qb_bounds` and `qb_clean`); sanitised strings: `QS_DETAIL`, `detail`, `pvd`. Spellings the census must see: the three env reads (counted with `grep -o`, whole-line comments and the `USAGE` heredoc, which names the env vars in prose, stripped) and the `tr -c` set spelled exactly. A bypass is a new reader that skips the helper, so the per-call-site mutation rows (not the counts alone) prove each site still reaches the helper.

**Mutation matrix.**

| # | Mutation (each must drive the suite RED) | Expected |
|---|---|---|
| 1 | Paste an inline copy of the three env reads back into `queue_wait_eval` | RED - the sentinel counts 2 instead of 1 |
| 2 | Own dispatch: run the sentinel's counting function against an empty file | RED - it must report failure (a count of 0 is not 1) |
| 3 | Second member: add a fourth function that reads `${PR_QUEUE_TIMEOUT:-10}` directly | RED - the sentinel sees 2 timeout reads |
| 4 | Delete `\| qb_clean` at the `queue_state_read` site (anchor: the `QS_DETAIL="$(printf ...` line) | RED - the queue-read ctl row (ESC byte and forged tag reach stdout) |
| 5 | Delete `\| qb_clean` at the `queue_wait_eval` site (anchor: the `detail="$(printf '%s' "$detail" ...` line) | RED - R5 ctl |
| 6 | Delete `\| qb_clean` at the `qw_snapshot` site (anchor: the `pvd="$(printf ...` line) | RED - the pr view ctl rows (F5, W3) |
| 7 | `queue_read_settled` reads the raw env nap instead of `QB_NAP` | RED - characterization: `PR_QUEUE_RETRY_SLEEP=abc` must log sleep 2 |
| 8 | Harness: a non-recording `timeout` shim (execs without logging) | RED - the timeout characterization rows report no calls |
| 9 | Must-PASS input differing from the canonical: `PR_QUEUE_TIMEOUT=7` and `PR_QUEUE_ATTEMPTS=3` pass through unclamped | PASS - logged 7; three attempts counted |

**Anchor.** Same as Guard 1: count floors are paired with per-site mutation rows, so a deleted site cannot be replaced by an unrelated green row.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "stop hard-coding main in queue_wait_eval's `repos/$o/$r/rules/branches/main` read" | Phase 2.1 (`queue_wait_eval` base argument, `$4` path operand), sentinel `rules/branches/main == 0` | mapped |
| 2 | "make qw_snapshot also read baseRefName (its strict answer regex and every mock in the test suite change with it)" | Phase 2.1 snapshot; Phase 0.1 and 0.7 mock widening | mapped |
| 3 | "judge the PR against its own base branch's rules" | Phase 2.1 (all three callers incl. the loop head read); rows N1-N6 | mapped |
| 4 | "replace the three copies of the PR_QUEUE_TIMEOUT / PR_QUEUE_ATTEMPTS / PR_QUEUE_RETRY_SLEEP clamping block and the `tr -c '[:alnum:] ._:/=-' '?'` sanitiser (in queue_state_read, queue_wait_eval, qw_snapshot) with one helper" | Phase 1.1 (`qb_bounds`, `qb_clean`); Guard 2 | mapped |
| 5 | "Behaviour must stay identical for main-based PRs" | Phase 0.3 characterization, 0.5 N7 golden texts, existing Q1 rows asserting the `main` request string | mapped |
| 6 | "tests first (cq-write-failing-tests-before), including a non-main-base case" | Phase 0 (RED commit), rows N1-N6 | mapped |
| 7 | "Out of scope: the hash-pinned AGENTS rule line and .claude/rule-weakening-acks.txt; do not touch scripts/lib/test-affected-paths.sh or the shard manifests" | Non-Goals; Acceptance Criteria (merge-base diff) | mapped |
| 8 | "reference #9454 and #10832 as Ref only (no closing keywords, so the issue is closed by hand only after merge verification)" | Acceptance Criteria; Post-merge step | mapped |
| 9 | "merge via the queue using session-state.sh with_lock merge-main; no SSH; no live credentialed probes beyond read-only gh" | Ship phase (unchanged pipeline); all probes in this plan are read-only gh | mapped |
| 10 | "Leave #9482, #10245, #5840 untouched. Do not close #9454." | Acceptance Criteria | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `plugins/soleur/scripts/sync-pr-behind.sh` edits (helpers, base plumbing) | "In plugins/soleur/scripts/sync-pr-behind.sh" | asked |
| `plugins/soleur/test/sync-pr-behind.test.sh` edits (stubs, characterization, sentinel, base rows) | "fixture suite plugins/soleur/scripts/sync-pr-behind.test.sh" ... "every mock in the test suite change with it" | asked (the brief's path names the other suite; Reconciliation row 1) |
| Standalone-loop head-read widening (`LOOP_BASE`) | "judge the PR against its own base branch's rules" | inferred - justification: `queue_wait_eval` has a third caller, the standalone loop, with no snapshot; without a base source it would keep judging against `main`, leaving the ask unmet for that caller (CTO F1) |
| `qw_base_path` allowlist and `%2F` encoding | "judge the PR against its own base branch's rules" | inferred - justification: a branch name is untrusted text interpolated into an API path; the existing fail-closed contract requires an unknown answer not to become a yes (CTO F3) |
| Interim non-`main` refusal at the three guarded callers (`qw_base_foreign`) | "Behaviour must stay identical for main-based PRs" | inferred - justification: the requested base-aware read turns a safe refusal into the existing `origin/main` merge for an armed non-`main` PR (flagless `--step`, the loop and the hook's `--queue-wait`); delivering ask 3 safely needs the guard, and the CTO ruled it part of the change, not a scope addition (CTO F7) |
| `QW_BASE` in `qw_refusal` / `qw_unreadable` texts | "Behaviour must stay identical for main-based PRs" | inferred - justification: without it a refusal for another base would say `main` and mislead the next action; byte-identical for `main` (CTO F6) |
| `queue_read_settled` calling the bounds helper | "replace the three copies" | inferred - justification: the nap clamp has a fourth copy there; leaving it would keep the clamp in two places and the sentinel `== 1` could not hold (CTO F2) |
| Request-shape-compatible edits to `.claude/hooks/pre-merge-rebase.test.sh`, `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`, `plugins/soleur/scripts/sync-pr-behind.test.sh` | "every mock in the test suite change with it" | inferred - justification: the strict answer regex change reds every other mock of the snapshot and the exact-argument head-read stub; the contract rots otherwise |
| Characterization rows and recording `timeout`/`sleep` shims | "Behaviour must stay identical for main-based PRs" | asked |
| Sentinel row | "replace the three copies ... with one helper" | inferred - justification: a refactor with no drift guard re-forks silently, which is the defect this issue exists to remove |
| Mutation rows over the helper call sites, the base binding and the refusals | "tests first (cq-write-failing-tests-before)" | inferred - justification: the suite's mutation rows are literal anchors over the SUT text, two of which this change rewrites, and an unmutated helper or refusal leaves its call sites unpinned |
| Header, `--help`, comment, hook-comment and `queue-mode.md` wording edits | "stop hard-coding main" | inferred - justification: the script's `--help` and header state the main-only base and the suite pins other `--help` substrings; stale docs contradict the code |
| ADR-270 addendum closing residual 6 | "Merge Queue epic #9454 (ADR-270)" | inferred - justification: the ADR records "the base is `main`" as an accepted residual; recorded architecture must not lag the change |
| Tracking issue for the Non-Goal surfaces | "Ref only" | inferred - justification: the deferral rule requires an issue for each deferred item; it carries the `sync_step` / hook consequence the CTO named and must be linked before merge (CTO F7) |

### Split Assessment

- Subsystems touched: 3 - `plugins/soleur`, `.claude`, `knowledge-base`
- Planned files: 8 edited + 3 created (plan, tasks, decision-challenges) = 11 | Estimated changed lines: about 550 (script +110/-60, main suite +330, other suites +40, docs +20)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Pre-merge (PR)

- [ ] Tests first: the branch history shows the test-only commit before the script commit (`git log --format=%s origin/main..HEAD`), and the PR notes list the row names that were RED against the unchanged script.
- [ ] `bash plugins/soleur/test/sync-pr-behind.test.sh` ends `=== <N> passed, 0 failed ===` with the `PASS -eq` pin updated to N, N = 172 plus the listed new rows (computed from the row ids in `tasks.md`, not copied from the run).
- [ ] `bash plugins/soleur/scripts/sync-pr-behind.test.sh` ends `all 10 assertions passed`; `bash .claude/hooks/pre-merge-rebase.test.sh`, `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` and `bash plugins/soleur/test/monitor-pr-checks.test.sh` pass with `EXPECTED_CASES=77` and `MIN_VERDICTS=1123` unchanged (no case added there).
- [ ] Main-based behaviour identical: the existing Q1 rows still assert `repos/o/r/rules/branches/main?per_page=100` and `repos/{owner}/{repo}/rules/branches/main?per_page=100`; N7 asserts the `main` refusal and unreadable texts equal the golden literals captured from the pre-change script.
- [ ] Non-main base: N1, N3 and N6 pass with the exact recorded request path for `develop` and `release%2F1.x`; N2 shows exit 4 / `queue_wait` / exit 4 for the three callers with nothing fetched, merged or pushed; N4 shows `kind=gh rc=4` with zero rules calls for each unsupported base; N5 shows an unarmed non-`main` PR still syncs and `rel+1` raises no error.
- [ ] One helper: the sentinel row reports exactly 1 sanitiser, 1 read of each env variable and 0 `rules/branches/main` literals, and its counting function fails when pointed at an empty file.
- [ ] `shellcheck -x plugins/soleur/scripts/sync-pr-behind.sh` prints nothing; `grep -v '^[[:space:]]*#' plugins/soleur/scripts/sync-pr-behind.sh | grep -cE 'mapfile|readarray|declare -A|\$\{[A-Za-z_]+(,,|\^\^)'` prints `0`.
- [ ] `--help` still passes the suite's pinned substrings and now names `baseRefName` (`bash plugins/soleur/scripts/sync-pr-behind.sh --help | grep -c baseRefName` prints at least 1).
- [ ] Out of scope untouched, diffed against the merge base: `git diff --stat origin/main...HEAD -- scripts/lib/test-affected-paths.sh scripts/suite-durations.tsv scripts/suite-durations.tsv.n scripts/suite-shard-legs.tsv scripts/suite-shard-legs.tsv.n .claude/rule-weakening-acks.txt AGENTS.rules.md AGENTS.md` prints nothing. The files this PR may write are the Files-to-Edit list plus `knowledge-base/project/plans/`, `knowledge-base/project/specs/feat-one-shot-10832-sync-pr-behind-base-and-helpers/` (including a generated `session-state.md`) and the generated `knowledge-base/INDEX.md` cache if tracked.
- [ ] PR body references `Ref #9454` and `Ref #10832` with no closing keyword: `grep -ciE '(close[sd]?|fix(e[sd])?|resolve[sd]?) #(9454|10832)'` over the body prints `0`; the title carries no issue number with a closing keyword; the body names the interim non-`main` refusal as a deliberate narrowing for non-main PRs.
- [ ] The tracking issue for the Non-Goal surfaces exists (`gh issue view <N> --json state` reads `OPEN`) and is linked in the ADR-270 addendum; the addendum carries the five-line closure; `markdownlint-cli2` is clean on the plan, `tasks.md` and the ADR change; `technical-ruling-gate.sh --branch feat-one-shot-10832-sync-pr-behind-base-and-helpers` passes.

### Post-merge (agent, after merge verification)

- [ ] Merge goes through the queue with `bash plugins/soleur/scripts/session-state.sh with_lock merge-main ... -- gh pr merge ... --squash --auto` (the ship phase owns the exact form). Automation: `gh` CLI via the ship skill, no operator step.
- [ ] After MERGED, verify on `main` that `git grep -c 'rules/branches/main' origin/main -- plugins/soleur/scripts/sync-pr-behind.sh` prints `0`, then close #10832 by hand with an evidence comment (`gh issue close 10832`); `gh issue view 9454 --json state` still reads `OPEN`; #9482, #10245 and #5840 are not touched. Automation: `gh` CLI, executed by the agent (the brief orders closing by hand, after verification, never by closing keyword).

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Two CTO rulings (see `decision-challenges.md`). First batch (F1-F6): widen the loop's existing head read for the base, one bounds helper plus one stdin sanitiser (not the timeout wrapper or repo parse), a conservative base allowlist with `/` to `%2F`, snapshot answer `<STATE> <MERGESTATE> <armed|disarmed> <base>` with a loose base token and validation only inside `queue_wait_eval`, fences and the shared merge path out of scope, and `QW_BASE` in the message texts. Second ruling (F7, after three plan reviewers independently found the regression): add an interim refusal for a non-`main` base at flagless `--step`, the standalone loop and `--queue-wait` (exit 4 `kind=gh` for the first two, `queue_wait` for the third), part of delivering the requested change safely, not a scope addition. No other domain is relevant (no user-facing surface, legal, marketing, finance, sales or support impact).

## Test Scenarios

All rows are `integration` (real git fixtures with PATH-shimmed `gh`, `git`, and in the characterization fixtures `timeout` and `sleep`; no network). Key given/when/then forms:

- Given an armed BEHIND PR whose base is `develop` and a queue rule only on `develop`, when flagless `--step` runs, then it exits 14 with `kind=queue_wait`, one `pr view`, one rules read of `repos/o/r/rules/branches/develop?per_page=100`, nothing fetched, merged or pushed; `--queue-wait` prints `queue_wait`.
- Given the same PR but the queue rule only on `main`, when flagless `--step` or the standalone loop runs, then it exits 4 `kind=gh` with the non-`main` refusal and nothing moves; `--queue-wait` prints `queue_wait`.
- Given base `release/1.x`, then the recorded request is `.../rules/branches/release%2F1.x?per_page=100`.
- Given an armed BEHIND PR with base `a..b`, `x.lock`, `a?b`, `feat%2Fx`, or an empty base (or a loop head read with no base), when any caller evaluates it, then `kind=gh rc=4`, zero rules calls, nothing moved.
- Given a disarmed PR with base `develop` or `rel+1`, then it syncs as today with zero rules calls.
- Given the standalone loop with head read `feat develop`, armed BEHIND, queue on `develop`, then `kind=queue_wait rc=0`.
- Given a `main`-based PR, then every request string, refusal text and exit code equals the pre-change value (golden literals).
- Given `PR_QUEUE_TIMEOUT`, `PR_QUEUE_ATTEMPTS`, `PR_QUEUE_RETRY_SLEEP` set to a table of valid and invalid values, then each parameter is clamped identically and each site reaches the helper (logged `timeout`/`sleep` arguments and call counts).

Regression scenarios: every pre-existing row (172) stays green throughout Phases 0-2. Properties that must never break: (1) no rules request is ever made with a base outside the allowlist; (2) no path reads the base before the armed check; (3) the `main` request string is byte-identical; (4) a non-`main` base is never synced by a guarded caller after `proceed`.

## Success Metrics

The two residuals in #10832 are closed with the suite as the durable proof; a later non-main-base PR armed on a queue repo is judged against its own base (observable: the `kind=queue_wait` line or the explicit non-`main` refusal, with the base named in the text).

## Dependencies & Risks

- **Pin and anchor churn**: the `PASS -eq 172` pin and two literal mutation anchors move with this change; mitigated by writing the prescribed source shape into the plan so tests and code agree, unique-fragment anchors, and running the unmutated control first.
- **Mock drift across four suites**: mitigated by request-shape-compatible widening (RED keeps pre-existing rows green) and by running all five suites in Phase 2.2.
- **Recording shims vs hang stubs**: the `sleep` shim would neutralise the hang stubs; confined to characterization fixtures (Phase 0.2).
- **Fail-closed tightening**: an unusual legal base on an armed BEHIND PR now reads `kind=gh rc=4` instead of being judged against `main`, and a non-`main` base with no queue rule is refused instead of synced (CTO F3, F7); the allowlist covers every base this repo uses and each failure names its cause. 299 of the last 300 PRs are `main`-based.
- **Real `gh` shape**: `baseRefName` is a documented `gh pr view --json` field and was read live (`main`); the `// ""` guard turns a hypothetical null into the same fail-closed arm.
- **Fence vs script disagreement** on a non-main base (fence reads `main`, flagless callers read the base): documented in Non-Goals and the ADR addendum; the fence's `--fence` path skips the guard by design.
- **Run time**: about 45 new rows (7 characterization, 1 sentinel, 15 base, 22 mutation, control and harness rows; fixtures shared through runtime stub files) raise the 64 s suite by roughly 40 s; no shard manifest is touched. The exact count and ids are in `tasks.md`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it (threshold `none`).
- The new rows' anchors are literal lines of the post-Phase-2 script; the plan therefore prescribes those lines. If the implementer changes a prescribed line, the matching mutant reports "anchor absent" (a red row, never a silent pass) and must be re-pointed in the same commit. Each anchor must occur exactly once in the script (the `qw_mutant` uniqueness check), so avoid fragments like the repeated `--json` list or `|| return 1`.
- `install_gh_wait`'s `ok:<STATE MERGESTATE>:<armed|disarmed>` split is `IFS=: read -r _ st arm`; do not append a base field to that token (it would land in `$arm`). The base comes from the runtime `pr-base` file.
- The recording `sleep` / `timeout` shims belong only in characterization fixtures; the `exec sleep N` hang stubs resolve `sleep` through PATH.
- `.claude/hooks/pre-merge-rebase.test.sh` and `plugins/soleur/test/monitor-pr-checks.test.sh` are not selected by a script-only diff (read from `scripts/test-all.sh`); this PR edits the hook suite so it is selected, but run both explicitly regardless. Do not edit `scripts/lib/test-affected-paths.sh` to "fix" that (out of scope).
- Sentinel counts must be exact (`== N`), computed with comments and the `USAGE` heredoc stripped, using `grep -o ... | wc -l` for per-variable env reads (the three reads share one line in `qb_bounds`); never a negated `grep -q`.
- `qw_base_path` rejects `%` outright (it is outside the class): percent-encoding is applied exactly once, by the helper, so `feat%2Fx` is refused rather than double-encoded. `local LC_ALL=C` is load-bearing: without it `[A-Za-z]` accepts `é` under `en_US.UTF-8`.
- The `--queue-wait` and flagless `--step` paths must still make exactly one `pr view` and one rules read (rows F1 and W1-W4 assert it); a helper that adds a `gh` call breaks them.
- The standalone loop resolves its base once. Say so in a code comment; do not "fix" it with a per-attempt read (CTO F1).
- The interim refusal must not run in `--fence`, `sync_step` or `queue_wait_eval` (CTO F7): `QW_BASE` is reset at the top of `queue_wait_eval` and set only after a successful rules read, so unarmed and unreadable paths never see it.
- Do not touch `AGENTS.rules.md` or `.claude/rule-weakening-acks.txt`: `workflow-fidelity.test.ts` and the rule-body hashes pin that text, and the brief puts it out of scope.
- The `decision-challenges.md` table is machine-gated (`Ruled by CTO agent, <date>:` prefix, no literal pipe in a row, exact three-column header); append rulings inside the table only.

## References and Research

- Issue #10832; epic #9454; ADR-270 (`knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`, lines 724 and 755); PR #10655 (armed-BEHIND refusal in `--step` and the hook).
- `plugins/soleur/scripts/sync-pr-behind.sh`, `plugins/soleur/test/sync-pr-behind.test.sh`, `plugins/soleur/scripts/sync-pr-behind.test.sh`, `.claude/hooks/pre-merge-rebase.sh` and its test, `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`, `plugins/soleur/scripts/admin-merge-ready.sh` (encoding precedent), `plugins/soleur/skills/ship/references/queue-mode.md`.
- Decision record: `knowledge-base/project/specs/feat-one-shot-10832-sync-pr-behind-base-and-helpers/decision-challenges.md`.
