# Tasks: feat-one-shot-auth-mode-selects-credential

Plan: `knowledge-base/project/plans/2026-10-30-feat-auth-mode-selects-agent-credential-plan.md` | Tracker #11591 | PR #11590 | Follow-up #11594

## Phase 1: Setup — shared binding auth-mode resolver

- 1.1 Write failing tests: `apps/web-platform/test/engine-binding-auth-mode.test.ts` (run present; no run + legacy; no run + pending throws unbound; no run + null state throws; state read error; run read error)
- 1.2 Create `apps/web-platform/server/auth-mode-error.ts` (dependency-free leaf: reasons tuple + `ConversationAuthModeError`)
- 1.3 Create `apps/web-platform/server/engine-binding-auth-mode.ts` (`readConversationBindingAuthMode`, `makeConversationAuthModeResolver`)
- 1.4 Edit `apps/web-platform/server/agent-auth-mode.ts` to delegate; update its REMOVAL CHECKLIST (keep new modules; delete the AC10 test with the diagnostic)

## Phase 2: Core Implementation — lease honours the mode

- 2.1 Write failing lease matrix in `apps/web-platform/test/byok-lease-credential-type.test.ts` (AC1-AC6, AC8, scenario 9; shared `managedResolver` fixture; mutation: remove the mode branch must fail the api-key test; reorder mode above the gates must fail the spy-never-called case)
  - 2.1.1 Update existing oauth cases to pass `managedResolver`
- 2.2 Edit `apps/web-platform/server/byok-lease.ts`: `resolveAuthMode?` on args and slot; `resolveLeaseAuthMode`; reorder `fetchAgentCredentialIntoSlot` (gates, mode, then decrypt/shape under managed); JSDoc for third callers
- 2.3 Write failing five-branch forwarding test in `apps/web-platform/test/byok-resolver-delegation-workspace.test.ts` (Guard 1, incl. `{ restOnly: true }` must-pass row, exactly-five-branches floor)
- 2.4 Edit `apps/web-platform/server/byok-resolver.ts`: required `LeaseModeOpts`, single `run` helper for all five branches, header comment
- 2.5 Wire callers: `agent-runner.ts` startAgentSession and cc-dispatcher.ts pass `makeConversationAuthModeResolver`; `agent-runner.ts` routing lease, `cfo-on-payment-failed.ts`, `github-on-event.ts` pass `{ restOnly: true }`
- 2.6 Write failing real-binding test `apps/web-platform/test/byok-lease-auth-mode-binding.test.ts` (AC7: flip binding between leases; legacy; pending; read error) and the AC10 divergence test; make them pass
- 2.7 Pin `credentialScheme: credential.scheme` in both frame files (AC9) with `grep -c ... >/dev/null`

## Phase 3: Bind unbound agent-running conversations

- 3.1 Add `rpc` to the `test/support-conversation.test.ts` mock; write failing tests for support (new row, sticky pending, sticky legacy not bound) and the auto-sync test (bind before `startAgentSession`, non-fatal failure)
- 3.2 Edit `apps/web-platform/server/auto-sync-trigger.ts` (service-client `bind`, non-fatal mirror op `auto-sync-bind`)
- 3.3 Edit `apps/web-platform/server/support-conversation.ts` (tenant-client `bind`; extend select to `id, engine_binding_state`; op `bind`)

## Phase 4: UI copy

- 4.1 Write failing tests in `apps/web-platform/test/agent-engine-settings.test.tsx` (labels incl. radio sub-label, helper Claude-only, disclosure in both modes, aria-describedby, unchanged PUT bodies)
- 4.2 Edit `apps/web-platform/components/settings/agent-engine-settings.tsx` (`authModeLabel`, helper outside the label, aria-describedby, disclosure in both modes, text verbatim)

## Phase 5: Architecture records

- 5.1 Amend ADR-048 via `soleur:architecture` (mode selection, gate order, alternatives, the two divergences) and add the one-line ADR-233 cross-reference
- 5.2 Edit `knowledge-base/engineering/architecture/diagrams/model.c4` (binding component description); run c4 syntax/render tests and `plugins/soleur/test/c4-count-parity.test.sh`
- 5.3 `bash scripts/check-adr-ordinals.sh` against freshly fetched origin/main

## Phase 6: Testing and gates

- 6.1 Sweep tests: `git grep -l "anthropic_oauth\|CC_OAUTH_ENABLED" apps/web-platform/test` and `git grep -ln "resolveKeyOwnerThenLease" apps/web-platform/test`
- 6.2 Run source-text tests: `git grep -l readFileSync apps/web-platform/test | xargs grep -l "byok-lease\|byok-resolver\|agent-runner\|cc-dispatcher\|agent-engine-settings\|auto-sync-trigger\|support-conversation\|agent-auth-mode\|engine-binding-auth-mode"`
- 6.3 `bash scripts/test-all.sh --capacity`, then targeted vitest files, `npx tsc --noEmit` (verify it fails when `LeaseModeOpts` is omitted once), lint scripts, pr-quality-guards userId check
- 6.4 PR body: `Ref #11591`, `Ref #11086`, `Ref #11541`, no `Closes`; render taste and operator-scope rows from decision-challenges.md
