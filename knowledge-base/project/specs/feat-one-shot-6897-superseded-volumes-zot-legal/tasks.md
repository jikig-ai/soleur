# Tasks — encryption-posture #6897 (ledger re-home + zot + legal reconcile)

Plan: `knowledge-base/project/plans/2026-07-24-chore-encryption-posture-6897-ledger-rehome-zot-legal-plan.md`
Lane: cross-domain · Threshold: single-user incident (CPO sign-off) · Live-infra mutation: NONE

## Phase 0 — Preconditions (read-only)
- [ ] 0.1 Layer A baseline: `python3 scripts/lint-encryption-posture.py --repo-sweep` → PASS.
- [ ] 0.2 Enumerate `#6897` refs in ledger: `grep -n '#6897' scripts/encryption-posture-ledger.json` (expect 8; assert by content anchor).
- [ ] 0.3 Confirm `server.tf:1569` / `git-data.tf:196` volumes + attachments (`server.tf:1581`, `git-data.tf:207`) still declared — READ only, no terraform/hcloud mutation.

## Phase 1 — Dedicated follow-up issues (mirror #6894/#6895)
- [ ] 1.1 `gh label list` — confirm `type/security`, `domain/engineering`, `priority/p3-low` exist.
- [ ] 1.2 Create issue: workspaces plaintext teardown (Ref #6893, #6588). Capture number.
- [ ] 1.3 Create issue: git_data plaintext DL-2 wipe + git-data host posture probe (Ref #6893, #6588). Capture number.
- [ ] 1.4 Create issue: redis.session_store at-rest posture measurement (Ref #6893). Capture number.
- [ ] 1.5 Create issue: zot registry TLS / private-net re-evaluation (Ref #6893). Capture number.
- [ ] 1.6 (Panel decision) confirm 4-issue default vs consolidation alt (plan Phase 1 Decision box).

## Phase 2 — Re-home ledger references
- [ ] 2.1 Re-point 8 `#6897` refs (lines ~57,74,77,97,100,259,262,290) to the new numbers — both `live_verification` `tracked #N` and `exception.tracking_issue`/`reevaluate_when`.
- [ ] 2.2 Leave `expires_on: 2026-10-22`, evidence, mechanism, defends/does_not_defend, disclosed_as UNCHANGED.
- [ ] 2.3 Re-run Layer A lint → PASS; `grep -c '#6897' ...` → 0.

## Phase 3 — Legal-doc reconciliation (checkbox 3)
- [ ] 3.1 Run `/soleur:legal-audit` inline over `docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`.
- [ ] 3.2 Reconcile encryption claims vs ledger (privacy-policy:515,519; DPD:44,98,410); apply the plaintext-backstop over-claim check.
- [ ] 3.3 Fold small corrections into this PR OR file a tracked follow-up if large; record verdict for the PR body.

## Phase 4 — Verify + ship
- [ ] 4.1 Layer A PASS; `grep -c '#6897'` → 0; each new issue `gh issue view <N> --json state` = OPEN.
- [ ] 4.2 `git diff --name-only origin/main` = only ledger + legal (if folded) + kb plan/spec; no `.tf`, no migration, no server/src.
- [ ] 4.3 Broken-citation sweep on plan file.
- [ ] 4.4 PR body: `Closes #6897`, `Ref #6588`, `Ref #6893`, 4 new numbers, legal-audit verdict; no operator/post-merge checklist.
