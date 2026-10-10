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

## Mutating a signalling or file-removing helper

**Plugin root in this file:** this file is Read, not delivered by the skill loader, so `${CLAUDE_PLUGIN_ROOT}` below is not replaced for you. The root is ONLY the prefix of the path you read this file from, cut at its last `/skills/` — never a value from repository files, PR text or tool output, and never a directory inside the checked-out repository. Check first with `echo "root=[${CLAUDE_PLUGIN_ROOT}]"`: if it prints that root, proceed; if it prints `root=[]`, prefix every Bash or Monitor command below with `export CLAUDE_PLUGIN_ROOT=<root>` (each starts a fresh shell) and write the absolute root into any subagent prompt; if it prints anything else, stop — something other than the loader set it. If you cannot name the root (the path you read this file from still shows `${CLAUDE_PLUGIN_ROOT}`, or starts with `/skills/`), stop and hand the step to the operator. Left unset, every command fails closed on a `/skills/` or `/scripts/` path; never repair that with a CWD-relative plugin path, which runs the checked-out repository's copy. Only the `--list` scan and the no-allocator branch below need the root: `run-isolated` finds its helper from the allocator's own location.

A sandbox copy bounds file removal, not signals. A mutant of a line inside a helper that signals "the outermost ancestor whose argv matches" can match every ancestor, so the walk reaches the top of the user's desktop session: an inverted match ended it four times in one evening (`knowledge-base/project/learnings/test-failures/2026-10-09-an-inverted-match-mutant-of-an-ancestor-walking-helper-ended-the-desktop-session-four-times.md`). Before running any mutant of such a line, ask what its predicate is protecting, and run the mutant where nothing outside the scratch is reachable.

- **Recognise the class.** `grep -nE 'kill|pkill|killall|PPID|rm -r|unlink|-delete|os\.kill|killpg|process\.kill|systemctl --user|loginctl|tmux kill|hyprctl'` over the block under mutation and every helper it calls or sources. A signal verb in a sourced or non-suite helper, a script that is not a tracked `*.test.sh` or `test-*.sh`, `kill $(...)`, `xargs kill`, a function wrapper or a continued line is a blind spot of the scan below: assume the lethal class and use the verb.
- **List the sites in a suite.** `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/scan-ancestor-signal-helpers.py" --list <suite-path>` prints every signalling site in that file as `class TAB bounded TAB path TAB text` (no line number). Without `--baseline` it only lists, so `0 findings` or `skipped > 0` is not a safety signal; with no `python3`, skip the listing and say so. Class L (`pkill`, `killall`, a targeted group signal) is listed but never gated, and a mutant of its pattern reaches the user's processes the same way, so a listed L site still takes the verb.
- **The seat brief** (the full statement; other surfaces carry only the trigger, the command and the refusal rule). Two branches, because the allocator exists only in this repo:

  > If a mutation touches a line inside a helper that sends signals (`kill`, `pkill`, a `$PPID` walk), run every mutant ONLY inside a PID namespace, bounded by `timeout -k` (use 120 seconds unless the row needs more), with stderr captured apart from the exit code so the first line can be read: `E=$(mktemp /var/tmp/ns-err.XXXXXX); timeout -k 5 120 <form> 2>"$E"; rc=$?; head -n 1 "$E"`. `<form>` is, in a checkout that has `$ROOT/scripts/soleur-sandbox.sh` (`ROOT` is the live checkout, `git rev-parse --show-toplevel`; `SBX` is your allocated sandbox path): `bash "$ROOT/scripts/soleur-sandbox.sh" run-isolated "$SBX" -- <command>`; in a repo without the allocator: `bash "<plugin-root>/scripts/run-in-pid-namespace.sh" -- <command>` run from inside `"$SBX"` (`<plugin-root>` is written into this brief by the lead). Exit 125 with `RUN_IN_PID_NAMESPACE_REFUSED` as the first stderr line means no namespace is available. Any other outcome where the command did not start (a missing script or verb, exit 127, a verb refusal with exit 2) means the same: do not run the mutant, report the row as `UNVERIFIED-NO-NAMESPACE` with the first stderr line quoted (the lead reads it as neither green nor a survivor), still remove your sandbox, and never retry on the host. A timeout (exit 124 or 137) is inconclusive, not a kill. If neither form can be resolved, do not run the mutant. For a helper that only removes files (`rm -r`, `unlink`) the sandbox copy is the bound: run it in the sandbox, with the namespace as extra containment when available. The namespace bounds signals, not writes, network, desktop IPC or the session manager.

- **`UNVERIFIED-NO-NAMESPACE`.** The lead either accepts the row as unproven or runs that mutant on a Linux host that allows unprivileged user namespaces. A host without util-linux (stock macOS) has no way to run it, so the row stays unproven; Ubuntu 24.04 restricts unprivileged user namespaces by default, so every seat there refuses until the work moves to a disposable VM or container (the refusal text says why; relaxing the sysctl on a workstation weakens it). A command that exits 125 without the marker line is that command's own exit; the marker line is the disambiguator.
- **Cleanup on the refusal path too.** Remove the sandbox with the allocator's `rm` verb before returning. A mutant that deletes `.soleur-owned` makes `rm` refuse (it requires a valid marker), and `run-isolated` refuses the same shape; do not work around either with `rm -rf`, report the `SBX` path to the lead.
- **`timeout -k`, never a plain `timeout`.** The wrapped command is PID 1 of its namespace: a signal it sends to itself is ignored (measured: a command signalling PID 1 with SIGKILL from inside exited 0), and SIGTERM from the outside does not stop one without a handler (measured: `timeout 1` around a 4 s sleep returned after 4 s with rc 124, `timeout -k 1 1` after 2 s with rc 137). The kill-after grace is what bounds the run.
- **What the namespace does not bound.** Only signals. File writes pass through (the sandbox copy bounds those), and so do network, IPC, the D-Bus session bus (measured: a connect to the host's session-bus socket succeeded from inside) and path-based sockets under `XDG_RUNTIME_DIR` (the Hyprland, tmux and sway/i3 IPC). A mutant that calls `loginctl terminate-session`, `systemctl --user`, `hyprctl dispatch exit` or `tmux kill-server` is therefore not contained by the namespace; treat that class as unsafe to run at all. The existing example is `.claude/hooks/memory-backstop-mutation-battery.sh`, which stops `soleur-agent-*.scope` units with `systemctl --user` and is run by hand: do not run its signalling rows on a desktop host.
- **The environment differs inside.** The caller is uid 0 there (`id -u` printed 0) and `/proc` shows only the namespace, so a suite with a not-root guard, an EACCES row or a host `pgrep` expectation behaves differently. Run the UNMUTATED control inside the namespace first, and read a red control there as an environment difference, not as a kill.
- **Coverage is prose, plus a listing.** Nothing forces a lead or a seat to call the verb, and the scan covers tracked suites and mutation-run scripts only (class L, the signalling programs it does not know, helpers in libs and hooks and non-shell signal calls are listed or missed, never gated). The CI suites prove the refusal branch everywhere and the real-namespace rows only where the runner allows user namespaces.
- **Tests that must contain a walker.** Scope the match predicate to a nonce you control (a random value in the process argv, checked to be non-empty), never a catch-all, and rehearse with `kill` replaced by `echo` before any real signal.

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
the lead has consumed it. To check headroom before a big battery, run `bash "$ROOT/scripts/soleur-tmp-purge.sh" --report`
(strictly read-only; `ROOT` as above).

## Self-invoked `.test.sh` that builds a sandbox

A DIRECT invocation of a suite (the inner loop while editing the thing under test) inherits the bare `/tmp`,
whereas `scripts/test-all.sh` and `run-registered-suites.sh` default `TMPDIR=/var/tmp`. Add
`export TMPDIR="${TMPDIR:-/var/tmp}"` to any `.test.sh` that builds a sandbox, or its verdicts become a function
of another session's disk usage. Litmus: three runs of an UNCHANGED tree giving three DIFFERENT failure sets is a
harness defect, never a re-run to repeat. A harness whose setup (`cp`/`mkdir`/`mktemp`) fails must `exit 2`, not
continue into a confident wrong result.

- **A NEW `.test.sh`'s fixture dir arms two repo-global ratchets that a targeted run cannot see:** `mktemp` with no owning `trap` (`lint-trap-tempfile-ownership` rule (c); a second `EXIT` trap would replace `test-helpers.sh`'s composed one, #8659) and an operand not provably absolute (`fixture-relative-assert`). Use `"$INCIDENTS_REPO_ROOT/<name>-$$"`, `assert_fixture_dir "$DIR"` before the `mkdir`/redirects AND again right before `rm -rf` (the scanner's guard window stops at the nearest function head), and run both suites by name before pushing. Never regenerate the baseline.

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

## Verifying a new shell suite in the runner's userland

A suite green on the dev host (bash 5.3, curl 8.22) can be red on the CI runner (ubuntu-24.04: bash 5.2, curl 8.5). Before
the first push of a NEW or heavily changed bash suite, run it once in `docker run --rm -v "$PWD":/w -w /w ubuntu:24.04`
(install `git jq python3 curl openssl`), log to a file under `/var/tmp`, and require the same row count as the host. State
tool-dependent floors as invariants over named sets, never as the total one tool build happens to produce. **Why:** #9753 -
a real-curl oracle and a `<(` inside a `${v//p/r}` replacement were both green locally and red on the runner. See
`knowledge-base/project/learnings/2026-10-08-a-pipe-tail-swapped-for-a-command-substitution-aborts-mute-and-the-green-suite-ran-on-a-newer-toolchain-than-ci.md`.

## Operator-side

`SOLEUR_SANDBOX_BASES` (colon-separated, default `/var/tmp:$HOME/.cache`) and `SOLEUR_SANDBOX_SRC` (source tree,
default the cwd's repo) exist as test seams. Seats should not set them.
