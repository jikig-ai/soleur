# Tasks — encryption-posture #6897 (ledger + C4 re-home + zot + legal reconcile)

Plan: `knowledge-base/project/plans/2026-07-24-chore-encryption-posture-6897-ledger-rehome-zot-legal-plan.md`
Lane: cross-domain · Threshold: single-user incident (CLO sign-off; user-impact-reviewer at review) · Live-infra mutation: NONE
Deepened 2026-07-24 (3-agent panel). Decisions/challenges: `decision-challenges.md`.

## Phase 0 — Preconditions (read-only)
- [ ] 0.1 Layer A baseline: `python3 scripts/lint-encryption-posture.py --repo-sweep` → PASS.
- [ ] 0.2 `git grep -l '#6897'` → expect 6 files (ledger, model.c4, model.likec4.json, audit doc, r2 plan, design-default tasks.md). Ledger has 8 refs; model.c4 has 2.
- [ ] 0.3 Confirm `server.tf:1569` / `git-data.tf:196` volumes + attachments (`server.tf:1581`, `git-data.tf:207`) — READ only, no terraform/hcloud mutation.

## Phase 1 — Follow-up trackers (Option B — 3 issues) + #6893 note
- [ ] 1.1 `gh label list` — confirm `type/security`, `domain/engineering`, `priority/p3-low` exist.
- [ ] 1.2 Create issue: superseded plaintext backstop teardown (workspaces detach+destroy; git_data DL-2 wipe). Ref #6893, #6588. Body carries BOTH triggers verbatim. Capture number.
- [ ] 1.3 Create issue: host at-rest posture measurement — session-store + git-data host (Layer-B probes). Ref #6893. Body carries BOTH triggers. Capture number.
- [ ] 1.4 Create issue: zot registry TLS / private-net re-evaluation. Ref #6893. Capture number.
- [ ] 1.5 Comment on #6893: Layer A lint checks tracking_issue shape only, not open/closed state (class gap; propose open-state/expires_on staleness check).
- [ ] 1.6 Durable handle: `encryption-posture:` title prefix + `type/security` label so numbers are re-derivable via `gh issue list`.

## Phase 2 — Sweep every LIVE artifact
- [ ] 2.1 Ledger: re-point all 8 `#6897` refs (57,74,77,97,100,259,262,290) to new numbers — both `live_verification` `tracked #N` and `exception.tracking_issue`/`reevaluate_when`. Leave expires_on/evidence/mechanism/defends/disclosed_as UNCHANGED.
- [ ] 2.2 model.c4:216,220 — genericize `, tracking #6897)` → `)` (point at ledger SoT). Prose-only; no element/relationship/view/tag change.
- [ ] 2.3 model.likec4.json — mirror the string edit (9 embeds) or regenerate via likec4 export.
- [ ] 2.4 Layer A lint → PASS; run c4 tests (`c4-code-syntax.test.ts`, `c4-render.test.ts`) → green.
- [ ] 2.5 Do NOT touch audit doc / r2 plan / design-default tasks.md (immutable historical).

## Phase 3 — Legal-doc reconciliation (checkbox 3)
- [ ] 3.1 Run `/soleur:legal-audit` inline over `docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`.
- [ ] 3.2 Reconcile encryption claims vs ledger (privacy-policy:515,519; DPD:44,98,410); apply the plaintext-backstop over-claim check.
- [ ] 3.3 MATERIAL over-claim (measured posture falsifies a published claim) → FOLD inline before Closes #6897 (never defer). Only large non-falsifying structural additions may defer (Ref #6893). Record verdict for PR body.

## Phase 4 — Verify + ship
- [ ] 4.1 Layer A PASS; c4 tests green; 3 new issues `gh issue view <N> --json state` = OPEN with reevaluate_when in body.
- [ ] 4.2 Repo-scoped: `git grep -l '#6897'` returns ONLY historical + own-feature allowlist (no ledger/model.c4/model.likec4.json).
- [ ] 4.3 `git diff --name-only origin/main` = ledger + model.c4 + model.likec4.json + legal (if folded) + kb plan/spec; no `.tf`, no migration, no server/src.
- [ ] 4.4 Broken-citation sweep on plan file.
- [ ] 4.5 PR body: `Closes #6897`, `Ref #6588`, `Ref #6893`, 3 new numbers, legal verdict, decision-challenges rendered; no operator/post-merge checklist.
