---
title: "fix(git-data): probe the pre-receive fence in the cutover's read-only proof, and sequence the copy and wrapper halves of #8101 into #8211's payload batch"
date: 2026-09-21
slug: fix-git-data-cutover-fence-probe-and-mapper-assert-sequencing
branch: feat-one-shot-8101-git-data-hooks-rsync-mapper-assert
issue: 8101
type: fix
lane: single-domain
closes: none (Ref #8101 — the issue stays open, see Decision D3)
brand_survival_threshold: none
---

# git-data cutover: the fence must survive the repoint, and the wrappers must know which disk they act on

## Enhancement Summary

**Deepened on:** 2026-09-21. This follows the plan-review panel; its revisions are at the end of
the file.

**Agents:**

- security-sentinel;
- test-design-reviewer;
- observability-coverage-reviewer;
- a claims/attribution verifier. All seven claim groups confirmed: issue states, the #8189 deletion
  commit `7fb9c5b39`, the suite anchors, the bootstrap lines, git's unset-key exit 1 (git 2.55.0),
  and the rung-2 runbook heading.

The halt gates all passed: 4.6 User-Brand, 4.7 Observability (the probe verb is allowlisted), 4.8
PAT, and 4.11 Guard Contract (lint green). Gates 4.5, 4.55, 4.9 and 4.10 did not fire.

### Key improvements

1. **Test harness realism.**
   - Two more exact-count rows were enumerated: `case_capture_census` 2→3 and the AC2 `::notice`
     count 7→8.
   - F15 was rewritten so M8 actually reds it.
   - The F16 harness is now specified completely: header-inclusive awk, stubs, `set -u` globals,
     and a child bash.
   - Parity row P1 is anchored on both sides, so it cannot pass vacuously.
2. **An honest probe label.** It is `probe=fence-shape`, not `fence`. A root attacker can plant a
   `root:root 755` `exit 0` hook that passes every shape check. The content check is #8211's
   `sha256sum` AC.
3. **The deferral is enforced, not just recorded.** #8211's flag flip must refuse unless the fence
   probe passes AND all three wrappers carry the executable mapper assertion. That closes the window
   in which the flag could flip before the assertion lands.
4. Input validation on `root` and `serving` before `%q`, and a layer-6 citation on every
   `alert_route`.
5. A discoverability probe that does not depend on the network or the GitHub rate limit.

### New considerations

- M10's use-site variant is caught only by the AC2 text diff, stated alongside M7.
- `rc=16` gets its own no-SSH remedy line in the runbook.

## Overview

Issue #8101 names two gaps that must close before the git-data store serves users.

1. **The copy does not carry `hooks/`.** `core.hooksPath` points at `/mnt/git-data/hooks`. The
   plaintext store holds that directory; the LUKS store does not. A cutover that copies only
   `repositories/` and then mounts the mapper at `/mnt/git-data` leaves the fence path dangling, and
   git then runs no `pre-receive` at all.
2. **The three forced-command wrappers check that a store is mounted, not which device backs it.**

Measured on today's tree, **neither half can land as the issue wrote it.**

- **Half 1 has nothing to edit.** The copy passes and `canary_luks_device` were deleted from
  `git-data-cutover.sh` in #8189. The script is now a read-only proof, and the G2 census in its suite
  forbids `rsync` and `canary_luks_*` outright. Their rebuild is #8211.
- **Half 2 is hash-bound.** All three wrappers are in the rung-2 evidence's bound file set. The
  committed evidence is valid for the current tree today (both hashes are `a0b5f37b…`). Editing any
  of the three wrappers voids that evidence, and the documented recovery takes two PRs and a paid
  rehearsal host. In between, both the birth job and the replace job refuse.

What this PR ships:

- **The fence readback instrument, now.** A fourth read-only probe in `git-data-cutover.sh`
  (`refuse_if_fence_not_intact`). It reads the bootstrap's own ownership literals back through
  `gd_capture`, plus the system `core.hooksPath` and the source device of the hooks directory. It
  takes the root AND the expected source device as parameters, so #8211 can call it on `FRESH_ROOT` (expecting `/dev/mapper/git-data`) after the copy with no new
  instrument. This is the "canary readback" the issue asked for. It lives in the one place a
  cutover-time read exists today, and it is not hash-bound.
- **The sequencing for everything else, in writing.** The hooks copy (both passes, `-aHAX`) and
  the post-copy readback on `FRESH_ROOT` go to #8211's rebuild. So does the unconditional mapper
  assertion in the three wrappers. #8211 already names a batch of hash-bound edits to these same
  files for "the next rung-2 payload change", and this assertion joins that batch. The reasons are
  measured below and recorded on #8101, on #8211 and in the cutover runbook.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality (measured 2026-09-21) | Plan response |
|---|---|---|
| "rsync `$OLD_ROOT/hooks/ → $FRESH_ROOT/hooks/` in BOTH passes" | The script has no rsync pass. The header says the rsync/freeze/repoint/flag-flip/rollback/wipe body "was deleted (git history keeps it)". `grep -n rsync apps/web-platform/infra/git-data-cutover.sh` hits comments only. The access suite's G2 census (`case_verb_census`) refuses `rsync` and `(bulk\|delta)_rsync` in code. | The copy requirement goes to #8211 as a stated AC (comment on #8211). This PR adds a pointer in the census comment so the edit that re-admits `rsync` meets the requirement at its chokepoint. |
| "extend `canary_luks_device` with `[ -x …/pre-receive ]` + `stat -c '%U:%G %a'` readbacks, before `CANARY_OK=1`" | `canary_luks_*` is in the census's refused-name list, and `CANARY_OK` appears nowhere. | Build the readback as a standalone probe, `refuse_if_fence_not_intact <root>`. It runs in the read-only proof today and on `FRESH_ROOT` in #8211. |
| "the bootstrap uses `stat -c '%U:%G %a'` literal readbacks" | True. `git-data-bootstrap.sh` `_own()` table rows: `$HOOKS_DIR root:$GIT_USER 750`, `$PRE_RECEIVE root:root 755` (`GIT_USER="git"`). | The probe compares against the same literals. A parity row asserts the two files agree. |
| "assert `findmnt -no SOURCE "$MOUNT_ROOT"` = `/dev/mapper/git-data` in all three wrappers … This edit is hash-bound and voids the rung-2 evidence" | Confirmed. `git_data_rung2_bound_files` lists all three wrappers among its 17 paths. `git_data_rung2_user_data_sha256` = `a0b5f37b2fefcb095c1d5e4a559dfac047840db87bb087ffdab5c78d514a0517` = committed `RUNG2_TEMPLATE_SHA256`. | Deferred to #8211's payload batch. Reasons are under D2. |
| "once the cutover repoints" | Today the plaintext store is at `/mnt/git-data` and LUKS is at `/mnt/git-data-luks` (bootstrap `GIT_DATA_ROOT`, `LUKS_ROOT`). A wrapper asserting the mapper at `/mnt/git-data` would refuse every call on today's layout. | The assertion design lands in #8211 with its rollback coupling spelled out (D2, point 5). |

## Research Insights

**Premise validation (Phase 0.6).**

- #8101: OPEN.
- #8211: OPEN. It rebuilds the real modes. Its body names the cutover's copy guards and "stale
  comments in hash-bound files (edit with the next rung-2 payload change): `git-data-provision.sh`
  and `git-data-remove.sh`". It also says the freeze-sentinel contract (read by all three wrappers)
  has no writer. It does **not** mention `hooks/`. `grep -i hook` on the body hits only "webhook".
- #8093: OPEN (tracker).
- #8094: CLOSED.
- #6897, #8209, #7226, #5274: OPEN.
- #8189: CLOSED. That PR deleted the copy body.
- Last cutover dry run: 2026-09-16, `success` (run 35119099336). Last rung-2 rehearsal: 2026-09-19,
  `success` (run 35465756680), and that is the committed evidence.
- The two stale premises are in the Reconciliation table above. Every other cited artifact exists on
  `origin/main` (`b6a198add`); the worktree's infra tree does not differ from it.

**Property List (Phase 0.6b).**

- P1: after any repoint, a push to the serving store runs the root-owned `pre-receive` fence.
- P2: before the copy that P1 depends on, the fence is present and intact on the source store, with
  the exact ownership the bootstrap installs, so the copy has something correct to carry.
- P3: an erasure, provision or transport call never acts on the plaintext volume once the store is
  meant to be the LUKS mapper.
- P4: the rung-2 birth/replace interlock is not voided for no gain. A hash-bound edit lands in a
  batch that one rehearsal covers.

**Cut List (Phase 0.6b).**

- Rsync of `hooks/` in both passes → P1. Nothing to edit today (body deleted). **Carried to #8211**,
  not cut.
- `canary_luks_device` extension → P2. The function is gone. Replaced by `refuse_if_fence_not_intact`,
  which buys P2 now and serves as P1's post-copy readback later.
- Wrapper `findmnt` assertion → P3. Hash-bound (P4). **Carried to #8211's payload batch.**
- A text tripwire in the suite ("any `rsync` of `repositories/` must pair with `hooks/`") → P1.
  **Cut.** A grep guard over prose-adjacent code is satisfiable by a comment. The census already
  refuses `rsync` outright, so the #8211 PR must edit that census. A comment at that exact line is
  the cheaper pointer.
- A marker file ("cut over = yes") that makes the wrapper assertion conditional → P3. **Cut.** It
  is planted host state, the same class of thing the assertion exists to distrust (D2, point 5).

**Hash binding — what it is now (measured, not inferred).**

- `git_data_rung2_bound_files apps/web-platform/infra/cloud-init-git-data.yml` → 17 paths: the
  template, the module's `main.tf`/`outputs.tf`/`variables.tf`, `git-data-bootstrap.sh`, the gc
  and luks-reopen unit families, `git-data-pre-receive-placeholder.sh`, **`git-data-provision.sh`,
  `git-data-remove.sh`, `git-data-transport-wrapper.sh`**. Neither `git-data-cutover.sh` nor
  `git-data-pre-receive.sh` is in the set.
- The hash is over **source bytes** (`outputs.tf` comment: "a hash of the SOURCE files"), so a
  comment-only edit to a wrapper voids the evidence too, even though ADR-152 strips rationale
  comments at render.
- Enforcement points:
  - `infra-validation.yml` step "Rung-2 evidence freshness (active only once evidence exists)".
    It reds a PR that changes a bound file while evidence is committed.
  - `apply-web-platform-infra.yml` jobs `git_data_host_replace` and `git_data_host_create`. Both call
    `git_data_rung2_rehearsal_gate` and HOLD on stale evidence.
  - Guard 4 (the provenance gate) refuses evidence that lands in the same commit as a payload change.
- Documented recovery (`git-data-rung2-rehearsal.md` § "Changing the payload: the two-PR sequence"):
  1. The payload PR deletes the evidence file.
  2. Merge.
  3. Dispatch the rehearsal on `main` (a paid throwaway host).
  4. An evidence-only PR.

  "The route is interlocked in between."

**Relevant files.**

- `apps/web-platform/infra/git-data-cutover.sh`: `gd_capture`, `_store_emit`, `_store_refuse`,
  `refuse_if_unmounted`, `refuse_if_cut_over`, `refuse_if_store_not_empty`, `main`.
- `apps/web-platform/infra/git-data-cutover-access.test.sh`:
  - the `ssh` shim's `case "$c"` dispatch (`"findmnt -no SOURCE "*`, `"d="*` with an `exec` mode
    that runs the remote bytes locally)
  - `has_store`, `mutating()`, `case_verb_census`, `case_main_order`
  - AC2's expected remote timeline file
  - the runtime container arm (real sshd; `apt-get install … openssh-server openssh-client
    netcat-openbsd iproute2`, with no `git` and no `git` group)
  - `MUTANT_FLOOR=19`, `FLOOR=176` ("exact, not a margin")
- `apps/web-platform/infra/git-data-bootstrap.sh`: `HOOKS_DIR="$GIT_DATA_ROOT/hooks"`, the
  `install -o root -g root -m 0755` of the placeholder, `git config --system core.hooksPath`, and
  the `_own` readback table.
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`: § Preconditions,
  § What the read-only dispatch does, § Verdict map.

**Institutional learnings applied.**

- `knowledge-base/project/learnings/2026-07-24-guest-luks-store-must-gate-consumer-on-mount-and-guard-suite-must-pin-fail-loud-semantics.md`.
  Pin the refusal *semantics* (exit 5 plus the verdict line), not the presence of a token.
- `knowledge-base/project/learnings/2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`.
  Mutate the design, then confirm the suite reds. A positive-control deletion must also be a row.
- `knowledge-base/project/learnings/2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`.
  Every refusal arm needs a row that forces it.
- `knowledge-base/project/learnings/2026-09-07-the-guard-i-wrote-died-on-the-case-it-was-written-to-catch.md`.
  Keep `_store_refuse` a plain statement. Never call it inside `$(…)`, where its `exit 5` would
  only leave a subshell (the same hazard `access_gate`'s comment names).
- `knowledge-base/project/learnings/2026-09-20-the-ops-only-green-verdict-claimed-a-fact-the-gate-never-measured.md`.
  Give each failure mode its own rendered reason word. Do not collapse them into one message.
- `knowledge-base/project/learnings/best-practices/2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md`.
  Relevant to the parity row's anchor, discussed in the Guard Contract.

**Conventions.**

- `cq-write-failing-tests-before`: the suite rows come first.
- `hr-no-ssh-fallback-in-runbooks`: the runbook gains no SSH read.
- `cq-cite-content-anchor-not-line-number`.

**Architecture gate (Phase 2.10).** Skipped. Nothing changes a boundary, a substrate or an ADR
decision. The probe extends ADR-220's read-only proof inside its existing channel. The deferral is
sequencing inside #8211's own scope. A reader of ADR-068/ADR-220 plus the C4 model is not misled
after this ships.

**The probe's channel needs no hash-bound edit (advisor check, measured).** `gd_capture` runs over `GIT_DATA_SSH` as **root**. The root key reaches the host through `hcloud_server.git_data`'s `ssh_keys` (`git-data.tf`: `concat([hcloud_ssh_key.default.id], [for k in data.hcloud_ssh_keys.git_data_root.ssh_keys : …])`), which is root's unrestricted `authorized_keys`. The `command=` forced-command confinement applies only to the three `git`-user keys in `/home/git/.ssh/authorized_keys` (`cloud-init-git-data.yml`). So adding `stat`, `git config --system` and `findmnt -T` to the remote command touches no allowlist and no bound file. The existing store-empty probe already runs `findmnt -T` and `find` over the same channel.

**Encryption posture (Phase 2.11).** Detection does not fire. No `.tf`, migration, cloud-init or
compose file is edited. No new store or connection is introduced; the probe rides the existing
ADR-220 `GIT_DATA_SSH` channel.

**IaC gate (Phase 2.8).** Does not fire. There is no new infrastructure. `git-data-luks.tf`'s
comment "access gate plus three store probes" stays true, because the new probe is a separate
*fence* probe (D1), so that file is not touched.

## Decisions

**D1 — The fence probe is a read-only probe with its own name and its own reason words.**
`refuse_if_fence_not_intact` runs after `refuse_if_store_not_empty`. It needs `STORE_SOURCE`, which
`refuse_if_unmounted` accepted, and it is ordered last so the three existing verdicts keep their
meaning. It emits through `_store_emit`/`_store_refuse` as `probe=fence-shape`. `_store_emit` gains an
optional fourth argument, `reason`, formatted as `${4:+ reason=$4}` in the same way `_access_emit`
already renders its reason.

The signature is `refuse_if_fence_not_intact [root] [expected_source] [serving_hooks]`:

- `root` defaults to `$OLD_ROOT`;
- `expected_source` defaults to `$STORE_SOURCE`;
- `serving_hooks` defaults to `$OLD_ROOT/hooks`, the path the system `core.hooksPath` names
  (`/mnt/git-data/hooks`).

`main()` calls it with no arguments, as a plain statement (`case_main_order` matches only
`name[[:space:]]*$`). The defaults are resolved in the first lines of the body with
`${1:-…}`/`${2:-…}`/`${3:-…}`. The body reads no global after that.

**Why `serving_hooks` is separate from `root` (plan-review P0).** The system hooksPath always names
the serving path, never the copy target. So on `FRESH_ROOT` before the repoint, `$root/hooks` ≠
`core.hooksPath` by construction. #8211's post-copy call is
`refuse_if_fence_not_intact "$FRESH_ROOT" "$LUKS_MAPPER"`: the third argument defaults to the
serving path and stays correct.

It runs one remote command in one ssh session, so the source it checks is the source it reads. The
remote exit codes are disjoint from `gd_capture`'s own (95/96/97) and from transport codes
(124/141/255). The checks run in this order:

| Remote exit | Check | Local verdict |
|---|---|---|
| 10 | `$root/hooks` is absent, a symlink (dangling or not), or not a directory | `fence_not_intact reason=hooks_dir_absent` |
| 12 | `$root/hooks/pre-receive` is absent, a symlink, not a regular file, or not `-x` | `fence_not_intact reason=hook_absent` |
| 16 | `stat` itself failed, or `git config` returned >1 (127 missing binary, 128 malformed config) | `probe_failed rc=16` |
| 11 | `stat -c '%U:%G %a'` of the hooks dir ≠ `root:git 750` | `fence_not_intact reason=hooks_dir_owner` |
| 13 | `stat -c '%U:%G %a'` of `pre-receive` ≠ `root:root 755` | `fence_not_intact reason=hook_owner` |
| 14 | `git config --system --get core.hooksPath` (rc 0 or 1) ≠ `serving_hooks` | `fence_not_intact reason=hooks_path_mismatch` |
| 5 | `findmnt -no SOURCE -T "$root/hooks"` failed | `probe_failed rc=5` |
| 15 | that source ≠ `expected_source` (the hooks dir sits on another volume) | `fence_not_intact reason=hooks_wrong_source` |
| 0 | all checks pass; prints `ok` (capture pattern `^ok$`) | `ok` |
| any other | transport or instrument failure | `probe_failed rc=<n>` |

Instrument failures never render as store-state words (plan-review P2). `stat` and `git` are each
captured with their own rc. A failed read is 16, which maps to `probe_failed`, not to an ownership
or path reason. `git config` exits 1 for an unset key (a real mismatch) and ≥2 for an instrument
failure. The remote string runs without `-e`, like the store-empty probe's.

**What "intact" does NOT claim (plan-review P1).** The probe checks the fence's *shape*: a real,
root-owned, executable file, wired by hooksPath, on the expected device. It does not check its
*content*. The bootstrap installs the fail-closed placeholder (`git-data-pre-receive-placeholder.sh`),
which rejects every push, and the real fence lands by host replace. Both pass. The runbook says so.
Content identity after a copy is a separate carried AC for #8211: `sha256sum` of source and copy
`pre-receive` must be equal.

**What the probe adds over boot (plan-review).** The bootstrap already FATALs at boot on each of
these facts (`-x` check, the `_own` table, the hooksPath read). The probe's value is *post-boot
drift* detection at cutover time, plus the reusable post-copy readback on `FRESH_ROOT`.

Existence checks run before ownership checks on purpose. The unit tier runs as a non-root user and
cannot create `root:git`-owned files, so this order lets its `exec` mode reach 10, 12 and 11 against
a real temporary tree. Rows 13, 14 and 15 are reached through the runtime container arm (root) and
through canned shim answers.

The remote bytes use `[ -f ]`/`[ -x ]`/`[ -d ]`/`[ -L ]`, never `test -f`. The suite's `mutating()`
regex treats `test -f` as a sentinel-write shape. `findmnt` does not contain the census token
`mount`, so the probe stays census-clean with no edit to the census regex.

**No backtick before the function name in any comment.** `case_main_order`'s wrap check greps the
raw file, so a comment like `` `refuse_if_fence_not_intact "$FRESH_ROOT"` `` would red H5. Write the
reuse pointer as plain prose (plan-review P2).

**Exit 5 is the right class.** Before any cutover, a missing fence on the plaintext store is a
**store-state refusal**, like `store_not_empty`: the host is not in the state a cutover can start
from. It is not an access failure (exit 3).

**D2 — The wrapper half is deferred to #8211's payload batch.** This is a measured decision. Five
reasons, each checked on the tree:

1. **Cost without coverage.** The edit voids valid evidence and forces the two-PR recovery plus a
   paid rehearsal host. During that window, birth and replace refuse.
2. **The rehearsal does not test this edit.**
   `git grep -ln 'git-data-provision.sh\|git-data-remove.sh\|git-data-transport-wrapper.sh' -- .github scripts apps/web-platform/infra/rung2-rehearsal apps/web-platform/infra/*.yml apps/web-platform/infra/*.sh`,
   excluding `*.test.sh`, returns only:
   - the template, which writes them and wires the forced commands;
   - the bootstrap, which only checks that `git-data-provision.sh` is executable;
   - `git-data-gc.sh` (a comment);
   - the budget harness (renders them);
   - the three files themselves.

   So the re-rehearsal would re-attest the boot, not the assertion. The assertion's proof is the
   wrappers' own suites (`git-data-{remove,provision,transport-wrapper}.test.sh`) either way.
3. **No earlier protection.** New wrapper bytes reach the host only through a `git_data_host_replace`.
   ADR-220 D6 (and #8211's own preconditions) require a fresh replace immediately before the real
   cutover. So bytes merged today and bytes merged in #8211's batch reach production at the same
   replace. The exception is an unrelated replace in between. There, today's layout would make the
   new wrappers refuse every call (harmless while `GIT_DATA_STORE_ENABLED=false`), which is a
   behaviour change no rehearsal covered.
4. **#8211 already owns a batch of hash-bound edits to the same files.** Its "stale comments in
   hash-bound files" item covers `git-data-provision.sh` and `git-data-remove.sh`. Its
   freeze-sentinel writer contract is read by all three wrappers. One payload PR → one rehearsal →
   one evidence PR covers all of them.
5. **The assertion is coupled to the cutover's own design.** It should be **unconditional**
   (`findmnt -no SOURCE "$MOUNT_ROOT"` must equal `/dev/mapper/git-data`, or refuse). A conditional
   form ("once cut over") needs a host-side marker, and a marker is planted state, the same class of
   thing the assertion distrusts. An unconditional assertion makes the wrappers refuse on plaintext.
   #8211's rollback must therefore flip `GIT_DATA_STORE_ENABLED=false` **before** it remounts
   plaintext at `/mnt/git-data`. Otherwise rollback fails closed, with the transport refusing, rather than a
   silent plaintext serve. That is the correct direction, but it has to be designed, not discovered.
   The suites also need an expected-device seam (for example `GIT_DATA_STORE_DEVICE`, defaulting to
   `/dev/mapper/git-data`) beside `GIT_DATA_MOUNT_ROOT`, because a temp-root real mount never reports
   the mapper. The existing seams are safe for the same reason this one is: the forced command's
   sshd forwards no client environment (wrapper header comments).

**D3 — #8101 stays OPEN. This PR references it and does not close it.** Roadmap row L27 names #8101
as the legal-activation dependency ("the cutover copies `hooks/` and the wrappers assert the mapper
device"). PA-36 §(g)(4) records it "OPEN, gates the cutover (#8101)". This PR closes neither of those
two properties. Closing #8101 would make both documents claim a control that does not exist. The
work phase comments on #8101 with the split and the re-evaluation trigger (#8211's payload PR), and
comments on #8211 with the carried ACs.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. `GIT_DATA_STORE_ENABLED` is false
  and no user request reaches git-data. A broken probe either makes the operator's reviewer-gated dry
  run refuse falsely (`fence_not_intact` on a healthy host, visible in the run's annotations) or pass
  falsely. A false pass would let the cutover-preconditions read "fence intact" while it is not,
  which matters only once #8211 exists. The suite's positive and negative rows cover both
  directions.
- **If this leaks, the user's data is exposed via:** no new vector. The probe reads ownership
  metadata and one git config value over the existing ADR-220 root channel. It captures only the
  literal `ok`, never prints a captured value (`gd_capture`), and never reads repository contents.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: the diff adds a read-only probe to a reviewer-gated
dry-run script and docs; no user traffic reaches git-data while GIT_DATA_STORE_ENABLED is false, and
the user-impacting halves of #8101 are explicitly not closed by this PR (they gate the flag flip
through #8211).`

## Implementation Phases

### Phase 1 — RED: suite rows before the probe (`git-data-cutover-access.test.sh`)

1.1 Add an `ssh` shim arm for the fence command. Its remote bytes begin `h=` (Phase 2.2), so the
arm is `"h="*`. This must be the *exact* first token of the command; otherwise it falls through to
the shim's default `exit "${SHIM_REMOTE_RC:-1}"` and every row reads `probe_failed rc=1`. The
`SHIM_FENCE` modes:

- `ok`: prints `ok`
- `r10`–`r16`: exit that code
- `r5`: exit 5
- `r255`: prints the ssh timeout line and exits 255
- `line2`: prints `ok` then a second line
- `exec`: `exec bash -c "$c"` against a real temp tree, mirroring `SHIM_COUNT=exec`

Every `exec` row (F11–F14) exits at 10, 12 or 11, which is before the `git config` read. So the
developer's `/etc/gitconfig` never reaches a unit-tier result. The hooksPath check runs for real
only in the root runtime arm.

1.2 Unit rows (script tier). In every negative row the fence probe is the **only** refusal, which
proves the store probes all read `ok` first.

| Row | Input | Expect |
|---|---|---|
| F1 | `SHIM_FENCE=ok` | exit 0, `has_store fence-shape ok`, `verdict=clear` |
| F2 | `r10` | exit 5, exact line `[git-data-cutover] STORE probe=fence-shape verdict=fence_not_intact reason=hooks_dir_absent` |
| F3 | `r11` | exit 5, `reason=hooks_dir_owner` |
| F4 | `r12` | exit 5, `reason=hook_absent` |
| F5 | `r13` | exit 5, `reason=hook_owner` |
| F6 | `r14` | exit 5, `reason=hooks_path_mismatch` |
| F7 | `r15` | exit 5, `reason=hooks_wrong_source` |
| F8 | `r5` | exit 5, `probe_failed rc=5` (not `fence_not_intact`) |
| F8b | `r16` | exit 5, `probe_failed rc=16` (an instrument failure is never a store-state word) |
| F9 | `r255` | exit 5, `probe_failed rc=255` |
| F10 | `line2` | exit 5, `probe_failed rc=96`; the canary second line is absent from `$OUT` |
| F11 | `exec`, temp root with no `hooks/` | `reason=hooks_dir_absent` |
| F12 | `exec`, `hooks/` present, no `pre-receive` | `reason=hook_absent` |
| F12b | `exec`, `hooks/` + a regular **non-executable (0644)** `pre-receive` | `reason=hook_absent` (this is the row that reds M3) |
| F13 | `exec`, `hooks/` as a symlink to a real dir | `reason=hooks_dir_absent` |
| F14 | `exec`, `hooks/` + an executable `pre-receive`, both owned by the CI user | `reason=hooks_dir_owner` |
| F15 | `SHIM_FINDMNT=rc1` | exact line `[git-data-cutover] STORE probe=store-mounted verdict=old_store_unmounted rc=1` AND `! grep -q 'probe=fence-shape' "$OUT"`. This form is RED under M8: the probe runs first and emits its own `probe_failed`. It is green on today's script, the one row where 1.7's "all RED" does not apply, and that is stated. |
| F16 | the extracted function called as `refuse_if_fence_not_intact /x/fresh /dev/mapper/git-data` with `STORE_SOURCE=/dev/sdb` and the shim recording | the recorded remote command carries `h=/x/fresh/hooks`, `src=/dev/mapper/git-data` and `sp=/mnt/git-data/hooks` (the serving path, not `/x/fresh/hooks`) |

F11–F14 drive the root and source onto the temp tree with the existing `OLD_ROOT` override plus
`SHIM_FINDMNT_T`, the same pattern the `g2*` rows use.

F15 covers ordering: an earlier refusal stops the proof before the fence probe.

**F16's harness** (deepen: the naive form does not work). The script ends with an unconditional
`main "$@"` under `set -euo pipefail`, so sourcing it runs the whole proof. Do **not** add a
`BASH_SOURCE` guard. Instead:

- use a variant of `case_main_order`'s awk that prints from the `name() {` header line **through**
  the closing `}` (the existing one skips the header, so its output cannot be sourced);
- extract `gd_capture`, `_store_emit`, `_store_refuse` and `refuse_if_fence_not_intact`, and assert
  that each extraction is non-empty;
- stub `log`, `step` and `_access_stderr`. `log()`/`step()` are one-liners the block awk cannot
  extract;
- set every global the functions read under `set -u`: `CAPTURE_TMP=""`, `GD_CAPTURED=""`,
  `GIT_DATA_HOST=10.0.1.20`, `GIT_DATA_SSH="$GD_INV"`, `OLD_ROOT=/mnt/git-data` (the `sp=` default
  derives from it), `STORE_SOURCE=/dev/sdb`, plus `TL`, `TMPDIR=$T` and `PATH=$BIN:/usr/bin:/bin`
  (the `timeout` shim logs to `TL`);
- run it in a **child** `bash`, because `_store_refuse` exits 5.

1.3 Update the existing rows whose shape changes with one more remote call (plan-review P1,
enumerated against the suite):

- **AC2's expected timeline:** append the exact fence command line.
- **AC2's `timeout` string** (`timeout 30 timeout 25 timeout 30 timeout 30 timeout 30`): append
  `timeout 30`.
- **AC2's `ssh-stdin` count:** 5 → 6.
- **`case_main_order`:** add `refuse_if_fence_not_intact` as the seventh call.
- **The H5 and AC2 pass messages:** "the four probes" and "all three store probes and the fence
  probe ok".
- **Runtime R5b:** `r5.remote` gains `findmnt -no SOURCE -T /mnt/git-data/hooks` (the fixture
  `findmnt` logs every call).
- **Runtime R5c:** `r5_web_accepted` 5 → 6 and `r5_gd_accepted` 3 → 4.
- **`case_capture_census`:** `[ "$calls" = 2 ]` → `3`. `gd_capture` gains a third call site.
- **AC2 annotation row:** "exactly seven ::notice" lines → eight (`probe=fence-shape verdict=ok`).
- **Every other exact-count or exact-timeline row:** grep the suite for `accepted`, `ssh-stdin`,
  `timeout 30`, `.remote`, `= 2 ]`, `^::notice` and `seven` before editing. List any hit not named
  above in the PR.

1.4 Parity row P1, anchored so it cannot pass vacuously.

- **Bootstrap side:** extract with `^\$HOOKS_DIR root:\$GIT_USER `, `^\$PRE_RECEIVE ` and
  `^GIT_USER="[a-z]+"$`.
- **Script side:** strip comments (`sed -E 's/^[[:space:]]*#.*$//'`), then anchor on the escaped
  use-site forms `\$oh\" = \"` and `\$op\" = \"`. A bare `root:git 750` token also appears in the
  comment block, so it would stay green under M4.
- **Both sides:** require exactly one match each before comparing. Two empty extractions would
  otherwise compare equal.

1.5 Runtime container arm:

- add `git` to the `apt-get install` set, and fail closed with `FIXTURE_APT_FAILED` exactly as
  today;
- `groupadd -f git`;
- a `plant_fence` helper: `/mnt/git-data/hooks` as `root:git 0750`, `hooks/pre-receive` as
  `root:root 0755`, and `git config --system core.hooksPath /mnt/git-data/hooks`.

Call `plant_fence` wherever the setup builds `/mnt/git-data`, **including after the r5 setup's
`rm -rf /mnt/git-data`**, which would otherwise wipe it. The existing clear run then reads
`probe=fence-shape verdict=ok`. Add these rows:

- `rf2`: `git config --system --unset core.hooksPath` → `reason=hooks_path_mismatch` (the
  real-host test of git's unset-key exit 1);
- `rfsrc` (must-PASS, non-canonical): write `/dev/nvme1n1` to `/fixture/findmnt.out`. The fixture
  `findmnt` answers both the mount read and `-T` with it, so the proof clears on a source other than
  `/dev/sdb`.

Restore the entry state after each row. Update `RUNTIME_ROWS`.

1.6 Mutation rows, written against the design and each asserted RED with `mutant_red`. These are
the matrix rows of Guard 1 (below).

1.7 Run the suite. Every new row is RED against the unmodified script, the parity row included (the
probe literals do not exist yet).

### Phase 2 — GREEN: the probe (`git-data-cutover.sh`)

2.1 Extend `_store_emit` to `<probe> <verdict> [rc] [reason]`. Pass the reason through
`_store_refuse` unchanged.

2.2 Add `refuse_if_fence_not_intact` directly below `refuse_if_store_not_empty`. The comment block
maps each remote exit code, in the same form as the store-empty probe's block. The function:

- resolves `root="${1:-$OLD_ROOT}"`, `src="${2:-$STORE_SOURCE}"` and
  `serving="${3:-$OLD_ROOT/hooks}"` in its first lines, and reads no global after that;
- fails closed on a `src` that does not match `^/dev/[A-Za-z0-9/_.-]+$`, and on a `root` or `serving`
  that does not match `^/[A-Za-z0-9/_.-]+$`, with `probe_failed`. #8211 will pass `FRESH_ROOT`, so
  both inputs are validated before they are quoted (deepen, security);
- quotes each value with `printf -v … '%q'`;
- makes one `gd_capture '^ok$' "<remote>"` call.

The remote bytes. They begin `h=`, which the shim arm keys on:

```sh
h=$qh; p="$h/pre-receive"; src=$qs; sp=$qsp
[ -L "$h" ] && exit 10
[ -d "$h" ] || exit 10
[ -L "$p" ] && exit 12
[ -f "$p" ] && [ -x "$p" ] || exit 12
oh=$(stat -c '%U:%G %a' "$h") || exit 16
op=$(stat -c '%U:%G %a' "$p") || exit 16
[ "$oh" = "root:git 750" ] || exit 11
[ "$op" = "root:root 755" ] || exit 13
v=$(git config --system --get core.hooksPath); g=$?
[ "$g" -le 1 ] || exit 16
[ "$v" = "$sp" ] || exit 14
s=$(findmnt -no SOURCE -T "$h") || exit 5
[ "$s" = "$src" ] || exit 15
echo ok
```

`$qh` is the `%q` of `$root/hooks`. The lines are joined with `;`, the same way the store-empty
probe builds its command. The local `case "$rc"` maps 10–15 to the reason words and everything else
to `probe_failed`. It emits `_store_emit fence-shape ok` only on rc 0 with the captured `ok`.

2.3 Add `refuse_if_fence_not_intact` as a plain statement, with no arguments, in `main()` after
`refuse_if_store_not_empty`. Update the start and clear log lines: "access gate, three store
probes, then the fence probe" and "…, empty, fence installed and wired".

2.4 Update the header comment: § "WHAT THIS SCRIPT DOES TODAY" gains item 3 (the fence probe, shape
not content) and "Exit 0 means" gains "fence installed and wired". § "WHAT IT NO LONGER DOES" gains
one sentence, as plain prose with no backticked call: the rebuilt copy must carry hooks in both
passes and re-run the fence probe against the fresh root, expecting the mapper, before any flag
flip (#8101, carried by #8211).

2.5 Add one comment line above `case_verb_census`'s refused list in the suite: re-admitting rsync
here is the #8211 rebuild, and the copy must also carry hooks (#8101).

2.6 Recount and set `MUTANT_FLOOR` and `FLOOR` to the exact new totals, with the per-section
arithmetic rewritten in the comment above each. Both are "exact, not a margin".

### Phase 3 — Docs and issue carry-over

The **#8211 body section is the one full copy** of the carried work. Everything else links to it
(plan-review P2: the deferral was written down four times).

3.1 Runbook `git-data-luks-cutover-5274.md`:

- § What the read-only dispatch does, step 7: add the fence probe and its verdicts. State that it
  checks the fence's shape (installed, root-owned, wired, on the store device) and not which hook is
  installed.
- "Exit 0 means": add "and the pre-receive fence is installed and wired on the store it will copy
  from".
- § Verdict map: add one row, `verdict=fence_not_intact reason=<word>` (exit 5), with the six words
  on one line each. Treat it as **post-boot drift on a root-owned path**: the bootstrap FATALs at
  boot on each of these facts. Remedy: `git-data-host-replace`, which re-runs the bootstrap. Add
  `probe_failed rc=5|16` for the fence probe (an instrument could not answer). The rc=16 remedy
  line: re-dispatch once; if it repeats, dispatch `git-data-host-replace`. An instrument failing on
  a bootstrapped host is itself drift. There is no SSH step.
- § Preconditions: rewrite the #8101 bullet as **one line**: "#8101 — fence readback landed; the
  hooks copy, post-copy readback and wrapper mapper assertion are carried in #8211 (see its
  'Carried from #8101' section)".

3.2 Edit #8211's body **additively**: append a `## Carried from #8101 (acceptance criteria)`
section of `- [ ]` checkboxes and rewrite none of the existing text. Hold the replaced body in a
`mktemp` file and apply it with `gh issue edit 8211 --body-file`. Then re-read the body and assert
the section is present exactly once. The section opens with D2's five reasons, one line each. The
checkboxes, each with its implementation pointer:

- rsync `$OLD_ROOT/hooks/` → `$FRESH_ROOT/hooks/` in the bulk and delta passes, `-aHAX`.
- After the delta pass, before the repoint: the fence probe on `FRESH_ROOT` expecting
  `$LUKS_MAPPER`. The third argument stays at its default (the serving path the system hooksPath
  names).
- After the copy: the `sha256sum` of `$OLD_ROOT/hooks/pre-receive` equals that of
  `$FRESH_ROOT/hooks/pre-receive`. The probe checks shape, not content.
- After the repoint, as the **last** step before the flip: the flag-flip step **refuses** unless (a)
  the fence probe passes on `/mnt/git-data` with the mapper expected, and (b) all three wrappers
  carry the executable `findmnt -no SOURCE` / `/dev/mapper/git-data` assertion. (b) is checked on
  comment-stripped code, never on a comment (deepen, security).
- The unconditional wrapper mapper assertion, plus the `GIT_DATA_STORE_DEVICE` test seam, in the
  same payload PR as the batch's other wrapper edits.
- Rollback flips `GIT_DATA_STORE_ENABLED=false` **before** it remounts plaintext.
- The census edit that re-admits rsync keeps the hooks pointer.
- The payload PR that lands the wrapper assertion says `Closes #8101`, provided the copy items above
  have also landed.

There is no separate #8211 comment.

3.3 `gh issue comment 8101`: a link to #8211's section, the words "blocked by #8211", and
"Re-evaluate when: #8211's payload PR opens". State that the issue stays open as the L27/PA-36
named dependency.

## Files to Edit

- `apps/web-platform/infra/git-data-cutover.sh`
- `apps/web-platform/infra/git-data-cutover-access.test.sh`
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
- Added by the review round (stale descriptions of the proof): `.github/workflows/git-data-cutover.yml`
  (header comment only), `ADR-220` (a dated amendment), `model.c4` and the regenerated
  `model.likec4.json`. None is in the rung-2 bound set.

## Files to Create

- None. The spec dir `knowledge-base/project/specs/feat-one-shot-8101-git-data-hooks-rsync-mapper-assert/`
  gets `tasks.md` (this skill), plus `session-state.md` if the pipeline writes one.

## Non-Goals

These are explicitly **not** done here, and none is hash-bound-safe or in scope:

- no edit to `git-data-remove.sh`, `git-data-provision.sh` or `git-data-transport-wrapper.sh`;
- no edit to `git-data-bootstrap.sh`, `cloud-init-git-data.yml`, `modules/git-data-userdata/*` or
  `git-data-rung2-boot-evidence.env`;
- no edit to `git-data-luks.tf`;
- no edit to `knowledge-base/legal/article-30-register.md`. PA-36 §(g)(4) still reads true;
- no roadmap edit (L27 still reads true).

Tracking for the deferred work is #8211 (existing) plus #8101 (stays open). No new issue is needed.

## Open Code-Review Overlap

None. The check ran on 2026-09-21 against `gh issue list --label code-review --state open`
(200 limit), using every path in Files to Edit plus the three wrappers. There were zero matches.

## Guard Contract

### Guard 1 — the fence probe (`refuse_if_fence_not_intact`)

**Property.** The read-only proof exits 0 only if, on the store device it accepted, the hooks
directory is a real `root:git 750` directory holding a real, executable, `root:root 755`
`pre-receive`, and the system `core.hooksPath` names that directory. Any other state exits 5 with
either a named reason or `probe_failed`, never 0.

**Assembly.**

- *Chokepoint 1*: `main()`, the only caller. The proof's exit-0 path is `main()` falling through to
  the `verdict=clear` notice.
- *Chokepoint 2*: `gd_capture`, the only remote-read path. It carries the bounds, the anchoring and
  the no-print property.
- *Chokepoint 3*: `_store_emit`/`_store_refuse`, the only verdict emitters.
- *Members*: the six remote facts listed in D1, all checked inside ONE remote command, plus the
  local rc→verdict map.
- A later reuse against `FRESH_ROOT` (#8211) is a second call site of the same function. The
  function takes the root, the expected source and the serving hooks path as parameters, so the
  chokepoint stays one function. F16 calls it with an explicit root and source that differ from the
  globals. It asserts the remote command carries both, and that the hooksPath expectation stays the
  serving path.

**Mutation matrix.** Written before the probe. Each row is a `mutate` + `mutant_red` pair.

| # | Edit (design-derived) | Must go RED on |
|---|---|---|
| M1 | Delete the `refuse_if_fence_not_intact` statement from `main()` (**own dispatch**) | `case_main_order` and the AC2 timeline diff |
| M2 | Replace the `gd_capture` call with `GD_CAPTURED=ok` (the probe "passes" without reading) | the AC2 timeline diff, and F2–F7 |
| M3 | Drop the `-x` test on `pre-receive` while the directory check stays (**second member after a compliant first**) | F12b (a 0644 hook now reaches the ownership check and exits 11) |
| M4 | Change `root:git 750` to `root:git 770` in the probe | parity row P1, and the runtime clear run |
| M5 | Map the 10–15 range to `ok` (swallow the refusal) | F2–F7 |
| M7 | Delete the `findmnt -T` source comparison | the AC2 timeline text diff only. The canned `r15` row never runs the remote bytes, so it cannot see this. Stated here so no one counts F7 as coverage. |
| M8 | **REORDER**: move the call before `refuse_if_unmounted` | `case_main_order`, and F15 (the probe must not run after a mount refusal) |
| M10 | Derive `sp=` from `$root/hooks` instead of `serving` (the plan-review P0, as a mutation) | F16 (`sp=` no longer the serving path). A use-site edit (`[ "$v" = "$h" ]`) is caught only by the AC2 timeline text diff. No row tests it behaviourally, because in `main()` the root always equals the serving path. |
| M11 | Map remote 16 to a `fence_not_intact` reason (an instrument failure rendered as store state) | F8b |

M6 and M9 were cut in plan review. The exact `reason=` assertions in F2–F7 already red a collapsed
reason map, and `case_main_order`'s wrap check already reds an `|| true` wrap.

**Harness rows.**

- H-a: make the shim's fence arm always print `ok`, ignoring `SHIM_FENCE`. F2–F10 go RED, which
  proves the negative rows are driven by the shim mode and not by the script's text.
- **Must-PASS, non-canonical:** runtime `rfsrc`, a consistent source `/dev/nvme1n1` on a real
  root-owned tree, clears. The contract permits any consistent `/dev/` source.
- **Must-PASS:** the runtime clear run on a real host-shaped tree. This is not a canned answer.

H-b was cut in plan review: F1 also asserts exit 0, so it could not isolate `has_store`.

**Anchor.** The literals `root:git 750` and `root:root 755` are stored values, compared with the
bootstrap's `_own` table by P1. One diff *can* edit both files. But `git-data-bootstrap.sh` is in
the rung-2 bound set, so any edit to it reds the "Rung-2 evidence freshness" step in
`infra-validation.yml`, and it HOLDs birth and replace until a fresh rehearsal lands. That forces a fresh rehearsal plus a separate evidence PR under Guard 4. The outside anchor
that must move is the rehearsal evidence. A weakening that edits only `git-data-cutover.sh` fails
P1 outright.

**Exit-site table** (the script never writes, so this is by position relative to the first
*refusal*, not the first write). Every exit before the probe is an existing exit (3 or 5). The
probe's only exits are `_store_refuse` (exit 5) and fall-through. There is no `die` inside it: an
`mktemp` failure inside `gd_capture` returns 95, which becomes `probe_failed rc=95`.

## Observability

```yaml
liveness_signal:
  what: "the git-data-cutover.yml run's annotations — '::notice title=git-data-cutover store::probe=fence-shape verdict=ok' on success, '::error title=git-data-cutover store::probe=fence-shape verdict=fence_not_intact reason=<word>' or 'verdict=probe_failed rc=<n>' on refusal, plus the same line in GITHUB_STEP_SUMMARY"
  cadence: "per reviewer-gated dispatch of git-data-cutover.yml (runbook post-merge step 5, and before any real cutover)"
  alert_target: "the dispatching operator: a refusal fails the job (exit 5), and GitHub notifies the dispatcher of a failed run"
  configured_in: "apps/web-platform/infra/git-data-cutover.sh (_store_emit) and .github/workflows/git-data-cutover.yml (the job's step)"
error_reporting:
  destination: "GitHub Actions check-run annotations and the job summary on the git-data-cutover.yml run"
  fail_loud: true
failure_modes:
  - mode: "fence directory or hook absent, replaced by a symlink, or not executable on the source store"
    detection: "remote exit 10/12 read in-surface on git-data by the probe's single ssh command; rendered as reason=hooks_dir_absent|hook_absent"
    alert_route: "layer 6 (workflow run log, ::error:: annotation) on the dispatcher's failed run"
  - mode: "fence ownership or mode drifted from the bootstrap's literals"
    detection: "remote exit 11/13 via stat -c '%U:%G %a' on git-data; reason=hooks_dir_owner|hook_owner"
    alert_route: "layer 6 (workflow run log, ::error:: annotation) on the failed run"
  - mode: "system core.hooksPath unset or repointed"
    detection: "remote exit 14 via git config --system on git-data; reason=hooks_path_mismatch"
    alert_route: "layer 6 (workflow run log, ::error:: annotation) on the failed run"
  - mode: "hooks directory lives on a different volume than the accepted store"
    detection: "remote exit 15 via findmnt -no SOURCE -T compared to the mount probe's accepted source; reason=hooks_wrong_source"
    alert_route: "layer 6 (workflow run log, ::error:: annotation) on the failed run"
  - mode: "an instrument on the host failed (stat error, git missing or config unreadable)"
    detection: "remote exit 16 (the failing instrument is named only in the run log's probe-stderr lines, not by the rc); rendered probe_failed rc=16, never a store-state reason"
    alert_route: "layer 6 (workflow run log, ::error:: annotation) on the failed run"
  - mode: "the read could not be completed (transport, timeout, oversized or multi-line answer, findmnt failure)"
    detection: "gd_capture rc (95/96/97/124/141/255) or remote exit 5; rendered probe_failed rc=<n>, never a store-state verdict"
    alert_route: "layer 6 (workflow run log, ::error:: annotation) on the failed run"
logs:
  where: "the git-data-cutover.yml run log and its check-run annotations (GitHub Actions)"
  retention: "GitHub Actions default log retention for the repository (90 days)"
discoverability_test:
  command: "grep -o -m1 '_store_emit fence-shape ok' apps/web-platform/infra/git-data-cutover.sh"
  expected_output: "_store_emit fence-shape ok"
```

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1. `bash apps/web-platform/infra/git-data-cutover-access.test.sh` exits 0. Its final ledger
  line shows `0 failed`. `MUTANT_FLOOR` and `FLOOR` equal the recounted exact totals, and the comment
  above each shows per-section arithmetic that sums to the value.
- [x] AC2. Each of F2–F7 asserts the exact line
  `[git-data-cutover] STORE probe=fence-shape verdict=fence_not_intact reason=<word>` with exit 5. F8–F10
  assert `probe_failed`. Implementation: the rc→reason `case` in
  `git-data-cutover.sh:refuse_if_fence_not_intact`.
- [x] AC3. AC2's expected timeline ends with exactly one fence command line, after the count line.
  Its `timeout` string and `ssh-stdin` count grow by one. Runtime R5b and R5c are updated to the
  counts that include the one extra read. `case_main_order` expects seven calls in the stated order.
- [x] AC4. Parity row P1 passes. The probe literals equal the bootstrap `_own` rows for `$HOOKS_DIR`
  and `$PRE_RECEIVE`, with `$GIT_USER` resolved.
- [ ] AC5 (unit + mutation rows verified locally; the runtime arm needs docker, run by infra-validation in CI). Mutation rows M1–M5, M7, M8, M10 and M11 each report RED. Harness row H-a reports RED.
  The runtime clear run and `rfsrc` pass. If the runtime arm cannot reach its fixture, it reports
  the existing `_runtime_skip` and never a silent pass.
- [x] AC6. The G2 census still passes unchanged in its regex. This proves the probe added no
  refused verb. It runs `case_verb_census` on the real script.
- [x] AC7. `git diff --name-only origin/main...HEAD` lists no file in the rung-2 bound set.
  Check: `bash -c 'source tests/scripts/lib/git-data-birth-readiness-gate.sh; git_data_rung2_bound_files apps/web-platform/infra/cloud-init-git-data.yml'`
  has an empty intersection with the diff. Also, `git_data_rung2_user_data_sha256` still prints
  `a0b5f37b2fefcb095c1d5e4a559dfac047840db87bb087ffdab5c78d514a0517`.
- [x] AC8. The diff is a subset of Files to Edit, plus this plan, plus
  `knowledge-base/project/specs/feat-one-shot-8101-git-data-hooks-rsync-mapper-assert/*`, plus any
  pipeline-generated `knowledge-base/INDEX.md` update.
- [x] AC9. The runbook's § Verdict map contains a `fence_not_intact` row naming all six reason words,
  and § Preconditions' #8101 bullet names #8211 and the rung-2 two-PR section.
  `lint-infra-no-human-steps.py --changed --base origin/main` passes.
- [ ] AC10. The PR body says `Ref #8101` and does not say `Closes #8101`.
- [x] AC11. #8211's body carries the `Carried from #8101` checkbox section, and #8101 has a comment
  carrying D2's five reasons. Check: `gh issue view 8211 --json body --jq .body | grep -c 'Carried from #8101'` = 1
  and `gh issue view 8211 --json body --jq .body | grep -c 'FRESH_ROOT'` ≥ 1.

### Post-merge

None required by this PR. The next reviewer-gated `git-data-cutover.yml` dry run (runbook
§ Post-merge order step 5, an existing step) reads `probe=fence-shape verdict=ok` against the live host.
That run needs explicit per-step authorization and is not a new step this PR adds.

## Domain Review

**Domains relevant:** none

This is an infrastructure/tooling change: a read-only probe and a written sequencing decision
inside one reviewer-gated script. The legal dependency this issue carries (roadmap L27, PA-36
§(g)(4)) is unchanged. #8101 stays open, and the text of both documents stays true (checked by
reading `knowledge-base/legal/article-30-register.md` PA-36 §(g)(4) and
`knowledge-base/product/roadmap.md` row L27). No UI surface is touched.

## Test Scenarios

Covered by Phase 1: F1–F16 (with F8b and F12b), the P1 parity row, runtime `rf2`, `rfsrc` and the
clear run, mutation rows M1–M5, M7, M8, M10 and M11, and harness row H-a.

## Sharp Edges

- **The first live dry run after merge may refuse.** It is the first time the probe reads the real
  host, and a host whose hooks drifted after boot reads `fence_not_intact`. That is the probe
  working: the remedy is the runbook's host replace, not a probe change. A pre-merge read of
  production over the root channel is **not** part of this plan. It needs its own per-step
  authorization (`hr-menu-option-ack-not-prod-write-auth`), and the dry run is already the
  sanctioned reader.
- **"Intact" means shape, not content.** The fail-closed placeholder hook passes the probe. Never
  cite a green fence probe as "the real fence is installed". The content check is #8211's
  `sha256sum` AC.
- A plan whose `## User-Brand Impact` section is empty, holds only placeholder text, or omits the
  threshold fails `deepen-plan` Phase 4.6. It is filled here.
- **Do not "fix" a wrapper in passing.** Any byte change to `git-data-remove.sh`,
  `git-data-provision.sh`, `git-data-transport-wrapper.sh`, `git-data-bootstrap.sh` or
  `cloud-init-git-data.yml` voids the rung-2 evidence. That includes a comment, and it includes the
  stale "git-data-cutover.sh plants …" comments #8211 lists. It reds the freshness step, and in
  practice it re-holds birth and replace. AC7 is the guard.
- `mutating()` in the suite treats `test -f` as a sentinel-write shape. Write the remote bytes with
  `[ ]`.
- `FLOOR` is exact. Removing or adding a row without recounting reds the suite on purpose.
- The runtime arm installs packages in a container. If `git` is not installable there, the arm
  must fail closed (`FIXTURE_APT_FAILED`) rather than skip the fence rows silently.
- `git config --system core.hooksPath` exits 1 when the key is unset. The probe compares the
  string, so under `set -e` in the remote the substitution must not abort first. The remote runs
  as a plain `sh -c`/bash string without `-e`, the same as the store-empty probe. Verify that
  against the runtime arm, not by reading.

## Plan Review Revisions (2026-09-21)

The panel was DHH, Kieran, code-simplicity, the CTO (devex lens) and a scoped advisor consult. All
applied findings are Mechanical.

- **P0 (Kieran, simplicity):** the hooksPath check compared against `$root/hooks`, so the #8211
  reuse on `FRESH_ROOT` could never pass. It now takes a third parameter, `serving_hooks`
  (default `$OLD_ROOT/hooks`), and has F16 and M10.
- **P1 (Kieran):** the shim arm keyed `h=` while the bytes began `r=`. The bytes now begin `h=`.
  The rows that change with one extra remote call (AC2 timeout string and ssh-stdin count, R5b,
  R5c, the r5 `rm -rf`) are enumerated. F12b (a 0644 hook) now carries M3. M7 is stated as caught
  only by the timeline diff. F16 uses awk-extracted functions, not sourcing. The must-PASS
  non-canonical row moved to the runtime arm (`rfsrc`).
- **P1 (DHH):** "intact" claimed more than it measured. The probe checks shape, not content, and
  that is stated. A `sha256sum` content AC is carried to #8211.
- **P2 (Kieran):** instrument failures (stat, git ≥2) now exit 16 → `probe_failed`.
  `hooks_path_unset` became `hooks_path_mismatch`. Comments carry no backticked call, which would
  trip H5.
- **Cuts (DHH + simplicity, both panels):** M6, M9, H-b and `rf1`.
- **Doc duplication (DHH):** #8211's body section is the one full copy, and the runbook and #8101
  link to it.
- **CTO:** the flag-flip refusal and the `Closes #8101` coupling are now #8211 checkboxes. A
  first-live-run refusal is recorded as a Sharp Edge.

**Declined, with reasons:**

- DHH's cut of the second and third parameters. Both the advisor and the P0 show they are
  load-bearing for the one planned reuse.
- DHH's collapse to three reason words. Simplicity kept all six, since they map one-to-one to the
  runbook lines.
- DHH's cut of F11–F14. The exec tier runs even where the runtime arm cannot reach docker.
- The CTO's pre-merge production read. It needs its own authorization, and the dry run is the
  sanctioned reader.
