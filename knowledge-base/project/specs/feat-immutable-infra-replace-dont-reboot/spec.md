---
feature: feat-immutable-infra-replace-dont-reboot
issue: 9750
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-08-immutable-infra-replace-dont-reboot-brainstorm.md
---

# Spec: Encode "replace, don't reboot" in shipped skills, agents and gates

## Problem Statement

The repo's own rule `hr-prod-host-config-change-immutable-redeploy` covers config changes to a running prod host, but it never reaches a Soleur user. The shipped infra agents do not state a replace-over-reboot default. Plan, review and deepen-plan detect downtime cost but not "reboot as the recovery or proof step". The web-2 work (#9372) showed the result: a soft reboot stranded a host dark, and "survives a reboot" had become an acceptance criterion.

## Goals

- Make replace-over-reboot the advisory default in the terraform-architect and platform-strategist agents.
- Have plan, review and deepen-plan flag "reboot the host" as a recovery or proof step, or "survives a reboot" as an acceptance criterion, with a justification slot.
- State the evidence rule: a host-property proof should be satisfiable by a fresh instance, with stateful data on a persistent volume.

## Non-Goals

- A new AGENTS rule (rule budget; the existing hard rule stays unchanged).
- A blocking gate, a hook, or a deterministic grep check (Approach B, deferred).
- Anything web-2-specific (#9372, ADR-263 addendum, #6931 grader).
- Changes to any skill or agent `description:` line.

## Functional Requirements

- **FR1** `terraform-architect.md` gains a "Replace, don't reboot" subsection: the default, the preconditions (state on a persistent volume, target stock verified first, dependents `-target`ed), and the legitimate reboot cases (fresh-host NIC bring-up, drained cutover, a kernel update the founder chose).
- **FR2** `platform-strategist.md` gains a 2-3 line strategy-layer statement of the same default.
- **FR3** `plan/references/plan-sharp-edges.md` gains one bullet covering reboot-as-recovery, "survives a reboot" as an acceptance criterion, and the fresh-instance and persistent-volume evidence rule. Plan §2.8 points at it.
- **FR4** The `review/SKILL.md` downtime bullet and the `deepen-plan/SKILL.md` infra reboot/replace class each gain one clause, keyed on intent (a reboot, a service restart or an SSH fix used as recovery or proof) rather than on `hcloud_*` names.

## Technical Requirements

- **TR1** Wording is provider-agnostic. Hetzner and `-replace` appear only as examples.
- **TR2** Advisory only: the agent states the trade-off and the founder decides. Nothing blocks.
- **TR3** No `description:` edits, so no cost against the skill-description word budget.
- **TR4** Cite anchors by content, not line number (`cq-cite-content-anchor-not-line-number`).
- **TR5** Evidence language cites measured state, not intent (CLO watch-item).
