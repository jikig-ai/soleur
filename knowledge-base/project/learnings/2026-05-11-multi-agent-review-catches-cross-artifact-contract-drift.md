---
module: review
date: 2026-05-11
problem_type: integration_issue
component: review_skill
symptoms:
  - "CSS file's self-documented contract with another file silently breaks when one side changes"
  - "Plan + pattern + architecture + code-quality reviewers approve a diff in isolation"
  - "Only git-history-analyzer reading the other-side artifact catches the drift"
root_cause: cross_artifact_contract_drift
severity: medium
tags: [multi-agent-review, contract-drift, cross-artifact, brand-guide, review-coverage]
synced_to: [review]
related_pr: 3556
related_issue: 3564
---

# Learning: Multi-agent review catches cross-artifact contract drift the rest of the agents miss

## Problem

In PR #3556 (font normalization), `apps/web-platform/app/globals.css:37` carried this comment:

```
Token names mirror knowledge-base/marketing/brand-guide.md exactly.
```

That comment is a **self-documented contract** — the CSS file promises to track the brand guide. The PR changed the typography (drop Cormorant Garamond, normalize to Inter) but did NOT update the brand guide, silently breaking the contract.

Eight of the ten review agents — pattern-recognition-specialist, architecture-strategist, code-quality-analyst, security-sentinel, performance-oracle, data-integrity-guardian, agent-native-reviewer, test-design-reviewer — approved the diff. None read the brand guide. Their scope was the diff and the file under it.

Only `git-history-analyzer` caught it. The agent:
1. Read `knowledge-base/marketing/brand-guide.md` for context on the typography spec
2. Read the CSS file's self-claiming comment at line 37
3. Cross-checked the two and flagged the contradiction as P1

## Solution

Fixed inline in two commits on the PR branch:
- Updated `knowledge-base/marketing/brand-guide.md` to scope Cormorant Garamond headlines to the marketing surface (Eleventy site, banners, landing) and add an explicit "Web-platform dashboard = Inter" row.
- The CSS comment at `globals.css:37` continues to claim fidelity to the brand guide; the brand guide now reflects the new dashboard state, so the contract is restored.

## Key Insight

**When a code/config file self-claims fidelity to another artifact (via comment, README, docstring), the multi-agent review pipeline can miss a divergence unless an agent is explicitly tasked with reading the claimed artifact.** This is the same defect class as the "telemetry-join format-contract drift" pattern in the review skill — internally each side passes tests, but the cross-stream contract silently breaks.

Three review agents covered the LOCAL code (pattern, architecture, code-quality) and all approved. The contract break was only visible by reading BOTH files. The git-history-analyzer's archaeology habit (read past commits + adjacent canonical docs) is what surfaced it.

### Sub-pattern: implicit cross-artifact contract (no self-claim comment) — confirmed PR #3596

PR #3596 added one row to `knowledge-base/legal/compliance-posture.md` `## Vendor DPA Status` documenting Anthropic PBC as a processor under SCCs Modules 2+3 (controller→processor + processor→processor). The row carried NO `mirrors X` / `matches X` self-claim comment — the scanner-pattern grep below would have returned zero hits.

But `docs/legal/gdpr-policy.md:31,39` had a public-facing claim that contradicted the row's framing: "the Plugin does not act as a data processor … Anthropic acts as an **independent data controller or processor** … requests are sent to Anthropic's Claude API using the user's own API key. Soleur does not intermediate." The row's SCCs-M2+3 framing implied Soleur engages Anthropic as its processor for ALL Anthropic API surface, contradicting the public framing for plugin/skill-mode invocations.

`security-sentinel` caught it because it instinctively reads adjacent public legal docs when reviewing a legal/compliance diff. The 3 other agents (git-history, pattern-recognition, code-quality) approved the diff in isolation. The fix narrowed the row's `Notes` cell scope to "Jikigai-keyed Anthropic API surface only" (`claude-code-action` CI workflows + compound-promotion-loop) and added an explicit pointer to `gdpr-policy.md § 2.2` for plugin-mode user-keyed calls.

**Generalized lesson:** Implicit cross-artifact contracts exist whenever two artifacts independently describe the same real-world relationship — vendor processor status, schema column meaning, taxonomy IDs, route auth posture. The scanner-pattern grep below catches the *explicit* self-claim case; for the *implicit* case, the review agent must have domain instinct to read the adjacent public-facing artifact. Make this instinct explicit in review prompts: **for any diff touching `knowledge-base/legal/`, the review prompt MUST include "verify the diff's framing of vendor role / data flow / transfer mechanism agrees with `docs/legal/{gdpr,privacy}-policy.md`'s existing public disclosure for the same vendor."**

## Prevention

**For future review prompts:** when the diff touches a file containing a "mirrors X" / "kept in sync with X" / "matches X" self-claim comment, include in the review prompt: *"Read the named artifact X and verify the claim still holds post-diff."*

**Scanner pattern (cheapest gate):** at plan time or review time, grep changed files for self-claiming comments:

```bash
git diff origin/main...HEAD --name-only | xargs rg -l "(mirror|matches|kept in sync|tracks|reflects) (the )?(knowledge-base/|docs/|spec/)" 2>/dev/null
```

Any hit produces a list of files whose changes must be cross-checked against the named artifact. This is the same shape as the existing `cq-eleventy-critical-css-screenshot-gate` (renders against an external truth, gates the diff).

## Session Errors

- **Bash CWD reset across calls** — Chained `cd apps/web-platform && cmd` worked, but a follow-up bare command lost CWD and got "no such file or directory". Recovery: use `cd <worktree-abs-path> && cmd` chains consistently. Prevention: discoverable via clear error; already documented in AGENTS.md (`hr-when-a-command-exits-non-zero-or-prints`). No new rule.
- **`next lint` triggered interactive ESLint setup prompt** — Project has no ESLint config; `next lint` blocks waiting for menu input. Recovery: skipped lint, relied on `tsc --noEmit` + `vitest run` as quality gates. Prevention: discoverable; this project uses TSC + Vitest, not ESLint. No new rule.
- **PR #3596: WebFetch to `https://www.anthropic.com/legal/dpa` returned HTTP 404** — guessed slug from document name rather than starting from canonical vendor terms page. Recovery: the correct URL (`/legal/data-processing-addendum`) was embedded as a link inside the commercial-terms § C response. Prevention: when verifying vendor legal docs, start from the canonical terms page and follow embedded links, never guess slugs. Already covered by the existing learning instinct; no new rule.

## Related

- Defect class entry in `plugins/soleur/skills/review/SKILL.md` § "Defect Classes This Review Reliably Catches" — "Cross-stream format-contract drift in telemetry joins" (PR #3124) is the closest precedent. This learning generalizes that pattern from telemetry joins to **any** self-claimed cross-artifact contract.
- PR #3556 — the originating PR (explicit-self-claim sub-pattern).
- PR #3596 — second confirmation (implicit cross-artifact contract sub-pattern, vendor-DPA-row vs gdpr-policy framing).
- Issue #3564 — the deferred-scope-out filed in the same review session as #3556 (CWV infrastructure, architectural-pivot).
