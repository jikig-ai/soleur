---
title: "infra(inngest): ADR-142 additive blue-green LUKS apparatus for the Redis AOF volume"
date: 2026-09-17
slug: infra-inngest-adr142-bluegreen-luks-apparatus
branch: feat-one-shot-adr142-inngest-aof-luks-bluegreen
issue: 6894
type: feat
lane: cross-domain
domain: engineering
priority: p2-medium
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
refs: [6894, 7695, 8017]
adr: ADR-142
---

## Enhancement Summary

**Deepened on:** 2026-09-17
**Review passes:** engineering domain lead, legal domain lead, flow analysis, scoped strong-model
advisor consult, architecture review, simplicity review, user-impact review, plus deepen-plan's
verify-the-negative, learnings and vendor-semantics sweeps.

### What the passes changed, not just what they said

1. **The device-selection mechanism was replaced twice.** A signature-precedence rule was rejected by
   two independent reviewers as fail-open; its replacement — a pointer in a root-disk file — was then
   rejected by a third, because the file lives on the disk the only delivery path destroys. The
   pointer now lives in the isolated secret store and is staged to that file as a cache.
2. **The cutover had two mutually exclusive definitions** and edits for both. It is now one: a
   reviewer-gated flag write, not a new Terraform apply target. That removed a workflow job, a
   coverage-test entry, and a gate that would have graded a plan shape that cannot occur.
3. **The copy scope was widened from the AOF directory to the whole mount**, because the flush latch
   that makes a second store-emptying refusable lives beside the AOF and a swap would have left it
   behind — silently disarming the guard the migration exists to protect.
4. **Quiesce left the critical path**, and one leg of the argument for removing it was then measured
   and found false. The leg is removed rather than repaired.
5. **The detach was cut**, after three passes disagreed: a destroy of a still-declared attachment is
   re-created by the next routine dispatch, so the detach was unachievable rather than merely
   expensive. A detector ships instead, and the exposure is stated rather than closed.
6. **Four mechanisms were cut for buying a property something already bought**, and six live
   references to superseded forks were swept — which is also how two of them had survived three
   revisions.
7. **The user-facing enumeration was rewritten from store-shaped to window-shaped**, adding three
   vectors that lose the user's work without the copy tearing at all.

### The largest remaining lever

Acceptance criterion 0. The whole apparatus is conditional on a key count nobody has read yet, and if
that count is zero the cheap gated path closes the issue instead. It is a criterion rather than a
phase bullet for exactly that reason.

## Overview

`hcloud_volume.inngest_redis` is a plaintext ext4 volume holding the Inngest Redis AOF — in-flight
job payloads, the encryption-posture ledger's highest-sensitivity row. ADR-142 decided the only
lawful migration for it: an **additive blue-green byte-copy** onto a second, raw LUKS volume
attached alongside the live one, cut over inside a reviewer-gated window. The destructive recut
path (`apply_target=inngest-volume-recut`) is unavailable on this store because ADR-199 permits the
destroy only against a measured-empty reading and the store cannot be drained empty.

ADR-142's apparatus does not exist. This plan designs it: the second volume plus its attachment,
the boot-time staging stage that opens and mounts it at `/mnt/data-luks` without touching the live
`/mnt/data`, and the reviewer-gated cutover that performs ADR-142 steps 1-10 with every device
selected by volume ID.

## Research Reconciliation — Brief vs. Codebase

Five claims were checked against the tree. Two held, three did not — and all three that did not are
claims **ADR-142 itself makes**, not errors in the brief. They are recorded here rather than quietly
corrected, because each one changes a step of the design.

| Claim | Reality (measured) | Plan response |
| --- | --- | --- |
| The second volume and its attachment are absent from `main`. | Holds. `git grep -n inngest_redis_luks origin/main -- apps/web-platform/infra/` returns only `random_password.inngest_redis_luks`, `doppler_secret.inngest_redis_luks_key`, and the value reference between them. | Build both. |
| There is no staging mount. | Holds for `/mnt/data-luks`. But `cloud-init-inngest.yml` already carries a **complete** LUKS state machine for `/mnt/data`: a passphrase-staging step, a bounded device-presence wait, a `blkid` probe with rc 0-or-2 accepted, four signature arms, an fstab assert, a `verify` assert, and a boot-reopen unit `inngest-luks-open.service`. It is the in-place recut path. | Do not author a second discriminator. Add a **staging arm** that reuses the existing emit vocabulary, guard discipline and detail-log convention, and extend the two existing suites rather than writing a third. |
| ADR-142 step 2: set `INNGEST_CUTOVER_QUIESCE` on `soleur-inngest/prd`. | **False.** The only reader is `apps/web-platform/app/api/internal/schedule-reminder/route.ts` (`isCutoverQuiesced()`, strict `"1"`/`"true"`), which runs in the web container and reads Doppler `soleur/prd`. Setting it on `soleur-inngest/prd` quiesces nothing. The runbook `knowledge-base/engineering/operations/runbooks/inngest-server.md` also records "a clear with no redeploy changes nothing" — the value is baked into the container environment at deploy time. And no `.tf` resource, workflow step or script writes it anywhere in the repo. | The plan's quiesce step targets `soleur/prd` and is paired with a web-platform redeploy on both the set and the clear. The quiesce mechanism is a deliverable, not a reuse. See Design fork Q. |
| ADR-142 apparatus item 5: the cutover script is "delivered via the infra-config push / `/hooks` channel (same as `inngest-wiped-volume-verify.sh`)". | **False for this host.** `inngest-wiped-volume-verify.sh` runs on **web-1**. The `deploy.` tunnel ingress pins its origin to web-1, the infra-config push POSTs to that origin, and the `hooks.json.tmpl` listener runs there. `hcloud_firewall.inngest` is a zero-rule deny-all and 10.0.1.40 runs no webhook listener and receives no push. Its only inbound channel is a Doppler value polled every 30 s by `inngest-cutover-flip.timer`; its only code-delivery path is the OCI bootstrap image. | The cutover runs as an on-host unit shipped in the bootstrap image and triggered by a reviewer-gated Doppler write, mirroring the flip FSM. See Design fork D. |
| ADR-142 step 6: the canary is the reminder count plus `DBSIZE`. | Partly unreachable. `inngest-enumerate-reminders.sh` queries inngest-server's GraphQL at `127.0.0.1:8288/v0/gql`, and on this host Redis **is** the queue store — with `inngest-redis.service` stopped the enumeration cannot answer. | The reminder count is a **pre-freeze baseline and a post-restart invariant**; the in-freeze canary is a direct key-count read against a Redis bound to the copied store. See Design fork C. |

One further correction, to a record rather than to the brief: the C4 `inngestRedis` node's description still
asserts `format = "ext4"` under `ignore_changes = [format]` for `hcloud_volume.inngest_redis`. The
attribute was dropped on 2026-09-03; the ledger row carries a `CORRECTED 2026-09-03` note saying so
and the C4 node did not get the same edit. This plan fixes it.

## Research Insights

### Premise Validation (Phase 0.6)

Every reference the brief cites was probed, not assumed.

| Cited | Probe | Result |
| --- | --- | --- |
| #6894 | `gh issue view 6894` | OPEN — `encryption-posture: hcloud_volume.inngest_redis is plaintext ext4`, `type/security`, `priority/p2-medium`. Holds. |
| #7695 | `gh issue view 7695` | OPEN — `build the gated inngest-volume-recut apply_target`. Holds. |
| #8017 | `gh issue view 8017` | OPEN, `priority/p0-critical` — `inngest recut is structurally unreachable: G14 compares findmnt's kernel device name against a /dev/disk/by-id path`. Holds. |
| PR #7778 | `gh pr view 7778` | MERGED 2026-09-04. Holds. |
| ADR-142 | read in full | `status: accepted`, plus a 2026-09-03 addendum bounding it against ADR-199. Holds. |
| ADR-199 | read in full | `status: accepted`, two amendments (2026-09-03, 2026-09-10). Holds. |
| "no `hcloud_volume.inngest_redis_luks` on main" | `git grep -n inngest_redis_luks origin/main -- apps/web-platform/infra/` | **Confirmed absent.** Three hits, all in `inngest-redis-luks.tf`: `random_password.inngest_redis_luks`, `doppler_secret.inngest_redis_luks_key`, and the value reference between them. No volume, no attachment. |
| "no staging mount" | `git grep -n data-luks origin/main` | **Confirmed absent from `cloud-init-inngest.yml`.** `/mnt/data-luks` exists only as the workspaces staging path (`workspaces-luks-cutover.yml` `STAGING_PATH`). |

Two premises in the brief are **refined** by measurement rather than refuted — recorded in Research
Reconciliation below because they change the design, not the goal.

### Property List (Phase 0.6b)

1. The Redis AOF's bytes reach a LUKS-backed device with no in-flight job state lost (queue, step state, retries, armed reminders).
2. A second, encryptable block device is attached to the inngest host at the same time as the live plaintext one.
3. On boot, that second device becomes an opened, ext4-formatted, mounted LUKS target at a path that is not `/mnt/data`, disturbing neither the live mount nor the running Redis.
4. The copy cannot read from, or write to, the wrong device.
5. A copy that lost or gained state is detected and hard-aborts before anything irreversible.
6. New reminder intake fails *cleanly and retryably* across the freeze rather than being silently dropped. **Note the change:** the first draft phrased this as "refused, and resumes only after verification passes", which presumed the quiesce flag. Fork Q removed that flag from the critical path, so the property is restated to what the design actually buys — the route's connection-refused arm returns a distinguishable 503 with a retry hint while Redis is down, and the SDK retries. A property list that outlived the mechanism it described would have made the plan ship knowingly unmet against its own stated requirements.
7. A failed or regretted cutover can be reversed onto the plaintext volume.
8. Every irreversible step carries a human authorization that a branch-pin makes meaningful.

### Cut List (Phase 0.6b)

Each line is: mechanism the brief names or a reader would reach for → the property it would buy → what on `origin/main` already buys it.

- **A new `random_password` + `doppler_secret` for the LUKS key** → P1/P3 → already exist: `random_password.inngest_redis_luks` and `doppler_secret.inngest_redis_luks_key` in `apps/web-platform/infra/inngest-redis-luks.tf`, on `soleur-inngest/prd`, and both are already in the per-merge `-target=` allowlist (`.github/workflows/apply-web-platform-infra.yml`, the `-target=random_password.inngest_redis_luks` / `-target=doppler_secret.inngest_redis_luks_key` pair). **CUT.** The brief says so; the grep confirms it.
- **Key escrow (an R2 header backup)** → durability → ADR-142 rejects it for this store with stated reasoning, and `workspaces-cutover.sh`'s escrow limb must therefore be dropped rather than ported. **CUT.**
- **A new reviewer-gated GitHub environment** → P8 → `github_repository_environment.inngest_cutover` already exists in `apps/web-platform/infra/inngest-arm-write-token.tf` with `reviewers { users = [54279] }`. **CUT**, and the branch pin is already there too: `github_repository_environment_deployment_policy.inngest_cutover_main` carries `branch_pattern = "main"`, and both addresses sit in the per-merge `-target=` set so they reconcile at merge. An earlier draft of this row called the branch policy "a defect in the existing resource" and pointed at a finding below that does not exist — the `deployment_branch_policy: null` reading it was recalling is dated 2026-09-03 and describes live state *before* the fix landed, not the resource as declared.
- **A new no-SSH command channel to the host** → P1/P4/P5 → `.github/workflows/cutover-inngest.yml` already drives host ops through the deploy webhook (HMAC + CF-Access) with an `op:` choice input and per-op `environment:` gating. **CUT** — extend the op set.
- **A new armed-reminder enumerator** → P5 → `apps/web-platform/infra/inngest-enumerate-reminders.sh` exists (GraphQL against `127.0.0.1:8288`, emits re-armable JSON records) with `inngest-enumerate-reminders.test.sh` beside it. **CUT.**
- **A new post-cutover verifier** → P5/P6 → `apps/web-platform/infra/inngest-wiped-volume-verify.sh` carries the `/health` + `functions >= 1` assertion shape ADR-142 step 8 cites. **CUT** — extend, do not author.
- **A new mutation-tested LUKS guard suite** → P4 → `apps/web-platform/infra/inngest-redis-luks.test.sh` and `inngest-redis-luks-loopback.test.sh` exist; the loopback harness re-binds five environment constants around the *verbatim* cloud-init stage and drives every arm on a real loop device. **CUT the new file; EXTEND both.**
- **A shared LUKS cloud-init fragment** → P3 → no such fragment exists anywhere (each host's `cloud-init-*.yml` hand-writes its own discriminator), so there is nothing to reuse and nothing to build: the inngest discriminator already exists in `cloud-init-inngest.yml` and gains a staging arm. **CUT as a new abstraction.**

What survives: the second volume + attachment, the staging arm in `cloud-init-inngest.yml`, the
cutover body and its plan-shape gate, the sudoers verbs those need, and the ledger/guard wiring.

### Measured quantities

- **cloud-init user_data budget.** `bash apps/web-platform/infra/inngest-userdata-budget.sh` (2026-09-17): `raw rendered 91997 B / after strip 30614 B / stored (b64gzip) 10888 B / cap 32768 B / headroom 21880 B`. The 32 KB Hetzner cap is enforced by that script and by `plugins/soleur/test/cloud-init-user-data-size.test.ts`; it destroyed a host on 2026-09-08 when `#7778` grew the template past it. Headroom is ample for a staging arm, but the number is re-measured as an acceptance criterion rather than assumed.
- **Dark-gate predicate count.** `tests/scripts/lib/inngest-host-dark-gate.sh` carries G1..G20 (24 `# Gn` comment anchors; `G1`..`G19` plus `G20` appear as tokens). ADR-199 C1 names twenty predicates.
- **Gate-library population.** `ls tests/scripts/lib/*gate*.sh` → 20 files. `tests/scripts/lib/registry-luks-recut-gate.sh` carries `SOLEUR-DEBT: 6th near-identical sourced destroy-guard … extract a shared allow-set + counter-scaffold helper when a 7th gate lib lands`. A new blue-green plan-shape gate trips that trigger; the plan takes a position rather than adding a silent seventh.

### Relevant institutional learnings

Every path below was verified to exist.

- `knowledge-base/project/learnings/2026-07-17-workflow-env-gate-references-unprovisioned-environment-auto-approves.md` — a `workflow_dispatch` job naming an `environment:` that Terraform never provisioned auto-creates it with **zero reviewers**, silently auto-approving. Binds: the new cutover job's environment must be the Terraform-provisioned `inngest-cutover`, asserted pre-merge.
- `knowledge-base/engineering/operations/post-mortems/workspaces-luks-deadman-silent-revert-postmortem.md` (2026-07-22) — a dead-man timer armed before a canary that then failed; it fired silently and remounted plaintext, undoing at-rest for ~6 hours with no alert. Binds: if this cutover arms a dead-man, the disarm must be reachable on the canary-failure path, and the failure must emit a diagnosable marker before dying.
- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md` §Addendum (2026-07-19) (a) — the original quiesce set enumerated containers and `webhook.service` but missed `inngest-redis.service`, a *systemd* writer under the mount; seven freezes aborted on torn-file mismatches before anyone noticed the writer was never stopped. Binds: the quiesce set is discovered by asking "what opens, writes or deletes under `/mnt/data`", and the straggler assert (`lsof +D`) is fail-closed with a positive control.
- `knowledge-base/engineering/operations/post-mortems/workspaces-luks-fsck-gate-false-abort-postmortem.md` (2026-07-20) — (root cause 1) a `luksFormat` + `luksOpen` with **no `mkfs`**: the mount silently failed and the whole dataset landed on the root disk under the mountpoint shadow; (root cause 2) a quiescence probe that *created and unlinked* a file inside the mount advanced the root mtime and made a real failure indistinguishable from a live-appending file. Binds: mkfs on the mapper; read-only probes inside the mount.
- `knowledge-base/engineering/operations/post-mortems/inngest-cutover-enumerate-undiagnosable-500-postmortem.md` (2026-06-17) — the read-only `op=enumerate` returned an opaque HTTP 500 with an empty body; the cutover halted correctly but nothing was diagnosable without SSH. Binds: the baseline op dumps the response body, and is independently dispatchable.
- `knowledge-base/project/learnings/2026-07-18-cutover-bridge-dryrun-guard-and-workflow-step-vs-in-script-ssh.md` — a dry-run guard copied verbatim between two cutover workflows whose SSH happens at different points, so the bridge was skipped and the dry run timed out. Binds: do not copy a guard condition; derive it from where this cutover first touches the host.
- `knowledge-base/engineering/operations/post-mortems/2026-09-03-inngest-cutover-flip-doppler-seam-root-exec-postmortem.md` — `inngest-cutover-flip.service` ran as root under a bare `doppler run --config prd`, which injects the whole config; the script then executed command seams read from the environment, so anyone with write on `soleur-inngest/prd` had root on the host within 30 seconds. Binds: no bare `doppler run --config prd` around a root cutover unit, and no command text read from the environment.
- `knowledge-base/engineering/architecture/decisions/ADR-119-…` §(b) — **the retained plaintext volume is DETACHED, not attached-unmounted.** "Unmounted is hygiene, not a control: `dd if=/dev/sdb | strings` still recovers everything." This is in direct tension with ADR-142 step 10 and is surfaced in Research Reconciliation.
- `knowledge-base/engineering/architecture/decisions/ADR-119-…` §(g) — the two-level discriminator: the *device* arm (`blkid -o value -s TYPE`, format only on an empty TYPE) and, one level down, the *mapper* arm (`blkid -p -s TYPE -o value`, mkfs only on an empty TYPE), with `-p` mandatory because a cached `/run/blkid/blkid.tab` entry is wrong in both destructive directions across a rollback-and-reformat cycle. Plus: the staging mount is fail-closed and carries a positive control asserting mount→mapper and mapper→device.
- `knowledge-base/project/learnings/2026-09-14-a-systemd-state-used-as-a-signal-had-no-provenance-and-replayed-a-stale-capture.md` (#6921) — a systemd `inactive|failed` + `disabled` shape used as the sole quiesce signal carried no provenance, so a crashed scheduler read as a deliberate quiesce. Binds: the freeze's own state is recorded in a host file with a timestamp and an owner, not inferred from unit state.
- `knowledge-base/engineering/operations/post-mortems/2026-08-04-infra-config-activation-silently-dead-postmortem.md` — the infra-config delivery path can be silently dead; a `write_files` entry looks like delivery. Binds: the cutover script's presence on the host is asserted by the workflow, not assumed from a merge.

### Learnings the deepen pass added

Four more, all verified to exist, none of them duplicates of the list above.

- `knowledge-base/project/learnings/best-practices/2026-06-03-oneshot-systemd-unit-inactive-is-healthy-report-the-timer.md` — a `Type=oneshot` reports `inactive` as its *healthy* steady state between timer fires, so a probe that watches the service reads green on a dead poller and red on a healthy one. Binds: the cutover unit's liveness is read from the timer, and the Observability block says so explicitly.
- `knowledge-base/project/learnings/2026-05-26-ssh-to-webhook-provisioner-migration-mount-namespace-traps.md` — systemd sandboxing directives create namespace traps where a path is read-only even to root, and a bind-mounted writable path does not grant write access if the target was created read-only first. Binds: the cutover unit's directive set is a decision, and `/etc` writability is part of it.
- `knowledge-base/project/learnings/2026-07-24-guest-luks-store-must-gate-consumer-on-mount-and-guard-suite-must-pin-fail-loud-semantics.md` — a consumer that starts on an unmounted empty directory serves an empty store while every liveness probe reads green. Binds: this host already has the mount gate as the Redis unit's `ExecStartPre`, which is why Fork P's resolver correctness is the whole ballgame — the gate is only as good as the device the pointer selected.
- `knowledge-base/project/learnings/best-practices/2026-06-18-self-enumerate-cannot-bridge-a-store-switching-cutover.md` — a re-arm that self-enumerates after a store switch reads the new, empty store and silently loses the set; the safe shape is capture-before, consume-after, fail loud on an invalid capture, and never a file-presence heuristic. Binds: not this plan's path, since the byte-copy preserves the store rather than switching to a fresh one — but it is the trap any fallback recovery would hit, and the plan records it so a later reader does not reinvent the unsafe shape.

### Vendor semantics, verified rather than assumed

- **`ReadWritePaths=` implies `PrivateMounts=`.** `man systemd.exec`, verbatim: *"Using this option implies that a mount namespace is allocated for the unit"*, and *"propagation from the unit's processes to the host is still turned off"*. This is the fact that falsified the first unit spec.
- **`cryptsetup --key-file -` reads stdin without prompting**, on both `luksFormat` and `open` — confirmed in both man pages.
- **`blkid -p` bypasses the cache** — `man blkid`: *"Switch to low-level superblock probing mode (bypassing the cache)"*. Exit 0 = found, 2 = not found, 8 = ambivalent under `-p`.
- **`DBSIZE` reports the currently selected database only**; `INFO keyspace` reports each database. Both confirmed against the vendor documentation, and both are why Fork C's key-count predicates are the `INFO keyspace` sum.
- **`redis-check-aof` without `--fix` is read-only**; with `--fix` it discards from the first invalid byte to the end of the file. The plan uses it without `--fix`, and the flag is not optional to get right.
- **Three claims documentation could NOT settle** are Phase 0 measurements rather than assumptions: whether starting Redis on a copy mutates it; the authoritative way to read a mapper's backing device; and whether `blkid -p` requires root. Each is recorded in Phase 0 with what it decides.

### Reused mechanisms and their exact anchors

- **No-SSH host-op channel.** `.github/workflows/cutover-inngest.yml` header: `op=enumerate → GET /hooks/inngest-enumerate-reminders`, `op=capture`/`op=rearm → POST /hooks/inngest-rearm-reminders`, `op=verify-wiped-volume → POST /hooks/inngest-wiped-volume-verify`, `op=inventory → GET /hooks/inngest-inventory`. Driver: `scripts/cutover-inngest.sh` (HMAC over the body + CF-Access headers against `https://deploy.soleur.ai/hooks/…`).
- **Reviewer gate shape.** `cutover-inngest.yml`: `environment: ${{ (inputs.op == 'arm' || inputs.op == 'rollback' || inputs.op == 'resume') && 'inngest-cutover' || '' }}`, and the two-job split `workspaces-luks-cutover.yml` documents ("a job's `environment:` gate blocks the job BEFORE its first step, so mode validation lives in an ungated preflight job that performs no mutation").
- **Privilege surface.** `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers` grants the `deploy` user a set of **pinned, wildcard-free** argv: `INNGEST_RESTART`, `INNGEST_STOP`/`INNGEST_START` (both `inngest-server.service`), `INNGEST_QUIESCE` (stop+disable `inngest-server.service`), `INNGEST_ENABLE`, `INFRA_CONFIG_INSTALL`, `SYSTEMCTL_DAEMON_RELOAD`. **Grepped: `inngest-redis` appears nowhere in the file, and no alias grants `mount`, `umount`, `cryptsetup` or a copy.** Sudoers changes have an automated delivery path — `.github/workflows/apply-deploy-pipeline-fix.yml` lists this file in its path filter — and a prior spec records that the aliases must land in **both** the sudoers file and the cloud-init copy for fresh-host parity.
- **Redis unit provenance.** `inngest-redis.service` is **not** written by cloud-init; it is extracted from the OCI bootstrap image (`docker cp soleur-inngest-bootstrap-extract:/inngest-redis.service`). Changing the unit means rebuilding the image via `.github/workflows/build-inngest-bootstrap-image.yml` and re-pinning the digest — a different, slower change class than editing cloud-init.
- **Cutover body to adapt.** `apps/web-platform/infra/workspaces-cutover.sh` implements every phase as a discrete, env-parameterised function (`freeze_writers`, `assert_mount_quiesced` with an `lsof` straggler assert, `prepare_staging_target`, `verify_byte_identity`, `app_canary`, `rollback`, `resume_writers`, `arm_dead_man`/`disarm_dead_man`, host freeze state under `/var/lib/workspaces-luks/state`). Its own header records the precedent for this decision: it "copies the SHAPE of `git-data-cutover.sh`; it NEVER sources or invokes it." `apps/web-platform/infra/git-data-cutover.sh` is **not** a source — it is a read-only proof, and its own header says so — the real modes are rebuilt in #8211.
- **Plan-shape gate to adapt.** `tests/scripts/lib/workspaces-luks-cutover-gate.sh` (`workspaces_luks_cutover_gate <plan-json>`) is the only gate in the family written for a **first `+create` of an additional volume` — its `luks_passphrase_touched` counter deliberately counts update/delete/forget only, because a first create is legal. That is exactly the additive blue-green shape. `tests/scripts/lib/gate-suite-harness.sh` and `tests/scripts/lib/plan-gate-preamble.sh` are genuinely shared and reused as-is.
- **Test wiring.** `.github/workflows/infra-validation.yml` runs each infra suite as a `- name: … / run: bash <path>` step; `inngest-redis-luks.test.sh` is already wired there, as are `workspaces-luks-staging.test.sh`, `workspaces-luks-freeze.test.sh` and `workspaces-luks-g4-mutation.test.sh`.

### Terraform ground truth (read in the worktree, not the bare repo)

- `hcloud_volume.inngest_redis` (`apps/web-platform/infra/inngest-host.tf`): `name = "soleur-inngest-redis-store"`, `size = var.inngest_redis_volume_size` (default 10 GB), `location = var.location`, `labels = { app = "soleur-web-platform" }`, **no `format` attribute** (dropped 2026-09-03 under #7695), and a retained `lifecycle { ignore_changes = [format] }` that keeps the existing ext4 volume's plan a no-op.
- `hcloud_volume_attachment.inngest_redis`: `volume_id = hcloud_volume.inngest_redis.id`, `server_id = hcloud_server.inngest.id`. No `automount`.
- The cloud-init render is `replace(templatefile("${path.module}/cloud-init-inngest.yml", { … }))` and passes, among others, `inngest_volume_id = hcloud_volume.inngest_redis.id` and `inngest_expect_luks = tostring(var.inngest_expect_luks)` (a string, because it is interpolated into a shell comparison).
- The `inngest-host` / `inngest-host-replace` dispatch `-target=` set in `.github/workflows/apply-web-platform-infra.yml` names `hcloud_server.inngest`, `hcloud_volume.inngest_redis`, `hcloud_volume_attachment.inngest_redis`, `hcloud_server_network.inngest`, `hcloud_firewall.inngest`, `hcloud_firewall_attachment.inngest`, and the inngest doppler/random resources. A new volume + attachment reach terraform only if they are added to that set.

### cloud-init ground truth

The `#7695` runcmd LUKS stage in `apps/web-platform/infra/cloud-init-inngest.yml` is a **single-device,
single-mount** state machine:

- `EXPECT_LUKS='${inngest_expect_luks}'`; `DEV="/dev/disk/by-id/scsi-0HC_Volume_${inngest_volume_id}"`; `MAPPER=/dev/mapper/inngest-redis`.
- It stages the passphrase to `/etc/default/inngest-luks` (umask 0177, root:root, FATAL if empty) because `runcmd` is first-boot-only and the boot-reopen unit runs before the network exists.
- `STAGE=device_wait` — a bounded 30 s attach wait with a `blockdev --getsize64 > 0` check, *before* the discriminator, because `blkid` on an absent path returns rc 2 and rc 2 is the "blank" signal.
- `STAGE=blkid_probe` — `blkid -o value -s TYPE "$DEV"`, accepting **only** rc 0 or rc 2; anything else is FATAL ("could not measure" is never "blank").
- Four arms: `ext4` → mount as-is, FATAL if `EXPECT_LUKS=true`; `crypto_LUKS` → `luksOpen` then mount; `""` → `luksFormat --batch-mode --type luks2 --key-file -`, `luksOpen`, `mkfs.ext4 -q "$MAPPER"`, mount; `*` → FATAL.
- Every arm writes the same fstab line guarded by `grep -q ' /mnt/data ' /etc/fstab`, with `nofail` retained deliberately (this host has no SSH and no console; a strict fstab turns a slow attach into an unrecoverable wedge), and loud failure delegated to the Redis unit's `ExecStartPre` mount re-assertion.
- Terminal stages `STAGE=fstab` and `STAGE=verify`, both emitting `SOLEUR_INNGEST_LUKS_STAGE`.
- The boot-reopen unit `/etc/systemd/system/inngest-luks-open.service` (`Before=inngest-redis.service local-fs.target`, `EnvironmentFile=/etc/default/inngest-luks`) runs `/usr/local/bin/inngest-luks-open.sh`, which resolves the **same** `${inngest_volume_id}` device, opens **the same mapper name `inngest-redis`**, never formats, and takes `reopen_skip_plaintext` when the device is ext4.

### Ledger ground truth

`scripts/encryption-posture-ledger.json`, `stores[]` entry `hcloud_volume.inngest_redis`:
`kind: guest-luks-volume`; `device_binding: { volume, attachment, mapper: "inngest-redis-plain" }`;
`at_rest: { mechanism: "plaintext-exception", evidence, defends_against: "nothing at the volume
layer", does_not_defend: "a seized/snapshot disk exposes the Inngest queue + run-state AOF, i.e.
in-flight job payloads (user prompts and agent output)", disclosed_as: "not-publicly-claimed",
live_verification: "unavailable:…", exception }`.

**Not a defect — the `-plain` suffix is the ledger's own convention for a plaintext row.**
`device_binding.mapper` reads `inngest-redis-plain`, which `grep -rn inngest-redis-plain` finds
nowhere else in the repo. That is correct and deliberate: `hcloud_volume.workspaces` carries
`workspaces-plain` and `hcloud_volume.git_data` carries `git-data-plain`, while their LUKS siblings
carry the bare `workspaces` and `git-data`. The convention is what makes the retained-plaintext
backstop row distinguishable from the encrypted row that supersedes it, and it is the shape a new
`hcloud_volume.inngest_redis_luks` row (`mapper: "inngest-redis"`) has to slot beside. Recorded here
because the first reading of it was "the row contradicts itself", and the two sibling rows are what
falsified that.

### Conventions that bind (CLAUDE.md → AGENTS.rules.md)

`hr-no-ssh-fallback-in-runbooks` (the cutover reaches the host through the deploy webhook, never
SSH); `hr-all-infrastructure-provisioning-servers` and `hr-fresh-host-provisioning-reachable-from-terraform-apply`
(no console, no hand-run command); `hr-never-label-any-step-as-manual-without` and
`hr-ship-message-no-operator-checklist`; `hr-menu-option-ack-not-prod-write-auth` (a dispatch
choice is an ack, not an authorization to write prod); `hr-observability-as-plan-quality-gate` and
`hr-observability-layer-citation`; `hr-when-in-a-worktree-never-read-from-bare`;
`cq-cite-content-anchor-not-line-number` (the ledger row already records being burned by a
line-number citation); `cq-assert-anchor-not-bare-token`.

## User-Brand Impact

**If this lands broken, the user experiences:** a scheduled reminder that never fires, or an agent
run that silently disappears mid-flight. The Inngest Redis AOF is the queue's survival mechanism;
a torn or partial copy is not a visible error, it is a job that was accepted and then never ran.
The concrete artifact is a missing reminder in the Command Center with no failure anywhere to point
at — the worst shape a scheduling bug can take, because nothing reports it.

**Three more ways the user loses work, none of them requiring the copy to tear.** The first draft
enumerated by *store* and missed every vector that lives in the *window*:

- **A cron tick due inside a window is not backfilled.** The runbook states the rule outright:
  *"Ticks missed in-window are not backfilled"*. A tick that was never dispatched has no attempt to
  retry, because retries belong to the function and the function never ran. The user sees a digest
  that did not arrive, with nothing anywhere recording that it should have. Recovery is the missed-tick
  enumeration, and this plan makes it a **mandatory close-out of every window**, not the opt-in flag
  it is today.
- **A reminder armed during a window fails terminally, and takes the rest of its batch with it.**
  Measured: the retry helper is `MAX_RETRIES = 2` with a 500 ms base over the SDK's own five
  attempts — roughly fifteen HTTP tries and five to seven seconds, then a terminal 503. Against a
  window measured in boots, that is a rounding error rather than a retry. And the only automated
  consumer aborts on the **first** 503 and exits, reporting *"reminder_id=… and any after it were
  NOT re-armed."*
- **A message the user sends from the dashboard can commit its row and lose its run.** The send route
  awaits the enqueue *after* the row is committed, is not wrapped in the retry helper, and on failure
  records a degraded marker and returns. The user sees their message land with nothing behind it.

**If this leaks, the user's data is exposed via:** a seized or snapshotted Hetzner block device. The
AOF holds in-flight job payloads — user prompts and agent output — in plaintext today. The migration
adds a **second** plaintext copy and this plan does not remove it. There is no detach or wipe
mechanism anywhere in the repository, the device stays attached, and a detach would not be deletion
in any case — a detached volume retains every byte and is re-attachable by any holder of the token.
The bound is a tracking issue's expiry that nothing enforces. The word "briefly" was in an earlier
draft of this paragraph and the plan's own body falsifies it.

**The scheduler-down windows, named rather than left in the phase prose.** Two of them are
user-visible and neither is hypothetical:

- **The replace — hours to days, not "a boot".** The only delivery path to this host destroys its
  root disk, and the start guard then refuses a prod start on a flag the host inherited without the
  root-disk marker. So the window closes when the recovery verb runs, and that verb sits behind the
  same required-reviewer gate as everything else — which means the window is bounded by **reviewer
  availability**, not by boot time. This estate's own history on this host: one dark window of about
  three and a half hours found incidentally, one of roughly twelve days behind a green heartbeat, and
  one incident recorded as never recovered. The user sees nothing fire for the duration.
- **The freeze.** Sub-second by design, bounded by a store the config caps small. A run already in
  the store genuinely resumes, because its state is in the AOF the copy preserves. The other two
  paths do not: see the three vectors above.

**The exposure that does not close in this plan.** The plaintext device stays attached and is not
wiped here. For the length of the backstop window there are two copies of the user's prompts and
agent output on two devices, one unencrypted. The plan ships a detector for the case where the
encrypted device stops being the mounted one, and the ledger carries the window's expiry, and the
wipe is tracked — but the window is open, and a user who deletes their account during it leaves data
resident on a device the deletion path does not reach. That is recorded here rather than in a
footnote because it is the user's data, not an infrastructure detail.

**Brand-survival threshold:** `single-user incident`.

One lost in-flight job for the single live user is the whole population. There is no aggregate to
average it away against, and the store's own recovery story (re-sync functions from Postgres,
re-arm the enumerable reminder subset) explicitly does not cover in-flight step state, retries or
`step.sleep`. CPO sign-off is required at plan time before implementation begins, and
`user-impact-reviewer` is invoked at review time.

## Design

Six design forks were put to the engineering domain lead and, independently, to a scoped
strong-model consult with only the overview and the riskiest phase quoted. The two converged on the
same objection to the first draft's central mechanism, and the draft was wrong in the dangerous
direction. Both rulings are recorded below with the reasoning that changed them, not just the
outcome.

### The shape, in one paragraph

A second Hetzner volume is attached to the dedicated Inngest host alongside the live plaintext one.
A single boot-time resolver — not a second stage — decides which of the two devices is the canonical
`/mnt/data`, from an explicit persisted pointer rather than from a disk signature. Until the pointer
says otherwise, the plaintext device is canonical and the second device is LUKS-formatted, opened
under a non-canonical mapper name and mounted at `/mnt/data-luks`, disturbing nothing. A reviewer-gated,
epoch-fenced one-shot then records a baseline, stops Redis, copies the mount byte-for-byte between
two devices each selected by volume id, proves the copy equal by checksum with Redis still down,
flips the pointer and the fstab line atomically, restarts on the canonical mapper backed by the
encrypted device and verifies. The plaintext device stays attached as the rollback path, watched by
an alert and bounded by a tracked wipe.

Everything in the merge is inert: no `hcloud_*` address on this host is in the per-merge `-target=`
set, so no merge-time apply can bring the volume into existence.

### Fork P — which device is `/mnt/data`, and why a disk signature must not decide it

**First draft, now rejected:** give the resolver a precedence rule — *the device carrying
`crypto_LUKS` is canonical; if neither does, the `ext4` device is; if both do, FATAL.*

Both reviewers rejected it, and the consult named the failure the draft had not seen. The rule
infers intent from a signature that both devices legitimately carry at different times, so it has
no notion of which side of the cutover the host is on. Post-cutover, if the encrypted device is
absent for any reason — a detach, a replace that attaches one volume, attach ordering — the rule
falls through to the `ext4` arm. The plaintext rollback device mounts at `/mnt/data`, **no mapper
exists**, and the Redis unit's mount guard is conditional on mapper existence, so it is *vacuous*
and passes. Redis starts on the stale plaintext AOF and takes writes. That is silent
un-encryption plus two divergent copies of in-flight run state — strictly worse than the dark host
the rule was introduced to prevent, and it converts a loud, data-safe failure into a quiet,
data-unsafe one.

The same inference also makes rollback non-durable. Mount the plaintext device back and the next
boot re-selects the encrypted one by signature, rolling forward onto an AOF that stopped taking
writes at the rollback instant. Making a rollback stick would require erasing the LUKS header — the
destructive act this whole design exists because it is unavailable.

**Ruling: an explicit persisted pointer is authoritative; the signature only corroborates it.**

- **The pointer lives in Doppler, not on the root disk.** The first draft put it in
  `/etc/default/inngest-luks`, reasoning that the file already exists at `0600 root:root` and is
  already the boot-reopen unit's `EnvironmentFile`, so the pointer would cost no new delivery path.
  That is true and it is also fatal: the file is on the **root disk**, its first-boot write is a
  truncating single-key `>` redirect, and the only delivery path to this host is a replace that
  destroys the root disk. The pointer would therefore be erased by the very dispatch every future
  change to this host must fire — after which the resolver takes its pointer-absent arm, mounts the
  plaintext device, leaves no mapper, and lets the Redis guard pass vacuously. That is the identical
  fail-open this fork rejected the signature rule for, reached through non-durability instead of
  through inference.
  So `INNGEST_LUKS_ACTIVE_VOLUME_ID` is a value on `soleur-inngest/prd`, written by the cutover
  through the same reviewer-gated arm token that writes the trigger, and **staged** into
  `/etc/default/inngest-luks` by the first-boot stage exactly as the passphrase already is — because
  the boot-reopen unit runs before the network exists and cannot fetch. Doppler outlives the host,
  which is precisely the property the sibling flag relies on. The staged copy is a cache of a durable
  value, not the value itself.
  The inherited-value hazard that shape carries elsewhere does not apply here and the difference is
  worth stating: the flip flag describes *this host's* progress, so inheriting it is wrong and a
  root-disk marker exists to catch that. The pointer describes *which volume holds the store*, which
  is a fact about the volumes and not about the machine. Inheriting it is correct, and an inherited
  pointer naming a device that is absent or not `crypto_LUKS` is caught by the corroboration check.
  The name must be admitted in the boot isolation pattern alongside the trigger, in the same merge.
- Boot resolution: **pointer present** and naming one of the two ids the template supplied → that
  device is canonical, and its `blkid` TYPE **must** be `crypto_LUKS` or FATAL. **Pointer absent** →
  the pre-cutover world: the plaintext device is canonical, and the second device is raw or already
  `crypto_LUKS` and is staged at `/mnt/data-luks`.
- "Pointer says encrypted, device missing" is now a **refusal**, not a fall-through. "Both devices
  read `crypto_LUKS`" needs no special arm, because the pointer decides. Rollback is a pointer flip
  plus an fstab rewrite, durable across reboots, with no header erase.

**One resolver over two devices, not two stages.** The existing four-arm discriminator is
generalised to take both by-id paths, rather than a second independent staging stage being bolted
beside it. The reason is a world the two-stage shape cannot survive: a host replaced *after* the
cutover re-runs first-boot `runcmd` in a world where the "staging" volume is the populated encrypted
one. Two independent stages would have the main stage mount the plaintext device at `/mnt/data`
while the staging stage tried to lay a filesystem over the live store. One resolver is idempotent
across both worlds; two stages are not.

**This makes the change non-additive for `cloud-init-inngest.yml`.** The plan edits a live four-arm
state machine that a running host depends on. So the guard battery carries a row asserting that a
**plaintext-only** boot — pointer absent, one device attached — behaves byte-identically to today.

**The pointer also decouples this route from `inngest_expect_luks`.** Flipping that variable
re-renders `user_data`, which is ForceNew on the sole scheduler. With the pointer in Doppler, "which
volume holds the store" is durable state the host reads rather than a render input, so no extra
replace is owed. `inngest_expect_luks` stays exactly as it is, owned by the ADR-199 recut route whose
four-dispatch order its own comment pins.

*(A Terraform render input was the other durable candidate and was weighed. It survives a replace by
construction, and the objection that flipping it costs a replace is weak because the post-cutover
world already pays a replace for every change. It was rejected because it makes a fact about the
volumes into a property of the server resource, so the two can disagree — and because a render input
cannot be corrected without a merge, which is the wrong latency for the one value that decides which
device holds user prompts.)*

**fstab is rewritten, never appended.** Every existing writer is `grep -q ' /mnt/data ' /etc/fstab ||`
append-if-absent, so the plaintext line would otherwise survive and win on the next boot. The swap
replaces the single line in place, retains `nofail`, and then asserts **exactly one** `/mnt/data`
line exists. Two such lines is a silent one-boot time bomb of the same shape the existing `fstab`
assertion was added to catch.

### Fork D — delivery and trigger, on a host nothing can reach

The `/hooks` channel terminates on web-1: the push POSTs to the `deploy.` tunnel origin, which is
pinned to web-1, and the listener runs there. The dedicated host has a zero-rule deny-all firewall,
no listener, and is not a push destination. The signed config-bundle path is producer-only — the
consumer refresh script does not exist in the repo, and the drift workflow says so.

**Delivery: the OCI bootstrap image, with no alternative.** The cutover script joins the image's
COPY set, its `docker cp` extract, and the install block that already places the flip trio. That
means a tag, a digest re-pin and a host replace.

**Trigger: a second, independent flag and FSM — not an extension of the existing flip.** The flip
FSM owns the one authorized `FLUSHALL` and the monotonic latch that makes a second one refusable.
Widening its `case` with a state that copies data would put a destructive verb and a preservative
verb behind one flag, one state file and one last-write-wins slot. A new `INNGEST_LUKS_CUTOVER` on
`soleur-inngest/prd` gets its own unit, its own timer, and a copy of the flip's proven shape:
terminal states are no-ops, an `ERR` trap drives the flag to `aborted`, the `SyslogIdentifier` is
allowlisted in the log-shipper config, and reason tokens are consumed by a query from CI.

**Authorization reuses the existing reviewer gate.** New `op=luks-cutover` and `op=luks-rollback`
verbs join the `environment: inngest-cutover` arm of the existing dispatch workflow, writing the
flag on stdin through the arm token exactly as the current `op=arm` does.

*(The ternary's empty-string arm — `environment: ${{ cond && 'name' || '' }}` meaning "no
environment" — is **not** documented by the vendor. It is verified by precedent instead: it is the
shipped shape on this very workflow and on the sibling cutover workflow, whose header records the
fail-closed reasoning behind each operand. Precedent on a live gate is stronger evidence here than a
doc search that returns nothing, and the acceptance criterion grades the conditional rather than
trusting it.)*

```bash
printf '%s' '<state>' | DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" \
  doppler secrets set INNGEST_LUKS_CUTOVER -p soleur-inngest -c prd --no-interactive >/dev/null
```

Three properties of that line are load-bearing and carried over verbatim: the value arrives on
**stdin**, never in argv, so it never reaches a process listing; a pre-write state guard reads the
current value and refuses from an unsafe state; and a Better Stack read afterwards confirms the
on-host FSM actually reached the expected state, because a successful write proves only that Doppler
accepted a string.

**A poll on a mutable flag is level-triggered, and this operation must not re-fire.** The consult
named the consequence: a flag left set, re-read, or re-polled after a restart re-fires the unit,
which copies the now-stale plaintext store over the migrated encrypted one — destroying in-flight
jobs *after* the cutover was reported green.

The first response to that was an epoch token plus a completion sentinel. **Both are cut**, on a
measured objection: the sibling FSM this design copies already states that its terminal states are
idempotent no-ops that exit 0, and its error trap drives the flag to a terminal state so the poll
halts loudly. A completed run therefore leaves the flag terminal and the next poll refuses before any
sentinel would be consulted. The residual case — a *non*-terminal flag after a completed copy — is
covered by the completion-with-verification latch, which already has to exist. Three mechanisms for
one property became one, plus a `flock` for concurrency and terminal no-ops for re-entry.

`Persistent=true` is dropped from the timer for the same reason: it is the only thing that creates
the replay-a-missed-tick case, and dropping it is free.

A Doppler read error is fail-closed, never "assume unset" — that arm survives the cut, because an
unreadable flag is not a terminal state and the terminal-state logic cannot see it.

*(Recorded as a disagreement resolved by measurement: the consult that raised the re-fire saw only
the overview and no repository, so it could not know the terminal-no-op arm was already in the shape
being copied.)*

**The state vocabulary is a deliverable, not an implementation detail.** Fork D's first draft named
a flag and a poll and never said what states exist — which makes "after an abort, which dispatch can
attempt N+1 use, and does its gate admit the resulting state" unanswerable from the document. The
cutover script ships with a state table: state, entry condition, guard predicate, legal successors,
and which verb writes it, one row per abort point in the body.

**The latch records completion-with-verification, never entry.** This distinction is the whole retry
story. The sibling FSM's latch is what refuses a re-arm on a replaced host, and its refusal is correct
there. If the new latch recorded merely that a copy *started*, a partial copy would latch and the
retry would be refused by the artifact the partial itself wrote — the mirror image of the trap that
makes the recut dispatch unreachable after a partial apply. So the latch is written after the T2
byte-equality predicate passes, never before it, and the retry path has its own state whose guard
admits a latched-partial.

**Against the SSH jump path.** A sibling cutover reaches a private host through web-1 with a
Terraform-minted root key, and Hetzner firewalls filter the public interface only, so it is
technically available. It is rejected: it adds a root-key mint, a jump path and a credential surface
to a host whose entire security posture is "no inbound", to save work the poll-flag pattern already
does, on a host that has to be replaced for delivery regardless.

**Blocking prerequisite the first draft missed.** The boot isolation self-check on
`soleur-inngest/prd` is EXACT-SET: it counts non-`DOPPLER_` names and requires the count to equal the
count matching its admitting pattern. Verified by reading the pattern —
`^(INNGEST_(SIGNING_KEY|EVENT_KEY|REDIS_PASSWORD|POSTGRES_URI|CUTOVER_FLIP|DIAGNOSTIC_BOOT|CONFIG_DIGEST|REDIS_LUKS_KEY|HEARTBEAT_URL)|BETTERSTACK_LOGS_TOKEN)$` —
`LUKS_CUTOVER` is **not** admitted. A new name in that project bricks the next re-provision: no
Vector, no server, no flip timer, and the failure invisible off-box. The admission lands in the same
merge as the resource that creates the name, positioned **before** `HEARTBEAT_URL` so the
`HEARTBEAT_URL)|BETTERSTACK_LOGS_TOKEN)` anchor an existing test depends on still holds, and the
`-lt 5` floor is not bumped. Admitting a name before the secret exists is a no-op for a subset test,
so the ordering hazard runs in only one direction.

### Fork Q — quiesce, removed from the critical path

The first draft proposed building the missing setter and clearer. The engineering ruling is to
**drop ADR-142 steps 2 and 9 from this cutover entirely**, and the argument is about what the flag
actually protects.

It does not protect data. The freeze is stop, copy, swap, start. Every write that landed before the
stop is copied; no write can land during the freeze, because Redis is down. Callers receive a clean,
distinguishable refusal during the window — the route's connection-refused arm returns a 503 with a
different header value than the quiesce arm. It also does not gate all intake: cron-fired functions
and every other send path are ungated. It gates one manual arming route.

**"And the SDK retries either way" was a leg of this argument and it is false as written.** Measured:
the retry helper is `MAX_RETRIES = 2` with a 500 ms base over the SDK's own five attempts, so the
ceiling is roughly fifteen HTTP tries and five to seven seconds — not "until the window closes". And
the one automated consumer of that path aborts on the **first** 503, exits 1, and reports that the
reminder it failed on *"and any after it were NOT re-armed"*. So a quiesce that outlives seven
seconds does not make callers wait; it makes a batch fail partway.

The ruling stands on its other legs — the flag protects no data, it gates one route, and Fork C's
predicates are sound over a live store — but the leg that said callers are fine is removed rather
than repaired, because repairing it would mean claiming a durability the measurement does not
support.

What it *did* buy in the first draft was a frozen denominator for an equality canary. Fork C replaces
that equality with predicates sound over a live store, so the dependency disappears with it.

Setting the flag is cheap belt-and-braces if a web deploy is happening adjacent to the window
anyway. It is not a gate, and this plan does not spend two container redeploys — each its own risk,
each widening a sub-second freeze into a multi-minute one — to stop one route.

**Removing it also removes a failure the first draft would have created and not watched.** With
quiesce on the critical path and the un-quiesce reachable only from the verify-passed branch, every
abort after the set — a red canary, an unwritable latch, a crashed unit, a poll that never fires,
a trio that was never installed — leaves the arming route refusing indefinitely, with no timer, no
expiry and no alert. That is this plan's own stated user-facing artifact: a missing reminder with no
failure anywhere to point at. If a future change does put quiesce back on the critical path, it owes
three things it does not owe today: a writer for both edges, a **self-expiring** deadline written
beside the flag so a dead cutover cannot quiesce forever, and a scheduled read as the detection —
never the cutover's own success path.

The factual errors in steps 2 and 9 are corrected in the ADR-142 amendment regardless, because a
reader following them verbatim sets a value on a project nothing reads and proceeds believing intake
is paused.

### Fork C — the canary: three predicates at three instants

The first draft proposed starting a Redis on the copied store and comparing `DBSIZE`. That was
rejected on two measured grounds.

**Starting Redis on the copy mutates the copy.** The Redis config is `appendonly yes` with `save ""`,
and a Redis 7 load walks a multi-part AOF through its manifest and writes on load and on shutdown.
A canary that mutates the artifact it is validating destroys byte-equality with the source and leaves
two divergent stores instead of an original and a faithful copy.

**`DBSIZE` reads database 0 only.** This store spans multiple databases — the exact trap already
recorded in the probe emitter, where a summed count returned 16 while a database-0-scoped read
returned nothing. Any key-count predicate must be the `INFO keyspace` sum.

The replacement:

- **T0, pre-freeze, informational.** The armed-reminder **set** from the enumerator, plus `redis_keys`
  and `redis_expires` from the probe row. Not a gate.
- **T1, the last action before the stop.** `K_freeze` = `INFO keyspace` sum and `E_freeze` = expires
  sum, recorded into the emitted state.
- **T2, in-freeze — the hard-abort predicate, byte-level, with no Redis started.** Preconditions: the
  Redis unit reports inactive, asserted before the copy; and both mounts resolve by `findmnt` to the
  two distinct expected by-id devices, compared against the two template variables — never against a
  kernel `/dev/sd*` name, never by mount-path string alone. Predicate: identical relative file list,
  identical per-file checksum set, identical total byte count, plus a read-only AOF structural check
  over the copy. This is an exact equality over a frozen source, so it has no false-abort mode — which
  is precisely why Fork Q's flag is not needed to make it sound, and it is strictly stronger than any
  key count because it validates in-flight step state, retries and sleep state that no logical count
  can see.
- **T3, post-restart on the canonical mapper.** `/health` 200 and `functions >= 1` via the GraphQL
  `functions` query — never the unregistered REST route, which returns a 404 body that reads as zero.
  Then `K_after >= K_freeze - E_freeze`, with an unconditional hard-abort on
  `K_freeze > 0 && K_after == 0`. Equality is the wrong predicate here: volatile keys legitimately
  expire across the window. And the reminder invariant is a **set**, not a count — every reminder id
  in the T0 set whose fire time is later than the window end must appear in the T3 set. A count
  cannot be equal, because reminders that fire during the window legitimately leave the armed set, so
  a count-equality gate produces false aborts and trains people to relax it.
  **A fourth predicate, because the first three are liveness proxies.** `/health` 200 and
  `functions >= 1` are Postgres and registration facts: a Redis serving an **empty** copied store
  answers both, and the enumerator queries that same re-synced registry. So T3 also re-takes the
  direct `INFO keyspace` sum against the canonical mapper and asserts it against the T1 reading,
  conjoined with `findmnt -no SOURCE /mnt/data` equalling the canonical mapper path — with the
  numeric-readability check kept separate from the equality check, exactly as T2 does. Without it,
  every predicate at T3 is satisfiable by a correctly-mounted, correctly-encrypted, empty store.

**A live-topology measurement is a precondition, not an assumption.** Both the enumerator and the
re-arm script default to web-1 loopback addresses. If the scheduler now lives on the dedicated host,
that canary is pointed at the wrong server today. The plan does not infer the topology from the repo:
Phase 0 reads the newest probe row and records `host_role`, `redis_keys`, `data_mount_devid` and
`redis_key_patterns`.

### Fork B — detach the backstop after verify

ADR-142 step 10 retains the plaintext device attached. ADR-119 §(b), written later and after an
incident, rules the opposite, and on **this** host the argument is stronger than on the host it was
written for:

- This host has a **coded** auto-reach path, not merely a timer. The boot-reopen script resolves a
  device from a template variable that is the plaintext volume's id. An attached retained plaintext
  device is literally the device the boot path reaches for. On web-1 the remount was an unfired
  disarm; here it would be the designed behaviour.
- There is no console and no inbound path, so the sole detector is a probe row. The workspaces
  incident's roughly six-hour detection gap was on a host that could be reached.
- The ledger's `reevaluate_when` pins the resolved device alias, amended precisely because a mapper
  name alone proves nothing about the backing device. A silent revert to the retained plaintext
  falsifies a published at-rest claim about user prompts and agent output.

**Ruling: the device stays attached, and the plan ships a DETECTOR instead of a detach.** This
reverses the first draft, and the reason is structural rather than a matter of appetite.

A Terraform destroy of a resource still declared in the configuration is re-created by the next apply
that targets it. `hcloud_volume_attachment.inngest_redis` is in the `inngest-host` dispatch's target
set and stays in the `inngest-host-replace` set, and the replace is **mandatory for every future code
change to this host**. So a detach would be silently undone by the next routine dispatch — and
nothing in the plan could see it, because the cutover gate grades the cutover plan, a detach gate
would grade the detach plan, and neither grades the plan of the dispatch that re-attaches. The
detach would not merely be reversible; its reversal would be *scheduled by the delivery model*.

Making it stick would mean gating the declaration itself behind a variable — a second ForceNew-shaped
control on the sole scheduler's dependency graph, for a confidentiality window the ledger already
bounds with an expiry and a tracked wipe. That is building a destructive apply path ahead of both its
consumers, for an event this plan's non-goals already exclude.

So: the device stays attached; an alert fires on a probe row whose resolved device alias is not the
encrypted volume's; the wipe is the tracked backstop event with its own clearance requirements. The
exposure is recorded honestly in `## User-Brand Impact` rather than closed by a mechanism that does
not hold.

*(Three passes disagreed here and the record keeps all three: the domain lead ruled detach-after-verify
on the sibling ADR's evidence; the simplicity pass called the detach dispatch YAGNI ahead of its
consumers; the architecture pass showed it would be undone by the next apply regardless. The third
argument is the one that decides it, because it makes the first unachievable rather than merely
expensive.)*

**The honest cost, stated because it is not free.** The plaintext device remains attached to a host
whose boot path resolves devices by id, so the resolver's corroboration check is what stops it being
selected — a guard rather than an absence. The ledger's exception carries the window's bound, the
tracked wipe carries its closure, and the detector carries its visibility. What this plan does not
claim is that the window is closed.

### Fork L — the copy scope, and the FLUSHALL door the swap would re-open

ADR-142 step 5 specifies the copy as `cp -a /mnt/data/redis/. /mnt/data-luks/redis/`. That scope is
too narrow, and the consequence is not a lost file — it is a re-opened path to data destruction.

`/mnt/data` carries a second thing besides the AOF: the flip FSM's **monotonic flush latch** at
`/mnt/data/inngest-cutover/flip-done.latch`. It is append-only, it lives on the durable device
deliberately, and it is the only trustworthy answer to "has a `FLUSHALL` ever been performed on this
host". Two guards read it — a pre-write filter on the arm dispatch and an on-host refusal arm. The
dispatch's own refusal text records the property: the latch *"survives BOTH a rollback and a host
replace"* and *"is cleared ONLY by recutting the host's /mnt/data volume"*.

A mount swap onto a fresh device is, from the latch's point of view, exactly a recut. Copy only
`redis/` and the swap lands `/mnt/data` on a device with no latch — so both guards stop seeing one,
and the door to a second authorized `FLUSHALL` against a now-populated store opens. The migration
whose entire purpose is to preserve the store would have removed the guard that stops it being
emptied.

**The copy is therefore the whole mount, not `/mnt/data/redis/.`**, with a post-copy assertion naming
the latch path specifically rather than trusting a recursive copy to have included it. An assertion
over a file count would not catch this; the latch is one path and the property is about that path.

### What this plan does not change

`apply_target=inngest-volume-recut` is **retained untouched**. ADR-199 and ADR-142 govern disjoint
worlds and a gate decides which world a dispatch is in at dispatch time; retiring the cheap path
would make the sole-copy protection conditional on a reader's judgement, which is the thing ADR-199's
bounding exists to prevent. Its precondition is measurable and currently unmet, which is what a
measured gate is for.

One consequence is worth recording in the amendment: **after** the blue-green cutover, the recut
becomes structurally unusable for its remaining purpose. Its mount pin requires the resolved device
alias to name the volume being destroyed, and post-cutover `/mnt/data` pins the *new* volume — so a
recut aimed at the retained plaintext device can never clear its own gate. Wiping the backstop needs
the separate destructive path Fork B names. One build, two consumers.

## Files to Create

| Path | What it is |
| --- | --- |
| `apps/web-platform/infra/inngest-luks-cutover.sh` | The on-host cutover body. Phase functions mirroring `workspaces-cutover.sh` (`freeze_writers`, `assert_mount_quiesced`, `prepare_staging_target`, the copy, the canary, `repoint_mount`, `resume_writers`, `rollback`), with the escrow limb and the git-fsck limb dropped. Env-parameterised; state under `/var/lib/inngest-luks-cutover/`. **`rollback`'s contract is specified, not implied:** unmount the staging path and, if swapped, the live path; restore the original fstab line; `cryptsetup luksClose` the canonical mapper; assert the mapper no longer exists; remount the plaintext device; restart. Without the close, an abort after the re-open leaves the canonical mapper open while `/mnt/data` is back on plaintext — and the Redis guard's unconditional second state then refuses every start, on a host with no inbound channel and with no sudoers verb able to close it. **The freeze set is enumerated, not named by a function:** `inngest-server.service`, `inngest-redis.service`, `inngest-cutover-flip.timer`, the probe timer, and any other unit measured to write under the mount — the discovery question is "what opens, writes or deletes under `/mnt/data`", and the sibling ADR records seven aborted freezes from answering it by memory. **Self-inhibit:** a `flock` on `/var/lock/inngest-luks-cutover` plus an `in_progress` state arm that refuses and emits, because the timer re-fires every 30 s and a copy can outlast a tick. Re-entry after a *completed* run is refused earlier, by the terminal-state no-op the sibling FSM already implements. |
| `apps/web-platform/infra/inngest-luks-cutover.service` | Root oneshot. `ExecStart=/usr/bin/doppler run --config prd --only-secrets <explicit name list> -- /usr/local/bin/inngest-luks-cutover.sh`. **Four things the first draft got wrong, each measured against the sibling unit:** (1) **`PrivateMounts=no`, and therefore no `ReadWritePaths=`.** `man systemd.exec` is explicit: *"Using this option implies that a mount namespace is allocated for the unit, i.e. it implies the effect of `PrivateMounts=`"*, and *"propagation from the unit's processes to the host is still turned off"*. So a unit carrying `ReadWritePaths=` performs mounts nothing else can see, and they vanish when the oneshot exits — the Redis unit would still be looking at the old mount. The precedent this copies runs outside any unit namespace, so it does not carry. The propagation decision is made explicitly here, not inherited. (2) `/etc` must be writable, because the two writes that *constitute* the cutover — staging the pointer and replacing the fstab line — both target it. (3) `EnvironmentFile=/etc/default/inngest-server` supplies `DOPPLER_PROJECT`, which is how the sibling resolves the isolated project with no `--project` flag; omitting it leaves the unit with no project and no credential. (4) a `SyslogIdentifier=` that matches the log-shipper allowlist exactly — the allowlist edit presupposes a name, and on this host that name is the only way anything is observable. **On `--no-exit-on-missing-only-secrets`:** this repo documents it as making a mis-authored list degrade *quietly*, which is in tension with the fail-closed criterion. Reconciling the two is the script's job, not the flag's, and the script asserts each name it needs is non-empty before use. |
| `apps/web-platform/infra/inngest-luks-cutover.timer` | `OnBootSec=30s` / `OnUnitActiveSec=30s`. **`Persistent=true` is deliberately NOT copied from the sibling timer** — it is safe there because those states are idempotent flag reads, and here a missed run fires at boot, so a host that reboots mid-window would re-enter before anyone had read the abort. Dropping it is free. |
| `apps/web-platform/infra/inngest-luks-cutover.test.sh` | Structural guard over the unit trio and the staging arm. Registered single-line in `infra-validation.yml`. |
| `tests/scripts/lib/inngest-luks-additive-gate.sh` | The plan-shape gate for the `inngest-host` dispatch that creates the new volume. Modelled on `tests/scripts/lib/workspaces-luks-cutover-gate.sh` — the only gate in the family written for a first `+create` of an **additional** volume, where a first passphrase create is legal. The qualifier is load-bearing: the recut gate also admits a bare create, but as a *recovery* arm on a replaced address. Sources `tests/scripts/lib/plan-gate-preamble.sh`. |
| `tests/scripts/test-inngest-luks-additive-gate.sh` | Its drop-one battery, one case per predicate. Sources `tests/scripts/lib/gate-suite-harness.sh`. |
| `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` | The dispatch runbook, mirroring `workspaces-luks-cutover-6604.md`. |
| `knowledge-base/project/specs/feat-one-shot-adr142-inngest-aof-luks-bluegreen/tasks.md` | Task breakdown derived from this plan. |

## Files to Edit

| Path | Change | Why it is in the list |
| --- | --- | --- |
| `apps/web-platform/infra/inngest-redis-luks.tf` | Declare `hcloud_volume.inngest_redis_luks` (no `format`, `size = var.inngest_redis_volume_size`, `location = var.location`, `labels = { app = "soleur-web-platform" }`) and `hcloud_volume_attachment.inngest_redis_luks`. | **Co-location is a lint requirement, not a style choice.** `scripts/lint-encryption-posture.py`'s `file_has_secret_pair` reads the file that declares the *attachment* and requires a `random_password` + `doppler_secret` pair in it. Putting the attachment in `inngest-host.tf` fails the sweep. The file's own `ONE FILE, DELIBERATELY` header already says this. |
| `apps/web-platform/infra/inngest-host.tf` | Pass `inngest_luks_volume_id = hcloud_volume.inngest_redis_luks.id` into the `templatefile()` map. | Fork P's resolver needs the second id, and the pointer's allowlist is built from the two ids the template supplies. |
| `apps/web-platform/infra/cloud-init-inngest.yml` | Generalise the existing four-arm discriminator into a **single two-device resolver** driven by the persisted pointer; extend the boot-reopen script the same way; **admit `INNGEST_LUKS_CUTOVER` in the boot isolation pattern, positioned before `HEARTBEAT_URL`**. | The staging mount, the post-swap reboot correctness and the not-bricking-the-next-boot precondition all live here. This is an edit to a live state machine a running host depends on, so it is not additive for this file. |
| `apps/web-platform/infra/inngest-bootstrap.sh` | Install the cutover unit trio from the image, mirroring the `inngest-cutover-flip.*` install block. | The only code-delivery path to this host. |
| `.github/workflows/apply-web-platform-infra.yml` | Add the new **volume and attachment** to the `inngest-host` `-target=` set. Add **only the attachment** to the `inngest-host-replace` set. Wire `inngest_luks_additive_gate` into the `inngest-host` job; extend the HALT remediation text. **No new `apply_target`** — the cutover is a Doppler-write op on the existing cutover workflow, not an apply. | **The two sets are not the same set, and an earlier draft treated them as one.** The replace set is exactly three targets — the server, its network attachment, and the plaintext volume's attachment — and the plaintext *volume* is **deliberately not targeted, so the durable AOF is preserved by omission**, which the workflow says in those words. Adding the new volume there would break that invariant. Separately, **`inngest-host-replace-gate.sh` aborts `out_of_scope`** without the new attachment: it interpolates the server's id, so a replace forces it into the plan. |
| `.github/workflows/cutover-inngest.yml` | Add `op=luks-cutover` and `op=luks-rollback` to the `op:` choice, and extend **both** the `environment:` conditional and the token-injection conditional to include them. | **This is the writer path.** Without it the new flag is a reader with no writer and the whole sequence is unreachable from merge. The token is injected conditionally so a bash comment is not the scoping mechanism. |
| `scripts/cutover-inngest.sh` | The op bodies: a pre-write read of the current value as a state guard, the stdin write, and a Better Stack confirmation that the on-host FSM reached the expected state. | The established writer shape for a flip-class value. A successful write proves only that Doppler accepted a string. |
| `apps/web-platform/infra/cutover-inngest-workflow.test.sh` | Extend with the same write-order and stdin-not-argv assertions it already pins for the sibling flag. | Otherwise the new writes ship ungraded. |
| `.github/workflows/build-inngest-bootstrap-image.yml` | Add the cutover script at **all four enumerating sites** — the copy step, the `COPY`, the `chmod +x`, and the entrypoint extraction. | An unlisted file is simply absent from the image. Four sites, and a guard scoped to one of four is the defect. |
| `apps/web-platform/infra/cloud-init-inngest.yml` (digest pins) | Re-pin the image tag and digest at **both** sites. | The pin appears twice — the direct reference and the registry-mirror reference. Re-pinning one leaves the fleet split. |
| `apps/web-platform/infra/doppler-injection-bound.test.sh` | Add the new unit to its authored population with a bounded injection list checked against what the script provably reads. | The suite enumerates every `doppler run` unit and pins the cardinality of its escape hatch. A new root unit enters that population on creation, and the post-mortem behind the suite is the one where a root unit under a bare injection became an arbitrary-execution primitive. |
| `apps/web-platform/infra/vector.toml` | Allowlist the new unit's `SyslogIdentifier` in the exact-value source list. | The list is exact-value. An unlisted tag ships nothing off-box — and the file's own comment records the last time that happened, which blinded a gate on this same host. |
| `.github/workflows/infra-validation.yml` | Register both new suites as single-line `run: bash <path>` steps in `deploy-script-tests`; add the new workflow path to `paths:` if a suite parses it. | `.github/scripts/test/test-infra-suite-registration.sh` is a required check and an unregistered suite is zero coverage, silently green. |
| `plugins/soleur/test/terraform-target-parity.test.ts` | Add both new addresses to `OPERATOR_APPLIED_EXCLUSIONS`; add the new job to `stripDispatchJobs`; add a per-dispatch `describe`. | Every managed resource must be reachable or excluded; the coverage test reds the moment the volume exists. |
| `scripts/encryption-posture-ledger.json` | Add a `hcloud_volume.inngest_redis_luks` row; rewrite the `hcloud_volume.inngest_redis` row into the retained-plaintext-backstop shape. **Do not flip its `mechanism` to `luks`.** | `check_resource_partition` fails on an unledgered store the moment the volume exists, and `check_positive_work_floor` rises with it. The existing row's `reevaluate_when` requires an observed cutover boot before the flip. |
| `knowledge-base/engineering/architecture/decisions/ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md` | Append an amendment covering Forks Q, D, C and B. | Three of its steps rest on premises measurement falsified, and Fork B diverges from step 10. Appended, never edited in place — the file's own addendum convention. |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Correct the `inngestRedis` description's stale `format = "ext4"` claim; extend it with the additive apparatus. | The node contradicts the ledger row that already carries the correction. |
| `knowledge-base/engineering/architecture/diagrams/model.likec4.json` | Regenerate via `bash scripts/regenerate-c4-model.sh`. | `plugins/soleur/test/c4-model-freshness.test.sh` asserts byte-identity with a fresh render. |
| `apps/web-platform/infra/inngest-redis-luks.test.sh` | Extend with the two ADR-142 §7 mutations that have no assertion today — a `format` line on the new volume, and the key written to `soleur/prd` instead of `soleur-inngest` — **and with the resolver's structural assertions**: the pointer's authority over the signature, the exactly-one-fstab-line rule, and the plaintext-only regression case. **No third suite.** The plan's own Cut List forbids one, and Fork P means there is no separate staging stage to grade — one resolver in one file, graded by the suite that already grades that file. | Roughly half of §7 exists. The third mutation is covered well by the loopback suite; the fourth has fixtures (`tests/scripts/fixtures/tfplan-inngest-luks-passphrase-*.json`) with no consumer. |
| `apps/web-platform/infra/inngest-redis-luks-loopback.test.sh` | Add staging arms. **Widen its two `sed -e "s\|DEV=…"` rebinds**, which are non-global substitutions over a file that will now carry a second `DEV=` reader. | A non-global `s///` leaves the staging reader unsubstituted and the suite silently exercises only the live path. |
| `.github/CODEOWNERS` | Rows for the new gate library and its suite. | Precedent rows exist for every sibling gate pair. |

### Additional deliverables from the engineering review

| Path / artifact | Change | Why |
| --- | --- | --- |
| `apps/web-platform/infra/inngest-host.test.sh` | Extend the boot-isolation name-set replay with `INNGEST_LUKS_CUTOVER`. | The predicate is replayed behaviourally; a new admitted name that the replay does not know is untested. |
| `tests/scripts/lib/inngest-host-replace-gate.sh` + `tests/scripts/test-inngest-host-replace-gate.sh` | Admit the new attachment, and the new volume create-only, mirroring the existing plaintext-volume admission. Keep the destroyed-volume backstop and add its twin. | Without it the first replace after merge aborts `out_of_scope` — a routine dispatch turned into a dead end. |
| A probe-row alert on a resolved device alias that is not the encrypted volume's, plus a tracked issue with an expiry | The **detection** that the backstop is still attached. | The gated detach dispatch is **cut from this change**. Verified: no `apply_target` anywhere is a detach or a wipe. **That is not the same as "the estate has no destructive apply path"** — an earlier draft implied it and that is false: the recut target destroys this very volume, and the sibling cutover workflow carries an input whose description opens with a deletion warning. The argument that survives is narrower and still decides it: a *new* destructive path here would arrive ahead of both its consumers, for an event outside this plan's non-goals, buying a confidentiality-window narrowing the ledger already bounds with an expiry. Detection ships; closure is tracked. |
| `/soleur:architecture` — a new ADR, **contested** | "Per-operation latched FSM flags are the control channel for irreversible host-local operations on the no-inbound Inngest host." | Two reviewers disagreed and both arguments are recorded rather than averaged. The engineering lead: it is a reusable fleet-wide constraint with real alternatives, both considered and rejected here, and burying it in a store-specific migration record hides it from the next person who has to move code onto this host. The simplicity pass: the pattern is already instantiated once on `main`, so this is its second instance rather than a new decision, and the ADR section's own reasoning argues against minting an ordinal. **Resolution: author it, because the alternatives were genuinely weighed here and nowhere else** — but if the ordinal proves contested at merge, fold it as amendment entry 6 rather than blocking. |

### Additional deliverables from the legal review

| Path / artifact | Change | When |
| --- | --- | --- |
| `knowledge-base/engineering/architecture/decisions/ADR-199-destructive-clearance-requires-a-measured-empty-store-and-a-dark-host.md` | Append a superseded-marker under every sentence naming the recut as the **sole** route to a flip. ADR-199's consequences say "`redis_keys > 0` routes to ADR-142, with no override" — true and unchanged — but its sequencing prose reads as if the recut is the only path that ends in an encrypted device. | at merge |
| `knowledge-base/legal/article-30-register.md` | PA-21 and PA-22 must name the Redis AOF as holding prompts and agent output. Today the register's **only** statement about the device is PA-13 §(f), which characterises it as not personal-data-bearing — scoped-true for PA-13, and divergent from what the ledger and both ADRs say. | **before cutover**, not at merge |
| A new `type/chore` backstop-wipe tracking issue, `expires_on: 2026-10-22` | Filed at merge, because the ledger row that cites it exists at merge. Mirrors the `workspaces` / `git_data` backstop trackers. | at merge |
| `knowledge-base/legal/data-processing-agreement-template.md`, `docs/legal/**`, `plugins/soleur/docs/pages/legal/**` | **No edit.** Verified: no document in the corpus claims queue or job data is encrypted at rest, so nothing is false today and nothing may be added. Adding a claim now is #8197 in its mirror form. | never at merge |
| `knowledge-base/legal/compliance-posture.md` | `#6894` has no Active Compliance Item row despite being the estate's highest-sensitivity plaintext store. Recommended, not gating; the table is an operator write and this plan does not make it. | advisory |

## Open Code-Review Overlap

| Issue | Title | Overlapping file | Disposition |
| --- | --- | --- | --- |
| #7942 | Two mutation batteries in `plugins/soleur/test/` are named `*.mutation.sh` and run in no gate | `.github/workflows/infra-validation.yml` | **Acknowledge.** Different concern: #7942 is about `*.mutation.sh` files under `plugins/soleur/test/` being invisible to the suite-registration gate. This plan registers two new `*.test.sh` suites under `apps/web-platform/infra/` in the single-line form the gate already derives from, so it neither worsens nor fixes #7942. The scope-out stays open. |

No other open `code-review` issue names any path in `## Files to Create` or `## Files to Edit`
(65 open issues scanned).

## Implementation Phases

Phase order is dependency order, not file order. A contract change precedes its consumers, and every
guard's mutation matrix is written before the guard it grades.

### Phase 0 — preconditions, measured not assumed

- Re-run `bash apps/web-platform/infra/inngest-userdata-budget.sh` and record the verbatim output.
  The cloud-init template is about to grow, and a payload past 32768 B stored destroyed this host
  once already: the merge apply's `-target=` set names no `hcloud_server`, so Terraform never
  submitted the oversized payload for validation and the rejection surfaced four days later on a
  replace, with the host already destroyed.
- Re-derive the ADR ordinal for the amendment. ADR-142 is amended, not replaced, so no new ordinal
  is claimed — but confirm that across every `origin/*` ref rather than against `origin/main` alone.
- Confirm `github_repository_environment.inngest_cutover` still carries a non-empty reviewer set and
  a `main`-pinned deployment branch policy. An environment referenced but never provisioned is
  auto-created with zero reviewers and auto-approves.
- **Read `INNGEST_CUTOVER_FLIP` and plan the post-replace re-entry before planning the replace.**
  The flag is `done`, the `done-owner` marker lives on the root disk a replace destroys, and the
  start guard refuses a prod start on an inherited `done`. The re-entry is the post-flush resume
  verb, and it is an ordered step, not a contingency.
- **Measure three vendor behaviours the design rests on, rather than inheriting them from docs.**
  Each is a claim a documentation search could not settle, and each decides a mechanism:
  (a) **does starting Redis on a copy mutate it** — the Redis docs do not state what a server with
  `appendonly yes` and `save ""` writes on load and on shutdown, and Fork C's whole T2 predicate
  depends on the copy being untouched. Measure it on a scratch copy before relying on the answer;
  (b) **how to read a mapper's backing device** — `cryptsetup status`'s field names are undocumented,
  so prefer `dmsetup table`, which is authoritative, and pin whichever is used in the guard;
  (c) **does `blkid -p` need root** — the man page says non-root gets cached unverified information
  and that `-p` reads the device directly, but does not state the privilege requirement outright. The
  cutover runs as root, so this bounds the *test harness*, not the unit.
- **Measure the live topology and the live store, and stop if the reading says stop.** Read the
  newest `SOLEUR_INNGEST_SERVER_PROBE` row and record `host_role`, `redis_keys`, `redis_key_patterns`
  and `data_mount_devid`. Two things turn on it. First, the enumerator and the re-arm script both
  default to web-1 loopback addresses, so if the scheduler now lives on the dedicated host the
  canary is pointed at the wrong server and Fork C's T0/T3 need repointing. Second, if `redis_keys`
  reads 0 under ADR-199's three pins, **this entire build is the wrong instrument** and one gated
  recut dispatch closes the issue instead. The premise that justifies the expensive path is a
  measurement, not a memory.

### Phase 1 — guard contracts and mutation matrices, before any guard

Write `## Guard Contract` entries and their mutation matrices for the **four** guards this plan ships
(below). Derive each row from the design, not from an implementation that does not exist yet. This
ordering is the whole point of the phase.

### Phase 2 — Terraform: the second volume, inert

`apps/web-platform/infra/inngest-redis-luks.tf` gains the volume and the attachment, beside the
passphrase pair that already lives there. `apps/web-platform/infra/inngest-host.tf` gains the second
template variable. Both addresses go into `OPERATOR_APPLIED_EXCLUSIONS`. Both join the `inngest-host` `-target=` set;
only the **attachment** joins the `inngest-host-replace` set, because that dispatch preserves the
durable volume by *omission*. Both join `inngest-host-replace-gate.sh`'s allow-set — **in the
same commit as the plan-shape gate**, so no intermediate state exists where the volume is creatable
and graded only by the generic additive-only check. The boot-isolation admission of the new flag name
also lands here rather than later: admitting a name before the secret exists is a proven no-op, so
the earliest placement is free, and the latest is a bricked boot. Ledger
rows land in the same commit, because an unledgered store fails the repo sweep.

### Phase 3 — cloud-init: the two-device resolver

The staging arm reuses the existing stage's discipline verbatim: a bounded device-presence wait
before any probe; `blkid -o value -s TYPE` with rc 0-or-2 accepted and anything else fatal; format
only on a positively empty type; refuse any unrecognised signature. It adds the level the existing
stage does not need and the workspaces precedent proves is required — a **mapper-level** probe with
`blkid -p` (bypassing the cache, because a stale read is wrong in both destructive directions across
an abort-and-retry cycle), mkfs only on an empty mapper, and a positive control asserting the
staging mount resolves to the staging mapper and the staging mapper resolves to the staging device.
Both links are asserted because neither alone proves which block device sits underneath a path.

The boot-reopen script is generalised the same way, driven by the same pointer. The fstab writer becomes a replace-in-place with an exactly-one-line assertion.

### Phase 4 — the on-host cutover unit trio, and the image cycle that is the only way it lands

This is a whole change class, not a line. Ordered:

1. The cutover script and the log-shipper allowlist edit join the image at **all four enumerating
   sites** in the build workflow — the copy step, the `COPY`, the `chmod +x`, and the entrypoint
   extraction. An unlisted file is simply absent.
2. The install block in `inngest-bootstrap.sh` mirrors the existing trio's, with one deliberate
   divergence: the "assets not staged, skipping install" arm is **fail-closed** here, emitting an
   install-missing state and refusing to enable the timer. Mirrored verbatim, a missing trio yields a
   boot that reports healthy, a flag nothing polls, and a dispatch that succeeds while the host never
   moves — on a host with no inbound channel. That is the silently-dead-delivery shape this plan
   already cites and would otherwise reproduce.
3. New pinned sudoers verbs, in both the sudoers file and its cloud-init copy, for fresh-host parity.
4. Push the tag and build the image. **The digest cannot be known before this step**, which is why
   "fold the re-pin into the same merge" is not achievable as first written: a digest pinned in the
   merge that *adds* the script is necessarily a digest of an image without it. So the ordering is
   explicit — tag, build, capture the digest, then re-pin it at **both** sites in the cloud-init
   template in a follow-up merge, and only then dispatch the replace. One scheduler outage is still
   paid, because the replace happens once, after the pin is correct.
5. Assert the pin resolves to an image that actually contains the script, before the replace rather
   than after it. A pin is a string; the presence of the file inside the image it names is a separate
   fact, and the estate has already paid once for treating a delivery-shaped artifact as delivery.

The presence of the trio on the host is **asserted from off-box**, by an emit on the staging boot —
not assumed from a merge.

### Phase 5 — the dispatch and its plan-shape gate

**There is exactly one cutover dispatch and it is not a Terraform apply.** An earlier draft carried
two mutually exclusive definitions — a Doppler-write op on the existing cutover workflow, and a new
`apply_target` job in the infra-apply workflow — with edits for both in the file lists. They cannot
both be right, and the apply-shaped one is the wrong one: by the time the cutover runs, the volume
and its attachment already exist (they were created at step 1), so a cutover plan shows `no-op`, not
a create. A gate modelled on a first-`+create` shape would grade a plan that cannot occur.

So the cutover is the **Doppler-write op**, on the existing reviewer-gated workflow. No new
`apply_target`, no new infra-apply job, no stock-preflight coverage entry.

The plan-shape gate therefore grades the dispatch that *does* plan a create — `inngest-host`, at step
1. `inngest_luks_additive_gate` asserts that plan creates the new volume and its attachment and
performs no positive action on the live plaintext volume, its attachment, the server, or the
passphrase pair. It is modelled on the cutover-class gate where a first passphrase create is legal,
and it does **not** route through the recut gate, whose allow-set is exactly two addresses and which
would abort `out_of_scope` on sight of the new ones.

### Phase 6 — records

ADR-142 amendment; C4 node correction and regeneration; the runbook; the ledger rows.

## Acceptance Criteria

### Pre-merge (PR)

0. **The kill switch, and it runs before anything else.** The newest `SOLEUR_INNGEST_SERVER_PROBE`
   row is read and its `redis_keys`, `host_role` and `data_mount_devid` recorded verbatim in the PR
   body. If `redis_keys` reads 0 under the three pins, **this plan is the wrong instrument** and the
   cheap gated recut closes the issue instead: stop, and do not build the apparatus. This is an
   acceptance criterion rather than a phase bullet because it is the single largest available cut —
   the whole plan is conditional on a number nobody has read yet, and a criterion is the only thing
   that stops the phases running past it.

   **RESOLVED 2026-09-17 — the kill switch does NOT fire; build the apparatus.** The reading was
   taken from the newest `SOLEUR_INNGEST_SERVER_PROBE` row under all three pins
   (`host=soleur-inngest`, `host_role=dedicated`, `probe_schema=8`), via
   `doppler run -p soleur -c prd_terraform -- scripts/inngest-host-state.sh`:

   ```
   observed_at    2026-09-17 12:38:36        instance_id  hetzner-166305436
   host_role=dedicated  probe_schema=8       cutover_flag=done  flush_latched=true
   redis_keys=442  redis_expires=431
   redis_key_patterns=?queue?:queue:*=6,?estate?:key:*=431,?queue?:partition:*=2,
                      ?connect?:gateways:*=1,?queue?:accounts:*=2
   data_mount_src=/dev/sdb  data_mount_devid=scsi-0HC_Volume_106261946  data_bytes=58898716
   ```

   Re-read at 12:49:35 on the successor host `hetzner-166317708`: `redis_keys=440`,
   `redis_expires=429`, same `data_mount_devid`. **442 ≠ 0**, so ADR-199's G13 refuses the recut
   and ADR-142 preserve-and-copy is the only lawful route — this is now measured, not inferred.

   The `?estate?:key:*=431` bulk is the armed-reminder set ADR-142 names as the reason the store
   cannot be drained to empty: those keys fire at arbitrary future times, so waiting for zero is
   unbounded. Carry this block verbatim into the PR body to satisfy the criterion.

1. An `awk` range bounded to the `hcloud_volume.inngest_redis_luks` block contains no `format` attribute. A whole-file `grep -c 'format'` is **not** the check — that file's own header prose uses the word, so the count is non-zero on a correct tree and the criterion would read ambiguously at review.
2. `hcloud_volume.inngest_redis_luks` and `hcloud_volume_attachment.inngest_redis_luks` are both declared in `apps/web-platform/infra/inngest-redis-luks.tf` — the same file as `random_password.inngest_redis_luks` and `doppler_secret.inngest_redis_luks_key`.
3. `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0 and reports **19 stores**, no `unledgered store` line, and `0 failing checks`. Measured baseline on this branch before the change, 2026-09-17: `encryption-posture: 18 stores, 6 connections, 0 unledgered, 0 failing checks -> PASS`. The count is asserted, not the word PASS, because the floor is derived from the `.tf` scan rather than from the ledger's own length.
4. The `hcloud_volume.inngest_redis` ledger row still reads `"mechanism": "plaintext-exception"`, and its `exception.expires_on` is unchanged at `2026-10-22`.
5. `python3 scripts/lint-guard-contract.py` exits 0 over this plan: every `### Guard n` entry carries `**Property.**`, `**Assembly.**`, and a mutation matrix of at least three data rows.
6. `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0 over every changed file under the five scan roots.
7. `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes: both new addresses resolve through `OPERATOR_APPLIED_EXCLUSIONS`, the new job is in `stripDispatchJobs`, and every stripped name is a real top-level job.
8. `bash plugins/soleur/test/c4-count-parity.test.sh` passes, and `bash plugins/soleur/test/c4-model-freshness.test.sh` passes after `bash scripts/regenerate-c4-model.sh`.
9. `bash .github/scripts/test/test-infra-suite-registration.sh` passes — both new suites are registered.
10. `bash apps/web-platform/infra/inngest-userdata-budget.sh` exits 0 and the stored size is under 32768 B; the verbatim output line is recorded in the PR body.
11. `bash apps/web-platform/infra/inngest-redis-luks.test.sh` passes, including the two newly-added ADR-142 §7 mutations.
12. `sudo bash apps/web-platform/infra/inngest-redis-luks-loopback.test.sh` passes, including a staging arm driven against a real loop device, and its `sed` rebinds are asserted to have landed on **both** `DEV=` readers.
13. `bash tests/scripts/test-inngest-luks-additive-gate.sh` passes with one case per predicate, not one per verdict token.
14. `grep -c 'inngest-redis' apps/web-platform/infra/deploy-inngest-bootstrap.sudoers` is non-zero, every new alias is wildcard-free, and the same aliases appear in the cloud-init copy.
15. The PR body carries `Ref #6894`, `Ref #7695`, `Ref #8017` — **never `Closes`**. The apparatus merges inert; the issues close after a real cutover, not at merge.
16. The cutover body's copy covers the whole mount, and a post-copy assertion names
    `/mnt/data/inngest-cutover/flip-done.latch` explicitly. `grep -c 'flip-done.latch' apps/web-platform/infra/inngest-luks-cutover.sh` is non-zero, and the suite drives it RED when the assertion is removed.
17. `grep -c 'INNGEST_LUKS_CUTOVER' apps/web-platform/infra/cloud-init-inngest.yml` is non-zero **inside the boot isolation pattern**, positioned before `HEARTBEAT_URL`, and `bash apps/web-platform/infra/inngest-host.test.sh` passes with the name-set replay extended. The `-lt 5` floor is unchanged.
18. `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` passes. **This is the tighter arm**: `INNGEST_GZIP_BUDGET = 18_000`, against a stored size measured at 10888 B, not the 32768 B Hetzner cap the Terraform precondition asserts. Both must hold.
19. The cloud-init resolver's authority is the pointer, not a signature: `grep -c 'INNGEST_LUKS_ACTIVE_VOLUME_ID' apps/web-platform/infra/cloud-init-inngest.yml` is non-zero, and the loopback suite drives a case where the pointer names the encrypted device and that device is absent — which must **refuse**, never fall through to the plaintext arm.
20. A plaintext-only boot — pointer absent, one device attached — behaves byte-identically to today. The loopback suite asserts it, because this change edits a live state machine rather than adding beside one.
21. The swap writes **exactly one** `/mnt/data` fstab line, and it retains `nofail`. The suite asserts the count, not merely the presence.
22. The cutover unit cannot re-fire after a completed run. Its terminal states are idempotent no-ops that exit 0, its error trap drives the flag terminal so the poll halts loudly, `Persistent=true` is absent from the timer, and a `flock` plus an `in_progress` arm cover a copy that outlasts a tick. The suite drives RED when any one of those four is removed.
23. A Doppler read failure in the cutover unit is fail-closed. The named case in `apps/web-platform/infra/inngest-luks-cutover.test.sh` drives a read failure and asserts the unit refuses and emits, rather than proceeding as if the flag were unset. Without a named case this criterion is a restatement of the design, not a post-condition.
24. `hcloud_volume_attachment.inngest_redis_luks` is in **both** the `inngest-host-replace` `-target=` set and `inngest-host-replace-gate.sh`'s allow-set. `hcloud_volume.inngest_redis_luks` is in the gate's allow-set **create-only** and is **not** in that dispatch's `-target=` set — mirroring the existing plaintext volume exactly, which the workflow preserves by omission and the gate admits create-only as a recovery arm. `bash tests/scripts/test-inngest-host-replace-gate.sh` proves a replace plans clean.
25. The backstop's continued attachment is **detected**, not merely intended: an alert fires on a probe row whose resolved device alias is not the encrypted volume's, wired in this change, plus a tracked issue carrying an expiry. The gated detach dispatch itself is **out of scope** — see Non-Goals. An acceptance criterion with an "or file an issue" escape hatch is not a post-condition, so this one names the arm actually taken.
26. The new ops are inside the **gated** arm, asserted rather than assumed: the dispatch workflow's
    `environment:` conditional and its token-injection conditional both name `luks-cutover` and
    `luks-rollback`, and the suite drives RED when either is left unextended. If the op lands in the
    choice list and the ternary does not, the job evaluates to an empty environment and runs
    **ungated** with the write token in hand, triggering an irreversible copy — and it merges green.
    That is the reviewer-gate inversion this estate has a recorded learning about.
27. The pinned image digest resolves to an image containing `/inngest-luks-cutover.sh`, asserted
    before the replace. A pin is a string; the file's presence inside the image it names is a
    separate fact.
28. `bash apps/web-platform/infra/doppler-injection-bound.test.sh` passes with the new unit in its
    population. The suite enumerates every unit whose `ExecStart` passes through `doppler run` and
    requires each to bound its injection or appear in a cardinality-pinned acknowledgement list; a new
    root unit that reads secrets enters that population on creation, and the post-mortem behind that
    suite is one this plan already cites.
29. The new unit's `SyslogIdentifier` appears in `apps/web-platform/infra/vector.toml`'s exact-value
    source list **and equals** the value in the `.service` file — asserted, not assumed. Every one of
    the observability failure modes routes through that one file, and a name mismatch between the two
    sides is silent. An earlier draft named this edit in two tables and graded it nowhere.
30. The rollback contract's mapper close is graded: the suite drives a case where the abort happens
    after the canonical mapper is re-opened, and asserts the rollback closes it and that the mapper no
    longer exists. Left ungraded, a failed rollback leaves the mapper open while the live mount is back
    on plaintext, the Redis guard refuses every start, and the only recovery is another replace.
31. The missed-tick enumeration is wired as a **mandatory** close-out of every window, not an opt-in
    flag. A cron tick due inside a window is never backfilled — the runbook says so — so nothing else
    records that it should have fired.
32. `bash scripts/test-all.sh` is green, or every failure is confirmed pre-existing on `origin/main` by the same command.

### Post-merge (reviewer-gated dispatches, tracked as follow-through)

33. An `inngest-host-replace` dispatch completes, the post-flush resume verb re-records the
    `done-owner` marker, the scheduler serves, and a boot emits `SOLEUR_INNGEST_LUKS_STAGE
    stage=staging_verify` — **carrying its measurements, not just its name**. A stage name proves the
    stage ran; it is satisfiable while the staging path is a directory on the root disk under a
    mountpoint shadow, which is a recorded root cause in this estate. The emit carries, and the
    follow-through asserts: `findmnt -no SOURCE /mnt/data-luks` equals the staging mapper path; the
    staging mapper's backing device, read from `cryptsetup status`, resolves to the new volume's id;
    and `findmnt -no SOURCE /mnt/data` differs from it. Note the comparison discipline — a mapper path
    against a mapper path, and a backing device resolved by the host, never a by-id string compared
    against a kernel name. That mistake is the open critical issue this plan cites in its own premise
    table, and reproducing its shape here would be the third instance.
34. The probe row for that boot still shows `data_mount_devid` pinning the **plaintext** volume alias and `redis_active=active` — proving the staging arm disturbed neither the live mount nor Redis.
35. The cutover dispatch completes **into the state the ledger's `reevaluate_when` names**, quoted
    rather than paraphrased so the two cannot drift: a post-cutover-boot probe row whose
    `data_mount_devid` pins the **encrypted** volume's alias, plus the cutover FSM in its terminal
    success state, plus the append-only latch present carrying a completion record. "The canary was
    green and the invariant held" is satisfiable by a cutover that copied, verified and then rolled
    back for an unrelated reason — which would make a flip on the estate's highest-sensitivity
    plaintext row reachable from a rolled-back state.

### Follow-Through Enrollment

Acceptance criteria 33-35 are satisfied by events after merge, not by the diff. Left in prose they
rot — which is the whole reason the daily sweeper exists — so the plan enrolls them.

- **Script:** `scripts/followthroughs/inngest-luks-staging-6894.sh`. Exit 0 when a Better Stack read
  returns a `staging_verify` row on the current `boot_id` **carrying its measurements** — the staging
  mount's resolved source equals the staging mapper path, the staging mapper's backing device
  resolves to the new volume's id, and the live mount's source differs from it — **and** the same
  boot's probe row still shows `data_mount_devid` pinning the **plaintext** volume alias with Redis
  active. Both halves are required: the first proves the staging arm did what it claims, the second
  proves it disturbed nothing. A row whose only content is a stage name proves the stage ran, which
  is satisfiable while the staging path is a directory on the root disk under a mountpoint shadow —
  a recorded root cause in this estate. Mirror the `start=` discipline of
  `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh` — pin the window strictly after the
  dispatch, never before it.
- **Directive:** a `<!-- soleur:followthrough script=scripts/followthroughs/inngest-luks-staging-6894.sh earliest=<dispatch date> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->` comment on the tracker, with the `follow-through` label.
- **A second script for the cutover itself:** `scripts/followthroughs/inngest-luks-cutover-6894.sh`,
  asserting AC 35's invariant as written — the probe row's `data_mount_devid`, the terminal FSM state
  and the completion latch. Enrolling only the staging criterion would leave the two that matter most
  in prose: the cutover, and the ledger flip on a row whose expiry this plan deliberately refuses to
  re-date. Nothing would report that row still reading `plaintext-exception` the day after it lapses.
- **The ledger flip is filed as its own tracked item, and is deliberately not an acceptance criterion** with the `follow-through` label, not
  left as a clause inside an acceptance criterion.
- **Sweeper secrets:** none to add. Verified 2026-09-17 —
  `.github/workflows/scheduled-followthrough-sweeper.yml` already exports
  `BETTERSTACK_QUERY_HOST`, `BETTERSTACK_QUERY_USERNAME` and `BETTERSTACK_QUERY_PASSWORD`.

Note the probe's exit semantics before wiring anything to them: in this family, exit 1 conventionally
means "the assertion did not hold **yet**", which is not the same as "this was done prematurely". A
sweeper arm that reopens on exit 1 would reopen a correctly-pending item on day zero.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/inngest-redis-luks.tf` gains `hcloud_volume.inngest_redis_luks` (size from
the existing `var.inngest_redis_volume_size`, location from the existing `var.location` — never a new
literal, because `tests/scripts/test-eu-location-allowset-parity.sh` pins the EU allow-set) and
`hcloud_volume_attachment.inngest_redis_luks`. `apps/web-platform/infra/inngest-host.tf` gains one
template variable. No new provider, no new version pin, no new sensitive variable: the passphrase
resource and its Doppler secret already exist and are already minted by the per-merge `-target=`
allowlist.

### Apply path

**There is no "following first boot", and the first draft said there was.** `runcmd` is
once-per-instance: a plain reboot does not re-run it, and the file's own isolation-check comment says
so. Only a re-provision does. So the sequence is four named dispatches, not two:

1. `inngest-host` — additive create of the volume and the attachment. The host is untouched, so
   nothing runs the resolver yet.
2. `inngest-host-replace` — the **only** thing that re-runs `runcmd` and therefore the only thing
   that reaches the resolver. This destroys the sole scheduler's root disk. See the re-entry
   precondition below, which the first draft missed entirely.
3. the reviewer-gated cutover dispatch.
4. the backstop wipe, which is its own separately-tracked destructive event and is not part of this
   plan.

Blast radius: step 1 adds one attached device and touches nothing live. Step 2 is HIGH — it destroys
the sole scheduler's root disk; data on both volumes survives because they are separate resources.
Step 3 is the highest — irreversible if the copy destination is wrong.

**Expected downtime: none for step 1; hours-to-days for step 2; a sub-second freeze for step 3.** An
earlier draft of this line said "a boot for step 2" and the re-entry note ten lines below said the
replace "produces a host whose scheduler refuses to start" — both in this section, and only one of
them true. The window closes when the recovery verb runs, and that verb is reviewer-gated, so the
bound is reviewer availability. The estate's three recorded dark windows on this host were about
three and a half hours, roughly twelve days, and one never recovered.

**The re-entry precondition on step 2, which is a trap and not a footnote.** `inngest-server`'s
start guard refuses a prod start when `INNGEST_CUTOVER_FLIP` reads `done` and the host carries no
`done-owner` marker. That marker lives on the **root disk**, at `/var/lib/inngest-cutover/done-owner`,
and its own header records that it cannot survive a replace. The live flag is `done` — the correct,
permanent terminal state for a serving host. **So a replace produces a host whose scheduler refuses
to start.** The guard names its own recovery and it is not a re-arm: a re-arm would consult the
monotonic flush latch, which survives the replace by design, and refuse into a terminal state,
leaving the host more blocked than before. The recovery is the post-flush resume verb, which starts
the server, verifies it serves, re-records the marker and completes to `done` without re-running the
flush. That verb already exists, already carries the reviewer gate, and is now an ordered step rather
than something to discover on a dark host.

### Distinctness / drift safeguards

The new volume carries no `lifecycle` block. The existing `lifecycle { ignore_changes = [format] }`
on `hcloud_volume.inngest_redis` stays exactly as it is — it is what keeps that volume's plan a
no-op now that the config no longer names a format. No secret value lands in state that is not
already there. `dev` is unaffected: this host exists only in prd.

### Vendor-tier reality check

Hetzner block volumes have no tier gate and a 10 GB minimum, which `var.inngest_redis_volume_size`
already satisfies at its default.

## Downtime & Cutover

The gate fires on two operations in this plan, and the honest answer differs for each.

### The offline-inducing operations

1. **`inngest-host-replace`** — a `-replace` of `hcloud_server.inngest`. It destroys and recreates the
   sole scheduler's root disk. Surface affected: every cron and every armed reminder — and the window
   is **not** bounded by the boot. The start guard refuses a prod start on a flag the replaced host
   inherited without the root-disk marker, and the recovery verb is reviewer-gated, so the bound is
   reviewer availability. This estate's three recorded dark windows on this host were about three and
   a half hours, roughly twelve days, and one never recovered.
2. **The freeze** — `systemctl stop inngest-redis` for the duration of the copy. Surface affected:
   the Inngest server's queue and run-state backend.

### Zero-downtime evaluation

**For the freeze, the zero-downtime path was evaluated and is genuinely unavailable.** Copying a
Redis AOF while Redis writes to it yields a torn file — that is the recorded reason the sibling
migration aborted seven freezes before anyone noticed an unquiesced writer. A live replication path
(a replica on the encrypted device, promoted at cutover) is the textbook zero-downtime shape and is
rejected here for a specific reason: it would make the encrypted device a *second live writer* of the
same store during the window, which is exactly the two-divergent-copies state every other part of
this design is built to prevent, and the promotion step has no rollback that does not lose the delta.
The accepted residual is a **sub-second** stop on a store whose config caps it small, inside a
reviewer-gated window, with the plaintext device retained as the rollback path. Justified, bounded,
and the shortest achievable.

**For the replace, the zero-downtime path is blue-green and it is NOT available on this host today.**
The sibling web tier does exactly this — a fresh host is born, drained into, and the old one retired
without a reboot. Here it is blocked by a fact this plan does not change: the Inngest host is a
**singleton**, and the flip FSM, the done-owner marker and the `-target=` sets all name one server
address. Standing up a second scheduler alongside the first is not a smaller change than this plan;
it is a larger one, with a double-fire hazard the flip FSM exists to prevent. So the replace is
accepted as a bounded outage.

### What the plan does instead of pretending otherwise

- **Bounds the window.** The replace happens **once**, not twice — which is why the image digest
  re-pin is ordered before the replace rather than folded into the merge that adds the script, and
  why the cloud-init edits ride the same cycle.
- **Names the re-entry as a step.** The post-replace resume verb is an ordered step, not a discovery
  made on a dark host. That is the difference between a boot-length outage and an open-ended one.
- **Verifies before it proceeds.** The byte-budget check runs before the template grows, because the
  recorded failure mode here is a replace that destroys the host and then cannot recreate it.
- **Keeps the rollback attached.** The plaintext device stays attached through and after the window,
  so a failed cutover is a mount flip rather than a restore.

### Residual, stated plainly

A boot-length scheduler outage on the replace, and a sub-second freeze on the cutover. Both inside
reviewer-gated windows. Neither is zero, and the plan does not claim it is.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_INNGEST_LUKS_STAGE stage=staging_verify (boot) and SOLEUR_INNGEST_LUKS_CUTOVER state=<state> (cutover)
  cadence: once per boot for the staging stage; every 30s poll for the cutover unit while a state is pending
  liveness_is_read_from: the TIMER's active state, never the oneshot service's. A `Type=oneshot` reports `inactive` as its healthy steady state between fires, so a probe that reads the service reads green on a dead poller and red on a healthy one.
  alert_target: Better Stack Logs source 2457081 via the on-host Vector journald tail
  configured_in: apps/web-platform/infra/vector.toml (SYSLOG_IDENTIFIER exact-value allowlist) plus the new unit's SyslogIdentifier
error_reporting:
  destination: journald tag -> Vector -> Better Stack; plus inngest-boot-phone-home.sh as the Vector-independent fallback
  fail_loud: true — every arm is fatal, no arm carries `|| true`, and the EXIT trap branches on rc rather than disarming on success
failure_modes:
  - mode: the staging device is slow to attach and reads as blank
    detection: a bounded device-presence wait emits stage=staging_device_wait before any probe runs
    alert_route: Better Stack; the stage is fatal, so the boot reports rather than formatting
  - mode: blkid cannot read the staging device
    detection: the probe's own rc is captured; only 0 and 2 are accepted
    alert_route: Better Stack; fatal, because "could not measure" is never "blank"
  - mode: the staging device carries an unrecognised signature
    detection: the discriminator's refusal arm, emitting the observed type
    alert_route: Better Stack; fatal, device untouched
  - mode: luksOpen succeeded but no filesystem was laid, so the staging mount silently lands on the root disk
    detection: the mapper-level `blkid -p` probe plus the positive control asserting staging mount -> staging mapper -> staging device
    alert_route: Better Stack; fatal before any copy
  - mode: the pointer names a device that is absent, or one whose signature contradicts it
    detection: the resolver's refusal arm; there is deliberately no ambiguity arm, because the pointer decides rather than the signature
    alert_route: Better Stack; fatal, refusing to fall through to the other device
  - mode: the copy is incomplete or torn
    detection: the T2 predicate — file list, per-file checksum set and total byte count compared against the frozen source with Redis stopped, behind two mount-source preconditions
    alert_route: Better Stack; hard-abort before the mount is touched
  - mode: the cutover unit cannot record its latch
    detection: the fail-closed latch arm, terminal rather than best-effort
    alert_route: Better Stack; the sequence aborts rather than proceeding unrecorded
  - mode: the cutover unit re-fires on a later poll and copies the stale plaintext store over the migrated one
    detection: the terminal-state no-op arm, which refuses before any work; plus the completion-with-verification latch for a non-terminal flag after a completed copy
    alert_route: Better Stack; the re-fire is refused, not merely logged
  - mode: a Doppler read fails and the unit cannot see the flag
    detection: the read is classified, and an unreadable class is fail-closed rather than treated as unset
    alert_route: Better Stack
  - mode: the cutover trio never reached the host, so the flag is polled by nothing
    detection: the install block is fail-closed and emits state=install_missing on the staging boot, and the presence of the trio is asserted from off-box rather than assumed from a merge
    alert_route: Better Stack; this is the silently-dead-delivery shape this estate has already paid for once
  - mode: the replaced host's scheduler refuses to start because it inherited a terminal flag without the root-disk marker
    detection: the start guard's own refusal line, and the absence of a serving probe row after the replace
    alert_route: Better Stack; the recovery verb is an ordered step, not a discovery
  - mode: the scheduler does not come back after the replace, and nobody notices the window opened
    detection: a liveness assertion independent of the cutover's own success path — no cron has fired since T, read from the probe and the function-finished rows, alerting rather than commenting
    alert_route: Better Stack alert. NOT the follow-through sweeper: it runs once a day and a failing script leaves the issue open with the job green, which is bookkeeping, not a page. The plan writes this rule for itself in Fork Q and must not then count a daily comment as an alert.
  - mode: a cron tick due inside a window is never dispatched and is not backfilled
    detection: the missed-tick enumeration, run as a mandatory close-out of every window rather than an opt-in flag
    alert_route: the dispatch's own summary; a tick with no attempt has nothing to retry and nothing else records it
  - mode: an aborted cutover leaves the canonical mapper open while the live mount is back on plaintext
    detection: the rollback contract's mapper-absence assertion; the Redis unit's guard would otherwise refuse every start with no verb able to close the mapper
    alert_route: Better Stack; recovery would otherwise be another replace, which re-enters the window above
  - mode: the cutover unit re-fires at runtime despite the terminal-state arm
    detection: the FSM state emit — the code path is graded by the suite, and this is what reports a fence that fails in production rather than leaving it to be inferred
    alert_route: Better Stack
  - mode: the backstop stays mounted, or becomes the mounted device again, leaving the store on the unencrypted copy
    detection: a probe-row alert where the resolved device alias is not the encrypted volume's, plus the tracked issue's expiry
    alert_route: Better Stack alert plus the follow-through sweeper
logs:
  where: /run/inngest-luks-stage.log and /run/inngest-luks-cutover.log on the host; journald under the two SyslogIdentifiers; Better Stack for off-host reads
  retention: Better Stack Logs retention for source 2457081
discoverability_test:
  command: bash apps/web-platform/infra/inngest-redis-luks.test.sh
  expected_output: a final line reporting zero failures and a non-zero pass count
  credentials_required: none
```

This satisfies the affected-surface extension: the dedicated Inngest host is a surface nothing can
inspect directly — no inbound rule, no listener, no console — so every detection above is an
**in-surface** emit carried off-box by the host's own Vector tail, with a phone-home fallback for the
case where Vector itself is down. Observability layer: the journald-to-Better-Stack path already
carries `inngest-luks-stage`, which is why the staging arm reuses that tag rather than minting one.
**The cutover unit's tag is new and is therefore not carried yet** — the source is an exact-value
allowlist, so an unlisted identifier ships nothing off-box. That edit is a first-class deliverable and
an acceptance criterion asserts the identifier in the allowlist equals the one in the unit, because a
mismatch between the two is silent.

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.inngest_redis_luks
    mechanism: plaintext-exception
    evidence: "apps/web-platform/infra/inngest-redis-luks.tf — the hcloud_volume.inngest_redis_luks block, declared with no format attribute, beside random_password.inngest_redis_luks and doppler_secret.inngest_redis_luks_key. CONTENT-ANCHORED, not line-numbered. The apparatus that will encrypt it lives in the staging arm of apps/web-platform/infra/cloud-init-inngest.yml and is INERT at merge: no hcloud_* address on this host is in the per-merge -target= set, so no merge-time apply can bring the device into existence."
    defends_against: "nothing yet — the resource is declared and inert; no device exists and no byte has been written"
    does_not_defend: "once cut, LUKS-header corruption strands this store: NO header escrow exists for this volume BY DESIGN (ADR-142 'No key escrow'), unlike cloudflare_r2_bucket.workspaces_luks_header, which is a first-class ledger row. The asymmetry is deliberate — the residual availability risk is borne by the controller (lost in-flight jobs), while the confidentiality risk an escrowed header would add is borne by data subjects. Also, once cut, a root compromise of the running host reads the mapper, and a leak of INNGEST_REDIS_LUKS_KEY from soleur-inngest/prd opens it."
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:the resource is not applied, so no probe row can exist. SOLEUR_INNGEST_SERVER_PROBE emits data_mount_devid at probe_schema=8, which becomes the live verification the moment /mnt/data resolves to this volume's alias. Tracked #6894."
    exception:
      justification: "declared-but-unformatted volume; the apparatus is inert on merge and the device becomes crypto_LUKS only on a reviewer-gated dispatch. Writing mechanism: luks here would be a false at-rest claim about user prompts and agent output in the estate's own accountability instrument — the mirror image of #8197, where a TOM described controls that did not exist."
      tracking_issue: "#6894"
      reevaluate_when: "the first boot observed reaching the staging stage with luksFormat applied to a device whose blkid TYPE was measured empty, the mapper opened, and data_mount_devid pinning THIS volume id. Flip mechanism to luks in that follow-up commit, never before."
      expires_on: "2026-10-22"
  - store: hcloud_volume.inngest_redis
    mechanism: plaintext-exception
    evidence: "apps/web-platform/infra/inngest-host.tf, resource \"hcloud_volume\" \"inngest_redis\" — no format attribute, lifecycle ignores changes to one; the live device is plaintext ext4 from its 2026-07-07 creation"
    defends_against: "nothing at the volume layer"
    does_not_defend: "a seized or snapshot disk exposes the Inngest queue and run-state AOF, i.e. in-flight job payloads — user prompts and agent output"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:the Hetzner API is blind to guest-side LUKS; the probe reports the by-id device either way while this row asserts plaintext"
in_transit:
  - connection: "the reviewer-gated dispatch to Doppler (writing INNGEST_LUKS_CUTOVER on soleur-inngest/prd)"
    tls: true
    cert_verification: on
    does_not_defend: "a compromise of DOPPLER_TOKEN_INNGEST_ARM, which is a live read/write handle on that config"
    disclosed_as: not-publicly-claimed
  - connection: "the host's Vector journald tail to Better Stack Logs"
    tls: true
    cert_verification: on
    does_not_defend: "the emit content itself, which is deliberately non-secret — stage names, rc values and device types, never the passphrase"
    disclosed_as: not-publicly-claimed
exception:
  store: hcloud_volume.inngest_redis
  justification: "retained as the rollback backstop for the blue-green cutover. The apparatus merges INERT — the device becomes crypto_LUKS only on a gated dispatch — so flipping this row to luks at merge would be a false at-rest claim about user prompts and agent output for an unbounded window."
  tracking_issue: "#6894"
  reevaluate_when: "AMENDED IN-CELL by this change: the live row previously named apply_target=inngest-volume-recut as the SOLE route to a flip. That sentence is now an incomplete statement of the conditions, because an additive blue-green route exists. Either route qualifies — the recut dispatch OR the additive cutover dispatch — AND a boot observed at SOLEUR_INNGEST_LUKS_STAGE stage=verify with data_mount_devid pinning the encrypted volume's alias. Flip mechanism to luks in that follow-up commit, never before."
  expires_on: "2026-10-22"
```

The `expires_on` is deliberately **not** re-dated. Pushing an at-rest exception's expiry forward is
buying more plaintext time with a keystroke, and the existing row already carries a note saying so.

## Architecture Decision (ADR/C4)

Four architectural decisions are made here: the store's migration mechanism; that the canonical
`/mnt/data` device is named by a persisted pointer rather than inferred from a disk signature; that a
per-operation latched flag polled from an isolated secret store is the control channel for
irreversible host-local work on a host with no inbound path; and a reversal of ADR-142 step 10. All
four are deliverables of this plan. Three are corrections or extensions to an existing decision and
belong in its file; the third is genuinely new and gets its own record.

### ADR

**Amend ADR-142, do not mint a new ordinal.** The decision being recorded is how ADR-142's own steps
are measured and one reversal of its step 10 — not a new architectural position. A new ordinal would
also create a renumber-sweep hazard against sibling branches for no gain, which is the reasoning
ADR-199's own 2026-09-10 amendment used for the same choice.

The amendment carries five entries, appended and never merged into the text above them:

1. **Step 2's project was wrong.** `INNGEST_CUTOVER_QUIESCE` is read from `soleur/prd` by the web
   container, needs a redeploy on both edges, and has no automated writer. Recorded with the grep
   that establishes it.
2. **Apparatus item 5's delivery channel does not reach this host.** The `/hooks` channel terminates
   on web-1. Replaced by the flip-FSM-shaped unit trio.
3. **Step 6's canary is split across three instants** because the enumerator needs a live server and
   the freeze stops the store it reads from.
4. **Step 5's copy scope is widened from `/mnt/data/redis/.` to the whole mount**, because the
   flip FSM's monotonic flush latch lives beside the AOF and a swap that leaves it behind disarms the
   only guard that refuses a second `FLUSHALL`.
5. **Step 10's attached backstop stands, and the record says why the obvious improvement does not
   work here.** A later sibling decision rules that a retained plaintext device should be detached
   rather than merely unmounted, on evidence this plan accepts. It cannot be applied here: the
   attachment stays declared in the configuration and sits in the target set of the dispatch that is
   mandatory for every future change to this host, so a detach would be re-created by the next
   routine apply — and no gate in the design could see it, because each gate grades a different
   dispatch's plan. A detector ships instead, and closure belongs to the tracked wipe. Recorded with
   both arguments, because a reader who finds only the sibling decision will try the detach.

### A new ADR, for the one decision that is not a correction

Three of the four decisions are corrections or extensions to ADR-142 and belong in its file. The
remaining one is not: **that a per-operation latched FSM flag on the isolated secret store is the control
channel for irreversible host-local operations on a host with no inbound path, and that each such
operation gets its own flag and its own FSM rather than extending an existing one.**

That is a reusable architectural constraint with real alternatives, both considered and rejected
here: build the signed config-bundle pull engine whose producer exists and whose consumer does not,
or reach the host through a CI-driven jump path with a freshly minted root key. Recording it in
ADR-142's amendment would bury a fleet-wide constraint inside a store-specific migration record, and
the next person who needs to move code onto this host would not find it.

It also carries a deviation that must be recorded rather than left silent. The principle that a
verification surface does not actuate — a component deciding whether something worked must not perform
the write it is judging — is broken here by construction: one script performs the copy, adjudicates
the byte-equality predicate, flips the pointer, rewrites the mount and publishes its own verdict, on
one credential. That may well be right for a single-shot host-local operation with no inbound channel,
but the register's own precedent is that such a deviation is recorded with its bounds and its explicit
waivers. This ADR is where it belongs.

The ordinal is provisional and re-derived immediately before merge, across every `origin/*` ref
rather than against `origin/main` alone — a sibling branch can claim an ordinal that `main` does not
yet show, and that collision has happened twice in one session on this repo.

### C4 views

Container view. Two edits:

- `platform.infra.inngestRedis`'s description asserts `format = "ext4"` under
  `ignore_changes = [format]`. The attribute was dropped 2026-09-03 and the ledger row already
  carries the correction; the C4 node did not get it. Corrected here.
- The additive apparatus is added to the same description: a second block device, encrypted, staged
  at a distinct mountpoint, with the in-place recut path retained for the disjoint world ADR-199
  governs.

**No new element and no `views.c4` edit.** Checked against all three model files, by enumeration
rather than by a grep for the feature's own noun:

- **External human actors**: none. This change has no human participant beyond the reviewer already
  modelled by the gated dispatch edge.
- **External systems / vendors**: Hetzner (already modelled, `hetzner`), Doppler (already modelled,
  `doppler`, and the edge already carries LUKS-key scoping prose), Better Stack (already modelled).
  No new vendor.
- **Containers / data stores touched**: `platform.infra.inngestRedis` (already modelled). The new
  volume is a second device backing the **same** container, exactly as `workspacesVolume` models one
  node across a plaintext and a LUKS device rather than two nodes.
- **Actor-to-surface access relationships**: unchanged. No access boundary moves.

The count-parity gate is a separate question from the actor rubric, so it is answered separately:
`bash plugins/soleur/test/c4-count-parity.test.sh` must be green. Its seven clauses are all on the
`github -> sentry` and `github -> resend` edges and count workflows, heartbeat check-ins, cron
monitors and Resend emitters. **The new workflow job lives inside an existing workflow file
(`apply-web-platform-infra.yml`), adds no `actions/sentry-heartbeat` step, no new `monitor-slug:`
and no Resend emitter** — so no clause moves. If implementation adds a heartbeat or a monitor to the
new dispatch, C1/C3/C5/C6 or C4/C6 move and the prose must move with them.

### Sequencing

The amendment is authored now and describes the target state. It is not postponed to the cutover.

## Guard Contract

### Guard 1 — the staging arm never writes to a device carrying data

**Property.** No device carrying any filesystem signature is ever written by the staging arm, and
the only device it may format is one positively measured blank.

**Assembly.** Not a list of the arms that exist today — the *chokepoint*. Every write in the staging
arm is reached through exactly one probe result: the `blkid -o value -s TYPE` call in
`apps/web-platform/infra/cloud-init-inngest.yml`'s staging stage, whose own rc is captured and whose
value dispatches a `case`. The property quantifies over every branch reachable from that `case`,
plus the mapper-level `blkid -p` probe that gates `mkfs`, plus the boot-reopen script's copy of the
same decision. The probe sites are enumerated **by the guard, not by this prose** — a count written
here goes stale against the design in the same document, and Fork P's two-device resolver probes both
devices at both sites. The guard walks the file, classifies every probe it finds, and reds on an
unclassified one; the sites named here are its floor, never its definition.

**Mutation matrix**

| # | Mutation | Must drive RED because |
| --- | --- | --- |
| 1 | Delete the rc capture on the staging `blkid`, so a failed probe collapses to an empty type. | "Could not measure" would take the format arm. |
| 2 | Change the empty-type arm's guard from `""` to a catch-all default. | Formatting becomes reachable from a populated device. |
| 3 | Add a **second** staging device reader that skips the probe entirely, after a compliant first one. | A guard that stops at the first reader cannot see the second. This is the row that makes the assembly structural. |
| 4 | Drop `-p` from the mapper-level probe. | A cached entry reports the previous type across an abort-and-retry cycle, and the arms are destructive in opposite directions. |
| 5 | Remove the guard's own dispatch (make the suite skip the staging stage). | A guard reporting "0 checked" and exiting 0 is vacuous. |
| 6 | Reorder `mkfs` to before `luksOpen`. | A lifetime property: deleting `mkfs` reds any suite that mounts at all, while **moving** it reds only a suite that observes inside the window between open and mount. |

**Harness rows.** (a) Replace the suite's staging fixture with the live-arm fixture — the suite must
red, because a harness that grades the wrong text is vacuous. (b) A must-PASS input that is not the
canonical: a staging device already carrying `crypto_LUKS` from a previous run must PASS (idempotent
re-entry is explicitly permitted), proving the guard does not simply reject everything.

**Anchor.** The guard compares the rendered cloud-init text against assertions in the same commit,
so a weakening could edit both. The outside anchor is the loopback suite: it extracts the stage
**verbatim** from `cloud-init-inngest.yml`, rebinds only five environment constants each asserted to
have landed, and drives every arm against a real loop device. A text-only weakening survives the
structural suite and dies on the real device.

### Guard 2 — the canary cannot be satisfied by an unreadable measurement

**Property.** The cutover proceeds past the copy only when the copy is proven byte-identical to the
frozen source — identical relative file list, identical per-file checksum set, identical total byte
count — with Redis still stopped and both mounts resolved to their two distinct expected devices.

*(An earlier draft of this guard graded a key count compared against a pre-freeze baseline. Fork C
deleted that canary — starting Redis on the copy mutates the copy, and the count primitive reads one
database of several. The guard is restated against what the design actually does, because a guard
that grades a deleted mechanism is worse than no guard: it is green by construction.)*

**Assembly.** The chokepoint is the T2 predicate block in `inngest-luks-cutover.sh`. The property
quantifies over the two mount-source preconditions, the unit-inactive precondition, the file-list
comparison, the checksum-set comparison, the byte-count comparison and the structural AOF read — and
over the T1 and T3 readings that bracket them, where the numeric-readability check is kept as a
**separate** predicate from any comparison. The merge is the defect: an unreadable sentinel compared
with a numeric operator is TRUE under shell arithmetic coercion, which is precisely why the sibling
dark gate splits its readability predicate from its value predicate and records that the two may not
be merged.

**Mutation matrix**

| # | Mutation | Must drive RED because |
| --- | --- | --- |
| 1 | Merge a readability check into its comparison. | An unreadable sentinel then reads as a clearing value. |
| 2 | Drop the unit-inactive precondition. | A copy taken while Redis writes yields a torn AOF, and the checksums would then compare two moving targets. |
| 3 | Make the hard-abort a warning that continues. | The chosen operational default is hard-abort; a warn-and-continue arm reaching the mount swap is the failure this guard exists to stop. |
| 4 | Compare only the file list, dropping the checksum set. | Equal names with unequal contents is exactly the torn-copy shape. |
| 5 | Add a **second** copy site that bypasses the predicate. | The property is over every copy, not the first. |
| 6 | Remove the guard's dispatch from the suite. | Anti-vacuity floor on the guard itself. |
| 7 | Move the latch write to before the T2 predicate instead of after it. | A lifetime property: a latch recording entry rather than completion makes a partial copy refuse its own retry, and only a case observing *inside* the copy window can see the difference. |

**Harness rows.** (a) Neuter the suite's abort-detection helper so every case trivially passes — the
suite must red on its own instrument self-test. (b) A must-PASS non-canonical input: a baseline and
post-copy pair that are equal but non-zero and of a different magnitude than the fixture must PASS.

**Anchor.** The readings are stored values the same commit could edit alongside the assertions. The
outside anchor is the probe: `data_bytes` and `redis_keys` are emitted hourly by the host's own
emitter, independently of the cutover script, so a T1 reading that disagrees with the last probe row
before the freeze is contradicted by a field nothing in this change authors.

**The cutover's own records go in the cutover's own state directory, never in the flush latch.**
An earlier draft anchored the baseline by appending it to `/mnt/data/inngest-cutover/flip-done.latch`.
That file is the sibling FSM's monotonic record of whether a `FLUSHALL` has ever happened, parsed by
two readers, and Fork L exists specifically to keep it intact across the swap. Appending cutover
canary data to it would change the content those readers see, inside the plan whose stated purpose is
to preserve it.

### Guard 3 — the additive-create plan touches only the additive set

**Property.** The `inngest-host` dispatch's Terraform plan — the one that brings the new volume into
existence — creates the new volume and its attachment, and performs no positive action on the live
plaintext volume, its attachment, the Inngest server, or the passphrase pair.

*(It grades that dispatch and not "the cutover", because by cutover time the addresses already exist
and a cutover plan would show `no-op`. A first-`+create` gate pointed at a no-op plan is green by
construction.)*

**Assembly.** The chokepoint is `inngest_luks_additive_gate`'s jq filter over
`terraform show -json`'s `resource_changes[]`. The property quantifies over every entry in that
array — not over a named subset — via an exact-equality allow-set plus a named-live set plus two
catch-alls (`resource_deletes`, `out_of_scope`). Membership is exact equality, never substring
containment. The positive-action filter excludes both `no-op` and `read`, and counts `forget`
alongside `delete`, because a state removal manifests as `forget`.

**Mutation matrix**

| # | Mutation | Must drive RED because |
| --- | --- | --- |
| 1 | Add a `delete` on `hcloud_volume.inngest_redis` to the fixture plan. | The live AOF device is the thing the whole design exists to preserve. |
| 2 | Add an `update` on `random_password.inngest_redis_luks`. | A re-mint opens a new header and strands the data; rotation is not rekey. |
| 3 | Add a positive action on an address in neither set. | The `out_of_scope` catch-all is the only predicate that can see an unenumerated address. |
| 4 | Change exact-equality membership to substring containment. | `hcloud_volume.inngest_redis` is a prefix of `hcloud_volume.inngest_redis_luks`; containment silently admits the wrong one. |
| 5 | Replace a counter's jq with an expression that evaluates to empty. | An uncomputed counter is `""`, and `[[ "" -gt 0 ]]` is FALSE — it silently satisfies every threshold. This is what `plan_gate_assert_numeric` exists for. |
| 6 | Remove the gate's invocation from the dispatch job. | Anti-vacuity floor on the dispatch itself. |

**Harness rows.** (a) Feed the suite a plan JSON that is not classifiable (a malformed
`resource_changes`) — the suite must red rather than pass on zero entries. (b) A must-PASS
non-canonical input: a plan in which the live volume and the Inngest server appear as explicit
`["no-op"]` entries must PASS, since untargeted-but-present is the normal shape.

**Anchor.** The gate's allow-set is a literal in the same repo as the workflow it grades, so one diff
could widen both. The outside anchor is `plugins/soleur/test/terraform-target-parity.test.ts`, which
independently enumerates every managed address from the `.tf` files and requires each to be reachable
or excluded — a widening that adds an address to the gate without adding it to the exclusions reds
there, in a different suite with a different input.

### Guard 4 — the canonical device is decided by the pointer, never inferred from a signature

**Property.** `/mnt/data` is mounted from the device the persisted pointer names, and from no other
device. When the pointer names a device that is absent or whose signature contradicts it, the boot
refuses rather than selecting a different device.

**Assembly.** The pointer's readers and writers are **derived, not listed**: the guard walks the
delivered artifacts for every read of `INNGEST_LUKS_ACTIVE_VOLUME_ID` and every write of it, and reds
on one it cannot classify. A hand-listed population is the stale snapshot that is this same defect one
level up — and it would already be stale here, because a draft that named "two sites, the resolver
and the boot-reopen copy" was written before the cutover script became the pointer's writer and the
first-boot stage became its stager, which is four. The
property quantifies over every path from the pointer read to a `mount` call: pointer present and
corroborated, pointer present and contradicted, pointer present and device absent, pointer absent.
It also quantifies over the Redis unit's mount guard, which is conditional on mapper existence and is
therefore **vacuous** on exactly the fall-through this guard exists to make unreachable.

**Mutation matrix**

| # | Mutation | Must drive RED because |
| --- | --- | --- |
| 1 | Replace the pointer read with a signature-precedence rule. | This is the rejected first draft: with the encrypted device absent it falls through to the plaintext arm, no mapper exists, the Redis guard is vacuous and passes, and Redis takes writes on a stale plaintext AOF. A loud, data-safe failure becomes a quiet, data-unsafe one. |
| 2 | Make "pointer names a device that is absent" fall through instead of refusing. | Same failure, reached by a different door. |
| 3 | Drop the corroboration check, so a pointer naming a device whose signature is `ext4` still mounts it. | The pointer would then be able to certify a plaintext mount as the encrypted one. |
| 4 | Apply the pointer in the first-boot resolver but not in the boot-reopen copy, or add a fifth reader the guard has never seen. | The property is over every reader, and the second half is the row that makes the population derived rather than pinned. |
| 5 | Remove the resolver's dispatch from the suite. | Anti-vacuity floor on the guard itself. |
| 6 | Change the fstab writer back to append-if-absent. | A lifetime property: the stale plaintext line survives and wins on the next boot, which no case that reads fstab only after the swap can observe. |

**Harness rows.** (a) Point the suite at a fixture with the pointer stripped — it must red rather
than silently grading the pre-cutover arm as if it were the post-cutover one. (b) A must-PASS
non-canonical input: a **plaintext-only** boot with the pointer absent and one device attached must
PASS and behave byte-identically to today's tree, which is the regression row this change earns by
editing a live state machine rather than adding beside one.

**Anchor.** The pointer is a value the cutover writes and the resolver reads, both in this repo, so
one change could move both. The outside anchor is the probe: `data_mount_devid` is emitted by the
host from its own resolved device, independently of the pointer, and the ledger row's
`reevaluate_when` already pins it. A resolver that mounted the wrong device would be contradicted by
a field nothing in this change authors.

## Risks and Sharp Edges

- **The cloud-init payload cap is a host-killer, and the merge path cannot see it.** The
  `-target=` set on the merge apply names no `hcloud_server`, so Terraform never plans the resource
  and never submits the payload for validation. An oversized template therefore merges green and
  surfaces on the next replace, with the host already destroyed. Measured headroom today is
  21880 B stored against a 32768 B cap — **and that cap is not the binding one.** The model-side
  size test carries a tighter budget of 18000 B against the same measured 10888 B, so a change can
  clear the vendor cap and still fail CI. Prose inside the `.yml` costs bytes; prose in the `.tf` is
  stripped and free.
- **A new secret name in `soleur-inngest/prd` bricks the next boot.** The boot isolation self-check
  is EXACT-SET: it counts non-`DOPPLER_` names and requires the count to equal the count matching its
  admitting pattern. `INNGEST_REDIS_LUKS_KEY` is already admitted. **Neither `INNGEST_LUKS_CUTOVER` nor
  `INNGEST_LUKS_ACTIVE_VOLUME_ID` is**, and admitting both must land in the same commit as the
  resources that create them. Admitting a name
  before the secret exists is a no-op for a subset test, so the admission is free of ordering hazard
  in that direction and fatal in the other.
- **`inngest-host-replace` aborts on sight of an unregistered attachment.** The new attachment
  interpolates `hcloud_server.inngest.id`, so a server replace forces it into the plan. If it is not
  in both the dispatch's `-target=` set and `inngest-host-replace-gate.sh`'s allow-set, that gate
  counts it `out_of_scope` and refuses — turning a routine replace into a dead end.
- **The loopback suite's `sed` rebinds are non-global.** They substitute a single `DEV=` literal. A
  second `DEV=` reader in the same file leaves the staging path unsubstituted, and the suite passes
  while exercising only the live arm. Widen the substitutions and assert each landed.
- **The structural suite splits the file on the first heredoc opener.** A second
  `doppler run … bash -s <<'LUKSEOF'` block would leave the range extraction capturing only the first,
  so its assertions would grade the wrong text. Either reuse the existing heredoc or move the split
  to a form that counts both.
- **The fstab idempotency guard is whole-mountpoint.** Every existing writer is
  `grep -q ' /mnt/data ' /etc/fstab ||` append-if-absent, so the plaintext line survives forever and
  wins on the next boot unless the swap **replaces** it rather than appending beside it. `nofail`
  must be retained on the replacement — a strict fstab turns a slow device attach into an
  unrecoverable boot wedge on a host with no console.
- **`inngest-redis.service` comes from the OCI image, not from cloud-init.** Changing the unit means
  rebuilding the image and re-pinning the digest — a slower change class. The mount-swap needs no
  unit edit, because every path in the unit is `/mnt/data/redis`, addressed by path rather than by
  device. What does change behaviour is its `ExecStartPre` mount guard, whose second state names the
  literal `/dev/mapper/inngest-redis` unconditionally. That is why the post-cutover canonical mapper
  keeps the bare name — the ledger's LUKS rows use the bare name and its plaintext rows use a `-plain`
  suffix, and the guard, the probe's post-cutover expectation and the ledger row all read the bare
  one. The staging mapper's distinct name is a consequence of that, not a preference.
- **`Persistent=true` on the timer would re-enter the sequence after a mid-window reboot.** It is
  safe on the sibling timer because those states are idempotent flag reads. Here a missed run fires
  at boot, so a host that reboots mid-window would re-enter before anyone had read the abort. It is
  therefore dropped, not copied.
- **`/mnt/data-luks` now names two different things in the estate.** The literal is already the
  workspaces cutover's staging path. Different host, so no runtime collision — but any grep-keyed
  guard or shared harness on that literal now matches two hosts' code. Either use a distinct staging
  path or record the collision where a guard would trip over it.
- **The `-target=` extension and the plan-shape gate must land in the same commit.** Between a phase
  that adds the addresses to the dispatch sets and a phase that ships the gate, a dispatch could
  create the volume graded only by the generic additive-only check. Intra-PR, so low severity, and
  free to avoid by ordering.
- **Inferring intent from a disk signature fails OPEN on this host.** The first draft's
  "`crypto_LUKS` wins, else `ext4`" rule looks fail-safe and is not: with the encrypted device
  absent it selects the plaintext one, no mapper exists, and the Redis unit's mount guard — which is
  conditional on mapper existence — is vacuous and passes. Redis then takes writes on a stale
  plaintext AOF. Two independent reviewers named this; neither was reading the other.
- **The tighter byte budget is not the Hetzner cap.** The Terraform precondition asserts 32768 B
  stored, but `plugins/soleur/test/cloud-init-user-data-size.test.ts` carries
  `INNGEST_GZIP_BUDGET = 18_000` against a measured 10888 B. A change can pass the cap and fail the
  test. Both are acceptance criteria.
- **A polled mutable flag is level-triggered.** Left set, re-read, or re-polled after a restart, a
  naive unit re-fires and copies the stale plaintext store over the migrated encrypted one —
  destroying in-flight jobs after the cutover was reported green. What prevents it here is the
  terminal-state no-op arm the sibling FSM already implements, plus the completion latch and the
  absent `Persistent=true`. An epoch token was proposed for this and cut: a fourth mechanism for a
  property three already bought.
- **Adding the new addresses to the `inngest-host` or `inngest-volume-recut` `-target=` lists does
  NOT satisfy the coverage test.** `stripDispatchJobs` removes both of those jobs from the parity
  test's view. `inngest_host_replace` is not stripped, so its list does count — but the intended
  answer is the exclusions set, and the exclusions set is what the test reads.
- **A copy scoped to `redis/` silently disarms the FLUSHALL guard.** The flip FSM's monotonic latch
  lives at `/mnt/data/inngest-cutover/flip-done.latch` on the same durable device. It is what makes a
  second `FLUSHALL` refusable, and a swap onto a device without it is indistinguishable from a host
  that was never flipped. Copy the whole mount and assert the latch path by name.
- **Two flags whose names rhyme mean opposite things.** `INNGEST_CUTOVER_FLIP` at `done` is the
  correct, permanent terminal state for a serving host — and it is exactly why
  `apply_target=inngest-volume-recut` returns `flag_unsafe` and can never fire. The additive path
  never invokes that dispatch, never `-replace`s the live volume, and therefore never has to pass
  G19. **Do not drive the flip flag to `rolled-back` to satisfy a gate this plan does not use** —
  that path stops the prod scheduler and is the recorded latch-erasure hazard.
- **Neither dispatch retires the other.** ADR-199 and ADR-142 govern disjoint worlds and a gate
  decides which world the dispatch is in at dispatch time. This plan does not retire
  `inngest-volume-recut`; that is a separate decision with its own evidence.
- **The gate-extraction debt comes due here.** `tests/scripts/lib/registry-luks-recut-gate.sh`
  carries a marker asking for a shared allow-set and counter scaffold once enough near-identical
  destroy-guards exist. `inngest_luks_additive_gate` is a candidate, and it is the only new gate library
  this plan ships — the detach gate was cut with the detach. The position taken here is to
  **ship one more and not pay the extraction in this PR**, because the shared scaffold would be
  authored from a population of gates whose allow-sets differ on the one axis that matters (whether a
  first passphrase create is legal), and getting that wrong generalises a data-loss guard. Recorded
  rather than skipped; a tracking issue is filed with the re-evaluation criterion.
- **`Ref`, never `Closes`.** The apparatus merges inert and the ledger flip waits on an observed
  cutover boot. `Closes #6894` in the PR body would auto-close at merge, before the remediation runs,
  producing a false-resolved state on the highest-sensitivity plaintext row in the ledger.
- **The linter over this directory rejects an actor token beside an infrastructure imperative, on
  the same line or an adjacent non-blank one.** `cryptsetup`, a filesystem attach verb, a device
  attach phrase and a `-target` apply phrase are all imperatives, and they are the working vocabulary
  of this plan. That is why this document says "the dispatch" and "the reviewer-gated dispatch"
  throughout rather than naming a human actor, and why the post-merge acceptance subsection is
  headed by the dispatch rather than by a role.

## Non-Goals

- Flipping the `hcloud_volume.inngest_redis` ledger row's `mechanism` to `luks`. Its own
  `reevaluate_when` forbids it until a cutover boot is observed.
- Dispatching anything. This plan produces an apparatus, its guards and its records. Every live
  mutation is a separately-gated event.
- Touching `hcloud_volume.inngest_redis` or its attachment. The device stays attached; Fork B
  explains why a detach would be undone by the next routine dispatch and why a detector ships in its
  place.
- Key escrow. ADR-142 rejects it for this store with reasoning this plan accepts: escrow would add a
  sensitive artifact which, together with the Doppler passphrase, yields full plaintext decrypt of
  user prompts and agent output — a confidentiality cost for a durability gain a transient,
  self-healing store does not need.
- Retiring `apply_target=inngest-volume-recut`. It governs a disjoint world and a gate decides which world a dispatch is in.
- Adding a new `apply_target`. The cutover is a Doppler-write op on the existing reviewer-gated workflow.
- Wiping or detaching the retained plaintext device. Both are separately-tracked events with their
  own clearance requirements, and the backstop-wipe tracker carries the window's expiry.

## Domain Review

**Domains relevant:** engineering, legal

The other six were assessed and are not relevant. Product carries no user-facing surface — the
mechanical UI-surface scan over `## Files to Create` and `## Files to Edit` returns nothing, so the
Product/UX gate does not fire and no wireframe is owed. Operations was assessed and declined on a
measured basis rather than a shrug: a second 10 GB Hetzner block volume adds no vendor, no account
and no tier gate, and the recurring cost is immaterial against the expense ledger. Finance, Sales,
Marketing and Support have no surface here.

### Engineering

**Status:** reviewed

**Assessment.** The domain lead confirmed every premise put to it and found three of them worse
than stated. Its headline is a sequencing fact the first draft had not internalised: `runcmd` is
first-boot-only and the server carries no `ignore_changes` on `user_data`, so **both** halves of the
apparatus — the cloud-init resolver and the baked cutover script — are gated on the same host-replace
dispatch. That is not a blocker; it is the spine the sequencing was missing, and once accepted the
design simplifies. The consequence folded into Phase 0 and the sequencing notes: fold the image
digest re-pin into the same merge, so the fleet pays one sole-scheduler outage rather than two.

Rulings adopted in full: Fork P's persisted pointer over signature precedence, with one resolver
rather than two stages; Fork D's image delivery plus an independent flag and FSM, with the
boot-isolation admission as a blocking prerequisite; Fork Q's removal of quiesce from the critical
path; Fork C's three-predicate canary with the hard abort on byte equality rather than a key count;
Fork B's detach-after-verify with an explicit statement that no detach mechanism exists yet. The
ruling against a CI-driven jump-host path is also adopted: it is technically available, and it would
add a root-key mint and a credential surface to a host whose entire posture is "no inbound", to save
work the poll-flag pattern already does.

Two capability gaps were recorded rather than absorbed: there is no gated detach or wipe dispatch
for a retained plaintext backstop anywhere in the repo, and there is no host-local code-delivery
channel to this host short of a replace. The second is out of scope here, and every future change to
this host pays a scheduler outage until it exists.

### Legal

**Status:** reviewed

**Assessment.** Four Critical items, all folded. The sharpest is one the first draft got wrong: the
new volume's ledger row must read `plaintext-exception` at merge, **not** `luks`. At merge the device
does not exist and no byte has been encrypted, so a `luks` row would be a false at-rest claim about
user prompts and agent output in the estate's own accountability instrument — the mirror image of the
recent finding where a measures schedule described access-control policies that did not exist. The
draft had written `luks`. It now reads `plaintext-exception` with its own exception block and its own
`reevaluate_when`.

Second Critical: the existing row's `reevaluate_when` names the recut as the **sole** route to a
flip, which stops being a complete statement of the conditions the moment an additive route exists.
It is amended in-cell, with superseded-markers on the sibling records that say the same thing.

Third: the new volume must carry `location = var.location`, whose validation pins the EU allow-set.
Without it the no-transfer limb recorded for these processing activities loses its basis for a device
holding user prompts. One line of Terraform, a Chapter V consequence.

Fourth: no at-rest claim may be added anywhere at merge. Verified by reading all three canonical
legal documents and all three mirrors — **no document claims queue or job data is encrypted at
rest**, so nothing is false today and nothing may be added. No measures-schedule edit, no
privacy-policy edit, no disclosure edit. After a verified cutover there are two lawful postures, and
keeping the claim unmade is the cheaper one.

Also folded: the absence of key escrow is recorded as an explicit negative in the new row's
`does_not_defend`, with the reasoning that makes it defensible — the residual availability risk is
borne by the controller as lost in-flight jobs, while the confidentiality risk an escrowed header
would add is borne by data subjects. An unexplained divergence between two stores in one estate is an
accountability gap even when the divergence is right.

Two items deliberately **not** at merge: the records register's processing activities for the agent
spawn and leader-prompt runtime must name the AOF as holding prompts and agent output — today the
register's only statement about the device characterises it as not personal-data-bearing, which is
scoped-true where it sits and divergent from what the ledger and both ADRs say — and that is owed
before the cutover, not before the merge. The retained-plaintext residual sentence is owed at
cutover.

### Flow analysis

**Status:** reviewed

**Assessment.** The flow lens read the plan as an operational journey and returned eight blocking
findings, every one measured against the tree rather than inferred. All eight are folded. The three
that changed the plan most:

- **The trigger had no writer.** Fork D named a reviewer-gated write of the new flag and nothing in
  the plan performed it. The dispatch workflow appeared only as "optionally add the read-only ops",
  and the script that actually writes flip-class values was in no file list. The whole sequence was
  unreachable from merge. Both are now first-class edits.
- **The apply path described a boot that does not happen.** `runcmd` is once-per-instance, so the
  additive create reaches no resolver; only a re-provision does. The apply path and the acceptance
  criterion described different sequences, and only one of them worked.
- **The dispatch that reaches the resolver dark-ends the scheduler.** The start guard refuses a prod
  start when the flip flag reads `done` and the host carries no `done-owner` marker — and that marker
  lives on the root disk a replace destroys. The plan analysed that flag at length and never noticed
  that its own required dispatch trips it. The recovery is a named verb that already exists and is now
  an ordered step.

Three more were contradictions inside the document rather than gaps against the tree: the detach was
prescribed by one section, forbidden by a guard's property in another, and excluded by the non-goals
in a third; the observability section asserted every detection reaches Better Stack while the
log-shipper allowlist that makes that true was in no file list; and the rollback path never said what
becomes of the canonical mapper, which on this host is the difference between a retry and a dark
scheduler with no verb able to close it.

### Advisor consult

**Status:** reviewed

**Assessment.** A scoped strong-model consult saw only the overview and the riskiest phase — no
conversation, no repo. It reached the engineering lead's conclusion on the device-selection question
independently and added the sharper framing: the rejected rule replaces a fail-safe failure with a
fail-open one. It also caught what neither the domain review nor the flow analysis did: a level-
triggered flag polled every thirty seconds is an edge-less trigger for an operation that copies an
AOF, so a flag left set or re-polled after a restart re-fires the unit and copies the stale plaintext
store over the migrated encrypted one, after the cutover was reported green. The first response was
an epoch token and a completion sentinel; the simplicity pass then cut both, on the measured ground
that the sibling FSM's terminal states are already idempotent no-ops. The finding was right and the
first remedy was not — recorded that way round, because the consult saw only the overview and could
not know what the shape it was reasoning about already did.

### Architecture review

**Status:** reviewed

**Assessment.** Three blocking findings, all of them a section of this document falsifying another.

The decisive one killed the first version of Fork P. The pointer was to live in a root-disk file, and
the plan itself already contained the fact that made that impossible: two sections later it explains
that the `done-owner` marker "lives on the **root disk** … and cannot survive a replace", about a
different artifact. The pointer's first-boot write is also a truncating single-key redirect, and the
replace is the only delivery path to this host — so the pointer would be erased by the very dispatch
every future change must fire, after which the resolver takes its pointer-absent arm and reaches
exactly the fail-open the fork rejected the signature rule for. Worse, the plan *certified* that arm:
a must-PASS harness row and an acceptance criterion both required "pointer absent, one device
attached" to behave as today, which post-cutover is a passing test for silent un-encryption. The
pointer now lives in the isolated secret store and is staged to the root-disk file as a cache.

The second killed Fork B's detach. A Terraform destroy of a resource still declared in the
configuration is re-created by the next apply that targets it — and the attachment is in the target
set of the dispatch that is mandatory for every future change to this host. The detach would not
merely be reversible; its reversal would be scheduled by the delivery model, and no gate in the plan
could see it, because each gate grades a different dispatch's plan.

The third found Guard 2 anchoring its baseline in the flush latch — the append-only file Fork L exists
to preserve, parsed by two readers — inside the plan whose stated purpose is to keep it intact.

Below those: the cutover dispatch had two mutually exclusive definitions and edits for both, with a
gate modelled on a create shape that cannot occur at cutover time; the unit spec would have forced a
private mount namespace, so every mount it performed would have been invisible to the Redis unit and
would have vanished on exit; the sudoers widening had no caller at all, because the unit is a root
oneshot, while standing as a live capability for the deploy account to unmount the live store; and
the image digest re-pin was circular — a digest folded into the merge that adds the script is
necessarily a digest of an image without it.

All are folded. Two of them made the plan smaller.

### Simplicity review

**Status:** reviewed

**Assessment.** The finding that mattered was not a mechanism; it was a pattern. Four review passes
had each added machinery and none had deleted what it superseded, so six live references pointed at
forks and flags that no longer existed — a guard grading a canary two forks old, a failure mode
detecting a step that had been removed, a risk row about a hazard a design change had dissolved. The
duplication is also *how* they survived: a test-scenario table that restated the guard matrices gave
every superseded row a second place to hide.

Cut, with the property each was supposed to buy re-checked against what already exists: the epoch
token and completion sentinel (the sibling FSM's terminal states are already idempotent no-ops, so
three mechanisms guarded one property); `Persistent=true`, which was the only thing creating the case
the epoch token was invented for; a third test suite the plan's own Cut List forbids and that Fork P
made unnecessary; an orphan dispatch op with no semantics anywhere; a gate-library extension whose
only gain was a better error string on a dispatch this plan never fires; and twenty-one test-scenario
rows reduced to seven.

It also caught the plan shipping knowingly unmet against its own stated requirements: a property in
the property list was bought by the quiesce flag, and Fork Q removed the flag without updating the
property. And it promoted the single largest available cut — the store's key count — from a phase
bullet to acceptance criterion 0, on the grounds that the whole plan is conditional on a number
nobody has read, and only a criterion stops the phases running past it.

### Negative-claim sweep

**Status:** complete. The highest-risk claims were verified by hand first; the automated sweep then
graded every absolute claim in the document.

Verified directly, each with the command that settled it:

- "no `hcloud_*` inngest address is in the per-merge `-target=` set" — **confirmed**, the count is zero.
- "`inngest-redis` appears nowhere in the sudoers file, and no alias grants `cryptsetup`, a mount verb or a copy" — **confirmed**.
- "no document in the legal corpus claims queue or job data is encrypted at rest" — **confirmed** across the canonical documents, their mirrors and the measures schedule.
- "no `apply_target` anywhere is a detach or a wipe" — **confirmed**; the single near-miss is a `verify-wiped-volume` op, which is a durability proof on the other host.
- "`runcmd` is once-per-instance" — **confirmed** from the file's own scoping comment.
- "the boot-reopen script opens only and never formats" — **confirmed**; the only match for a format verb in that window is the comment asserting it.

The automated sweep then returned and graded all fourteen high-value claims plus a dozen secondary
ones. Twelve confirmed. **Two contradicted this plan's own text**, and both were the plan's error
rather than the tree's:

- **The reviewer environment's branch pin was called a defect and is not one.** The
  `deployment_branch_policy` resource exists with `branch_pattern = "main"`, and both addresses are in
  the per-merge target set. The `null` reading the draft was recalling is dated and describes live
  state before the fix. The row also pointed at "the finding below", which did not exist — a dangling
  forward-reference that no reader of that row alone could have caught.
- **The `inngest-host` and `inngest-host-replace` target sets were treated as one set.** They are
  not. The replace set is three targets and the durable volume is *deliberately omitted* so it
  survives — in the workflow's own words. The draft would have added the new volume to both, breaking
  the preserve-by-omission invariant, and it contradicted its own acceptance criterion, which admits
  the volume create-only in the gate. This was the more consequential of the two.

Four further claims drifted rather than failed: "the estate has no destructive apply path" (the recut
target is one), the attribution for the sibling cutover script's read-only state, a missing
"additional" qualifier that made a gate sound unique when it is not, and a key-count trap cited
against the wrong neighbouring primitive. All six are corrected in place, with the superseded reading
kept beside the correction rather than quietly replaced.

**Brainstorm-recommended specialists:** none — no brainstorm preceded this plan.

**Agents invoked:** `soleur:engineering:cto`, `soleur:legal:clo`, `soleur:product:spec-flow-analyzer`, `soleur:engineering:review:architecture-strategist`, `soleur:engineering:review:code-simplicity-reviewer`, `soleur:engineering:review:user-impact-reviewer`, and a scoped strong-model advisor consult

**Skipped specialists:** none

## Test Scenarios

**Deliberately short.** The four guard mutation matrices *are* the test scenarios, and the
guard-contract lint enforces that each carries at least three rows. An earlier draft duplicated them
into a twenty-one-row table, and the duplication is how two rows grading deleted mechanisms — a
quiesce step and a key-count canary — survived three revisions. Only the cases that no guard matrix
and no acceptance criterion already covers are listed here.

| # | Mutation applied to the tree | Expected result |
| --- | --- | --- |
| 1 | Append `format = "ext4"` to `hcloud_volume.inngest_redis_luks`. | Structural suite RED — the discriminator stops being sound when both devices read `ext4`. |
| 2 | Point `doppler_secret.inngest_redis_luks_key` at project `soleur` instead of the isolated one. | Structural suite RED — the isolation boundary is the reason this apparatus may key off a root config at all. |
| 3 | Move `hcloud_volume_attachment.inngest_redis_luks` into `inngest-host.tf`. | Posture lint FAIL — no co-located passphrase pair in the declaring file. |
| 4 | Add `INNGEST_LUKS_CUTOVER` or `INNGEST_LUKS_ACTIVE_VOLUME_ID` to the isolated project without admitting either in the boot isolation pattern. | Host suite RED — the predicate is replayed behaviourally over a name set, and a live miss bricks the next re-provision. |
| 5 | Leave the dispatch workflow's `environment:` ternary unextended while adding the op to the choice list. | Workflow suite RED — the job would run ungated with the write token in hand. |
| 6 | Re-pin a digest for an image built before the cutover script joined its COPY set. | The pre-replace assertion FAILS — the pin resolves to an image without the file. |
| 7 | Remove the new `SyslogIdentifier` from the log-shipper allowlist, or change it in one of the two files. | Suite RED — every observability detection routes through that one exact-value list, and a mismatch is silent. |
| 8 | Delete the mapper close from the rollback contract. | Suite RED — a failed rollback would leave the mapper open, the Redis guard refusing every start, and no verb able to close it. |
| 9 | Add a new sudoers grant for the cutover. | Diff assertion FAILS — the unit is a root oneshot, the host runs no listener, and the grant would have no caller while standing as a live capability. |
