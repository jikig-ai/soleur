---
title: "docs: extend hr-verify-repo-capability-claim-before-assert to external-existence claims"
date: 2026-06-29
type: docs
issue: 5706
branch: feat-one-shot-5706-external-existence-rule
lane: procedural
brand_survival_threshold: none
status: planned
---

# 📚 docs: extend `hr-verify-repo-capability-claim-before-assert` to external-existence claims

Closes #5706.

## Enhancement Summary

**Deepened on:** 2026-06-29 · **Sections enhanced:** verification record added · **Approach:** proportionate inline deepen (one-line AGENTS edit; a 40-agent fan-out would violate the repo's own minimalism rules).

### Key confirmations
1. **Byte feasibility proven, not assumed.** A measured fold-in candidate is 480 B vs the current 473 B line → +7 B, landing B_ALWAYS at 22986 ≤ 23000. No paired trim is strictly required; net ≤ 0 remains the preferred discipline.
2. **Premise corrected.** The issue's "22,000 critical threshold" is stale; the real reject cap is 23000 (issue #4599, CLOSED). Reconciliation table records this.
3. **All cited references verified live.** `hr-verify-repo-capability-claim-before-assert`, `cq-rule-ids-are-immutable`, `cq-agents-md-tier-gate` are ACTIVE (the retired-registry hit for the immutability rule was a comment-line false positive). #4599 and #4819 resolve as CLOSED issues whose titles match their claimed roles.

### Deepen-plan gate results
- Phase 4.6 (User-Brand Impact): PASS — section present, threshold `none`, non-sensitive path (AGENTS.core.md is not in the preflight Check 6 regex).
- Phase 4.7 (Observability): skip — pure-docs (`.md` at repo root, outside `plugins/*/skills/` and `apps/*/`).
- Phase 4.8 (PAT-shaped var): PASS — no PAT-shaped variable or token literal in the plan.
- Phase 4.9 (UI wireframe): skip — no UI surface in Files to Edit.
- Phase 4.4 (precedent-diff): precedent for byte-disciplined AGENTS-rule edits is established (#4819 introduced this rule; #4599 raised the cap). No SQL/atomic-write/lock pattern; no novel-pattern scrutiny needed.

## Overview

The hard rule `hr-verify-repo-capability-claim-before-assert` (AGENTS.core.md:47) today encodes
"verify-before-asserting" only for **this-repo capability** claims — e.g. "tool X is GUI-only",
"script Y doesn't exist". Issue #5706 (route-to-definition proposal from the 2026-06-29
skill-eval-gate brainstorm) asks to **generalize the same discipline to the denial direction for
external-world existence**: before asserting a named external system / model / paper / product /
company is *fake / doesn't exist / is hallucinated*, `WebSearch` it first when it could plausibly
postdate the knowledge cutoff.

This is a single-line AGENTS.core.md body edit. The rule **id is unchanged** (immutable per
`cq-rule-ids-are-immutable`), so the AGENTS.md pointer line is untouched and the
pointer↔body coupling (`lint-rule-ids.py`) holds. The only hard constraint is the
always-loaded byte budget.

**Origin (already captured, no edit needed):** the failure was denying SkillOpt (arXiv 2605.23904),
EvoSkill (2603.02766), and GPT-5.5 as fabrications off a stale Jan-2026 cutoff — all three are real.
Source learning: `knowledge-base/project/learnings/2026-06-29-verify-post-cutoff-existence-before-asserting-fabrication.md`.

## Research Reconciliation — Spec/Issue vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "always-loaded AGENTS payload is 22,979 B (**over the 22,000 critical threshold**)" | The reject cap was raised **22000 → 23000 in #4599** (`scripts/lint-agents-rule-budget.py`: `B_ALWAYS_REJECT = 23000`, `B_ALWAYS_WARN = 20000`). Current B_ALWAYS = 22979 → **21 B under the real cap**, but in the WARN tier (≥20000). | The issue's premise is stale on the *number* but the practical guidance (byte-neutral-or-negative) is still the right discipline because 21 B is negligible headroom. **A paired trim elsewhere is NOT strictly required** — a +7 B fold-in already passes (proven below). Aim for net ≤ 0; hard fail at any net change > +21 B. |
| "must be byte-neutral-or-negative (pair with a trim), not an add" | A measured fold-in candidate is **480 B** vs the current **473 B** line (`splitlines`/`encode("utf-8")`, no newline) → **+7 B**, landing B_ALWAYS at 22986 ≤ 23000. Per-rule cap is 600 B (124 B of line headroom). | Fold into the existing rule body (no new rule). Reword the now-contradictory `Scope: this-repo artifacts, not general facts.` clause to cover external existence. Byte-measure at /work; prefer a ≤473 B (net ≤ 0) form, accept ≤494 B (+21 B) as the absolute ceiling. |
| Rule covered by tests? | `plugins/soleur/test/mandatory-wireframes-hardening.test.ts:73-82` asserts the id is present in both AGENTS.md and AGENTS.core.md, AND that the word **"subagent"** appears within `[idx-400, idx+200)` of the id. | Keep the id string byte-identical and keep "subagent" in the prose **before** the id (within 400 chars). No exact-wording assertion exists, so the reword is free otherwise. |

## User-Brand Impact

**If this lands broken, the user experiences:** no direct user-facing artifact — this is internal
agent-guidance text. A botched edit (over-trim, broken id) would degrade agent reasoning quality
(rule silent-no-op) but produces no UI/endpoint/data change.
**If this leaks, the user's data is exposed via:** N/A — no data surface; AGENTS.md is committed
guidance, not a runtime secret or schema.
**Brand-survival threshold:** none — internal procedural doc, not a sensitive path (not a schema,
migration, auth flow, API route, or `.sql` file per the preflight Check 6 regex). No CPO sign-off required.

## Premise Validation

- **Cited issue #5706** — open; `deferred-scope-out`; this plan targets it (Closes). Held.
- **Cited file `AGENTS.core.md` rule line** — confirmed present at line 47; id matches. Held.
- **Cited learning file** — exists (3078 B). Held; no edit needed (historical record).
- **Cited byte threshold "22,000"** — **STALE**; real cap is 23000 (#4599). Reconciled above.
- **Cited mechanism (fold into existing rule, byte-neutral)** — feasibility proven by measurement
  (+7 B candidate passes). The mechanism is sound; only the "must pair with a trim" necessity is relaxed.

## Files to Edit

- `AGENTS.core.md` — reword the single rule body line (`:47`) for `hr-verify-repo-capability-claim-before-assert`:
  - Extend the limiting/negative-claim clause to ALSO cover "a named external system/model/paper/product is fake/doesn't exist/hallucinated".
  - Add the remedy for the external case: `WebSearch` before asserting fabrication when the entity could postdate the knowledge cutoff.
  - Reword/replace the contradictory `Scope: this-repo artifacts, not general facts.` sentence (it now contradicts the broadened scope).
  - Append `#5706` to `**Why:**` (retain `#4819`).
  - Keep the `[id: hr-verify-repo-capability-claim-before-assert]` token byte-identical; keep "subagent" before the id.

**Illustrative candidate (480 B — MUST be byte-measured and ideally tightened to ≤473 B at /work):**

```text
- Before asserting — in your own output OR a subagent prompt — a limiting/negative claim about THIS repo's tools/scripts/skills/flags ("Y doesn't exist"), OR that a named external system/model/paper/product is fake/hallucinated, verify first (grep/read repo source; WebSearch a post-cutoff entity) or phrase it as a question [id: hr-verify-repo-capability-claim-before-assert]. Trigger is semantic: a confident false claim trips it, in either direction. **Why:** #4819, #5706.
```

## Files to Create

None.

## Non-Goals

- **No new rule.** Folding into the existing body keeps the AGENTS.md index pointer (and its
  always-loaded ~55 B cost) unchanged. Adding a rule would consume the 21 B headroom and fail the budget.
- **No edits to the SKILL.md prose mirrors** (`plugins/soleur/skills/brainstorm/SKILL.md:223`,
  `plugins/soleur/skills/plan/SKILL.md:105`). These describe the *repo-capability* application of the
  rule and remain accurate; extending them to external-existence is out of scope for a byte-disciplined
  one-line change and adds no enforcement. Acknowledge, do not fold in.
- **No edit to `knowledge-base/project/rule-metrics.json`** — generated artifact (`generated_at` field),
  not a hand-maintained definition.
- **No edit to the source learning file** — it is a point-in-time record that already references the
  route-to-definition proposal.
- **No `AGENTS.md` pointer change** — id is immutable and unchanged.

## Open Code-Review Overlap

Queried open `code-review` issues for `AGENTS.core.md` / `AGENTS.md` / the rule id. Matches —
**#4133** (Observability schema-parity test), **#3373** (SLOT_TRIGGER nightly CI), **#3002**
(service-worker error handler) — are **false positives**: their bodies mention the AGENTS filenames
in unrelated contexts; none touch the `hr-verify-repo-capability-claim-before-assert` line.
**Disposition: Acknowledge** (none relevant; no fold-in).

## Acceptance Criteria

### Pre-merge (PR)
- [x] **AC1 — content extended.** `sed -n '/hr-verify-repo-capability-claim-before-assert/p' AGENTS.core.md` contains both `WebSearch` and an external-existence phrase (`external` and one of `fake|hallucinat|doesn't exist`). ✅ verified.
- [x] **AC2 — id intact in both files.** `grep -l 'hr-verify-repo-capability-claim-before-assert' AGENTS.md AGENTS.core.md` returns both paths; the `[id: ...]` token is byte-identical to HEAD. ✅ verified.
- [x] **AC3 — B_ALWAYS within cap.** Net change −3 B → B_ALWAYS = **22976** ≤ 23000 (under HEAD's 22979). ✅ verified.
- [x] **AC4 — per-rule cap.** Reworded body line = **470** UTF-8 bytes ≤ 600. ✅ verified.
- [x] **AC5 — budget linter green.** `lint-agents-rule-budget.py` exits 0 (WARN only — B_ALWAYS ≥ 20000, expected). ✅ verified.
- [x] **AC6 — rule-id linter green.** `lint-rule-ids.py` exits 0 (id present, not retired, not duplicated). ✅ verified.
- [~] **AC7 — enforcement-tag linter.** `lint-agents-enforcement-tags.py` exits 1 due to **11 PRE-EXISTING** anchor-resolution failures on UNRELATED rules (lines 19,20,21,33,36,38,44,45 + AGENTS.docs.md). Identical error count before and after this edit; my rule (line 47) carries **no enforcement tag** → produces zero errors. This linter IS wired as a **local pre-commit gate** in `lefthook.yml` (`agents-enforcement-tag-lint`, glob `AGENTS.core.md`) — already red on those 11 anchors for any AGENTS edit (pre-existing repo debt) — but is **NOT referenced by any `.github/workflows/` CI job** (verified by grep), and `test-all.sh` does not run it either, so it does **not** block merge; main CI is green. Fixing the unrelated anchors is out-of-scope creep on a high-collision file. Intent (no NEW tag failure introduced) holds. *(Correction: an earlier draft of this AC claimed "only its own `.test.sh` references it" — false; `lefthook.yml` also invokes it. Caught at multi-agent review — ironically the exact ungrepped-negative-claim failure mode `hr-verify-repo-capability-claim-before-assert` guards against.)*
- [x] **AC8 — test suite green.** `bun test plugins/soleur/test/mandatory-wireframes-hardening.test.ts` → 13 pass / 0 fail. ✅ verified.
- [x] **AC9 — provenance.** `**Why:** #4819, #5706.` — both present. ✅ verified.

(Full-suite exit gate: `scripts/test-all.sh` → **128/128 suites passed**, exit 0.)

## Test Scenarios

- **T1 (positive).** After the edit, the budget + rule-id + enforcement-tag linters all exit 0 and the existing test passes — proves the fold-in is byte-legal and test-compatible.
- **T2 (window invariant).** Confirm `core.indexOf(id) - core.indexOf("subagent")` keeps "subagent" within 400 chars before the id (the test window), so the reword does not regress AC8.
- **T3 (net-byte regression).** `git show HEAD:AGENTS.md HEAD:AGENTS.core.md` byte-sum vs. working-tree byte-sum confirms net change ≤ +21 B (target ≤ 0).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal agent-guidance / tooling change. No UI surface
(no files under `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`); Product gate does not
fire. No infrastructure (Phase 2.8), no regulated-data surface (Phase 2.7 GDPR), no code-class
observability surface (Phase 2.9), no architectural decision (Phase 2.10 — guidance wording, not a
system-architecture change).

## Risks & Sharp Edges

- **Byte budget is the only hard gate.** B_ALWAYS headroom is 21 B. Byte-measure the reworded line
  (`encode("utf-8")`, no newline) before commit; do not eyeball. Prefer a net ≤ 0 form so future rule
  additions keep room.
- **Scope sentence contradiction.** The current `Scope: this-repo artifacts, not general facts.`
  directly contradicts the extension — it MUST be reworded/removed, not left in. Leaving it produces a
  self-contradictory rule.
- **"subagent" window.** `mandatory-wireframes-hardening.test.ts` requires "subagent" within
  `[idx-400, idx+200)` of the id; keep it in the prose before the id.
- **Id immutability.** Do not alter the `[id: ...]` token (`cq-rule-ids-are-immutable` + AC2 + test).
- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 —
  this plan's section is filled (threshold `none`, non-sensitive path).
