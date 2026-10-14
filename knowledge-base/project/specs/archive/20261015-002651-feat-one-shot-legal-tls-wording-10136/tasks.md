# Tasks: qualify the in-transit TLS claim (Ref #10138 item 3, Ref #10136)

Plan: `knowledge-base/project/plans/2026-10-14-fix-legal-qualify-in-transit-tls-claim-plan.md`. Decisions: `decision-challenges.md` in this directory. Legal wording is CLO-ruled; do not reword. Locate every edit by content anchor, not line number. Use exact-string replace with a count-equals-one assertion (the target lines are 1 to 38 KB single paragraphs).

## Phase 1: Setup

- 1.1 Fetch `origin/main`; record the baseline: run the five Phase 4 gates once and confirm they are green before editing.
- 1.2 Confirm the sibling drafts (#10291, #9051, #8626) are still open and note which passages they touch; do not edit those passages.

## Phase 2: Published documents (canonical then mirror)

- 2.1 Privacy Policy section 11 bullet: canonical and mirror, exact CLO text (plan Phase 1a).
- 2.2 DPD 8.1(c): canonical and mirror, CLO split-status text (plan Phase 1b).
- 2.3 Last Updated entries in PP and DPD, canonical and mirror body (plan Phase 1c); `Previous:` chain kept intact.
- 2.4 Mirror hero `<p>` date in both mirrors (plan Phase 1d). Defer the final date value to 5.3.

## Phase 3: Article 30 register

- 3.1 PA-1 (g)(1) full marker; PA-2 (g)(1) one-clause marker; PA-3 (g) one-clause marker plus inline `Added` pointer (plan 2a-2c).
- 3.2 Cross-Cutting bullet: indented blockquote after the unedited bullet (plan 2d); run markdownlint.
- 3.3 PA-13 (g): new final item (14), single source of truth (plan 2e). Do not edit (11).
- 3.4 Pointers on PA-16, PA-17, PA-21, PA-22, PA-27, PA-29, no field lists (plan 2f).
- 3.5 Verify by diff that PA-4, PA-6, PA-14, PA-18, PA-31, PA-36 and `last_reviewed` are untouched.

## Phase 4: Ledger and DPA template

- 4.1 Ledger: `disclosed_as` of the Supabase connection row -> `not-publicly-claimed`; nothing else (plan 3a).
- 4.2 DPA template: replace the one `Encryption in transit` list item (plan 3b).

## Phase 5: Verification and final pin

- 5.1 Re-open each call site named in AC11 and build the claim-to-source table for the PR body; drop any claim whose call site is gone.
- 5.2 Run the AC greps (word-level `ADDED` helper) for AC1, AC2, AC4-AC9.
- 5.3 Post the #10136 comment (PR link, step-outputs discrepancy, follow-up list) before marking ready.
- 5.4 Final pin: set the Last Updated date `<D>` on all six surfaces, `sha256sum` both canonical files into `legal-doc-shas.ts`, run the Phase 4 gate list (drift ratchet, `check-tc-document-sha.sh`, `lint-encryption-posture.py --repo-sweep`, `lint-legal-registers.sh`, `probe-legal-corpus-truth.sh`, the two vitest files, markdownlint).
- 5.5 Spawn the CLO agent with the final diff for attestation; record `Ruled by CLO agent, <date>: ...` in the PR body.

## Phase 6: Ship

- 6.1 PR body: `Ref #10138`, `Ref #10136`, Tier 2, the `operator (scope)` items, the DPD (c) deviation and why, "no TLS added, no exception renewed". No `Closes`.
- 6.2 If a sibling PR merged first: one `git merge origin/main`, resolve the Last Updated line keeping all entries in date order, recompute both hashes from the merged canonical files, rerun the gates, CLO re-attests. Whichever of this PR and its siblings merges second does this.
- 6.3 Merge queue; then `soleur:postmerge`; verify the two live soleur.ai pages (old sentence count 0, HTTP 200) and `tc-document-sha-guard` green on `main`. Emit DONE only after `postmerge verification complete!`.
