# Brainstorm: Encode "replace, don't reboot" in shipped skills, agents and gates

**Date:** 2026-10-08 · **Issue:** #9750 · **Branch:** feat-immutable-infra-replace-dont-reboot · **Draft PR:** #9754 · **Lane:** cross-domain

> **Superseded at plan time (2026-10-08):** the `deepen-plan` clause, the `plan/SKILL.md` pointer and the `restart` trigger below were cut or changed in the plan (byte ceilings; `deepen-plan` 4.55 is a HALT gate). The plan's Research Reconciliation and Review Amendments sections are authoritative.

## What We're Building

Make "replace, don't reboot" (immutable infrastructure) the advisory default in the surfaces a Soleur user receives, not only in this repo's AGENTS rules. All edits are body text. No description lines change, so there is no skill-description budget cost.

1. `plugins/soleur/agents/engineering/infra/terraform-architect.md`: a short "Replace, don't reboot" subsection with the default, the preconditions, and when a reboot is legitimate.
2. `plugins/soleur/agents/engineering/infra/platform-strategist.md`: the same principle in 2-3 lines at the strategy layer, before any HCL is generated.
3. `plugins/soleur/skills/plan/references/plan-sharp-edges.md`: one bullet covering three things. (a) "reboot the host" as a recovery step. (b) "survives a reboot" as an acceptance criterion. (c) the evidence rule: a graded host-property proof should be satisfiable by a fresh instance, with stateful data on a persistent volume. Plan §2.8 points at it.
4. `plugins/soleur/skills/review/SKILL.md` (~L1255, the downtime bullet) and `plugins/soleur/skills/deepen-plan/SKILL.md` (~L354, the infra reboot/replace class): one clause each, keyed on intent (reboot, `systemctl restart` or an SSH fix used as recovery or proof), not on `hcloud_*` names.

## Why This Approach

- `hr-prod-host-config-change-immutable-redeploy` (AGENTS.rules.md L36) already covers config changes to a running prod host. It is repo-internal and never reaches a Soleur user.
- Neither infra agent states the replace-over-reboot default. Review L1255 and deepen-plan L354 detect downtime cost, not the direction of the fix.
- `cq-agents-md-tier-gate` routes domain-scoped IaC content to the owning skill or agent. The rule budget is tight (ADR-151: the corpus loads every session).
- Reboot is not forbidden. A fresh host may need a soft reboot for its NIC (learning 2026-07-07), and a drained reboot can sit inside a cutover (2026-07-02). The guidance is advisory, with a justification slot, so it cannot become boilerplate-paste friction.

## Key Decisions

| Decision | Choice |
|---|---|
| Mechanism | Approach A: advisory text only. Rejected B (deterministic grep check: false-positive tuning, new code) and C (new hard rule: budget, repo-only reach, legit reboots). |
| New AGENTS rule | None |
| Gate strength | Advisory in agents, plan and review. Nothing blocks. |
| Generalization | Provider-agnostic wording ("unit of recovery is a fresh instance from declared config"). Hetzner and `-replace` appear as examples only. |
| Preconditions carried in the guidance | State lives on a persistent volume. Target capacity and stock are verified first (`-replace` destroys before it creates). Dependents are `-target`ed. |
| Productize candidate | None |

## User-Brand Impact

- **Artifact:** the terraform-architect and platform-strategist agents, plan sharp-edges, and the review and deepen-plan infra bullets.
- **Vector:** a default that over-claims "replace" without the persistent-volume and stock preconditions can strand a user's fleet with no rollback. A default that is too loud trains agents and users to paste boilerplate justifications.
- **Threshold:** `single-user incident`

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

No new rule. Place the text in the agents, the plan sharp-edges file and the review/deepen-plan bullets. Key the triggers on intent, not on provider resource names. Main risks: false positives on legitimate reboots, and over-claiming replace.

### Product (CPO)

The gap is real and the benefit lands on solo founders, who have no second reviewer. Ship the advisory layer only. A blocking gate would punish a single VPS where a reboot is fine. Out of scope: hook, blocking gate, new skills.

### Legal (CLO)

No legal impact for a guidance-only change. Watch-items if later work performs real replacements: new LUKS-header escrow and secret scope per replaced host, the open Art. 32(1)(c) restore gap (#7992), and destroying superseded snapshots (#8734 class). Evidence rules must cite measured state, not intent.

## Open Questions

- Should the generic "reboot as recovery or proof" clause also point to the existing reboot-aware destroy-guard (learning 2026-07-03), or stay independent of it?
- Does the plan template need a visible prompt, or is the sharp-edges bullet enough? Plan time decides.
- Whether a normative ADR is warranted (CTO: only if the default goes beyond ADR-145). Deferred to plan.
- (out of scope) The deterministic plan-time check (Approach B). Revisit if advisory text proves ignored in practice.
- (out of scope) Anything web-2-specific (#9372, ADR-263 addendum, #6931 grader).
