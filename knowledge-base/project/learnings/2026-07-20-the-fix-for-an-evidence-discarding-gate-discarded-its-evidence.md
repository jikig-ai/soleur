---
date: 2026-07-20
problem_type: logic_error
component: infra
module: workspaces-luks-cutover
severity: high
tags: [fail-closed-gate, evidence-discarding, git-fsck, differential-gate, command-substitution, vacuous-tests, test-harness-verification, observability]
issue: 6733
synced_to: []
---

# Learning: the fix for an evidence-discarding gate discarded its own evidence

## Problem

The pre-repoint integrity gate in `apps/web-platform/infra/workspaces-cutover.sh` was

```sh
git -C "$ws" fsck --full >/dev/null 2>&1 || { fsck_fail=…; log "FSCK FAIL: $ws"; }
```

Two defects: evidence discarded (`>/dev/null 2>&1` throws away the only datum separating a corrupt
object from a benign repo condition, and `hr-no-ssh-fallback-in-runbooks` means there is no second
way to ask), and the wrong property measured (it tested "are these repos pristine", not "did the
copy corrupt anything"). Real cutover run 29725194755 safe-aborted on 8 of 10 workspaces with no
way to know why.

**The PR written to fix that reinstated defect (1) inside its own fix.** The shared emitter
`_fsck_emit_and_verdict` returned its verdict on **stdout**, and both call sites wrote
`abort_cls="$(_fsck_emit_and_verdict …)"`. That function's stdout **is** the marker stream (`echo` at
column 0, mirroring `emit_verify_diff`), so command substitution captured every
`SOLEUR_WORKSPACES_LUKS_FSCK` row into a shell variable: the run log and Better Stack received
nothing. Observed during implementation, not theorised.

This is the **third** instance of the evidence-discarding class on this one script: the C1 byte-identity
verify before the #6604 follow-up, the G4 holder probe before #6735, now the fsck gate.

## Solution

The verdict goes to a **file** (`$work/verdict`), read back with `cat`; both entry points call the
emitter **directly**, never in `$(…)`, a pipe, or a subshell (`workspaces-cutover.sh`, see the
`_fsck_emit_and_verdict` header comment and `verify_git_fsck_differential`).

**Generalizable rule:** when a function's stdout **is** a telemetry stream, its return value must go
to a FILE. **Litmus:** grep whether any caller wraps it in `$(...)`. If one does, the telemetry is
already gone.

## git fsck semantics every integrity gate gets wrong (all measured, git 2.53.0)

- **rc is a BITMASK.** Corruption is rc **3**, not 1.
- **rc 0 does not mean clean.** Broken `objects/info/alternates` emits `error:` lines at **rc 0**. A
  "both rc 0 → ok" short-circuit makes a differential gate *weaker* than the rc-only gate it replaces.
- **The report spans BOTH streams.** A missing object is **rc 2 with `missing blob` on STDOUT and
  stderr EMPTY**. Folding the streams is exactly defect (1) of the old C1 verify.
- **THE DECISIVE ONE.** A corrupt loose object exits **rc 128 with a `fatal:` line**
  (`fatal: loose object <sha> … is corrupt`) — indistinguishable *by rc* and *by the presence of a
  fatal* from the setup failure `fatal: bad config line 1 in file .git/config`. So keying a "probe
  could not inspect" classification on `rc == 128` or on any `fatal:` is wrong in **both** directions:
  it labels genuine corruption "nothing was verified", and it makes a fault present on **both sides**
  abort — which is precisely the false positive a differential exists to remove, reintroduced under a
  new name. Discriminate on the **KIND** of fatal: a setup-fatal allowlist
  (`_FSCK_SETUP_FATAL_RE`) vs a content-fatal allowlist (`_FSCK_CONTENT_FATAL_RE`), and fail
  **CLOSED** (`unclassified`) on any fatal matching neither.
- **`--name-objects` appends in-repo file PATHS** — but even WITHOUT it, fsck names user-authored
  **ref paths**: `error: refs/heads/feature/acme-payroll: badRefOid: …`. Branch names carry client
  names and ticket titles. Anything shipping fsck output to a third-party log sink must **scrub ref
  paths** (`_fsck_scrub_first`), not merely decline the flag.
- **A linked worktree fsck'd at a COPIED path follows its absolute `gitdir:` pointer BACK ACROSS THE
  MOUNT** and reports the ORIGINAL filesystem's state — false positives *and* false negatives about
  the copy. Same hazard for an `alternates` entry pointing outside the probed root.

## Three ways a differential gate silently becomes a no-op

1. **A cap that bounds a capture also bounds the COMPARISON that reads it.** The code asserted "caps
   apply to EMISSION only" in a comment and it was false: `_fsck_one` truncated the raw captures and
   `_fsck_normalize` read those same files. Worse, asymmetric in the **unsafe** direction — dst paths
   carry `/mnt/data-luks/` vs src's `/mnt/data/`, 5 bytes longer per occurrence, so dst loses its tail
   FIRST, preferentially discarding exactly the dst-only lines that abort. Demonstrated with
   truncation as the only variable: `copy_corruption` → `preexisting`. Fix: record the ceiling hit and
   classify `unclassified` → abort, never compare a partial set.
2. **`ok` from a differential is byte-identical to "inspected nothing."** Fix: a per-side object-count
   floor via `git count-objects -v` (`ok|preexisting|src_only` → `copy_corruption` on
   `dst_objs < src_objs`, `unclassified` on both zero). Proven **non-vacuous** against an
   UNREFERENCED object removed from the copy: it emits no error line on either side (dangling is
   filtered as a notice), so the error-line differential is structurally blind to it and only the
   count sees it.
3. **A skip/exclusion path removes a workspace from the population entirely.** "Visible, not silent"
   is not "safe" — nothing between a log line and a later destructive phase reads it. Skips are
   counted on the summary row precisely so a non-zero count is a legible coverage hole.

## Test-side: four vacuity shapes, all green

- **A case can be UNSATISFIABLE and never noticed.** L6h asserted `truncated=1`, which requires
  rows > cap, with ONE workspace at `cap=1` — `1 > 1` is false, so it could never have been observed
  green. It shipped with a confident failure message naming exactly the right risk.
- **Independent whole-file greps pass with the classifications attached to the WRONG subject.** L6d
  asserted `copy_corruption`, `preexisting` and a `ws=` id as four separate greps, so a SUT that
  labelled the SHARED fault `copy_corruption` and the DST-ONLY fault `preexisting` satisfied all four
  — the case named "path prefixes normalized" went green under exactly the normalization hole it
  exists to exclude. Fix: anchor classification and `ws=` on the **same line**, plus a negative
  control on the inverse.
- **A fixture selected by `find | head -n1` picks by readdir order**, which on ext4 is a hash of the
  entry name — so the classifier branch under test was a coin flip per run (commit/tree → rc 128 +
  content fatal; blob → rc 3 + `missing blob`, zero fatals). Select **by type**: `corrupt_loose <repo>
  <commit|blob>`.
- **Asserting a marker only on a stubbed `logger` leaves the STDOUT channel unguarded** — and stdout
  was the channel the whole PR existed to restore. Re-introducing the command-substitution regression
  would have left all ten cases green.

## Verifying the verifier

The first local driver returned **rc=0 on all four scenarios** — clean, corrupt, both-fail and
probe-failed alike — because `git add -q` is invalid on this git version and loose objects are mode
0444, so **no fixture was ever built**. ALL-GREEN ACROSS SCENARIOS THAT SHOULD DIFFER is the tell for
a broken harness, not a working SUT. Before trusting a driver, confirm at least one scenario **FAILS**.

## Session Errors

1. **`ionice -p $$` would have left the ENTIRE cutover at idle I/O priority**, including the
   freeze-critical delta rsync — `$$` does not change inside a subshell. Recovery: `$BASHPID` inside
   the advisory-probe subshell. **Prevention:** in any "re-nice just this part" subshell, `$$` is
   always the wrong variable; use `$BASHPID`.
2. **Verdict returned via `$(...)` swallowed every marker row** (the headline). Recovery: verdict to a
   file. **Prevention:** if a function's stdout is a telemetry stream, grep its call sites for `$(`
   before trusting the sink.
3. **First local driver: all four scenarios rc=0, no fixture ever built** (`git add -q` invalid on
   this git version; loose objects 0444). **Prevention:** a harness that is green on scenarios
   designed to differ is broken; require one deliberate FAIL before reading any pass.
4. **The same 0444 hazard was live in the test file's `corrupt_loose`** — under non-root it would have
   silently returned an *uncorrupted* repo, making every dst-only assertion vacuous. Recovery:
   `chmod u+w` + a loud `FIXTURE ERROR` on failure to write. **Prevention:** fixture helpers must fail
   loudly, never return a half-built fixture.
5. **The plan's own rule-2 discriminator was falsified by measurement at implementation time**
   (`rc == 128`/any-`fatal:` ⇒ probe_failed). **Prevention:** a plan's discriminator is a hypothesis;
   measure it against the real tool before implementing on top of it.
6. **Eight further gate-blinding defects found by review agents:** root-dependent `<WS>/` normalization
   producing spurious dst-only lines; `alternates` containment tested against only the side's own root
   (H2's shape → `unclassified` abort mid-freeze); whole-file instead of per-line alternates scanning;
   a non-total classifier table defaulting unmatched states to green; signal-killed probes (rc > 128)
   with a partial walk classifying `preexisting`; hardcoded `/mnt/data*` prefixes making two
   substitutions unconditional no-ops under the loopback harness; missing `LC_ALL=C` on `sort`/`comm`
   (locale collation makes `comm`'s diff undefined); `git … | head -c N` under `pipefail` yielding rc
   141 → `unclassified` on a healthy run. **Prevention:** already covered by
   `rf-never-skip-qa-review-before-merging`; the pattern is that every one of them turned an abort into
   a pass, never the reverse.
7. **Four vacuous/unsatisfiable test cases** (the section above). **Prevention:** for every assertion,
   state what SUT behaviour would make it fail; if none exists, the case is decoration.
8. **Plan ACs 1 and 2 returned 1 against CORRECT code** because the new comments quote the forbidden
   strings (`>/dev/null 2>&1`, `$(_fsck_emit_and_verdict`) verbatim. This is a recurrence of
   `cq-assert-anchor-not-bare-token`. Recovery: strip comment lines before the grep.
   **Prevention:** already rule-covered; anchor body-greps on syntax the file's own prose cannot carry.
9. **WORKFLOW ERROR:** the session ended a turn on a `## Review Phase Complete` marker with the text
   "Next: compound, then ship" instead of invoking the successor skill in the same response; the
   operator had to ask "why did you stop here?". **Prevention:** a phase-complete marker is a
   checkpoint, and the next tool call in the SAME response must be the successor skill — stating an
   intention is not performing it.
10. **The loopback suite could not run locally** (uid 1001, no passwordless sudo for losetup/cryptsetup);
    device-level verification was deferred to CI at `.github/workflows/infra-validation.yml`.
    **Prevention:** state which verification channel actually ran rather than implying a green suite.

## Cross-references

- `apps/web-platform/infra/workspaces-cutover.sh` — the `_fsck_*` family (`_fsck_one`,
  `_fsck_normalize`, `_fsck_probeable`, `_fsck_classify`, `_fsck_emit_and_verdict`,
  `verify_git_fsck_differential`, `fsck_advisory_probe`)
- `apps/web-platform/infra/workspaces-luks-loopback.test.sh` — `corrupt_loose`, `break_alternates`, L6a–L6h2
- `knowledge-base/project/plans/2026-07-20-fix-workspaces-luks-fsck-gate-differential-evidence-plan.md`
- `knowledge-base/project/learnings/workflow-patterns/2026-07-19-real-cutover-routes-to-workflow-dispatch-and-failclosed-gate-must-self-report.md` — instance 1 of this class (C1 verify)
- `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
- ADR-119 (`knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`)
