---
title: "Vendor General-Legal CC0 legal templates into legal-generate"
date: 2026-09-13
lane: cross-domain
brand_survival_threshold: single-user incident
status: complete
pr: "#8120"
---

# Brainstorm: Vendor General-Legal CC0 legal templates into legal-generate

## User-Brand Impact

- **Artifact:** the legal-document surface Soleur ships to users — `legal-generate`/`legal-audit` plus vendored third-party template content under `plugins/soleur/skills/legal-generate/references/`.
- **Vector:** a defective or license-contaminated clause silently delivered into a founder's MSA/privacy policy/NDA, or a vendored template carrying a third-party law firm's credit footnote into a user deliverable (implied endorsement).
- **Threshold:** `single-user incident`.

## What We're Building

Vendor all 12 templates from `General-Legal/legal-templates` (CC0-1.0, attorney-drafted, LLM-optimized markdown with `<mark>` customization fields) into `plugins/soleur/skills/legal-generate/references/templates/`, register them as the plugin's second vendored-content bundle under `content-vendoring.md` policy, and switch `legal-generate` from pure from-scratch generation to template-fill: the generator fills `<mark>` fields from Phase-0 company context, wraps output in the existing YAML-frontmatter + dual-DRAFT-blockquote contract, and passes the unchanged Phase-2.5 redaction gate.

Template inventory: Advisor Agreement, Business Associate Agreement (HIPAA), Cookie Notice, DPA (U.S.), DPA (Global/GDPR-aligned), Employee Offer Letter (California exempt), Master Services Agreement, Mutual NDA, One-Way NDA, Privacy Policy (U.S.), Privacy Policy (GDPR-enhanced), Terms of Use.

## Why This Approach

Chosen over three alternatives:

- **Route only (vendor-neutral reference):** rejected — leaves users to fetch/fill templates themselves; doesn't deliver the contract coverage the operator asked for.
- **Fetch-and-fill at runtime (SHA-pinned):** rejected — adds a runtime fetch dependency, unpinned-HEAD drift/injection risk on fetched prose (the fetched text is generator input), and no offline path.
- **Vendor subset:** chosen — strongest provenance story (pinned attorney-drafted baselines, auditable once, reviewable), no runtime dependency, and the vendoring machinery already exists (`content-vendoring.md`: NOTICE schema, blob-SHA pins, lefthook `vendor-pin-integrity`, `vendor-pin-verify.yml`, Inngest drift cron).

Controlling precedent: `2026-05-15-claude-for-legal-evaluation-brainstorm.md` converged on no-integration for `anthropics/claude-for-legal`. This case differs materially: CC0 (no Apache-2.0 NOTICE-generation burden), static templates (not attorney-assuming skills), and the operator is the demand signal. The #3786 re-eval criteria remain unfired — recorded here so this decision doesn't silently moot that deferral.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Copy vs reference | **Vendor** all 12 into `legal-generate/references/templates/` | Operator directive; machinery exists; offline + pinned beats runtime fetch |
| Subset | **All 12** | Operator choice. BAA gated behind regulated-industry acknowledgment; offer letter gated as off-ICP (company-of-one) — both gated in skill prose, not excluded |
| Overlapping types (~5) | **Template-fill replaces from-scratch generation** | Vendored template is the base; agent fills `<mark>` fields + wraps disclaimers/frontmatter. Jurisdiction guard required: upstream is US-centric — no UK coverage; uncovered jurisdictions keep the existing from-scratch path |
| Credit footnote | **Retain in corpus, strip in emitted output** | CC0 makes it optional; keeping it in stored templates preserves provenance; propagating it into user deliverables is a third-party ad surface + implied-endorsement risk (CMO) |
| Legal surface amendments | **Required** | Disclaimer §2.3 says generated docs are "not prepared by licensed attorneys" — literally false once vendored; T&C §7.2 scoped to "AI-generated" only. Both must be amended → TC_VERSION bump + CLO attestation + all five `docs/legal/**` CI gates |
| Drift machinery | **Generalize to multi-NOTICE** | `cron-content-vendor-drift.ts` is hardcoded to gdpr-gate (`NOTICE_FILE_REL`, `SKILL_PREFIX` constants); second bundle requires enumerating `skills/*/NOTICE`. Register lefthook globs + `vendor-pin-verify.yml` path filters + `compliance-posture.md` §Vendored Code Provenance row + `.markdownlintignore` exclusion |
| Placement | `plugins/soleur/skills/legal-generate/references/templates/` | Ships to every install (marketplace `git-subdir` source is `plugins/soleur`), zero component-count delta, zero per-turn tokens. NOT `docs/legal/` or `plugins/soleur/docs/pages/legal/` (mirror/SHA gates red immediately; republication-under-our-name, #7331 class). NOT repo-root `knowledge-base/` (doesn't ship) |
| `.docx` originals | **Exclude** | Binary dead weight; regenerable via upstream `scripts/` |
| Marketing claims | **No "attorney-drafted" claims in output** | Conflicts with published Disclaimer §2.3 even after amendment; upstream "attorney-drafted" is vendor-reported — requires attribution per brand guide and decays on downstream edit |
| Legal staleness | **Scheduled `legal-audit benchmark` re-runs** | Drift cron proves blob agreement, not correctness against current law — "gates measure agreement, not truth" (#7349). First lift includes a `legal-compliance-auditor` pass on the GDPR/DPA-Global templates before adoption |

## Open Questions

1. UK jurisdiction: upstream has no UK coverage — refuse/route, or keep generator-only fallback for uncovered jurisdictions? (Lean: keep fallback; the from-scratch path already advertises UK.)
2. Demand instrumentation: does the vendored launch re-arm the #3786 deferral (a shipped contract-doc surface partially serves the demand claude-for-legal would)? Comment on #3786 at ship time.
3. ADR needed: multi-bundle vendored-content registry generalization — suggest `/soleur:architecture create 'Multi-bundle vendored-content registry'` during plan.
4. Second-vendor pairing is NOT needed for this path (vendor-neutrality test governs `recommended-tools.md`, not vendored corpora) — but if we also add a `recommended-tools.md` "contract templates" row for the fetch-them-yourself case, it needs ≥2 vendors (Common Paper, NVCA model docs, Cooley GO, Orrick).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Legal (CLO)

**Summary:** CC0 is the cleanest possible license — no attribution/notice conditions; footnote is a non-binding request (retain-in-corpus/strip-in-output). Vendoring modestly IMPROVES liability posture if framed as "generic starting point, still requires counsel" — but expands reliance class: the net-new types are bilateral executed contracts, categorically higher-stakes than published policies. Blocking items if copy is chosen: Disclaimer §2.3 + T&C §7.2 amendments (both currently scoped to "AI-generated" only), vendoring-machinery generalization, jurisdiction mapping (no UK), BAA regulated-industry gate, and a pre-vendor `legal-compliance-auditor` pass.

### Product (CPO)

**Summary:** The library's doc-type mix (contracts) vs ours (published-compliance docs) is the real story — the feature is "contract-type coverage," not "template import." Watch imported framings: inbound-MSA review (the common founder case) is already covered by `recommended-tools.md#vendor-msa-review`; offer letter contradicts the company-of-one ICP; US-jurisdiction defaults re-import the Delaware-governing-law defect class fixed in dogfooding. Templates-as-generator-substrate is the stronger framing than templates-as-user-artifact.

### Engineering (CTO)

**Summary:** `plugins/soleur/skills/legal-generate/references/templates/` is the right home — ships via `git-subdir`, zero per-turn tokens, mirrors the gdpr-gate `references/` precedent. Costs: multi-bundle generalization of lefthook/CI/cron, output-contract wrap step (`<mark>` fill + frontmatter + disclaimers), precedence rule for overlapping types (resolved: fill replaces generate), no `.docx`. No blocking capability gaps — machinery exists, single-bundle hardcoding is the work.

### Marketing (CMO)

**Summary:** Footnote = uncompensated third-party ad unit inside user deliverables — strip in output. General Legal is a YC26 firm whose "agent-operated company" wedge is Soleur's own category thesis — no privileged placement without written justification. No "attorney-drafted" marketing claims. Vendor-neutrality test applies to `recommended-tools.md` rows, not the vendored corpus.

## Capability Gaps

- **Multi-bundle vendored registry** — `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts:72-77` hardcodes `NOTICE_FILE_REL`/`SKILL_PREFIX` to gdpr-gate; lefthook `vendor-pin-integrity` globs (`lefthook.yml:266-272`) and `vendor-pin-verify.yml` path filters are literal gdpr-gate paths. Evidence: grep of constants; repo-research confirmed single registry row in `content-vendoring.md` §10.
- **Template-fill step in `legal-document-generator`** — agent generates from scratch only; no `<mark>`-fill/wrap path exists. Evidence: `legal-document-generator.md` (51 lines, no template handling).
- **Staleness banner for non-gdpr-gate bundles** — runtime 30d/90d banner lives inside `gdpr-gate.sh`. Evidence: repo-research §5.
- **Dangling `knowledge-base/legal/recommended-tools.md` references in shipped components** (pre-existing, unrelated to this feature but surfaced): `legal-audit/SKILL.md`, `clo.md`, `commands/go.md`, `eval-harness/prompts/go-skill.txt` all point at a repo-root KB path absent from the plugin payload. Worth a sibling fix or filed issue. Evidence: repo-research §4 divergence flag.
