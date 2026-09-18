# fix(git-data): reopen /dev/mapper/git-data on every boot, proven by a rung-2 reset arm

`Ref #8210` — deliberately not `Closes`. The fix reaches no live host at merge: it ships inert
and is delivered by PM4's guarded replace, so the issue is closed by a follow-through probe once
the reboot evidence really lands on `main`. `Ref #8010`, `Ref #8211`.

## The defect

The git-data host opened its LUKS mapper exactly once in its life. `cryptsetup luksOpen` runs
inside cloud-init's `runcmd:` stage, and cloud-init runs `runcmd` **once per instance**; the
fstab line that stage appends carries `nofail`. So on any later boot the mount job waited for a
mapper nothing opened, timed out, and the boot continued with the encrypted store absent **and
no signal emitted** — the host answering on :22 the whole time, which is what every reachability
probe checks. ADR-115 already recorded this as a normative blocker.

No live impact today: the host is born but `GIT_DATA_STORE_ENABLED` gates every write path. This
is the window to land a payload change, which is why it is a precondition of the first real
cutover (#7226, #8209, #8211).

## What ships

One script, one unit, one reporter, two env lines, one runcmd arm, one measured boolean, one
rehearsal reset arm, two ADR amendments, one C4 edge.

- **`git-data-luks-reopen.sh`** — straight-line, no traps, never formats, never calls `mount(8)`.
  Phases: `config → key → device → header → open → identity → target → mount → identity-mount`,
  each written to a phase file *before* it runs so the tag names the phase that was executing
  when the script died, including on SIGTERM.
- **`git-data-luks-reopen.service`** — the `git-data-gc.service` shape under
  `doppler run --only-secrets … --no-fallback` with a templated `--config`, bounded
  `Restart=on-failure`, and `RuntimeDirectoryPreserve=yes`.
- **`git-data-luks-reopen-failure.service`** — `OnFailure=` reporter. One fatal per failure,
  carrying `action=<phase>` plus the unit's own `Result`/`ExecMainStatus`/`ExecMainCode`/
  `NRestarts`, with a `timeout 90` that keeps the direct arm reachable when Doppler *hangs*.
- **Routing** — `luks_reopen` and `gitdata_luks_reopen_arm` join the fatal rule;
  `gitdata_luks_reopen_arm_warn` joins the warning rule; **`luks_reopen_ok` is in NO rule**,
  because the fatal router has no `level` condition and an `info` row on a routed stage would
  page on every healthy reboot.
- **`boot_complete` gains `luks_reopen_unit`** — MEASURED (`systemctl is-enabled` AND
  `Result=success`) and TERMINAL, swept into both readers, both SQL projections, the birth
  runbook, the emitter follow-through and the apply workflow's disclosure prose.
- **The rung-2 reset arm** — settle, hard reset by exact server name, then a `--reboot-since`
  probe reading both channels server-side-bounded. The upload gates on both rcs.
- **`git_data_host_replace` joins the rung-2 interlock** — only the create job called it, so an
  un-rehearsed payload could reach the live host by replace from any ref.

## Measured, not assumed (Phase 0)

| Claim | Measurement |
|---|---|
| `luksOpen` is per-instance | It is under `runcmd:`; `bootcmd:` holds only the Sentry beacon; no crypttab; fstab is `nofail` |
| A `mount(8)` inside the unit is invisible to PID 1 | systemd 255 container, shared root: inside `tmpfs`, outside `NONE`. A PID-1 mount propagates back in |
| `RuntimeDirectoryPreserve=yes` is mandatory | Without it systemd removes the dir at the final failed state, **before** `OnFailure=` runs — the reporter would read nothing |
| `Restart=on-failure` is legal on a oneshot | Verified on 255 and 261; `Result`/`ExecMainStatus`/`ExecMainCode`/`NRestarts` all survive `start-limit-hit` |
| Doppler CLI 3.75.3 (pinned, not the host's 3.76.5) | Repeated `--only-secrets`, `--no-fallback`, `--config` all parse; child exit codes forward (measured 7) |
| `cryptsetup isLuks` rc table | 0 LUKS / 1 not-LUKS / 4 absent. `findmnt --fstab` exits 1 on no match |
| Budget | 15,444 → 17,840 B of a 32,768 cap |

## Deviation from the plan

**AC17** expects the follow-through probe to exit 1 against today's `main`; it exits **2
(TRANSIENT)**. The repo's three-state convention makes "the rehearsal has not run yet" transient,
and a 1 would post a daily false alarm from merge+1d until the operator schedules PM1 — about a
state the plan itself calls the intended safe one. Recorded in `decision-challenges.md` (T4).

## Defects found in this PR's own work, fixed at the cause

1. **`RUNDIR` seam unguarded** — every write derives from it, so an empty value resolved
   `"$RUNDIR/action"` to `/action`: a root-filesystem write, as root, on the host holding every
   user's source. Now validated and `${VAR:?}`-guarded at each use (both needed: the P1b scanner
   reads `readonly` as a re-binding). Measured: `/`, a relative path, `/run/../etc` and
   `/proc/self` each refused by name; the production default still proceeds.
2. **Deferral ledger 47 → 48** — closed by **promotion**, as the gate's own message prescribes,
   not by raising the ratchet.
3. **Inline `assert_fixture_dir` drifted** from the canonical definition by one message string.
4. **The Sentry warn-emit arm checked only the FIRST `$${STAGE}_warn` emit** — blind to a second
   by construction. Generalised to all, mutation-verified.
5. **The capture's FAIL alternation gained a name with no fixture driving it** — a guard nobody
   had seen fire. Now 107/0 → 2 failed when the name is removed.

## Pre-existing failures, confirmed not mine

23 suites fail on this box independently of this branch: 5 script suites (`scratch-root`,
`guardrails`, both `notice-frontmatter`, `lint-legal-scope-block-placement`) and 18 web-platform
component files (happy-dom 20.8.9 not providing `localStorage`). Each was confirmed by
reproduction in a **sibling worktree on an unrelated branch**, or by this diff provably not
touching the files — it changes **zero** files under `apps/web-platform` outside `infra/`.

## Post-merge (all `gh`-driven)

- **PM1** dispatch the rehearsal from `main` (dry-run, then real); the environment approval is the
  one human gate, granted via `gh api … pending_deployments`.
- **PM2** commit the evidence ALONE in an evidence-only PR (Guard 4).
- **PM3** the follow-through closes #8210 once PM2 lands.
- **PM4** `git-data-host-replace` — the replace route is HELD until PM2, which is the intended
  safe state. Record as an #8211 prerequisite with contract clauses (a)–(h).
- **PM5** file the follow-on for `--only-secrets … --no-fallback` on the two untouched
  `doppler run` sites and `--retry 2` on the emitter's Better Stack POST.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
