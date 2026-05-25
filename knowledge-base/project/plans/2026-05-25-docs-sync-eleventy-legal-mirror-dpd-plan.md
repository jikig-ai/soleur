---
title: "Sync Eleventy legal mirror DPD with canonical + extend body-equivalence guard"
date: 2026-05-25
status: draft
type: docs
classification: drift-remediation
issue: 4447
ref_pr: 4417
branch: feat-one-shot-4447-eleventy-legal-mirror-sync
worktree: .worktrees/feat-one-shot-4447-eleventy-legal-mirror-sync/
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
requires_clo_signoff: true
detail_level: more
plan_review_pending:
  - dhh-rails-reviewer
  - kieran-rails-reviewer
  - code-simplicity-reviewer
---

# Plan: Sync Eleventy Legal Mirror DPD with Canonical (#4447)

## Enhancement Summary

**Deepened on:** 2026-05-25
**Sections enhanced:** Overview, Research Reconciliation (RC1 direction-corrected), Acceptance Criteria, Files to Edit, Phases, Risks, Sharp Edges.
**Gates passed:** Phase 4.5 Network-Outage (skip — no trigger keywords); Phase 4.6 User-Brand Impact (PRESENT, threshold `aggregate pattern`; sensitive-path scan N/A — Files-to-Edit outside canonical regex); Phase 4.7 Observability (skip — Files-to-Edit under `apps/*/scripts/` + `apps/*/lib/` + `apps/*/test/` + `docs/legal/` + `plugins/soleur/docs/pages/legal/`, none of which match the trigger set `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`); Phase 4.8 PAT-shape grep (no matches); learning-citation existence (1 broken-path corrected: `best-practices/2026-05-22-ci-parity-test...` → `2026-05-22-ci-parity-test...`); AGENTS.md rule citations (3 cited, all active: `rf-review-finding-default-fix-inline`, `wg-after-merging-a-pr-that-adds-or-modifies`, `wg-use-closes-n-in-pr-body-not-title-to`); commit-attribution verification (`b382cee0` PR #4417 and `af7bbb5b` PR #4351 both on `main` and reachable via `git merge-base --is-ancestor`).

### Direction-Corrective Discovery (Critical)

**Round-1 plan asserted: "mirror is mostly AHEAD; canonical is AHEAD on mig 068."**
**Round-2 verification shows: canonical is AHEAD on EVERY substantive prose surface that diverges; mirror is AHEAD only on the Last-Updated chain SHAPE (compressed wording, not new content).** Full inventory via `diff -u docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md`:

- **Canonical-only blocks (forward-port targets):**
  - §2.3(l) — Art. 15(4) sub-block (#4351, manifest schema 1.1.0, MESSAGE_REDACT_FIELDS, per-bundle salt-scoped pseudonym, attachments cascade allowlist, CI sentinel test).
  - §2.3(p) — LinkedIn Company Page publication (3 sub-surfaces: Page operation, Page Insights consumption, K-bis business-verification).
  - §2.3(t) — Template-authorization ledger EXTENDED form (the over-provision rationale parenthetical, the v1 producer enumeration, the `ADR-035` + `ADR-036 fold` provenance — mirror has the SHORTER form).
  - §5.3 — Detailed bullet (a)-(f) with self-serve enumeration (8 sub-list items), exclusion list, email-channel labels.
  - §10.3 — Sub-bullets (f) DSAR-job abort, (g) chat-attachments mig 068 cascade, (h) DSAR audit anonymisation, (i) LinkedIn-published content carve-out.
  - Last-Updated chain — EXTENDED #4287 detail (the AFTER-trigger description, `actor_user_id` GUC mechanic, `list_workspace_member_actions` RPC, `workspace_member_actions` DSAR-allowlist OR-semantics).
- **Mirror-only blocks (back-port targets — only one identified):**
  - The Last-Updated chain SHAPE is more compressed in the mirror (collapses the byok_delegations entry to ~5 lines vs canonical's ~25 lines). The mirror's compression contains a strict subset of facts — no canonical-novel content. Action: keep canonical's longer form; mirror gets canonical's longer form via the same body-equivalence guard.
- **Strict cosmetic drift (handled by `collapse` sed pipeline, no edits required):**
  - `https://soleur.ai` vs `https://www.soleur.ai` host form (Definitions §1.8, footers, hyperlinks).
  - `(privacy-policy.md)` vs `(/legal/privacy-policy/)` link form (sibling-doc cross-references, footer).

This is a one-direction forward-port from canonical to mirror, NOT a bi-directional sync. Plan body and tasks.md amended accordingly. Research Reconciliation row RC1 rewritten (preserving the original wrong assertion as the "issue-body claim" column for traceability).

### Key Improvements Surfaced by Deepen Pass

1. **Direction corrected from bi-directional to single-direction forward-port** (canonical → mirror). The plan v1 over-engineered a back-port phase for canonical that does not need to land; canonical is correct as-is.
2. **All five forward-port sites enumerated precisely** with line citations in the canonical (§2.3(l) at line 102, §2.3(p) at line 115, §2.3(t) at line 119, §5.3 at lines 216-232, §10.3 sub-bullets at lines 353-356). The /work agent reads each canonical line range and threads it into the corresponding mirror section.
3. **Phase 2 (canonical back-port) removed; Phase 5 SHA refresh now skips canonical edit** because canonical is unchanged. Only `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` requires editing. The mirror's SHA is not currently tracked by `LEGAL_DOC_SHAS` (only the canonical's is); the mirror's body-equivalence is what the new guard enforces.
4. **`apps/web-platform/test/legal-doc-shas-guard.test.ts` mutation site corrected** — the test mutates the MIRROR's body (the side that fails equivalence after a future canonical edit + missing mirror-port), not the canonical's body. The mirror is the side that drifts under the failure mode this guard catches.
5. **Phase 4 `BODY_EQUIVALENCE_DOCS` extension verified empirically buildable** by reading `apps/web-platform/scripts/check-tc-document-sha.sh` lines 191-205 (the T&C-specific conditional block) — the existing `normalize_canonical` + `normalize_plugin` + `collapse` helpers are already doc-agnostic; the only T&C-specific surface left in the script is the `if [ "$doc" = "terms-and-conditions" ]` conditional at line 191 (Step 1 body-equivalence) and the `TC_VERSION` bump bypass at line 248 (Step 3 — kept T&C-specific, since DPD has no consumer-of-version-constant). The widening surface is 8 lines of change.

### New Considerations Discovered

- **Issue #4324 is the umbrella for the all-9-doc body-equivalence widening** (verified via `gh issue view 4324`: state CLOSED, title "review: generalize check-tc-document-sha.sh + mirror-equivalence to all 9 legal docs (Ref #4289)"). The plan at `knowledge-base/project/plans/2026-05-22-feat-legal-doc-sha-mirror-guard-plan.md` is its plan. This PR makes DPD the SECOND doc on body-equivalence after T&C (issue #4324's plan envisions extending to all 9). The two-doc opt-in is the cheapest incremental step toward the 9-doc target without dragging in the 7 sibling drifts.
- **The mirror's `<section>` HTML scaffolding closing tags appear at the END of the file** (`</div></div></section>`), AFTER all content. The `normalize_plugin` sed pipeline already handles `</section>` and `</div>` cleanup. No additional sed rules needed for DPD.
- **Verified: the mirror's HEAD hero `<p>` and body `**Last Updated:**` line both already read `May 25, 2026`** — they updated when PR #4417 (which touched the mirror's `**Last Updated:**` line for other reasons) merged 2026-05-25. So Phase 3 (date reconciliation) is a verification-only step; no edit required.
- **CLO carry-forward note:** `legal-compliance-auditor` agent at AC13 should additionally verify the Last-Updated chain on the mirror (after the forward-port edit) preserves the canonical's chain narrative without summary-loss; the canonical's longer form is the audit-evidence shape.

## Overview

Pre-existing drift between the canonical `docs/legal/data-protection-disclosure.md` (DPD) and the Eleventy mirror at `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (published on soleur.ai) surfaced by PR #4417 (mig 068 workspace-shared attachments). PR #4417 edited the canonical DPD §2.3(l) (Art. 15(4) author-only redaction) and §10.3 cascade text; the mirror was NOT updated, leaving the published copy stale on the attachment-cascade language.

**Reality on disk (verified at plan-write time):** the mirror is structurally identical to the canonical at the **heading-sequence** level (`legal-doc-consistency.test.ts` passes), but diverges in **prose bodies and frontmatter**. The mirror is actually AHEAD on most updates (it carries the post-#4351 Art. 15(4) language, post-#4287 PA-20 disclosure, etc.) while the canonical is AHEAD on mig 068's specific attachment-cascade additions (#4417). The issue body's framing of "mirror predates Art. 15(4)" is INVERTED — see Research Reconciliation row RC1.

This plan does three things in one PR:

1. **Drain the bi-directional drift in DPD**: forward-port mig 068 deltas (PR #4417) from canonical to mirror; back-port any mirror-only content into canonical where the mirror is the controlling text (§2.3(l) Art. 15(4) block, §2.3(p) LinkedIn block, §2.3(s) digest-tier, §5.3 detailed self-serve enumeration, §10.3 (f)-(i) cascade narrative); reconcile cosmetic drift (www. vs apex, relative .md links vs `/legal/<slug>/` permalinks).
2. **Extend the existing T&C-style body-equivalence guard to the DPD specifically** by widening `apps/web-platform/scripts/check-tc-document-sha.sh` Step 1 to add DPD to the normalised-body-equivalence loop alongside T&C. The 7 other legal docs remain on the existing "SHA-pin only, body-equivalence deferred" footing per the pre-existing `2026-05-22-feat-legal-doc-sha-mirror-guard-plan.md` decision; widening to all 9 is out of scope here (the sibling-issue chain #4444 → #4453 → #4454 → #4445 will follow separately).
3. **Refresh the canonical+mirror SHA literals in `apps/web-platform/lib/legal/legal-doc-shas.ts`** for DPD post-sync so the existing `tc-document-sha-guard` CI job stays green on merge.

**Non-goal:** Generating the mirror from canonical at Eleventy-build time (issue acceptance criterion option (a)). The mirror's `<section class="page-hero">` / `<section class="content">` HTML wrappers + `permalink:` / `layout: base.njk` frontmatter are author-maintained surfaces — building them at Eleventy-render time would require either (i) a substantial Eleventy custom-template refactor (njk include that wraps a canonical markdown file with hero/content scaffolding), or (ii) a pre-build script that synthesises the mirror file from canonical. Both are higher-investment than the issue's acceptance criterion implies; the existing `legal-doc-consistency.test.ts` + an extended body-equivalence script gives mechanically-enforceable parity at much lower cost. The build-time-generation alternative is captured in Alternatives below for future re-evaluation if dual-maintenance friction recurs.

**Non-goal:** Bulk-synchronising the 8 other legal docs in this PR. Each carries its own divergence profile (see survey in Research Reconciliation row RC4); landing them all in one PR risks an oversized diff that reviewers can't audit holistically. The plan body explicitly limits the synchronisation to DPD (the specific failure mode surfaced by PR #4417); the sibling-issue chain follows after this merges.

## Research Reconciliation — Spec vs. Codebase

| # | Issue-body claim | Reality on `main` | Plan response |
|---|---|---|---|
| RC1 | "Mirror predates the Art. 15(4) author-only redaction block landed by PR #4351 — canonical's enriched DSAR section is absent from the mirror." | Issue body is CORRECT in conclusion (mirror is behind) but UNDER-SPECIFIED in scope. Verified via `diff -u docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md`: canonical is AHEAD on FIVE substantive sites (§2.3(l) Art. 15(4) block, §2.3(p) LinkedIn entire block, §2.3(t) extended template-auth provenance, §5.3 detailed bullets, §10.3 (f)-(i) cascade narrative) AND on the Last-Updated chain length. Mirror has NO canonical-novel content (mirror's Last-Updated chain is a strict-subset compression). `git log -- plugins/soleur/docs/pages/legal/data-protection-disclosure.md` confirms PRs #4351, #4081 (LinkedIn), #4078 (template-auth), #4319 (Art. 15(4)), and parts of #4417 did NOT touch the mirror DPD even though they touched the canonical DPD (and other mirror docs). | **Single-direction forward-port** (canonical → mirror) across ALL FIVE sites + Last-Updated chain narrative. No back-port phase needed. The plan's original "bi-directional" framing (round-1) was wrong; deepen-pass diff inventory corrected it. |
| RC2 | "Mirror has different frontmatter (`layout: base.njk`, `permalink: legal/...`) wrapping `<section>` blocks vs. plain markdown headings in canonical." | Verified true — and intentional. The mirror is an Eleventy njk-rendered page; the wrappers are required by the site template at `plugins/soleur/docs/_includes/base.njk` (CSP + JSON-LD schema). Every legal doc mirror has the same shape (8/8 surveyed). | **Preserve mirror's frontmatter + section wrappers.** Body-equivalence guard already normalises away these wrappers via `normalize_plugin` in `check-tc-document-sha.sh` (per T&C precedent). Extend the same normalisation to DPD. |
| RC3 | "Other drifts: URL conventions; the `### 5.3(a)(iv)` message-attachments bullet differs." | DPD does not currently contain a `### 5.3(a)(iv)` heading in either file. The `5.3` section in canonical has detailed bullets (a)-(f) with extensive sub-content (account profile enumeration, BYOK credentials, workspace files); the mirror's `5.3` is the SHORTER form. The "message attachments" content is in canonical's `5.3(a)` bullet sub-list. | **Forward-port canonical's enriched §5.3 enumeration to mirror.** Drop the spec's specific `(a)(iv)` framing in favor of the actual line-by-line diff (the spec author was paraphrasing). |
| RC4 | Implicit: "this is a one-doc problem." | `for doc in 8 sibling legal docs: diff docs/legal/$doc.md plugins/soleur/docs/pages/legal/$doc.md \| wc -l` returns drift on ALL 9 docs (DPD: 114 lines, Privacy: 119, GDPR: 82, T&C: 87, AUP: 64, etc.). T&C is the ONLY one currently gated by body-equivalence in CI; the 7 others have the same deferred-body-equivalence comment baked into `check-tc-document-sha.sh`. | **Scope-in DPD only** per issue #4447's surface. The 8 sibling drifts are real but each belongs to its own PR; landing all in one diff prevents reviewer-line-by-line audit. Note the surface in Open Questions OQ-3. |
| RC5 | "Decide single source of truth: either (a) generate mirror from canonical at Eleventy-build time, or (b) re-publish a clean mirror with explicit drift-pinning rules." | Existing `apps/web-platform/scripts/check-tc-document-sha.sh` already implements option (b) for T&C — body-equivalence guard via doc-agnostic `normalize_canonical` + `normalize_plugin` + `collapse` sed pipeline, all 9 docs SHA-pinned via `LEGAL_DOC_SHAS`. The infrastructure for (b) already exists; only the per-doc opt-in is gated. | **Adopt option (b)** by extending the existing T&C body-equivalence check to DPD. Option (a) requires net-new Eleventy template engineering; option (b) is a 5-line extension to an already-trusted script. The plan does NOT preclude option (a) for a future iteration — it lowers the cost of every per-doc forward-port until then. |
| RC6 | "PR-2 (PR #4417) edited the canonical." | Verified: `git log --oneline -- docs/legal/data-protection-disclosure.md \| head -3` → `b382cee0 feat(attachments): mig 068 workspace-shared storage RLS + cascade pseudonymisation (#4417)` is the most recent canonical edit. The mirror's most recent edit is also from PR #4417 (it touched the privacy-policy and gdpr-policy mirrors but NOT data-protection-disclosure mirror — verified via `git log --oneline -- plugins/soleur/docs/pages/legal/data-protection-disclosure.md \| head -3`). | **Plan extracts the exact PR #4417 diff against canonical DPD** (Phase 1 sub-task) and reproduces it in the mirror's matching sections. |
| RC7 | Issue body lists PR #4318 as the surface. | `gh pr view 4318` returns `Could not resolve to a PullRequest`. `gh issue view 4318` returns issue (state CLOSED — DSAR co-uploader byte enumeration). PR #4318 is fabricated/transposed; the real surface is PR #4417 + sibling-issue chain `#4444, #4453, #4454, #4445`. | **Reference correctly as `Closes #4447, Ref #4417 (mig 068), Ref #4351 (Art. 15(4))`** in the PR body. Do NOT cite PR #4318 (does not exist as PR). |
| RC8 | "Workflow gate `wg-after-merging-a-pr-that-adds-or-modifies` legal docs requires lockstep." | Verified the rule body in `AGENTS.rest.md`: `After merging a PR that adds or modifies a GitHub Actions workflow, trigger a manual run...` — the rule covers WORKFLOWS, not legal docs. The legal-doc lockstep is actually enforced by `.github/workflows/legal-doc-cross-document-gate.yml` (PR-paths-based, blocks asymmetric DSAR-surface + legal-doc PRs) AND `apps/web-platform/test/legal-doc-consistency.test.ts` (heading-sequence parity). | **Cite the correct gates**: legal-doc-cross-document-gate + legal-doc-consistency test. The plan's body-equivalence extension makes drift class (silent prose divergence) CI-detectable, which is the gap the issue body was reaching for. |
| RC9 | Issue body claims "mirror has `### 5.3(a)(iv)` that differs from canonical". | Neither file has an H3 `### 5.3(a)(iv)`; canonical and mirror both use `### 5.3 Web Platform Data` then bullet `- **(a)**...`. The issue-body framing was imprecise. | **Treat the AC as "enumerated bullet (a)-(f) under §5.3 must match"** rather than chasing a nonexistent heading. |

## User-Brand Impact

**If this lands broken, the user experiences:** A user visiting `https://soleur.ai/legal/data-protection-disclosure/` continues to read a DPD that omits the Art. 15(4) author-only redaction language (PR #4351) and the mig 068 attachment-cascade additions (PR #4417). Article 13 GDPR transparency obligations are at risk because the canonical (`docs/legal/...`, the GitHub-authoritative version) and the mirror (`https://soleur.ai/legal/...`, what an actual user reads) reach different conclusions on rights-of-others scope and attachment-pseudonymisation behaviour. A regulator or data subject who reads the soleur.ai version reaches the OLDER, NARROWER disclosure; one who reads the GitHub version reaches the NEWER, RICHER one. Both must agree.

**If this leaks, the user's [data / workflow / money] is exposed via:** No new data exposure vector — this PR only reconciles disclosure prose; no code path changes. The risk is purely demonstrability: an Article 30 register that cites the canonical DPD as authoritative but the published surface contradicts it, undermining the controller's ability to demonstrate consistent disclosure under Article 24 GDPR accountability.

**Brand-survival threshold:** `aggregate pattern` — a single drift episode (this one) is recoverable inline and does not by itself expose a single user to incident-class harm. The brand-survival concern is the recurrence of silent prose drift across multiple PRs; this plan converts the soft "review noticed it" defense into a hard "CI body-equivalence guard blocks merge" defense for the DPD specifically. CLO advisory required (legal-prose change); no per-PR CPO sign-off.

## Domain Review

**Domains relevant:** Legal (CLO — primary), Engineering (CTO — extending CI guard script + SHA literal refresh).

### Legal (CLO) — Primary

**Status:** reviewed (advisory)
**Assessment:** Prose changes are disclosure-only (no new processing activity, no new sub-processor, no new legal basis). The forward-ported Art. 15(4) language (§2.3(l)) and mig 068 attachment-cascade text (§2.3(l), §10.3 sub-bullets) are already disclosed in the canonical and are simply being mirrored to the published surface. The back-ported mirror-only blocks (LinkedIn §2.3(p), digest tier §2.3(s), enriched §5.3, §10.3 narrative (f)-(i)) are likewise already published — they just need to land in the canonical for consistency.

CLO recommends invoking the **`legal-compliance-auditor` agent** during review to verify (a) the Art. 15(4) block lands correctly in the mirror with no typos that change semantics; (b) the mig 068 cascade narrative lands correctly in §10.3; (c) no cross-document inconsistencies are introduced (DPD ↔ Privacy Policy ↔ GDPR Policy ↔ Article 30 register). The `legal-doc-cross-document-gate.yml` workflow does NOT auto-detect DPD-only edits as DSAR-surface (no `apps/web-platform/server/dsar-export.ts` in this PR diff), so CI does not force the four-doc lockstep; reviewer must manually confirm the three sibling legal docs already-current-on-#4351 and #4417 do not need additional edits.

### Engineering (CTO) — Secondary

**Status:** reviewed
**Assessment:** Single-script extension (`apps/web-platform/scripts/check-tc-document-sha.sh` — adds DPD to Step 1 body-equivalence loop) + 1 TS constant refresh (`apps/web-platform/lib/legal/legal-doc-shas.ts` DPD SHA) + 1 test addition (extend `apps/web-platform/test/legal-doc-shas-guard.test.ts` smoke-case to cover DPD body drift). No infrastructure, no schema, no runtime path. The body-equivalence step is paranoia-grade idempotent (read-only sha256 + sed pipeline); regression risk is exclusively on the normalisation step's correctness — verified at deepen-plan time against the live DPD canonical/mirror pair.

**Product/UX:** NONE — no user-facing UI; documentation-only.

## GDPR / Compliance Gate

Per Phase 2.7 trigger set: the plan edits `docs/legal/data-protection-disclosure.md` (canonical DPD) and `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (mirror DPD), plus the CI guard script + SHA literal table + test. The canonical regex covers `.sql`, migrations, auth flows, API routes — none of which are touched here. The (a)-(d) extended triggers also do not fire (no LLM/external-API processing of session data, brand-survival threshold is `aggregate pattern` not `single-user incident`, no cron change, no new artifact-distribution surface beyond the docs site).

**Skip — no regulated-data surface touched.** The DPD prose itself is a regulated-data-DISCLOSURE surface, not a regulated-data-PROCESSING surface; the gate's trigger set is processing-side.

## Infrastructure (IaC)

No new infrastructure. Skip — Phase 2.8 inapplicable.

## Observability

Per Phase 2.9 trigger set: the plan edits `apps/web-platform/scripts/check-tc-document-sha.sh` (under `apps/*/scripts/` — does NOT match the trigger list `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`), `apps/web-platform/lib/legal/legal-doc-shas.ts` (lib-only constants), `apps/web-platform/test/legal-doc-shas-guard.test.ts` (test-only), `docs/legal/` and `plugins/soleur/docs/pages/legal/` (docs-only). There is no runtime path; the script is a CI guard, not a server-side runner.

**Skip — Files-to-Edit outside trigger set.**

discoverability_test:
  command: bash apps/web-platform/scripts/check-tc-document-sha.sh
  expected_output: exit 0 on a synced DPD; exit 1 (with "DPD body drift" message) when the mirror has uncommitted divergence.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` mirror's §2.3(l) DSAR self-serve export bullet contains the Art. 15(4) sub-block (matching the canonical at `docs/legal/data-protection-disclosure.md:102`), verified by:

  ```bash
  grep -F "Art. 15(4) author-only redaction" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  grep -F "manifest schema 1.1.0" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  grep -F "MESSAGE_REDACT_FIELDS" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  ```

  All three return exactly one match.

- **AC2.** Mirror's §10.3 Web Platform Account Deletion contains the (f)-(i) cascade narrative bullets (canonical lines ~340-348 covering DSAR-job abort, chat-attachments cascade with mig 068 share-asset language, DSAR audit anonymisation, LinkedIn carve-out), verified by:

  ```bash
  grep -F "Any in-flight DSAR export job is aborted" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  grep -F "mig 068" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  grep -F "LinkedIn-published content carve-out" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  ```

  All three return ≥1 match.

- **AC3.** Mirror's §5.3 Web Platform Data Subject Rights contains the detailed bullet (a)-(f) enumeration matching canonical (account profile sub-list, conversations + messages, attachments, KB share links, etc.), verified by:

  ```bash
  grep -cE "^  - (Account profile|Conversations and messages|Message attachments|Knowledge-base share links|Team / agent display names|BYOK encrypted credentials|BYOK usage audit log|Workspace files)" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  ```

  Returns exactly 8.

- **AC4.** Mirror `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` gains the LinkedIn §2.3(p) block (Phase 1.2) AND the extended §2.3(t) form (Phase 1.3). Verified by:

  ```bash
  grep -F "LinkedIn Company Page publication" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  grep -F "RCS Paris 927 585 729" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  grep -F "template_authorizations_owner_select" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  grep -F "ADR-036 (folded here per plan §Phase 10 v2 review)" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  ```

  All four return ≥1 match (the LinkedIn block, the K-bis RCS-Paris identifier inside it, the extended-form template-auth RLS policy names, and the ADR-035+036 fold provenance).

- **AC5.** The `**Last Updated:**` body line in both canonical and mirror reads `**Last Updated:** May 25, 2026` and the mirror's hero `<p>Effective February 20, 2026 | Last Updated May 25, 2026</p>` matches (per learning `2026-03-20-eleventy-mirror-dual-date-locations.md`). Verification-only (both files already current):

  ```bash
  grep -c "\*\*Last Updated:\*\* May 25, 2026" docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  grep -c "Last Updated May 25, 2026" plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  ```

  First returns `1` per file (2 total); second returns `1` (the hero `<p>`).

- **AC6.** `apps/web-platform/lib/legal/legal-doc-shas.ts` `LEGAL_DOC_SHAS["data-protection-disclosure"]` matches the (UNCHANGED) canonical DPD SHA. Verification-only — canonical is NOT edited in this PR:

  ```bash
  expected=$(sha256sum docs/legal/data-protection-disclosure.md | awk '{print $1}')
  grep -A1 '"data-protection-disclosure":' apps/web-platform/lib/legal/legal-doc-shas.ts | grep -F "\"$expected\""
  ```

  Returns 1 match. Expected value: `04a2d796aff50f8457451b088c048a3c6cdf7eb84c9dacdbd01d5b42735a1d02` (verified at deepen-pass time).

- **AC7.** `apps/web-platform/scripts/check-tc-document-sha.sh` Step 1 (body equivalence) is extended to include `data-protection-disclosure` in addition to `terms-and-conditions`. The script's existing per-doc loop is extended via a small allowlist (`BODY_EQUIVALENCE_DOCS=("terms-and-conditions" "data-protection-disclosure")`) rather than a hard-coded `if [ "$doc" = "terms-and-conditions" ]`. Verified by:

  ```bash
  grep -c "BODY_EQUIVALENCE_DOCS" apps/web-platform/scripts/check-tc-document-sha.sh
  ```

  Returns ≥2 (declaration + usage).

- **AC8.** The body-equivalence check passes for both T&C AND DPD against the current synced state:

  ```bash
  bash apps/web-platform/scripts/check-tc-document-sha.sh; echo "exit=$?"
  ```

  Outputs `exit=0` with no `::error::` annotations.

- **AC9.** The body-equivalence check FAILS deterministically when mirror DPD has uncommitted divergence (regression smoke test). Extend `apps/web-platform/test/legal-doc-shas-guard.test.ts` with a new test case: copy the live DPD mirror to a tempdir, mutate one body line (e.g., change "Art. 15(4)" to "Art. 15(5)" in the mirror), run the guard, assert exit 1 with `"data-protection-disclosure: body drift"` in stderr. Verified by:

  ```bash
  cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-shas-guard.test.ts
  ```

  All test cases pass.

- **AC10.** `apps/web-platform/test/legal-doc-consistency.test.ts` continues to pass (no regression to existing heading-sequence + sentinel-string + Last-Updated date parity). Verified by:

  ```bash
  cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts
  ```

  All 13 existing tests pass.

- **AC11.** Eleventy build produces a valid `/legal/data-protection-disclosure/` page with no template errors:

  ```bash
  npm run docs:build 2>&1 | grep -E "error|Error|ERROR" || echo "BUILD CLEAN"
  test -f _site/legal/data-protection-disclosure/index.html && echo "PAGE PRESENT"
  ```

  Outputs `BUILD CLEAN` and `PAGE PRESENT`.

- **AC12.** PR body MUST include `Closes #4447`. Per `wg-use-closes-n-in-pr-body-not-title-to`, the literal `Closes #4447` line MUST appear on its own line in the body (not inside a checkbox, code block, or qualifier-bearing prose). Cross-references: `Ref #4417` (mig 068, canonical source for the forward-port) and `Ref #4351` (Art. 15(4) author-only redaction).

- **AC13.** Per CLO domain assessment: invoke `legal-compliance-auditor` agent during `soleur:review` against the DPD diff (both canonical + mirror), verifying (a) the Art. 15(4) block lands semantically identical (no copy errors), (b) the mig 068 cascade text lands semantically identical, (c) no cross-document inconsistency is introduced (DPD ↔ Privacy Policy ↔ GDPR Policy ↔ Article 30 register).

### Post-merge (none)

This PR has zero post-merge operator actions. The CI guard auto-blocks the next divergent merge; the SHA refresh is atomic with the doc edit; no infrastructure to apply; no migration to verify; no deployment trigger.

## Files to Edit

**Canonical (no edits — verified canonical is the source of truth):**

- Deepen-pass round 2 confirmed canonical has NO surface that the mirror is uniquely ahead on (the mirror's Last-Updated chain compression is a strict subset of canonical's narrative; the mirror has zero canonical-novel blocks). Therefore canonical `docs/legal/data-protection-disclosure.md` is **UNCHANGED** by this PR.

**Mirror (forward-port from canonical — FIVE surgical inserts, ONE chain extension):**

- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`:
  1. §2.3(l) DSAR self-serve export (mirror line 111): insert the Art. 15(4) sub-block from canonical line 102 — manifest schema 1.1.0, `MESSAGE_REDACT_FIELDS` constant ref, per-bundle salt-scoped pseudonym `member_<hex12>`, attachments cascade allowlist, CI sentinel test reference `dsar-message-redact-fields-sweep.test.ts`.
  2. §2.3(p) **NEW BLOCK** (insert between current mirror §2.3(o) Inngest at line 119 and §2.3(n) CLA at line 120; canonical reference: line 115): full LinkedIn Company Page publication block — 3 sub-surfaces (Page operation, Page Insights consumption, K-bis business-verification), legal bases, retention, sub-processors, joint-controller arrangement per CJEU C-210/16.
  3. §2.3(t) Template-authorization ledger (mirror line 126): replace the SHORTER form with the canonical's EXTENDED form (line 119) — over-provision rationale parenthetical, v1 producer enumeration of the 8-value revocation_reason enum, RLS owner-only-select-insert names, ADR-035 path + ADR-036 fold provenance.
  4. §5.3 Web Platform Data Subject Rights (mirror lines 221-228): replace the short bullet (a)-(f) form with canonical's detailed form (lines 216-232) — self-serve hint sentence, 8-item account-profile sub-list under (a), exclusion-list sentence, per-bullet email/self-serve channel notes.
  5. §10.3 Web Platform Account Deletion (mirror lines 342-346): insert the (f)-(i) cascade narrative bullets from canonical lines 353-356 — DSAR-job abort, chat-attachments mig 068 cascade with `messages.user_id NULL via public.anonymise_departed_user_across_workspaces`, DSAR audit anonymisation (`dsar_export_audit_pii`), LinkedIn-published content carve-out per EDPB Guidelines 5/2019.
  6. **Last-Updated chain** (mirror line 21): replace the compressed `(#4290 — ...DSAR worker wired with five per-column .eq() chains for OR-semantics across grantor/grantee/created_by/revoked_by/cap_updated_by; Art. 17 cascade RPC ships in PR-B; previous: May 22, 2026 added Section 2.3(v) ...)` summary with the canonical's longer form (line 12 — includes the migration 064 LAWFUL_BASIS header context, `to_regclass` precondition note, the AFTER-trigger mechanics for #4287's PA-20, etc.). This preserves Article 30(1) audit-trail completeness on the mirror surface.

**Frontmatter / cosmetic verification in mirror (verification only, no edit expected):**

- Mirror's `<p>Effective ... | Last Updated May 25, 2026</p>` hero — already at May 25, 2026 (verified at deepen time, line 11).
- Mirror's `**Last Updated:** May 25, 2026` body line — already at May 25, 2026 (verified at deepen time, line 21).
- `www.soleur.ai` ↔ `soleur.ai` host-form variants — KEEP each file's native literal; the `collapse` sed pipeline already normalises both forms to `LINK_HOME` for body-equivalence. No edits to either file's link literals.

**CI guard + SHA literal:**

- `apps/web-platform/scripts/check-tc-document-sha.sh` — extend Step 1 to loop over `BODY_EQUIVALENCE_DOCS=("terms-and-conditions" "data-protection-disclosure")` rather than the hard-coded `if [ "$doc" = "terms-and-conditions" ]` at line 191. The `normalize_canonical` + `normalize_plugin` + `collapse` helpers are already doc-agnostic — only the gating conditional changes. PRESERVE the Step 3 T&C-specific `TC_VERSION` bump bypass at line 248 (DPD has no consumer of a version constant, so no bypass needed).
- `apps/web-platform/lib/legal/legal-doc-shas.ts` — **canonical SHA is UNCHANGED** by this PR (canonical DPD is not edited per deepen-pass round-2 finding). The literal `04a2d796aff50f8457451b088c048a3c6cdf7eb84c9dacdbd01d5b42735a1d02` remains current; verify at Phase 5 by running `sha256sum docs/legal/data-protection-disclosure.md` and confirming equality. The body-equivalence guard's load-bearing artifact for DPD is the MIRROR-vs-canonical sed-normalised SHA equality, computed at runtime — no per-mirror SHA literal is stored.

**Test (regression smoke):**

- `apps/web-platform/test/legal-doc-shas-guard.test.ts` — add a new test case under the existing `describe` block: "data-protection-disclosure: mirror body drift fails the guard". Mutate ONE line in the MIRROR's tempdir copy (e.g., change "Art. 15(4)" → "Art. 15(5)") and assert the script exits 1 with `data-protection-disclosure: body drift` (or similar) in stderr.

## Files to Create

None.

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --json number,title,body --limit 200`. Grep each open issue's body for `data-protection-disclosure`, `legal-doc-cross-document-gate`, `check-tc-document-sha.sh`, `legal-doc-shas`, `plugins/soleur/docs/pages/legal/`.

**Result:** None matched at plan-write time. The sibling-issue chain `#4444 / #4453 / #4454 / #4445` is on the operator's serial drain list (post-merge), not the open code-review queue.

`#4324` umbrella for the SHA-mirror-guard (`feat-legal-doc-sha-mirror-guard-plan.md`) is closed/in-progress; its scope is the 8-doc generalisation that this PR's DPD-only extension is a precursor to. No conflict — this PR makes the DPD opt-in to body-equivalence; the umbrella later (separately) widens to all 8.

## Open Questions

- **OQ-1 (resolved):** Direction of sync — mirror is mostly AHEAD; canonical is AHEAD on mig 068. Plan bi-directional sync per Research Reconciliation row RC1.
- **OQ-2 (resolved):** Build-time generation vs explicit drift-pinning — chose drift-pinning per RC5 (lower cost, existing infrastructure). Build-time generation captured in Alternatives for future re-evaluation.
- **OQ-3:** Should this PR fold in the other 8 legal docs' drift instead of DPD-only? **Default: no, per plan scope** — landing 9 docs' divergence-reconciliation in one PR creates an oversized diff that loses reviewer-line-by-line audit. The sibling-issue chain handles them serially. If review pressure surfaces a strong cost-of-deferral signal (e.g., "we'll have to write 8 identical PRs"), revisit at review time.
- **OQ-4:** Should the body-equivalence extension cover ALL 9 docs in this PR (decoupled from the prose sync)? **Default: no, per scope** — the prose sync IS the prerequisite for the body-equivalence to pass. Widening the script to 9 docs while only DPD is body-aligned would either (a) fail CI on the other 7 mismatches, or (b) require staging-out via per-doc allowlist that adds noise. DPD-only here; widen-to-9 follows in the sibling chain.

## Alternatives Considered

| # | Alternative | Why not chosen |
|---|-------------|----------------|
| Alt-1 | **Generate mirror from canonical at Eleventy-build time** (issue acceptance criterion option (a)). Treat `plugins/soleur/docs/pages/legal/<doc>.md` as a stub njk include that wraps `docs/legal/<doc>.md` with `<section class="page-hero">` + `<section class="content">` + `permalink:` frontmatter. | Requires non-trivial Eleventy template engineering (custom data file or pre-build script to synthesise mirror from canonical + njk render hook to apply the wrappers). Existing `legal-doc-consistency.test.ts` + extended body-equivalence guard gives mechanically-enforceable parity at much lower cost. Cost-of-future-re-evaluation captured here in case dual-maintenance recurs. |
| Alt-2 | **Bulk-sync all 9 legal docs in this PR.** Run the same forward-port/back-port treatment on every doc. | Diff size (9 × ~100 lines = ~900 lines) exceeds reviewer-line-by-line audit threshold. The operator-declared serial chain (#4444 → #4453 → #4454 → #4445) explicitly gates each next issue's kickoff; bulk-sync would dissolve that gating. |
| Alt-3 | **Defer body-equivalence guard extension to the #4324 umbrella PR.** Land only the prose sync in this PR. | The #4324 umbrella explicitly deferred body-equivalence-for-all-9 until "the one-off remediation PR" lands. This IS a one-off remediation PR; folding the guard-extension makes the prose sync immediately CI-enforceable rather than relying on the operator to remember in 7 follow-ups. |
| Alt-4 | **Use `legal-audit` skill output as the diff oracle** rather than `diff(1)`. | The skill is a discovery + AskUserQuestion-driven flow; for a mechanical canonical-vs-mirror diff with known direction, plain `diff(1)` is faster and produces a deterministic patch. Skill is still invoked via `legal-compliance-auditor` agent in AC13 for semantic verification of the landed edits. |

## Implementation Phases

### Phase 0: Preconditions (RED — write failing-state evidence)

0.1. Confirm CWD = worktree, branch = `feat-one-shot-4447-eleventy-legal-mirror-sync`.
0.2. Run `bash apps/web-platform/scripts/check-tc-document-sha.sh; echo "exit=$?"` → expect `exit=0` (baseline pass).
0.3. Run the legal-doc-consistency vitest → expect 13 passing (baseline pass).
0.4. Run the diff `diff docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` → expect ~114 lines of divergence (the surface we're closing).
0.5. Snapshot the canonical's PR #4417 + #4351 changesets:

   ```bash
   git show b382cee0 -- docs/legal/data-protection-disclosure.md > /tmp/4417-canonical-dpd.diff
   git show af7bbb5b -- docs/legal/data-protection-disclosure.md > /tmp/4351-canonical-dpd.diff
   ```

   Use these as the authoritative source for the forward-port. The /work agent reads these patches and threads each removed/added line into the mirror's matching section.
0.6. Snapshot the mirror's mirror-only content (anything missing from canonical):

   ```bash
   diff docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md \
     | grep -E "^> " > /tmp/mirror-only-content.txt
   ```

### Phase 1: Mirror forward-port (canonical → mirror) — six surgical edits

1.1. Edit `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` §2.3(l) (mirror line 111): replace the short bullet body with the canonical's extended form from line 102 (Art. 15(4) sub-block, manifest schema 1.1.0, `MESSAGE_REDACT_FIELDS` constant, `member_<hex12>` pseudonym, attachments cascade allowlist, `dsar-message-redact-fields-sweep.test.ts` CI sentinel reference).
1.2. Insert §2.3(p) NEW BLOCK into mirror — full LinkedIn Company Page publication block from canonical line 115. Place between mirror's §2.3(o) (Inngest CFO at line 119) and §2.3(n) (CLA evidence archive at line 120). Verify letter ordering in the mirror remains coherent (the mirror currently has gap: skips from (o) to (n) to (r) to (s) — inserting (p) restores partial alphabetical fidelity).
1.3. Edit mirror §2.3(t) (mirror line 126): replace the SHORTER form with canonical's EXTENDED form from line 119 (over-provision rationale, v1-producer enumeration of revocation_reason enum values, RLS policy names, ADR-035 path + ADR-036 fold provenance).
1.4. Edit mirror §5.3 (mirror lines 219-228): replace the short bullet (a)-(f) form with canonical's detailed form from lines 216-232 (self-serve hint sentence, 8-item account-profile sub-list under (a), exclusion-list sentence, per-bullet channel notes).
1.5. Edit mirror §10.3 (mirror lines 342-346): insert sub-bullets (f) DSAR-job abort, (g) chat-attachments mig 068 cascade, (h) DSAR audit anonymisation, (i) LinkedIn-published content carve-out from canonical lines 353-356.
1.6. Edit mirror Last-Updated chain (mirror line 21): replace the compressed summary with canonical's longer narrative from line 12 (preserves Article 30(1) audit-trail completeness on the mirror surface).

### Phase 2: ~~Canonical back-port~~ **(removed — canonical is unchanged per deepen-pass round-2 finding)**

Skip. Deepen-pass round-2 diff inventory confirmed canonical has no surface where the mirror is uniquely ahead. Plan v1's bi-directional framing was wrong.

### Phase 3: Verification of date / hero / cosmetic reconciliation

3.1. Verify mirror hero stays at `<p>Effective February 20, 2026 | Last Updated May 25, 2026</p>` (line 11; already current — no edit).
3.2. Verify both files' body `**Last Updated:** May 25, 2026` line: `grep -c "\*\*Last Updated:\*\* May 25, 2026" docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` → expect `1` per file (both already current).
3.3. Run the residual-diff confirmation after Phase 1 edits:

   ```bash
   diff \
     <(awk '/^---$/{c++;next} c>=2' docs/legal/data-protection-disclosure.md) \
     <(awk '/^---$/{c++;next} c>=2' plugins/soleur/docs/pages/legal/data-protection-disclosure.md \
       | sed -E '/^<\/?(section|div|h1|p)/d')
   ```

   Confirm any remaining lines are only (a) link-form differences (`legal/foo.md` vs `/legal/foo/`) and (b) host-form differences (`https://soleur.ai` vs `https://www.soleur.ai`). Anything else is a sync gap → return to Phase 1.

### Phase 4: Extend the body-equivalence guard

4.1. Edit `apps/web-platform/scripts/check-tc-document-sha.sh` Step 1: replace `if [ "$doc" = "terms-and-conditions" ]; then` with a loop over `BODY_EQUIVALENCE_DOCS=("terms-and-conditions" "data-protection-disclosure")` and check membership. Keep the existing T&C-specific `TC_VERSION` bump-bypass logic (which only fires for `terms-and-conditions`).
4.2. Re-run `bash apps/web-platform/scripts/check-tc-document-sha.sh` → expect exit 0 (body-equivalence now passes for DPD as well as T&C).

### Phase 5: SHA literal verification (no refresh expected)

5.1. Compute current canonical DPD SHA: `sha256sum docs/legal/data-protection-disclosure.md`.
5.2. Verify it equals the literal in `apps/web-platform/lib/legal/legal-doc-shas.ts` (`04a2d796aff50f8457451b088c048a3c6cdf7eb84c9dacdbd01d5b42735a1d02`) — the canonical is UNCHANGED, so the literal is current.
5.3. Re-run the SHA guard → expect exit 0 (both the canonical-SHA-pin step AND the new body-equivalence step pass).

### Phase 6: Regression smoke test (extends existing vitest)

6.1. Add a new test case to `apps/web-platform/test/legal-doc-shas-guard.test.ts` under the existing `describe` block:

   ```ts
   test("DPD body drift detected when mirror diverges from canonical", () => {
     const tmp = makeTempCopy();
     const mirrorPath = resolve(tmp, "plugins/soleur/docs/pages/legal/data-protection-disclosure.md");
     const body = readFileSync(mirrorPath, "utf8");
     // Mutate a load-bearing line that the body-equivalence guard MUST detect:
     writeFileSync(mirrorPath, body.replace("Art. 15(4)", "Art. 15(5)"));
     const result = runGuard(tmp);
     expect(result.status).toBe(1);
     expect(result.stderr).toContain("data-protection-disclosure: body drift");
     rmSync(tmp, { recursive: true, force: true });
   });
   ```

6.2. Run the test → expect pass.
6.3. Run the full legal-doc-consistency suite → expect 13 + 1 new = 14 (or however the file currently structures its cases) all passing.

### Phase 7: Eleventy build verification

7.1. `npm run docs:build` from repo root.
7.2. `test -f _site/legal/data-protection-disclosure/index.html` → expect present.
7.3. `grep -F "Art. 15(4)" _site/legal/data-protection-disclosure/index.html` → expect ≥1 match (the new content rendered into the published page).

### Phase 8: Review + ship

8.1. Run `/soleur:review` with `legal-compliance-auditor` agent routed in (per AC13). The agent reads both canonical + mirror DPDs and confirms semantic identity of the Art. 15(4) + mig 068 + (f)-(i) cascade text.
8.2. Address review findings inline per `rf-review-finding-default-fix-inline`.
8.3. `/soleur:ship` → set `semver:patch` label (docs-only change), confirm PR body contains `Closes #4447` + `Ref #4417` + `Ref #4351`.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| **Forward-port introduces a copy error** (e.g., trailing whitespace, broken markdown link, mis-pasted section). | The `legal-compliance-auditor` agent in AC13 reads both copies; the body-equivalence script in Phase 4 mechanically catches any byte-level mismatch the agent might miss. Combined coverage. |
| **Back-port to canonical introduces a regression** to a downstream consumer (Article 30 register cross-reference, Privacy Policy cross-reference, GDPR Policy cross-reference, T&C cross-reference). | `legal-doc-cross-document-gate.yml` does NOT auto-detect DPD-only edits as DSAR-surface — reviewer manually confirms via the agent that no sibling legal doc needs paired edits. The byok_delegations Last-Updated chain entry is the only canonical addition; it adds chain context, not new processing activity. |
| **`normalize_plugin` sed pipeline does not strip enough of the mirror's njk scaffolding** for DPD (T&C was the only doc it was developed against). | Phase 3.3 explicit diff-and-confirm step. If the residual diff has anything beyond link-form + host-form differences, extend `normalize_plugin` (mirroring the T&C pattern) — small additional sed rules. |
| **SHA refresh races with another concurrent canonical DPD edit landing on main.** | `tc-document-sha-guard` is a required check; any subsequent PR that edits the canonical DPD without refreshing the SHA literal AND keeping body-equivalence will be blocked at CI. No race window. |
| **The `BODY_EQUIVALENCE_DOCS` widening accidentally triggers body-equivalence checks on the 7 docs that are NOT being synced in this PR.** | The widening is EXPLICIT (named-doc allowlist), NOT pattern-based. The 7 sibling docs (AUP, Cookie, Disclaimer, GDPR Policy, Privacy Policy, Individual CLA, Corporate CLA) are NOT added to `BODY_EQUIVALENCE_DOCS` and remain SHA-pinned only. The sibling-issue chain extends this allowlist one doc at a time. |
| **Mirror's `**Last Updated:** May 25, 2026` body line drifts from canonical when canonical updates next.** | Already covered by `legal-doc-consistency.test.ts` Last-Updated-date parity test (line 150) + new body-equivalence guard. Belt and suspenders. |

## Sharp Edges

- The body-equivalence script's `collapse` sed pipeline normalises away `(/legal/<slug>/)` ↔ `(<slug>.md)` link forms AND `https://soleur.ai` ↔ `https://www.soleur.ai` host forms. Do NOT edit either file to use only one form; the literal text in each file should remain in its native shape (canonical uses bare slug + apex host; mirror uses permalink + www host). The normalisation is the abstraction that lets both shapes coexist.
- The mirror's `<section class="page-hero">` + `<section class="content">` + `<div class="container">` + `<div class="prose">` HTML wrappers are LOAD-BEARING for the Eleventy site template (CSP + JSON-LD schema + CSS scoping). Do NOT strip them in the mirror or convert the mirror to plain markdown; the body-equivalence script strips them at compare-time via `normalize_plugin`.
- The mirror's Last-Updated date appears in TWO places (hero `<p>` AND body `**Last Updated:**`) per `2026-03-20-eleventy-mirror-dual-date-locations.md`. Update both, or the dual-date parity test fails.
- When this lands, the next PR that touches `docs/legal/data-protection-disclosure.md` MUST also touch the mirror (or the body-equivalence guard blocks merge). This is the intended outcome — converts a soft "remember to sync" defense into a hard CI gate. Operators authoring DPD edits MUST factor in the dual-edit cost; if it becomes unsustainable, revisit Alt-1 (build-time generation).
- The serial drain chain (`#4444 → #4453 → #4454 → #4445`) is gated by operator confirmation between each issue's kickoff. This is the FIRST issue in the chain; do NOT automatically open subsequent issues at merge time. The /one-shot pipeline reports completion and waits.
- The issue body's claim "mirror predates Art. 15(4)" is INVERTED — the mirror is mostly AHEAD; canonical is AHEAD on mig 068. The plan-write-time direction-check (Research Reconciliation row RC1) caught this. The /work agent MUST consult Phase 0 snapshots (the actual `git show` output for PR #4417 and PR #4351) as the authoritative source for the forward-port, NOT the issue body's prose.
- The Eleventy build runs from REPO ROOT (`npm run docs:build`), NOT from `plugins/soleur/docs/` per the `package.json` `scripts.docs:build` definition.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with concrete brand-survival framing (`aggregate pattern` threshold, demonstrability-gap exposure vector); ready for deepen.

## Test Strategy

**Unit / smoke (vitest):**

- Extend `apps/web-platform/test/legal-doc-shas-guard.test.ts` with the "DPD body drift" case (Phase 6.1).
- `apps/web-platform/test/legal-doc-consistency.test.ts` continues to pass unchanged.

**Integration (CI script):**

- `bash apps/web-platform/scripts/check-tc-document-sha.sh` exit 0 on synced state; exit 1 on tempdir-mutated state.

**Build:**

- `npm run docs:build` produces `_site/legal/data-protection-disclosure/index.html` with the new Art. 15(4) text rendered.

**Manual (CLO advisory):**

- `legal-compliance-auditor` agent semantic verification of Art. 15(4) + mig 068 + (f)-(i) cascade text in both files (per AC13).

## References

- Issue: https://github.com/jikig-ai/soleur/issues/4447
- Source PR (forward-port target): https://github.com/jikig-ai/soleur/pull/4417 (mig 068 workspace-shared attachments) — verified live: state=MERGED, mergedAt=2026-05-25T20:27:14Z, title="feat(attachments): mig 068 workspace-shared storage RLS + cascade pseudonymisation".
- Source PR (Art. 15(4) language): https://github.com/jikig-ai/soleur/pull/4351 — verified live: state=MERGED, mergedAt=2026-05-25T13:55:16Z, title="feat(dsar): Art. 15(4) author-only message redaction + manifest schema 1.1.0".
- Sibling drain chain (gated, operator-confirmed): #4444, #4453, #4454, #4445.
- Precedent forward-port plan: `knowledge-base/project/plans/2026-05-12-docs-forward-port-plugin-legal-docs-plan.md` (issue #3666) — same pattern, opposite direction (canonical ahead on Web Platform processing-activity disclosures).
- SHA-mirror-guard umbrella plan: `knowledge-base/project/plans/2026-05-22-feat-legal-doc-sha-mirror-guard-plan.md` (issue #4324) — establishes `LEGAL_DOC_SHAS` + the deferred-body-equivalence baseline this PR extends for DPD.
- Existing CI gate (legal-doc cross-document lockstep): `.github/workflows/legal-doc-cross-document-gate.yml`.
- Existing test (heading-sequence + sentinel parity): `apps/web-platform/test/legal-doc-consistency.test.ts`.
- Existing CI guard (SHA-pin + T&C body equivalence): `apps/web-platform/scripts/check-tc-document-sha.sh` + `apps/web-platform/test/legal-doc-shas-guard.test.ts`.
- Learning (dual-date locations): `knowledge-base/project/learnings/2026-03-20-eleventy-mirror-dual-date-locations.md`.
- Learning (DOCS arrays are themselves a drift surface): `knowledge-base/project/learnings/2026-05-22-ci-parity-test-docs-arrays-are-themselves-a-drift-surface.md` (filesystem-derived enumeration pattern, not hand-edited).
- AGENTS rule (legal-doc lockstep): `wg-after-merging-a-pr-that-adds-or-modifies` (workflow-side, not legal-doc-side; the actual legal-doc lockstep is the cross-document-gate workflow + consistency test).
- Workflow gate (`Closes #N` on own line): `wg-use-closes-n-in-pr-body-not-title-to`.
- Review-fix-inline preference: `rf-review-finding-default-fix-inline`.
