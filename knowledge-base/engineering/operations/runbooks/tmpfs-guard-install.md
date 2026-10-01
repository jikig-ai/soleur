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

The shipped unit assumes the checkout is `~/soleur`. If it lives elsewhere:

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

## Immediate space recovery after a quarantine

A quarantine `mv` on the same disk frees **no bytes** until drain, and the
default scratch TTL is 7 days. To recover the space now (after reviewing
what was quarantined; this is the point of no return for those entries):

```bash
bash scripts/soleur-tmp-purge.sh --report --base /var/tmp | grep 'quarantine '   # what would go
SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 bash scripts/soleur-tmp-purge.sh --drain
```

`SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0` zeroes the dwell only for the
`scratch` and `prefix` classes. The `worktrees` class keeps its own 30-day
TTL (`SOLEUR_PURGE_QUAR_WT_TTL_MIN`), and the terminal delete stays scoped
beneath `<base>/soleur-quarantine.<uid>/`. Each drain lands a `drain` row in
the ledger.

## Reclaiming legacy unattributable residue (one-off, operator-run)

Directories created before ownership markers existed (agent-named scratch
such as `vac*`, `td-*`, `perf-*`, `mut*`, `sdkprobe.*`) have no machine-
verifiable owner, so no automated trigger (Reaper 3, the session sweep, the
timer) ever touches them, and `soleur-tmp-purge.sh --apply` reports them
only. That is deliberate (ADR-250). This section is the supported way for
you, the operator, to reclaim them. Run `--report` first and take the
family names from its `unattributable-families` table; never invent a
pattern.

Rules that apply to both procedures below:

- Dry-run is the default (`APPLY=0`). Read the whole dry-run output, then
  re-run the identical command with `APPLY=1`.
- Disk-backed bases only. The quarantine script refuses a `tmpfs`/`ramfs`
  base, because a same-disk move frees nothing in RAM; leave `/tmp` to
  reboot and systemd-tmpfiles.
- Patterns are literal-prefix globs of at least 3 characters with an
  optional trailing `*`; protected and Soleur-owned families (`tmp*`,
  `claude-*`, `plan-*`, `shared-*`, `systemd-*`, `playwright*`,
  `node-compile*`, `soleur-*`) are refused.
- Your uid only, directories only (a symlink is never followed), no
  per-entry delete: entries are removed with `git worktree remove` or moved
  into the quarantine root, and every move is ledgered so `--restore` works.

### A. Registered `.git`-bearing worktrees (for example `td-*`)

These are in a repository's worktree registry, so they must leave through
`git worktree remove`, never `mv` or `rm`. The procedure removes a worktree
only if it is registered, has no tracked, untracked or ignored changes, has
no commit that is missing from every remote, and no process has it as cwd or
an open fd. `git worktree remove` is run without `--force`, so git itself
refuses anything it considers dirty or locked.

```bash
BASE=/var/tmp APPLY=0 bash -s -- 'td-*' <<'EOF'
set -u
: "${BASE:?}" "${APPLY:=0}"
[ -d "$BASE" ] && [ ! -L "$BASE" ] || { echo "refuse: $BASE is not a plain directory"; exit 1; }
for pat in "$@"; do
  [[ "$pat" =~ ^[A-Za-z0-9._-]{3,}\*?$ ]] || { echo "refuse pattern '$pat' (need >=3 literal chars, optional trailing *)"; exit 1; }
done
for pat in "$@"; do
  while IFS= read -r -d '' d; do
    [ -f "$d/.git" ] && [ ! -L "$d/.git" ] || { echo "skip $d (no .git file: not a worktree)"; continue; }
    common="$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { echo "skip $d (gitdir lost: leave it for the unregistered-worktree path)"; continue; }
    git --git-dir="$common" worktree list --porcelain 2>/dev/null | grep -qxF "worktree $d" || { echo "skip $d (not registered in $common)"; continue; }
    [ -z "$(git -C "$d" status --porcelain --ignored 2>/dev/null | head -n 1)" ] || { echo "skip $d (dirty, untracked or ignored files present)"; continue; }
    [ "$(git -C "$d" rev-list --count HEAD --not --remotes 2>/dev/null || echo 1)" = "0" ] || { echo "skip $d (commits not on any remote)"; continue; }
    [ -z "$(find /proc/[0-9]*/cwd /proc/[0-9]*/fd -lname "$d*" -print -quit 2>/dev/null)" ] || { echo "skip $d (live process handle)"; continue; }
    if [ "$APPLY" = 1 ]; then
      git --git-dir="$common" worktree remove -- "$d" && echo "REMOVED $d" || echo "FAILED $d (left in place)"
    else
      echo "WOULD-REMOVE $d (registered, clean, fully pushed, no live handle)"
    fi
  done < <(find "$BASE" -mindepth 1 -maxdepth 1 -type d -user "$(id -u)" -name "$pat" -print0)
done
EOF
```

Every `skip` line names the reason. A worktree skipped as `dirty` or
`commits not on any remote` is real work: inspect it, push or discard it
yourself, then re-run. A worktree whose gitdir is gone or no longer lists it
is not removed here (`soleur-tmp-purge.sh --apply` quarantines
proven-unregistered worktrees once they are old enough, and an unverifiable
one escalates to its operator-decision list); procedure B also keeps it,
because it holds a `.git` file.

### B. Named non-`.git` residue (move into the existing quarantine root)

The procedure moves a directory into `<base>/soleur-quarantine.<uid>/scratch/`
(the same root `--apply` uses, so the TTL drain, `--restore` and `--report`
all see it) only if: it holds no `.git` within six levels, nothing inside it
changed in the last `DAYS` days (default 7), no process has it as cwd or an
open fd, and it holds no other filesystem. Check for a live handle yourself
as well (a tool run you started minutes ago that has not opened the directory
yet is invisible to `/proc`): do not run this while a test run, build or
agent session that could be using these directories is active.

```bash
BASE=/var/tmp DAYS=7 APPLY=0 bash -s -- 'vac*' 'perf-*' <<'EOF'
set -u
: "${BASE:?}" "${DAYS:=7}" "${APPLY:=0}"
LEDGER="${SOLEUR_PURGE_LEDGER:-$HOME/.local/state/soleur/tmp-purge-ledger.log}"
[ -d "$BASE" ] && [ ! -L "$BASE" ] || { echo "refuse: $BASE is not a plain directory"; exit 1; }
case "$(stat -f -c %T "$BASE" 2>/dev/null)" in tmpfs|ramfs) echo "refuse: $BASE is RAM-backed; a same-disk move frees nothing there"; exit 1 ;; esac
[[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "refuse: DAYS must be an integer"; exit 1; }
for pat in "$@"; do
  [[ "$pat" =~ ^[A-Za-z0-9._-]{3,}\*?$ ]] || { echo "refuse pattern '$pat' (need >=3 literal chars, optional trailing *)"; exit 1; }
  case "$pat" in tmp*|claude-*|plan-*|shared-*|systemd-*|playwright*|node-compile*|soleur-*) echo "refuse pattern '$pat' (protected or Soleur-owned family)"; exit 1 ;; esac
done
QROOT="$BASE/soleur-quarantine.$(id -u)"; QDIR="$QROOT/scratch"
if [ -e "$QROOT" ] || [ -L "$QROOT" ]; then
  [ -d "$QROOT" ] && [ ! -L "$QROOT" ] && [ "$(stat -c %u "$QROOT")" = "$(id -u)" ] || { echo "refuse: $QROOT is a symlink or not ours"; exit 1; }
fi
moved=0; kept=0
for pat in "$@"; do
  while IFS= read -r -d '' d; do
    why=""
    if   [ -n "$(find "$d" -mindepth 1 -maxdepth 6 -name .git -print -quit 2>/dev/null)" ]; then why="holds a .git (use procedure A)"
    elif [ -n "$(find "$d" -mtime "-$DAYS" -print -quit 2>/dev/null)" ];                      then why="something inside changed in the last $DAYS days"
    elif [ -n "$(find /proc/[0-9]*/cwd /proc/[0-9]*/fd -lname "$d*" -print -quit 2>/dev/null)" ]; then why="live process handle"
    elif [ -n "$(find "$d" -xdev -mindepth 1 -type d -printf '%D\n' 2>/dev/null | sort -u | grep -vx "$(stat -c %d "$d")" | head -n 1)" ]; then why="holds another filesystem"
    fi
    if [ -n "$why" ]; then echo "keep $d ($why)"; kept=$((kept + 1)); continue; fi
    if [ "$APPLY" != 1 ]; then echo "WOULD-QUARANTINE $d ($(du -sk -x "$d" 2>/dev/null | cut -f1) KiB)"; continue; fi
    mkdir -p "$QDIR" && chmod 0700 "$QROOT" "$QDIR" || { echo "refuse: cannot create $QDIR"; exit 1; }
    dest="$QDIR/${d##*/}"; i=0; while [ -e "$dest" ] || [ -L "$dest" ]; do i=$((i + 1)); dest="$QDIR/${d##*/}.$i"; done
    if mv -n -- "$d" "$dest" && [ ! -e "$d" ] && [ -e "$dest" ]; then
      mkdir -p "$(dirname "$LEDGER")"
      printf '%s\tmove\tscratch\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$d" "$dest" >> "$LEDGER"
      echo "QUARANTINED $d -> $dest"; moved=$((moved + 1))
    else echo "FAILED $d (left in place)"; fi
  done < <(find "$BASE" -mindepth 1 -maxdepth 1 -type d -user "$(id -u)" -name "$pat" -print0)
done
echo "moved=$moved kept=$kept apply=$APPLY (quarantine frees bytes only at drain)"
EOF
```

Then, after reviewing `bash scripts/soleur-tmp-purge.sh --report --base /var/tmp`
(the quarantine line shows the pending bytes), either wait out the 7-day TTL
or recover the space immediately with the drain command in the previous
section. Undo a mistaken move before the drain with
`bash scripts/soleur-tmp-purge.sh --restore <basename>`; the ledger row
written above is what `--restore` replays. The script was exercised against a
fixture base (dry-run, apply, `--restore`, TTL=0 `--drain`) on 2026-10-01; it
has not been run against your real residue, which is why dry-run is the
default.

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
| `~/.npm` (787 MiB, 2026-10-01) | `npm` (`npm ci`, `npx`) | `du -sh ~/.npm` | `npm cache clean --force` | Refills on the next install from the registry; content-addressed, identical lockfiles do not add entries. |
| `~/.cache/.bun` (0 B and empty, 2026-10-01; `bun pm cache` prints `~/.cache/.bun/install/cache` here) | `bun install` | `du -sh ~/.cache/.bun` | `bun pm cache rm` (run from any directory containing a `package.json`) | Refills on the next `bun install`; content-addressed. |
| `~/.cache/debuginfod_client` (absent on this host today; recorded as a large cache in the original investigation) | debuginfod client library, used by `perf`, `gdb`, `coredumpctl`, `valgrind` | `du -sh ~/.cache/debuginfod_client` | `rm -rf ~/.cache/debuginfod_client` | Refills each time one of those tools symbolizes a binary with `DEBUGINFOD_URLS` set. |
| `~/.local/share/mise` (2.2 GiB, all under `installs/`, 12 tool-version directories) | `mise` (node, bun, claude, codex, gh, ...) | `du -sh ~/.local/share/mise` | `mise prune --dry-run`, then `mise prune` (removes only versions no tracked config requires; on 2026-10-01 the dry-run listed `claude@2.1.285` and `codex@0.159.2` as superseded) | Regrows with each tool upgrade; prune again after upgrades. |
| `~/.codex/.tmp/marketplaces` (83 MiB, 2026-10-01; holds `.staging` and `git-*` clones) | the Codex CLI (marketplace sync) | `du -sh ~/.codex/.tmp/marketplaces` | CLI-owned: clear only with **no Codex session running** (`pgrep -a codex` must print nothing), by deleting the `git-*` entries inside it, not the directory | Refilled by the Codex CLI on its next marketplace sync. |

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
