---
date: 2026-08-10
issue: "#7394"
pr: 7407
category: workflow-patterns
module: git-worktree
tags: [mutation-testing, review-findings, probes, measurement, vacuity]
---

# The fix for a blind spot was as unpinned as the blind spot

## Problem

`ensure_bare_config` was dead code on the operator's bare-repo-in-`.git` layout: its guard
branched on the gitdir's SHAPE (`.git` is a directory), which is true of that layout too. So
`extensions.worktreeConfig` was never removed, every linked worktree inherited
`core.bare = true`, and git reported valid worktrees as bare — the mechanism behind #7332,
where all 14 worktrees wedged mid-rebase.

The implementation reversed the polarity and shipped with 44 green assertions, a green
280/280 full suite, clean `tsc`, and a non-vacuity check (the suite still failed 16
assertions against the pre-fix script). It looked done. A 13-agent review then found a
data-destruction path, a migration gap that missed the entire installed base, and eight
fail-opens — most introduced by the fix.

## Solution

### 1. A whole-file revert is ONE mutation axis, and it is the axis you authored against

"Run the new suite against the old script — it still fails 16" feels like proof of
non-vacuity. It is not. It proves the suite notices *the change as a whole*; it says nothing
about whether any INDIVIDUAL behaviour is pinned. Mutating behaviours one at a time on a
sandbox copy found that two of the highest-severity fixes could be reverted with the suite
**fully green**:

- the `IS_BARE` downgrade (the data-destruction path), and
- the symlinked-`config.worktree` guard.

The generalisation: **the fix for a blind spot is exactly as unpinned as the blind spot
was**, because the fix is written after the tests and nothing forces a fixture for it. When
review hands you findings, each fix needs its own must-FIRE fixture in the same commit —
and the way to know is to mutate the fix back out and confirm the suite reddens.

### 2. Some fixes cannot be pinned behaviourally — say so instead of implying coverage

Two fixes only manifest when `git rev-parse --is-bare-repository` DEGRADES (the char-device
config mask). That state is not portably synthesizable, and a naive fixture actively hides
it: in the fixture where the heal succeeds, the re-probe also succeeds, so the downgrade is
invisible. The honest instrument was a structural assertion over the extracted function body
— anchored on the assignment syntax so a comment mentioning `IS_BARE=false` cannot satisfy
it — with the limitation stated in the test rather than left implied.

First attempt at that structural pin was itself a false positive: the pattern matched the
`git -C "$common_dir" rev-parse …` re-derivation line a few lines below. A structural pin
needs the same "name the mutation that satisfies this while violating the property"
discipline as any other assertion.

### 3. A review finding can be a regression — implement it, MEASURE it, and revert with the reason recorded

`security-sentinel` correctly identified that a genuinely-bare repo under the config mask
now takes the benign skip branch instead of the `bare-fail` wedge. The proposed fix —
consult `git rev-parse --is-bare-repository` and fail loud when it says bare — was
implemented and immediately broke the sibling suite's Test 24.

Why: under that exact degradation `GIT_ROOT` is the RELATIVE string `.git`, and
`git -C .git rev-parse --is-bare-repository` returns **true** for ANY normal clone, because
a `.git` directory looks bare from the inside. Escalating on it re-opens the #5934 D3 wedge
on the production Concierge surface — the twice-fixed one.

The resolution was to report the ambiguity (`reason=masked-cannot-determine`) without
changing control flow, and to record the declined finding *in the code and the ADR*, not
just in a PR comment. A finding from a strong agent is a hypothesis with evidence attached,
not an instruction.

### 4. Ad-hoc probes are less reliable than the committed suite

Three throwaway probes returned wrong answers in one session:

- a sourced-script probe exited before defining the function (`rc=127`) and I read the
  silence as a result;
- a `create_worktree` probe never reached `ensure_bare_config` (it bailed earlier), so
  "0 markers" meant nothing;
- the same probe shape returned 0 twice for a marker my own Case 11 asserts and passes.

Each time, the committed suite already had the answer. **When a quick probe disagrees with a
passing test, the test is the better instrument** — and a probe with no positive control is
not a measurement. The one probe that DID hold up was the one with a control arm (the
`--type=bool` normalization check: `no extension → false`, `+ extension → true`).

### 5. A guard's own explanatory comment can regress an absence-assertion — twice

`AC8a` asserts the inverted sentence "linked worktrees inherit" is GONE from the script. It
regressed twice: first because the rewrite QUOTED the retired claim to refute it, then
because a later comment used the same phrase in a new sentence. A presence-grep cannot tell
quoting-to-refute from asserting. When a task requires both "assert X is absent" and
"document why X was wrong", they collide by construction — paraphrase the retired claim
rather than quoting it.

## Key Insight

Every defect this session reduces to one shape: **a check that certified something other
than what it claimed.** The non-vacuity check certified "the change as a whole is noticed",
not "each behaviour is pinned". The probes certified "a command ran", not "the SUT reached
the code path". The absence-grep certified "the string is gone", not "the claim is retired".
The review finding certified "this state is unobservable", not "escalating is safe".

The discriminator that works, in every case, is to name the mutation — the input, the edit,
the state — that would satisfy the check while violating the property. If you cannot name
one, the check is stronger than it looks. If you can, it is a comment.

## Session Errors

- **Asserted a config key's presence from an ambiguous multi-command probe.** Three `git
  config` calls printed two lines; I attributed the second `true` to the wrong key and told
  the planning subagent the extension was present. It is absent, which is why `draft-pr`
  succeeded at Step 0c. — **Prevention:** label each probe's output (`echo "ext: $(...)"`),
  never infer which command produced which line by position.
- **Three ad-hoc probes returned wrong answers** (see §4). — **Prevention:** give every probe
  a positive control, and prefer the committed suite when the two disagree.
- **The F1 fix reintroduced the #5934 D3 wedge.** — **Prevention:** before acting on a
  finding that adds a `rev-parse` call, check whether the surrounding code deliberately
  avoids that call; this file's own comments said why.
- **Two of my own fixes were unpinned** (see §1). — **Prevention:** mutate each fix back out
  before committing; a fix with no failing fixture is a comment.
- **`AC8a` regressed twice from my own prose** (see §5). — **Prevention:** re-run the AC's
  literal command after every comment edit in the same file.
- **A commit message claimed 83/0 where the measurement was 82/0**, and the PR body kept
  `39 / 0` and `16` after the suite grew to 44. — **Prevention:** re-derive every count from
  the artifact at write time; the counts moved twice in one session.
- **`MIN_ASSERTIONS` was guessed twice (63, then 66) instead of derived.** Both times the
  floor itself caught the error, which is the floor working correctly. — **Prevention:**
  set the floor from a green run's printed total, never from a mental tally.
- **The structural re-probe pin was a false positive** matching a sibling line. —
  **Prevention:** apply the name-the-satisfying-mutation test to structural assertions too.
- **Wrote a heredoc issue body in the same Bash call as a hook-gated `gh issue create`.** The
  hook denied the whole call, so the heredoc never ran and the retry failed `no such file`.
  This is documented in `work/SKILL.md` and I hit it anyway. — **Prevention:** the Write tool
  for the body, then `gh issue create --body-file` as its own call.
- **Killed my own baseline full-suite run** after finding `/tmp` at 97% with two sibling
  sessions. Correct call (the documented false-RED condition), but it cost a launch. —
  **Prevention:** check `df /tmp` and sibling `test-all.sh` owners BEFORE launching.
- **Mutation-harness bugs**: literal `\n` in a shell-passed replacement string, and anchors
  that matched 0 or 2 sites. — **Prevention:** assert the mutation LANDED (`diff -q` against
  a pristine backup) and treat baseline-identical as UN-RUN, never as a survivor.
- **Case 19's expected vocabulary missed the `branch=$_branch` indirection**, and Case 18
  used the wrong `create_for_feature` argument. — **Prevention:** derive an expected set from
  the emitter with every emission shape it can take, not just the literal one.
- Forwarded from `session-state.md`: an untracked 715-line plan from an aborted prior run was
  validated and updated in place rather than duplicated; two of its facts were falsified.

## Related

- [ADR-173 — bare config polarity for linked worktrees](../../engineering/architecture/decisions/ADR-173-bare-config-polarity-for-linked-worktrees.md)
- [ADR-099 — git surface topology](../../engineering/architecture/decisions/ADR-099-git-surface-topology.md)
- `2026-08-09-one-shared-config-key-took-all-fourteen-worktrees-down-mid-rebase.md` (#7332 — the incident this defect caused)
- #7411 — deferred: shrink `ensure_bare_config` to what the measurements leave load-bearing
