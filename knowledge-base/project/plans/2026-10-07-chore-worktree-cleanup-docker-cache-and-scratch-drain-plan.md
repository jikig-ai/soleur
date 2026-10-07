---
title: "chore(worktree): prune Docker images/build cache and /var/tmp scratch when a worktree is cleaned up"
type: chore
date: 2026-10-07
slug: worktree-cleanup-docker-cache-and-scratch-drain
branch: feat-docker-var-tmp-worktree-cleanup
issue: 9677
closes: 9677
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore(worktree): Docker builder cache and /var/tmp scratch drain on session-start cleanup (#9677)

## Overview

`worktree-manager.sh cleanup-merged` runs at every session start, on the operator's workstation and on every customer machine that has the Soleur plugin. It already sweeps owner-marked scratch (`sweep_orphan_scratch_dirs`, ADR-250), but disk is still not coming back. Measured on 2026-10-07 the cause is mechanical, not a missing feature:

1. The sweep's 10 s timebox is shorter than its own one-time liveness-map build (12.7 s here), so after the first declared-owner candidate every other candidate is `deferred`.
2. Marker-only dirs on a disk base are only **quarantined**; the TTL drain that deletes them runs only from a systemd timer that is not installed on this host (no crontab, no `tmpfs-guard.timer`).
3. 44 of the 71 marked dirs are a count leak from one test suite whose sourced library calls `mktemp -t gdboot.*` outside any owned scratch root.
4. When space *is* freed, btrfs snapshots can pin it, so "reclaimed N GB" overstates what `df` shows.

Brainstorm decisions (user-confirmed): opt-in builder-cache-only Docker prune; session-start quarantine drain; producer cleanup; install the existing `tmpfs-guard.timer` on the operator host; `df`-delta + snapper note. Deferred: worktree-stamped markers (#9693), report-only listing of unmarked dirs (#9694). Brainstorm: `knowledge-base/project/brainstorms/2026-10-07-worktree-cleanup-docker-and-scratch-brainstorm.md`. Spec: `knowledge-base/project/specs/feat-docker-var-tmp-worktree-cleanup/spec.md`.

## Research Insights

**Premise validation (Phase 0.6).** Cited refs checked on 2026-10-07: #9677, #9693, #9694, #7004, #8786 all OPEN; PR #9690 open draft. Every cited file exists on `origin/main` (`worktree-manager.sh`, `tmp-classify.sh`, `scratch-root.sh`, `git-data-boot-signal-poll.sh`, `tmpfs-guard.{sh,service,timer}`, `soleur-tmp-purge.sh`, `test-scratch-session.sh`). ADR corpus grep for the mechanism found ADR-250 (governs; this plan amends it) and ADR-133/195 (heuristic reclamation over a shared base rejected, report-not-reap for unattributable orphans). No cited blocker was stale.

**Property List (Phase 0.6b).**

- P1. A session start on a host with dead-owner scratch eventually frees it, with bounded dwell, without any installed timer.
- P2. Docker loses nothing the user did not opt into; the opt-in path touches only old builder cache and dangling images.
- P3. The user can see logical bytes freed beside the measured `df` delta and why they can differ.
- P4. Leaking marker producers do not create unreclaimable dirs.
- P5. Nothing leaves the user's machine.

**Cut List (Phase 0.6b).** Label-scoped prune (no `docker build` call site stamps a worktree label; only the CI inngest-bootstrap build passes any `--label`). Global `image prune -a` above a disk threshold (daemon is shared; Supabase/test images). Per-worktree scratch stamping (#9693). Unmarked-dir report (#9694; ADR-250/195 already settle report-not-reap). `snapper list` detection (needs root; a read-only file check is enough). Edits steering agents to `soleur-sandbox.sh` (a placement-gate matter for AGENTS rules, not this PR).

**Measurements (this host, 2026-10-07).**

| Fact | Value | Command |
|---|---|---|
| Liveness-map build | 12.7 s wall (739 procs, 3,933 `/var/tmp` + 2,795 `/tmp` entries) vs `SOLEUR_SWEEP_TIMEBOX_S` default 10 | `time tc_build_inuse_map /tmp /var/tmp` |
| One candidate decided WITHOUT the map | > 100 s (killed by `timeout 100`) | `time tc_reap_decide /var/tmp/gdboot.* 1440` |
| Full purge dry-run over `/var/tmp` | 77.8 s, 3,892 entries | `soleur-tmp-purge.sh --dry-run` with `SOLEUR_PURGE_BASES=/var/tmp` |
| Marked dirs | 71 (66 dead owner, 5 live); 68 modified < 24 h ago (the age gate); `gdboot.*` 44, `soleur-run.*` 12, `soleur-inc-*` 10, `soleur-sbx.*` 4 | `find /var/tmp -maxdepth 2 -name .soleur-owned`, pid via `kill -0` |
| `gdboot.*` | 44 dirs, all 2026-10-06, ~8 KB each; created by `tests/scripts/test-git-data-boot-signal-poll.sh` (sets `TMPDIR=/var/tmp`, cleans only its own `gdbootpoll.*` sandbox) | `git grep git_data_boot_poll` |
| Quarantine | 142 MB, 21,549 nested entries (2,103 + 19,446) across `soleur-quarantine.{0,1000}` | `find <q> -mindepth 1 \| wc -l` |
| Triggers | no `crontab`; only `omarchy-session-save.timer` in user timers | `systemctl --user list-timers` |
| Docker | 17 images (317 MB reclaimable), build cache ~0, 12 of 15 containers running | `docker system df` |

Note: the agent-reported "3,984 quarantine entries" and "191 `docker build` lines" did not reproduce and are not used.

**Root-cause summary for the PR body (acceptance criterion).** Survivors are (a) held by the 24 h age gate (68 of 71 today, by design), (b) deferred because the timebox expires during the map build (the structural bug), and (c) after quarantine, never deleted because the drain has no trigger. `tmpfs-guard-install.md` already says the timer install is manual.

**Local `docker build` call sites** (for a future label step, not this PR): `plugins/soleur/skills/deploy/scripts/deploy.sh:15`, `apps/web-platform/infra/cloud-init-plugin-seed.test.sh:50`, `apps/web-platform/scripts/sandbox-canary-regression.test.sh:166`.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality | Plan response |
|---|---|---|
| Issue: 128 marked dirs with dead owners (522 MB) | 66 dead of 71 today; operator cleaned up since | Cite both numbers; the mechanism, not the count, is the finding |
| Issue: "`sweep_orphan_scratch_dirs` ... is the 10 s time box ... hit?" (unanswered) | Yes: map build 12.7 s > 10 s | Rebase the deadline after the map build (Phase 2) |
| Issue: Docker prune scoped by `--label soleur.worktree=<name>` | No local build stamps it | Cut; builder-cache-only opt-in with `until=24h` (Phase 4) |
| Spec FR3: "producers use the allocator or EXIT cleanup" | `git-data-boot-signal-poll.sh` is a SOURCED lib (ADR-129: it cannot own a trap) and runs in CI on ephemeral runners; the host leak is its TEST | Fix the test (per-run owned scratch root), leave the lib alone (Phase 5) |
| Brainstorm: "install the timer" | Shipped unit assumes checkout `~/soleur`; this host's checkout is elsewhere | Systemd drop-in override per runbook (Phase 7) |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Docker pruning as part of worktree cleanup" [issue #9677] | Phase 4 (builder cache + dangling, opt-in, dry-run default) | mapped |
| 2 | "a root-cause investigation, and fix, of why `/var/tmp` is not cleaned up with the worktree" [issue #9677] | Phase 1 measurement table, Phase 2 (deadline rebase, session-start drain), Phase 5 | mapped |
| 3 | "Report effective space, not just logical" [issue #9677] | Phase 3 (`SOLEUR_CLEANUP_SPACE` + `space-report`) | mapped |
| 4 | "Builder cache only, opt-in (Recommended)" [brainstorm answer] | Phase 4 | mapped |
| 5 | "3 and 4" [brainstorm answer: producer fix + session-start drain, plus timer on the operator host] | Phases 2, 5, 7 | mapped |
| 6 | "Core + df report, defer 3 and 4 (Recommended)" [brainstorm answer] | Worktree stamping and unmarked report out of scope | descoped — justification: user chose it; tracked as #9693 and #9694 |
| 7 | "Docker volumes and running containers are never touched; absent `docker` is a clean skip." [issue AC] | Phase 4 tests T4, T5 | mapped |
| 8 | "The root cause of the 128 surviving marked directories is named in the PR with a measurement." [issue AC] | Research Insights table, PR body | mapped |
| 9 | "snapshots are never deleted" [issue AC] | Phase 3 (read-only file check), test T9 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit `worktree-manager.sh` (deadline rebase, drain, docker, space report) | asks 1–3, 5 | asked |
| Edit `tmp-classify.sh` (`tc_drain_quarantine` deadline arg + bytes) | "3 and 4" | asked |
| Edit `test-git-data-boot-signal-poll.sh` | "3 and 4" | asked |
| Create `tests/scripts/test-cleanup-merged-space.sh` + register in `scripts/test-all.sh` | "tested with a fake `docker` shim and a fixture `/var/tmp`" [issue AC] | asked |
| Extend `tests/scripts/test-scratch-session.sh` | asks 2, 5 | asked |
| Amend ADR-250; edit `model.c4` plugin description | — | inferred — justification: Phase 2.10 makes the ADR amendment and the C4 sentence for a new user-machine delete surface deliverables of this plan |
| Edit runbook `tmpfs-guard-install.md`, `git-worktree/SKILL.md` | — | inferred — justification: the runbook states the drain needs the timer, which this change falsifies; SKILL.md documents the new env vars |
| `space-report` subcommand | — | inferred — justification: Phase 2.9 requires a local, SSH-free, under-15 s `discoverability_test`; the same helper serves item 3 |
| `SOLEUR_QUARANTINE_DRAIN=1` opt-in gate | "Opt-in: SOLEUR_QUARANTINE_DRAIN=1 (Recommended)" [plan-review answer] | asked |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur`, `tests`, `knowledge-base`
- Planned files: 11 | Estimated changed lines: ~420
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

1 open scope-out touches `worktree-manager.sh`: #8496 ("cleanup-merged never gh-queries [gone] branches that have no worktree"). **Acknowledge:** different concern (branch-merge evidence in the reap loop, not scratch or Docker); it stays open. No overlap on the other files.

## Problem Statement / Motivation

Merged-worktree cleanup leaves disk behind: undrained quarantine and leaked scratch in `/var/tmp`, Docker build cache, and the freed space is often pinned by btrfs snapshots. The operator's root filesystem sat at 85% and the only remedy was a manual hunt.

## Proposed Solution

Fix the existing mechanism instead of adding new ones: make the sweep able to finish, give the drain a trigger that needs no install, stop one producer leaking, add one opt-in Docker step, and report honestly what freed.

## Technical Approach

### Architecture

All plugin-side work lives in `worktree-manager.sh` (the session-start entry) plus the shared classifier `tmp-classify.sh`. Everything reuses ADR-250 primitives: `tc_drain_quarantine`, `tc_ledger_append`, the `flock` on `~/.local/state/soleur/tmp-guard.lock`, the stdout-only `SOLEUR_*` marker convention. No new egress; all output stays in the user's session (Privacy Policy line 65, CLO assessment).

### Implementation Phases

#### Phase 1: RED tests first (cq-write-failing-tests-before)

Write the failing scenarios before any code (see Test Scenarios). Fixtures are synthesized in a per-test temp tree; `docker`, `findmnt` and `df` are PATH shims; the snapper config path is an env seam (`SOLEUR_SNAPPER_CONFIG_DIR`). Follow the inline-invocation pattern at `tests/scripts/test-scratch-session.sh` (the sweep cases near lines 361 and 392). New file `tests/scripts/test-cleanup-merged-space.sh`, registered in `scripts/test-all.sh` next to `tests/scripts/scratch-session` (line 4804 pattern).

#### Phase 2: Sweep fixes in `worktree-manager.sh` + `tmp-classify.sh`

1. **Rebase the deadline after the map build.** In `sweep_orphan_scratch_dirs`, inside the `map_tried == 0` block right after `tc_build_inuse_map $bases`, set `deadline=$(( $(now_s) + ${SOLEUR_SWEEP_TIMEBOX_S:-10} ))`. The map is a fixed cost already paid today (it is lazy: a host with no declared-owner candidate pays nothing); the timebox must bound per-candidate work. Emit `map_s=` (whole seconds: `now_s` is `EPOCHSECONDS`, 1 s resolution) in the summary line. The worktree arm shares the variable, so a timebox that still expires after the rebase must keep deferring (regression test T1b). `tc_inuse_map_refresh` rebuilds the map when older than `TC_INUSE_TTL_S` (120 s); with the rebased deadline a decision sequence cannot outlive that TTL, and a failing/empty map falls back to the per-candidate walk (fail-closed, slow) — covered by T12.
2. **Drain at session start, inside the `tmp-guard.lock` window.** The drain runs after the candidate loop and BEFORE `exec {sweep_fd}>&-` (so it is serialized against `tmpfs-guard.sh` and `soleur-tmp-purge.sh`). It does not run on the early-return paths (`lock-contended`, `flock-missing`, `bases-empty`, classifier missing); those already print `SOLEUR_TMP_SWEEP skipped reason=…`. TTLs come from `SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN` / `SOLEUR_SWEEP_QUAR_WT_TTL_MIN` (defaults 10080 / 43200), each floored at 1440 so an exported `SOLEUR_PURGE_QUAR_*=0` recovery seam can never make session start drain everything. Add an optional trailing argument to `tc_drain_quarantine`: an **absolute epoch deadline** checked between top-level entries, plus an entry cap (`SOLEUR_SWEEP_DRAIN_MAX_ENTRIES`, default 200). One very large entry can still overrun the bound (a `find -delete` cannot be interrupted); it stays in place if cut short and is retried next session, because the ledger row is written only after a completed delete. `tc_drain_quarantine` resets `TC_DRAINED` on every call, so the sweep **sums per base** into its own counters; bytes come from `du -sk` × 1024 taken before the delete (portable; accumulate with `x=$((x + n))`, never `(( x += n ))` under `set -e`). **Opt-in:** the drain runs only when `SOLEUR_QUARANTINE_DRAIN=1` (exactly `"1"`), decision D1 (user, plan review). Without it the sweep behaves as today on every customer machine; the existing "holds entries — run … --drain or install the timer" note prints whenever quarantine holds entries and the drain did not run (disabled or bounded out). On the operator host the installed timer (Phase 7) already drains every 5 minutes and does not need the variable; the variable is for hosts that cannot or do not install a timer.
3. **Summary line:** `SOLEUR_TMP_SWEEP bases=[…] reaped=… quarantined=… retained=… deferred=… drained=<n> drained_bytes=<n> map_s=<n> wt_scanned=… ms=…` — a superset of today's, so existing greps keep matching.
4. **Call-site safety.** `cleanup_merged_worktrees` is invoked bare under `set -euo pipefail`; the sweep is already called `|| headless_or_stderr warn …`. Every new call (drain is inside the sweep; Docker; space report) is guarded the same way, and `timeout` is captured with `rc=0; cmd || rc=$?` so rc 124 becomes `reason=timeout` instead of aborting maintenance.

#### Phase 3: Effective-space report

**Placement (set -e and early returns).** Rename the current body to an inner function and make `cleanup_merged_worktrees` a thin wrapper: `space_begin; inner || rc=$?; docker_builder_prune || warn; report_cleanup_space || warn; return ${rc:-0}`. The inner function keeps its single `RETURN` trap (`release_lock cleanup-merged`, ADR-129 single slot) and all its early returns (lock contended, fetch failure); the wrapper runs after the lock is released, so a slow Docker call never holds the cleanup-merged lock that siblings give up on after 5 s. The inner function exports the removal count (the `cleaned` array at `worktree-manager.sh` ~L3595/L3894) through one global, which gates Docker.

`report_cleanup_space` is also exposed as `worktree-manager.sh space-report` (read-only: current `df`, fstype, snapshot hint, Docker opt-in state; no baseline, so `logical_bytes` and `df_delta_bytes` print `-`). Portable `df -Pk "$path"` (macOS + Linux; no GNU `--output`) where `path` is the first scratch base, `/var/tmp` by default — the filesystem the drain frees. The delta is signed (`$(( after - before ))`, a negative value prints as is: concurrent sessions and Docker also write). Line: `SOLEUR_CLEANUP_SPACE logical_bytes=<n> df_delta_bytes=<n> fstype=<fs|unknown> docker_prune=<off|dry-run|apply> snapshots=<snapper|none|unknown>`. `logical_bytes` = drained bytes (`du -sk` × 1024) only; Docker's own reclaimed text is printed verbatim on the Docker line, never parsed (no unit parser). `fstype` via `findmnt -no FSTYPE <path>` when present, else `unknown`. `snapshots=snapper` only when fstype is `btrfs` and `/etc/snapper/configs/root` (or `$SOLEUR_SNAPPER_CONFIG_DIR/root`) exists; then one hint line: "freed space can stay pinned by snapper snapshots until they rotate; Soleur never deletes snapshots." No `snapper` binary call, no root. Limits stated in SKILL.md: a differently named snapper config, Timeshift, or a `/var/tmp` outside a snapshotted subvolume reads `snapshots=none`.

#### Phase 4: Docker builder cache, opt-in

`docker_builder_prune` in `worktree-manager.sh`, called by the wrapper (Phase 3) once per `cleanup-merged` run, after the cleanup lock is released, and only when `SOLEUR_DOCKER_PRUNE` is `1` (dry-run) or `apply`; any other non-empty value prints `SOLEUR_DOCKER_PRUNE skipped reason=invalid-value` and does nothing. Gated on at least one worktree removed in this run (the exported removal count); with the opt-in set and nothing removed it prints `skipped reason=no-worktree-removed`, so opt-in is never silent. Commands: `docker builder prune -f --filter until=24h` and `docker image prune -f --filter until=24h` (dangling only — "builder cache plus dangling images", the option the user picked; the `until` filter protects a sibling session's active build on the shared daemon). Never `-a`, never `container`, never `volume`, never `system prune`. Guards: `command -v docker`; the existing `timeout`/`gtimeout` fallback at `worktree-manager.sh` ~L190–195 (without either, `skipped reason=no-timeout`, never a misleading `daemon-unreachable`); reachability probe `timeout 5 docker info`; each prune wrapped in `timeout 60`; rc 124 captured with `rc=0; … || rc=$?`. Markers: `SOLEUR_DOCKER_PRUNE mode=<dry-run|apply> reclaimed="<docker's own text>"` or `SOLEUR_DOCKER_PRUNE skipped reason=<docker-missing|no-timeout|daemon-unreachable|timeout|no-worktree-removed|invalid-value>`. `builder prune` ends `Total:  <size>` while `image prune` prints `Total reclaimed space: <size>`; both lines are echoed verbatim. Dry-run reads `docker system df`, which ignores `until=24h`, so it is labelled an upper bound. `timeout 60` kills the client, not the daemon-side prune: the marker says `reason=timeout`, nothing more. `SOLEUR_DOCKER_PRUNE` is set in the user's shell profile or session env; documented in SKILL.md.

#### Phase 5: Producer cleanup

`tests/scripts/test-git-data-boot-signal-poll.sh` defaults `TMPDIR` to `/var/tmp` (line 21), creates `SANDBOX` with `mktemp -d -t gdbootpoll.XXXXXXXX` (line 43) and removes only it via `trap 'rm -rf "$SANDBOX"' EXIT` (line 44). The library's `mktemp -d -t gdboot.*` honours `TMPDIR`, so one line fixes the leak: `export TMPDIR="$SANDBOX"` immediately after the trap is installed. The existing trap then removes the library's dirs too, on success and on failure. No scratch-root sourcing, no trap change, no marker-schema change, so the four-writer sweep is not needed (the marker-format change is #9693). The library is unchanged (a sourced lib cannot own a trap, ADR-129) and `scripts/lint-trap-tempfile-ownership.highwater` needs no change. Verify by running the suite twice and counting `/var/tmp/gdboot.*` before and after (0 new), including a forced-failure run (T13).

#### Phase 6: Docs and architecture

ADR-250 amendment, `model.c4` plugin description sentence, runbook and SKILL.md updates (see Architecture Decision and Files to Edit).

#### Phase 7: Operator host timer (agent-run, after merge, not plugin code)

The agent runs the runbook's Option 1 with the checkout path override (`systemctl --user edit tmpfs-guard.service` drop-in: `WorkingDirectory=` and `ExecStart=` at the main checkout `/data/git-repositories/jikig-ai/soleur`), then `systemctl --user daemon-reload && systemctl --user enable --now tmpfs-guard.timer`, and verifies `systemctl --user list-timers tmpfs-guard.timer`. This is the operator's own workstation, not infrastructure in the `hr-all-infrastructure-provisioning-servers` sense; the unit files are already repo-versioned. The drop-in's checkout-path override is host-specific, so the runbook (`tmpfs-guard-install.md`) gains a short "checkout not at `~/soleur`" paragraph with the exact drop-in text rather than leaving it only in the PR body. Recorded in the PR body as a post-merge verification the agent performs. The timer stays worthwhile after the session-start drain: it adds the 5-minute cadence and the `/tmp` Reapers 1–2 that session start does not run.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Timer-only drain (status quo) | Not installed on this host; every customer install would need the same manual step |
| Raise `SOLEUR_SWEEP_TIMEBOX_S` default | Map cost scales with process count; rebasing the deadline is structural, a bigger constant is a guess |
| Detached background drain | Output lost from the session, holds the `flock` past the session |
| Label-scoped Docker prune | No local build stamps a label; builds a mechanism for a path that does not exist |
| Global `docker image prune -a` on a disk threshold | Shared daemon; CTO/CPO flagged highest blast radius |

## User-Brand Impact

- **If this lands broken, the user experiences:** the session-start cleanup deletes quarantined scratch (or, with the opt-in set, Docker cache/images) the user still wanted, silently and unrecoverably after the 7-day TTL; or session start stalls for tens of seconds.
- **If this leaks, the user's workflow is exposed via:** new stdout `SOLEUR_*` lines carrying paths and byte counts; they stay in the local session and are never sent anywhere (Privacy Policy line 65).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the script runs on every installed machine and a terminal delete there is unrecoverable for one user, so one affected user is enough; `aggregate pattern` would under-weigh a single lost directory.

CPO sign-off: **SIGN-OFF WITH CONDITIONS** at plan review (2026-10-07): (1) the drain defaults OFF on non-operator machines — applied (D1: opt-in), (2) split per D2 or state in the PR that the deadline rebase widens quarantine scope — the user chose a single PR, so the PR body carries the statement, (3) consistent defaults in this plan — applied. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

Layer 7 per `hr-observability-layer-citation` (plugin code on a customer's self-hosted CLI; stdout markers in the user's session, no egress by CLO constraint).

```yaml
liveness_signal:
  what: SOLEUR_TMP_SWEEP summary line (now with drained=, drained_bytes=, map_s=) and SOLEUR_CLEANUP_SPACE line printed on every cleanup-merged run
  cadence: per session start (every cleanup-merged invocation)
  alert_target: the user's own session output; the disposition ledger ~/.local/state/soleur/tmp-purge-ledger.log records each move and drain
  configured_in: plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh (sweep_orphan_scratch_dirs, report_cleanup_space, docker_builder_prune)

error_reporting:
  destination: stdout markers plus stderr via headless_or_stderr in worktree-manager.sh; ledger file for terminal deletes; no Sentry (plugin does not phone home)
  fail_loud: SOLEUR_TMP_SWEEP skipped reason=..., LEDGER-DROP, SOLEUR_DOCKER_PRUNE skipped reason=..., deferred=<n> with the SWEEP-DEFER line

failure_modes:
  - mode: sweep truncated by its timebox (candidates deferred)
    detection: deferred=<n> and map_s=<n> in the SOLEUR_TMP_SWEEP line plus the SWEEP-DEFER line (layer 7, stdout)
    alert_route: visible in the session; test T1 asserts deferred=0 when the map build exceeds the timebox
  - mode: quarantine drain deletes less than expected or fails
    detection: drained=<n> drained_bytes=<n> in the sweep line; ledger rows with action drain (layer 7, ledger)
    alert_route: visible in the session; test T2/T3
  - mode: Docker prune unavailable or slow
    detection: SOLEUR_DOCKER_PRUNE skipped reason=docker-missing|no-timeout|daemon-unreachable|timeout|no-worktree-removed|invalid-value (layer 7, stdout)
    alert_route: visible in the session; test T4/T5
  - mode: effective space differs from logical (snapshot pinning)
    detection: SOLEUR_CLEANUP_SPACE df_delta_bytes vs logical_bytes plus snapshots=snapper (layer 7, stdout)
    alert_route: visible in the session; test T8/T9

logs:
  where: session stdout/stderr; ledger ~/.local/state/soleur/tmp-purge-ledger.log
  retention: session lifetime for stdout; the ledger persists until the user removes it

discoverability_test:
  command: bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh space-report
  expected_output: SOLEUR_CLEANUP_SPACE
```

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-250** (Amendment 2) (`knowledge-base/engineering/architecture/decisions/ADR-250-ownership-keyed-scratch-reclamation.md`) via `soleur:architecture`: the amendment must qualify three existing statements, not just add one: the `### Trigger` line that timer installation is "deliberately manual" (still true as the default; session-start drain is now an explicit opt-in alternative needing no timer), the A1 Consequences line "session sweep unchanged" (true by default; changed only under `SOLEUR_QUARANTINE_DRAIN=1`), and the A1 note that weaker-evidence marker moves are drained only by the timer's unattended drain (also by the opt-in session-start drain). D1 (opt-in) is recorded in the ADR as the consent model. It also records: the timebox excludes the one-time liveness-map build; the drain runs inside the `tmp-guard.lock` window; TTL floors; and a **Docker carve-out in the style of A1.3's durable-log GC** — an age-filtered prune over a shared daemon is the heuristic ADR-250 rejects for ownership, so it is admitted only as a regenerable-cache, opt-in, `until=24h` exception. `## Alternatives Considered` gains the rows from this plan (timer-only, bigger constant, detached drain). A new ADR is not warranted: no new boundary, but the trigger and consent model move, so the amendment says so explicitly.

### C4 views

Read all three model files (`model.c4`, `views.c4`, `spec.c4`). Enumeration: (a) external human actor: the installed user/operator, already modeled as `founder` with the plugin "executing on an installed user's machine"; (b) external system: the local Docker daemon is the user's own runtime, not a boundary element (the model's only Docker edge is the prod `hetzner -> claude`); (c) data store: `/var/tmp` scratch and quarantine are local filesystem state, none modeled, consistent with `scratch-root.sh`/`emit-decision.sh`; (d) access relationships: unchanged. **One edit is required:** `model.c4` line 152 (the `plugin` system description) already enumerates every user-machine write surface (ADR-178, ADR-254, ADR-264, ADR-268) and this change adds a user-machine **terminal delete** and an opt-in daemon prune, so it gains one sentence in the same style. No element, edge or view-include changes. After the edit run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`, `plugins/soleur/test/c4-count-parity.test.sh` (green before the edit: "ALL TESTS PASSED"), and let the `c4-model-regenerate` pre-commit hook re-render `model.likec4.json` on commit (diagrams README, step 2), then confirm the JSON is in the staged set.

### Sequencing

The ADR describes the target state; it ships in this PR, not a follow-up.

## Infrastructure (IaC)

Not applicable to Terraform: no cloud resource, vendor account or secret is introduced. The only host-level step (Phase 7) is a user-level systemd timer on the operator's own workstation using repo-versioned unit files, installed by the agent and verified with `systemctl --user list-timers`.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from the brainstorm; CPO + CLO + CTO ran at framing time)

### Engineering

**Status:** reviewed
**Assessment:** Label-scoping infeasible; builder-cache-only is the safe Docker slice; items 2 and 4 are one mechanism (scratch with no drain). Amend ADR-250. Marker-schema change deferred (#9693).

### Product

**Status:** reviewed
**Assessment:** Default-off for non-operator users, dry-run first; defer the unmarked report; keep root-cause measurement and the `df` delta. Product/UX Gate: no UI surface, tier NONE.

### Legal

**Status:** reviewed
**Assessment:** Nothing material; no `soleur:gdpr-gate`. Constraint carried into the design: markers stay local, Soleur-owned scope only, snapshots read-only.

**Brainstorm-recommended specialists:** none named.

## Acceptance Criteria

### Pre-merge (PR)

#### Functional Requirements

- [x] With the liveness-map build exceeding `SOLEUR_SWEEP_TIMEBOX_S`, the sweep still processes every declared-owner candidate it would have processed with a fast map (`deferred=0` in the fixture).
- [x] The sweep drains quarantine entries past their class TTL (scratch 7 d, worktrees 30 d, each floored at 1440 min), inside the `tmp-guard.lock` window, bounded by an absolute deadline and an entry cap, and prints `drained=<n> drained_bytes=<n>` summed across bases; entries younger than TTL are untouched; without `SOLEUR_QUARANTINE_DRAIN=1` the sweep drains nothing (today's behavior); the drain does not run on the `lock-contended` / `flock-missing` / `bases-empty` early returns.
- [x] With `SOLEUR_DOCKER_PRUNE` unset nothing Docker-related runs and nothing prints; `=1` is a dry-run (labelled an upper bound); `=apply` calls only `docker builder prune -f --filter until=24h` and `docker image prune -f --filter until=24h`; absent `docker`, no `timeout`/`gtimeout`, an unreachable daemon, a timeout, no worktree removed, or an unrecognized value is a clean skip with a named reason; Docker runs after the cleanup lock is released.
- [x] No test or code path invokes `docker volume`, `docker container`, `docker system prune`, or any `-a`/`--all` flag (the shim records every call).
- [x] `SOLEUR_CLEANUP_SPACE` prints logical bytes (drained only) beside the signed measured `df -Pk <first scratch base>` delta; on btrfs with a snapper config it also prints the pinning hint; no `snapper` binary is called and no snapshot is touched; it prints on every `cleanup-merged` run including the lock-contended and fetch-failure early returns.
- [x] A failure in `docker_builder_prune` or `report_cleanup_space` (rc 124, parse miss, `df` failure) does not abort the rest of cleanup-merged (guarded calls).
- [x] `test-git-data-boot-signal-poll.sh` adds zero `/var/tmp/gdboot.*` dirs, on a passing and on a failing run.
- [x] `worktree-manager.sh space-report` prints `SOLEUR_CLEANUP_SPACE` without mutating anything.

#### Non-Functional Requirements

- [x] No new network egress and no new telemetry sink (verified by grep of the diff for `curl`/`wget`/Sentry/Better Stack).
- [ ] NFR register assessment run (no NFR is affected: a local, opt-in, stdout-only maintenance script — recorded in the PR body instead of a separate run) (`soleur:architecture assess`) and recorded in the PR.
- [x] Session-start latency: the bounds are stated honestly in ADR-250 A2 — the timebox is checked between candidates (map build + one timebox + one candidate; the tmpfs action-time check no longer runs the per-process walk), the drain bound is between entries (one large entry can overrun), Docker only when opted in (up to ~140 s).

#### Quality Gates

- [x] ADR-250 amended; `model.c4` plugin description updated; C4 syntax/render/count-parity tests green.
- [x] Runbook and `git-worktree/SKILL.md` document `SOLEUR_QUARANTINE_DRAIN` and `SOLEUR_DOCKER_PRUNE` (one table, both opt-in) and the new markers.
- [ ] PR body carries the root-cause table with the measurement commands, and `Closes #9677` (written at ship).
- [x] `tests/scripts/test-cleanup-merged-space.sh` is registered in `scripts/test-all.sh` and `lint-orphan-test-suites.sh` (run once the file is tracked) does not report it as never run.
- [x] The declared `discoverability_test` (`bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh space-report`) is executed once in the preflight Check 10 sandbox (repo read-only, `HOME` on tmpfs) and prints `SOLEUR_CLEANUP_SPACE` without writing outside tmp; it contains none of the shell-active characters the check rejects.
- [ ] PR body states that the deadline rebase lets the default sweep quarantine more candidates per session on every machine, and that the drain and Docker prune are opt-in (written at ship).
- [x] markdownlint is clean on the plan and `tasks.md`.

### Post-merge (agent-run)

Automation: the agent runs these; none is operator-only (a user-level systemd timer and a local `systemctl` read need no portal, CAPTCHA or consent).

- [ ] Phase 7 timer installed on the operator host and `systemctl --user list-timers tmpfs-guard.timer` shows it.
- [ ] On this host, one session start prints `deferred=0` (or a named residual) and a `SOLEUR_CLEANUP_SPACE` line; the quarantine size trends down at the next timer tick past TTL.

## Test Scenarios

RED-first, fixture-synthesized (`cq-test-fixtures-synthesized-only`), PATH-shimmed externals.

- T1. Given a fixture tree whose `tmp-classify.sh` wrapper sources the real library and redefines `tc_build_inuse_map` to sleep 2 s, `SOLEUR_SWEEP_TIMEBOX_S=1`, and three dead-owner marked dirs older than the age floor, when the sweep runs, then all three are quarantined and `deferred=0` (before the fix: `deferred=2`). The sweep sources the classifier from `$SCRIPT_DIR/../../../scripts/lib/tmp-classify.sh`, so the seam is a copied script tree, not an env override (the existing `sweep()` helper in `test-scratch-session.sh` uses `env -i`/`bash -c`; reuse its harness).
- T1b. Given the same fixture and 5 candidates each sleeping past the timebox AFTER the rebase, then remaining candidates are still `deferred` (the timebox still bounds per-candidate work).
- T2. Given quarantine entries in the scratch and worktrees classes and TTLs set per class (the suite's existing `QUAR_TTL=0` versus `999999` approach — drain age is ctime, which `touch -d` cannot backdate), when the sweep runs, then only the past-TTL class is deleted, `drained` counts both bases (summed, not the last call's value) and `drained_bytes` equals `du -sk` × 1024 of the deleted entries.
- T2b. Given an exported `SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0`, then the sweep does not drain entries younger than the 1440-min floor.
- T2c. Given a drained entry, then `soleur-tmp-purge.sh --restore` reports it already gone; given an undrained entry within TTL, restore still works.
- T3. Given `SOLEUR_QUARANTINE_DRAIN` unset (and, separately, `0`/`yes`), when the sweep runs, then nothing is drained and the existing "holds entries" note prints; given `=1`, the drain runs.
- T4. Given a `docker` shim and `SOLEUR_DOCKER_PRUNE=apply`, then the shim log contains exactly the two prune calls with `--filter until=24h` and no `volume`/`container`/`system`/`-a`.
- T5. Given no `docker` on PATH (and, separately, a shim whose `info` fails, a PATH without `timeout`/`gtimeout`, and a shim that sleeps past the bound), then `SOLEUR_DOCKER_PRUNE skipped reason=<docker-missing|daemon-unreachable|no-timeout|timeout>` is printed and the run exits 0 with the rest of cleanup-merged completed.
- T6. Given `SOLEUR_DOCKER_PRUNE=1`, then the shim log has only read calls; given `yes`/`true`/`0`, then `skipped reason=invalid-value`; given the opt-in set and no worktree removed, then `skipped reason=no-worktree-removed`.
- T7. Given the shim prints `Total:  1.2GB` (builder) and `Total reclaimed space: 300MB` (image), then both lines appear verbatim on the Docker marker and nothing is parsed.
- T8. Given a `findmnt` shim returning `btrfs` and a fixture snapper config, then `snapshots=snapper` and the hint line print; given `ext4`, then `snapshots=none`.
- T9. Given the snapper fixture, then no `snapper` command is executed (PATH has none) and the snapshot directory is unchanged.
- T10. Given `space-report`, then the marker prints and `find` shows no file changed under the fixture tree.
- T11. Mutation rows for the new tests (so they are not vacuous): delete the deadline rebase, T1 reddens; make the drain ignore TTL, T2 reddens; move the drain after `exec {sweep_fd}>&-`, a lock-held assertion (T14) reddens; add `--all` to the shim-recorded call, T4 reddens; drop the `|| warn` guard on `docker_builder_prune`, T5's timeout case reddens.
- T12. Given a `tc_build_inuse_map` that fails (empty map), then candidates fall back to the per-candidate walk and the sweep stays inside its bounds or defers, never reaping a candidate with live handles.
- T13. Given the gdboot poll suite forced to fail mid-run, then no `gdboot.*` dir remains under the suite's `TMPDIR`.
- T14. Given a held `tmp-guard.lock`, then the sweep prints `skipped reason=lock-contended` and drains nothing; given the lock free, then the drain executes while the lock fd is still open.
- T15. Given a lock-contended `cleanup-merged`, then `SOLEUR_CLEANUP_SPACE` still prints once.

## Success Metrics

On the operator host after merge: `deferred=0` on a session start with marked dirs present, quarantine size trending to 0 within one TTL, and `SOLEUR_CLEANUP_SPACE` showing logical vs `df` bytes.

## Decisions Taken at Plan Review (Step 4.5 advisor consult + plan-review panel, 2026-10-07)

The scoped advisor consult and the review panel challenged operator-stated directions. Per ADR-084 these were surfaced as User-Challenges and the user resolved each at the plan-review gate:

- **D1 (resolved by the user at plan review, 2026-10-07): drain is opt-in** (`SOLEUR_QUARANTINE_DRAIN=1`). Customers keep today's behavior; opt-in satisfies CPO's sign-off condition 1 and the CLO lean.
- **D2 (resolved by the user at plan review): single PR as planned.** The PR body states that the deadline rebase lets the default sweep quarantine more candidates per session on every machine (CPO condition 2).
- **D3 (resolved: keep Docker; item 5 kept as planned).** Trim scope inside the user-chosen items. DHH, code-simplicity and the advisor argue the Docker step reclaims ~nothing on this host (build cache ~0, 317 MB images) and that snapper/`findmnt`/`space-report` are machinery beyond a plain `df` delta; CPO accepts Docker only because it was asked for. Resolution: keep both, with the cuts that do not remove an asked-for output already applied (no unit parser, no `snapper` binary call, `map_s` not `map_ms`). Challenge: drop the Docker step (file separately) and/or reduce item 5 to `df` before/after only.
- **Plan-review tally for D1/D2:** opt-in drain preferred by CPO (condition), CLO, CTO, advisor, DHH, spec-flow, architecture; split preferred by CPO, CTO, DHH, advisor.
- **Accepted from the consult without changing scope:** the liveness map is already lazy (built only at the first declared-owner candidate, so a clean host pays nothing); `map_s` is emitted so the cost stays visible; the `df` delta reading near zero under snapshot pinning is the point of Phase 3, and the `snapshots=` field explains it.

## Dependencies & Risks

- **Terminal delete on customer machines** (single-user incident class): off by default (opt-in `SOLEUR_QUARANTINE_DRAIN=1`), then bounded by the quarantine dwell (7 d scratch / 30 d worktrees), the ledger, and `--restore` before TTL. Never touches anything outside `soleur-quarantine.<uid>/`.
- **Latency:** worst case roughly +15 s over today on a busy host (rebased 10 s sweep + 5 s drain); the map build is not new. One oversized quarantine entry can overrun the drain bound (a `find -delete` is not interruptible); it is retried next session. On macOS the sweep skips with `flock-missing`, so drain and the sweep's `df` do not apply there; Docker prune and the space report still run (with the `gtimeout` fallback).
- **`find -delete` on quarantine is the one permitted terminal delete (ADR-250);** the drain keeps its symlink/ownership/mount refusals unchanged.
- **Docker shared daemon:** `until=24h`, opt-in, dry-run default.
- **Cross-consumer:** `tc_drain_quarantine` gains an optional trailing argument (absolute epoch deadline) and keeps resetting `TC_DRAINED` per call; existing callers (`tmpfs-guard.sh:944`, `soleur-tmp-purge.sh:161`) pass none and are unchanged (confirm with `git grep tc_drain_quarantine`).

## Files to Edit

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
- `plugins/soleur/scripts/lib/tmp-classify.sh`
- `tests/scripts/test-scratch-session.sh`
- `tests/scripts/test-git-data-boot-signal-poll.sh`
- `scripts/test-all.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-250-ownership-keyed-scratch-reclamation.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and `model.likec4.json` if it is regenerated from descriptions)
- `knowledge-base/engineering/operations/runbooks/tmpfs-guard-install.md`
- `plugins/soleur/skills/git-worktree/SKILL.md`

## Files to Create

- `tests/scripts/test-cleanup-merged-space.sh`

## References & Research

- ADR-250, ADR-133, ADR-129, ADR-195, ADR-178 (user-machine write surfaces)
- Learning: `knowledge-base/project/learnings/2026-09-24-a-reaper-whose-trigger-isnt-installed-is-a-no-op.md`
- Issue #9677; deferred #9693, #9694; related #7004, #8786, #8496
