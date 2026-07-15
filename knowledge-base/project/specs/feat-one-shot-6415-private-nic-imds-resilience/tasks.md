# Tasks — feat-one-shot-6415-private-nic-imds-resilience

Derived from the **finalized (post-review) v2** plan:
[`2026-07-15-fix-private-nic-boot-convergence-plan.md`](../../plans/2026-07-15-fix-private-nic-boot-convergence-plan.md)

**Scope:** registry host **only** (git-data/inngest deferred — reboot on git-data would silently
unmount the LUKS store). **L1** (on-host converger) + **L2** (emit → alarm). **L3** (off-host probe)
is **deferred** — see `decision-challenges.md` UC-1.

**Lane:** `cross-domain` · **Threshold:** `single-user incident` · **CPO:** approve-with-conditions.

> **Read first (`/work` Phase 0):** the v2 plan's `## Plan-Review Consolidation`. Six agents found
> **three P0s in v1** — two of them were mechanisms v1 invented that *could not work*. The v2 shape is
> deliberate; do not re-add the netplan path.

---

## Phase 1 — Terraform: teach the host its IP, from ONE source

- [x] **1.1** `apps/web-platform/infra/zot-registry.tf:248` — add `private_ip = local.registry_private_ip`
      to the `templatefile(…)` map. (The local exists at `:40`. Non-secret.)
- [x] **1.2** `apps/web-platform/infra/network.tf:60` — replace the hardcoded `ip = "10.0.1.30"` with
      `ip = local.registry_private_ip`. **Load-bearing:** 1.1 promotes this constant to *reboot
      authority*; if the two literals drift, the guard bakes a wrong `EXPECTED_IP` and **reboots a
      healthy host to the cap**. (Same shape `inngest-host.tf` fixed after #6180.)
- [x] **1.3** Confirm no `hcloud_server` / `hcloud_server_network` schema change; **no** inline
      `network {}` block (force-replaces the host — `network.tf:9-13`).

## Phase 2 — L1: the on-host converger (`cloud-init-registry.yml`)

- [x] **2.1** `write_files` `/usr/local/bin/soleur-private-nic-guard.sh` (`root:root`, `0755`),
      mirroring `zot-disk-heartbeat.sh` (`:148-234`). Copy the bounded-wait shape from `:264-267`
      (the volume solves this identical race already).
  - [x] **2.1.1** `EXPECTED_IP='${private_ip}'`.
  - [x] **2.1.2** **Trigger predicate = the local fact ALONE**: `ip -4 -o addr show` + **exact-word**
        match (`grep -qw`). Present ⇒ `converged_by=already`, `nic_ok=true`, **exit 0 with zero
        mutation**. Never key the predicate on IMDS (telemetry, not a trigger).
  - [x] **2.1.3** Bounded wait (the `:264-267` shape) before acting.
  - [x] **2.1.4** Diagnose `imds_rc` / `imds_nets` via `curl -sf -m 5` on
        `…/hetzner/v1/metadata/private-networks`. **Exit-code-neutralize** — a nonzero exit is a valid
        data outcome and must not abort under `set -e`.
  - [x] **2.1.5** **Store-mount self-heal (fixes a pre-existing bug):**
        `mountpoint -q /var/lib/zot || { mount -a; mountpoint -q /var/lib/zot && docker restart zot; }`.
        The `docker restart` is **required** — `--restart unless-stopped` (`:369`) can start zot before
        the mount lands, so `mount -a` alone leaves the bind pointing at an empty dir. Emit
        `zot_store_mounted`.
  - [x] **2.1.6** **Converge — ONE primitive, a guarded reboot.** Single gate:
        `ip_present=false && imds_nets>0 && uptime_s>600 && reboot_count<2`.
    - [x] Counter at **`/var/lib/soleur/private-nic-reboots`** (**root disk**), keyed by **instance-id**,
          **literal cap 2**, written **before** the reboot.
    - [x] **Not** `/var/lib/zot` (survives replace ⇒ inherited exhausted budget). **Not** `/run`/`/tmp`
          (tmpfs ⇒ rotates per boot ⇒ infinite-reboot trap). **Not** `boot_id`-keyed.
    - [x] No cooldown (redundant with a hard cap).
  - [x] **2.1.7** **Emit always** (success *and* failure), 9 fields:
        `SOLEUR_PRIVATE_NIC nic_ok= converged_by= imds_rc= imds_nets= reboot_count=
        zot_store_mounted= uptime_s= boot_id= zot_last_err=` (**`zot_last_err` LAST**).
    - [x] The field **must** be `zot_last_err`, not `last_err` — `scripts/lib/zot-telemetry-parse.sh:27`
          strips the **literal** ` zot_last_err=`. Wrong name ⇒ the spoof guard silently never fires.
    - [x] Do **not** emit `host` — the lib states `boot_id` (not `host`) discriminates old/new host,
          because `registry-host-replace` reuses the hostname.
- [x] **2.2** `/etc/cron.d/soleur-private-nic-guard` — every 5 min under
      `doppler run --project soleur-registry --config prd` (the `:241` shape), wrapped in **`flock`**.
- [x] **2.3** `runcmd` boot invocation — **after `:318`** (the token file `/etc/default/registry-doppler`
      at `:317-318`), **not** merely after the CLI install; source the env file first (`:390`
      precedent); suffix `|| true` (fail-open); take the **same `flock`** as the cron.
      *(Anywhere in `:306-316` has no token ⇒ `doppler run` resolves nothing ⇒ the emit dies silently.)*

## Phase 3 — L2: emit → human (`scripts/zot-restart-loop-alarm.sh`)

- [x] **3.1** **Independent absence probe** for `SOLEUR_PRIVATE_NIC`. The existing `PRODUCER_SILENT`
      (`:106-124`) keys only on `$MAIN` (`SOLEUR_ZOT_DISK`) — a dead NIC guard beside a live disk
      heartbeat reads **GREEN**. Reuse the control-marker → LOOKBACK ladder.
- [x] **3.2** Fire on `nic_ok=false` **scoped to the newest `boot_id`** (`zot_newest_boot` /
      `zot_scope_to_boot`) — **not** any-in-window. The window is 3h (`:63`); any-in-window pages on
      every successful self-heal.
- [x] **3.3** **Advisory branch** on `reboot_count>0` / `converged_by=reboot` (these emit
      `nic_ok=true` ⇒ the terminal alarm never fires ⇒ the race would self-heal silently forever).
      Lower severity, distinct from the terminal alarm.
- [x] **3.4** **Exit contract.** Early exits at `:106/:129/:155/:177/:197` terminate before any appended
      check (a zot isolation FATAL ⇒ `zot_restarts=-1` ⇒ `:155` ⇒ `exit 2` ⇒ NIC never read).
      Evaluate the NIC check **before** the zot early-exits, or restructure to carry both facts.
      **Do NOT add exit code 4** — `scheduled-zot-restart-loop.yml:220` maps non-0/1/3 to `'error'`.
      Sweep `case "$rc"` at `:103-109`. Define zot-FIRE vs NIC-FIRE precedence.
- [x] **3.5** **Auto-close branch** — add the NIC title to the GREEN close path (`:182-203`), else the
      issue goes stale and trains the operator to ignore `action-required`.
- [x] **3.6** `.github/workflows/scheduled-zot-restart-loop.yml` — deduped `action-required` branch
      mirroring `:136`/`:171`, with a **no-SSH** reproduce block.

## Phase 4 — Tests

- [x] **4.1** Create `apps/web-platform/infra/private-nic-guard.test.sh` (two layers, per
      `registry-boot-guard.test.sh:20-60`).
  - [x] **4.1.1** **Render step (required):** the guard body is a Terraform template (`$${…}` escaping,
        unrendered `${private_ip}`) — extracted bytes are **not** executable bash. Un-escape/render +
        PATH stubs (`ip`, `curl`, `reboot`, `mountpoint`, `docker`) + a fake counter FS.
        *(The cited precedent extracts only scalars — this is a materially bigger exercise.)*
  - [x] **4.1.2** Behavioral cases (**synthesized** fixtures): healthy ⇒ no mutation · `imds_rc≠0` ⇒ no
        reboot · `imds_nets=0` ⇒ no reboot · `uptime_s<600` ⇒ no reboot · corroborated+unexhausted ⇒
        counter-then-**one** reboot · counter exhausted ⇒ no reboot · store unmounted ⇒ `mount -a` +
        `docker restart`.
  - [x] **4.1.3** Structural: counter written **before** reboot · counter path is **`/var/lib/soleur/…`**
        (assert the **positive** path — "not `/var/lib/zot`" does not exclude tmpfs) · **literal cap 2** ·
        `flock` on **both** cron and boot · `|| true` on boot · boot invocation after `:318` ·
        `zot_last_err` trailing · the `doppler run --project soleur-registry --config prd` wrapper.
- [x] **4.2** Register in `.github/workflows/infra-validation.yml` as an explicit `- name:` / `run: bash`
      step (convention at `:167`–`:176`; `registry-boot-guard.test.sh` at `:224`; **no** glob discovery).
- [x] **4.3** Extend `scripts/zot-restart-loop-alarm.test.sh` for the NIC branches — **including** the
      "NIC silent while `SOLEUR_ZOT_DISK` flows ⇒ FIRE" regression and the zot-early-exit case.
      *(v1 edited the alarm but tested none of it.)*

## Phase 5 — ADR + learning

- [x] **5.1** Create `knowledge-base/engineering/architecture/decisions/ADR-113-dedicated-host-private-nic-boot-convergence.md`.
  - [x] Decision + the `hr-fresh-host-provisioning-reachable-from-terraform-apply` headline.
  - [x] **NORMATIVE BLOCKER** (required): the reboot primitive **MUST NOT** ship to a host whose storage
        unlock lives in `runcmd` without a reboot-safe equivalent (`crypttab`/keyscript); **git-data is
        excluded until then**. *(The ADR outlives the plan and the tracking issue — the constraint must
        live here.)*
  - [x] `status: accepted` for **registry**; **not** class-wide.
  - [x] Do **not** claim `hr-prod-host-config-change-immutable-redeploy` "blesses" self-reboot — it does
        not. Earn the authority on the bounding's own merits.
  - [x] **Re-verify the ordinal against `origin/main` before merge**; if renumbered, sweep
        `plans/` + `specs/` in the same edit (AC11 names it).
- [x] **5.2** `knowledge-base/engineering/architecture/diagrams/model.c4` — 2 description edits:
      `:396` (`zotRegistry -> betterstack` enumerates only `SOLEUR_ZOT_DISK`) and `:400`
      (`github -> betterstack` names only the restart-loop alarm). **Not** `:264` (that falsifies only
      if the deferred L3 lands). Then run `c4-code-syntax.test.ts` + `c4-render.test.ts` and regenerate
      `model.likec4.json` via `scripts/regenerate-c4-model.sh`.
- [x] **5.3** `knowledge-base/project/learnings/2026-07-07-immutable-redeploy.md` — point **Sharp edge 2**
      at the automated convergence + `SOLEUR_PRIVATE_NIC` (its manual "always verify after a `-replace`"
      is the operator-memory dependency this removes).

## Phase 6 — Deferred-item tracking issues (same PR)

> **CONSOLIDATED at `/work` into ONE tracker: #6438.** The `/work` follow-up-filing net-flow gate
> requires deferred-FEATURE follow-ups from the same PR to collapse into a single tracker with a
> checklist (only *discovered defects in a different subsystem* stay separate — none here). All
> three items below are one work-stream: extend private-NIC convergence beyond the registry, and
> add the off-host layer. Filing three would have been **net +3** against 0 closes.
> **Net-issue-flow: Closing 0 / Filing 1 / Net +1** — and #6415 itself closes once the post-merge
> replace (AC14) verifies, so steady-state is net 0.

- [x] **6.1** **L3 off-host probe.** Must carry: the web-host delivery site
      (`ignore_changes=[user_data]` ⇒ not cloud-init); the **arming blocker** (`ignore_changes=[paused]`
      at `:355` ⇒ the source flip is a **no-op**; either drop that attribute + reconcile the ADR-103
      manifest in the same PR, **or** arm via the Better Stack API — already called at
      `apply-web-platform-infra.yml:1803`); the **cadence mismatch** (`period=60/grace=30` needs a ping
      ≤90s vs a 60s cron floor + 2 round trips ⇒ flapping); `betterstack_paid_tier=false` ⇒
      **email-only, no escalation** (`variables.tf:301`).
- [x] **6.2** **Generalize to git-data + inngest** — blocked on a reboot-safe LUKS unlock.
- [x] **6.3** **Web hosts (`10.0.1.10/.11`)** — they share the race **and** the silent-failure property
      (`model.c4:380` GHCR atomic fallback ⇒ deploys keep working ⇒ identical 14-day shape). Needs the
      bake-and-extract path. Give it a **bounded** re-evaluation trigger, not "the next ADR-068 window".

## Phase 7 — Ship

- [ ] **7.1** Verify all pre-merge ACs (AC1–AC13), incl. **both** suites: `infra-validation.yml` **and**
      `scripts/test-all.sh`.
- [ ] **7.2** PR body uses **`Ref #6415`**, **not** `Closes` (ops-remediation: remediation completes only
      after the post-merge replace, and #6415 stays open for the deferred L3).
- [ ] **7.3** `/ship` renders `decision-challenges.md` into the PR body + files the `action-required`
      issue (UC-1 scope call, UC-2 issue metadata).
- [x] **7.4** ~~**Operator (CPO C2, not automatable from here)**~~ — **MIS-CLASSIFIED; DONE at `/work`.**
      "Not automatable from here" was false: this is three `gh issue edit` flags. Labelling it an
      operator step violated `hr-never-label-any-step-as-manual-without` +
      `hr-exhaust-all-automated-options-before`. **Applied:** #6415 → **Phase 4: Validate + Scale**,
      `priority/p2-medium` → `priority/p1-high`, dropped `type/chore`, added `observability`.
      The live label definitions confirm CPO's ruling exactly: `p2-medium` is defined as
      *"Important but not urgent, **workaround exists**"* — which #6400 falsified (the GHCR
      fallback was **also** degraded, which is why prod stuck at `0.213.2`); `p1-high` is
      *"Degraded functionality, **no workaround**"*. #6415 now matches #6400 (Phase 4 / p1-high),
      the P1 it root-causes.

## Phase 8 — Post-merge (AC14–AC17)

- [ ] **8.1** Fire `registry-host-replace` via the `apply-web-platform-infra.yml` dispatch
      (`apply_target=registry-host-replace`) — a `gh workflow run`, **not** SSH.
- [ ] **8.2** Within 10 min, SSH-free:
      `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30m --grep SOLEUR_PRIVATE_NIC --limit 20`
      ⇒ ≥1 event with `nic_ok=true`, `zot_store_mounted=true`.
- [ ] **8.3** **Record `converged_by`** — it is the empirical H1-vs-H2 verdict (`already` ⇒ no race this
      boot; `reboot` ⇒ the race is real and the guard healed it). Write it into ADR-113.
- [ ] **8.4** **Zero rows ⇒ do NOT read as "no signal"** (ambiguous across ≥6 causes). Run
      `bash scripts/zot-restart-loop-alarm.sh` — its control-marker → LOOKBACK → PRODUCER_SILENT ladder
      discriminates them.
- [ ] **8.5** **`nic_ok=false` ⇒ revert → merge → re-dispatch** (no in-place rollback on a ForceNew,
      no-SSH host). Name an owner for the first 30 min.
- [ ] **8.6** **Do NOT accept deploy-pipeline success as proof zot is reachable** — the GHCR fallback
      satisfies it with zot down (that *is* #6400). Assert `nic_ok=true` **plus** a zot-served pull.
