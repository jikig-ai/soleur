# Tasks: hosted autonomous ask-before-destroy (#9776)

Plan: `knowledge-base/project/plans/2026-10-10-feat-hosted-autonomous-ask-before-destroy-plan.md`
Rulings: `cto-ruling.md`, `cpo-signoff.md`, `clo-ruling.md` in this directory.

## Phase 0 — RED
- 0.1 Write `apps/web-platform/test/fixtures/destroy-ask-corpus.json` (AC-1, AC-2, AC-6, AC-22 rows; `hookAsks`, `hostedOnly` notes)
- 0.2 Write `test/destroy-ask-classifier.test.ts` (corpus, safe-bash invariant, floor)
- 0.3 Write `test/permission-callback-destroy-ask.test.ts` (lane order, cache laundering, forged selection, un-acked owner, support, non-owner, telemetry hygiene, gate lifecycle AC-19, card visibility AC-20)
- 0.4 Write `test/resolve-protected-branches.test.ts` (union, failure, hardening, TTL, AC-23)
- 0.5 Write `test/destroy-ask-hook-parity.test.ts`; confirm bash, perl, jq exist on the CI shard; missing tool fails hard
- 0.6 Add the factory-wiring test (AC-14) beside `test/cc-dispatcher-bash-gate.test.ts`
- 0.7 Run each new file, confirm RED for the right reason

## Phase 1 — classifier
- 1.1 `server/destroy-ask-classifier.ts`: git push family, terraform/tofu, `gh` family, fail-closed rule, near-miss keywords
- 1.2 Corpus and classifier tests GREEN

## Phase 2 — resolver, lane, wiring, telemetry
- 2.1 `server/resolve-protected-branches.ts` (hardened local read, TTL, repo from dispatch scope)
- 2.2 Lane in `server/permission-callback.ts` (after support deny, before `bashAutonomous`; Approve/Reject; `cachePrefix = ""`; deny text)
- 2.3 Wire `resolveProtectedBranches` in `server/cc-dispatcher.ts`; confirm legacy `agent-runner.ts` needs no edit
- 2.4 Telemetry: pino, `warnSilentFallback`, outcomes, near-miss, degradations; approver role
- 2.5 Lane and wiring tests GREEN

## Phase 3 — mutation harness
- 3.1 `test/destroy-ask-mutation.test.sh` (anchor-asserted mutants, one targeted file per mutant, runtime budget)
- 3.2 Register the suite where sibling guard suites register; do not run the full battery locally
- 3.3 Run repo-wide ratchets on the committed tree

## Phase 4 — copy and CLO audit
- 4.1 Apply CLO bytes to the banner constant and toggle paragraph; update LOCKED-copy tests; add the vocabulary guard test
- 4.2 Create `knowledge-base/legal/audits/2026-10-counsel-review-9776-ask-gate.md`; add the conditional supersede marker to `2026-10-counsel-review-9776.md`
- 4.3 Confirm `docs/legal/**`, mirrors, `TC_VERSION`, `TC_DOCUMENT_SHA`, `LEGAL_DOC_SHAS`, migrations have an empty diff

## Phase 5 — ADR and C4
- 5.1 `soleur:architecture` create ADR-282 (re-derive ordinal over `refs/remotes/origin/*`)
- 5.2 ADR-277 addendum (hosted ask, CPO3-R2, verify-migrations finding #9825); ADR-093 sentence; `agent-env.ts` comment
- 5.3 `model.c4` hosted-posture descriptions (three sites); regenerate `model.likec4.json`; run C4 tests

## Phase 6 — soak enrollment and filing
- 6.1 `scripts/followthroughs/hosted-destroy-ask-window-9776.sh` (`--window 24h|7d`, call-count floor, notify-only); tracker directive twice; sweeper secrets
- 6.2 File the CLO C6 tracking issue (gated `gh issue create`; net-issue-flow override block)

## Ship
- S.1 Review panel (security-sentinel, user-impact-reviewer, architecture-strategist, observability-coverage-reviewer, test-design-reviewer, code-simplicity-reviewer, pattern-recognition-specialist); report-only, fix all findings in one commit
- S.2 CLO attestation against C1-C9
- S.3 ASK the operator for go-ahead with the production effects listed in the plan; then emit-review-trailer, push, arm merge
- S.4 Post-deploy: `deploy-arm.sh find <sha>` DEPLOY=success and `served <sha>` CONTAINS; dev probe (CLO C9); record numbers in ADR-277 addendum
