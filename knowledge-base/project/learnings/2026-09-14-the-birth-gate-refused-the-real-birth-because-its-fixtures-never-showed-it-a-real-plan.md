---
title: "The birth gate refused the real birth because its fixtures never showed it a real plan — three arms read an unknown Terraform collection as empty"
date: 2026-09-14
category: test-failures
module: git-data-host-birth-gate
tags: [terraform, plan-json, after_unknown, fixture-shape, gate, hcloud, git-data, collision-preflight]
issues: [8152, 8139, 8136, 7025, 6982]
severity: P1
---

# The birth gate refused the real birth because its fixtures never showed it a real plan

## Problem

The first real `git-data-host-create` dispatch (run 34822248580, 2026-09-14, main `dddc190a6`, all four readiness gates RELEASED) planned the exact scoped birth — **20 to add, 0 to change, 0 to destroy** — and `git_data_host_birth_gate` aborted with `firewall_unreadable=1`: "the plan does not disclose hcloud_firewall.git_data's rule set". Nothing was created. The suite guarding that gate was 93/0 and had been through mutation batteries and a ten-agent review.

Three arms of one gate each read a Terraform plan-JSON **collection** as empty when it was **unknown at plan time**:

| Arm | Read | Real first-birth shape | Effect |
|---|---|---|---|
| `firewall_unreadable` | `(.after_unknown.rule // false) != false` | `after.rule: []`, `after_unknown.rule: []` — a known-empty set, deny-all | **false refusal** (the one that fired) |
| `fw_attach_ok` | `(.after.server_ids // []) \| length == 1` | `after: {"label_selectors": null}`, `after_unknown.server_ids: true` — the id is API-assigned | **false refusal** on every first birth ("boots NAKED"); the PASS line was never reachable on a real plan |
| `server_inline_firewalls` | `(.after.firewall_ids // []) \| length > 0` | `after_unknown.firewall_ids: true` — Optional+Computed, unknown on every create | **fail-open**: an inline list containing the deny-all's own id collapses to unknown and reads as empty |

`after_unknown` is not a boolean. It mirrors the value's nesting, sparsely: `true` for a wholly-unknown value, `[]` for a known-empty set, `[{field:true}]` per unknown leaf, and an unknown *element* of a nested set collapses that set to `true`. The suite's `rc_entry` fixture builder emits `after: {}` and no `after_unknown` key at all, so no row had ever shown the gate the provider's serialisation. Every fixture that "passed" passed through a shape the provider never emits.

## Solution

PR #8152. `firewall_unreadable` now searches for a boolean `true` leaf anywhere under `after_unknown.rule` (`def has_unknown`, order-independent of the sibling arms), and refuses an `after` object with no `rule` key (a shape no provider emits, which the old fixtures relied on). The two `.after.<set>` arms read the one plan-time signal that IS decidable — the plan's `configuration` block, which discloses what the HCL references: the attachment's `server_ids` expression must reference exactly `hcloud_server.git_data` (a fan-out shows extra references, a literal shows `constant_value`, a missing block cannot be read — all refuse), and any `firewall_ids` expression on the server's config entry is an inline binding regardless of what the value discloses.

Fixtures were rebuilt from captured real output (offline `terraform plan` with hcloud 1.63.0 and a 64-character dummy token — the provider validates token length, not the token — mirroring `git-data.tf`'s three resources), including a `mk_plan_cfg` helper that carries a `configuration` block. Suite 95 → 106/0, each new arm mutation-proven in both directions, plus a static pin that every counter the gate compares numerically is registered with `plan_gate_assert_numeric` (dropping one registration left the suite green while `[[ "" -ne 0 ]]` is false).

## Key Insight

**A fixture is a claim about the producer, and `rc_entry`'s `after: {}` was a claim nobody had checked.** Every assertion in the suite was correct about the fixture and wrong about Terraform. The two P1s were found only when a review seat spliced *real* plan JSON into the fixture — the same instrument (an offline scratch root) that took two minutes to build and would have caught all three arms at authoring time. When a gate reads a serialised artifact, capture one real instance of every state the gate must decide on (create, no-op, update, replace, unknown) before writing a fixture, and ask per collection read: *what does this return when the value is unknown at plan time?* For Terraform that answer is `absent from after` for every API-assigned id and every computed attribute, which is exactly the population a birth gate exists to judge.

**The fix for one arm stopped one arm short.** I fixed the arm that fired and did not walk the gate for the class; the enumeration seat mapped `after_unknown` reads and missed the `.after.<set>` twins. "Applied to the class" means every read of the same kind of value, in both halves of the plan JSON.

## Session Errors

1. **One-shot #8139 duplicated an open sibling PR (#8136) for the same defect.** The release-regression prompt named a commit SHA, a run id and a file basename but no `#N`, so one-shot Step 0a.5's collision check ran zero probes; plan, deepen, work and a ten-seat review ran before a history seat noticed #8136 (3.5 h older, auto-merge armed, byte-equivalent hook fix plus the PR-CI Docker build my plan had deferred). Recovery: stopped the guard-scoped seats, transferred the hook findings to #8136 as comments, watched it to MERGED (prod advanced to `506516c99`), closed #8139. **Prevention:** derive the collision key from the defect's anchors when no issue number is present — routed into `one-shot` Step 0a.5 in this PR.
2. **`/tmp` scratchpad swept during a ~10 h idle gap; `gh pr close --comment "$(cat <missing>)"` closed #8139 with an empty comment** and my compound notes vanished. **Prevention:** durable session artifacts go to `/var/tmp/<session>` or the worktree (existing rule); never feed `$(cat file)` to a mutating command without `[[ -s file ]]` first — an empty substitution is a valid argument.
3. **The plan's perl one-liner `$1 =~ /^new/` clobbered `$2`** (a successful inner match resets the captures), so every `new URL` hit printed an empty specifier. The guard's second zero floor (`saw_url`) caught it on the first run. **Prevention:** copy captures into lexicals before any further match.
4. **The gate refused the real birth on `after_unknown.rule: []`** (the body of this learning). **Prevention:** capture real producer output for every decided state before writing fixtures; the `mk_plan_cfg` + `rc_firewall` helpers now carry the provider's shape.
5. **My fix covered one arm; two sibling arms had the same class**, found by `security-sentinel` splicing real plan JSON. **Prevention:** grep every collection read (`(.after.<x> // []) | length`, `after_unknown.<x>`) in the gate the moment one is fixed; routed into the review structural-enumeration seat in this PR.
6. **The `after` no-`rule`-key tightening reddened 55 rows** — every `rc_entry` firewall lacked the key. Expected RED of a tightening; fixed by giving the suite's firewall entries the real shape. **Prevention:** none beyond (4).
7. **The apply workflow's poll step (`if: always()`) ran its 10-minute budget after a SKIPPED apply**, and its error text asserts "the apply may be green while the host booted DARK" on a run where no apply happened. **Prevention:** gate the poll on the apply step's outcome; tracked on the #8010 post-birth sweep list (workflow file, different subsystem from this PR).
8. **The #8128 settle-then-admin-merge hatch was pre-empted by the pre-merge hook's third auto-sync.** One-off; the admin merge still landed. **Prevention:** none.
9. **The structural-enumeration seat was scoped to `after_unknown` reads** and so could not see the `.after.<set>` twins. **Prevention:** routed into the seat's prompt guidance in this PR.
10. **The git-history seat labelled #8136 "the current PR."** Caught by comparing against the PR number under review. **Prevention:** read every `gh pr list` result against the CURRENT PR number before believing "no sibling".
11. **A `run_in_background` poll was denied by `hr-monitor-not-run-in-background-for-polling`** — the hook worked; replaced with a Monitor. **Prevention:** already enforced.

## Related

- `knowledge-base/project/learnings/2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md` — the fixture-drawn-from-what-reads-well class
- `knowledge-base/project/learnings/2026-08-14-my-gate-reserved-its-reassuring-message-for-its-alarming-condition.md` — the steady-state fixture missing from a change-shaped matrix
- `knowledge-base/project/learnings/2026-07-27-the-safety-rationale-i-wrote-was-false-and-the-gate-it-justified-failed-open-three-ways.md` — a gate's detection layer failing open where the decision-layer battery cannot see
- ADR-149 (git-data birth route and readiness interlock); runbook `git-data-birth.md`
