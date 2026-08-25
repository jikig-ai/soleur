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
