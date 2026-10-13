---
title: The local gate defaults to the affected set plus always-on ratchets; the full battery is CI or explicit --full
status: active
date: 2026-09-18
amends: ADR-181, ADR-183, ADR-196, ADR-133
related_adrs: [ADR-181, ADR-183, ADR-196, ADR-133, ADR-177]
amended_by:
  - "#9552 (2026-10-05) — decision 20: a registration-only runner diff takes the bounded selection under branch scope (closed grammar, fail closed); the 2026-09-29 option-d rejection is reversed in part; see ## Amendment — 2026-10-05 (#9552)"
  - "ADR-262 (2026-09-30, #9323) — decision 1's \"CI keeps the full battery\" and the merge-gate statements are narrowed for five self-test mutation batteries on a pull_request run; four labels leave ALWAYS_ON; see ## Amendment — 2026-09-30"
  - "#9173 (2026-09-29) — the diff-source scope axis (`--affected-scope=staged`) and the scope-aware `runner-changed` arm; see ## Amendment — 2026-09-29"
  - "#9307 (2026-09-30) — anchored edge matching, the runner-subcommand skip, `--print-selection` / `--paths`, and the evidence-based always-on audit; see ## Amendment — 2026-09-30"
  - "#9400 (2026-10-01) — the affected-ratchets pre-push lane moves the cheap ratchet net earlier than the local gate (push time, merged tree); the required `test` context remains the merge gate; see ## Amendment — 2026-10-01 (#9400)"
  - "#9813 (2026-10-10) — decision 22: the `glob:<literal-head>/<glob-tail>` declared-edge kind for corpus walkers, the five-site malformed-shape doctrine, and the per-suite dispositions; see ## Amendment — 2026-10-10 (#9813)"
  - "#9814 (2026-10-11) — the local weight-drift detector: TEST_TIMING_LOG defaults on affected-shaped local runs and the epilogue emits advisory WEIGHT_DRIFT lines against committed weights; see ## Amendment — 2026-10-11 (#9814)"
  - "#10117 (2026-10-13) — decision 27: the root-anchored `glob:` grammar residual is detected, not extended; the extension triggers only on a live dir-less corpus file (#10198); see ## Amendment — 2026-10-13 (#10117)"
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
  minutes on the measured `feat-one-shot-8231` serial baseline; the 2026-09-30
  amendment re-measured it as 145 entries and 39.3 minutes), so the win
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
10. **`runner-changed` is scope-aware.** *(Closing sentence superseded in part, and its "unconditional always-on runner-SUT battery" premise corrected,
    by decision 20: a registration-only diff now takes the bounded selection under branch scope too.)* Under `staged` the ladder arm is
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
| `runner-changed` distinguishes selection-logic vs registration-data edits (option d) | A pathname trigger cannot see edit kind without fragile diff-content inspection, and the dangerous narrowing edit is data-shaped — already covered by self-inclusion edges, the always-on census, and unclassified-selects-anyway. **Superseded in part by decision 20 (2026-10-05, #9552):** a CLOSED whole-line grammar over added lines, with zero tolerance for removed lines, is not the fragile inspection this row rejected, and the data-shaped narrowing edit is answered by the label-binding rule. |
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
    record is `knowledge-base/project/specs/archive/20261013-062704-feat-affected-parallel-test-gate/edge-anchoring-corpus.md`.
    **The direction flips.** A substring over-matched toward RUNNING, the safe side decisions 3 and 8 rely on;
    an anchored edge errs toward NOT running whenever the diff text does not present a path as its own line.
    The diff blob therefore has to: `--name-status -M` rename rows (`R100<TAB>old<TAB>new`) are split on TABs
    so the OLD path matches (rows t8/t9/m7), and a git C-quoted name (`"dir/caf\303\251.md"`) is unwrapped so
    a directory prefix still matches (t10/m8). The corpus above used `--name-only` and could not see renames;
    that gap was found at review, not by it. An edge to a path that no longer exists is dropped when edges are
    minted (as before), so deleting a declared subject is caught by the census linter in the same run, not by
    selection. A path whose name holds a TAB, a newline or a `|` is not supported.
13. **A runner subcommand is not an operand.** The word `test` in `bun test <file>` resolved to the repo-root
    `test/` directory and minted an edge that selected every `bun test` suite for any diff under it. The
    derivation now skips `test` after `bun|npm|pnpm|yarn|go|cargo`. Removing it exposed three suites that had no
    real edge (the bogus one had been masking that, selecting them only when a diff path contained the word
    "test"); they now declare their subject.
14. **Selection is observable.** `--print-selection` runs the same pre-pass a real run applies and prints
    `AFFECTED_SELECTED<TAB>label<TAB>0|1<TAB>class<TAB>edges` per runnable suite plus one `AFFECTED_SUMMARY`
    line, running nothing; every real affected run prints the same summary on stdout, and a degraded run says
    `selected=all ... fallback=<reason>` instead of inventing a selection. `--paths=a,b`, valid only with
    `--print-selection` (and with `--enumerate-commands`, which the pre-pass uses to forward it to its
    enumerate child so the relevance-gated registrations are declined against the SAME named paths), selects
    against named paths instead of the real diff, so it cannot narrow a real run. `of=` counts runnable
    registrations only; a relevance-declined suite is in neither `selected` nor `of`. The row format is
    private to the Soleur runner and unversioned; PR 2's plugin gate must not parse it.
    `--print-affected-set` stays class-only and must not be quoted as a selection.
15. **The always-on floor is audited with evidence, and a ratchet guards the demotions.** *(Superseded in part by decisions 16 to 18: one-run evidence became a committed recorder, 20 of the 23 demotions were re-promoted, and the "one audited run" caveat no longer applies.)* Each always-on suite
    ran serially under an inotify open-event recorder (`strace` is not installed on the operator host) and its
    observed reads, not its name, decided whether it may leave the set. 23 suites moved to declared edges (24
    were audited as demotable; `scripts/domain-model-drift` was put back, see below);
    `_MIN_ALWAYS_ON_DECLARED` rose to 116. A `*-live` suite may carry a declared edge: the census linter
    demands a declaration but does not check the evidence, so the audit document is the only record that
    backs it. `scripts/test-affected-kb-consumers.test.sh` fails when a suite that reads a real
    `knowledge-base/` path is neither always-on nor covered by an edge, and when its committed baseline is
    stale. It covers literal `knowledge-base/` reads only, one hop deep; the `docs/legal/`, `AGENTS*.md` and
    migrations edges of the demoted suites rest on the one audited run alone. It is registered in
    `scripts/test-all.sh` (it was a never-run suite until the census said so) with a declared edge set, and
    costs one `--print-selection` walk (about 11 minutes of CPU today), so it runs on every CI battery and
    locally only when its own inputs change. **The measured limits:** the demoted suites are the fast ones,
    about 0.5 of 39.3 minutes of always-on time (1%); about 80% of the time is nine suites that walk the whole
    tree (about 62% is runner-SUT or census batteries; the rest are whole-corpus scanners) and stay always-on.
    The saving is suite count, not time. A demotion also moves a suite from a free always-on skip to a full
    source-closure derive in the pre-pass: about 2 s for the 23 together, but 82 s for
    `scripts/domain-model-drift` (its comments name `test-all.sh`) against 0.9 s of suite time, so that one
    stayed always-on. The pre-pass itself is about 11 minutes of CPU on every local `--affected` run, 73% of
    it in eight registrations; that, not the always-on count, is the dominant local cost and is tracked on
    #9307. Observed reads are evidence for the run that happened, not a proof for every input (inotify open
    events do not see `stat` calls or probes of missing files), which is why the disqualifiers are
    deliberately broad and CI's full battery stays authoritative.

Alternatives added by this amendment:

| Alternative | Why not |
|---|---|
| Drop the always-on class and trust derivation for every suite | Derivation attaches a self-edge to a corpus scanner, which then declines on the diffs that drift the corpus; the census linter exists to prevent exactly that |
| Anchor by rewriting every declared edge by hand | The edge set is derived; anchoring in the one minting function covers every source and cannot drift |
| Add an env seam to fake the diff for `--print-selection` | An exported `SOLEUR_*` variable could narrow a real run; a print-only flag cannot (decision 11) |
| Demote the nine heavy batteries in this change | Their reads span the tree; the evidence cannot bound them, so the decision is per-suite and follows separately |
| Observe reads with `strace` | Not installed on the operator host; inotify open events cover reads and directory listings, but not `stat`, probes of missing files or git-index access. The disqualifiers target git and clock use, not `stat`, so the compensation for that gap is unmeasured |
| Run the dropped-consumer ratchet over declared arrays only (seconds, not minutes) | Declared arrays are a subset of a demoted suite's effective edges (declared plus derived), so it would flag reads the derived closure already covers; the full walk is the only exact oracle until the closure derive is made cheap |

## Amendment — 2026-10-01

Context: the pre-pass cost recorded under decision 15 (about 11 minutes of CPU on every local `--affected` run) was
attributed to comment tokens and an O(n) edge scan. Profiling the walk found a different mix. Decisions are numbered
in landing order; the follow-on work is decision 17 onward.

16. **The derive is cheaper, bash-version independent, and changes to it are certified by a selection-identity
    bench.** Four changes, each its own commit:
    (a) `shopt -u patsub_replacement` as the second statement of the runner's derive section (after `_AC_CLASS=""`).
    On bash 5.2 and later an unescaped `&` in the replacement of `${v//pat/repl}` expands to the matched text, and
    the derive substitutes captured variable values into tokens, so a value carrying `&` resolved differently on 5.2
    and later than on 3.2. The option is a no-op before 5.2 and `BASH_COMPAT` does not disable it. It applies to the
    rest of the runner process; a review found no later `&`-in-replacement site in the runner or its libraries.
    Repo precedent quotes the replacement instead (`ci-deploy.sh`), which is unverified on old bash and would let a
    future site reintroduce the hazard.
    (b) `_affected_resolve_vars` stops starting new passes once the string has grown more than 4096 bytes over its
    input (counted in the C locale). A self-referential value multiplies the string every pass, and review measured
    that removing the cap takes the walk from about 90 s back to 220-260 s. **This one is not identity-preserving in
    general:** a trip stops resolution, so a later variable on the same line is left as `$VAR`, dies at the `-e`
    filter, and its edge is not minted (the 12-pass cap alone would have resolved it; a review reproduced it with a
    1100-byte value repeated five times before a second variable). Selection is identical on today's corpus, which the
    bench shows, and any later change to this function is gated by the same bench. Failing safe on a trip would change
    selection for the lines that trip today, so it is not done here.
    (c) Edge membership is a newline-bracketed shadow set (`_AC_ESET`) beside the ordered `_AC_EDGES` array, appended
    with `+=`; the closure's visited list is the same kind of set. Every site that assigns the array goes through
    `_affected_reset_edges` or `_affected_resolve_edges`, and a suite row counts the sites so a fourth fails.
    `_affected_resolve_edges` validates its `eval` operand as an identifier.
    `scripts/affected-prepass-bench.sh` is the acceptance contract for any later change to the pre-pass: it compares the
    `AFFECTED_SELECTED` rows of a base revision and a head byte for byte (registrations the change adds, and edges that
    exist only because the change added a file, are declared and counted), and times both sides interleaved. Its
    limits, stated: only registrations classified under the chosen probes are compared; each side derives over its own
    tree; identity is checked on one bash (head-on-5.3 versus base-on-3.2 is argued by the derive suite, not measured);
    and it is operator-run, so CI keeps `scripts/test-affected-derive.test.sh` and the dropped-consumer ratchet's full
    walk as regression coverage and does not prove identity against a merge base.

**Corrected figures for decision 15.** The 8 registrations that held 73% of the pre-pass were the first to scan the
files of a shared closure: `_affected_file_edges` memoises per file, so cost lands on whichever registration touches a
file first (`scripts/orphan-process-reaper` is registration 74 and carries 23.8 s because its closure reaches the runner
and about 465 files). Profile of the walk after (a), (b) and the first shadow set (one `--print-selection --paths=README.md`
run, instrumented copy, 80 s of classify time): 785 distinct files scanned for 45.5 s (57%), 8,076 memo replays for
5.5 s, 1,093 per-token `sed` forks in `_affected_normpath` for about 4.4 s, and the remainder in the closure loops. A
review prototyped three further identity-preserving changes (the memo index, which this change did not take, plus the
two taken here) at 5-7x on one registration's warm derive; the memo index is the open candidate and is measured only
by the bench, not here. Measured on the operator host (16 cores, bash 5.3.15, locale en_US.UTF-8) with the bench, base
and head interleaved, two base and three head runs per probe, median CPU (user+sys): the README probe went from 277 s to 69 s (4.0x) and
a multi-path probe that selects edge suites from 427 s to 98 s (4.4 (3.1 at the minimum, 280 s to 89 s, because the base side was noisy)x), load average 5 to 10 during the
runs, selection identical on both probes (537 and 538 base rows byte for byte, one declared added
registration). The earlier figure of about 11 minutes was taken at load average 30 to 64 and overstated the cost on a
quiet host. The route to a further order of magnitude is to stop following what the runner's text merely names (about
450 edges for 18 suites, measured at 61.9 s CPU by the plan); that narrows selection, so it is not
identity-preserving and is a separate decision (decision 18, with the `REPO_ROOT` idiom fix).

## Amendment — 2026-10-03 (PR-B and PR-C of #9307)

Context: decision 15's evidence was one run of session-scratch scripts, and decision 16 named the further route to a cheaper pre-pass
(stop following what the runner's text merely names) as a separate decision. This amendment records both. Numbers follow landing order.
The measured figures live in `knowledge-base/project/specs/archive/20261013-062704-feat-affected-parallel-test-gate/always-on-audit.md` (Rounds 2 and 3); they are not restated here.

17. **The always-on evidence is a committed recorder with one verdict function, and a recording that is not complete is never evidence for a
    demotion.** `scripts/audit-suite-reads.sh` (with `scripts/lib/inotify-open-recorder.py`) re-issues decision 15's audit as "Round 2" and
    **supersedes its "one audited run" caveat.** A recording that overflowed the inotify queue, failed to watch a directory, exited non-zero
    or disagrees with its repeat, or skipped an arm of the suite (a `SKIP` line: its reads are unobserved), or moved or deleted a watched directory,
    or left a dirty checkout, is `unreliable` (retry; the classification is never changed on it); a probe the open-event stream cannot see
    (`[[ -e ]]`, `stat`, `ls`, `find`) whose operand the static scan cannot resolve **disqualifies**, and the audit doc states that the scan has
    low resolving power. The event source is a raw-inotify reader because `inotifywait` was measured to deliver exactly 16,384 events for 17,500
    opens and print no overflow record when the reader lags, so it cannot back that rule. Applied to the 23 existing demotions: 3 stay demoted and 20 return
    to `ALWAYS_ON_SUITES`: 18 on the first recording, and 2 more after review found that the two rows first recorded `unreliable` were an artifact of
    the recorder's own contamination probe (tracked-but-gitignored files made window 1 of every run look dirty; fixed) and re-recorded them `uncovered`.
    The rule is the plan's: an `unreliable` suite that is already demoted goes BACK, because the default is keep (the first write-up of this decision left
    them demoted, which is the unsafe direction). The isolation is "no IP network and a scrubbed environment", not a filesystem sandbox; only revisions
    that are ancestors of HEAD or `origin/main` are audited. Three smaller changes belong to the same decision: a runner subcommand
    (`deno test`, `make test`, `npm|bun|pnpm|yarn run test`) is not an operand in the argv walk or the `-c` payload walk (extends decision 13); the
    dropped-consumer ratchet gains a form table with one new form (a directory operand with no code file), classifies every non-literal baseline
    row, decides existence by git-tracked paths, and treats the declarations libs as data; and a declared edge to a deleted subject still being
    dropped (decision 12's clause) was **not** reversed: that change was cut for cost and is tracked in #9441.
18. **The runner and its index are closure leaves for text mentions, and the selection delta is certified by the bench's declared-delta mode plus
    the recorder, not by identity.** `CLOSURE_LEAF_FILES` (exactly the two files the `runner-changed` fallback greps for, pinned equal by a derive
    row) keep their real load edges (`source` and `.` lines, variables and `$(dirname "${BASH_SOURCE[0]}")` resolved) and lose the invocation words and
    `$VAR/path` tokens; the file itself stays an edge of every closure reaching it. This **amends decision 16's wording that the bench is the identity
    contract**: it stays so for every non-narrowing change, and this narrowing is the declared exception (`--leaf-files`: the head may only lose edges,
    no real source edge of a leaf may be lost, every row that reaches a leaf with outbound edges must lose exactly what the walker expects, a row that
    reaches none must lose nothing, a walker with no suite commands refuses, and two ceilings, `--max-unexplained` and `--max-kept`, both default 0).
    The oracle's walker is a second implementation of the derive's text rules and reproduces every edge-classified row of the stream (408 of 408 at the
    README probe), which is what lets the ceilings be 0; the first walker was not a model of the derive and needed a ceiling of 240, which the first
    write-up understated as 200 and described as "over-approximating". It still cannot see a read the derive never modelled, so the recorder's check
    mode on the suites that reached the runner is the behavioural cover, and it found runtime reads the incidental edges had covered, now declared per
    label. The `runner-changed` fallback is NOT part of that cover: it fires only on a diff to the two leaf files themselves (and not under
    `--affected-scope=staged`), never on a file the leaf stopped following. The recorder is operator-run, so a read added to a suite later is not
    re-validated automatically; CI's full battery is the cover for that. Where the recorder gave no evidence the suite is hedged to always-on when
    that costs under about 7 s (six suites after the re-check), and where hedging would cost 77 s to 134 s (`test-affected-kb-consumers`,
    `orphan-process-reaper-mutations`, `audit-suite-reads`) the suite stays on its derived or declared edges with the evidence gap stated in the audit. The first version of this rule dropped the runner's
    variable-sourced libs; the retained-edge floor, which had been vacuous when the list was empty, is what caught it. The `REPO_ROOT` idiom
    fix (D1) is a **widening** recorded here with its census and selection delta: `cd "<dir>[/..]" && pwd` resolves to its cd target when the target
    is fully resolved, and a token D1 leaves without an edge is re-run as before so it can only widen. Non-leaf files also resolve
    `$(dirname ...)/` on the whole line (the slash form only: the bare form mints a coarse directory edge on 241 rows), which restores the real
    source edges of the 11 hooks that lost them. Phase C: none of the six heavy always-on batteries narrows (no clean recording); `domain-model-drift` stays always-on on the
    recorder rule now that its 82 s derive cost is 0.2 s.

Alternatives added by this amendment:

| Alternative | Why not |
|---|---|
| Keep `inotifywait` as the event source | It drops queue overflow silently (measured), which defeats "never demotable from an incomplete recording" |
| Resolve `$VAR` probe operands in the recorder to keep more suites demoted | An unprovable operand is unproven; resolving it is the next increment of the scan, and always-on is the safe side meanwhile |
| Make the bench an exact-equality oracle for the leaf rule | An independent text walker cannot reproduce every dropped edge; equality would force the walker to become the derive |
| Treat the runner as a leaf by skipping passes 2 and 3 wholesale | Loses `source "$VAR"` loads (measured: five libs), which had reached suites only by being mentioned |
| Declare `.` as an edge for the five suites that open the checkout root | A directory open of the root is a read of no particular file; no pre-change cover held it either |

## References

- Issue: #8322; motivating review session: #8270/#8231; duplicate-full-run
  dedup: #8247 (`battery-owed.sh`); prior affected-test win: #8045.
- Plan: `knowledge-base/project/plans/archive/20260920-163321-feat-test-all-affected-gate-default-plan.md`
- Index: `scripts/lib/test-affected-paths.sh`; classifier + mode matrix:
  `scripts/test-all.sh`; mutation suite: `scripts/test-all-affected.test.sh`.

## Amendment — 2026-09-30 (#9323, ADR-262)

Narrowed, not reversed. Decision 1's "CI keeps the full battery", Context's "the merge gate is unchanged:
CI's required `test` context runs the full battery", the Consequences line "the serial battery still runs —
on CI" and the accepted-residual bound "CI's full battery on the PR head, which remains the authoritative
merge gate" are each **true except for five self-test mutation batteries on a `pull_request` event**, which
decline when the PR's diff touches none of their declared subject paths (ADR-262). The required `test`
context still reports on every PR and no job `if:` changed; on `push`, `merge_group`, `workflow_dispatch` and
the 6-hourly `main-health-monitor` the full battery runs, so an escape is caught on the push run or the
monitor, not on the PR.

**ALWAYS_ON rationale for four labels.** `scripts/test-all-affected`, `scripts/battery-tag-authorship-mutations`
and the two `--rows` halves of `scripts/lint-orphan-test-suites-mutations` were classified `ALWAYS_ON` as
"runner-SUT" suites whose verdict is a property of the whole registration set. That reasoning does not hold
for them: each is a mutation battery that scores a **sandbox copy of named files**, so its edge set is the
declared array (`LINT_ORPHAN_BATTERY_PATHS`, `TAG_AUTHORSHIP_BATTERY_PATHS`,
`TEST_ALL_AFFECTED_BATTERY_PATHS`), now read as `AFFECTED_CONSUMED_EDGES`. Their subjects
(`scripts/lint-orphan-test-suites`, `scripts/battery-tag-authorship`) stay `ALWAYS_ON`. The new guard suite
`scripts/test-all-pr-battery-gate` is `ALWAYS_ON`: its subject is the runner itself.

## Amendment — 2026-10-01 (#9400)

Added, not narrowed: a **third local gate tier** now exists below this ADR's `test-all.sh --affected`
dispatch. `scripts/pre-push-ratchet-lane.sh` runs at `pre-push` time (lefthook `ratchet-lane` command and
stage 1 of `scripts/hooks/pre-push`) and is scoped to the curated ratchet/lint members a push diff can trip:
the highwater family (`lint-trap-tempfile-ownership`, `lint-supabase-deprecated-endpoints`,
`lint-diagnosis-claims`, `alarm-issue-filing-guard`, `lint-workflow-step-env-refs`), the standalone
`plugin-root-anchor-debt` probe, the three fixture-scan suites, the merge-base byte/body lints
(`lint-skill-body-budget`, `lint-rule-bodies`), plus `test-affected-kb-consumers` under a conditional
trigger and a capped branch-touched suite tier run in the deps-free, disk-backed-TMPDIR scratch.

The load-bearing difference from every other local gate: the lane **evaluates the merged tree**, not the
branch tree. It fetches `origin/main`, materializes the branch in an ephemeral detached scratch worktree,
merges `origin/main` there, and runs every member with cwd inside that scratch — the shape that makes the
five #9339 CI-only failure classes visible locally without mutating the operator's branch or working tree
(a fetch failure degrades to `merge=skipped:fetch-failed` and members still run on the unmerged tree; a
merge conflict exits 2 with `verdict=MERGE_CONFLICT`; the receipt never reads `all green`/`tests verified`).

**ADR-183 reaffirmed.** This lane is not the merge gate and is never described as one. The required `test`
context on the PR head remains the only merge gate; the lane is the cheap local net in front of it, and its
receipt is a `RATCHET_LANE verdict=` line, not a battery verdict.

## Amendment — 2026-10-04 (section 2 of #9307)

19. **The recorder runs suites as the invoking user, and a suite whose recorded read set no short declaration can bound is hedged, not declared.** The
    recorder probes `unshare -cn` (the caller's own uid), falls back to `unshare -rn` (namespace-root, stamped `idmap=root`), then bwrap, and carries
    `unshare` on its scratch PATH. The mapping is stamped in the header and written to the meta file; a `--mode demote` row is decided only for `idmap=current`:
    `idmap=root` (also a run started by uid 0) comes out `unreliable reason=idmap-root` and a meta with no IDMAP line (a pre-cell recording)
    `reason=idmap-unknown`, because a namespace-root run can skip arms that refuse a privileged caller without saying so. **This supersedes,
    for `scripts/test-affected-kb-consumers`, `scripts/orphan-process-reaper-mutations` and `scripts/audit-suite-reads` only, decision 18's sentence that
    keeps them on their derived or declared edges with the evidence gap stated, and decision 18's threshold of about 7 s under which a suite with no
    evidence is hedged.** The two suites with an instrument-side gap now have evidence; the third (`scripts/test-affected-kb-consumers`) is hedged into
    `ALWAYS_ON_SUITES` because no short declaration bounds its read set (the registration corpus, plus a `git ls-files` walk inotify cannot see). The
    criterion is "no short declaration bounds the set": a recorded read set spanning more than 20 directories, or any whole-tree `git ls-files` walk
    (measured 2026-10-04: 24 directories for the hedged suite, at most 4 for every other row of that table). Directory-listing residue may stay
    undeclared only where a cited assertion cannot depend on it (`scripts/audit-suite-reads` asserts only that the real runner enumerates at least
    400 registrations). **Both-state, deliberately:** that label is
    also kept in its declared array, solely because `scripts/pre-push-ratchet-lane.test.sh` arm 21 pins the lane's `KB_CONSUMERS_INPUTS` to it; the
    array is dead to selection (always-on wins). Removing the always-on entry trips row f2; deleting the array trips arm 21. **Demotions recorded
    before 2026-10-04 stand, as a deliberate exception to decision 17's keep-default** (they were recorded under `idmap=root`, where a skipped arm prints
    SKIP and rates its row unreliable; a silent skip is the residual risk). The re-record that would close the exception is section 3 of the #9307
    follow-up list (a scheduled recorder check); it does not exist yet and no separate issue tracks it, so the trigger is the next edit to any demoted
    suite's edge array: re-record that suite then, or put it back in `ALWAYS_ON_SUITES`. **Revisit** the hedge when always-on suite time passes 1,500 s or when the suite
    becomes incremental, so "keep" does not become permanent by default; row f1 holds the census slack at 5 and this change leaves it at 0, so the next
    always-on addition raises the floor (in `scripts/test-all.sh` and in f1's pin), which is the review point. The measurements, costs and final table live in the audit doc's 2026-10-04 addendum
    (`knowledge-base/project/specs/archive/20261013-062704-feat-affected-parallel-test-gate/always-on-audit.md`), not here.

## Amendment — 2026-10-05 (#9552)

20. **A registration-only runner diff takes the bounded selection under branch scope; every other runner edit keeps `runner-changed`.** Registering a
    new suite is itself an edit to `scripts/test-all.sh`, so every suite-adding PR paid the whole battery (a recent one was stopped after 2 h 13 m of
    contended run), and the run read as a hang. `_aff_classify_runner_diff` judges the diff `git merge-base origin/main HEAD` to the working tree for
    both runner-critical files against a closed grammar, and the pre-pass takes the bounded walk (`AFFECTED_RUNNER_IN_SCOPE reason=registration-only`,
    `AFFECTED_SUMMARY ... fallback=none`) only when EVERY changed line fits: **G0** headers only (a mode, rename, delete, binary or no-newline marker is
    semantic); **G1** zero removed lines (an edited line is a removal plus an addition); **G2** every line added to the runner is a blank line, a `#`
    comment, or one single-line `  run_suite "<label>" <argv0> <args>` in a closed charset (argv0 in `bash|python3|bun|node`; a plain repo-relative first <!-- markdownlint-disable-line MD038 -->
    path argument that is not option-shaped, has no leading `/` and no `..` segment; `python3 -m` only `unittest|pytest`; no quote, substitution, redirect,
    `;`, `&` or `|`), and an **anchor rule** binds every added line (the nearest preceding post-image line that is not blank or a comment must itself be a
    complete single-line registration, which keeps added lines out of continuations, heredocs and multi-line strings; every added line must also equal the
    working-tree line it claims to be); **G3** the only admitted additions to `scripts/lib/test-affected-paths.sh` are one contiguous
    `AFFECTED_<MAP(label)>_PATHS=( ... )` block per added suite (opener directly below another array's closing `)` or entry, entries in a closed charset,
    closer a lone `)`, all in one hunk) and entries of `ALWAYS_ON_SUITES`, each bound (**G5**) to a label ADDED in the same diff, with the array defined exactly once and not named by any
    `AFFECTED_CONSUMED_EDGES` pair, because the label-to-array map is not injective; **G4** `bash -n` passes on both post-images. The pre-pass then requires every
    added label to occur exactly once in the live `--enumerate-commands` stream, every anchor label at least once, no added label to inherit an
    already-declared array, and no OTHER live label to map to a declared array name, because loops and globs produce about half of the live registrations
    and their labels never appear as literals; any other count degrades to the full fallback through the same print block (never a new ladder arm, which
    repeated the #9197 defect). That check runs after the 70-80 s walk and against the `all`-group stream, an accepted cost of deciding on the live stream.
    Anything the classifier cannot decide (no merge-base, a git error, an empty diff text, a diff that registers nothing) is `undecidable` and behaves as
    semantic; under `--paths` the classifier is not computed at all. It is also not computed under `--affected-scope=staged`, which stays byte-identical.
    The verdict covers only the two trigger files: a registration that rides along with an edit to a third runner-sourced file
    (`scripts/lib/test-relevance-paths.sh`, `scripts/lib/test-contention.sh`, ...) gets that file's ordinary edge-based selection, exactly as editing it
    alone does today.
    The full-fallback banner states the cause, the manifest-weight cost (`about N min`, or "duration unknown"), the first offending `<file>:<line>
    [rule-code]` and a fixed sentence per code; it never prints diff text, because agents read this output (the only free-form token is an added label, restricted to
    the registration charset, with spaces shown as `_` and cut at 64 characters).
    **This SUPERSEDES decision 10's closing sentence** ("Branch scope keeps the full-corpus fallback byte-identical") for registration-only diffs, and
    **CORRECTS a stale premise in decision 10**: it cites an "unconditional always-on runner-SUT battery (which includes `scripts/test-all-affected`)", but
    ADR-262 withdrew that suite from `ALWAYS_ON_SUITES`; it still runs on every runner-touching diff because the runner is in its declared edge set and the
    diff names it, and the residual argument rests on that edge. **Why this reverses the 2026-09-29 option-d rejection in part:** that row feared "fragile
    diff-content inspection" and said the dangerous narrowing edit is data-shaped. A closed allowlist of whole-line shapes models none of bash's syntax and
    every miss falls toward the full battery, so it is not fragile in the way that matters; and the only data edit that can narrow (a new
    `AFFECTED_*_PATHS` array on an existing unclassified label turns "always runs" into "runs only when its edge is touched") is refused because every
    declaration must bind to a label the same diff registers. **Measured** (2026-10-05, over 226 non-merge commits touching either runner file since 2026-06-01; 230 on 2026-10-06): 152 (67%) fit the
    grammar including the anchor rule and 139 of those add a registration; the full battery is 91.4 min at manifest weights against 58.6 min for a bounded selection (a 36% saving, not minutes: 13.6 min of the
    43 edge suites are heavy batteries that are not runner-SUT, and narrowing those is a separate, deferred concept). **Accepted residual**, the same class
    as decision 10's with a larger window (the whole branch, not one commit's index): the classifier lives in the file it judges, so a PR that edits it is
    semantic by G1/G2 and goes full. The real residual is a latent gap in the already-merged grammar that wrongly admits a FUTURE diff (for example, the
    anchor check is by label, so it relies on every two-space `run_suite "` literal in the runner being a live call site). It is defended by the closed,
    default-deny grammar, the live-stream checks and `bash -n`, by the rows in `scripts/test-all-affected.test.sh` (selected by every runner-touching run), and
    by CI's full sharded battery on the PR head, which stays the merge gate. The `PR_GATE_MACHINERY_PATHS` arming of ADR-262 is unchanged: the name list a registration-only run reads still contains both paths.

    Alternatives considered: (b) registrations in a data file (about 560 registrations interleaved with relevance-gated blocks and ordinal-indexed shard
    selection; the data file would become a third runner-critical path needing its own grammar, which is mechanism (a) relocated); (c) banner only (does not
    deliver the narrowing; its banner half is kept for the fail-closed arm); a selection-equivalence oracle (sees selection metadata only, costs two walks);
    a classifier in a third file (an edit to it would not match the two-file trigger); admitting deletions or edits (a removed `run_suite` is a narrowing
    edit by definition); `SUITE_GLOBS` auto-discovery of root `scripts/*.test.sh` (162 explicit registrations make it a mass conversion, and "registration
    is a reviewed act" is a property worth keeping). Index declarations (G3/G5) ship in their own commit and are separable: dropping them changes no
    runner-only line. They serve about 3.5% of the measured demand (5 of the commits that fit the grammar touched the index at all: 4 array blocks, 1 entry) and
    were kept because the operator named "a new AFFECTED_*_PATHS array" as registration-only.

## Amendment — 2026-10-09 (#9812)

21. **The derive's per-registration classification is a cacheable pure function; verdicts are not.** The
    `_aff_stream` walk paid one fresh `_affected_classify` per registration on every local run (~150 s CPU
    measured on a contended host — the dominant cost of the local fast tier, #9763 arc). A classify is a pure
    function of (label, argv, the derive code, the environment channels that reach it, and the file contents +
    existence probes it consults), so `scripts/lib/test-affected-derive-cache.sh` caches its OUTPUT — class,
    ordered edge set, suite file — as one record per registration under
    `.soleur/cache/affected-derive/v<schema>/`, keyed on schema + derive-code hash (the EXTRACTED derive span,
    not the whole runner — an unrelated `test-all.sh` edit no longer flushes every record; both anchor legs
    must extract non-empty or the whole file hashes, a flush never a stale serve) + environment fingerprint
    (BASH_VERSION, the locale set, glob/case shell options, IFS — a record minted under one semantics cannot
    replay under another) + label + length-prefixed argv, and validates a hit by re-hashing every recorded read
    (`git hash-object --no-filters --stdin-paths`, one batched fork per record) and re-running every recorded
    `-e`/`-f`/`-d` probe. Any drift, a malformed or corrupted record (an `end` trailer plus a `sum` cksum over
    the body — a cut file can never serve a partial edge set and an in-body bit-flip cannot ride structure
    checks alone), a schema or worktree or cwd mismatch, an unwritable cache dir, or a missing git re-derives
    that record only — the cache is advisory and can never narrow a selection.
    `SOLEUR_AFFECTED_DERIVE_CACHE=0` is the kill switch. The runner instruments the derive span
    (`_affected_probe`, `_affected_rec_read`, inside the extraction anchors so the derive suite carries them)
    rather than duplicating the algorithm, so the recorded input set is the real one; the `[[ -d "$PWD" ]]`
    `_wt_missing_die` liveness probe is named-exempt, and the `-c` payload word-split is `set -f` so glob
    tokens can never pathname-expand into an unrecordable directory listing. The `_FE_FILES` memo carries a
    parallel `_FE_PROBESETS` slice so a memo consumer's record inherits the extractor's probes — without it a
    created-at-recorded-miss path inside a shared helper invalidated only the extractor (review P1). What is
    cached is selection METADATA only — `_diff_touches` still runs fresh per record and suite verdicts are
    never memoised (the twice-rejected suite-result shape, #7454 / #9804 Proposal 2). The walk emits
    `AFFECTED_DERIVE_CACHE state=/hits=/misses=/derived=` on stderr (stdout is the bench's machine-compared
    surface) so a dead cache is visible rather than silent. Identity gate: `affected-prepass-bench
    --added-edges` exits 0 with byte-identical `AFFECTED_SELECTED` cold AND warm (the bench's own second probe
    serves the warm arm); measured warm derive ~11–20 s CPU vs ~88–126 s base (6.3–7.8x) on probe 2, ~9 s wall
    vs ~2 min locally, cold arm ~27–71 s slower once per record per tree-state under contention. Per-record
    files (not one JSON) keep a single corrupt record's blast radius at one registration; `.soleur/`
    (gitignored, per-worktree) over XDG because a record is meaningless outside its worktree and the
    `worktree`+`cwd` fields refuse a moved checkout or a subdirectory invocation. The input-site census row in
    `scripts/test-affected-derive-cache.test.sh` fails on any future probe, file read, or out-of-span
    derive-family helper added to the derive span without recording — the standing guard against a silent
    invalidation weakening. Residual accepted and documented: a file edited mid-walk can mint a torn record
    (edges of content v1 keyed to hash v2, sticky until the next change) — hashing at read time would cost the
    per-file forks the design exists to avoid.

## Amendment — 2026-10-10 (#9813)

22. **The declared-edge grammar has a third kind, `glob:<literal-head>/<glob-tail>`, for corpus
    walkers whose read set is narrower than a directory.** Six `*.sh` corpus walkers declared
    `knowledge-base/` — honest at prefix granularity (generated operator scripts ship under
    `knowledge-base/project/specs/`) but over-broad in practice: a `.md`-only kb diff could never
    move their verdict yet selected all six for ~264 committed seconds (the issue's ~331 s figure
    counted `test-affected-kb-consumers` too, which still selects on any kb path by design; the
    five extension-bounded walkers that took the glob account for ~248 s of it). A
    `glob:` entry mints `^glob:<pattern>`; a diff line under the literal head matching the tail
    under bash `[[ == ]]` semantics (`*` crosses `/`, so `knowledge-base/**.sh` covers both `x.sh`
    and `a/b/c.sh`) selects the suite. The degrade ladder always fails toward coverage: a missing
    head dir mints `^<head>/` (the dir-prefix edge the entry replaced), a malformed entry mints
    `^glob:<entry verbatim>` — an always-match shape, since a bare `^` would evaluate `*\n\n*` and
    narrow — and a `glob:` with no metachar recurses as a literal path entry. `glob:` is
    declaration-array-only by intent: the token extractors never emit it on purpose (a
    `glob:`-spelled literal in scanned content still hits the same mint arm — widen-only), and the
    relevance arrays stay verbatim substring edges. The malformed-shape doctrine — a closed
    charset (`[-A-Za-z0-9_./]` plus `*` in the tail) and a repo-relative head (a `..`/`/`/`//`
    head can pass a `-d` probe while matching no diff line ever — review B1) — is pinned
    identical at five sites: the mint arm in `_affected_add_edge`, the in-flight revalidation in
    `_diff_edge_hit`, the census arm in `scripts/lint-orphan-test-suites.sh` (a static RED, since
    a bad entry widens every diff's selection), the `covers()` oracle in
    `scripts/test-affected-kb-consumers.test.sh`, and the `GLOBENT` shape in the
    registration-only classifier, which admits the shape as registration-only; every other added
    line stays semantic. The real `.md` read under kb the consumer ratchet surfaced —
    the provision-script `DPA_FILE` closure for `operator-ack-guard` — is a literal file edge:
    the issue's `.md`-only-decline contract holds for the corpus scan, not for reads a suite
    actually has. `lint-trap-tempfile-ownership` carries the wider seven-entry set its
    `ALL_EXT` corpus (.sh .bash .py .ts .mjs .js + bunfig.toml) reads, so an extension the
    issue's `*.sh` framing never named is not silently under-covered. Two suites keep
    `knowledge-base/` because their corpora are NOT extension-bounded:
    `scripts/test-affected-kb-consumers` (any kb file can be a consumer) and
    `plugins/soleur/test/operator-agent-runnable` — its Guard-1 discovery is `git grep
    --untracked` for the generated-script marker on ANY extension, a content-keyed read the
    review surfaced (a kb `.md` quoting the marker is in its corpus; `**.sh` would
    under-cover, ~16 committed seconds is the price of honesty).

Alternatives added by this amendment:

| Alternative | Why not |
|---|---|
| Per-suffix literal edges (one `^`-anchored file edge per corpus member) | A new `.sh` file under kb would silently under-cover until the arrays were re-edited — the exact drift class the glob tail exists to absorb. |
| Keep `knowledge-base/` and accept the over-selection | The measured cost is ~331 committed seconds per kb-markdown diff — the entire motivation for the ticket. |
| A regex edge kind instead of the bash-pattern glob | Bash `[[ == ]]` patterns are already the runner's grammar (`*.test.sh` glob registration, anchored edge matching); a second matcher family adds a semantics to keep consistent at the mint/hit/census sites for zero measured need. |
| Malformed `glob:` mints a bare `^` | A bare `^` evaluates `*\n\n*` against the normalized blob — it matches only diffs containing an EMPTY line, which narrows instead of widening. `^glob:<verbatim>` is the always-match shape the hit arm recognizes by rule. |

## Amendment — 2026-10-11 (#9814)

A local run reports local-vs-committed weight drift as an advisory line, never
a gate. `scripts/test-all.sh` defaults `TEST_TIMING_LOG` to
`$_durable_log_dir/suite-timings.tsv` on local affected-shaped runs
(`CI` unset, `TEST_TIMING_LOG` unset, `TEST_GROUP=affected` or
`_AFFECTED==1` on the all-group default — the two selectors stay disjoint by
design, and enumerate/print paths decline before paying a `mkdir`), guarded
by a `mkdir -p` + `[[ -w && -O ]]` probe — `-w` degrades an unwritable target
to "no timing log" instead of a `>>`-under-`set -e` mid-run abort, and `-O`
declines a co-tenant-owned pre-created leaf (the `basename-$$-EPOCHSECONDS`
name is predictable), followed by `: >` truncation so a bash-3.2 PID-reused
dir never serves stale rows, and an armed `[note]` naming the log path.
The assignment is IN-SHELL, never `export`: every consumer (`run_suite`'s
`>>`, `_emit_bytes_probe`, the epilogue emit) reads it in the runner's own
process, and an exported var would leak this run's log path into every
nested copy of the runner that runner-SUT suites spawn — phantom
`committed=unmeasured` lines on exactly the runner-touching diffs this
feature is for. (Corollary: every runner-SUT sandbox inherits the arm —
sibling fixtures opt out with `TEST_TIMING_LOG=/dev/null`.) The epilogue then calls
`weight_drift_report` (`scripts/lib/test-weight-drift.sh`, one `LC_ALL=C awk`
pass, bash-3.2-safe, always returns 0) over `"$_scriptdir"/suite-durations*.tsv`
— the glob, not two literals, so a future manifest joins the comparison
instead of mis-reporting `unmeasured`. The emit sits in the post-marker NOTE
region: `=== N/N suites passed ===` stays the last `===`-shaped line and a
monitor exiting on the marker never sees the lines, which is accepted — they
live in run output and the durable TSV. The predicate is strict
`local > 2*committed AND local > 10000` (`WEIGHT_DRIFT_FLOOR_MS`, value-pinned
beside `LOCAL_FAST_CAP_MS`'s convention); ran rows with no committed row emit
`committed=unmeasured` (absence is visible, never silent), `floor`-class
anchors add `basis=floor`, and a log whose ran rows all show `elapsed_ms=0`
emits `WEIGHT_DRIFT_UNAVAILABLE` once — the bash-3.2 vacuity is named, not
read as clean. Lines dual-emit to stdout and stderr: a line that only reaches
stderr is invisible to the invoking agent's stdout capture. The new suite
registers as `ALWAYS_ON_SUITES` + an `AFFECTED_*_PATHS` block whose manifest
edge is `glob:scripts/*.tsv` — not `suite-durations*`: the #9813 grammar
requires a /-terminated literal head, so a file-prefix glob cannot be declared
and covering the manifest class is the honest widening — and its committed
weight row is
written only by `regenerate-shard-manifest.py --incremental --write`
(ADR-240: generated, never hand-edited).

Alternatives added by this amendment:

| Alternative | Why not |
|---|---|
| Gate on drift (fail the run) | A contended host inflates every ratio (7.6x and 6.0x measured on the 2026-10-09 spot-check); a gate would flake every local run on a loaded machine. The issue's own posture is warn-only. |
| Opt-in only (no default; require TEST_TIMING_LOG set) | An opt-in instrument is invisible by default — the exact shape that let the 185s-vs-8.5s suite slip through #9763 unnoticed. |
| Local-median baseline file | Needs a local timing corpus that does not exist; committed rows are the only baseline, and they are what the fast-tier ratchet is charged against, so drift-from-committed is the meaningful signal. |
| Compare against `_suite_budget_ms` declared budgets | That predicate compares per-suite DECLARED budgets, not committed CI weights; a suite with no declared budget is invisible — the same unaccountability class this amendment closes. |

## Amendment — 2026-10-11 (#9815)

Context: decision 3's affected-selection doctrine ("the diff that makes a suite relevant is the diff that
selects it") stopped at suite granularity — the two webplat vitest legs always ran their whole projects on any
app diff (~82 s `unit`, ~80 s `repo-wide+component`, measured in #9763). This amendment extends the doctrine one
level down, to intra-suite narrowing, and records the mechanism and its bounds.

23. **Intra-suite narrowing follows the same eligibility doctrine as suite-level selection: narrow only inside
    a positively-armed affected-shaped local run, and every decline lands on the full shape.** When the local
    gate is armed (`TEST_GROUP=affected`, or the default `_AFFECTED` path with no `_aff_fallback` degradation),
    `CI` unset, `SOLEUR_TEST_FORCE_ALL != 1`, and the diff decidable (`_diff_detect_ok`/`_diff_head_ok`), the
    runner computes the diff's app-relative changed files and hands them to the suite command as
    `WEBPLAT_RELATED` — an `env` prefix on the registration, never exported, so a nested runner child cannot
    inherit a parent's list. The `repo-wide` project can never be narrowed (its subject is the repository) and
    runs full inside every shape; `unit` and `component` narrow-or-fall-back. Zero resolves are a coverage
    verdict, never a green: the wrapper greps vitest's own `No test files found` phrase — a version-pinned
    string, so a vitest bump that rewords it reds the suite's real-binary arm on the bump diff — and re-runs
    the full project. A nonzero `related` rc propagates WITHOUT a fallback re-run (a red is a verdict, not a
    coverage gap). CI legs are untouched by construction: the `CI` conjunct leaves `WEBPLAT_RELATED` empty and
    the empty path IS today's exact `npm run test:ci` invocation, shard forward included.

24. **The run-semantics set (`WEBPLAT_RELATED_META`) is a measured enumeration, not a heuristic.** Fourteen
    entries derived from the actual tree: every file that changes *what the run means* — both vitest configs,
    the project-membership file, the containment guard (the doctrine anchor), every `setupFiles:`/`globalSetup:`
    entry the config names (verified invisible to `related`'s import graph — a setup diff would otherwise
    narrow out the very tests that exercise it), the package manifest pair, `tsconfig.json`, `.npmrc`,
    `.nvmrc`, the wrapper itself (the narrowing mechanism never narrows its own diff), and the predicate lib.
    `test/helpers`, mocks and fixtures are deliberately NOT meta: they are ordinary import-graph members and
    `related` resolves their importers correctly — the issue's "shared helpers" prompt is satisfied by the
    graph, not the list. Every member must exist on disk (the suite's A9d arm pins the derivation).

25. **The degraded-full verdict is the boundary below which no narrowing may hide.** `_aff_fallback` non-empty
    (runner-changed, index-missing, undecidable-diff, force-all degradation) is the runner's own statement
    "this affected run degraded to the full battery" — a run carrying that verdict must not run a narrower
    shape inside itself, so the same flag gates the computation. Enumerate passes compute `""` deterministically
    (the command record is stable across enumerate and execute).

26. **The runner-side vocabulary is `vitest related <files> --run`, not `vitest run --related`** — the issue
    text's spelling does not exist at the pinned vitest (4.1.11): `related` is a distinct subcommand that takes
    the project flag. The wrapper keeps `--run` (the docs-prescribed non-watch form); the measured uncertainty —
    at 4.1.11 a `related` call over positional files exits clean without it — is recorded rather than asserted:
    the pin is static (the flag's presence is asserted, and removing it reds the pin), the behavioural necessity
    is not claimed. Dynamic `import(var)` is invisible to `related`'s static graph (3 sites in
    `cron-ux-audit.ts`; the meta set and the zero-resolution fail-safe bound the residual: a change that
    exercises behaviour ONLY through a dynamic import narrows to zero tests and falls back to full).

Alternatives added by this amendment:

| Alternative | Why not |
|---|---|
| Narrow at the registration edge instead of inside the suite | The registration's `if _diff_touches` gate already answers "app diff or not"; the narrowing question is WHICH test files inside an app diff — an argv-level answer the runner can compute but only the vitest import graph can resolve. Putting resolution inside the suite keeps the runner's job to eligibility + the file list. |
| `vitest run --related` (issue text's spelling) | Does not exist at vitest 4.1.11 — `CACError: Unknown option`. `vitest related <files> --run` is the real form. |
| Export `WEBPLAT_RELATED` | The #9814 learning's env-scrub class: an exported var leaks into every suite child (a nested runner would inherit the parent's list). `env` per registration is the bounded channel. |
| Meta-hit = subset of diff under the app | Two meta entries live outside the app (`scripts/lib/test-affected-paths.sh`'s sibling, `test-relevance-paths.sh`) — membership is checked against the whole diff, not only app paths. |
| Decline the whole feature because `related` misses dynamic imports | The residual is bounded: zero-resolution falls back to full, the meta set covers run-semantics files, and a dynamic-import-only change is already the class of diff a reviewer flags. Accepting a bounded coverage gap buys the measured ~40-60 s per app diff. |

## Amendment — 2026-10-13 (#10117)

Context: decision 22's `glob:<literal-head>/<glob-tail>` edge kind covered every corpus member
under a directory but stopped at the grammar boundary — a dir-less corpus file at the repository
root (`x.test.sh`, `x.sh`) has no `<dir>/` head to mint, so no declared edge can cover it and its
diff would select no corpus suite: a silent hole. The same fix round's review identified two
further residuals on different surfaces: `--paths` elements were diff-name stand-ins that never
matched a git path line (`./x` silently selected nothing — a misleading diagnostic), and the th6
root-coverage census certified a `glob:<root>/` edge by *suffix shape* rather than *matchability*
(a `sub/*.test.sh` tail ends in `.test.sh` yet reaches only that subtree — it under-covers the
root the corpus scan enumerates).

27. **The root-anchored `glob:` grammar stays unrepresentable; detection, not extension, is the
    durable posture.** A dir-less corpus file is detected loudly — the th8 row in
    `scripts/test-all-affected.test.sh` re-derives the single-component complement of
    `git ls-files` (`.test.sh` and `.sh`-but-not-`.test.sh` as disjoint classes, with a
    producer-liveness floor and `_TH_REPO` fixture confinement) and REDs the first battery run
    carrying one — while the grammar extension is deferred to #10198 and activates only when a
    live member exists. The row stays RED on existence alone: a literal edge or an ALWAYS_ON
    entry covers the file's *selection* in the interim but does not clear it — the durable exits
    are moving the file under a covered root or landing the #10198 extension (at which point the
    row's expectation revisits what the new grammar expresses). The decision is *detect now,
    extend on evidence* — the grammar grows for a member that exists, never for one that might.
    Companion hardening in the same change: `--paths` elements normalize a leading `./` run to
    fixpoint at the parse arm and refuse unclean spellings (empty elements, absolute, `..` or
    `/.` or `//` segments, a trailing `/`, control bytes) with a named rc-2 error — a print-only
    diagnostic that silently selects nothing is a lie; and the th6 census predicate now requires
    a literal `glob:<root>/` head plus a bare `*<ext>` or `**<ext>` tail, so only an edge that
    can actually match the corpus class certifies it. Note for readers of
    `scripts/audit-suite-reads.sh`: its `UNCOVERED_AWK` compares an edge by literal equality or
    `<dir>/` prefix only, so a read covered solely by a `glob:` member reports as uncovered —
    over-report, the safe direction; those rows are not oracle disagreements.
