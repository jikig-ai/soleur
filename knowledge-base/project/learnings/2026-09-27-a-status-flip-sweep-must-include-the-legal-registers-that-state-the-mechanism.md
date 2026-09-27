---
title: "A status-flip docs PR must sweep the legal registers that state the flipped mechanism in the future tense"
date: 2026-09-27
category: workflow-issues
module: knowledge-base/engineering/architecture, knowledge-base/legal
tags: [adr-status, claim-sweep, article-30, append-only, precedent-transfer]
issue: 8211
pr: 9094
---

# Learning: a status-flip sweep must include the legal registers that state the mechanism

## Problem

PR #9094 (#8211 PR2 PM4) recorded ADR-220 D1b and ADR-239 as `accepted` and flipped the C4
`github -> gitDataStore` edge from TARGET to LIVE. The plan's claim sweep covered ADRs, C4, runbooks,
`.github/` and infra. It deliberately put `knowledge-base/legal/**` out of scope, because #8634 owns
Art. 30 *activation* for ADR-239.

That scoping mixed up two things:

- **Activation.** When encryption at rest became active. This is #8634's scope.
- **A tense claim about the same mechanism.** Art. 30 register PA-36 (g)(13) still said the dedicated
  root key "*will* authenticate … as root", inside a `DRAFTED / NOT-YET-ACTIVE` cell. The
  counsel-review audit had pinned that sentence to a re-evaluation trigger (the AC19 dry run reading
  `role=git-data-auth verdict=ok`). The trigger had fired 11 days earlier and was never recorded.

After merge, every engineering record would have said root authentication is LIVE while the one legal
record naming that authority said it had not happened yet. It also understated access: the key has no
forced command. No CI gate compares these files. The pattern-recognition reviewer found it, and the
CLO ruled an append-only, tense-only Superseded marker plus a dated discharge note in this PR.

## Solution

- Index the sweep by the claim's **subject** (the root key, the store, the edge), not by the
  directories the PR is "about".
- Include the legal records that name that subject: the Art. 30 register and the counsel-review
  audits' `re_evaluation_triggers`.
- Route any hit to the CLO for drafted wording. Do not route it to the operator, and do not defer it to
  an issue that owns a *different* activation event.

## Key Insight

"Out of scope because issue N owns activation" is a claim about one event. A status flip can make a
**different** sentence about the same mechanism false. Before excluding a corpus from a status-flip
sweep, grep it for the flipped mechanism's nouns and read every future-tense hit.

A second instance of the same root, precedent transfer, came up in this PR:

- The plan kept ADR-220's D5 table untouched "as #9036 did".
- #9036's ADR-237 has no per-decision status table. ADR-220's own Status section says dated text the
  log replaces "carries a Superseded marker".

A precedent transfers only when the target has the same structure. Check the target's own rules
before citing a sibling's shape.

## Session Errors

1. **The plan scoped `knowledge-base/legal/**` out of the claim sweep, so a stale tense claim in the
   Art. 30 register (PA-36 (g)(13)) survived to review.**
   - Recovery: CLO ruling; an append-only marker plus an audit discharge addendum in-PR.
   - **Prevention:** a bullet in plan-sharp-edges: status-flip sweeps grep `knowledge-base/legal/` for
     the mechanism's nouns and the counsel-review `re_evaluation_triggers`.
2. **The #9036 "leave dated text alone" precedent was applied to ADR-220, whose D5 table requires a
   Superseded marker.**
   - Recovery: an added D5 marker blockquote.
   - **Prevention:** before citing a sibling PR's shape, read the target ADR's own Status or
     amendment rule. Covered by the existing precedent-mirror guidance.
3. **Three added sentences were imprecise:** a verdict named as a probe; "the forward fix booted"
   (a subject re-pointed by substitution); a residual's close attributed to the wrong event.
   - Recovery: rewritten at review.
   - **Prevention:** read each substituted clause against its new subject. Covered by the existing
     dependent-clause guidance in `work/SKILL.md`.
4. **A review fix (citing the clean re-run on host-key step 4) changed a count that AC5 pinned.**
   - Recovery: the AC was amended explicitly, with a reason.
   - **Prevention:** existing rule — amend an AC rather than quietly satisfying a looser one.
5. **The stop hook fired twice, because closing text named future actions while waiting on
   report-only agents.**
   - Recovery: a `<stop>BLOCKED: …</stop>` marker.
   - **Prevention:** when waiting on a panel, end with the stop marker rather than a promise.

## Tags

category: workflow-issues
module: architecture-records, legal-registers
