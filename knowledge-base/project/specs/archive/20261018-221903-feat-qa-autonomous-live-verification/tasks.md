# Tasks: feat-qa-autonomous-live-verification (#10449)

Plan: knowledge-base/project/plans/2026-10-16-feat-autonomous-live-verification-plan.md

## Phase 1 — Records
- [x] 1.1 Amend ADR-064 (I-cannot-spend, I-no-model-turn-in-prod, I-egress-not-attested-by-gate, contract paragraph, repo-write note) via soleur:architecture
- [x] 1.2 Add seed-qa-user.sh to Article 30 synthetic-principal rows; run soleur:gdpr-gate
- [x] 1.3 Read model.c4, views.c4, spec.c4; edit only if a gap; run c4-code-syntax and c4-render tests

## Phase 2 — I-cannot-spend gate
- [x] 2.1 Write failing tests in apps/web-platform/test/live-verify/gate.test.ts (non-sentinel, extra provider, delegation, zero rows, dry-run)
- [x] 2.2 Implement the all-rows + byok_delegations check inside verifyPrincipal (run.ts), own RLS session, runs under --dry-run
- [x] 2.3 Add ciphertext fields to redact.ts
- [x] 2.4 web-platform-release.yml: BLOCK=1 for cannot-spend-violated; rename the "(report-only)" step

## Phase 3 — Skill corrections
- [x] 3.1 postmerge/SKILL.md lines 239, 376, 387-393, 593, 620: gate is blocking, cite enforcing step
- [x] 3.2 flag-set-role/SKILL.md: three-step verification ladder; no operator-session hand-off
- [x] 3.3 Grep ADR-064 and skills for report-only|REPORT-ONLY; decide each hit

## Phase 4 — Tracking
- [x] 4.1 Passive-verification issue filed: #10461; OD1 filed: #10460
- [x] 4.2 Comment on #10450: runner/flows split at flow #2, contract ADR, dev/staging measurement
