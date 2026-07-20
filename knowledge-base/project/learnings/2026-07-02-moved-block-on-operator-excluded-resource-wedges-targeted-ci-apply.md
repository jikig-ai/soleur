---
title: "A `moved` block on an operator-excluded resource red-lines every target-scoped CI apply — the fix is the cutover, not an allow-list edit"
date: 2026-07-02
category: workflow-patterns
tags: [terraform, moved-block, target-scoped-apply, ci, adr-068, sequencing, infra]
issue: 5887
---

# Learning: a `moved` migration on an operator-excluded resource wedges targeted CI applies

## Problem

A singleton→`for_each` `moved {}` migration (#5877, ADR-068 Phase 3) added four
`moved` blocks to `apps/web-platform/infra/placement-group.tf` but shipped without
its operator cutover apply. Every subsequent target-scoped CI run
(`apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`) went red with
`Error: Moved resource instances excluded by targeting` — Terraform requires every
pending `moved` source/target base address to be inside the `-target=` set on a
targeted plan, and these bases were deliberately in `OPERATOR_APPLIED_EXCLUSIONS`.

## The trap

The obvious fix — add the moved bases to the per-PR `-target=` allow-list — is
unsafe: `hcloud_server.web` carries `placement_group_id` + `for_each` (`server.tf`),
so targeting it in the unattended per-PR path forces a power-off reboot of the
running prod host. The `delete`-only, Cloudflare-scoped destroy-guard is blind to
that in-place reboot. The real root cause is operator-action-pending **sequencing**,
not a forgotten allow-list entry.

## The rule

A singleton→`for_each` `moved` migration on an operator-excluded resource red-lines
target-scoped CI applies until an operator maintenance-window full apply consumes the
pending moves; the fix is the cutover **with** the migration + a `moved`/`-target`
parity guard, **NOT** an allow-list edit. After the cutover, no pending moves remain
and the targeted CI plan self-heals with zero workflow change.

Authoritative record + full rationale (reboot evidence, blast radius across both
targeted workflows, the recurrence guard): **ADR-068 §Amendment (2026-07-02,
#5877/#5887)** and the `moved`/`-target` parity block in
`plugins/soleur/test/terraform-target-parity.test.ts` (`MOVED_OPERATOR_CONSUMED`).
Discoverable via `git grep 5887`.
