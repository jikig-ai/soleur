---
title: Team-Workspace Legal Scaffolding (ToS 2.2.0 + AUP §5.5 + DPD §2.3(u) + Privacy §4.11 + Side Letter)
status: planned
issue: 4284
brainstorm: knowledge-base/project/brainstorms/2026-05-22-feat-team-workspace-legal-scaffolding-brainstorm.md
spec: knowledge-base/project/specs/feat-team-workspace-legal-scaffolding/spec.md
branch: feat-team-workspace-legal-scaffolding
pr: 4289
source_pr: 4225
parent_umbrella: 4229
date: 2026-05-22
lane: cross-domain
brand_survival_threshold: single-user incident
requires_clo_signoff: true
requires_cpo_signoff: true
requires_cto_signoff: true
requires_adr: false
type: legal-scaffolding
---

# Plan — Team-Workspace Legal Scaffolding (PR #4289)

## Overview

Land the user-facing legal disclosures and Side Letter scaffolding that gate
`FLAG_TEAM_WORKSPACE_INVITE=1` per AC-LEGAL-FLIP
(`knowledge-base/legal/compliance-posture.md:95`). Source PR #4225 merged
2026-05-21 with schema + RLS + DSAR cascade; this PR ships ToS 2.2.0 §Workspace
Members + AUP §5.5 + DPD §2.3(u) + Privacy Policy §4.11 + Side Letter template
+ register + operator-attested counsel-review audit in one monolithic PR
(operator override of recommended split per brainstorm Key Decision #1).

Plan-review cuts applied (DHH + Kieran + code-simplicity): dropped ADR-039
(brainstorm Key Decision #1 + counsel-review audit §4 cover the decision
record); dropped middleware `?prev=` query-param threading (banner predicate
reads server-side from `tc_accepted_version`); collapsed Side Letter register
schema 6→3 columns; consolidated phases 12→8.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| FR6: Side Letter at `docs/legal/side-letter-template.md` | LIA precedent (PR #4051) puts internal compliance docs in `knowledge-base/legal/`; Eleventy may auto-pick up `docs/legal/` files | Move template to `knowledge-base/legal/side-letter-template.md`; canonical-only; not Eleventy-served |
| Counsel audit at `2026-05-22-counsel-review-team-workspace.md` | Precedents #4051 + #4066 use `YYYY-MM-counsel-review-<PR>.md` | Rename to `knowledge-base/legal/audits/2026-05-counsel-review-4289.md` |
| FR1 indemnification covers co-member access | CLO + SpecFlow (d-iii) surfaced #4231 audit-log scope-bleed (recipient_id_hash, body_sha256, template_hash become co-member-visible) | FR1 expanded — indemnification explicitly extends to send-audit-ledger visibility (the #4231 carve-out) |
| FR9: `/accept-terms` disclosure "location TBD" | SpecFlow (a-iii): page exists at `apps/web-platform/app/(auth)/accept-terms/page.tsx`; current copy is generic ("review and accept our terms"); no Art. 13(3) "what changed" disclosure | FR9 upgraded to require literal "§Workspace Members" string + Last-Updated date + link to canonical ToS in the page copy; AC asserts via `accept-terms-copy-regression.test.tsx` |
| TR8: "no new code paths" | SpecFlow (a-ii): `ws-handler.ts:1100-1230 recheckTcMidSession` is a separate TC-enforcement surface that fires immediately on TC_VERSION bump | Spec inherits "no new code paths" claim — verified via Phase 0 surface-parity grep (TC_VERSION readers at middleware + callback + ws-handler); no edits needed, surfaces already gate correctly |
| Eleventy mirror has ONE Last-Updated line | Learnings #2: mirror has BOTH hero `<p>Last Updated: ...</p>` AND body `**Last Updated:** ...`; `legal-doc-consistency.test.ts:122-134` enforces both via separate regexes | All 4×{canonical, mirror-body, mirror-hero} = 12 date sites updated to `May 22, 2026` in lockstep |
| Repo-research agent claimed `TC_VERSION = "1.0.0"` and "no precedent PR bumped TC_VERSION" | Direct read of `apps/web-platform/lib/legal/tc-version.ts:14` shows `"2.1.0"`; PR #4065 (PR-H precursor) bumped `2.0.0 → 2.1.0` per `compliance-posture.md:7` | Bump path is `2.1.0 → 2.2.0` per brainstorm Key Decision #1 + spec G2. Repo-research finding discarded as hallucination |
| Repo-research suggested next PA = PA-19 | This PR is NOT adding a new processing activity; it updates disclosure surface for the existing PA-2 (workspace co-member, added by #4225) | No PA-19 needed; Phase 8.2 updates existing PA-2 forward-looking text only |
| TC enforcement surfaces = 3 per SpecFlow (a-ii) | Repo-research found 4: middleware:175-177, `app/(auth)/callback/route.ts:32`, `server/ws-handler.ts:321` (+`:1100-1230 recheckTcMidSession`), `app/api/accept-terms/route.ts:44,53` | Phase 0.5 verifies 4 surfaces (callback added); AC17 updated to 4 |
| Canonical `docs/legal/*.md` Last-Updated dates are stale on main (March 20, 2026 / February 20, 2026) vs. mirrors at May 21, 2026 | Repo-research finding: precedent PRs only updated mirrors; canonical drift accumulated | Side effect of this PR: Phase 1.3 + 3.3 + 4.3 + 5.3 all update canonical Last-Updated lines to `May 22, 2026`, closing the drift gap |

## Files to Edit

Canonical legal docs (`docs/legal/`):
- `docs/legal/terms-and-conditions.md` — add §Workspace Members (~150-250 words) with 3 sub-clauses: (a) owner-as-controller framing, (b) co-member access under owner's account, (c) owner indemnification including audit-log scope-bleed carve-out. Update `**Last Updated:**` body line + change-summary parenthetical.
- `docs/legal/acceptable-use-policy.md` — append §5.5 "Workspace member attestation" (owner attests invitees under employment/contractor agreement until customer-DPA ships). Update Last Updated.
- `docs/legal/data-protection-disclosure.md` — append §2.3(u) "Workspace co-member data category" mirroring §2.3(t) style; add carve-out clause in §4.2 footer ("co-members are NOT processors under Article 28; access is contract-mediated under §C of Anthropic Commercial Terms"). Update Last Updated.
- `docs/legal/privacy-policy.md` — append §4.11 "Workspace co-members" parallel to §4.10 LinkedIn pattern; add recipient note at §4.7 workspace-data block. Update Last Updated.

Eleventy mirrors (`plugins/soleur/docs/pages/legal/`):
- `plugins/soleur/docs/pages/legal/terms-and-conditions.md` — sync body + update hero AND body dates
- `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` — sync body + update both dates
- `plugins/soleur/docs/pages/legal/data-processing-disclosures.md` (NOTE: plural in mirror) — sync body + update both dates
- `plugins/soleur/docs/pages/legal/privacy-policy.md` — sync body + update both dates

Code:
- `apps/web-platform/lib/legal/tc-version.ts` — bump `TC_VERSION = "2.2.0"` (line 14); refresh `TC_DOCUMENT_SHA = "<sha256-of-canonical-ToS>"` (line 35)
- `apps/web-platform/app/(auth)/accept-terms/page.tsx` — add Art. 13(3) change-summary banner above existing form. Reads `tc_accepted_version` server-side (Server Component / `getServerSession()` equivalent); renders iff prior version is non-null AND not equal to `TC_VERSION`. NO middleware edit (per DHH+Simplicity+Kieran plan-review reconciliation).

Tests:
- `apps/web-platform/test/accept-terms-copy-regression.test.tsx` — extend to assert the new change-summary banner copy (literal "Workspace Members" + literal "May 22, 2026")

KB artifacts:
- `knowledge-base/legal/compliance-posture.md` (line 95) — narrow AC-LEGAL-FLIP "Remaining" cell to Doppler-only (`FLAG_TEAM_WORKSPACE_INVITE=1` + `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS`)
- `knowledge-base/legal/article-30-register.md` (lines 62-67) — remove forward-looking "Flag-flip ON blocked on AC-LEGAL-FLIP" sentence; replace with past-tense reference to the merged legal-PR

GitHub artifacts:
- #4231 issue body — append note that ToS 2.2.0 indemnification already absorbs audit-log scope-bleed carve-out so no ToS bump needed when audit-log lands

## Files to Create

- `knowledge-base/legal/side-letter-template.md` — bespoke template (confidentiality + IP assignment + workspace-activity-logged + audit-log visibility acknowledgement). Jurisdiction token MUST be `RCS Paris` (single token per `legal-doc-consistency.test.ts:137-189` invariant). Signature block uses "Jikigai" (legal entity), not "Soleur" (product). Canonical-only — NOT added to `DOCS` const at `legal-doc-consistency.test.ts:29-35` (per brainstorm Open Question Q3).
- `knowledge-base/legal/side-letter-register.md` — counterparty signature ledger; mirrors `tenant-dpa-register.md` shape. **3-column schema** (cut from 6 per code-simplicity P1; remaining columns added when their first row makes them necessary): `| Counterparty | Workspace ID | Signed at |`. PDF stored off-repo (encrypted operator drive); external-counsel-trigger state derivable from the audit file.
- `knowledge-base/legal/audits/2026-05-counsel-review-4289.md` — operator-attested counsel review (Jean as Jikigai SARL gérant). Structure cloned from `audits/2026-05-counsel-review-4066.md` (richer 5-artifact template). Sections: (1) Artifacts reviewed, (2) Operator attestation, (3) External counsel re-review triggers (≥2: first non-Jikigai-affiliate invitee; any invitee outside the EEA), **(4) Decision record (per DHH plan-review): brief summary of the monolithic-vs-split decision + rationale + canonical-date-drift fix consequence** (replaces dropped ADR-039).

## User-Brand Impact

**If this lands broken, the user experiences:** Re-acceptance loop without
explanation (page redirects but doesn't say what changed) OR rejected Art-15
DSAR because owner-as-controller framing is unclear OR ToS §Workspace Members
indemnification clause is missing the audit-log scope-bleed carve-out and the
inviting owner is later sued by a co-member over their `action_sends` rows.

**If this leaks, the user's data is exposed via:** Privacy Policy §4.11
missing recipient disclosure at flag-flip time (Art. 13(1)(e) gap); ToS
§Workspace Members §C-misalignment with Anthropic's "authorized users" clause;
co-member `recipient_id_hash` exposure path that ToS indemnification fails
to cover.

- **Brand-survival threshold:** `single-user incident`.

The `user-impact-reviewer` agent at PR review is the load-bearing gate.
CPO sign-off captured in brainstorm + reaffirmed by carry-forward in this
plan. CLO + CTO carry-forward sign-offs in `Domain Review` below.

## Domain Review

**Domains relevant:** Product, Legal, Engineering (carried forward from
brainstorm `## Domain Assessments`).

### Product (CPO)

**Status:** carry-forward
**Assessment:** Approved with operator override on PR shape (monolithic over
recommended split). Off-platform Side Letter PDF; no click-to-attest in v1.
Threshold conceptually drops to "no operator harm beyond doc drift" for a
doc-only PR, but operator chose monolithic which couples ToS body change to
TC_VERSION re-acceptance — parent `single-user incident` threshold carried
forward for that reason.

### Legal (CLO)

**Status:** carry-forward
**Assessment:** DPD §2.3 was NOT covered by #4225 (PA-2 row in article-30-
register.md is the internal Art-30 register, not the user-facing DPD).
TC_VERSION bump = MINOR `2.1.0 → 2.2.0`. Side Letter has no artifact home yet —
new `knowledge-base/legal/side-letter-register.md` mirrors
`tenant-dpa-register.md`. Counsel posture: operator-attested per #4081/#4066/
#4213 precedent. **Privacy Policy ALSO needs Art. 13(1)(e) recipient
amendment in lockstep — DPD alone is not the user-facing notice surface.**
Brand-survival risk #4231 scope-bleed: workspace_member_actions audit-log
will expose member A's `action_sends` rows to member B; ToS 2.2.0
indemnification must explicitly extend to co-member access to send-audit
ledgers.

### Engineering (CTO)

**Status:** carry-forward
**Assessment:** Middleware re-acceptance fires unconditionally on TC_VERSION
mismatch (`apps/web-platform/middleware.ts:175-177` — no flag guard).
TC_DOCUMENT_SHA is scoped only to ToS canonical
(`check-tc-document-sha.sh:112,187`). DSAR allowlist already covers the 4
workspace tables (`dsar-export-allowlist.ts` lines 151-178). Doc-only PR
sharp edges: RCS-jurisdiction invariant, sentinel-string regression,
`**Last Updated:**` regex strictness, Eleventy build doesn't validate
cross-doc links. ADR recommended.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline) — `/accept-terms` page edit is copy
addition to an existing page; no new components/routes; mechanical
classification = ADVISORY. Brainstorm-recommended copywriter: not invoked
(operator-attested counsel will own copy). The `accept-terms-copy-regression`
test extension is the load-bearing gate on the new copy literal.
**Agents invoked:** none
**Skipped specialists:** ux-design-lead (N/A — no wireframes needed for
copy-only banner), copywriter (operator owns)
**Pencil available:** N/A

## Infrastructure (IaC)

N/A — doc-only PR + version literal + a copy edit to an existing page. No
new infrastructure surface (server, systemd, cron, vendor account, DNS, TLS,
secret, firewall, monitoring webhook). Doppler flip is post-merge operator
action and lives in a SEPARATE flag-flip PR per brainstorm Key Decision #1.

## Observability

```yaml
liveness_signal:
  what: tc_acceptances row count for version 2.2.0
  cadence: monotonically increasing post-merge as users re-accept
  alert_target: none required (re-acceptance is expected, not anomaly)
  configured_in: apps/web-platform/supabase/migrations/<TC_VERSION-acceptance-ledger>.sql + existing /api/accept-terms route
error_reporting:
  destination: Sentry (existing wiring at /api/accept-terms + middleware)
  fail_loud: true (middleware redirects to /accept-terms?error=db_unavailable on Supabase outage; user sees outage banner per page.tsx:18-22)
failure_modes:
  - mode: TC_DOCUMENT_SHA drift (canonical edited without literal refresh)
    detection: .github/workflows/ci.yml :: tc-document-sha-guard (line 106)
    alert_route: CI red on PR; gates merge
  - mode: Eleventy mirror canonical-vs-mirror parity drift
    detection: apps/web-platform/test/legal-doc-consistency.test.ts (heading sequence, Last-Updated, sentinel strings, RCS-jurisdiction)
    alert_route: CI red on PR; gates merge
  - mode: tc_acceptances WORM trigger rejects UPDATE/DELETE outside the Art-17 anonymise RPC
    detection: existing WORM trigger from tc-version-bump-policy.md:127-130
    alert_route: Postgres error → Sentry
  - mode: middleware TC version comparison fails open (e.g., db_unavailable)
    detection: middleware.ts redirect to /accept-terms?error=db_unavailable
    alert_route: outage banner to user; Sentry capture in middleware
logs:
  where: tc_acceptances table (Postgres) + Sentry events
  retention: indefinite as append-only audit record; Art-17 anonymise RPC for erasure cascade
discoverability_test:
  command: curl -fsS -o /dev/null -w "%{http_code}" --max-time 10 https://app.soleur.ai/accept-terms
  expected_output: "200 or 307"
  operator_runbook: |
    psql query against the audit ledger (run from a shell with DATABASE_URL set in Doppler dev/prd):
      psql -c "select count(*) from tc_acceptances where version = '2.2.0';"
    post-merge: 0 then monotonically increasing as users re-accept; cap at registered user count.
```

NO ssh-based verification needed; all signals are API/CI/SQL queryable.

## Implementation Phases

### Phase 0 — Preconditions / Verifications (≤45 min)

0.1. Read sentinel list in `apps/web-platform/test/legal-doc-consistency.test.ts:80-113`. Confirmed sentinel set covers ~14 fragments across CLA preambles + Privacy §5.11 + DPD §2.3(n)/Cloudflare/FreeTSA + GDPR §3.4. Adding NEW sections (§Workspace Members, §5.5, §2.3(u), §4.11) does NOT touch existing sentinels; safe.

0.2. Verify `legal-doc-consistency.test.ts:137-189` RCS-jurisdiction token. Canonical = `RCS Paris 927 585 729` (per `docs/legal/data-protection-disclosure.md:177`). Side Letter MUST use this exact form; NO secondary RCS-city token anywhere in the template (e.g., a "Counterparty: ___ (RCS Lyon)" placeholder would fail `tokens.size === 1`).

0.3. Confirmed letter sequences: DPD §2.3(u) next free (a-t taken); Privacy Policy §4.11 next free (§4.1-§4.10 taken); AUP §5.5 next free (§5.1-§5.4 taken).

0.4. **TC enforcement surface parity grep** (SpecFlow a-ii + repo-research g + Kieran P1-4): `rg "tc_accepted_version|TC_VERSION" apps/web-platform/` and verify 4 surfaces gate correctly:
- `apps/web-platform/middleware.ts:175-177` (HTTP redirect — `userRow?.tc_accepted_version !== TC_VERSION`)
- `apps/web-platform/app/(auth)/callback/route.ts:32` (OAuth callback enforcement)
- `apps/web-platform/app/api/accept-terms/route.ts:44,53` (POST handler / acceptance writer)
- `apps/web-platform/server/ws-handler.ts:321` and `:1100-1230` (`recheckTcMidSession` — 30s cache)

**Document not just line numbers but the 4 comparison expressions** side-by-side in the PR body — confirm they are semantically equivalent (string-equal against `TC_VERSION` constant, no semver-`<` comparison, no `null` treated as "accepted"). The 30s ws-handler cache window IS an accepted operator-experience tradeoff (Q-IMPORTANT-5 deferred).

0.5. Read `apps/web-platform/app/(auth)/accept-terms/page.tsx` lines 1-60 to confirm form shape and decide banner insertion point (above existing `<p>` description; reuse `outageBanner`'s `rounded-lg border` pattern). Note the page already calls `useSearchParams()` for `?error=db_unavailable`; the banner uses server-side data, not a query param.

### Phase 1 — Draft 4 Legal Docs + Sync 4 Mirrors (consolidates old Phases 1-5)

For each of the 4 canonical docs, the steps are isomorphic: append the new section, update `**Last Updated:** May 22, 2026 (<change summary>)`, sync the Eleventy mirror at the matching path (note DPD mirror has plural filename `data-processing-disclosures.md`), update both mirror dates (body `**Last Updated:**` AND hero `<p>Last Updated: ...</p>` per learnings #2).

1.1. **ToS 2.2.0 §Workspace Members** — `docs/legal/terms-and-conditions.md` + mirror. New top-level §Workspace Members (insertion at next-free numbered section, ~150-250 words) with 3 sub-clauses:
- (a) **Workspace owner is the controller.** Co-members access under owner's account; their actions are attributable to the owner under Anthropic Commercial Terms §C "authorized users" clause.
- (b) **Co-member visibility scope.** Co-members are recipients of one another's metadata for in-workspace conversations they participate in; each retains independent Art-15/17/20 rights.
- (c) **Owner indemnification including audit-log carve-out.** Owner indemnifies Jikigai for any third-party claim arising from co-member access, including co-member access to the workspace's send-audit ledger (`workspace_member_actions` per #4231; `action_sends` recipient_id_hash, body_sha256, template_hash; template_authorizations rows). Indemnification extends to co-member ↔ co-member tort claims.

1.2. **AUP §5.5 Workspace member attestation** — `docs/legal/acceptable-use-policy.md` + mirror. ~80-120 words: owner attests every invitee is under employment/contractor/consultancy agreement obligating confidentiality + IP assignment equivalent to the Side Letter template. Attestation in force until Jikigai publishes a customer-facing DPA (brainstorm Non-Goal N1).

1.3. **DPD §2.3(u) + §4.2 carve-out** — `docs/legal/data-protection-disclosure.md` + mirror (`data-processing-disclosures.md`, plural). §2.3(u) "Workspace co-member data category" mirrors §2.3(t) shape (~120-180 words): data processed (user_id of co-member, workspace_id, cross-member conversation metadata), legal basis Art. 6(1)(b), retention (until Art-17 cascade), no new sub-processors, RLS via `is_workspace_member()` as Art. 32 TOM. §4.2 footer adds carve-out: "Workspace co-members are NOT processors under Article 28; access is contract-mediated under Anthropic Commercial Terms §C. See §2.3(u)."

1.4. **Privacy Policy §4.11 Workspace co-members + §4.7 recipient note** — `docs/legal/privacy-policy.md` + mirror. §4.11 parallel to §4.10 LinkedIn pattern (~120-180 words) with **dual-perspective coverage** (SpecFlow c-iii):
- From owner's perspective: when you invite a co-member, their conversations/KB queries/BYOK usage/action_sends become visible to you.
- From co-member's perspective: if you accept an invitation, your activity is visible to the workspace owner and other co-members. Owner is controller; your Art-15/17/20 over your own rows is unaffected.

Add recipient note at §4.7 (workspace-data block): "Workspace co-members are recipients within the meaning of Art. 13(1)(e) GDPR. See §4.11 for the bilateral disclosure."

### Phase 2 — TC_VERSION + TC_DOCUMENT_SHA Bump

2.1. After all Phase 1 edits are final + committed, run `sha256sum docs/legal/terms-and-conditions.md` from worktree root. Record the 64-char lowercase hex.

2.2. Edit `apps/web-platform/lib/legal/tc-version.ts`:
- Line 14: `export const TC_VERSION = "2.2.0";`
- Line 35: `export const TC_DOCUMENT_SHA = "<sha-from-2.1>";`

2.3. Run `bash apps/web-platform/scripts/check-tc-document-sha.sh` locally; expect exit 0. If exit non-zero, re-run sha256sum and re-update the literal (ToS may have been touched in a later commit).

### Phase 3 — Side Letter Template + Register

3.1. Create `knowledge-base/legal/side-letter-template.md`. Sections: header (title, `Template version: 1.0.0 — May 22, 2026`, `Governed by French law; jurisdiction: RCS Paris`), §1 Confidentiality (mutual, 5-year survival), §2 IP Assignment (work product to Jikigai; pre-existing IP carve-out), §3 Workspace-activity-logged acknowledgement (invitee acknowledges owner sees all conversations + KB queries + action_sends + template_authorizations + #4231 workspace_member_actions), §4 Audit-log visibility (explicit acknowledgement of recipient_id_hash + body_sha256 + template_hash cross-member visibility per ToS 2.2.0 §Workspace Members(c)), §5 Termination + post-termination obligations. Signature block: "Jikigai SARL (RCS Paris 927 585 729) — gérant: ___" + "Counterparty: ___" with date lines.

3.2. Create `knowledge-base/legal/side-letter-register.md`. 3-column schema (per code-simplicity P1):

```markdown
# Side Letter Register

| Counterparty | Workspace ID | Signed at (ISO 8601) |
|---|---|---|
| (none yet) | | |
```

Single ledger file (not per-counterparty). PDF stored off-repo. PDF hash, template version, and external-counsel-trigger state derive from the audit file; columns added when needed.

### Phase 4 — /accept-terms Disclosure Banner

4.1. Edit `apps/web-platform/app/(auth)/accept-terms/page.tsx`. Insert a `<div role="status">` banner above the existing `<p>` description (page.tsx:50-54). Banner copy: "Updated May 22, 2026 — We've added a new **§Workspace Members** section covering the team-workspace feature. [Read the full Terms](/legal/terms-and-conditions)".

4.2. **Banner predicate** (per Simplicity P0 + Kieran P0-1): read `tc_accepted_version` server-side (Server Component or `getServerSession()` equivalent). Render banner iff `tc_accepted_version != null && tc_accepted_version !== TC_VERSION` — i.e., any returning user upgrading from a prior version sees the banner; first-time signups (null version) do not. **No middleware edit needed**; the page reads the same Supabase row middleware already read. This addresses Kieran P0-1: pre-2.1.0 users (if any) also see the banner.

4.3. Style: reuse the `rounded-lg border` pattern from `outageBanner` (page.tsx:64-67).

4.4. Update `apps/web-platform/test/accept-terms-copy-regression.test.tsx` to assert: when the rendered page receives a non-null prior version (test fixture), it contains literal strings "Workspace Members" AND "May 22, 2026" AND a link to `/legal/terms-and-conditions`; when prior version is null, none of these appear.

### Phase 5 — AC-LEGAL-FLIP + Article 30 PA-2 Updates

5.1. Edit `knowledge-base/legal/compliance-posture.md:95`. Narrow "Remaining" cell of AC-LEGAL-FLIP row to: "legal-PR #4289 merged 2026-05-22 with ToS 2.2.0 + AUP §5.5 + DPD §2.3(u) + Privacy Policy §4.11 + Side Letter template + register. AC-LEGAL-FLIP remaining precondition is **Doppler-only**: `FLAG_TEAM_WORKSPACE_INVITE=1` + `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS=<jikigai-org-id>`. Sweeper at `scripts/followthroughs/team-workspace-flag-flip-4284.sh` auto-closes #4284."

5.2. Edit `knowledge-base/legal/article-30-register.md:62-67` (PA-2 workspace-co-member block). Remove forward-looking "Flag-flip ON blocked on AC-LEGAL-FLIP (parallel legal-PR for ToS 2.2.0 / AUP §5.5 / DPD §2.3 / Side Letter must land first)." Replace with: "Legal scaffolding shipped in PR #4289 (2026-05-22): ToS 2.2.0 §Workspace Members, AUP §5.5, DPD §2.3(u), Privacy Policy §4.11, Side Letter template + register. Remaining precondition: Doppler flag-flip."

### Phase 6 — Counsel-Review Audit File

6.1. Create `knowledge-base/legal/audits/2026-05-counsel-review-4289.md`. **Clone structure from `knowledge-base/legal/audits/2026-05-counsel-review-4066.md`** (richer 5-artifact template). Sections:
- YAML frontmatter (`title`, `type: counsel-review`, `date: 2026-05-22`, `issue: 4284`, `pr: 4289`, `status: SIGNED-OFF (operator-attested)`, `signed_off_at`, `signed_off_by: Jean Deruelle (Jikigai SARL gérant)`, `re_evaluation_triggers` list).
- Body intro: load-bearing AC reference (this plan's AC for counsel sign-off) + "PR held in draft until all rows signed off".
- `## Artifact 1 — ToS 2.2.0 §Workspace Members` through `## Artifact 5 — Side Letter template + register` — each with File / Scope of review / Particular attention requested / 5-column sign-off table (Counsel | Date | Channel | Sign-off | Substantive comments).
- `## Operator attestation`: Verbatim phrase: "Jean Deruelle (Jikigai SARL gérant, operator-attested in lieu of external counsel review for v1 — Soleur-as-tenant-zero posture)".
- `## External counsel re-review triggers`: (i) first non-Jikigai-affiliate invitee; (ii) any invitee outside the EEA; (iii) any invitee belonging to a regulated industry (healthcare, finance).
- `## Decision record (replaces ADR-039)`: 2 paragraphs: (a) operator chose monolithic PR over recommended doc-only-now-ToS-later split; rationale = small user base, re-acceptance wave bounded, follow-up flag-flip PR becomes Doppler-only; (b) side effect: closes canonical-vs-mirror date drift introduced by prior PRs (#4065, etc.) that only refreshed mirrors.
- `## Post-sign-off operator actions`: `gh pr ready 4289` + `gh pr merge 4289 --squash --auto`.

### Phase 7 — Verify + Push + GDPR-gate

7.1. Run `/soleur:gdpr-gate` against this PR's diff. Expected findings null or minor (single-user-incident threshold fires per Phase 2.7 (b); no Art. 9 special-category writes; Art. 13(1)(e) coverage explicit in Privacy §4.11). Any Critical finding triggers operator-ack + `compliance-posture.md` Active Items write + GitHub issue `compliance/critical`.

7.2. Local verification:
- `bash apps/web-platform/scripts/check-tc-document-sha.sh` → exit 0
- `(cd plugins/soleur/docs && npm run build)` → Eleventy smoke; check `_site/legal/*.html` renders without 404s on internal links
- `cd apps/web-platform && npx vitest run test/legal-doc-consistency.test.ts test/accept-terms-copy-regression.test.tsx` → all green
- Re-compute `sha256sum docs/legal/terms-and-conditions.md` matches `tc-version.ts:35` literal (Simplicity hidden-assumption check)

7.3. Push and observe CI gates: `tc-document-sha-guard`, `legal-doc-cross-document-gate`, `scheduled-legal-audit`.

### Phase 8 — Review + Merge + Post-Merge Follow-Ups

8.1. Mark PR #4289 ready. `user-impact-reviewer` agent fires automatically per Phase 2.6 conditional-agent block.

8.2. Spawn parallel review agents: `pr-review-toolkit:code-reviewer`, `soleur:legal:legal-compliance-auditor` (full audit of 4 doc changes + Side Letter template + register). Address findings inline per `rf-review-finding-default-fix-inline`.

8.3. Merge via `gh pr merge 4289 --squash --auto`.

8.4. **Post-merge follow-ups** (automated where possible):
- Update #4231 issue body via `gh issue edit 4231` (Bash one-liner) noting ToS 2.2.0 indemnification absorbs audit-log scope-bleed carve-out.
- File 4 deferred follow-up issues (see "Deferred Follow-Up Issues" section below) via `gh issue create`.
- Doppler flag-flip remains operator-driven via a SEPARATE PR; sweeper `scripts/followthroughs/team-workspace-flag-flip-4284.sh` auto-closes #4284 when both Doppler keys are set.

### Phase 1 — Draft ToS 2.2.0 §Workspace Members

1.1. Read full `docs/legal/terms-and-conditions.md` to find insertion point. Place §Workspace Members at the next-free top-level numbered section (likely §N where current ToS ends).

1.2. Draft §Workspace Members body (~150-250 words) with 3 sub-clauses:
- (a) **Workspace owner is the controller.** The natural person (or legal entity) who creates an organization and invites members is the controller of all data processed under that workspace. Co-members access under the owner's account; their actions are attributable to the owner under the Anthropic Commercial Terms §C "authorized users" clause.
- (b) **Co-member visibility scope.** Co-members of a shared workspace are recipients of one another's metadata for in-workspace conversations they participate in. Each co-member retains independent Art-15/17/20 rights over their own identifiable rows.
- (c) **Owner indemnification.** Workspace owner indemnifies Jikigai for any third-party claim arising from co-member access, **including co-member access to the workspace's send-audit ledger** (`workspace_member_actions` per #4231; covers `action_sends` recipient_id_hash, body_sha256, template_hash, and template_authorizations rows). Indemnification extends to claims by co-members against the owner OR against other co-members for tortious use of shared-workspace audit data.

1.3. Update `**Last Updated:** May 22, 2026 (PR #4289 added §Workspace Members for the team-workspace feature; owner-as-controller framing, co-member access framing, owner indemnification including audit-log carve-out)` and preserve the prior change-summary parenthetical chain.

1.4. Sync `plugins/soleur/docs/pages/legal/terms-and-conditions.md`:
- Body §Workspace Members identical to canonical.
- Body `**Last Updated:** May 22, 2026` line identical.
- Hero `<p>Last Updated: May 22, 2026</p>` updated (per learnings #2 — TWO date locations).
- Heading sequence MUST match canonical (`legal-doc-consistency.test.ts:71-78`).

### Phase 2 — TC_VERSION + TC_DOCUMENT_SHA refresh

2.1. From the worktree root: `sha256sum docs/legal/terms-and-conditions.md` → record the 64-char lowercase hex.

2.2. Edit `apps/web-platform/lib/legal/tc-version.ts`:
- Line 14: `export const TC_VERSION = "2.2.0";`
- Line 35: `export const TC_DOCUMENT_SHA = "<sha-from-2.1>";`

2.3. Run `bash apps/web-platform/scripts/check-tc-document-sha.sh` locally; expect exit 0.

### Phase 3 — Draft AUP §5.5 Owner Attestation

3.1. Append `### 5.5 Workspace member attestation` to `docs/legal/acceptable-use-policy.md` (after §5.4 which closes at line varies — read at draft time).

3.2. Body (~80-120 words): the workspace owner attests that every invitee they add via the team-workspace feature is under an employment, contractor, or consultancy agreement that obligates them to confidentiality and IP assignment terms equivalent to the Side Letter template at `knowledge-base/legal/side-letter-template.md`. Attestation remains in force until Jikigai publishes a customer-facing DPA (tracked separately; see brainstorm Non-Goal N1).

3.3. Update `**Last Updated:**` body line. Sync mirror at `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` (body + hero dates).

### Phase 4 — Draft DPD §2.3(u) + §4.2 Carve-Out

4.1. Append `### 2.3(u) Workspace co-member data category` to `docs/legal/data-protection-disclosure.md` after §2.3(t) (line ~117 per current file). Body (~120-180 words) mirrors §2.3(t) style: data processed (user_id of co-member, workspace_id, conversation metadata visible cross-member), legal basis (Art. 6(1)(b) contract performance — workspace participation is contract-of-employment-mediated), retention (until co-member's Art-17 cascade), sub-processors (none new), cross-references (Article 30 PA-2; SECURITY DEFINER `is_workspace_member()` is the RLS load-bearing TOM per Art. 32).

4.2. Add carve-out note in DPD §4.2 (Web Platform Processors table footer at line ~179): "Workspace co-members are NOT processors under Article 28; their access is contract-mediated under the Anthropic Commercial Terms §C 'authorized users' framework. See §2.3(u)."

4.3. Update `**Last Updated:**` body line; preserve change-summary chain. Sync mirror at `plugins/soleur/docs/pages/legal/data-processing-disclosures.md` (note plural in mirror filename).

### Phase 5 — Draft Privacy Policy §4.11 + Recipient Note

5.1. Append `### 4.11 Workspace co-members` to `docs/legal/privacy-policy.md` after §4.10 (line ~166 per current file). Body (~120-180 words) parallel to §4.10 LinkedIn pattern. **Dual-perspective coverage** (per SpecFlow c-iii):
- **From the owner's perspective:** when you invite a co-member to your workspace, their conversations, KB queries, BYOK usage, and `action_sends` rows become visible to you as workspace owner.
- **From the co-member's perspective:** if you accept an invitation to join a workspace, your activity (conversations you participate in, KB queries you submit, sends you make under the workspace's grants) is visible to the workspace owner and to other co-members. The workspace owner is the controller; your Art-15/17/20 rights over your own identifiable rows are unaffected.

5.2. Add recipient note at §4.7 (workspace-data block, line ~97 per current file): "Workspace co-members are recipients within the meaning of Art. 13(1)(e) GDPR. See §4.11 for the bilateral disclosure."

5.3. Update both `**Last Updated:**` lines (body + hero). Sync mirror at `plugins/soleur/docs/pages/legal/privacy-policy.md`.

### Phase 6 — Side Letter Template + Register

6.1. Create `knowledge-base/legal/side-letter-template.md`. Sections:
- Header: Title, version (e.g., `Template version: 1.0.0 — May 22, 2026`), jurisdiction notice (`Governed by French law; jurisdiction: RCS Paris`).
- §1 Confidentiality (mutual; survives termination 5 years).
- §2 IP Assignment (work product assigned to Jikigai; carve-out for invitee's pre-existing IP).
- §3 Workspace-activity-logged acknowledgement (invitee acknowledges workspace owner has access to all conversations, KB queries, action_sends, template_authorizations, and — when #4231 lands — workspace_member_actions audit log).
- §4 Audit-log visibility (explicit acknowledgement that recipient_id_hash, body_sha256, template_hash become cross-member visible per ToS 2.2.0 §Workspace Members(c)).
- §5 Termination + post-termination obligations.
- Signature block: "Jikigai SARL (RCS Paris 927 585 729) — gérant: ___" and "Counterparty: ___" with date lines.

6.2. Create `knowledge-base/legal/side-letter-register.md`. **Explicit column schema** (closes SpecFlow b-iii):

```markdown
# Side Letter Register

| Counterparty | Workspace ID | Signed at (ISO 8601) | Template version | SHA-256 of executed PDF | External-counsel review trigger fired? |
|---|---|---|---|---|---|
| (none yet) | | | | | |
```

The register is a SINGLE ledger file (not per-counterparty files) — operator appends one row per executed Side Letter. PDF stored off-repo (encrypted operator drive).

### Phase 7 — /accept-terms Disclosure Copy (Art. 13(3) banner)

7.1. Edit `apps/web-platform/app/(auth)/accept-terms/page.tsx`. Insert a `<div role="status">` banner between the existing `<h1>` and `<p>` (lines ~50-54) with:
- Title: "Updated May 22, 2026"
- Body: "We've added a new **§Workspace Members** section covering the team-workspace feature. [Read the full Terms](/legal/terms-and-conditions)."
- Banner only renders for users whose `tc_accepted_version === '2.1.0'` (i.e., existing users); for first-time signups (no prior acceptance), banner is hidden. Detect via a server-side prop OR a `?prev=2.1.0` query param set by middleware redirect (simplest: check `searchParams?.get('prev')` — middleware adds `&prev=<version>` to the redirect target).

7.2. Banner styling: reuse the existing `rounded-lg border` pattern from `outageBanner` (page.tsx:64-67).

7.3. Update `apps/web-platform/test/accept-terms-copy-regression.test.tsx` to assert: when `prev=2.1.0` is present, the page renders literal strings "Workspace Members" AND "May 22, 2026" AND a link to `/legal/terms-and-conditions`.

7.4. Update middleware (`apps/web-platform/middleware.ts:175-177`) to append `?prev=${userRow.tc_accepted_version}` to the redirect URL. This is a 1-line change to thread the prior version into the banner predicate.

### Phase 8 — AC-LEGAL-FLIP + Article 30 PA-2 Updates

8.1. Edit `knowledge-base/legal/compliance-posture.md:95`. Narrow the "Remaining" cell of the AC-LEGAL-FLIP row:
- BEFORE: "Single-user-incident threshold. ... AC-LEGAL-FLIP blocks `FLAG_TEAM_WORKSPACE_INVITE=1` in any environment until the parallel legal-scaffolding PR (Phase 10, branch `feat-team-workspace-legal-scaffolding`) lands ToS 2.2.0 / AUP §5.5 / DPD §2.3 / Side Letter."
- AFTER: "Single-user-incident threshold. ... legal-PR #4289 merged 2026-05-22 with ToS 2.2.0 + AUP §5.5 + DPD §2.3(u) + Privacy Policy §4.11 + Side Letter template + register + ADR-039. AC-LEGAL-FLIP remaining precondition is **Doppler-only**: set `FLAG_TEAM_WORKSPACE_INVITE=1` in prd Doppler AND set `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS=<jikigai-org-id>`. Sweeper at `scripts/followthroughs/team-workspace-flag-flip-4284.sh` auto-closes #4284 once both keys are set."

8.2. Edit `knowledge-base/legal/article-30-register.md` (lines 62-67, PA-2 workspace-co-member block). Remove the forward-looking sentence "Flag-flip ON blocked on AC-LEGAL-FLIP (parallel legal-PR for ToS 2.2.0 / AUP §5.5 / DPD §2.3 / Side Letter must land first)." Replace with past-tense reference: "Legal scaffolding shipped in PR #4289 (2026-05-22): ToS 2.2.0 §Workspace Members, AUP §5.5, DPD §2.3(u), Privacy Policy §4.11, Side Letter template + register. Remaining precondition: Doppler flag-flip."

### Phase 9 — ADR-039 + Counsel-Review Audit

9.1. Run `/soleur:architecture create "Decouple legal-doc copy PR from TC_VERSION bump for flag-gated features"` to scaffold `knowledge-base/engineering/architecture/decisions/ADR-039-monolithic-legal-pr-and-reacceptance-wave.md`. Decision body:
- **Context:** PR #4289 lands ToS 2.2.0 (operator user) + TC_VERSION bump (forces re-acceptance) for a clause (§Workspace Members) that is inoperative until a downstream Doppler flip enables the team-workspace feature.
- **Considered alternative:** doc-only-now + ToS-body-later (recommended by CTO + CPO; rejected by operator).
- **Decision:** monolithic PR — ship ToS body + TC_VERSION bump together; accept the re-acceptance wave for the small existing user set.
- **Consequences:** (i) re-acceptance fires immediately on merge for all users; (ii) `/accept-terms` page must surface Art. 13(3) "what changed" banner to mitigate confusion; (iii) follow-up flag-flip PR is Doppler-only (no ToS edits, no TC_VERSION bump); (iv) precedent for future flag-gated legal scaffolding: weigh re-acceptance wave size vs. PR-split overhead.

9.2. Create `knowledge-base/legal/audits/2026-05-counsel-review-4289.md` with operator attestation. **Clone structure from `knowledge-base/legal/audits/2026-05-counsel-review-4066.md`** (richer 5-artifact template per repo-research finding c). Required sections:
- Title + frontmatter (date, counsel-reviewer, PR, status).
- §1 Artifacts reviewed (enumerate: 4 canonical legal docs, 4 mirrors, Side Letter template, register, ADR-039, Article 30 PA-2 amendment).
- §2 Operator attestation (Jean Deruelle as Jikigai SARL gérant signs off on legal sufficiency for jikigai-internal scope).
- §3 External counsel re-review triggers (at least 2 triggers, all must be met for live-counsel re-review): (i) first non-Jikigai-affiliate invitee; (ii) any invitee outside the EEA; (iii) any invitee belonging to a regulated industry (healthcare, finance) — recommended by Q6.

### Phase 10 — GDPR-gate + Verification

10.1. Run `/soleur:gdpr-gate` against this PR's diff. Expected findings: null or minor (single-user-incident threshold trigger fires per Phase 2.7 (b); no Art. 9 special-category writes; Art. 13(1)(e) coverage explicit in Privacy §4.11; Art. 30 PA-2 already updated by #4225). Any Critical finding triggers operator-ack + write to `compliance-posture.md` Active Items + GitHub issue `compliance/critical`.

10.2. Local verification:
- `bash apps/web-platform/scripts/check-tc-document-sha.sh` → exit 0
- `(cd plugins/soleur/docs && npm run build)` → smoke Eleventy build; check that `_site/legal/*.html` renders without 404s on internal links
- `cd apps/web-platform && npx vitest run test/legal-doc-consistency.test.ts test/accept-terms-copy-regression.test.tsx` → all green

10.3. Push and observe CI gates:
- `tc-document-sha-guard` (`.github/workflows/ci.yml:106`)
- `legal-doc-cross-document-gate` (`.github/workflows/legal-doc-cross-document-gate.yml`)
- `scheduled-legal-audit` (`.github/workflows/scheduled-legal-audit.yml`)

### Phase 11 — PR Review

11.1. Mark PR #4289 ready. `user-impact-reviewer` agent fires automatically per Phase 2.6 conditional-agent block (single-user-incident threshold).

11.2. Spawn parallel review agents:
- `pr-review-toolkit:code-reviewer` (general adherence)
- `soleur:engineering:review:legacy-code-expert` — N/A (no test-free code path)
- `soleur:legal:legal-compliance-auditor` — full audit of the 4 doc changes + Side Letter template + register
- `soleur:engineering:review:observability-coverage-reviewer` — N/A (no server-side code added; skip)

11.3. Address findings inline per `rf-review-finding-default-fix-inline`. P1 issues block merge; P2 fixed inline or filed as follow-up scope-outs.

### Phase 12 — Merge + Post-Merge Follow-Ups

12.1. Merge via `gh pr merge --squash --auto` (will auto-merge once CI + review pass).

12.2. Post-merge operator action: update #4231 issue body to note ToS 2.2.0 indemnification already absorbs audit-log scope-bleed carve-out. Automatable via:
```bash
gh issue view 4231 --json body --jq .body > /tmp/4231-body.txt && \
  echo $'\n\n---\n\n## Note (2026-05-22)\n\nToS 2.2.0 §Workspace Members (PR #4289) indemnification already absorbs the audit-log scope-bleed carve-out for `workspace_member_actions`. No additional ToS bump needed when this audit-log PR (#4287) lands.' >> /tmp/4231-body.txt && \
  gh issue edit 4231 --body-file /tmp/4231-body.txt
```

12.3. File deferred follow-up issues per "Deferred Follow-Up Issues" section below.

12.4. Doppler flag-flip remains operator-driven via a SEPARATE PR (not in scope here). Sweeper `scripts/followthroughs/team-workspace-flag-flip-4284.sh` auto-closes #4284 when both Doppler keys are set.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `docs/legal/terms-and-conditions.md` §Workspace Members contains all 3 named sub-clauses — owner-as-controller, co-member-access-under-owner's-account, owner-indemnification-including-audit-log-carve-out. Verify with a content-shape grep (3 separate `grep -c` against the canonical doc returning ≥1 each).
- [ ] AC2: `bash apps/web-platform/scripts/check-tc-document-sha.sh` exits 0; `apps/web-platform/lib/legal/tc-version.ts` shows `TC_VERSION = "2.2.0"` and `TC_DOCUMENT_SHA = "<64-char hex matching sha256sum docs/legal/terms-and-conditions.md>"`.
- [ ] AC3: DPD §2.3(u) is present in both canonical and plural-stemmed mirror AND DPD §4.2 footer contains literal "co-members are NOT processors". Verify: 2 `grep -c` (one per file) for `### 2.3(u)` + 2 for `co-members are NOT processors`.
- [ ] AC4: Privacy Policy §4.11 contains BOTH `owner` perspective AND `co-member` perspective fragments (dual-perspective coverage per SpecFlow c-iii); §4.7 contains literal `Art. 13(1)(e)` recipient note. Verify with 4 separate `grep -c` returning ≥1.
- [ ] AC5: `knowledge-base/legal/side-letter-template.md` exists. Grep: `grep -nE 'RCS\s+[A-Z][a-z]+' knowledge-base/legal/side-letter-template.md` returns matches ONLY with `RCS Paris` (zero matches for any other city — single-token invariant per `legal-doc-consistency.test.ts:137-189`).
- [ ] AC6: `knowledge-base/legal/side-letter-register.md` exists with 3-column schema (Counterparty | Workspace ID | Signed at).
- [ ] AC7: `knowledge-base/legal/audits/2026-05-counsel-review-4289.md` exists with operator attestation (Jean as Jikigai SARL gérant) AND ≥2 external-counsel re-review triggers AND a `## Decision record (replaces ADR-039)` section.
- [ ] AC8: `knowledge-base/legal/compliance-posture.md:95` AC-LEGAL-FLIP row narrowed to Doppler-only remaining precondition; references PR #4289 in past tense.
- [ ] AC9: `knowledge-base/legal/article-30-register.md:62-67` no longer contains the forward-looking "Flag-flip ON blocked on AC-LEGAL-FLIP" sentence. Verify: `grep -c "Flag-flip ON blocked on AC-LEGAL-FLIP" knowledge-base/legal/article-30-register.md` → `0`.
- [ ] AC10: `apps/web-platform/app/(auth)/accept-terms/page.tsx` renders the Art. 13(3) banner when the rendered page receives a non-null prior `tc_accepted_version`. Banner contains literal strings "Workspace Members" AND "May 22, 2026" AND a link to `/legal/terms-and-conditions`. First-time signups (null prior version) do not see the banner. Verify via `accept-terms-copy-regression.test.tsx` with both fixture branches.
- [ ] AC11: **Date-site count** (per Kieran P0-2 — explicit per-site greps, not line-count). All 12 Last-Updated sites carry `May 22, 2026`. Verify with **two explicit greps**:
  - `grep -REc '\*\*Last Updated:\*\* May 22, 2026' docs/legal/ plugins/soleur/docs/pages/legal/ | awk -F: '{s+=$2} END {print s}'` → 8 (4 canonical body + 4 mirror body)
  - `grep -REc 'Last Updated May 22, 2026' plugins/soleur/docs/pages/legal/ | awk -F: '{s+=$2} END {print s}'` → 4 (4 mirror hero)
- [ ] AC12: `npx vitest run apps/web-platform/test/legal-doc-consistency.test.ts apps/web-platform/test/accept-terms-copy-regression.test.tsx` exits 0 locally. (This subsumes the prior sentinel-regression check; `legal-doc-consistency.test.ts:80-113` enumerates sentinels exhaustively, so a separate sentinel AC is redundant per DHH P0-2.)
- [ ] AC13: CI gates green: `tc-document-sha-guard`, `legal-doc-cross-document-gate`, `scheduled-legal-audit`.
- [ ] AC14: `/soleur:gdpr-gate` ran against this PR's diff (Phase 7.1). Output captured in PR body OR in counsel-review audit file. Any Critical findings have operator-ack + `compliance/critical` issue filed.
- [ ] AC15: **TC enforcement surface parity verified at 4 surfaces with comparison-expression equivalence** (per Kieran P1-4 — not just line numbers, but the actual `!==` comparison expressions documented side-by-side in the PR body):
  - middleware.ts:175-177 — `userRow?.tc_accepted_version !== TC_VERSION`
  - app/(auth)/callback/route.ts:32 — expected: same form
  - api/accept-terms/route.ts:44+53 — expected: same form
  - server/ws-handler.ts:321 + :1100-1230 — expected: same form (string-equal, no semver-`<`, `null`/`undefined` treated as "needs accept")
  Any divergence in comparison semantics = P0; document or remediate inline.
- [ ] AC16: `user-impact-reviewer` agent pass at PR review (single-user-incident threshold gate).
- [ ] AC17: `legal-compliance-auditor` agent pass at PR review.
- [ ] AC18: Operator counsel attestation signed in audit file `2026-05-counsel-review-4289.md`.
- [ ] AC19: PR body uses `Ref #4284` (NOT `Closes #4284`). Verify: `gh pr view 4289 --json body --jq .body | grep -E '^(Closes|Fixes|Resolves) #4284' | wc -l` → `0` (per Kieran P1-3). The sweeper auto-closes #4284 when Doppler keys land, not at this PR's merge (ops-remediation class per Sharp Edges).

### Post-merge (operator)

- [ ] PM1: Side Letter signed by Jean + Harry off-platform. Register row recorded with `(Harry, jikigai-workspace-id, <signed-at>, 1.0.0, <pdf-sha256>, none)`.
- [ ] PM2: Follow-up flag-flip PR opened. Doppler `FLAG_TEAM_WORKSPACE_INVITE=1` + `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS=<jikigai-org-id>` set via the `menu-option-ack-not-prod-write-auth` flow (operator manual ack). Sweeper auto-closes #4284.
- [ ] PM3: #4231 issue body updated noting audit-log indemnification carve-out absorbed (automation per Phase 12.2 `gh issue edit`).
- [ ] PM4: Deferred follow-up issues filed (per "Deferred Follow-Up Issues" section).

## Test Strategy

Three CI gates must pass:

1. **`legal-doc-consistency.test.ts`** — enforces canonical-mirror parity for headings, Last-Updated lines (body + hero), sentinel strings, RCS-jurisdiction invariant. Run locally before push.

2. **`tc-document-sha-guard`** — fails on SHA literal mismatch without TC_VERSION bump. Verified by `check-tc-document-sha.sh`.

3. **`accept-terms-copy-regression.test.tsx`** — extended in Phase 7.3 to assert new banner copy when `prev=2.1.0`.

No new test framework. No new test files (extending existing ones).

## Risks

| # | Risk | Mitigation |
|---|------|------------|
| R1 | Sentinel-string drift: §Workspace Members text accidentally retires a sentinel-matched fragment in `legal-doc-consistency.test.ts:80-113` | Phase 0.1 reads the sentinel list before drafting; §Workspace Members is added as NEW content, no existing prose touched |
| R2 | Date drift: PR merges on May 23 instead of May 22; all 12 Last-Updated sites become stale | Phase 0 establishes "May 22, 2026" as the placeholder; if merge slips, regenerate dates via `sed -i 's/May 22, 2026/May 23, 2026/g'` across 8 files in one pre-merge commit. Last-Updated date is the SOLE editable date; never use ISO format |
| R3 | TC_DOCUMENT_SHA computed before final ToS edit; re-computation required | Phase 2 explicitly states "compute AFTER all ToS body edits final". Add a Phase 2 pre-check: `git diff docs/legal/terms-and-conditions.md` empty before computing SHA |
| R4 | Re-acceptance wave fires for confused users who don't understand why they're seeing /accept-terms | Phase 7 Art. 13(3) banner names "§Workspace Members" + Last-Updated date + link to canonical ToS |
| R5 | `recheckTcMidSession` 30s cache window means in-flight WS sessions continue under 2.1.0 consent for up to 30s post-merge (SpecFlow a-ii) | Accepted operator-experience tradeoff (Q-IMPORTANT-5 deferred — see Deferred Follow-Up Issues). 30s window IS load-bearing per existing performance design |
| R6 | Side Letter terms drift from ToS 2.2.0 §Workspace Members in future ToS 2.3.0 (SpecFlow b-ii) | Side Letter §3 explicitly cross-references ToS §Workspace Members; future ToS bump must update Side Letter Template version (filed as deferred follow-up) |
| R7 | Privacy Policy §4.11 dual-perspective copy reads ambiguously for either role (SpecFlow c-iii) | Phase 5.1 explicit dual-perspective sub-clauses; legal-compliance-auditor pass at Phase 11.2 reviews |
| R8 | #4231 audit-log salting (recipient_id_hash per-workspace) is NOT in scope here; ToS 2.2.0 indemnification is the legal cover but not the technical mitigation | Out of scope for this PR (#4231 owns); ToS indemnification clause makes legal recourse explicit. Filed as deferred follow-up |
| R9 | Eleventy build doesn't validate cross-doc internal links | Phase 10.2 manual smoke after `npm run build` checks `_site/legal/*.html` |

## Open Questions

(Carried forward from brainstorm + new from SpecFlow)

1. **Q1 (brainstorm):** Privacy Policy section number — confirmed §4.11.
2. **Q2 (brainstorm):** DPD subsection number — confirmed §2.3(u).
3. **Q3 (brainstorm):** Side Letter in `DOCS` const? — Decision: keep canonical-only for v1.
4. **Q4 (brainstorm):** When to move AC-LEGAL-FLIP row to "Completed"? — Decision: NARROW the remaining cell at this PR's merge (Phase 8.1); MOVE to Completed at flag-flip PR's merge.
5. **Q5 (brainstorm):** `/accept-terms` disclosure text wording — DRAFTED in Phase 7.1: "Updated May 22, 2026 — We've added §Workspace Members. [Read full Terms]". Iterate via copy-regression test.
6. **Q6 (brainstorm):** Counsel-review trigger granularity — INCLUDED regulated-industry trigger (Phase 9.2 §3 triggers list).

New from SpecFlow:

7. **Q-CRIT-1 (SpecFlow a-iii):** `/accept-terms` copy for 2.1.0→2.2.0 — resolved in Phase 7.
8. **Q-CRIT-2 (SpecFlow b-i):** Is signed Side Letter a programmatic flag-flip precondition? — **DEFERRED** to follow-up issue. v1 honor-system; AC-LEGAL-FLIP remains Doppler-only.
9. **Q-CRIT-3 (SpecFlow c-ii / d-ii):** When member A executes Art-17, do `workspace_member_actions` rows survive for member B / owner J? — **DEFERRED** to #4231 follow-up issue.
10. **Q-IMPORTANT-4 (SpecFlow d-i):** Is `recipient_id_hash` salted per-workspace? — **DEFERRED** to #4231 follow-up.
11. **Q-IMPORTANT-5 (SpecFlow a-ii):** Does in-tab client surface a banner when ws-handler closes with `TC_NOT_ACCEPTED`? — **DEFERRED** to follow-up; 30s cache window is the load-bearing design choice.

## Deferred Follow-Up Issues

Filed at PR-finalization (per Phase 6 Final Review pre-submission `Deferral tracking check`):

1. **feat: Per-invitee signed Side Letter as programmatic flag-flip precondition (#4289 follow-up)** — Q-CRIT-2. Re-evaluation trigger: at first non-Jikigai-affiliate invitee being added to the workspace allowlist. Distinct mechanism from counsel re-review (per DHH P1-3 pushback — counsel re-review is "should we get a new audit"; this is "should the flag-flip be programmatically gated").
2. **feat: /accept-terms in-tab banner for ws-handler TC_NOT_ACCEPTED close (#4289 follow-up)** — Q-IMPORTANT-5. Re-evaluation: at next TC_VERSION bump after this one.
3. **feat: Art-17 cascade vs. `workspace_member_actions` audit retention (#4231 follow-up)** — Q-CRIT-3. Re-evaluation trigger (per Kieran P2-7): when `workspace_member_actions` table migration lands OR when first invitee with overlapping prior-workspace history is added.
4. **feat: Per-workspace salt for `recipient_id_hash` (#4231 follow-up)** — Q-IMPORTANT-4. Re-evaluation trigger: when >1 active workspace exists with overlapping invitees, OR when `recipient_id_hash` cross-workspace correlation becomes possible via the audit-log surface.

(Deferred follow-up #5 "Future ToS 2.3.0 reminder" cut per DHH P1-3 + Simplicity P2 — handled as an inline comment in the Side Letter template's §3 cross-reference, not a tracking issue.)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- **Use `Ref #4284`, NOT `Closes #4284` in the PR body.** This is an ops-remediation class plan — #4284 closes when Doppler keys land (post-merge sweeper run), not at this PR's merge. `Closes #N` would auto-close at squash-merge before the remediation is complete.
- **TC_DOCUMENT_SHA recomputation:** If any commit edits `docs/legal/terms-and-conditions.md` AFTER Phase 2.1, re-run `sha256sum` and update the literal. The CI gate `tc-document-sha-guard` catches drift but only after push.
- **All 12 Last-Updated sites must move together.** If the PR sits open past May 22, regenerate via `sed -i 's/May 22, 2026/<new-date>/g' docs/legal/*.md plugins/soleur/docs/pages/legal/*.md apps/web-platform/test/accept-terms-copy-regression.test.tsx` in one pre-merge commit.
- **DPD mirror filename differs from canonical:** canonical is `data-protection-disclosure.md`, mirror is `data-processing-disclosures.md` (plural, different stem). Both must be edited.
- **Side Letter is canonical-only — NOT in `DOCS` const.** Do not add it to `legal-doc-consistency.test.ts:29-35` (would require heading-parity work this PR doesn't scope).
- **RCS jurisdiction token = "RCS Paris" exactly.** Any other city/registry token in Side Letter, ToS, AUP, DPD, Privacy, or Article 30 register fails `legal-doc-consistency.test.ts:137-189`.
- **`**Last Updated:** Month D, YYYY` regex is strict** — never use ISO `2026-05-22` or lowercase `may`; the test at `:122-124` enforces `[A-Z][a-z]+\s+\d{1,2},\s+\d{4}`.
- **Eleventy mirror has TWO Last-Updated lines per file:** hero `<p>Last Updated: ...</p>` and body `**Last Updated:** ...`. Update both, or `legal-doc-consistency.test.ts:122-134` fails.
- **PA-2 row in `article-30-register.md` already shipped by #4225.** Edits here only remove the forward-looking "blocked on" sentence. Do NOT add a new PA-N row (we are not adding a new processing activity, only updating disclosure surface on the existing PA-2 row).
- **`/soleur:gdpr-gate` runs as a subskill in Phase 7.1.** Per `wg-plan-prescribed-skills-must-run-inline`, /work must execute this skill inline.
- **No ADR created (dropped per DHH + Simplicity plan-review).** Decision record lives in the counsel-review audit `## Decision record` section (Phase 6.1).
- **No middleware edit.** Banner predicate reads `tc_accepted_version` server-side (page.tsx Server Component); no `?prev=` query-param threading. Eliminates a load-bearing URL contract.

## Refs

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-22-feat-team-workspace-legal-scaffolding-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-team-workspace-legal-scaffolding/spec.md`
- Source PR (merged): #4225
- Closed umbrella: #4229
- Gating follow-through: #4284
- This PR (draft): #4289
- Related in-flight: #4231 (workspace_member_actions audit-log; WIP at #4287)
- AC-LEGAL-FLIP source: `knowledge-base/legal/compliance-posture.md:95`
- Article 30 PA-2 (already amended by #4225): `knowledge-base/legal/article-30-register.md:62-67`
- TC bump policy: `knowledge-base/legal/tc-version-bump-policy.md`
- Counsel-review precedents: #4081 / #4066 / #4213 audits at `knowledge-base/legal/audits/`
- Legal-doc consistency test: `apps/web-platform/test/legal-doc-consistency.test.ts`
- /accept-terms page: `apps/web-platform/app/(auth)/accept-terms/page.tsx`
- Middleware TC gate: `apps/web-platform/middleware.ts:175-177`
- WS-handler TC recheck: `apps/web-platform/server/ws-handler.ts:1100-1230` (`recheckTcMidSession`)
- TC version literals: `apps/web-platform/lib/legal/tc-version.ts`
- DSAR allowlist (already covers workspace tables): `apps/web-platform/server/dsar-export-allowlist.ts:151-178`
