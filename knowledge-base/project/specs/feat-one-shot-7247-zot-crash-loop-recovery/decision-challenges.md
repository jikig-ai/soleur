# Decision Challenges — feat-one-shot-7247-zot-crash-loop-recovery

Surfaced during `plan` (Step 4.5 scoped consult) and `plan-review` (6-agent panel), classified per
[decision-principles.md](../../../../plugins/soleur/skills/brainstorm-techniques/references/decision-principles.md)
(ADR-084). Headless run — persisted here rather than asked, for `ship` Phase 6 to render into the PR
body and file as an `action-required` issue.

Plan: `knowledge-base/project/plans/2026-08-06-fix-registry-userdata-budget-measures-unstripped-render-plan.md`

---

## DC-1 — Move the registry render into a provider-free Terraform module (`taste`)

**Raised by:** cto (F5), architecture-strategist (P1-1 alternative), Step 4.5 consult (rec. 1).

**The challenge.** The plan fixes the *measurement* of a duplicated render decision. The stronger
move is to delete the duplication: `apps/web-platform/infra/modules/git-data-userdata/` is already a
provider-free module (locals only, no `resource`, no `required_providers`) exporting
`output "rendered"` precisely so a size harness can measure the real thing. A
`modules/registry-userdata/` of the same shape would let `zot-registry.tf` write
`user_data = base64gzip(module.registry_userdata.rendered)` and let the budget script call the same
module — one render expression, one application, and arms B2/B3/B4/B5/B6 become unnecessary.

The stated objection (a scratch dir would need `terraform init`) is weak: `terraform init
-backend=false` against a provider-free *local* module is offline, credential-free, fork-PR-safe,
and costs ~2 s.

**Why not adopted now.** Moving the render changes `${path.module}` resolution on a `user_data` that
is ForceNew with no `ignore_changes`, on the sole container pull path, mid-deploy-freeze, with a
destructive recut pending. Right direction, wrong moment — the reviewers who proposed it said so.

**Recorded as:** an *Out of Scope* tracker to be filed in Phase 4, with the exit criterion
*"`registry-render-strip-parity.test.sh` is deleted as unnecessary"* — which makes the new suite
explicitly temporary scaffolding with a demolition date rather than a permanent per-host guard.

---

## DC-2 — Ship a self-discovering `user_data` budget-coverage enumerator instead of another per-host guard (`taste`)

**Raised by:** cto (F4).

**The challenge.** Five `.tf` files render `base64gzip(templatefile(…))` into `user_data`.
`inngest-host.tf:261` and `grok-dogfood.tf:30` have **no** budget arm in either the `.ts` gate or a
`.sh` gate. The breach that started this whole family (34,628 B against a 32,768 B cap, #7278)
happened precisely because the registry had no arm. Hand-copying a guard per host guarantees the next
breach lands on the host nobody copied to — and two such hosts exist right now.

The plan cites `2026-06-07-self-discovering-parity-guard-for-cross-producer-drift.md` in its
References and then does not apply its recipe: discover every `user_data = base64gzip(` site, assert
`discovered === EXPECTED`, with a non-vacuity floor.

**Why not adopted now.** The enumerator would go RED immediately on `inngest-host.tf` and
`grok-dogfood.tf`, so it needs a scoped allowlist with issue references — its own change, not a
rider on a P1 unblock.

**Recorded as:** an *Out of Scope* tracker to be filed in Phase 4.

---

## DC-3 — Generalise the mutation-battery contract into a meta-harness (`taste`)

**Raised by:** cto (F6).

**The challenge.** The "a green signal certified something other than what it claimed" family has
roughly **30** learnings entries between 2026-07-22 and 2026-08-05 — about one every twelve hours.
Every existing mechanism against it is per-instance: ~10 hand-written mutation batteries, 8 parity
suites over single artifact pairs, and two `AGENTS.rules.md` conventions explicitly marked *"no gate
enforces it"*. This plan adds an 11th per-instance battery. That is correct for this instance and
does nothing for the class.

`tests/scripts/test-registry-gate-mutation-battery.sh` already carries the right contract
(proven-to-land mutation, green-baseline-first, restore-to-pristine, `exit 2` = harness fault).
Lifting it to consume a manifest of (guard, source, mutation) triples would collapse the 10 batteries
into one runner plus a registry, and make *"does this guard have a mutation arm?"* a countable,
gateable property rather than a reviewer's memory.

**Partially adopted.** The cheapest rung — extending `scripts/lint-diagnosis-claims.sh`'s path scope
to `apps/web-platform/infra/` (ADR-166, already blocking, already ratcheted via `.highwater`) — is
folded into the plan as **Phase 2c**. It is the one deliverable in this PR that is not another
instance fix.

**Recorded as:** the meta-harness itself is an *Out of Scope* tracker to be filed in Phase 4.

---

## DC-4 — Amend ADR-096 to record single-delivery-path as an accepted architectural risk (`taste`)

**Raised by:** architecture-strategist (advisory, Q2).

**The challenge.** ADR-096 records "the registry host is cloud-init-only" as a decision. Nothing
records the consequence: **delivery availability ≡ Hetzner stock availability in `hel1-dc2`**, and
any host-side defect is unfixable for the duration of a stock outage. A stateful host on the sole
container-pull path has exactly one code-delivery mechanism — destroy-and-recreate — whose
availability is a function of third-party inventory in one datacenter. The plan's "No ADR" verdict is
right for the gate fix in isolation and wrong for the class the gate fix keeps revealing.

**Why not adopted now.** An ADR amendment is a decision record, not a defect fix; folding it into a
P1 unblock would couple two unrelated review cycles.

**Recorded as:** an *Out of Scope* tracker to be filed in Phase 4, naming #7278 as the mitigation and
the `cpx22` / location repin as the contingency.

---

## DC-5 — Rewrite #7302's body and its unblocking route (`mechanical`, applied indirectly)

**Raised by:** cto (F3).

#7302's body states: *"That PR made the script extract-and-apply the strip **and dropped
`continue-on-error: true`**, so the job now fails the run for real."* Verified false —
`.github/workflows/infra-validation.yml:1194` still carries it. Deferring the flip would leave #7302
a tracker certifying a change that never shipped, which is this plan's own defect class one layer up.

**Adopted** as plan **Phase 2b** (drop `continue-on-error` in this PR; promotion to a *required
context* stays with #7302, genuinely gated on the `paths:` filter, #6480).

**Still outstanding for #7302:** its body needs correcting, and its "What unblocking looks like"
proposes registering a second per-check required context across three files kept in lockstep by
`plugins/soleur/test/required-checks-canonical-parity.test.sh`. The `infra-validate-required`
aggregator (`infra-validation.yml:318`, already `if: always()`) is strictly simpler — add
`registry-userdata-budget` to its `needs:` and fail-closed check, and it rides along when #6480
lands, with no ruleset entry and no canonical-JSON lockstep. Left to #7302's own cycle.
