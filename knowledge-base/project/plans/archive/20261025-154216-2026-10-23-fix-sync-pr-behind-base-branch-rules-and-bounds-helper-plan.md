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

## Enhancement Summary

**Deepened on:** 2026-10-23
**Sections enhanced:** Proposed Solution (source shape), Implementation Phases, Guard Contract, Non-Goals, Acceptance Criteria, Test Scenarios, Sharp Edges
**Research agents used:** CTO (two rulings, F1-F7), DHH, Kieran, code-simplicity and CTO devex plan-review panel; deepen pass with security-sentinel, architecture-strategist, test-design-reviewer, pattern-recognition-specialist, spec-flow-analyzer and a verify-the-negative sweep

### Key improvements

1. The interim non-`main` refusal became an internal verdict (`foreign`) with one arm per caller, and a second internal verdict (`badbase`) so the pre-merge hook, which treats any non-zero exit as "sync anyway", gets `queue_wait` for an unusable base instead of falling through to an `origin/main` merge.
2. Every reader of the clamped bounds calls `qb_bounds` itself (a call-site that relied on an earlier call was unobservable and aborts under `set -u` on the `--queue-wait` path), pinned by a function-scoped call count.
3. The armed bit is parsed with `read -r` only (a suffix expansion would have read a base named `disarmed` as the armed bit and failed open); the sanitiser is `LC_ALL=C` for BSD `tr`; the base validator is a subshell function with a length cap.
4. Test plan corrected: green-before guard rows separated from RED rows, head-read stub serves JSON through the script's own `--jq`, recording shims confined to characterization fixtures, unique multi-line anchors for the per-caller arms, a hook-suite pair of rows for the real consumer, and an authoritative row-id inventory.
5. Factual correction: `plugins/soleur/lib/pr-merge-poll.ts` has no inline `rules/branches/main` read (the inline reads are in the two fences, `battery-owed.sh` and one reference).

### New considerations discovered

- The Phase 7 fences pass `--fence`, so the interim refusal covers no caller the pipeline uses; the live exposure is the fence's queue-wait expiry arm for a non-`main` armed BEHIND PR. Said plainly in Non-Goals and the ADR addendum, and named in the tracking issue.
- Only armed BEHIND or UNKNOWN PRs are refused; disarmed, DIRTY and BLOCKED non-`main` PRs keep syncing `origin/main` as they always did (pinned as known-wrong rows).
- Customer repos whose default branch is not `main` now get a clear refusal text instead of a `fetch` failure.

## Overview

Two residuals in `plugins/soleur/scripts/sync-pr-behind.sh`, both left open by PR #10655 (ADR-270, accepted residual 6) under epic #9454 and tracked as #10832:

1. **Base hard-coded to `main`.** `queue_wait_eval` reads `repos/$o/$r/rules/branches/main?per_page=100`, so a PR whose base is another branch is judged against `main`'s rules. Fix: carry the PR's own `baseRefName` into `queue_wait_eval` from each of its three callers and read that branch's rules. Because that moves one class of PR from a safe refusal to the script's existing `origin/main` merge, the change also adds one interim refusal for a non-`main` base (plan-review finding, CTO F7).
2. **Triplicated bound/sanitise helpers.** The `PR_QUEUE_TIMEOUT` / `PR_QUEUE_ATTEMPTS` / `PR_QUEUE_RETRY_SLEEP` clamping block and the `tr -c '[:alnum:] ._:/=-' '?'` sanitiser are repeated across `queue_state_read`, `queue_wait_eval` and `qw_snapshot` (the nap clamp has a fourth copy in `queue_read_settled`). Fix: one bounds helper and one sanitiser filter.

Behaviour for PRs based on `main` stays byte-identical, including the request string `repos/o/r/rules/branches/main?per_page=100`. Tests are written first (RED), including non-main-base cases, then the refactor (behaviour-preserving, GREEN), then the base change (GREEN).

This is Ref #9454 and Ref #10832 only. No closing keyword anywhere; #10832 is closed by hand after merge verification and #9454 stays open.

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality (verified) | Plan response |
|---|---|---|
| "fixture suite plugins/soleur/scripts/sync-pr-behind.test.sh" | That file (252 lines, 10 rows) covers only the regenerable-conflict arm of the standalone loop. The merge-queue and queue-wait rows live in `plugins/soleur/test/sync-pr-behind.test.sh` (1710 lines, 172 rows, baseline green in ~64 s). | Both suites are edited; the queue-wait suite carries the new rows. The scripts-side suite needs a stub-only change (see next row). |
| "make qw_snapshot also read baseRefName ... every mock in the test suite change with it" | `qw_snapshot` serves only the flagless `--step` guard and `--queue-wait`. The standalone loop reaches `queue_wait_eval` through `queue_wait_gate` with only `<STATE> <MERGESTATE>` and the armed bit from the queue GraphQL read, and has no snapshot. | The loop needs its own base source: widen its one pre-loop `headRefName` read (CTO F1, no extra `gh` call). |
| The snapshot is mocked in "the test suite" | Three suites mock the snapshot: `plugins/soleur/test/sync-pr-behind.test.sh`, `.claude/hooks/pre-merge-rebase.test.sh` (~l.905-930, which splits the mode with `read -r st mm arm` and so needs a fourth variable) and `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (~l.1712-1718). A fourth stub, `plugins/soleur/scripts/sync-pr-behind.test.sh`, matches the exact argument `headRefName` and would STUB-MISS on the widened loop read. | All four are edited, request-shape-compatible first (they serve the base only when the SUT asks for it), so they stay green against the old SUT during RED. |
| "three copies of the clamping block" | The three copies differ: `queue_state_read` and `queue_wait_eval` clamp timeout, attempts and nap; `qw_snapshot` clamps only the timeout; `queue_read_settled` holds a fourth nap clamp. | One helper sets all three values; each of the four readers calls it itself (CTO F2). |
| `main` is hard-coded only in the rules read | `sync_step` also fetches and merges `origin/main` (l.501-509); the hook's `--queue-wait` consumer then does its own `origin/main` merge; the Phase 7 fences keep inline `rules/branches/main` reads (`ship/SKILL.md` l.2304 and l.2316, `merge-pr/SKILL.md` l.426 and l.433, plus `plugins/soleur/skills/ship/scripts/battery-owed.sh` l.268 and `plugins/soleur/skills/ship/references/red-on-main-quarantine.md` l.66). `plugins/soleur/lib/pr-merge-poll.ts` has NO inline read (prose only). | Making the rules read base-aware changes what `proceed` means for a non-`main` base. Interim refusal added in this PR (CTO F7); the shared merge path, the fences and the hook's own merge stay out of scope with a tracking issue that must exist before merge. |
| Mutation rows pin the script text | `plugins/soleur/test/sync-pr-behind.test.sh` mutates the SUT by literal anchor (`qw_mutant`, `consume_mutant`, each requiring the whole anchor to occur exactly once); two anchors sit on lines this change rewrites (the `tr -c` sanitiser line and the snapshot answer-regex line) and the file ends in a `PASS -eq 172` pin. | Anchors and the pin move in the same commit as the code that moves them; new mutants anchor on unique fragments, which this plan prescribes. |

## Research Insights

### Premise validation (Phase 0.6)

Checked: #10832 is OPEN with no closing PR; #9454 is OPEN; the cited residual is ADR-270 line 724 ("(6) The base is `main`, as everywhere in the script") and line 755 ("hard-coded base, triplicated helpers ... tracked on #10832"). `git grep` on the worktree confirms one non-comment `rules/branches/main` literal in the script, three `tr -c` sanitiser lines, and env reads of `${PR_QUEUE_TIMEOUT:-` at l.195, l.290, l.337, `${PR_QUEUE_ATTEMPTS:-` at l.195, l.290 and `${PR_QUEUE_RETRY_SLEEP:-` at l.195, l.270, l.290. ADR corpus check for the mechanism: ADR-270 only; no alternatives-table entry rejects reading the base's rules. Stale premises found: the fixture-suite path and the `pr-merge-poll.ts` inline-read claim (see Reconciliation). Read-only measurement (2026-10-23): `gh pr list --state all --limit 300 --json baseRefName` shows 299 PRs on `main` and 1 on a stacked branch, so non-`main` bases are rare; the change is correct but near-dormant on this repo, which is why the test volume is justified by safety (a fail-open here is a wrong push), not frequency. The script also runs on customer hosts, where the default branch may not be `main`.

### Property list and cut list (Phase 0.6b)

Properties:

1. An armed BEHIND/UNKNOWN PR is judged against the merge-queue rule of its own base branch, from every caller (flagless `--step`, `--queue-wait`, standalone loop).
2. A base that is empty or outside a conservative name set is never used in a URL; it fails closed (`kind=gh`, rc 4) at flagless `--step` and the loop, and answers `queue_wait` at `--queue-wait`; paths that do not reach the rules read are unaffected by any base.
3. For `main`-based PRs nothing observable changes: same request string, same refusal text, same exit codes.
4. Each env clamp and the stderr sanitiser exist once, every reader goes through them, and each reader calls the bounds helper itself.
5. A future copy-paste of either block, or a bypassing call site, turns a test red.
6. An armed BEHIND or UNKNOWN PR with a validated non-`main` base and no queue rule is never handed to a sync that merges `origin/main` by flagless `--step`, the standalone loop or the `--queue-wait` verdict. Scope is deliberately that narrow (see Non-Goals).

Cut list (mechanism, property, what already covers it):

- A separate lazy `gh pr view --json baseRefName` read inside `queue_wait_eval` - property 1 for the loop - covered by widening the loop's existing head read at no extra call (CTO F1, option A).
- Appending the base to the per-attempt `state_line` - property 1 - rejected: a base such as `fix-DIRTY` corrupts the `*DIRTY*` glob tests.
- A general percent-encoder for base names - property 2 - cut: a conservative allowlist plus `/` to `%2F` covers every base this repo uses and fails closed otherwise (CTO F3); the hook fall-through that made a deterministic `kind=gh` dangerous is handled by the `badbase` verdict instead.
- Folding the `timeout`/`gtimeout` wrapper selection and the `PR_QUEUE_REPO` parse into the helper - property 4 - cut (CTO F2); residual duplication is recorded, not hidden.
- Making `sync_step` merge `origin/<base>` - property 6 - cut: it touches the shared merge/push path the fences use (CTO F7 option (c)).
- Refusing every non-`main` base before `queue_wait_eval`'s early returns (the base is in hand without an extra call) - property 6 - cut: it would change behaviour for disarmed, DIRTY and BLOCKED non-`main` PRs the brief never asked about.
- Plan-review cuts applied: the sentinel set collapses to two rows; harness meta-mutants are limited to one per guard (the Guard Contract rules require one harness row and one must-pass row); characterization tables use boundary values through one site each; mock stubs read the base from a runtime file so one fixture serves a table.

### Rulings (CTO, 2026-10-23)

Recorded in `knowledge-base/project/specs/feat-one-shot-10832-sync-pr-behind-base-and-helpers/decision-challenges.md` (rows F1-F6, the F5 correction and the F7 row with its deepen-plan refinements). The first batch also served as the plan's scoped strong-model consult (Step 4.5: same decision gate, curated payload, no separate advisor spawn). The plan-review panel (DHH, Kieran, code-simplicity, CTO devex lens) then reviewed the finished plan; its one correctness convergence (the `sync_step` regression) went back to the CTO as a second ruling (F7); the deepen pass (security, architecture, test design, pattern, spec-flow, verify-the-negative) produced the refinements recorded in the F7 row.

### Files and call sites measured

- `plugins/soleur/scripts/sync-pr-behind.sh` (647 lines): clamps at l.195-199, l.270-271, l.290-297, l.338; sanitiser at l.240, l.317, l.352; rules read at l.305; snapshot at l.331-356; loop head read at l.567; `--queue-wait` mode at l.361-370; `step_guard` at l.376-385 (a bare `case` with no trailing `return 0`; its call at l.560 is a bare statement); `queue_wait_gate` at l.472-481; refusal and unreadable texts at l.323-329; the dequeue recovery text at l.448 hard-codes `main`.
- Callers of the three reads: `.claude/hooks/pre-merge-rebase.sh` l.757-790 (`--queue-wait` with `PR_QUEUE_ATTEMPTS=1 PR_QUEUE_TIMEOUT=5`; it accepts a verdict only on rc 0 plus exactly one `queue_wait|proceed` line and otherwise falls through to its own `origin/main` merge), `monitor-pr-checks.sh` and the fences (`--queue-state`), the fences (`--step --fence`, guard skipped). No `apps/` file references the script (`git grep -n sync-pr-behind -- apps/` is empty), so there is no hosted caller.
- Verified read-only on 2026-10-23: `gh pr view 10939 --json baseRefName --jq .baseRefName` prints `main`; `gh api "repos/jikig-ai/soleur/rules/branches/main?per_page=100" --jq length` prints `5`; the same call for the nonexistent branches `feat%2Fx` and `feat/x` prints `0` (a branch without rules answers an empty array, not an error, and both slash spellings are accepted - so the `%2F` encoding is adopted on the `plugins/soleur/scripts/admin-merge-ready.sh` l.414 precedent, `jq @uri`, whose test l.310 expects `rules/branches/feat%2Fx`, not because the live API distinguishes them; this script has no standalone `jq`, so the encoding is hand-rolled); `baseRefName` is a valid `gh pr view --json` field (`plugins/soleur/test/pr-overlap-preflight.test.sh` l.118 field list).
- Helper behaviour run under bash 5.3 before prescribing it (`qw_base_path` over `main develop release/1.x feat/x/y - -x a. .h x.lock a..b a//b a?b feat%2Fx '' é rel+1 a.lock/b v1.lockx` under `LC_ALL=en_US.UTF-8`; the security pass re-ran a wider hostile table: dot segments, `%`, `?`, `#`, `{branch}`, control characters, unicode spaces, gh flag lookalikes, 300-character names): only plain `[A-Za-z0-9._-]` components survive and none alters the request; `local LC_ALL=C` rejects `é` where `[A-Za-z]` accepts it in `en_US.UTF-8`; GNU `tr` is byte-wise but BSD `tr` (macOS) is locale-aware, so `qb_clean` also pins `LC_ALL=C`. bash 3.2 itself was not available to run, so the validator is written as a subshell function body (`( LC_ALL=C; ... )`), which does not depend on `local` scoping of `LC_ALL`.
- Baselines before any edit: `bash plugins/soleur/test/sync-pr-behind.test.sh` ends `=== 172 passed, 0 failed ===` (64 s); `bash plugins/soleur/scripts/sync-pr-behind.test.sh` ends `all 10 assertions passed`; `shellcheck -x plugins/soleur/scripts/sync-pr-behind.sh` is clean; floors `EXPECTED_CASES=77` (`.claude/hooks/pre-merge-rebase.test.sh` l.2804) and `MIN_VERDICTS=1123` (`plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` l.2396). The suite exports `PR_QUEUE_RETRY_SLEEP=0` (l.44) and `PR_QUEUE_REPO=o/r` only between l.1135 and l.1634; rows that assert `repos/o/r/...` must sit inside that window.
- Documentation that names the main-only base (update): script header l.53, `--help` l.99, l.118-119, l.134-135, `queue_wait_eval` comment l.281-287, `.claude/hooks/pre-merge-rebase.sh` l.757-758 (comment), `plugins/soleur/skills/ship/references/queue-mode.md` l.7 (the new sentence must not contain `--fence` or `sync-pr-behind.sh <PR> --step`: `pr-merge-poll.test.ts` l.100-148 censuses both across every `.md` under `plugins/soleur`), stale comments quoting the three-field snapshot (`.claude/hooks/pre-merge-rebase.test.sh` l.912 and l.2117, `plugins/soleur/test/sync-pr-behind.test.sh` l.1301), ADR-270 (new addendum placed after the existing 2026-10-23 addendum; the earlier addenda are dated records and stay). Leave but name in the addendum (they keep saying "main has a merge queue" or describe a standalone armed BEHIND PR as `kind=queue_wait` by design): fence prose in `ship/SKILL.md` and `merge-pr/SKILL.md`, `monitor-pr-checks.sh` l.405, `plugins/soleur/lib/harness.ts`, `antigravity/INSTRUCTIONS.md`, `infra/github/README.md`, `ship/references/merge-queue-dequeue.md` l.37, `drain-prs/SKILL.md` l.89, `AGENTS.rules.md` (pinned by `workflow-fidelity.test.ts` and the rule-body hashes), `pr-merge-poll.ts` l.82.
- CI selection (read from `scripts/test-all.sh` by the research pass): the stem rule selects both sync-pr-behind suites from a script edit; `.claude/hooks/pre-merge-rebase.test.sh` and `plugins/soleur/test/monitor-pr-checks.test.sh` are NOT selected by a script-only diff, but this plan edits the hook suite and the hook file, which selects them. `scripts/lib/test-affected-paths.sh` and the shard manifests stay untouched per the brief.

### Learnings applied

- `knowledge-base/project/learnings/2026-10-19-a-per-area-drawdown-cannot-satisfy-a-live-census-gate-and-reindenting-breaks-text-anchored-mutants.md` - grep the suites for the changed text before editing; run the unmutated control first.
- `knowledge-base/project/learnings/2026-09-25-gh-stub-must-mirror-real-cli-flags.md` - stubs serve fields by request shape and refuse the rest; no invented flags.
- `knowledge-base/project/learnings/2026-10-07-a-sync-that-defers-to-a-queue-needs-a-bounded-wait-and-a-reset-that-a-deleted-read-took-with-it.md` - list what a removed or moved read also did; every unreadable answer keeps the old safe arm.
- `knowledge-base/project/learnings/2026-10-22-a-verdict-function-inside-command-substitution-cannot-exit-and-an-echoing-stub-inflated-my-counts.md` - the helpers must not `exit` outside a subshell body; `queue_wait_eval` keeps returning 0 and reporting through `QW_VERDICT`.

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open` (213 KB) and matched each planned path with `jq --arg`: no issue body names `plugins/soleur/scripts/sync-pr-behind.sh`, `plugins/soleur/test/sync-pr-behind.test.sh`, `plugins/soleur/scripts/sync-pr-behind.test.sh`, `.claude/hooks/pre-merge-rebase.test.sh` or `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`. One substring hit on `sync-pr-behind`: #8659 ("33 test suites replace test-helpers' composed EXIT trap and leak the incident sandbox on direct runs"). Disposition: **Acknowledge** - a different concern (EXIT-trap composition in test suites); the queue-wait suite already installs its owning trap before sourcing `test-helpers.sh`, and the new rows reuse that arrangement. The issue stays open.

## Problem Statement / Motivation

A non-`main`-based PR armed on a queue repo is judged against `main`'s rules, so the wait-versus-sync decision can be wrong in both directions: a PR on a branch with no queue rule is refused a sync it needs, or a PR on a queue-ruled branch is synced when the queue should make it current. The duplicated clamp and sanitiser blocks mean any future change to a bound or to the sanitiser must be made three or four times, and the suite pins only one of the sanitiser copies. Re-evaluation criteria from #10832: take both together the next time the script is edited, or when a non-main-base PR is armed on a queue repo.

## Proposed Solution

### Prescribed source shape (tests in Phase 0 anchor on these lines, so they are specified here; normative only where a literal anchor depends on it)

Helpers, defined once before `queue_state_read`, with the globals initialised at the top level of the script (`set -u`): `QB_TIMEOUT=10; QB_ATTEMPTS=2; QB_NAP=2; QW_BASE=""; LOOP_BASEREF=""`.

```bash
qb_bounds() {
  QB_TIMEOUT="${PR_QUEUE_TIMEOUT:-10}"; QB_ATTEMPTS="${PR_QUEUE_ATTEMPTS:-2}"; QB_NAP="${PR_QUEUE_RETRY_SLEEP:-2}"
  [[ "$QB_TIMEOUT" =~ ^[1-9][0-9]{0,3}$ ]] || QB_TIMEOUT=10
  [[ "$QB_ATTEMPTS" =~ ^[1-9]$ ]] || QB_ATTEMPTS=2
  [[ "$QB_NAP" =~ ^[0-9]{1,3}$ ]] || QB_NAP=2
}
qb_clean() { LC_ALL=C tr -c '[:alnum:] ._:/=-' '?'; }
qw_base_path() (  # <base> -> prints the rules-URL path segment; exit 1 for an empty or unsupported name
  LC_ALL=C; b="${1:-}"
  [[ ${#b} -le 255 && "$b" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$ ]] || exit 1
  [[ "$b" != *..* && "$b" != *.lock && "$b" != *.lock/* ]] || exit 1
  printf '%s' "${b//\//%2F}"
)
```

Why hand-rolled and why this allowlist (code comment): the script has no standalone `jq` and targets macOS bash 3.2, so `admin-merge-ready.sh`'s `jq @uri` is unavailable; the set is stricter than that script's `^[A-Za-z0-9._/-]+$` on purpose, because here the value reaches a model-visible line and an API path.

Call sites: every function that reads a `QB_*` value calls `qb_bounds` itself first and uses the globals directly (no copies into locals): `queue_state_read` (all three), `queue_read_settled` (`QB_NAP`), `queue_wait_eval` (all three), `qw_snapshot` (`QB_TIMEOUT`). `--queue-wait` runs `qw_snapshot` before anything else, so a snapshot that relied on an earlier call would abort under `set -u`. The three sanitised strings become `... | qb_clean)"` with their distinguishing prefixes unchanged (`QS_DETAIL=`, `detail=`, `pvd=`); where a base is echoed, truncation to 60 characters happens after `qb_clean`. `qb_bounds`, `queue_wait_eval` and the readers are called directly, never inside `$( )`, so the globals they set are not lost to a subshell; `qw_refusal`, `qw_unreadable`, `qw_foreign` and `qw_base_path` run inside `$( )` and only read globals. Helpers never `exit` outside a subshell body.

Base plumbing:

- `qw_snapshot` asks `--json state,mergeStateStatus,autoMergeRequest,baseRefName` (base appended last so mocks that glob `mergeStateStatus,autoMergeRequest` still match) with `--jq` producing `<STATE> <MERGESTATE> <armed|disarmed> <base>` (base via `.baseRefName // ""`, so the line always ends with a space and a possibly empty token). The strict regex becomes `^(OPEN|CLOSED|MERGED)\ [A-Z_]+\ (armed|disarmed)\ [^[:space:]]*$`: the base token is loose and may be empty (CTO F4, refined), because validation belongs inside `queue_wait_eval` after the armed check, so an odd or empty base never fails a path that does not reach the rules read; the old three-token shape (no trailing space) still fails the regex. The answer is split with `read -r st ms am base <<<"$out"` only (never a suffix or prefix expansion: `${out##* }` would read a base named `disarmed` as the armed bit and fail open) into `QW_STATE="$st $ms"`, `QW_ARMED="$am"` and `QW_BASEREF="$base"`; `qw_snapshot` initialises its own outputs. The `qw_snapshot; queue_wait_eval "$QW_STATE" "$QW_ARMED"` pair now appears twice (`--queue-wait` mode and `step_guard`); fold it into one `qw_probe` function that passes `"$QW_BASEREF"` as the third argument once.
- `queue_wait_eval <state_line> <armed|disarmed|-> <base>`: `QW_BASE` is reset to empty at the top; after the existing OPEN, BEHIND/UNKNOWN-not-DIRTY and `armed` checks (order preserved: an unarmed or non-BEHIND PR never touches the base) validate the base with `qw_base_path`. On failure set the internal verdict `badbase` with a detail that starts `base branch` (not the `rule read failed after` prefix an existing mutation anchor uses) and shows the base after `qb_clean` and a 60-character truncation, returning 0. On success set `QW_BASE` immediately, before the read (so `qw_unreadable` keeps naming the base and is byte-identical for `main`), then build the read as `gh api "repos/$1/$2/rules/branches/$4?per_page=100" --jq "$3"` with `$4` the encoded base; for base `main` the string is byte-identical to today's. After a successful read: rules >= 1 gives `wait` (unchanged); rules == 0 and `$QW_BASE` not `main` gives the internal verdict `foreign`; rules == 0 and base `main` gives `proceed` (unchanged).
- Standalone loop: the pre-loop read becomes `--json headRefName,baseRefName --jq '"\(.headRefName) \(.baseRefName // "")"'`, split with `[[ "$head_out" =~ ^([^[:space:]]+)\ ([^[:space:]]*)$ ]]` into `head_ref` and `LOOP_BASEREF` (CTO F1's single-line regex, with the second token allowed to be empty); any other shape (a single token, a multi-line answer because stderr is merged by `2>&1`) leaves `head_ref` as the whole answer, exactly as today, and `LOOP_BASEREF` empty. An empty base is fatal only when `queue_wait_eval` reaches the rules read (armed BEHIND), where it is `badbase`. The base is resolved once per run; a mid-loop retarget is judged against the old base (at worst one stray merge, because `sync_step` then reports `noop`), and a code comment says so. The widened read ignores `PR_QUEUE_REPO`, as the read it replaces did. `queue_wait_gate` passes `"$LOOP_BASEREF"`.
- **Interim non-`main` refusal (CTO F7), one arm per caller, written as `case` arms placed directly after the `wait)` arm so each is a unique multi-line anchor:**
  - `step_guard`: `foreign)` and `badbase)` print `kind=gh` rc 4 and exit 4. It also ends in an explicit `return 0` (it is a bare statement under `set -e`).
  - `queue_wait_gate`: `foreign)` and `badbase)` print `kind=gh` rc 4 and exit 4.
  - `--queue-wait` mode: `foreign)` and `badbase)` print `queue_wait` and exit 0 (read-only, the stricter direction, matches the pre-change answer for this class; `kind=gh` would make the hook treat the answer as unreadable and fall through to its own `origin/main` merge). The stdout stays exactly one line.
  - Texts live in two functions beside `qw_refusal` and `qw_unreadable`: `qw_foreign` ("PR #N is armed and BEHIND on base '<base>', not main, and that base has no merge queue; this script only syncs from origin/main, so it is not syncing; NOT A TRANSIENT ERROR - retrying will not help; sync by hand against the base or retarget the PR") and a `badbase` text with the same "NOT A TRANSIENT ERROR" lead (it does not borrow `qw_unreadable`'s "retry the poll" advice). Neither text advises "disarm first, sync, re-arm", which on a foreign base walks into the merge the refusal prevents. The `--help` exit-4 row gains a clause naming these causes and keeps the pinned substring `kind=gh`. No new kind, no new exit code.
  - Not in `--fence`, `sync_step` or `queue_wait_eval`'s return value for `main`. A forgotten caller arm falls through to `proceed` as today, which the per-caller mutation rows pin.
- `qw_refusal` and `qw_unreadable` interpolate `QW_BASE` where they say "main" (`${QW_BASE:-its base branch}` in `qw_unreadable`, where the base may be unknown); text is byte-identical for `main`.
- Documentation: header l.53, `--help` l.99 / l.118-119 / l.134-135 and the `queue_wait_eval` comment say "the PR's own base branch" and name `baseRefName` in the snapshot field list; every substring the suite and the fences pin in `--help` stays (`--fence`, `--queue-wait`, `--step`, `exit codes`, `^  10`, `^  11 .*kind=noop`, `^  12 .*wrong_branch`, `^  13 .*merge queue`, `^  14 .*kind=queue_wait`, `^  4 .*kind=gh`, `kind=dequeued`, `kind=queued`, `should a sync be skipped`, `is the PR in the queue`, `nobody else`, `merge queue`). A code comment states that the refusal is a convenience interlock, not an authorization boundary (a PR author can retarget between the snapshot and the read).

## Non-Goals

- **Honest scope of the refusal.** It covers only an armed BEHIND or UNKNOWN PR with a validated non-`main` base and no queue rule, at flagless `--step`, the standalone loop and `--queue-wait`. It does NOT cover the Phase 7 fences (they pass `--fence`, which skips the guard; the fence's queue-wait expiry arm after 6 idle ticks runs `--step --fence` straight into `sync_step`, and the fence's own inline `main` rules read sets the queue flag for a non-`main` PR - that is the live exposure for the pipeline, and it stays), and it does NOT cover a disarmed, DIRTY, BLOCKED or CLEAN non-`main` PR, which keeps syncing `origin/main` exactly as it always did (pinned by rows as known-wrong, not intended). Refusing those would change behaviour the brief never asked about.
- `sync_step` still fetches and merges `origin/main`, the hook still does its own `origin/main` merge, and the fences keep inline `rules/branches/main` reads (`ship/SKILL.md` l.2304 and l.2316 carry the same `select(.type == "merge_queue")` program, `merge-pr/SKILL.md` l.426 and l.433, `battery-owed.sh` l.268, `red-on-main-quarantine.md` l.66). Option (c), making `sync_step` merge `origin/<base>`, needs its own design and tests against the fence rows (CTO F7). One tracking issue for all of it must exist and be linked in the ADR addendum before merge (the work phase files it with `gh issue create`, labels verified with `gh label list --limit 200` first, milestone from `knowledge-base/product/roadmap.md`), referencing #9454 and #10832 as Ref only. It names: the fence expiry arm as the live exposure; the hook's `queue_wait` context wording ("the queue makes it current", inaccurate for a foreign base with no queue); the dequeue recovery text at script l.448 that hard-codes `main`; the post-push "BEHIND resolved: branch caught up to main" wording; `pr-merge-poll.ts`, `merge-queue-dequeue.md` and `drain-prs/SKILL.md`, which describe a standalone armed BEHIND PR as `kind=queue_wait`. Re-evaluation criterion: the first non-main-base PR armed on a queue repo, or the next edit of `sync_step`.
- Optional hardening noticed but not done: the raw `gh` stderr echoed at script l.568, l.579 and l.637 (`gh pr view failed: ...`), and the `..` segment the existing `PR_QUEUE_REPO` regexes accept (operator-controlled). Listed in the tracking issue.
- `.claude/hooks/pre-merge-rebase.test.sh`'s selection gap: a script-only diff does not select the hook suite or `monitor-pr-checks.test.sh`; fixing the mapping means editing `scripts/lib/test-affected-paths.sh`, which the brief forbids. Recorded only as a Sharp Edge.
- The hash-pinned AGENTS rule line, `.claude/rule-weakening-acks.txt`, `scripts/lib/test-affected-paths.sh`, the shard manifests (`scripts/suite-*.tsv*`), #9482, #10245, #5840: untouched.

## Technical Considerations

- **bash 3.2 portability** (the script runs on customer macOS hosts): no `mapfile`, no `${x,,}`, no associative arrays; `[[ =~ ]]` with the regex written inline is 3.2-safe (the script already relies on it); `read -r`, `BASH_REMATCH` and a subshell function body are 3.2-safe. The new code adds no external binary beyond the `tr` already used.
- **`set -euo pipefail`**: `queue_wait_eval` keeps returning 0 and reports through `QW_VERDICT` (now `wait | proceed | unreadable | foreign | badbase`); `qb_clean` runs in a pipeline stage; every caller's verdict handling is a `case` (an unlisted verdict falls through to `proceed`, as today). `step_guard` ends with `return 0`. Globals are initialised at the top level.
- **Fail-closed**: an unreadable, empty or unsupported base never reaches a URL and never yields `proceed`; the single place that already fails closed on an unknown rules answer (ADR-270 addendum 2026-10-09) keeps that meaning.
- **Sanitising**: the base value is untrusted text (an attacker-editable branch name); it is validated before any use in a URL and, when echoed in a detail, passed through `qb_clean` then truncated to 60 characters; a validated base cannot contain a space, `=`, a bracket or a control character, so it cannot forge a tagged line or a key=value pair.
- **No extra `gh` call on any path**: flagless `--step` still makes one `pr view` and one rules read; `--queue-wait` the same; the loop adds none (CTO F1).
- **Network-Outage gate**: the keyword scan matches `timeout` (the local `timeout(1)` wrapper and its env bounds). This is not a connectivity symptom (no SSH, firewall, DNS or provider outage); hung `gh` reads are already bounded by the existing wrapper and this change does not touch it, so the L3-L7 deep-dive does not apply.
- NFR impact: none beyond reliability of an operator tool; no NFR register change.

## Implementation Phases

Order is dependency-first: tests define the contract before the code moves. Commits are RED, GREEN-refactor, GREEN-base so the history shows the tests-first order (a review aid only: the repo squash-merges). The authoritative row-id inventory and counts are in `tasks.md`; this section names the rows and what each proves.

### Phase 0 - RED tests and request-shape-compatible mock widening

Edit `plugins/soleur/test/sync-pr-behind.test.sh`. Stub widening is green (every pre-existing row stays green against the old SUT because stubs answer the old request shape exactly as today and serve the new fields only when the SUT asks for them).

- 0.1 Stubs read the base from runtime files so one fixture serves a whole table, with env knobs `QBASE` and `QRULES_BRANCH` on `fw_run` / `qw_run` (like `QPR` and `FW_MARKER`; each run unsets them afterwards so a leaked `develop` cannot decide a later `main` row). `install_gh` and `install_gh_wait` write `$bin/pr-base` (default `main`). The head-read arm serves raw JSON `{"headRefName":"<head>","baseRefName":"<base>"}` through the `--jq` the script passed (the way `install_gh_wait` serves the snapshot) when argv names `baseRefName`, and the old plain `<head>` otherwise; a wrong or reordered `--jq` therefore reddens N6 instead of passing on an echoed string. Pr view JSON bodies are built with `jq -n --arg` (hand-interpolated JSON breaks on control characters) and the existing "delete fields `--json` did not name" loop covers `baseRefName`. `install_gh_wait`'s `ok:<STATE MERGESTATE>:<armed|disarmed>` split (`IFS=: read -r _ st arm`) is unchanged. `install_rules` parses the requested branch out of the path (between `rules/branches/` and `?`), decodes `%2F`, applies its mode only to the branch in a `rules-branch` file (default `main`; any other branch answers `[]`, a branch without rules, as measured), and refuses an unparseable path with exit 64 and a refusal log the suite asserts empty. Every call still appends its argv to `rules-calls`.
- 0.2 Recording `timeout` and `sleep` shims (the `install_git_shim` pattern) live in a separate `bin` used only by the characterization fixtures. The `sleep` shim is log-only (it must not exec the real `sleep`: nine seconds of dead wall-clock in the nap table otherwise); the `timeout` shim resolves the real `timeout` or `gtimeout` to an absolute path first, execs it, and the suite SKIPS loudly if neither exists. Both log the wrapped command's first words (`gh api graphql`, `gh api repos`, `gh pr view`) beside the numeric argument so the sites can be told apart. They never sit in a fixture that uses a hang mode: the hang stubs `exec sleep 8` / `exec sleep 5` through PATH. Nap rows set `PR_QUEUE_RETRY_SLEEP` explicitly per case and use `env -u PR_QUEUE_RETRY_SLEEP` for the default case (the suite exports `0`).
- 0.3 Characterization rows C1-C7 (green before and after; they pin today's behaviour through the refactor): three tables looped inside one row each, bad cases reported by name, through one site each - timeout via `--queue-state` (unset, `7`, `0`, `00`, `07`, `abc`, `9999`, `10000` expect `10 / 7 / 10 / 10 / 10 / 10 / 9999 / 10`), attempts via a failing rules read (unset, `1`, `3`, `0`, `abc`, `9`, `10` expect call counts `2 / 1 / 3 / 2 / 2 / 9 / 2`), nap via `queue_wait_eval` on a failing rules read (unset, `5`, `0`, `abc`, `999`, `1000`, `-1` expect `2 / 5 / 0 / 2 / 999 / 2 / 2`) - plus one non-default-value row per remaining site proving it reaches the helper: timeout through `--queue-wait` (pr view, disarmed run) and through the rules read, attempts through `queue_state_read` (`gqlfail`), nap through `queue_read_settled` (marker-dequeue run).
- 0.4 Sentinel rows. S1 (red until Phase 1): counted over the SUT with whole-line comments (`^[[:space:]]*#`) and the `USAGE` heredoc stripped, with exact `== N` comparisons (never `<=`, never a negated `grep -q`), `grep -oF` and `tr -d ' '` (macOS `wc -l` pads), and `|| true` (not `|| echo 0`, which printed two lines under `pipefail`): the `tr -c '[:alnum:] ._:/=-'` spelling `== 1`; each of `PR_QUEUE_TIMEOUT:-`, `PR_QUEUE_ATTEMPTS:-`, `PR_QUEUE_RETRY_SLEEP:-` `== 1` (census broadened to the `$X` and `${X-` spellings too); and, per consumer function (extracted with an awk range as the existing M8 row does), exactly one `qb_bounds` call in each of `queue_state_read`, `queue_read_settled`, `queue_wait_eval` and `qw_snapshot`. Baselines today: 3 sanitisers; env reads timeout 3 / attempts 2 / nap 3; zero `qb_bounds`. One anti-vacuity check runs the counting function against an empty file and requires it to fail. S2 (red until Phase 2, its own row so Phase 1 can be green): `rules/branches/main` `== 0` paired with `rules/branches/` `== 1` (the `== 0` clause alone also passes on an empty file).
- 0.5 Base rows. **RED before the change** (each fails on a behavioural assertion message, never on "anchor absent"), via `fw_run` (flagless `--step`, `wait`) and `qw_run` (loop), asserting the exact request in `rules-calls` and, on refusal arms, that nothing was fetched, merged or pushed:
  - N1s base `develop`, queue on `develop` only: flagless `--step` exits 14 `kind=queue_wait`, path `repos/o/r/rules/branches/develop?per_page=100`, one `pr view`, one rules read. N1w `--queue-wait` prints `queue_wait`.
  - N2s base `develop`, queue on `main` only (the rules the old script would read): flagless `--step` exits 4 `kind=gh` with `qw_foreign` text, nothing moved. N2w `--queue-wait` prints exactly one line `queue_wait` (the path read is `develop`; the old script prints the same word, so the path assertion and the mutants carry this arm). N2l standalone loop exits 4. N2u the same as N2s on `OPEN UNKNOWN`. (Under the old script N2s exits 14 and N2l exits 0 with `kind=queue_wait`.)
  - N3a base `release/1.x` with the queue on that branch: refused (14), path `release%2F1.x?per_page=100`. N3b base `feat/x/y` (three components): path `feat%2Fx%2Fy`. These are also the must-PASS non-canonical inputs.
  - N4s unsupported-base table at flagless `--step` on an armed BEHIND PR, one looping row asserting the CAUSE (the `badbase` text naming the sanitised base, not "pr view snapshot read failed"), `kind=gh rc=4`, zero rules calls, nothing moved, no ESC byte: `feat%2Fx`, `a?b`, `a..b`, `x.lock`, `a.lock/b`, `a//b`, `a/./b`, `a/`, `-x`, `rel+1`, `a@b`, `{branch}`, an ESC-bearing base, a base over 60 characters (truncation) and over 255 (length cap), and the empty base. N4w the same table through `--queue-wait`: exactly one line `queue_wait`, rc 0. N4l the loop with an empty base and with a legacy single-token head read: `kind=gh rc=4`.
  - N6 standalone loop with head read `feat develop`, armed BEHIND, queue on `develop`: `kind=queue_wait rc=0`, path `develop`. N6b `--max-attempts 2` documents "base resolved once": the second attempt's recorded rules path is `develop` as well.
  - N7c refusal text for `develop` names `develop` where the `main` text says `main`.
  - N11 `é` base under `LC_ALL=en_US.UTF-8` (SKIP loudly when that locale is unavailable): rejected, so the `LC_ALL=C` pin is not dead.
  - N12 armed-bit parse: bases named `armed`, `disarmed`, `OPEN`, `BEHIND` (legal names that pass the allowlist) on an armed BEHIND PR: still judged armed (a suffix-expansion parse would read the base as the armed bit).
- 0.5b **Green before the change (guard rows, listed separately in the RED evidence):** N5a base `develop`, PR disarmed: flagless `--step` syncs (rc 0), `--queue-wait` prints `proceed`, zero rules calls; N5b the same for base `rel+1`; N5c `OPEN CLEAN` armed with an odd base: syncs, zero rules calls (so mutant G1-7, validate-before-armed, is killable); N5d a DIRTY non-`main` PR (flagless `--step` and loop) still syncs `origin/main` - pinned as known-wrong, tracked; N7a the `main` refusal text equals the golden literal captured from the pre-change script in this phase; N7b the `main` `qw_unreadable` text equals its golden; N8 snapshot answers with the old three-token shape, extra tokens or whitespace in the base: `kind=gh rc=4`; N9 `--step --fence` with a foreign base: guard skipped, syncs (documents the known bypass so it cannot regress silently); N10 a queued PR with a foreign base: `kind=queued`, zero rules calls.
- 0.6 Mutation and harness rows (RED until Phases 1-2: "anchor absent" is not RED evidence and is reported as such in the PR notes): see the Guard Contract. The two anchors this change rewrites (the `tr -c` line and the snapshot regex line) are re-pointed at the new lines in the phase that moves them; every new anchor is a fragment that occurs exactly once (the full `... --repo "$3" --json ...baseRefName --jq "$2"; else gh pr view "$1" ...` fragment, not the repeated `--json` list; the name-regex line, not the repeated `|| exit 1`; the per-caller `foreign)` arms anchored with the unique preceding `wait)` line). Add the new scenario kinds to `qw_scenario` (step, loop, wait) and a "real SUT satisfies the base scenarios" control row before the mutants, as lines 1594 and 1620 do.
- 0.7 Mock widening in the three other suites, request-shape-compatible: `.claude/hooks/pre-merge-rebase.test.sh` (`mss-<N>` gains an optional fourth token, default `main`; the split becomes `read -r st mm arm base`; the body carries `baseRefName`; the "delete fields not in `--json`" loop lists it; the rules route becomes branch-aware (other branches answer zero queue rules); the two comments quoting the three-field shape are updated) plus two new hook rows, T-Q23 (armed BEHIND, unsupported base: `--queue-wait` prints `queue_wait`, the hook skips its sync, no merge, no push) and T-Q24 (base `develop` with no queue rule: same), `EXPECTED_CASES` 77 to 79 and the case list; `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (the snapshot `data` JSON gains `"baseRefName":"main"`); `plugins/soleur/scripts/sync-pr-behind.test.sh` (the `headRefName*` arm answers JSON through the `--jq`). The stale snapshot comment at `plugins/soleur/test/sync-pr-behind.test.sh` l.1301 is updated.
- 0.8 Run every edited suite against the unchanged SUT: pre-existing rows stay green (control first - a red unmutated control voids every row below it); the RED rows fail on behavioural messages; the green-before guard rows are listed separately. Commit as test-only.

### Phase 1 - GREEN: one bounds helper, one sanitiser (behaviour-preserving)

- 1.1 Add `qb_bounds` and `qb_clean` exactly as specified; replace the four clamp copies and the three `tr -c` copies; each of the four readers calls `qb_bounds` first. No other change in this phase.
- 1.2 C1-C7 stay green throughout; S1 turns green (S2 and the snapshot-regex mutant stay red until Phase 2); re-point the `tr -c` mutation anchor; add and green the helper mutants.
- 1.3 `shellcheck -x plugins/soleur/scripts/sync-pr-behind.sh` stays clean; `bash plugins/soleur/test/sync-pr-behind.test.sh` is green except the base rows, S2 and the snapshot-regex mutant.

### Phase 2 - GREEN: base plumbing and the interim refusal

- 2.1 Snapshot (`read -r` parse, `qw_probe`), `qw_base_path`, `queue_wait_eval` with the `foreign` and `badbase` verdicts, loop head read, the per-caller arms, `qw_foreign` and the `badbase` text, `QW_BASE` in the two texts, `--help` / header / comment edits, as specified. Update the pass-count pin deliberately to the measured number (172 plus the new rows; the ids are in `tasks.md`).
- 2.2 All suites green: `bash plugins/soleur/test/sync-pr-behind.test.sh`, `bash plugins/soleur/scripts/sync-pr-behind.test.sh`, `bash .claude/hooks/pre-merge-rebase.test.sh` (`EXPECTED_CASES=79`), `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (`MIN_VERDICTS` unchanged: no case added there), plus `bash plugins/soleur/test/monitor-pr-checks.test.sh` as a control; the `pr-merge-poll` and `workflow-fidelity` censuses (`bun test plugins/soleur/test/pr-merge-poll.test.ts plugins/soleur/test/workflow-fidelity.test.ts`) stay green after the doc edits.

### Phase 3 - Documentation, ADR addendum, tracking issue

- 3.1 `.claude/hooks/pre-merge-rebase.sh` l.757-758 comment and `plugins/soleur/skills/ship/references/queue-mode.md` l.7: the PR's own base branch, without `--fence` or `sync-pr-behind.sh <PR> --step` in the new sentence. `queue-mode.md` l.5 (the fence reads `main`) is left as is.
- 3.2 ADR-270: append a short addendum (via `soleur:architecture`) after the existing 2026-10-23 addendum: residual 6 is partly closed (the rules read uses `baseRefName`; `sync_step`, the fences and the hook's own merge still read `main`), the snapshot field list is now four, the interim non-`main` refusal and its scope (armed BEHIND or UNKNOWN only, three guarded callers, not the fences), accepted residual (2) (the fence guard bypass) extends to it, the hook now receives `queue_wait` for an unusable or foreign base rather than falling through, the places that keep saying "main has a merge queue", and the tracking issue number. No C4 change (no actor, system, container, data store or access relationship changes; the script already talks only to GitHub through `gh`, as ADR-270's 2026-10-22 addendum states for this residual).
- 3.3 File the tracking issue (see Non-Goals) before the PR is marked ready, and link it in the ADR addendum.

## Files to Edit

- `plugins/soleur/scripts/sync-pr-behind.sh` - helpers, call sites, snapshot, `qw_probe`, `queue_wait_eval`, loop head read, per-caller arms, texts, header/`--help`/comments.
- `plugins/soleur/test/sync-pr-behind.test.sh` - stubs, characterization, sentinel, base, mutation and harness rows, anchors, pin, stale comment.
- `plugins/soleur/scripts/sync-pr-behind.test.sh` - `headRefName` stub arm only.
- `.claude/hooks/pre-merge-rebase.test.sh` - snapshot and rules stubs, two comments, two new cases, `EXPECTED_CASES`.
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
  configured_in: "plugins/soleur/scripts/sync-pr-behind.sh (tag, qw_refusal, qw_unreadable, qw_foreign, the badbase text)"

error_reporting:
  destination: "stdout tagged lines only; no Soleur-side sink by design (self-hosted CLI output must not be routed to Soleur infrastructure)"
  fail_loud: "an unusable base and a non-main base on an armed BEHIND PR print kind=gh rc=4 and exit 4 at flagless --step and the loop with a NOT A TRANSIENT ERROR lead (--queue-wait prints queue_wait, so the hook skips its own sync); every unreadable rules or pr view answer prints kind=gh rc=4; the pre-merge hook turns an unreadable answer into a named queue_wait_unreadable note, never a silent proceed"

failure_modes:
  - mode: "base branch read wrongly (field missing, garbled answer, unsupported name)"
    detection: "kind=gh rc=4 line from the strict answer regex or from the badbase arm, layer cli-stdout-artifact; covered by rows N4s, N4l and N8 of the committed fixture suite"
    alert_route: "agent session output; at the hook the answer is queue_wait and the hook's context text carries the skip"
  - mode: "rules read judged against the wrong branch (regression to a literal main)"
    detection: "rows N1-N3 and N6 fail pre-merge in the committed suite, which asserts the exact rules path recorded per request; layer cli-stdout-artifact (committed artifact: plugins/soleur/test/sync-pr-behind.test.sh)"
    alert_route: "CI (test shard) and the work-phase exit gate"
  - mode: "a non-main base reaches the origin/main merge (a per-caller refusal arm removed)"
    detection: "rows N2s, N2w, N2l assert exit 4 / queue_wait / exit 4 per caller and the per-caller mutation rows; the hook rows T-Q23 and T-Q24 assert no merge and no push at the real consumer; layer cli-stdout-artifact (committed artifacts: the two suites)"
    alert_route: "CI (test shard)"
  - mode: "clamp or sanitiser re-forked, or a call site bypasses the helper"
    detection: "sentinel S1 counts each block, each env read and each reader's qb_bounds call, plus per-call-site mutation rows; layer cli-stdout-artifact (committed artifact: the same suite)"
    alert_route: "CI (test shard)"

logs:
  where: "stdout of the invoking Monitor or Bash call; hook output in the session transcript"
  retention: "session transcript lifetime; the committed fixture suites are the durable record of every line's shape"

discoverability_test:
  command: bash plugins/soleur/scripts/sync-pr-behind.sh --help
  expected_output: "baseRefName"
```

Hosted path: no `apps/` file invokes the script (`git grep -n sync-pr-behind -- apps/` is empty), so layers 1-6 have nothing to cover; the only hosted occurrence is the vendored plugin tree being present in the image. The discoverability command reads the committed script text and prints the new field name only after Phase 2 (it prints nothing for `baseRefName` today).

## Guard Contract

### Guard 1 - Base-branch binding of the rules read, and no merge of `origin/main` into a non-`main` base by the guarded callers

**Property.** For an armed BEHIND or UNKNOWN PR, the merge_queue rule is read from the rules endpoint of that PR's own `baseRefName` from every guarded caller, an empty or unsupported base never reaches a rules request (`kind=gh` rc 4 at flagless `--step` and the loop, `queue_wait` at `--queue-wait`), and a validated non-`main` base with no queue rule is never given a sync by flagless `--step`, the standalone loop or the `--queue-wait` verdict.

**Assembly.** `queue_wait_eval` is the one chokepoint for the rules read and has three callers: `step_guard` (flagless `--step`) and the `--queue-wait` mode, both through `qw_probe` and `qw_snapshot`, and `queue_wait_gate` (standalone loop, fed by the widened pre-loop head read via `LOOP_BASEREF`); the `--step --fence` path skips the guard by design and is not a member. The members that must agree: the snapshot `--json` / `--jq` / regex triple and its `read -r` split, the head-read `--jq` and regex, the third argument at the three call sites, the single `rules/branches/` occurrence and its `$4` operand, `qw_base_path` (including its `LC_ALL=C` line), the internal verdicts `foreign` and `badbase`, one `foreign)` arm and one `badbase)` arm per caller (each with its own outcome: exit 4, exit 4, `queue_wait`), and the two message texts that interpolate `QW_BASE`. Order is part of the property: the base is validated only after the OPEN, BEHIND/UNKNOWN and armed checks, so unarmed paths never read it.

**Mutation matrix.**

| # | Mutation (each must drive the suite RED) | Expected |
|---|---|---|
| G1-1 | Replace the base segment of the rules URL with the literal `main` (anchor: the `rules/branches/$4?per_page=100` fragment) | RED - N1s (queue only on `develop`) and N2s (queue only on `main`: exit 14 instead of 4) |
| G1-2 | Own dispatch: pass an empty base at all three callers, so the rules read is never reached | RED - the existing main-based Q1 rows come back `badbase` instead of `kind=queue_wait`, and N1s finds zero recorded rules calls |
| G1-3 | Second member: pass the base at the snapshot callers but the literal `main` at `queue_wait_gate` | RED - N6 (loop, base `develop`) |
| G1-4 | Second member: pass the base at `step_guard` but an empty string in the `--queue-wait` mode | RED - N1w (`--queue-wait` prints `queue_wait`) |
| G1-5 | Drop the `/` to `%2F` encoding (anchor: the `printf '%s' "${b//\//%2F}"` line) | RED - N3a (`release%2F1.x` request) |
| G1-6 | Drop the allowlist (anchor: the full name-regex line) | RED - N4s (an unsupported base reaches a rules request) |
| G1-7 | Reorder: validate the base before the `armed` check | RED - N5b and N5c (a `rel+1` disarmed PR and a CLEAN armed PR with an odd base must make zero rules calls and sync) |
| G1-8 | Remove the `foreign)` arm at `step_guard` only (unique anchor: the `exit 14 ;;` line plus the arm) | RED - N2s (flagless `--step` syncs instead of exit 4) |
| G1-9 | Remove the `foreign)` arm at `queue_wait_gate` only (unique anchor: the `queue_wait 0` line plus the arm) | RED - N2l (the loop syncs instead of exit 4) |
| G1-10 | Remove the `foreign)` arm in the `--queue-wait` mode only (unique anchor: the `echo queue_wait; exit 0` line plus the arm) | RED - N2w (`--queue-wait` prints `proceed` instead of `queue_wait`) |
| G1-11 | Remove the `badbase)` arm in the `--queue-wait` mode (the hook would see rc 4 and fall through to its own merge) | RED - N4w (and hook row T-Q23: the hook must not merge) |
| G1-12 | Swap the head-read `--jq` field order, or drop its `// ""` | RED - N6 (the stub runs the script's own `--jq`, so the base reads wrong) |
| G1-13 | Delete the `LC_ALL=C;` line in `qw_base_path` | RED - N11 (`é` accepted under `en_US.UTF-8`) |
| G1-14 | Parse the armed bit by suffix expansion (`${out##* }`) instead of `read -r` | RED - N12 (a base named `disarmed` reads as the armed bit and the PR proceeds) |
| G1-H1 | Harness: the rules stub ignores the requested branch and applies its mode to any path | RED - N2s (the suite must notice the stub stopped discriminating) |

Must-PASS inputs that differ from the canonical (ordinary rows, not mutants): N3b (`feat/x/y`), N5b (`rel+1` unarmed), N12 (bases named like the armed bit).

**Anchor.** No stored value is compared to the thing it protects. The suite's `PASS -eq N` pin is a count floor and survives an add-one-delete-one substitution, so the mutation rows above (each fails when its targeted behaviour regresses) and the exact-path assertions are the identity check; the pin is bumped deliberately with the new row ids listed in `tasks.md`.

### Guard 2 - Single bounds helper and single sanitiser

**Property.** Each of the three env clamps and the stderr sanitiser exists in exactly one place in `sync-pr-behind.sh`, every reader of `PR_QUEUE_TIMEOUT`, `PR_QUEUE_ATTEMPTS` and `PR_QUEUE_RETRY_SLEEP` goes through them and calls `qb_bounds` itself, and every sanitised `gh` stderr string goes through `qb_clean`.

**Assembly.** Readers: `queue_state_read`, `queue_read_settled`, `queue_wait_eval`, `qw_snapshot` (the chokepoints are `qb_bounds` and `qb_clean`); sanitised strings: `QS_DETAIL`, `detail`, `pvd`. Spellings the census must see: the three env reads (counted with `grep -oF`, whole-line comments and the `USAGE` heredoc, which names the env vars in prose, stripped; `$X` and `${X-` spellings included), the `tr -c` set spelled exactly, and one `qb_bounds` call per consumer function (a call that relied on an earlier reader's global is unobservable to any behavioural row, because the environment is constant within a process, so the count is the only pin). A bypass is a new reader that skips the helper, so the per-call-site mutation rows (not the counts alone) prove each site still reaches the helper.

**Mutation matrix.**

| # | Mutation (each must drive the suite RED) | Expected |
|---|---|---|
| G2-1 | Paste an inline copy of the three env reads back into `queue_wait_eval` | RED - S1 counts 2 instead of 1 |
| G2-2 | Own dispatch: run S1's counting function against an empty file | RED - it must report failure (a count of 0 is not 1) |
| G2-3 | Second member: add a fourth function that reads `${PR_QUEUE_TIMEOUT:-10}` directly | RED - S1 sees 2 timeout reads |
| G2-4 | Delete `\| qb_clean` at the `queue_state_read` site (anchor: the `QS_DETAIL="$(printf ...` line) | RED - the queue-read ctl row (ESC byte and forged tag reach stdout) |
| G2-5 | Delete `\| qb_clean` at the `queue_wait_eval` site (anchor: the `detail="$(printf '%s' "$detail" ...` line) | RED - R5 ctl |
| G2-6 | Delete `\| qb_clean` at the `qw_snapshot` site (anchor: the `pvd="$(printf ...` line) | RED - the pr view ctl rows (F5, W3) |
| G2-7 | Delete the `qb_bounds` call from `queue_wait_eval` (or from `qw_snapshot`) | RED - S1's per-function call count (and `set -u` aborts the `--queue-wait` path for the snapshot variant) |
| G2-8 | `queue_read_settled` reads the raw env nap instead of `QB_NAP` | RED - C7 (`PR_QUEUE_RETRY_SLEEP=abc` must log sleep 2) |
| G2-H2 | Harness: a non-recording `timeout` shim (execs without logging) | RED - the timeout characterization rows report no calls |

Must-PASS input differing from the canonical (ordinary rows): `PR_QUEUE_TIMEOUT=7` and `PR_QUEUE_ATTEMPTS=3` pass through unclamped (C1, C2).

**Anchor.** Same as Guard 1: count floors are paired with per-site mutation rows, so a deleted site cannot be replaced by an unrelated green row.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "stop hard-coding main in queue_wait_eval's `repos/$o/$r/rules/branches/main` read" | Phase 2.1 (`queue_wait_eval` base argument, `$4` path operand), sentinel S2 | mapped |
| 2 | "make qw_snapshot also read baseRefName (its strict answer regex and every mock in the test suite change with it)" | Phase 2.1 snapshot; Phase 0.1 and 0.7 mock widening | mapped |
| 3 | "judge the PR against its own base branch's rules" | Phase 2.1 (all three callers incl. the loop head read); rows N1-N6 | mapped |
| 4 | "replace the three copies of the PR_QUEUE_TIMEOUT / PR_QUEUE_ATTEMPTS / PR_QUEUE_RETRY_SLEEP clamping block and the `tr -c '[:alnum:] ._:/=-' '?'` sanitiser (in queue_state_read, queue_wait_eval, qw_snapshot) with one helper" | Phase 1.1 (`qb_bounds`, `qb_clean`); Guard 2 | mapped |
| 5 | "Behaviour must stay identical for main-based PRs" | Phase 0.3 characterization, 0.5b N7a and N7b golden texts, existing Q1 rows asserting the `main` request string | mapped |
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
| Standalone-loop head-read widening (`LOOP_BASEREF`) | "judge the PR against its own base branch's rules" | inferred - justification: `queue_wait_eval` has a third caller, the standalone loop, with no snapshot; without a base source it would keep judging against `main`, leaving the ask unmet for that caller (CTO F1) |
| `qw_base_path` allowlist, length cap and `%2F` encoding | "judge the PR against its own base branch's rules" | inferred - justification: a branch name is untrusted text interpolated into an API path and echoed to a model-visible line; the existing fail-closed contract requires an unknown answer not to become a yes (CTO F3) |
| Interim non-`main` refusal at the three guarded callers (`foreign` verdict) | "Behaviour must stay identical for main-based PRs" | inferred - justification: the requested base-aware read turns a safe refusal into the existing `origin/main` merge for an armed non-`main` PR (flagless `--step`, the loop and the hook's `--queue-wait`); delivering ask 3 safely needs the guard, and the CTO ruled it part of the change, not a scope addition (CTO F7) |
| `badbase` verdict and the `--queue-wait` answer `queue_wait` for it | "judge the PR against its own base branch's rules" | inferred - justification: the hook treats any non-zero exit as "sync anyway", so an unusable base returning `kind=gh` rc 4 would reopen the wrong merge through the hook; found independently by the architecture and spec-flow passes |
| `qw_probe` folding the snapshot-plus-eval pair | "make qw_snapshot also read baseRefName" | inferred - justification: the pair appears at two sites and a forgotten base argument at one is the bug class; one function passes it once |
| `QW_BASE` in `qw_refusal` / `qw_unreadable` texts | "Behaviour must stay identical for main-based PRs" | inferred - justification: without it a refusal for another base would say `main` and mislead the next action; byte-identical for `main` (CTO F6) |
| Each reader calling `qb_bounds` itself, and `queue_read_settled` using the helper | "replace the three copies" | inferred - justification: the nap clamp has a fourth copy there, and a reader relying on another's call aborts under `set -u` on the `--queue-wait` path |
| Request-shape-compatible edits to `.claude/hooks/pre-merge-rebase.test.sh`, `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`, `plugins/soleur/scripts/sync-pr-behind.test.sh` | "every mock in the test suite change with it" | inferred - justification: the strict answer regex change reds every other mock of the snapshot and the exact-argument head-read stub; the contract rots otherwise |
| Two new hook-suite cases T-Q23 and T-Q24 | "tests first (cq-write-failing-tests-before), including a non-main-base case" | inferred - justification: the hook is the one real consumer of `--queue-wait` and the only caller that merges `origin/main` after `proceed`; the guarantee is a property of the hook's behaviour, not of the script's stdout |
| Characterization rows and recording `timeout`/`sleep` shims | "Behaviour must stay identical for main-based PRs" | asked |
| Sentinel rows S1 and S2 | "replace the three copies ... with one helper" | inferred - justification: a refactor with no drift guard re-forks silently, which is the defect this issue exists to remove |
| Mutation rows over the helper call sites, the base binding and the refusals | "tests first (cq-write-failing-tests-before)" | inferred - justification: the suite's mutation rows are literal anchors over the SUT text, two of which this change rewrites, and an unmutated helper or refusal leaves its call sites unpinned |
| Header, `--help`, comment, hook-comment and `queue-mode.md` wording edits | "stop hard-coding main" | inferred - justification: the script's `--help` and header state the main-only base and the suite pins other `--help` substrings; stale docs contradict the code |
| ADR-270 addendum | "Merge Queue epic #9454 (ADR-270)" | inferred - justification: the ADR records "the base is `main`" as an accepted residual; recorded architecture must not lag the change, and the interim refusal extends residual (2) |
| Tracking issue for the Non-Goal surfaces | "Ref only" | inferred - justification: the deferral rule requires an issue for each deferred item; it carries the fence-expiry exposure and the hook wording the CTO and reviewers named, and must be linked before merge (CTO F7) |

### Split Assessment

- Subsystems touched: 3 - `plugins/soleur`, `.claude`, `knowledge-base`
- Planned files: 8 edited + 3 created (plan, tasks, decision-challenges) = 11 | Estimated changed lines: about 650 (script +130/-60, main suite +400, other suites +60, docs +25)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Pre-merge (PR)

- [ ] Tests first: the branch history shows the test-only commit before the script commit (`git log --format=%s origin/main..HEAD`), and the PR notes list the row names that were RED against the unchanged script on a behavioural message, separately from the green-before guard rows and from "anchor absent" non-evidence.
- [ ] `bash plugins/soleur/test/sync-pr-behind.test.sh` ends `=== <N> passed, 0 failed ===` with the `PASS -eq` pin updated to N, N = 172 plus the new rows (computed from the row ids in `tasks.md`, not copied from the run).
- [ ] `bash plugins/soleur/scripts/sync-pr-behind.test.sh` ends `all 10 assertions passed`; `bash .claude/hooks/pre-merge-rebase.test.sh` passes with `EXPECTED_CASES=79`; `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` and `bash plugins/soleur/test/monitor-pr-checks.test.sh` pass with `MIN_VERDICTS=1123` unchanged; `bun test plugins/soleur/test/pr-merge-poll.test.ts plugins/soleur/test/workflow-fidelity.test.ts` passes.
- [ ] Main-based behaviour identical: the existing Q1 rows still assert `repos/o/r/rules/branches/main?per_page=100` and `repos/{owner}/{repo}/rules/branches/main?per_page=100`; N7a and N7b assert the `main` refusal and unreadable texts equal the golden literals captured from the pre-change script.
- [ ] Non-main base: N1s, N3a, N3b and N6 pass with the exact recorded request path for `develop`, `release%2F1.x` and `feat%2Fx%2Fy`; N2s, N2w, N2l and N2u show exit 4 / `queue_wait` / exit 4 / exit 4 with nothing fetched, merged or pushed; N4s, N4w and N4l cover the unsupported-base table with the cause asserted; N5a-N5d show disarmed, CLEAN and DIRTY non-`main` PRs still sync as today; N9 shows `--step --fence` skips the guard; N10 shows a queued foreign PR makes zero rules calls; hook rows T-Q23 and T-Q24 show the hook skips its sync and neither merges nor pushes.
- [ ] One helper: S1 reports exactly 1 sanitiser, 1 read of each env variable and one `qb_bounds` call in each of the four readers, and its counting function fails when pointed at an empty file; S2 reports 0 `rules/branches/main` literals and 1 `rules/branches/`.
- [ ] `shellcheck -x plugins/soleur/scripts/sync-pr-behind.sh` prints nothing; `grep -v '^[[:space:]]*#' plugins/soleur/scripts/sync-pr-behind.sh | grep -cE 'mapfile|readarray|declare -A|\$\{[A-Za-z_]+(,,|\^\^)'` prints `0`.
- [ ] `--help` still passes the suite's pinned substrings (listed in Proposed Solution) and now names `baseRefName` (`bash plugins/soleur/scripts/sync-pr-behind.sh --help | grep -c baseRefName` prints at least 1).
- [ ] Out of scope untouched, diffed against the merge base: `git diff --stat origin/main...HEAD -- scripts/lib/test-affected-paths.sh scripts/suite-durations.tsv scripts/suite-durations.tsv.n scripts/suite-shard-legs.tsv scripts/suite-shard-legs.tsv.n .claude/rule-weakening-acks.txt AGENTS.rules.md AGENTS.md` prints nothing. The files this PR may write are the Files-to-Edit list plus `knowledge-base/project/plans/`, `knowledge-base/project/specs/feat-one-shot-10832-sync-pr-behind-base-and-helpers/` (including a generated `session-state.md`) and the generated `knowledge-base/INDEX.md` cache if tracked.
- [ ] PR body references `Ref #9454` and `Ref #10832` with no closing keyword: `grep -ciE '(close[sd]?|fix(e[sd])?|resolve[sd]?) #(9454|10832)'` over the body prints `0`; the title carries no issue number with a closing keyword; the body names the interim non-`main` refusal as a deliberate narrowing and states its scope (armed BEHIND or UNKNOWN only; not the fences).
- [ ] The tracking issue for the Non-Goal surfaces exists (`gh issue view <N> --json state` reads `OPEN`) and is linked in the ADR-270 addendum; the addendum carries the closure and residual notes; `markdownlint-cli2` is clean on the plan, `tasks.md` and the ADR change; `technical-ruling-gate.sh --branch feat-one-shot-10832-sync-pr-behind-base-and-helpers` passes.

### Post-merge (agent, after merge verification)

- [ ] Merge goes through the queue with `bash plugins/soleur/scripts/session-state.sh with_lock merge-main ... -- gh pr merge ... --squash --auto` (the ship phase owns the exact form). Automation: `gh` CLI via the ship skill, no operator step.
- [ ] After MERGED, verify on `main` that `git grep -c 'rules/branches/main' origin/main -- plugins/soleur/scripts/sync-pr-behind.sh` prints `0`, then close #10832 by hand with an evidence comment (`gh issue close 10832`); `gh issue view 9454 --json state` still reads `OPEN`; #9482, #10245 and #5840 are not touched. Automation: `gh` CLI, executed by the agent (the brief orders closing by hand, after verification, never by closing keyword).

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Two CTO rulings (see `decision-challenges.md`). First batch (F1-F6): widen the loop's existing head read for the base, one bounds helper plus one stdin sanitiser (not the timeout wrapper or repo parse), a conservative base allowlist with `/` to `%2F`, snapshot answer `<STATE> <MERGESTATE> <armed|disarmed> <base>` with a loose base token and validation only inside `queue_wait_eval`, fences and the shared merge path out of scope, and `QW_BASE` in the message texts. Second ruling (F7, after three plan reviewers independently found the regression): add an interim refusal for a non-`main` base at flagless `--step`, the standalone loop and `--queue-wait`, part of delivering the requested change safely, not a scope addition; refined at deepen-plan into internal `foreign` and `badbase` verdicts with per-caller arms. No other domain is relevant (no user-facing surface, legal, marketing, finance, sales or support impact).

## Test Scenarios

All rows are `unit`-layer shell suites by the repository's classification (real git fixtures with PATH-shimmed `gh`, `git`, and in the characterization fixtures `timeout` and `sleep`; no network, no service boot). Key given/when/then forms:

- Given an armed BEHIND PR whose base is `develop` and a queue rule only on `develop`, when flagless `--step` runs, then it exits 14 with `kind=queue_wait`, one `pr view`, one rules read of `repos/o/r/rules/branches/develop?per_page=100`, nothing fetched, merged or pushed; `--queue-wait` prints `queue_wait`.
- Given the same PR but the queue rule only on `main`, when flagless `--step` or the standalone loop runs, then it exits 4 `kind=gh` with the non-`main` refusal and nothing moves; `--queue-wait` prints exactly one line `queue_wait`, and the pre-merge hook skips its sync.
- Given base `release/1.x` or `feat/x/y`, then the recorded request is `.../rules/branches/release%2F1.x?per_page=100` or `feat%2Fx%2Fy`.
- Given an armed BEHIND PR with an unsupported base (`feat%2Fx`, `a?b`, `a..b`, `x.lock`, `a.lock/b`, `a//b`, `a/./b`, `a/`, `-x`, `rel+1`, `a@b`, `{branch}`, an ESC-bearing, over-60 and over-255 name, or empty), then flagless `--step` and the loop answer `kind=gh rc=4` with the cause named, zero rules calls and nothing moved, and `--queue-wait` answers `queue_wait`.
- Given a legal base named `armed` or `disarmed` on an armed PR, then the armed bit is still read from its own token.
- Given a disarmed PR with base `develop` or `rel+1`, or a CLEAN armed PR with an odd base, then it syncs as today with zero rules calls; given a DIRTY non-`main` PR, it still syncs `origin/main` (pinned as known-wrong).
- Given `--step --fence` on a foreign base, then the guard is skipped and it syncs (the documented bypass); given a queued foreign PR, then `kind=queued` with zero rules calls.
- Given the standalone loop with head read `feat develop`, armed BEHIND, queue on `develop`, then `kind=queue_wait rc=0`, also on a second attempt.
- Given a `main`-based PR, then every request string, refusal text and exit code equals the pre-change value (golden literals).
- Given `PR_QUEUE_TIMEOUT`, `PR_QUEUE_ATTEMPTS`, `PR_QUEUE_RETRY_SLEEP` set to a table of valid, boundary and invalid values, then each parameter is clamped identically and each site reaches the helper (logged `timeout`/`sleep` arguments and call counts).

Regression scenarios: every pre-existing row (172) stays green throughout Phases 0-2. Properties that must never break: (1) no rules request is ever made with a base outside the allowlist; (2) no path reads the base before the armed check; (3) the `main` request string is byte-identical; (4) a validated non-`main` base with no queue rule is never synced by a guarded caller after the armed BEHIND or UNKNOWN check.

## Success Metrics

The two residuals in #10832 are closed with the suites as the durable proof; a later non-main-base PR armed on a queue repo is judged against its own base (observable: the `kind=queue_wait` line or the explicit non-`main` refusal, with the base named in the text).

## Dependencies & Risks

- **Pin and anchor churn**: the `PASS -eq 172` pin, `EXPECTED_CASES` and two literal mutation anchors move with this change; mitigated by writing the prescribed source shape into the plan so tests and code agree, unique-fragment anchors, an authoritative id inventory in `tasks.md`, and running the unmutated control first.
- **Mock drift across four suites**: mitigated by request-shape-compatible widening (RED keeps pre-existing rows green) and by running all suites in Phase 2.2.
- **Recording shims vs hang stubs**: a `sleep` shim would neutralise the hang stubs; confined to characterization fixtures (Phase 0.2).
- **Fail-closed tightening**: an unusual legal base on an armed BEHIND PR now reads `kind=gh rc=4` (or `queue_wait` at the hook) instead of being judged against `main`, and a non-`main` base with no queue rule is refused instead of synced (CTO F3, F7); the allowlist covers every base this repo uses and each failure names its cause. 299 of the last 300 PRs are `main`-based; customer repos with another default branch get a clear refusal instead of a `fetch` failure.
- **Real `gh` shape**: `baseRefName` is a documented `gh pr view --json` field and was read live (`main`); the `// ""` guard turns a hypothetical null into the same fail-closed arm.
- **Fence vs script disagreement** on a non-main base (fence reads `main`, flagless callers read the base): documented in Non-Goals and the ADR addendum; the fence's `--fence` path skips the guard by design and its expiry arm remains the live exposure, named in the tracking issue.
- **Run time**: 59 new rows (7 characterization, 2 sentinel, 16 RED base rows, 9 green-before guard rows, 25 mutation, harness and control rows; fixtures shared through runtime stub files) plus 2 hook cases raise the 64 s suite by roughly a minute and the pin to 231; no shard manifest is touched; the exact ids are in `tasks.md`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it (threshold `none`).
- The new rows' anchors are literal lines of the post-Phase-2 script; the plan therefore prescribes those lines. If the implementer changes a prescribed line, the matching mutant reports "anchor absent" (a red row, never a silent pass, but not RED evidence) and must be re-pointed in the same commit. Each anchor must occur exactly once in the script (the `qw_mutant` uniqueness check), so avoid fragments like the repeated `--json` list, `|| exit 1`, or an identical `foreign)` arm; anchor each per-caller arm on the unique line before it. The `badbase` detail must not start with `QW_VERDICT=unreadable; QW_DETAIL="rule read failed after` (an existing anchor).
- Parse the snapshot with `read -r st ms am base` only. A suffix or prefix expansion on that string reads a base named `disarmed` as the armed bit and fails open.
- `install_gh_wait`'s `ok:<STATE MERGESTATE>:<armed|disarmed>` split is `IFS=: read -r _ st arm`; do not append a base field to that token (it would land in `$arm`). The base comes from the runtime `pr-base` file. In the hook suite the split is `read -r st mm arm` and must become `read -r st mm arm base`.
- The recording `sleep` / `timeout` shims belong only in characterization fixtures; the `exec sleep N` hang stubs resolve `sleep` through PATH. The suite exports `PR_QUEUE_RETRY_SLEEP=0`: the default-nap case needs `env -u`, and `PR_QUEUE_REPO=o/r` is exported only between l.1135 and l.1634, so rows asserting `repos/o/r/...` must sit in that window.
- `.claude/hooks/pre-merge-rebase.test.sh` and `plugins/soleur/test/monitor-pr-checks.test.sh` are not selected by a script-only diff (read from `scripts/test-all.sh`); this PR edits the hook suite so it is selected, but run both explicitly regardless. Do not edit `scripts/lib/test-affected-paths.sh` to "fix" that (out of scope).
- Sentinel counts must be exact (`== N`), computed with comments and the `USAGE` heredoc stripped, using `grep -oF ... | tr -d ' '` with `|| true`; never a negated `grep -q`, never `|| echo 0` (two lines under `pipefail`).
- `qw_base_path` rejects `%` outright (it is outside the class): percent-encoding is applied exactly once, by the helper. `LC_ALL=C` in the validator and in `qb_clean` is load-bearing (`[A-Za-z]` accepts `é` in `en_US.UTF-8`; BSD `tr` is locale-aware); N11 pins the first, bash 3.2 was not available to run.
- The `--queue-wait` and flagless `--step` paths must still make exactly one `pr view` and one rules read (rows F1 and W1-W4 assert it); a helper that adds a `gh` call breaks them.
- The standalone loop resolves its base once. Say so in a code comment; do not "fix" it with a per-attempt read (CTO F1).
- The interim refusal must not run in `--fence` or `sync_step`; a forgotten caller arm falls through to `proceed`, so the per-caller mutation rows are the pin. `step_guard` needs its explicit `return 0`.
- The edited `queue-mode.md` sentence must not contain `--fence` or `sync-pr-behind.sh <PR> --step`: `pr-merge-poll.test.ts` censuses both across every `.md` under `plugins/soleur`.
- Do not touch `AGENTS.rules.md` or `.claude/rule-weakening-acks.txt`: `workflow-fidelity.test.ts` and the rule-body hashes pin that text, and the brief puts it out of scope.
- The `decision-challenges.md` table is machine-gated (`Ruled by CTO agent, <date>:` prefix, no literal pipe in a row, exact three-column header); append rulings inside the table only.

## References and Research

- Issue #10832; epic #9454; ADR-270 (`knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`, lines 724 and 755); PR #10655 (armed-BEHIND refusal in `--step` and the hook).
- `plugins/soleur/scripts/sync-pr-behind.sh`, `plugins/soleur/test/sync-pr-behind.test.sh`, `plugins/soleur/scripts/sync-pr-behind.test.sh`, `.claude/hooks/pre-merge-rebase.sh` and its test, `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`, `plugins/soleur/scripts/admin-merge-ready.sh` (encoding precedent), `plugins/soleur/skills/ship/references/queue-mode.md`.
- Decision record: `knowledge-base/project/specs/feat-one-shot-10832-sync-pr-behind-base-and-helpers/decision-challenges.md`.
