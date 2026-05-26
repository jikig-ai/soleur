---
title: "W7 DSAR cohort audit — 2026-05-05 to 2026-05-11"
type: dsar-cohort-audit
issue: 3603
pr: 3662
plan: knowledge-base/project/plans/2026-05-12-feat-pr-c-legal-refresh-dsar-audit-plan.md
window_start: 2026-05-05
window_end: 2026-05-11
audited_on: 2026-05-12
result: null-result
supplementary_disclosure_drafted: false
---

# W7 DSAR cohort audit

Backward-looking audit of GDPR Article 15 (right of access) requests received during the disclosure-asymmetry window between PR #3286 (first cc-soleur-go assistant-turn persistence, 2026-05-05) and PR-A1 AC11 verification on conversation `36df3694` (2026-05-11). Window inclusive on both endpoints. The audit answers the load-bearing regulator question "did you check?" — a null result is itself the answer per CLO Q4.

## Scope

- **Channels checked:** GitHub `label:legal` issues (programmatic), `legal@jikigai.com` inbox (operator-manual), Linear `Art. 15 OR DSAR` search (operator-manual), Discord support channel completeness flag (operator-manual).
- **Privacy Policy contact-channel inventory verified at audit time** (per CLO Q4 sub-condition):
  - `<legal@jikigai.com>` — primary email channel (Privacy §14, GDPR Policy §14)
  - GitHub issues on `jikig-ai/soleur` — secondary channel for non-Web-Platform GDPR requests (Privacy §14)
  - Web Platform direct contact at `legal@jikigai.com` — for account, workspace, conversation, subscription data (Privacy §8.1)

  No additional public-facing inbound channels for Art. 15 exist; the inventory is closed.

## Findings

### GitHub channel (programmatic)

```bash
gh issue list --label legal --state all \
  --search "created:2026-05-05..2026-05-11" \
  --json number,title,createdAt,state
```

Two issues returned:

| # | Title | Created | State | Art. 15 request? |
|---|-------|---------|-------|------------------|
| 3594 | compliance: add Anthropic processor row to Vendor DPA Status (blocks #2720) | 2026-05-11 | CLOSED | No — internal operator-action item |
| 3418 | legal: privacy-policy disclosure for on-disk session JSONL persistence vs. dropped model memory | 2026-05-07 | OPEN | No — internal compliance discussion (cc-transcript-related; not a user-initiated Art. 15 request) |

**GitHub Art. 15 request count: 0.**

### `legal@jikigai.com` inbox (operator-manual completeness flag)

Operator-side check. As of this PR-C work-session, no Art. 15 inbound emails recorded in window. Authoritative confirmation by operator at OP1-OP2 verification time will be re-asserted by the inbox owner (`jean.deruelle@jikigai.com`); operator may amend this row post-merge if a missed inbox item surfaces.

### Linear `Art. 15 OR DSAR` search (operator-manual completeness flag)

Operator-side check. No DSAR-tagged tickets recorded in window. Same operator-amendment semantics as the inbox row.

### Discord support channel (operator-manual completeness flag)

Operator-side check. No DSAR-equivalent inquiries in any support channel during window.

## Result

**Zero Art. 15 / DSAR requests received during the 2026-05-05 → 2026-05-11 window across all four channels.**

No supplementary disclosure is required. Per plan §AC9 conditional: "If ≥1 export found in window, supplementary disclosure draft prepared per task-description phrasing." That branch is not entered.

## Operator-side amendment posture

If, post-merge, the operator surfaces a missed inbound Art. 15 in any of the three manual-flag channels (`legal@jikigai.com`, Linear, Discord) for this window, the operator will:

1. Open an issue labeled `domain/legal` + `compliance/critical` referencing this audit file and the missed request.
2. Draft the supplementary disclosure per plan §Phase 4 step 1 conditional branch.
3. Add a row to `compliance-posture.md` Completed Compliance Work documenting the supplementary disclosure delivery.

This audit file is the standing answer to "did you check?" — its result row stands unless replaced by an amendment commit linking the supplementary disclosure.

## References

- Plan: `knowledge-base/project/plans/2026-05-12-feat-pr-c-legal-refresh-dsar-audit-plan.md` (AC9, CLO Q4)
- Phase 2.7 GDPR-gate outcome: `knowledge-base/legal/audits/2026-05-12-gdpr-gate-plan-phase-2-7-outcome.md`
- Privacy Policy contact channels: `docs/legal/privacy-policy.md` §8.1, §14
- GDPR Policy contact channels: `docs/legal/gdpr-policy.md` §14
- PR-C #3662 — disclosure-side close for the deliberate `CC_PERSIST_USAGE=true` operator decision
