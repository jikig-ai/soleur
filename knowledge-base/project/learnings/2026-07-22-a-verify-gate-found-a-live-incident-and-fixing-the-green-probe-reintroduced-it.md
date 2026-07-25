# A ground-truth verify gate found a live P0, and fixing the green-probe bug reintroduced the green-probe bug

**Date:** 2026-07-22 · **Issue:** #6807 (PR) · **Incident:** #6812 · **Branch:** feat-one-shot-6807-luks-canary-verify-probes

## Problem

#6807 was a probe-code fix: three defects that made a *successful* /workspaces LUKS cutover report
failure, plus a coverage gap (the off-host verify never asserted the volume was actually serving
user data). The plan's Phase 2 was a hard gate — dispatch the read-only verify workflow to answer
the one open question: *is the repointed volume populated?*

Two things happened that are worth compounding, and neither is "the probe fix."

## Key insight 1 — a verify/ground-truth gate can surface an INCIDENT, not a pass/fail

The Phase 2 dispatch returned `FAIL (mount_not_mapper): mount_source=/dev/sdb`. That is not "the
fix's test failed" — it is **production is broken**. The 2026-07-20 cutover had landed, served
~27 minutes, aborted at `app_canary` on a Cloudflare 521, and then its own **dead-man timer
remounted the retained plaintext volume over the healthy LUKS mount** ~27 min later. `/mnt/data` was
raw `/dev/sdb`; encryption-at-rest was not in effect; ~27 minutes of sole-copy user writes were
stranded on a now-unmounted LUKS volume; and **nothing paged for ~6 hours**. Filed #6812 (P0).

The load-bearing moves:

- **Read the actual marker, not the run status.** "run: failure" on a verify meant to catch this is
  the *signal working*, not the fix breaking. The `mount_not_mapper mount_source=/dev/sdb` line is
  the finding.
- **Pull the observability layer to reconstruct the timeline** (`hr-no-dashboard-eyeball-pull-data-yourself`):
  Better Stack journald showed `OK: /mnt/data is LUKS-backed` at 22:18, then
  `workspaces-luks-deadman.service: Failed with result 'exit-code'` at 22:42. Source confirmed the
  causal chain: `CANARY_OK=1` is set BEFORE `app_canary`, so a canary `die` skips both rollback
  (`cleanup()` guard) AND `disarm_dead_man` — the armed timer wins.
- **A resume prompt's "prod is healthy, LUKS-backed" was TRUE when written (22:20) and FALSE 22
  minutes later (22:42).** A stated-fact carried forward from a prior session is a claim to
  re-verify against live state, exactly like a plan-quoted count — the more so when a timed backstop
  can flip it after the sentence was written.

The disposition that mattered: **do NOT reach for `ROLLBACK=1`** on seeing "failure" — the dead-man
had already done the plaintext remount, so rollback would recover nothing and could destroy
post-cutover writes. The operator accepted the loss and authorized a re-cut AFTER the fixed probes
merge (a re-cut on the old code would hit the same 521 and re-arm the same dead-man).

## Key insight 2 — fixing a green-probe-that-cannot-fail bug re-creates the class inside the fix

This is a **recurrence** of a densely-documented class (see
`2026-07-20-i-fixed-three-unfailable-gates-and-shipped-eight-more.md`,
`the-fix-for-a-green-with-no-artifact-bug-shipped-green-with-no-artifact.md`,
`my-fix-for-a-crash-class-reintroduced-the-crash-class-three-times.md`,
`2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md`). It recurred here, and multi-agent
review caught three fresh instances — the new, reusable artifact is a **degenerate-operand
checklist** for any PR whose whole point is "assert the thing it names":

1. **UNREADABLE ≠ EMPTY.** `wl_count_workspace_dirs` guarded `[ -d "$root" ]` only. A root that
   *exists but cannot be listed* (search-but-not-read perm on the parent) then has both globs stay
   literal → count `0`, rc `0` — while the docstring PROMISED "returns non-zero if unreadable, caller
   fails closed." The cutover persists that `0` as the baseline, and `count -lt 0` is false for every
   count: a **permanently unfailable green** that a total wipe would pass. Fix: require `-r` AND `-x`.
2. **0 ≠ MISSING.** The baseline guard was `''|*[!0-9]*` — `0` is digits, so it passed. Same
   absorbing-green (`-lt 0` never true). A real host never has zero workspaces at a cutover. Fix:
   reject `0` as missing on both the host read and the workflow seed input.
3. **NON-NUMERIC left operand silently SKIPS.** `[ <non-numeric> -lt N ]` exits 2 ("integer
   expected"); inside an `if` under `set -uo pipefail` with no `-e` that reads as "not less than" and
   falls through to the green verdict. Guard BOTH operands, not just the one you happened to think of.
4. **exit 2 is bash-RESERVED** (syntax error / builtin misuse). A probe that means "readiness
   failure" by `exit 2` reports a *syntax error in itself* as a data-loss verdict routing to
   halt-and-escalate. Use 3. This is the confidently-wrong-verdict class one layer down.

The audit question for the whole PR: **for every new comparison/guard, name the degenerate operand
(unreadable, empty, zero, non-numeric, missing) and confirm it fails CLOSED, not toward the happy
verdict.** Four independent review agents converged on the unreadable-root path — a strong signal
that the degenerate-operand class is worth a dedicated pass, not incidental coverage.

## Key insight 3 — an unattended backstop must emit on its FIRE, not only on its error branches

The dead-man timer's inline command emitted a marker ONLY on `cryptsetup close` failure. A
**successful** remount — the backstop engaging and quietly undoing the cutover — emitted nothing on
any channel. That silence is exactly why #6812 was dark for 6 hours. Any unattended
backstop/self-healing guard (dead-man, failover, auto-remediate) must emit **armed / fired / outcome
(ok|failed) / disarmed** markers. "The backstop worked" is still an event someone needs to see,
because "the backstop worked" can mean "it reverted the thing it was backing up."

## Key insight 4 — a plan-prescribed doc correction can be falsified by an incident between plan-time and work-time

The plan said to correct `model.c4`/ADR-119's "PLAINTEXT AT REST" as *stale* (the cutover had
landed). But the dead-man made that claim TRUE again. "Correcting" it would have asserted
encryption-at-rest on a volume that is currently `/dev/sdb` — a false claim about a live security
property, pointing the same direction as the privacy policy's existing overclaim. This is the
"removing a false claim can strengthen the false claim"
(`2026-07-16-removing-a-false-claim-can-strengthen-the-false-claim-that-leaned-on-it.md`) trap in a
new shape: **a plan's instruction to fix a doc is itself a claim to re-verify against current state**,
because an incident can invert the doc's truth-value between plan-time and work-time. Wrote the
measured position (plaintext as of 2026-07-21, landing + auto-revert recorded), kept ADR
`status: adopting`.

## Session Errors

- **Broke the "no apostrophes inside a single-quoted `bash -c` body" harness rule** (wrote
  `ci-deploy.test.sh's`) → 3 suites failed at parse time. Recovery: reworded. **Prevention:** the
  harness documents this rule twice at the top; re-read the block's own NOTE before editing a
  `bash -c` body or a `<<'STUB'` heredoc. Documented class — one-off this session.
- **An `&&`-chain did not gate a `git commit` on a preceding Python assertion**, so a commit landed
  with a dead `$tmp` reference (would error under `set -u` on the readyz success path). Recovery:
  fixed + `--amend`, verified the committed blob. **Prevention:** when an edit's correctness is
  proven by a check, put the check and the commit in the SAME bash call with `&&`, or verify the
  committed blob (`git show HEAD:<file> | grep`) rather than trusting the tool's success report.
- **A concurrent review agent's restore-to-HEAD (`git checkout -- <file>` for its own
  mutation-testing) wiped my uncommitted inline review fixes** to `emit.sh` (all) and
  `luks-monitor.sh` (partial), mid-review. Recovery: re-applied everything, committed IMMEDIATELY,
  verified the committed blob. **Detection signal (new angle):** three brand-new tests went RED
  against fixes I believed I had already made — *tests failing against work you're sure you did = a
  silent revert; `git diff HEAD <file>` and grep for your markers before re-debugging.*
  **Prevention:** on a shared worktree with concurrent agents, commit each verified unit immediately;
  and mutation-test only on `mktemp` BACKUPS restored via `cp`, never `git checkout` (the tree is
  dirty, so checkout wipes siblings). Adjacent to
  `2026-07-02-concurrent-session-collision-on-shared-worktree.md` and
  `2026-07-15-ad-hoc-verification-evidence-is-as-perishable-as-uncommitted-code.md`.
- **A background `test-all.sh` completion notification reported "exit code 0" while the real rc
  (from the `echo $? > rc` file) was 1** — a genuine `lint-trap-tempfile-ownership` failure the
  notification masked. Recovery: read the rc file + the suite's own `N/N suites passed` line.
  **Prevention:** for `cmd > log 2>&1; echo $? > rc`, the notification is the trailing `echo`'s
  status; ALWAYS read the rc FILE and the runner's summary line. Documented class; recurred.
- **A new `mktemp -d` in a test tripped the tempfile-ownership lint** (no owning trap). Recovery:
  moved it under the harness's already-trapped `RUN_SCRATCH`. **Prevention:** in a suite that sources
  a harness with a scratch dir + EXIT trap, allocate under that dir; don't `mktemp` afresh. One-off.
- **Inline `python3 - <<'PY'` used `sys` without importing it** (`NameError`). Recovery: wrote the
  script to a file and ran it. One-off; a heredoc-python that needs stdlib should `import` at the top
  like any module.

## Tags
category: workflow-patterns
module: workspaces-luks / verify-gate / green-probe
related: 6807, 6812, 6754, 6808
