# Scratch sandboxes for mutating seats

Loaded by pointer from `work/SKILL.md` (instrument/artifact and self-invoked `.test.sh` bullets) and
`review/SKILL.md` (the seat-spawn contract, "Suite scope for every agent below"). Use it whenever a seat, a
mutation battery or a destructive experiment needs a MUTABLE copy of the working tree. The seat brief is the
anchored command in the next section: use the allocator, never hand-copy a tree.

## Why this exists

`/tmp` on the dev host is a RAM-backed tmpfs with a fixed ceiling shared by every parallel worktree. A seat
that builds one full tree copy per mutant in the session scratchpad, with no cleanup, fills it; then every Bash
call in the session fails with no output until the operator frees space (#8292/PR #8536). A SIGKILLed seat never
runs its EXIT trap, so the failure also orphans the largest artifacts. The allocator below puts the copy on disk,
makes it small, stamps an owner marker at creation, and removes it with one command.

## Allocate, use, remove

`scripts/soleur-sandbox.sh` exists only in this repo's checkout: not in a plugin consumer's repo, and a bare
`scripts/...` path breaks from a subdirectory. Anchor it to the live tree's root, compute `ROOT` in every Bash
call (it must be taken from the LIVE tree: a sandbox has no `.git`, so `git rev-parse` fails inside one), and
treat an allocation failure as a stop:

```bash
ROOT=$(git rev-parse --show-toplevel)
SBX=$(bash "$ROOT/scripts/soleur-sandbox.sh" new <seat>) && [ -d "$SBX" ] || { echo ALLOC-FAILED >&2; exit 2; }
echo "SBX=$SBX"                                      # the path is the only state that survives; keep it in your notes
# ... run the battery / experiment with the sandbox as the working tree ...
bash "$ROOT/scripts/soleur-sandbox.sh" rm "$SBX"     # BEFORE the seat returns, on the failure path too
```

- **Allocation failure rule.** On `ALLOC-FAILED` stop and report it. Never mutate the live tree instead, and
  never fall back to `/tmp` or the session scratchpad: that is the incident shape above. (`new` itself fails
  closed when no disk-backed base exists.)
- `new` prints ONLY the path on stdout (warnings go to stderr). `rm` takes the PATH, not a label.
- Allocate ONE copy per seat and restore it from a pristine backup per row/mutant. Do not allocate a copy per
  mutant.
- **Lost path.** If the path was not kept, find it: `ls -d /var/tmp/soleur-sbx.<seat>.*` (also
  `$HOME/.cache/soleur-sbx.<seat>.*` when `/var/tmp` was unusable), then `rm` it by that path.
- **Session-scoped ownership.** The marker's owner pid is the long-lived agent process (the first non-shell
  ancestor), not the seat. A seat that dies without running `rm` therefore leaks its 90-300 MB copy until the
  whole session ends, and only then do the reapers consider it (24 h age floor, then a 7-day quarantine). The
  LEAD must `rm` the sandbox after any seat returns or fails; have every seat state its `SBX` path in its report.
- `rm` refuses anything that is not a sandbox: the directory name must match `soleur-sbx.*`, it must carry a valid
  marker, its realpath must sit directly under a scratch base, and it must be owned by the current uid.
  A refusal is correct; do not work around it with `rm -rf`.

### Fallback: a repo without `scripts/soleur-sandbox.sh`

Same shape, one copy, removed before returning (no owner marker, so no reaper will ever clean it up for you):

```bash
SBX=$(mktemp -d /var/tmp/<seat>-sbx.XXXXXXXX) && [ -d "$SBX" ] || { echo ALLOC-FAILED >&2; exit 2; }
git ls-files -z --cached --others --exclude-standard | tar --null -T - -cf - | tar -x -C "$SBX"
# ... run the battery / experiment ...
rm -rf "$SBX"                                         # before the seat returns, on the failure path too
```

## What the copy contains (by design)

- The DIRTY working tree: `git ls-files --cached --others --exclude-standard`, so uncommitted fixes the seat is
  mutating are present. Tracked files deleted in the tree are absent. Gitignored files (`.env`, `__pycache__`,
  build output) are NOT copied.
- NO `.git`, so `git diff` / `git status` do not work inside the sandbox. This is deliberate: with no `.git` it can
  never enter the worktree registry (a detached worktree is a REGISTERED worktree that the classifier retains
  forever when unmerged), so a seat must not "pin a SHA" with `git worktree add --detach` either. A suite that
  needs a repo inside the sandbox gets its own throwaway one: `(cd "$SBX" && git init -q && git add -A)`.
  Otherwise diff against the live tree: `diff -r -x .git -x .soleur-owned -x knowledge-base -x node_modules "$ROOT" "$SBX"`, or
  `md5sum` before/after per mutation.
- Run `TEST_GROUP=affected` (and any gate runner) from the LIVE tree only, never from inside the sandbox: it has
  no `.git`, so the affected-set selection has no diff to read.
- NO `knowledge-base/` (the bulk of non-code bytes; seats mutate code, not docs). A suite that reads
  `knowledge-base/` will SKIP or find nothing in the sandbox and can print GREEN without exercising anything:
  prove the unmutated control non-vacuous (the suite's executed count is above zero, and one deliberately broken
  row goes RED) before reading any verdict.
- NO `node_modules`. Choose by suite kind:
  - **bash/python suites:** do not link. Run them with no dependency tree.
  - **TS/vitest batteries:** pass `--link-node-modules`; the root `node_modules` is small (36 MB) but
    `apps/web-platform/node_modules` is 1.7 GB, which is why the allocator links rather than copies. The link
    writes THROUGH to the real tree: tool caches (`node_modules/.cache`, `.vite`) land in the live checkout (the
    #8800 hazard). `rm` removes the link, never the target.
  - **Containing the write-through:** never run an install (`npm`, `bun`, `pnpm`) inside a linked sandbox;
    `touch "$SBX/.t0"` before the battery, and afterwards report anything it created in the live tree with
    `find "$ROOT/node_modules" "$ROOT"/apps/*/node_modules -maxdepth 3 -newer "$SBX/.t0" 2>/dev/null | head`.
    Tool caches in that list are expected and harmless; a changed package is not.
- Base: forced disk-backed. The first of `/var/tmp`, `$HOME/.cache` that is writable and not tmpfs/ramfs. If none
  exists `new` exits non-zero rather than falling back to a RAM disk. Do not point it at `/tmp`. A
  `$HOME/.cache` base is outside every reaper's default bases (`/tmp /var/tmp`); only `rm` reclaims it, and
  `new` warns when it picks one.

## Artifacts that must survive

Logs, rc files and results the lead will read AFTER the seat returns must NOT live in the sandbox (it is deleted).
Create them separately on disk, outside the sandbox, and mark them so a dead owner is reclaimable:

```bash
OUT=$(mktemp -d /var/tmp/<seat>-out.XXXXXXXX)         # or a path inside the worktree
source "$ROOT/scripts/lib/scratch-root.sh" && soleur_scratch_mark_owned "$OUT"
```

A literal `/var/tmp/<seat>-out.*` directory carries no owner declaration, so no reaper will ever touch it:
without the `soleur_scratch_mark_owned` line (or in a repo without the script) the lead must remove it by hand.
Never `/tmp`: it is actively reaped here and the reap takes restore sources and rc files, not just logs. A monitor
over such files must test `-s` on an rc file (empty rc is truncation, not a verdict). Remove the output dir when
the lead has consumed it. To check headroom before a big battery, run `bash scripts/soleur-tmp-purge.sh --report`
(strictly read-only).

## Self-invoked `.test.sh` that builds a sandbox

A DIRECT invocation of a suite (the inner loop while editing the thing under test) inherits the bare `/tmp`,
whereas `scripts/test-all.sh` and `run-registered-suites.sh` default `TMPDIR=/var/tmp`. Add
`export TMPDIR="${TMPDIR:-/var/tmp}"` to any `.test.sh` that builds a sandbox, or its verdicts become a function
of another session's disk usage. Litmus: three runs of an UNCHANGED tree giving three DIFFERENT failure sets is a
harness defect, never a re-run to repeat. A harness whose setup (`cp`/`mkdir`/`mktemp`) fails must `exit 2`, not
continue into a confident wrong result.

## Rejected shapes (do not reintroduce)

- Hardlink copies (`cp -al`): hardlinks write THROUGH to the live repo, so a mutation edits the real file (#8800).
- `git worktree add --detach` sandboxes (including "pin a SHA this way"): a registered worktree that the
  classifier retains forever when unmerged.
- A hand-copied subtree (`cp -r dir "$sb/"`): it copies INTO an existing directory instead of over it, so row N
  re-runs row N-1's mutation, and it strips the repo context a suite needs.
- A per-seat copy under the session scratchpad or `/tmp`: the incident shape above.

`git ls-files | tar` is cheap (about 0.7 s for the tracked tree) and creates no registry entry.

## Pinning a seat's input

A report-only seat that copies the tree while the lead edits underneath it reports a baseline no SHA ever had.
The allocator copies the DIRTY tree at allocation time, so the lead either holds edits until every seat has
allocated, or has the seat compare against the SHA's content with `git show <sha>:<path>` read from the LIVE tree.
It does not need a worktree.

## Operator-side

`SOLEUR_SANDBOX_BASES` (colon-separated, default `/var/tmp:$HOME/.cache`) and `SOLEUR_SANDBOX_SRC` (source tree,
default the cwd's repo) exist as test seams. Seats should not set them.
