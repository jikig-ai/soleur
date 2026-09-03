---
title: "infra(inngest): build the gated inngest-volume-recut apply_target and recut /mnt/data as LUKS"
date: 2026-09-02
slug: infra-inngest-volume-recut-luks
branch: feat-one-shot-7695-inngest-volume-recut-luks
issue: 7695
tracks: [7695, 7674, 6894]
type: infra
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

The dedicated Inngest host cannot leave its terminal `rolled-back` cutover state because arming
reaches a monotonic flush latch on `/mnt/data` that no repository mechanism can clear. This plan
builds the gated `inngest-volume-recut` apply_target that clears it, and recuts the volume as
LUKS rather than plaintext ext4 in the same change.

No spec.md exists for this branch — spec lacks valid `lane:`, defaulted to `cross-domain` (TR2
fail-closed).

## Deepen-Plan Revisions (2026-09-02)

A two-agent adversarial review found **six defects that made the first draft non-executable**. Each
was verified against source before being accepted; the plan below is the corrected version. Recorded
here because the corrections change the plan's *shape*, not just its detail.

| # | Defect | Verified by | Correction |
|---|---|---|---|
| R1 | **Phase 1 could not be delivered by its own vehicle.** `tests/scripts/lib/inngest-host-replace-gate.sh` allows exactly `hcloud_server.inngest`, `hcloud_server_network.inngest`, `hcloud_volume_attachment.inngest_redis`; `hcloud_volume.inngest_redis` is *"DELIBERATELY ABSENT"* with a `redis_volume_destroyed` backstop, and PASS requires `oos==0 && rdel==0 && replaced==1`. Removing `format` puts a volume replace in that plan (`-target` prunes dependents, not dependencies), so Dispatch A **aborts**. | Read the gate | Split into **two merges**; keep `format` behind `ignore_changes` (R6). **Never widen that gate** — it has no reviewer gate, no confirm, no id-pin, so widening it creates an unguarded second recut path. |
| R2 | **Guard 2 measured the wrong thing.** `redis_keys == 0` is a claim about a Redis *process*, not about the *block device*. The current mount is `mount … \|\| true` + `nofail`, so a failed mount leaves `/mnt/data` on the ephemeral root disk — Redis then reports an empty store while the volume holds a populated AOF. The gate would pass and the destruction would be unsafe. | Read `cloud-init-inngest.yml`; the FSM already carries a `latch-unrecordable detail=not-a-mountpoint` abort for this exact case | Added mount-source, `data_bytes`, and `unknown`-on-error conditions. |
| R3 | **The recut cannot achieve P2 today, and would make things worse.** `record_flush_latch` runs at `inngest-cutover-flip.sh:492` — **before** `verify_or_abort` at `:502`. `verify_or_abort` needs `/health` 200 plus a non-empty function registry. The host cannot bind (`http_code=000`) *even though* `INNGEST_DIAGNOSTIC_BOOT=1` already bypasses the flag allowlist — so the flag is not what keeps it dark. The first post-recut `arm` would write a **fresh** latch, fail verify, and land in terminal `aborted`: latch re-armed, flag worse than `rolled-back`, destructive one-shot spent. | Read the FSM ordering | **#7674 PASS is now a hard precondition of the recut, not a follow-on.** |
| R4 | **No concurrency mutex; a real TOCTOU.** Guard 2 reads rows up to 90 min old; `cutover-inngest.yml op=arm` writes the Doppler flag from a *different* workflow and the on-host timer acts within 30s. Terraform could destroy the volume mid-`FLUSHALL`. `workspaces_luks_recut` carries a `web-1-swap` group; this target had none. | Read both workflows | Added a shared `inngest-cutover` concurrency group and a synchronous pre-apply flag re-read. |
| R5 | **The `crypto_LUKS` reopen is not idempotent across boots.** `cloud-init-inngest.yml` states `runcmd` runs *"on FIRST BOOT ONLY"* and `/run` is tmpfs. On boot 2 nothing calls `luksOpen`, the mapper is absent, the `nofail` fstab line skips, and Redis writes plaintext to the root disk. `workspaces-luks.tf` has the identical unsolved gap (deferred to #6931), so there is **no working precedent to copy**. | Read both files | A boot-reopen systemd unit is now a **deliverable**, not an assumption. |
| R6 | **Removing `format` disables `apply_target=inngest-host` for the whole window.** That target carries an additive-only guard (*"a net-new host provisioning must create, never destroy"*), so a queued volume replace makes it **permanently abort** — disabling the recovery dispatch for a host that is already not serving, indefinitely if Guard 2 refuses. | Read the guard | `lifecycle { ignore_changes = [format] }` until the recut branch drops it. |

Two further corrections of my own reasoning: the stated rationale for removing `format`
("`ext4` makes a fresh volume byte-indistinguishable from a populated one") was **wrong** —
`git-data-luks.tf` keeps `format = "ext4"` and `luksFormat`s straight over it. The correct
precedent is zot/registry's Option B, chosen *because the registry has a volume-preserving
host-replace dispatch*, which inngest also has. And `L = 0` is a **property of today**, not a
standing one: after a successful post-recut flip, `record_flush_latch` emits fresh rows and G3.7
will refuse the next `op=arm` within retention.

## Research Insights

### Premise Validation (Phase 0.6) — every cited reading re-measured 2026-09-02

All measurements taken this session via `doppler run -p soleur -c prd_terraform -- bash
scripts/betterstack-query.sh`, the Hetzner API, `doppler secrets get`, and `gh api`. No SSH.

**CONFIRMED as briefed:**

| Premise | Live reading |
|---|---|
| Host dark, never served | `SOLEUR_INNGEST_SERVER_PROBE` @19:44:46Z: `server_active=inactive http_code=000 vector_active=active redis_active=active uptime_s=1191133 boot_id=cb4e3bb0-b625-45d4-8da1-dde39e4a7dbe cutover_flag=rolled-back` |
| Doppler flags | `soleur-inngest/prd`: `INNGEST_CUTOVER_FLIP=rolled-back`, `INNGEST_DIAGNOSTIC_BOOT=1` |
| `rolled-back` is terminal | `inngest-cutover-flip.sh` header: "`done / rolled-back / aborted / unset` idempotent no-op, exit 0" |
| Latch path + mount gate | `LATCH_FILE="${INNGEST_CUTOVER_LATCH:-/mnt/data/inngest-cutover/flip-done.latch}"`, `LATCH_REQUIRE_MOUNT="${INNGEST_CUTOVER_LATCH_MOUNT-/mnt/data}"` |
| Volume predates the flip, never recut | Hetzner `106261946`: `created=2026-07-07T23:51:07Z size=10 format=ext4 server=162809678 location=hel1` |
| G3.7 fails open | Measured L (flush-latch evidence, 365d) = **0**; H (flip-FSM liveness, 15m) = **20**. `flush_latch_decide(0,20)` → `clear` → gate **PASSES** |
| Live scheduler is web-1 | `function.finished` over 2h: **18 rows, 18/18 `host_name=soleur-web-platform`, 0 from soleur-inngest** |
| Nothing clears the latch today | `apply_target` options list has no inngest volume recut; `inngest-wiped-volume-verify.sh` `DATA_DIR="${INNGEST_DATA_DIR:-/var/lib/inngest}"` |
| Reviewer set non-empty | `gh api .../environments/inngest-cutover` → one required reviewer, `deruelle` (54279). Terraform-backed: `github_repository_environment.inngest_cutover` `reviewers { users = [54279] }` |

**CORRECTED — six premises did not survive measurement (four from the brief, two from my own
first-pass reasoning):**

1. **G3.7's blindness is RETENTION, not an ingestion stoppage.** The brief says "Better Stack
   ingestion for that channel stopped 2026-08-14". It has not: H=20 rows arrived in the last 15
   minutes. Measured warehouse floor — whole table, ungrepped: `oldest=2026-08-13 15:14:14`,
   `newest=2026-09-02 20:15:16`, `n=2855466`. Retention is **~20 days**. The flip completed
   2026-07-23/24, roughly **20 days before the oldest retained row**. The conclusion is not
   merely preserved, it is *strengthened*: L can **never** observe that flip, and no narrowing of
   `FLUSH_LATCH_SINCE` recovers it, because the row is not in the warehouse at all. G3.7's own
   text already concedes this — "Better Stack retention against a 365d window is UNMEASURED". This
   plan measures it.

2. **Layer B does not exist.** The brief says "Layer B is `cron-encryption-posture-reconcile.ts`".
   `git ls-files | grep encryption-posture` returns no such file, and **ADR-141** (`status:
   adopting`) records Layer B as **deliberately deferred** ("no runner-reachable live signal
   today"). Only **Layer A** (`scripts/lint-encryption-posture.py --repo-sweep`) plus the ledger
   row are in scope. Registering the new store in a Layer B reconciler is **cut**.

3. **R2 header escrow is explicitly REJECTED for this store.** The brief names
   `workspaces-luks-header.tf` as a precedent to copy. **ADR-142** rejects escrow here by name:
   "No key escrow (git-data-lean shape)… Escrowing the header would **add** a sensitive artifact
   (which, with the Doppler passphrase, yields full plaintext decrypt of user prompts/agent
   output) — a net **increase** in confidentiality attack surface for a durability gain this
   transient store does not need." Copying it would silently reverse an accepted ADR. See
   Decision Challenges.

4. **Uptime is 13.8 days, not three weeks.** `uptime_s=1191133` ⇒ boot ≈ 2026-08-20 00:52, which
   matches the flip channel's oldest row (`2026-08-20 00:53:27`) to the minute. The host is a
   **replacement** provisioned 2026-08-20; the latch was written by its **predecessor** in July and
   rode the re-attached volume across. The narrow claim (this host has not rebooted and has not
   served since 2026-08-20) holds — but see correction 5 for what it does **not** license.

5. **"Never served" is measured over the WRONG WINDOW — my own overreach, and the brief's.**
   The brief reasons "the host has not rebooted and has never served" and uses it to retire the
   risk that the July flip left recoverable state. It cannot. The current host **booted
   2026-08-20**; the flip completed **2026-07-23/24**, on a *previous host generation*. The
   evidence window therefore begins ~4 weeks **after** the window of concern, and extending it
   backward is exactly the failure mode
   `2026-08-25-i-wrote-the-evidence-down-and-then-concluded-the-opposite.md` records. The
   `server_active=inactive` reading is true and useful; it simply does not speak to July.
   **Consequence:** the question "was a FLUSHALL ever performed on this volume?" remains
   **UNMEASURED**, and the historical form of it is unanswerable (Better Stack retention is ~20d;
   July dispatch outcomes are gone by construction). The plan replaces it with the present-tense
   question, which is answerable and sufficient — see Phase 1.

6. **The CI-side `L` signal is already 0, so it is not a second blocker.** A design review raised
   that destroying the volume cannot decrement G3.7's `L` (Better Stack rows are immutable), and
   that a remediation leaving half the blocker standing is no remediation. The reasoning is sound
   but the premise is not: **L is measured at 0 today**, so G3.7 already returns `clear` and is
   already passing. The only standing blocker is the on-host latch. `L` is a weak pre-filter that
   can only ever ADD a refusal, and it decays by age-out, never by remediation. Recorded so the
   next reader does not mistake it for a second thing to fix.

**MECHANISM-vs-ADR conflict (Phase 0.6 step 4) — the load-bearing finding.**
**ADR-142** (`status: accepted`) decides an **additive blue-green byte-copy** migration for this
exact volume and forbids the briefed mechanism outright: "A `-replace` of
`hcloud_volume.inngest_redis` is ForceNew → a new empty volume → **every in-flight job lost**."
**ADR-100** §What remains open (later) blesses the destructive path conditionally: the
`inngest-volume-recut` design, "five guard layers including a 'host is dark' pre-flight refusal
absent from the `workspaces-luks-recut` template it is modelled on".

ADR-142's premise (sole-copy *live* in-flight data) is **in doubt but NOT falsified** — correction 5
above is precisely why. The resolution is therefore not "override ADR-142" but "**measure the thing
ADR-142 assumed, and make the answer a gate**": the destructive path is authorized only on a
measured-empty store, and ADR-142's byte-copy remains mandatory otherwise. Both the ADR-142
addendum and the new ADR recording that bound are deliverables of this plan (Phase 2.10), not
follow-ups.

### The blocker is exactly ONE arm — traced, not assumed

`flush_already_performed()` is a **disjunction over two** records, which the brief does not mention.
Both must be false for an arm to proceed:

- **Arm (a) — `/mnt/data/inngest-cutover/flip-done.latch`.** Append-only, monotonic, and on the
  volume *specifically so it survives a host replace*. This is the standing blocker, and only a
  recut (or an equivalent authorized clear) removes it.
- **Arm (b) — `/var/lock/inngest-cutover-flip.state` with `.flag == "done"`.** **Already false**,
  for two independent reasons the source states outright: `emit_state()` stamps the slot on *every*
  branch, and *"the `rolled-back` arm writes `{"flag":"rolled-back"}` straight over the `done`
  record"* — which is the live value today. Separately, *"`/var/lock` is the ephemeral root disk, so
  a host replace wiped the slot."*

So the recut plus the host replace clear both arms, and arm (b) needs no work. This also settles a
tempting wrong turn the source flags explicitly: relocating the erasable slot onto the durable
volume — *"the obvious 'make the latch survive a replace' fix"* — would make things **strictly
worse** by persisting the erasure, *"converting a latch that fails safe by amnesia into one that
fails unsafe by false memory."* The plan does not touch arm (b).

Corollary, and the reason Phase 1 is not optional: since arm (b) is already false and arm (a) is
invisible off-host, **nobody can currently tell whether the system is blocked at all.** The
measured `L = 0` means G3.7 passes, so the CI side is not blocking either. The entire question
reduces to one unreadable file — which is exactly what Phase 1 makes readable.

### Property List (Phase 0.6b)

- **P1** A standing `/mnt/data` flush latch can be cleared by an in-repo mechanism.
- **P2** The cutover FSM *becomes able* to leave terminal `rolled-back` without aborting into
  `aborted`. This plan removes the latch blocker and builds the gated capability; it does **not**
  leave the state — arming is a separate operator decision at the window. And removing the latch is
  necessary but **not sufficient**: `record_flush_latch` runs before `verify_or_abort`, so until
  #7674 is fixed the first `arm` would re-write the latch and land in `aborted` anyway. #7674 PASS
  is therefore a precondition of the recut, enforced by Guard 2 condition 10.
- **P3** The AOF volume holding user prompts/agent output is encrypted at rest, flipping the
  ledger row from `plaintext-exception` before its `expires_on: 2026-10-22`.
- **P4** The destructive capability cannot fire without human authorization, and cannot fire by
  typo or mis-dispatch.
- **P5** The destructive capability cannot fire against a host that is actually serving.

### Cut List (Phase 0.6b) — mechanisms removed before research

| Mechanism | Property it would buy | Why cut |
|---|---|---|
| `cron-encryption-posture-reconcile.ts` registration | posture reconciled against live state | File does not exist; ADR-141 defers Layer B deliberately. Grepped the authority (`git ls-files`), not a consumer. |
| R2 header-escrow bucket (copy of `workspaces-luks-header.tf`) | LUKS header survives header-region corruption | **Cut — decided, not pending.** ADR-142 rejects it for this store by name on confidentiality grounds, and the CTO ruling confirmed it categorically. See §Escrow and Decision Challenge 1. |
| Webhook latch readback (`cat-inngest-cutover-state.sh` behind a webhook id) | latch readable off-host | ADR-100 Decision 6a stands unamended; declined 2026-08-25 in favour of the Vector→Better Stack substitution. **Also moot:** a recut clears the latch unconditionally, so its prior state stops being a question you must answer. |
| New reviewer-gated environment | human authorization | Already exists — `github_repository_environment.inngest_cutover`, reviewer set verified non-empty. Reuse. |

### Reusable precedents (do not invent new shapes)

- **Escape hatch:** `apply_target=workspaces-luks-recut` in
  `.github/workflows/apply-web-platform-infra.yml` — `environment:` gate + typed `confirm` +
  `terraform plan -replace=<vol> -target=<vol> -target=<attachment>`. `server.tf` documents why
  `prevent_destroy` is omitted from the recut target: "*it collides with the
  `apply_target=workspaces-luks-recut` `-replace` escape hatch (prevent_destroy errors on
  -replace)*".
- **Destroy guard:** `tests/scripts/lib/workspaces-luks-recut-gate.sh` — sourced by BOTH the
  workflow step and its test so the decision logic is the same bytes. Carries the fail-closed
  `plan-gate-preamble.sh` (`assert_readable` / `assert_classifiable` / `assert_numeric`), an
  **ID-PIN** binding destruction to an operator-supplied physical volume id, named-live backstop
  counters, a 4-verb positive-action filter, and a **recovery bare-create arm** (`before == null`)
  for a stranded destroy-before-create.
- **LUKS volume:** `hcloud_volume.workspaces_luks` — **deliberately no `format` attribute**, so the
  device is raw and `blkid -o value -s TYPE` is a sound discriminator ("format only a device with
  NO filesystem signature"). `format = "ext4"` would make a fresh volume byte-indistinguishable
  from a populated one.
- **Ledger row:** `scripts/encryption-posture-ledger.json`, `hcloud_volume.workspaces_luks` —
  `device_binding{volume,attachment,mapper}` + `at_rest{mechanism,evidence,defends_against,
  does_not_defend,disclosed_as,live_verification}`. `lint-encryption-posture.py` resolves the
  citation structurally (attachment's `volume_id` must literally reference the volume; a
  co-located `random_password` + `doppler_secret` pair; a real `luksFormat`/`luksOpen` apparatus;
  mount evidence) — never by name similarity.
- **ADR-142 apparatus scope** already enumerates the intended resources:
  `random_password.inngest_redis_luks` (len 40, `special=false`), `doppler_secret.
  inngest_redis_luks_key` → `INNGEST_REDIS_LUKS_KEY` on the existing isolated `soleur-inngest/prd`,
  and the mapper name `inngest-redis`.

### Institutional learnings that change the design

| Learning | What it forces here |
|---|---|
| `2026-07-17-workflow-env-gate-references-unprovisioned-environment-auto-approves.md` | A YAML `environment:` line is not an environment. A missing/zero-reviewer environment **auto-approves silently**. Verified non-empty live AND Terraform-backed; add an assertion so it stays non-empty. |
| `2026-07-23-terraform-destroy-guard-address-vs-physical-id-and-replace-recovery-arm.md` | Authorize by **physical id**, not terraform address — state corruption makes every address counter read 0 while the wrong volume dies. Also: accept the bare-create recovery shape or re-dispatch loops forever. |
| `2026-07-24-guest-luks-store-must-gate-consumer-on-mount-and-guard-suite-must-pin-fail-loud-semantics.md` | Encrypting is necessary, not sufficient: the consumer must **re-assert the mount and fail loud** before serving, or a failed encryption boot degrades silently onto the root disk. |
| `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md` | `luksFormat`+`luksOpen` without `mkfs` leaves a mapper with no filesystem; an unguarded `mount` under `set -uo pipefail` **without `-e`** swallows it. Guard each fs op explicitly. |
| `2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect.md` | A heartbeat proves the timer fired, nothing else — this host beat green for 12 days while serving zero dispatches. Any new liveness assertion must name the port/process, not the timer. |
| `2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist.md` | Every new `logger -t <tag>` must be added to `vector.toml` Source 4 `include_matches.SYSLOG_IDENTIFIER` **and** its drift fixture in the same change, or the marker never leaves the deny-all-public box. |
| `2026-08-20-making-op-arm-idempotent-opened-the-window-the-refusal-was-holding-shut.md` | The `armed` value sits inside `inngest-server-flip-guard.sh`'s prod-start allowlist; removing a refusal opens states other guards' allowlists still accept. |
| `2026-07-07-immutable-redeploy.md` | A server `-replace` must also `-target` its attachments (`hcloud_server_network`, `hcloud_volume_attachment`, `hcloud_firewall_attachment`); a fresh host may boot with its private NIC down. |

### Registration sites for a new `apply_target` (all FIVE, or the gate is silently partial)

1. `.github/workflows/apply-web-platform-infra.yml` — the `options:` list **and** the job. Issue
   #7695 requires these be **bound**, so the option cannot exist without its guarded job.
2. `plugins/soleur/test/terraform-target-parity.test.ts`.
3. `plugins/soleur/test/stock-preflight-coverage.test.ts` (`EXCLUSION_ALLOWLIST`).
4. `scripts/test-all.sh` — `run_suite "tests/scripts/<name>-gate" bash tests/scripts/test-<name>-gate.sh`.
5. **`.github/workflows/infra-validation.yml`** — the site the four-site list I first derived
   **missed**, and the one issue #7695 calls out by name: *"Ship a `*.test.sh`, **registered in
   `.github/workflows/infra-validation.yml`** — an unregistered infra suite silently never gates."*
   Confirmed real: that workflow already registers `cutover-inngest-workflow.test.sh`,
   `inngest-dedicated-host-classify.test.sh`, `workspaces-luks-verify-workflow.test.sh` and others
   by name. An `apps/web-platform/infra/*.test.sh` that is not listed there never runs in CI.

The full-suite exit gate, not the touched-file loop, is what catches a missed registration — and
site 5 is exactly the orphan-suite class that gate exists for.

### The design is already written — inherit it, do not re-derive it

`knowledge-base/project/plans/archive/20260825-134550-2026-08-25-fix-inngest-host-not-serving-and-latch-gate-blindness-plan.md`
§Phase 3 carries the complete `inngest-volume-recut` design, deferred to "the PR that opens the
cutover window" — which is this one. Constraints taken from it verbatim rather than reinvented:

- **Name it `-volume-`, not `-luks-`.** `hcloud_volume.inngest_redis` is `format = "ext4"` with zero
  LUKS apparatus, so inheriting the template's name would assert a posture the volume does not have.
- **A typed confirm literal distinct from every existing one** (`RECUT-WORKSPACES-LUKS`,
  `RECUT-REGISTRY-LUKS`, …), so a token typed for another target cannot authorize this one. This
  plan uses `RECUT-INNGEST-VOLUME`.
- **A distinctly-named `expected_inngest_volume_id` input**, matched `^[0-9]+$` — not a shared id
  input, because sharing one across targets makes a wrong-volume mis-dispatch a typo rather than an
  impossibility.
- **Input budget:** `workflow_dispatch` caps at **10 inputs and 7 are used**;
  `expected_inngest_volume_id` spends slot 8, leaving two. The workflow's own convention note says
  the next per-target input *pair* should split into a dedicated workflow rather than spend the
  last two slots — so this target must not add a second input.
- **A job-level `concurrency` mutex.**
- **No `[ack-destroy]` bypass.** The environment reviewer approval is the authorization
  (`hr-menu-option-ack-not-prod-write-auth`); the typed token and the id pin are *typo-guards* and
  must be labelled as such.
- **Inherited cost, stated rather than discovered later:** a reviewer gate on this workflow has
  previously left apply runs `waiting` up to 13h while holding the workflow-level concurrency group
  (`cancel-in-progress: false`), blocking sibling applies. `workspaces_luks_recut` already accepts
  this trade; so does this target.
- **The dark-check reads the FLAG as well as the probe:** refuse unless the flag is readable **and
  outside `{armed, flipping, flushed, done}`** — every value in `inngest-server-flip-guard.sh`'s
  prod-start allowlist — *and* the latest probe row shows the host not serving.

### Conventions carried forward

- `hr-no-ssh-fallback-in-runbooks` / `hr-no-dashboard-eyeball-pull-data-yourself`: every reading
  above came from a scripted query, and the plan's probes must too.
- `hr-menu-option-ack-not-prod-write-auth`: a commit trailer is not authorization for a prod write;
  the environment reviewer gate is.
- `hr-tf-variable-no-operator-mint-default`: the LUKS passphrase is a `random_password`, never an
  operator-minted variable.
- `cq-test-fixtures-synthesized-only`: guard fixtures are synthesized plan JSON, never captured
  production plans.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Measured reality | Plan response |
|---|---|---|
| "Better Stack ingestion for that channel stopped 2026-08-14" | Channel is live (H=20 rows in 15m). Warehouse floor is `2026-08-13 15:14:14` — **~20d retention**, table-wide. | Reframe G3.7's blindness as a **retention floor**, not an outage. The 2026-07-23/24 flip is ~20d outside retention, so L is structurally incapable of seeing it. Record the measured floor in ADR-100, which currently calls it "UNMEASURED". |
| "Layer B is `cron-encryption-posture-reconcile.ts`" | No such file. ADR-141 (`status: adopting`) **defers** Layer B — "no runner-reachable live signal today". | **Cut.** Scope reduces to Layer A (`lint-encryption-posture.py --repo-sweep`) + the ledger row. |
| "the R2 header-escrow bucket in workspaces-luks-header.tf" is a precedent to copy | ADR-142 **rejects** escrow for this store by name, on confidentiality grounds. | **Cut**, pending the CTO ruling recorded below. Raised as a decision-challenge, not silently reversed. |
| "Same boot_id as three weeks ago" | `uptime_s=1191133` ⇒ boot ≈ 2026-08-20 00:52, matching the flip channel's oldest row to the minute. **13.8 days.** | Corrected. The host is a **replacement**; the latch rode the re-attached volume from its predecessor. Material claim (never rebooted, never served) stands. |
| "Mirror the workspaces-luks-recut escape hatch" | That gate requires the passphrase be **UNTOUCHED** (it reuses an existing header). Here the passphrase is a **first provision**. | The gate is a **hybrid**: volume-replace semantics from `workspaces-luks-recut-gate.sh`, passphrase-**first-create** semantics from `workspaces-luks-cutover-gate.sh`. Stated explicitly so the inversion is not copied wrong. |

## User-Brand Impact

**If this lands broken, the user experiences:** a destroy-guard scoped one address too wide fires a
`terraform -replace` against `hcloud_volume.workspaces["web-1"]` — the live, sole-copy `/workspaces`
volume holding every user's repositories and agent working state — and the product is gone with no
backup. The nearer-term failure is milder but still user-visible: a LUKS mount that fails open
leaves Redis writing its AOF to the ephemeral root disk, so the next host replace silently discards
every queued job and armed reminder, and scheduled work stops firing with no error surface.

**If this leaks, the user's data is exposed via:** the AOF on this volume holds **in-flight job
payloads — user prompts and agent output** (ADR-142, the encryption-posture ledger's
highest-sensitivity row). Today it is plaintext ext4: a seized, RMA'd, or snapshot-imaged Hetzner
block volume yields those payloads directly. A LUKS passphrase written to the wrong Doppler project,
or a header escrowed next to its own key, converts an at-rest control into a single-artifact
compromise.

**Brand-survival threshold:** single-user incident

Consequences of that threshold, per the plan skill's staging model: `requires_cpo_signoff: true` in
frontmatter; `user-impact-reviewer` is invoked at review time; the eng plan-review panel escalates
to include `architecture-strategist` and `spec-flow-analyzer`.

## Open Code-Review Overlap

**None.** Queried all 63 open `code-review` issues (`gh issue list --label code-review --state open
--json number,title,body --limit 200`) against every path in Files to Edit / Files to Create —
`inngest-host.tf`, `cloud-init-inngest.yml`, `apply-web-platform-infra.yml`,
`encryption-posture-ledger.json`, `cutover-inngest.sh`, `inngest-cutover-flip.sh`, `test-all.sh`.
Zero bodies matched any path.

## Architecture Decision (ADR/C4)

This plan **changes an accepted architectural decision**, so the ADR work is a deliverable here, not
a follow-up (`wg-architecture-decision-is-a-plan-deliverable`).

### ADR

Two distinct instruments, because this repo's convention — visible in both ADR-100 and ADR-142 —
is **addenda for observations, new ADRs for decisions**. Conflating them is what would leave the
encryption-posture ledger's provenance pointing at a document that no longer says what it said.

**(a) Addendum-in-place to ADR-142 — records measured fact, changes no decision.** ADR-142's
Context is written in the present tense about a live queue with armed reminders at arbitrary future
fire-times. That premise is now materially in doubt: the host has not served across the whole
observable window, `INNGEST_CUTOVER_FLIP=rolled-back` is terminal, and the store's occupancy is
**unmeasured**. A reader today would size the quiesce/canary work against a premise that may be
empty. The addendum states what is measured and what is not — including that the historical
"was a FLUSHALL ever performed" question is unanswerable at ~20d retention. It does **not** touch
ADR-142's `## Decision`. Small.

**(b) A NEW ADR for the decision this plan actually makes** — **ADR-199**.

> **Superseded 2026-09-03 (#7695):** this paragraph originally read *"provisionally ADR-198, the
> next free ordinal measured across all 64 `origin/*` refs (highest seen: ADR-197)"*. That reading
> was correct when taken and is stale now. Re-derived at merge across **67** refs: ADR-198 is
> claimed by the open branch `feat-one-shot-7460-betterstack-baked-token`, so the next free ordinal
> is **199**. The ordinal above has been advanced (the plan declared it provisional and instructed
> exactly this re-derivation); the original measurement is preserved in this note rather than
> overwritten, and the full record is in `## Addendum — 2026-09-03 (#7695, Merge B as delivered)`.

> *No-SSH authorized clearance of the inngest monotonic flush latch, bounded by a measured
> empty-store precondition.*

Its Decision: the destructive recut is authorized **only** when the store is *measured* empty and
the host *measured* dark on the same probe row; ADR-142's byte-copy remains mandatory otherwise.
This is not a reversal of ADR-142 — it is the branch ADR-142 never had to consider, because when
ADR-142 was written the store was presumed live. The two coexist: ADR-142 governs a populated
store, ADR-199 governs a provably empty one, and the gate decides which world you are in **at
dispatch time** rather than at authoring time.

**Why the bound, and not a blanket override.** The reasoning that "a re-flip `FLUSHALL`s Redis
anyway, so a recut and a latch-clear converge" is correct *only if the store is empty or its
contents are about to be flushed regardless*. It does **not** license destroying unmeasured state:
dormancy is a property of the host and is reversible (a host replace re-attaches this same volume);
a `-replace` is a property of the bytes and is not. So the plan does not assert the store is
empty — it **builds the channel that can say**, and makes the answer a precondition.

Also recorded in the new ADR:
- The measured Better Stack **retention floor (~20 days)**, retiring ADR-100's "retention against a
  365d window is UNMEASURED" with a number and the command that produced it.
- That `L`'s polarity **inverts** between `op=arm` (L≥1 ⇒ REFUSE) and `op=resume` (L≥1 ⇒ G2
  precondition SATISFIED), so any change to latch semantics must be reasoned through both.
- The escrow ruling (below), so the next reader does not re-litigate it.

The ADR-199 ordinal is **provisional**. `/ship`'s ADR-Ordinal Collision Gate must re-derive it
against freshly-fetched refs immediately before merge, and any renumber must sweep this plan,
`tasks.md`, and every AC naming the ordinal **in the same edit** — a renumber that reaches only the
ADR body leaves an AC asserting a nonexistent file.

### Escrow — ADR-142 wins, categorically

The brief names `workspaces-luks-header.tf`'s R2 header escrow as a precedent to copy. It is not
one. ADR-142 rejected escrow for **this** store by name and the reasoning is undisturbed: the
inngest AOF's total-loss recovery is already built and proven (`inngest-wiped-volume-verify.sh` —
functions re-sync from Postgres, the SDK re-registers, reminders enumerate/re-arm), so escrow's
specific job (surviving header corruption while the passphrase is intact) has a blast radius equal
to the bounded loss the queue-with-retry architecture already tolerates. Against that, the header
**plus** the Doppler passphrase yields full plaintext decrypt of user prompts and agent output — a
CWE-522-class net increase in confidentiality surface for a durability gain this store does not
need. `/workspaces` escrows because its loss is unrecoverable *by the user*; this store's is not.

This is the same template-inheritance error #7695 already caught one layer up when it refused the
`-luks-` name for a volume that is not yet LUKS — inheriting the template's escrow is that mistake
again with a security cost attached.

### C4 views

Read all three model files — `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,
spec.c4}` — in full, not a keyword grep, and enumerate for this change:

- **External human actors:** none added or changed. The recut is an infrastructure lifecycle
  operation with no new correspondent, reviewer, or recipient.
- **External systems / vendors:** none added. Hetzner (block volume), Doppler (passphrase), Better
  Stack (probe transport) are all already modeled; this change introduces no new vendor edge. The
  R2 escrow bucket that *would* have added one is cut.
- **Containers / data stores touched:** `hcloud_volume.inngest_redis` — an **existing** store whose
  at-rest mechanism changes plaintext → LUKS. If the C4 model carries an at-rest or encryption
  annotation on this store (or describes it as plaintext), that description is falsified by this
  change and must be corrected.
- **Actor↔surface access relationships:** unchanged. No sharing, ownership, or trust-boundary move.

A "no C4 impact" conclusion is only permissible **after** that enumeration is actually performed
against all three files and each item above is confirmed already-modeled; record which. If the
model annotates this volume's encryption state, edit `.c4` directly and re-run
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` (a `view … include`
referencing an undefined element fails there, not at `tsc`).

### Sequencing

The ADR amendment is authored **in this PR**, describing the target state. It is not gated on the
cutover window actually being opened — the decision is true when the capability and its bound ship,
not when someone dispatches it.

## Encryption Posture

**The row is STAGED, and this is load-bearing.** The volume is plaintext ext4 from merge until
Dispatch B succeeds. A PR that flips the ledger to `luks` at merge would publish a false at-rest
claim about user prompts and agent output for an unbounded window — and if Guard 2 refuses
(`redis_keys > 0`), a **permanent** one. That is precisely the #6588 class ADR-140 exists to
prevent, and it would contradict this plan's own line that a lapsed exception is evidentially worse
than an honest extension. So Phase 5 splits: **at merge the row keeps its exception**, re-dated
with the recut as justification and with only the bare-line-number citation fixed; the flip to
`luks` lands in a follow-up commit gated on the post-recut verification.

### Merge-time row (what ships in this PR)

```yaml
at_rest:
  - store: hcloud_volume.inngest_redis
    mechanism: plaintext-exception
    evidence: >-
      apps/web-platform/infra/inngest-host.tf (resource "hcloud_volume" "inngest_redis" — no LUKS
      apparatus until the gated recut lands). CONTENT ANCHOR, not a line number: the existing row
      cites `inngest-host.tf:288`, which violates cq-cite-content-anchor-not-line-number and is
      corrected in this PR.
    defends_against: nothing at the volume layer
    does_not_defend: >-
      a seized/snapshot disk exposes the Inngest queue + run-state AOF, i.e. in-flight job payloads
      (user prompts and agent output)
    disclosed_as: not-publicly-claimed
    live_verification: >-
      unavailable:the Hetzner API is blind to guest-side LUKS and no inngest-host posture probe
      exists; tracked #6894
    exception:
      justification: >-
        the LUKS apparatus ships inert in this PR; the cutover is a gated dispatch whose
        empty-store precondition may route the work to ADR-142's byte-copy instead
      tracking_issue: "#6894"
      reevaluate_when: the gated inngest-volume-recut dispatch completes and Dispatch C verifies
      expires_on: "2026-10-22"
```

### Post-cutover row (follow-up commit, gated on verification)

```yaml
at_rest:
  - store: hcloud_volume.inngest_redis
    mechanism: luks
    evidence: >-
      apps/web-platform/infra/cloud-init-inngest.yml (cryptsetup luksFormat --batch-mode --type
      luks2 --key-file - / cryptsetup luksOpen --key-file - <dev> inngest-redis, guarded by the
      blkid TYPE discriminator); key: random_password.inngest_redis_luks +
      doppler_secret.inngest_redis_luks_key (apps/web-platform/infra/inngest-redis-luks.tf);
      mount gate: the findmnt re-assertion in the inngest-redis unit's ExecStartPre
    defends_against: >-
      a seized, RMA'd, or snapshot-imaged Hetzner block volume: the Inngest queue and run-state
      AOF — in-flight job payloads, i.e. user prompts and agent output — are unreadable without
      the Doppler-held LUKS passphrase
    does_not_defend: >-
      a leaked Doppler credential (the passphrase lives there, so a Doppler compromise is a key
      custody compromise), any read on the live host where the mapper is already unlocked, or an
      application-layer read through the Inngest control API
    disclosed_as: not-publicly-claimed
    live_verification: >-
      unavailable:the Hetzner API is blind to guest-side LUKS and no inngest-host posture probe
      exists (the workspaces luks-monitor.sh analogue is not built for this host)
in_transit:
  - connection: inngest-server -> host-local Redis
    tls: none
    cert_verification: n/a
    does_not_defend: an on-host process reading the loopback socket
    disclosed_as: not-publicly-claimed
    note: >-
      loopback-only (`bind 127.0.0.1`, ADR-100 Decision 6a); no network path exists to intercept,
      so this is not a plaintext-exception requiring an expiry
exception: none
```

**Citations must RESOLVE or `/ship` preflight Check 12 fails.** Check 12 fires on this diff — its
scope regex is `\.tf$|supabase/migrations/.*\.sql$|cloud-init.*\.ya?ml$|docker-compose.*\.ya?ml$`
and this PR touches both `.tf` and `cloud-init-inngest.yml`. It shells out to
`scripts/lint-encryption-posture.py --repo-sweep` and relays the exit code; the check does **not**
reimplement the logic, so the only way to pass is to satisfy the linter's structural resolution:
the attachment's `volume_id` must **literally** reference the volume resource, a `random_password`
+ `doppler_secret` pair must be **co-located in the same file**, a real `luksFormat`/`luksOpen`
apparatus must resolve to the named mapper, and mount evidence must exist for that mapper.

Two ledger-hygiene items carried from the legal review:

- The **existing** row's evidence string cites `apps/web-platform/infra/inngest-host.tf:288` — a
  bare line number, which violates `cq-cite-content-anchor-not-line-number`. The rewrite replaces
  it with a content anchor, matching the `hcloud_volume.git_data_luks` row's style.
- The row's `exception` block is **retained and re-dated at merge**, and removed only in the
  post-cutover follow-up commit; #6894 closes when the recut is verified. If the recut slips past
  2026-10-22, re-date the exception again with a fresh justification rather than letting it lapse
  silently — a lapsed exception is evidentially worse than an honest extension. This is the whole
  reason the row is staged.
- **No retained plaintext backstop row is needed.** The destructive recut leaves no second volume;
  had this followed ADR-142's additive path, the retained plaintext volume would have required its
  own ledger row with its own exception and expiry, exactly like `hcloud_volume.workspaces` and
  `hcloud_volume.git_data`.

## Guard Contract

**Five layers, two code guards — the mapping, so "five promised, two delivered" is not a finding.**

| Layer | Mechanism | Where its contract lives |
|---|---|---|
| 1 | `environment: inngest-cutover` required-reviewer gate — **the sole authorization** | Not a code guard. Verified non-empty at Phase 0.3 and asserted by AC13. |
| 2 | Typed `confirm=RECUT-INNGEST-VOLUME` — a **typo-guard**, not authorization | AC6c (literal distinctness). |
| 3 | `expected_inngest_volume_id` pinned against the live attachment — typo-guard | Folded into **Guard 1** as the ID-PIN counter, and into **Guard 2** condition 6. |
| 4 | Terraform plan destroy-guard | **Guard 1** below. |
| 5 | Pre-flight "host is dark" refusal — the layer absent from the template | **Guard 2** below. |

Layers 1-3 are configuration and inputs; they have acceptance criteria but no mutation matrix
because there is no decision function to drive red. Layers 4-5 are executable decision logic and
carry the full contract. Stating this explicitly is itself a guard: a plan that claimed five
mutation matrices and shipped two would be the vacuity class this section exists to prevent.

### Guard 1 — `inngest_volume_recut_gate` (terraform plan destroy-guard)

**Property.** No `terraform apply` reachable from `apply_target=inngest-volume-recut` destroys,
detaches, or replaces any resource other than **the inngest AOF volume and its attachment** — in
particular `hcloud_server.inngest` shows **zero actions** — and the volume it destroys is the exact
physical Hetzner volume the dispatch named.

The allow-set is therefore exactly two addresses: `hcloud_volume.inngest_redis` (a genuine replace,
or the recovery bare-create) and `hcloud_volume_attachment.inngest_redis` (a create). Everything
else, `hcloud_server.inngest` included, is named-live or out-of-scope.

**Assembly.** The guard quantifies over **every element of `.resource_changes[]` in the
`terraform show -json` document** produced by the recut job's own plan step — not over a list of
addresses known today. The chokepoint is that single plan document: the workflow step and
`tests/scripts/test-inngest-volume-recut-gate.sh` both `source
tests/scripts/lib/inngest-volume-recut-gate.sh` and call the same function, so CI's decision logic
is the same bytes the test exercises. There is exactly one chokepoint and no second injection site;
the guard's closure property is that any address **not** in the allow-set and **not** in the
named-live set trips `out_of_scope`, so a resource nobody enumerated still aborts.

**Mutation matrix** (each row MUST drive the guard RED; derived from the design, written before the
guard):

| # | Mutation | Why it must redden |
|---|---|---|
| 1 | Plan additionally shows `hcloud_volume.workspaces["web-1"]` with `["delete","create"]` | The live sole-copy `/workspaces` volume. `old_volume_touched` ≥ 1. |
| 2 | Plan shows `hcloud_server.web["web-1"]` replaced | cx33 is unrebuildable; `web1_server_touched` ≥ 1. |
| 3 | `.change.before.id` on the inngest volume is `999999999`, dispatch pinned `106261946` | ID-PIN: address resolves to a different physical volume than authorized. `luks_id_mismatch` ≥ 1. |
| 4 | Plan shows `doppler_secret.inngest_redis_luks_key` with `["update"]` | Passphrase **first create** is legal here; an update/delete/forget rotates the header key and strands the store. |
| 5 | Plan shows a second, un-enumerated resource (`hcloud_volume.git_data`) with `["delete"]` | `resource_deletes` catches any delete outside the two legitimately-replaced addresses. |
| 5b | Plan shows `hcloud_server.inngest` with `["delete","create"]` | The recut must **not** replace the host — that is `inngest-host-replace`'s job, under its own guard. `inngest_server_touched` ≥ 1. This row is what pins the three-dispatch split. |
| 6 | **Guard's own dispatch** — the workflow step is edited so the gate function is never called (the `source` line removed) | Anti-vacuity: a guard that reports "0 checked" and exits 0 is vacuous. The job must fail when the gate does not run. |
| 7 | A second inngest-adjacent resource is added to the plan after a compliant first (`hcloud_volume_attachment.git_data` created) | A check that stops at the first member is itself the defect class. The quantifier must reach member two. |
| 8 | Plan JSON is truncated / unparseable | `plan_gate_assert_readable` — "I could not check" must not read as "it is fine". |
| 9 | A counter evaluates to the empty string | `plan_gate_assert_numeric` — `[[ "" -gt 0 ]]` is FALSE under bash coercion, silently satisfying every threshold. |
| 10 | Plan shows the inngest volume with `["delete","create"]` while `expected_id` is **empty** | `id_pin_absent`. The template takes `expected_id="${2:-}"`, so an omitted pin would silently disable the ID-PIN on a genuine destroy. The pin is **required** whenever `before != null`; it is a no-op only for the bare-create recovery shape. |

**Harness rows** (mutate the SUITE, not the guard):

| # | Mutation | Why it must redden |
|---|---|---|
| H1 | Delete one fixture from `test-inngest-volume-recut-gate.sh` and leave the pass count assertion | The suite must assert a **floor on its own case count**, or dropping a case is invisible. |
| H2 | Replace the gate function body with `return 1` (reject everything) | Must be caught by a **must-PASS** row, not a RED row — RED rows cannot detect a guard that rejects everything. |
| H3 | **must-PASS, non-canonical:** the recovery bare-create shape (`["create"]` with `before == null`, no `expected_id` supplied) | A legal shape that is NOT the canonical replace. If only the canonical fixture passes, the guard is `diff <fixture> <canonical>` in disguise and a stranded destroy-before-create re-dispatch would loop forever. |

Fixtures are **synthesized** plan JSON, never captured production plans (`cq-test-fixtures-synthesized-only`).

### Guard 2 — `inngest_host_dark_gate` (the fifth layer, absent from the workspaces template)

**Property.** The recut cannot be dispatched against an inngest host that is currently serving.

**Property (full form).** The recut cannot be dispatched unless, on **one single probe row** from
the **current** host, the store is measured empty and the host measured dark.

**Assembly.** Quantifies over `SOLEUR_INNGEST_SERVER_PROBE` rows for the dedicated host inside a
**90-minute** window (the probe's cadence is hourly; a shorter window makes a healthy host look
silent), read through `scripts/betterstack-query.sh` — the same no-SSH transport
`_flip_query_rows` / `_flush_latch_count` already use, so no new transport, credential, or fixture
class is introduced. **All six conditions, and all field reads from the SAME row — never joined
across rows:**

0. **`probe_schema=2` on the chosen row.** Phase 2's emitter stamps this; the pre-Phase-2 host
   does not. A row without it yields verdict `stale_schema` ⇒ REFUSE. This is what makes the
   Phase 2 → Phase 4 ordering a **mechanical precondition** rather than operator discipline: before
   the new emitter is live there is no schema-2 row, so the recut is unreachable by construction.
   Do not rely on "the missing field parses to empty" — a lenient extractor makes absence satisfy
   everything, which is the fail-open this condition replaces.
1. Row count in the window **≥ 1**. Zero rows ⇒ verdict `silent` ⇒ REFUSE — distinct from
   `unreadable`, and never `dark`.
2. Counts validated by an explicit `^[0-9]+$` predicate. A non-decimal or unparsed count ⇒
   `unreadable` ⇒ REFUSE. (`[[ "" -gt 0 ]]` is FALSE under bash coercion — the documented
   empty-count bypass class.)
3. `server_active=inactive` **and** `http_code` non-200. `server_active` alone is a systemd claim;
   `http_code` is the claim that matters — this host once reported a started unit that had failed
   to bind its port.
4. **`boot_id` on that row equals the `boot_id` on the newest row.** Without this, "dark" can be a
   fact about a host that no longer exists. This condition is absent from every existing gate on
   this surface and is what makes the other five sound.
5. **`redis_keys == 0`**, from `INFO keyspace` across **all** databases — **not `DBSIZE`**, which
   is db-0 only while `FLUSHALL` spans every db. The shipped post-flush assert already carries that
   asymmetry; it must not be inherited into a gate that authorizes destruction.
6. The live Hetzner attachment's volume id equals the id the dispatch pinned.
7. **Host identity — `host=soleur-inngest` AND `host_name=soleur-inngest-prd` on the row.**
   `inngest-bootstrap.sh` is the **SHARED** renderer for both hosts, so the co-located web host
   emits this probe too. Without the full conjunction a web-host row reporting its own (irrelevant)
   state could satisfy the gate. Reuse `scripts/inngest-dedicated-host-classify.sh`, which already
   measures exactly this conjunction and whose suite carries an `R_SPOOF` fixture
   (`host=soleur-web-platform` with `host_name=soleur-inngest-prd`) for the near-miss case. Emit the
   new fields **only** on the dedicated host, or as `n/a` elsewhere — never a defaulted `0`.
8. **`data_mount_src` equals the pinned device.** The probe emits `findmnt -no SOURCE /mnt/data`;
   it must equal `/dev/disk/by-id/scsi-0HC_Volume_<pinned-id>` pre-recut (or
   `/dev/mapper/inngest-redis` post-recut). **This is the condition that makes the whole gate mean
   what it claims.** `redis_keys` is a statement about a Redis *process*; the recut destroys a
   *block device*. Today's mount is `mount … || true` with `nofail`, so a failed mount leaves
   `/mnt/data` on the ephemeral root disk and Redis reports an empty store **while the volume holds
   a populated AOF** — gate passes, destruction unsafe. The FSM already carries a
   `latch-unrecordable detail=not-a-mountpoint` abort for precisely this shape, so the repo has been
   bitten by it before. Empty or mismatched ⇒ `mount_mismatch` ⇒ REFUSE.
9. **`data_bytes` is reported** (`du -sb /mnt/data`) and lands in the row. Not a pass/fail threshold
   — an **audit** field. An empty Redis on a volume holding megabytes is a state a human should see
   before it is erased.
10. **`#7674` reads PASS** — `scripts/followthroughs/inngest-host-not-serving-7674.sh`. See the
    precondition box in §Apply path: without this the recut is strictly counterproductive.
11. **`INNGEST_DIAGNOSTIC_BOOT` is unset or `0`** on the same row. If it is still set, the flip
    reaches `done` against a SQLite-only non-durable scheduler — #7228's defect reproduced one layer
    over, now with the latch burned.
12. **The Doppler flag is re-read synchronously immediately before apply** and must be
    `rolled-back` or `aborted`. Guard 2's Better Stack row is a ≤90-minute-old snapshot; the flag is
    readable in real time and is the thing that actually authorizes a concurrent `FLUSHALL`.

**Concurrency is part of the contract, not an afterthought.** Guard 1 quantifies over a plan
document and Guard 2 over log rows; **neither quantifies over a concurrent dispatch**. A
`cutover-inngest op=arm` between the two flips the Doppler flag, the 30s on-host timer fires
`run_preflush_flip`, and terraform can destroy the volume mid-`FLUSHALL`. The new job therefore
carries `concurrency: {group: inngest-cutover, cancel-in-progress: false}` — and so must
`inngest_host`, `inngest_host_replace`, **and** the `cutover-inngest` arm/resume workflow. A mutex
on one side of a race is not a mutex.

13. **`redis_active=active` on that same row.** Without this the gate authorizes destruction on an
   ambiguity: a host where Redis failed to start emits a `redis_keys` derived from a failed
   `INFO keyspace`, and "Redis is down" becomes indistinguishable from "the store is empty". That
   is the same fail-open shape as mutation row 5 — silence is not evidence — applied to the field
   the whole decision rests on. **At the emit site, a failed `INFO keyspace` MUST emit
   `redis_keys=__UNREADABLE__`, never an empty string and never `0`.**

**Every consumed field is validated for PRESENCE, not just format.** Conditions 3, 4 and 6 read
fields whose *absence* would otherwise satisfy them — an absent `http_code` is trivially "non-200",
and an absent `boot_id` compared against an absent `boot_id` is trivially equal. Each field goes
through a readable/classifiable assert before any comparison, exactly as Guard 1's
`plan_gate_assert_numeric` does for its counters.

Independently, `function.finished` rows carrying `host_name=soleur-inngest` must be **zero**.

**Nothing extra is needed to enforce the Phase 1 → Phase 3 ordering.** The two phases ship in the
same PR, so in principle someone could dispatch the recut first — but Guard 2 makes that
self-defeating rather than dangerous. Before Phase 1's emitter is live, probe rows exist but carry
**no `redis_keys` field**; the read yields an empty string, condition 2's `^[0-9]+$` predicate
fails, and the verdict is `unreadable` ⇒ REFUSE. The ordering is enforced by the gate's own
fail-closed parse, not by documentation asking for patience. This is deliberate: an ordering
constraint that lives only in prose is not a constraint.

**If `redis_keys > 0` the destructive path is REFUSED outright, no exceptions** — and note that
enumeration is then unavailable, because `inngest-enumerate-reminders.sh` queries
`127.0.0.1:8288`, which is not bound on a dark host. Non-empty **and** non-enumerable means
ADR-142's preserve-and-copy is the only lawful path, and the dispatch must route there.

**The decision function is a positive allowlist.** It proceeds only on the literal `dark`; every
other token — including `unreadable` — aborts. This is deliberate and inverts G3.7's posture: G3.7
is a *pre-filter* that may only ADD a refusal, so a read failure there degrades safely to the
on-host latch. Here the gate is *authorizing an irreversible destroy*, so an unreadable signal must
abort. A gate that cannot see the host must never conclude the host is dark.

**Mutation matrix:**

| # | Mutation | Why it must redden |
|---|---|---|
| 1 | Probe rows report `server_active=active` | The host is serving; the recut destroys live queue state. |
| 2 | Probe rows report `http_code=200` with `server_active=inactive` | Disagreeing signals are not "dark". Both must agree. |
| 3 | One or more `function.finished` rows carry `host_name=soleur-inngest` | The host is executing functions regardless of what the probe says. |
| 4 | The Better Stack read returns non-zero / `__UNREADABLE__` | Fail-closed: unreadable ≠ dark. |
| 5 | Zero probe rows in the window (host silent, not proven dark) | **Silence is not evidence of darkness** — this is the exact G3.7 fail-open class, and this gate must not repeat it. |
| 6 | **Guard's own dispatch** — the gate call is removed from the job | Anti-vacuity floor. |
| 7 | `redis_keys=3` with every other condition satisfied | The store is populated; the destructive path is refused outright. |
| 8 | `redis_keys` sourced from `DBSIZE` instead of `INFO keyspace`, with keys present only in db-1 | `DBSIZE` reads db-0 only and would report 0 on a populated store — a false `dark`. |
| 9 | The row satisfying conditions 3+5 carries a `boot_id` differing from the newest row's | Reading a pre-replace host. "Dark" about a host that no longer exists. |
| 10 | Conditions 3 and 5 satisfied but on **two different rows** | Fields must come from one row, or the gate authorizes on a state that never simultaneously existed. |
| 11 | `redis_active=inactive` with `redis_keys=0` | Redis being down is not the store being empty. Must verdict `unreadable`, never `dark`. |
| 12 | `redis_keys` absent from the row entirely | Absence must not parse to `0`. Verdict `unreadable`. |
| 13 | A row lacking `probe_schema` (the pre-Phase-2 emitter) | Verdict `stale_schema` — this is the interlock that stops a recut dispatched before the read channel exists. |
| 14 | `http_code` absent from the row | Absence must not read as "non-200". Verdict `unreadable`. |
| 15 | `boot_id` absent from **both** the chosen and the newest row | `"" == ""` must not satisfy the pin. Verdict `unreadable`. |

**Harness rows:**

| # | Mutation | Why it must redden |
|---|---|---|
| H1 | Remove a fixture, keep the count assertion | Case-count floor. |
| H2 | Make the decision function always return `dark` | Caught only by a must-FAIL row pairing; assert the reason token, never just rc. |
| H3 | **must-PASS, non-canonical:** probe rows present and dark, `function.finished` rows present but **all** `host_name=soleur-web-platform` | The real production shape — a busy fleet with a dark inngest host — must PASS, or the gate is unusable exactly when it is needed. |

**Why layer 5 exists at all:** every other layer authorizes *by intent* (a human approved, a token
was typed, the plan shape matched). Only this one checks the *world*. The measured facts that make
this recut safe (host dark, scheduler elsewhere) are facts about the world at dispatch time, and a
plan that assumes them without checking is a plan that was correct on 2026-09-02 and silently wrong
afterwards. Encoding the premise as a gate is what stops this plan's own reasoning from rotting —
the failure mode this feature's history is a case study in.

## Downtime & Cutover

**The gate fires.** This plan replaces `hcloud_server.inngest` (user_data is ForceNew with no
`ignore_changes`, so the cloud-init edit forces it) and `-replace`s `hcloud_volume.inngest_redis`
plus its attachment. Both are the infra reboot/replace class.

**The offline-inducing operation and the surface it affects.** Dispatch A and Dispatch C each
destroy and recreate the dedicated Inngest host; Dispatch B destroys and recreates its AOF volume.
The affected surface is the **dedicated Inngest scheduler host** — and it is measured **not
serving**: `server_active=inactive`, `http_code=000`, `cutover_flag=rolled-back`, with 18 of 18
`function.finished` rows over 2h attributed to `soleur-web-platform`. The live scheduler is web-1,
a different host with a different volume, untouched by every dispatch here and protected by Guard
1's `web1_server_touched` counter.

**User-visible downtime: zero minutes.** Not "brief" or "acceptable" — zero, because the surface
being taken offline is already offline and serves no traffic. This is the one case where the
downtime question has a trivial answer, and the plan states the measurement rather than asserting
the conclusion.

**Zero-downtime path evaluated, and it is the branch we keep.** The zero-downtime alternative for
the *volume* is ADR-142's additive blue-green: provision a second raw LUKS volume, quiesce intake,
freeze, byte-copy, canary on reminder-count, mount-swap, retain the plaintext volume as a rollback
backstop. It is **not rejected** — it remains **mandatory** whenever the store is non-empty, and
Guard 2's `redis_keys == 0` condition is precisely the switch between the two paths. The
destructive path is taken only in the world where blue-green would copy zero bytes and then
`FLUSHALL` them, i.e. where "zero-downtime" and "destructive" have identical outcomes and the
blue-green machinery buys only its own three FATAL footguns (wrong device, torn AOF, mid-window
reboot re-mounting plaintext).

**Why the surface cannot be drained instead.** Inngest cannot be drained to empty by waiting:
armed reminders sit at arbitrary future fire-times, so "wait for the queue to empty" is unbounded.
That is exactly why ADR-142 chose byte-copy over drain, and why this plan measures occupancy rather
than waiting for it to reach zero.

**Per-stage verification and rollback.**

| Stage | Verification before proceeding | Rollback |
|---|---|---|
| Dispatch A (host replace, probe delivery) | Probe rows resume on the hourly cadence carrying the four new fields; `blkid` arm reports `ext4` and mounts as-is; no data touched | Re-dispatch `inngest-host-replace` on the prior image; the volume is untouched throughout |
| Observation window | ≥1 probe row with `flush_latched`, `latch_flushed_at`, `latch_dbsize`, `redis_keys` on the current `boot_id` | N/A — read-only |
| Dispatch B (volume recut) | Guard 1 (plan shape + ID-PIN, `hcloud_server.inngest` zero actions) and Guard 2 (six conditions, one row) both PASS | **None — this stage is irreversible.** That is why it sits behind five layers and a measured empty-store precondition, and why the pre-destruction probe row is the audit record |
| Dispatch C (host replace onto raw volume) | `SOLEUR_INNGEST_LUKS_STAGE` rc=0 through `stage=fstab`; `/mnt/data` is a genuine mountpoint on `/dev/mapper/inngest-redis`; probe reports `redis_active=active` | Re-dispatch; the volume is already LUKS and the `crypto_LUKS` arm is idempotent |

**Bounded window.** Each dispatch is a single Hetzner replace on a non-serving host; the
maintenance window is bounded by provider replace time plus cloud-init, not by any drain. The
reviewer-gated environment can hold a run `waiting` for hours while holding the workflow-level
concurrency group (`cancel-in-progress: false`), which blocks *sibling applies* — that cost is
inherited from `workspaces_luks_recut` and is stated here rather than discovered during the window.

## Observability

```yaml
liveness_signal:
  what: >-
    SOLEUR_INNGEST_LUKS_STAGE — a boot-stage marker emitted by the cloud-init LUKS block, mirroring
    the existing inngest-boot-phone-home.sh SOLEUR_INNGEST_BOOT_STAGE emitter, carrying
    stage (key-fetch|blkid-probe|luksFormat|luksOpen|mkfs|mount|fstab), rc, and the blkid TYPE read
  cadence: once per boot, per stage
  alert_target: Better Stack Logs (same source table as SOLEUR_INNGEST_SERVER_PROBE)
  configured_in: >-
    apps/web-platform/infra/cloud-init-inngest.yml (emitter) and
    apps/web-platform/infra/vector.toml Source 4 include_matches.SYSLOG_IDENTIFIER (allowlist)
error_reporting:
  destination: Better Stack via the on-host Vector journald shipper; the boot-stage HTTP emitter is
    the independent fallback for failures that precede Vector
  fail_loud: >-
    yes — the LUKS stage runs under `set -euo pipefail` inside its own exec'd child with an ERR
    trap, and every fs operation (luksFormat, luksOpen, mkfs, mount) is individually rc-checked.
    No `|| true` on any step that can leave /mnt/data on the root disk.
failure_modes:
  - mode: cryptsetup luksOpen fails (wrong/empty passphrase from Doppler)
    detection: SOLEUR_INNGEST_LUKS_STAGE stage=luksOpen with non-zero rc
    alert_route: Better Stack; the host never reaches the mount stage and Redis must not start
  - mode: LUKS mount fails open, leaving /mnt/data as a root-disk directory
    detection: >-
      the inngest-redis unit's ExecStartPre findmnt re-assertion refuses to start, emitting a FATAL
      marker; independently, the flip FSM's own mountpoint gate emits
      `latch-unrecordable detail=not-a-mountpoint`
    alert_route: Better Stack; both markers are on the allowlisted tag set
  - mode: blkid reports a filesystem signature on a device the recut expected to be raw
    detection: SOLEUR_INNGEST_LUKS_STAGE stage=blkid-probe with the observed TYPE; the guard
      refuses to format a populated device
    alert_route: Better Stack; boot halts loudly rather than overwriting a populated store
  - mode: the recut lands but the flip FSM can no longer record its latch
    detection: >-
      `"reason":"latch-unrecordable"` rows — the same literal G3.7 already keys on. This is the
      coupling the legal review surfaced: the latch's re-arm path depends on /mnt/data being a
      genuine mountpoint on the NEW volume.
    alert_route: Better Stack; the FSM drives the flag to terminal `aborted`, halting the poll
logs:
  where: >-
    on-host journald → Vector (Source 4, SYSLOG_IDENTIFIER exact-value allowlist) → Better Stack
    Logs, source soleur-inngest-vector-prd, table t520508_soleur_inngest_vector_prd_3_logs. The
    cloud-init boot-stage emitter POSTs directly to the same Better Stack ingest, so a failure that
    precedes Vector is still recorded. No SSH path exists or is required.
  retention: >-
    ~20 days, MEASURED this session rather than assumed — whole-table probe returned
    oldest=2026-08-13 15:14:14, newest=2026-09-02 20:15:16 over 2,855,466 rows. This is the number
    that makes G3.7's 365d L-window structurally blind to the 2026-07-23/24 flip, and it is
    recorded in the new ADR so the next reader does not re-derive it.
discoverability_test:
  command: >-
    doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 6h
    --grep SOLEUR_INNGEST_LUKS_STAGE --limit 20
  expected_output: >-
    one JSON row per boot stage with rc=0 through stage=fstab, and a subsequent
    SOLEUR_INNGEST_SERVER_PROBE row reporting redis_active=active
  # INLINE, not a folded scalar. preflight Check 10 reads this sub-field with a flat awk that
  # takes only the key line, so a `>-` header made the runtime see the value as `>-` — a bare
  # block indicator, which it correctly treats as "declares nothing" — and the waiver silently
  # did not apply. The declaration itself is unchanged; only its YAML shape is.
  credentials_required: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} from Doppler prd_terraform — the log warehouse has no unauthenticated read surface, so no unauthenticated probe verifies this property
```

**Vector allowlist coupling is load-bearing.** `vector.toml` Source 4 matches
`SYSLOG_IDENTIFIER` by **exact-value equality** (`sd_journal_add_match`), not prefix or regex — a
tag typo silently matches nothing and the marker never leaves this deny-all-public host. The new
tag must be added to the Source 4 allowlist **and** to the drift fixture
`apps/web-platform/test/infra/vector-pii-scrub.test.sh` **in the same change**. "It rides the
already-shipped shipper" is a claim, never a fact.

**Do not build a heartbeat.** This host beat green for 12 days while serving zero dispatches
(`2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect.md`). Every signal above
names a stage, an rc, or a port — never a timer firing.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Issued a binding ruling that **refused the destructive recut as briefed** — not on
ADR-142 doctrine, but on two code-level grounds. Both were adopted, one after correction.

- **Adopted — the premise is unmeasured.** Nobody has read
  `/mnt/data/inngest-cutover/flip-done.latch`. ADR-100's "latch intact" is a
  survival-by-construction claim about host replaces, not an observation. Dispatching a destructive
  target against an unmeasured premise inverts the evidence ordering the rest of this surface
  enforces. **This restructured the plan**: Phase 1 now builds the read channel, and the gate makes
  the measurement a precondition rather than an assumption.
- **Adopted — "already dead" is not sufficient grounds.** Dormancy is a property of the host and is
  reversible (a host replace re-attaches this same volume); a `-replace` is a property of the bytes
  and is not. The correct test is never "is it currently functioning" but "is its content
  enumerable, and is it empty or reproducible elsewhere." The plan no longer argues from dormancy.
- **Adopted — my "never served" evidence covers the wrong window.** See Research Insights
  correction 5. Owned, not deflected.
- **Adopted in full — the escrow ruling**, the `INFO keyspace`-not-`DBSIZE` correction, the
  `boot_id` pin, the `silent`≠`unreadable` split, and the six-site cross-consumer sweep including
  `L`'s polarity inversion between `op=arm` and `op=resume`.
- **Corrected — "the recut clears only one of two blockers."** The ruling held that destroying the
  volume cannot decrement G3.7's `L` (log rows are immutable), and called this disqualifying. The
  mechanism is right; the premise is not. **`L` is measured at 0**, so G3.7 already returns `clear`
  and is not blocking. The ruling's own leading hypothesis predicts exactly this. Recorded as a
  caveat, not a blocker.
- **Re-scoped rather than accepted wholesale.** The ruling's recommended Option A (execute ADR-142's
  full byte-copy migration inside #7695) is itself the scope collision it warns against one
  paragraph earlier. The plan instead builds ADR-142's *shared apparatus* (passphrase, Doppler
  secret, raw volume, cloud-init LUKS block — inert on merge, common to both paths) plus the gated
  recut as a **bounded** cutover mechanism. The ruling's own words license this: *"If `redis_keys >
  0`: the destructive path is REFUSED outright"* — which is a precondition, not a prohibition, and
  *"if the store is empty now, risks (1) and (2) and the entire dormancy debate collapse to
  nothing."* The gate is that precondition made mechanical.

### Legal (CLO)

**Status:** reviewed
**Assessment:** Advisory, draft, not legal advice. No legal blocker; no DPIA trigger (the change
reduces risk).

- **No public over-claim — affirmatively cleared.** Every at-rest claim in the published corpus
  (`docs/legal/privacy-policy.md` §11 ×2, §5.7) is scoped by its own text to *workspace git data*
  or *API keys*. None reaches this store. The August 2 re-scoping is what averted it. The plan
  states this affirmatively rather than leaving the question open.
- **Adopted — Art. 30 PA-13 is materially false and this change makes it conspicuous.** Limb (e)
  says "Self-hosted binary persists state in SQLite on the same Hetzner host" — wrong substrate
  (Redis AOF on a block volume) and wrong host (extracted to a dedicated host per ADR-100). Split
  per `wg-when-an-audit-identifies-pre-existing`: **correct (e) in-PR** (a one-line substrate fix on
  a file this PR already reasons about); **file a `compliance/` issue** for limb (f)'s harder
  cross-PA determination of whether the store is personal-data-bearing, which needs real analysis.
- **Adopted — ledger hygiene.** Five fields change, not one; the existing evidence string cites a
  bare line number (`inngest-host.tf:288`), violating `cq-cite-content-anchor-not-line-number`.
- **Adopted — verify `--history-retention` is actually set** against the unit file rather than
  assumed, or PA-13(f)'s published 30-day envelope is unevidenced.
- **Adopted — record the destruction.** An Art. 5(2) one-line record in
  `knowledge-base/legal/audits/` converts an undocumented wipe into evidence.
- **Rejected as stated, underlying insight adopted.** The review flagged CRITICAL that the recut
  "disarms the #7228 P0-5 re-flush guard" and must "carry the latch across." Carrying it across
  would defeat the entire purpose of #7695 — clearing that latch *is* the deliverable, and a
  latch that survives its own clearance mechanism is not a fix. But the underlying coupling is
  real and load-bearing, so the plan encodes it three ways: (i) `record_flush_latch` re-arms the
  guard automatically at the next successful flip, so the disarmed window is bounded by design;
  (ii) that re-arm depends on `/mnt/data` being a **genuine mountpoint** on the new LUKS volume —
  if the LUKS mount fails open, the FSM's own mountpoint gate fires `latch-unrecordable` and
  drives the flag to terminal `aborted`, which is fail-closed and correct, and the plan asserts
  the mountpoint property directly; (iii) the audit trail the review wanted is satisfied
  **off-host and immutably** — Phase 1's probe ships the verbatim latch record to Better Stack
  before anything is destroyed. That is a better record than an on-disk file, which the recut
  would destroy anyway.

### Product/UX Gate

Not applicable. The mechanical UI-surface override did not fire: no path in Files to Create or
Files to Edit matches the shared UI-surface term list or glob superset — the change is Terraform,
cloud-init, shell guards, a workflow job, a JSON ledger, and ADRs. Product assessed **NONE**.

### Finance

Not relevant under the chosen design. The recut **replaces** the volume rather than adding one, so
there is no new recurring vendor line (`wg-record-recurring-vendor-expense-before-ready` does not
fire). Had this followed ADR-142's additive path, the second 10 GB Hetzner volume retained as a
backstop would have been a new recurring cost requiring a ledger entry before PR-ready.

## Infrastructure (IaC)

### Terraform changes

| File | Change |
|---|---|
| `apps/web-platform/infra/inngest-redis-luks.tf` **(new)** | `random_password.inngest_redis_luks` (length 40, `special = false`, **no** `ignore_changes`) and `doppler_secret.inngest_redis_luks_key` → `INNGEST_REDIS_LUKS_KEY` on the **existing isolated** `soleur-inngest/prd`, `visibility = "masked"`. Co-located in one file because `lint-encryption-posture.py` requires the `random_password` + `doppler_secret` pair be co-located to resolve the citation. |
| `apps/web-platform/infra/inngest-host.tf` | Add `lifecycle { ignore_changes = [format] }` to `hcloud_volume.inngest_redis`. The `format = "ext4"` line is dropped **only on the recut branch**, so the recut yields a raw device and `blkid` becomes a sound discriminator — while `apply_target=inngest-host` keeps producing a zero-delete plan in the meantime. |
| `apps/web-platform/infra/cloud-init-inngest.yml` | Replace the plaintext mount block with a three-arm LUKS stage (below). **ForceNew on `hcloud_server.inngest`.** |

No new provider, no new version pin, no new no-default variable — the passphrase is a
`random_password`, never an operator-minted `TF_VAR_*` (`hr-tf-variable-no-operator-mint-default`),
and it lands in the existing isolated project read by the existing read/write boot token. No new
Doppler project, no new GitHub Actions secret, no new branch config.

**`format` is the highest-risk single line in the diff, and the first draft got its consequence
wrong.** `format` is ForceNew, so config-null against state-`"ext4"` plans a **replace**. The first
draft called this "an unexpected replace nobody expected" and deferred the design to a measurement.
The real consequence is sharper: `apply_target=inngest-host` carries an **additive-only** destroy
guard (*"a net-new host provisioning must create, never destroy. Any delete → abort BEFORE
apply"*), so a queued replace does not destroy anything there — it makes that dispatch
**permanently abort**. That is the provisioning and recovery path for a host which is already not
serving, and if Guard 2 refuses the recut the outage of that path is **indefinite**.

So the design is committed now rather than deferred: **`lifecycle { ignore_changes = [format] }`
lands in Merge B**, and the `format` line is dropped only on the recut branch. The mitigation the
first draft offered — "the volume is outside every merge-apply `-target=` list" — is true and
irrelevant: the exposure was never the merge-apply, it was the dispatch paths and the operator's
full untargeted apply, which `inngest-host.tf`'s own header names as a real apply path.

Phase 0 still measures, but the measurement is now an **AC**, not a fork: `apply_target=inngest-host`
must still produce a zero-delete plan after the change.

### Apply path

**(b) TWO MERGES, then gated dispatches** — never a merge-apply, and never in one merge.

The first draft put everything in one PR and delivered it through `apply_target=inngest-host-replace`.
That is not executable: `inngest_host_replace_gate` refuses any plan touching
`hcloud_volume.inngest_redis`, and both of the `.tf` edits put the volume into that plan. The fix is
a split, and **not** widening that gate — it has no reviewer gate, no typed confirm and no id-pin,
so widening it would create a completely unguarded second recut path in the same PR that builds
five guard layers.

**Merge A — the read channel only.** `inngest-bootstrap.sh` probe extension. **No `.tf` change, no
cloud-init LUKS block**, so `inngest_host_replace_gate`'s three-address allow-set is satisfied
unchanged. Delivered by `apply_target=inngest-host-replace`. Zero data touched; its whole purpose is
to make the latch, the mount source, and the store's occupancy **readable**.

**Merge B — the apparatus and the gated target.** `inngest-redis-luks.tf`, the cloud-init LUKS
stage, the boot-reopen unit, the new `inngest-volume-recut` target and its guards.

**Merge B is NOT fully inert, and treating it as inert is the defect.** The LUKS passphrase must
exist in Doppler *before* any host boots that reads it, or the boot FATALs on an empty key. So
`random_password.inngest_redis_luks` and `doppler_secret.inngest_redis_luks_key` go **into the
per-merge `-target=` allowlist** — the precedent is already there for
`random_password.inngest_redis_password_prd` / `doppler_secret.inngest_redis_password_prd`. Everything
else in Merge B stays out of every automatic apply path.

**Dispatch order, and the precondition that gates all of it.**

> **#7674 must read PASS before the recut is dispatched.** This is a hard precondition, not a
> follow-on check. `record_flush_latch` runs at `inngest-cutover-flip.sh:492`, **before**
> `verify_or_abort` at `:502`, and `verify_or_abort` requires `/health` 200 plus a non-empty
> function registry. The host cannot bind today — `http_code=000` — and `INNGEST_DIAGNOSTIC_BOOT=1`
> is **already** bypassing the flag allowlist, which proves the flag is not what keeps it dark. So
> a recut dispatched now buys nothing and costs everything: the first `arm` writes a **fresh**
> latch, fails verify, and lands in terminal `aborted`. Latch re-armed, flag worse than
> `rolled-back`, and the one-shot destructive capability spent on an undiagnosed bind failure.

1. **Merge A.** Inert except the probe.
2. **Dispatch A — `apply_target=inngest-host-replace`.** Volume untouched; gate passes unchanged.
3. **Observe**, with a bounded watch (below). Requires a `probe_schema=2` row.
4. **Merge B.** Passphrase lands via the `-target=` allowlist; everything else inert.
5. **#7674 reaches PASS.** Until then, stop. Guard 2 enforces it.
6. **Clear `INNGEST_DIAGNOSTIC_BOOT`** — it is baked into the unit at boot, so clearing the Doppler
   value alone leaves the installed unit in diagnostic form and `inngest-server-flip-guard.sh`
   refuses that disagreement. Clearing it **before** Dispatch B means Dispatch C's boot re-bakes it,
   and no fourth replace is needed.
7. **Dispatch B — `apply_target=inngest-volume-recut`.** Volume + attachment only;
   `hcloud_server.inngest` shows **zero actions**.
8. **Dispatch C — `apply_target=inngest-host-replace`.** New host boots, sees a raw device,
   luksFormats it.
9. **FSM re-entry is a separate operator decision at the window** — not this PR's work. For the
   record, it is: set `INNGEST_CUTOVER_FLIP=armed` (`unset` will not do it — `unset` is itself one
   of the terminal no-ops), then the FSM runs `armed → flipping → FLUSHALL → assert DBSIZE==0 →
   flushed → start → verify → done`, and `record_flush_latch` writes a **new** latch on the new
   LUKS mount, re-arming the guard.

**Bounded watch after each dispatch** (`hr-dispatch-async-must-arm-watch`). The probe is hourly, so
arm a **2h** watch on `SOLEUR_INNGEST_SERVER_PROBE` for a `probe_schema=2` row on the new `boot_id`.
On timeout, do not conclude anything from silence — query the `inngest-boot-phone-home` markers
first, which are a **different channel** that survives a Vector failure. The three causes of silence
(boot failed / Vector down / tag not allowlisted) need three different actions and are
distinguishable only that way.

**Every refusal has a stated next action.** A gate that dead-ends is a gate that gets bypassed.

| Verdict | Meaning | Next action |
|---|---|---|
| `stale_schema` | Row predates Merge A's emitter | Complete Dispatch A; re-observe |
| `silent` | Zero rows in the window | Query `inngest-boot-phone-home` markers; if those are also absent the host failed to boot — re-dispatch A on the prior image |
| `unreadable` | Query rc≠0, or a consumed field absent/non-numeric | Verify `BETTERSTACK_QUERY_*` in `prd_terraform`; if creds are fine, the emitter shipped an incomplete row — fix the emitter, do not relax the gate |
| `not_dark` | `server_active=active` or `http_code=200` | The host is serving. **Stop.** Nothing about this plan applies to a serving host |
| `redis_keys > 0` | Store is populated | Destructive path refused. Route to ADR-142 byte-copy under #6894 — **but see the circularity note below** |
| `mount_mismatch` | `/mnt/data` is not on the pinned device | The mount failed open and Redis is on the root disk. Do **not** recut; the volume's real contents are unmeasured |
| `id_pin_absent` / `luks_id_mismatch` | Pin missing, or address resolves elsewhere | Re-read the live Hetzner attachment id and re-dispatch. If the volume was stranded, use the bare-create recovery shape |
| Guard 1 `out_of_scope` / `resource_deletes` | Drift is in the plan | Do **not** widen the gate. Reconcile drift under its own dispatch first |
| LUKS boot fails after Dispatch B | Volume already destroyed | **No rollback exists.** The store was empty by precondition, so recovery is re-provision: functions re-sync from Postgres and the SDK re-registers |

**The `redis_keys > 0` branch is circular, and that is named rather than hidden.** Routing to
ADR-142's byte-copy requires enumerating reminders, but `inngest-enumerate-reminders.sh` queries
`127.0.0.1:8288`, which is not bound on a dark host; binding requires leaving `rolled-back`; leaving
it requires clearing the latch — the thing being gated. So on that branch the **append-only
authorized latch clear** (Alternative 2) is the stated fallback, filed as its own issue in-PR per
`wg-when-deferring-a-capability-create-a`. Without that, the branch has no path to P1/P2 and the
plan would have shipped a destructive capability that can never legitimately fire.

Blast radius: the dedicated host and its AOF volume only. The live scheduler is web-1 — a different
host with a different volume, untouched by every dispatch and protected by Guard 1's
`web1_server_touched` counter.

### Distinctness / drift safeguards

- The passphrase lands on `soleur-inngest/prd`, **never** `soleur/prd` — a mutation-tested guard row.
- **No `lifecycle.ignore_changes` on the passphrase or its secret.** Rotation is
  `cryptsetup luksChangeKey`, **never** a `-replace`: a `-replace` mints a new passphrase without
  rekeying the LUKS header and strands the store. The gate asserts the passphrase is untouched at
  recut time for exactly this reason.
- `user_data` stays **out** of `ignore_changes` on `hcloud_server.inngest`, preserving the
  replace-to-reprovision path this host's delivery model depends on (#6780).
- Terraform state carries the passphrase in plaintext; the R2 backend is the existing encrypted
  tfstate bucket, and the escrow bucket that would have added a second sensitive artifact is cut.

### Vendor-tier reality check

None. No new vendor, no tier-gated resource, no free-tier limit in play — Hetzner block volumes,
Doppler secrets, and Better Stack log ingest are all existing, in-plan capabilities.

## Implementation Phases

**Two merges.** The split is not stylistic — Merge A's delivery vehicle (`inngest-host-replace`)
aborts on Merge B's `.tf` edits, so combining them makes Merge A undeliverable.

### Phase 0 — Preconditions (measure, do not assume)

0.1 Re-run every Premise Validation reading. This plan's own history is a case study in a stale
    reading repeated as current.
0.2 `terraform plan` and record the verbatim line proving `apply_target=inngest-host` still yields
    a **zero-delete** plan under `ignore_changes = [format]`. This is now an AC (B4), not a fork.
0.3 Confirm the `inngest-cutover` reviewer set is still non-empty.
0.4 Read all three `.c4` files and complete the enumeration the ADR/C4 gate requires.
0.5 Verify `--history-retention` against the unit file.
0.6 Confirm `RECUT-INNGEST-VOLUME` collides with no existing confirm literal, and that the
    `workflow_dispatch` input count is at 7 before adding the 8th.

### Phase 1 — MERGE A: the read channel, and nothing else

Extend `SOLEUR_INNGEST_SERVER_PROBE` at **both** emit sites with `probe_schema=2`, `flush_latched`,
`latch_flushed_at`, `latch_lines`, `redis_keys` (`INFO keyspace`, all dbs, `__UNREADABLE__` on any
error), `data_mount_src` (`findmnt -no SOURCE /mnt/data`), and `data_bytes` (`du -sb /mnt/data`).
Emit from the terminal no-op arms too. Scope the new fields to the dedicated host — this bootstrap
is the **shared** renderer for both hosts. Give the probe unit its Redis credential without shipping
raw stderr.

**No `.tf` change and no cloud-init LUKS block in this merge.** That is what keeps
`inngest_host_replace_gate`'s three-address allow-set satisfied and makes Dispatch A possible.

This is **not** the webhook readback ADR-100 Decision 6a rejected. It adds no inbound control plane
and no new transport — it extends an emitter that already runs, over the transport ADR-100 records
the operator choosing on 2026-08-25. Decision 6a stands unamended.

### Phase 2 — MERGE B: LUKS apparatus

2.1 `inngest-redis-luks.tf` — `random_password.inngest_redis_luks` (length 40, `special = false`,
    no `ignore_changes`) + `doppler_secret.inngest_redis_luks_key` → `INNGEST_REDIS_LUKS_KEY` on
    `soleur-inngest/prd`, masked. **One file** — the posture linter requires co-location. Both go
    into the per-merge `-target=` allowlist so the passphrase exists before any host reads it.
2.2 `lifecycle { ignore_changes = [format] }` on `hcloud_volume.inngest_redis`; the `format` line
    drops only on the recut branch.
2.3 The five-arm cloud-init LUKS stage with the bounded device-presence wait, the `expect_luks`
    flag threading, and git-data's hardening (exec'd child, ERR trap, `blkid` rc 0-or-2 with any
    other rc fatal, damaged-header detection, per-operation rc checks).
2.4 `inngest-luks-open.service` — the boot-reopen unit. `runcmd` runs first boot only, so without
    this the mapper is absent on boot 2.
2.5 The two-state `ExecStartPre` `findmnt` gate on the Redis unit.
2.6 `SOLEUR_INNGEST_LUKS_STAGE` in `vector.toml` Source 4 **and** its drift fixture, same commit.
2.7 `inngest-redis-luks.test.sh`, registered in `infra-validation.yml`.

### Phase 3 — MERGE B: the gated apply_target

3.1 **Write both mutation matrices BEFORE the guards.** A matrix derived from finished code tests
    the code that exists; one derived from the design tests the property.
3.2 `inngest-volume-recut-gate.sh` + its suite.
3.3 `inngest-host-dark-gate.sh` + its suite, including the drop-one battery.
3.4 The workflow job: `environment: inngest-cutover`, typed confirm, `expected_inngest_volume_id`,
    the shared `concurrency` group, no `[ack-destroy]` bypass, never auto-executed, never chained.
3.5 All six registration sites, including the `confirm` input description.
3.6 The mechanically-runnable mutation harness (B10).

### Phase 4 — MERGE B: records

ADR-142 addendum; the new ADR; ledger row **keeping its exception** with the citation fixed;
Article 30 PA-13(e); the `compliance/` issue for PA-13(f); the append-only-latch-clear fallback
issue; the destruction-record template.

### Phase 5 — Verification

`bash scripts/test-all.sh` in full; `lint-encryption-posture.py --repo-sweep`; `terraform validate`;
`actionlint`; the guard harness with independent re-mutation.

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/infra/inngest-redis-luks.tf` | `random_password.inngest_redis_luks` + `doppler_secret.inngest_redis_luks_key`, co-located so the posture linter can resolve the citation |
| `tests/scripts/lib/inngest-volume-recut-gate.sh` | Sourced destroy-guard; the same bytes CI and the test both call |
| `tests/scripts/test-inngest-volume-recut-gate.sh` | Mutation matrix + harness rows for Guard 1 |
| `tests/scripts/lib/inngest-host-dark-gate.sh` | Guard 2 decision function (positive allowlist on `dark`) |
| `tests/scripts/test-inngest-host-dark-gate.sh` | Mutation matrix + harness rows for Guard 2 |
| `apps/web-platform/infra/inngest-redis-luks.test.sh` | LUKS apparatus guard: no `format` on the volume, key on `soleur-inngest` not `soleur`, blkid discriminator present, three-arm coverage |
| `knowledge-base/engineering/architecture/decisions/ADR-199-*.md` | New decision (ordinal provisional — re-derive before merge) |
| `knowledge-base/legal/audits/inngest-aof-destruction-record.md` | Art. 5(2) destruction record template |
| `apps/web-platform/infra/inngest-luks-open.service` (or its `write_files` stanza) | Boot-reopen unit — `runcmd` runs first boot only, so the mapper is otherwise absent on boot 2 |

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/infra/inngest-host.tf` | Remove `format = "ext4"` from `hcloud_volume.inngest_redis` |
| `apps/web-platform/infra/cloud-init-inngest.yml` | Three-arm LUKS stage replacing the plaintext mount; `ExecStartPre` findmnt re-assertion |
| `apps/web-platform/infra/inngest-bootstrap.sh` | **Merge A.** Extend `SOLEUR_INNGEST_SERVER_PROBE` at **both** emit sites (the `logger -t` line and the `inngest-boot-phone-home.sh` Vector-down fallback) with `probe_schema`, `flush_latched`, `latch_flushed_at`, `latch_lines`, `redis_keys`, `data_mount_src`, `data_bytes`; scope to the dedicated host; add the Redis credential |
| `apps/web-platform/infra/vector.toml` | Add `SOLEUR_INNGEST_LUKS_STAGE` to Source 4 `include_matches.SYSLOG_IDENTIFIER` |
| `apps/web-platform/test/infra/vector-pii-scrub.test.sh` | Drift fixture for the new tag — same commit as the allowlist |
| `.github/workflows/apply-web-platform-infra.yml` | `inngest-volume-recut` in `options:` + the bound gated job; `expected_inngest_volume_id` input; the `confirm` input **description** (it enumerates which targets carry an `environment:` gate); the passphrase pair added to the per-merge `-target=` allowlist; `concurrency` groups on the recut, `inngest_host` and `inngest_host_replace` jobs |
| `.github/workflows/cutover-inngest.yml` | The shared `inngest-cutover` concurrency group on the arm/resume path — a mutex on one side of a race is not a mutex |
| `plugins/soleur/test/terraform-target-parity.test.ts` | Register the new apply_target |
| `plugins/soleur/test/stock-preflight-coverage.test.ts` | `EXCLUSION_ALLOWLIST` entry |
| `scripts/test-all.sh` | `run_suite` lines for both new gate suites |
| `.github/workflows/infra-validation.yml` | Register `inngest-redis-luks.test.sh` — an unregistered infra suite silently never gates (#7695) |
| `scripts/encryption-posture-ledger.json` | Rewrite the `hcloud_volume.inngest_redis` row: 5 fields, content-anchored evidence, exception block removed |
| `knowledge-base/engineering/architecture/decisions/ADR-142-*.md` | Addendum recording measured fact |
| `knowledge-base/legal/article-30-register.md` | PA-13 limb (e) substrate correction |

## Acceptance Criteria

Rewritten after review: the first draft had 12 of 22 criteria that were ceremony, unverifiable,
evadable, or would have passed on a broken implementation — including one that would have passed on
an actively false compliance claim. Every criterion below names a command or a checkable
post-condition.

### Merge A (read channel)

A1. `SOLEUR_INNGEST_SERVER_PROBE` emits `probe_schema=2`, `flush_latched`, `latch_flushed_at`,
    `latch_lines`, `redis_keys`, `data_mount_src`, `data_bytes` — from **both** emit sites (the
    unconditional `logger -t` line and the `inngest-boot-phone-home.sh` Vector-down fallback).
A2. A test asserts the two emit sites' field lists are **identical**, mirroring the
    two-halves-must-not-drift pattern `inngest-server-flip-guard.test.sh` already uses.
A3. A failed `INFO keyspace` (bad auth, Redis down, missing `# Keyspace` header) emits
    `redis_keys=__UNREADABLE__` — never an empty string and never `0`. Pinned by a test that feeds
    an error string through the extractor.
A4. The probe unit has the Redis credential it needs, and its stderr is not shipped raw — the same
    discipline the file already applies to credentialed CLI output, so a token's own error text
    cannot reach Better Stack.
A5. On the co-located web host the new fields emit as `n/a`, never `0`. Pinned by a fixture.
A6. `bash tests/scripts/test-inngest-host-replace-gate.sh` still passes — Merge A must not perturb
    that gate's three-address allow-set.

### Merge B (apparatus + gated target) — pre-merge

B1. `bash scripts/test-all.sh` exits 0 — the **full** suite. An unregistered apply_target is only
    visible there.
B2. `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0 **with the row still carrying
    its `exception` block** (`tracking_issue: #6894`, a future `expires_on`). A row asserting
    `mechanism: luks` at merge would be a false at-rest claim about user prompts and agent output
    for an unbounded — possibly permanent — window.
B3. `grep -c 'inngest-host\.tf:[0-9]' scripts/encryption-posture-ledger.json` returns `0`.
B4. `terraform plan` for `apply_target=inngest-host` shows **zero deletes** after the
    `ignore_changes = [format]` change. Record the verbatim plan line.
B5. `random_password.inngest_redis_luks` and `doppler_secret.inngest_redis_luks_key` appear in the
    per-merge `-target=` allowlist — the passphrase must exist before any host boots that reads it.
B6. `inngest-volume-recut` appears in all **six** registration sites: the workflow `options:`, its
    bound job, `terraform-target-parity.test.ts`, `stock-preflight-coverage.test.ts`,
    `test-all.sh`, and `.github/workflows/infra-validation.yml` (with `run-registered-suites.sh` as
    the local runner). The workflow's `confirm` input **description** — which enumerates which
    targets carry an `environment:` gate — is amended too, or the workflow's own documentation
    asserts something false.
B7. The enum option and its guarded job are **bound**: a check fails if either exists without the
    other.
B8. `RECUT-INNGEST-VOLUME` is distinct from every existing confirm literal, and
    `expected_inngest_volume_id` is declared as a dispatch input (slot 8 of 10; no second input).
B9. The recut job, `inngest_host`, `inngest_host_replace`, and the `cutover-inngest` arm/resume
    workflow all declare `concurrency: {group: inngest-cutover, cancel-in-progress: false}`.
B10. **Guard batteries are mechanically runnable, not asserted.** A committed harness applies each
    mutation as a patch to a pristine copy, runs the guard, and asserts the **reason token** — not
    merely a non-zero rc. Invoked from `test-all.sh`. This replaces the first draft's
    "demonstrated by an independent re-mutation", which was an unfalsifiable claim.
B11. Guard 2 has a **drop-one battery**: one case per condition, each dropping exactly that
    condition and asserting a distinct reason token. This replaces the first draft's
    "returns `dark` for no input other than full satisfaction", which is an unverifiable universal.
B12. A test feeds a **real emitter line** through the Guard 2 parser and asserts every field name
    resolves — the emit/read contract, which nothing in the first draft pinned.
B13. `grep -c 'DBSIZE' tests/scripts/lib/inngest-host-dark-gate.sh` is `0`, and a mutation row
    asserts the gate never reads `latch_dbsize` (a historical db-0-only reading that sits one field
    away from `redis_keys`).
B14. The cloud-init LUKS stage contains no `|| true`, no `|| :`, and no `set +e` on any step that
    could leave `/mnt/data` on the root disk; the fstab line **retains** `nofail` (loud failure
    belongs in `ExecStartPre`, not in a boot-wedging fstab on a no-SSH host).
B15. `inngest-redis-luks.test.sh` covers all five `blkid` arms, and carries the case pinning that
    the **`ext4` arm still permits Redis to start** pre-recut — the regression test for the
    `ExecStartPre` deadlock.
B16. The boot-reopen unit is exercised against a **second simulated boot** via the loop-file
    harness; the mapper is present and `/mnt/data` is on it.
B17. `SOLEUR_INNGEST_LUKS_STAGE` appears in **both** `vector.toml` Source 4 and
    `vector-pii-scrub.test.sh`, in the same commit.
B18. The `inngest-cutover` environment reviewer set is asserted non-empty by a check that **fails
    when it is emptied** — named file, with environment-API read access.
B19. ADR-142 carries the addendum; the new ADR exists; `grep -rn 'ADR-<n>'` across the plan, tasks,
    and the ADR filename agree on one ordinal.
B20. Article 30 PA-13 limb (e) no longer says "SQLite"; a `compliance/` issue exists for limb (f).
B21. An issue exists for the append-only authorized latch clear — the stated fallback for the
    `redis_keys > 0` branch (`wg-when-deferring-a-capability-create-a`).
B22. PR bodies use `Tracks #7695`, `Tracks #7674`, `Tracks #6894` — **never `Closes`**.

### Post-merge (gated dispatches — separate operator decisions at the window)

P1. Dispatch A completes; a `probe_schema=2` row lands on the new `boot_id` within the 2h watch.
P2. **`scripts/followthroughs/inngest-host-not-serving-7674.sh` reads PASS.** This gates everything
    below it. Dispatching the recut before this is strictly counterproductive: the first `arm` would
    write a fresh latch, fail `verify_or_abort`, and land in terminal `aborted`.
P3. `INNGEST_DIAGNOSTIC_BOOT` is cleared **before** Dispatch B, so Dispatch C's boot re-bakes the
    unit and no fourth replace is needed.
P4. A probe row carrying the latch record and `data_bytes` has landed **before** any destructive
    dispatch — it is Guard 2's input and the only surviving audit record of what is destroyed.
P5. **Decision point.** All Guard 2 conditions hold ⇒ recut authorized. `redis_keys > 0` or
    `mount_mismatch` ⇒ refused; route per the verdict table.
P6. Dispatch B's saved plan shows `hcloud_server.inngest` with **zero actions**.
P7. Post-recut: `SOLEUR_INNGEST_LUKS_STAGE` rc=0 through `stage=fstab`; `/mnt/data` is a genuine
    mountpoint on `/dev/mapper/inngest-redis`; `redis_active=active`.
P8. A reboot of the recut host leaves `/mnt/data` still on the mapper — the boot-reopen unit
    working in production, not just in the harness.
P9. The ledger row flips to `luks` and the `exception` block is removed **only now**, in the
    follow-up commit, gated on P7.
P10. The Art. 5(2) destruction record is completed with the observed `redis_keys`, `data_bytes`,
    and latch state from P4's row.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The store is not actually empty and the recut destroys recoverable armed reminders.** The historical question is unanswerable at ~20d retention. | Do not answer it. Guard 2 requires `redis_keys == 0` measured **now**, on the current `boot_id`. Non-empty ⇒ refused outright and routed to ADR-142. |
| **Removing `format = "ext4"` queues an unscheduled replace.** | Phase 0.2 measures it with `terraform plan` before anything else. The volume is outside every merge-apply `-target=` list, and Guard 1's ID-PIN binds any destroy to an operator-named physical id. |
| **The destroy guard is scoped one address too wide and reaches `hcloud_volume.workspaces["web-1"]`.** | Named-live backstop counters make that address independently load-bearing, plus the `out_of_scope` catch-all for anything nobody enumerated. Mutation rows 1 and 2 pin both. |
| **State corruption maps the correct address to the wrong physical volume.** | ID-PIN against `.change.before.id`; address-based counters all read 0 in exactly this scenario, which is why the pin exists. |
| **LUKS mount fails open; Redis writes plaintext AOF to the root disk.** | No `|| true` on the mount path; `ExecStartPre` findmnt re-assertion refuses to serve off an unmounted path; the FSM's own mountpoint gate independently emits `latch-unrecordable` and drives terminal `aborted`. |
| **The new tag never leaves the host** because Source 4 matches by exact value and a typo matches nothing. | Allowlist entry and drift fixture land in the same commit, asserted on both sides. |
| **The latch's re-arm path breaks**, so every future flip aborts `latch-unrecordable`. | AC20 asserts `/mnt/data` is a genuine mountpoint on the mapper post-recut — the property `record_flush_latch` depends on. |
| **A `-replace` strands the volume out of state** between destroy and create (no `create_before_destroy`). | Guard 1 accepts the recovery bare-create shape (`["create"]`, `before == null`), so a re-dispatch converges instead of looping. Harness row H3 pins it. |
| **Passphrase `-replace` mints a new key without rekeying the header**, stranding the store. | No `ignore_changes`; Guard 1 mutation row 4 reddens on any update/delete/forget. Rotation is `cryptsetup luksChangeKey`, documented in the ADR. |
| **The new host boots with its private NIC down** after replace. | Known class; converge is verified via Better Stack rows, never hand-verification. `hcloud_firewall_attachment` is deliberately not `-target`ed. |
| **The recut is dispatched before #7674 is fixed**, so the first `arm` re-writes the latch, fails `verify_or_abort`, and lands in terminal `aborted` — one-shot spent, strictly worse than today. | Guard 2 condition 10 requires `inngest-host-not-serving-7674.sh` to read PASS, and condition 11 requires `INNGEST_DIAGNOSTIC_BOOT` clear. This is the single most consequential precondition in the plan. |
| **A concurrent `op=arm` races the apply**, destroying the volume mid-`FLUSHALL`. | Shared `inngest-cutover` concurrency group across the recut, `inngest_host`, `inngest_host_replace` and the cutover workflow, plus a synchronous Doppler flag re-read immediately before apply. |
| **Redis reports an empty store while the volume holds a populated AOF** (mount failed open onto the root disk). | Guard 2 condition 8 pins `data_mount_src` to the expected device; condition 9 reports `data_bytes` as an audit field. `redis_keys` alone was never a statement about the block device. |
| **The mapper is absent on the second boot**, so Redis writes plaintext to the root disk while the ledger claims LUKS. | `inngest-luks-open.service` is a deliverable, exercised against a simulated second boot. The `ExecStartPre` gate turns the residual case into a loud refusal rather than silent plaintext. |
| **Widening `inngest_host_replace_gate` to unblock Merge A** would create an unguarded second recut path — that target has no reviewer gate, no confirm and no id-pin. | Merge A carries no `.tf` change, so the gate passes unchanged. The split exists precisely so nobody reaches for the widening. |
| **The ledger claims LUKS while the volume is plaintext.** | The row is staged: the exception is retained and re-dated at merge, and flipped only in a follow-up gated on post-recut verification. |
| **This plan's own measurements rot.** | Phase 0.1 re-runs every reading. Guard 2 encodes the premise as a dispatch-time check, so the plan cannot be correct on 2026-09-02 and silently wrong later. |

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| **Execute ADR-142's full byte-copy migration inside #7695** | It clears the latch for free (the copy set is `redis/` only, so `inngest-cutover/` does not come across) and closes #6894 — genuinely attractive. Rejected as a **scope collision**: it folds quiesce/freeze/canary/mount-swap/backstop into a latch-clearing PR, and its three FATAL footguns buy nothing when the store is empty. It remains the mandatory path when `redis_keys > 0`, so it is not discarded — it is the other branch of the gate. |
| **A new FSM verb: append-only authorized latch clear** (write `flip-done.cleared`, predicate becomes "newest latch not superseded by a newer clear") | Genuinely cheaper and touches no volume. Rejected for this PR because it does **not** close the `plaintext-exception` expiring 2026-10-22, and because it adds a terminal state to a safety FSM whose `L` polarity already inverts between `op=arm` and `op=resume` — a change needing its own ADR and its own six-site sweep. Recorded as the fallback if Phase 0.2 shows the `format` removal is unsafe. |
| **Refine `flush_already_performed()`'s refusal instead of erasing its evidence** — refuse re-arm unless the store is provably empty and the host provably dark | The most elegant option: preserves #5450 exactly (a live prod queue has keys and serves 200), touches no volume, needs no destructive target. Rejected only because it needs the same Phase 1 read channel and interacts with `L`'s polarity inversion. **Worth re-grading at plan-review** — if it survives, it may dominate. |
| **R2 header escrow, mirroring `workspaces-luks-header.tf`** | Rejected by ADR-142 by name, on confidentiality grounds. See §Escrow. |
| **Webhook readback of the latch** | ADR-100 Decision 6a stands unamended; declined 2026-08-25. Phase 1 meets the intent over the already-adopted transport instead. |
| **Recut to plaintext ext4, defer LUKS** | Recreates a `plaintext-exception` the ledger wants closed, while paying the entire cost of a destructive recut. Strictly dominated. |

## Test Scenarios

Beyond the two mutation matrices (which are the primary deliverable — for a change whose deliverable
*is* guards, scenarios of the shape "command X → terminal Y" test the thing being guarded, not the
guard):

1. Guard 1 against a synthesized canonical recut plan → PASS.
2. Guard 1 against the recovery bare-create plan, no `expected_id` → PASS (non-canonical must-PASS).
3. Guard 1 against each of mutation rows 1-9 → ABORT, asserting the **reason token**, not just rc.
4. Guard 2 against a synthesized dark+empty row set → `dark`.
5. Guard 2 against a busy fleet (many `function.finished` from `soleur-web-platform`, none from
   `soleur-inngest`) with a dark inngest row → `dark` (non-canonical must-PASS).
6. Guard 2 against zero rows → `silent`, never `dark`.
7. Guard 2 against an unparseable count → `unreadable`, never `dark`.
8. Cloud-init three-arm dispatch: `ext4` → mounts, does not format; empty → formats; `crypto_LUKS`
   → opens only; `xfs` → FATAL halt.
9. `lint-encryption-posture.py --repo-sweep` fails when the `random_password`/`doppler_secret` pair
   is split across files — pinning that the linter's co-location requirement is actually satisfied
   rather than incidentally passing.

## Decision Challenges

Headless run — these are recorded here and in
`knowledge-base/project/specs/<branch>/decision-challenges.md` for `/ship` to render into the PR
body and file as an `action-required` issue. They are **not** applied silently.

1. **The brief's scope item 2 is narrowed.** The brief directs recutting as LUKS mirroring
   `workspaces-luks-recut` *including its R2 header escrow*. The escrow is **cut** — ADR-142
   rejects it for this store by name, and copying it would reverse an accepted ADR while adding a
   CWE-522-class artifact. The LUKS recut itself is retained.

2. **The destructive recut is now gated on a measurement that does not yet exist.** The brief
   treats "the host is dark, so the recut is cheap" as established. It is established for
   2026-08-20→now, but the flip that wrote the latch was in July on a previous host generation, so
   the evidence window begins after the window of concern. The plan therefore builds the read
   channel first and makes `redis_keys == 0` a hard precondition. **If the store turns out
   non-empty, this plan does not authorize the recut** — the work routes to ADR-142's byte-copy
   under #6894. That is a real possibility the brief does not contemplate.

3. **A cheaper option may dominate and should be graded at plan-review.** Refining
   `flush_already_performed()`'s refusal (empty-store + dark-host predicate) clears the blocker
   without any destructive target, without touching the volume, and without a new apply_target.
   It does not close the encryption exception, so it is not a full substitute — but if #6894 is
   going to run ADR-142's migration anyway, this plan may be building a destructive capability
   that the migration would make unnecessary.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above with a
  concrete artifact and a concrete exposure vector.
- The ADR-199 ordinal is provisional and **will** move if a sibling PR claims it. Re-derive against
  freshly-fetched refs before merge and sweep this plan, `tasks.md`, and AC14 in the same edit.
- Guard fixtures must be **synthesized** plan JSON. A captured production plan would embed real
  volume ids and drift silently (`cq-test-fixtures-synthesized-only`).

## Addendum — 2026-09-02 (#7695, Merge A as delivered)

Appended, not edited: everything above is the plan as approved, and the rows below are what the
review panel changed about its delivery. Three findings were verified at source and each one
narrows what Merge A ships. Merge B must read this section before implementing Guard 2.

### D1 — the dedicated/web discriminator is `DOPPLER_PROJECT`, not the mountpoint

The implementation first gated the store fields on "is `/mnt/data` a mountpoint", on the stated
premise that the co-located web host has no `/mnt/data`. **That premise is false.**
`cloud-init.yml` (`mkdir -p /mnt/data` / the `scsi-0HC_Volume_${workspaces_volume_id}` fstab line
/ `mount /mnt/data`) mounts the **workspaces** volume there. On web-1 the test is true, so the
probe would have walked every user's repository tree hourly and shipped the aggregate byte count
off-box — and a web-host row could have carried a store measurement into Guard 2's clearance
condition.

Delivered instead: `host_role` derived from `DOPPLER_PROJECT` (`soleur-inngest` = dedicated,
anything else = web), this codebase's canonical discriminator, reaching the unit through
`EnvironmentFile=-/etc/default/inngest-server`. `host_role` is now an **emitted field**, so Guard 2
can refuse any row that does not positively identify itself as the dedicated host rather than
inferring it from `instance_id` or `data_mount_src`.

### D2 — `redis_keys` is NOT delivered. Guard 2 condition 5 has no input.

**This is the one item Merge B must act on.** Guard 2 condition 5 (`redis_keys == 0`, from
`INFO keyspace` across all dbs) has no field to read, because the probe no longer emits one.
Three independent reasons, any one sufficient:

1. **It cannot be authenticated.** `inngest-redis.service` starts redis with `--requirepass`, and
   the probe unit's only env source is `/etc/default/inngest-doppler` (`HOME`, `DOPPLER_TOKEN`,
   `DOPPLER_CONFIG_DIR`, `DOPPLER_ENABLE_VERSION_CHECK` — no redis password). In production the
   field would have read `__UNREADABLE__` on every fire, forever, while the tests exercised only
   the fixture seam. The plan's "add the Redis credential" task is what would have fixed it.
2. **The fix is not available to this merge.** Supplying the credential means wrapping the probe's
   `ExecStart` in `doppler run`, as `inngest-cutover-flip.service` does. But that unit is rendered
   by `inngest-bootstrap.sh`, which is **shared with the web host**, and `/usr/bin/doppler` is a
   symlink created only by `cloud-init-inngest.yml`; the web host installs to `/usr/local/bin` and
   has no such symlink. The shared unit would fail `203/EXEC` on web-1 and silently end the hourly
   liveness marker on the host that actually serves. `doppler run` also injects every secret in the
   config as an env var, which would make the probe's fixture seam settable by anyone with Doppler
   write access.
3. **It measures the wrong object anyway.** R2 above already says so: `redis_keys` is a claim about
   a Redis *process*, not about the block device being destroyed. The plan's own preserve list —
   mount-source pinning, `data_bytes`, the host-identity conjunction, the `__UNREADABLE__`
   sentinels — does not include it.

**Merge B must therefore either** drop condition 5 and rest the emptiness claim on `data_bytes` +
`data_mount_src` + `host_role` (the recommended reading of R2), **or** first solve (1) and (2) —
a probe-specific env file carrying only `INNGEST_REDIS_PASSWORD`, or a host-role-conditional
`ExecStart` — and re-add the field at `probe_schema=3`. It must not silently treat a missing
`redis_keys` as satisfied; the plan's own case 12 ("absence must not parse to `0`") is the rule.

### D3 — `latch_flushed_at` and `latch_lines` are not delivered; task 1.8 is not delivered

`latch_flushed_at` and `latch_lines` had no consumer in any Guard 2 condition and no arm in which
either could be a measurement rather than a constant; `latch_lines` additionally degraded to `0`
on the not-latched path, which is the one value the whole degradation vocabulary exists to
prevent. Both were dropped. `flush_latched` alone carries the latch question.

Task 1.8 (mirror the new fields from `inngest-cutover-flip.sh`'s terminal no-op arms) is **not
delivered**. The implementation shipped a `flush_latched` mirror there and review rejected it on
four counts: the bit was computed by a *different* predicate than the FSM's own
`flush_already_performed` (`-f` vs `-e`, no mount gate, and missing the documented
"completed before this change shipped" arm), so a host in terminal `done` would have emitted
`{"flag":"done","flush_latched":false}` twice a minute — a self-contradictory row from the source
of truth — and the same field name would have meant two different things in the two files that
emit it. `inngest-cutover-flip.sh` is therefore byte-identical to `main` in Merge A. If Merge B
wants the mirror, it must call `flush_already_performed` itself rather than re-deriving the bit.

### D4 — probe field list as actually shipped (`probe_schema=2`)

`probe_schema`, `host_role`, `flush_latched`, `data_mount_src`, `data_bytes` — at **both** emit
sites, pinned byte-for-byte against each other. Degradation vocabulary unchanged: `n/a` (does not
apply on this host) and `__UNREADABLE__` (applied, unanswerable), never `0`. `flush_latched`
inherits `data_bytes`' unreadability rather than being tested independently, because `[ -f ]`
cannot distinguish "no latch" from "cannot read the directory" — on a volume detached while still
mounted it would emit `false`, a positive claim about a store never read.

## Addendum — 2026-09-03 (#7695, Merge B): §D2 reason 2 was FALSE, and the CTO reversed it

Appended, not edited. §D2 above stands as the record of what Merge A shipped and why I believed
it at the time. This section records that one of its three reasons does not survive contact with
the source, and that the decision it drove has been reversed for Merge B.

### The false claim

§D2 reason 2 says supplying the probe's Redis credential "means wrapping the probe's `ExecStart`
in `doppler run`", and that doing so would fail `203/EXEC` on the co-located web host because
`/usr/bin/doppler` is symlinked only by `cloud-init-inngest.yml`.

**The premise is false.** The probe unit as rendered by `inngest-bootstrap.sh` already carries two
tolerant environment files and a plain script `ExecStart`:

```
EnvironmentFile=-/etc/default/inngest-doppler
EnvironmentFile=-/etc/default/inngest-server
ExecStart=/usr/local/bin/inngest-server-probe.sh
```

A third `EnvironmentFile=-/etc/default/inngest-probe` is shape-identical to what is already there.
`ExecStart` is not touched, so there is no `/usr/bin/doppler` dependency and no `203/EXEC` on
web-1 — that host simply has no such file, the `-` prefix tolerates the absence, and
`INNGEST_REDIS_PASSWORD` stays unset, which is the honest state for a host with no inngest Redis.

The second sub-objection (that `doppler run` would inject every secret and make the fixture seam
settable by anyone with Doppler write access) dissolves with it: a one-variable env file injects
one variable.

The pattern is not even new. `web-probe-envwrite.sh` already writes a single-purpose
`/etc/default/inngest-consumer-probe` under `umask 0137` + `chmod 600`, consumed by
`EnvironmentFile=` in `inngest-consumer-probe.service`.

### How it got shipped, and where it propagated

I reasoned from "the unit needs a secret" to "the unit must run under `doppler run`" without
reading the unit I had edited in the same PR. The claim then went into this plan's §D2, into the
compound learning, into PR #7754's body, and into its commit message — four sites, two of them
now on `main` and one immutable — before anything tested it. Grepping the OLD claim is what
found them; a residual count over the corrected text would have been blind to every one.

That is the same defect class §D1 records one level up: §D1 was a false premise about a *host*,
this is a false premise about a *unit*, and both were written into a comment as settled fact.

### What Merge B does instead (CTO ruling, 2026-09-03)

Option (d): re-add `redis_keys` at `probe_schema=3`, credentialed by a probe-specific
single-secret env file, and rest Guard 2's emptiness claim on `redis_keys == 0` **conjoined with**
`data_mount_src` pinning. Rejected alternatives, with the reasoning, are recorded in the new ADR
rather than restated here.

Two consequences worth stating at this file's level:

- **§D2 reason 3 was overstated.** R2's remedy was to ADD mount-source pinning, not to retire
  `redis_keys`. With `data_mount_src` pinned to the physical volume and `redis_active=active` on
  the same row, the Redis process's `dir` provably sits on the block device being destroyed, and
  `INFO keyspace = 0` becomes a statement about that device. The conjunction is what bridges
  process to device — which was always R2's design.
- **Plan condition 11 has no input either, and §D2 did not catch it.** `INNGEST_DIAGNOSTIC_BOOT`
  is not an emitted field; the probe emits `cutover_flag` (a read of `INNGEST_CUTOVER_FLIP`) and
  nothing about diagnostic boot. It moves to a dispatch-time synchronous Doppler read, which is
  strictly better than a ≤90-minute-old snapshot.

## Addendum — 2026-09-03 (#7695, Merge B as delivered)

Appended, not edited, except for the ADR ordinal — which this plan itself declared **provisional**
and instructed to be re-derived before merge, so resolving it is the instructed action rather than
a rewrite of a dated reading. Everything else above stands as approved.

### The ADR ordinal moved 198 -> 199, and re-deriving against `origin/main` alone would have missed it

`origin/main`'s highest is **ADR-197**, so a `max+1` against main yields 198 — the value this plan
carried. Re-derived across **all 67 `origin/*` refs** on 2026-09-03,
`ADR-198-baking-the-better-stack-ingest-token-into-git-data-user-data.md` already exists on the OPEN
branch `feat-one-shot-7460-betterstack-baked-token`. The next free ordinal is therefore **ADR-199**,
and every reference in this plan and in `tasks.md` now says so.

This is the collision class the plan's own §Sharp Edges anticipated, arriving exactly as described.
The derivation that catches it is over refs, not over `main`:

```
for r in $(git for-each-ref --format='%(refname)' refs/remotes/origin/); do
  git ls-tree -r --name-only "$r" knowledge-base/engineering/architecture/decisions/ 2>/dev/null
done | grep -oE 'ADR-[0-9]+' | sort -t- -k2 -n -u | tail -1
```

### B4 is FALSIFIED AS WRITTEN, and the property it exists to establish HOLDS

AC B4 says: "`terraform plan` for `apply_target=inngest-host` shows **zero deletes** after the
`ignore_changes = [format]` change. Record the verbatim plan line."

Run on 2026-09-03 against the live state, with the `inngest_host` job's own sixteen `-target`s:

```
Plan: 3 to add, 1 to change, 3 to destroy.
```

So the literal criterion is **NOT met**, and the AC is recorded here as falsified rather than
quietly satisfied by a looser reading. The three destroys, measured per address from
`terraform show -json`:

| Address | Actions | Why |
|---|---|---|
| `hcloud_server.inngest` | `delete,create` | `~ user_data … # forces replacement` — this merge's cloud-init edits, which the plan authorizes explicitly |
| `hcloud_server_network.inngest` | `delete,create` | `~ server_id … # forces replacement` |
| `hcloud_volume_attachment.inngest_redis` | `delete,create` | `~ server_id … # forces replacement` |
| **`hcloud_volume.inngest_redis`** | **`no-op`** | **the property B4 exists to establish** |

`ignore_changes = [format]` does exactly what §2.2 claims: the volume is **untouched**, so keeping
`format = "ext4"` declared does not queue a replace. What B4's wording did not anticipate is that
Merge B's own cloud-init edits force a host replace in the same plan — `user_data` is ForceNew with
no `ignore_changes` — so a zero-delete plan for this target was never reachable from this branch.

**The corrected criterion, and it was measured PASSING:** the delivery vehicle for a cloud-init edit
is `apply_target=inngest-host-replace`, not `inngest-host`. That job's own plan
(`-replace=hcloud_server.inngest` plus its three `-target`s) was run and graded with the REAL gate:

```
Plan: 3 to add, 0 to change, 3 to destroy.
inngest_out_of_scope_changes=0 redis_volume_destroyed=0 inngest_server_replaced=1
inngest_host_replace_gate: PASS — scoped inngest-host recreate permitted
  (server + 2 dependents replace; Redis AOF volume preserved)
```

`redis_volume_destroyed=0` is the AOF-preservation property, measured rather than asserted, on the
branch as it will merge. Dispatch A is therefore still reachable after this merge — which is what
B4 was ultimately protecting and what a zero-delete count was standing in for.

### Two P0s in Merge B's own Phase 2, found by the suite written to satisfy B15/B16

`inngest-luks-open.service` shipped (a) never `systemctl enable`d and (b) reading
`INNGEST_REDIS_LUKS_KEY` from `/etc/default/inngest-doppler`, which carries only `HOME` and the
Doppler token. Either alone leaves the mapper closed on boot 2, the `nofail` fstab line skipping
silently, and Redis writing its AOF to the ephemeral root disk — the exact failure the unit exists
to prevent. The comment above the unit asserted "there is no second credential path to keep in
sync", which is how it passed reading. Task 2.10's two-state `ExecStartPre` guard was also not
delivered. All three are fixed in this merge and pinned by mutation-proven structural arms.

### AC B9's concurrency literal was changed, deliberately

B9 named a NEW `inngest-cutover` group for four surfaces. A GitHub job may declare exactly ONE
concurrency group, and `cutover-inngest.yml` already serialises on `deploy-inngest-restart` together
with `deploy-inngest-image.yml` and `restart-inngest-server.yml`. Minting a new literal and putting
it on the cutover job would have REMOVED that job from the group it shares with the deploy pipeline,
letting a deploy restart inngest-server mid-cutover — a strictly worse race than the one B9 set out
to close. All four surfaces now carry the EXISTING literal, which covers six surfaces instead of
four and orphans none. `terraform-target-parity.test.ts` asserts the PROPERTY (all four carry one
identical group) rather than the string, so the guard survives a rename.

### A third instance of the #6178 boot-brick class, in the same regex

`cloud-init-inngest.yml`'s boot isolation self-check is EXACT-SET, and its admitting regex did not
know `INNGEST_REDIS_LUKS_KEY`. Since this merge puts the passphrase pair in the per-merge `-target=`
allowlist (AC B5), the secret lands at merge — from which point `n_total != n_inngest` FATALs every
re-provision, with no Vector to report it. Admitted, placed before `HEARTBEAT_URL` so the existing
top-level-anchor assertion still reads, and pinned behaviourally rather than by source fragment.
