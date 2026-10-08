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
- Have the plan skill and the review skill flag "reboot the host" as a recovery or proof step, or "survives a reboot" as an acceptance criterion, with a justification slot.
- State the evidence rule: a host-property proof should be satisfiable by a fresh instance, with stateful data on a persistent volume.

## Non-Goals

- A new AGENTS rule (rule budget; the existing hard rule stays unchanged).
- A blocking gate, a hook, or a deterministic grep check (Approach B, deferred).
- Anything web-2-specific (#9372, ADR-263 addendum, #6931 grader).
- Changes to any skill or agent `description:` line.
- A `deepen-plan` Phase 4.55 change, a `plan/SKILL.md` pointer to the new bullet, or a `plan-review` standing check (byte ceilings and operator decision; see FR3, FR4).
- A deploy-time lens (deferred to #9764).

## Functional Requirements

- **FR1** `terraform-architect.md` gains a `## Replace, Don't Reboot` section: the default, host-config drift versus Terraform state drift, the preconditions (declared config and state on a persistent volume; capacity re-probed at apply time with no rollback after destroy; drain-gated path for serving hosts), and four named legitimate reboots (fresh-host NIC bring-up, a kernel update the user chose, a drained cutover reboot, a stateless single host). It is the canonical statement; the other surfaces are shorter.
- **FR2** `platform-strategist.md` gains one Reproducibility First bullet pointing at terraform-architect for the preconditions.
- **FR3** `plan/references/plan-sharp-edges.md` gains one bullet (about 850 B, trigger phrase in the lead-in) covering reboot-as-recovery, "survives a reboot" as an acceptance criterion, and the fresh-instance and persistent-volume evidence rule. Step 6.5 already loads the whole catalogue, so no pointer is added to `plan/SKILL.md`.
- **FR4** The `review/SKILL.md` downtime bullet gains a trigger extension (a plan or runbook whose recovery or proof step is a host reboot) and one in-quote clause for the spawned reviewers, under 400 B total (1404 B ceiling headroom). The `deepen-plan` Phase 4.55 clause is cut: 103 B of headroom and 4.55 is a HALT gate.
- **FR5** `plan/SKILL.md` §2.8 `### Apply path` is rewritten byte-neutrally so `-replace` is the default for a running host with state on a persistent volume and the bootstrap script is the exception (operator decision 2026-10-08; the file has 4 B of headroom).

## Technical Requirements

- **TR1** Wording is provider-agnostic. Hetzner and `-replace` appear only as examples.
- **TR2** Advisory only: the agent states the trade-off and the founder decides. Nothing blocks.
- **TR3** No `description:` edits, so no cost against the skill-description word budget.
- **TR4** Cite anchors by content, not line number (`cq-cite-content-anchor-not-line-number`).
- **TR5** Evidence language cites measured state, not intent (CLO watch-item).
