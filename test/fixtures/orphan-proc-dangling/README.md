# `orphan-proc-dangling` — a committed procfs fixture

This is the target of the `discoverability_test` in the #7537 plan, and the
control case the behavioural suite calls AC30b.

It is the fixture anyone would write FIRST, and it is silently wrong as a
positive arm — which is exactly why it is committed as a *control*. The `cwd`
symlink points at a path that does not exist and ends in `' (deleted)'`, so:

* `readlink` succeeds and returns a `' (deleted)'`-suffixed absolute path — a
  detector that tests the SUFFIX would flag this entry as an orphan;
* `stat -L` FAILS, so a detector that tests `st_nlink` counts it `unreadable`
  and leaves the process alive.

The probe therefore asserts `anchors=0 unreadable_gone=1`, which has information
content: a regression from the inode test back to a suffix test turns
`unreadable_gone=1` into `anchors=1` and reddens.

Nothing here is a real `/proc`. `reap` refuses a non-procfs root unless a signal
sink is injected, so pointing `report` at this tree is safe by construction.

## Why the two symlinks are no longer committed (2026-09-18)

`4242/cwd` and `4242/fd/255` were committed as dangling symlinks (`/nonexistent-orphan-fixture/…
(deleted)`). The GitHub Actions runner extracts this repository's archive whenever a workflow
references one of its actions by self-repository (`$/…`) or `owner/repo/path@ref` form, and
that extraction FAILS on a dangling symlink — measured on run 35360150848: `Set up job` ended in
`Could not find file '…/_staging/soleur-<sha>/test/fixtures/orphan-proc-dangling/4242/cwd'`, so
the job never started. The repository's five valid symlinks extract fine; only dangling ones do
not.

Nothing reads the committed tree at runtime: the control case (AC30b in
`scripts/orphan-process-reaper.test.sh`) synthesizes the same two dangling links under
`mktemp -d` with `ln -sfn` on every run, and that is where the property is asserted. The
remaining files (`cmdline`, `stat`, `uptime`) and this README stay so the shape is documented
in-tree. Do not re-commit a dangling symlink anywhere in this repository — synthesize it in the
suite that needs it.
