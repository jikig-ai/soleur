---
title: The local gate defaults to the affected set plus always-on ratchets; the full battery is CI or explicit --full
status: active
date: 2026-09-18
amends: ADR-181, ADR-183, ADR-196, ADR-133
related_adrs: [ADR-181, ADR-183, ADR-196, ADR-133, ADR-177]
amended_by:
  - "#9173 (2026-09-29) — the diff-source scope axis (`--affected-scope=staged`) and the scope-aware `runner-changed` arm; see ## Amendment — 2026-09-29"
  - "#9307 (2026-09-30) — anchored edge matching, the runner-subcommand skip, `--print-selection` / `--paths`, and the evidence-based always-on audit; see ## Amendment — 2026-09-30"
---

# ADR-242: `test-all.sh` — the local gate defaults to the affected set plus always-on ratchets (#8322)

## Context

The local `test-all.sh` invocation ran the full battery unconditionally — ~46
minutes serial, measured. Three observations made the cost wrong, not merely
high:

- **The full battery finds nothing that the affected surface misses.** The
  #8270/#8231 review session produced 24 findings, 8 of them P1 — every one
  from affected suites, the always-on ratchets, review agents, or direct
  probes. The full battery produced zero findings.
- **The full battery is the contended resource.** Over roughly three hours the
  #8270 gate was refused twice (`rc=4`, `CAPACITY_CONTENDED
  reason=sibling_runs`) and expired once at its watcher cap, because five
  sibling worktrees were each attempting their own full gate on the same
  host. The affected set still carries the ~130 always-on ratchets (~22.5
  minutes on the measured `feat-one-shot-8231` serial baseline), so the win
  is roughly half the wall time plus exemption from the contention refusals —
  it is the narrow gate, not an opportunistic second battery.
- **Selection machinery already existed.** `scripts/lib/test-affected-paths.sh`
  did not; but the runner already computed the diff (`_diff_names`,
  `_diff_detect_ok`), already relevance-gated five suites via
  `test-relevance-paths.sh`'s `*_PATHS` arrays, and already had decline
  accounting (ADR-181). What was missing was the inverse: *positive selection*
  of what the diff can move, plus a ratchet floor that never narrows.

The merge gate is unchanged: CI's required `test` context runs the full
battery, sharded, on the PR head (ADR-183 — no local run is the merge gate).
What changes is the local default, which was the same battery paid at every
commit hook.

## Decision

1. **Local `test-all.sh` defaults to `--affected`.** A local non-CI invocation
   with no mode flag runs the suites the diff can move — classified
   `edge:consumed`, `edge:declared`, `edge:derived` through argv self-edges,
   source/import closure, name-stem resolution, and the declared edges in
   `scripts/lib/test-affected-paths.sh` — plus every `ALWAYS_ON_SUITES`
   repo-global ratchet (`*-live` scanners, runner-SUT suites, corpus linters).
   `edge:declared`/`edge:consumed` UNION with derivation rather than shadow
   it: a declared array records only what derivation could not reach at write
   time, so a dependency a suite gains afterwards widens its edge set instead
   of being declined behind a stale declaration.
   CI (`CI` set) and explicit `TEST_GROUP` group runs are unaffected; CI keeps
   the full battery.

2. **`--full` is the only spelling of the local full battery.** It arms the
   legacy force-all semantics (`_diff_touches` always true, the infra-arm
   conjunct) explicitly. `SOLEUR_TEST_FORCE_ALL=1` keeps its narrower
   relevance-only meaning and does NOT arm the infra conjunct — under affected
   mode it degrades the selection to full via the fallback ladder instead.

3. **Selection uncertainty fails toward coverage.** `AFFECTED_FALLBACK
   reason=undecidable-diff` (diff flags disagree), `reason=index-missing`
   (declarations lib absent), `reason=runner-changed` (the diff touches
   `test-all.sh` or the index itself), and `reason=force-all` each degrade the
   run to the full battery with a printed banner — never silently narrow. A
   gutted declarations file (`|ALWAYS_ON|` below the runner's
   `_MIN_ALWAYS_ON_DECLARED` floor — the *live-derived* `*-live` floor lives in
   the orphan linter's census) or an empty effective selection refuses `rc=4`
   (`AFFECTED_UNRESOLVED`) before anything runs.

4. **Affected mode is exempt from BOTH full-gate refusal arms.** ADR-196's
   subagent arm and sibling-contention arm now check the resolved mode: pure
   `--affected` runs proceed (they are the narrow gate the refusal exists to
   steer toward), `--full` runs refuse as before, and a run that DEGRADED to
   full re-checks both arms post-derivation — a degraded run IS a full battery,
   the thing the sibling guard exists to serialize. This is a deliberate
   deviation from the plan's "refusals unchanged" note, recorded so the
   reasoning is not re-derived: without it, every `git commit` on a branch that
   touches the runner or index (this one, permanently) would refuse while any
   sibling held a gate.

5. **Enumerate is never affected-filtered.** `--enumerate` and
   `--enumerate-commands` answer "what is registered" — they emit the full
   stream regardless of mode flags, and the affected classifier's own pre-pass
   is a nested `--enumerate-commands` self-call. This resolves the spec's
   ambiguity ("composes with `--enumerate`") in favour of the enumerate
   contract's consumers, which invoke it repeatedly to count registrations.

6. **`TEST_GROUP=<g>` is an explicit cross-cut, not the selection mechanism.**
   A non-`all` group ask force-selects that group's registrations rather than
   intersecting them away — an explicit ask must produce an executed suite, not
   a counted `not-affected` decline that sets `_infra_ran` on a suite that
   never ran (the Phase 0-reproduced false-coverage seam ADR-181's accounting
   would otherwise admit).

7. **Declines stay counted; the numerator subtracts them.** The ADR-181 decline
   machinery is preserved — `not-affected` is a fourth decline class with a
   distinct counter, included in the denominator and excluded from `passed`.
   The epilogue prints the `--full` recovery lever once, so a run with
   declines names its re-run.

8. **Token-level diff edges are deferred.** Spec FR2 listed diff-content token
   edges; both review panels converged on cutting them — they are a
   narrowing-only win that requires a second diff-content channel, and the
   unclassified→always-run rule already covers the gap at battery-cost, not
   correctness-cost.

## Consequences

- The local gate is minutes-scale by default. The serial battery still runs —
  on CI, and locally under `--full` or any fallback arm.
- **ADR-181's premise is narrowed, not reversed.** Relevance declines still
  exist for the five consumed-edge suites; what changes is that the *default*
  local run positively selects instead of running-everything-and-declining.
- **ADR-183's ship default moves.** `/ship` Phase 4 dispatches
  `battery-owed.sh` first; OWED (or any non-42 verdict) runs `--affected`,
  and `--full` is an explicit operator opt-in that outranks even a SKIPPABLE
  verdict — the operator who typed `--full` asked for the battery itself, not
  a dedup decision.
- **ADR-196's Decision 6 is stale in one direction.** It asserted the two
  git-hook invokers "invoke the full gate deliberately and both set
  `SOLEUR_ALLOW_FULL_GATE=1`". Post-#8322 both invoke `--affected` with no
  hatch — the exemption is structural, not a grant. The refusal arms still
  exist and still bind to full-shaped invocations; `fanout-suite-scope.test.sh`
  Arm 11 pins the matrix.
- **ADR-133's contention machinery is demoted to the rare full path.** The
  flock, the sibling census, and the preamble still gate full batteries; the
  common local run no longer pays the census's measured-full cost.
- A healthy affected run reports `N-k/N` with a `not-affected` breakdown —
  `N/N` is now the exception, and a reader must not read the smaller numerator
  as incompleteness.
- **Accepted niche: a diff that ONLY deletes a derivable SUT.** Edge
  registration filters on `[[ -e ]]`, so a pure deletion diff never matches an
  edge that no longer exists — a suite whose SUT vanishes in the same commit
  declines. This is bounded (deleting a SUT while keeping its test is rare,
  and always-on ratchets still run) and fixing it would mint dead edges for
  argv tokens that merely look like paths — the `[[ -e ]]` test is the garbage
  filter that keeps the edge set honest. Fail-safe via `unclassified` already
  covers the common case (the deletion removes the suite's only edge).

## Alternatives considered

| Alternative | Why not |
|---|---|
| Keep the full battery as the local default, `--affected` as opt-in | Inverts the measured value: the full battery produced zero of the 24 motivating findings while being refused three times for contention. The expensive default should be the opt-in. |
| Refusal arms still bind affected runs (plan's original FR8) | Would refuse every commit on runner/index-touching branches whenever a sibling holds a gate — the self-edge makes degraded-full the *common* case there, and the refusal would gate commits, not batteries. |
| Refuse affected runs that degrade under contention | That IS the design — degradation re-checks the arms. What changed is the *pure*-affected exemption. |
| Token-level diff edges | Narrowing-only win; needs a second diff-content channel; unclassified→always-run already fails safe. Deferred, not rejected. |
| Let enumerate filter by mode | Breaks every enumerate consumer that counts registrations; the classifier itself depends on the unfiltered stream. |

## Amendment — 2026-09-29

**#9173 — the diff-source scope axis (`--affected-scope=staged`).** The
fallback ladder in Decision 3 is a correct fail-safe pointed at the wrong unit
of work at a pre-commit gate: a hook's diff under test is the *commit*, but
`_diff_names` answered with the *branch*. A branch touching `test-all.sh` or
`test-affected-paths.sh` — which every suite-registration PR does — degraded
each ts-staging commit to the ~4 h full battery inside the hook, past
`TC_RUNTIME_CEILING_S` and behind the test-all advisory lock (measured on
#9136: three refused/killed/queued attempts; the commit landed only via
side-branch cherry-pick and `LEFTHOOK_EXCLUDE`, each of which bypasses *every*
hook including gitleaks).

Decisions added by this amendment:

9. **The affected gate gains a diff-source scope axis** —
   `--affected-scope=branch|staged`, default `branch`. Under `staged`,
   `_diff_names` derives from `git diff --cached` (name-only plus the
   `--name-status -M` rename-source form) and the branch window is dark: the
   `HEAD` diff, the `origin/main...HEAD` range, and all three untracked
   appends are skipped, because untracked content is definitionally not in
   the commit. A failed staged read arms the existing `undecidable-diff`
   fallback — the fail-toward-coverage direction is unchanged. The flag is
   valid only where an affected axis consumes `_diff_names` (`--affected`,
   the local default, or `TEST_GROUP=affected`); combined with `--full`, an
   unknown enum value, or a non-affected `TEST_GROUP` it exits 2. The
   `lefthook` `bun-test` hook invokes `--affected --affected-scope=staged`
   behind `TC_LOCK_TIMEOUT=300` — the ticket queue defaults to the lock
   timeout, so one knob bounds both of tc_acquire's wait stages and on expiry
   it proceeds with the `LOCK_CONTENDED_PROCEEDING` banner rather than
   aborting.
10. **`runner-changed` is scope-aware.** Under `staged` the ladder arm is
    gated off and the staged runner/index path is detected *inside* the
    bounded-selection walk — the paths are in the staged set by construction,
    so their declared self-edges plus the unconditional always-on runner-SUT
    battery (which includes `scripts/test-all-affected`, the classifier's own
    mutation suite) cover what the commit can move — announced as
    `AFFECTED_RUNNER_IN_SCOPE reason=runner-changed`, with `_aff_fallback`
    left empty so the degraded-full refusal re-check does not apply. Emitting
    the note inside the `else` (not a dedicated `elif` arm) is load-bearing:
    a dedicated arm consumed the chain, left `_aff_ready=0`, and the
    chokepoint read that as select-everything — a silent full battery (#9197
    review, caught by two independent seats). Keeping the staged path in the
    walk also preserves the below-floor `ALWAYS_ON_SUITES` refusal, which a
    consumed elif would shadow exactly when a gutted index needs it. Branch
    scope keeps the full-corpus fallback byte-identical. The accepted
    residual: a commit staging a *selector-corrupting* runner edit could
    narrow the selector it runs under — bounded by the runner-SUT battery's
    unconditional membership and by CI's full battery on the PR head, which
    remains the authoritative merge gate.
11. **Scope is flag-selected, never env-selected.** An exported `SOLEUR_*`
    variable would inherit into the runner's nested `--enumerate-commands`
    self-call and any later shell — presence is not ownership (measured in
    `knowledge-base/project/learnings/2026-09-28-an-exported-session-env-var-forked-nested-runner-behavior.md`).
    A flag on the one sanctioned call site carries provenance for free, is
    greppable, and cannot leak. The flag is forwarded into that nested
    enumerate call so the child's decline records evaluate the same diff the
    parent applies.

Alternatives added by this amendment:

| Alternative | Why not |
|---|---|
| `TEST_GROUP=commit-scope` + a `SOLEUR_ALLOW_*`-style provenance env (#9173 option b) | Duplicates the existing narrow selector with new `want_*` plumbing for the same property; an env var's presence is not ownership and it inherits into the nested enumerate self-call. A flag buys the property outright. |
| `runner-changed` → runner suites + staged set under branch scope (option c alone) | Still needs the staged plumbing; keeps branch-diff over-selection on every commit of a runner-touching branch; keeps the use-the-suspect-selector trust hole without the per-commit semantics that bound it. Its bounded-degradation half was adopted *inside* staged scope. |
| `runner-changed` distinguishes selection-logic vs registration-data edits (option d) | A pathname trigger cannot see edit kind without fragile diff-content inspection, and the dangerous narrowing edit is data-shaped — already covered by self-inclusion edges, the always-on census, and unclassified-selects-anyway. |
| Pass lefthook `{staged_files}` argv to the runner | Space-separated argv fragility; the in-runner index derivation is authoritative and seam-testable. |
| `no_stash` on the hook (sibling symptom in #8045) | Out of scope for this amendment — `git diff --cached` is stash-agnostic, and the false-RED/stash question belongs to #8045. |

## Amendment — 2026-09-30

Context: a session reported the local gate "over-selected 229 mostly unrelated suites" (#9307). Measuring it
found that `--print-affected-set` prints each registration's CLASS and ignores the diff, that the
knowledge-base-only diff really selected the 145-entry always-on floor plus five suites pulled in by one false
edge, and that the always-on floor is 52% of light-group suite time. Four decisions follow; they extend
decisions 1-3 above and do not change the CI contract.

12. **Edge matching is anchored.** `_affected_add_edge` stores every edge it accepts with a `^` marker: a
    directory edge (`^dir/`) matches a diff line that STARTS with `dir/`, a file edge (`^file`) matches a line
    that EQUALS it. `_diff_touches` keeps the legacy substring match for unmarked edges, so the relevance
    arrays that reach it directly are untouched, and edges rooted at `.`/`..` stay unanchored (an anchored `^./`
    could never match, which would turn a select-everything edge into a select-nothing one). Evidence: over 30
    real diffs the new matcher selected 0 suites the old one did not and dropped 84 selections belonging to 7
    suites, every one a demonstrated false positive (a directory token matched inside a longer path); the
    record is `knowledge-base/project/specs/feat-affected-parallel-test-gate/edge-anchoring-corpus.md`.
13. **A runner subcommand is not an operand.** The word `test` in `bun test <file>` resolved to the repo-root
    `test/` directory and minted an edge that selected every `bun test` suite for any diff under it. The
    derivation now skips `test` after `bun|npm|pnpm|yarn|go|cargo`. Removing it exposed three suites that had no
    real edge (the bogus one had been masking that, selecting them only when a diff path contained the word
    "test"); they now declare their subject.
14. **Selection is observable.** `--print-selection` runs the same pre-pass a real run applies and prints
    `AFFECTED_SELECTED<TAB>label<TAB>0|1<TAB>class<TAB>edges` per runnable suite plus one `AFFECTED_SUMMARY`
    line, running nothing; every real affected run prints the same summary on stdout, and a degraded run says
    `selected=all ... fallback=<reason>` instead of inventing a selection. `--paths=a,b`, valid only with
    `--print-selection`, selects against named paths instead of the real diff, so it cannot narrow a real run.
    `--print-affected-set` stays class-only and must not be quoted as a selection.
15. **The always-on floor is audited with evidence, and a ratchet guards the demotions.** Each always-on suite
    ran serially under an inotify open-event recorder (`strace` is not installed on the operator host) and its
    observed reads, not its name, decided whether it may leave the set. 24 suites moved to declared edges;
    `_MIN_ALWAYS_ON_DECLARED` rose to 116 (new count minus 5). A `*-live` suite may carry a declared edge, as
    the census linter already permits, but only with this evidence. `scripts/test-affected-kb-consumers.test.sh`
    fails when a suite that reads a real `knowledge-base/` path is neither always-on nor covered by an edge
    (one-sided baseline of pre-existing gaps). **The measured limit:** the 24 are the fast suites, 0.5 of 39.3
    minutes of always-on time (1%); about 80% of the time is nine runner-SUT and census batteries that walk the
    whole tree and stay always-on. The saving is suite count, not time; narrowing the nine is a per-suite design
    decision tracked separately. Observed reads are evidence for the run that happened, not a proof for every
    input, which is why the disqualifiers are deliberately broad and CI's full battery stays authoritative.

Alternatives added by this amendment:

| Alternative | Why not |
|---|---|
| Drop the always-on class and trust derivation for every suite | Derivation attaches a self-edge to a corpus scanner, which then declines on the diffs that drift the corpus; the census linter exists to prevent exactly that |
| Anchor by rewriting every declared edge by hand | The edge set is derived; anchoring in the one minting function covers every source and cannot drift |
| Add an env seam to fake the diff for `--print-selection` | An exported `SOLEUR_*` variable could narrow a real run; a print-only flag cannot (decision 11) |
| Demote the nine heavy batteries in this change | Their reads span the tree; the evidence cannot bound them, so the decision is per-suite and follows separately |
| Observe reads with `strace` | Not installed on the operator host; inotify open events cover reads and directory listings, but not `stat` or git-index access, which the disqualifiers compensate for |

## References

- Issue: #8322; motivating review session: #8270/#8231; duplicate-full-run
  dedup: #8247 (`battery-owed.sh`); prior affected-test win: #8045.
- Plan: `knowledge-base/project/plans/archive/20260920-163321-feat-test-all-affected-gate-default-plan.md`
- Index: `scripts/lib/test-affected-paths.sh`; classifier + mode matrix:
  `scripts/test-all.sh`; mutation suite: `scripts/test-all-affected.test.sh`.
