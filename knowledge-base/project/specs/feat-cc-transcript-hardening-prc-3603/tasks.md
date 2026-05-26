---
title: "PR-C tasks — Legal refresh for cc-soleur-go transcript persistence + DSAR cohort audit"
issue: 3603
pr: 3662
plan: knowledge-base/project/plans/2026-05-12-feat-pr-c-legal-refresh-dsar-audit-plan.md
---

# Tasks — PR-C of #3603

## Phase 1 — Pre-edit hygiene + parity baseline

- [x] 1.1 Run inline grep inventory (false-statement bucket, framing-overwrite bucket, Last-Updated count). Paste output into Phase 2 commit footer. No persistent evidence file.
- [x] 1.2 Confirm `git diff main -- docs/legal plugins/soleur/docs/pages/legal` is empty (parity baseline).

## Phase 2 — Forward-port and extend all four document pairs

Source-first (plugin mirror), mirror-second (canonical). One commit per doc pair (4 commits). Each commit footer includes the `awk` ordering output (R8 hallucination defense per Kieran P1c).

- [x] 2.1 **Privacy Policy** edits — plugin mirror first, then canonical. Sections: §4.7 (full Conversation-data bullet forward-port + `usage` appendage + SIGKILL final sentence), §7 (retention conversation + cascade), §8.1 (cross-ref to §4.7 limitation). SIGKILL phrasing (CLO Q2 revised): "In rare cases of unexpected service interruption (e.g., kernel-level process termination or container restart) after generation but before persistence completes, a small portion of an in-progress reply may not be retained in the conversation record." Both Last-Updated lines advance to 2026-05-12 with summary.
- [x] 2.2 **DPD** edits. Plugin mirror: §2.3(i) `usage` appendage. Canonical: §2.1b(c) data-list mention, §2.3(i) NEW letter item (full conv-mgmt activity + `usage` appendage), §4.2 Supabase row data column, §4.2 cross-ref line updated to add `, 2.3(i)`. Pre-edit `awk` enumeration verifies canonical stops at (h) and plugin at (i). Post-edit re-run verifies canonical now reaches (i) monotonically.
- [x] 2.3 **T&C §5.5** edits. Canonical: forward-port full §5.5 (three bullets: Tokens consumed before Stop are billed / Side-effecting tool calls already dispatched are not automatically reversed / Partial assistant output is preserved) from plugin l. 109-116. Plugin mirror: no content edit beyond Last-Updated.
- [x] 2.4 **GDPR Policy** edits. Plugin mirror: §3.7 `usage` appendage, §10 activity #10 `usage` appendage + SIGKILL data-completeness Notes. Canonical: §3.7 (conv mgmt entry + `usage`), §4.2 (Supabase row data column — conversation columns only, OAuth deferred), §8.4 (retention conv + cascade), §9 (DPIA re-eval), §10 (activity #10 + count line "nine"→"ten" + `usage` + SIGKILL Notes), §11.2 (conv breach scenario). Pre-edit `awk` confirms canonical lists 9 activities; post-edit verifies monotonic 1→10 with #10 = conv mgmt.

## Phase 3 — `legal-compliance-auditor` + fix cycle

- [x] 3.1 Invoke `legal-compliance-auditor` with scope: "Audit `docs/legal/` and `plugins/soleur/docs/pages/legal/` for cross-document consistency on cc-soleur-go conversation-data + `usage` + SIGKILL. Verify no doc references `volatile session storage` or `session-only` for cc-soleur-go data."
- [x] 3.2 Address P0/P1 findings inline. Defer P2/P3 to AC13 consolidated follow-up issue.
- [x] 3.3 Re-run auditor. Final pass returns 0 P0 findings (auditor's own taxonomy per Kieran P2b).

## Phase 4 — W7 DSAR audit + compliance-posture.md + follow-up issue

- [x] 4.1 W7 DSAR cohort audit. Window 2026-05-05 → 2026-05-11. Channels: `legal@jikigai.com` inbox (operator manual step), `gh issue list --label legal --state all --search "created:2026-05-05..2026-05-11"`, Linear `Art. 15 OR DSAR`, Discord support channel completeness-only. Record result count.
- [x] 4.2 Write evidence file `knowledge-base/legal/audits/2026-05-12-w7-dsar-cohort-audit.md` (load-bearing per CLO Q4 — null result is the audit answer).
- [x] 4.3 If ≥1 export found in window: prepare supplementary disclosure draft at `knowledge-base/legal/audits/2026-05-12-w7-supplementary-disclosure-draft.md`. Otherwise skip.
- [x] 4.4 Update `compliance-posture.md`: frontmatter `last_updated: 2026-05-12`; Legal Documents table dates for Privacy Policy / DPD / GDPR Policy / T&C advanced; Vendor DPA Supabase Notes appended (`usage` jsonb column added 2026-05-12 PR #3648, processing-activity-bound DPA scope); TWO Completed Compliance Work rows: (a) W7 audit determination + evidence ref, (b) deliberate operator flip of `CC_PERSIST_USAGE=true` on [verified-date], disclosure-in-flight posture, PR-C #3662 closes disclosure side.
- [x] 4.5 File single consolidated follow-up issue: `gh issue create --title "Forward-port canonical-vs-plugin legal-doc backlog (KB-sharing + OAuth provider row)" --label "domain/legal,priority/p3-low" --body "<body>"`. Reference this PR.

## Phase 5 — `/work` Phase 2 exit GDPR-gate + PR body

- [x] 5.1 Invoke `/soleur:gdpr-gate` against the diff (work-phase 2 exit). Expected 0 BLOCKers. Capture outcome inline in PR body (no separate evidence file).
- [x] 5.2 Author PR body: summary, `Ref #3603` (NOT `Closes`), Operator handoff paragraph (verify live + smoke-test + close umbrella), `## Changelog` with `semver:patch` label, gate outcomes inline.
- [x] 5.3 Verify content-body parity per Test Strategy step 3 (corrected `sed -E 's|/legal/([a-z-]+)/|\1.md|g'` script).
- [x] 5.4 Mark draft PR #3662 Ready.

## Verification (pre-Ready)

- [x] V1 AC4 content-body parity: all 4 doc pairs return "content-body parity OK".
- [x] V2 AC3 GDPR §10 monotonic 1→10 in both copies.
- [x] V3 AC5 auditor 0 P0 findings.
- [x] V4 AC7 Eleventy mirror dual Last-Updated verified for each touched plugin-mirror doc.
- [x] V5 AC10 GDPR-gate Phase 5 outcome captured inline in PR body.
- [x] V6 AC13 follow-up issue exists and references this PR.

## Post-merge (operator handoff, NOT in PR-C)

- [ ] OP1 Verify PR-C content live at https://soleur.ai/legal/privacy-policy/ AND https://app.soleur.ai/legal/privacy-policy/. Record timestamp.
- [ ] OP2 Smoke-test one cc-soleur-go conversation; confirm `messages.usage` populated jsonb on next assistant turn.
- [ ] OP3 `gh issue close 3603`.
