---
feature: feat-harden-agent-sandbox-5875
plan: knowledge-base/project/plans/2026-07-01-feat-harden-agent-sandbox-sdk-bump-plan.md
closes: 5875
lane: cross-domain
---

# Tasks — Harden agent-sandbox against SDK-bump breakage (#5875)

Derived from the finalized plan. Three PRs preceded by a blocking spike. Check #5875's boxes as each item lands.

## Phase 0 — Spike (blocking, pre-PR) — DONE (see #5875 comment)

- [x] 0.1 Read installed `node_modules/@anthropic-ai/claude-agent-sdk/**`. **Finding:** seccomp-EPERM stderr lands in `err.message` (plain `Error`, no `.stderr` field); `agent-runner.ts:2648` already reads it. → PR1 classifier keyed on `.message` is correct.
- [x] 0.2 **Finding: NOT feasible.** Sandbox init is gated behind `query()` (Anthropic API call); `startup()` only pre-warms the subprocess; the Bash tool is always model-driven. → faithful canary needs creds + network + must handle model non-determinism.
- [x] 0.3 Recorded both findings in #5875 (comment).

**PR2/PR3 mechanism fork (route to `soleur:engineering:cto` at PR2 kickoff — work-skill architectural-fork gate):** Q2 means the plan's "SDK-driven, no-model-turn canary" is partially blocked. Two candidates: (a) model-turn-driven (faithful; creds+network; scope to SDK-bump PRs; handle non-determinism), (b) capture-the-SDK-bwrap-argv-once-then-replay creds-free (decouples faithfulness from the model turn; re-capture on each SDK bump). CTO picks the mechanism; record in ADR-079.

## Phase 1 — PR1: sandbox-start observability (item 2)

- [x] 1.1 Create `apps/web-platform/server/sandbox-startup-classifier.ts` (mirror `abort-classifier.ts:54-88`): `classifySandboxStartupError()` → `{ sandboxKind, errorCode, sdkVersion }`, keyed off the Phase-0 error shape; `sandboxKind` enum = `missing_binary | seccomp_or_userns_denial | other`.
- [x] 1.2 Create `apps/web-platform/test/sandbox-startup-classifier.test.ts` — synthesized seccomp-EPERM signal (in the Phase-0 field), assert `sandboxKind` + `feature:"agent-sandbox"` tag + raw stderr; deterministic, no LLM in the assertion path.
- [x] 1.3 Broaden `cc-dispatcher.ts` catch (`:2694`; substring at `:2722`) to emit the tagged structured event for any startup failure; confirm the streaming-phase catch is covered.
- [x] 1.4 Broaden `agent-runner.ts` catch (`:2476`; substring at `:2649`; generic capture at `:2662`) to tag when `sandboxKind !== "other"`. **CTO ruling (ADR-079): NO `streamStartSent` gate** — it is always true at the catch (set before the iterator loop) and the seccomp denial surfaces mid-stream, so the gate silently suppressed the real signal; the classifier's signature match is the necessary+sufficient mis-tag guard.
- [x] 1.5 Emit per-user (no global-key debounce); pass raw `userId` → auto-hash to `userIdHash`; omit `workspacePath`. **Also promote `userIdHash` → event `user.id` (`observability.ts` `userScopeFromExtra`)** so `event_unique_user_frequency` counts distinct tenants — found at PR1 review (`observability-coverage-reviewer` P1). #3739 fold-in NOT taken (no new withIsolationScope+setUser site; the emit routes through the existing `reportSilentFallback`).
- [x] 1.6 Add the Sentry alert to `apps/web-platform/infra/sentry/issue-alerts.tf` — `event_unique_user_frequency` (≥3 tenants/1h), filters `feature=agent-sandbox`+`op=sdk-startup`; `terraform validate` passes.
- [x] 1.7 Author `knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md` (status `adopting`); cross-ref ADR-031/068/072/075/027. (Optional cleanup: add `sentry` to C4 — not a merge gate.)
- [x] 1.8 `tsc --noEmit`; run `observability-coverage-reviewer` at review. PR body: `Ref #5875` (item 2).

## Phase 2 — PR2: faithful canary, dark-launch (item 1)

- [x] 2.1 Create `apps/web-platform/scripts/sandbox-canary.mjs`. **Mechanism = ADR-079 hybrid (CTO-ruled):** `--capture`/`--verify` (CI/PR3) import `agent-runner-sandbox-config.ts` (lazy dynamic import; does not re-specify options) + drive the SDK to snapshot the argv; `--replay` (deploy-time, default) replays the captured SETUP argv creds-free inside the canary container. Runs in-container (`docker exec <canary> node …`) — the host has no node.
- [x] 2.2 Create `apps/web-platform/test/sandbox-canary.test.ts` (14 tests, vitest-collected; classifier/fixture/invocation + source-contract, no LLM).
- [x] 2.3 Wire the faithful canary into `ci-deploy.sh` **non-blocking** (`run_faithful_sandbox_canary` after the legacy probe, which stays the gate); verdict → `write_sandbox_canary_state` → deploy-state. Baked into the image via Dockerfile COPY.
- [x] 2.4 Exit-code classification (`docker exec` 125/126/127/ENOENT ⇒ `canary_infra_error`; `bwrap … Operation not permitted` ⇒ `sandbox_broken`) in the mjs + host wrapper; `set +o pipefail` around the logger/exec block.
- [x] 2.5 `cat-deploy-state.sh` surfaces `sandbox_canary` on `/hooks/deploy-status` (+ soak accumulators); `sandbox_canary_sentry_event` on faithful-FAIL (never journald-only).
- [x] 2.6 Create `scripts/followthroughs/canary-promotion-5875.sh` (single stateless GET; PASS after `consecutive_pass ≥ 5` over ≥3d, self-pinned via host-accumulated `first_pass_at`); wire secrets into `scheduled-followthrough-sweeper.yml`. **Deviation:** the `follow-through` directive is enrolled on a **dedicated soak issue #5889** that Refs #5875 (NOT #5875 itself) — the sweeper CLOSES on soak-pass, which would prematurely close the umbrella #5875 before PR3 (items 3+4). Soak accumulation lives host-side in `write_sandbox_canary_state` (increment/reset/hold), tested by `sandbox-canary-soak.test.sh` (11 cases, registered in infra-validation.yml).
- [x] 2.7 `tsc --noEmit` (canary is `.mjs` + shell — no TS surface); vitest 14/14 + infra shells green. PR body: `Ref #5875` (item 1).

## Phase 3 — PR3: SDK-bump guard + profile→redeploy (items 3 + 4)

- [ ] 3.1 `ci.yml` `pull_request` job: detect a resolved-version change of `@anthropic-ai/claude-agent-sdk` / `@anthropic-ai/claude-code` in **`package-lock.json`** (deploy-authoritative); add a `bun.lock`↔`package-lock.json` parity assertion; on trigger, run the faithful canary via `docker run` on the committed profile (blocking).
- [ ] 3.2 Create the synthesized pre-#5874 seccomp fixture (`apps/web-platform/infra/test-fixtures/.../seccomp-pre-5874.json`); regression test: #5849 replay against it makes the canary FAIL.
- [ ] 3.3 `apply-deploy-pipeline-fix.yml`: sequenced (post-apply) redeploy POST to `/hooks/deploy`; then assert `/hooks/deploy-status` `seccomp_profile_sha256 == sha256(committed)` + canary pass; `::error::`+`exit 1` if not (fail-loud).
- [ ] 3.4 `ci-deploy.sh` records the loaded profile sha256; `cat-deploy-state.sh` emits `seccomp_profile_sha256`.
- [ ] 3.5 AppArmor apply-parity: add `terraform_data.apparmor_bwrap_profile` to the workflow `-target=` set + `on.push.paths`; update the #5505 paths-union and #5873 co-target assertions in lockstep.
- [ ] 3.6 Add a **new** loaded-verification guard to `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`: redeploy step ordered after `terraform apply` + a `loaded==committed` fail-loud assertion. Keep the #5505/#5515/#5873 describes green.
- [ ] 3.7 Promote the canary to blocking; a `sandbox_broken` verdict hooks the existing `ci-deploy.sh:784` rollback path.
- [ ] 3.8 Flip ADR-079 → `accepted`. `tsc --noEmit`; `bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`; run `security-sentinel` at review. PR body: `Closes #5875`.

## Sequencing notes
- Phase 0 gates everything (error shape → classifier; no-model-turn → canary/CI shape).
- PR2 before PR3 (item 3 + item 4 consume the canary; promotion to blocking needs the dark-launch soak).
- PR1 and PR2 could merge (canary is non-blocking) if preferred; default keeps observability first.
