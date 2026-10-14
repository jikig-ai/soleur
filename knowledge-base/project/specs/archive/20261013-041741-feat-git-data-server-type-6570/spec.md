---
feature: git-data-server-type-6570
issue: 6570
pr: 6974
branch: feat-git-data-server-type-6570
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-07-27-git-data-server-type-off-arm-brainstorm.md
status: draft
date: 2026-07-27
---

# Spec — move `soleur-git-data` off the unorderable `cax11` ARM pin

## Problem Statement

`apps/web-platform/infra/git-data.tf:120` declares the git-data host on
`var.git_data_server_type`, defaulted to `cax11` (ARM64/Ampere). The entire Hetzner `cax` line is
orderable in **0 of 3** EU datacenters (live probe 2026-07-26T22:07Z: `nbg1-dc3`, `hel1-dc2`,
`fsn1-dc14` all `cax_orderable=0`). The host therefore cannot be born on its declared type, and
never has been — `/v1/servers` returns 5 hosts, none of them git-data.

ADR-068 Phase-3 concurrent serving is gated on a shared git-data store, so the whole active-active
chain sits behind a host that cannot come into existence. ADR-143:149 names #6570 as the owner of
this decision and deliberately left the pin unchanged.

The move is a **code change, not a var flip**: `cloud-init-git-data.yml:129` hardcodes the
`linux_arm64` Doppler CLI build, and git-data — unlike `zot-registry.tf` and `inngest-host.tf` —
has no arch-derivation local.

## Goals

- G1 — git-data is declared on a type that is orderable in all three EU DCs.
- G2 — the host's architecture is *derived* from its type pin, not hardcoded, so pin and binary
  download cannot drift apart.
- G3 — a nonexistent or unorderable type fails at **plan**, before `git-data-host-replace`'s
  destroy-first `-replace` can strand the fleet.
- G4 — the cost change is recorded in the expense ledger before the PR is marked ready.
- G5 — the voided `git/sshd are ARM-native` rationale is removed, not left standing as stale
  justification.

## Non-Goals

- **NG1 — birthing the host.** The birth is a separate gated `workflow_dispatch` with a live
  stock re-probe at dispatch time. Stock moves on an hours timescale; orderability at merge is
  not orderability at apply.
- **NG2 — ADR-068 Phase-3 GA, the coordinator, or LB weight changes.** `replicas=1` stays in
  force (ADR-143). This unblocks the *host*, not the flip.
- **NG3 — remediating the other grandfathered hosts** (web-1 `cx33`, `soleur-grok-dogfood`
  `cx33`, `soleur-registry` `cx23`). That is #6460.
- **NG4 — touching the LUKS passphrase resources.** `random_password.git_data_luks` and
  `doppler_secret.git_data_luks_key` stay out of scope so the existing
  `luks_passphrase_touched` backstop keeps holding.
- **NG5 — an account-cap raise.** The live limit is 10 servers with 5 running; the issue's "cap
  is 5" premise is false.
- **NG6 — the git-data heartbeat OR-masking fix (#6975).** Filed by this brainstorm. It is a
  probe-topology defect, not a server-type decision, and it gates the **birth** rather than this
  repin (with no git-data host, both probes currently fail and nothing is masked).
- **NG7 — `GIT_DATA_STORE_ENABLED`.** Verified absent from Doppler `soleur/prd`;
  `workspace-resolver.ts:57` gates on `=== "true"`. It must be flipped **only** via
  `git-data-cutover.sh`, which sits behind drain → delta-rsync → set-identity verify. A manual
  Doppler set would skip the write-freeze. Not touched here.

## Downstream Dependencies — merging this does NOT yield a usable git-data store

Recorded so no reviewer reads a merged repin as "git-data is available". Each verified open.

0. **SETTLED (2026-07-27) — keep the plaintext→LUKS cutover topology; do NOT birth onto LUKS
   directly.** Brainstorm **D10**. Born-on-LUKS was considered and rejected: the encryption
   outcome it argued for is *already guaranteed*, because every git-data write path is gated on
   `isGitDataStoreEnabled()` and `git-data-cutover.sh` `preconditions()` refuses to run unless the
   flag is OFF, setting it to `true` only as its final step after `repoint_luks_mount`. So user
   data can never reach the plaintext volume. Rejected on cost: ~12 files including the
   both-volumes-preserved destroy-guard (`git-data-host-replace-gate.sh`) and an ADR-068
   amendment. **The birth must therefore keep the flag OFF** — that is what makes the sequence
   safe, and it is a hard precondition of step 1, not an optimization.
1. **#6977 — build a birth route. There is none today.** *(Added at deepen; the hedge in the
   original item 1 — "verify that path rather than assume it" — was verified and came back
   negative.)* `git-data-host-replace` **cannot** birth an unborn host: its gate counts
   `server_replaced` as `actions ⊇ {delete, create}` and a first birth is `["create"]` only, and
   ≥6 never-provisioned dependencies blow the `out_of_scope == 0` allow-set. There is no
   `git-data-host-create` target. The only remaining route is an **untargeted** prod-wide
   `terraform apply` that runs neither the destroy-guard nor the stock preflight.
2. **Birth the host** via that new route, **with `GIT_DATA_STORE_ENABLED` OFF/absent** (per item 0).
3. **Deliver the minted transport keys to the running web container.** *(Added at deepen — was
   missing entirely.)* `git-data.tf` documents `GIT_TRANSPORT_/GIT_PROVISION_/GIT_REMOVE_SSH_PRIVATE_KEY`
   as "baked into the container env at start". The birth mints the `tls_private_key` resources
   (they are `user_data` dependencies) but their `doppler_secret` siblings are **dependents** and
   are **not** in the replace `-target` set — verified: that set is five `hcloud_*` addresses and no
   `doppler_secret`. So after a birth the host's `authorized_keys` holds public halves whose private
   halves live only in tfstate, and `soleur-web.service` must be **restarted** to pick them up once
   they land. This is a precondition of the cutover's `bulk_rsync`, not something
   `flip_flag_and_reload`'s late restart covers.
   **Coupled risk:** `removeGitDataRepo` is deliberately NOT gated on `isGitDataStoreEnabled()` — it
   gates on `GIT_REMOVE_SSH_PRIVATE_KEY` being present. That key has no dependency on
   `hcloud_server.git_data`, so an untargeted apply can land it in `prd` even if the server CREATE
   fails; every account deletion then throws in `resolveGitDataSshHost()` and files a false
   **"Art. 17 erasure failed"** Sentry event for a store that does not exist.
4. **Fix `git-data-cutover.sh`'s stale web roster.** *(Added at deepen.)* `WEB_HOSTS` defaults to
   `10.0.1.10` on the comment *"web-2 (10.0.1.11) retired #6538; single-host roster"* — falsified by
   web-2's 2026-07-24 re-add at that same address (ADR-143), and `git-data-cutover.yml` does **not**
   override it. If web-2 is alive at cutover: `acquire_freeze()` drains only web-1 so web-2 writes
   straddle the "authoritative" freeze `verify_set_identity` assumes is quiesced;
   `flip_flag_and_reload()` writes a **global** Doppler flag but restarts only web-1, leaving the two
   hosts reading from **different git-data sources**; `rollback()` and `release_freeze()` inherit the
   same blind spot. Every log line in those functions says "both hosts" — the tell that the constant
   drifted out from under the code. Harmless today (web-2 is serving-weight 0), live by the time
   this chain completes.
5. **#6975** — heartbeat masking; precondition of the birth. **#6548** — `git_data_prd` heartbeat
   never unpaused and absent from live Better Stack; same gating status as #6975.
6. **#6680** — `git-data-cutover.yml` has no tunnel ingress for `10.0.1.20`; the CF Tunnel SSH
   bridge reaches only web-1 and the whole cutover runs over it (`preconditions()` does
   `gd_ssh "$GIT_DATA_HOST" 'true'`). **Host born is not cutover-runnable.** An unsolved design
   question, not a mechanical fix — and per item 0 it is now unconditionally on the critical
   path, since the cutover is the sanctioned mechanism that flips the flag.
7. **Cutover + flip** via `git-data-cutover.sh`. On a never-enabled store this runs against an
   **empty** source: the rsync copies nothing and the set-identity verify passes trivially, so
   the write-freeze is a formality rather than a data-risk window. Its real work is
   `repoint_luks_mount` + the coordinated two-host flag flip.

Even all of the above does not give web-2 traffic: `lb-weight-gate.sh` Condition B additionally
needs a `GIT_DATA_LUKS` soak marker, and condition (3) needs web-2 `/workspaces` LUKS-backed
(#6931).

**Separately, at the read-source flip (PR C), not at the birth:** git-data population is lazy and
turn-driven (`replicateToGitData` force-pushes at session end; no web-1 → git-data rsync exists,
and no backfill exists in code). ADR-068 §(d) concedes a fresh GitHub clone "can be strictly
behind the user's latest tip", so an idle workspace never pushed to git-data may read stale once
`fetchFromGitData` serves reads. Whether PR C needs a one-time backfill is unresolved —
brainstorm Q2.

## Functional Requirements

- **FR1** — `var.git_data_server_type` default changes `cax11` → `cpx22`. Its `description` is
  rewritten to state the shape (2 vCPU x86 / 4 GB), that arch is DERIVED from it, and that
  `cpx22` is a stock-forced choice rather than a sizing decision.
- **FR2** — add `local.git_data_arch = startswith(var.git_data_server_type, "cax") ? "arm64" : "amd64"`
  in `git-data.tf`, mirroring `local.registry_arch` (`zot-registry.tf:58`) and
  `local.inngest_arch` (`inngest-host.tf:62`).
- **FR3** — add `local.git_data_doppler_sha256` selecting the per-arch checksum off
  `local.git_data_arch`. Reuse the pinned-version pair already at `inngest-host.tf:66` verbatim;
  do not re-derive.
- **FR4** — `cloud-init-git-data.yml` selects the Doppler CLI download URL and its `sha256sum -c`
  operand from the templated arch/checksum instead of the hardcoded `linux_arm64` literal. This is
  the only arch-coupled artifact in that file.
- **FR5** — add a `validation` block on `var.git_data_server_type` rejecting a prefix outside
  `^(cax|cpx|cx|ccx)`, mirroring `inngest_server_type`'s guard.
- **FR6** — add `data "hcloud_server_type" "git_data"` so an unknown type fails at plan, mirroring
  `data.hcloud_server_type.registry` (`zot-registry.tf:134`, the #6508 fix for #6288's
  destroy-then-fail disaster).
- **FR7** — replace the `# cax11 = ARM64 (Ampere); git/sshd are ARM-native` comment at
  `git-data.tf:120` with the stock-forced rationale plus the live measurement and its date.
- **FR8** — update `knowledge-base/operations/expenses.md` row 19: `Hetzner CAX11 (git-data)` →
  `CPX22`, amount `4.10` → `~21.05` USD (EUR 19.49 × ~1.08 FX). Status stays
  `approved-not-billing` (host still unborn). Record the +€13.50/mo delta and the
  identical-net-vs-gross caveat the web-2 row carries.
- **FR9** — record the decision as an **ADR-143 addendum** (not a new ADR), per ADR-143:149 and
  the #6966 precedent.

## Technical Requirements

- **TR1** — `terraform validate` + `terraform plan` must pass with zero diff for the git-data
  *resources* beyond the type/user_data change. The host does not exist, so the plan shows a
  CREATE that is **not** applied by this PR (NG1).
- **TR2** — the change must not alter `hcloud_volume.git_data`, `hcloud_volume.git_data_luks`, or
  the LUKS passphrase resources. `git-data-host-replace`'s `luks_passphrase_touched` backstop
  must still pass.
- **TR3** — `cpx22` is x86/amd64, so `local.git_data_arch` resolves to `amd64` and the amd64
  Doppler build is selected. Verify the checksum matches the amd64 artifact for the pinned
  Doppler version.
- **TR4** — no new Doppler secret, no new sub-processor, `hel1` unchanged (EU residency, CLO T-1).
- **TR5** — `tests/scripts/lib/stock-preflight-gate.sh` is already sourced by
  `git-data-host-replace`; confirm the gate reads the new type and that no test encodes today's
  availability (`cq-test-fixtures-synthesized-only`).
- **TR6 — validation gates that fail silently and green if skipped.**
  - `scripts/test-all.sh` does **not** cover `apps/web-platform/infra/`. The authoritative infra
    gate is `bash apps/web-platform/infra/run-registered-suites.sh`, which derives its suite list
    from `.github/workflows/infra-validation.yml` and reports unregistered orphans. It must be
    run (~25 min).
  - Nothing auto-discovers `tests/scripts/` — any new suite needs an explicit `run_suite` line in
    `scripts/test-all.sh` inside the `want_scripts` block.
  - Any new dispatch job sharing `group: web-1-swap` must be enrolled in **both** the allow-list
    and the total-count assertion in
    `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` — enrolling in one half makes
    the number stop meaning what it says.
- **TR7 — rebase hygiene.** `variables.tf` and `apply-web-platform-infra.yml` are high-traffic
  files. No pushed branch currently conflicts (`origin/feat-one-shot-6969-web-host-replace`
  changes only two planning docs, verified 2026-07-27), but a parallel session holds unpushed
  edits to them. Fetch `origin/main` immediately before editing either file.
- **TR8 — ADR numbering is not consumed.** D8 records an ADR-143 **addendum**, allocating no new
  number. If that is ever revisited into a standalone ADR, re-derive the next free number
  (`ls knowledge-base/engineering/architecture/decisions | grep -oE 'ADR-[0-9]+' | sort -t- -k2 -n | tail -1`
  — highest on `main` was **ADR-147** at spec time).

## Acceptance Criteria

- **AC1** — `grep git_data_server_type apps/web-platform/infra/variables.tf` shows `cpx22`.
- **AC2** — no `linux_arm64` literal remains in `cloud-init-git-data.yml`.
- **AC3** — `local.git_data_arch` exists and is consumed by the cloud-init template.
- **AC4** — a nonsense type (`cx99`) fails at `terraform plan`, not after a destroy.
- **AC5** — expense ledger row 19 reads CPX22 with the corrected amount and a `verify_by` marker.
- **AC6** — ADR-143 carries a dated addendum recording D1–D9 and the falsified account-cap premise.
- **AC7** — the brainstorm's Premise Corrections table is reflected in the PR body so the stale
  "cap is 5 / slot freed by retiring web-2" framing is not re-imported downstream.

## Risks

| Risk | Mitigation |
|---|---|
| `cpx22` leaves the orderable set before the birth dispatch | The birth re-probes stock at dispatch (`stock-preflight-gate.sh`). `cpx*`/`ccx*` have been stably orderable across both recorded probes. |
| The amd64 Doppler checksum is wrong → host boots without LUKS passphrase access | Reuse the exact pair from `inngest-host.tf:66` (same pinned version, already proven on a live host). `sha256sum -c` fails closed at boot. |
| Reviewer reads this as authorizing the birth | NG1 stated explicitly in spec + PR body; D9 in the brainstorm. |
| Stale "cap is 5" resurfaces in a later artifact | AC7 puts the correction in the PR body; #6460 owns recording limits as facts with a decay date. |
