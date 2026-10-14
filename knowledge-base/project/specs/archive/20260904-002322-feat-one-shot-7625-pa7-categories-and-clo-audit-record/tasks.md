---
title: "Tasks — Art. 30 PA-7 §(c) categories + the missing #7622 CLO review record"
branch: feat-one-shot-7625-pa7-categories-and-clo-audit-record
plan: knowledge-base/project/plans/2026-09-03-legal-pa7-c-categories-and-clo-audit-record-plan.md
issue: 7625
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks

Derived from the plan after a seven-agent review pass. **The plan's
`## CLO Advisory — Binding Rulings` and its `## Addendum after plan review` govern; where a task here
and the advisory disagree, the advisory wins.** Phase order is dependency order, not narrative order —
the filings phase runs before the amendment because THREE cells cite issue numbers it mints — the
`CORPUS DIVERGENCE` block and the `(h)` cell cite #7812, and the Special-categories cell cites issue
7815. (An earlier draft said two and missed that third dependency.)

> **Numbering note.** This file counts phases from 1; the plan counts from 0. The mapping is
> `tasks N` = `plan N-1` throughout: tasks Phase 1 = plan Phase 0 (transcribe the advisory), tasks
> Phase 3 = plan Phase 2 (filings), tasks Phase 4 = plan Phase 3 (amend PA-7), and so on. A "Phase N"
> reference *inside* this file always means this file's numbering. Separately, `Phase 4: Validate +
> Scale` in backticks is a GitHub **milestone**, not a phase in either list.

## Phase 1 — Transcribe the binding advisory

- [ ] 1.1 Read `## CLO Advisory — Binding Rulings` and `## CLO Advisory — Addendum after plan review`
      in full before touching anything.
- [ ] 1.2 Create `knowledge-base/legal/audits/2026-09-counsel-review-7625.md` and write both sections
      verbatim. Frontmatter modelled on
      `knowledge-base/legal/audits/2026-08-20-clo-review-7624-corpus-transfer-reconciliation.md:1-29`:
      the twelve-key common core plus `governing_record`, `scope_boundary`, `related`, and `pr:` once
      the PR exists.
- [ ] 1.3 Carry the standing caveat verbatim (v1 internal counsel review; not a substitute for
      external counsel; external counsel reserved for the frontmatter triggers).
- [ ] 1.4 Record in it that the register is a **public file in a public repository** — "internal-only"
      means not-mirrored-to-the-published-corpus, not non-public — so after this PR lands the
      divergence is visible from public sources alone. That is an independent reason to bound PR B.

## Phase 2 — Record the archive as UNMEASURED

- [ ] 2.1 Write `written_against:` recording the archive's realised contents as **UNMEASURED**, with
      the reason: the capture predicate is a code fact; the register records what is processed, not
      what the bucket holds.
- [ ] 2.2 Record which of three states applies — *measured*, *read-refused*, *credentials-absent*.
      Never record a `signatures/` count of zero as measured-empty: at least two records must exist if
      the path ever fired.
- [ ] 2.3 Do **not** gate the register edit on this. Ruling 1 is explicit.

## Phase 3 — File what the advisory split out (runs before the amendment)

- [ ] 3.1 `gh label list --limit 200` — confirm the ten verified labels still exist.
- [ ] 3.2 File **PR B** (published-corpus transparency *and rights* gap). Milestone
      `Phase 4: Validate + Scale`. Scope: `gdpr-policy.md` §3.4, `privacy-policy.md` §§4.5, **5.11**
      and **8.1**, `data-protection-disclosure.md` §2.3(n), three Eleventy mirrors, a
      `legal-doc-shas.ts` re-pin. **No `EXPECTED_COUNT` change.** Trigger: before tester #2 comments
      on a PR here. Mark blocked-by 3.3. Carry the measurement recipe as a prerequisite of drafting
      §3.4.
- [ ] 3.3 File **"Close the cla-evidence capture-predicate gap"** — one issue, `type/security` +
      `domain/engineering`, milestone `Phase 4: Validate + Scale`. Frame as **spec-implementation
      drift against an approved design** (`2026-05-04-feat-cla-legal-rigor-evidence-layer-plan.md:151`
      step 3(c)), not an open question. Include: gate on the event payload not the fetched body; the
      two-sided `edited` predicate; mirror upstream matching semantics; no schema change; the
      `override_reason` enum + DPA-log split + the `>=10 chars` help-text drift + both runbook sites;
      a sign-comment mode for `sentinel-pr.sh`.
- [ ] 3.4 File the four `compliance/critical` issues, one per Active Items row (A5 table).
- [ ] 3.5 File the AUP §4.7 over-broad citation issue — **four sites**: PA-17's Special-categories
      cell AND its Art. 6(1)(f) balancing limb, PA-31's Special-categories cell, PA-33's
      Special-categories cell. Not PA-35, and not two — the two-site figure was retracted at
      addendum A7.1. Cite by activity and cell, never by line number (`cq-cite-content-anchor-not-line-number`):
      the `(h)` row this PR adds shifts every line anchor below it.
- [ ] 3.6 File the six remaining bare `**Special categories**` labels (PA-3/4/5/6/8/9) as one
      mechanical pass. Measured: 31 rows, 24 suffixed, 7 bare. Post-MVP.
- [ ] 3.7 File the C4 gaps issue (FreeTSA element, `soleur-cla-evidence` R2 edge). Post-MVP.
- [ ] 3.8 File the register's ten pre-existing markdownlint errors — `MD034` ×6, `MD050` ×2, `MD038`,
      `MD055`, all outside PA-7. Post-MVP.
- [ ] 3.9 Fold the signer-only retrieval runbook into the `(h)` issue — do not edit it here; it is
      inside `lint-infra-no-human-steps.py`'s scan dirs.
- [ ] 3.10 Every issue gets a milestone. Items for PR B and the capture-predicate gap →
      `Phase 4: Validate + Scale`; the rest → `Post-MVP / Later`. A split whose other half lands
      undated is a deferral wearing a split's clothes.

## Phase 4 — Amend PA-7 (five cells)

- [ ] 4.1 `(c) Categories of data subjects` — Ruling 2 text + `WIDENING` block (A2) + `CORPUS
      DIVERGENCE` block (A3), with the real PR B issue number substituted.
- [ ] 4.2 `(c) Categories of personal data` — Ruling 2 text (**include `schema_version` in shape 3**)
      + `WIDENING` block.
- [ ] 4.3 `Special categories` → relabel `Special categories (Art. 9 / 10)`; Ruling 1 text +
      `CORRECTION` block.
- [ ] 4.4 `Lawful basis` — Ruling 3 text **with the A1 corrected limb-(iii) tail** + `CORRECTION`
      block ending by pointing at the divergence block rather than restating it.
- [ ] 4.5 Add the new `(h) DSAR (Art. 15 / 20)` row (A4). No amendment block.
- [ ] 4.6 Carry the dormancy observation into the capture-predicate sentence.
- [ ] 4.7 Every block goes **before** the row's terminating `|`. Anchor edits on the row prefix, never
      a line number.
- [ ] 4.8 Re-read every cross-reference in the five cells against its target document.

## Phase 5 — Write the #7622 CLO review record

- [ ] 5.1 `gh pr view 7622 --json body --jq .body`.
- [ ] 5.2 Create `knowledge-base/legal/audits/2026-09-03-clo-review-7622-pa7-r2-evidence-layer.md`.
      Frontmatter modelled on `2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md:1-25`.
- [ ] 5.3 All nine findings, grouped §(g) / §(d) / §(e) as the source groups them.
- [ ] 5.4 `date: 2026-09-03`, `pr: 7622`, `attested_commits: 28612e8cd`; body states it records a
      2026-08-20 review. Its `disposition` and triggers are that review's, restated as history.
- [ ] 5.5 Facts, not arguments. Keep the meta-reasoning out.

## Phase 6 — Sweep, compliance rows, index

- [ ] 6.1 `grep -rn "PA-7\b\|Processing Activity 7\b" --include=*.md . | grep -v /archive/`.
- [ ] 6.2 Add **four** Active Items rows to `compliance-posture.md`, each referencing its Phase 3
      issue, `Status: OPEN`, with a `check_id`. Bump `last_updated`.
- [ ] 6.3 Confirm Ruling 6's "zero edits" — §0 DPO cell and `compliance-posture.md:20,44` untouched.
- [ ] 6.4 Confirm the PA count is unchanged.
- [ ] 6.5 `bash scripts/generate-kb-index.sh && git add knowledge-base/INDEX.md`.

## Phase 7 — Verify

- [ ] 7.1 `python3 scripts/lint-credential-path-literals.py`
- [ ] 7.2 `cd apps/web-platform && npx vitest run --project repo-wide test/legal-doc-consistency.test.ts`
- [ ] 7.3 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`
- [ ] 7.4 `npx --yes markdownlint-cli` on the two new audit files and the plan — **not** the register.
- [ ] 7.5 Handle the register's markdownlint blocker deliberately: `.markdownlintignore` in a separate
      PR, or `--no-verify` with the ten-error baseline recorded in the PR body. Do not discover this
      at commit time — `lefthook.yml:18-22` runs markdownlint on staged `*.md` and the register fails
      on ten pre-existing errors.
- [ ] 7.6 Re-read every cross-reference in the five amended cells against its target document. The
      review pass caught one false cross-reference the advisory itself had introduced.
- [ ] 7.7 Walk AC1-AC19.
