---
title: "fix(infra): mkfs the LUKS mapper + fail-close the staging mount in workspaces-cutover.sh"
issue: 6588
type: bug
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-19
branch: feat-one-shot-6588-luks-mkfs-staging-mount-guard
---

# fix(infra): mkfs the LUKS mapper + fail-close the staging mount

> Spec lacks valid `lane:` (no `spec.md` for this branch) — defaulted to `cross-domain` (TR2 fail-closed).
>
> **v3 — post 5-agent plan review (DHH, Kieran, code-simplicity, architecture-strategist,
> spec-flow-analyzer) + CTO.** Simplification pass: loopback validation promoted to Phase 1 (was a
> deferrable Phase 6); the stray-copy **deletion** removed entirely (split to a follow-up PR); ACs cut
> 26 → 11. Correctness pass: **the plan's own invariant recursed one layer and v1/v2 reproduced the
> bug they diagnosed** — nothing anchored `$MAPPER` → `$FRESH_DEV`, so Phase 2 now anchors it at
> prepare time. `emit_staging_target` was called but never defined; `_same_dev` could fail open;
> three `set -u` aborts would have killed the first-cutover path before any marker; `blkid` cache
> hazard; the re-run-after-success entry state was undefined; `rollback()` leaks the mapper via an
> unmounted `$STAGING`; and the capacity gate moved from deferred to in-scope because **this PR is
> what first makes ENOSPC reachable**. Every change to existing code is **strictly additive
> fail-closure**.

## Enhancement Summary

**Deepened on:** 2026-07-19
**Passes:** CTO domain review → 5-agent plan review (DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow-analyzer) → deepen-plan gates + verify-the-negative sweep +
external technical verification.

### Key improvements

1. **The invariant was applied to only one path.** Two independent reviewers found that the plan's own
   rule — *anchor a path to its device before certifying it* — recursed one layer deeper than v1/v2
   reached: nothing anchored `$MAPPER` → `$FRESH_DEV`, so a stale mapper backed by a different
   container would have passed every gate **including the new positive control**. Now anchored at
   prepare time.
2. **Verification budget reallocated.** Loopback validation on real devices moved from a deferrable
   Phase 6 to a blocking Phase 1 — the stubbed harness proves the shell *branches*, and the defect
   was a real command that was never called. The escape hatch is deleted; a structural dispatch gate
   on the irreversible arm replaces prose enforcement.
3. **Destructive scope removed.** The stray-copy **deletion** is gone (split to a follow-up PR). Both
   simplification reviewers fired on that scope, and architecture showed the dry-run carve-out was
   *inverted*: it would have put an irreversible `rm -rf` of user source on the arm that has zero
   human approval by construction, whose reversibility premise is what authorizes it being ungated.
4. **Six same-class sites folded in.** `:670`, `:686`, `:693`, `:892`, `:899`, and `rollback()` `:577`
   — all fail-open → fail-closed, all on the freeze-critical or recovery path. `:892` and the
   `rollback()` `$STAGING` leak are arguably higher severity than the nominal P0.
5. **Two self-inflicted defects caught before implementation.** `emit_staging_target` was *called but
   never defined* (a swallowed 127 → the marker would silently never emit), and `_same_dev`'s naive
   form **fails open** when `readlink` errors. Both were the exact defect class the plan exists to fix.
6. **ACs cut 26 → 11** and re-anchored by content rather than line number; behaviour is asserted by
   tests, not greps over shell source.

### New considerations discovered

<!-- lint-infra-ignore start: retrospective ANALYSIS of failure modes an operator could stumble into (e.g. reaching for ROLLBACK=1 after a prepare-time abort) — these describe mistakes the new die messages now PREVENT, they do not instruct a Soleur user to run anything -->

- **This PR is what first makes `ENOSPC` reachable** — the copy moves from the root disk (where it
  fit) into a mapper strictly smaller than its source. The capacity gate moved from deferred to
  in-scope.
- **Re-running after a successful cutover had no defined outcome** — and re-dispatch is the most
  likely operator action. It would have mounted the mapper twice and rsynced source-into-itself.
- **A prepare-time abort could provoke a gratuitous outage** if an operator reached for `ROLLBACK=1`
  (which umounts the live plaintext volume). Every new die message now says no rollback is needed.
- **Three `set -u` aborts** would have killed the first-cutover path *before emitting any marker*.
- **The stubbed harness could not have run the specified tests** — `run_case` lives in a different
  file, never sets `WORKSPACES_STAGING`, and has a single-rc `mountpoint` stub.

<!-- lint-infra-ignore end -->

## Overview

The 2026-07-19 real freeze (run `29695998561`) safe-aborted on C1 and auto-rolled-back to plaintext
via DP-6. Prod is healthy on the plaintext volume. C1 was **right**; the defect is one layer below
what C1 can report.

`apps/web-platform/infra/workspaces-cutover.sh` `luksFormat`s the fresh device (`:686`), `luksOpen`s
it to `$MAPPER` (`:693`), `mkdir -p "$STAGING"` (`:695`), then mounts (`:696`) — but **never runs
`mkfs` on the mapper**. There is no filesystem inside the LUKS container, so the mount fails with
`wrong fs type, bad option, bad superblock on /dev/mapper/workspaces`.

The script runs `set -uo pipefail` with **no `-e`** (`:32`), and `:696` is unguarded:

```bash
696: [ "$DRY_RUN" = "1" ] || { mountpoint -q "$STAGING" || mount "$MAPPER" "$STAGING"; }
```

so that failure is **swallowed** — a direct violation of `hr-when-a-command-exits-non-zero-or-prints`
("Investigate any non-zero exit or printed warning before proceeding. Never treat a failed step as
success"). An unguarded `mount` in a script without `set -e` is the root enabler of this entire
silent-target class, and closing it is FR1. `mkdir -p "$STAGING"` at `:695` had already created
`/mnt/data-luks` as a plain directory on the **root disk**, and it stays one. Every downstream step
then targets the root disk: bulk rsync (`:802`), delta rsync (`:839`), `verify_byte_identity`
(`:861`), G3 manifest (`:880`).

That is why C1 reported exactly one difference, `icode=.d..t...... path=./` (root dir mtime only):
**the copy succeeded byte-for-byte onto the wrong block device.** The rsync itemize vocabulary
cannot express *"correct copy, wrong target"*.

### The root cause is a shape transplant across differing error-handling regimes

<!-- lint-infra-ignore start: quotes the EXISTING git-data cloud-init precedent verbatim as evidence for the diagnosis — provisioning code that already ships, not a step anyone runs by hand -->

The sibling git-data volume has the **identical** line (`cloud-init-git-data.yml:159-170`):

```bash
set -euo pipefail                                    # <-- note the -e
...
if ! blkid /dev/mapper/git-data >/dev/null 2>&1; then
  mkfs.ext4 -q /dev/mapper/git-data                  # <-- the step the cutover omits
fi
mkdir -p /mnt/git-data-luks
mountpoint -q /mnt/git-data-luks || mount /dev/mapper/git-data /mnt/git-data-luks
```

That unguarded `mountpoint … || mount …` is **fail-closed in git-data** — because `set -e` makes a
failed `mount` fatal. `workspaces-cutover.sh` copied the line's *shape* into a `set -uo pipefail`
(no `-e`) script, converting a fail-closed line into a fail-open one, and dropped the `mkfs` that
would have made the mount succeed in the first place. `git-data-luks.tf:73-78` documents the
mechanism explicitly ("the guest's `luksFormat` overwrites the LUKS header region and `mkfs.ext4`
lays the real FS **INSIDE** the mapper").

<!-- lint-infra-ignore end -->

### The layer below: every downstream gate is *relational*, none is *anchored*

The missing `mkfs` is the proximate cause and the `set -e` transplant explains why it went unnoticed,
but neither is the deepest layer. **C1 verify, the `du` apparent-size assert, `git fsck`, and the G3
manifest are all pure functions of the two strings `$MOUNT` and `$STAGING` — not one of them anchors
either path to a block device.** Nothing in that closure can distinguish "right bytes, wrong device",
so no amount of strengthening the copy gates could ever have caught this. Even with `set -e`, the
class survives anywhere a path-valued variable is certified without a device assert.

> **The invariant: a gate that certifies a path must first anchor that path to its intended device.**

### The invariant has a live counterexample three lines above the fix

Plan review caught that v1 applied this rule to only **one** of the two paths. At `:669-670`:

```bash
669: mountpoint -q "$MOUNT" || die "L3: $MOUNT is not mounted — …"
670: [ -b "$(findmnt -no SOURCE "$MOUNT" 2>/dev/null)" ] || log "WARN: $MOUNT source is not a block device"
```

`$MOUNT` is the **source of every byte** and the path rollback remounts — and it is anchored only to
"is *a* block device", and only as a `log WARN`. That is a live violation of the plan's own rule on
the more consequential path. Fixed in Phase 4 (`|| die`), because shipping the principle while
leaving a counterexample beside it is how the principle rots.

### The invariant recurses: nothing anchors `$MAPPER` → `$FRESH_DEV`

Both correctness reviewers independently found the same deeper gap, and it is the sharpest finding of
the review. The staging positive control anchors **path → mapper**. But `$MAPPER` is a *name*
(`/dev/mapper/workspaces`), and at `:692` the open is skipped when that name merely **exists**:

```bash
692: if [ "$DRY_RUN" != "1" ] && [ ! -e "$MAPPER" ]; then
693:   printf '%s' "$KEY" | cryptsetup luksOpen --key-file - "$FRESH_DEV" "$MAPPER_NAME"
694: fi
```

A **stale mapper left open from a prior run, backed by a different device**, satisfies `[ ! -e ]`, so
`luksOpen` is skipped silently — and every downstream step, *including the new positive control*,
operates on the wrong container while reporting success. `_same_dev "$staging_src" "$MAPPER"` proves
`$STAGING` is mounted from `$MAPPER`; it never proves `$MAPPER` is backed by `$FRESH_DEV`.

`cryptsetup status` does establish that link — but only at `:912`, in the **post-repoint canary**:
after the freeze, after the copy, after the plaintext has been umounted. That is the same
relational-not-anchored shape the plan is about, one layer up, and v1/v2 reproduced it. Phase 2 now
anchors mapper → device **at prepare time**, pre-freeze.

Also unguarded, two lines above the block being fixed: **`:686` `luksFormat` and `:693` `luksOpen`
have no `|| die`** — the identical swallowed-failure defect. A failed `luksOpen` leaves `$MAPPER`
absent, `blkid` returns empty, and the new code would take the *"no filesystem"* arm and try to
`mkfs.ext4` a nonexistent path — dying with `staging_mkfs_failed`, a misleading reason on the one
channel the operator can read without SSH. Both folded into Phase 4.

### Explicit anti-goal

"Fixing" this as an rsync-semantics/attribute issue (e.g. `--omit-dir-times` on the mount root)
would turn C1 **green** and drive the run into repointing `/mnt/data` at an unformatted mapper —
converting a safe abort into user-visible data loss. This plan does the opposite: it makes the
target-preparation path fail *earlier* and *louder*. See Non-Goals.

## Premise Validation

| Premise (cited by reference) | Check | Result |
|---|---|---|
| Issue #6588 open | `gh issue view 6588` | **Holds** — OPEN, `priority/p0-critical`, `domain/engineering`, `type/security` |
| `set -uo pipefail`, no `-e` | `grep -n '^set '` | **Holds** — `:32`, sole `set` line |
| No `mkfs` anywhere in the cutover | `grep -n mkfs` | **Holds** — zero hits |
| Unguarded mount at `~696` | Read `:696` | **Holds** — verbatim as diagnosed |
| Downstream sites target `$STAGING` | `grep -n STAGING` | **Holds** — `:802, :839, :861, :866, :872, :877, :880, :892` |
| git-data mkfs precedent | `cloud-init-git-data.yml:166` | **Holds** |
| `git-data-luks.tf:73-78` documents it | Read | **Holds** |
| **New:** git-data runs `set -euo pipefail` | Read the heredoc | **Holds** — why the same line is safe there |
| **New:** all 4 `workspaces-luks*.test.sh` suites are CI-wired by explicit `run:` lines, no glob | `grep infra-validation.yml` | **Holds** — `:382, :387, :616, :619`. A new suite not added there is an **orphan** |
| Open code-review issues touching these files | `gh issue list --label code-review` + `jq` | **None** |

## Research Reconciliation — Spec vs. Codebase

<!-- lint-infra-ignore start: retrospective premise-vs-codebase VALIDATION table (what was verified on main) — describes the cutover MECHANISM this PR fixes, not a runtime step a Soleur user performs -->

| Claim | Reality | Plan response |
|---|---|---|
| "Mount at `~696` is unguarded" | Exact | Fix (Phase 2) |
| "`mkfs` omitted" | Exact | Fix (Phase 2) |
| "Assert before any rsync touches `$STAGING`" | Earliest is the **bulk** rsync `:802`, which is **pre-freeze** (freeze starts `:807`) | Assert at *prepare* time — pre-freeze, so a failure aborts with **zero downtime**. v1's extra re-assert before `:802` is **cut**: nothing between prepare and bulk rsync unmounts anything |
| "Mirror the git-data shape" | git-data's guard is bare `blkid <dev>`; the cutover's **own** idiom (`:683`) is `blkid -s TYPE -o value` + empty-check | Mirror the **cutover's own** `:683-691` three-arm idiom — stricter, and matches the C7 guard already in-file |
| "Add a `SOLEUR_*` marker" | `LUKS_LOG_TAG` default `luks-monitor` (`:193`) already vector-allowlisted (`vector.toml:184`) | Zero infra change |
| "This is a code fix only" | The prepare block is **top-level**, below the sourced-detection guard (`:652`); `run_case` `source`s the script ("functions only, no main body") | Untestable unless extracted into a function above `:652`. Convention already exists at `:351`/`:608` |
| ADR-119 records the cutover mechanism | §(g) documents the 3-arm `blkid` state machine on the **device**; the Reversibility proof describes `prepare_luks_target` as *"selects, `luksFormat`s-if-raw, and opens the FRESH device"* | **The ADR carries the same gap** — zero `mkfs` hits, no staging-mount step. Amend it |
| **Review finding:** v1 claimed a failed `:892` umount makes "rollback fail EBUSY" | `rollback()` `:577` is `cryptsetup close … 2>/dev/null \|\| true` — the EBUSY is **swallowed**, rollback remounts plaintext (`:579`) and reports **success** | Corrected. The real end state is worse: **plaintext live at `$MOUNT` AND a still-open mapper holding a full divergent copy still mounted at `$STAGING`**, run green, no telemetry. Also violates ADR-119 §(b)'s "retained volume is DETACHED, not attached-unmounted" in the mirror direction |
| **Review finding:** v1 justified not reordering `FLIP_DONE` as "rollback would not learn a partial flip occurred" | **False.** `FLIP_DONE`'s only in-script reader is `cleanup()` `:602`, whose condition is `[ "$FLIP_DONE" = "1" ] \|\| [ "$FREEZE_HELD" = "1" ]` — and `FREEZE_HELD=1` is set at `:808`, ~90 lines earlier, so the disjunction is **already** satisfied. The persisted copy has no in-script reader (`read_state` is used only for `PLAINTEXT_DEV`, `:580`) | Rationale corrected. Guarding `:899` is chosen because it is the **smaller diff**, not because ordering is safety-critical. v1's AC pinning the ordering is **dropped** — it encoded a false invariant |

<!-- lint-infra-ignore end -->

## User-Brand Impact

**If this lands broken, the user experiences:** their entire checked-out repository — including
`refs/checkpoints/*`, which `model.c4:186` records as **sole-copy** (pushed by no refspec, no git
remote at all on signup-provisioned workspaces) — silently written to the wrong block device, then
`/mnt/data` repointed at an **unformatted** mapper. Total, unrecoverable loss of every workspace for
every user, presenting as an empty `/workspaces`.

**If this leaks, the user's source code is exposed via:** a full plaintext copy of all 8 workspaces
sitting on web-1's **root disk** at `/mnt/data-luks` right now (left by the swallowed mount) —
unencrypted user source on the exact surface the published privacy policy claims is LUKS-encrypted.

**Brand-survival threshold:** `single-user incident`

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/workspaces-cutover.sh` | Add `prepare_staging_target()` above `:652`; call it in place of `:695-696`. Plus three **strictly-additive** fail-closures on existing lines: `:670`, `:892`, `:899` |
| `apps/web-platform/infra/workspaces-luks-loopback.test.sh` | **New.** Real luksFormat → luksOpen → mkfs → mount → assert → rsync → verify on a loopback device. The only artifact that can catch this defect class |
| `apps/web-platform/infra/workspaces-luks.test.sh` | ~6 stubbed cases for branches loopback cannot reach cheaply |
| `.github/workflows/infra-validation.yml` | Wire the loopback suite. Suites are invoked by **explicit `run:` lines** (`:382, :387, :616, :619`) — there is no glob, so an unwired suite is an **orphan that never runs** |
| `.github/workflows/workspaces-luks-cutover.yml` | Structural dispatch gate: hard-fail `dry_run=false` unless loopback validation is evidenced (see Phase 1) |
| `knowledge-base/engineering/architecture/decisions/ADR-119-…md` | Amend §(g) (mapper arm) + the Reversibility proof's `prepare_luks_target` description |

**Not edited (v1 → v2 cuts):** no `CLEAN_STAGING_STRAY` workflow input, no `rm -rf`, no `du -sb`, no
path-precondition block, no `_same_dev` retrofit onto `:901`/`:911`. See Non-Goals.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` returned no issue body
containing `apps/web-platform/infra/workspaces-cutover.sh` or `workspaces-luks`.

## Implementation Phases

### Phase 1 — RED, on real devices: the loopback suite

**Promoted from v1's Phase 6.** The stubbed harness proves the shell *branches* correctly; the defect
was a real command that was never called. A stub asserting `mkfs.ext4` appears in `$CALLS` proves only
that the line was written. The loopback suite is the only thing that exercises actual `blkid`/`mkfs`/
`mount`/`findmnt` behaviour.

Create `apps/web-platform/infra/workspaces-luks-loopback.test.sh`: `truncate` a backing file, `losetup`
it, real `cryptsetup luksFormat`/`luksOpen`, then drive `prepare_staging_target` → `rsync` → 
`verify_byte_identity` against fixture data; assert `findmnt` reports the mapper; tear down.

**Write L5 (mkfs suppressed) first and watch it fail at the positive control** — that reproduces the
2026-07-19 incident on a real device and is the actual RED step.

**No escape hatch.** v1 permitted shipping if Phase 6 proved infeasible, enforced only by prose in a
merged PR body — a procedural gate, precisely the class this plan exists to eliminate and the class
named in the learning it cites. Enforcement, in preference order:

1. **Primary:** run the suite in CI and wire it in `infra-validation.yml` as a real check.
   **Verified at deepen time:** `losetup`, `cryptsetup`, `mkfs.ext4` and `mount` are all present on
   GitHub-hosted `ubuntu-latest`, `/dev/loop*` is available, and **no privileged container or
   `--cap-add=SYS_ADMIN` is required** (GH-hosted runners are VMs, not job containers). The
   "runner privileges might block it" hedge is therefore removed — Phase 1 is feasible as a plain
   `run:` step, so it is **not deferrable**.
2. **Structural backstop (ship regardless):** a step in `workspaces-luks-cutover.yml` that hard-fails
   `dry_run=false` unless loopback validation is evidenced. This puts the gate on the **irreversible
   arm**, where it can actually fire — rather than on a merge that has already happened.

Option 2 ships either way: it is the only form of the "do not freeze until validated" gate that is
not prose.

#### Phase 1b — stubbed-harness prerequisites (verified blockers, not incidental)

Plan review verified the harness against the files and found v2's assumptions wrong. These are
**scoped work items**, not discovered-at-implementation surprises:

- **`run_case` does not live in `workspaces-luks.test.sh`** — that file has **zero** `run_case`
  references; the harness exists only in `workspaces-luks-freeze.test.sh`. **Decide explicitly:**
  extract `run_case` into a shared `workspaces-luks-harness.sh` sourced by both, or put the new
  stubbed cases in the freeze file. Either is acceptable; leaving it implicit is not.
- **`run_case` never sets `WORKSPACES_STAGING`** (`grep -n STAGING workspaces-luks-freeze.test.sh` →
  zero hits). It sets `WORKSPACES_MOUNT="$MNT"` but leaves `STAGING` at its default `/mnt/data-luks`,
  so every new case would `mkdir -p /mnt/data-luks` on the **real CI runner** → non-root `EACCES` →
  die. Every `rc 0` case would false-fail for a reason unrelated to the code under test. **Add
  `WORKSPACES_STAGING="$d/staging"` to `run_case`** — a modification to a shared harness, called out
  here rather than discovered later.
- **The `mountpoint` stub returns one global rc** (`return "${MOUNTPOINT_RC:-0}"`). The new function
  calls `mountpoint -q "$STAGING"` more than once needing *different* answers (stray check vs. mount
  guard), and T-cases need a state transition (not mounted → mount → mounted). **A sequenced stub is
  required** (e.g. `MOUNTPOINT_RCS="1 1 0"` consumed by call index). Without it roughly half the
  matrix is unwritable as specified.
- **Stub list** must add `readlink` (now load-bearing for `_same_dev`) and `mkdir`. Already stubbed
  and fine: `mount`, `mountpoint`, `logger`, `hostname`, `cryptsetup`, `die`, `emit_drift`.
- **T-cases asserting the `dm-N` form belong in the loopback suite, not the stub harness.** On a CI
  box neither `/dev/mapper/workspaces` nor `/dev/dm-N` exists, so `readlink -f` returns the literal
  path and a stubbed `dm-N` case **false-fails**. Only Phase 1's real devices can exercise
  canonicalization — which is a further reason the loopback suite is not optional.

### Phase 2 — GREEN: `prepare_staging_target()`

<!-- lint-infra-ignore start: specifies the SHELL FUNCTION this PR adds to workspaces-cutover.sh; the 'operator action' referenced is re-dispatching the gated workflow, which is exactly the automated route this lint asks for -->

Define **above the sourced-detection guard at `:652`** (after `log`/`die`/`emit_drift`/`_vscrub`/
`LUKS_LOG_TAG`), mirroring the `:351`/`:608` convention. **No `local`** for `KEY`, `FRESH_DEV`,
`raw_type` — they are read at `:716`, `:737-739`, `:909-914` and must stay global. (`fs_type`,
`staging_src`, `STAGING_FS_REUSED` are function-internal → **do** declare them `local`.)

**Define `emit_staging_target()` too**, above `:652` alongside `emit_drift`. v1/v2 *called* it and
never defined it — under `set -uo pipefail` with no `-e` an undefined function returns 127 and is
**swallowed**, so the `die` would fire but the marker would silently never emit: exactly the "gate
that never announced what it did" class this plan exists to close. It must emit via a bare `echo` at
column 0 **plus** `logger -t "$LUKS_LOG_TAG"`, matching the `:336-338` convention — the harness routes
`logger` to `$MARKER_LOG`, so any AC asserting a marker depends on this shape.

**`set -u` initializations (verified blockers).** Initialize `STAGING_FS_REUSED=0` **before** the
`if` — it is assigned only in the `ext4` arm, but the `result=ok` marker reads it on every path, so
the first-cutover path would abort with `unbound variable` *and emit no marker*. Same for any
`stray_*` variable the marker reads. Any optional env read must use `${VAR:-0}`.

1. `mkdir -p "$STAGING" || { emit_drift staging_mkdir_failed; die "…"; }` — `:695` is unguarded today.
1b. **Mapper preconditions — anchor the device before trusting the name.** The three-arm `blkid` guard
   is total over *filesystem types*, not over *mapper existence or backing device*:

   ```bash
   [ -b "$MAPPER" ] || { emit_drift staging_mapper_absent; die "$MAPPER is not a block device — luksOpen did not produce a mapper; refusing to prepare"; }
   mapper_dev="$(cryptsetup status "$MAPPER_NAME" 2>/dev/null | sed -n 's/^ *device: *//p')"
   _same_dev "$mapper_dev" "$FRESH_DEV" \
     || { emit_drift staging_mapper_wrong_device; die "$MAPPER is backed by '${mapper_dev:-<unknown>}', not $FRESH_DEV — a stale mapper from a prior run; refusing to prepare"; }
   ```

   This closes the recursion described in the Overview: without it a stale mapper pointing at a
   different container passes every downstream gate including the new positive control.
2. **Stray guard — detect and REFUSE, never delete.** If `$STAGING` is not a mountpoint and is
   non-empty, it is a stray root-disk copy (canonical data lives at `$MOUNT`; post-repoint `$STAGING`
   is unmounted, `:892`):

   ```bash
   if ! mountpoint -q "$STAGING" && [ -n "$(ls -A "$STAGING" 2>/dev/null)" ]; then
     emit_drift staging_stray_present
     die "$STAGING is a non-mountpoint and non-empty — a stray root-disk copy is present; refusing to prepare over it"
   fi
   ```

   This is fail-closed, non-destructive, and mechanically blocks any cutover until the stray is
   remediated. Deletion moves to a separate PR (Non-Goals).

2b. **Refuse a re-run after an already-successful cutover.** Spec-flow found this entry state has **no
   defined outcome** in v1/v2 and it is reachable by the most likely operator action — re-dispatch.
   After a successful cutover `$MOUNT` **is** the mapper, so: `blkid` → `ext4` → reuse arm →
   `mountpoint -q "$STAGING"` is false → the mapper is mounted a **second** time at `$STAGING` while
   live at `$MOUNT`, making `$MOUNT` and `$STAGING` the same filesystem, and the bulk rsync at `:802`
   then runs **source into itself**. That is the very double-mount hazard this plan calls highest
   severity at `:892`, manufactured by the new function.

   ```bash
   mount_src="$(findmnt -no SOURCE "$MOUNT" 2>/dev/null || true)"
   ! _same_dev "$mount_src" "$MAPPER" \
     || { emit_drift staging_already_cutover; die "$MOUNT is ALREADY the LUKS mapper — this cutover has already completed; refusing to re-stage onto the live volume"; }
   ```
3. **DRY_RUN short-circuit** — `[ "$DRY_RUN" = "1" ] && { log "(dry-run) would mkfs+mount …"; emit marker result=dryrun; return 0; }`, mirroring the `:573`/`:614` early-return idiom. Note the stray guard above runs in **both** arms — it is a read-only assert, so the rehearsal reports the condition honestly.
4. **mkfs guard** — mirror the script's own three-arm `:683-691` shape, on the **mapper**:

   ```bash
   # -p: LOW-LEVEL probe, bypassing the /run/blkid/blkid.tab cache (man blkid: "Switch to low-level
   # superblock probing mode"). A cached entry can report the PREVIOUS TYPE for the same device name
   # after a rollback-and-reformat cycle — and one arm here mkfs's destructively while another
   # refuses destructively, so a stale read is wrong in BOTH directions.
   # NOTE: `-c /dev/null` is NOT equivalent (verified) — it suppresses use of a cache FILE but still
   # performs a normal (non-probing) lookup. Only `-p` forces the live superblock scan. Use `-p`.
   fs_type="$(blkid -p -s TYPE -o value "$MAPPER" 2>/dev/null || true)"
   if [ -z "$fs_type" ]; then
     log "mapper carries NO filesystem — mkfs.ext4 (first cutover)"
     # A multi-TB volume with lazy init disabled writes the full inode table SYNCHRONOUSLY: a long,
     # silent, progress-free operation. Log before it or the operator reads a working run as a hang.
     log "mkfs may take several minutes on a large volume (lazy init disabled deliberately) — not a hang"
     # lazy_*_init=0: the defaults finish inode-table/journal init in a BACKGROUND kernel thread that
     # would compete with the bulk rsync. Pay it here, pre-freeze.
     mkfs.ext4 -q -E lazy_itable_init=0,lazy_journal_init=0 "$MAPPER" \
       || { emit_drift staging_mkfs_failed; die "…"; }
   elif [ "$fs_type" = "ext4" ]; then
     log "mapper already carries ext4 — no mkfs (idempotent re-run)"
     local STAGING_FS_REUSED=1
   else
     emit_drift staging_unexpected_fs
     die "mapper carries TYPE=$fs_type (expected empty or ext4) — refusing to mkfs over an unrecognised filesystem"
   fi
   ```

   The `else` arm is load-bearing: it stops a re-run wiping an already-good copy. `blkid -s TYPE -o
   value` (not bare `blkid`) is required — bare `blkid` returns 0 for a partition table with no
   filesystem, which would **skip** the needed mkfs and reproduce this bug.

   The `ext4` no-op arm is **not silent**: it will reuse a *populated* filesystem from a prior partial
   run. Not a correctness hole (the `--delete --checksum` delta rsync at `:839` reconciles it and C1
   verifies byte identity) but it must be visible → `reused=1` in the marker.
5. **Fail-closed mount** — explicit `if/then`, never `A || B || C` (the `:788-789` L3 lesson):

   ```bash
   if ! mountpoint -q "$STAGING"; then
     mount "$MAPPER" "$STAGING" || { emit_drift staging_mount_failed; die "…"; }
   fi
   ```
6. **Positive control** — the primary regression guard, on **new code only**:

   ```bash
   # findmnt -no SOURCE returns /dev/mapper/<name> for an active mapper in the common case
   # (VERIFIED at deepen time), but the form is not contractually guaranteed across
   # kernel/util-linux versions, so canonicalize both sides rather than string-compare.
   # `findmnt -no MAJ:MIN` is an equally robust alternative and is form-independent by construction.
   #
   # THIS HELPER CARRIES ITS OWN POSITIVE CONTROL. The naive form
   #   [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ]
   # FAILS OPEN: if readlink errors or is absent, BOTH substitutions yield "" and "" = "" is TRUE —
   # certifying a mount that was never verified. That is verbatim the failure this script already
   # named at :438 ("reads 'the probe failed' as 'the mount is clean'"). Explicit rc checks plus
   # `[ -b "$b" ]` make the canonicalizer prove it ran against a real block device.
   _same_dev() {
     local a b
     [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
     a="$(readlink -f -- "$1" 2>/dev/null)" || return 1
     b="$(readlink -f -- "$2" 2>/dev/null)" || return 1
     [ -n "$a" ] && [ -n "$b" ] && [ -b "$b" ] && [ "$a" = "$b" ]
   }

   staging_src="$(findmnt -no SOURCE "$STAGING" 2>/dev/null || true)"
   _same_dev "$staging_src" "$MAPPER" || { emit_staging_target fail source_not_mapper; die "…"; }
   ```

   Assert **where the bytes go**; never infer it from a command that was allowed to fail.
7. **Capacity gate — folded in, no longer deferred.** Spec-flow established that this PR is what makes
   `ENOSPC` reachable: before the fix the rsync landed on the **root disk**, where it evidently fit;
   after the fix it lands in the **mapper**, whose usable capacity is the volume *minus* the LUKS2
   header *minus* ext4 metadata. Verified: LUKS2 metadata + keyslot areas give a default data offset
   of **~16–32 MiB** (the plan's earlier "~16 MB" was the low end). Since the fresh volume is sized
   equal to the plaintext source, the mapper is **strictly smaller** than the source filesystem — so
   this is not a hypothetical. `df "$STAGING"` at `:877` is a
   post-copy preflight for the repoint, not a capacity gate — there is genuinely nothing before `:802`.
   And while `:802` is pre-freeze, the delta rsync at `:839` is **inside** the freeze, where an ENOSPC
   burns the irreversible-freeze approval exactly as the 2026-07-19 run did.

   ```bash
   src_b="$(du --apparent-size -sb "$MOUNT"/workspaces 2>/dev/null | cut -f1)"
   avail_b="$(df --output=avail -B1 "$STAGING" 2>/dev/null | tail -1 | tr -dc '0-9')"
   [[ "$src_b" =~ ^[0-9]+$ && "$avail_b" =~ ^[0-9]+$ ]] \
     || { emit_drift staging_capacity_unreadable; die "capacity probe produced non-numeric output (src='$src_b' avail='$avail_b') — cannot gate ENOSPC"; }
   [ "$avail_b" -gt "$src_b" ] \
     || { emit_drift staging_insufficient_capacity; die "LUKS target has $avail_b B available but the source is $src_b B — the copy cannot fit; aborting BEFORE the freeze"; }
   ```

   Runs post-mount, pre-freeze: zero downtime on failure, consistent with every other new assert. The
   non-numeric guard mirrors the `:867` idiom so a failed `du`/`df` cannot pass vacuously.
8. Emit the `result=ok` marker (`fs=`, `reused=`, `reused_bytes=`, `source=`, `mapper=`, `avail_b=`).
   Carry **`reused_bytes=`** alongside `reused=1`: the most common retry is "mkfs succeeded, mount
   failed", where the filesystem is *empty* and `reused=1` fires anyway. Without a byte count the flag
   cries wolf on its most frequent trigger and gets ignored.

<!-- lint-infra-ignore end -->

### Phase 3 — wire the call site

Replace `:695-696` with `prepare_staging_target`. Top-level call ordering is otherwise unchanged.

### Phase 4 — strictly-additive sibling fail-closures

<!-- lint-infra-ignore start: enumerates fail-open->fail-closed code edits and the die-message text they emit; the ROLLBACK=1 prose is the WARNING the new messages carry, not an instruction -->

Every item converts fail-open → fail-closed. None can make a currently-passing run fail for a new
reason; each can only abort a run that is *already* broken.

| Site | Current | Failure mode | Fix |
|---|---|---|---|
| `:670` | `[ -b "$(findmnt -no SOURCE "$MOUNT")" ] \|\| log "WARN…"` | The **source of every byte**, anchored only as a warning — a live counterexample to this plan's own invariant. | `\|\| die`. Optionally also compare against the persisted `PLAINTEXT_DEV`. |
| `:686` | `[ "$DRY_RUN" = "1" ] \|\| printf … \| cryptsetup luksFormat …` | Unguarded — **the identical swallowed-failure defect, two lines above the block being fixed.** A failed `luksFormat` falls through to `luksOpen`. | `\|\| { emit_drift luksformat_failed; die "…"; }` |
| `:693` | `printf … \| cryptsetup luksOpen …` | Unguarded. A failed open leaves `$MAPPER` absent; the new code would then take the *"no filesystem"* arm and die as `staging_mkfs_failed` — a **misleading reason** on the operator's only no-SSH channel. | `\|\| { emit_drift luksopen_failed; die "…"; }` |
| `rollback()` `:577` | `umount "$MOUNT"` then `cryptsetup close "$MAPPER_NAME" 2>/dev/null \|\| true` — **`$STAGING` is never unmounted** | If `$STAGING` is mounted from the mapper, the close fails `EBUSY` **silently** and the mapper is leaked open + mounted **through the recovery path**. Byte-for-byte the `:892` hazard, on the path where it matters more. | Add `umount "$STAGING" 2>/dev/null \|\| true` **before** the `cryptsetup close`, and drop the `2>/dev/null \|\| true` on the close so an EBUSY is at least reported. |
| `:892` | `umount "$STAGING" 2>/dev/null \|\| true` | **Highest severity.** A failed umount leaves `$MAPPER` mounted at `$STAGING` *and* then at `$MOUNT` (`:899`). `:901` only checks `$MOUNT`, so it **passes**. `rollback()` `:577` then swallows the resulting EBUSY (`\|\| true`), remounts plaintext, and reports **success** — leaving **plaintext live at `$MOUNT` and a still-open mapper holding a divergent full copy at `$STAGING`**, with no telemetry. | `umount "$STAGING" \|\| { emit_drift staging_umount_failed; die "…"; }` |
| `:899` | `mount "$MAPPER" "$MOUNT"` (unguarded) | A failed mount falls through to `FLIP_DONE=1; persist_state` at `:900` before the `:901` assert. | `\|\| { emit_drift repoint_mount_failed; die "…"; }`. **`FLIP_DONE` is deliberately not reordered** — but only because guarding is the smaller diff. It is *not* safety-critical: `cleanup()` `:602` already has `FREEZE_HELD=1` (set `:808`) satisfying its disjunction, and the persisted copy has no in-script reader. |

**Die-message requirement for all prepare-time aborts.** Every new `die` in `prepare_staging_target`
fires at `:695`, long before `FREEZE_HELD=1` (`:808`), so `cleanup()`'s rollback condition
(`CANARY_OK != 1 && (FLIP_DONE=1 || FREEZE_HELD=1)`) is **not** met and no rollback runs — correctly,
since nothing has been unwound. But the messages must **say so explicitly** ("no freeze was held; no
rollback is needed; do NOT run `ROLLBACK=1`"). Otherwise an operator reaching for `ROLLBACK=1` after a
prepare-time abort triggers `umount "$MOUNT"` on the **live plaintext volume** and takes a gratuitous
outage. Residual state after such an abort is a mapper left open (and possibly mounted at `$STAGING`);
that is idempotent on re-run and must be documented in the die text.

<!-- lint-infra-ignore end -->

### Phase 5 — ADR-119 amendment

Amend §(g) to add the **mapper** arm (the existing state machine covers only the *device*), and
correct the Reversibility proof's description of `prepare_luks_target`. Both are description
corrections completing an existing decision — no new ADR.

## Acceptance Criteria

Pruned from v1's 26 to 11 and renumbered. **Behaviour is asserted by tests, not by greps over shell
source** — grep-shaped ACs break on harmless refactors and pass on subtly wrong code. Only criteria
no test can express are kept.

### Pre-merge (PR)

- **AC1** — **Regression pin.** `verify_byte_identity`, `emit_verify_diff`, `assert_mount_quiesced`,
  `emit_freeze_holders`, and both rsync invocations are **byte-identical to `origin/main`**. C1/G4 are
  not weakened. **Anchor by content, never by line number** (`cq-cite-content-anchor-not-line-number`)
  — inserting `prepare_staging_target` above `:652` shifts every subsequent line, so a line-keyed
  check rots immediately. Mechanical form: extract each function body from both revisions
  (`git show origin/main:<file> | sed -n '/^verify_byte_identity()/,/^}/p'`) and `diff` against the
  same extraction from `HEAD`; for the rsync lines, `grep -F` the exact invocation strings.
- **AC2** — **Anti-goal pin.** `! grep -rq 'omit-dir-times' apps/web-platform/infra/` exits 0.
  (Not `grep -rc … == 0`: a directory arg without `-r` errors, and *with* `-r` it emits **per-file**
  counts — roughly 200 lines of `file:0` — so an `== 0` comparison is meaningless and false-fails.)
- **AC3** — **Declaration position.** `prepare_staging_target` is declared above the sourced-detection
  guard (`:652`), so the harness can reach it.
- **AC4** — **Vacuity guard.** Deleting `prepare_staging_target` from a scratch copy makes every new
  stubbed case report `HARNESS_UNDEFINED` rather than pass.
- **AC5** — **No orphan suite.** `.github/workflows/infra-validation.yml` contains an explicit
  `run: bash apps/web-platform/infra/workspaces-luks-loopback.test.sh` line, and the loopback suite
  reports a **non-zero executed-case count** (it cannot silently skip when `losetup`/`cryptsetup` is
  unavailable — it exits non-zero with `LOOPBACK_UNAVAILABLE`).
- **AC6** — **The structural dispatch gate exists.** `workspaces-luks-cutover.yml` hard-fails
  `dry_run=false` absent loopback-validation evidence. Verified by `actionlint` + reading the step
  condition; the gate is on the irreversible arm, not in prose.
- **AC7** — `bash -n apps/web-platform/infra/workspaces-cutover.sh` exits 0;
  `bash apps/web-platform/infra/workspaces-luks.test.sh` and the loopback suite each report 0 failures;
  `actionlint` exits 0 on both edited workflows.
- **AC8** — **No new destructive operation.** `git diff origin/main -- apps/web-platform/infra/workspaces-cutover.sh`
  introduces **zero** `rm`, `rm -rf`, `mkfs` outside the guarded `[ -z "$fs_type" ]` arm, or `dd`.
- **AC9** — ADR-119 §(g) contains a mapper arm mentioning `mkfs`, and the Reversibility proof no
  longer describes `prepare_luks_target` without it.
- **AC10** — PR body states honestly that (a) a green dry-run does **not** validate this fix (the
  freeze/copy/verify path is entirely behind the `DRY_RUN` gate — the workflow's own `dry_run` input
  description already says so), and (b) because this mount failure predates the freeze-quiesce work
  merged 2026-07-19, **no cutover attempt has ever written to the LUKS volume** — the earlier
  inngest-redis AOF diagnosis was real but was not the only defect.
- **AC11** — PR body uses `Ref #6588`, **not** `Closes #6588` (ops-remediation carve-out on
  `wg-use-closes-n-in-pr-body-not-title-to`): #6588 stays open until the volume is encrypted **and**
  verified live.

### Post-merge (operator)

None. `Automation: fully automated — no operator step.` The real freeze is a separately gated,
operator-approved dispatch that this task must not trigger.

## Test Scenarios

**Loopback (Phase 1) — real devices, primary evidence.** These replace v1's stubbed T1/T2/T5/T7,
which asserted the same branches without exercising the mechanism.

| # | Scenario | Expect |
|---|---|---|
| L1 | Fresh loop device: luksFormat → luksOpen → `prepare_staging_target` | real `mkfs.ext4` runs; mount succeeds; `findmnt` reports the mapper; `result=ok` |
| L2 | Re-run against the same prepared device | **no** mkfs; mount idempotent; `reused=1`; rc 0 |
| L3 | Full path: prepare → `rsync` fixture data → `verify_byte_identity` | 0 diffs; bytes provably on the mapper |
| L4 | Observe and record which form `findmnt -no SOURCE` actually returns on the runner | recorded — this is the evidence that decides the deferred `:901`/`:911` retrofit |
| L5 | **Incident reproduction:** mkfs suppressed | mount fails → `staging_mount_failed`; and with the mount forced, the positive control catches `source_not_mapper`. **Written first; must fail before the fix.** |

**Stubbed (`workspaces-luks.test.sh`) — only branches loopback cannot reach cheaply.** Harness rule
(inherited, load-bearing): never pipe into an assertion predicate — under `set -o pipefail` an early
`grep -q` match SIGPIPEs the producer and a negative assertion fails **open**.

| # | Scenario | Expect |
|---|---|---|
| T1 | `blkid` → `xfs` (unexpected FS) | **no** `mkfs.ext4`; `staging_unexpected_fs`; rc≠0 |
| T2 | `mkfs.ext4` returns 1 | `staging_mkfs_failed`; rc≠0; marker emitted **before** the die |
| T3 | `DRY_RUN=1` | no `mkfs.ext4`, no `mount`; `result=dryrun`; rc 0 |
| T4 | Stray present (non-mountpoint, non-empty), both arms | rc≠0; `staging_stray_present`; **no** `rm` anywhere in `$CALLS` |
| T5 | `:892` `umount "$STAGING"` returns 1 | rc≠0; `staging_umount_failed`; **no** `mount "$MAPPER" "$MOUNT"` recorded |
| T6 | `:899` `mount "$MAPPER" "$MOUNT"` returns 1 | rc≠0; `repoint_mount_failed`; run does not reach the canary |
| T7 | `:670` `findmnt` reports a non-block source | rc≠0 (was a `log WARN`) |
| T8 | Vacuity guard (AC4) | `HARNESS_UNDEFINED`, not a pass |
| T9 | `$MAPPER` absent (`luksOpen` failed) | rc≠0 with `staging_mapper_absent` — **not** `staging_mkfs_failed` (reason must be accurate) |
| T10 | `cryptsetup status` reports a device ≠ `$FRESH_DEV` (stale mapper) | rc≠0; `staging_mapper_wrong_device`; **no** `mkfs.ext4` |
| T11 | `$MOUNT` already sourced from `$MAPPER` (re-run after success) | rc≠0; `staging_already_cutover`; **no** `mount`, **no** rsync reachable |
| T12 | `df --output=avail` < `du` source bytes | rc≠0; `staging_insufficient_capacity` |
| T13 | `du`/`df` return non-numeric | rc≠0; `staging_capacity_unreadable` (no vacuous pass) |
| T14 | `readlink` fails / returns empty inside `_same_dev` | `_same_dev` returns **1** (fails CLOSED) — the naive form would have returned 0 |
| T15 | `:686` `luksFormat` returns 1 | rc≠0; `luksformat_failed`; `luksOpen` not reached |
| T16 | First-cutover path (empty arm) emits a marker | marker present with `reused=0` — guards the `STAGING_FS_REUSED` unbound-variable abort |

## Observability

```yaml
liveness_signal:
  what: SOLEUR_WORKSPACES_LUKS_STAGING_TARGET (result=ok|fail|dryrun)
  cadence: once per cutover-workflow run (both arms)
  alert_target: Better Stack Logs source 2457081 via the `luks-monitor` syslog tag
  configured_in: apps/web-platform/infra/vector.toml:184 (tag ALREADY allowlisted — zero infra change)
error_reporting:
  destination: Sentry via emit_drift -> workspaces_luks_emit (WL_LEVEL=fatal); run log always
  fail_loud: true — every new failure path calls emit_drift then die; no path returns non-zero silently
failure_modes:
  - mode: mapper carries no filesystem and mkfs fails
    detection: result=fail reason=mkfs_failed
    alert_route: emit_drift staging_mkfs_failed -> Sentry fatal
  - mode: mapper carries an UNEXPECTED filesystem (re-run would wipe a good copy)
    detection: result=fail reason=unexpected_fs fs=<type>
    alert_route: emit_drift staging_unexpected_fs -> Sentry fatal
  - mode: mount of the mapper at $STAGING fails. POST-FIX THIS IS *NOT* THE 2026-07-19 DEFECT —
          mkfs now runs first, so this means something NEW (corrupt fs, missing ext4 module, EBUSY).
          Investigate filesystem integrity; do not assume the original root cause.
    detection: result=fail reason=mount_failed
    alert_route: emit_drift staging_mount_failed -> Sentry fatal
  - mode: mapper absent, or backed by a device other than $FRESH_DEV (stale mapper from a prior run)
    detection: result=fail reason=mapper_absent | mapper_wrong_device mapper_dev=<actual>
    alert_route: emit_drift staging_mapper_absent | staging_mapper_wrong_device -> Sentry fatal
  - mode: cutover re-dispatched after it already succeeded ($MOUNT is already the mapper)
    detection: result=fail reason=already_cutover
    alert_route: emit_drift staging_already_cutover -> Sentry fatal
  - mode: LUKS target too small for the source (ENOSPC, first reachable in this PR)
    detection: result=fail reason=insufficient_capacity avail_b=<n> src_b=<n>
    alert_route: emit_drift staging_insufficient_capacity -> Sentry fatal
  - mode: $STAGING mounted but NOT from $MAPPER (silent wrong-target)
    detection: result=fail reason=source_not_mapper source=<actual> mapper=<expected>
    alert_route: emit_drift staging_not_mapper -> Sentry fatal
  - mode: stray plaintext copy on the root disk blocks the cutover
    detection: result=fail reason=stray_present
    alert_route: emit_drift staging_stray_present -> Sentry fatal
  - mode: staging umount fails at repoint (would leave two live divergent copies)
    detection: emit_drift staging_umount_failed
    alert_route: Sentry fatal (previously SILENT — `|| true`)
logs:
  where: workflow-run log (stdout, column 0) + Better Stack via `logger -t "$LUKS_LOG_TAG"`
  retention: Better Stack Logs source retention; GH Actions run-log retention
discoverability_test:
  command: bash apps/web-platform/infra/workspaces-luks-loopback.test.sh
  expected_output: "0 failures, non-zero executed-case count; L5 demonstrates the guard catching the incident"
```

The swallowed mount produced **no marker at all** — which is why the failure surfaced as an
uninterpretable C1 itemize code rather than a named condition. Per `hr-observability-as-plan-quality-gate`,
the target-preparation asserts now self-report on **every** outcome, including success: a green run
emitting `result=ok` proves the assert *executed*, closing the "gate that silently never ran" class
(`2026-07-16-a-gate-that-proves-it-cannot-fail-open-shipped-its-own-proof-unwired.md`).

Per `hr-observability-layer-citation`: the emit layer is the host `logger` → `vector` → Better Stack
Logs pipeline (`vector.toml:179-184`), plus Sentry via `workspaces_luks_emit`. No SSH is required to
read any of it (`hr-no-ssh-fallback-in-runbooks`).

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-119** — no new ADR. The decision (additive LUKS volume + cutover) is unchanged; its
recorded mechanism is incomplete in exactly the way the script was:

- §(g) documents a three-arm `blkid` state machine on the **device** only. Add the **mapper** arm:
  after `luksOpen` the mapper is an empty container and `mkfs.ext4` must lay the filesystem **inside**
  it, under the same discriminator.
- The Reversibility proof (`:427`) describes `prepare_luks_target` as *"selects, `luksFormat`s-if-raw,
  and opens the FRESH device"* — omitting both the `mkfs` and the staging mount. Correct it and record
  the staging positive control.

**Deliberately NOT amended:** the 2026-07-18 authorization addendum. Plan review established that its
reversibility claim is the **load-bearing premise** of the ungated-dry-run authorization model
(`environment: ${{ !inputs.dry_run && 'workspaces-luks-cutover' || '' }}`). v1 would have put an
irreversible `rm -rf` of user source on the arm that has **zero human approval by construction**, then
edited the prose justifying that arm. v2 removes the deletion entirely, so the premise stands
untouched and no authorization-model amendment is needed.

### C4 views

**No C4 impact.** Verified by reading all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`), not by keyword grep:

- **External human actors:** none added or changed (only the workspace Owner, `model.c4:9`).
- **External systems/vendors:** none added — Hetzner, Doppler, R2, Better Stack (`model.c4:285`) and
  Sentry are all already modeled; no new webhook, outbound API, or third-party store.
- **Containers / data stores:** `workspacesVolume` (`model.c4:184-186`) already models the volume, its
  `/mnt/data` mount, the sole-copy property, and — verbatim — the plaintext-at-rest gap and the
  `#6588`/ADR-119 additive-LUKS cutover. This fix repairs the cutover's implementation; the modeled
  target state is unchanged and the description stays true (the volume remains plaintext until the
  cutover succeeds).
- **Access relationships:** unchanged — no owner/sharing/tenancy semantics touched.

No element description is falsified, so no `.c4` edit and no `views.c4 include` line is required.

### Sequencing

Code fix and ADR amendment ship in **this** PR. Nothing architectural is deferred.

## Domain Review

**Domains relevant:** Engineering, Legal/Compliance

### Engineering

**Status:** reviewed (CTO + 5-agent plan-review panel)

**CTO:** confirmed the diagnosis and raised the framing one layer — every downstream gate is
relational, none anchored — making the positive control the real fix. Endorsed the function extraction
as low-risk given unchanged top-level ordering. Surfaced four same-class sites; three folded in, the
capacity gate deferred. Raised three failure modes the fix itself would have introduced (silent
stale-FS reuse, `mkfs` lazy init competing with the bulk rsync, unproven `findmnt` return form), all
now mitigated.

**Plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer):**
both simplification reviewers fired on the **same scope** — the stray-copy deletion — which per the
consolidation rule means delete rather than fix; it is gone. Loopback promoted from a deferrable
Phase 6 to a blocking Phase 1 with a structural dispatch gate, on the finding that a hard gate
enforced only by PR prose is itself the procedural-gate class this plan exists to eliminate.
Architecture caught that v1 violated its own invariant at `:670`, that the `:892` consequence was
understated (rollback *swallows* the EBUSY and reports success, leaving two live divergent copies),
and that v1's `FLIP_DONE` rationale was factually wrong — all corrected. The `_same_dev` retrofit onto
`:901`/`:911` was pulled: it *relaxes* a currently-strict assert on the rollback-critical path on a
hypothesis only Phase 1 can settle, and the current code false-fails **safely**. ACs cut 26 → 11.

The correctness panel (Kieran + spec-flow) then converged independently on the sharpest finding:
**the plan's own invariant recurses one layer further and v1/v2 reproduced the bug they diagnosed.**
Nothing anchored `$MAPPER` → `$FRESH_DEV`, so a stale mapper backed by a different container would
pass every gate including the new positive control. Both also found `emit_staging_target` called but
never defined (a 127 swallowed under no `-e` — the marker would silently never emit), and that `:686`
`luksFormat` / `:693` `luksOpen` are unguarded two lines above the block being fixed. Kieran further
proved `_same_dev`'s naive form **can fail open** when `readlink` fails, found three `set -u` aborts
that would have killed the first-cutover path before any marker, found the `blkid` cache hazard, and
verified the stubbed harness cannot run the specified tests (`run_case` is in a different file, never
sets `WORKSPACES_STAGING`, and has a single-rc `mountpoint` stub). Spec-flow found the undefined
re-run-after-success entry state, the `rollback()` `$STAGING` leak, the ROLLBACK-after-prepare-abort
outage trap, and established that **this PR is what first makes ENOSPC reachable** — moving the
capacity gate from deferred to in-scope. All folded into v3.

### Legal/Compliance

**Status:** reviewed
**Assessment:** The published privacy policy claims LUKS encryption-at-rest for user source while
`/workspaces` is plaintext — #6588's own subject, not changed by this plan, which moves toward
compliance. The plan surfaces one finding the issue did not track: the failed cutover left a **second**
full plaintext copy of all 8 workspaces on web-1's root disk. v2 does not delete it (see Non-Goals) but
**mechanically blocks any further cutover until it is remediated**. No new processing activity, no new
data category, no new sub-processor, no cross-border transfer → **no Article 30 entry, no DPIA trigger**.

### Product/UX Gate

Not applicable. Mechanical UI-surface scan of `## Files to Edit` (`.sh`, `.yml`, `.md`) matched no
term or glob in `ui-surface-terms.md`. Product = **NONE**.

## GDPR / Compliance Gate

Invoked under expansion trigger (b) — `brand_survival_threshold: single-user incident` — though the
canonical regex (schemas, migrations, auth flows, API routes, `.sql`) matches nothing here.

**Advisory only; not legal advice.** Findings: **no Critical.** The change processes no personal data,
adds no lawful-basis question, and creates no new processing activity. It *reduces* an existing
Art. 32 (security of processing) exposure by stopping the cutover writing user source to an
unencrypted device. The policy-vs-reality gap remains tracked by #6588 (AC11: `Ref`, not `Closes`).

**AP-009 (never delete user data) — deviation avoided.** v1 proposed deleting the stray copy, which is
user data. Architecture review flagged this as an advisory AP-009 deviation that would have needed to be
named rather than left implicit under "redundant". v2 removes the deletion, so no deviation is taken in
this PR. The follow-up PR that does remediate it **must name the AP-009 deviation explicitly**.

## Infrastructure (IaC)

**Skipped — no new infrastructure.** No new server, service, secret, vendor, DNS record, cert, firewall
rule, or persistent runtime process. The change edits a script already shipped to web-1 by the existing
`workspaces-luks-cutover.yml` tar-bundle content-carrier path (`:175`, ADR-119 §(e)) and adds workflow
steps. No `.tf` file is touched, so `apply-web-platform-infra.yml` does not fire.

## Downtime & Cutover

<!-- lint-infra-ignore start: states that the freeze is a separately gated, operator-APPROVED workflow_dispatch that this task must NOT trigger — the routing this lint requires, described rather than prescribed -->

Deepen-plan gate 4.55 fires: the script this PR edits performs a freeze on a serving surface.

**This PR itself takes nothing offline.** It ships code, tests, workflow steps, and an ADR
amendment. No `.tf` file is touched, so `apply-web-platform-infra.yml` does not fire and no host is
rebooted or replaced. The freeze is a separately gated, operator-approved dispatch that this task must
not trigger.

**The zero-downtime path for the cutover itself was already evaluated and is impossible.** ADR-119's
*Alternatives Considered* records blue-green as **rejected on a hard constraint**, not on preference:
cx33 is `available = false` in all three EU datacenters, so `-replace` would destroy the sole prod
host and fail to recreate it. `cryptsetup reencrypt` in place was also rejected — it operates on the
live device holding sole-copy data with no rollback artifact. The **additive** design (fresh volume +
copy + repoint, retaining the plaintext volume as the rollback backstop) is what remains, and it
requires a bounded freeze to copy the delta consistently.

**Residual downtime is therefore accepted, bounded, and pre-existing:** a ≤20 min freeze budget
(`:805`), armed dead-man (`arm_dead_man`, `:808`), DP-6 `trap cleanup EXIT` auto-rollback, and a
rollback rehearsal (`:783`) that proves the retained plaintext remounts read-only before the freeze
begins. This plan does not extend that window.

**Correction (post-implementation review).** The global claim below — "every new assert is
pre-freeze" — is **false as written**, and was asserted twice in this plan. `FREEZE_HELD=1` is set
at the freeze step, and **two** of this PR's new asserts land below it: the repoint
`umount "$STAGING"` (`staging_umount_failed`) and the repoint `mount "$MAPPER" "$MOUNT"`
(`repoint_mount_failed`). Both are still the right call — each converts a silent two-live-divergent-copies
state into a loud abort, and neither can fail a *correct* run — but their user impact is **in-freeze**:
bounded outage, DP-6 rollback to the retained plaintext, zero data loss. The narrower claim (every die
in `prepare_staging_target` is pre-freeze) is the true one and is what the ADR amendment carries.

**This plan strictly reduces expected downtime.** Every assert in `prepare_staging_target` is **pre-freeze** (the freeze
starts at `:807`), so each converts a would-be mid-freeze failure — or, in the 2026-07-19 case, a
silent wrong-target copy followed by a repoint onto an unformatted mapper — into a zero-downtime
abort. The capacity gate (Phase 2 step 7) is the clearest instance: without it an `ENOSPC` would fire
at the delta rsync (`:839`), **inside** the freeze, burning an irreversible-freeze approval; with it
the run aborts before any user impact. `mkfs`'s synchronous inode-table write is likewise paid
pre-freeze by design.

<!-- lint-infra-ignore end -->

## Risks & Mitigations

<!-- lint-infra-ignore start: risk/mitigation table; the operator-error rows describe scenarios the new guards make impossible, not procedures to follow -->

| Risk | Mitigation |
|---|---|
| **A green dry run is not validation.** The dry-run arm structurally cannot reach the freeze/copy/verify path. | Stated in the PR body (AC10). Evidence comes from Phase 1's loopback suite on real devices, plus the structural dispatch gate (AC6) that blocks `dry_run=false` without it. |
| **`mkfs` is destructive inside a cutover.** A mis-guard wipes an already-good copy on a re-run. | Three-arm guard with a fail-closed `else`; `blkid -s TYPE -o value` (not bare `blkid`, which returns 0 on a bare partition table and would skip the needed mkfs). T1 asserts the `else` arm dies without calling `mkfs`; L2 proves idempotence on a real device. |
| **Function extraction touches a freeze-critical script.** | Scoped to the new logic plus the two lines it replaces (`:695-696`); the `luksFormat`/`luksOpen`/`FRESH_DEV` selection at `:676-693` is **not** moved. AC1 pins C1/G4 and both rsyncs byte-identical to main. |
| **Globals escaping the new function.** `KEY`, `FRESH_DEV`, `raw_type` are consumed at `:716`, `:737-739`, `:909-914`. | Those assignments stay at top level. Only `fs_type`, `staging_src`, `STAGING_FS_REUSED` are `local`. |
| **`findmnt -no SOURCE` form is unproven.** May return `/dev/dm-N` rather than `/dev/mapper/<name>`. | `_same_dev` canonicalizes, but **only in new code**. The existing `:901`/`:911` asserts are left alone — they false-fail *safely* (abort → DP-6 rollback → zero data loss), and relaxing them on an unproven hypothesis would loosen the last assert before `docker start`. L4 records the actual form; the retrofit is a follow-up gated on that evidence. |
| **`_same_dev` CAN fail open in its naive form.** If `readlink` errors or is absent, both command substitutions yield `""` and `[ "" = "" ]` is **true** — certifying a mount that was never verified. Verbatim the failure this script already named at `:438` ("reads 'the probe failed' as 'the mount is clean'"). v2 understated this as a footnote. | The helper now carries its **own positive control**: explicit `|| return 1` on each `readlink`, non-empty checks on both results, and `[ -b "$b" ]` requiring the mapper side to actually be a block device. T14 asserts it fails **closed** where the naive form returned 0. |
| **The three-arm `blkid` guard is total over filesystem *types*, not over mapper *existence* or *backing device*.** A stale mapper from a prior run satisfies `:692`'s `[ ! -e "$MAPPER" ]`, so `luksOpen` is skipped and everything downstream — including the new positive control — operates on the wrong container while reporting success. | Phase 2 step 1b adds `[ -b "$MAPPER" ]` plus a `cryptsetup status`-derived **mapper → `$FRESH_DEV` anchor** at prepare time (pre-freeze), instead of relying on `:912`'s post-repoint canary. T9/T10 cover both. |
| **Re-running after a successful cutover had no defined outcome** — and re-dispatch is the most likely operator action. `$MOUNT` *is* the mapper, so the mapper would be mounted a second time at `$STAGING` and the bulk rsync would run source-into-itself. | Phase 2 step 2b refuses when `$MOUNT` already resolves to `$MAPPER` (`staging_already_cutover`). T11. |
| **`blkid` caches** via `/run/blkid/blkid.tab`; after a rollback-and-reformat cycle a stale entry can report the previous `TYPE`. One arm mkfs's destructively, another refuses destructively — a stale read is wrong in **both** directions. | Use the low-level probe `blkid -p -s TYPE -o value` (equivalently `-c /dev/null`). |
| **`set -u` aborts with no marker.** `STAGING_FS_REUSED` is assigned only in the `ext4` arm but read by the marker on every path — the first-cutover path would abort as `unbound variable` *before emitting anything*. | Initialize `STAGING_FS_REUSED=0` before the `if`; `${VAR:-0}` for every optional env read. T16 pins the first-cutover marker. |
| **`emit_staging_target` was called but never defined** in v1/v2. Under `set -uo pipefail` with no `-e`, an undefined function returns 127 **swallowed** — the die would fire but the marker would silently never emit, recreating the exact class this plan closes. | Defined explicitly above `:652`, emitting a column-0 `echo` **plus** `logger -t "$LUKS_LOG_TAG"` per the `:336-338` convention (the harness routes `logger` to `$MARKER_LOG`). |
| **`rollback()` never unmounts `$STAGING`**, so `cryptsetup close` fails `EBUSY` silently and leaks the mapper open + mounted **through the recovery path**. | Phase 4 adds the umount before the close and stops swallowing the close's error. |
| **A prepare-time abort could provoke a gratuitous outage.** No rollback runs (correctly — `FREEZE_HELD` is not yet set), but an operator reaching for `ROLLBACK=1` would `umount "$MOUNT"` on the **live plaintext volume**. | Every prepare-time die message states explicitly that no freeze was held, no rollback is needed, and `ROLLBACK=1` must not be run. |
| **Harness assumptions were wrong** — `run_case` is not in `workspaces-luks.test.sh`, never sets `WORKSPACES_STAGING` (so cases would `mkdir` against the real runner and `EACCES`), and its `mountpoint` stub has a single global rc. | Phase 1b scopes all three as explicit work items rather than implementation surprises. |
| **`mkfs.ext4` lazy init competes with the bulk rsync.** | `-E lazy_itable_init=0,lazy_journal_init=0`; the mkfs runs **pre-freeze**, so the cost is outside the budget. |
| **Silent stale-FS reuse.** The `ext4` arm reuses a populated filesystem from a prior partial run. | Not a correctness hole — the `--delete --checksum` delta rsync (`:839`) reconciles and C1 verifies byte identity. Made visible via `reused=1`; L2 covers it on a real device. |
| **New asserts could abort a freeze that would otherwise succeed.** | Every assert in `prepare_staging_target` is **pre-freeze**, so a failure aborts with **zero downtime** — strictly better than proceeding onto the wrong device. **Two exceptions** (corrected post-review): the repoint `umount` and repoint `mount` asserts are **in-freeze**; a failure there is a bounded outage + DP-6 rollback, not zero-downtime. Phase 4's changes are all fail-open → fail-closed and cannot make a currently-*correct* run fail. |
| **Unverified current on-host state.** What `blkid` reports for the mapper on web-1 now is unknown from here (no SSH). | The three-arm guard is total by construction — empty, `ext4`, or anything else are all handled and the third arm dies. No arm assumes a particular current state. |
| **The stray copy remains on disk after this PR.** | The `staging_stray_present` die **mechanically blocks every cutover** until it is remediated, and emits a Sentry-fatal + marker so it is tracked rather than invisible. Remediation ships in the immediately-following PR (Non-Goals), sequenced before any real freeze. |

<!-- lint-infra-ignore end -->

## Research Insights (deepen-plan)

### Verify-the-negative sweep — 15/15 CONFIRMS, 0 contradictions

Every negative/absolute claim in this plan was mechanically re-verified against the actual files.
All 15 hold **verbatim**, including exact line numbers and the zero-hit greps for `mkfs`,
`emit_staging_target`, `_same_dev`, `run_case` (in `workspaces-luks.test.sh`), and `STAGING` (in
`workspaces-luks-freeze.test.sh`). Notable confirmations: `rollback()` `:571-591` contains **no**
`$STAGING` reference at all; `FLIP_DONE` has exactly three occurrences (`:170` init, `:602` reader,
`:900` setter) confirming `cleanup()` is its only in-script reader; `read_state` is used only for
`PLAINTEXT_DEV` (`:580`, `:630`).

### External technical verification

| Claim | Verdict | Consequence for the plan |
|---|---|---|
| `mkfs.ext4 -E lazy_itable_init=0,lazy_journal_init=0` — valid syntax, disables lazy init, meaningfully lengthens mkfs on large volumes; no conflict with `-q` | **TRUE** | Kept, with the operator "not a hang" log line (Phase 2 step 8) |
| `blkid -p` performs a live superblock probe bypassing the cache | **TRUE** | Kept |
| `blkid -c /dev/null` is equivalent to `-p` | **FALSE** | **Corrected** — `-c /dev/null` suppresses the cache *file* but still does a normal lookup. Only `-p` forces the live scan. The plan no longer offers it as an alternative |
| Bare `blkid <dev>` exits 0 on a partition-table-only device (prints `PTTYPE=`) | **TRUE** | Confirms the rejection of the git-data bare-`blkid` shape in favour of `-s TYPE -o value` |
| Freshly `luksOpen`'d unformatted mapper → `blkid -s TYPE -o value` prints empty | **TRUE** | Three-arm guard is sound |
| `findmnt -no SOURCE` returns `/dev/mapper/<name>` for an active mapper | **TRUE (common case)** | **Softened** — the `dm-N` form is not the default, so the existing `:901`/`:911` literal compares are very likely fine. Reinforces the decision **not** to retrofit them. `_same_dev` is retained for new code as cheap insurance; `MAJ:MIN` noted as a form-independent alternative |
| `cryptsetup status <name>` output contains a `device:` line; `sed -n 's/^ *device: *//p'` extracts it | **TRUE** | The mapper→device anchor (Phase 2 step 1b) is implementable as written |
| `losetup` + `cryptsetup` + `mkfs.ext4` + `mount` all work on GH-hosted `ubuntu-latest`, `/dev/loop*` available, **no privileged container needed** | **TRUE** | **Strengthens Phase 1** — the "runner privileges might block it" hedge is removed; the loopback suite is a plain `run:` step and is genuinely non-deferrable |
| LUKS2 default data offset ≈ 16 MiB | **NUANCED** | **Widened to ~16–32 MiB.** A LUKS volume sized equal to its plaintext source is strictly smaller — making the capacity gate (Phase 2 step 7) load-bearing, not precautionary |

### Institutional learnings applied

- `2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md` — the #6588
  post-mortem: 28/28 green tests missed 4 P1s and a P0 because the harness violated the rule it
  enforced. Directly motivates Phase 1's real-device evidence and the vacuity guard (AC4).
- `workflow-patterns/2026-07-19-real-cutover-routes-to-workflow-dispatch-and-failclosed-gate-must-self-report.md`
  — a fail-closed gate must emit its evidence **before** it dies. Encoded in `emit_staging_target`
  firing pre-`die` on every failure path.
- `test-failures/2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md` — `pipefail` +
  `grep -q` SIGPIPEs the producer and flips a real match to a false negative. Why the harness rule
  "never pipe into an assertion predicate" is restated in Phase 1b.
- `best-practices/2026-06-12-porting-external-ci-gate-needs-calibration-positive-control-fail-closed.md`
  — the ancestor of the G4 fd positive control; the direct model for `_same_dev` carrying its own.
- `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md` and
  `2026-07-16-a-gate-that-proves-it-cannot-fail-open-shipped-its-own-proof-unwired.md` — why AC5
  requires a non-zero executed-case count and why the loopback suite may not skip silently.
- `2026-07-15-a-guard-that-never-ran-has-more-than-one-reason-and-indexof-block-scoping-swallows-siblings.md`
  — a guard that never ran usually has more than one cause; why Phase 4 sweeps all seven
  freeze-critical sites rather than stopping at the first.

## Non-Goals

- **Do NOT** "fix" C1 as an rsync attribute/semantics problem (`--omit-dir-times`, `--no-times`, or
  relaxing the itemize count). C1 was correct. Doing so turns C1 green and drives the run into
  repointing `/mnt/data` at an unformatted mapper. Pinned by AC2.
- **Do NOT** weaken C1, G4, G3, the escrow proof, the header backup, or any existing gate. Pinned by AC1.
- **Do NOT** dispatch `workspaces-luks-cutover.yml` from this task. The real freeze is a separately
  gated, operator-approved dispatch.
- **Do NOT** close #6588 (AC11).

### Deferred, each with a tracked follow-up issue (`wg-when-deferring-a-capability-create-a`)

1. **Stray-copy deletion — separate PR, sequenced BEFORE the next real freeze.** Both simplification
   reviewers and architecture converged: it is remediation of an artifact the failed run left behind,
   not a fix for #6588 — different blast radius, different review posture, and 100% of v1's destructive
   risk. It must **not** be reachable from the ungated `dry_run=true` arm (that arm has zero human
   approval by construction; ADR-119's reversibility proof is the load-bearing premise of that
   authorization model). Preferred vehicle: a dedicated `CLEAN_STRAY=1` **mode branch** mirroring the
   existing `ROLLBACK` mode (`:59` default, `:660-663` branch, workflow input `:41` → env `:130`) so the
   destructive capability is single-purpose and reviewable on its own terms. Must name the **AP-009**
   deviation explicitly. **Re-evaluation criterion:** required before the next real freeze — this PR's
   `staging_stray_present` die blocks the cutover until it lands.
2. **`_same_dev` retrofit onto `:901`/`:911`.** **Re-evaluation criterion:** only if Phase 1's L4
   observes `findmnt -no SOURCE` returning the `dm-N` form. Until then the strict compare false-fails
   safely and must not be relaxed.
3. **Full swallowed-failure class sweep** of remaining unguarded commands outside the freeze-critical
   path. This PR fixes the target-preparation path, the class's root enabler, and all seven
   freeze-critical instances (`:670`, `:686`, `:693`, `:695`, `:892`, `:899`, `rollback()` `:577`).
   **Re-evaluation criterion:** if review surfaces a further freeze-critical site, fold it in
   (`rf-review-finding-default-fix-inline`).

> **No longer deferred:** v2 deferred the pre-freeze capacity gate. Spec-flow review established that
> this PR is precisely what makes `ENOSPC` reachable — the copy moves from the root disk (where it fit)
> into a mapper that is *strictly smaller* than the source if the volume was sized equal — and that the
> delta rsync at `:839` is **inside** the freeze. It is now Phase 2 step 7.
