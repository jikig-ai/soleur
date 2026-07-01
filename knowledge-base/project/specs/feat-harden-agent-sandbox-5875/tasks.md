---
feature: feat-harden-agent-sandbox-5875
plan: knowledge-base/project/plans/2026-07-01-feat-harden-agent-sandbox-sdk-bump-plan.md
closes: 5875
lane: cross-domain
---

# Tasks — Harden agent-sandbox against SDK-bump breakage (#5875)

Derived from the finalized plan. Three PRs preceded by a blocking spike. Check #5875's boxes as each item lands.

## Phase 0 — Spike (blocking, pre-PR)

- [ ] 0.1 Read installed `node_modules/@anthropic-ai/claude-agent-sdk/**` (`.d.ts` + sandbox builder); determine the exact field a seccomp-EPERM surfaces in (`err.message` vs subprocess `.stderr`).
- [ ] 0.2 Confirm the SDK can spawn a Bash sandbox + run a no-op **without** a model round-trip (or record the scope-down: creds + network, SDK-bump-PRs only).
- [ ] 0.3 Record both findings in #5875 — they gate PR1's classifier input and PR2/PR3's canary shape.

## Phase 1 — PR1: sandbox-start observability (item 2)

- [ ] 1.1 Create `apps/web-platform/server/sandbox-startup-classifier.ts` (mirror `abort-classifier.ts:54-88`): `classifySandboxStartupError()` → `{ sandboxKind, errorCode, sdkVersion }`, keyed off the Phase-0 error shape; `sandboxKind` enum = `missing_binary | seccomp_or_userns_denial | other`.
- [ ] 1.2 Create `apps/web-platform/test/sandbox-startup-classifier.test.ts` — synthesized seccomp-EPERM signal (in the Phase-0 field), assert `sandboxKind` + `feature:"agent-sandbox"` tag + raw stderr; deterministic, no LLM in the assertion path.
- [ ] 1.3 Broaden `cc-dispatcher.ts` catch (`:2694`; substring at `:2722`) to emit the tagged structured event for any startup failure; confirm the streaming-phase catch is covered.
- [ ] 1.4 Broaden `agent-runner.ts` catch (`:2476`; substring at `:2649`; generic capture at `:2662`); gate classification on `streamStartSent === false` (declared `:980`, set `:2107`) so mid-stream errors are not tagged.
- [ ] 1.5 Keep emit per-user (no global-key debounce on the sandbox-startup path); pass raw `userId` → auto-hash to `userIdHash` (`observability.ts:217`); omit/hash `workspacePath`. Evaluate folding in #3739's `reportSilentFallbackWithUser` helper.
- [ ] 1.6 Add the Sentry alert to `apps/web-platform/infra/sentry/issue-alerts.tf` using a native frequency/affected-users threshold; `terraform validate`.
- [ ] 1.7 Author `knowledge-base/engineering/architecture/decisions/ADR-077-faithful-sandbox-canary-and-profile-redeploy-verification.md` (status `adopting`); cross-ref ADR-031/068/072/075/027. (Optional cleanup: add `sentry` to C4 — not a merge gate.)
- [ ] 1.8 `tsc --noEmit`; run `observability-coverage-reviewer` at review. PR body: `Ref #5875` (item 2).

## Phase 2 — PR2: faithful canary, dark-launch (item 1)

- [ ] 2.1 Create `apps/web-platform/scripts/sandbox-canary.mjs` — import `agent-runner-sandbox-config.ts` (do not re-specify options), feed into the SDK, start a Bash sandbox, run a no-op; honor the Phase-0 no-model-turn finding.
- [ ] 2.2 Create `apps/web-platform/test/sandbox-canary.test.ts` (under `test/` so vitest globs collect it — not `scripts/`).
- [ ] 2.3 Wire the faithful canary into `ci-deploy.sh` **non-blocking**; keep the legacy `:784` probe as the gate; write the verdict to deploy-state.
- [ ] 2.4 Exit-code classification: `125/126/127/ENOENT` ⇒ `canary_infra_error` (non-blocking); `bwrap … Operation not permitted` ⇒ `sandbox_broken`. Bash traps: `set +o pipefail` around `| logger`, `awk '!seen[$0]++'`.
- [ ] 2.5 `cat-deploy-state.sh` surfaces the canary verdict on `/hooks/deploy-status`; emit a Sentry event on faithful-FAIL (no journald-only signal).
- [ ] 2.6 Create `scripts/followthroughs/canary-promotion-5875.sh` (exit 0 after 5 green verdicts over ≥3 days, `start=` pinned after PR2 deploy); add the tracker directive + `follow-through` label on #5875; wire secrets into `scheduled-followthrough-sweeper.yml`.
- [ ] 2.7 `tsc --noEmit`. PR body: `Ref #5875` (item 1).

## Phase 3 — PR3: SDK-bump guard + profile→redeploy (items 3 + 4)

- [ ] 3.1 `ci.yml` `pull_request` job: detect a resolved-version change of `@anthropic-ai/claude-agent-sdk` / `@anthropic-ai/claude-code` in **`package-lock.json`** (deploy-authoritative); add a `bun.lock`↔`package-lock.json` parity assertion; on trigger, run the faithful canary via `docker run` on the committed profile (blocking).
- [ ] 3.2 Create the synthesized pre-#5874 seccomp fixture (`apps/web-platform/infra/test-fixtures/.../seccomp-pre-5874.json`); regression test: #5849 replay against it makes the canary FAIL.
- [ ] 3.3 `apply-deploy-pipeline-fix.yml`: sequenced (post-apply) redeploy POST to `/hooks/deploy`; then assert `/hooks/deploy-status` `seccomp_profile_sha256 == sha256(committed)` + canary pass; `::error::`+`exit 1` if not (fail-loud).
- [ ] 3.4 `ci-deploy.sh` records the loaded profile sha256; `cat-deploy-state.sh` emits `seccomp_profile_sha256`.
- [ ] 3.5 AppArmor apply-parity: add `terraform_data.apparmor_bwrap_profile` to the workflow `-target=` set + `on.push.paths`; update the #5505 paths-union and #5873 co-target assertions in lockstep.
- [ ] 3.6 Add a **new** loaded-verification guard to `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`: redeploy step ordered after `terraform apply` + a `loaded==committed` fail-loud assertion. Keep the #5505/#5515/#5873 describes green.
- [ ] 3.7 Promote the canary to blocking; a `sandbox_broken` verdict hooks the existing `ci-deploy.sh:784` rollback path.
- [ ] 3.8 Flip ADR-077 → `accepted`. `tsc --noEmit`; `bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`; run `security-sentinel` at review. PR body: `Closes #5875`.

## Sequencing notes
- Phase 0 gates everything (error shape → classifier; no-model-turn → canary/CI shape).
- PR2 before PR3 (item 3 + item 4 consume the canary; promotion to blocking needs the dark-launch soak).
- PR1 and PR2 could merge (canary is non-blocking) if preferred; default keeps observability first.
