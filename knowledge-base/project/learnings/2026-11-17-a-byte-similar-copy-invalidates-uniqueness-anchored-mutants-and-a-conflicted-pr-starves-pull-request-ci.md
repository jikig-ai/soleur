# Learning: a byte-similar copy invalidates uniqueness-anchored mutants — and a conflicted PR starves `pull_request` CI silently

## Problem

#9294 added a second (narrow) arm to `.github/actions/infra-credentials/action.yml`,
deliberately kept byte-similar to the broad arm (copy-parity is the pinned export
mechanism). Two downstream failures surfaced late in the pipeline, both classes that
will recur whenever guarded code is duplicated by design:

1. **Mutation-anchor non-uniqueness.** `git-data-wipe-access.test.sh`'s
   `g1-10-mask-blob` mutant does a literal `seg.count(old) == 1` check before
   replacing `while IFS= read -r line; do` with `for line in $payload; do`.
   The byte-similar narrow arm added a second identical line, so the mutator
   refused to apply — `mutator: '...' matched 2 times, wanted 1` — and the
   deploy-script-tests leg went red. The mutant's intent (prove the census reds
   a neutered mask loop) was still reachable; only the anchor was ambiguous.
   Sibling risk inverted: had the mutator silently matched *both*, the WANT
   diff-line count would have failed instead. Either direction, one copied block
   breaks a uniqueness-anchored mutant it never named.

2. **`pull_request` workflows never dispatch on a conflicted PR.** After main
   moved (ENV_SECRETS list, G1k guard), the PR went `mergeable: CONFLICTING`.
   GitHub runs `pull_request` workflows against the merge ref
   (`refs/pull/N/merge`); with no mergeable commit there is **no run record at
   all** — not a skip, not a failure, just absence. `pull_request_target`
   workflows (CLA, cla-evidence) kept running because they target the base ref,
   which made the absence look like a dispatch delay or an Actions outage.
   Diagnosing by polling `gh run list` finds nothing; `gh pr view --json
   mergeable` names it in one call.

3. Compounding minor: `-target=` lines in `apply-web-platform-infra.yml` are
   load-bearing (terraform-target-parity), but the file sits ~44 B under the
   490,000-byte gate; the four additions landed it 206 B over. The fix is the
   gate's own prescription: relocate narrative comment prose to
   `apply-web-platform-infra-job-rationale.md` under the existing
   `## Comment prose relocated from the apply step` heading — the
   `§`-pointer↔`##`-heading parity test in `workflow-file-size.test.ts` counts
   pointers and headings both ways, so appending *under an existing* heading
   keeps parity where a new heading would need a new pointer.

## Solution

- Re-anchored each mask loop by its distinguishing context: the broad arm's
  `while` line sits at 8-space indent, the narrow arm's copy at 10-space, so
  `"\n        while IFS= read -r line; do"` / `"\n          while IFS= read -r
  line; do"` are each count-1. Added `g1-10b-narrow-mask-blob` as the twin
  mutant — a copied guarded block is a *new bypass path* and needs its own
  mutant, not just a repaired anchor. `MUTANT_FLOOR` 184 → 185; suite 633/0.
- Resolved the conflict (union of both `ENV_SECRETS` additions — main's
  `DOPPLER_TOKEN_INNGEST_CUTOVER_WRITE` comment block plus
  `DOPPLER_TOKEN_DEPLOY_CHANNEL`), bumped `FLOOR` to the merged measurement
  (459 + G1k = 460), pushed; `pull_request` workflows dispatched normally on
  the merge head.
- Moved the transport-grouping prose to the runbook; merged workflow measures
  489,515 B.

## Prevention

- **When a PR copies a guarded block byte-similar, grep the mutation batteries
  for anchors inside the copied region** (`git grep -n 'while IFS= read -r
  line' apps/web-platform/infra/*.test.sh` would have found `g1-10` before CI
  did). Anchors keyed on unique context (indent width, a comment, an adjacent
  literal) survive copies; bare-line anchors do not.
- **Each new copy of a guarded block wants a twin mutant.** The mutation floor
  is exact-count, so adding the twin is a deliberate act anyway — do it in the
  same change that adds the copy, not in a CI fix round.
- **When PR CI appears absent (not red), check `mergeable` first.** A
  conflicted PR produces zero `pull_request` runs and zero check entries;
  `pull_request_target` runs still appear, which is the tell. Merge/rebase
  before spending time polling.
- **Files near a size gate need a budget check before adding required lines**:
  `wc -c` the file plus the merged-delta before commit when touching
  `apply-web-platform-infra.yml`; the runbook-relocation home already exists.

## Session Errors

- `pgrep -f` and a broad `ps | awk` probe self-matched the Bash wrapper and were
  rejected by guardrails. **Prevention:** use `scripts/lib/proc.sh` `list_runs`
  or captured PIDs for process inspection; never pattern-match a command line
  that contains your own probe text.
- Invoked `scripts/test-all.sh` directly → `Permission denied` (the runner is
  not executable; `bash scripts/test-all.sh` is the call). **Prevention:** the
  convention is now in session-state; check `test -x` or read the shebang
  before running repo scripts.
- A hand-rolled `sleep`-and-poll loop for the affected-gate log was malformed
  and had to be killed. **Prevention:** poll bounded artifacts (`tail`,
  `grep -c`, scratch-dir listing) directly rather than wrapping them in shell
  loops; or use the `monitor` pattern the repo provides.
- `gh issue create` for the c4-render environmental failure was rejected twice
  (missing `--milestone`, then missing the machinery/user-impact/mandate exit
  fields). **Prevention:** the machinery-issue template's required fields are
  `meta/machinery` label + a stated user-impact/mandate exit; read a recent
  machinery issue's shape before filing.
- The first `--affected` gate run died with the session (parent-death
  watchdog). **Prevention:** relaunch long gates with
  `SOLEUR_TEST_ALL_ALLOW_ORPHAN=1` when the run must outlive the session.
