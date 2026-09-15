---
lane: cross-domain
plan: knowledge-base/project/plans/2026-09-15-chore-aup-scope-names-playwright-mcp-plan.md
issue: 7981
pr: 8207
---

# Tasks — AUP §2 scope names the Playwright MCP (#7981)

## 1. Setup

- [x] 1.1 `WORK_DATE=$(date -u +%F)`; derive the long form (e.g. `September 15, 2026`).
- [x] 1.2 Read both AUP files, `legal-doc-shas.ts`, `compliance-posture.md`, and the tail of the #7980 attestation before editing.

## 2. Core Implementation

- [x] 2.1 Canonical + mirror + pin (single commit)
  - [x] 2.1.1 Replace the §2 bullet in `docs/legal/acceptable-use-policy.md` and `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` with the CLO-ruled line (plan Phase 1 step 1).
  - [x] 2.1.2 Canonical frontmatter `last-updated:` → `WORK_DATE`.
  - [x] 2.1.3 Both body `**Last Updated:**` lines: replace only the `**Last Updated:** September 13, 2026 *(` prefix with the new entry + `Previous: September 13, 2026 *(`.
  - [x] 2.1.4 Mirror hero `<p>` date → long `WORK_DATE`.
  - [x] 2.1.5 `sha256sum docs/legal/acceptable-use-policy.md` → `LEGAL_DOC_SHAS["acceptable-use-policy"]` (last).
- [x] 2.2 Register + trigger
  - [x] 2.2.1 `knowledge-base/legal/compliance-posture.md`: AUP row date and frontmatter `last_updated` → `WORK_DATE`.
  - [x] 2.2.2 Append the `## Addendum — #7981 re-evaluation trigger, <WORK_DATE>` section at end of `knowledge-base/legal/audits/2026-09-14-clo-attestation-7980-playwright-mcp-redact-proxy.md` (plan Phase 2 step 7 text).

## 3. Testing / Verification

- [x] 3.1 Commit, then run AC1–AC8 from the plan (AC5 = all legal gates + vitest).
- [x] 3.2 Review the Last Updated diff hunk by eye (identical corruption on both surfaces is invisible to body-equivalence).
- [ ] 3.3 PR #8207 body: `Closes #7981`, Tier 2 / `TC_VERSION` not-engaged line, pointer to the addendum, `Ref #7980, #8156` (AC9).
