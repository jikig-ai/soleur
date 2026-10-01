# Scratch sandboxes for mutating seats

Loaded by pointer from `work/SKILL.md` (instrument/artifact and self-invoked `.test.sh` bullets) and
`review/SKILL.md` ("Brief every mutating seat's sandbox size and lifetime"). Use it whenever a seat, a
mutation battery or a destructive experiment needs a MUTABLE copy of the working tree.

## Why this exists

`/tmp` on the dev host is a RAM-backed tmpfs with a fixed ceiling shared by every parallel worktree. A seat
that builds one full tree copy per mutant in the session scratchpad, with no cleanup, fills it; then every Bash
call in the session fails with no output until the operator frees space (#8292/PR #8536). A SIGKILLed seat never
runs its EXIT trap, so the failure also orphans the largest artifacts. The allocator below puts the copy on disk,
makes it small, stamps an owner marker at creation, and removes it with one command.

## Allocate, use, remove

```bash
SBX=$(bash scripts/soleur-sandbox.sh new <seat>)     # prints the absolute path on stdout
# ... run the battery / experiment with the sandbox as the working tree ...
bash scripts/soleur-sandbox.sh rm "$SBX"             # BEFORE the seat returns
```

- `new` prints ONLY the path on stdout (warnings go to stderr). `rm` takes the PATH, not a label: cleanup
  usually runs in a different Bash call than the allocation, so the path is the only state that survives. Echo it
  into the seat's notes so the cleanup call can use it.
- Allocate ONE copy per seat and restore it from a pristine backup per row/mutant. Do not allocate a copy per
  mutant.
- Remove it before the seat returns, on the failure path too. A seat that dies mid-run leaves a
  `soleur-sbx.<label>.*` directory with a `.soleur-owned` marker; the reapers attribute it by the marker's owner
  pid and reclaim it once that process is gone.
- `rm` refuses anything that is not a sandbox: the directory name must match `soleur-sbx.*`, it must carry a valid
  marker, its realpath must sit directly under a scratch base, and it must be owned by the current uid.
  A refusal is correct; do not work around it with `rm -rf`.

## What the copy contains (by design)

- The DIRTY working tree: `git ls-files --cached --others --exclude-standard`, so uncommitted fixes the seat is
  mutating are present. Tracked files deleted in the tree are absent.
- NO `.git`, so `git diff` / `git status` do not work inside the sandbox. This is deliberate: with no `.git` it can
  never enter the worktree registry (a detached worktree is a REGISTERED worktree that the classifier retains
  forever when unmerged). Diff against the live tree instead (`diff -r`, or `md5sum` before/after per mutation).
- NO `knowledge-base/` (the bulk of non-code bytes; seats mutate code, not docs).
- NO `node_modules`. Suites that need it should either run against the live tree's installed dependencies or
  pass `--link-node-modules`, which symlinks the live `node_modules` (and `apps/*/node_modules`) into the sandbox.
  That link writes THROUGH to the real tree: installs and tool caches (`node_modules/.cache`, `.vite`) land in the
  live checkout (the #8800 hazard). `rm` removes the link, never the target. Prefer no link.
- Base: forced disk-backed. The first of `/var/tmp`, `$HOME/.cache` that is writable and not tmpfs/ramfs. If none
  exists `new` exits non-zero rather than falling back to a RAM disk. Do not point it at `/tmp`.

## Artifacts that must survive

Logs, rc files and results the lead will read AFTER the seat returns must NOT live in the sandbox (it is deleted).
Create them separately on disk, outside the sandbox:

```bash
OUT=$(mktemp -d /var/tmp/<seat>-out.XXXXXXXX)         # or a path inside the worktree
```

Never `/tmp`: it is actively reaped here and the reap takes restore sources and rc files, not just logs. A monitor
over such files must test `-s` on an rc file (empty rc is truncation, not a verdict). Remove the output dir when
the lead has consumed it.

## Self-invoked `.test.sh` that builds a sandbox

A DIRECT invocation of a suite (the inner loop while editing the thing under test) inherits the bare `/tmp`,
whereas `scripts/test-all.sh` and `run-registered-suites.sh` default `TMPDIR=/var/tmp`. Add
`export TMPDIR="${TMPDIR:-/var/tmp}"` to any `.test.sh` that builds a sandbox, or its verdicts become a function
of another session's disk usage. Litmus: three runs of an UNCHANGED tree giving three DIFFERENT failure sets is a
harness defect, never a re-run to repeat. A harness whose setup (`cp`/`mkdir`/`mktemp`) fails must `exit 2`, not
continue into a confident wrong result.

## Rejected shapes (do not reintroduce)

- Hardlink copies (`cp -al`): hardlinks write THROUGH to the live repo, so a mutation edits the real file (#8800).
- `git worktree add --detach` sandboxes: a registered worktree that the classifier retains forever when unmerged.
- A per-seat copy under the session scratchpad or `/tmp`: the incident shape above.

`git ls-files | tar` is cheap (about 0.7 s for the tracked tree) and creates no registry entry.

## Operator-side

`SOLEUR_SANDBOX_BASES` (colon-separated, default `/var/tmp:$HOME/.cache`) and `SOLEUR_SANDBOX_SRC` (source tree,
default the cwd's repo) exist as test seams. Seats should not set them.
