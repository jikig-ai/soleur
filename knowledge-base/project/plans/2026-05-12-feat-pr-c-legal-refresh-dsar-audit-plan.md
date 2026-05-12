---
title: "PR-C — Legal refresh for cc-soleur-go transcript persistence + DSAR cohort audit (#3603)"
type: feat
issue: 3603
pr: 3662
branch: feat-cc-transcript-hardening-prc-3603
worktree: .worktrees/feat-cc-transcript-hardening-prc-3603
classification: regulated-data-document-refresh
brand_survival_threshold: single-user-incident
requires_cpo_signoff: true
gdpr_gate_required: true
created: 2026-05-12
revised: 2026-05-12 (post-plan-review v2 — collapsed phases, cut audit-file proliferation, reframed Doppler flip as deliberate operator decision)
---

# Plan: PR-C — Legal refresh for cc-soleur-go transcript persistence + DSAR cohort audit

Issue: [#3603](https://github.com/jikig-ai/soleur/issues/3603) (umbrella). Draft PR: [#3662](https://github.com/jikig-ai/soleur/pull/3662). Branch: `feat-cc-transcript-hardening-prc-3603`. Worktree: `.worktrees/feat-cc-transcript-hardening-prc-3603`.

## Overview

PR-A1 (#3602, merged 2026-05-12 07:03 UTC) shipped stream-end persistence of cc-soleur-go assistant turns plus abort-flush of partial assistant text as `status: aborted` rows. PR-A2 (#3648, merged 2026-05-12 09:41 UTC) shipped the `usage` jsonb column write (token consumption + cost metadata), gated by the `CC_PERSIST_USAGE` env var. At plan-time on 2026-05-12 the operator confirmed `CC_PERSIST_USAGE=true` is set in both `prd` and `prd_scheduled` Doppler configs — a **deliberate operator decision** taken with PR-C disclosure in flight, not a flag-flip-by-mistake. PR-C is the disclosure side of that decision.

PR-C does not ship code. It updates controller-side data-processing disclosures (Privacy Policy, Data Protection Disclosure, GDPR Policy, Terms & Conditions, plus the internal `compliance-posture.md` register) and runs a backward-looking DSAR cohort audit covering 2026-05-05 (PR #3286 first ship of cc-soleur-go assistant-turn persistence) through 2026-05-11 (PR-A1 AC11 verification on conversation `36df3694`).

**Why this matters:** the canonical `docs/legal/` is materially behind the plugin mirror on conversation-data disclosure (verified at plan-time). The Privacy Policy / DPD / T&C / GDPR Policy live in two parallel locations and they currently differ. With `CC_PERSIST_USAGE=true` live, the disclosure-side close cannot wait. A single CNIL-actionable disclosure asymmetry on `usage` jsonb is the brand-survival floor.

**GDPR-gate triple invocation:** plan Phase 2.7 (completed — see [evidence file](../../legal/audits/2026-05-12-gdpr-gate-plan-phase-2-7-outcome.md)), `/work` Phase 2 exit (Phase 5 below), `/ship` Phase 5.5 (post-work).

## User-Brand Impact

**If this lands broken, the user experiences:** a Privacy Policy + DPD that fails to disclose that cc-soleur-go assistant turns, aborted-turn partial outputs, and token-consumption / cost metadata (`usage` jsonb) are persisted under Jikigai control. Materially divergent disclosure between docs and prod behavior.

**If this leaks, the user's [data / workflow / money] is exposed via:** legal misrepresentation. The data category itself (token counts + cost) is not high-risk — the **disclosure asymmetry** is the actionable harm.

**Brand-survival threshold:** `single-user incident`. One CNIL referral citing the §4.7 / Article 30 register gap against `usage` collection is sufficient. CPO sign-off required at plan-time (`requires_cpo_signoff: true`); `user-impact-reviewer` enumerates failure modes at review-time.

**Residual post-merge exposure (deferred to follow-up #3666):** the plugin-mirror legal docs at soleur.ai trail the canonical at app.soleur.ai on several non-cc-soleur-go processing activities (KB sharing, push notifications, Resend transactional email, OAuth provider row in GDPR §4.2). A user reading only the plugin-mirror docs may miss disclosures for activities that reach them. PR-C does not absorb this cross-surface asymmetry; AC13 follow-up consolidates the forward-port. Surfaced post-merge by review-time `user-impact-reviewer` (PR #3662 review).

## Research Reconciliation — Spec vs. Codebase

Three verified divergences between the brainstorm-handoff framing and codebase / external-service reality.

| Spec claim | Reality (verified at plan time) | Plan response |
|---|---|---|
| "Update `docs/legal/privacy-policy.md` §4.7" — implying §4.7 base disclosure exists | Canonical §4.7 lists Account / Workspace / Subscription / Technical only. **Conversation-data bullet exists only in plugin mirror** (`plugins/soleur/docs/pages/legal/privacy-policy.md:113`). | Unidirectional forward-port (plugin → canonical), then extend BOTH copies with `usage` + SIGKILL. |
| "Update DPD activity #10" | Canonical DPD §2.3 stops at (h); plugin mirror has (i) = "Web Platform conversation management". The "activity #10" framing corresponds to the **GDPR Policy** Article 30 register (`§10`): canonical lists 9 activities, plugin lists 10, where #10 = conversation management added 2026-03-29. | Forward-port DPD §2.3(i) plugin → canonical AND GDPR §10 activity #10 plugin → canonical; extend both copies of both with `usage` appendage. |
| "Latent-exposure window between PR-A2 merge and PR-C merge" | `CC_PERSIST_USAGE=true` in BOTH `prd` and `prd_scheduled` at plan time. Operator confirmed deliberate flip with PR-C in flight. Sentry `op: "cc-persist-usage-on"` Art. 33 anchor (`cc-dispatcher.ts:222`) is the per-process first-true observation timestamp. | Plan reframes from "latent window" to "deliberate operator decision". `compliance-posture.md` Completed Compliance Work row documents the decision + PR-C ETA; not a near-miss, not an Art. 33-notifiable incident. PR-C closes the disclosure side as the planned-and-known counterpart to the operator's flip decision. |

Sub-agent verification note: the plan-time CLO advisory claimed canonical DPD has §2.3(i)/(j)/(k) that the plugin lacks. Direct `awk` enumeration against both files proved this false (canonical stops at (h); plugin at (i); neither has (j)/(k)). Sub-agent inventory claims about sibling-letter ordering are verified by `awk` before propagation; the bidirectional-sync framing the CLO derived from the hallucinated claims is rejected.

Full canonical-vs-plugin gap table (verified state):

| Disclosure surface | Canonical (`docs/legal/`) | Plugin mirror (`plugins/soleur/docs/pages/legal/`) | PR-C action |
|---|---|---|---|
| Privacy Policy §4.7 Conversation-data bullet | ❌ absent | ✓ present (l. 113) | Forward-port + extend (`usage`, SIGKILL) |
| Privacy Policy §7 retention conversation + cascade | ❌ absent | ✓ present (l. 223) | Forward-port |
| Privacy Policy §8.1 Art. 15 export-completeness cross-ref | ❌ absent | ❌ absent | Add (new, both copies) |
| DPD §2.1b(c) data list mentions conversation metadata + message content | ❌ absent | ✓ present (l. 80) | Forward-port |
| DPD §2.3(i) Web Platform conversation management | ❌ absent | ✓ present (l. 108) | Forward-port + extend (`usage`) |
| DPD §4.2 Supabase row data column | ❌ stops at session data | ✓ includes conversation metadata + message content (l. 159) | Forward-port |
| T&C §5.5 Metered Usage and Partial Consumption | ❌ absent | ✓ present (l. 109-116) | Forward-port |
| GDPR Policy §3.7 conversation management entry | ❌ absent | ✓ present (l. 97) | Forward-port + extend (`usage`) |
| GDPR Policy §4.2 Supabase row (conversation columns) | ❌ absent | ✓ present (l. 140) | Forward-port |
| GDPR Policy §8.4 retention conversation + cascade | ❌ absent | ✓ present (l. 265) | Forward-port |
| GDPR Policy §9 DPIA conversation re-evaluation | ❌ absent | ✓ present | Forward-port |
| GDPR Policy §10 Article 30 register activity #10 | ❌ absent (9 activities) | ✓ present (l. 304, ten activities, #10 = conv mgmt) | Forward-port + extend (`usage`) — verify monotonic 1→10 ordering post-edit |
| GDPR Policy §11.2 conversation breach scenario | ❌ absent | ✓ present | Forward-port |
| KB-sharing forward-port (Privacy §4.8 / DPD / T&C §8.1c / GDPR §3.8) | ❌ absent | ✓ present | OUT OF SCOPE — single follow-up issue |
| OAuth provider row in GDPR §4.2 | ❌ absent | ✓ present | OUT OF SCOPE — same follow-up issue |

## Domain Review

**Domains relevant:** Legal (CLO), Product (CPO sign-off only).

### Legal (CLO)

**Status:** reviewed
**Assessment:** Four validated findings (Q1-Q4). The Q1 "Art. 13(3) latent-exposure window" framing was reframed to "deliberate operator decision" at plan-time after the operator confirmed the flag-flip was intentional with PR-C in flight (see Research Reconciliation row 3). The other three findings remain in effect:

- **Q2 SIGKILL placement (P1):** co-locate the limitation with the affirmative claim in §4.7 (EDPB Guidelines 01/2022 adjacency doctrine). Reject standalone §7 placement. Cross-ref from §8.1. Draft phrasing (≤25 words, factual): *"In rare cases of unexpected service interruption (e.g., kernel-level process termination or container restart) after generation but before persistence completes, a small portion of an in-progress reply may not be retained in the conversation record."* (Phrasing revised from the CLO original "the Service has no record of such content" per Kieran C3 — Sentry breadcrumbs may capture partial text outside the conversation record, so "no persisted copy in the conversation record" is the load-bearing precision.)
- **Q3 Supabase processor row:** no new processor disclosure required. Existing DPA (signed 2026-03-19, eu-west-1, SCCs M2+M3) covers any column on existing tables — processing-activity-bound, not column-bound. Vendor DPA table Supabase Notes column gets an evidentiary appendage.
- **Q4 W7 DSAR audit table form:** use **Completed Compliance Work** row form. Channels in scope: `legal@jikigai.com` inbox, GitHub `label:legal` + Art. 15 body search, Linear `Art. 15 OR DSAR` search, Discord completeness-only flag. Write evidence file (load-bearing per CLO Q4 — null result still answers the regulator question "did you check?"). Phase 7 step 1 also verifies the Privacy Policy contact-channel list at audit time to bound channel completeness.

### Product/UX Gate

**Tier:** none — no UI surface. CPO sign-off requirement at plan-time per `requires_cpo_signoff: true` (USER_BRAND_CRITICAL framing), not a UX-tier classification. CPO concern from brainstorm-time (user-facing trust framing of SIGKILL caveat) is carried into the §4.7 phrasing.

**Brainstorm-recommended specialists:** legal-document-generator (W6 edits), legal-compliance-auditor (post-edit verification + fix cycle). Both invoked during `/work`.

## Open Code-Review Overlap

**None.** Phase 1.7.5 scan against all open `label:code-review` issues returned zero matches for any PR-C file path.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — All forward-port targets present in BOTH `docs/legal/` and `plugins/soleur/docs/pages/legal/`** per the Research Reconciliation gap table. Each row of the table maps to one or more sections (Privacy Policy §4.7/§7/§8.1, DPD §2.1b(c)/§2.3(i)/§4.2 Supabase row, T&C §5.5, GDPR Policy §3.7/§4.2/§8.4/§9/§10/§11.2). KB-sharing and OAuth provider rows excluded per the OUT OF SCOPE label.
- [ ] **AC2 — Extensions applied to both copies** of Privacy Policy §4.7 and DPD §2.3(i): (a) `usage` jsonb (token consumption + cost metadata, written when `CC_PERSIST_USAGE` operator config enabled) appended to data list; (b) SIGKILL transparency sentence (CLO Q2 revised phrasing) as final sentence of §4.7 Conversation-data bullet only. Privacy Policy §8.1 gets the one-line cross-ref to §4.7 limitation in both copies.
- [ ] **AC3 — GDPR Policy §10 Article 30 register lists ten processing activities** in BOTH copies, with monotonic numbering 1→10 (verified via `awk '/^[0-9]+\./{print substr($1,1,length($1)-1)}'` returning the sequence `1 2 3 4 5 6 7 8 9 10` exactly). Activity #10 = Web Platform conversation management with `usage` appendage and SIGKILL data-completeness caveat in Notes. Activity-count line ("nine"→"ten") updated.
- [ ] **AC4 — Cross-document content-body parity** verified via Test Strategy script (below). Frontmatter / hero-wrapper / link-form / email-autolink differences ignored; content-body identity verified for the conversation-data + `usage` + SIGKILL sections.
- [ ] **AC5 — `legal-compliance-auditor` returns 0 findings at the agent's own P0 severity** after at most one fix-reaudit cycle. P1/P2 deferred to follow-up issue. "P0 at the agent's own taxonomy" is the explicit alignment per Kieran P2b.
- [ ] **AC6 — Pre-edit `awk` enumeration of letter/number ordering** committed inline to plan as evidence (per R8 hallucination-defense step). For each touched section: source-side ordering BEFORE edit + target-side ordering BEFORE edit + target-side ordering AFTER edit. No persistent evidence file — output pasted into the relevant commit message footer per DHH ceremony cut.
- [ ] **AC7 — Eleventy mirror dual Last-Updated lines updated** for each touched plugin-mirror doc (hero `<p>Last Updated: …</p>` AND body `**Last Updated:** …`) per learning `2026-03-20-eleventy-mirror-dual-date-locations.md`. Both lines advance to `2026-05-12` with one-line summary of changes.
- [ ] **AC8 — `compliance-posture.md` updated:** `last_updated` frontmatter to `2026-05-12`; Legal Documents table dates advanced for Privacy Policy, DPD, GDPR Policy, T&C; Vendor DPA Supabase Notes appendage (`usage` jsonb column added 2026-05-12 PR #3648, processing-activity-bound DPA scope); **two Completed Compliance Work rows**: (a) W7 DSAR cohort audit determination + evidence-file reference, (b) **deliberate operator flip of `CC_PERSIST_USAGE=true` on [verified-date], accepting disclosure-in-flight posture; PR-C #3662 closes disclosure side**.
- [ ] **AC9 — W7 DSAR cohort audit performed.** Window 2026-05-05 → 2026-05-11. Channels checked: `legal@jikigai.com` inbox (operator manual step), `gh issue list --label legal --state all --search "created:2026-05-05..2026-05-11"`, Linear `Art. 15 OR DSAR`, Discord support channel completeness-only. Result count recorded. Evidence file `knowledge-base/legal/audits/2026-05-12-w7-dsar-cohort-audit.md` written (load-bearing per CLO Q4 — null result is itself the audit answer). If ≥1 export found in window, supplementary disclosure draft prepared per task-description phrasing.
- [ ] **AC10 — `/soleur:gdpr-gate` Phase 2.7 invoked** — done at plan-time, outcome at `knowledge-base/legal/audits/2026-05-12-gdpr-gate-plan-phase-2-7-outcome.md`. Phase 9 work-phase 2 exit re-invocation runs at end of `/work`; outcome captured inline in PR body (no separate evidence file per code-simplicity feedback). Phase 5.5 ship-time reserved for `/ship`.
- [ ] **AC11 — `Ref #3603`, NOT `Closes #3603`,** in PR body. Umbrella closes only after live-on-prod verification (OP-list below).
- [ ] **AC12 — PR body includes "Operator handoff" callout** with one paragraph: "Post-merge, verify PR-C content live on app.soleur.ai and soleur.ai legal docs; smoke-test one cc-soleur-go conversation to confirm `messages.usage` writes are documented by current disclosure; then `gh issue close 3603`. A single follow-up issue covers the canonical-vs-plugin KB-sharing + OAuth-provider gaps (out of PR-C scope)."
- [ ] **AC13 — One follow-up issue created** before PR-C is marked Ready: "Forward-port canonical-vs-plugin legal-doc backlog (KB-sharing §4.8/§8.1c/§3.8 + OAuth provider row in GDPR §4.2)" labeled `domain/legal` + `priority/p3-low`, referencing this PR.

### Post-merge (operator handoff)

- [ ] **OP1 — Verify PR-C content live on prod.** Confirm canonical `docs/legal/privacy-policy.md` §4.7 Conversation-data bullet renders at https://soleur.ai/legal/privacy-policy/ AND at https://app.soleur.ai/legal/privacy-policy/. Record verification timestamp.
- [ ] **OP2 — Smoke test.** Open one cc-soleur-go conversation post-merge. Verify via service-role DB query that the next assistant-turn row has `messages.usage` populated as jsonb (since flag is already `true`, the smoke test confirms continuity, not a fresh activation).
- [ ] **OP3 — Close umbrella issue.** `gh issue close 3603` after OP1-OP2.

## Implementation Phases

### Phase 1 — Pre-edit hygiene + parity baseline

1. **Inline grep inventory** (not an evidence file per DHH/simplicity feedback). Run, before any edit:
   ```bash
   rg -n 'accumulatedAssistantText|saveAssistantMessage|cc-soleur-go' docs/legal plugins/soleur/docs/pages/legal && \
   rg -n 'volatile session storage|session-only|does not retain|transient|does not collect|does not store' docs/legal plugins/soleur/docs/pages/legal && \
   rg -n 'Last Updated|Effective Date' plugins/soleur/docs/pages/legal
   ```
   Expected: zero hits on internal symbols in legal copy (false-statement check), zero hits on `volatile session storage` / `session-only` (the framing PR-C overwrites), two hits per touched plugin-mirror doc on `Last Updated` (hero + body). Output pasted into commit message footer.
2. **Parity baseline:** record `git diff main -- docs/legal plugins/soleur/docs/pages/legal` is empty before edits.

### Phase 2 — Forward-port and extend all four document pairs

One phase, one logical scope. Per DHH: "edit doc A, edit doc B, edit doc C, edit doc D is the same operation four times." Phase 2 covers all of W6.1-W6.5 (Privacy Policy + DPD + GDPR Policy + T&C) and applies the `usage` + SIGKILL extensions.

**Edit order:** source-first (plugin mirror), mirror-second (canonical), per learning `2026-03-02-legal-doc-bulk-consistency-fix-pattern.md`.

**Per-edit hallucination defense** (R8 mitigation per Kieran P1c): before each insertion into a numbered/lettered list (DPD §2.3, GDPR §10), run `awk '/^### <section>/,/^---/{ if (/^- \*\*\([a-z]\)\*\*/ || /^[0-9]+\./) print NR": "$0 }'` on BOTH source and target. Paste output into commit message footer. After insertion, re-run on target only and confirm monotonic ordering. This is the standing defense against the next sub-agent / future-author letter/number-claim hallucination.

**Commit discipline:** one commit per touched doc pair (4 commits in Phase 2). Each commit pairs canonical + plugin-mirror edits for the same doc.

**Sections touched per the gap table:**

- **Privacy Policy:** §4.7 (full Conversation-data bullet forward-port + `usage` appendage + SIGKILL final sentence), §7 (retention conversation + cascade), §8.1 (cross-ref to §4.7 limitation).
- **DPD:** §2.1b(c) (data list mention), §2.3(i) (new letter item, full conversation-management activity + `usage` appendage; canonical §4.2 cross-ref line updated to add `, 2.3(i)`), §4.2 (Supabase row data column).
- **T&C:** §5.5 (full Metered Usage and Partial Consumption section — three bullets — forward-port to canonical; plugin mirror already has it).
- **GDPR Policy:** §3.7 (conversation management entry + `usage` appendage), §4.2 (Supabase row data column — conversation columns only; OAuth provider deferred), §8.4 (retention conversation + cascade), §9 (DPIA re-evaluation note for conversation + `usage`), §10 (Article 30 register activity #10 + monotonic-renumbering check + `usage` appendage + SIGKILL data-completeness Notes), §11.2 (conversation breach scenario).

**Per-doc Last-Updated update:** both hero + body lines in plugin-mirror copies advance to `2026-05-12` with one-line summary of changes per the existing convention.

### Phase 3 — Run `legal-compliance-auditor` + fix cycle

After Phase 2's four commits land, invoke `legal-compliance-auditor` with scope: "Audit `docs/legal/` and `plugins/soleur/docs/pages/legal/` for cross-document consistency. Verify the conversation-data + `usage` + SIGKILL claims are consistent across all four document pairs. Verify no doc references `volatile session storage` or `session-only` framing for cc-soleur-go data."

Expect 4-8 findings on first pass (normal per learning `2026-02-20-dogfood-legal-agents-cross-document-consistency.md`). Address P0/P1 inline; defer P2/P3 to the consolidated follow-up issue (AC13). Re-run. Final pass returns 0 P0 findings per AC5.

### Phase 4 — W7 DSAR audit + `compliance-posture.md` updates + AC13 follow-up issue

1. Run the DSAR cohort audit per AC9. Write the evidence file (load-bearing per CLO Q4). If any export found in window, prepare supplementary disclosure draft.
2. Update `compliance-posture.md` per AC8 (frontmatter date, Legal Documents table dates, Vendor DPA Supabase Notes appendage, **two** Completed Compliance Work rows).
3. File the single consolidated follow-up issue per AC13.

### Phase 5 — `/work` Phase 2 exit GDPR-gate + PR body authoring

Invoke `/soleur:gdpr-gate` against the diff. Capture outcome inline in PR body (no separate evidence file per code-simplicity feedback). Expected: 0 BLOCKers (PR-C is the *close* of the Art. 13(3) gap, not the introduction of one; the operator-decision framing was confirmed at plan time so no Art. 33 fork).

Author PR body per AC11 + AC12. Push to draft PR #3662; mark Ready when AC1-AC13 are checked.

## Files to Edit

- `docs/legal/privacy-policy.md` (§4.7, §7, §8.1)
- `docs/legal/data-protection-disclosure.md` (§2.1b(c), §2.3(i) — new letter item, §4.2 Supabase row, §4.2 cross-ref line)
- `docs/legal/terms-and-conditions.md` (§5.5 — new section forward-ported from plugin)
- `docs/legal/gdpr-policy.md` (§3.7, §4.2 Supabase row, §8.4, §9, §10 activity #10 + count line, §11.2)
- `plugins/soleur/docs/pages/legal/privacy-policy.md` (§4.7 `usage` + SIGKILL, §8.1 cross-ref)
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (§2.3(i) `usage` appendage)
- `plugins/soleur/docs/pages/legal/gdpr-policy.md` (§3.7 `usage` appendage, §10 activity #10 `usage` appendage + SIGKILL Notes)
- `knowledge-base/legal/compliance-posture.md` (frontmatter, Legal Documents table, Vendor DPA Supabase Notes, Completed Compliance Work two rows)

## Files to Create

- `knowledge-base/legal/audits/2026-05-12-w7-dsar-cohort-audit.md` (AC9 evidence — load-bearing per CLO Q4)
- (Conditional) `knowledge-base/legal/audits/2026-05-12-w7-supplementary-disclosure-draft.md` (only if W7 finds any in-window exports)

The Phase 2.7 GDPR-gate outcome file (`2026-05-12-gdpr-gate-plan-phase-2-7-outcome.md`) was written at plan-time before this revision; it remains in place. Phase 9 work-phase 2 exit outcome is captured inline in PR body, not a separate file.

## Test Strategy

Docs-only PR. Strategy is parity verification + auditor cycle.

1. **Pre-edit grep inventory** (Phase 1) — three-bucket classification, output in commit message footer.
2. **Per-edit `awk` ordering check** (per R8 defense step in Phase 2) — output in commit message footer.
3. **Content-body parity (AC4):**
   ```bash
   for doc in privacy-policy data-protection-disclosure terms-and-conditions gdpr-policy; do
     diff <(sed -E '
              1,/^---$/d            # drop frontmatter
              /^---$/d
              /<section class="page-hero">/,/<\/section>/d   # drop Eleventy hero
              /<section class="content">/d
              /<div class="container">/d
              /<div class="prose">/d
              /^<\/section>$/d
              /^\*\*Last Updated:/d  # last-updated drift is expected per-edit
              s|\(/legal/([a-z-]+)/\)|\1.md|g                # link form normalize
              s|<([^>]+@[^>]+)>|\1|g                         # email autolink strip
            ' "plugins/soleur/docs/pages/legal/$doc.md") \
          <(sed -E '
              1,/^---$/d
              /^---$/d
              /^\*\*Last Updated:/d
            ' "docs/legal/$doc.md") \
       && echo "$doc: content-body parity OK" \
       || echo "$doc: DIFFERS — inspect"
   done
   ```
   The `\1` references the `([a-z-]+)` capture group — corrected from the v1 plan's broken script that used `\1` against a non-capturing pattern (Kieran C1).
4. **GDPR §10 monotonic numbering (AC3):** `awk '/^## 10\. Record of Processing/,/^## 11\./{ if (/^[0-9]+\./) print substr($0, 1, index($0, ".")-1) }' docs/legal/gdpr-policy.md` returns the sequence `1 2 3 4 5 6 7 8 9 10`. Same against plugin mirror.
5. **`legal-compliance-auditor` pass** — at least one fix-reaudit cycle expected.
6. **GDPR-gate Phase 9 invocation** at end of `/work`.

## Risks / Sharp Edges

| ID | Severity | Risk | Mitigation |
|---|---|---|---|
| R1 | **P1** | Forward-port omits a section the auditor flags as inconsistent → auditor blocks PR. | Phase 3 budgets one fix-reaudit cycle. Phase 1 inline grep + Phase 2 per-edit `awk` ordering surface missed sections cheaply. |
| R2 | **P1** | SIGKILL phrasing undermines the persistence-claim's load-bearing strength. | Revised phrasing (≤25 words, "rare cases", "small portion", "not retained in the conversation record" — explicit about persistence-side limit, leaves Sentry-side breadcrumb behavior un-claimed). Plan-review and `legal-compliance-auditor` exercise this. |
| R3 | **P1** | W7 DSAR audit reveals an actual Art. 15 request in window that was answered without cc-soleur-go assistant content → supplementary disclosure required + backward-looking regulatory exposure. | Phase 4 step 1 conditional supplementary disclosure draft. Per CLO Q4. |
| R4 | **P2** | Operator changes `CC_PERSIST_USAGE` state between plan-time verification and PR-C live-on-prod (toggle back to `false`, or toggle to a new value). | Acceptable variance — the disclosure copy describes the behavior whether the flag is on or off ("when usage telemetry is enabled per operator configuration"). State changes do not invalidate the disclosure. Documented in AC8 row (b) as the operator-decision audit trail. |
| R5 | **P2** | Eleventy mirror dual Last-Updated lines missed in one of the touched plugin-mirror docs → docs-site renders stale date. | AC7 per-doc verification per learning. |
| R6 | **P2** | KB-sharing forward-port gap surfaces as a `legal-compliance-auditor` cross-document finding mid-edit, expanding scope. | AC13 single consolidated follow-up issue filed BEFORE auditor runs (Phase 3). Auditor invoked with scope explicitly bounded to "cc-soleur-go conversation-data + `usage` + SIGKILL"; KB-sharing findings classified as P2 deferred. |
| R7 | **P3** | Follow-up issue (AC13) sits in backlog indefinitely. | `priority/p3-low` + drain criterion: re-evaluate when next non-cc-soleur-go legal-doc PR opens. |

### Sharp-edge notes

- **`Ref #3603`, not `Closes #3603`** per the ops-remediation sharp-edge rule. Umbrella closes after OP1-OP3 verification, not at merge.
- **Doppler state verification at plan time** confirmed `CC_PERSIST_USAGE=true` in both `prd` and `prd_scheduled`. Operator confirmed this is deliberate. Plan handles the disclosure side; flip state is not gated by PR-C.
- **No new dependencies, no migrations, no security headers, no lockfile changes.** Preflight expects PASS/SKIP on all checks except the legal-document sensitive-path gate (Check 6 fires on `docs/legal/**` + `knowledge-base/legal/**`).
- **Labels prescribed:** `domain/legal`, `priority/p1-high`, `compliance/critical` (single-user-incident threshold), `semver:patch`. All four verified to exist via `gh label list --limit 200`.

## GDPR-Gate Plan Phase 2.7 Outcome

Invoked and captured at `knowledge-base/legal/audits/2026-05-12-gdpr-gate-plan-phase-2-7-outcome.md`. 0 Critical, 0 Important, 4 Suggestions (Art. 13(3) timing, Art. 30 register, Art. 9 classification, Art. 35 DPIA threshold). Disposition: plan proceeds to `/work`. The "latent-exposure window" framing in the v1 outcome file is amended to "deliberate operator decision" per Research Reconciliation row 3 (see the v2 amendment block appended to the outcome file).

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-12-feat-pr-c-legal-refresh-dsar-audit-plan.md

Context: branch feat-cc-transcript-hardening-prc-3603, worktree .worktrees/feat-cc-transcript-hardening-prc-3603, draft PR #3662, umbrella issue #3603.
Plan v2 complete (post-plan-review): 5 phases, 13 ACs, 7 risks. Phase 2.7 GDPR-gate already invoked (0 Critical, 4 Suggestions). Phase 5 GDPR-gate re-invocation at work-phase 2 exit. CPO sign-off needed at plan-time before /work. Implementation next.
```
