# Tasks — cron sandbox hook-primary containment (v3.1)

Plan: `knowledge-base/project/plans/2026-06-08-fix-cron-sandbox-hook-primary-containment-plan.md`
Status: **v3 DRAFT — implement the v3.1 design (the "Security Panel Findings" section of the plan), NOT the two-matcher §D1.**
Branch: `feat-one-shot-5000-5004-cron-sandbox-bwrap-fix` · Draft PR #5018 · Ref #5000/#5004 (→ durable issues, P0-E)
Supersedes earlier v1/v2 task lists for this branch.

## Phase 0 — gating re-verification (the panel reopened AC0)

- [ ] 0.1 **(P0-D, gating)** Re-run the 6 probes against the **Dockerfile-pinned** `claude-code@2.1.79` (or bump the pin to 2.1.168 in this PR and re-run AC2b against it). Prior probes ran on 2.1.168; prod runs 2.1.79. Pin the working result in `phase0-probe-results-AC0.md`.
- [ ] 0.2 **(P0-C)** Verify the `/app/shared/plugins/soleur` mount (`plugin-path.ts:17`) is **read-only** to the cron spawn. If yes → hook-integrity is infra-enforced. If no → file a Tier-2 infra issue (model can poison the shared mount).
- [ ] 0.3 **(P1-A)** Enumerate ALL ~21 producers that call `setupEphemeralWorkspace` (not just the 12 `Bash`-token crons). Classify each Tier-1 (hook-allowlistable) / Tier-2 (fail-closed).
- [ ] 0.4 **(D-new-1b)** Positive control: the spawn-time self-test ABORTS the cron when the hook is unreachable. Own AC.

## Phase 1 — RED (tests first; real-spawn behavioral)

- [ ] 1.1 `cron-bash-allowlist-hook.test.ts` — adversarial parser unit tests: compound `&&`/`;`/`||` per-segment matching; quote-aware tokenizer (the `gh api '…' --jq '.[]|{…}'` quoted-pipe must NOT false-deny — P1-F); `--body-file`/`-F`/`@`-file argument-injection denial (P0-B); `git remote`/non-origin-push denial.
- [ ] 1.2 `cron-claude-eval-substrate.test.ts` rewrite — real `claude --print` spawn (AC2b/P1-D): `Read(.git/config)` DENIED, `Read(/proc/self/environ)` DENIED, `Grep` of secret paths DENIED, `uname` DENIED, `curl`/`WebFetch` DENIED, Write to `.claude/` DENIED, an unrecognized tool DENIED (catch-all), allowlisted `gh issue list` ALLOWED. Assert via the byte-identical settings-registered command.
- [ ] 1.3 "no env-read verb is ever allowlisted" guard test (P2 — the most fragile coupling).
- [ ] Confirm RED.

## Phase 2 — GREEN

- [ ] 2.1 **(P0-A)** Hook = **deny-by-default at the tool-class level**: catch-all `*` matcher denies unrecognized tools; `Read|Glob|Grep` matcher denies `.git/**`,`/proc/**`,`**/.env*`,`.claude/`,`settings.json`,`$HOME` creds; `Bash` deny-by-default allowlist (quote-aware tokenizer, argument inspection); `Write|Edit` self-protection (realpath-aware, covers the symlinked plugin subtree — P0-C). Settings-baked allowlist, NOT env (P1-B). `node` by absolute path.
- [ ] 2.2 **(P0-A root fix)** Post-clone `git remote set-url origin <tokenless>` + credential helper so `GH_TOKEN` never persists in `.git/config` (removes the on-disk secret class).
- [ ] 2.3 `_cron-claude-eval-substrate.ts`: D3 overlay (`sandbox:false`, tool-class hook matchers, `allow:[]`, no `bypassPermissions`) + D2 spawn-time self-test (real-spawn-shaped, P1-D) + comment rewrite.
- [ ] 2.4 `cron-roadmap-review.ts` (D4): settings-baked allowlist enumerating EVERY prompt verb incl. `gh issue list/comment/edit/close`, `gh pr list/comment`, `gh label create`, `git checkout/add/commit/push origin` (P1-F); resolve AC4c (hook-deny→RED path OR accept-and-document — P1-C).
- [ ] 2.5 `cron-community-monitor.ts` (D5): keep read-auth tokens (C1); surface disabled platforms (C2).
- [ ] 2.6 **(P1-A)** D6 atomic with 2.3: pause Inngest schedules (or mute monitors w/ Tier-2 link) for ALL Tier-2 producers IN THE SAME COMMIT; AC asserts no Tier-2 cron has a live schedule post-merge.
- [ ] 2.7 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` + `vitest run …/inngest/` + `bash scripts/test-all.sh` green.

## Phase 3 — docs

- [ ] 3.1 `runbooks/cloud-scheduled-tasks.md` — hook-primary model, `sandbox:false`, self-test, version-pin note.
- [ ] 3.2 ADR-033 I7 binding invariant (incl. negative guarantee: containment ≠ Node-level `spawn`); consider a dedicated ADR for the sandbox→hook inversion.
- [ ] 3.3 Learning: headless `claude --print` is deny-list/hook-driven; hook fails OPEN on crash AND for unhooked tool classes; Read-deny ≠ Bash `cat`; token-in-`.git/config` is the exfil root.

## Phase 4 — follow-up issues + post-merge

- [ ] 4.1 **(P0-E)** Create DURABLE tracking issues (Tier-1 fix #5018; Tier-2 growth-audit etc.); `Ref` those, NOT the closed `[Scheduled]` artifacts. Founder-readable Tier-2 issue (which weekly outputs pause).
- [ ] 4.2 **(P1-E)** Tier-2 issue lists the **4** raw-`spawn("bash")` crons incl. `cron-weekly-analytics.ts`.
- [ ] 4.3 Post-merge: deploy → `/soleur:trigger-cron roadmap-review` → confirm `[Scheduled] Weekly Roadmap Review` produced end-to-end (AC11); record Tier-1 trigger results.
