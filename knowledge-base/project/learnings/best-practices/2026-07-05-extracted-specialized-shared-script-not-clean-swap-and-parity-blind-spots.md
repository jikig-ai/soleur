---
title: Extracted-then-specialized shared scripts aren't clean swaps; parity/classification guard blind spots (head -1, forget)
date: 2026-07-05
category: best-practices
module: apps/web-platform/infra, plugins/soleur/skills/review
tags: [drift-guard, fail-open, terraform, scope-out, concur-gate, review, parity, dry]
severity: medium
related:
  - "[[2026-06-14-all-members-drift-guard-must-rebase-before-ship]]"
  - "[[2026-07-02-cloned-drift-guard-convenience-filter-is-fail-open]]"
  - "[[2026-06-12-source-scan-containment-gate-call-detection-and-fail-closed-lexing]]"
  - "[[2026-05-06-scope-out-criterion-misclassification-adr-not-architectural-pivot]]"
---

# Extracted-then-specialized shared scripts aren't clean swaps; parity/classification guard blind spots

Surfaced by the 10-agent review of PR #6030 (web-2-recreate bootstrap: a CI-driven
`terraform apply -replace='hcloud_server.web["web-2"]'` guarded by a jq destroy-guard
counter + coherence preflight). Zero P1; the value was three generalizable review catches.

## 1. `head -1` in a drift-parity guard silently un-guards a newly-added copy

`web-hosts-fanout-parity.test.sh` asserts every workflow copy of the
`WEB_HOST_PRIVATE_IPS` fan-out roster equals `var.web_hosts`. Its extractor ended in
`| tr -d '"' | head -1` — it validated only the FIRST occurrence per file. When this PR
added a SECOND copy (the new `web_2_recreate` job env), that copy escaped the guard
entirely: a future edit to `10.0.1.11` in the new copy would pass CI, defeating the
single-peer `reason==ok ⟹ web-2 accepted` invariant the guard exists to protect.

**Insight:** a parity guard that extracts "the first match" is NOT an all-members guard —
it is a *first-member* guard that goes stale the moment a PR adds copy N+1. A union-then-
compare is also wrong (it hides a copy that DROPS a member). The fix is per-copy
validation + a KNOWN-copy-count assertion (`min_copies`), so a silently-removed copy or a
new-and-unequal copy both fail loud. Reviewer reflex: when a PR adds a new copy of a
replicated literal that already has a parity guard, open the guard and confirm it iterates
ALL occurrences, not `head -1` / `[0]` / `grep -m1`. Extends
[[2026-06-14-all-members-drift-guard-must-rebase-before-ship]] — there the guard missed a
member added on `main`; here it missed a member added *by the same PR*.

## 2. `["forget"]` is a fail-open blind spot in delete/create/update-only plan gates

The destroy-guard counted any resource change with `actions ∋ {create,update,delete}`
outside a 3-address allow-set. A Terraform 1.7+ `removed {}` block serializes as
`actions == ["forget"]` (drops the resource from state WITHOUT destroying the real infra) —
which the enumerated predicate did NOT count. A future `removed{}` on the data volume or
web-1 would have passed the gate. Two orthogonal agents (security + data-integrity)
converged on it.

**Insight:** any classification gate over terraform plan actions that enumerates
`create/update/delete` has a `forget` hole. `forget` is low-blast-radius (state-drift, not
data loss) but it evades the gate. Close it pre-emptively by adding `forget` to the action
predicate (the allow-set's own replaces never emit `forget`, so no false-positive) and add
a fixture that RED-tests it (drop `forget` from the predicate → the fixture must flip to a
false-PASS). Generalizes the fail-open family ([[2026-07-02-cloned-drift-guard-convenience-filter-is-fail-open]]):
enumerate the FULL action vocabulary of the format you classify, not just the obvious verbs.

## 3. A shared script extracted-and-specialized for its FIRST consumer is not a clean swap for its origin sibling

`deploy-status-fanout-verify.sh` was extracted from `warm_standby`'s inline verify poll so
the new `web_2_recreate` job could "REUSE this poll rather than re-derive a copy." Two
agents flagged that `warm_standby` was never migrated onto it — two divergent copies, drift
hazard. The `code-simplicity-reviewer` CONCUR gate first DISSENTED, judging the migration a
"small in-file swap" that should be fixed inline.

But inspecting the actual artifacts showed the extraction had SPECIALIZED the script for its
first consumer: (a) recovery messages hard-coded to the recreate context ("recreate landed",
"web-2 recreated but NOT deployed") — wrong for warm_standby's provision context; (b) the
script is MONOLITHIC (baseline+trigger+verify in one bash run, no step outputs) while
`warm_standby` is THREE GHA steps publishing `deployed_tag`/`pre_start_ts` outputs consumed
downstream; (c) the copies had already drifted on a tag-downgrade race guard. So the
migration is a moderate STRUCTURAL refactor of a working prod path (about to run in the
imminent GA cutover), not a mechanical swap.

**Insight:** "extracted for reuse" ≠ "reusable by the sibling it came from." When an
extraction is specialized to its first caller (context strings, collapsed step structure,
new guards), migrating the origin sibling is a real refactor. A CONCUR/simplicity gate
assessing *migrate-inline vs defer* on a "small swap" premise can reach the wrong verdict —
so verify the extraction's structural + messaging divergence and the origin's step-output
structure BEFORE accepting or rejecting the deferral. When the DISSENT is on the criterion
LABEL (not the underlying deferral), re-file under the fitting criterion with the structural
evidence the first pass lacked (per [[2026-05-06-scope-out-criterion-misclassification-adr-not-architectural-pivot]]).
Here that flipped `cross-cutting-refactor` → `contested-design` (3 genuinely trade-off
approaches: collapse-to-one-call / sourceable-functions / parity-guard-test) and the second
gate CONCURred. Filed as #6040 with an event-grep follow-through (auto-closes when
`warm_standby` sources the shared script; scoped to the warm_standby job block so the
pre-existing occurrence in `web_2_recreate` cannot vacuously close it).

## Session Errors

- **IaC-routing-hook blocks on descriptive prose (forwarded from plan phase).** Recovery:
  resolved via the `iac-routing-ack` opt-out + rephrasing root-cause/rejected-alternative
  prose so it doesn't read as prescribed steps. Prevention: already covered — the
  `lint-infra-no-human-steps` ignore-region + ack mechanism exists; one-off. Not recurring.
- **Forget fixture had an extra `}` brace → `jq parse error` on the first T28 run.** Recovery:
  removed the extra brace; `jq empty` validated; T28 passed. Prevention: run `jq empty
  <fixture>` on any new hand-authored plan-JSON fixture before wiring it into a test (cheap
  pre-check). One-off typo.
- **First CONCUR gate DISSENTED on the `cross-cutting-refactor` label.** Recovery: re-filed
  the scope-out under `contested-design` with structural evidence (monolithic script vs
  warm_standby's 3-step-with-outputs + recreate-specialized messaging). Prevention: when a
  deferral's criterion is contested, present the STRUCTURAL evidence (not just the file
  count) in the CONCUR prompt so the gate judges the real shape — see insight #3. Recurring
  workflow insight → routed to the review skill.
