---
title: "fix(infra): disarm the /workspaces LUKS dead-man at the host-canary door, and release retained web-1 snapshot 411798619"
date: 2026-09-28
slug: fix-luks-deadman-host-canary-disarm-and-snapshot-411798619-release
branch: feat-one-shot-luks-residuals-8734-9045
issue: 9045
closes: [9045]
refs: [8734, 8706, 6604, 6178, 8632, 8626]
type: bug
priority: p1
domain: [engineering, legal]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-09-28
**Agents used:**

- review: security-sentinel, observability-coverage-reviewer, test-design-reviewer, user-impact-reviewer;
- research: best-practices-researcher (systemd transient-unit semantics), plus a verify-the-negative sweep;
- earlier, in plan-review: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CTO.

**Halt gates:** 4.6, 4.7, 4.8, 4.10 and 4.11 all passed (`lint-guard-contract.py`: 3 entries). The
probe verb passes `probe-verb-gate.sh`. 4.5 and 4.55 do not trigger: there is no connectivity
symptom, and the only apply is an idempotent re-fire with no downtime.

### Key improvements

1. **The post-canary roll-forward can no longer start the app on an empty or wrong mount.**
   - Before the disarm, the host canary checks the workspace count on `$MOUNT` against
     `WORKSPACES_COUNT`.
   - `cleanup` re-asserts the mapper before rolling forward. `resume_writers` alone checks only
     `mountpoint` (user-impact review and verify sweep).
2. **An unattended dead-man fire now pages** through a new Better Stack logs alert on
   `result=fired`. That closes the #6812 six-hour-silence class, and the SIGKILL residual with it
   (observability review).
3. **`rollback()` handles the dead-man before any unmount**, with a bounded wait for a running
   fire. The harness gains a last-event-wins GC model, `DRY_RUN=0` everywhere, `(exit 9)`
   injection, a stub self-test and an instrument control. Without these, about half the planned
   cases would have passed vacuously (test-design review).
4. **The forensic print and the delete script are leak-safe** (security review):
   - exact-field fstab select;
   - a one-key `apt-config shell`;
   - an argv-only `ExecStart` hash;
   - a wider DIAG_OK deny list;
   - xtrace refusal and the token passed on stdin;
   - a scrubbed, length-capped `detail=`, kept out of Sentry.
5. **Credential dispositions are scoped to the image route.** The service-role key and BYOK
   also go into the token-route issue. A blanket line covers every other root-disk secret class,
   and `GET /v1/servers` joins the evidence limb.
6. **The 2026-10-06 deadline is enforced without a new secret.** A follow-through probe keys on
   #8734's deletion-evidence marker; putting `HCLOUD_TOKEN` in the public-repo sweeper is the
   #8209 class.

### New considerations discovered

- **Two authorities disagree on elapsed-timer retention.** systemd.timer(5) says an elapsed
  timer stays loaded (`RemainAfterElapse=yes`), but web-1 printed the timer `inactive/dead`. The
  real-systemd case settles it, and no design decision depends on the answer: the arm's timer
  stop tolerates both.
- **The drift alert's filter is `eq`, not `IS_IN`**, and every reason groups into Sentry issue
  135268270. The runbook says never to archive it.
- **`WORKSPACES_DEAD_MAN_MIN` is never passed by the workflow**, so the window is always 30 min.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Resume the remaining /workspaces LUKS work after the #8706 host-timer fix. This plan covers four
items in order: releasing the retained web-1 snapshot image 411798619 (#8734), fixing the cutover
abort path so the LUKS dead-man is disarmed and records an outcome (#9045), measuring what web-1's
fstab entry for /mnt/data actually names, and the date-gated #8706 follow-through check.

## Research Insights

### Premise Validation (Phase 0.6, 2026-09-28)

| Cited premise | Checked with | Result |
|---|---|---|
| #8734 open, P1, due 2026-10-06 | `gh issue view 8734 --comments` | Holds. Three comments since filing: exposure window widened to 2026-07-18..rotation (web-probes-read could read current `soleur/prd`), #8737 order (minter tokens rotated first, satisfied 2026-09-27), and `GITHUB_APP_PRIVATE_KEY` + `STRIPE_SECRET_KEY` added to the "rotate, or state why not" list. |
| #9045 open | `gh issue view 9045` | Holds. No PR references it. |
| #8706 fixed and armed | issue + follow-through script | Holds. Follow-through `scripts/followthroughs/luks-monitor-host-timer-8706.sh` enrolled, earliest 2026-10-01T01:00Z. |
| "Snapshot 411798619 may be the ADR-119 rollback anchor" | ADR-119 §(b), Hetzner `GET /v1/images/411798619` | **Does not hold.** ADR-119 §(b) says "Do not take a pre-cutover Hetzner snapshot"; the /workspaces rollback is the retained plaintext volume. A Hetzner server snapshot holds the root disk only, never attached volumes. The image carries `labels.purpose=inngest-cutover-pre`, was created by `scripts/cutover-inngest.sh` `op=backup` (anchor: `DELETE after cutover confirmed: DELETE /v1/images/$IMAGE_ID`), and is the ADR-100 / #6178 Inngest-cutover rollback substrate. |
| "ADR-100's 2026-09-23 addendum retains it until 2026-10-06" (#8632 body) | `git grep` on `origin/main`; `git log -S406654994 --all` | **Stale reference.** That addendum exists only on the unmerged #8626 branch (`origin/feat-ledger-root-disk-scope-and-record-anchors`, commit 348810a96c), with the Art. 5(2) destruction record `knowledge-base/legal/audits/2026-09-23-art-5-2-web1-snapshot-destruction-record.md`. On `main`, ADR-100's 2026-09-19 addendum releases all four `inngest-cutover-pre-*` images after a SOAK CLEAN re-read. Three were deleted on 2026-09-24 (commit 36c120851f on the #8626 branch; Hetzner image actions confirm `delete_image` at 07:23:49Z/07:23:55Z/07:24:01Z). |
| "fstab /mnt/data names the superseded plaintext volume" (ADR-119 2026-09-27 review amendment) | apply run 36340195638 state print; `git show 5b8e24206c:apps/web-platform/infra/cloud-init.yml` | **Does not hold as stated.** `findmnt --fstab -no SOURCE /mnt/data` printed the literal `/dev/disk/by-id/scsi-0HC_Volume_*`. That is web-1's first-boot line from the 2026-03-17 cloud-init (`echo '/dev/disk/by-id/scsi-0HC_Volume_* /mnt/data ext4 defaults 0 2' >> /etc/fstab`), written before the #6604 pin to the by-id path + `nofail`. It names neither the plaintext volume by id nor the mapper; the glob is not expanded by systemd, so it matches no device node. |
| "The dead-man should have fired on 2026-07-23" (#9045) | `workspaces-cutover.sh` `arm_dead_man`, postmortem, run 29995956562 log | **Probably did not arm.** `systemd-run … --unit=workspaces-luks-deadman … 2>/dev/null \|\| true` swallows a refusal, and the `result=armed` marker is logged unconditionally afterwards. The 2026-07-20 fire left `workspaces-luks-deadman.service` failed (postmortem: `Failed with result 'exit-code'` at 22:42:13Z), and a loaded failed unit makes a same-name `systemd-run` refuse. See Hypotheses. |

### Mechanism Minimality (Phase 0.6b)

**Property List.**

- P1: A retained image that holds prd secret values stops existing, and its deletion is evidenced (who, when, the identity re-read before, the 404 after).
- P2: The #8209 / #8734 legal records state the image-use evidence and its coverage boundary, and the credential-by-credential rotation position.
- P3: After a post-canary cutover abort, nothing unattended reverts `/mnt/data` to plaintext.
- P4: Every cutover abort leaves a recorded dead-man outcome that is readable off the host without SSH.
- P5: A dead-man that did not actually arm is detected at arm time, not discovered by inference two months later.
- P6: What web-1's dead-man last did, and what fstab names for `/mnt/data`, is readable without SSH.

**Mechanisms in the ask, and what already covers them.**

| Mechanism | Property | Already on `main`? | Disposition |
|---|---|---|---|
| Terraform-managed snapshot deletion | P1 | No Terraform resource manages snapshots (they are created by `cutover-inngest.sh` over the API); the three sibling deletions used `DELETE /v1/images/<id>` | **Cut** Terraform import+destroy. Use the same single API DELETE with an identity re-read, as PR-4b did. |
| Value rotation (service-role key, App key, Stripe key, BYOK) | P2 | #8734's own rule: rotate if step 1 is INCONCLUSIVE or the image outlives 2026-10-06 | Decided per credential in Phase 1 after the CLO determination; not a default deliverable. |
| New `result=` marker checked by the verify job | P4 | `logger -t luks-monitor` is Vector-allowlisted and already carries `SOLEUR_WORKSPACES_LUKS_DEADMAN result=armed/fired/ok/fail/disarmed`; `terraform_data.luks_monitor_install` already prints the dead-man units into every apply log | **Cut** a verify-job change and any state-file keys (plan review: they have no reader between installer fires). Reuse the marker channel: reason-coded disarm markers plus one `result=cutover_aborted outcome=<x>` marker per abort, readable on demand through Better Stack and Sentry. |
| Terraform host step to clear the failed dead-man unit | P5 (indirectly) | The only consumer of the unit name is `arm_dead_man` | **Cut.** `arm_dead_man` pre-clears a stale non-waiting unit itself and verifies the arm; the failed unit stays on web-1 as evidence. |
| fstab rewrite through Terraform | (reboot safety) | — | **Cut from this PR.** A rewrite to the mapper alone lets dockerd resurrect the app over a bare root-disk `/mnt/data` (ADR-119 §(e) hazard; the mount gate was never delivered to web-1). Filed as its own issue with the coupled fix. |

### Relevant files (content anchors, `origin/main` at fff36b6172)

- `apps/web-platform/infra/workspaces-cutover.sh`: `arm_dead_man()`, `disarm_dead_man()`, `rollback()` (ends `disarm_dead_man` then `emit_drift rollback_engaged`), `cleanup()` (`if [ "$CANARY_OK" != "1" ] && …; then rollback`), main body `FREEZE_HELD=1; persist_state FREEZE_HELD 1; arm_dead_man`, host canary block ending `CANARY_OK=1; persist_state CANARY_OK "1:$(cryptsetup luksUUID "$FRESH_DEV")"`, and the `docker start "$CONTAINER"` / `app_canary` / `disarm_dead_man` block.
- `apps/web-platform/infra/workspaces-luks-freeze.test.sh`: T6b (rollback disarms), T12/T12b/T12c (dead-man command shape), T25/T25b (pins `app_canary` BEFORE `disarm_dead_man` in the main body; inverted by this plan), AC8 (retry budget < dead-man window).
- `apps/web-platform/infra/workspaces-luks-harness.sh`: `run_case` stubs; `systemctl show` currently prints `${STOP_RESULT:-success}` for every property, and `systemd-run` always returns 0 (both need knobs).
- `apps/web-platform/infra/workspaces-luks.tf`: `terraform_data.luks_monitor_install` — `triggers_replace` hashes the four delivered files + the DSN only, so an edit to its inline state print does NOT re-fire it; the exit-17 freeze guard keys on `SubState=waiting`.
- `apps/web-platform/infra/luks-monitor-install.test.sh`: G2 pins the state print (`workspaces-luks-deadman.timer` / `.service` present).
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` §3 blockquote ("The dead-man can undo a SUCCEEDED cutover, silently … cleared by `disarm_dead_man`, which runs *after* `app_canary`") becomes false after this change.
- `scripts/followthroughs/inngest-soak-6178.sh` (main: `SNAPSHOTS='398857857, 406654994, 407991378, 411798619'`) — its ACTION REQUIRED verb (3) goes stale once the last image is released; the #8626 branch already rewrites this line.
- Legal records: `knowledge-base/legal/audits/2026-09-8209-prior-exposure-assessment.md` (§"L2-L5", L3 bullet), `knowledge-base/legal/breach-register.md` (2026-09-23 row), `knowledge-base/legal/compliance-posture.md` (Active Items table: R1, R5 rows).

### Live measurements taken during planning (read-only)

- `GET /v1/images/411798619`: `type=snapshot status=available created=2026-07-23T15:34:04Z created_from=123931471 (soleur-web-platform) protection.delete=false bound_to=null labels={purpose:inngest-cutover-pre, ts:20260723T153403Z} image_size≈23.8 GB`. It is the only snapshot in the project; no `type=backup` images.
- `GET /v1/servers/actions` (7 pages, 317 actions, 2026-07-03T07:13:22Z..2026-09-27T14:56:48Z, deleted servers included): 0 `rebuild_server`; 101 `create_server`, every one with image `161547269` (Ubuntu 24.04); the only action naming `411798619` is its own `create_image`. Web-1 (`123931471`) has no rescue, reset, reboot or rebuild action in the window.
- `GET /v1/images/actions`: only `delete_image` rows (408787015 on 07-15; 398857857, 406654994, 407991378 on 09-24). Nothing for 411798619.
- `GET /v1/volumes`: plaintext `soleur-web-platform-data` (105149570, ext4) and `soleur-web-platform-data-luks` (106443278) are BOTH attached to web-1. ADR-119 §(b) wants the retained plaintext detached; its wipe/detach is #6604's PR 3 (the #6604 soak sweeper reads "SOAK PASSED — wipe authorized").
- Apply run 36340195638 (2026-09-27 18:21Z) state print: `workspaces-luks-deadman.timer ActiveState=inactive SubState=dead`; `workspaces-luks-deadman.service ActiveState=failed Result=exit-code`; `mnt-data.mount What=/dev/mapper/workspaces FragmentPath=/run/systemd/generator/mnt-data.mount`; fstab source the literal glob.
- Better Stack: the s3 archive's earliest retained row is 2026-08-13; zero `SOLEUR_WORKSPACES_LUKS_DEADMAN` rows from web-1 in hot + archive. July's dead-man rows are gone, as #9045 says.
- Cutover run 29995956562 (2026-07-23): host canary PASSED 09:40:34Z, then `FATAL: /internal/readyz … reason=readyz_gate_regression code=403` at 09:40:41Z, `ABORT (rc=1)`. `systemd-run` stderr is discarded, so the run log cannot show whether the arm was refused.

### Institutional learnings applied

- `2026-09-24-i-parked-a-fix-for-a-cause-i-never-tested-and-my-stubs-could-not-see-the-device.md`: stubs must assert the operand, not the call count. The new `systemctl show` knob answers per unit and per property.
- `2026-07-24-guest-luks-store-must-gate-consumer-on-mount-and-guard-suite-must-pin-fail-loud-semantics.md`: pin exit-code co-location, not marker text. The arm-verification rows assert `died` plus the absence of `result=armed`, not the presence of a message.
- `2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist.md`: every new `logger -t` tag must be Vector-allowlisted. This plan adds none; every new marker rides the existing `luks-monitor` tag.
- `workflow-patterns/2026-07-19-real-cutover-routes-to-workflow-dispatch-and-failclosed-gate-must-self-report.md`: a fail-closed gate emits before it dies. The arm and disarm refusals emit their marker and a Sentry drift before `die`.
- `2026-09-27-the-monitor-that-was-never-installed-and-the-dependency-that-would-have-mounted-plaintext.md`: arming something that never ran is a first execution. The same applies here: the reordered disarm has never run on a real cutover, so its first run is a future re-cut. The static ordering test and the harness cases are the only pre-merge proof.
- `2026-06-18-live-credential-rotation-and-argv-to-env-redeploy.md`: a `-target`-scoped apply never applies a resource that has no `-target=` line. The installer re-fire is triggered through `triggers_replace`, not by adding a resource.

### CLAUDE.md / AGENTS conventions that bind this plan

`hr-menu-option-ack-not-prod-write-auth` (the image DELETE waits for a per-command go-ahead), `hr-no-ssh-fallback-in-runbooks` (every verification is the apply-log state print, Hetzner GETs or Better Stack), `hr-prod-host-config-change-immutable-redeploy` (the installer re-fire rests on ADR-154's standing web-1 exception, as #8706 did; no new host mutation is added), `hr-before-asserting-github-issue-status`, `wg-use-closes-n-in-pr-body-not-title-to`, `cq-write-failing-tests-before`, `cq-cite-content-anchor-not-line-number`.

### Functional overlap (Phase 1.5b)

No relevant community overlap (functional-discovery, 2026-09-28): `hetzner-skills` can delete an image but has no cutover, timer or audit-record handling.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Research Reconciliation — Spec vs. Codebase

| Claim in the ask / issues | Reality | Plan response |
|---|---|---|
| "Confirm whether 411798619 is still the ADR-119 rollback anchor" | It never was. ADR-119 §(b) forbids a pre-cutover snapshot; a server snapshot excludes volumes; the image is ADR-100's Inngest substrate. | The rollback-loss weighing and the release decision go in an **ADR-100** addendum (the ADR that owns the image's release order). The confirmation goes in the #8734 evidence comment, not ADR-119. The ask records into ADR-119 only if the image IS its anchor (plan review). |
| #8734: "delete at the earliest point ADR-100's soak verbs allow (SOAK CLEAN)" | Soak read `UNEXPLAINED=1` on 2026-09-27. ADR-100's own 2026-09-25 update says the heaviest slice outgrows the page budget around 2026-09-28, after which the probe reads CANNOT ESTABLISH until #6178 closes. Horizon 2026-10-06. | Release before SOAK CLEAN, recorded as a deliberate departure from ADR-100's verb order, with the rollback value weighed (Phase 1). |
| #9045: "Read the dead-man unit's current state" via the apply log | The print exists but lacks `LoadState` and every timestamp, so it cannot say WHEN the service failed. An inline edit does not re-fire the installer. The existing print also runs AFTER the exit-17 arm step, so a live freeze suppresses it. | A separate read-only forensic step, placed BEFORE the arm step, prints manager-memory properties (they survive journal rotation). Its command list is a `local` folded into `triggers_replace`, so the merge re-fires the installer once. |
| #9045: "decide keep armed vs disarm" | ADR-119 §(b) already says "The rollback door closes at `docker start`". The 2026-07-20 incident is what an armed dead-man past that door costs. | Disarm at the host-canary pass, before `docker start`. A post-canary abort then has nothing armed, by construction. |
| ADR-119 2026-09-27 review amendment: "an elapsed transient timer keeps `ActiveState=active, SubState=elapsed` until reboot" | The 2026-09-27 print reads `inactive/dead` for the timer. `LoadState` was not printed. | Qualify the claim in place as unmeasured and contradicted by the print. The new print adds `LoadState` to settle it. |
| ADR-119 2026-09-27 review amendment: fstab "can be the superseded plaintext volume" | fstab carries the literal glob, and that line cannot mount the plaintext volume. | Qualify in place, record the actual reboot hazard, and file the coupled reboot-path fix as its own issue. |

## Plan Review Revisions (2026-09-28)

The six-seat panel was DHH, Kieran, code-simplicity, architecture-strategist, spec-flow and CTO
devex. Both axes fired on the dead-man machinery, so the rule was to delete before fixing.

**Applied (Mechanical):**

- **R1 (P0, Kieran + spec-flow + architecture):** `DEADMAN_ARMED=1` is set as soon as
  `systemd-run` returns 0, so a failed verification can never leave a live timer on an unfrozen
  host. `DEADMAN_ARMED=0` is initialised globally for `set -u` (T32b).
- **R2 (P0, spec-flow + Kieran + CTO devex):** a post-canary abort is fix-forward only in the
  runbook, and `cleanup` rolls FORWARD (`docker start` + `resume_writers`) instead of leaving the
  app down (architecture #1).
- **R3 (architecture + spec-flow + Kieran):** disarm order is (a) `LastTriggerUSec`, then the
  stop, then (b) service `ActiveState`, then the `reset-failed`. The caller's `findmnt` re-assert
  is the GC-proof check.
- **R4 (DHH + simplicity + spec-flow + Kieran + architecture):** cut the `stale_cleared`
  evidence emit, the `LoadState` GC poll, the `InvocationID` gate, the `DEADMAN_OUTCOME` and
  `ABORT_OUTCOME` state keys, the `post_canary_abort`/`pre_freeze_abort` reasons and the
  defensive second disarm, and the forensic `journalctl` tail. `--description=` is added to
  `systemd-run`.
- **R5 (DHH + simplicity + Kieran):** the new privileged smoke suite is replaced by one
  real-systemd case in the existing loopback suite, using a throwaway unit name and plain
  `systemd-run`.
- **R6 (Kieran):** harness fidelity. File-backed `_seq_next` per unit and property, a GC model,
  `logger` recorded in `$CALLS`, `LastTriggerUSec` defaulting to empty, and globals set inside the
  invocation. AC3/T39 now count logical command lines.
- **R7 (architecture):** added the missed consumer `tests/scripts/test-workspaces-luks-cutover-gate.sh`.
  AC2 now covers every `git grep -l workspaces-cutover.sh` suite.
- **R8 (architecture):** the ADR-100 addendum supersedes #8626's pending retention clause, and
  the #8626 comment prescribes the rebase order, the ledger flip and the `SNAPSHOTS` drop.
- **R9 (spec-flow):** the snapshot script re-pulls the action log after the DELETE and names its
  non-204/non-404 branches. The no-go-ahead branch labels #8734 `action-required`.
- **R10 (spec-flow):** "reboot web-1 once" in the cutover log line and in runbook step 4 now
  points at the fstab issue.
- **R11 (Kieran + spec-flow):** forensic lines are `|| true`/`echo`-guarded, and
  `reboot-required`/`automatic-reboot` echo explicit values.
- **R12 (architecture):** an ADR-154 `Re-examined 2026-09-28` note.
- **R13 (DHH):** one #8734 evidence comment, with the other comments linking to it. The ADR-119
  "never its anchor" line moves to that comment.
- **R14 (spec-flow):** `rollback()` waits (bounded) for a running fire, gates its verifying
  disarm on `DEADMAN_ARMED`, and `arm_dead_man` also refuses a fire in progress.

**Kept against a cut request:**

- the network-layer Hypotheses table, required by the plan skill's Phase 1.4 gate once "SSH"
  appears in the ask;
- Phase 4 (#8706), which the ask names as item 4;
- the compliance-posture row, recommended by the CLO and listed in #8734's own task;
- `BASELINE_DECLARED_PROBES`, forced by this plan's `credentials_required`.

**Taste / challenges, persisted to `knowledge-base/project/specs/feat-one-shot-luks-residuals-8734-9045/decision-challenges.md`
for ship:**

- split into a records PR and a code PR (CTO devex);
- make `ROLLBACK=1` refuse after a matching `CANARY_OK` UUID (spec-flow P0, second half);
- a watchdog for a SIGKILL after the disarm (spec-flow);
- name the consumer of the hardening (CTO devex).

## Hypotheses

### Network layer (Phase 1.4 checklist; triggered by the literal token "SSH" in the ask)

No connectivity symptom is under diagnosis. The only SSH path this plan touches is the Terraform
apply bridge, and its most recent run connected and completed.

| Layer | Verified? | Artifact |
|---|---|---|
| L3 firewall allow-list | Verified (indirect) | Apply run 36340195638: `terraform_data.luks_monitor_install (remote-exec): Connected!` four times, `Creation complete after 21s`. The bridge traverses the firewall on every merge. |
| L3 DNS / routing | Verified (indirect) | Same run; the bridge resolves and reaches web-1. |
| L7 TLS / proxy | Not applicable | No HTTPS symptom is in scope. |
| L7 application | Not applicable | No service-layer hypothesis is proposed. |

### Dead-man history (#9045)

- **H1 (favoured; CTO concurs).** The 2026-07-20 fire left `workspaces-luks-deadman.service`
  loaded and failed. Nothing reset it: the only run between the fire and the real 07-23 cut was
  29995797567 (2026-07-23 09:33Z), a dry run, and both `arm_dead_man` and `rollback()` return early
  in a dry run. On 2026-07-23 the real run's `systemd-run --unit=workspaces-luks-deadman` was then
  refused ("already loaded"). The refusal went to `/dev/null` and `|| true`, and `result=armed` was
  logged anyway. So the 07-23 dead-man never armed, which is why the LUKS mount survived that
  post-canary abort. Supporting evidence: the post-#6807 fire command ends in `logger` on both
  branches and almost never exits non-zero, while the pre-#6807 command did (postmortem: "the
  dead-man's own restart chain … exited non-zero").
- **H2.** The 07-23 dead-man armed, fired around 10:10Z and failed. Disfavoured: a fire reverts
  `/mnt/data` or stacks plaintext over it, and the live mount is the mapper.
- **Discriminator (post-merge, no SSH).** The re-fired installer prints `ExecMainStartTimestamp`,
  `ExecMainExitTimestamp` and `InvocationID`. It also prints the sha256 of the loaded failed unit's
  `ExecStart` and whether that `ExecStart` contains `result=fired`, a substring that exists only in
  the post-#6807 command. An exit time of 2026-07-20 22:42:13Z with no `result=fired` substring
  confirms H1. If the unit is `LoadState=not-found`, the print says "not loaded" rather than hashing
  empty text.

### fstab (item 3)

- **Measured:** the `/mnt/data` source is the literal `/dev/disk/by-id/scsi-0HC_Volume_*`.
- **Inferred from the 2026-03-17 template:** the options are `defaults 0 2`, with no `nofail`. The
  new print measures the full line.
- **Inferred (CTO agrees) from systemd-fstab-generator semantics:** the generator does not expand
  globs. `mnt-data.mount` therefore waits on a device unit that never appears. Without `nofail`, a
  failed `local-fs.target` sends the boot to emergency mode, and web-1 becomes unreachable over the
  bridge.
- **Measured:** web-1 has no boot-time unlock for `/dev/mapper/workspaces`. No crypttab line is
  delivered to it; #6931 covers the fresh-host path.
- **Conclusion:** today's line fails closed for data but not for availability. Rewriting it to the
  mapper plus `nofail` without the ADR-119 §(e) structural gate would let dockerd resurrect the app
  over a bare root-disk `/mnt/data`, which is worse.

## Problem Statement

1. **#8734.** A plaintext image of web-1's root disk from 2026-07-23 still exists and very likely
   holds prd secret values and journald personal data. It is the last of four
   `inngest-cutover-pre-*` images, and no rollback arm in the repo restores from it. Its hard expiry
   is 2026-10-06. The legal records do not yet describe it as a route to root.
2. **#9045.** The cutover keeps its dead-man armed past `docker start`. A post-canary abort then has
   one of two outcomes, and neither is recorded anywhere a future re-cut can read:
   - if the arm took, the dead-man silently reverts a correct LUKS mount and strands writes
     (2026-07-20);
   - if the arm silently failed, nothing is armed while the log claims it is (2026-07-23, H1).
3. **fstab.** The reboot hazard on record is described wrongly. The real hazard (emergency mode, no
   mapper unlock, an undelivered mount gate) has no tracking issue.
4. **#8706.** Date-gated. The sweeper closes it on `HOST_TIMER_PASS nights=3`, on or after
   2026-10-01.

## Proposed Solution

### Phase 1 — #8734: release snapshot 411798619 (operational, API, per-command go-ahead)

Runs FIRST in the work phase, in this order:

1. **Re-pull the evidence (read-only, `doppler run -p soleur -c prd_terraform --only-secrets HCLOUD_TOKEN`).**
   Query `GET /v1/images/411798619`, every page of `GET /v1/servers/actions?sort=started:desc`, and
   `GET /v1/images/actions`. Assert all four of the following:
   - (a) zero `rebuild_server` actions;
   - (b) EVERY `create_server` row carries a `resources[]` entry of `type=image` (measured today:
     all 101 do), and none names `411798619`;
   - (c) the only action naming `411798619` is its own `create_image`;
   - (d) no `delete_image` or `change_protection` action exists on it;
   - (e) `GET /v1/servers`: no live server has `image.id == 411798619` (security review).

   Every assertion is a `jq` expression with an exit status, never a reading by eye.

   The coverage window runs from `2026-07-23T15:34:04Z`, the image's creation, to the DELETE
   instant. The image did not exist earlier, so the action log's 2026-07-03 start does not limit
   this sub-limb. A `create_server` row with no image resource makes the sub-limb **INCONCLUSIVE**.
   That fires the issue's own rotation rule, so stop and file the rotation issue rather than
   continuing silently (CLO gap 1).
2. **Show the exact command and wait for the per-command go-ahead**
   (`hr-menu-option-ack-not-prod-write-auth`, compliance tier). The command is one scratch script
   run under Doppler, the same shape the PR-4b precedent used:
   - It re-reads the image identity and refuses unless all of these hold: `id=411798619`,
     `type=snapshot`, `created_from.id=123931471`, `labels.purpose=inngest-cutover-pre`,
     `description=inngest-cutover-pre-20260723T153403Z`, `bound_to=null`.
   - It sends `DELETE /v1/images/411798619` and expects `204`.
   - It sends `GET` and expects `404 not_found`.
   - It then re-pulls every page of `GET /v1/servers/actions` and re-asserts (a)–(d) up to the
     DELETE timestamp, so the coverage window really ends at the DELETE (spec-flow).
   - It prints UTC timestamps for every step.
   - **Token hygiene (security review):**
     - it refuses to run under xtrace, with the same `case "$-" in *x*)` guard as
       `workspaces-cutover.sh`;
     - it passes the `Authorization` header to curl on stdin (`--config -`), never in argv, and
       never uses `-v`;
     - it posts only the status code and `jq`-selected fields;
     - it deletes itself after use.
   - **Named failure branches:**
     - a failed identity check, a non-204 DELETE or a non-404 GET makes it stop, edit no records,
       and post the raw status on #8734;
     - a post-DELETE re-pull that shows image use makes it stop, file the rotation issue at once,
       and treat the image-use sub-limb as INCONCLUSIVE.
3. **Record the deletion at the moment it happens.**
   - **One evidence comment on #8734**, opened with the marker
     `<!-- soleur:snapshot-411798619-deleted -->`, carrying:
     - the identity re-read;
     - the DELETE 204 and GET 404 timestamps;
     - the go-ahead text;
     - the evidence limbs;
     - the confirmation that 411798619 was never ADR-119's rollback anchor (ADR-119 §(b)).

     The other comments link to it rather than repeat it.
   - **A comment on PR #8626** linking that evidence, so the Art. 5(2) destruction record's row 4
     can cite a record made at the time. That record's `status:` stays `partial` until #8626
     lands, and this PR never calls it complete. The comment also says what #8626 must do on
     rebase:
     - order its 2026-09-23 ADR-100 addendum ABOVE this PR's 2026-09-28 one, with a
       `Superseded 2026-09-28 (#8734)` marker on its "retained-until SOAK CLEAN" clause;
     - flip its ledger row `hetzner.web1_inngest_cutover_snapshots` to destroyed;
     - drop `411798619` from its `SNAPSHOTS` line;
     - point Article 30 PA-8 (f) at the deletion (architecture review, gdpr-gate).
   - **A comment on #6178** linking the evidence: ADR-100 verb (3) was satisfied by #8734 ahead
     of SOAK CLEAN.
4. **Correct the records (in this PR, after step 3, worded per the CLO advisory).**
   - `knowledge-base/legal/audits/2026-09-8209-prior-exposure-assessment.md`:
     - widen the frontmatter `open_limbs` L3 text in-cell: "… and a server created or rebuilt
       from retained snapshot image 411798619, the fourth route, #8734";
     - add a `> **Superseded 2026-09-28 (#8734):**` marker under the L3 bullet;
     - add a dated addendum recording the image-use sub-limb as **CLEAN within
       [2026-07-23T15:34:04Z, DELETE instant]** and the token-read limb as **INCONCLUSIVE**. It
       states in writing why a CLEAN image-use limb bounds the in-image copy of `web-probes-read`,
       and that any other holder of that token belongs to #8705's population;
     - leave #8209's L3 as a whole **INCONCLUSIVE**. Volume attach/detach for #8209's window is
       unattributed, the two `enable_rescue` actions (2026-07-07 and 2026-07-14, on other servers)
       are unattributed, and nothing before 2026-07-03 is covered.
   - `knowledge-base/legal/breach-register.md`:
     - widen the 2026-09-23 row's description cell in-cell to "… rescue, rebuild, a volume
       re-attach, or a server built from a retained root-disk snapshot", and widen its limbs cell
       the same way;
     - add a `## Corrections — 2026-09-28 (#8734)` section quoting each superseded clause;
     - make no Art. 33/34 change (REACHABILITY-ONLY stands).
   - `knowledge-base/legal/compliance-posture.md`: add a new Active Items row: "Retained
     unencrypted root-disk snapshot held prd secret values past its purpose, a lapsed
     secrets-management measure (Art. 32(1)(b); Art. 5(1)(e)) | #8734 | CLOSED on deletion <UTC> |
     2026-10-06 | …". Cite code and ADRs by name, never by line.
   - ADR-100: append `## Addendum — 2026-09-28 (#8734) — 411798619 is released before SOAK CLEAN`.
     It records four things:
     - **Rollback value:** about nil. No arm restores from the image. `op=rollback` re-arms web-1's
       own quiesced scheduler from the live root disk. A restore would bring back a root disk two
       months stale whose credentials are revoked or rotated (the prd token on 2026-07-30,
       `workspaces-luks-boot` in #8703, `web-probes-read` in #8733, the minter tokens in #8737).
     - **Retention cost:** prd values and personal data kept past their purpose (Art. 5(1)(e),
       Art. 32).
     - **Soak state:** SOAK CLEAN is unlikely before the 2026-10-06 horizon.
     - **Scope:** the ADR's status (`adopting`) and #6178's close order are unchanged.
   - A correcting comment on #8632. It retracts "the service-role and BYOK exposure through the
     images is closed", citing #8734's value paths and this deletion.
5. **Credential dispositions (recorded on #8734 and in the assessment addendum).**
   - `SUPABASE_SERVICE_ROLE_KEY`: "not rotated under #8734's image route (image-use CLEAN, image
     deleted before 2026-10-06); the token-route decision is owed under #<token-route issue>".
   - `BYOK_ENCRYPTION_KEY`: worded the same way, with the CTO's concurrence recorded on
     2026-09-28. The concurrence has two conditions: the re-pull at deletion, and a mandatory
     rotation issue if the image outlives 2026-10-06.
   - The two keys are still readable through the `web-probes-read` token route, whose read limb is
     INCONCLUSIVE, and deleting the image does not close that route (security review). The
     token-route issue names both keys, alongside Stripe.
   - **Every other root-disk secret class the image holds** is tied to the same CLEAN image-use
     limb in one blanket line (security review). That covers web-1's SSH host private keys (CI
     pins `local.web_1_ssh_host_key`), cloud-init `user-data`, the cloudflared tunnel credentials,
     the GHCR pull token and the Vector/Better Stack ingest token.
   - The addendum also states whether `HCLOUD_TOKEN` itself was readable through any config the
     exposed tokens could read. It lives in `prd_terraform`, which `web-probes-read` (scoped to
     `soleur/prd`) could not read. Verify this read-only from the token's config scope, and record
     it.
   - `STRIPE_SECRET_KEY`: not triggered on the image route. #8705 left value exposure to #8734, so
     nobody owns the token-route disposition. **File a separate operator-gated issue** for the
     token-route value-rotation determination. It covers the Stripe key, the service-role key,
     BYOK, and the other `soleur/prd` values. It does not belong in this PR.
   - `GITHUB_APP_PRIVATE_KEY`: "not rotated under #8734; owed under #8209 R5 / R1". Never write
     "no rotation needed".
6. **If the go-ahead does not come in-session,** leave the records unedited: they must describe
   reality. The PR ships the code items with `Ref #8734`.
   - #8734 gets a comment carrying the prepared command.
   - #8734 gets the `action-required` label, which puts it in the operator digest and triage.
   - The comment states the 2026-10-06 expiry. Past it, the service-role and BYOK rotation issues
     become mandatory (CTO condition).
   - The records and the ADR-100 addendum then ride a follow-up PR opened after the DELETE.
   - **A follow-through probe enforces the deadline** (user-impact and spec-flow reviews):
     `scripts/followthroughs/snapshot-411798619-expiry-8734.sh`. It is enrolled on #8734 with
     `earliest=2026-10-06T00:00Z` and needs **no new secret**. The sweeper already has
     `GH_TOKEN`, and wiring `HCLOUD_TOKEN` into a public-repo workflow is the exact
     repo-secret-reachable class #8209 is evicting.
     - It reads #8734's comments for the deletion-evidence marker
       `<!-- soleur:snapshot-411798619-deleted -->`, which the Phase 1 evidence comment carries.
     - Marker present: exit 0.
     - Absent on or after 2026-10-06: exit 5 (ACTION REQUIRED), naming the service-role and
       BYOK rotation issues to file.
     - The marker is a proxy for the deletion; the evidence comment holds the actual GET-404
       proof.
     - The probe ships only on the no-go-ahead branch; the go-ahead path does not need it.

### Phase 2 — #9045: disarm at the host-canary door, verify the arm, record the outcome (TDD)

[Revised 2026-09-28 after the six-seat plan review; see `## Plan Review Revisions`.]

In `apps/web-platform/infra/workspaces-cutover.sh`:

1. **`arm_dead_man()` fails closed and verifies itself.** A new global `DEADMAN_ARMED=0` is
   initialised beside `FREEZE_HELD`, `FLIP_DONE` and `CANARY_OK`, because `set -u` would
   otherwise abort `cleanup()` inside the EXIT trap. The arm then runs these steps:
   - **Refuse if a dead-man is live.** If the timer reads `SubState=waiting`, or the service
     reads `active` or `activating` (a fire in progress), it emits
     `result=arm_refused reason=already_armed|fire_in_progress` plus the drift
     `deadman_already_armed`, then dies. It never stops a live timer.
   - **Pre-clear a stale unit.** It stops the timer, tolerating exit 5 ("not loaded"), then
     `reset-failed`s both units. The forensic print on this PR's merge apply captures web-1's
     current stale unit before any re-cut, so no evidence-emit step is added here.
   - **Run `systemd-run` without the swallow.** The `2>/dev/null || true` goes. `--description=`
     is set to a fixed string, so the journal no longer echoes the command line (systemd-run(1):
     the default description is the command).
   - **Capture the error without a temp file:** `err="$(systemd-run … 2>&1 >/dev/null)"`. Then
     scrub it under `LC_ALL=C`: `head -n1`, `cut -c1-200`, `_vscrub`, and `=` mapped to `_` so
     text like `result=armed` cannot spoof a marker field. `detail=` goes LAST in the marker and
     never into `WL_REASON`/`emit_drift`, so Sentry never receives free text (security review). On a non-zero exit it emits
     `result=arm_failed reason=systemd_run_refused detail=<scrubbed first line>` plus the drift
     `deadman_arm_failed`, then dies. A lagging garbage collection surfaces here, as a named
     failure, and the runbook row gives the no-SSH recovery: re-dispatch, since the
     `reset-failed` has already run.
   - **Set `DEADMAN_ARMED=1` as soon as `systemd-run` returns 0,** before any verification. A
     failed verification then still reaches the disarm in `cleanup()`, so no timer is ever left
     live with nothing frozen (P0 from Kieran, spec-flow and the architecture review).
   - **Verify the arm.** A bounded poll checks for `SubState=waiting`: at most 5 attempts, 1 s
     apart, counted by attempt rather than clock, so the harness's no-op `sleep` cannot spin it. On a miss it emits
     `result=arm_failed reason=timer_not_waiting substate=<x>` and dies, and `cleanup()` disarms.
   - On success it emits `result=armed reason=freeze_engaged deadline_min=<n>`, the existing
     marker.
   - **The unit name stays fixed** (`workspaces-luks-deadman`). Four consumers key on it: the
     installer's exit-17 guard, the forensic print, the runbook and the harness.
2. **The main body arms BEFORE setting the freeze flag:**
   `arm_dead_man; FREEZE_HELD=1; persist_state FREEZE_HELD 1`.
3. **`disarm_dead_man <reason>` returns a status and never `die`s.** A `die` inside `rollback()`
   would abort the rollback halfway. It runs in this order (race-free per the architecture and
   spec-flow reviews):
   - (a) Read the timer's `LastTriggerUSec` BEFORE the stop. Stopping a transient timer unloads
     it, and garbage collection then empties every property.
   - Stop the timer. From this point no new fire can start.
   - (b) Read the service `ActiveState` AFTER the stop. A fire that started before the stop is
     still `active`/`activating`, because a running unit is not collected.
   - `reset-failed` both units, then (c) verify the timer no longer reads `waiting`.
   - If (a) is non-empty, (b) is active or activating, or (c) still reads waiting, it emits
     `result=disarm_failed reason=<reason> check=<a|b|c>` plus the drift `deadman_disarm_failed`
     and returns 1. Otherwise it emits `result=disarmed reason=<reason>`, sets `DEADMAN_ARMED=0`
     and returns 0.
   - The reason vocabulary is closed: `host_canary_passed`, `rollback_engaged`, `arm_aborted`.
   - **Every new dead-man marker is echoed to stdout AND logged** (`echo "$row"; logger -t …`),
     the pattern the drift rows already use. The cutover run log then shows `detail=` at once,
     while Better Stack keeps the durable copy (observability review).
4. **`rollback()` handles the dead-man FIRST, before any unmount** (test-design review):
   - It waits for the dead-man service to leave `active`/`activating`, for at most 30 attempts
     3 s apart. On expiry it emits `result=disarm_failed reason=rollback_engaged check=fire_stuck`
     and proceeds anyway: the plaintext remount the fire was performing is the same end state.
   - With `DEADMAN_ARMED=1` it runs the verifying `disarm_dead_man rollback_engaged`, whose check
     (a) reads before its own stop.
   - With `DEADMAN_ARMED=0` it runs an unconditional timer stop (T6b stays pinned) and emits
     `result=not_armed reason=rollback_engaged`. That avoids a false fatal page in a `ROLLBACK=1`
     dispatch after an earlier fire.
   - Only then does it unmount and remount. Today the path logs the false
     `reason=canary_passed`, after the remount.
5. **The single disarm point moves to the host canary.** It sits after the last host-canary assert
   (`mountpoint -q "$MOUNT" || { emit_drift not_mounted; … }`) and before `CANARY_OK=1`.
   - **First, a population assert on the live mount (user-impact review).**
     `wl_count_workspace_dirs "$MOUNT/workspaces"` must equal the persisted `WORKSPACES_COUNT`.
     Otherwise it runs `emit_drift host_canary_workspace_count_mismatch` and dies while
     `CANARY_OK=0`, and the rollback is still lossless. Today the only content check on `$MOUNT`
     is `readyz`, which runs after `docker start`, past the door. The count G3 persisted was
     taken on `$STAGING`, and this check proves it on `$MOUNT` after the repoint.
   - `disarm_dead_man host_canary_passed || die "…"`.
   - Then the GC-proof re-assert: `findmnt -no SOURCE "$MOUNT"` must equal `$MAPPER`. A fire
     unmounts `$MOUNT`, and garbage collection cannot hide that. A mismatch runs
     `emit_drift deadman_fired_before_disarm` and dies while `CANARY_OK=0`, so `cleanup()` rolls
     back before `docker start`, where the rollback is lossless (ADR-119 §(b)).
   - The post-`app_canary` `disarm_dead_man` line is DELETED.
   - The comment above `app_canary` is rewritten: the dead-man guards the freeze window, not app
     health.
6. **`cleanup()` records one outcome marker on every non-zero exit.** The marker is
   `SOLEUR_WORKSPACES_LUKS_DEADMAN … result=cutover_aborted outcome=<x>` on the existing
   `luks-monitor` tag. No new state-file keys: the review found they had no reader between
   installer fires, while Better Stack and Sentry are readable on demand.
   - **Pre-canary with the freeze or flip held:** it runs `rollback`. The outcome is
     `rolled_back` if `findmnt` then shows a non-mapper source at `$MOUNT`, else
     `rollback_remount_failed`.
   - **`CANARY_OK=1` (post-canary):** it rolls FORWARD on the LUKS mount, but only after it
     re-asserts `findmnt -no SOURCE "$MOUNT"` equals `$MAPPER`. `resume_writers` is guarded only
     by `mountpoint -q`, not by device identity (verify-the-negative sweep).
     - It then runs `docker start` with its exit status checked; a failure emits
       `cleanup_docker_start_failed`.
     - Then `resume_writers`.
     - This covers a death between `CANARY_OK=1` and the end of `resume_writers` (architecture
       review #1). The main body's own `docker start` stays unchecked, as today; the roll-forward
       is the backstop.
     - If the mapper re-assert fails, it does not roll forward. It emits
       `cleanup_mount_not_mapper` and leaves the app down: that is a page, not a silent start. The outcome is
     `post_canary_luks_retained`, and it calls `emit_drift cutover_aborted_post_canary` (fatal).
     That matches the existing `sentry_alert.workspaces_luks_drift` filter in
     `apps/web-platform/infra/sentry/issue-alerts.tf` (`feature eq workspaces-luks` AND
     `op eq workspaces-luks-drift`; `workspaces-luks-emit.sh` hard-codes both). The reason goes
     in a tag. All reasons group into one Sentry issue (135268270), so the runbook notes that
     this issue must never be archived (observability review).
   - **`DEADMAN_ARMED=1`, nothing frozen (an arm-verification failure):** it runs
     `disarm_dead_man arm_aborted`. The outcome is `arm_aborted`.
   - **Otherwise:** the outcome is `pre_freeze`.
   - **Accepted residual:** a SIGKILL of the host-side script after the host-canary disarm leaves
     nothing armed and pages nobody. An SSH drop delivers SIGHUP, and SIGHUP runs the EXIT trap
     (measured by spec-flow, rc=129). A watchdog timer for SIGKILL alone is cut as
     disproportionate.
   - **A dead-man fire now pages** (observability review): a new
     `logtail_exploration_alert.workspaces_luks_deadman_fired` in
     `apps/web-platform/infra/betterstack-logs-alerts.tf`. Its predicate is
     `SYSLOG_IDENTIFIER='luks-monitor'`, `host_name='soleur-web-platform'` and the message
     containing `op=workspaces-luks-deadman result=fired`, with the paging semantics copied from
     `monitor_send_failed` and ADR-218. It adds a sibling `*-alert.test.sh` in
     `apps/web-platform/test/infra/`, following `inngest-luks-wrong-volume-alert.test.sh`.
   - Today an unattended fire (SIGKILL residual, or any future path) writes only Better Stack
     rows, and nothing alerts on them: that is the #6812 six-hour blind spot. No alert is added
     for `cutover_aborted` or `arm_failed`, because Sentry already pages those (it would double
     the page).
7. **The dead-man fire command is unchanged** (T12/T12b/T12c). The green-path log line changes:
   the C15 boot-path instruction is replaced by a pointer to the new fstab issue, because the
   plan's fstab finding shows a restart sends web-1 to emergency mode.

In `apps/web-platform/infra/workspaces-luks.tf` (`terraform_data.luks_monitor_install`):

8. **Add a read-only forensic `remote-exec` step BEFORE the exit-17 arm step,** so a live freeze
   cannot suppress it.
   - Its list is `locals { luks_monitor_forensic_print = [ … ] }`, referenced as
     `inline = local.luks_monitor_forensic_print`.
   - `join("\n", local.luks_monitor_forensic_print)` is added to `triggers_replace`, so this merge
     re-fires the installer once. A re-fire is idempotent: files are redelivered byte-identical,
     the DSN line is rewritten identically, and there is one extra probe kick.
   - The coupling is recorded in the ADR-119 addendum: any later edit to the print re-delivers
     the installer.
   - The step references no `var.*`. Every line uses an `echo "<label>=$( … || echo none)"` or
     `… || true` form, so a missing value can neither fail the step nor taint the resource.
   - It prints:
     - both dead-man units, one property per call:
       `LoadState ActiveState SubState Result LastTriggerUSec ExecMainStartTimestamp ExecMainExitTimestamp ExecMainStatus InvocationID`;
     - the loaded service's `ExecStart` handled in exactly two ways (security review):
       - `fired_cmd=yes|no`, from `grep -q result=fired`;
       - the sha256 of the `argv[]` portion only. The full property embeds `start_time`/`pid`
         and changes every run.
       - Or `exec=not-loaded`. Never the command itself.
     - `uptime -s`;
     - the `/mnt/data` fstab entry, selected with `awk '$1 !~ /^#/ && $2 == "/mnt/data"'`, its
       options field restricted to `[A-Za-z0-9,=._-]` or printed as `<redacted-options>`;
     - a COUNT of `^workspaces` lines in `/etc/crypttab`;
     - `reboot-required=yes|no`;
     - `automatic-reboot=true|false|unset`, from
       `apt-config shell AR Unattended-Upgrade::Automatic-Reboot` (one key; a full dump prints any
       proxy credentials).
   - **No `journalctl` tail.** A transient unit's journal echoes its command line and possibly
     personal data into the public Actions log (four review seats). The manager-memory properties
     answer H1/H2 without it.
   - Never add a read of `/etc/default/luks-monitor` beyond the existing counts. The DIAG_OK deny
     list in `luks-monitor-install.test.sh` gains: a `-p ExecStart` without the hash or
     `grep -q` pipe, `systemctl cat`, a `systemctl show` with no `-p`, `cat /etc/fstab`,
     `apt-config dump`, and `journalctl`.

Tests (RED first, `cq-write-failing-tests-before`):

9. `apps/web-platform/infra/workspaces-luks-harness.sh`:
   - a per-unit, per-property `systemctl show` stub. The unit is parsed in any argv position.
     Values are sequenced through the existing file-backed `_seq_next`, keyed
     `show.<unit>.<prop>`, because a shell counter never advances inside `$( )`. The knobs are
     `DEADMAN_TIMER_SUBSTATES`, `DEADMAN_SVC_ACTIVESTATES` and `DEADMAN_TIMER_LASTTRIGGER`, with
     the last one **defaulting to empty**. Every other `show` keeps `${STOP_RESULT:-success}`;
   - **garbage-collection modelling, last event wins per exact unit** (test-design review):
     - a `systemctl stop|reset-failed` naming `X.timer` or `X.service` puts that unit into
       `LoadState=not-found` with empty properties;
     - a later `systemd-run --unit=X` revives both units, and the sequenced knobs apply again;
     - a bare `workspaces-luks-deadman` means the service;
     - a `DEADMAN_STOP_INEFFECTIVE=1` knob keeps the timer `waiting` after a stop, so check (c) can
       fail;
   - `SYSTEMD_RUN_RC` / `SYSTEMD_RUN_OUT` knobs;
   - the `logger` stub also runs `rec "logger $*"`, and the `emit_drift` stub records
     `rec "EMIT_DRIFT $1"` as well, so call, marker and drift ORDER is assertable in one file.
     Every existing `has`/`idx` pattern is re-anchored (`^mount[[:space:]]`, not `mount`) so the added
     `logger` lines cannot match it;
   - a stub self-test: `systemctl show workspaces-luks-deadman.service -p SubState --value`,
     run with `DEADMAN_TIMER_SUBSTATES=waiting`, must NOT print `waiting`. This proves the stub is
     keyed on the unit;
   - an **instrument control**: the pass count of every existing suite is compared against the
     unchanged harness before any new verdict is trusted.
10. `apps/web-platform/infra/workspaces-luks-freeze.test.sh`:
    - new cases T30–T38 (see Test Scenarios);
    - T25/T25b inverted: `disarm_dead_man host_canary_passed` follows the host canary's
      `not_mounted` assert and precedes `CANARY_OK=1` and `docker start "$CONTAINER"`;
    - T25c: no `disarm_dead_man` in the main body after `docker start`;
    - T25d: `arm_dead_man` precedes `FREEZE_HELD=1`. The two move to SEPARATE lines, and the test
      requires that, because a same-line pair defeats a line-number comparison;
    - the AC8 comment reworded, with its bound kept.
    - Flags are set INSIDE the invocation string, always including `DRY_RUN=0`: the script
      defaults `DRY_RUN=1`, and `arm_dead_man`/`rollback` return early under it. Sourcing also
      resets every global.
    - Cleanup cases inject a distinctive status, `(exit 9)`, and assert `CASE_RC=9`, so an
      injected failure cannot be confused with a `die` inside `cleanup` (as T23 already does).
    - Arm-then-cleanup cases use `trap cleanup EXIT; …; arm_dead_man`, because the `die` stub
      exits the subshell.
11. `apps/web-platform/infra/luks-monitor.test.sh` (x): replace the
    `result=disarmed reason=canary_passed` literal. Assert the disarm marker template, each
    reason's call site (`disarm_dead_man host_canary_passed`, `disarm_dead_man rollback_engaged`),
    and the arm-failure and `cutover_aborted` markers.
12. `apps/web-platform/infra/luks-monitor-install.test.sh`:
    - teach `inline_raw()` to resolve `inline = local.NAME`;
    - G-rows: the forensic step precedes the exit-17 step, its local is inside `triggers_replace`,
      the property names are present, no `journalctl` and no `/etc/default/luks-monitor` read
      beyond counts, and every forensic line carries an `|| true`/`echo` guard;
    - mutation rows that must go RED: the local dropped from `triggers_replace`, the step moved
      after the arm step, and a `journalctl` line added.
13. `tests/scripts/test-workspaces-luks-cutover-gate.sh` Q3/Q4 (a missed consumer, found by the
    architecture review): it calls the real `arm_dead_man` with only `systemd-run` and `logger`
    stubbed. Stub `systemctl`, with the timer reading `waiting` after the run, and stub
    `emit_drift`. More generally, every suite that `git grep -l workspaces-cutover.sh` lists must
    stay green (AC2).
14. **One real-systemd case, folded into the existing privileged
    `apps/web-platform/infra/workspaces-luks-loopback.test.sh`.** It is already wired as
    `sudo bash …` in `.github/workflows/infra-validation.yml`, so no new file and no registry
    work. It uses a throwaway unit name with plain `systemd-run` (not `arm_dead_man`) and measures
    the one load-bearing assumption:
    - a loaded failed transient service makes a same-name `systemd-run` exit non-zero, AND its
      stderr names the collision ("already loaded" or "fragment"). A bare non-zero could be a bus
      or permission error;
    - after the script's exact clear-out (stop the timer, then `reset-failed` both units), the
      same-name `systemd-run` succeeds within the bounded attempts and reads `SubState=waiting`;
    - it records, as measurements for the fakes, the unit states after a transient service
      finishes (`LoadState`, `SubState`, `LastTriggerUSec` on the timer).

    The research sources disagree here: systemd.timer(5) says `RemainAfterElapse=yes` keeps an
    elapsed timer loaded, while web-1's print read the timer `inactive/dead`. This case settles it
    on systemd 255. After its EXIT trap it asserts that no throwaway unit is left loaded.

    An EXIT trap stops and resets the throwaway unit. With no usable systemd the case reports
    `SYSTEMD_UNAVAILABLE` and fails, never passes.

Docs:

15. **ADR-119.** Add `## Addendum (2026-09-28): the dead-man guards the freeze window only (#9045)`
    before `## References`. It records:
    - the decision and the rejected alternatives;
    - the roll-forward on a post-canary abort;
    - H1/H2 and their discriminator, and where the verdict lands (a #9045 comment);
    - the print/installer coupling.

    In-place markers go under "Known gap, not fixed here" (`Superseded`), and under the review
    amendment's elapsed-timer claim and its fstab clause (`Qualified`).
16. **Runbook** `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`:
    - rewrite the §3 blockquote;
    - replace step 4's "reboot web-1 once" (C15) with "blocked on #<fstab issue>";
    - add triage rows, each with a no-SSH read (the Sentry event, or
      `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 2h --grep SOLEUR_WORKSPACES_LUKS_DEADMAN`)
      and an expected time to recovery:
      - `deadman_already_armed`: do not re-dispatch while a timer waits. It fires within
        `DEAD_MAN_MIN`, and its markers show the outcome. Then read the next verify run and
        re-dispatch;
      - `deadman_arm_failed`: re-dispatch once, since the `reset-failed` already ran. On a second
        failure, escalate;
      - `deadman_disarm_failed`, `deadman_fired_before_disarm`: `cleanup` has already rolled back
        pre-`docker start`. Verify with the verify workflow;
      - `cutover_aborted_post_canary`: **fix-forward only.** The LUKS mount is authoritative, and
        `cleanup` has already restarted the app on it. `rollback=true` would strand every write
        since `docker start` on the LUKS volume (ADR-119 §(b)): reconcilable, but never the
        first move (CTO devex, spec-flow P0, Kieran P1).
17. **ADR-154.** Add a `Re-examined 2026-09-28 (#9045)` note: re-read `cx33` stock via
    `GET /v1/datacenters` at work time, as #8705 and #8706 did. The installer re-fire is another
    in-place web-1 change.

### Phase 3 — fstab: measure, correct the record, file the coupled fix

1. Phase 2 step 8 takes the measurements: the full fstab line, the crypttab count, uptime,
   reboot-required and Automatic-Reboot.
2. Phase 2 step 15 carries the ADR-119 in-place qualification.
3. **Before the PR ships, file a new P1 issue (CPO condition 3):** "infra: a web-1 reboot takes the
   site down — /mnt/data fstab is a literal glob, there is no boot-time unlock, and the ADR-119
   §(e) mount gate was never delivered".
   - The body states the hazard in plain words: after a restart the server does not come back, and
      every user's workspace stays offline until it is repaired through the provider's console.
   - It carries the measured facts.
   - It proposes a coupled fix, applied together through a Terraform-owned installer: an fstab
      line naming the mapper with `nofail`; a crypttab entry plus a key-fetch unlock modelled on
      `cloud-init-git-data.yml`; and the `chattr +i` root-inode gate applied through a bind peek.
   - Re-evaluation trigger: "before any planned web-1 reboot, and immediately if the forensic print
      shows `/var/run/reboot-required` or `Automatic-Reboot "true"`".
   - Milestone per `knowledge-base/product/roadmap.md`, linked to #6604 and #6931.

### Phase 4 — #8706: date-gated follow-through (post-merge, not a blocker)

On or after 2026-10-01T01:00Z, the sweeper runs
`scripts/followthroughs/luks-monitor-host-timer-8706.sh`. The post-merge check is
`gh issue view 8706 --json state,closedAt` plus the sweeper comment. If #8706 is still open after
the 2026-10-01 sweep, run the script under `doppler run -p soleur -c prd_terraform --` and diagnose
from its exit code: 0 PASS, 1 FAIL, 2 TRANSIENT. The script's queries already union the hot table
with the `s3Cluster` archive. This PR carries `Ref #8706` only.

### Phase 5 — post-merge verification (no SSH)

1. Watch the `apply-web-platform-infra.yml` run for the merge commit.
   `terraform_data.luks_monitor_install` must re-fire (its triggers changed), with no exit 17.
2. Read the forensic print with `gh run view <id> --log`. Record the H1/H2 verdict, the fstab
   line, uptime, reboot-required and Automatic-Reboot on #9045 and on the new fstab issue. Escalate
   the fstab issue at once if `Automatic-Reboot "true"` or reboot-required is present.
3. In the same print, confirm `luks-monitor.timer` is still `enabled`/`active`. Confirm
   `soleur-luks-monitor-host-timer-dark-prd` has not triggered.

## Files to Edit

- `apps/web-platform/infra/workspaces-cutover.sh`: `arm_dead_man`, `disarm_dead_man`, `rollback`, `cleanup`, where the main body arms and disarms, and the comments.
- `apps/web-platform/infra/workspaces-luks-harness.sh`: stub knobs for `systemctl show` and `systemd-run`.
- `apps/web-platform/infra/workspaces-luks-freeze.test.sh`: T25/T25b inverted, T30–T38 added, AC8 comment.
- `apps/web-platform/infra/luks-monitor.test.sh`: the (x) marker set.
- `apps/web-platform/infra/workspaces-luks.tf`: the forensic step, its local, and the trigger.
- `apps/web-platform/infra/luks-monitor-install.test.sh`: `inline_raw()` resolves locals, plus the new G-rows and mutations.
- `apps/web-platform/infra/workspaces-luks-loopback.test.sh`: one real-systemd case (Phase 2 step 14). It is already wired as a privileged step in `infra-validation.yml`.
- `tests/scripts/test-workspaces-luks-cutover-gate.sh`: Q3/Q4 stubs (Phase 2 step 13).
- `apps/web-platform/infra/betterstack-logs-alerts.tf`: `logtail_exploration_alert.workspaces_luks_deadman_fired` (Phase 2 step 6).
- `knowledge-base/engineering/architecture/decisions/ADR-154-repair-the-credential-channel-not-the-host.md`: the `Re-examined 2026-09-28` note (Phase 2 step 17).
- `plugins/soleur/test/preflight-discoverability-test.test.ts`: bump `BASELINE_DECLARED_PROBES` 32 → 33, with the PLACEMENT/TRUTH/NO SUBSTITUTE comment its failure text asks for. This plan's `discoverability_test` declares `credentials_required`, and committing the plan moves that repo-global ratchet.
- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`: the addendum and the in-place markers.
- `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`: the addendum, written only after the Phase 1 deletion.
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`: the §3 blockquote, the step-4 reboot line, and the new triage rows.
- `knowledge-base/legal/audits/2026-09-8209-prior-exposure-assessment.md`, `knowledge-base/legal/breach-register.md` and `knowledge-base/legal/compliance-posture.md`: edited only after the Phase 1 deletion.

## Files to Create

- `apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh`: the alert's predicate test.
- `scripts/followthroughs/snapshot-411798619-expiry-8734.sh` plus its `.test.sh`, ONLY on the no-go-ahead branch of Phase 1.

The real-systemd case folds into the existing loopback suite. The deletion script is a session scratch file, as in PR-4b, and is not committed.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Keep the dead-man armed across `app_canary` (today's intent) | An unattended revert after `docker start` strands writes (ADR-119 §(b); the 2026-07-20 incident). The dead-man guards the freeze window; app health is attended. |
| Keep it armed only for data-shaped `readyz` failures (`populated=false`) | C1 byte-identity, G3 and the host-canary device anchor already certify the data before the door. What remains is an automated revert that still strands writes, bought with a reason classifier on the path nobody watches. |
| A fire-time guard inside the dead-man's `sh -c` that skips the revert when `CANARY_OK=1` | `$STATE_FILE` persists across runs. A stale `CANARY_OK` from an earlier run would suppress a legitimate pre-canary revert, unless the header UUID were compared inside the inline string. Disarming at the door is simpler and covers every path. |
| Clear web-1's failed dead-man unit now through Terraform | It is a host mutation with no functional gain: the fixed arm clears the unit, with its evidence, before any re-cut. Clearing it now would also destroy the evidence before the print reads it. |
| Rewrite fstab to the mapper in this PR | Without the §(e) gate and a boot unlock, a reboot would resurrect the app over a bare root-disk `/mnt/data`. That trades today's fail-closed emergency mode for silent divergence. The coupled fix is filed as its own issue. |
| Wait for SOAK CLEAN before deleting 411798619 | SOAK CLEAN is likely unreachable before the 2026-10-06 horizon. The image's rollback value is about nil, and the retention cost accrues every day. |
| Rotate `SUPABASE_SERVICE_ROLE_KEY` anyway | The issue's rule does not fire on the evidence. A service-role rotation is a user-facing production change that carries its own risk, and a CLEAN limb does not justify it (CLO). |
| Edit `scripts/followthroughs/inngest-soak-6178.sh` `SNAPSHOTS` on `main` | #8626 already rewrites that line. Editing it here creates a conflict over a line whose probe refuses to run past 2026-10-06 anyway. A comment on #6178 carries the fact instead. |
| Hash a separate state-print script file instead of a `local` | It breaks `luks-monitor-install.test.sh`'s four-delivered-files parity, and it moves the lines outside the DIAG_OK leak check (Terraform review). |

## Non-Goals

- Detaching or wiping the retained plaintext volume 105149570. That belongs to #6604's PR 3, and its soak has already authorized the wipe.
- Any web-1 host mutation beyond re-firing the existing installer. No fstab, crypttab or chattr change.
- #8626 (blocked on #8095) and AC-0c-i.
- #8209's L3 limb as a whole. It stays INCONCLUSIVE; this PR adds only the image-use sub-limb.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/workspaces-luks.tf`, `terraform_data.luks_monitor_install`: one new
  read-only `remote-exec` step, placed before the exit-17 arm step, and one new `locals` list folded
  into `triggers_replace`. No new resource. No new `-target=` line in
  `.github/workflows/apply-web-platform-infra.yml`. No new variable or provider.
  `web-host-provisioner-parity.test.sh` stays unchanged: its connection-block floor is untouched,
  and read-only lines add no install destinations.
- The snapshot is deleted with a single API `DELETE`, not through Terraform. No Terraform resource
  manages snapshots: `scripts/cutover-inngest.sh` `op=backup` creates them over the API, and the
  three sibling images were deleted the same way (PR-4b).

### Apply path

(b) The existing per-merge SSH apply re-fires the existing installer. The only host-side effects
are the idempotent redelivery the resource was designed for and one `--no-block` probe run. No
downtime. The blast radius is one tainted resource if a step fails; the next apply re-fires it.

### Distinctness / drift safeguards

- The in-place change on web-1 rests on ADR-154's standing web-1 exception, as #8706 did.
  `hr-prod-host-config-change-immutable-redeploy` is deviated from only in its already-recorded
  form. `cx33` is still unorderable (ADR-154, re-measured 2026-09-27).
- The forensic step reads host state and changes nothing.

### Vendor-tier reality check

Not applicable. No new vendor resource.

## Architecture Decision (ADR/C4)

### ADR

- **Amend ADR-119** with an appended addendum (2026-09-28, #9045): "the dead-man guards the freeze
  window only; it is disarmed at the host-canary pass, before `docker start`". This is a corollary
  of §(b), and it reverses the cutover's documented intent to keep the dead-man armed across
  `app_canary`. A post-canary abort now rolls forward on the LUKS mount. The addendum also carries in-place Superseded/Qualified markers on the 2026-09-27
  addendum's "Known gap" paragraph, its elapsed-timer claim and its fstab clause. It is written via
  the `soleur:architecture` conventions (addendum, not a new ADR: it narrows an existing ADR's
  mechanism and adds no new decision surface).
- **Amend ADR-100** with an appended addendum (2026-09-28, #8734): "411798619 is released before
  SOAK CLEAN". It departs from the 2026-09-19 addendum's verb order for one image, with the
  rollback value weighed. It is written only after the deletion executes.
  - The #8626 branch carries an unmerged 2026-09-23 ADR-100 addendum that retains 411798619 until
    SOAK CLEAN. A plain tail-append would put "retain" after "released".
  - This addendum therefore names that pending clause and supersedes it.
  - The #8626 comment (Phase 1 step 3) prescribes the rebase ordering: 09-23 above 09-28, with a
    `Superseded` marker.
  - No new ADR is created, so no ordinal is at stake.

### C4 views

No C4 impact. Checked against all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):

- **External actors:** none added. The operator is already modelled.
- **External systems:** Hetzner (`hetzner`), Sentry and Better Stack are already modelled. The
  snapshot image is not modelled; `grep -i snapshot` in `model.c4` finds only the unrelated
  `snapshotGuard` component. Its deletion changes no element.
- **Containers and data stores:** the `workspacesVolume` element and its `hetzner -> workspacesVolume`
  edge are unchanged. Its description's history clause ("an earlier 2026-07-20 cutover attempt …")
  stays true.
- **Access relationships:** unchanged. The dead-man is a host-internal mechanism, not a modelled
  element.

The work phase backs this conclusion with a green `bash plugins/soleur/test/c4-count-parity.test.sh`
run (no edge cardinality moves).

### Sequencing

Both addenda describe the state that exists at merge. The ADR-100 addendum and the legal records
are committed only after the Phase 1 DELETE has run and been verified.

## User-Brand Impact

- **If this lands broken, the user experiences:** a future `/workspaces` re-cut whose disarm
  silently fails after `docker start`. The dead-man then reverts `/mnt/data` to the stale plaintext
  volume, and the user's most recent workspace edits (commits, files written since the container
  started) vanish from their workspace. That is the 2026-07-20 shape: 27 minutes of writes
  stranded, and encryption silently off.
- **If this lands broken, the user experiences:** a broken forensic step in
  `terraform_data.luks_monitor_install` taints the installer. The nightly encryption self-check then
  stays un-re-armed until the next apply, and the host-timer-dark alert fires after about 27 h.
- **If this leaks, the user's data is exposed via:** retained image 411798619 until it is
  deleted. Anyone holding `HCLOUD_TOKEN` can create a server from it and read:
  - the 2026-07-23 `SUPABASE_SERVICE_ROLE_KEY` (RLS bypass on every user's rows);
  - `BYOK_ENCRYPTION_KEY` (decrypts every user's stored third-party API keys);
  - `STRIPE_SECRET_KEY` (charges and refunds on customers' saved payment methods);
  - `GITHUB_APP_PRIVATE_KEY` (write access to every installed user's repos);
  - journald email addresses.

  Dispositions are in Phase 1 step 5: the image route is closed by the deletion, and the token
  route is owed under a new issue (and, for the App key, under #8209). If the deletion does not
  happen in-session, the 2026-10-06 follow-through probe enforces the deadline.
- **If this leaks, the user's data is exposed via:** the forensic print in the public Actions log.
  It is bounded to unit properties, an argv hash, counts, the exact `/mnt/data` fstab entry and
  three single-value host flags. It never prints a command body, an env-file line, crypttab
  contents, an apt config dump or a state-file value.
- **If this lands broken, the user experiences:** nothing from the merge-time installer re-fire.
  Its one probe run is read-only (`luks-monitor.sh` header), so the worst case is a false page.
- **Accepted and tracked, not fixed here:** any web-1 reboot (provider maintenance, kernel
  panic) currently lands in emergency mode, taking every user's workspace offline until repaired
  from the provider console. Detection is the existing uptime monitoring of app.soleur.ai. It is
  tracked as P1 in the new fstab issue (Phase 3), which carries the console-recovery procedure and
  the escalation rule when the forensic print shows `reboot-required=yes` or
  `automatic-reboot=true`.
- **Brand-survival threshold:** `single-user incident`

`requires_cpo_signoff: true`. The CPO signed off at plan time (2026-09-28) with four conditions,
each folded in:

1. Evidence is recorded before the deletion, and the ADR-100 rollback loss is weighed (Phase 1
   steps 1 and 4).
2. #8734 stays open until the CLO concurs in writing on no-rotation and no-notification. The PR says
   `Ref #8734`, and #8734 closes manually after the records land.
3. The fstab issue is filed as P1 before ship (Phase 3).
4. A post-canary abort pages through Sentry fatal, and the runbook states a time to recovery
   (Phase 2 steps 6 and 16).

`soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_WORKSPACES_LUKS_DEADMAN markers (result=armed|arm_refused|arm_failed|disarmed|disarm_failed|not_armed|cutover_aborted|fired|ok|fail) on the Vector-allowlisted luks-monitor syslog tag, shipped to Better Stack; plus terraform_data.luks_monitor_install's forensic print in the apply log on every installer fire"
  cadence: "per cutover run (freeze arm, host-canary disarm, every abort); per installer fire (a merge that changes a trigger)"
  alert_target: "Sentry issue alert on feature=workspaces-luks AND op IS_IN workspaces-luks-drift (emit_drift, level fatal) for deadman_already_armed, deadman_arm_failed, deadman_disarm_failed and cutover_aborted_post_canary"
  configured_in: "apps/web-platform/infra/workspaces-cutover.sh (arm_dead_man, disarm_dead_man, cleanup); apps/web-platform/infra/sentry/issue-alerts.tf; apps/web-platform/infra/workspaces-luks.tf (luks_monitor_install forensic step)"

error_reporting:
  destination: "Sentry via workspaces-luks-emit.sh; the DSN is the SOLEUR_SENTRY_DSN line of /etc/default/luks-monitor, delivered by terraform_data.luks_monitor_install"
  fail_loud: "die prints '[workspaces-cutover] FATAL: ...' in the workspaces-luks-cutover.yml run log AND a Sentry fatal drift event with the reason slug; a lost Sentry send logs SOLEUR_WORKSPACES_LUKS_SEND_FAILED, which pages through logtail_exploration_alert.monitor_send_failed"

failure_modes:
  - mode: "systemd-run refuses the arm (a stale loaded unit, the H1 shape), or the timer never reads waiting"
    detection: "arm_dead_man checks the exit status and a bounded SubState=waiting check; emits result=arm_failed (echo + logger) and drift deadman_arm_failed, then dies before FREEZE_HELD=1; cleanup disarms any timer it created"
    alert_route: "direct Sentry envelope (workspaces-luks-emit.sh -> sentry_alert.workspaces_luks_drift, fatal) + layer 3 (vector journald -> Better Stack, luks-monitor tag) + layer 6 (workflow run log: die FATAL in workspaces-luks-cutover.yml)"
  - mode: "a dead-man timer is already waiting, or a fire is in progress, when a cutover arms"
    detection: "arm_dead_man pre-check; result=arm_refused + drift deadman_already_armed"
    alert_route: "direct Sentry envelope (sentry_alert.workspaces_luks_drift, fatal) + layer 3 (vector journald -> Better Stack, luks-monitor tag) + layer 6 (workflow run log: die FATAL in workspaces-luks-cutover.yml)"
  - mode: "the host canary finds a population mismatch, or the disarm does not take (timer still waiting, service active, fire already started)"
    detection: "host_canary_workspace_count_mismatch; disarm_dead_man checks (a)/(b)/(c) plus the caller's findmnt re-assert (deadman_disarm_failed / deadman_fired_before_disarm); the main body dies before CANARY_OK=1 and cleanup rolls back before docker start"
    alert_route: "direct Sentry envelope (sentry_alert.workspaces_luks_drift, fatal) + layer 3 (vector journald -> Better Stack) + layer 6 (workflow run log: die FATAL in workspaces-luks-cutover.yml)"
  - mode: "the cutover aborts after the host canary (app canary, queue check, monitor arm)"
    detection: "cleanup re-asserts the mapper, rolls forward (checked docker start + resume_writers), logs result=cutover_aborted outcome=post_canary_luks_retained and emits drift cutover_aborted_post_canary (or cleanup_mount_not_mapper / cleanup_docker_start_failed)"
    alert_route: "direct Sentry envelope (sentry_alert.workspaces_luks_drift, fatal; the runbook row gives fix-forward recovery and time to recovery) + layer 3 (vector journald -> Better Stack) + layer 6 (workflow run log: die FATAL in workspaces-luks-cutover.yml)"
  - mode: "a pre-canary rollback cannot remount the plaintext"
    detection: "existing emit_drift rollback_remount_failed and rollback_engaged in rollback(); outcome marker rollback_remount_failed"
    alert_route: "direct Sentry envelope (sentry_alert.workspaces_luks_drift, fatal) + layer 3 (vector journald -> Better Stack) + layer 6 (workflow run log: die FATAL in workspaces-luks-cutover.yml)"
  - mode: "the dead-man fires unattended (SIGKILL residual, or any path that leaves it armed)"
    detection: "the fire command's own result=fired marker, matched by logtail_exploration_alert.workspaces_luks_deadman_fired"
    alert_route: "layer 3 (vector journald -> Better Stack logs alert, paging per ADR-218)"
  - mode: "the installer's forensic step fails"
    detection: "red SSH step in apply-web-platform-infra.yml; the resource taints and re-fires on the next apply"
    alert_route: "layer 6 (workflow run log, apply-web-platform-infra.yml) + layer 3 (soleur-luks-monitor-host-timer-dark-prd fires if the timer stays unarmed for about 27 h)"
logs:
  where: "web-1 journald (SYSLOG_IDENTIFIER=luks-monitor) -> Vector -> Better Stack source soleur-inngest-vector-prd (hot table + s3Cluster archive); GitHub Actions logs of workspaces-luks-cutover.yml and apply-web-platform-infra.yml"
  retention: "Better Stack archive: earliest retained row measured 2026-08-13 on 2026-09-28 (about 6-7 weeks); Actions logs 90 days; web-1 journald bounded by SystemMaxUse=1G (journald-soleur.conf); the unit properties the forensic print reads live in systemd manager memory until reboot or reset-failed"

discoverability_test:
  command: bash scripts/betterstack-query.sh --since 2d --grep 'OK: /mnt/data is LUKS-backed'
  expected_output: "LUKS-backed"
  credentials_required: "BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD from Doppler soleur/prd_terraform, read-only ClickHouse connection — the new dead-man markers share the luks-monitor tag path with the nightly OK row, which proves that path live; dead-man rows themselves exist only during a cutover run, and the warehouse has no unauthenticated reader"
```

## Encryption Posture

```yaml
at_rest:
  - store: "hetzner image 411798619 (snapshot of web-1's root disk, 2026-07-23; ledger row hetzner.web1_inngest_cutover_snapshots on the unmerged #8626 branch)"
    mechanism: plaintext-exception
    evidence: "GET /v1/images/411798619 on 2026-09-28: type=snapshot created_from=123931471; web-1's root disk carries no guest-side encryption (the #8626 ledger scope, ADR-119 Context)"
    defends_against: "nothing at rest beyond Hetzner project access control"
    does_not_defend: "any holder of HCLOUD_TOKEN creating or rebuilding a server from the image and reading the prd values, Doppler fallback files and journald email addresses it holds"
    disclosed_as: not-publicly-claimed
    live_verification: "available: GET /v1/images/411798619 returns 404 not_found after the Phase 1 deletion"
  - store: "hcloud_volume.workspaces_luks (web-1 /mnt/data, soleur-web-platform-data-luks 106443278)"
    mechanism: luks
    evidence: "device binding in apps/web-platform/infra/workspaces-luks.tf; live mnt-data.mount What=/dev/mapper/workspaces (apply run 36340195638)"
    defends_against: "a seized or RMA'd disk; a raw provider-side copy of the LUKS volume"
    does_not_defend: "root on the unlocked host; a leaked prd_workspaces_luks token reading WORKSPACES_LUKS_KEY; the retained plaintext volume 105149570, still attached to web-1 until #6604's PR 3 wipes it"
    disclosed_as: "docs/legal/privacy-policy.md, docs/legal/gdpr-policy.md and docs/legal/data-protection-disclosure.md — the LUKS-at-rest statements ADR-119's Context names"
    live_verification: "available: luks-monitor.timer host rows (soleur-luks-monitor-host-timer-dark-prd) and workspaces-luks-verify.yml"
in_transit: []   # no new cross-component connection
exception:
  justification: "the image predates this plan; this plan removes it, and no new plaintext store is created"
  tracking_issue: "#8734"
  reevaluate_when: "the Phase 1 DELETE runs (the exception then lapses), or 2026-10-06 arrives with the image still present (rotation becomes mandatory)"
  expires_on: 2026-10-06
```

No new state-file keys are added. Outcomes are recorded as markers only (Phase 2 step 6).

## Guard Contract

### Guard 1 — the dead-man arm is verified, and a failed arm never outlives the run

**Property.** `result=armed` is emitted, and the freeze flag is set, only if the timer is
observably `waiting` after this run's own `systemd-run`. Any timer this run created is disarmed on
every exit path that does not reach the host-canary disarm.

**Assembly.**

- The one arm site is `arm_dead_man()` in `apps/web-platform/infra/workspaces-cutover.sh`. The
  chokepoint every arm passes through: the un-swallowed `systemd-run --on-active … --unit=workspaces-luks-deadman`,
  then `DEADMAN_ARMED=1`, then the bounded `SubState=waiting` check.
- The call site is the main-body line `arm_dead_man; FREEZE_HELD=1`.
- The cleanup site is `cleanup()`'s `DEADMAN_ARMED=1` branch.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `2>/dev/null \|\| true` on the `systemd-run` (`SYSTEMD_RUN_RC=1`) | T31 RED: `result=armed` present, rc 0 |
| 2 | Keep the rc check, delete the `SubState=waiting` check (`SYSTEMD_RUN_RC=0`, `DEADMAN_TIMER_SUBSTATES=dead`). The precondition holds and the property fails | T32 RED |
| 3 | Reorder: move `DEADMAN_ARMED=1` after the waiting check | T32b RED: `cleanup` after a `timer_not_waiting` die records no `disarm_dead_man arm_aborted` |
| 4 | Dispatch: rename `arm_dead_man` so every arm case hits `HARNESS_UNDEFINED` | T30–T33 FAIL. `undef()` makes `ran`/`died` false |
| 5 | Second member: add a second `systemd-run --unit=workspaces-luks-deadman` line with `\|\| true`, after the compliant one | T39 RED. It counts un-commented logical command lines, continuations folded, and asserts exactly one with no swallow |
| 6 | Reorder: move `arm_dead_man` after `FREEZE_HELD=1` | T25d RED |
| 7 | Remove the live-timer refusal | T33 RED: `systemctl stop workspaces-luks-deadman.timer` recorded while the timer is `waiting` |

**Harness rows:**

| # | Suite edit or input | Expected |
|---|---|---|
| H1 | Make the `systemctl show` stub ignore the unit operand | The stub self-test goes RED: the service's `SubState` answers `waiting` under `DEADMAN_TIMER_SUBSTATES=waiting`. T33 alone cannot see it, because the code reads different properties per unit |
| H2 | Must-PASS, non-canonical: `DEADMAN_TIMER_SUBSTATES="dead waiting"` (waiting on the second read) | T30b PASS |

**Anchor.** No stored value. The rows read the live script.

### Guard 2 — one disarm, at the host-canary door

**Property.** In the main body, the dead-man is disarmed exactly once. That disarm comes after the
last host-canary assert and before both `CANARY_OK=1` and `docker start "$CONTAINER"`. No
`disarm_dead_man` follows `docker start`. A failed disarm never `exit`s from inside `rollback()`.

**Assembly.**

- Main-body call sites: the region after the sourced-detection guard, extracted as T25's
  `$T25BODY.main`.
- Every other `disarm_dead_man` call site is outside the main body: `rollback()`
  (`rollback_engaged`, gated on `DEADMAN_ARMED`) and `cleanup()` (`arm_aborted`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert: move the disarm back after `app_canary` | T25' RED |
| 2 | Second member: keep the compliant disarm and add another `disarm_dead_man` after `docker start` | T25c (negative sentinel) RED |
| 3 | Dispatch: rename the call to `disarm_deadman`, so the extractor finds zero disarm lines | T25' FAILS "not found". It never passes on an empty extraction |
| 4 | Reorder: move `CANARY_OK=1` above the disarm | T25' RED. A failed disarm would then skip rollback |
| 5 | Make `disarm_dead_man` call `die` on a failed verification | T35 RED: `rollback()` stops halfway with no remount or `docker start` recorded |
| 6 | Make `rollback()` pass `canary_passed` again | T36b RED (the marker reason must be `rollback_engaged`) |
| 7 | Reorder: move read (a) `LastTriggerUSec` after the timer `stop` | T36a RED. The GC-modelling stub empties the unit after the stop, so a fired timer reads as never-fired and reports `disarmed` |
| 7b | Reorder: move read (b) service `ActiveState` before the timer `stop` | T36d RED. A service that turns `activating` only after the stop, sequenced `inactive activating`, must fail `check=b` |
| 8 | Delete the post-disarm `findmnt` re-assert in the main body | T36c RED |

**Harness rows:**

| # | Suite edit or input | Expected |
|---|---|---|
| H1 | Point the extractor at the whole file instead of the main body | Rows 1–2 misfire on `rollback()`'s call. T25c's own positive control (a synthesized main body with exactly one compliant disarm must PASS) catches this |
| H2 | Must-PASS, non-canonical: the disarm line carries a trailing comment and different indentation | T25' PASS |

**Anchor.** No stored value.

### Guard 3 — the forensic print re-fires, and runs before the freeze refusal

**Property.** Every edit to the installer's forensic print re-fires
`terraform_data.luks_monitor_install`. The print executes before the exit-17 arm step.

**Assembly.**

- `terraform_data.luks_monitor_install` in `apps/web-platform/infra/workspaces-luks.tf`: its
  `triggers_replace` expression and its provisioner order.
- Every `inline = local.<name>` the resource references. The chokepoint is `inline_raw()` in
  `luks-monitor-install.test.sh`, which must resolve locals.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `join("\n", local.luks_monitor_forensic_print)` from `triggers_replace` | G-row RED |
| 2 | Reorder: move the forensic step after the exit-17 arm step | G-row RED |
| 3 | Dispatch: `inline_raw()` returns empty for `inline = local.X` | The row FAILS "no lines resolved". It never passes on emptiness |
| 4 | Second member: add a second `inline = local.other` step whose local is not in `triggers_replace` | G-row RED ("every referenced local is hashed") |
| 5 | Add `cat /etc/default/luks-monitor` to the forensic list | The DIAG_OK leak row RED |

**Harness rows:**

| # | Suite edit or input | Expected |
|---|---|---|
| H1 | Must-PASS: the local's lines reordered | PASS (order within the print is free) |
| H2 | Make the leak check skip local-sourced steps | Row 5 stays green on a real leak. The suite's positive control, a fixture local containing the leak that must FAIL, catches this |

**Anchor.** No stored value.

## Open Code-Review Overlap

None. None of the 86 open `code-review` issues names any path in Files to Edit (checked 2026-09-28
with the two-stage `gh issue list --json` + `jq --arg` query).

## Domain Review

**Domains relevant:** Legal, Engineering, Product

### Legal

**Status:** reviewed (soleur:legal:clo, 2026-09-28)

**Assessment:** "No mandatory rotation" is conditionally sound once three gaps close. The plan
closes all three:

1. Attribute each `create_server` image. Measured: every row carries a `type=image` resource.
2. Re-pull the evidence up to the DELETE instant, with the coverage window starting at 2026-07-23.
3. State in writing why the token-read limb's INCONCLUSIVE does not reach the image route.

The CLO's guidance on each record and credential, all adopted in Phase 1:

- `GITHUB_APP_PRIVATE_KEY`: record "owed under #8209 R5 / R1".
- `STRIPE_SECRET_KEY` token route: file a separate operator-gated issue.
- #8209's L3 as a whole stays INCONCLUSIVE.
- The records get in-cell widening plus Superseded markers.
- The destruction is recorded on PR #8626 at the moment it happens. The Art. 5(2) record stays
  `partial` until #8626 lands.
- No Art. 33/34 change. An unattributable image use would start a fresh 72 h clock.

After the edits, `soleur:legal:legal-compliance-auditor` runs once across the three records and
the #8632 comment.

**gdpr-gate (Phase 2.7, 2026-09-28):** advisory, no Critical findings. `GDPR-Art-5e` (Important) is
covered by Phase 1, with one addition. The Article 30 PA-8 (f) retention amendment for these images
lives only on the #8626 branch, so the PR #8626 comment must say that PA-8 (f) cites this deletion
when #8626 lands. `GDPR-Art-32` (Suggestion) covers the forensic print: before posting the #9045
verdict, check the first real print for anything that looks like personal data. The review
removed its `journalctl` tail for this reason.

### Engineering

**Status:** reviewed (soleur:engineering:cto, 2026-09-28)

**Assessment:** The CTO agrees with the disarm at the host canary and favours H1. Every refinement
the CTO asked for is adopted in Phase 2:

- print `ExecStart` as a hash plus a `result=fired` probe, with `InvocationID` and `LoadState`;
- tolerate exit 5 on stopping the timer (the GC poll and the stale-unit evidence emit were later
  cut by the plan review: the arm fails closed on a lagging GC, and the merge-apply forensic print
  captures the one stale unit that exists);
- `disarm_dead_man` returns a status and never `die`s inside `rollback()`;
- the disarm also verifies that the service is not active after the timer stop (the
  `InvocationID` gate was cut: it is vacuous under GC);
- a `DEADMAN_ARMED` flag lets `cleanup()` disarm on an abort between the arm and the freeze;
- a post-canary abort pages through fatal `emit_drift`;
- T25 is inverted, with a negative sentinel;
- the ADR-119 elapsed-timer claim is corrected;
- fstab gets no host fix here; the forensic print adds reboot-required and Automatic-Reboot;
- the fstab fix is modelled on `cloud-init-git-data.yml`.

The CTO concurs that BYOK is not rotated under #8734, on two conditions: the re-pull at deletion,
and a mandatory rotation issue if the image outlives 2026-10-06. The Terraform review
(soleur:engineering:infra:terraform-architect) moved the forensic print ahead of the exit-17 step,
kept the `local` over a script file, and required `inline_raw()` to resolve locals.

### Product/UX Gate

**Tier:** none (no UI surface; CPO invoked for the `single-user incident` sign-off only)
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

Approved with four conditions (see User-Brand Impact). The #9045 trade-off (an attended rollback
instead of an automatic revert) puts integrity and confidentiality ahead of automatic availability.
The CPO judges it the right call.

## Test Scenarios

All run through `run_case` in `workspaces-luks-freeze.test.sh` with the new harness knobs, unless
marked static. Every invocation string sets `DRY_RUN=0` and its globals inline, because sourcing
resets them. Cleanup cases inject `(exit 9)` and assert `CASE_RC=9`. Drift is observed as
`EMIT_DRIFT <reason>` in `CALLS` (and on `CASE_OUT`).

### Arm

- **T30 — happy path** (timer reads `dead`, then `waiting`):
  - rc 0;
  - the timer `stop` and the `reset-failed` of both units are recorded BEFORE `systemd-run`;
  - `systemd-run` carries `--description=`;
  - marker `result=armed reason=freeze_engaged`.
- **T30b** — `waiting` only on the second read: PASS.
- **T31** — `SYSTEMD_RUN_RC=1`: `died`, `result=arm_failed reason=systemd_run_refused`, NO
  `result=armed`.
- **T32** — rc 0 but never `waiting`: `died`, `result=arm_failed reason=timer_not_waiting`, NO
  `result=armed`.
- **T32b** — `trap cleanup EXIT; DRY_RUN=0; …; arm_dead_man` with T32's knobs:
  - a `result=disarmed reason=arm_aborted` (or `disarm_failed reason=arm_aborted`) marker is
    present. It is a function, so the marker is asserted, not a recorded call;
  - the outcome marker reads `outcome=arm_aborted`.
- **T33** — the timer is already `waiting`, or the service is `activating`:
  - `died`, `result=arm_refused`;
  - neither a timer `stop` nor `systemd-run` is recorded.

### Disarm

- **T35** — `rollback()` with `DEADMAN_ARMED=1` and `DEADMAN_STOP_INEFFECTIVE=1` (check c
  fails):
  - the disarm marker precedes the first `^umount[[:space:]]` in `CALLS`;
  - the rollback still records the plaintext remount, `docker start`, and
    `EMIT_DRIFT rollback_engaged` (the function's last line);
  - the marker reads `result=disarm_failed reason=rollback_engaged`;
  - there is no mid-rollback exit.
- **T35d** — the service is stuck `activating`: the bounded wait runs to exactly its attempt
  limit, emits `check=fire_stuck`, and the rollback proceeds.
- **T35b** — `rollback()` with `DEADMAN_ARMED=0`:
  - the timer `stop` is still recorded (T6b);
  - the marker is `result=not_armed`;
  - no `deadman_disarm_failed` drift.
- **T35c** — `rollback()` while the service reads `activating activating inactive`: it waits, and
  no `umount` is recorded before the service reads `inactive`.
- **T36** — `disarm_dead_man host_canary_passed` succeeds: marker
  `result=disarmed reason=host_canary_passed`, rc 0. In `CALLS` the order is:
  `show … LastTriggerUSec` < timer `stop` < `show …service … ActiveState` < `reset-failed`.
- **T36a** — fired then collected (`DEADMAN_TIMER_LASTTRIGGER` non-empty on the pre-stop read, GC
  model active): rc 1, `check=a`, no `result=disarmed`. It has a rollback-path twin
  (`DEADMAN_ARMED=1`) that must reach the same `check=a`.
- **T36b** — `rollback()`'s marker reason is `rollback_engaged`, never `canary_passed`.
- **T36c (static)** — searched only BETWEEN the `disarm_dead_man host_canary_passed` line and
  `CANARY_OK=1`: a `findmnt -no SOURCE "$MOUNT"` re-assert against `$MAPPER` is present. The
  existing canary `findmnt` lines sit outside that window, so they cannot satisfy it.
- **T40** — the host-canary population assert, run through a function extracted from the canary
  tail: `wl_count_workspace_dirs` over `$MNT/workspaces` with 2 dirs against a persisted
  `WORKSPACES_COUNT=3` gives `died`, `EMIT_DRIFT host_canary_workspace_count_mismatch`, and no
  disarm marker. With 3 dirs it passes.
- **T36d** — the service sequence `inactive activating` against the post-stop read: rc 1,
  `check=b`.

### Cleanup

- **T37** — `CANARY_OK=1`, `(exit 9)`, `FINDMNT_MOUNT_SRC` set to the script's own `$MAPPER`
  value:
  - no `^umount[[:space:]]`/`^mount[[:space:]]`/`cryptsetup close` recorded;
  - `docker start` plus the `resume_writers` starts recorded (roll-forward);
  - marker `outcome=post_canary_luks_retained`;
  - `EMIT_DRIFT cutover_aborted_post_canary`;
  - `CASE_RC=9`.
- **T37b** — the same with `FINDMNT_MOUNT_SRC` naming a plaintext device: NO `docker start`,
  and `EMIT_DRIFT cleanup_mount_not_mapper`.
- **T37c** — a `docker start` failure in the roll-forward: `EMIT_DRIFT cleanup_docker_start_failed`.
- **T38** — `FREEZE_HELD=1`, `CANARY_OK=0`, `(exit 9)`. The rollback runs. Three arms on the
  post-rollback source:
  - a plaintext device gives `outcome=rolled_back`;
  - `$MAPPER` (read from the script) gives `rollback_remount_failed`;
  - empty gives `rollback_remount_failed`.

### Static

- **T25'** — `disarm_dead_man host_canary_passed` sits after the `not_mounted` assert and before
  `CANARY_OK=1` and `docker start "$CONTAINER"`.
- **T25c** — no `disarm_dead_man` in the main body after `docker start`. It carries a synthesized
  positive control.
- **T25d** — `arm_dead_man` and `FREEZE_HELD=1` sit on separate lines, and the arm comes first.
- **T39** — over un-commented logical command lines, with backslash continuations folded: exactly
  one `systemd-run --on-active`, and it carries no `|| true`.

### Other suites

- **Real systemd** (`workspaces-luks-loopback.test.sh`, privileged):
  - H1 reproduced, with stderr naming the collision;
  - success after the script's exact clear-out;
  - no unit left loaded after the EXIT trap.
- **Alert** (`apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh`): the
  predicate carries the tag, host and `result=fired` conjuncts. A mutation dropping any one of
  them goes RED (mirrors `inngest-luks-wrong-volume-alert.test.sh`).
- **Existing suites stay green:** T6b, T12/T12b/T12c, AC8, every suite
  `git grep -l workspaces-cutover.sh` lists (including
  `tests/scripts/test-workspaces-luks-cutover-gate.sh` with its new stubs), `luks-monitor.test.sh`
  (x), and `luks-monitor-install.test.sh` with the new G-rows.
- **RED proof:** each new case fails against `origin/main`'s `workspaces-cutover.sh`. The work
  phase records the failing case IDs in the PR body.

## Acceptance Criteria

### Pre-merge

- [ ] AC1: `bash apps/web-platform/infra/workspaces-luks-freeze.test.sh` exits 0 with T30–T39 and
      T25'/T25b'/T25c/T25d present. The same cases were run RED against the pre-change script, and
      the PR body lists their IDs.
- [ ] AC2: every suite in `git grep -l workspaces-cutover.sh -- '*.test.sh' 'tests/scripts/*.sh'`
      exits 0, including `tests/scripts/test-workspaces-luks-cutover-gate.sh`,
      `luks-monitor.test.sh` and `luks-monitor-install.test.sh`. Privileged suites are judged by
      their `infra-validation.yml` run.
- [ ] AC3: T39 passes. Over un-commented logical lines with continuations folded, there is exactly
      one `systemd-run --on-active` command and it has no `|| true`. A bare `grep -c` is wrong
      here: it prints 2 on `main` because of a comment.
- [ ] AC4: `terraform fmt -check` and `terraform validate` pass for `apps/web-platform/infra`. The
      existing CI jobs are green.
- [ ] AC5: ADR-119 carries the 2026-09-28 addendum and the three in-place markers. The runbook §3
      blockquote and the four triage rows are updated.
      `python3 scripts/lint-infra-no-human-steps.py --changed` exits 0.
- [ ] AC6: the P1 fstab boot-path issue and the go-ahead-gated token-route value-rotation issue
      are filed. Their numbers are in the PR body.
- [ ] AC7 (#8734, runs only after the per-command go-ahead):
  - the evidence re-pull asserts (a)–(d) with a coverage window starting at 2026-07-23T15:34:04Z;
  - DELETE returns 204 and the follow-up GET returns 404 `not_found`, both with UTC timestamps;
  - the PR #8626, #8734, #6178 and #8632 comments are posted;
  - the three legal records and the ADR-100 addendum are committed after the DELETE.

  Without a go-ahead, none of the record files is edited, and #8734 carries the prepared command.
- [ ] AC8: `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0. Measured green on
      2026-09-28 before any edit.
- [ ] AC9: `python3 scripts/lint-guard-contract.py <this plan>` reports three guard entries and
      exits 0.
- [ ] AC10: the PR body carries `Closes #9045`, `Ref #8734`, `Ref #8706`, `Ref #6604` and
      `Ref #6178`, and no `Closes` for #8734, #8706 or #6178.
      Its first line states that the merge re-fires `terraform_data.luks_monitor_install` on
      web-1 (read-only forensic print, idempotent redelivery).
- [ ] AC15: the `infra-validation.yml` run on the PR head passes the loopback step, and its log
      shows the new real-systemd case's H1 line: a same-name `systemd-run` fails while a failed unit
      is loaded.
- [ ] AC16: `plugins/soleur/test/preflight-discoverability-test.test.ts` passes with
      `BASELINE_DECLARED_PROBES` bumped by exactly 1, carrying the PLACEMENT/TRUTH/NO SUBSTITUTE
      comment.

### Post-merge

- [ ] AC11: the `apply-web-platform-infra.yml` run for the merge commit re-fires
      `terraform_data.luks_monitor_install` with no exit 17. Its log contains the forensic lines:
      `ExecMainExitTimestamp=` for `workspaces-luks-deadman.service`, the fstab line, `uptime -s`,
      `reboot-required=` and `automatic-reboot=`. The H1/H2 verdict is posted on #9045, citing the
      run id. H1 needs two things: an exit timestamp at 2026-07-20 22:42:13Z with `fired_cmd=no`,
      and `uptime -s` earlier than 2026-07-20.
- [ ] AC12: the fstab facts (full line, crypttab count, uptime, reboot-required, Automatic-Reboot)
      are posted on the new fstab issue. It is escalated immediately if reboot-required is present
      or Automatic-Reboot is `true`.
- [ ] AC13: #8734 is closed by an explicit `gh issue close` with an evidence comment, never by a PR keyword. That happens only once three things
      hold: the DELETE is verified, the records are merged, and the CLO concurrence on no-rotation
      and no-notification is recorded on the issue.
- [ ] AC14 (rides the #8706 sweeper; not checkable at merge on 2026-09-28): on or after 2026-10-01, `gh issue view 8706 --json state` reads `CLOSED` by the sweeper
      (`HOST_TIMER_PASS nights=3`). If it is not closed,
      `doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/luks-monitor-host-timer-8706.sh`
      runs and its exit code is diagnosed on #8706.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold fails `deepen-plan` Phase 4.6.
- Garbage collection after `reset-failed` is asynchronous. The arm does not poll for it; a lagging
  collection surfaces as a named `systemd_run_refused`, and the runbook's re-dispatch recovers.
  The real-systemd case measures the window.
- `systemctl stop` on an unloaded timer exits 5. Treating any non-zero as a failure turns every
  first-ever arm into a refusal. T30 must start from `LoadState=not-found`.
- The ADR-100 addendum and the legal records must not be written before the DELETE has run. A
  record drafted before a destructive act is a precondition, and one drafted after it is a
  justification. Both must describe what actually happened.
- The forensic print lands in a PUBLIC Actions log. Never print the dead-man `ExecStart` body, any
  `/etc/default/luks-monitor` line, crypttab contents or a state value other than the listed keys.
- H1 is favoured but unmeasured. The ADR-119 addendum must say where the measured verdict will
  land, and must not state H1 as fact. The code fix is correct under both H1 and H2, so no part
  of Phase 2 waits on the verdict.
- **Merging this PR alone mutates production.** `apps/web-platform/infra/**` is the `paths:`
  trigger of the push-triggered `apply-web-platform-infra.yml`, and `terraform_data.luks_monitor_install`
  is on its SSH `-target=` list. The merge re-fires the installer on web-1 (read-only forensic
  step, idempotent redelivery, one probe kick). The PR body's first line states this. No other
  push-triggered workflow applies this resource: `infra-validation.yml` and
  `validate-vector-config.yml` only validate.
- **Consumers of the dead-man's systemd state** (reusing a state as a signal):
  - the installer's exit-17 guard refuses on `SubState=waiting` (refuse-only, so the state
    alone suffices);
  - `arm_dead_man` refuses on `waiting` (refuse-only);
  - `disarm_dead_man` reads `LastTriggerUSec` BEFORE the timer stop and the service `ActiveState`
    AFTER it, because GC erases the "fired" signal, and only a post-stop read closes the race
    with a fire;
  - the forensic print is read-only.
- **The harness fakes must replay systemd's real output shape.** `systemctl show -p X --value`
  prints the bare value. `systemctl show -p X` prints `X=value`. An unloaded unit prints
  `SubState=dead`/`LoadState=not-found` with empty timestamps. The real-systemd case (step 14)
  measures what it can; a fake that disagrees with it is wrong. Query one property per call:
  `-p A,B,C` answers in systemd's order, not the request order (Kieran, systemd 261).
- **Recovery for a refused arm (`arm_refused reason=already_armed`).** The naive repair would be
  to stop the timer by hand on the host, and that is exactly what must not happen: a waiting
  timer belongs to an earlier run's freeze. The runbook row says to let that timer resolve (it
  fires within `DEAD_MAN_MIN`, and its markers land in Better Stack), read the next
  `workspaces-luks-verify.yml` run, and only then re-dispatch. Never re-dispatch while it is
  waiting.
- **New issues' labels.** Before filing, confirm `priority/p1-high`, `type/bug`,
  `type/security`, `domain/engineering` and `domain/legal` exist
  (`gh label list --limit 200`).
- **Lint before handing off.** Run `npx markdownlint-cli2` on this plan and on `tasks.md` before
  the Session Summary. `lint-infra-no-human-steps.py` and `lint-guard-contract.py` pass on this
  plan (measured 2026-09-28).
