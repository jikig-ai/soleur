---
title: The local gate defaults to the affected set plus always-on ratchets; the full battery is CI or explicit --full
status: active
date: 2026-09-18
amends: ADR-181, ADR-183, ADR-196, ADR-133
related_adrs: [ADR-181, ADR-183, ADR-196, ADR-133, ADR-177]
amended_by:
  - "ADR-262 (2026-09-30, #9323) — decision 1's \"CI keeps the full battery\" and the merge-gate statements are narrowed for five self-test mutation batteries on a pull_request run; four labels leave ALWAYS_ON; see ## Amendment — 2026-09-30"
  - "#9173 (2026-09-29) — the diff-source scope axis (`--affected-scope=staged`) and the scope-aware `runner-changed` arm; see ## Amendment — 2026-09-29"
  - "#9307 (2026-09-30) — anchored edge matching, the runner-subcommand skip, `--print-selection` / `--paths`, and the evidence-based always-on audit; see ## Amendment — 2026-09-30"
  - "#9400 (2026-10-01) — the affected-ratchets pre-push lane moves the cheap ratchet net earlier than the local gate (push time, merged tree); the required `test` context remains the merge gate; see ## Amendment — 2026-10-01 (#9400)"
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
The measured figures live in `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md` (Rounds 2 and 3); they are not restated here.

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

19. **The recorder runs suites as the invoking user, and a recorded read set equal to the registration corpus means hedge, not declare.** The recorder
    now probes `unshare -cn` (the caller's own uid), falls back to `unshare -rn` (namespace-root, stamped `idmap=root`), then bwrap, and carries `unshare`
    on its scratch PATH, so an `unreliable` row can no longer be explained by namespace-root; rows recorded before 2026-10-04 are `idmap=root` and not
    comparable. **This supersedes, for `scripts/test-affected-kb-consumers`, `scripts/orphan-process-reaper-mutations` and `scripts/audit-suite-reads`
    only, decision 18's sentence that keeps them on their derived or declared edges with the evidence gap stated, and decision 18's threshold of about
    7 s under which a suite with no evidence is hedged.** The two suites with an instrument-side gap now have evidence (`covered`, and `uncovered` for
    directory listings only, with five file reads declared); the third reads the registration corpus itself (1,244 files over 24 directories), so it is
    hedged into `ALWAYS_ON_SUITES` at +68.4 s (+5.6%). **Revisit** that hedge when always-on suite time passes 1,500 s or when the suite becomes
    incremental, so "keep" does not become permanent by default. The reasoning, the measured costs and the final table live in the audit doc's
    2026-10-04 addendum (`knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md`); this entry does not restate them.
