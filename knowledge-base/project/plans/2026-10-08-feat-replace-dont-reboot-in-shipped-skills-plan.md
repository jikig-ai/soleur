---
title: "feat: encode replace-don't-reboot (immutable infrastructure) in skills, agents and gates"
type: feat
date: 2026-10-08
slug: replace-dont-reboot-in-shipped-skills
branch: feat-immutable-infra-replace-dont-reboot
issue: 9750
closes: 9750
priority: p3
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

## Overview

Ship the replace-over-reboot default in the plugin surfaces a Soleur user receives: the two infra agents, the plan skill's IaC "Apply path" default, the plan sharp-edges catalogue (applied to every plan at Step 6.5), and the review downtime lens. The change is advisory body text. It adds no AGENTS rule, no hook, no blocking gate and no `description:` edit (brainstorm Approach A, 2026-10-08).

Brainstorm: `knowledge-base/project/brainstorms/2026-10-08-immutable-infra-replace-dont-reboot-brainstorm.md`. Spec: `knowledge-base/project/specs/feat-immutable-infra-replace-dont-reboot/spec.md`.

## Research Insights

**Premise Validation.** Checked in this worktree: #9750 is OPEN; the cited parent #9372 is OPEN and Ref-only. `hr-prod-host-config-change-immutable-redeploy` exists in `AGENTS.rules.md` and covers config changes to a running prod host, repo-internal only. Neither infra agent states replace-over-reboot as a default. Review's downtime bullet and `deepen-plan` Phase 4.55 detect reboot/replace as a change's *effect* and require a zero-downtime evaluation; neither addresses a reboot used as the *recovery or proof step* of a plan. No ADR rejects the mechanism (ADR-145, ADR-143, ADR-154 are compatible and set the preconditions below). Plan review (2026-10-08) found two more facts: `plan/SKILL.md` §2.8 "Apply path" makes an idempotent bootstrap script the default for existing infra, contradicting the hard rule; and the review downtime bullet fires only on a diff touching infra paths, migrations or deploy restructures, so a plan-only or runbook-only PR never loads it. The cursor and grok agent files are stubs that point at the canonical agent file, and `agents.manifest.json` carries only id, path, name, description and model, so body edits need no regeneration.

**Property List.**

1. A user consulting the infra agents is told, up front, that the unit of change and of recovery for a running host is a fresh instance from declared config.
2. A plan that names a reboot as its recovery step, or "survives a reboot" as an acceptance criterion, is questioned at plan time, and the plan skill's own IaC default agrees with that.
3. A review of a PR that changes such a plan or runbook surfaces it as an advisory finding.
4. A graded host-property proof should be satisfiable by a fresh instance, with stateful data on a persistent volume.
5. Legitimate reboots (fresh-host NIC bring-up, a kernel update the user chose, a drained cutover reboot, a stateless single host) are not punished.

**Cut List.**

- New AGENTS rule → buys P1-P3 only for this repo, none for users; the existing hard rule already covers the repo (CTO, CPO, learnings agree).
- Deterministic grep check / hook (Approach B) → P2 is bought by the sharp-edges verification pass; false-positive tuning cost; deferred in the brainstorm.
- `deepen-plan` Phase 4.55 clause (spec FR4, second half) → `deepen-plan/SKILL.md` is 79897 B against a 80000 B ceiling (`plugins/soleur/test/skill-body-budget.json`), and 4.55 is a HALT gate, so adding "reboot as recovery step" to its trigger would make the advisory default blocking, contradicting TR2.
- Plan §2.8 *pointer* to the sharp-edges bullet → Step 6.5 already loads the whole catalogue. (The §2.8 *Apply path default* is a different edit and is in scope: Phase 2.)
- `plan-review` standing-check line → operator decision 2026-10-08: skip; Step 6.5 covers plan authoring and the review trigger covers PRs.
- Deploy-time lens → deferred to #9764 (advisory only).
- An eval-harness case for the new text (CTO) → not asked; revisit if the advisory text proves ignored in practice.
- New ADR → advisory guidance under existing decisions, not a new architectural decision.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| FR3: "Plan §2.8 points at [the sharp-edges bullet]" | `plan/SKILL.md` has 4 B of ceiling headroom; Step 6.5 already applies the whole catalogue | Drop the pointer; update spec |
| FR4: review bullet AND `deepen-plan` clause | `deepen-plan` has 103 B headroom and 4.55 is a HALT gate | Review clause only; update spec |
| Spec silent on plan §2.8 | §2.8 Apply path defaults to a bootstrap script and allows replace only if the host can't be patched in place, contradicting the new default | Byte-neutral rewrite of the Apply path line (operator decision 2026-10-08); new FR5 |
| Review lens "fires on a plan or runbook" | The bullet fires only on a diff touching `apps/*/infra/**`, a migration or a deploy restructure | Extend the trigger and put the clause inside the quoted reviewer instruction |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "The infra agents (terraform-architect, platform-strategist) and the plan template: default to replace over in-place change or reboot, and say so when a plan proposes a reboot." [issue #9750] | Phase 1 (both agents), Phase 2 (plan skill Apply path default), Phase 3a (sharp-edges bullet) | mapped |
| 2 | "Review and deploy gates: flag a plan or runbook whose recovery or proof step is \"reboot the host\"." [issue #9750] | Phase 3b (review bullet). Deploy gate: descoped to #9764 | mapped (deploy side: descoped — justification: no deploy-skill lens exists to extend, and a new one is the blocking gate the brainstorm rejected; tracked in #9764) |
| 3 | "Evidence rules: a graded proof of a host property should be satisfiable by a fresh instance, with stateful data on a persistent volume." [issue #9750] | Phase 1 and Phase 3a texts | mapped |
| 4 | "Decide whether this is one rule, a skill section, or a plan-time check, and keep it small (the AGENTS rule budget applies)." [issue #9750] | Decision recorded: skill/agent sections plus a plan-time catalogue bullet; no AGENTS rule | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| terraform-architect section | "default to replace over in-place change or reboot" | asked |
| platform-strategist bullet | "default to replace over in-place change or reboot" | asked |
| plan skill Apply path default | "the plan template: default to replace over in-place change or reboot" | asked |
| plan-sharp-edges bullet | "say so when a plan proposes a reboot" | asked |
| review downtime clause and trigger extension | "flag a plan or runbook whose recovery or proof step is \"reboot the host\"" | asked |
| Persistent-volume precondition | "stateful data on a persistent volume" | asked |
| Capacity re-probe, no-rollback warning, drain-gated path, declared-config precondition | — | inferred — justification: single-user-incident threshold; the existing hard rule records that replace destroys before it creates with no rollback, so a default that omitted these could strand a fleet |
| Legitimate-reboot carve-out (four cases) | — | inferred — justification: without it the default contradicts the existing hard rule's own note that a fresh host may need a reboot for its NIC |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur/agents/engineering/infra/`, `plugins/soleur/skills/{plan,review}/`
- Planned files: 5 plugin edits (+ spec, tasks) | Estimated changed lines: ~45
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Implementation Phases

### Phase 1 — Infra agents

**`terraform-architect.md`.** Insert a `## Replace, Don't Reboot` section between `## Review Protocol` and `## State Management Advisory` (after the line "For each finding, include the file and resource reference…"). Content (no plan or runbook review bullet: this agent writes and reviews `.tf`, the review lens lives in Phase 3):

> For a running host, the unit of change and of recovery is a fresh instance built from declared config (cloud-init or image, applied through the IaC tool's replace: Terraform `-replace`, Pulumi replace, CloudFormation replacement). It is not an in-place edit and not a reboot, and a reboot is not proof of a host property. This is about host-config drift (the running host differs from its declared config), not Terraform state drift. Advisory: state the trade-off and let the user decide.
>
> Preconditions before recommending a replace:
>
> - The host has declared config (otherwise replace loses it: declare it first) and its state lives on a persistent volume or managed store.
> - Replace destroys before it creates, with no rollback. Re-probe target capacity at apply time (a dated "available" reading is not a reservation; no stock means do not replace) and include dependent attachments (network, volume, firewall) in the `-target` scope.
> - A serving or stateful host needs a drain-gated, volume-preserving path, one host at a time; the zero-downtime evaluation still applies.
>
> A reboot is fine when named: first-boot NIC bring-up on a fresh host, a kernel update the user chose, a drained reboot inside a cutover, or a stateless single host with no declared config. Cite measured boot-time safety (unlock, mount gates), not intent.

**`platform-strategist.md`.** In `### 1. Reproducibility First`, add one bullet after the "Always IaC for configuration" bullet:

> - **Replace, don't reboot** for a running host: recovery and proof of a host property go through a fresh instance from declared config, with state on a persistent volume (the persistent-volume bullet under Cost-Aware Defaults). A reboot or in-place edit is the exception and must say why; see `soleur:engineering:infra:terraform-architect` for the preconditions and the named cases.

### Phase 2 — Plan skill IaC default (`plan/SKILL.md` §2.8)

Rewrite the `### Apply path` bullet (anchor: the text "`### Apply path` — one of:") so replace is the default and the bootstrap script the exception. Exact new text:

> - `### Apply path` — one of: (a) cloud-init-only (not yet provisioned), (b) taint + `terraform apply -replace` (default for a running host with state on a persistent volume; verify capacity first), (c) cloud-init + idempotent bootstrap script (only when a replace is not viable). State the chosen path and the expected downtime/blast-radius.

Byte budget: `plan/SKILL.md` is 119996 B against 120000 B. The old line is replaced with a line measured at +8 B before the trim; shortening "(resource not yet provisioned)" to "(not yet provisioned)" brings it to -1 B net. The ratchet lint (AC5) proves it; if it reds, trim an equal number of bytes elsewhere in that line, never raise the ceiling. No other file reads this wording (grep, 2026-10-08).

### Phase 3 — Plan-time check and review lens

**3a. `plan-sharp-edges.md`.** Append one bullet (about 850 B, trigger phrase in the lead-in):

> - **A plan that names "reboot the host" as its recovery or proof step, or "survives a reboot" as an acceptance criterion, has chosen the wrong unit of recovery.** A fresh instance built from declared config is the recovery path, and a host-property proof (volume unlocked and mounted, service up at boot, NIC converged) must be satisfiable by that instance with stateful data on a persistent volume. Ask whether a replace can do the step. If yes, rewrite it. If a reboot is genuinely needed (first-boot NIC bring-up, a chosen kernel update, a drained cutover reboot, a stateless single host), name which and cite measured boot-time safety, not intent. Replace is itself downtime on a serving host, so the zero-downtime evaluation still applies. Advisory, does not block. **Why:** #9372 — a soft reboot left a web host dark with no recovery path but a replace, while "survives a reboot" had become an acceptance criterion. See `knowledge-base/project/learnings/2026-07-07-immutable-redeploy.md`.

**3b. `review/SKILL.md`.** In the bullet beginning `**User-facing downtime introduced without a zero-downtime path**` (anchor: that bold lead-in), make two edits, total under 400 B:

1. Extend the trigger list ("When the diff touches `apps/*/infra/**` with a reboot/replace-class change, a migration …, or a deploy/router restructure") with: ", or a plan or runbook whose recovery or proof step is a host reboot".
2. Append, inside the quoted `MUST instruct` text and before its closing quote: `Also flag a plan or runbook that uses a host reboot as its recovery or proof step ("survives a reboot", "reboot to verify") when a fresh-instance replace could satisfy it, and name the replace-based equivalent; a named, justified reboot is not a finding.`

Ceiling: `review/SKILL.md` is 475596 B against 477000 B (1404 B headroom).

### Phase 4 — Spec sync

Update `spec.md`: FR1 gains the four carve-outs and the preconditions; FR3 and FR4 per the cuts; add FR5 (plan skill Apply path default). Commit with the plan.

## Files to Edit

- `plugins/soleur/agents/engineering/infra/terraform-architect.md`
- `plugins/soleur/agents/engineering/infra/platform-strategist.md`
- `plugins/soleur/skills/plan/SKILL.md`
- `plugins/soleur/skills/plan/references/plan-sharp-edges.md`
- `plugins/soleur/skills/review/SKILL.md`
- `knowledge-base/project/specs/feat-immutable-infra-replace-dont-reboot/spec.md`

## Files to Create

- `knowledge-base/project/specs/feat-immutable-infra-replace-dont-reboot/tasks.md`

## Open Code-Review Overlap

None. Queried open `code-review` issues for each planned plugin file; the only hit was #4133 (follow-through: schema parity test for the Observability block), which touches `deepen-plan/SKILL.md` and `plan/SKILL.md`. This plan edits only the §2.8 Apply path line of `plan/SKILL.md`, which #4133 does not touch. Acknowledge, no action.

## Acceptance Criteria

Run the checks after committing (or use two-dot `git diff origin/main -- plugins/soleur` before).

- [ ] AC1: `terraform-architect.md` has the section and its preconditions. Check: `grep -c "Replace, Don't Reboot" plugins/soleur/agents/engineering/infra/terraform-architect.md` returns 1, and `grep -c "not a reservation" plugins/soleur/agents/engineering/infra/terraform-architect.md` returns 1.
- [ ] AC2: `platform-strategist.md` Reproducibility First has the bullet. Check: `grep -c "Replace, don't reboot" plugins/soleur/agents/engineering/infra/platform-strategist.md` returns 1, and the text "(see §4)" is absent.
- [ ] AC3: `plan/SKILL.md` §2.8 default flipped. Check: `grep -c "default for a running host with state on a persistent volume" plugins/soleur/skills/plan/SKILL.md` returns 1 and `grep -c "the default for existing infra" plugins/soleur/skills/plan/SKILL.md` returns 0.
- [ ] AC4: `plan-sharp-edges.md` ends with the new bullet, at most 1100 B. Check: `grep -c "chosen the wrong unit of recovery" plugins/soleur/skills/plan/references/plan-sharp-edges.md` returns 1 and `tail -n 1 plugins/soleur/skills/plan/references/plan-sharp-edges.md | wc -c` is at most 1100.
- [ ] AC5: `review/SKILL.md` carries the trigger extension and the in-quote clause. Check: `grep -c "plan or runbook whose recovery or proof step is a host reboot" plugins/soleur/skills/review/SKILL.md` returns 1.
- [ ] AC6: Gates are green. `python3 scripts/lint-skill-body-budget.py --base origin/main` exits 0 (fetch `origin/main` first), `bun test plugins/soleur/test/components.test.ts` passes, and `npx markdownlint-cli2` on the plan, spec, tasks and the five edited plugin files reports 0 issues.
- [ ] AC7: No `description:` line changed and no provider resource names added: `git diff origin/main -- plugins/soleur | grep -E '^[+-]description:'` and `git diff origin/main -- plugins/soleur | grep -E '^\+.*hcloud_'` both print nothing.
- [ ] AC8: The spec reflects the plan. Check: `grep -c "Apply path" knowledge-base/project/specs/feat-immutable-infra-replace-dont-reboot/spec.md` is at least 1, and `grep -n "restart" knowledge-base/project/specs/feat-immutable-infra-replace-dont-reboot/spec.md` prints nothing.

## Test Scenarios

- Given a plan that says "verify by rebooting web-2 and checking the volume unlocks", when `soleur:plan` Step 6.5 applies the catalogue, then the plan is questioned and rewritten to a fresh-instance proof or names the reboot as one of the four legitimate cases.
- Given a single stateless VPS with no declared config that reboots after a kernel update the user asked for, when reviewed, then no finding is raised.
- Given terraform-architect is asked to fix package drift on a running host, when it responds, then it recommends re-provisioning, lists the declared-config, capacity-re-probe and drain preconditions, and does not propose an in-place edit or a reboot.
- Given a PR that only edits a runbook whose recovery step is "reboot the host", when `soleur:review` runs, then the downtime lens loads and the reviewer prompt carries the reboot-as-recovery clause.
- Given the ceiling lint runs against this branch, when `plan/SKILL.md` and `review/SKILL.md` changed by the budgeted amounts, then it exits 0.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward, plus plan-review devex lens)
**Assessment:** No new rule. Place the text in the agents, the plan skill, the sharp-edges file and the review bullet, keyed on intent. Risks: false positives on legitimate reboots; over-claiming replace without the persistent-volume and capacity preconditions; wording drift across surfaces (terraform-architect is the canonical source for the preconditions and the named cases).

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward, plus plan-review scope lens)
**Assessment:** Ship the advisory layer only. A blocking gate would punish a single-VPS founder where a reboot is fine. The deploy-gate half is deferred and tracked (#9764). Product/UX Gate: not applicable — no UI surface.

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** No legal impact for guidance-only scope. Watch-items for any later real replacement: new escrow and secret scope per replaced host, the open restore-substrate gap, destroying superseded snapshots. Evidence language cites measured state, not intent.

## User-Brand Impact

- **If this lands broken, the user experiences:** an infra agent that tells them to replace a host without checking that its data survives, or a plan that is nagged over a justified reboot.
- **If this leaks, the user's workflow is exposed via:** not applicable (no data path); the exposure is a recovery default that over-claims "replace" and strands a fleet because the create fails after the destroy.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** carried forward from the brainstorm's always-on framing; the preconditions text (declared config, persistent volume, capacity re-probed at apply time, drain-gated serving hosts) is what keeps the default from stranding a user.

CPO sign-off: carried forward from the brainstorm CPO assessment. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Sharp Edges

- The byte ceilings are the binding constraint: `plan/SKILL.md` has 4 B of headroom (Phase 2 must be net-neutral), `review/SKILL.md` 1404 B, `deepen-plan/SKILL.md` 103 B (untouched). Any later wish to extend those bodies needs its own ceiling PR.
- The repo's hard rule `hr-prod-host-config-change-immutable-redeploy` is the mandatory form of this default; the shipped text is the advisory form for users who do not have that rule. If either changes, change the other.
- Keep the plan, spec and tasks prose free of literal service-control and remote-shell command strings; `iac-plan-write-guard.sh` denies the write on prose alone (hit once on this branch's spec).
- The sharp-edges catalogue has 230 bullets and is read once at Step 6.5. The new bullet leads with its trigger phrase and stays near 850 B so it is noticed.
- The terraform-architect section is the single canonical statement of the preconditions and the named cases. The other surfaces are shorter on purpose; do not copy the full list into them.
- Invocation surfaces for the two agents (grep, 2026-10-08): terraform-architect is spawned from plan §2.8, the `provision-hetzner` skill and `infra-security`; platform-strategist from brainstorm. The new text has no output template, so no non-diff fallback string is required.
- Cite anchors by content, not line number (`cq-cite-content-anchor-not-line-number`).
