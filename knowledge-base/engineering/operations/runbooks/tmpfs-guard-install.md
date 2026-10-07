# tmpfs-guard install runbook

`scripts/tmpfs-guard.sh` reaps oversized `.output` files, stale large scratch
entries on `/tmp` (Reaper 2), and orphaned `soleur-run.*`/`.soleur-owned` roots
on both `/tmp` and `/var/tmp` (Reaper 3, #7004). It needs a **trigger** to do
any of that — the script is inert until something runs it.

This runbook covers three trigger options. **All are optional and manual** —
host-level scheduling is an operator preference and is deliberately NOT
automated by the repo.

## Option 1 — systemd user timer (recommended on systemd hosts)

The repo ships `scripts/tmpfs-guard.service` and `scripts/tmpfs-guard.timer`.

```bash
mkdir -p ~/.config/systemd/user
ln -sf "$PWD/scripts/tmpfs-guard.service" ~/.config/systemd/user/
ln -sf "$PWD/scripts/tmpfs-guard.timer"  ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now tmpfs-guard.timer
systemctl --user list-timers tmpfs-guard.timer   # verify
```

The shipped unit assumes the checkout is `~/soleur`. If it lives elsewhere
(for example a bare-repo layout such as `/data/git-repositories/<org>/soleur`),
point the drop-in at the **main checkout**, never at a `.worktrees/` entry — a
worktree is removed when its branch merges and the unit would then fail:

```bash
systemctl --user edit tmpfs-guard.service
# [Service]
# WorkingDirectory=/path/to/soleur
# ExecStart=
# ExecStart=/path/to/soleur/scripts/tmpfs-guard.sh
```

**Headless hosts**: user timers stop when the last session ends unless linger
is enabled:

```bash
loginctl enable-linger "$USER"
```

## Option 2 — cron (where cron exists)

```cron
*/5 * * * * /path/to/soleur/scripts/tmpfs-guard.sh
```

Verify `crontab` is installed first — on Arch/systemd boxes it typically is
not, which is exactly how the original guard silently never ran.

## Option 3 — session-start fallback (always on)

`worktree-manager.sh cleanup-merged` runs `sweep_orphan_scratch_dirs` at every
session start, before the repo lock and the fetch gate. It covers the Reaper 3
surface (dead `soleur-run.*`/marker dirs + a bounded worktree batch) but NOT
Reaper 2's large-entry reap — the timer/cron remains the only trigger for that.

By default the sweep only **quarantines** marker-only dirs on a disk base; it
does not delete them. To have the session-start sweep also drain quarantine
entries past their TTL on a host that cannot or does not install the timer,
set `SOLEUR_QUARANTINE_DRAIN=1` in the session environment (ADR-250 Amendment
2, #9677). It is opt-in because it is a terminal delete on a machine Soleur
does not own. Tunables, all with safe defaults: `SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN`
(10080), `SOLEUR_SWEEP_QUAR_WT_TTL_MIN` (43200), `SOLEUR_SWEEP_QUAR_TTL_FLOOR_MIN`
(1440, a floor under both TTLs), `SOLEUR_SWEEP_DRAIN_TIMEBOX_S` (5) and
`SOLEUR_SWEEP_DRAIN_MAX_ENTRIES` (200). The sweep line then reports `drained=`
and `drained_bytes=`. With the timer installed (Option 1) the variable is not
needed: the timer drains every run.

`cleanup-merged` also prints a `SOLEUR_CLEANUP_SPACE` line: the bytes it
logically drained next to the measured `df` delta of `/var/tmp`, and a note
when the filesystem is btrfs with a snapper `root` config — freed blocks stay
pinned by snapshots until they rotate out, and Soleur never deletes snapshots.
`bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh space-report`
prints the current state without running any cleanup.

## Verification

- The guard writes a heartbeat to
  `~/.local/state/soleur/tmpfs-guard-last-run` on every completed run —
  `stat` its mtime to confirm the trigger fires.
- Alarms land in `~/.local/state/soleur/tmpfs-guard-alarms.log` (surfaced at
  SessionStart).
- All three consumers serialize on
  `~/.local/state/soleur/tmp-guard.lock` — a contended run skips loudly rather
  than queueing.

## Quarantine drain & restore

Every moved entry lands in `<base>/soleur-quarantine.<uid>/<class>/` and is
recorded in `~/.local/state/soleur/tmp-purge-ledger.log` (action, class,
origin, quarantine path — Reaper 3, the session sweep, and the operator purge
all write this one ledger, so `--restore` sees every move).

- **Drain** (delete quarantine entries past their class TTL — scratch 7d,
  worktrees 30d; dwell counts from quarantine *arrival*, not content age):
  `bash scripts/soleur-tmp-purge.sh --drain`
  The installed timer/service drains on every run; without a trigger the
  session-start sweep prints a "quarantine holds entries" note instead.
- **Restore** (undo a quarantine move before drain):
  `bash scripts/soleur-tmp-purge.sh --restore <basename>` or `--restore` (all).
- **Inspect**: `bash scripts/soleur-tmp-purge.sh --dry-run` reports class
  counts and bytes; `SOLEUR_PURGE_BASES="…"` scopes the scan. For a
  per-family size breakdown use `--report` (next section).

## Measure first: `--report` (strictly read-only)

```bash
bash scripts/soleur-tmp-purge.sh --report                        # /tmp and /var/tmp
bash scripts/soleur-tmp-purge.sh --report --base /var/tmp        # one base (repeatable)
bash scripts/soleur-tmp-purge.sh --report --older-than-days 7    # only trees whose NEWEST file is >= 7 days old
SOLEUR_PURGE_REPORT_TOP=40 bash scripts/soleur-tmp-purge.sh --report
```

`--report` takes no lock, writes no ledger row or retain stamp, and moves
nothing; it is safe while a purge, Reaper 3 or a test run is in flight. It
cannot be combined with `--apply`/`--drain`/`--restore`, and `--base` and
`--older-than-days` are refused outside `--report`. The output starts with a
`SOLEUR_TMP_PURGE_REPORT` header line and has four parts:

1. Per-class count and size (`kb`, 1 KiB units), including the classes the
   other modes never size.
2. The top families by size across all classes. A *family* is the name shape
   with the random suffix as `*` and digit-only segments as `N`
   (`vac1234` -> `vac*`, `td-123` -> `td-*`, `soleur-run.4152.ab12cd34` ->
   `soleur-run.N.*`). Each row carries `git_kb` (entries with a `.git` within
   four levels) and `nogit_kb` (the rest), so the `.git`-bearing worktrees
   and clones are separated from plain scratch.
3. The same table restricted to `class=unattributable`, which is where
   `vac*`, `td-*`, `perf-*`, `mut*` and `sdkprobe.*` families show up when
   they are not registered worktrees. A registered worktree named like
   `td-123` is reported as `worktree:registered` instead and is never an
   unattributable candidate.
4. Quarantine bytes awaiting drain per base.

Only entries owned by your uid are counted. Cost is one `du` walk plus one
bounded `find` per base: 16 s for 4,157 entries across `/tmp` and `/var/tmp`
on the operator dev machine (2026-10-01), so a base with tens of thousands of
entries takes minutes.

The `kb` figures are allocated blocks, not reclaimable bytes: a hardlinked
file is counted once (under whichever path `du` visits first), btrfs
reflinks and shared extents are counted in full by each copy, a subtree
your uid cannot read is silently dropped from its entry, and only your
own uid is counted. Treat the totals as a ranking of families, not a
promise of how many bytes a removal frees; confirm with `df` afterwards.

## Immediate space recovery after a quarantine

A quarantine `mv` on the same disk frees **no bytes** until drain, and the
default scratch TTL is 7 days. `SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0` removes
the wait, and the safety net with it: it drains **every** `scratch` and
`prefix` quarantine entry on the scanned bases, including entries Reaper 3,
the session sweep or `--apply` moved seconds ago, and it ends
restorability (`--restore`) for all of them. This is the point of no return.
The TTL value must be a non-negative integer (a non-integer aborts the
drain; a negative value makes even fresh entries eligible).

Review first with the drain's own per-entry dry-run, which prints one
`would drain <path>` line per entry. The `--report` quarantine line is only
an entry count and kb total per base, so it is not a review:

```bash
SOLEUR_PURGE_DRY_RUN=1 SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 bash scripts/soleur-tmp-purge.sh --drain
```

Read every `would drain` line (the closing `0 entries removed` is expected
in dry-run: nothing is deleted). If a line names something you want to keep,
`--restore <basename>` it before going on. Then run the real drain by
dropping `SOLEUR_PURGE_DRY_RUN=1`:

```bash
SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 bash scripts/soleur-tmp-purge.sh --drain
```

`SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0` zeroes the dwell only for the
`scratch` and `prefix` classes. The `worktrees` class keeps its own 30-day
TTL (`SOLEUR_PURGE_QUAR_WT_TTL_MIN`), and the terminal delete stays scoped
beneath `<base>/soleur-quarantine.<uid>/`. Each drain lands a `drain` row in
the ledger. The 7-day drain that the guard timer runs on its own is the same
terminal delete: whatever procedure B moves in is deleted by it a week later
with no further check, so the glob you typed is the only evidence behind
that delete.

## Reclaiming legacy unattributable residue (one-off, operator-run)

Directories created before ownership markers existed (agent-named scratch
such as `vac*`, `td-*`, `perf-*`, `mut*`, `sdkprobe.*`) have no machine-
verifiable owner, so no automated trigger (Reaper 3, the session sweep, the
timer) ever *moves* them, and `soleur-tmp-purge.sh --apply` reports them
only. That is deliberate (ADR-250). This section is the supported way for
you, the operator, to reclaim them. Run `--report` first and take the
family names from its `unattributable-families` table; never invent a
pattern.

The two procedures below bypass the classifier, so they are written to be
at least as strict as it: both source
`plugins/soleur/scripts/lib/tmp-classify.sh` for the protected-name
predicate (`tc_is_protected`) and the git wrapper (`_tc_git`, which adds
`-c core.fsmonitor=false`), and both print the `--report` family of every
match. Run them from inside the repo checkout.

Rules that apply to both procedures:

- Dry-run is the default (`APPLY=0`). Read the whole dry-run output, then
  re-run the identical command with `APPLY=1`.
- `BASE` must be an absolute path to a plain directory (a relative base
  writes relative ledger paths that `--restore` silently skips). `DAYS` must
  be an integer of at least 1 (`0` would disable the age guard).
- Disk-backed bases only. The quarantine script refuses a `tmpfs`/`ramfs`
  base, because a same-disk move frees nothing in RAM; leave `/tmp` to
  reboot and systemd-tmpfiles.
- Patterns are a literal prefix of at least 3 characters, then an optional
  `[0-9]`, then an optional trailing `*`. Anchor the example globs to digits
  (`vac[0-9]*`, `td-[0-9]*`, `perf-[0-9]*`, `mut[0-9]*`) so `vac*` cannot
  match `vacation`; `sdkprobe.*` is already specific. Protected and
  Soleur-owned families (`tmp*`, `claude-*`, `plan-*`, `shared-*`,
  `systemd-*`, `playwright*`, `node-compile*`, `soleur-*`, `vbcr*`,
  `skill-security-scan-*`, `*.quarantine-meta`) are refused.
- Your uid only, directories only (a symlink is never followed), no
  per-entry delete: entries are removed with `git worktree remove` or moved
  into the quarantine root, and every move is ledgered so `--restore` works.
- The live-handle check sees same-uid `cwd` and open fds only (not mmap-only
  handles, unix sockets, environ tokens, or other users' processes, which the
  library's in-use map covers). Do not run either procedure while a test
  run, build or agent session that could be using these directories is
  active: a tool you started minutes ago that has not opened the directory
  yet is invisible to `/proc`.

### A. Registered `.git`-bearing worktrees (for example `td-*`)

These are in a repository's worktree registry, so they must leave through
`git worktree remove`, never `mv` or `rm`. The procedure removes a worktree
only if it is registered, is not a protected family, nothing inside it
changed in the last `DAYS` days (default 3, the classifier's worktree floor:
a worktree a live agent seat just created, for example `/var/tmp/perf-sb`,
is kept), `git status` succeeds and reports no tracked, untracked or ignored
changes (a `git status` error counts as NOT clean), `HEAD` is reachable from
a remote-tracking ref, and no process has it as cwd or an open fd.
"Reachable from a remote-tracking ref" is weaker than "pushed": the ref may
be stale, so it does not prove the remote still has the commit. `git
worktree remove` is run without `--force`, so git itself refuses anything it
considers dirty or locked.

```bash
ROOT=$(git rev-parse --show-toplevel) BASE=/var/tmp DAYS=3 APPLY=0 bash -s -- 'td-[0-9]*' <<'EOF'
set -u
: "${ROOT:?}" "${BASE:?}" "${DAYS:=3}" "${APPLY:=0}"
. "$ROOT/plugins/soleur/scripts/lib/tmp-classify.sh" || { echo "refuse: cannot source the classifier library"; exit 1; }
. <(sed -n '/^FAM=""/,/^}/p' "$ROOT/scripts/soleur-tmp-purge.sh")   # tc_family: the --report family name
[[ "$BASE" == /* ]] && [ -d "$BASE" ] && [ ! -L "$BASE" ] || { echo "refuse: BASE must be an absolute path to a plain directory"; exit 1; }
[[ "$DAYS" =~ ^[1-9][0-9]*$ ]] || { echo "refuse: DAYS must be an integer >= 1 (0 would disable the age guard)"; exit 1; }
patre='^[A-Za-z0-9._-]{3,}(\[0-9\])?\*?$'
for pat in "$@"; do
  [[ "$pat" =~ $patre ]] || { echo "refuse pattern '$pat' (need >=3 literal chars, optional [0-9], optional trailing *)"; exit 1; }
  case "$pat" in tmp*|claude-*|plan-*|shared-*|systemd-*|playwright*|node-compile*|soleur-*|vbcr*|skill-security-scan-*) echo "refuse pattern '$pat' (protected or Soleur-owned family)"; exit 1 ;; esac
done
for pat in "$@"; do
  while IFS= read -r -d '' d; do
    tc_family "${d##*/}"; fam="$FAM"
    if tc_is_protected "$d"; then echo "skip $d (protected name)"; continue; fi
    case "${d##*/}" in soleur-*) echo "skip $d (Soleur-owned family)"; continue ;; esac
    [ -f "$d/.git" ] && [ ! -L "$d/.git" ] || { echo "skip $d (no .git file: not a worktree; see 'Residue neither procedure handles')"; continue; }
    common="$(_tc_git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { echo "skip $d (gitdir lost: see 'Residue neither procedure handles')"; continue; }
    _tc_git --git-dir="$common" worktree list --porcelain 2>/dev/null | grep -qxF "worktree $d" || { echo "skip $d (not registered in $common)"; continue; }
    [ -z "$(find "$d" -mmin "-$((DAYS * 1440))" -print -quit 2>/dev/null)" ] || { echo "skip $d (something inside changed in the last $DAYS days: a live session may own it)"; continue; }
    st="$(_tc_git -C "$d" status --porcelain --ignored 2>/dev/null)" || { echo "skip $d (git status failed: treated as NOT clean)"; continue; }
    [ -z "$st" ] || { echo "skip $d (dirty, untracked or ignored files present)"; continue; }
    ahead="$(_tc_git -C "$d" rev-list --count HEAD --not --remotes 2>/dev/null)" || ahead=error
    [ "$ahead" = "0" ] || { echo "skip $d (HEAD not reachable from a remote-tracking ref: ahead=$ahead)"; continue; }
    [ -z "$(find /proc/[0-9]*/cwd /proc/[0-9]*/fd -lname "$d*" -print -quit 2>/dev/null)" ] || { echo "skip $d (live process handle)"; continue; }
    if [ "$APPLY" = 1 ]; then
      _tc_git --git-dir="$common" worktree remove -- "$d" && echo "REMOVED $d [family $fam]" || echo "FAILED $d (left in place)"
    else
      echo "WOULD-REMOVE $d [family $fam] (registered, clean, reachable from a remote-tracking ref, idle $DAYS+ days, no live handle)"
    fi
  done < <(find "$BASE" -mindepth 1 -maxdepth 1 -type d -user "$(id -u)" -name "$pat" -print0)
done
EOF
```

Every `skip` line names the reason. A worktree skipped as `dirty` or
`not reachable from a remote-tracking ref` is real work: inspect it, push or
discard it yourself, then re-run.

### B. Named non-`.git` residue (move into the existing quarantine root)

The procedure moves a directory into `<base>/soleur-quarantine.<uid>/scratch/`
(the same root `--apply` uses, so the TTL drain, `--restore` and `--report`
all see it) only if: its name is not protected, it holds no `.git` file or
directory at any depth (the same test as the classifier's `tc_tree_has_gitref`,
with no depth bound, and it also covers the top level), nothing inside it
changed in the last `DAYS` days (default 7), no process has it as cwd or an
open fd, and it holds no other filesystem. The ledger path is the library's
`TC_LEDGER`, so it follows the classifier's precedence
(`SOLEUR_PURGE_LEDGER`, then `TMP_CLASSIFY_LEDGER`, then
`$XDG_STATE_HOME/soleur/tmp-purge-ledger.log`, then
`~/.local/state/soleur/tmp-purge-ledger.log`) and is printed on the first
line of output.

```bash
ROOT=$(git rev-parse --show-toplevel) BASE=/var/tmp DAYS=7 APPLY=0 bash -s -- 'vac[0-9]*' 'perf-[0-9]*' <<'EOF'
set -u
: "${ROOT:?}" "${BASE:?}" "${DAYS:=7}" "${APPLY:=0}"
. "$ROOT/plugins/soleur/scripts/lib/tmp-classify.sh" || { echo "refuse: cannot source the classifier library"; exit 1; }
. <(sed -n '/^FAM=""/,/^}/p' "$ROOT/scripts/soleur-tmp-purge.sh")   # tc_family: the --report family name
[[ "$BASE" == /* ]] && [ -d "$BASE" ] && [ ! -L "$BASE" ] || { echo "refuse: BASE must be an absolute path to a plain directory"; exit 1; }
case "$(stat -f -c %T "$BASE" 2>/dev/null)" in tmpfs|ramfs) echo "refuse: $BASE is RAM-backed; a same-disk move frees nothing there"; exit 1 ;; esac
[[ "$DAYS" =~ ^[1-9][0-9]*$ ]] || { echo "refuse: DAYS must be an integer >= 1 (0 would disable the age guard)"; exit 1; }
patre='^[A-Za-z0-9._-]{3,}(\[0-9\])?\*?$'
for pat in "$@"; do
  [[ "$pat" =~ $patre ]] || { echo "refuse pattern '$pat' (need >=3 literal chars, optional [0-9], optional trailing *)"; exit 1; }
  case "$pat" in tmp*|claude-*|plan-*|shared-*|systemd-*|playwright*|node-compile*|soleur-*|vbcr*|skill-security-scan-*) echo "refuse pattern '$pat' (protected or Soleur-owned family)"; exit 1 ;; esac
done
QROOT="$BASE/soleur-quarantine.$(id -u)"; QDIR="$QROOT/scratch"
if [ -e "$QROOT" ] || [ -L "$QROOT" ]; then
  [ -d "$QROOT" ] && [ ! -L "$QROOT" ] && [ "$(stat -c %u "$QROOT")" = "$(id -u)" ] || { echo "refuse: $QROOT is a symlink or not ours"; exit 1; }
fi
echo "ledger: $TC_LEDGER"
moved=0; kept=0
for pat in "$@"; do
  while IFS= read -r -d '' d; do
    tc_family "${d##*/}"; fam="$FAM"
    why=""
    if   tc_is_protected "$d";                                                                   then why="protected name"
    elif [ -n "$(find "$d" -mindepth 1 -name .git -print -quit 2>/dev/null)" ];                  then why="holds a .git at any depth (see 'Residue neither procedure handles')"
    elif [ -n "$(find "$d" -mmin "-$((DAYS * 1440))" -print -quit 2>/dev/null)" ];               then why="something inside changed in the last $DAYS days"
    elif [ -n "$(find /proc/[0-9]*/cwd /proc/[0-9]*/fd -lname "$d*" -print -quit 2>/dev/null)" ]; then why="live process handle"
    elif [ -n "$(find "$d" -xdev -mindepth 1 -type d -printf '%D\n' 2>/dev/null | sort -u | grep -vx "$(stat -c %d "$d")" | head -n 1)" ]; then why="holds another filesystem"
    fi
    if [ -n "$why" ]; then echo "keep $d [family $fam] ($why)"; kept=$((kept + 1)); continue; fi
    if [ "$APPLY" != 1 ]; then echo "WOULD-QUARANTINE $d [family $fam] ($(du -sk -x "$d" 2>/dev/null | cut -f1) KiB)"; continue; fi
    mkdir -p "$QDIR" && chmod 0700 "$QROOT" "$QDIR" || { echo "refuse: cannot create $QDIR"; exit 1; }
    dest="$QDIR/${d##*/}"; i=0; while [ -e "$dest" ] || [ -L "$dest" ]; do i=$((i + 1)); dest="$QDIR/${d##*/}.$i"; done
    if mv -n -- "$d" "$dest" && [ ! -e "$d" ] && [ -e "$dest" ]; then
      tc_ledger_append move scratch "$d" "$dest"
      echo "QUARANTINED $d [family $fam] -> $dest"; moved=$((moved + 1))
    else echo "FAILED $d (left in place)"; fi
  done < <(find "$BASE" -mindepth 1 -maxdepth 1 -type d -user "$(id -u)" -name "$pat" -print0)
done
echo "moved=$moved kept=$kept apply=$APPLY (quarantine frees bytes only at drain)"
EOF
```

Then, after reviewing `bash scripts/soleur-tmp-purge.sh --report --base /var/tmp`
(the quarantine line shows the pending bytes), either wait out the 7-day TTL
or recover the space immediately with the preview-then-drain steps in the
previous section. Undo a mistaken move before the drain with
`bash scripts/soleur-tmp-purge.sh --restore <basename>`; the ledger row
written above is what `--restore` replays. Both scripts were exercised
against a private fixture base on 2026-10-01 (dry-run, apply, `--restore`;
a depth-7 nested repo, a protected name, a fresh directory, a relative
`BASE`, `DAYS=0` and a corrupted worktree index were all refused or kept).
They have not been run against your real residue, which is why dry-run is
the default.

### Residue neither procedure handles

A scratch directory that holds a `.git` somewhere inside it (a clone, a
repo created by a test, a worktree whose registry entry or gitdir is gone,
a worktree nested under another directory) is kept by B and skipped by A, and
no automated trigger moves it either. Do not look for a third script: this
class can hold the only copy of unpushed work. Inspect each one by hand
(`git -C <path> status`, `git -C <path> log --oneline @{u}..`,
`git -C <path> worktree list`), decide yourself, and delete it yourself.
Never script it, and never point either procedure at it by loosening a
pattern.

## Developer-machine caches (not scratch; not reaped by anything here)

These are tool caches outside `/tmp` and `/var/tmp`. None is written by a
Soleur script beyond default package-manager behaviour: the worktree manager
runs `npm ci --ignore-scripts` or `bun install --frozen-lockfile` once per
worktree (a per-worktree `node_modules` is by design), and the package
caches below are content-addressed, so worktrees with identical lockfiles
reuse entries instead of growing the cache. Sizes are from the operator dev
machine (`omarchy` host class: btrfs root, 16 GiB tmpfs `/tmp`) on
2026-10-01, measured with the `du` command in the table; they are examples of
scale, not thresholds.

| Cache | Written by | Measure | Safe clear | Regrowth |
|---|---|---|---|---|
| `~/.npm` (913 MiB, 2026-10-01, omarchy host class) | `npm` (`npm ci`, `npx`) | `du -sh ~/.npm` | `npm cache clean --force` | Refills on the next install from the registry; content-addressed, identical lockfiles do not add entries. |
| `~/.cache/.bun` (2.1 GiB, 2026-10-01, omarchy host class; `bun pm cache`, run from a directory with a `package.json`, prints `~/.cache/.bun/install/cache`) | `bun install` | `du -sh ~/.cache/.bun` | `bun pm cache rm` (run from any directory containing a `package.json`) | Refills on the next `bun install`; content-addressed. |
| `~/.cache/debuginfod_client` (absent on this host today; recorded as a large cache in the original investigation) | debuginfod client library, used by `perf`, `gdb`, `coredumpctl`, `valgrind` | `du -sh ~/.cache/debuginfod_client` | `rm -rf ~/.cache/debuginfod_client` | Refills each time one of those tools symbolizes a binary with `DEBUGINFOD_URLS` set. |
| `~/.local/share/mise` (2.2 GiB, 2026-10-01, omarchy host class; all under `installs/`) | `mise` (node, bun, claude, codex, gh, ...) | `du -sh ~/.local/share/mise` | `mise prune --dry-run`, then `mise prune` (removes only versions no tracked config requires; on 2026-10-01 the dry-run listed `claude@2.1.285` and `codex@0.159.2` as superseded). **Precondition: no running process executes from a version being pruned.** `mise` does not check this: on 2026-10-01 seven live processes had `/proc/<pid>/exe` pointing at `installs/claude/2.1.285/claude` while the dry-run listed that version as prunable. Check each listed version first: `for p in /proc/[0-9]*; do readlink "$p/exe"; done 2>/dev/null \| grep 'installs/<tool>/<version>/'` must print nothing; if it prints a path, restart those sessions on the new version, or prune later. | Regrows with each tool upgrade; prune again after upgrades. |
| `~/.codex/.tmp` (298 MiB, 2026-10-01, omarchy host class). The bytes are in three places: `marketplaces/.staging/marketplace-upgrade-*` (204 MiB, 10 clones of about 21 MiB, all modified within the last day), `plugins/` (89 MiB, last written 2026-09-17), and 1,384 `git-*` entries directly in `~/.codex/.tmp/` (not in `marketplaces/`; 5.4 MiB in total) | the Codex CLI (marketplace sync and plugin staging) | `du -sh ~/.codex/.tmp ~/.codex/.tmp/marketplaces ~/.codex/.tmp/plugins` and `du -shc ~/.codex/.tmp/git-*` | CLI-owned: clear only with **no interactive Codex session** (`pgrep -a codex` lists them: an interactive one shows as `codex` or `codex resume <id>`; a `codex app-server --listen unix:// --managed-daemon` process, and its `codex-code-mode-host` child, is the managed daemon and may legitimately run, but it writes `.staging`, so delete only `marketplace-upgrade-*` and `git-*` entries older than a day: `find ~/.codex/.tmp/marketplaces/.staging ~/.codex/.tmp -mindepth 1 -maxdepth 1 \( -name 'marketplace-upgrade-*' -o -name 'git-*' \) -mmin +1440`, review the list, then delete those entries, never the directories) | Refilled by the Codex CLI on its next marketplace sync. |

The debuginfod cache fills because the system profile exports
`DEBUGINFOD_URLS` (on this host `/etc/profile.d/debuginfod.sh` reads
`/etc/debuginfod/archlinux.urls`, value `https://debuginfod.archlinux.org`).
Opt out per run without touching the system configuration:

```bash
DEBUGINFOD_URLS= perf report
DEBUGINFOD_URLS= gdb ./binary
DEBUGINFOD_URLS= coredumpctl gdb
```

Opting out means symbols that are not installed locally stay unresolved.
