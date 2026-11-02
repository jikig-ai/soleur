---
title: "An issue's prescribed ratchet remedy can be wrong — run the runbook's pre-acceptance grep before writing either row"
date: 2026-11-02
category: workflow-patterns
tags: [affected-index, ratchet, followthrough, #11848]
---

# An issue's prescribed ratchet remedy can be wrong

When `affected-index-ratchet` went red on main with `new-pair`
(`plugins/soleur` ↔ `inngest-userdata-budget.sh`, ref
`terraform-target-parity.test.ts:5876` — a yaml `run:`-string pin), the tracking
issue #11848 was filed prescribing an anchor-keyed **accept** row ("the suite
merely names the file"). The plan-time verification refuted it: the pair is
suite-level, and sibling `cloud-init-user-data-size.test.ts` holds a real
read+execute edge via `BUDGET_SH = join(INFRA, ...)`, invisible to the audit's
literal-name scan. An accept row would have been a live false negative once
PR3b (#10859) makes the context required. The remedy was **declare**, per the
prior ruling on this class (#11771 → #11781, "ambiguity resolves to the
stricter default").

Rule: before writing EITHER row (accept or declare) for a `new-pair`, run the
pre-acceptance grep from `ci-pr-affected-activation.md` §Ratchet red — grep the
suite for the path's basename AND its parent directory as separate string
literals; a computed construction (`join(INFRA, ...)` reads the file without
producing a literal the audit sees. The issue body is a starting hypothesis,
not evidence. Second instance of this class in 24h (first: #11771).
