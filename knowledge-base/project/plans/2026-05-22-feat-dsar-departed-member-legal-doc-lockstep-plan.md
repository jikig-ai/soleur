---
title: DSAR departed-member legal-doc lockstep follow-up to PR #4294
type: docs-only
classification: legal-disclosure-lockstep
lane: cross-domain
issue: 4333
follow_up_to_pr: 4294
related_adr: ADR-039
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
requires_counsel_attestation: true
date: 2026-05-22
deepened_on: 2026-05-22
---

## Enhancement Summary

**Deepened on:** 2026-05-22
**Sections enhanced:** 6 (frontmatter, Research Reconciliation, Files to Edit, Acceptance Criteria, Risks, Research Insights)
**Research applied:** inline verification (live `gh` API for PR/issue citations, repo grep for DPD letter sequence, byline-convention cross-check across all three canonical + three mirror legal docs, label-existence check, sibling-issue overlap check). Sub-agent fan-out unavailable in this environment; checks performed inline against deepen-plan's quality gate inventory.

### Key Improvements

1. **Corrected GDPR-Policy and DPD byline conventions.** Plan v1 said "GDPR Policy uses inline `(Added 2026-MM-DD: …)` annotations" and "DPD uses no body-line Last-Updated." Live grep proved BOTH carry the same `**Last Updated:** May 22, 2026 (...)` byline as Privacy Policy (line 13 GDPR, line 12 DPD). All three canonical docs MUST be byline-extended (prepend a new `#<PR> — …` segment); cannot bump date (date is already 2026-05-22 from PR #4287 earlier today).
2. **Corrected Eleventy mirror byline scope.** Plan v1 only specified hero+body sync on Privacy Policy mirror. Live grep proved ALL THREE Eleventy mirrors carry both the hero `<p>Effective February 20, 2026 | Last Updated May 22, 2026</p>` (no colon) AND the body `**Last Updated:** May 22, 2026 (...)` byline. Extended AC5 to cover all three mirrors.
3. **Verified DPD `(v)` next-free letter empirically.** Enumerated full §2.3 letter set: `(a)-(p), (r), (s), (t), (u)`. Letters `(q)` AND `(v)` are both free. Plan picks `(v)` to follow the existing `(q)`-skip precedent. Phase 0.2 grep is load-bearing as the verification.
4. **Verified all 9 PR/issue citations are live and state-correct.** `gh pr view 4294` → MERGED. `gh issue view {4229,4230,4231,4284,4329,4338}` all CLOSED. `gh issue view {4319,4333}` OPEN. `gh pr view 4289` MERGED. No drift between plan attributions and live state.
5. **Verified labels.** `domain/legal`, `priority/p2-medium`, `type/feature`, `domain/engineering`, `priority/p3-low`, `type/chore`, `code-review`, `chore` all exist in `gh label list --limit 200`. AC13's `gh issue create --label` invocation is well-formed.
6. **Caught cross-doc sibling disambiguation hazard.** GDPR Policy line 13 already discloses `anonymise_workspace_member_actions` (PA-20, PR #4231) — this is the SIBLING ledger, not PA-19 (`workspace_member_removals`). The new disclosure prose must explicitly distinguish PA-19 from PA-20 by name to prevent reviewers conflating the two ledgers — added a Risk + Sharp Edge entry.
7. **Verified docs/legal/* contains zero existing references to "departed member" or "workspace_member_removals".** Clean insertion; no prose-collision footgun.
8. **Confirmed legal-doc-cross-document-gate.yml `surface_patterns` regex.** Touching only legal docs leaves `surface_hit=false`; gate trivially passes. Load-bearing correctness check is AC10's lockstep simulation, not AC9's gate-green.
9. **Confirmed sibling open issue #4338 (tenant-integration drift on mig 062)** is orthogonal to this docs-only PR — it's a CI/dev-Supabase-state problem on the prior PR (#4294) that does NOT block #4333's legal-doc-only diff from merging. Added to Risks as a Risk-7 "out-of-band CI noise" note.

### New Considerations Discovered

- **Three-byline lockstep on all three canonical docs.** Plan v1 over-narrowed the byline edit to Privacy Policy. All three must be byline-extended in lockstep with each section-body edit; otherwise the legal-doc-cross-document-gate's `required_legal_files` lockstep is structurally violated even though the file-diff lockstep is satisfied. Fixed in §Files to Edit and AC1/AC2/AC3.
- **PA-19 vs PA-20 collision risk.** GDPR Policy's existing 2026-05-22 byline already names `anonymise_workspace_member_actions` (PA-20, sibling table). Reviewers reading top-to-bottom will see "Last Updated: today, workspace_member_actions cascade…" THEN this PR's added Section 5.3 paragraph naming `workspace_member_removals` cascade. The two ledgers are easy to conflate. The new paragraph must explicitly name BOTH the table (`workspace_member_removals`) AND the PA number (PA-19) AND distinguish from PA-20 in adjacent prose.
- **Today's date IS already May 22, 2026.** Plan v1 wrote "Update body `**Last Updated:**` byline to today (2026-05-22)" implying a date-bump. The date is already today; the edit is byline-segment-prepend, not date-bump. Clarified in §Files to Edit.

---

# Plan: DSAR departed-member legal-doc lockstep (#4333 — follow-up to PR #4294)

## Overview

PR #4294 (closed umbrella #4229 follow-up #4230) shipped the `workspace_member_removals` WORM ledger + Approach-A attestation UNION + Article 17 cascade extension on 2026-05-22, but the `legal-doc-cross-document-gate` workflow run FAILED on the same PR. The gate was configured as advisory (not on the main-branch required-checks list) so auto-merge fired regardless. Three public-facing legal docs landed without the departed-member disclosure they need:

1. `docs/legal/privacy-policy.md` (canonical) + Eleventy mirror — needs GDPR Art. 15 / 17 / 20 disclosure for departed workspace members, cross-referencing the `workspace_member_removals` audit ledger and 36-month retention floor.
2. `docs/legal/gdpr-policy.md` (canonical) + Eleventy mirror — needs Art. 15 + Art. 17 cascade disclosure noting the anonymise-before-auth-delete ordering and the lineage columns (`id`, `removed_at`) preserved post-erasure for Art. 5(2) accountability.
3. `docs/legal/data-protection-disclosure.md` (canonical) + Eleventy mirror — needs a new §2.3 sub-section (next free letter — `(v)` per current sequence) covering the workspace-member-removal audit ledger as PA-19 of the Article 30 register.

`compliance-posture.md` and `article-30-register.md` (PA-19) were updated in #4294 already; the gate's `required_legal_files` triplet of `docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` is the un-addressed remainder.

This plan is **docs-only**. No source code, no migration, no infra changes. Brand-survival threshold is **single-user incident** (one departed member receiving a privacy-policy text that fails to disclose the audit ledger they were recorded in is an Art. 13(1)(c)/(e) transparency breach — notifiable risk).

## User-Brand Impact

**If this lands broken, the user experiences:** A departed workspace member reads our privacy-policy / GDPR-policy / DPD page after being removed from a workspace, finds no mention of how their identifiable removal-event row is processed, retained, or accessible — and (a) escalates an Art. 13 / Art. 30(1)(g) transparency complaint to the CNIL or (b) files an Art. 15 request grounded on "I have no idea what records of me you hold" because nothing on our public pages discloses the new ledger. The brand position becomes "we built an audit trail of removals but hid its existence from the people it most affects."

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — pure disclosure delta. No new data flow, no new processor, no new code path. The leak vector is *omission of disclosure*, not exfiltration.

**Brand-survival threshold:** `single-user incident`. One departed-member CNIL escalation grounded on undisclosed processing is brand-survival-relevant. Carried forward from PR #4294's threshold per ADR-039 frontmatter `brand_survival_threshold: single-user incident`.

## Research Reconciliation — Spec vs. Codebase

| Issue-body claim | Codebase reality | Plan response |
|------------------|------------------|---------------|
| "DPD §2.3 needs a new sub-section" | DPD §2.3 currently sequences `(a)`–`(u)` with letters `(o)`/`(n)`/`(r)`/`(s)`/`(p)`/`(u)`/`(t)` (out-of-alphabetical-order historical accretion). The next free letter that does NOT collide is `(v)`. | Use `(v)` for the new workspace-member-removal sub-section. Verified by `grep -nE '^- \*\*\(.{1,2}\)\*\*' docs/legal/data-protection-disclosure.md`. |
| "Mirror to plugins/soleur/docs/pages/legal/*.md (Eleventy source)" | Eleventy mirrors live at `plugins/soleur/docs/pages/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` and are distinct files (NOT symlinks). They carry an Eleventy frontmatter wrapper + a `<section class="page-hero">` HTML banner + replace `**Last Updated:**` body-line with hero `Last Updated <date>` (no colon). | Edit BOTH the canonical and the mirror in the SAME PR. Apply identical body changes; preserve mirror's hero-banner + frontmatter shape; respect the hero's `Last Updated May 22, 2026` (NO colon) form vs body's `**Last Updated:** May 22, 2026` (WITH colon). |
| "Verify `.github/workflows/legal-doc-cross-document-gate.yml` PASSES on the follow-up PR" | Gate's `required_legal_files` list = `docs/legal/privacy-policy.md`, `docs/legal/gdpr-policy.md`, `docs/legal/data-protection-disclosure.md`, `knowledge-base/legal/compliance-posture.md`. Gate fires on a `surface_patterns` regex — touching ONLY legal docs does NOT trip the gate's surface-hit branch (surface_hit=false → trivial pass). | The gate will trivially pass because no DSAR surface file is being changed. AC must use a STRONGER check than "gate green" — verify the four `required_legal_files` are each present in the diff via a per-file `git diff --name-only origin/main...HEAD | grep -Fxq <file>` check, simulating what the gate WOULD enforce if a surface file were also in scope. compliance-posture.md was already updated in #4294 and does NOT need re-touching here — but the PR diff against `main` will not include it. So the simulation is: "if a surface file existed in this diff, would the gate pass?" — verify the THREE legal docs are in the diff (compliance-posture lockstep is satisfied by #4294 historically). |
| "Counsel-attested audit at `knowledge-base/legal/audits/2026-05-counsel-review-<PR>.md`" | Audit-file convention from `2026-05-counsel-review-{4051,4066,4289}.md`: YAML frontmatter (`title`, `type: counsel-review`, `date`, `issue`, `pr`, `status`, `signed_off_at`, `signed_off_by`, `re_evaluation_triggers`) + per-artifact section with scope-of-review + particular-attention-requested + sign-off table. | Author the audit at `knowledge-base/legal/audits/2026-05-counsel-review-<PR>.md` (PR number filled at /work-time post-`gh pr create`). Three artifact sections (one per legal doc); operator-attested per Soleur-as-tenant-zero posture; re-evaluation triggers carry forward ADR-039's (first non-Jikigai-affiliate invitee removal / EEA-out invitee removal / regulated-industry invitee removal). |
| Issue body: "(Out-of-scope here, separate workflow-gate issue) Promote the gate to required-check on main ruleset" | Yes — separate workflow-quality concern, NOT in this PR's scope. | Confirmed out-of-scope. Add a Sharp Edges note that this PR does NOT promote the gate to required-check; that follow-up will be filed as a separate issue from /work Phase 6. |
| Issue body brand-survival threshold | ADR-039 frontmatter line 10: `brand_survival_threshold: single-user incident`. | Carry forward verbatim. CPO sign-off required at plan-time (this section); `user-impact-reviewer` invoked at PR review time per AGENTS.md (handled by review skill conditional agents). |

## Files to Edit

**Note (corrected at deepen-pass):** All three canonical docs AND all three Eleventy mirrors carry the SAME byline convention — `**Last Updated:** May 22, 2026 (...)` in canonical (line 13 GDPR, line 12 DPD, line 11 Privacy Policy) AND `<p>Effective February 20, 2026 | Last Updated May 22, 2026</p>` in mirror hero blocks (line 11) + `**Last Updated:** May 22, 2026 (...)` in mirror body bylines. The date IS already 2026-05-22 from PR #4287's edits earlier today; this PR's edit is byline-segment-PREPEND of a `#<this-PR> — added departed-workspace-member DSAR disclosure for the `workspace_member_removals` WORM ledger introduced by migration 062 / PR #4294 (PA-19 — distinct from PA-20 `workspace_member_actions`); Art. 15 / 17 / 20 over the ledger; 36-month retention floor (Art. 82(2) shortest-jurisdiction); Art. 17 cascade via `anonymise_workspace_member_removals` step 3.905 in `server/account-delete.ts` BEFORE `auth.admin.deleteUser`; lineage columns (`id`, `removed_at`) preserved post-erasure for Art. 5(2) accountability; no new sub-processor engaged;` segment AHEAD of the existing `#4287 — …` segment, NOT a date-bump.

### Canonical (`docs/legal/`)

1. `docs/legal/privacy-policy.md` — add a new bullet in §8.1 "Rights Under GDPR (EU/EEA Users)" disclosing Art. 15 / 17 / 20 over the `workspace_member_removals` ledger for departed workspace members (cross-reference §4.11 "Workspace co-members" data class). Prepend a new `#<PR> — …` segment to the existing line 11 `**Last Updated:** May 22, 2026 (...)` byline (PREPEND, do NOT bump date — see Note above).
2. `docs/legal/gdpr-policy.md` — add a new paragraph (or inline `(Added 2026-05-22: …)` annotation) in §5.3 "Rights Exercisable Against Jikigai (Web Platform)" specifically under the Art. 15 + Art. 17 entries describing the departed-member `workspace_member_removals` ledger, the cascade ordering (`anonymise_workspace_member_removals` BEFORE `auth.admin.deleteUser`), and lineage preservation. Explicitly name PA-19 AND distinguish from PA-20 (already disclosed earlier in this doc's existing line 13 byline as `anonymise_workspace_member_actions`). Prepend a new `#<PR> — …` segment to the existing line 13 `**Last Updated:** May 22, 2026 (...)` byline.
3. `docs/legal/data-protection-disclosure.md` — add new `- **(v)** **Workspace member removal audit ledger:**` sub-section under §2.3 (next free letter — full set `(a)-(p), (r), (s), (t), (u)` verified by `grep -oE '^- \*\*\([a-z]{1,2}\)\*\*' docs/legal/data-protection-disclosure.md | sort -u`; `(q)` AND `(v)` are both free, picking `(v)` to maintain the existing `(q)`-skip precedent). Mirror the §2.3(u) workspace-co-member section's structural shape (Data processed / Legal basis / Retention / Sub-processors / Article 30 cross-reference to PA-19). Prepend a new `#<PR> — …` segment to the existing line 12 `**Last Updated:** May 22, 2026 (...)` byline.

### Eleventy mirrors (`plugins/soleur/docs/pages/legal/`)

4. `plugins/soleur/docs/pages/legal/privacy-policy.md` — apply EXACT same body delta as (1) AND prepend the same `#<PR> — …` byline segment in BOTH (a) line 11 hero-banner `<p>Effective February 20, 2026 | Last Updated May 22, 2026</p>` (NO colon — date is part of HTML prose) AND (b) line 20 body `**Last Updated:** May 22, 2026 (...)` byline (WITH colon). The two strings carry distinct shapes; both must be touched in the same edit per learning `2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md` Sharp Edge. **Note:** hero form does NOT carry a change-log — only the date string ("Last Updated May 22, 2026"). Since the date stays today, the hero is changed only if a date-bump occurs (none here) — but VERIFY at /work that the hero already reads "May 22, 2026" so AC5 grep ≥ 2 holds (1 hero + 1 body); if hero shows a stale date, fix in same edit.
5. `plugins/soleur/docs/pages/legal/gdpr-policy.md` — apply same body delta as (2). Same hero+body byline convention as (4) — verified by `grep -n 'Last Updated\|page-hero' plugins/soleur/docs/pages/legal/gdpr-policy.md` showing line 8 hero + line 11 date string + line 22 body byline.
6. `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — apply same body delta as (3). Same hero+body byline convention as (4) — verified by `grep -n 'Last Updated\|page-hero' plugins/soleur/docs/pages/legal/data-protection-disclosure.md` showing line 8 hero + line 11 date string + line 21 body byline.

### Knowledge-base

7. `knowledge-base/legal/audits/2026-05-counsel-review-<PR>.md` — NEW file. Counsel-attestation audit. Three artifact sections (privacy / GDPR / DPD). Operator-attestation per Soleur-as-tenant-zero posture. Re-evaluation triggers carry forward ADR-039's. Filename PR-number is filled at /work Phase 5 AFTER `gh pr create` returns the number.

## Files to Create

Only the counsel-review audit at `knowledge-base/legal/audits/2026-05-counsel-review-<PR>.md` (see #7 above).

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json` then per-file `jq` against each Files-to-Edit path. **None** of the six target files appear in any open code-review issue body. No overlap to fold / acknowledge / defer.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `docs/legal/privacy-policy.md` §8.1 contains a NEW bullet (or paragraph) mentioning ALL THREE of (`workspace_member_removals` audit ledger, 36-month retention, departed workspace members can exercise Art. 15 / 17 / 20). Verify via three independent greps:
  - `grep -nF 'workspace_member_removals' docs/legal/privacy-policy.md` returns ≥ 1.
  - `grep -nF '36 months' docs/legal/privacy-policy.md` returns ≥ 1 line referencing the removal ledger (use line-context inspection, not raw count — `Last Updated` substring is allowed to also match in the byline change-log).
  - `grep -nE 'departed (workspace |team )?members?' docs/legal/privacy-policy.md` returns ≥ 1.
- [ ] **AC2** `docs/legal/gdpr-policy.md` §5.3 contains a NEW disclosure including ALL THREE of (`workspace_member_removals`, `anonymise_workspace_member_removals` cascade, lineage columns `id` + `removed_at` preserved post-erasure for Art. 5(2)). Verify via three independent greps.
- [ ] **AC3** `docs/legal/data-protection-disclosure.md` contains a NEW `### 2.3(v)` (or `- **(v)**`) sub-section bullet named "Workspace member removal audit ledger" cross-referencing PA-19. Verify via `grep -nE '\*\*\(v\)\*\*.*[Ww]orkspace member removal' docs/legal/data-protection-disclosure.md` returns 1 AND `grep -nF 'Processing Activity 19' docs/legal/data-protection-disclosure.md` returns ≥ 1.
- [ ] **AC4** All three Eleventy mirrors (`plugins/soleur/docs/pages/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`) contain the SAME body delta. Verify via mirror-parity check — for each canonical/mirror pair, `diff <(sed -n '/<the new section start marker>/,/<the new section end marker>/p' <canonical>) <(sed -n '/<same start>/,/<same end>/p' <mirror>)` exits 0 (or with only frontmatter/hero whitespace differences — call out each accepted divergence by line).
- [ ] **AC5** ALL THREE Eleventy mirrors (`privacy-policy.md`, `gdpr-policy.md`, `data-protection-disclosure.md`) have BOTH the hero-banner `Last Updated May 22, 2026` (no colon — line 11 region) AND the body `**Last Updated:** May 22, 2026 (...)` byline (with colon) date-synchronised. Verify via three independent greps: `grep -cE 'Last Updated[: *]+May 22, 2026' plugins/soleur/docs/pages/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` each returns ≥ 2. (The byline date is already May 22, 2026 from PR #4287 today; this PR's edit is a change-log segment PREPEND, not a date bump — but the date strings MUST still satisfy ≥ 2 on each mirror.)
- [ ] **AC5b** All three canonical docs (`docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`) have the body `**Last Updated:** May 22, 2026 (...)` byline with a `#<this-PR>` segment prepended ahead of the existing `#4287` segment. Verify via `grep -nE '^\*\*Last Updated:\*\* May 22, 2026 \(#[0-9]+ —' docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` returns 3 lines (one per file) AND `grep -oE '#[0-9]+' docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md | head -3` shows the new PR number is the LEADING `#N` in each file (NOT `#4287`).
- [ ] **AC5c** New disclosure prose in §5.3 of `docs/legal/gdpr-policy.md` explicitly names BOTH `workspace_member_removals` (PA-19, this PR's new disclosure) AND `workspace_member_actions` (PA-20, already disclosed via line 13 existing byline) and distinguishes the two ledgers — sibling tables, distinct purposes, distinct retention floors (PA-19 = 36 months, PA-20 = 7 years). Verify: `grep -c 'PA-19\|Processing Activity 19\|workspace_member_removals' docs/legal/gdpr-policy.md` ≥ 2 AND `grep -c 'PA-20\|Processing Activity 20\|workspace_member_actions' docs/legal/gdpr-policy.md` ≥ 1 AND the §5.3 disclosure paragraph names the two distinct retention floors (36-month vs 7-year). This is the PA-19/PA-20 disambiguation guardrail per Risk-6.
- [ ] **AC6** Counsel-review audit file at `knowledge-base/legal/audits/2026-05-counsel-review-<PR>.md` exists, has the canonical frontmatter shape (per the 4289 template — `title`, `type: counsel-review`, `date`, `issue: 4333`, `pr: <PR>`, `status: SIGNED-OFF (operator-attested)`, `signed_off_at: 2026-05-22`, `signed_off_by: "Jean Deruelle (Jikigai SARL gérant)"`, `re_evaluation_triggers`), and contains THREE artifact sections (one per legal doc). Verify via `awk '/^## Artifact /{n++} END{print n}' <file>` returns 3.
- [ ] **AC7** PR body uses `Closes #4333` (NOT `Ref #4333`) — this PR's work fully closes #4333 at merge (no post-merge operator step extends beyond `/soleur:ship` automation; the audit-file rename of `<PR>` → `4xxx` is done pre-merge inside the same PR, not post-merge). Per `wg-use-closes-n-in-pr-body-not-title-to`.
- [ ] **AC8** Article 30 register and compliance-posture.md are NOT modified by this PR (they were already updated in #4294; modifying them here would double-count). Verify via `git diff --name-only origin/main...HEAD | grep -E 'knowledge-base/legal/(article-30-register|compliance-posture)\.md' || true` returns empty (the `|| true` accepts the empty-stdout case as success in bash strict mode).
- [ ] **AC9** legal-doc-cross-document-gate.yml workflow check posts a GREEN status on the PR. (Trivial pass — no surface_pattern is hit; the surface_hit=false branch fires immediately.) Verify via `gh pr checks <PR> --json name,conclusion | jq -r '.[] | select(.name == "enforce") | .conclusion'` returns `success` (NOT `failure` and NOT `null`).
- [ ] **AC10** Required-checks lockstep simulation: if THIS PR's diff INCLUDED a `surface_pattern` file (e.g. `apps/web-platform/server/dsar-export.ts`), the gate WOULD pass. Verify by running the gate's enforce-step logic locally with `BASE_REF=main` and the changed-files list manually augmented with a synthetic `dsar-export.ts` entry — confirm the four `required_legal_files` greps all match. This is a defense-in-depth check that the legal-doc lockstep WOULD hold if a future PR re-touches a DSAR surface AND inadvertently regresses the legal-doc lockstep. Bash one-liner: `printf '%s\n' "apps/web-platform/server/dsar-export.ts" "docs/legal/privacy-policy.md" "docs/legal/gdpr-policy.md" "docs/legal/data-protection-disclosure.md" "knowledge-base/legal/compliance-posture.md" | grep -Fxc -f <(printf '%s\n' docs/legal/privacy-policy.md docs/legal/gdpr-policy.md docs/legal/data-protection-disclosure.md knowledge-base/legal/compliance-posture.md)` returns `4`.
- [ ] **AC11** `tsc --noEmit` is NOT relevant (docs-only). Eleventy build does NOT need to run in CI for this PR (no `.njk` / template change). Verify the only file types touched are `*.md`: `git diff --name-only origin/main...HEAD | grep -vE '\.md$' || true` returns empty.

### Post-merge (operator) — minimised per AGENTS.md `wg-block-pr-ready-on-undeferred-operator-steps`

- [ ] **AC12** `gh issue close 4333` runs automatically via `Closes #4333` PR-body keyword at merge — no operator action.
- [ ] **AC13** Follow-up: file a separate issue (NOT in this PR's scope per issue body) for promoting `legal-doc-cross-document-gate` to a required-check on the main-branch ruleset. Operator action: `gh issue create --title 'workflow-gate: promote legal-doc-cross-document-gate to required-check on main ruleset' --body 'Out-of-scope-from-#4333 follow-up. Per #4333 §"Why the gate didn'\''t block": the gate is advisory and was bypassed by auto-merge on PR #4294. Required-check status would have blocked the merge. Implementation: gh api PATCH repos/jikig-ai/soleur/rulesets/<id> --input - <<<JSON adding "enforce" to required_status_checks. Verify on next PR diff that touches docs/legal/ — gate appears as required check.' --label 'domain/engineering,priority/p3-low,type/chore'` — automatable via `gh` CLI per "automation-feasibility gate." File from /work Phase 6 AFTER this PR is merged.

## Test Strategy

No new test code is needed. Verification is via:

1. **AC1–AC3 greps** — operator runs the per-AC grep commands during `/work` Phase 5 GREEN-equivalent (this is docs-only — there is no RED phase; the gate is correctness-of-prose-against-AC-grep).
2. **AC4 mirror-parity** — operator runs the `diff` two-arg compare per canonical/mirror pair.
3. **AC9 workflow-gate check** — read from `gh pr checks` after CI runs.
4. **AC10 lockstep simulation** — single bash one-liner, no test runner.
5. **AC11 file-type sweep** — single grep.

No `package.json` `scripts.test` runner invocation (no new `*.test.ts` file). Per the "Phase 0 grep test-runner" Sharp Edge in `plan/SKILL.md` — confirmed by `grep -E '"test"' apps/web-platform/package.json` that `vitest` is the runner, but no test code is being added so this is moot.

## Domain Review

**Domains relevant:** Legal (CLO), Product (CPO).

### Legal (CLO)

**Status:** reviewed (operator-attested per Soleur-as-tenant-zero posture; external counsel re-review triggered on first non-Jikigai-affiliate departed-member DSAR per ADR-039 §Re-evaluation).
**Assessment:** This PR is the canonical follow-up to a legal-doc-cross-document-gate FAILURE that auto-merged. Adding the three disclosures closes the loop on Art. 13 / Art. 30(1)(g) transparency obligations introduced by #4294's `workspace_member_removals` substrate. The ledger itself is already disclosed in Article 30 register (PA-19) and `compliance-posture.md` (added by #4294); only the public-facing pages remained un-updated. Counsel-attestation audit file lands in same PR (AC6) per the v1 Soleur-as-tenant-zero pattern (PR #4081 / #4066 / #4289 precedent).

### Product/UX Gate

**Tier:** none — no UI surface change. Pure copy in static docs pages. The Eleventy-rendered pages will re-deploy at next docs-deploy run; no React component, no `app/**/page.tsx`, no `components/**/*.tsx` file is touched. Mechanical escalation per `plan/SKILL.md` does NOT fire.
**Decision:** skipped (no UX surface).
**Agents invoked:** none.
**Skipped specialists:** none (no UX surface).
**Pencil available:** N/A.

## Infrastructure (IaC)

Not applicable. Pure docs-only PR. No new resource, no new secret, no new vendor, no new persistent runtime process. Skipping per `plan/SKILL.md` Phase 2.8 skip-condition.

## Observability

Not applicable. Skipping per `plan/SKILL.md` Phase 2.9 skip-condition (plan is pure-docs; no Files-to-Edit under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`).

## Risks

1. **Last-Updated mirror drift.** The hero-banner form (no colon) vs. body-line form (with colon) on `privacy-policy.md` mirror is a known footgun (see Sharp Edge: `2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md`). AC5 catches both forms explicitly via `Last Updated[: *]+May 22, 2026` tolerating both punctuation shapes. **Mitigation:** AC5 verifies count ≥ 2.
2. **DPD §2.3 sub-section letter collision.** Existing letters `(o)`, `(n)`, `(r)`, `(s)`, `(p)`, `(t)`, `(u)` are non-alphabetical historical accretion. The next free letter `(v)` was verified at plan-write time by grep. **Mitigation:** /work Phase 0 RE-runs `grep -nE '^- \*\*\(.{1,2}\)\*\*' docs/legal/data-protection-disclosure.md` and picks the next free letter if `(v)` has been taken by an intervening PR.
3. **Gate trivial-pass false confidence.** The legal-doc-cross-document-gate.yml workflow PASSES on this PR (AC9) but only because the surface_hit branch is false. It does NOT verify the legal docs ACTUALLY have departed-member content. AC10's lockstep simulation is the load-bearing correctness check, not AC9. **Mitigation:** AC10 explicitly simulates the gate's required_legal_files check with the surface-file branch forced true.
4. **Counsel-review audit PR-number rename.** The audit file is created with `<PR>` placeholder in the filename; renamed post-`gh pr create` (which assigns the number). **Mitigation:** /work Phase 5 step prescribes `mv knowledge-base/legal/audits/2026-05-counsel-review-PLACEHOLDER.md knowledge-base/legal/audits/2026-05-counsel-review-<actual-PR>.md` AFTER `gh pr create` returns. The `pr:` frontmatter field is set in the same edit. AC6 verifies the renamed file matches the gh-CLI PR number.
5. **Re-touching `compliance-posture.md` / `article-30-register.md`.** These were updated by #4294 already. Re-touching them in this PR would (a) double-count the disclosure and (b) potentially trigger the legal-doc gate's required_legal_files check on a column that's already satisfied. **Mitigation:** AC8 explicitly verifies these two files are NOT in the diff.
6. **PA-19 vs PA-20 conflation hazard.** GDPR Policy line 13 byline already names `anonymise_workspace_member_actions` (PA-20, PR #4231, sibling `workspace_member_actions` ledger). This PR's new §5.3 paragraph adds disclosure of `anonymise_workspace_member_removals` (PA-19, PR #4294, `workspace_member_removals` ledger). The names are confusingly similar — `workspace_member_actions` vs `workspace_member_removals` differ by one word; both are WORM audit logs introduced in adjacent migrations (063 vs 062) within hours of each other. A reviewer or counsel reading the doc top-to-bottom can easily conflate them. **Mitigation:** AC5c explicitly grep-validates that the §5.3 paragraph names BOTH PA-19 and PA-20 distinctly AND quotes the two distinct retention floors (36-month vs 7-year). The paragraph prose must lead with "**Workspace member removal audit ledger (PA-19, distinct from PA-20 below):**" or equivalent.

7. **Out-of-band: sibling issue #4338 (recently closed).** Verified at deepen-pass: #4338 (CI tenant-integration mig-062 fails — missing `public.workspaces`) was closed `2026-05-22T12:34:32Z` (about an hour before this plan). Attributed to #4294's `062_workspace_member_removals_and_remove_rpc_update.sql` not applying against a dev-Supabase instance that lacked `public.workspaces`. **This is orthogonal to #4333's docs-only diff** — the docs PR will not run tenant-integration migrations. Risk is non-blocking. **Mitigation:** AC11 (only `.md` files in diff) guarantees this PR triggers zero migration-apply CI; even if some lingering retry of tenant-integration fires against this branch, it is pre-existing-unrelated and tracked at the now-closed #4338. /work Phase 4 should call this out in the PR body if the check appears red.

8. **Future-PR gate-promotion split.** The follow-up to promote the gate to a required-check (issue-body's "out-of-scope here, separate workflow-gate issue") is filed only at /work Phase 6 post-merge (AC13). Failure to file leaves the next DSAR-surface PR exposed to the same auto-merge-around-failure pattern. **Mitigation:** AC13 is the explicit operator-step automation; the gh-CLI invocation form is prescribed verbatim in AC13's body.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares `single-user incident` threshold (carried forward from ADR-039) and `requires_cpo_signoff: true` in frontmatter. CPO sign-off is required at plan-time AND `user-impact-reviewer` will be invoked at PR-review time per AGENTS.md.
- This PR does NOT promote `legal-doc-cross-document-gate.yml` to a required-check on the main branch ruleset. That is filed as a separate follow-up issue from /work Phase 6 (AC13). Without the promotion, a future DSAR-surface PR could auto-merge around a failed gate again. The promotion is a workflow-gate-quality concern, not a legal-disclosure-quality concern, and they are properly separated per issue body §"Why the gate didn't block."
- DPD §2.3 sub-section lettering is NOT alphabetically contiguous. The grep at /work Phase 0 verifies `(v)` is still free; if intervening PRs have taken `(v)`, pick the next free letter and update AC3's grep accordingly.
- The Eleventy mirror's hero-banner `Last Updated May 22, 2026` (no colon) and body `**Last Updated:** May 22, 2026` (with colon) MUST both be updated in the same edit on `privacy-policy.md` mirror — they are date-redundant by design but drift independently if edited separately. `gdpr-policy.md` and `data-protection-disclosure.md` mirrors use different Last-Updated conventions — verify per-doc by grep before editing.
- The counsel-review audit's PR-number rename is a /work Phase 5 step that depends on `gh pr create` having run. Do NOT pre-fill a placeholder PR number — use the literal `PLACEHOLDER` string in the filename until `gh pr create` returns.
- **PA-19 vs PA-20 disambiguation.** GDPR Policy line 13's existing byline already discloses `anonymise_workspace_member_actions` (PA-20). This PR adds `workspace_member_removals` (PA-19). The names look almost identical; do NOT let any prose or AC text say just "the workspace_member_* ledger." The §5.3 disclosure MUST name BOTH ledgers and their distinct retention floors (36-month for PA-19, 7-year for PA-20). AC5c is the load-bearing grep guardrail.
- **Byline prepend, NOT date bump.** All three canonical docs already carry `**Last Updated:** May 22, 2026 (#4287 — ...)` from PR #4287's earlier-today edits. This PR PREPENDS a new `#<PR> — added departed-workspace-member DSAR disclosure ...` segment AHEAD of the existing `#4287` segment. The date string stays "May 22, 2026" — do NOT rewrite it. The existing PR #4287 byline content stays after `;` separator. AC5b verifies the new `#<PR>` is the LEADING segment.
- **Eleventy mirror hero is a date-only string, no change-log.** The `<p>Effective February 20, 2026 | Last Updated May 22, 2026</p>` hero block carries ONLY the date — not a change-log. Since the date stays today (no bump), the hero may not need any text edit. AC5's `grep -c ≥ 2` is satisfied by the existing hero + the body-byline-with-new-segment. Verify per-file at /work Phase 0 that hero reads "May 22, 2026"; if any hero shows a stale date (e.g., a mirror that wasn't touched by #4287), bump it in the same edit.

## Hypotheses

N/A — no network / SSH / connectivity surface. Skipping per `plan/SKILL.md` Phase 1.4 trigger-pattern check (none of `SSH`, `connection`, `kex`, `firewall`, `unreachable`, `timeout`, `502`, `503`, `504`, `handshake`, `EHOSTUNREACH`, `ECONNRESET` match).

## Research Insights

- ADR-039 (`knowledge-base/engineering/architecture/decisions/ADR-039-departed-member-removal-ledger.md`) is the canonical source for the WORM-ledger invariants, retention rationale (36-mo Art. 82(2) shortest-jurisdiction floor), cascade ordering, and RLS deviation (departed members CANNOT read their own removal row via `is_workspace_member` — DSAR service-role read only).
- PR #4294 (`gh pr view 4294`) merged 2026-05-22T09:21:11Z. Plan body cites PR-H (#4077), PR-I (#4078), and umbrella #4229; verified all three resolve as either PR or issue via `gh pr view` / `gh issue view`.
- Article 30 register PA-19 (`knowledge-base/legal/article-30-register.md` line 344) is the canonical regulator-facing record. PA-20 (line 366) is the sibling `workspace_member_actions` ledger (PR #4231) — distinct from PA-19's `workspace_member_removals` ledger. Disclosure must cite PA-19 specifically.
- Counsel-audit precedent (`knowledge-base/legal/audits/2026-05-counsel-review-{4051,4066,4289}.md`) — three artifacts each (one per legal-doc surface touched). This PR follows the same three-artifact shape.
- legal-doc-cross-document-gate.yml `surface_patterns` regex list confirms the gate trivially passes on docs-only PRs. AC10 is the load-bearing simulation check.
- No existing references to `workspace_member_removals` / `workspace member removal` / `departed.*member` in any `docs/legal/*.md` file (verified via `grep -l`). This is a clean insertion — no edit-in-place of pre-existing prose.
- No skill description budget impact (no `plugins/soleur/skills/*/SKILL.md` edit). Skipping `plan/SKILL.md` Phase 1.8 / Step 2 re-check.

### Deepen-pass verifications (2026-05-22)

| Check | Command | Result |
|-------|---------|--------|
| PR #4294 state | `gh pr view 4294 --json state,mergedAt` | `MERGED` at `2026-05-22T09:21:11Z` |
| Issue #4333 state | `gh issue view 4333 --json state` | `OPEN` (target of this PR) |
| Issue #4229 (umbrella) | `gh issue view 4229 --json state` | `CLOSED` |
| Issue #4230 (DSAR follow-up) | `gh issue view 4230 --json state` | `CLOSED` (closed by #4294) |
| Issue #4231 (sibling actions ledger) | `gh issue view 4231 --json state` | `CLOSED` |
| Issue #4284 (flag-flip follow-through) | `gh issue view 4284 --json state` | `CLOSED` |
| PR #4289 (legal scaffolding) | `gh pr view 4289 --json state` | `MERGED` |
| Issue #4319 (Art. 15(4) split) | `gh issue view 4319 --json state` | `OPEN` (related but out-of-scope for #4333) |
| Issue #4329 (sister-table RESTRICT) | `gh issue view 4329 --json state` | `OPEN` (related but out-of-scope) |
| Issue #4338 (mig 062 CI drift) | `gh issue view 4338 --json state` | `CLOSED` (sibling; orthogonal to docs-only diff) |
| DPD §2.3 letter sequence | `grep -oE '^- \*\*\([a-z]{1,2}\)\*\*' docs/legal/data-protection-disclosure.md \| sort -u` | `(a)–(p), (r), (s), (t), (u)` — `(q)` and `(v)` are both free |
| Departed-member existing prose | `grep -l 'workspace_member_removals\|departed.*member' docs/legal/*.md` | empty — clean insertion |
| Privacy Policy current byline | `head -11 docs/legal/privacy-policy.md` | `**Last Updated:** May 22, 2026 (#4287 — ...)` |
| GDPR Policy current byline | line 13 of `docs/legal/gdpr-policy.md` | `**Last Updated:** May 22, 2026 (#4287 — ...anonymise_workspace_member_actions...)` — already names PA-20, the SIBLING |
| DPD current byline | line 12 of `docs/legal/data-protection-disclosure.md` | `**Last Updated:** May 22, 2026 (#4287 — ...Processing Activity 20...)` — already names PA-20 |
| Mirror hero+body conventions | `grep -n 'Last Updated\|page-hero' plugins/soleur/docs/pages/legal/*.md` | All three mirrors have BOTH hero (line 8 `<section class="page-hero">` + line 11 date-only `<p>Effective February 20, 2026 \| Last Updated May 22, 2026</p>`) AND body byline (line 20/21/22 `**Last Updated:** May 22, 2026 (...)`) |
| Labels exist | `gh label list --limit 200 \| grep -E '^(domain/legal\|priority/p2-medium\|type/feature\|domain/engineering\|priority/p3-low\|type/chore)'` | All 6 labels exist |
| Gate workflow `required_legal_files` | `cat .github/workflows/legal-doc-cross-document-gate.yml` lines 76-81 | privacy / gdpr / dpd / compliance-posture (4 files) |
| Gate workflow `surface_patterns` regex | lines 53-60 | 6 patterns — none match `docs/legal/`-only diff → trivial pass |

### Verified citations (live `gh`)

- All 9 cited PR / issue numbers above resolve to live records with state matching plan attribution. No fabrication, no transposition.
- `gh pr view 4287 --json mergedAt` confirms PR #4287's prior edits to the three legal docs landed today before this plan (2026-05-22) — the `(#4287 — …)` byline segment is real and current.

### Deepen-pass corrections summary

1. Added Enhancement Summary section (this section above) per deepen-plan output contract.
2. Corrected `Files to Edit` byline-shape assumption (GDPR + DPD use the same `**Last Updated:** …` form as Privacy, NOT inline annotations).
3. Generalized AC5 to cover all three Eleventy mirrors (not just `privacy-policy.md`).
4. Added AC5b verifying canonical byline `#<PR>` LEADING segment shape.
5. Added AC5c verifying PA-19 ⊥ PA-20 disambiguation.
6. Added Risk-6 (PA-19/PA-20 conflation hazard) + Risk-7 (#4338 sibling-CI noise).
7. Added Sharp Edges entries for byline-prepend semantics + Eleventy-hero date-only convention.
