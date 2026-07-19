# Tasks — fix(infra): mkfs the LUKS mapper + fail-close the staging mount

**Plan:** `knowledge-base/project/plans/2026-07-19-fix-workspaces-luks-mkfs-staging-mount-guard-plan.md`
**Issue:** #6588 (stays OPEN — `Ref`, not `Closes`)
**Lane:** cross-domain (spec absent → fail-closed default)
**Brand-survival threshold:** single-user incident

> **Phase order is load-bearing.** Phase 1 is RED on **real devices** — write L5 (mkfs suppressed)
> first and watch it fail before writing any fix. The stubbed harness proves branching; branching is
> not what failed.

---

## Phase 1 — RED: loopback validation on real devices

- [ ] 1.1 Create `apps/web-platform/infra/workspaces-luks-loopback.test.sh`: `truncate` a backing
      file, `losetup`, real `cryptsetup luksFormat` + `luksOpen`, fixture data, teardown trap.
- [ ] 1.2 **Write L5 first** — mkfs suppressed → assert the mount fails (`staging_mount_failed`), and
      with the mount forced, the positive control catches `source_not_mapper`. **Must fail before the
      fix exists.** This reproduces the 2026-07-19 incident on a real device.
- [ ] 1.3 L1 — fresh device: real mkfs runs, mount succeeds, `findmnt` reports the mapper, `result=ok`.
- [ ] 1.4 L2 — re-run against the same prepared device: no mkfs, idempotent mount, `reused=1` with a
      `reused_bytes=` value.
- [ ] 1.5 L3 — full path: prepare → `rsync` fixture data → `verify_byte_identity` → 0 diffs.
- [ ] 1.6 L4 — **record which form `findmnt -no SOURCE` actually returns on the runner.** This is the
      evidence that decides the deferred `:901`/`:911` retrofit. Write the observation into the plan.
- [ ] 1.7 Suite must **fail loud, never skip**: exit non-zero with `LOOPBACK_UNAVAILABLE` when
      `losetup`/`cryptsetup` are unavailable; report a non-zero executed-case count.

### Phase 1b — stubbed-harness prerequisites (verified blockers)

- [ ] 1b.1 **Decide and record** where `run_case` lives: extract to a shared
      `workspaces-luks-harness.sh` sourced by both files, or put the new cases in
      `workspaces-luks-freeze.test.sh`. (`workspaces-luks.test.sh` has **zero** `run_case` refs.)
- [ ] 1b.2 Add `WORKSPACES_STAGING="$d/staging"` to `run_case` — it currently leaves `STAGING` at
      `/mnt/data-luks`, so every case would `mkdir` against the real runner and `EACCES`.
- [ ] 1b.3 Replace the single-rc `mountpoint` stub with a **sequenced** one (e.g. `MOUNTPOINT_RCS`
      consumed by call index) — the new function calls it repeatedly needing different answers.
- [ ] 1b.4 Add `readlink` and `mkdir` to the stub list.
- [ ] 1b.5 Keep the harness rule: **never pipe into an assertion predicate** (pipefail SIGPIPE makes
      negative assertions fail open).

---

## Phase 2 — GREEN: `prepare_staging_target()`

Define **above the sourced-detection guard at `:652`** (convention: `:351`, `:608`).

- [ ] 2.1 Define `emit_staging_target()` above `:652` alongside `emit_drift` — column-0 `echo` **plus**
      `logger -t "$LUKS_LOG_TAG"` (`:336-338` shape). **v1/v2 called it without defining it**; a 127
      is swallowed under no `-e`, so the marker would silently never emit.
- [ ] 2.2 Initialize `STAGING_FS_REUSED=0` before the `if`; use `${VAR:-0}` for optional env reads.
      Declare `fs_type`, `staging_src`, `mapper_dev` as `local`. Do **not** touch `KEY`/`FRESH_DEV`/
      `raw_type` (they stay top-level; the function replaces only `:695-696`).
- [ ] 2.3 `mkdir -p "$STAGING" || { emit_drift staging_mkdir_failed; die …; }`
- [ ] 2.4 **Mapper preconditions:** `[ -b "$MAPPER" ]` → `staging_mapper_absent`; then anchor
      mapper → device via `cryptsetup status "$MAPPER_NAME"` + `_same_dev … "$FRESH_DEV"` →
      `staging_mapper_wrong_device`. **Closes the invariant's recursion.**
- [ ] 2.5 **Stray guard — detect and REFUSE, never delete:** non-mountpoint + non-empty →
      `staging_stray_present` + die. Runs in **both** arms (read-only assert).
- [ ] 2.6 **Refuse re-run after success:** `$MOUNT` already resolving to `$MAPPER` →
      `staging_already_cutover` + die. Prevents mounting the mapper twice and rsyncing into itself.
- [ ] 2.7 DRY_RUN short-circuit (`:573`/`:614` idiom) → `result=dryrun` marker, `return 0`.
- [ ] 2.8 **mkfs guard**, three arms mirroring `:683-691`, using `blkid -p -s TYPE -o value` (the
      `-p` low-level probe bypasses the `/run/blkid/blkid.tab` cache — a stale TYPE is wrong in both
      the destructive and the refusing direction):
      - empty → `log` the "may take minutes, not a hang" line, then
        `mkfs.ext4 -q -E lazy_itable_init=0,lazy_journal_init=0` → `staging_mkfs_failed` on failure
      - `ext4` → no-op, `STAGING_FS_REUSED=1`
      - anything else → `staging_unexpected_fs` + die **(the arm that stops a re-run wiping a good copy)**
- [ ] 2.9 **Fail-closed mount** — explicit `if/then`, never `A || B || C` (`:788-789` lesson).
- [ ] 2.10 Define `_same_dev()` **with its own positive control**: explicit `|| return 1` on each
      `readlink`, non-empty checks, and `[ -b "$b" ]`. The naive form **fails open** when `readlink`
      errors (both substitutions empty → `"" = ""` true).
- [ ] 2.11 **Positive control:** `findmnt -no SOURCE "$STAGING"` vs `$MAPPER` via `_same_dev` →
      `source_not_mapper` + die. **The primary regression guard.**
- [ ] 2.12 **Capacity gate** (post-mount, pre-freeze): `du --apparent-size -sb "$MOUNT"/workspaces` vs
      `df --output=avail -B1 "$STAGING"`, with a non-numeric guard mirroring `:867`. →
      `staging_insufficient_capacity` / `staging_capacity_unreadable`.
- [ ] 2.13 Emit `result=ok` marker: `fs=`, `reused=`, `reused_bytes=`, `source=`, `mapper=`, `avail_b=`.
- [ ] 2.14 **Every prepare-time die message must state**: no freeze was held, no rollback is needed,
      do NOT run `ROLLBACK=1` (which would `umount "$MOUNT"` on the live plaintext volume).

---

## Phase 3 — wire the call site

- [ ] 3.1 Replace `:695-696` with `prepare_staging_target`. Top-level call ordering otherwise unchanged.

---

## Phase 4 — strictly-additive sibling fail-closures

All are fail-open → fail-closed; none can make a currently-**correct** run fail.

- [ ] 4.1 `:670` — `[ -b "$(findmnt -no SOURCE "$MOUNT")" ] || log WARN` → `|| die`. (The source of
      every byte, anchored only as a warning — the plan's own invariant, violated.)
- [ ] 4.2 `:686` — guard `cryptsetup luksFormat` → `luksformat_failed`.
- [ ] 4.3 `:693` — guard `cryptsetup luksOpen` → `luksopen_failed`. (Unguarded today; a failed open
      makes the new code die as `staging_mkfs_failed` — a misleading reason.)
- [ ] 4.4 `:892` — `umount "$STAGING" 2>/dev/null || true` → `|| { emit_drift staging_umount_failed;
      die …; }`. **Highest severity:** a failed umount leaves the mapper double-mounted, `:901` still
      passes, and `rollback()` swallows the EBUSY and reports success — leaving plaintext live at
      `$MOUNT` **and** a divergent copy at `$STAGING`, with no telemetry.
- [ ] 4.5 `:899` — guard `mount "$MAPPER" "$MOUNT"` → `repoint_mount_failed`. **Do not reorder
      `FLIP_DONE`** — guarding is the smaller diff. Note: ordering is *not* safety-critical
      (`FREEZE_HELD=1` at `:808` already satisfies `cleanup()`'s disjunction at `:602`, and the
      persisted copy has no in-script reader).
- [ ] 4.6 `rollback()` `:577` — add `umount "$STAGING" 2>/dev/null || true` **before**
      `cryptsetup close`, and stop swallowing the close's error. Currently the mapper leaks open +
      mounted through the recovery path.

---

## Phase 5 — ADR-119 amendment

- [ ] 5.1 §(g): add the **mapper** arm (existing state machine covers only the *device*) — after
      `luksOpen` the mapper is an empty container and `mkfs.ext4` lays the FS **inside** it.
- [ ] 5.2 Correct the Reversibility proof's description of `prepare_luks_target` (currently omits both
      the `mkfs` and the staging mount); record the staging positive control.
- [ ] 5.3 **Do NOT** amend the 2026-07-18 authorization addendum — v3 removes the deletion, so its
      reversibility premise stands untouched.

---

## Phase 6 — CI wiring + structural dispatch gate

- [ ] 6.1 Add an explicit `run: bash apps/web-platform/infra/workspaces-luks-loopback.test.sh` line to
      `.github/workflows/infra-validation.yml`. **Suites are invoked by explicit `run:` lines
      (`:382`, `:387`, `:616`, `:619`) — there is no glob, so an unwired suite is an orphan that
      never runs.**
- [ ] 6.2 Add the structural dispatch gate to `.github/workflows/workspaces-luks-cutover.yml`:
      hard-fail `dry_run=false` absent loopback-validation evidence. **The gate must live on the
      irreversible arm** — a hard gate enforced only by PR prose is the procedural-gate class this
      plan exists to eliminate.
- [ ] 6.3 `actionlint` both edited workflows (workflows, not composite actions — actionlint is correct).

---

## Phase 7 — verification

- [ ] 7.1 `bash -n apps/web-platform/infra/workspaces-cutover.sh`
- [ ] 7.2 Run the stubbed suite and the loopback suite — 0 failures, non-zero executed-case count.
- [ ] 7.3 **AC1 regression pin, anchored by CONTENT not line number**
      (`cq-cite-content-anchor-not-line-number` — inserting the function shifts every later line):
      extract `verify_byte_identity` / `emit_verify_diff` / `assert_mount_quiesced` /
      `emit_freeze_holders` bodies from `origin/main` and `HEAD` via `sed -n '/^fn()/,/^}/p'` and
      `diff`; `grep -F` the two exact rsync invocation strings.
- [ ] 7.4 AC2 anti-goal pin: `! grep -rq 'omit-dir-times' apps/web-platform/infra/` exits 0.
      (**Not** `grep -rc … == 0` — that emits per-file counts and false-fails.)
- [ ] 7.5 AC8: `git diff origin/main` introduces **zero** `rm`/`rm -rf`/`dd`, and no `mkfs` outside the
      guarded empty arm.
- [ ] 7.6 Vacuity guard: deleting `prepare_staging_target` from a scratch copy makes every stubbed case
      report `HARNESS_UNDEFINED`, not pass.

---

## Phase 8 — ship

- [ ] 8.1 PR body: `Ref #6588` (**never** `Closes` — ops-remediation carve-out; #6588 stays open until
      the volume is encrypted **and** verified live).
- [ ] 8.2 PR body states honestly: (a) **a green dry run does not validate this fix** — the
      freeze/copy/verify path is entirely behind the `DRY_RUN` gate (the workflow's own `dry_run` input
      description already says so); (b) because this mount failure predates the freeze-quiesce work
      merged 2026-07-19, **no cutover attempt has ever written to the LUKS volume** — the earlier
      inngest-redis AOF diagnosis was real but was not the only defect.
- [ ] 8.3 File the deferred follow-up issues with re-evaluation criteria:
      1. **Stray-copy deletion** — separate PR, sequenced **before** the next real freeze; a dedicated
         `CLEAN_STRAY=1` mode mirroring `ROLLBACK` (`:59`/`:660-663`/workflow `:41`→`:130`); must **not**
         be reachable from the ungated `dry_run=true` arm; must name the **AP-009** deviation.
      2. **`_same_dev` retrofit onto `:901`/`:911`** — only if Phase 1's L4 observes the `dm-N` form.
      3. **Full swallowed-failure class sweep** outside the freeze-critical path.
- [ ] 8.4 **Do NOT dispatch `workspaces-luks-cutover.yml`.** The real freeze is a separately gated,
      operator-approved dispatch.
