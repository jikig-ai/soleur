---
title: "Adding a cron-egress ASSERT-FAILED sentinel requires a runbook row; and editing apps/web-platform/infra/** fires the infra apply (path-glob, not *.tf)"
date: 2026-07-11
category: best-practices
module: apps/web-platform/infra
tags: [nftables, cron-egress, drift-guard, terraform, apply-workflow, inngest, "6178"]
pr: 6349
---

# Learning: cron-egress sentinel↔runbook coupling + infra path-glob fires the apply

## Problem

Two non-obvious couplings surfaced while adding a single nftables egress accept rule
(`10.0.1.40 tcp dport 8288 accept`, the dedicated Inngest host for the #6178 / ADR-100
cutover) to `apps/web-platform/infra/cron-egress-nftables.sh`:

1. **A new `ASSERT-FAILED:` sentinel in `cron-egress-postapply-assert.sh` breaks the suite
   until it is documented in the runbook.** The plan prescribed adding a runtime sentinel
   (`... || { echo 'ASSERT-FAILED: dedicated-inngest-8288-accept'; exit 1; }`) but did not
   anticipate that `cron-egress-firewall.test.sh` carries a **runbook-parity drift-guard**
   (lines ~617-639): it extracts every `ASSERT-FAILED: [a-z0-9-]+` name from the assertion
   block and requires each to appear in
   `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`. First test run
   failed **196 passed / 1 failed** with `FAIL: sentinel name(s) absent from
   cron-egress-blocked.md (runbook drift): dedicated-inngest-8288-accept`.

2. **The delivery premise "merging does not fire the apply because it is not a `.tf` file"
   is false.** `apply-web-platform-infra.yml` triggers on the **path-glob**
   `apps/web-platform/infra/**` (`:69-70`), NOT `*.tf`. `terraform_data.cron_egress_firewall`
   is in the merge-triggered `-target` set (`:593`) and folds the loader into its `config_hash`
   (`server.tf:1074-1088`), so editing the loader re-provisions **web-1** and restarts its
   **live** firewall on merge (gap-free; `hcloud_server` is NOT recreated).

## Solution

1. When adding an `ASSERT-FAILED: <name>` sentinel to `cron-egress-postapply-assert.sh`, add a
   matching row to `cron-egress-blocked.md`'s sentinel table **in the same change**. The name
   is matched by `grep -qF` (substring), so it must appear verbatim. This raised
   `SENTINEL_COUNT` 17→18 (floor `>=15` still holds) and turned the suite green (197/0).
2. Treat any edit under `apps/web-platform/infra/**` as apply-triggering. For an additive,
   inert, gap-free change this is safe-to-merge (the loader resolves allowlist sets before the
   atomic `nft -f -` flush+add, and `die`s before flush on resolve failure — no egress gap),
   but it is **not** a no-op on running hosts: it restarts web-1's production egress firewall.
   Record the corrected model in `decision-challenges.md` so `ship` surfaces it to the operator.

## Key Insight

The cron-egress test suite self-guards against sentinel/runbook drift — a new runtime
assertion is only "done" once its operator-facing runbook row exists. And in this repo the
infra apply is gated on a **path-glob**, not a file extension: a bundled `.sh` host script is
as apply-triggering as a `.tf` file. Verify the workflow's `paths:` and `-target` set, never
assume `*.tf` is the trigger.

## Session Errors

- **iac-routing hook false-positive (plan phase)** — the PreToolUse `iac-routing` hook blocked
  a plan edit containing `systemctl restart` in prose. Recovery: added the
  `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out with justification (the prose
  describes the existing Terraform-managed `remote-exec`, not a new manual step). Prevention:
  expected hook behavior; the opt-out is the sanctioned path when the trigger word is
  descriptive. One-off.
- **firewall.test.sh 196/1 on first run** — new sentinel undocumented in the runbook.
  Recovery: added the runbook row. Prevention: this learning (couple sentinel + runbook row).
- **Test batch timeout** — running firewall + enforce-probe + ci-deploy + observability in one
  2-minute foreground command timed out (ci-deploy/observability do heavy docker/registry mock
  setup). Recovery: ran ci-deploy + observability in the background. Prevention: run the heavy
  infra suites (`ci-deploy.test.sh`, `soleur-host-bootstrap-observability.test.sh`)
  individually with a generous timeout or backgrounded, not batched under a short foreground
  limit.
- **Task premise "apply must NOT fire on merge" was false** — corrected against the repo at
  deepen-plan (path-glob trigger). Prevention: this learning. Not a session mistake; a
  reusable fact now captured.
