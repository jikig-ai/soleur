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

1. **Birth the host** — gated `workflow_dispatch`. `git-data-host-replace` plans a plain CREATE
   against a host absent from state; **verify that path rather than assume it**, since the stock
   preflight would have aborted on `cax11` and this shape has never actually run.
2. **#6975** — heartbeat masking; precondition of the birth.
3. **#6680** — `git-data-cutover.yml` has no tunnel ingress for `10.0.1.20`; the CF Tunnel SSH
   bridge reaches only web-1 and the whole cutover runs over it. **Host born is not
   cutover-runnable.** An unsolved design question, not a mechanical fix.
4. **Cutover + flip** via `git-data-cutover.sh` (write-freeze + drain).

Even all four does not give web-2 traffic: `lb-weight-gate.sh` Condition B additionally needs a
`GIT_DATA_LUKS` soak marker, and condition (3) needs web-2 `/workspaces` LUKS-backed (#6931).

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
