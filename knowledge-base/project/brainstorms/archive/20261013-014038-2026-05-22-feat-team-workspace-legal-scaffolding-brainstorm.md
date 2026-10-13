---
title: Team-Workspace Legal Scaffolding (ToS 2.2.0 + AUP §5.5 + DPD §2.3 + Privacy + Side Letter)
status: brainstormed
parent_issue: 4229
gating_issue: 4284
pr: 4289
branch: feat-team-workspace-legal-scaffolding
source_pr: 4225
date: 2026-05-22
lane: cross-domain
brand_survival_threshold: single-user incident
domains_assessed: [Product, Engineering, Legal]
requires_clo_signoff: true
requires_cpo_signoff: true
requires_cto_signoff: true
requires_adr: true
---

# Team-Workspace Legal Scaffolding — Brainstorm

PR #4289 ships the legal-track that unblocks `FLAG_TEAM_WORKSPACE_INVITE=1`
per AC-LEGAL-FLIP (`knowledge-base/legal/compliance-posture.md:95`). Source
PR #4225 (`feat-team-workspace-multi-user`) merged 2026-05-21 with schema
migrations 053–057, RLS rewrite, DSAR Art-15/17/20 cascade, Article 30 PA-2
amendment, and the invite UI behind `TEAM_WORKSPACE_INVITE_ENABLED` (default
OFF). The flag stays OFF until this PR plus a Doppler flip land.

## What We're Building

A monolithic legal-doc PR that lands every artifact required by AC-LEGAL-FLIP
in one merge. After this PR, the only remaining work for the flag-flip is
two Doppler keys (`FLAG_TEAM_WORKSPACE_INVITE=1` + `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS`).

**Deliverables (build sequence in Open Questions / Build Sequence below):**

1. ToS 2.2.0 §Workspace Members — owner is controller; co-members access
   under owner's account; owner indemnifies (with carve-out covering #4231
   workspace_member_actions audit-log visibility).
2. AUP §5.5 — owner attestation that all invitees are under
   employment/contractor agreement until customer-DPA ships.
3. DPD §2.3(u) — workspace co-member as data category + §4.2 carve-out
   clarifying co-members are NOT processors.
4. Privacy Policy new §4.x "Workspace co-members" data-class disclosure
   (parallel to §4.10 LinkedIn pattern) + recipient note at the existing
   workspace-data block. Required for Art. 13(1)(e) — DPD alone is not the
   user-facing notice surface.
5. Side Letter template (canonical-only) + Side Letter register (mirrors
   `tenant-dpa-register.md`).
6. Counsel-review audit (operator-attested) at
   `knowledge-base/legal/audits/2026-05-22-counsel-review-team-workspace.md`.
7. ADR recording the rationale for re-acceptance-wave-on-merge tradeoff.
8. `TC_VERSION` 2.1.0 → 2.2.0 + `TC_DOCUMENT_SHA` refresh in
   `apps/web-platform/lib/legal/tc-version.ts`.
9. Eleventy mirror sync for every canonical doc that changes (ToS, AUP, DPD,
   Privacy Policy).
10. AC-LEGAL-FLIP row update at `knowledge-base/legal/compliance-posture.md:95`
    to narrow the remaining precondition to Doppler-only.

## User-Brand Impact

`USER_BRAND_CRITICAL=true`. Threshold: `single-user incident` (inherited
verbatim from parent brainstorm). All three Phase 0.1 vectors are load-bearing:

1. **Trust breach / cross-tenant read** — owner-as-controller framing must
   be correct, OR invited co-member has no Art-15/17/20 recourse over their
   own identifiable rows. Mitigated by: ToS 2.2.0 §Workspace Members + DPD
   §2.3(u) recipient framing.
2. **User data exposure** — Privacy Policy §4.x must disclose co-member as
   a recipient class before the flag flips, OR Art. 13(1)(e) is not
   demonstrable.
3. **Disclosure / Art-13 gap** — TC_VERSION bump fires re-acceptance
   immediately on merge per `middleware.ts:175-177` (no flag guard). Notice
   text on `/accept-terms` must explain what changed.

Inheritance: the `user-impact-reviewer` agent at PR review is the
load-bearing gate. Plan (if any) inherits this section verbatim.

## Why This Approach

The TC_VERSION ↔ TC_DOCUMENT_SHA coupling at `tc-document-sha-guard` makes
a clean PR-split possible: AUP / DPD / Privacy edits do NOT touch
TC_DOCUMENT_SHA (scope confirmed at `check-tc-document-sha.sh:112`,`:187` —
operates only on `docs/legal/terms-and-conditions.md`). The recommended
shape was therefore a two-PR split (doc copy now, ToS body + TC bump in the
flag-flip PR).

**Operator overrode to monolithic.** Rationale: user base is small
(operator + intern + handful of waitlist), the re-acceptance wave is bounded,
and a single-PR follow-up of "Doppler-only flag flip" is operationally
cleaner than two co-merged PRs. Accepted as a deliberate tradeoff.

CPO surfaced the deferral argument. CLO surfaced two additional load-bearing
items (Privacy Policy §recipient amendment for Art. 13(1)(e); Side Letter
register as net-new artifact). CTO surfaced the SHA-vs-version coupling
mechanics and four doc-only PR sharp edges (RCS-jurisdiction invariant,
sentinel-string regression, `**Last Updated:**` regex strictness, Eleventy
build cross-doc links).

## Domain Assessments

**Assessed:** Product (CPO), Engineering (CTO), Legal (CLO). Marketing,
Operations, Sales, Finance, Support not spawned — scope is internal/legal,
no public positioning surface, no infra spend, no pipeline impact.

### Product (CPO)

**Summary:** Threshold drops conceptually to "no operator harm beyond doc
drift" because this PR adds zero runtime paths, but operator chose monolithic
which couples it to TC_VERSION re-acceptance — keep parent threshold of
single-user incident for that reason. Side Letter stays off-platform PDF
(bespoke per workspace; click-to-attest premature). Minimum viable cut not
needed since operator did not adopt the 2-day deadline constraint.

### Engineering (CTO)

**Summary:** Middleware re-acceptance fires unconditionally on TC_VERSION
mismatch (`middleware.ts:175-177` — no flag guard). TC_DOCUMENT_SHA is scoped
only to ToS canonical (`check-tc-document-sha.sh:112,187`). DSAR
allowlist already covers the 4 workspace tables (`dsar-export-allowlist.ts`
lines 151–178 from #4225); no code surface beyond doc text + SHA + version.
Doc-only PR sharp edges: RCS-jurisdiction invariant (must be "RCS Paris"),
sentinel-string regression, `**Last Updated:**` format regex
`[A-Z][a-z]+\s+\d{1,2},\s+\d{4}`, Eleventy build doesn't validate cross-doc
links. ADR recommended for the decoupling-or-not decision.

### Legal (CLO)

**Summary:** DPD §2.3 was NOT covered by #4225 (article-30-register.md
PA-2 row is the internal Art-30 register, not the user-facing DPD).
TC_VERSION bump = MINOR `2.1.0 → 2.2.0` per
`tc-version-bump-policy.md:115-120`. Side Letter has no artifact home yet —
new `knowledge-base/legal/side-letter-register.md` mirrors `tenant-dpa-register.md`.
Counsel posture: operator-attested per #4081/#4066/#4213 precedent; external
re-review trigger = first non-Jikigai-affiliate invitee OR any invitee
outside the EEA. **Privacy Policy ALSO needs Art. 13(1)(e) recipient
amendment in lockstep — DPD alone is not the user-facing notice surface.**
Brand-survival risk #4231 scope-bleed: workspace_member_actions audit-log
will expose member A's `action_sends` rows (recipient_id_hash, body_sha256,
template_hash) to member B as workspace-co-member — ToS 2.2.0 indemnification
must explicitly extend to co-member access to send-audit ledgers, or
inviting owner has unbounded exposure.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Monolithic PR (ship ToS body + TC_VERSION bump in #4289) | Operator override of recommended split; small user base, re-acceptance wave bounded, follow-up flag-flip is Doppler-only |
| 2 | Side Letter as off-platform template + signature register | CPO + CLO consensus: bespoke per workspace, click-to-attest premature |
| 3 | ToS 2.2.0 indemnification includes audit-log carve-out for #4231 | CLO scope-bleed risk; cheaper than ToS 2.3.0 bump weeks later |
| 4 | Counsel review: operator-attested (Jean as Jikigai SARL gérant) | Precedent #4081/#4066/#4213; intra-Jikigai scope; external re-review trigger = first non-affiliate OR non-EEA invitee |
| 5 | TC_VERSION bump = MINOR 2.1.0 → 2.2.0 | Per `tc-version-bump-policy.md:115-120` — material but consistent with user expectations |
| 6 | Privacy Policy gets its own §recipient amendment (lockstep) | CLO sharp finding (d) — DPD alone doesn't satisfy Art. 13(1)(e) user-facing notice |
| 7 | `/accept-terms` page disclosure of what changed | Reduce re-acceptance friction; Art. 13(3) "we updated" notice |
| 8 | RCS-jurisdiction token in Side Letter = "RCS Paris" | CTO sharp edge — `legal-doc-consistency.test.ts:137-189` enforces `tokens.size === 1` |
| 9 | All `**Last Updated:**` lines = "May 22, 2026" | CTO sharp edge — regex strictness in legal-doc-consistency test |

## Build Sequence

Single PR; order minimizes CI flips:

1. Draft ToS 2.2.0 §Workspace Members text in `docs/legal/terms-and-conditions.md`
   — body change + `**Last Updated:** May 22, 2026`. Include indemnification
   audit-log carve-out (Decision #3). Avoid retiring/rephrasing existing
   sentinel-matched fragments per `legal-doc-consistency.test.ts:80-113`.
2. Sync Eleventy mirror at `plugins/soleur/docs/pages/legal/terms-and-conditions.md`
   (same body, hero date).
3. Recompute `sha256sum docs/legal/terms-and-conditions.md` and update
   `TC_DOCUMENT_SHA` literal at `apps/web-platform/lib/legal/tc-version.ts:35`.
4. Bump `TC_VERSION` 2.1.0 → 2.2.0 at `tc-version.ts:14`.
5. Draft AUP §5.5 at `docs/legal/acceptable-use-policy.md` + mirror at
   `plugins/soleur/docs/pages/legal/acceptable-use-policy.md`. Update
   `**Last Updated:**` in both.
6. Draft DPD §2.3(u) + §4.2 carve-out at
   `docs/legal/data-protection-disclosure.md` + mirror at
   `plugins/soleur/docs/pages/legal/data-processing-disclosures.md`. Update
   `**Last Updated:**` in both.
7. Draft Privacy Policy §4.x co-member disclosure + recipient note at the
   workspace-data block in `docs/legal/privacy-policy.md` + mirror at
   `plugins/soleur/docs/pages/legal/privacy-policy.md`. Update
   `**Last Updated:**` in both.
8. Create `docs/legal/side-letter-template.md` (canonical-only; not in
   `legal-doc-consistency.test.ts` DOCS const yet — decide whether to
   extend or keep out-of-test). RCS token = "RCS Paris".
9. Create `knowledge-base/legal/side-letter-register.md` mirroring
   `knowledge-base/legal/tenant-dpa-register.md` shape.
10. Create `knowledge-base/legal/audits/2026-05-22-counsel-review-team-workspace.md`
    (operator-attested) — sign-off on the 4 doc-text artifacts + Side Letter
    template + register.
11. Update `/accept-terms` page copy to explain what changed (Art. 13(3) notice).
12. Update AC-LEGAL-FLIP row at `knowledge-base/legal/compliance-posture.md:95`
    — narrow remaining precondition to Doppler flip + allowlist.
13. Move row to "Completed Compliance Work" at merge time (or in follow-up
    flag-flip PR — decide via Open Question Q4).
14. Run `/soleur:architecture create` for the ADR documenting the
    re-acceptance-wave-on-merge tradeoff.
15. Update #4284 (gating follow-through) — the sweeper auto-closes when the
    legal-PR is merged AND Doppler flips. No manual close needed; the script
    at `scripts/followthroughs/team-workspace-flag-flip-4284.sh` handles it.
16. Update #4231 scope (workspace_member_actions audit-log) — note that ToS
    2.2.0 already absorbs the indemnification carve-out so no ToS bump needed
    when audit-log lands.

## Open Questions

1. **Q1 — Privacy Policy section number.** New §4.x for "Workspace co-members"
   — pick the next free number in `docs/legal/privacy-policy.md` (currently
   §4.10 is LinkedIn). Suggest §4.11.
2. **Q2 — DPD subsection number.** §2.3(u) is the next free letter after the
   PR-I §2.3(t) extension (2026-05-21). Confirm during drafting.
3. **Q3 — Side Letter doc in `legal-doc-consistency.test.ts`?** Add to the
   `DOCS` const at `legal-doc-consistency.test.ts:29-35` for mirror-parity
   enforcement, OR keep canonical-only? Decision: keep canonical-only for v1
   (no plugin-docs use case yet); revisit at first external-workspace ask.
4. **Q4 — When to move AC-LEGAL-FLIP row to "Completed"?** At this PR's merge
   (when 100% of items in the row are done modulo the Doppler flip itself) OR
   at the flag-flip PR (when the Doppler keys are set)? Operator preference.
5. **Q5 — `/accept-terms` page disclosure text wording.** Draft + iterate
   during PR build; out-of-scope for brainstorm.
6. **Q6 — Counsel-review re-review trigger granularity.** Should the trigger
   list explicitly include "first invitee belonging to a regulated industry"
   (healthcare, finance) in addition to the EEA/affiliate axes? CLO discretion
   during drafting.

## Session Errors

None. Triad reconciled cleanly after CTO surfaced the TC_VERSION ↔
TC_DOCUMENT_SHA coupling, which dissolved the apparent CPO ↔ CLO
contradiction (they were addressing different artifacts; CPO's concern was
ToS-body-specific).

## Refs

- Parent brainstorm: `knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md`
- Parent spec: `knowledge-base/project/specs/feat-team-workspace-multi-user/spec.md`
- Source PR (merged): #4225
- Closed umbrella: #4229
- Gating follow-through: #4284
- This PR (draft): #4289
- Related in-flight: #4231 (workspace_member_actions audit-log; WIP at #4287)
- AC-LEGAL-FLIP source: `knowledge-base/legal/compliance-posture.md:95`
- Article 30 PA-2 (already amended by #4225): `knowledge-base/legal/article-30-register.md:62-67`
- TC bump policy: `knowledge-base/legal/tc-version-bump-policy.md`
- Counsel-review precedents: #4081 / #4066 / #4213
