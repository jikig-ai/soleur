# Tasks: retire the GHCR token minter and host-side GHCR credential plumbing (#8714 task 5.4)

Plan: `knowledge-base/project/plans/2026-09-27-chore-retire-ghcr-token-minter-and-host-credential-plumbing-plan.md`

## 1. Setup

- [x] 1.1 Worktree + branch from origin/main e980b9bfc8
- [x] 1.2 Whole-repo consumer census with dispositions (plan § Consumer census)
- [x] 1.3 Open code-review overlap check (#8595 acknowledged)

## 2. RED

- [ ] 2.1 Parity describe `#8714 5.4 GHCR minter retirement` + TEST_FLOOR bump (RED before deletion)
- [ ] 2.2 App tests to post-retirement shape (count 69; exemptions and minter cases removed)

## 3. GREEN

- [ ] 3.1 Delete `ghcr-minter-doppler-token.tf`, `ghcr-read-credential.tf`; remove `var.ghcr_read_*`; tftest dummies
- [ ] 3.2 Delete `cron-ghcr-token-minter.ts` + test; route.ts, cron-manifest.ts, routine-metadata.ts
- [ ] 3.3 Delete `scripts/followthroughs/ghcr-minter-live-6031.sh`
- [ ] 3.4 Comment edits: zot-registry.tf, inngest-betterstack-token.tf, inngest-host.tf, token-drift-read-tokens.tf, zot-entry-gate.sh, github-app-manifest-parity.test.ts, encryption-posture-ledger.json
- [ ] 3.5 C4 edges; ADR-096 amendment; ADR-088 note; zot-registry-revert.md runbook line

## 4. Verify

- [ ] 4.1 Parity suite + mutation battery
- [ ] 4.2 Targeted vitest suites; tsc
- [ ] 4.3 terraform fmt/validate/test; c4 parity; encryption lint; infra-no-human-steps; markdownlint

## 5. Ship

- [ ] 5.1 `[ack-destroy]` in branch commit; PR `Ref #8714`
- [ ] 5.2 infra-validation plan comment = exactly 4 deletes; no apply queued
- [ ] 5.3 squash merge with `--body-file` carrying `[ack-destroy]`
- [ ] 5.4 Post-merge: apply Plan line, Doppler names gone, token gone, deploy green; tick 5.4 on #8714
- [ ] 5.5 File deferral issues (target cleanup; non-TF residue)
