# Tasks: Re-measure the SDK's per-host SandboxNetworkAccess allow cache on Agent SDK 0.3.328

Plan: `knowledge-base/project/plans/2026-11-19-chore-remeasure-sdk-sandbox-network-allow-cache-plan.md`
Branch: `feat-one-shot-12906-sdk-allow-cache-remeasure` · PR: #12966 · Issue: #12906 (`Ref`, not closed)
Lane: cross-domain · Threshold: none · Rulings: `decision-challenges.md` (CTO 1-10, 14-18; CLO 11-13)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Two stages: Build starts when #12897 has merged. Measure starts at the later of #12897 merged and 2026-11-21T23:14Z. Never bump the production SDK pin; never touch `apps/web-platform/package.json` or `package-lock.json`.

## Phase 0 — Gate

- [ ] 0.1 `gh pr view 12897 --json state,mergedAt` reports merged; otherwise stop, keep the PR draft, emit a resume prompt.
- [ ] 0.2 `git fetch origin && git rebase origin/main` (WIP commit first, never stash); confirm `apps/web-platform/test/helpers/netns-egress-harness.mts` exists (AC1).

## Phase 1 — Classifier (tests first)

- [ ] 1.1 RED: `apps/web-platform/test/sandbox-network-cache-verdict.test.ts` with a fresh-object fixture factory; the cases listed in plan Phase 1 (verdicts incl. MIXED exit 0 and `incoherent-f-f2`, every precondition incl. `post-teardown-ran`, extra input keys, baseline, LEAK and `LEAK (baseline)`, precedence pairs, UNVERIFIED, F2 counts, parser ERROR, sentinel redaction, `--markdown`).
- [ ] 1.2 GREEN: `apps/web-platform/scripts/lib/sandbox-network-cache-verdict.ts` exporting `MEASURED_BASELINE` and `DEAD_FORWARDER`; precedence table as the combine order; `REMEASURE verdict= exit= reason= next=` line; `--out`; `--markdown`; verdict-to-action table in the header.
- [ ] 1.3 Apply each Guard 1 mutation (rows 1-8) once; record the failing test name for the PR body (AC2).

## Phase 2 — Harness override

- [ ] 2.1 RED: runtime suite imports `MEASURED_BASELINE`/`DEAD_FORWARDER`; step-0 asserts `sdkVersion === MEASURED_ON_SDK` and per-arm `initClaudeCodeVersion === step0.cliVersion`.
- [ ] 2.2 GREEN: harness `NETNS_SDK_ENTRY` + `loadSdk()`; STEP0 `sdkEntry` (via `fileURLToPath(import.meta.resolve(...))`), `sdkVersion`, `cliPath`, `cliVersion`; per-arm `initClaudeCodeVersion` from the `system`/`init` message; `step0.ok` unchanged.
- [ ] 2.3 Reword the `MEASURED_ON_SDK` failure message (both versions, the command, CACHES-only baseline move).
- [ ] 2.4 Run the runtime suite under `unshare`; green on 0.3.321 (AC4).

## Phase 3 — Re-run script (tests first)

- [ ] 3.1 RED: `apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.test.sh` (stubs on PATH, copied fixture tree, no env seams); rows from plan Phase 3.
- [ ] 3.2 GREEN: `apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh` steps 1-11 (arch/setup preflight, userns check, trap first, whole-tree app hash, version resolve, `time[exact]` floor, two scratch prefixes with free-space check, installs with `--min-release-age=3` + `npm audit signatures`, version asserts, two harness runs both with `NETNS_SDK_ENTRY`, classify).
- [ ] 3.3 Apply each Guard 2 mutation once; record the failing case for the PR body (AC3).
- [ ] 3.4 `git add` the suite; run it and `bash scripts/lint-orphan-test-suites.sh`; `tsc --noEmit` (AC7).

## Phase 4 — Pointers

- [ ] 4.1 `sdk-bump-sandbox-gate.sh`: `echo` after `DETECTED bump`; run its `.test.sh`.
- [ ] 4.2 ADR-278 2026-11-18 addendum "Re-measure trigger": the command and the verdict-to-action table (AC5).

## Phase 5 — Measure (after 2026-11-21T23:14Z and #12897 merged)

- [ ] 5.1 Run `bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh 0.3.328 --out <scratchpad>/verdict-0.3.328.json --markdown <scratchpad>/records` via a run_in_background launch or Monitor (never sleep-poll).
- [ ] 5.2 Branch on `verdict=`: CACHES / RE-ASKS-AFTER-TEARDOWN / MIXED / INCONCLUSIVE (one re-run) / UNVERIFIED / REFUSED / LEAK / ERROR, per plan Phase 5.
- [ ] 5.3 Write `## Addendum — <run date> (#12906): ...` in ADR-278 with the CLO verbatim wording (AC8-AC10).
- [ ] 5.4 `gh issue comment 12906 --body-file <file>` (AC11); file the conditional issues (AC12).

## Phase 6 — Verification

- [ ] 6.1 Both vitest suites; both `.test.sh` suites; `tsc --noEmit`.
- [ ] 6.2 `git diff --quiet origin/main...HEAD -- apps/web-platform/package.json apps/web-platform/package-lock.json` (AC6); pin and `MEASURED_BASELINE.version` still 0.3.321 (AC13).
- [ ] 6.3 `python3 scripts/lint-guard-contract.py <plan>`.
