# Every fixture for the kernel-denial row fed its hints through stdout and held one denial, so both the stderr merge and the selection logic were unpinned

**Issues:** #9860 (Ref only) · **PR:** #9938 · **Date:** 2026-10-11

## Problem

PR #9938 adds a `kdeny` row to the canary DIAG bundle: a bounded, scrubbed host-side read of the kernel stream (journal rung,
then dmesg rung), reported as `src= j= d= total= hits= mproc= [fields]`. A 13-seat panel, three fix-round seats and a
verification seat reviewed it. The defects that survived the author's own mutation battery were all fixture-shape defects:

- **The hint text arrived on stdout.** Real `journalctl` and `dmesg` print their "not allowed to read" hints to STDERR. The
  mock printed them to stdout, so deleting `2>&1` from either read left every row green while production would have read
  `noaccess` as `empty` (the difference between "could not read" and "read it, nothing there", which the row exists to state).
- **Every fixture held at most one denial line.** `hits++` -> `hits=1`, `mproc++` -> `mproc=1`, the newest-first selection and
  the "mount denial beats a newer non-mount denial" ternary were all unobserved. D10h repeated one line 400 times and asserted
  only the prefix and the length.
- **The `error` state was never reached** (no fixture with rc 1, no hint, no lines), and the 130-character field cap was only
  bounded above by the 200-character tail, so it could drift to 146.
- **`sdk_noproc` was checked by name and flag, not as a control.** An argv that differed from `sdk_probe` in a second way
  would have confounded the H6 reading the row exists to isolate.
- **Two classifier holes the fix round found in its own fix:** an `fstype` guard that accepted an unbalanced quote
  (`"?...?"`), and a second hit test (`type=1326 audit(`) that was not anchored like the first, so free text inside an
  ALLOWED record could raise `hits`. A non-zero exit AFTER an anchored denial discarded a real record.

## Solution

- Give the mock an `_ERR=1` knob that writes the fixture to stderr, and run every hint fixture through it. Deleting `2>&1`
  now fails two rows per rung.
- Add multi-denial fixtures whose answer differs under each single-line mutant: two mounts (newest fields win), two opens
  (mproc stays 0), an older mount plus a newer open (the mount wins the fields). 13 targeted mutants, 13 killed.
- Pin the measured cap exactly (`-eq 130`) rather than a band, and assert `hits == total` on the repeated-denial fixture.
- State a control's property as an equality, not as two greps: `"${probe// --proc \/proc/}" == "$noproc"`, with the guard
  that BOTH greps matched exactly one line so empty-equals-empty cannot pass.

## Key Insight

A fixture is a claim about which inputs the code can see. A mock that cannot produce the channel the real tool uses (stderr),
or that holds at most one record, makes every mutation of the code that handles the missing dimension equivalent. When a
reader merges streams or selects among records, ask what the fixture CANNOT express and add the smallest input that can.

## Session Errors

1. **Floor measured in a sandbox.** The scratch sandbox has no `.git`, so rows using `git grep` fail (`git-grep-rc=128`)
   and the TOTAL (605, one failure) differed from the live tree (608/608). **Recovery:** measured on the live tree.
   **Prevention:** added a bullet to `plugins/soleur/skills/work/references/work-scratch-sandboxes.md` ("measure an assertion
   floor on the LIVE tree").
2. **A stale sandbox path was reused.** The pointer file named a sandbox another cleanup had removed, so the trim script
   printed `boundary not found` for every row. **Recovery:** allocated a fresh sandbox and regenerated the scripts.
   **Prevention:** the harness now takes the path from one file written at allocation; check `ls -d` before a run.
3. **Backticks inside a double-quoted `diag_check` label ran as a command** (`--proc: command not found`). The assertion
   still passed, so only the verification seat's read of the run log found it. **Recovery:** removed the backticks.
   **Prevention:** none beyond reading a suite's stderr for `not found` after adding a label; a lint for command
   substitution in test labels was judged not worth its own guard.
4. **D10h asserted `mproc == total`.** `head -c` cuts the OLDEST line mid-record, so one record loses `fstype` and
   `mproc == total - 1`. **Recovery:** asserted the real relation and wrote the reason in the label. **Prevention:**
   assert on a measured value, not on the value the fixture's intent suggests.
5. **`git stash list` in a command was blocked by the PreToolUse hook.** The hook matches the substring. **Recovery:**
   dropped it. **Prevention:** none needed; it was not an intended stash.
6. **Earlier in the pipeline (carried from the compacted context):** suite cleanup deleted `/var/tmp` logs; `$M` landed in
   `$0` under `bash -c`; a trim script used fixed line numbers that went stale; two mutants (the 9999 cap and a census
   control that tripped two rules at once) survived the first battery; a Python edit script's stray assertion aborted
   before writing; `pgrep -f` was blocked by a hook. **Prevention:** logs in the scratchpad, argv passing as `_ "$M"`,
   boundaries located by function name, single-rule fixtures for census controls.
7. **Duplicate Monitor notifications.** Each event re-delivered the whole accumulated list, so a status line had to be
   written for repeats. One-off friction; a per-event filter that prints only new lines would avoid it.

## Tags

category: test-design
module: apps/web-platform/infra/ci-deploy
