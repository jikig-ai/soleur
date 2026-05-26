# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-05-18-legal-amend-aup-app-soleur-ai-chat-attachments-art9-ccpa-spi-plan.md`
- Status: complete
- Draft PR: #3988

### Errors
None.

### Decisions
- §4.6 numbering collision: existing AUP §4.6 "Shared Content" stays; new sections become §4.7 (Special-Category Data) and §4.8 (California SPI). Internal back-reference `§4.6` inside the drafted §4.8 → renumber to `§4.7` at edit time. AC3 has positive+negative grep pair.
- §6.2 "Consequences of Violation" exists (canonical line 188) — drafted cross-reference stays as-is, no substitution. PR body records the verification.
- AC4 (tc-version.ts bump) scoped out: `tc-document-sha-guard` is hard-pinned to T&C only (`apps/web-platform/scripts/check-tc-document-sha.sh:26-28`). T&C §9 incorporates AUP by reference, so AUP-only edits do not trigger re-consent.
- Docs-site mirror at `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` added to Files to Edit. Three independently-drifted dates moved to 2026-05-18 in lockstep (canonical, mirror, compliance-posture).
- `legal-doc-cross-document-gate.yml` will fire on `compliance-posture.md` change but exits trivially (no DSAR surface touched). Recorded as R6.
- T4 Eleventy validation: `npx @11ty/eleventy --dryrun` from repo root (matches deploy-docs.yml).

### Components Invoked
- `soleur:plan` (docs-only single-domain lane; GDPR Gate + IaC Gate skipped per phase rationale)
- `soleur:deepen-plan`
