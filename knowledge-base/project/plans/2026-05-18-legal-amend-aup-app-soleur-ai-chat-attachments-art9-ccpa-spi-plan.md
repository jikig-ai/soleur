---
title: "legal: amend AUP for app.soleur.ai + chat-attachments Art. 9 / CCPA SPI upload warning"
type: legal
date: 2026-05-18
issue: 3921
pr: 3988
lane: single-domain
requires_cpo_signoff: false
---

# legal: amend AUP for app.soleur.ai + chat-attachments Art. 9 / CCPA SPI upload warning

## Enhancement Summary

**Deepened on:** 2026-05-18
**Sections enhanced:** Overview / Files to Edit / Risks / Test Scenarios / Implementation Phases
**Research lenses applied:** legal-doc cross-document gate path-fire analysis; Eleventy build command verification against `deploy-docs.yml`; AC grep executability sandboxed against synthetic fixtures; AGENTS.md sharp-edge cross-check (paren-safety, awk-self-match, unicode separator handling, github-prescribed-labels verification, citation provenance).

### Key Improvements

1. **T4 build command corrected:** Plan v1 prescribed `cd plugins/soleur/docs && bun run build`. The actual deploy-docs.yml uses `npx @11ty/eleventy` from repo root; `plugins/soleur/docs/package.json` has `docs:build` script that `cd`s up to the repo root before invoking the same. Plan now prescribes `npx @11ty/eleventy --dryrun` (no `_site/` artifact written) for plan-time validation, with `bun run docs:build` from `plugins/soleur/docs/` as the equivalent.
2. **legal-doc cross-document gate fire path traced:** The gate workflow at `.github/workflows/legal-doc-cross-document-gate.yml` triggers on `paths:` that include `knowledge-base/legal/compliance-posture.md`. This PR DOES touch compliance-posture.md and WILL trigger the workflow run. However, the workflow body only fails when `surface_hit=true`, which fires only for DSAR surface files (`apps/web-platform/server/dsar-export*.ts`, `apps/web-platform/app/api/account/export/**`, migrations 041/042). This PR touches none of those, so the gate exits 0 with `"No DSAR surface file touched — gate trivially passes."` Confirmed via reading the workflow body. **No plan changes required** — the gate is safe.
3. **AC1 grep executability verified:** The backtick + parenthesis sequence in the AC1 grep pattern (`chat-attachments\` upload surface (image and PDF files up to 24 MB)`) was sandboxed against a synthetic fixture: `grep -F` exit code = 0, single match, no escaping required. Per AGENTS.md `cq-regex-unicode-separators-escape-only` and the paren-safety sharp edge: the AC1 grep uses `grep -F` (fixed-string), so the `(image and PDF...)` parentheses are literal, not regex metacharacters. Safe.
4. **Unicode characters first-introduction flag:** The current AUP has zero `§` (section-sign U+00A7) and zero `—` (em-dash U+2014) characters in either canonical or mirror. This PR introduces both for the first time. Eleventy `.njk` rendering handles UTF-8 natively; Nunjucks does not strip or transcode the section sign. **Mitigation:** new Phase 4 verification step grep-counts `§` occurrences post-edit (≥ 6 in canonical: 1 in §4.7 body cross-reference + 1 in §4.8 heading-area body + several `§1798.140(ae)` citations).
5. **No `legal` GitHub label exists in this repo's label list.** Verified via `gh label list --limit 200 | grep -i legal` returns empty. AC12 prescribes only `Closes #3921` — no `--label` site is created in this PR (the issue is already tagged upstream). **No plan change required**; recorded for audit-trail.
6. **PR/issue citation provenance verified live:** PA2 line 62 (the Art. 9 / chat-attachments cell with the "PR-D follow-up: explicit AUP warning..." note) was landed by **PR #3883 (PR-D, `144edb12`, merged 2026-05-16 19:07 UTC)** — the same PR that surfaced issue #3921. A separate PR #3940 (merged 2026-05-17, "PR-F Inngest trigger layer + CFO autonomous-draft") DID touch `article-30-register.md` but added the PA-13 (CFO autonomous-draft) row, NOT PA2 — earlier plan drafts conflated the two. Issue #3921 — verified open. Draft PR #3988 — verified open, base `main`, head `feat-one-shot-issue-3921-aup-art9-ccpa-spi-warning`. Provenance corrected post-review per git-history-analyzer Check 1 (PR #3988 multi-agent review).

### New Considerations Discovered

- The plan's Phase 5 mention of removing the PR-D "follow-up tracked separately" note from PA2 line 62 is correctly scoped OUT of this PR (Phase 5 prose says "deferred to whichever next legal PR touches PA2"). This preserves the parity gate AC6 — if this PR modified PA2, the AC6 cross-reconciliation would compete with itself.
- The drafted §4.8 (California SPI) cites `Cal. Civ. Code §1798.140(ae)`. The CPRA-amended California Civil Code reorganized §1798.140 in 2023; the current operative subsection for "Sensitive Personal Information" is (ae). The legislature periodically renumbers subsections via uncodified amendments. AC8 attestation must verify the subsection letter at PR-review time against the current operative text at leginfo.legislature.ca.gov (note: as of 2026-05-18, (ae) is correct; this could drift in a future legislative session).
- The drafted §4.7 cross-references "internal compliance procedure" (the `gdpr-gate` regulated-data surface rule). This is a forward-looking reference to internal procedure — a regulator reading the AUP cannot inspect this procedure. Acceptable for a user-facing AUP (regulators inspect the Article 30 register, which DOES name `hr-gdpr-gate-on-regulated-data-surfaces` at PA2 line 62), but worth recording: the AUP-to-internal-procedure cross-reference is asymmetric.

## Overview

Broaden the existing Acceptable Use Policy (`docs/legal/acceptable-use-policy.md` + its plugin docs-site mirror at `plugins/soleur/docs/pages/legal/acceptable-use-policy.md`) so that:

1. §2 (Scope) names the hosted Web Platform at `app.soleur.ai`, the conversational prompt input surface, the `chat-attachments` upload surface (image PNG/JPEG/GIF/WebP + PDF, ≤24 MB), and persisted artifacts — without dropping the prior plugin-scoped framing.
2. A new section warns users not to submit GDPR Art. 9 special-category data or Art. 10 criminal-conviction data via prompts or attachments, mirroring the disclaimer language in `knowledge-base/legal/article-30-register.md` PA2 §(b) Special categories (Art. 9 / 10) cell at line 62.
3. A new section warns users not to submit California CCPA Sensitive Personal Information (Cal. Civ. Code §1798.140(ae)) via the same surfaces.

This closes the PR-D follow-up explicitly tracked in PA2 line 62: *"PR-D follow-up: explicit AUP warning for attachment Art. 9 upload (tracked separately)."* The trigger gate ("before 2nd hosted founder OR GA") has not fired, but the operator chose to ship now for compliance hygiene.

## Research Reconciliation — Spec vs. Codebase

The pre-resolved feature-description context made four claims that needed live-state verification before plan finalization. Discoveries (with disposition):

| Pre-resolved claim | Codebase reality | Plan response |
|---|---|---|
| AUP "last touched 2026-02-20" | Frontmatter shows `last-updated: 2026-04-10`; body `Last Updated: April 10, 2026`; docs-site mirror shows `Last Updated March 29, 2026`. compliance-posture row shows `2026-03-20`. Three different dates already in the system. | Plan moves ALL three to `2026-05-18` in lockstep (AUP canonical, AUP mirror, compliance-posture row). |
| Insert new §4.6 and §4.7 | §4.6 ("Shared Content", KB sharing) ALREADY exists since 2026-04-10 (see `docs/legal/acceptable-use-policy.md:119-130` and mirror). Inserting a NEW §4.6 would collide and break the §4.6 cross-reference in §6.1 enforcement narrative. | **Renumber the new sections to §4.7 (Special-Category Data — Hosted Chat Surface) and §4.8 (California Sensitive Personal Information).** Update all internal cross-references in the drafted clauses (`§4.6` → `§4.7` where the §4.7 text refers back to "the prohibition as §4.6"). |
| `§6.2 cross-reference may be dangling` | §6.2 EXISTS at `acceptable-use-policy.md:188` titled "Consequences of Violation"; bullet at `:187` reads "Termination of Web Platform account and deletion of associated data" — this is the closest existing removal-of-content clause. | **Keep the `§6.2 of this Policy` cross-reference as drafted; no substitution needed.** Record this in the PR body for auditability. |
| `TC_DOCUMENT_SHA may cover the AUP` | The CI guardrail `tc-document-sha-guard` (`.github/workflows/ci.yml:93`, `apps/web-platform/scripts/check-tc-document-sha.sh`) is hard-scoped to `CANONICAL=docs/legal/terms-and-conditions.md` and its mirror — **the AUP is NOT in scope**. `TC_VERSION` and `TC_DOCUMENT_SHA` cover ONLY the T&C document per `tc-version-bump-policy.md`. | **No `TC_DOCUMENT_SHA` bump required. No `TC_VERSION` bump required.** The AUP has no standalone consent-version constant in the web-platform code; AUP acceptance rides on T&C consent (T&C §9 incorporates AUP by reference at `docs/legal/terms-and-conditions.md:205`). AC4 from the pre-resolved feature description is therefore SCOPED OUT — this is documented under "Scope-outs and rationale" below. |

Two additional discoveries surfaced at plan-write time:

| Discovery | Impact | Plan response |
|---|---|---|
| AUP has a plugin docs-site mirror at `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` with Eleventy frontmatter + page-hero scaffolding. | A canonical-only edit would leave the mirror stale (mirror shows different date already — `March 29, 2026` vs canonical `April 10, 2026`). Risk that operator-facing site shows pre-amendment AUP indefinitely. | **Mirror is in `Files to Edit`.** Both new sections + §2 bullet + `Last Updated` date land in both files in the same commit. |
| PA2 §(c) Categories of personal data cell (line 60 of article-30-register.md) explicitly enumerates the file types: `image (PNG / JPEG / GIF / WebP) and PDF up to 24 MB`. | Pre-resolved drafted §4.7 clause uses "image and PDF files up to 24 MB" — abbreviates the four image formats. This is acceptable in a user-facing AUP (concision over enumeration); strict parity is NOT required. | Adopt the drafted phrasing verbatim. Plan records the abbreviation as intentional. |

## Files to Edit

- `docs/legal/acceptable-use-policy.md` (canonical AUP) — append §2 bullet; insert §4.7 Special-Category Data; insert §4.8 California SPI; bump `last-updated:` frontmatter and `Last Updated:` line to 2026-05-18.
- `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` (Eleventy mirror) — same body edits + page-hero `Last Updated May 18, 2026`.
- `knowledge-base/legal/compliance-posture.md` — AUP row date `2026-03-20` → `2026-05-18`; append top-of-file dated comment summarizing the amendment scope.

## Files to Create

None. (Knowledge-base spec/tasks files are scaffolded by the plan skill itself — they do not count as feature-file creation.)

## Open Code-Review Overlap

No open issues with `label:code-review` reference any of the three files above. Verified at plan time via `gh issue list --label code-review --state open --json number,title,body --limit 200` and standalone `jq` substring match on each path. Recorded `None` per the Step 1.7.5 contract.

## Scope-outs and rationale

| Scope-out | Rationale |
|---|---|
| `apps/web-platform/lib/legal/tc-version.ts` consent-version bump | `TC_VERSION` and `TC_DOCUMENT_SHA` cover the Terms & Conditions document only. The CI guardrail (`check-tc-document-sha.sh`) is hard-pinned to `CANONICAL=docs/legal/terms-and-conditions.md`. The AUP has no separate consent-version constant in the web-platform code. T&C §9 incorporates the AUP by reference — material AUP changes that *should* force re-consent must do so by bumping T&C (the contract-of-record), which is a separate decision outside this PR's scope. The operator can file a follow-up issue if forced re-consent on this AUP amendment is desired; this PR does not assume that decision. |
| Root-level `article-30-register.md` (orphaned French private draft) | Explicit operator instruction: out of scope for this PR; separate cleanup later. AC9 enforces this surface is untouched. |
| Privacy Policy, GDPR Policy, Data Protection Disclosure | The drafted clauses cite PA2 of the Article 30 register as the controlling processing-activity disclosure. PA2 already discloses Art. 9 incidental ingress at line 62 (landed via #3940). Privacy Policy / GDPR Policy / DPD do not need to change in lockstep because the AUP's role is **user prohibition**, not **controller disclosure** — the disclosure is already current. AC10 enforces non-modification. |
| Trigger gate ("before 2nd hosted founder OR GA") | Operator chose to ship early for compliance hygiene. No CPO sign-off required (threshold = aggregate pattern, see User-Brand Impact). |

## User-Brand Impact

**If this lands broken, the user experiences:** a malformed AUP section (e.g., duplicated §4.6 heading, dangling §6.2 cross-reference, or stale date metadata) on `app.soleur.ai/legal/acceptable-use-policy/` — the publicly-served legal page either renders incorrectly or contradicts the PA2 disclosure already on file with regulators.

**If this leaks, the user's [data] is exposed via:** N/A. This is a docs-only edit; no data flows are changed. The leak surface is the *absence* of the warning, not the warning itself — i.e., a user submits Art. 9 / CCPA SPI content without knowing it is prohibited, then incurs the existing PA2 incidental-ingress handling rule (`hr-gdpr-gate-on-regulated-data-surfaces`). This PR closes that knowledge gap.

**Brand-survival threshold:** `aggregate pattern` (compliance-documentation completeness across the legal-doc suite, NOT a single-user incident). Explicitly recording this so the downstream `user-impact-reviewer` does NOT misfire on a `single-user incident` threshold during review. The matter is P3 priority by label; the gating trigger ("before 2nd hosted founder OR GA") has not yet fired but is being closed ahead of trigger for compliance hygiene.

No `requires_cpo_signoff: true` is set in the frontmatter (threshold is not `single-user incident`).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — §2 of `docs/legal/acceptable-use-policy.md` AND `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` contains the new app.soleur.ai bullet verbatim:
  > `- The hosted Web Platform at \`app.soleur.ai\`, including conversational prompt input, the \`chat-attachments\` upload surface (image and PDF files up to 24 MB), and any artifacts persisted to user-scoped storage.`

  Verify: `grep -F 'chat-attachments\` upload surface (image and PDF files up to 24 MB)' docs/legal/acceptable-use-policy.md plugins/soleur/docs/pages/legal/acceptable-use-policy.md` returns 2 matches (one per file). The prior plugin-scoped bullets in §2 (lines 33-42 of canonical) remain present and unmodified.

- [ ] **AC2** — `### 4.7 Special-Category and Sensitive Personal Data — Hosted Chat Surface` inserted verbatim per the source-of-truth clause in this plan, immediately AFTER the existing `### 4.6 Shared Content` and BEFORE `## 5. User Responsibilities`, in both canonical and mirror. The §6.2 cross-reference is **preserved as-drafted** (§6.2 "Consequences of Violation" exists in both files at `:188` canonical / equivalent mirror line; the substitution self-check in the feature-description block did NOT trigger). The PR body records: "§6.2 cross-reference verified to resolve to existing §6.2 Consequences of Violation; no substitution required."

  Verify: `grep -c '^### 4.7 Special-Category and Sensitive Personal Data' docs/legal/acceptable-use-policy.md plugins/soleur/docs/pages/legal/acceptable-use-policy.md` returns `1` for each file. `grep -F 'under §6.2 of this Policy' docs/legal/acceptable-use-policy.md plugins/soleur/docs/pages/legal/acceptable-use-policy.md` returns 2 matches.

- [ ] **AC3** — `### 4.8 California Sensitive Personal Information` inserted verbatim per the source-of-truth clause in this plan, immediately AFTER §4.7 and BEFORE `## 5. User Responsibilities`, in both canonical and mirror. The internal back-reference in §4.8 (which the source-of-truth feature-description text writes as "the same prohibition as §4.6") MUST be updated to read **"the same prohibition as §4.7"** AND **"incidental ingress will be treated under §4.7"** to reflect the §4.6→§4.7 renumbering. (See Research Reconciliation row 2.)

  Verify: `grep -c '^### 4.8 California Sensitive Personal Information' docs/legal/acceptable-use-policy.md plugins/soleur/docs/pages/legal/acceptable-use-policy.md` returns `1` for each file. `grep -F 'same prohibition as §4.7' docs/legal/acceptable-use-policy.md plugins/soleur/docs/pages/legal/acceptable-use-policy.md` returns 2 matches. `grep -F 'same prohibition as §4.6' docs/legal/acceptable-use-policy.md plugins/soleur/docs/pages/legal/acceptable-use-policy.md` returns 0 matches (catches accidental verbatim-paste of the unupdated source-of-truth text).

- [ ] **AC4** — *(SCOPED OUT — see "Scope-outs and rationale" above.)* No `tc-version.ts` edit; no `TC_VERSION` or `TC_DOCUMENT_SHA` bump. The CI workflow `tc-document-sha-guard` is hard-scoped to T&C and is unaffected by AUP edits. Verify: `git diff --name-only main...HEAD -- apps/web-platform/lib/legal/tc-version.ts` returns empty.

- [ ] **AC5** — `knowledge-base/legal/compliance-posture.md` AUP row's `Last Updated` cell moved from `2026-03-20` to `2026-05-18`. Frontmatter `last_updated:` advanced to `2026-05-18`. A new top-of-file dated comment is appended summarizing the amendment scope (app.soleur.ai + chat-attachments Art. 9 / CCPA SPI warning; closes #3921; cites PR #3988 + PA2 line 62 cross-reference). The Active Compliance Items table is NOT touched (no new active item; this PR closes a PA2 follow-up that was tracked inline in PA2, not as a separate Active Items row).

  Verify: `grep -E '^\| Acceptable Use Policy \|.*\| 2026-05-18 \| Active \|$' knowledge-base/legal/compliance-posture.md` returns 1 match. `grep -E '^\| Acceptable Use Policy \|.*\| 2026-03-20 \|' knowledge-base/legal/compliance-posture.md` returns 0 matches.

- [ ] **AC6** — Parity check vs `knowledge-base/legal/article-30-register.md` PA2 line 62 passes on these dimensions:
    - bucket name: `chat-attachments` (drafted clauses use this literal; PA2 confirms);
    - file types: image (PNG/JPEG/GIF/WebP) + PDF (drafted clauses abbreviate to "image and PDF files" — intentional concision per Research Reconciliation row 6; ACCEPTED);
    - size cap: 24 MB (drafted clauses match PA2);
    - surface naming: "prompts and attachments" (drafted clauses use "prompt field and `chat-attachments` upload surface" + "prompts or attachments" — semantically aligned);
    - cross-reference target: "processing activity PA2 (Conversation Data) in our Article 30 register" (drafted clauses contain verbatim).

  Verify by inspection of the diff against the PA2 line 62 snapshot recorded above; no automated grep beyond AC1-AC3.

- [ ] **AC7** — GDPR Art. 9(1) category list (a)-(h) in the new §4.7 matches the regulation verbatim. Art. 10 (criminal convictions and offences) is item (i). Pre-merge legal-source verification cite required in PR body — reviewer (CLO or human) confirms against the official EUR-Lex text of GDPR Art. 9(1) and Art. 10 at `https://eur-lex.europa.eu/eli/reg/2016/679/oj` (no automated check; legal-text faithfulness is a domain-reviewer attestation).

- [ ] **AC8** — CCPA SPI categories in §4.8 match Cal. Civ. Code §1798.140(ae). Pre-merge legal-source verification cite required in PR body — reviewer (CLO or human) confirms against the official California Legislative Information text at `https://leginfo.legislature.ca.gov/faces/codes_displaySection.xhtml?sectionNum=1798.140&lawCode=CIV`.

- [ ] **AC9** — Root-level orphaned `article-30-register.md` (French private draft) NOT modified. Verify: `git diff --name-only main...HEAD -- article-30-register.md` returns empty.

- [ ] **AC10** — Privacy Policy, GDPR Policy, Data Protection Disclosure NOT modified. Verify: `git diff --name-only main...HEAD -- docs/legal/privacy-policy.md docs/legal/gdpr-policy.md docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/privacy-policy.md plugins/soleur/docs/pages/legal/gdpr-policy.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns empty.

- [ ] **AC11** — Both AUP files carry `Last Updated: May 18, 2026` (canonical body line 15) AND mirror page-hero `Last Updated May 18, 2026` AND canonical frontmatter `last-updated: 2026-05-18`. Verify: `grep -cF 'Last Updated: May 18, 2026' docs/legal/acceptable-use-policy.md` returns ≥ 1; `grep -cF 'Last Updated May 18, 2026' plugins/soleur/docs/pages/legal/acceptable-use-policy.md` returns ≥ 1; `grep -E '^last-updated:[[:space:]]*2026-05-18' docs/legal/acceptable-use-policy.md` returns 1 match.

- [ ] **AC12** — PR body uses `Closes #3921` (not `Ref`). This is a normal docs-only change with no post-merge operator action required, so the `wg-use-closes-n-in-pr-body-not-title-to` ops-remediation carve-out does NOT apply.

### Post-merge (operator)

- [ ] **AC13** — None. This is docs-only; the Eleventy build of the plugin docs site re-deploys automatically via the docs CI pipeline once `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` lands on `main`. No DNS, no migration, no apply. Operator action limited to: (a) verify `https://soleur.ai/legal/acceptable-use-policy/` shows the new §4.7/§4.8 within one Eleventy rebuild window, (b) close PR-D's PA2 line-62 follow-up note in the next PA2 amendment by editing the cell to remove the "PR-D follow-up: explicit AUP warning for attachment Art. 9 upload (tracked separately)" sentence (deferred to whichever next legal PR touches PA2; NOT in this PR's scope to avoid expanding into article-30 territory).

## Domain Review

**Domains relevant:** Legal (primary)

### Legal

**Status:** reviewed (carry-forward from pre-resolved CLO assess phase — the feature description explicitly records: "CLO assess phase already ran and confirmed: `docs/legal/acceptable-use-policy.md` is plugin-scoped today...")
**Assessment:** Amendment broadens scope to the hosted Web Platform and codifies the Art. 9 / Art. 10 / CCPA SPI prohibition that already lives in the Article 30 register PA2. Faithful to regulatory text (verifiable against EUR-Lex and California Legislative Information). No new contractual obligation on the operator; the warning is a user-side prohibition that aligns with existing TOMs (filename sanitisation, content-type allowlist, per-user folder isolation per migration 045). T&C §9 incorporates AUP by reference, so the new prohibition lands automatically into the contract surface without a T&C re-consent — acceptable given the change is *prohibitive* (narrows user-permitted conduct) rather than *expansive* of operator processing.

No Product, Engineering, or other domain leader required: pure legal-text amendment to a published policy doc; no UI, no schema, no code path.

### Product/UX Gate

Not applicable. This PR does not create or modify any user-facing page, component, or flow. The AUP page itself is operator-facing (rendered by Eleventy from the mirror); no Pencil wireframes or copywriter review needed. Brainstorm-recommended specialists: none (no brainstorm document for this PR; CLO assessment was pre-resolved upstream).

## GDPR / Compliance Gate (Phase 2.7)

**Trigger evaluation:** This plan touches `docs/legal/acceptable-use-policy.md` — a legal-document surface, not the canonical `hr-gdpr-gate-on-regulated-data-surfaces` regex (schemas, migrations, auth flows, API routes, `.sql` files). None of the four expansion triggers (a)-(d) fire either (no new LLM-bound processing, no single-user-incident threshold declared, no new cron/workflow, no new artifact distribution surface).

**Decision:** Skip `/soleur:gdpr-gate` invocation. The amendment IS the closure of a Critical-finding precursor (PR-D follow-up note in PA2 line 62). Re-invoking the gate against the AUP edit itself would be a self-referential audit — the regulatory analysis already happened upstream when PA2 was authored; this PR transcribes that analysis into the user-facing AUP. Documented for audit trail.

## Infrastructure (IaC) Gate (Phase 2.8)

**Trigger evaluation:** No new infrastructure. No new server, systemd service, cron, vendor account, DNS record, TLS cert, secret, firewall rule, or monitoring webhook. The plan touches three markdown files only.

**Decision:** Skip — no Terraform changes, no apply path, no vendor-tier reality check. Documented for audit trail.

## Test Scenarios

This is a docs-only PR (markdown only — the AC4 scope-out eliminates the single TS-constant bump originally posited in the feature description). No Playwright flows apply. QA skill (`/soleur:qa`) will skip-with-grace given the docs-only nature.

- **T1** — *(SCOPED OUT)* The `tc-document-sha-guard` CI workflow runs on every PR but does NOT depend on this PR's edits (it is scoped to `docs/legal/terms-and-conditions.md` and the T&C mirror only). Expected: pass without intervention.
- **T2** — Grep for `tc-version.ts` consumers of the AUP: `grep -rn "acceptable-use" apps/web-platform/lib/ apps/web-platform/app/` returns 0 matches (verified at plan time). No `bun test apps/web-platform/test/legal/` run needed because no test loads AUP content.
- **T3** — Cross-document parity grep: `grep -c "chat-attachments" docs/legal/acceptable-use-policy.md knowledge-base/legal/article-30-register.md` — post-merge, both must have ≥ 1 match. (Verified at plan time: article-30 has 5 matches; AUP has 0 today, will have ≥ 3 after merge — §2 bullet + §4.7 body + §4.8 reference.)
- **T4** — Eleventy build sanity: from repo root, `npx @11ty/eleventy --dryrun` must complete without error (matches the production command in `.github/workflows/deploy-docs.yml` line for the build step: `run: npx @11ty/eleventy`). Equivalent: `cd plugins/soleur/docs && bun run docs:build` (the package.json script `cd`s up to repo root and invokes the same command). The `--dryrun` flag suppresses writing `_site/` artifacts during plan-time verification. Catches mirror-only markdown syntax issues that would break the published site.

- **T6** — Unicode integrity post-edit: `grep -cF '§' docs/legal/acceptable-use-policy.md plugins/soleur/docs/pages/legal/acceptable-use-policy.md` returns ≥ 4 for each file (1 in §4.7 body cross-reference `§6.2 of this Policy`, 1 in §4.7 body `Art. 9(2)(a)`-style reference is not §-prefixed in drafted text — verify against actual drafted body — and ≥ 2 in §4.8 body for `§4.7` back-references + `§1798.140(ae)` citation). `grep -cF '—' docs/legal/acceptable-use-policy.md plugins/soleur/docs/pages/legal/acceptable-use-policy.md` returns ≥ 2 for each file (em-dash in §4.7 heading "Special-Category and Sensitive Personal Data — Hosted Chat Surface"). Confirms UTF-8 round-trip through the markdown editor was clean (no transcoding to `&#xA7;` or `&mdash;` entities, no accidental ASCII hyphen substitution).
- **T5** — Existing `legal-doc-cross-document-gate.yml` workflow: this gate (active per compliance-posture row for DSAR §3637) requires that PRs touching `apps/web-platform/server/dsar-export.ts` update all four legal docs in lockstep. This PR touches NEITHER `dsar-export.ts` NOR Privacy Policy / GDPR / DPD, so the gate's lockstep rule is not triggered. Pre-merge sanity: verify the gate does NOT misfire on AUP-only edits (read the workflow file briefly during /work Phase 0 to confirm trigger paths).

## Implementation Phases

### Phase 0 — Preconditions (read-only verification)

1. Read `docs/legal/acceptable-use-policy.md` (entire file) and `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` (entire file) — confirm both have §4.6 Shared Content and §6.2 Consequences of Violation as named in Research Reconciliation rows 2-3.
2. Read `.github/workflows/legal-doc-cross-document-gate.yml` — confirm its trigger paths do NOT include `docs/legal/acceptable-use-policy.md` as a standalone fire (per T5).
3. `gh pr view 3988 --json title,body,headRefName,baseRefName` — confirm draft PR exists, base = main, head = `feat-one-shot-issue-3921-aup-art9-ccpa-spi-warning`.
4. `git log --oneline main..HEAD` — confirm only the `chore: initialize` commit is on the branch (no surprise commits to reconcile).

### Phase 1 — Canonical AUP edit

1. Edit `docs/legal/acceptable-use-policy.md`:
   - Frontmatter: `last-updated: 2026-04-10` → `last-updated: 2026-05-18`.
   - Body line 15: `**Last Updated:** April 10, 2026` → `**Last Updated:** May 18, 2026`.
   - §2: insert the new `app.soleur.ai` bullet after the existing last bullet (`Any output, artifact, or action produced by or through the Platform.`) and before the trailing paragraph (`The Plugin operates locally on your machine...`). Bullet text per AC1 verbatim.
   - §4: insert new `### 4.7 Special-Category and Sensitive Personal Data — Hosted Chat Surface` after the existing `### 4.6 Shared Content` (ending at the `<!-- End: KB sharing -->` marker on line 130) and before the `---` separator on line 132. Body text per drafted §4.6 source-of-truth in the feature description, header renamed to §4.7. Cross-reference to `§6.2 of this Policy` preserved.
   - §4: insert new `### 4.8 California Sensitive Personal Information` immediately after the new §4.7 and before the same `---` separator. Body text per drafted §4.7 source-of-truth in the feature description, with the two internal back-references updated: `§4.6` → `§4.7` (two occurrences — "the same prohibition as §4.6" and "incidental ingress will be treated under §4.6").

### Phase 2 — Mirror sync

1. Edit `plugins/soleur/docs/pages/legal/acceptable-use-policy.md`:
   - Page-hero line 11: `Effective February 20, 2026 | Last Updated March 29, 2026` → `Effective February 20, 2026 | Last Updated May 18, 2026`.
   - Body `**Last Updated:** March 29, 2026` (or equivalent body Last-Updated line if present) → `**Last Updated:** May 18, 2026`.
   - Apply the same §2 bullet, §4.7, §4.8 insertions as Phase 1 step 1. Preserve Eleventy frontmatter and `<section class="page-hero">` / `<section class="content">` / `<div class="container">` / `<div class="prose">` scaffolding.

### Phase 3 — Compliance posture update

1. Edit `knowledge-base/legal/compliance-posture.md`:
   - Frontmatter `last_updated:` → `2026-05-18`.
   - Legal Documents table row for Acceptable Use Policy: `2026-03-20` → `2026-05-18`.
   - Append top-of-file dated comment (after the existing dated comment block, before `# Legal Compliance Posture`):
     > `<!-- 2026-05-18: PR #3988 (feat-one-shot-issue-3921-aup-art9-ccpa-spi-warning) — AUP §2 scope broadened to name app.soleur.ai + chat-attachments. New §4.7 prohibits GDPR Art. 9 (special categories) and Art. 10 (criminal convictions) submissions via prompts or attachments. New §4.8 prohibits CCPA SPI (Cal. Civ. Code §1798.140(ae)) via same surfaces. Closes #3921 and PR-D PA2 line-62 follow-up note (note itself removed in next PA2 amendment). No T&C / Privacy Policy / GDPR Policy / DPD changes; no TC_VERSION bump (AUP is incorporated by reference under T&C §9). -->`

### Phase 4 — Verification

1. Run all AC1-AC11 grep verifications listed inline.
2. Run T4 Eleventy build sanity check: from repo root, `npx @11ty/eleventy --dryrun`. Expected: exit 0, no errors. (Matches the production deploy-docs.yml invocation.)
3. Run T5 cross-document-gate path check: read `.github/workflows/legal-doc-cross-document-gate.yml` and confirm the `surface_patterns` array does NOT include `docs/legal/acceptable-use-policy.md`. (Deepen-pass verified at plan time: surface array is DSAR-only; gate exits 0 with "No DSAR surface file touched" on AUP-only edits.)
4. Run T6 unicode integrity check: `grep -cF '§' docs/legal/acceptable-use-policy.md plugins/soleur/docs/pages/legal/acceptable-use-policy.md` and `grep -cF '—' ...` both return non-zero per T6 thresholds.
5. Confirm `git diff --stat main...HEAD` shows exactly three changed files (canonical AUP, AUP mirror, compliance-posture.md).
6. PR body draft includes: (a) `Closes #3921`, (b) Research Reconciliation summary (renumber §4.7/§4.8 reason, §6.2 cross-reference preserved, TC_VERSION/TC_DOCUMENT_SHA scope-out), (c) EUR-Lex and California Legislative Information citations for AC7 and AC8, (d) line-62 PA2 follow-up closure note.

### Phase 5 — Compound learnings

The plan-time research reconciliation surfaced 6 verifiable discoveries that the pre-resolved feature-description block did not contain. Notable learning candidates (not blocking, captured for `/soleur:compound`):

- §4.6 numbering collision (KB sharing already used §4.6 since 2026-04-10) — pattern: any drafted-clause insertion that prescribes a specific section number MUST grep the target file's current section list first.
- Multi-date AUP drift (canonical `April 10, 2026`, mirror `March 29, 2026`, compliance-posture `2026-03-20`) — pattern: legal-doc edits must verify ALL three date surfaces are in sync as part of the AC.
- `TC_DOCUMENT_SHA` scope (T&C only, NOT all legal docs) — pattern: CI guardrail scope MUST be read from the script body, not inferred from naming.

## Risks

- **R1** — Drafted §4.7 source-of-truth uses `§6.2` cross-reference. §6.2 exists and is the closest removal-of-content clause, but its title is "Consequences of Violation" (a broader category than "content removal"). Risk: a future reader may find the cross-reference imprecise. **Mitigation:** preserve as-is for this PR (avoids inventing a §6.2.x sub-clause); record the cross-reference choice in the PR body so a future AUP revisit can tighten it if needed.
- **R2** — §4.6 → §4.7 renumbering inside the source-of-truth drafted text for §4.8 ("the same prohibition as §4.6", "incidental ingress will be treated under §4.6") MUST be applied at edit time, not paste time. AC3's `grep -F 'same prohibition as §4.6' ... returns 0` catches a verbatim-paste regression. **Mitigation:** AC3 grep is the structural gate.
- **R3** — Mirror date drift (mirror was `March 29, 2026` while canonical was `April 10, 2026` before this PR) suggests prior AUP edits did NOT consistently update the mirror. Risk: post-merge, an operator might publish a future AUP amendment that updates only the canonical, breaking the mirror again. **Mitigation:** out of scope for this PR; consider filing a follow-up `legal-doc-cross-document-gate.yml` extension that fires on AUP edits (currently fires on `dsar-export.ts` only). Recorded as compound-learning candidate.
- **R4** — T&C §9 ("Acceptable Use") incorporates the AUP by reference. A material AUP amendment could in principle warrant a T&C re-consent, but this PR's amendment is **prohibitive** (narrows user-permitted conduct toward an already-disclosed regulatory limit) rather than **expansive** of operator processing — re-consent is not legally required. **Mitigation:** Decision recorded in Scope-outs. Operator may file a follow-up if forced re-consent is preferred.
- **R5** — CCPA SPI subsection citation drift. The drafted §4.8 cites `Cal. Civ. Code §1798.140(ae)`. The CPRA-amended California Civil Code reorganized §1798.140 in 2023; subsection letter (ae) is correct as of 2026-05-18 but the California legislature periodically renumbers via uncodified amendments. **Mitigation:** AC8 attestation is the gate — the reviewer (CLO or human) verifies the subsection letter against the current operative text at `https://leginfo.legislature.ca.gov/faces/codes_displaySection.xhtml?sectionNum=1798.140&lawCode=CIV` before merge. If a renumbering has occurred, update §4.8 inline AND record the corrected subsection in the PR body.
- **R6** — legal-doc cross-document gate runs (compliance-posture.md is in the workflow's `paths:` filter) but trivially passes (workflow body exits 0 when no DSAR surface is hit). Visible in GitHub Actions output as a workflow run with `"No DSAR surface file touched — gate trivially passes."` log line. **Mitigation:** Not a risk to the PR — recorded so the operator does not interpret the workflow run as a near-miss or false-alarm.
- **R7** — The drafted §4.7 phrases incidental-ingress handling as "treated under the regulated-data surface handling rule in our internal compliance procedure." A regulator reading the AUP cannot inspect that procedure. **Mitigation:** Cross-reference asymmetry is acceptable for a user-facing AUP because the regulator-facing Article 30 register (PA2 line 62) names the internal rule (`hr-gdpr-gate-on-regulated-data-surfaces`) and the AUP defers to PA2 by name. Recorded for audit trail; no plan change.

## Sharp Edges

- The drafted §4.7 source-of-truth in the feature-description block titles itself `### 4.6 Special-Category and Sensitive Personal Data — Hosted Chat Surface`. The PLAN renames this to §4.7 at edit time. A verbatim copy-paste of the source-of-truth heading would produce a duplicate `### 4.6` and break the AUP. AC2's `grep -c '^### 4.7 Special-Category...' returns 1` catches the regression.
- The drafted §4.8 source-of-truth in the feature-description block titles itself `### 4.7 California Sensitive Personal Information`. The PLAN renames this to §4.8 AND updates the two internal back-references (`§4.6` → `§4.7`). AC3's two greps catch the regression.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is populated with `aggregate pattern` threshold + concrete artifact / vector lines.

## References

- Issue: #3921
- Draft PR: #3988
- Article 30 register PA2 line 62 (controlling disclosure): `knowledge-base/legal/article-30-register.md`
- Article 30 register PA2 amendment that surfaced this follow-up: PR #3883 (PR-D itself, merged 2026-05-16; same PR that filed issue #3921 as a deferred follow-up). (Earlier plan drafts mis-cited PR #3940 — that PR added PA-13, not PA2.)
- T&C bump policy (T&C-only scope, confirms AUP is NOT covered): `knowledge-base/legal/tc-version-bump-policy.md`
- CI guardrail (confirms scope): `apps/web-platform/scripts/check-tc-document-sha.sh` lines 26-28
- Compliance posture: `knowledge-base/legal/compliance-posture.md`
- Hard rule: `hr-gdpr-gate-on-regulated-data-surfaces` (incidental-ingress handling rule cited in §4.7)
- GDPR Art. 9(1) + Art. 10: `https://eur-lex.europa.eu/eli/reg/2016/679/oj`
- Cal. Civ. Code §1798.140(ae): `https://leginfo.legislature.ca.gov/faces/codes_displaySection.xhtml?sectionNum=1798.140&lawCode=CIV`
