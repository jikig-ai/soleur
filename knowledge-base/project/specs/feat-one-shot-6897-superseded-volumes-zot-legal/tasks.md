# Tasks — encryption-posture #6897 (verify ledger current + legal reconcile; #6897 stays OPEN)

Plan: `knowledge-base/project/plans/2026-07-24-chore-encryption-posture-6897-ledger-rehome-zot-legal-plan.md`
Lane: cross-domain · Threshold: single-user incident (CLO sign-off; user-impact-reviewer at review) · Live-infra mutation: NONE
Deepened 2026-07-24 (3-agent panel). **Disposition (operator 2026-07-24): #6897 STAYS OPEN — 0 new issues, net-issue-flow = 0. No re-homing, no C4 edit.** Decisions: `decision-challenges.md`.

## Phase 0 — Preconditions (read-only)
- [ ] 0.1 Layer A baseline: `python3 scripts/lint-encryption-posture.py --repo-sweep` → PASS.
- [ ] 0.2 Confirm the ledger rows exist + are current for `hcloud_volume.workspaces`, `hcloud_volume.git_data`, and the zot registry link (`grep -n '#6897' scripts/encryption-posture-ledger.json` — 8 refs; they correctly point at the still-open #6897 and STAY).
- [ ] 0.3 Confirm `server.tf` / `git-data.tf` volumes + attachments still declared — READ only, no terraform/hcloud mutation.

## Phase 1 — (REMOVED — no trackers; #6897 stays open). One advisory comment on parent:
- [ ] 1.1 Comment on the OPEN #6893: Layer A lint checks `tracking_issue` shape only, not open/closed state (latent class gap; propose an open-state/`expires_on` staleness check). Single comment on an existing open issue — NOT a new issue.

## Phase 2 — Verify ledger + zot rows current (READ-ONLY; no ref edits, no C4 edit)
- [ ] 2.1 Verify `workspaces`/`git_data`/zot ledger rows' evidence/mechanism/defends/does_not_defend/`tracking_issue: #6897`/`expires_on` are accurate against code. Leave every `#6897` ref UNCHANGED. Edit ONLY a provably-stale field (none expected).
- [ ] 2.2 `model.c4` + `model.likec4.json`: LEAVE UNCHANGED (no C4 edit → no regenerate).
- [ ] 2.3 Layer A lint → PASS (confirm read-only verification did not perturb the ledger).
- [ ] 2.4 Do NOT touch audit doc / r2 plan / design-default tasks.md (immutable historical).

## Phase 3 — Legal-doc reconciliation (checkbox 3 — THE actionable deliverable)
- [ ] 3.1 Run `/soleur:legal-audit` inline over `docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`.
- [ ] 3.2 Reconcile encryption claims vs ledger measured postures (privacy-policy:515,519; DPD:44,98,410); apply the plaintext-backstop over-claim check (does the wording over-claim absolute at-rest encryption in a way the still-attached plaintext backstops falsify?).
- [ ] 3.3 MATERIAL over-claim (measured posture falsifies a published claim) → FOLD inline before merge (never defer; #6588 shape). If a legal doc is edited, keep its Eleventy mirror in lockstep + regenerate `legal-doc-shas.ts`; run `legal-doc-consistency.test.ts` + `legal-doc-shas-guard.test.ts` AFTER the edit. Only large non-falsifying structural additions may defer (Ref #6893). Record verdict for PR body.

## Phase 4 — Verify + ship
- [ ] 4.1 Layer A PASS; if a legal doc edited, mirror-parity tests green. NO new GitHub issue created (net-issue-flow ≤ 0).
- [ ] 4.2 Ledger `#6897` refs UNCHANGED (`git diff scripts/encryption-posture-ledger.json` shows no ref change); `model.c4`/`model.likec4.json` UNCHANGED.
- [ ] 4.3 `git diff --name-only origin/main` = legal docs + mirror (if folded) + kb plan/spec (+ ledger ONLY if a stale field corrected); no `.tf`, no migration, no server/src, no C4.
- [ ] 4.4 Broken-citation sweep on plan file.
- [ ] 4.5 Check off #6897 checkboxes 1 & 2 (ledger current) via issue comment; #6897 STAYS OPEN.
- [ ] 4.6 PR body: `Ref #6897` (stays open — NOT Closes), `Ref #6588`, `Ref #6893`, legal verdict, decision-challenges rendered; no operator/post-merge checklist.
