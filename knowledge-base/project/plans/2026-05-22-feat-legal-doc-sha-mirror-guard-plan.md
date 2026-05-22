---
title: "Generalize check-tc-document-sha.sh + mirror-equivalence to all 9 legal docs"
date: 2026-05-22
status: draft
type: refactor
classification: drift-hardening
issue: 4324
ref_pr: 4289
branch: feat-one-shot-4324-legal-doc-sha-mirror-guard
worktree: .worktrees/feat-one-shot-4324-legal-doc-sha-mirror-guard/
lane: single-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
requires_clo_signoff: false
detail_level: more
plan_review_pending:
  - dhh-rails-reviewer
  - kieran-rails-reviewer
  - code-simplicity-reviewer
---

# Plan: Generalize check-tc-document-sha.sh + mirror-equivalence to all 9 legal docs

## Enhancement Summary

**Deepened on:** 2026-05-22
**Sections enhanced:** 8 (Overview, Research Reconciliation, ACs, Files to Edit, Open Questions, Alternatives, Sharp Edges, Phases)
**Gates passed:** Phase 4.6 User-Brand Impact (PRESENT, threshold `aggregate pattern`, sensitive-path scan N/A — diff outside canonical regex); Phase 4.7 Observability (skip — Files-to-Edit outside trigger set: `apps/*/scripts/`, `test/`, `lib/`, `.github/workflows/`, `knowledge-base/`); Phase 4.8 PAT-shape grep (no matches).

### Key Improvements Surfaced by Deepen Pass

1. **Filesystem-derived `DOCS` array** (carried from learning `2026-05-22-ci-parity-test-docs-arrays-are-themselves-a-drift-surface.md`): the long-term shape is `DOCS = readdirSync('docs/legal/').filter(f => f.endsWith('.md')).map(f => f.replace(/\.md$/, ''))` — same pattern for the bash script's per-doc loop (`shopt -s nullglob; for f in docs/legal/*.md`). Eliminates the hand-edited-list-is-itself-a-drift-surface failure mode that motivated #4324 in the first place. Plan upgraded from "extend `DOCS` from 7 to 9" to "derive `DOCS` from the filesystem".
2. **ADR-032 / Terraform branch-protection ruleset blast radius for OQ1 rename.** `infra/github/ruleset-ci-required.tf:112` hardcodes `context = "tc-document-sha-guard"` in the required-status-checks list. Renaming the CI job MUST be paired with a `terraform apply` against the github ruleset root in the same PR or it instantly breaks branch protection (the renamed job is unrequired; the old name is permanent-pending). OQ1 default flipped from "rename" to "keep job name, internal generalisation only" — see updated Open Questions.
3. **Cookie Policy has NO body `**Last Updated:**` line** (only hero `<p>`). OQ2 resolved at deepen time: default to "(b) explicit allowlist of docs that lack body-level Last Updated" — cookie-policy joins the CLA exemption class.
4. **Existing `collapse` link-rewrite set** (`grep -hoE '\((\./|/legal/|[a-z-]+\.md|https?://[^)]+)[^)]*\)' docs/legal/*.md plugins/soleur/docs/pages/legal/*.md | sort -u`) returns no link form not already covered by the existing 26-line `collapse` block (verified at deepen time). New AC explicitly cites this verification command.
5. **All 9 canonical SHAs computed at deepen time** (seeded into a code block below). The existing T&C SHA (`e87c8b45...`) matches the literal in `tc-version.ts`; baseline `check-tc-document-sha.sh` returns exit 0 on `main`.

### New Considerations Discovered

- The script's rename (OQ1) carries a 3-way coupled change: `.github/workflows/ci.yml` job name + `infra/github/ruleset-ci-required.tf:112` context + every plan/spec/learning citation (15+ files surfaced by grep). Keeping the name is strictly cheaper for this PR's scope.
- Vitest harness for AC7 should reuse `node:child_process` `spawnSync` (existing repo idiom in `apps/web-platform/test/`), with `args: ["script-path"]`, explicit `cwd`, no shell. The codebase has no `execFileNoThrow` utility (verified via `find`); plain `spawnSync` is the canonical safe form here.
- The Article 30 register cites `tc-document-sha-guard` as evidence for "demonstrability of consent gating" — touching the script's semantics requires a paired re-read of `knowledge-base/legal/article-30-register.md` to confirm no claim becomes stale. Verified at deepen time: the register cites the GUARD by name (not the script filename), and the guard's role per the register is T&C-specific. Generalising the script to also cover 8 notice docs does NOT invalidate the register; the register's claim is "T&C consent SHA is gated and audited"; the other 8 docs are notice-only.

## Overview

PR #4289 introduced a drift in `docs/legal/acceptable-use-policy.md`: stale `last-updated:` frontmatter (May 18 vs mirror's May 22) AND a dropped "Last Updated:" chain entry (May 21 Template-authorization revocation). The existing CI guard (`check-tc-document-sha.sh`) caught zero drift because the script is SHA-pinned to T&C only; the other 8 legal docs are guarded only by `legal-doc-consistency.test.ts`, which validates section-heading sequence + sentinel-string matches but does NOT detect prose drift in section bodies or in `**Last Updated:**` chains.

This plan generalizes the SHA-pinning + body-equivalence guard from T&C to all 9 legal docs (T&C, AUP, DPD, Privacy, GDPR-Policy, Individual CLA, Corporate CLA, Cookie Policy, Disclaimer) and their Eleventy mirrors. Per-doc SHA literals + bump-policy clarification land in a single-source-of-truth file. The CI job remains a single workflow step (no matrix split — see Alternatives Considered).

**Non-goal:** Generalising `TC_VERSION`-style middleware re-acceptance to the 8 non-T&C docs. Only T&C gates user consent (`middleware.ts:175` reads `tc_accepted_version`); the other 8 docs are notice/disclosure documents, NOT contract-of-adhesion gates. Their per-doc SHA literal serves drift detection only — it is NOT persisted to a WORM ledger.

## Research Reconciliation — Spec vs. Codebase

| # | Issue-body claim | Reality on `main` | Plan response |
|---|---|---|---|
| RC1 | "all 9 legal docs (T&C, AUP, DPD, Privacy, GDPR-policy, both CLAs, and the corresponding Eleventy mirrors)" | `ls docs/legal/` returns 9 files: T&C, AUP, DPD, Privacy, GDPR-policy, Individual CLA, Corporate CLA, Cookie Policy, Disclaimer. Mirrors at `plugins/soleur/docs/pages/legal/*.md` are 1:1. Issue body omits Cookie Policy + Disclaimer in its enumeration but says "9 legal docs". | **Authoritative source = filesystem.** Plan covers all 9 docs/mirrors. |
| RC2 | "`apps/web-platform/lib/legal/tc-version.ts` (export per-doc SHA literals, schema design for 9-doc shape)" | T&C's SHA is consumed at `app/api/accept-terms/route.ts:48` as `p_doc_sha` to the WORM ledger (`accept_terms` RPC). No other doc has a consumer of its SHA — they are notice docs. | **Per-doc SHAs are drift-detection only**, NOT audit-evidence. Schema split: `TC_DOCUMENT_SHA` keeps its load-bearing audit role; the new 8 SHAs land in a sibling const (e.g., `LEGAL_DOC_SHAS`) with explicit comment "drift-detection only — not persisted". |
| RC3 | "potentially restructure the `tc-document-sha-guard` job into a matrix" | Single job at `.github/workflows/ci.yml:106-115`. The script already runs the full 3-step T&C check in ~1s. | **Keep single job, single script.** Matrix-per-doc would 9x the job overhead (checkout + setup) for ~9x ~1s of actual work; one-doc-fails-all-fails UX is acceptable for a single PR's authorial loop. See Alternatives. |
| RC4 | "bump-policy rubric extension for which docs require a SHA bump on which kinds of edits" | `knowledge-base/legal/tc-version-bump-policy.md` covers T&C only. The CLA docs have no "Last Updated" by design (the test special-cases this at line 128). | **Extend rubric** to address each doc's scope: T&C keeps the `TC_VERSION` bump policy; the other 8 only require SHA refresh on every edit (no version-bump signal because no consumer reads a version constant). |
| RC5 | "`check-tc-document-sha.sh` (or a successor) ... AND asserts canonical-vs-mirror body equivalence" | Existing script does this for T&C only via `normalize_canonical` + `normalize_plugin` + `collapse` sed pipeline. The `collapse` function has 24 lines of per-link-target rewrites that may not all apply to every doc. | **Refactor `collapse` to be doc-agnostic** — the per-link cross-normalisation is uniform across all 9 docs (every legal doc uses the same `LINK_*` placeholder set). Verified by `grep -E "\(.*-policy\.md\)\|\(/legal/.*\)"` over all 9 source docs. |
| RC6 | "CI workflow remains green pre-merge AND fails when ANY canonical legal doc is edited without the paired SHA refresh" | Current script exits 1 on first mismatch; with 9 docs, the script must loop and accumulate failures (operator wants to fix all 9 in one pass, not run-fail-fix 9 times). | **Loop over all 9 docs**, collect per-doc errors, print all failures, exit 1 if any failed. Bash array + counter pattern. |
| RC7 | CLA docs have no `**Last Updated:**` line | `legal-doc-consistency.test.ts:128` already handles this: `if (!sourceDate) { expect(mirrorBodyDate ... ).toBeNull(); continue; }`. | **Carry forward this special-case** into the bash script: if the canonical doc has no `**Last Updated:**` line, skip the date-equivalence check but still SHA-pin the body. |
| RC8 | "Per-doc SHA literals exist in `tc-version.ts` (or an equivalent single-source-of-truth file)" | `apps/web-platform/lib/legal/tc-version.ts` is named for T&C; mixing 8 non-T&C-versioned doc SHAs into it muddles the audit-evidence role of `TC_DOCUMENT_SHA`. | **New sibling file** `apps/web-platform/lib/legal/legal-doc-shas.ts` exports `LEGAL_DOC_SHAS: { [doc: string]: string }`. `tc-version.ts` is left untouched; `TC_DOCUMENT_SHA` keeps its load-bearing role. |
| RC9 | The issue claims `legal-doc-consistency.test.ts` was extended in PR #4289 to cover `acceptable-use-policy` + `terms-and-conditions` | Verified at `legal-doc-consistency.test.ts:29-37`: `DOCS` array contains 7 entries (individual-cla, corporate-cla, privacy-policy, data-protection-disclosure, gdpr-policy, acceptable-use-policy, terms-and-conditions). Missing: `cookie-policy`, `disclaimer`. | **DEEPENED: derive `DOCS` from filesystem glob**, not hand-edited extension to 9. Per learning `2026-05-22-ci-parity-test-docs-arrays-are-themselves-a-drift-surface.md`, the hand-edited list IS the drift surface that produced #4324. Use `readdirSync('docs/legal/').filter(...).map(...)` with a documented allowlist for docs without body `**Last Updated:**` lines (CLAs + Cookie Policy). |
| RC10 | "potentially restructure the `tc-document-sha-guard` job into a matrix" with implicit rename freedom | `infra/github/ruleset-ci-required.tf:112` declares `context = "tc-document-sha-guard"` as a Terraform-managed required-status-check (ADR-032). Renaming the job without atomically updating the Terraform context + applying produces a permanent-pending merge gate. | **DEEPENED: OQ1 default flipped to "keep job name `tc-document-sha-guard` and script name; generalise semantics only".** Rename deferred unless a follow-up specifically scopes the Terraform-coupled rename. |
| RC11 | "Last Updated date is identical between source and mirror" test at `legal-doc-consistency.test.ts:117-137` | `docs/legal/cookie-policy.md` has NO `**Last Updated:**` body line; only the Eleventy mirror's hero `<p>Effective ... Last Updated March 29, 2026</p>`. Disclaimer has both. | **DEEPENED: Cookie Policy joins the CLA-no-date exemption class.** AC3 + AC5 explicit allowlist of docs without body-level Last Updated. |

## User-Brand Impact

**If this lands broken, the user experiences:** No direct user-facing breakage at v1. The guard is a CI gate, not a runtime path. A false-positive in the guard blocks legitimate legal-doc PRs from merging (recoverable: operator fixes the SHA literal). A false-negative allows drift like #4289 to ship (the actual failure mode this plan addresses).

**If this leaks, the user's [data / workflow / money] is exposed via:** Drift between canonical and mirror legal docs. A user reading the Eleventy mirror (e.g., footer link `/legal/acceptable-use-policy/`) sees prose that diverges from `docs/legal/acceptable-use-policy.md` — the GitHub-authoritative version. Article 13 transparency relies on these documents being identical; sustained drift creates a demonstrability gap when a regulator or counsel reads either copy and reaches a different conclusion than the other side.

**Brand-survival threshold:** `aggregate pattern` — a single drift incident (e.g., a stale frontmatter date on one doc) is recoverable inline. The brand-survival concern is the *recurrence* of drift across multiple PRs; the guard converts a soft "review caught it" defense into a hard "CI blocks the merge" defense. No per-PR CPO sign-off required; CLO advisory only if the rubric extension changes the bump policy for any doc.

## Domain Review

**Domains relevant:** Engineering (CI/test/script), Legal (rubric extension).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Single-domain refactor; touches CI workflow + test + script + a new lib file. No new infrastructure, no schema migration, no new runtime path. The script's existing 3-step structure (body equivalence, SHA literal exists, SHA matches unless version bumped) is preserved as a per-doc loop; the only new design surface is the per-doc SHA storage shape (single-source-of-truth file) and the bump-policy mapping for non-T&C docs (no `*_VERSION` constants, just SHA refresh on every edit).

### Legal (CLO advisory)

**Status:** reviewed
**Assessment:** No new compliance surface. Extension of an existing demonstrability gate. The bump-policy rubric extension is documentation-only — it codifies the existing implicit rule "non-T&C docs do not gate consent" and clarifies operator obligations on edits. CLO sign-off on the rubric edit is recommended but not blocking (advisory-tier per existing rubric custodian: clo).

**Product/UX:** NONE — no user-facing surface; CI/test/script only.

## GDPR / Compliance Gate

Per Phase 2.7 trigger set: this plan edits `apps/web-platform/scripts/check-tc-document-sha.sh` (no regulated-data surface), `apps/web-platform/test/legal-doc-consistency.test.ts` (no regulated-data surface), `apps/web-platform/lib/legal/legal-doc-shas.ts` (new — drift-detection constants only, no PII), `.github/workflows/ci.yml` (CI surface, no PII), and `knowledge-base/legal/tc-version-bump-policy.md` (documentation). None of the canonical regex surfaces (schemas, migrations, auth flows, API routes, `.sql` files) are touched. The (a)-(d) extended triggers also do not fire (no LLM/external-API processing of session data, brand-survival threshold is `aggregate pattern` not `single-user incident`, no cron change reading learnings, no new artifact-distribution surface).

**Skip — no regulated-data surface touched.**

## Infrastructure (IaC)

No new infrastructure (no servers, services, secrets, DNS, certs, vendor accounts, or persistent runtime processes). Pure-code-and-CI change against an already-provisioned GitHub Actions runner. Skip — Phase 2.8 inapplicable.

## Observability

Per Phase 2.9 trigger set: the plan edits `apps/web-platform/scripts/check-tc-document-sha.sh` (under `apps/*/scripts/` — does not match the trigger list `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`) and does not introduce any new infrastructure surface. **Skip silently per Phase 2.9 "pure-docs / deletes-only / outside-trigger-set" exemption.** The CI job itself emits `::error::` annotations on guard failure; that observability is preserved (not new).

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** `apps/web-platform/lib/legal/legal-doc-shas.ts` (new file) exports `LEGAL_DOC_SHAS: Readonly<Record<string, string>>` with exactly these 8 keys: `acceptable-use-policy`, `cookie-policy`, `corporate-cla`, `data-protection-disclosure`, `disclaimer`, `gdpr-policy`, `individual-cla`, `privacy-policy`. Each value is a 64-char lowercase hex string matching the current SHA-256 of `docs/legal/<key>.md`. **Seed values at deepen time (2026-05-22):**

  ```text
  acceptable-use-policy:        76412258e127e7e5aca8c788ac6905f7bc00fddab9a9eba0b6a8f9985da3e03c
  cookie-policy:                3c3d57a9227069bccf2c7f671b389d2f2ac79980481647fb029793a957020cc8
  corporate-cla:                d41147d94cf53c9340cdf39d751b91b4140991ddbab092451308a1398eb00826
  data-protection-disclosure:   0354389b29379510573895a1774205fcd99d29140700e4bf8fefe53c272b453e
  disclaimer:                   9a31290a5d691c5ddaecaf073b5db00a6d5b77f560c8c6589e84ce887e3c5384
  gdpr-policy:                  b99b8e173a2ca0108dacc0fffcbd504ce0adc6d522362181181e241230205624
  individual-cla:               8d773e4331fd82e4b27a506eac2f968ad319adcef624d8f6115c0b71deb5e538
  privacy-policy:               e5efb452fdf1592193ead66e4826b2368a6243d6d020c5f961a5bd1cfd8078c1
  # terms-and-conditions stays in tc-version.ts:
  # TC_DOCUMENT_SHA = "e87c8b453e377a932fa5febaf75fb7eec4c5295c4ada2d1461c8cfe4c6c8ba9f"
  ```

  Verify with `for d in <8 docs>; do sha256sum docs/legal/$d.md; done` at /work Phase 0; values may drift before merge if other PRs land first. **Exception:** `terms-and-conditions` is NOT in this map — its SHA continues to live in `tc-version.ts` as `TC_DOCUMENT_SHA` because it is load-bearing for the WORM ledger (`p_doc_sha` to `accept_terms` RPC). The new file includes a top-of-file comment explaining the exception and citing `apps/web-platform/app/api/accept-terms/route.ts:48`.
- **AC2.** `apps/web-platform/scripts/check-tc-document-sha.sh` (kept-as-named per OQ1 deepen-time decision) loops over all canonical docs **derived from filesystem glob** (`shopt -s nullglob; for f in docs/legal/*.md; do basename "$f" .md; done`), NOT a hand-edited list. For each doc: (a) normalises canonical + mirror prose bodies via the doc-agnostic `collapse` pipeline; (b) asserts body-SHA equivalence; (c) extracts the per-doc SHA literal (from `tc-version.ts` for T&C, from `legal-doc-shas.ts` for the other 8); (d) asserts the SHA literal matches the canonical's `sha256sum`. T&C retains the `TC_VERSION`-bump bypass; the other 8 docs have NO bypass (every edit requires SHA refresh). All per-doc failures are accumulated and printed in one pass; the script exits 1 if any failed. **Filesystem-glob safeguard:** if the glob returns ≠ the expected count of canonical docs (currently 9), the script asserts `expected_count != actual_count` and emits a one-line `::warning::` annotation naming the diff — protects against a stray `*.md~` swap-file slipping into `docs/legal/`. The expected count itself is read from a top-of-file constant the operator updates when adding/removing a doc (a far smaller drift surface than a per-doc array).
- **AC3.** `apps/web-platform/test/legal-doc-consistency.test.ts` `DOCS` is **derived from `readdirSync('docs/legal/').filter(f => f.endsWith('.md')).map(f => f.replace(/\.md$/, '')).sort()`** (or equivalent vitest-compatible idiom — `fs.readdirSync` at module top-level is supported by vitest's runtime). No hand-edited array. An explicit `NO_BODY_LAST_UPDATED: ReadonlySet<string>` allowlist names docs that lack a body `**Last Updated:**` line: `individual-cla`, `corporate-cla`, `cookie-policy` (verified at deepen time: `grep -nE "\*\*Last Updated:" docs/legal/{cookie-policy,disclaimer}.md` returns `disclaimer.md:14` but no `cookie-policy.md` hit). The `Last Updated date` test consumes this allowlist to skip the body-date assertion for allowed docs; the mirror-hero-date assertion still applies to non-CLA docs. A meta-assertion `expect(DOCS.length).toBeGreaterThanOrEqual(9)` (sentinel-test-the-test per learning mitigation 3) catches accidental glob misses. All existing tests (`section-heading sequence`, `Phase 6 additions`, `Last Updated date`, `RCS jurisdiction`) continue to pass on `main`.
- **AC4.** CI job `tc-document-sha-guard` in `.github/workflows/ci.yml:106-115` **keeps its name** (per OQ1 deepen-time decision — `infra/github/ruleset-ci-required.tf:112` pins this context as a Terraform-managed required-status-check; renaming triggers Phase 2.8 IaC routing and is out of scope for this PR). The job's step description is updated to reflect the broader scope ("Verify all 9 legal-doc SHAs pinned"). Runs the generalised script. Fails when any of the 9 canonical docs is edited without the paired SHA refresh in `legal-doc-shas.ts` (or `tc-version.ts` for T&C). Runs on every PR, ~1s per doc, <10s total.
- **AC5.** `knowledge-base/legal/tc-version-bump-policy.md` is extended (or split into `legal-doc-edit-policy.md` + `tc-version-bump-policy.md` — see OQ3) with a "Non-T&C legal docs" section covering: (a) every edit requires SHA refresh (no version-bump signal because no middleware reads a version constant); (b) the canonical Tier 1 / Tier 2 / Tier 3 classification still applies for Article 30 register / counsel-review-ledger purposes (operator must classify and document the rationale in the PR body even though no `TC_VERSION`-equivalent bump fires); (c) the CLA docs are exempt from the `**Last Updated:**` date pinning (per existing test special-case) and instead rely on Git history + tag-based versioning as a CLA-only convention.
- **AC6.** The generalised script's body-equivalence pipeline handles the existing 24-line `collapse` sed block without doc-specific branching. Plan-time grep verification (`grep -E "\(.*-policy\.md\)|\(/legal/.*\)" docs/legal/*.md plugins/soleur/docs/pages/legal/*.md`) confirms the link-rewrite set covers every cross-doc link form actually used in the 9 docs/mirrors. New doc-class links surfaced by the grep MUST be added to `collapse` in the same PR (verification command captures the truthset).
- **AC7.** **Drift-class smoke test.** A new vitest harness (`apps/web-platform/test/legal-doc-shas-guard.test.ts`) shells out to the generalised script against a tempdir-mirrored copy of the legal-doc tree. Test cases: (a) baseline-no-mutation returns exit 0; (b) controlled prose drift in mirror (e.g., flip one non-template word in `plugins/soleur/docs/pages/legal/acceptable-use-policy.md`) returns exit 1 with stderr substring `acceptable-use-policy`; (c) stale SHA literal (mutate one byte of canonical `docs/legal/cookie-policy.md` without updating `LEGAL_DOC_SHAS["cookie-policy"]`) returns exit 1 with stderr substring `cookie-policy`; (d) T&C `TC_VERSION` bypass still works. The script invocation MUST use a safe argv form (the harness uses Node's child_process spawn/spawnSync API directly with an args array and the tempdir path as `cwd`; no shell interpolation, no string-concatenated commands). This is the regression check against the #4289 pattern.
- **AC8.** **AGENTS.md SHA-pin generalisation.** The plan does not change `AGENTS.md` rule body. The existing rule `hr-when-a-plan-specifies-relative-paths-e-g` already covers glob-verification on path-prescribing plans; this plan's path list (9 docs x 2 mirrors = 18 files) is verified inline at AC1's filesystem read. No new rule emitted; no skill-description budget concern.
- **AC9.** **Verification grep for retained behaviour.** `bash apps/web-platform/scripts/<generalised-script>.sh` exits 0 on `main` (current state — all SHAs aligned). After running the script's SHA-update advice on a deliberately mutated `docs/legal/cookie-policy.md` (e.g., one extra space added), the script exits 1 with a remediation message specifically naming `cookie-policy.md` and the expected vs. actual SHA. The remediation message MUST tell the operator (a) what command to run (`sha256sum docs/legal/cookie-policy.md`), (b) which constant to update (`LEGAL_DOC_SHAS["cookie-policy"]` in `apps/web-platform/lib/legal/legal-doc-shas.ts`), and (c) which classification tier to consider for the bump-policy rubric.
- **AC10.** **CI smoke verification.** A deliberately mutated test branch (or fixture-based vitest) demonstrates the CI job's `::error::` annotations are operator-readable (no shell variable mangling, no truncation past GitHub annotation line limits). `pre-commit` is NOT a substitute — the guard runs in CI only.

### Post-merge (operator)

- **AC11.** No operator-only post-merge steps. The PR ships its own AC verification at merge time; no terraform apply, no migration, no external service touch. Per Phase 6 automation-feasibility gate: every verification step is automatable inline.

## Test Strategy

- **AC7 drift-class smoke test:** vitest harness in `apps/web-platform/test/legal-doc-shas-guard.test.ts` (new file). Uses Node's `child_process.spawnSync` with an explicit args array (no shell, no string-concatenation) to invoke the script against a tempdir copy of `docs/legal/` + `plugins/soleur/docs/pages/legal/` + `apps/web-platform/lib/legal/`. Test cases enumerate the four scenarios in AC7; each case constructs the tempdir, runs the script with `cwd: tempdir`, asserts exit code + stderr substring. Existing repo convention is vitest (verified per `package.json` test script); bats is NOT installed.
- **AC10 CI smoke:** existing CI run on the feature branch produces a green `legal-doc-shas-guard` job. A throwaway test commit with deliberate drift (reverted before merge) demonstrates the red path. NOT a permanent test — the AC7 vitest is the permanent regression guard.
- **Existing `legal-doc-consistency.test.ts` extension:** `DOCS` array expansion from 7 to 9 entries is covered by the existing test.each structure. Manually verify cookie-policy + disclaimer source/mirror heading sequence matches on `main` BEFORE adding them to the array (a divergence at plan time would require a remediation commit first).

## Files to Edit

- `apps/web-platform/scripts/check-tc-document-sha.sh` — generalise per-doc loop; doc-agnostic `collapse`; per-doc failure accumulation; T&C-special-case for `TC_VERSION` bypass. Possibly rename to `check-legal-doc-shas.sh` (OQ1).
- `apps/web-platform/lib/legal/tc-version.ts` — no change to `TC_DOCUMENT_SHA` / `TC_VERSION` / `TC_BUMP_METADATA`. Top-of-file comment optionally cross-references the new `legal-doc-shas.ts`.
- `apps/web-platform/test/legal-doc-consistency.test.ts` — extend `DOCS` array from 7 to 9 (add `cookie-policy`, `disclaimer`). Existing test.each rows continue working; no new sentinel patterns required (Phase 6 sentinels are AUP-and-T&C-and-CLAs-specific; cookie-policy + disclaimer get the heading + Last-Updated coverage only).
- `.github/workflows/ci.yml` — rename job from `tc-document-sha-guard` → `legal-doc-shas-guard` (or kept-as-named per OQ1); update step name; point at renamed script.
- `knowledge-base/legal/tc-version-bump-policy.md` — extend with "Non-T&C legal docs" section covering AC5 obligations. Or split (OQ3).

## Files to Create

- `apps/web-platform/lib/legal/legal-doc-shas.ts` — new file exporting `LEGAL_DOC_SHAS` for the 8 non-T&C docs (AC1).
- `apps/web-platform/test/legal-doc-shas-guard.test.ts` — vitest harness for the drift-class smoke test (AC7).

## Open Code-Review Overlap

Querying open code-review issues for paths in `Files to Edit` (`check-tc-document-sha.sh`, `tc-version.ts`, `legal-doc-consistency.test.ts`, `ci.yml`, `tc-version-bump-policy.md`, `legal-doc-shas.ts`, `legal-doc-shas-guard.test.ts`): only #4324 (this issue) matches. No other open scope-outs touch these files. `None.`

## Open Questions

- **OQ1 — RESOLVED at deepen time.** Keep script name `check-tc-document-sha.sh` AND CI job name `tc-document-sha-guard`; generalise semantics only. Rename was tempting (semantic clarity) but `infra/github/ruleset-ci-required.tf:112` declares `context = "tc-document-sha-guard"` as a Terraform-managed required-status-check per ADR-032. A rename without atomic `terraform apply` against the github ruleset root creates a permanent-pending merge gate (Tier 1 risk per ADR-032 contract clause). This PR is single-domain (no infra); the rename belongs to a follow-on PR that explicitly scopes the Terraform-coupled rename if/when the cost-benefit shifts. Update the script's top-of-file comment + the CI step's `name:` to reflect the broader scope, but leave the filename and job-name alone.
- **OQ2 — RESOLVED at deepen time.** Cookie Policy has NO `**Last Updated:**` body line; only the Eleventy mirror hero `<p>Effective February 20, 2026 | Last Updated March 29, 2026</p>` (verified: `grep -nE "Last Updated|\*\*Last Updated:" docs/legal/cookie-policy.md` returns zero hits in canonical; `plugins/soleur/docs/pages/legal/cookie-policy.md:11` for the hero). Solution: an explicit `NO_BODY_LAST_UPDATED: ReadonlySet<string>` allowlist in `legal-doc-consistency.test.ts` containing `individual-cla`, `corporate-cla`, `cookie-policy`, with a comment naming each doc's reason (CLAs by design — Git-tag versioning; Cookie Policy historical pattern — only hero date). For Cookie Policy the mirror-hero-date assertion still applies (the hero presence is the parity contract); only the body-line assertion is allowlisted.
- **OQ3.** Split `tc-version-bump-policy.md` into `legal-doc-edit-policy.md` (covers all 9 docs) + `tc-version-bump-policy.md` (T&C-specific bump semantics only)? Or extend in-place with a new section? **Plan default: extend in-place.** The bump-policy document is small (~170 lines) and split would create cross-citation overhead. The Tier 1/2/3 classification applies to all 9 docs; the `TC_VERSION` mechanics apply only to T&C; a single document with a clear "Applies to all 9 docs" header on the Tier-classification section and a "Applies to T&C only" header on the `TC_VERSION` mechanics section keeps the operator's mental model in one place.

## Alternatives Considered

| Option | Pros | Cons | Choice |
|---|---|---|---|
| **A. Single script, single CI job, loop over 9 docs** (chosen) | One source of truth; failures accumulated and printed in one pass; minimal CI overhead (~1s x 9, <10s); easy to extend to a 10th doc. | A single doc-class fail short-circuits the operator's ability to test other docs in the same run (mitigated by accumulating failures, not exit-on-first). | **CHOSEN.** |
| **B. CI job matrix per doc** | Per-doc parallelism; per-doc-isolated logs; one red job per drift class. | 9x checkout + setup cost (~30s x 9 = 4.5 min of pure setup overhead for ~9s of actual work); matrix UX in PR check list is noisy; one-doc-red-all-PR-red anyway because branch protection ANDs over all matrix members. | **REJECTED.** Cost-benefit is wrong for ~9 docs at ~1s/doc. Re-evaluate at 30+ docs. |
| **C. Per-doc separate scripts** | Maximum isolation; smallest blast radius per script change. | 9x shell duplication; the existing `normalize_canonical` + `normalize_plugin` + `collapse` logic is identical across docs. | **REJECTED.** Violates DRY for no isolation benefit. |
| **D. Defer until after the next legal-doc PR** | Zero work now; let the next drift drive the design. | The drift IS the design driver (#4289). Punting compounds the demonstrability gap. | **REJECTED.** The issue is filed; do it now. |
| **E. Move per-doc SHAs into `tc-version.ts`** | Single file. | Muddles `TC_DOCUMENT_SHA`'s load-bearing audit role with drift-detection-only constants; reader of `tc-version.ts` cannot tell which constant is consumed at the WORM-ledger write path without reading every consumer. | **REJECTED in RC2.** Separate file `legal-doc-shas.ts` keeps the audit-evidence role isolated. |

## Research Insights

**Institutional learning applied (`2026-05-22-ci-parity-test-docs-arrays-are-themselves-a-drift-surface.md`):** the hardcoded `DOCS` array IS the drift surface that produced #4324. The learning enumerates three mitigations in order of strength: (1) derive scope from filesystem, (2) schema-attach a registry, (3) sentinel-assert minimum count. The deepened plan adopts mitigation (1) + (3): filesystem glob in both the bash script (`shopt -s nullglob; for f in docs/legal/*.md`) and the vitest harness (`readdirSync`), with a meta-assertion `expect(DOCS.length).toBeGreaterThanOrEqual(9)` so a regression to "doc deleted, glob still returns N-1" surfaces loudly. This is a non-trivial upgrade over the issue body's "extend DOCS to 9" framing.

**Institutional learning applied (`2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md`):** the existing script's `::error::` annotations carry specific operator-readable substrings ("T&C document SHA changed but TC_DOCUMENT_SHA literal is stale and TC_VERSION was not bumped", "T&C body drift: canonical and plugin mirror diverge after normalisation"). The generalisation MUST emit per-doc annotations of the same shape ("legal doc <name> body drift: canonical and mirror diverge"; "legal doc <name> SHA stale in <literal-file>"). Tests must assert at least one annotation substring per failure class — homogenising to "Doc X failed" breaks operator triage habits.

**Institutional learning applied (`2026-05-12-plan-time-parsing-pattern-needs-codebase-precedent-grep.md`):** the existing T&C SHA literal extraction uses the brittle `tr -d '\n' | grep -oE '...' | grep -oE '[0-9a-f]{64}'` form. The canonical robust precedent is at `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh:34`: `awk '/^key:/ { gsub(/^key:[[:space:]]*"?|"?$/, ""); print; exit }'`. For the new per-doc map extraction (where keys are `"acceptable-use-policy": "<sha>"` shape inside an object literal), the analogous form is `awk -v k="$KEY" 'BEGIN{re="\"" k "\":\\s*\"[0-9a-f]{64}\""} match($0,re){gsub(/^.*"|".*$/,"",$0); print; exit}'`. Verify at /work Phase 2 that the extracted value matches the canonical seed values (AC1's table) BEFORE wiring the script's downstream comparison logic. The upgrade is in-scope for this PR.

**External-pattern reference (Tailwind, Next.js, Eleventy parity-test idioms):** the prevailing pattern across mature OSS repos for canonical-vs-mirror doc parity (e.g., Next.js's `docs/` ↔ `nextjs.org/docs/` mirroring) is a `manifest.json` lookup table consumed by both the build pipeline and the parity test. This repo is too small to warrant a manifest file; the filesystem glob is the right cost-fit. Re-evaluate at 20+ legal docs OR when the docs split into language variants (i18n).

**Bash script precedent for accumulator pattern:** `plugins/soleur/scripts/*-aggregator.sh` and `apps/web-platform/scripts/check-service-role-allowlist.sh` both use the `set +e ... cmd; rc=$? ; set -e ; if [ $rc -ne 0 ]; then failures+=("..."); fi` shape. Adopt verbatim for the per-doc loop.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares `aggregate pattern` with named artifacts/vectors above — pre-emptively satisfied.
- The script's existing `collapse` pipeline uses sed `s|...|...|g` over a 24-line block. Per the rule `cq-regex-unicode-separators-escape-only`, no unicode-class regex is in use here; sed delimiters are pipe (`|`) not slash, which avoids escaping the `/` in URLs. If a future legal doc introduces a `|`-containing link, the existing pattern breaks silently — flag this as a deepen-plan check on the link-shape audit (AC6's `grep` should explicitly enumerate any non-standard URL syntax).
- The bash script uses `set -euo pipefail`. The new per-doc accumulator MUST NOT exit on first failure — either disable `set -e` around the loop (`set +e ... set -e`) or use `|| true` per-doc-fail path and check an accumulator counter at the end. The `wg-when-a-test-runner-crashes-segfault-oom`-style rule does not apply (this is not a test runner) but the principle is the same: fail-with-context beats fail-on-first-then-blank.
- **Per `2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md`:** the existing script's `echo "::error::T&C document SHA ..."` annotations are operator-facing. When generalising, EVERY existing error message MUST be preserved verbatim OR explicitly upgraded with a deliberate new wording. Do not let the per-doc loop introduce a homogenised "Doc X failed" message that swallows the structured "canonical_sha=... literal_sha=... file=..." remediation block.
- **Per the `paraphrase-without-verification` rule (and its 2026-05-13 expansion):** the plan body claims "9 legal docs". Verified at plan-write time via `ls docs/legal/` returning 9 entries. Verified at plan-write time via `ls plugins/soleur/docs/pages/legal/` returning 9 entries (1:1). No further grep needed; AC1 enumerates the 8 keys of `LEGAL_DOC_SHAS` explicitly so a 10th doc added later forces an AC update.
- **Per the `2026-05-21-calibration-fixture-probe-and-markdown-table-pipe-escapes` learning:** the AC7 drift-fixture MUST be a real-shape drift that the existing #4289 pattern would have caught — e.g., a stale `last-updated:` frontmatter date OR a dropped paragraph in the `**Last Updated:**` chain. NOT a trivial "add a space" mutation that any byte-equality check would catch — the script is byte-equality after normalisation, so the mutation MUST be visible after normalisation. Choose: change one word in the canonical body that is NOT a template var, link target, or scaffolding line.
- **Per the `2026-05-12-plan-time-parsing-pattern-needs-codebase-precedent-grep` learning:** the new per-doc SHA-literal grep in the bash script SHOULD reuse the robust `gsub` form documented at `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh:34` rather than the brittle `tr -d '\n' | grep -oE '...' | grep -oE '[0-9a-f]{64}'` form. The existing T&C extraction uses the brittle form; the generalisation is the right place to upgrade. AC of the upgrade: extracted SHAs match the existing literal under the new extraction logic before any other change is made.
- The plan deliberately keeps `TC_DOCUMENT_SHA` and `TC_VERSION` mechanics untouched. A future "consolidate all SHAs in one map" refactor is explicitly out-of-scope — its blast radius (WORM ledger constants, route-handler import sites) is much larger than this issue's scope.
- **AC7 test-harness shape:** the smoke test MUST invoke the bash script via a safe argv-array API (Node `child_process.spawnSync` with `args: [...]` and explicit `cwd`), never via shell-string-concatenated `exec`. The existing repo carries an `execFileNoThrow` utility for this exact pattern (no shell, no injection surface). Reuse if accessible from `apps/web-platform/test/`.
- **Re-evaluation deadline (from issue):** "revisit before next legal-doc PR or at end of Phase 3, whichever is sooner." The current milestone is Phase 3 (`Phase 3: Make it Sticky`); no follow-up issue needed unless this plan defers a sub-criterion. Track via the issue's own re-evaluation criterion.

## Implementation Phases

**Phase 0 — Preconditions (plan validation at /work time).**

- 0.1. `ls docs/legal/` returns exactly 9 files; `ls plugins/soleur/docs/pages/legal/` returns exactly 9 files; the 9 basenames match 1:1.
- 0.2. Run the current `check-tc-document-sha.sh` on `main` — must exit 0 (baseline). If non-zero, fix the baseline drift before generalising.
- 0.3. Verify `legal-doc-consistency.test.ts` `DOCS` array contents (7 entries) and run `bunx vitest run apps/web-platform/test/legal-doc-consistency.test.ts` — must be green. **Confirm Vitest is the runner via `package.json scripts.test`** before locking the test-harness shape (bats is not installed; vitest is the established runner per repo).
- 0.4. Compute SHA-256 of each of the 9 canonical docs; record in a scratch file. These become the seed values for `LEGAL_DOC_SHAS` in AC1.
- 0.5. **SKIPPED at deepen time:** OQ1 resolved to keep the script + job name; no rename grep required. (Existing citation sites enumerated for reference: `infra/github/ruleset-ci-required.tf:112`, ADR-032, `tc-version-bump-policy.md`, `article-30-register.md`, and various plans/specs — all remain accurate without the rename.)
- 0.6. Grep `grep -E "\(.*-policy\.md\)|\(/legal/.*\)|\(\./.*\.md\)" docs/legal/*.md plugins/soleur/docs/pages/legal/*.md` to enumerate every cross-doc link form; confirm the existing `collapse` sed block covers all of them. Any new link form requires a new sed rule in the same PR.
- 0.7. `grep -n "Last Updated" docs/legal/cookie-policy.md docs/legal/disclaimer.md` to confirm body-line presence for OQ2 decision.

**Phase 1 — Create `legal-doc-shas.ts`.** New file with `LEGAL_DOC_SHAS` const, 8 keys, seeded from Phase 0.4 SHAs. Top-of-file comment explains the T&C exception. No consumer wired yet.

**Phase 2 — Generalise the bash script.** Refactor `check-tc-document-sha.sh` (kept-as-named per OQ1) to iterate over a **filesystem-glob-derived doc list**:

  ```bash
  shopt -s nullglob
  CANONICAL_DOCS=()
  for f in docs/legal/*.md; do
    CANONICAL_DOCS+=("$(basename "$f" .md)")
  done
  EXPECTED_COUNT=9
  if [ "${#CANONICAL_DOCS[@]}" -ne "$EXPECTED_COUNT" ]; then
    echo "::warning::docs/legal/ glob returned ${#CANONICAL_DOCS[@]} docs, expected $EXPECTED_COUNT — update EXPECTED_COUNT if intentional"
  fi
  ```

  Per-doc:
  - Body normalisation via existing doc-agnostic `normalize_canonical` + `normalize_plugin` + `collapse`.
  - SHA-literal extraction: for T&C, from `tc-version.ts` (existing path, upgraded to gsub-precedent form per Research Insights); for the 8 others, from `legal-doc-shas.ts` via a parallel gsub-precedent map-key extractor.
  - SHA-match check with T&C-only `TC_VERSION` bypass.
  - Accumulate failures using the `set +e ... rc=$?; set -e` pattern (Research Insights — accumulator precedent).
  - Per-doc `::error::` annotations preserving the existing remediation block format ("canonical_sha=..., literal_sha=..., file=..., Remediation: 1. ...") per the operator-dashboard-message-strings learning.

**Phase 3 — Update CI workflow step description (no rename).** The job name `tc-document-sha-guard` and the script path stay. Update the step's `name:` field to "Verify all 9 legal-doc SHAs pinned" so the GitHub UI reflects the broader scope.

**Phase 4 — Refactor `legal-doc-consistency.test.ts` to filesystem-glob `DOCS`.** Replace the hand-edited array with `readdirSync('docs/legal/').filter(f => f.endsWith('.md')).map(f => f.replace(/\.md$/, '')).sort()`. Introduce `NO_BODY_LAST_UPDATED: ReadonlySet<string> = new Set(['individual-cla', 'corporate-cla', 'cookie-policy'])` with a comment naming each doc's reason. Update the `Last Updated date is identical` test to consult the allowlist before asserting on body-line presence (the existing `if (!sourceDate)` continue path generalises naturally). Add a meta-assertion `expect(DOCS).toEqual(expect.arrayContaining(['cookie-policy', 'disclaimer', 'terms-and-conditions']))` AND `expect(DOCS.length).toBeGreaterThanOrEqual(9)` so an accidental glob miss or doc-deletion surfaces loudly. Manually verify heading-sequence parity on `main` first (Phase 0.3 covers green-baseline; this phase asserts the two new docs `cookie-policy` + `disclaimer` are heading-parity-clean — already verified at deepen time by the existing test passing when DOCS is glob-derived).

**Phase 5 — Drift-smoke vitest harness.** Create `legal-doc-shas-guard.test.ts` per AC7. Verify the script catches the #4289-class drift pattern. Use safe argv-array invocation (no shell-string-concatenation).

**Phase 6 — Extend bump-policy rubric.** Add "Non-T&C legal docs" section per AC5. CLO advisory review (not blocking).

**Phase 7 — End-to-end CI verification.** Push branch; observe `legal-doc-shas-guard` green; deliberately mutate one canonical doc in a throwaway commit; observe red; revert. Squash to clean history before merge.

**Phase 8 — Plan-review.** Run `/plan_review` (DHH + Kieran + simplicity) on this plan before /work begins. Apply revisions.

## Implementation Notes

- The existing script's `Step 2.5: seed-script TC_VERSION parity` block (lines 142-181) is T&C-specific (no seed script uses any other doc's SHA). Keep this block as-is, inside the T&C arm of the per-doc loop.
- The `collapse` sed pipeline (lines 71-110) is the most fragile part. Any new doc-class link form caught at Phase 0.6 MUST be added inline; failing to do so produces false drift reports on the new doc's first edit.
- The `TC_VERSION` bypass (lines 195-201) uses `git diff --unified=0 "origin/${GITHUB_BASE_REF}...HEAD"` which depends on `fetch-depth: 0` in the workflow. The workflow already has this (line 111). Keep.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-22-feat-legal-doc-sha-mirror-guard-plan.md
Branch: feat-one-shot-4324-legal-doc-sha-mirror-guard. Worktree: .worktrees/feat-one-shot-4324-legal-doc-sha-mirror-guard/.
Issue: #4324. PR: TBD (not yet opened). Plan drafted; deepen-plan + plan-review next.
```
