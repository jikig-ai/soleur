---
title: "Vendor General-Legal CC0 legal templates into legal-generate"
date: 2026-09-13
lane: cross-domain
brand_survival_threshold: single-user incident
issue: "#8122"
brainstorm: knowledge-base/project/brainstorms/2026-09-13-legal-templates-cc0-eval-brainstorm.md
pr: "#8120"
---

# Feature: Vendor General-Legal CC0 legal templates into legal-generate

## Problem Statement

Soleur's `legal-generate` skill generates 8 published-compliance document types entirely from the model's parametric knowledge — no attorney-drafted baseline, and no coverage of the bilateral contract types founders most often need (MSA, NDA, advisor agreement, offer letter, BAA). `General-Legal/legal-templates` is a real, CC0-1.0-licensed, attorney-drafted library of 12 startup legal templates in LLM-optimized markdown (`<mark>` customization fields), offering both better grounding for our existing types and net-new contract coverage.

## Goals

- Vendor all 12 General-Legal templates (verbatim, pinned commit) as the plugin's second vendored-content bundle under `plugins/soleur/skills/legal-generate/references/templates/`.
- `legal-generate` switches to template-fill: the generator fills `<mark>` fields from Phase-0 company context and wraps output in the existing YAML-frontmatter + dual-DRAFT-blockquote contract; Phase-2.5 redaction gate unchanged.
- Generalize the vendored-content machinery (currently single-bundle, hardcoded to gdpr-gate) to a multi-NOTICE registry.
- Expand `legal-generate`'s doc-type coverage to the contract class, with regulated/off-ICP gates on the BAA and offer letter.

## Non-Goals

- No fetch-at-runtime path (rejected: availability + unpinned-drift + prose-injection risk on fetched text).
- No `recommended-tools.md` vendor row required by this feature (vendor-neutrality test would need ≥2 vendors; optional follow-up).
- No `.docx` originals (regenerable via upstream scripts; binary dead weight).
- No placement under `docs/legal/` or `plugins/soleur/docs/pages/legal/` (mirror/SHA gates; republication-under-our-name, #7331 class).
- No "attorney-drafted" marketing claims on generated output.
- Not a re-litigation of the claude-for-legal bridge (#3786 stays deferred; this feature partially serves its demand — comment on #3786 at ship time).

## Functional Requirements

### FR1: Vendored template corpus

All 12 upstream `templates/<name>/template.md` files vendored verbatim into `plugins/soleur/skills/legal-generate/references/templates/<name>/` (README.md may be included for context; `.docx` excluded). Each file carries the line-1 header `<!-- Adapted from General-Legal/legal-templates (CC0-1.0) — see NOTICE -->` and its embedded "General Legal credit footnote" is retained in the corpus copy for provenance. A `NOTICE` file at the bundle root follows `content-vendoring.md` §2: upstream, pinned-commit, last-verified, per-file `upstream-blob-sha` + `local-blob-sha`.

### FR2: Template-fill generation mode

`legal-document-generator` gains a template-fill path: select the vendored template for the doc type, substitute `<mark>` fields from Phase-0 context (mechanical substitution, disclosed as such — not individualized advice), append mandatory DRAFT blockquotes top+bottom and YAML frontmatter per the existing output contract, and pass the Phase-2.5 redaction gate unchanged. Template-fill is the default for all doc types with a vendored match; from-scratch generation remains for uncovered jurisdictions (upstream is US-centric; no UK coverage) and doc types without a template.

### FR3: New contract doc types

`legal-generate` supported-types list grows to include: `master-services-agreement`, `mutual-nda`, `one-way-nda`, `advisor-agreement`, `business-associate-agreement` (gated: requires explicit regulated-industry/HIPAA acknowledgment before generation), `employee-offer-letter` (gated: off-ICP warning — company-of-one users rarely hire employees; suggest advisor/contractor agreement instead). SKILL.md "8 document types" prose, README counts, and agent descriptions updated atomically.

### FR4: Footnote strip in emitted output

Emitted documents never carry the General Legal credit footnote or any `general.legal`/portal links. The corpus copy retains it; the fill step strips it. A grep assertion (`general.legal`, `General Legal`, `portal.general.legal`) covers emitted output — per `hr-third-party-content-grep-on-undertaking`, the diff is grepped for the party's content pre-merge.

### FR5: Legal surface amendments

`disclaimer.md` §2.3 ("not prepared by licensed attorneys") and `terms-and-conditions.md` §7.2 ("AI-generated") are reworded to cover template-derived documents. TC_VERSION bump, canonical↔mirror sync, `legal-doc-shas.ts` re-pin, and CLO attestation at ship Phase 5.5. All five `docs/legal/**` CI gates must pass.

### FR6: Pre-vendor audit pass

Before adoption, run `legal-compliance-auditor` (benchmark mode) against `privacy-policy-gdpr` and `dpa-global` — a US firm's "GDPR" doc is not self-certifying. Findings feed the vendored-vs-adapt decision for those two files (vendor verbatim or drop from the bundle).

## Technical Requirements

### TR1: Multi-NOTICE vendoring machinery

Generalize `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts` (hardcoded `NOTICE_FILE_REL`/`SKILL_PREFIX` at lines 72-77) to enumerate `plugins/soleur/skills/*/NOTICE`. Register the new bundle in: lefthook `vendor-pin-integrity` globs (`lefthook.yml:266-272`), `.github/workflows/vendor-pin-verify.yml` path filters, `compliance-posture.md` §Vendored Code Provenance row, `.markdownlintignore` exclusion (lint rewrites break SHA pins). Suggest `/soleur:architecture` ADR for the multi-bundle registry decision.

### TR2: Jurisdiction mapping

Explicit mapping table in the skill: which template covers which jurisdiction claim; uncovered jurisdictions route to the from-scratch path; a US-template must not silently emit Delaware-governing-law defaults for non-US companies (the dogfood defect class — Phase-0 jurisdiction context gates governing-law fields).

### TR3: Legal staleness ownership

The drift cron proves upstream-blob agreement, not correctness against current law (#7349 "gates measure agreement, not truth"). Schedule periodic `legal-audit benchmark` re-runs against the vendored set (mechanism chosen at plan time — cron or documented manual cadence).

### TR4: Component-count and budget checks

No new skill — templates live under the existing `legal-generate` skill dir (loader does not recurse into `references/`). README component tables unchanged except doc-type prose. Verify `SKILL_DESCRIPTION_WORD_BUDGET` headroom before any `description:` edit.

## Carry-Forward

- Lane: `cross-domain`; triad CPO+CLO+CTO assessed; CMO assessed (external-product-comparison trigger).
- Capability gaps recorded in brainstorm §Capability Gaps, including the pre-existing dangling `knowledge-base/legal/recommended-tools.md` references in shipped components (sibling fix or filed issue at plan time).
