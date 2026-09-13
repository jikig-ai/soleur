---
title: "feat: Vendor General-Legal CC0 legal templates into legal-generate"
type: feat
date: 2026-09-13
slug: feat-legal-templates-cc0-eval
branch: feat-legal-templates-cc0-eval
issue: 8122
closes: 8122
priority: p2-medium
domain: legal
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# feat: Vendor General-Legal CC0 legal templates into legal-generate

## Overview

Vendor the 12 attorney-drafted, CC0-1.0 templates from `github.com/General-Legal/legal-templates`
(pinned at `0f7c7bfabf1be77a2bf52eef80815e24c93a190a`) into
`plugins/soleur/skills/legal-generate/references/templates/` as a NOTICE-registered bundle, switch
overlapping document types to template-fill against the vendored `<mark>`-field substrates, keep the
from-scratch generator for uncovered types and the UK jurisdiction, strip the vendor's embedded
credit footnote from emitted output while retaining it in the corpus, and amend the two published
legal documents whose current wording would otherwise be falsified by shipping attorney-drafted
substrate. The vendoring machinery is generalized from its single hard-coded gdpr-gate bundle to a
registry-driven multi-bundle model.

## Problem Statement

`legal-generate` produces eight policy-type documents from scratch. It has no contract coverage
(MSA, NDA, advisor agreement, offer letter, BAA) and its generated prose carries no
attorney-drafted baseline. The upstream corpus is CC0 (no attribution obligation), LLM-optimized
markdown with `<mark>[FIELD]</mark>` fill slots, and attorney-drafted. Three cross-cutting
constraints bind the shape of the import:

1. Every upstream `template.md` ends with a `---` + "prepared by General Legal, PC" credit
   paragraph and links to `general.legal` — a third-party ad surface inside the deliverable.
2. `docs/legal/disclaimer.md` §2.3 affirmatively states generated documents are "**not** prepared
   by licensed attorneys" — shipping attorney-drafted substrate falsifies a published legal
   claim unless the disclaimer is amended (T&C §7.2, TC_VERSION bump, CLO attestation, five CI
   gates).
3. The vendoring enforcement stack (drift cron, lefthook pin-integrity, PR-time upstream verify)
   is hard-coded to the gdpr-gate bundle and must be generalized before a second bundle can land
   enrolled rather than unhooked.

## Research Insights

**Relevant file paths (verified this session):**

- `plugins/soleur/skills/legal-generate/SKILL.md` — 8-type menu (lines 12–19), Phase 2 invokes
  `legal-document-generator`, Phase 2.5 redaction gate is the emit chokepoint.
- `plugins/soleur/agents/legal/legal-document-generator.md` — thin prompt agent; disclaimer
  placement, YAML frontmatter, cross-reference hints. Template-fill slots in as a substrate
  protocol section.
- `knowledge-base/engineering/policies/content-vendoring.md` — NOTICE schema (§2), lifting
  procedure (§3), four drift layers (§4), registry (§10). §6 notes the pre-vendor diff scan for
  first-time lifts is DEFERRED — contamination inventory is manual this cycle.
- `plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh:75` — parser is already
  bundle-agnostic (`NOTICE_FILE` env override); reusable for legal-generate with no copy.
- `plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh:52` — `SKILL_PREFIX`
  constant is hard-coded to gdpr-gate; `NOTICE_FILE` override already exists (line 33).
- `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts:72–77` —
  `NOTICE_FILE_REL`, `PARSER_REL`, `CLASSIFIER_REL`, `SKILL_PREFIX` all hard-coded to gdpr-gate;
  the real generalization cost lives here (per-bundle detect/attest/heartbeat).
- `lefthook.yml:266–272` — `vendor-pin-integrity` glob covers only `gdpr-gate/**`.
- `.github/workflows/vendor-pin-verify.yml:13–18` — `paths:` covers only gdpr-gate.
- `docs/legal/disclaimer.md:68` — the "not prepared by licensed attorneys" bullet; mirror at
  `plugins/soleur/docs/pages/legal/disclaimer.md`.
- `docs/legal/terms-and-conditions.md` §7.2 (line 228) + mirror.
- `apps/web-platform/lib/legal/tc-version.ts` — `TC_VERSION` `2.5.0`, `TC_DOCUMENT_SHA`
  hand-edited literal; bump rubric at `knowledge-base/legal/tc-version-bump-policy.md`.
- `apps/web-platform/lib/legal/legal-doc-shas.ts` — per-document SHA pins re-pinned by
  `check-tc-document-sha.sh` after any canonical edit.
- `knowledge-base/legal/compliance-posture.md` §Vendored Code Provenance — one row per bundle.
- `plugins/soleur/test/legal-recommended-tools.test.ts` — vendor-neutrality gate on
  `recommended-tools.md` (≥2 vendors per section, no endorsement framing).

**Upstream (verified live 2026-09-13):** `General-Legal/legal-templates`, CC0-1.0, not archived,
HEAD `0f7c7bfabf1be77a2bf52eef80815e24c93a190a`. 12 `templates/<name>/template.md` files; each
ends `---` + the General Legal credit paragraph (deterministic strip boundary). `<mark>` fields
confirmed (`<mark>[Company</mark>]` etc.). `docx-originals/`, template `README.md`s, and upstream
`scripts/` are NOT vendored.

**Institutional learnings applied:**

- `2026-09-13-cc0-legal-template-vendoring-eval.md` — CC0 removes license friction, not
  correctness/liability/endorsement risk; credit footnote is a vendor-marketing surface;
  check sibling deferral criteria before re-deriving an import decision.
- `2026-05-15-claude-for-legal-evaluation-brainstorm.md` + issue #3786 — prior third-party
  legal integration was deferred with ALL-must-hold re-evaluation criteria. This plan is a
  *different mechanism* (CC0 content vendoring, not a plugin integration), but it partially
  serves the same deferred demand (contract coverage); the relationship is recorded in #3786 at
  ship time, and #3786's criteria are NOT rewritten by this plan.
- `2026-05-09-evaluating-vendor-branded-claude-code-skills.md` — contamination inventory before
  lift; inspiration/reference/lift/fork matrix.
- `2026-02-25-stripe-atlas-legal-benchmark-mismatch.md` — brand association ≠ document-type fit.
- `#7710`-era NOTICE lessons baked into content-vendoring.md §6a — `last-verified` freshness
  attestation conditions the cron must keep honoring per bundle.

**Functional-overlap scan (community registries):** no installable artifact vendors an
attorney-drafted CC0 substrate. Closest: `general-legal-assistant` (MIT, prompt-encoded
templates benchmarked on CommonPaper), `anthropics/claude-for-legal` (Apache-2.0, review-focused,
no substrates — the same sibling deferred via #3786). Peer template libraries for the
vendor-neutral reference section: CommonPaper (CC BY 4.0), Bonterms (CC BY 4.0),
Open-Agreements (MIT). General-Legal's CC0 + `<mark>` markdown is the best vendoring substrate.

**Skill-description budget baseline:** `SKILL_DESCRIPTION_WORD_BUDGET = 2442`, measured
**2442/2442 — zero headroom**. The `legal-generate` `description:` rewrite MUST be word-neutral
or ship sibling trims in `## Files to Edit` (the constant is bumped only via attestation-class
changes; do not prescribe a bump for a cosmetic mention).

**Premise Validation (Phase 0.6):** all cited artifacts verified on this branch — #8122 open,
#3786 open-deferred with unfired criteria, PR #8120 draft, `content-vendoring.md` / cron /
lefthook globs / `vendor-pin-verify.yml` / gdpr-gate NOTICE all present as spec describes.
Nothing stale.

**Property List (Phase 0.6b):** (1) attorney-drafted clause baseline + contract-type coverage —
no existing mechanism; (2) provenance/license compliance for the corpus — covered by NOTICE
machinery, reused per-bundle; (3) drift detection for a second bundle — needs parameterization of
the existing stack, not a new mechanism; (4) vendor-surface exclusion from emitted docs —
uncovered; (5) disclaimer/text-vs-feature consistency — covered by existing legal CI gates,
amendment required.

**Cut List:** none — every proposed mechanism buys a property nothing on `main` covers.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Disclaimer §2.3 carries the attorney claim | Confirmed — `docs/legal/disclaimer.md:66–72`, section IS §2.3 | Amend canonical + mirror atomically |
| Cron is hard-coded to one bundle | Confirmed — `cron-content-vendor-drift.ts:72–77` | Registry-driven per-bundle loop (Phase 2) |
| Vendor machinery is a single hard-coded bundle | Partially — parser already takes `NOTICE_FILE` env; only `SKILL_PREFIX` (integrity script) + cron constants + two glob lists are hard-coded | Smaller generalization than spec implies: env-parameterize the integrity script, keep scripts gdpr-gate-owned per the ADR-095 shared-engine precedent, do NOT relocate them |
| 12 templates to vendor | Confirmed — 12 `template.md` files at pinned HEAD | NOTICE declares exactly 12 `lifted-files` |

## Proposed Solution

A NOTICE-registered `references/templates/` bundle under `legal-generate`, a deterministic
credit-strip script the generator pipes substrate through before field-fill, a gated doc-type
expansion for six new contract types, and a registry-driven generalization of the existing
three-layer vendoring enforcement. Two published legal documents are amended so their claims stay
true of the shipped feature.

## Technical Approach

### Architecture

- **Corpus retains, output strips.** Vendored `template.md` files carry the line-1 attribution
  header and keep the General Legal credit paragraph verbatim (`status: active-verbatim` — clean
  upstream diffs and provenance). `scripts/strip-vendor-credit.sh` removes BOTH the line-1
  `<!-- Adapted … -->` header AND the trailing credit block on the emit path — the header names
  `General-Legal` (hyphenated, which a `general\.?legal` grep cannot see) and points at a NOTICE
  that does not exist in the user's document; provenance lives in the NOTICE, nothing is lost by
  stripping it. The script anchors on the credit-paragraph marker text, not a bare `---`
  delimiter (horizontal rules appear legitimately). Emit-side guard asserts the assembled
  document contains zero matches for case-insensitive `general[-.[:space:]]?legal` (covers all
  three written forms) AND zero `attorney[- ]draft|prepared by|reviewed by` claim-leakage AND
  zero residual `<mark`/`[FIELD]`-style unfilled-slot remnants.
- **Doc-type map.** `terms-of-use`→terms-and-conditions, `privacy-policy-us`→privacy-policy (US),
  `privacy-policy-gdpr`→gdpr-policy + privacy-policy (EU), `cookie-notice`→cookie-policy,
  `dpa-us`/`dpa-global`→data-processing-agreement (US / EU-global), plus six NEW types:
  mutual-nda, one-way-nda, master-services-agreement, advisor-agreement (default menu) and
  employee-offer-letter, business-associate-agreement (**request-only, gated**: not listed in the
  default AskUserQuestion menu; BAA requires an affirmative "you process PHI / operate in a
  HIPAA-regulated context" confirmation; offer letter requires explicit request and is labeled
  off-ICP). UK jurisdiction and the three types with no substrate (AUP, data-protection-disclosure,
  disclaimer) keep the from-scratch generator path.
- **Scripts stay gdpr-gate-owned** (ADR-095 shared-engine precedent — same pattern as
  `incident/scripts/redact-sentinel.sh`). `vendor-pin-integrity.sh` gains a `SKILL_PREFIX` env
  override alongside the existing `NOTICE_FILE` override. `notice-frontmatter.sh` needs no change.
- **Cron generalization.** `cron-content-vendor-drift.ts` is **1,489 lines**, not a small
  constants patch — the four exported constants (`NOTICE_FILE_REL`, `PARSER_REL`,
  `CLASSIFIER_REL`, `SKILL_PREFIX` at :72–77) are the easy part. The real work is a
  **per-bundle identifier manifest**: every cross-bundle surface must key on a bundle slug,
  or the legal-generate arm silently suppresses/corrupts the gdpr-gate arm:
  1. **Enrollment is schema-keyed, not filename-keyed.** `plugins/soleur/skills/incident/NOTICE`
     already exists — a 39-line prose MIT attribution with NO frontmatter (verified). The bare
     glob `skills/*/NOTICE` matches it today → `extract_frontmatter` returns nothing → the cron
     throws `Failed to parse NOTICE` every week, forever. A bundle is a `*/NOTICE` whose
     frontmatter parses AND declares `upstream` + `pinned-commit` (+ `registry` pointer); a
     non-conforming NOTICE is skip-with-warn. The cron, Guard 2's derived population, the
     `vendor-pin-verify.yml` loop, and the discoverability command share this one predicate.
  2. **`step.run` IDs are the sharpest hazard** — Inngest memoizes step results by ID, so a
     naive loop reusing `detect-drift`/`attest-freshness` returns bundle A's memoized result
     for bundle B. Per-bundle step IDs (`<id>-<bundleSlug>`) for every per-bundle step;
     run-level steps (`run-started-at`, `mint-installation-token`, `setup-workspace`,
     `ensure-labels`) stay unsuffixed — one clone, one token, shared label set.
  3. **Branch names** — `deriveBranchName(cronName, runStartedAt)` produces
     `ci/content-vendor-drift-<ts>` for BOTH bundles → colliding/mixed PR. Pass a per-bundle
     `cronName` (e.g. `cron-content-vendor-drift-<slug>`) into `safeCommitAndPr` — branch
     naming, ledger rows, and Sentry tags then key per-bundle for free; `ATTEST_BRANCH_PREFIX`
     likewise (`ci/vendor-attest-<bundle>`). Dedup transition: legacy un-suffixed open
     branches/issues (`ci/content-vendor-drift-<ts>`) can only be gdpr-gate's — the shared
     prefix query stays, results classify by suffix, so a stuck pre-refactor PR is neither
     duplicated nor suppressing.
  4. **Dedup queries** — `head:ci/content-vendor-drift-` (:955), `head:ci/vendor-attest-`
     (:1238), and the issue-title dedup (:1047) are bundle-agnostic; scope per bundle (with
     the legacy-suffix rule above) or a bundle-A open PR suppresses bundle-B forever (the
     `skipped-open-pr`-behind-green shape #7710 documented). Re-keyed test anchors must pin
     slug-bearing literals, not shared prefixes (cq-assert-anchor-not-bare-token).
  5. **Spawned-script env** (:560–565) passes only PATH/NODE_ENV/HOME/GH_TOKEN — no
     `NOTICE_FILE` — correct today only because the parser default coincides with gdpr-gate.
     The loop sets `NOTICE_FILE` per bundle (absolute `join(repoRoot, noticeFileRel)` — the
     parser resolves it bare, repo-relative works only because `cwd: repoRoot`) or bundle B's
     `last-verified` is attested onto bundle A's registry — a falsified attestation no pure
     predicate can detect.
  6. **`gosprinto/compliance-skills` literals** in commit/PR text (:1008, :1265) and the
     `ref: "main"` upstream-fetch literal (:699) → per-bundle upstream name + `upstreamRef`
     (default branch) from the descriptor/NOTICE; assert `default_branch` in Phase 0.
  7. **Per-arm worktree reset** — `safeCommitAndPr` does `checkout -B <branch>` from current
     HEAD (`_cron-safe-commit.ts:622`) on the run's single clone. Without a reset to
     `origin/main` between arms, bundle B's attestation PR can carry bundle A's unmerged
     re-vendor commit — unreviewed vendored bytes merging through the attestation channel.
     Add `baseRef` support or reset the clone (`checkout -f origin/main` + scoped clean)
     before each bundle's write step.
  8. **Failure isolation is a mechanism, not a property** — a throwing `step.run` fails the
     handler (`retries: 1` → top-level catch :1430) and the sibling arm never runs. Each
     per-bundle arm converts throws into typed failure results (`couldNotMeasure`-style
     totals) inside a per-bundle try boundary; `mayAttestFreshness`/`heartbeatOk` consume a
     bundle that produced no totals as failed, not absent.
  9. **`allowedPaths`/`readFile(NOTICE_FILE_REL)` call sites** (:399 sentinel iterates every
     discovered bundle, :1138, :1154) → per-bundle paths; discovery runs INSIDE a `step.run`
     against the clone (`repoRoot`), never module-level (ADR-033 I1).
  10. **Heartbeat stays function-level** — one Sentry monitor per function; per-bundle slug
      threads into `reportSilentFallback` message/op/extra and the `attestation-summary`
      warn fields so a red bundle is identifiable; run health is AND-aggregated (any bundle
      failed → run failed) with per-bundle breakdown in the handler result.
  Per-bundle failures must not mask each other (a bundle that cannot be measured fails its
  own arm, never the sibling's).
- **Regression net is part of the refactor, not an afterthought.**
  `apps/web-platform/test/server/inngest/cron-content-vendor-drift.test.ts` (736 lines) pins
  ~25 source-shape anchors that all red under the refactor: constants-equality tests
  (:163–181), `mayAttestFreshness(detectResult)` signature (:514), `step.run("attest-freshness")`
  slices (:527, :626, :634, :669), `ATTEST_BRANCH_PREFIX` (:618), `allowedPaths` literal
  (:130), `heartbeatOk(measurementFailed, …)` (:556). Each anchor is re-keyed to the bundle
  descriptor or preserved deliberately — declared per-anchor in the PR, never rewritten ad
  hoc. NEW test required: **cross-bundle masking** — an open `ci/content-vendor-drift-gdpr-gate-*`
  PR must not suppress a legal-generate re-vendor/issue, and vice versa (no existing test
  shape can express this today).
- **Legal amendment — disclaimer only.** Disclaimer §2.3 "not prepared by licensed attorneys"
  is rewritten to distinguish substrate provenance from review status (generated documents
  remain drafts requiring review; the *claim being removed* is the absolute provenance
  denial; the *claim retained* is "not reviewed or endorsed by any attorney"). Canonical +
  mirror edited atomically; `legal-doc-shas.ts` re-pinned via `sha256sum`; Last-Updated +
  posture Disclaimer cell updated. **T&C §7.2 is NOT amended** (operator adjudication —
  verified anodyne; a parity-only sentence is not worth a forced all-user re-acceptance);
  queued via follow-up issue for the next natural bump.

### Implementation Phases

#### Phase 0 — Preconditions and upstream pin

- Confirm upstream HEAD is still `0f7c7bfabf1be77a2bf52eef80815e24c93a190a` and repo is
  unarchived (`gh api repos/General-Legal/legal-templates`).
- Contamination inventory: grep all 12 templates for `general.legal`, `General Legal`, `@`,
  URLs, and any non-credit vendor surface; record findings in the PR body. (Policy §6's
  pre-vendor diff scan is deferred upstream — this manual inventory is the cycle's substitute.)

#### Phase 1 — Vendor the corpus (lands with Phase 2 in one PR; ordering is commit-level only)

- Create `plugins/soleur/skills/legal-generate/references/templates/<name>/template.md` ×12 with
  line-1 `<!-- Adapted from General-Legal/legal-templates (CC0-1.0) — see NOTICE -->`.
- **`.markdownlintignore`**: exclude `plugins/soleur/skills/legal-generate/references/` (same
  pattern as the gdpr-gate exclusion at :45) — vendored markdown must not be lint-rewritten or
  the `local-blob-sha` pins desync silently. Without this the vendoring commit cannot pass
  lefthook `markdown-lint` or CI.
- Write `plugins/soleur/skills/legal-generate/NOTICE` (schema per policy §2; `pinned-commit`
  `0f7c7bf…`; 12 `lifted-files` entries with dual blob SHAs via `git hash-object --no-filters`;
  `status: active-verbatim` for all 12 — the line-1 attribution header is the policy's standard
  provenance header, the same shape gdpr-gate's `active-verbatim` entries carry; human table in
  body matching frontmatter). Declare `soleur-authored:` explicitly — empty list today;
  `strip-vendor-credit.sh` lives under `scripts/` (outside the `references/**/*.md` registry
  walk) so it needs no entry. Any future `.md` added under `references/` MUST be registered in
  exactly one of the two registries (TS6 symmetric-difference walk enforces).
- Add `compliance-posture.md` §Vendored Code Provenance row + `content-vendoring.md` §10
  registry row.
- The NOTICE pins SHAs whose *enforcement* is Phase-2 machinery; because both phases land in
  this one PR, no unenrolled vendored content ever reaches `main`.

#### Phase 2 — Generalize the enforcement stack

- `vendor-pin-integrity.sh`: `SKILL_PREFIX="${SKILL_PREFIX:-plugins/soleur/skills/gdpr-gate}"`;
  parser path stays script-dir-relative. (File is 179 lines; the `--verify-upstream` arm does
  not read `SKILL_PREFIX`, only `NOTICE_FILE` + the upstream coordinate in the NOTICE itself.)
- `lefthook.yml`: second stanza globbing `plugins/soleur/skills/legal-generate/{NOTICE,references/**}`
  — `references/**`, NOT `references/templates/**` — a future `references/foo.md` outside
  `templates/` must not slip the gate (the existing stanza's own narrow-glob doctrine,
  lefthook.yml:239–243) → same script with env overrides.
- `vendor-pin-verify.yml`: add legal-generate NOTICE + `references/**` to `paths:`; run the
  script once per NOTICE (`NOTICE_FILE`/`SKILL_PREFIX` per bundle).
- `cron-content-vendor-drift.ts` (1,489 lines): bundle discovery over
  `plugins/soleur/skills/*/NOTICE`; the constants block becomes a typed `BundleDescriptor[]`
  (slug, `noticeFileRel`, `skillPrefix`, parser/classifier rel paths stay shared); the
  per-bundle identifier manifest in §Architecture is the contract — per-bundle step IDs,
  branch prefixes, dedup scopes, spawned-env `NOTICE_FILE`, commit/PR text, allowedPaths, and
  AND-aggregated heartbeat with per-bundle breakdown.
- `apps/web-platform/test/server/inngest/cron-content-vendor-drift.test.ts` (736 lines):
  re-key the ~25 pinned anchors to the descriptor (constants-equality → descriptor-shape
  assertions; `step.run` ID slices → per-bundle IDs; `ATTEST_BRANCH_PREFIX` → per-bundle
  prefix; `allowedPaths` literal → per-bundle; `mayAttestFreshness`/`heartbeatOk` signatures
  preserved or re-keyed per-anchor). Add the cross-bundle masking test (Architecture bullet).
- NOTICE frontmatter↔table parity: `notice-frontmatter.test.sh`/`_base-notice-frontmatter.test.sh`
  are gdpr-gate-pinned — parameterize (or add a second invocation) so the legal-generate NOTICE
  gets the same parity guard; the parity defect class is exactly what #7710 was about.
- Extend `vendor-pin-integrity.test.sh` / `vendor-drift-workflow.test.sh` for the two-bundle case.
- New `plugins/soleur/test/vendor-bundle-coverage.test.sh` — Guard 2 below.

#### Phase 3 — Emit path

- `scripts/strip-vendor-credit.sh` (legal-generate-owned): removes the trailing `---` + credit
  block; fails loudly (exit 2) when invoked on input lacking the expected credit marker — a
  substrate missing its credit is a provenance anomaly, not a clean strip. The strip applies
  ONLY to the substrate path; generator-fallback documents bypass it entirely (Guard 1
  mutation 4 — a non-substrate input is not routed through the strip at all).
- **`<mark>` field-collection contract** (in `legal-document-generator.md`; prompt-level, per
  CTO assessment — no fill shell scripts):
  1. After substrate selection, enumerate all `<mark>[NAME]</mark>` slots in the template via
     grep (mechanical, not from memory).
  2. Slots satisfiable from Phase-0 context (company name, jurisdiction, contact) fill
     silently; each remaining slot is asked via AskUserQuestion, batched ≤4 related fields per
     question.
  3. **Fail closed on decline**: if the user declines or blanks a required slot, do NOT emit —
     state which fields are missing and stop. The only escape is the user's explicit choice to
     switch to the from-scratch arm (still a draft, still review-gated). Never emit a document
     containing an unfilled `<mark>` placeholder or a bracketed `[FIELD]` remnant. A declined
     *optional* slot removes its containing clause/sentence rather than blocking emission. A
     "supply all known values in one message" escape hatch is offered up front to cut the
     question rounds (an MSA carries ~10–30 slots — expect 3–8 rounds otherwise; that is the
     designed UX, deterministic clause coverage is what it buys).
  4. Emit-side guard: before presenting, grep the assembled document for `<mark`/`</mark>` and
     generic `[FIELD]`-style remnants — any residual fails emission (added to the widened
     vendor-mark + claim-leakage grep in §Architecture).
- **Menu mechanics**: the numbered text list shows only non-gated types (gated types are named
  in a "request-only" prose note, never as selectable numbers/options). The AskUserQuestion
  offers the four most common (privacy policy, terms, NDA, DPA) relying on the built-in
  "Other" free-text escape for the rest. "NDA" triggers a mutual-vs-one-way follow-up (default
  mutual, one-way named as the alternative). All corpus/script/NOTICE paths resolve via
  `${CLAUDE_PLUGIN_ROOT}` — repo-relative paths work only inside this repo's dogfood tree and
  fail (or resolve a hostile planted file) at real installs (ADR-179 bare anchor, ADR-093).
- **Gate semantics**: BAA — blocking AskUserQuestion confirm ("do you process PHI / operate in
  a HIPAA-regulated context?"); on "no", decline to produce a BAA and stop. Offer letter —
  blocking confirm of the CA-exempt scope limitation; on decline, suggest the
  advisor-agreement as the alternative and offer the from-scratch arm. Neither is
  warn-and-proceed.
- **Jurisdiction scope of contract substrates**: the six contract templates are US-drafted;
  the governing-law `<mark>` swaps a state name while every other clause stays US-shaped.
  Non-US contract requests therefore route to the from-scratch arm — filling a governing-law
  slot does not make a US contract a German one (TR2's dogfood defect class).
- `legal-document-generator.md`: substrate-selection protocol (doc type + jurisdiction →
  template path), the field-collection contract above, mandatory strip step, no
  "attorney-drafted" / endorsement claims, UK/fallback routing.
- `legal-generate/SKILL.md`: doc-type list + new types (gated types request-only), staleness
  banner pre-step (`NOTICE_FILE=… notice-frontmatter.sh days-stale`, same 30/90 thresholds),
  template-fill Phase-2 arm, word-neutral `description:` (zero-headroom budget).
- `plugins/soleur/test/legal-template-vendor-surface.test.ts` — Guard 1 below.

#### Phase 4 — Legal-document amendments + attestations

- **Disclaimer §2.3** (canonical + mirror): remove the absolute "not prepared by licensed
  attorneys" claim — falsified once attorney-drafted substrates ship. Wording constraint (CMO
  review): convey provenance WITHOUT the licensure term — e.g. "may incorporate text derived
  from third-party template libraries" — and RETAIN a review-status denial ("generated
  documents are not reviewed or endorsed by any attorney"), which stays true and preserves the
  protective strength the absolute denial provided. Operative claims intact: drafts only, not
  legal advice, professional review required, reliance at user's own risk. The disclaimer's
  `**Last Updated:**` line (:14, carries a change-summary parenthetical by convention) and the
  `compliance-posture.md` Disclaimer cell (:76 — unguarded, goes stale silently) update in
  lockstep. Disclaimer is a non-T&C notice doc: `legal-doc-shas.ts` re-pin (`sha256sum`, NOT
  `git hash-object` — the legal-doc SHA literals are 64-hex sha256; the blob-hash recipe is for
  NOTICE pins only) + mirror sync; no `TC_VERSION` machinery involved.
- **T&C §7.2 — CUT at the apply-gate (operator adjudication).** §7.2 today is anodyne — it
  makes NO provenance claim and stays literally true (verified :228–230). Six of eight plan
  reviewers converged that a parity-only sentence does not justify the codebase's most
  expensive user-facing mechanism (any `TC_VERSION` bump forces every user to re-accept and
  kills live WebSocket sessions — `tc-version-bump-policy.md:24–27`). Decision: **ship
  disclaimer-only; the §7.2 provenance sentence rides the next natural Tier-1/2 T&C change**
  via a filed follow-up issue. No `tc-version.ts`, seed-script, `TC_DOCUMENT_SHA`, or
  posture-T&C-cell edits. This reverses the brainstorm-CLO carry-forward — that mandate
  predated the verification that §7.2 is anodyne; CLO sign-off on the *disclaimer* amendment
  still applies (non-T&C legal doc, advisory-tier per policy §239).
- `legal-compliance-auditor` pass over the vendored corpus; report committed under
  `knowledge-base/legal/audits/` (the `clo` agent's audit path convention, clo.md:68 — AC15
  uses the same path; `vendor-reviews/` does not exist).
  **Spec reconciliation — FR6 audit timing:** the spec asked for a *pre-adoption* audit with
  a "vendor verbatim or drop" decision. The plan audits post-vendor but **pre-merge** — the
  auditor retains the drop decision (a failed template is removed from the PR, its
  lifted-files entry deleted, AC15 blocks ship). The deviation is ordering only, recorded
  here because spec→plan drift must be explicit.
  **Spec reconciliation — TR3 cadence:** the spec requires a periodic correctness re-audit
  (drift-agreement proves blob equality, not currency against current law — the #7349
  "agreement ≠ truth" class). Mechanism chosen at plan time: **documented manual cadence** —
  a `compliance-posture.md` row recording "re-audit the General-Legal corpus on every upstream
  re-vendor and quarterly otherwise" + a filed follow-up issue tracking the first quarterly
  run. No new cron (a benchmark run needs legal-domain judgment, not machinery).
- `recommended-tools.md`: new `## template-libraries` section (literal kebab heading — the
  anchor-lock test pins it) with a ≥2-row vendor table listing CommonPaper (CC BY 4.0),
  Bonterms (CC BY 4.0), General-Legal (CC0) — **peers-first/alphabetical ordering, not
  vendored-vendor-first** — plus a neutral transparency sentence ("Soleur vendors a CC0
  snapshot of one listed library"). `plugins/soleur/test/legal-recommended-tools.test.ts`
  `EXPECTED_THRESHOLDS` 5→6 with a comment (frozen-catalog sentinel is deliberate).
- `content-vendoring.md`: standing "emit-strip doctrine" section — vendored content may carry
  upstream promotional surfaces; corpus retains them for provenance/diff-fidelity; emit paths
  strip deterministically and fail loud on unexpected shape; **the doctrine applies only to
  no-attribution licenses** (a CC-BY bundle would require attribution — scoped in ADR-218 and
  the descriptor via `license`/`strip-permitted`).
- Follow-up issues: "UK legal-template coverage" (generator fallback; re-evaluate on demand);
  "periodic legal-currency re-audit" (TR3 mechanism above); "split cron-content-vendor-drift
  detect/attest/report into discrete steps" (monolith bookkeeping); "demand-signal
  instrumentation for new contract types" (feeds #3786's re-evaluation); "dangling
  `knowledge-base/legal/recommended-tools.md` references at plugin install sites" (spec
  carry-forward — clo.md:33–37, legal-audit/SKILL.md, go.md, work SKILL.md resolve only in
  this repo). Record this PR against #3786 (criteria NOT rewritten).

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Reference-first (recommend GL by URL only) | Lowest risk but delivers no contract coverage and no quality uplift to generated docs; every leader's "safe" option still leaves the user's 2 a.m. MSA problem unsolved. Retained as fallback if vendoring is blocked at review. |
| Fetch templates at runtime (unpinned) | Drift/injection surface with no NOTICE/pin enforcement; rejected by the same reasoning as vendor-pin-verify §4.4. |
| Strip credit at vendor time | Loses provenance fidelity and makes every re-vendor merge conflict on the credit block; corpus retains + deterministic emit-strip is cleaner. |
| Vendor `.docx` + READMEs + upstream scripts | Binary blobs defeat blob-SHA review; READMEs/scripts add surface without fill value; excluded. |
| Vendor subset only (5 overlapping types) | The new contract types are the actual value; subset solves the overlap Soleur already covers. |
| Cron: N scheduled functions or `step.invoke` fan-out instead of one in-function loop | Inngest functions register statically — N registrations means N Sentry monitors and N token mints for the same job; `step.invoke` adds replay/serialization complexity for isolation a per-bundle try boundary already provides. The in-function loop with per-bundle step IDs is the minimal shape. |
| Stacked PRs (refactor first, feature second) | Repo convention is one plan → one PR; commit-level ordering inside the PR achieves the same review split without a second ship cycle. Reconsidered if the diff proves unreviewable. |
| Amend T&C §7.2 unconditionally | Six of eight reviewers flagged the forced re-acceptance cost vs a parity-only sentence; escalated to the apply-gate (Phase 4). |

## User-Brand Impact

- **If this lands broken, the user experiences:** a generated MSA / NDA / privacy policy carrying
  a wrong clause, an unstripped third-party law-firm credit, or an "attorney-drafted" implication
  Soleur never earned — inside a document the founder signs or publishes.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the generated document
  itself (the deliverable IS the exposure vector — a defective clause silently shipped into a
  signed contract); secondarily, company-context PII through the emit path (already bounded by
  the Phase 2.5 redaction gate).
- **Brand-survival threshold:** `single-user incident` (brainstorm carry-forward).

CPO sign-off required at plan time before `/work` — carried forward from brainstorm CPO
assessment (see `## Domain Review`).

## Observability

```yaml
liveness_signal:
  what:            "Sentry cron monitor for content-vendor-drift (slug: scheduled-content-vendor-drift) — per-bundle last-verified ages"
  cadence:         "weekly (17 11 * * 1)"
  alert_target:    "Sentry issue via failure_issue_threshold"
  configured_in:   "apps/web-platform/infra/sentry/cron-monitors.tf (existing monitor; per-bundle age reported in handler result)"

error_reporting:
  destination:     "Sentry web-platform via reportSilentFallback (SENTRY_DSN)"
  fail_loud:       "re-vendor PR or compliance/critical issue per bundle; vendor/cron-failure issue on measurement failure"

failure_modes:
  - mode:          "Bundle NOTICE missing after clone (new bundle landed unhooked or deleted)"
    detection:     "setupEphemeralWorkspace sentinel throws per bundle; bundle-discovery test asserts registry coverage"
    alert_route:   "Sentry issue + failed run"
  - mode:          "Per-bundle upstream unreachable / archived"
    detection:     "upstreamRepoState per bundle; route to issue, never sibling-bundle failure"
    alert_route:   "GitHub issue (vendor/upstream-archived, compliance/critical)"
  - mode:          "Bundle last-verified age ≥30d (drift unresolved or cron silent)"
    detection:     "heartbeatOk age gate per bundle — unconditional, per existing design"
    alert_route:   "Sentry monitor page"
  - mode:          "Emitted doc carries vendor credit (strip bypassed or substrate shape changed)"
    detection:     "legal-template-vendor-surface test — applies strip to every corpus file and greps output for vendor marks; corpus-count floor asserts the sweep is non-vacuous"
    alert_route:   "CI red on PR"

logs:
  where:           "Inngest run logs (web-platform); per-bundle ComparisonTotals in handler result"
  retention:       "Inngest dashboard retention"

discoverability_test:
  command:         "bash -c 'for n in plugins/soleur/skills/*/NOTICE; do d=$(NOTICE_FILE=\"$n\" bash plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh days-stale); echo \"$n: $d days\"; done'"
  expected_output: "one line per discovered NOTICE (>=2), each reporting < 30 days on a healthy tree"
```

## Architecture Decision (ADR/C4)

This plan generalizes single-bundle vendoring to a registry-driven multi-bundle model — a
resolver/trust-boundary change to a compliance enforcement stack.

### ADR

Create `knowledge-base/engineering/architecture/decisions/ADR-218-multi-bundle-vendored-content-registry.md`
(ordinal **provisional** — re-verify next-free against all `origin/*` refs immediately before
merge per the ADR-155/#7418 collisions). Decision: vendored-content enforcement is
registry-driven — every `plugins/soleur/skills/*/NOTICE` is auto-enrolled in drift cron,
lefthook integrity, and PR-time upstream verify; scripts stay gdpr-gate-owned and shared via
`NOTICE_FILE`/`SKILL_PREFIX` env override (ADR-095 shared-engine precedent); corpus retains vendor
credits, emit path strips them deterministically.

### C4 views

Checked `model.c4` / `views.c4` / `spec.c4` for the feature's external surface: no new external
human actor (no correspondent/reviewer), no new container or data store. One new external
*system* edge of an already-modeled class: the content-vendor-drift cron fetches upstream blobs
from GitHub — goSprinto today, plus General-Legal after this plan. Task: extend the existing
`github` external-system element's description (and the cron→github edge label if present) to
record the second vendored upstream, rather than adding a per-vendor element the model's
granularity doesn't carry (goSprinto itself is not an element). Run
`apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`, and
`plugins/soleur/test/c4-count-parity.test.sh` after the edit.

### Sequencing

The ADR describes the shipped state and lands in this PR — not deferred.

## Guard Contract

### Guard 1 — vendor-credit emit strip

**Property.** No document emitted by `legal-generate` from a vendored substrate contains
General Legal vendor marks (`general.legal`, `General Legal`); the corpus retains them.

**Assembly.** The emit chokepoint is the substrate pipeline in
`legal-document-generator.md` — every template-fill output passes through
`strip-vendor-credit.sh` before Phase 2.5 redaction. The test quantifies over ALL files in
`references/templates/*/template.md` (a directory walk, never a hardcoded list) plus the SKILL /
agent instruction that routes every template-fill through the script. Two chokepoints, both
named: the script (deterministic transform) and the instruction (the only path to emission).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the credit-block deletion from `strip-vendor-credit.sh` | RED — output retains marks |
| 2 | Point the test's corpus glob at an empty fixture dir | RED — corpus-count floor (≥12) fails; "0 checked" is vacuous |
| 3 | Add a 13th synthetic template carrying `general.legal` mid-document (not in the trailing block) | RED — the mark grep covers the whole output, not only the trailing block |
| 4 | Harness: feed a generator-fallback document (no vendor content) through the pipeline | PASS — fallback docs bypass the strip entirely (it runs on the substrate path only); the pipeline does not reject non-substrate input |
| 5 | Narrow the emit grep back to `general\.?legal` (dot-only) | RED — the hyphenated `General-Legal` header token and spaced `General Legal` credit token escape detection |

### Guard 2 — vendored-bundle coverage

**Property.** Every schema-conforming `plugins/soleur/skills/*/NOTICE` (parseable frontmatter
declaring `upstream` + `pinned-commit`) on the tree is enrolled in all three enforcement
surfaces (lefthook glob, `vendor-pin-verify.yml` paths, cron bundle set). Prose attribution
NOTICEs without frontmatter (e.g. `incident/NOTICE`, already on the tree) are correctly NOT
enrolled — the guard derives its population with the same schema predicate the cron uses.

**Assembly.** The discovery set is the glob `plugins/soleur/skills/*/NOTICE` filtered by the
schema predicate; the enforcement surfaces are the two config files' path lists and the cron's
bundle enumeration. Members drift — a third conforming bundle landing tomorrow must fail this
guard, not sail past it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a synthetic schema-conforming `NOTICE` under `plugins/soleur/skills/fake-bundle/` without registering it | RED |
| 2 | Remove the legal-generate glob from `lefthook.yml` while its NOTICE exists | RED |
| 3 | Weaken the schema predicate so `incident/NOTICE` counts as a bundle | RED — it is not enrolled in any surface |
| 4 | Harness: run the guard on the real tree post-Phase-2 | PASS — both conforming bundles enrolled, `incident/NOTICE` excluded |

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Marketing (brainstorm carry-forward — all
assessed at brainstorm Phase 0.5 with `USER_BRAND_CRITICAL=true`).

### Legal (CLO)

**Status:** reviewed (carry-forward)
**Assessment:** CC0 permits vendoring; risks are correctness/UPL/jurisdiction/endorsement, not
license. Mandatory: no attorney-drafted claims, disclaimer §2.3 + T&C §7.2 amendments with
TC_VERSION bump and CLO attestation, compliance-auditor pass over corpus, BAA gated
regulated-industry, vendor neutrality preserved. All encoded as FRs/ACs above.

### Engineering (CTO)

**Status:** reviewed (carry-forward)
**Assessment:** Generalization scope is the real cost — cron per-bundle loop, integrity-script
parameterization, CI globs. Template-fill is a prompt-level change with a deterministic strip;
no runtime dependencies added. Encoded in Phase 2.

### Product (CPO)

**Status:** reviewed (carry-forward; sign-off per `requires_cpo_signoff`)
**Assessment:** Contract coverage is the actual user value; reference-only leaves it unsolved.
Gated types keep the ICP boundary legible.

### Marketing (CMO)

**Status:** reviewed (carry-forward)
**Assessment:** No "attorney-drafted"/partnership/endorsement claims in any Soleur output;
footnote stripped in emitted docs; vendor positioned neutrally in recommended-tools alongside
peers. Encoded in Phase 3–4.

### Product/UX Gate

**Tier:** none — no UI-surface file in Files to Create/Edit (skills/markdown/scripts/CI only;
mechanical override did not fire).

**Brainstorm-recommended specialists:** `legal-compliance-auditor` — covered as a Phase-4
deliverable (corpus audit before ship), not a UX-gate specialist. No copywriter recommendation
carried forward (no user-facing copy surface).

## Acceptance Criteria

- [ ] AC1: `plugins/soleur/skills/legal-generate/NOTICE` exists; frontmatter carries
  `upstream: github.com/General-Legal/legal-templates`,
  `pinned-commit: 0f7c7bfabf1be77a2bf52eef80815e24c93a190a`, and exactly 12 `lifted-files`
  entries each with both `upstream-blob-sha` and `local-blob-sha` (`awk`/`yq` count assertion).
- [ ] AC2: All 12 `references/templates/*/template.md` start with the line-1 attribution header
  `<!-- Adapted from General-Legal/legal-templates (CC0-1.0) — see NOTICE -->` AND retain the
  credit paragraph (`grep -l 'General Legal' | wc -l == 12` — provenance retained in corpus).
- [ ] AC3: `strip-vendor-credit.sh <each corpus file>` emits output with
  `grep -icE 'general[-.[:space:]]?legal' == 0` — all three written forms including the
  hyphenated `General-Legal` in the line-1 header (which the strip removes on the emit path)
  and the spaced `General Legal` in the credit body; invoking it on a substrate lacking the
  credit marker exits non-zero (provenance-anomaly fail-loud; anchored on the credit text, not
  a bare `---`).
- [ ] AC4: `lefthook.yml` contains a `vendor-pin-integrity` stanza whose glob covers
  `plugins/soleur/skills/legal-generate/NOTICE` and `references/**` (not `references/templates/**`
  — future sibling files must not slip); a staged edit to a vendored template without a NOTICE
  bump fails the hook.
- [ ] AC5: `vendor-pin-verify.yml` `paths:` covers legal-generate NOTICE + `references/**`; the
  verify step runs once per NOTICE (both bundles verified on the PR diff).
- [ ] AC6: `cron-content-vendor-drift.ts` enrolls bundles by SCHEMA-QUALIFIED discovery —
  `plugins/soleur/skills/*/NOTICE` with parseable frontmatter carrying `upstream` +
  `pinned-commit` (skips `incident/NOTICE`, a prose attribution with no frontmatter) — AND
  satisfies the full per-bundle identifier manifest: per-bundle `step.run` IDs, per-bundle
  branch prefixes via per-bundle `cronName` into `safeCommitAndPr`, dedup queries scoped per
  bundle with legacy-suffix classification, `NOTICE_FILE` (absolute) in the spawned-script
  env, no `gosprinto`/`ref: "main"` literals in shared paths, per-arm reset to `origin/main`
  before each write step, per-bundle typed failure returns (a bundle that produced no totals
  counts as failed, never masks the sibling), AND-aggregated function-level heartbeat with
  per-bundle breakdown.
- [ ] AC6b: `cron-content-vendor-drift.test.ts` re-keyed anchors all pass (slug-bearing
  literals, not shared prefixes) AND includes the cross-bundle masking test (open bundle-A
  re-vendor PR does not suppress bundle-B) AND a schema-exclusion test (a prose NOTICE without
  frontmatter is skipped, not enrolled).
- [ ] AC6c: `.markdownlintignore` excludes `plugins/soleur/skills/legal-generate/references/`;
  lefthook `markdown-lint` and CI lint pass on the vendored corpus.
- [ ] AC6d: `.github/CODEOWNERS` pins `/plugins/soleur/skills/legal-generate/NOTICE` to the
  same owner as gdpr-gate's (the #3535 trust-binding gate for `last-verified` drive-by edits).
- [ ] AC7: `vendor-bundle-coverage.test.sh` passes on the real tree — every discovered NOTICE is
  enrolled in all three surfaces (Guard 2).
- [ ] AC8: `docs/legal/disclaimer.md` and `plugins/soleur/docs/pages/legal/disclaimer.md` no
  longer assert generated documents are "not prepared by licensed attorneys" in absolute form;
  the amended text conveys provenance without the term "attorney-drafted", retains a
  review-status denial ("not reviewed or endorsed by any attorney"), and still requires
  professional legal review. `lint-legal-mirror-drift-baseline.sh --base origin/main` green.
- [ ] AC9: **No T&C diff** — `docs/legal/terms-and-conditions.md`, `tc-version.ts`, the three
  seed scripts, and `TC_DOCUMENT_SHA`/`TC_BUMP_METADATA` are untouched (§7.2 amendment cut at
  the apply-gate; follow-up issue filed to ride the next natural bump). Disclaimer entries in
  `legal-doc-shas.ts` re-pinned via `sha256sum`; `check-tc-document-sha.sh` green;
  disclaimer `**Last Updated:**` + posture Disclaimer cell updated.
- [ ] AC10: `legal-doc-consistency.test.ts` green; `lint-legal-scope-block-placement.sh --base
  origin/main` green; `EXPECTED_COUNT` sentinel unchanged (no new canonical doc — generated
  artifacts are user-side, not corpus).
- [ ] AC11: `legal-generate/SKILL.md` lists the new doc types with the menu mechanics (numbered
  list + top-4 AskUserQuestion + Other); BAA and employee-offer-letter appear only as
  request-only gated types with blocking confirms (never menu options);
  `description:` word count is word-neutral vs `main` (zero-headroom budget) or sibling trims are
  listed in Files to Edit.
- [ ] AC12: `legal-document-generator.md` mandates the strip step + the `<mark>`
  field-collection contract (mechanical slot enumeration, AskUserQuestion batching, fail-closed
  on declined required fields, residual-`<mark>` emit grep) + jurisdiction routing
  (UK/uncovered → generator fallback) + a prohibition on attorney-drafted/endorsement claims;
  a grep sentinel asserts the prohibition line exists.
- [ ] AC12b: NOTICE `soleur-authored:` block declared (empty list acceptable — no `.md` outside
  `templates/` exists under `references/`); the NOTICE frontmatter↔table parity test covers the
  new bundle.
- [ ] AC13: `knowledge-base/engineering/policies/content-vendoring.md` §10 registry row +
  `compliance-posture.md` §Vendored Code Provenance row added.
- [ ] AC14: `recommended-tools.md` gains a `## template-libraries` section (kebab heading) with
  a ≥2-row vendor table, peers-first ordering, and the transparency sentence;
  `legal-recommended-tools.test.ts` green with `EXPECTED_THRESHOLDS` deliberately bumped 5→6.
- [ ] AC15: `legal-compliance-auditor` corpus report committed under
  `knowledge-base/legal/audits/`; CLO attestation recorded on the PR.
- [ ] AC16: ADR written (ordinal re-verified against `origin/*` before merge); C4 model edit
  landed; `c4-code-syntax`, `c4-render`, `c4-count-parity` green.
- [ ] AC17: `lint-guard-contract.py` green on this plan file.
- [ ] AC18: Full diff grep for vendor marks: no `general[-.[:space:]]?legal` token
  (case-insensitive, all three written forms) appears outside an explicit allowlist —
  `plugins/soleur/skills/legal-generate/references/templates/**` (corpus), the legal-generate
  `NOTICE`, `content-vendoring.md`, `compliance-posture.md`, `recommended-tools.md`,
  ADR-218, and the vendoring runbook (`hr-third-party-content-grep-on-undertaking`).
- [ ] AC19: `plugins/soleur/README.md` skill-table prose updated (14 document types — the
  `:252` "(8 document types, 3 jurisdictions)" line).
- [ ] AC20: `knowledge-base/engineering/operations/runbooks/vendor-pin-drift-resolution.md`
  generalized per-bundle (issue-title/path literals parameterized; the stale "dispatch the
  workflow" line at :87 referencing the deleted GHA workflow fixed).
- [ ] AC21: `content-vendoring.md` carries the standing emit-strip doctrine section scoped to
  no-attribution licenses; ADR-218 records the schema-keyed enrollment contract, the
  license-scoped strip doctrine, the shared-monitor trade-off, and the `layers/`-anchored
  classifier limitation for `templates/` upstream paths.

## Open Code-Review Overlap

None — queried 65 open `code-review` issues; zero bodies mention any planned file.

## Test Scenarios

- Given a vendored template, when the generator fills `<mark>` fields from company context, then
  the emitted document contains the filled values, both DRAFT disclaimers, and zero vendor marks.
- Given a request for `data-processing-agreement` + jurisdiction `UK`, when substrate selection
  runs, then the from-scratch generator path is used (no UK substrate exists).
- Given an explicit request for `business-associate-agreement`, when the skill asks the
  regulated-industry confirmation and the user declines, then generation does not proceed.
- Given a staged local edit to a vendored template without a NOTICE bump, when `git commit`
  runs, then `vendor-pin-integrity` exits non-zero naming the file.
- Given the drift cron sees General-Legal HEAD move, when the weekly run fires, then a re-vendor
  PR opens scoped to the legal-generate bundle only (gdpr-gate attestation untouched).
- Given `strip-vendor-credit.sh` invoked on a file without the credit marker, when it exits, then
  exit code is non-zero and no "clean" output is produced.
- Given a template-fill request where the user declines a required `<mark>` field, when the
  field-collection contract runs, then no document is emitted and the missing fields are named;
  a subsequent explicit choice of the from-scratch arm produces a draft.
- Given an open `ci/content-vendor-drift-gdpr-gate-*` re-vendor PR, when the drift cron's
  legal-generate arm finds drift, then a legal-generate re-vendor PR opens — bundle-A's open PR
  does not suppress bundle-B (cross-bundle masking test).

## Success Metrics

- 14 doc types reachable via legal-generate (8 existing + 6 new), 11 of them substrate-backed
  (5 existing: ToS, privacy-policy US+EU, cookie-policy, gdpr-policy, DPA; 6 new: all).
- All four vendoring enforcement layers cover both bundles (cron, lefthook, CI verify,
  staleness banner).
- Zero vendor-mark tokens in any emitted document; zero "attorney-drafted" claims in Soleur
  output or docs.

## Dependencies & Risks

- **Blocking:** the disclaimer §2.3 amendment (falsified claim — non-T&C doc, SHA re-pin only,
  no re-acceptance cost; CLO sign-off advisory-tier). If review rejects the disclaimer
  amendment, the vendored substrate cannot ship — fallback is reference-only (Alternative 1).
- **Correctness ownership:** templates are attorney-drafted for general cases; Soleur still owns
  drift monitoring and the emit-strip. `legal-compliance-auditor` pass is a ship gate (AC15).
- **Cron refactor blast radius:** the per-bundle loop touches attestation logic hardened by
  #7710; per-bundle isolation is required so one bundle's failure cannot mask another's
  (Failure-mode rows above).
- **Demand risk:** #3786's criteria are unfired; this plan proceeds because the mechanism is
  different (CC0 content, not a plugin integration) and the marginal cost is bounded by the
  existing enforcement stack — recorded against #3786 at ship time.
- **Upstream health:** General-Legal is a law-firm lead-gen surface; an upstream quality or
  license regression is handled by the existing classifier routes (archived/rollback/license
  → compliance/critical issue).
- **Competitor adjacency (CMO):** General Legal (YC) maintains `agent-operated-company` and a
  paid-funnel MCP — its core narrative is Soleur's core narrative. CC0 removes license
  friction, not narrative adjacency: vendored corpus is fine (transparent provenance), but
  recommended-tools ordering is peers-first and the weekly re-vendor can pull NEW competitor
  upsell content into the corpus — Guard 1's widened token set + the pre-merge corpus audit
  are the controls.
- **#7710 sequencing (advisor):** the attestation writer's first post-merge firing is the
  2026-09-14 cron run on the pre-refactor code path; this PR lands after it and rebases onto
  whatever Monday's run produced — the descriptor refactor must not swallow that first
  attestation evidence.
- **gdpr-gate (Phase 2.7, advisory):** zero findings — no regulated-path diff, no new processor,
  no Art. 9 surface. Adjacency note: the corpus-freshness attestation writer (#7710 row,
  IN-PROGRESS) fires its first post-merge cron run 2026-09-14; this bundle's `last-verified`
  will be advanced by that same machinery once generalized in Phase 2.

## References & Research

- Brainstorm: `knowledge-base/project/brainstorms/2026-09-13-legal-templates-cc0-eval-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-legal-templates-cc0-eval/spec.md`
- Learning: `knowledge-base/project/learnings/2026-09-13-cc0-legal-template-vendoring-eval.md`
- Policy: `knowledge-base/engineering/policies/content-vendoring.md`
- Upstream: `github.com/General-Legal/legal-templates` @ `0f7c7bf` (CC0-1.0)
- Related: #3785 (founder-threshold handoff), #3786 (claude-for-legal deferral — relationship
  recorded, criteria unchanged), #8120 (draft PR), #7710 (NOTICE/attestation hardening)

## Files to Create

- `plugins/soleur/skills/legal-generate/NOTICE`
- `plugins/soleur/skills/legal-generate/references/templates/{advisor-agreement,business-associate-agreement,cookie-notice,dpa-global,dpa-us,employee-offer-letter,master-services-agreement,mutual-nda,one-way-nda,privacy-policy-gdpr,privacy-policy-us,terms-of-use}/template.md` (×12)
- `plugins/soleur/skills/legal-generate/scripts/strip-vendor-credit.sh`
- `plugins/soleur/test/legal-template-vendor-surface.test.ts`
- `plugins/soleur/test/vendor-bundle-coverage.test.sh`
- `apps/web-platform/test/server/inngest/cron-content-vendor-drift.test.ts` additions —
  cross-bundle masking test (may live inside the existing file's describe blocks)
- `knowledge-base/engineering/architecture/decisions/ADR-218-multi-bundle-vendored-content-registry.md` (ordinal provisional)
- `knowledge-base/legal/audits/<date>-general-legal-corpus-audit.md` (auditor output — audits/ is the clo-path convention, clo.md:68)

## Files to Edit

- `plugins/soleur/skills/legal-generate/SKILL.md` (doc-type list + menu mechanics, template-fill arm, staleness pre-step, gated types with blocking confirms, word-neutral description)
- `plugins/soleur/agents/legal/legal-document-generator.md` (substrate protocol, `<mark>` field-collection contract, strip step, residual-`<mark>` emit grep, claim prohibitions, fallback routing)
- `plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh` (`SKILL_PREFIX` env override)
- `lefthook.yml` (legal-generate stanza, `references/**` glob)
- `.github/workflows/vendor-pin-verify.yml` (paths + per-NOTICE verify loop)
- `.markdownlintignore` (exclude `plugins/soleur/skills/legal-generate/references/`, mirroring the gdpr-gate exclusion)
- `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts` (BundleDescriptor[] + per-bundle identifier manifest — step IDs, branch prefixes, dedup scopes, spawned env, commit text, allowedPaths, heartbeat aggregation)
- `apps/web-platform/test/server/inngest/cron-content-vendor-drift.test.ts` (re-key ~25 anchors to descriptor; add cross-bundle masking test)
- `plugins/soleur/test/vendor-drift-workflow.test.sh` (≥2-bundle coverage)
- `plugins/soleur/test/vendor-pin-integrity.test.sh` (multi-bundle case)
- `plugins/soleur/test/notice-frontmatter.test.sh` + `_base-notice-frontmatter.test.sh` (parameterize or second invocation so the legal-generate NOTICE gets frontmatter↔table parity)
- `plugins/soleur/test/legal-recommended-tools.test.ts` (`EXPECTED_THRESHOLDS` 5→6)
- `plugins/soleur/README.md` (`:252` doc-type count prose)
- `.github/CODEOWNERS` (legal-generate NOTICE row, #3535 trust-binding parity)
- `knowledge-base/engineering/operations/runbooks/vendor-pin-drift-resolution.md` (per-bundle generalization + stale :87 fix)
- `knowledge-base/engineering/policies/content-vendoring.md` (§10 row + §4 multi-bundle note + standing emit-strip doctrine section)
- `knowledge-base/legal/compliance-posture.md` (§Vendored Code Provenance row + Disclaimer cell :76; T&C cell untouched)
- `docs/legal/disclaimer.md` + `plugins/soleur/docs/pages/legal/disclaimer.md` (§2.3 + `**Last Updated:**`)
- `apps/web-platform/lib/legal/legal-doc-shas.ts` (re-pin disclaimer via `sha256sum`; T&C entry untouched)
- `knowledge-base/legal/recommended-tools.md` (template-libraries section)
- `knowledge-base/engineering/architecture/diagrams/model.c4` (+ `views.c4` if the cron→github edge renders)
