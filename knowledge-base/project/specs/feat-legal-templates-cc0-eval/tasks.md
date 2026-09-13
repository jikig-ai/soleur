# Tasks — Vendor General-Legal CC0 legal templates into legal-generate

> Auto-generated from `2026-09-13-feat-legal-templates-cc0-eval-plan.md` by `/soleur:plan`.
> Execution: `/soleur:work` reads this file to fan out implementation agents.
> Full context, evidence, and failure modes live in the plan file — read it first.
> Phases land in ONE PR; task ordering is commit-level sequencing, not separate merges.
> Plan-review incorporated: §7.2/TC_VERSION bump CUT at the apply-gate (disclaimer-only ship);
> emit-grep widened to `general[-.[:space:]]?legal` + claim-leakage tokens; schema-keyed
> bundle enrollment; per-arm worktree reset; typed per-bundle failure returns.

| ID | Task | Dependencies |
|----|------|--------------|
| 1 | Vendor corpus + NOTICE + `.markdownlintignore` + registry rows + CODEOWNERS | — |
| 2 | Static enforcement: `SKILL_PREFIX` override + lefthook stanza + vendor-pin-verify + parity tests | 1 |
| 3 | Cron generalization: schema-keyed discovery + full per-bundle identifier manifest + test re-key | 1, 2 |
| 4 | Emit path: strip-vendor-credit.sh + Guard 1/Guard 2 tests | 1 |
| 5 | Generator agent: substrate selection + `<mark>` field-collection contract + gates | 4 |
| 6 | SKILL.md + README: menu mechanics, fill arm, staleness pre-step, word-neutral description | 5 |
| 7 | Legal: Disclaimer §2.3 amendment only (canonical+mirror, sha256 repin, Last-Updated, posture cell) | 5 |
| 8 | Closures: recommended-tools, ADR-218, C4, corpus audit, runbook, policy doctrine, follow-up issues, spec/#3786 | 7 |

---

## Task 1 — Vendor corpus + NOTICE + `.markdownlintignore` + registry rows + CODEOWNERS

**Create** under `plugins/soleur/skills/legal-generate/`:

- `references/templates/<dir>/template.md` ×12 from
  `raw.githubusercontent.com/General-Legal/legal-templates/0f7c7bfabf1be77a2bf52eef80815e24c93a190a/<dir>/template.md`:
  `advisor-agreement, business-associate-agreement, cookie-notice, dpa-global, dpa-us,
  employee-offer-letter, master-services-agreement, mutual-nda, one-way-nda,
  privacy-policy-gdpr, privacy-policy-us, terms-of-use`.
  Prepend line-1 `<!-- Adapted from General-Legal/legal-templates (CC0-1.0) — see NOTICE -->`.
  Retain the trailing credit paragraph verbatim (corpus retains; emit path strips BOTH the
  header and the credit). No `.docx`, no upstream scripts/READMEs.
- `NOTICE` — mirror `plugins/soleur/skills/gdpr-gate/NOTICE` schema exactly:
  `upstream: github.com/General-Legal/legal-templates`, `pinned-commit`,
  `last-verified: 2026-09-13`, `registry: knowledge-base/engineering/policies/content-vendoring.md`,
  `lifted-files:` 12 entries each with `path`, `upstream-path: <dir>/template.md`,
  `upstream-blob-sha` (GH blob SHA at pinned commit via `gh api repos/General-Legal/legal-templates/git/trees/<sha>?recursive=1`),
  `local-blob-sha` (`git hash-object --no-filters` post-header — NOTICE pins ARE git blob
  hashes; only the legal-doc SHAs use sha256sum), `status: active-verbatim` (the header is
  the policy's standard provenance line — gdpr-gate's active-verbatim entries carry it too).
  `soleur-authored:` declared as an EMPTY list — `scripts/*.sh` sit outside the
  `references/**/*.md` registry walk. Human table in body matching frontmatter.

**Edit:**

- `.markdownlintignore` — add `plugins/soleur/skills/legal-generate/references/` (mirroring
  the gdpr-gate exclusion ~:45). Without it, lint rewrites desync `local-blob-sha` pins.
- `.github/CODEOWNERS` — add `/plugins/soleur/skills/legal-generate/NOTICE @<same owner as
  gdpr-gate row :38>` (#3535 trust-binding parity).
- `content-vendoring.md` §10 registry row.
- `compliance-posture.md` §Vendored Code Provenance row.

**Phase 0 precondition:** `gh api repos/General-Legal/legal-templates` — confirm HEAD is still
`0f7c7bf…`, unarchived, and record `default_branch` (expected `main`; the cron descriptor
carries `upstreamRef` per bundle). Contamination inventory: grep all 12 for
`general[-.[:space:]]?legal`, `@`, URLs, non-credit vendor surfaces → PR body.

**Verify:** NOTICE frontmatter↔table parity; `git hash-object --no-filters` each template ==
its `local-blob-sha`; `grep -l 'General Legal' … | wc -l == 12`.

## Task 2 — Static enforcement + parity tests

- `vendor-pin-integrity.sh` (179 lines): `SKILL_PREFIX="${SKILL_PREFIX:-plugins/soleur/skills/gdpr-gate}"`.
  `--verify-upstream` reads only `NOTICE_FILE` + NOTICE-internal upstream coords — confirm.
- `lefthook.yml`: second `vendor-pin-integrity` stanza globbing
  `plugins/soleur/skills/legal-generate/NOTICE` + `…/references/**` (NOT `templates/**` —
  narrow-glob doctrine, lefthook.yml:239–265).
- `vendor-pin-verify.yml`: add legal-generate NOTICE + `references/**` to `paths:`; run the
  script once per schema-conforming NOTICE (share the predicate with the cron/Guard 2 —
  `incident/NOTICE` has no frontmatter and must NOT be enrolled).
- `vendor-pin-integrity.test.sh`: multi-bundle case. `notice-frontmatter.test.sh` +
  `_base-notice-frontmatter.test.sh`: parameterize (or second invocation) so the legal-generate
  NOTICE gets frontmatter↔table parity (#7710 defect class).

**Verify:** both bundles pass local + `--verify-upstream`; corrupted template fails naming the
file; gdpr-gate regression green.

## Task 3 — Cron generalization (highest blast radius)

`apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts` — 1,489 lines.

**Enrollment predicate (shared):** a bundle is `plugins/soleur/skills/*/NOTICE` whose
frontmatter parses AND declares `upstream` + `pinned-commit`. `incident/NOTICE` (prose, no
frontmatter) is skip-with-warn — the same predicate feeds cron discovery, Guard 2, the
verify workflow, and the discoverability command. Discovery runs INSIDE a `step.run` against
the clone (`repoRoot`), never module-level (ADR-033 I1).

**BundleDescriptor:** slug, noticeFileRel, skillPrefix, upstreamRef (default branch), upstream
name. Constants block (:72–77) → descriptors; `PARSER_REL`/`CLASSIFIER_REL` stay shared
(ADR-095 shared-engine — they are shared paths, not bundle constants).

**Per-bundle identifier manifest (all 10 items from plan §Architecture):**
1. Schema-keyed discovery (above).
2. Per-bundle `step.run` IDs (`<id>-<slug>`) — Inngest memoizes by ID; run-level steps
   (`run-started-at`, `mint-installation-token`, `setup-workspace`, `ensure-labels`) stay
   unsuffixed.
3. Per-bundle `cronName` (`cron-content-vendor-drift-<slug>`) into `safeCommitAndPr` →
   `deriveBranchName` yields `ci/content-vendor-drift-<slug>-<ts>`; `ATTEST_BRANCH_PREFIX` →
   `ci/vendor-attest-<slug>-`. Dedup transition: legacy un-suffixed branches/issues classify
   as gdpr-gate's.
4. Dedup queries (:955, :1238, :1047) scoped per bundle — unscoped, an open bundle-A PR
   suppresses bundle-B forever (#7710's skipped-open-pr shape).
5. Spawned-script env (:560–565) gains `NOTICE_FILE` as ABSOLUTE `join(repoRoot,
   noticeFileRel)` per bundle — without it bundle B attests onto A's registry.
6. `gosprinto` literals (:1008, :1265) + `ref: "main"` (:699) → per-bundle name/upstreamRef.
7. Per-arm reset to `origin/main` before each write step (`checkout -B` branches from HEAD,
   `_cron-safe-commit.ts:622` — without reset, B's attest PR carries A's unmerged commits).
8. Per-bundle typed failure returns inside a try boundary — a throwing step fails the handler
   and skips the sibling; `mayAttestFreshness`/`heartbeatOk` treat no-totals as failed.
9. `allowedPaths`, `readFile(NOTICE_FILE_REL)` (:399/:1138/:1154) → per-bundle.
10. Function-level heartbeat; slug in `reportSilentFallback` + `attestation-summary` fields;
    AND-aggregated health + per-bundle breakdown in handler result.

**Test re-key** — `apps/web-platform/test/server/inngest/cron-content-vendor-drift.test.ts`
(736 lines, ~25 anchors): constants-equality (:163–181) → descriptor-shape; step-ID slices
(:527/:626/:634/:669) → per-bundle; `ATTEST_BRANCH_PREFIX` (:618), `allowedPaths` (:130),
`mayAttestFreshness` (:514), `heartbeatOk` (:556) — re-key to slug-bearing literals, declared
per-anchor in the PR body. NEW: cross-bundle masking test + schema-exclusion test (prose
NOTICE skipped).

**Verify:** `cd apps/web-platform && npx vitest run test/server/inngest/cron-content-vendor-drift.test.ts`

## Task 4 — Emit path scripts + Guard tests

- `plugins/soleur/skills/legal-generate/scripts/strip-vendor-credit.sh` — removes the line-1
  `<!-- Adapted … -->` header AND the trailing credit block; anchors on the credit-paragraph
  marker text (NOT a bare `---`); exit 2 on input lacking the marker (provenance anomaly).
  Substrate path only — fallback docs bypass it.
- `plugins/soleur/test/legal-template-vendor-surface.test.ts` — Guard 1: walk ALL
  `references/templates/*/template.md` (never hardcoded list), run strip, assert
  `grep -icE 'general[-.[:space:]]?legal' == 0` (covers `general.legal`, `General Legal`,
  `General-Legal`); corpus-count floor ≥12; mutation rows per plan (incl. narrowed-regex RED
  and mid-document mark RED).
- `plugins/soleur/test/vendor-bundle-coverage.test.sh` — Guard 2: every schema-conforming
  `*/NOTICE` enrolled in lefthook glob + verify paths + cron bundle set; `incident/NOTICE`
  excluded by the shared predicate; mutation: weakening the predicate so incident counts → RED.
- `plugins/soleur/test/vendor-drift-workflow.test.sh` — ≥2-bundle coverage.

## Task 5 — Generator agent

`plugins/soleur/agents/legal/legal-document-generator.md` (45 lines — stays thin):

- 14 doc types with `substrate:` annotations; six contract substrates are US-only —
  non-US contract requests route to from-scratch (governing-law fill does not localize a
  US-drafted contract). UK + AUP/DPD/disclaimer → from-scratch.
- `<mark>` field-collection contract: mechanical grep enumeration; Phase-0 context fills
  shared slots; AskUserQuestion ≤4 related fields/question; "supply all values in one
  message" escape hatch offered up front; fail-closed on declined required slot (name missing
  fields, emit nothing, explicit from-scratch escape only); declined OPTIONAL slot removes
  its containing clause.
- Emit-side guard before presenting: zero `general[-.[:space:]]?legal`, zero
  `attorney[- ]draft|prepared by|reviewed by`, zero `<mark`/`[FIELD]` remnants.
- Mandatory strip step on substrate path; BAA blocking HIPAA confirm (decline → stop);
  offer-letter blocking CA-exempt confirm (decline → suggest advisor-agreement + offer
  from-scratch arm); NDA → mutual-vs-one-way follow-up (default mutual).
- Prohibition line (grep sentinel): no attorney-drafted/endorsement claims. DRAFT banner
  retained verbatim. All paths resolve via `${CLAUDE_PLUGIN_ROOT}`.

## Task 6 — SKILL.md + README

- `description:` word-neutral vs `main` — budget 2442/2442, zero headroom.
- Numbered list shows non-gated types only; gated types in a "request-only" prose note;
  AskUserQuestion top-4 + built-in Other; staleness pre-step
  (`NOTICE_FILE=…/legal-generate/NOTICE … days-stale`, 30/90 thresholds); template-fill arm;
  self-audit gains vendor-mark + residual-`<mark>` greps.
- `plugins/soleur/README.md:252` — "(8 document types, 3 jurisdictions)" → 14 types.

**Verify:** `skill-descriptions-count.test.ts`, `plugin-lint.sh`, `md-heading-sequence.test.ts`.

## Task 7 — Disclaimer amendment only (no T&C, no TC_VERSION)

**Operator-adjudicated cut:** §7.2 is anodyne; a parity sentence is not worth forced
re-acceptance for all users + WS session kills. Disclaimer is a non-T&C notice doc —
SHA re-pin only, no version machinery.

- `docs/legal/disclaimer.md` §2.3 + `plugins/soleur/docs/pages/legal/disclaimer.md`:
  remove the absolute "not prepared by licensed attorneys" claim; convey provenance WITHOUT
  "attorney-drafted" ("may incorporate text derived from third-party template libraries");
  RETAIN a review-status denial ("not reviewed or endorsed by any attorney"); keep
  drafts/not-legal-advice/review-required/reliance-at-own-risk; update `**Last Updated:**`
  (:14, with change-summary parenthetical per convention).
- `apps/web-platform/lib/legal/legal-doc-shas.ts` — disclaimer entry re-pinned via
  `sha256sum` (64-hex; NOT `git hash-object`).
- `compliance-posture.md` Disclaimer cell (:76) updated (unguarded cell — would go stale).
- File follow-up: "§7.2 substrate-provenance sentence rides the next natural Tier-1/2 T&C
  bump."

**Verify:** `lint-legal-mirror-drift-baseline.sh --base origin/main`,
`lint-legal-scope-block-placement.sh --base origin/main`, `check-tc-document-sha.sh`,
`legal-doc-consistency.test.ts`, EXPECTED_COUNT sentinel unchanged.

## Task 8 — Closures

- `knowledge-base/legal/recommended-tools.md` — `## template-libraries` (kebab heading),
  ≥2-row table, peers-first ordering (CommonPaper CC BY 4.0, Bonterms CC BY 4.0,
  General-Legal CC0 last or alphabetical), transparency sentence ("Soleur vendors a CC0
  snapshot of one listed library"); `legal-recommended-tools.test.ts` `EXPECTED_THRESHOLDS`
  5→6 with comment.
- `content-vendoring.md` — standing emit-strip doctrine section scoped to no-attribution
  licenses.
- `vendor-pin-drift-resolution.md` — per-bundle generalization + fix stale :87 (deleted GHA
  workflow reference).
- `ADR-218` — ordinal re-verified vs `origin/*` pre-merge; records schema-keyed enrollment,
  license-scoped strip doctrine, shared-monitor trade-off, `layers/`-anchored classifier
  limitation on `templates/` paths.
- `model.c4` — extend `github` external-system description for second upstream; c4 tests green.
- `legal-compliance-auditor` corpus pass → `knowledge-base/legal/audits/`; auditor retains the
  drop decision pre-merge (AC15 gates ship).
- Spec closure: `spec.md` G1 → filled; `legal-generate`/`legal-audit` → `partial`.
- Follow-up issues: UK template coverage; periodic legal-currency re-audit (TR3 — documented
  manual cadence row in compliance-posture.md + tracking issue); cron monolith split
  (detect/attest/report); demand-signal instrumentation (feeds #3786); dangling
  `recommended-tools.md` install-site references; §7.2 provenance sentence (next T&C bump).
- `gh issue comment 3786` — partial overlap recorded, criteria unchanged.

---

## Execution notes for /work

- All phases land in ONE PR — no unenrolled vendored content reaches `main`.
- Task 3 is the blast-radius task; the sharpest hazards are step-ID memoization, the missing
  `NOTICE_FILE` env, and the per-arm worktree reset — all three silently corrupt the sibling
  bundle behind a green monitor if missed.
- `incident/NOTICE` is on the tree TODAY and matches the bare glob — the schema predicate is
  not optional.
- Commits land on `feat-legal-templates-cc0-eval` in `.worktrees/feat-legal-templates-cc0-eval/`.
