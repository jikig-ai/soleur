# Tasks: Re-measure the SDK's per-host SandboxNetworkAccess allow cache on Agent SDK 0.3.328

Plan: `knowledge-base/project/plans/2026-11-19-chore-remeasure-sdk-sandbox-network-allow-cache-plan.md`
Branch: `feat-one-shot-12906-sdk-allow-cache-remeasure` · PR: #12966 · Issue: #12906 (`Ref`, not closed)
Lane: cross-domain · Threshold: none · Rulings: `decision-challenges.md` (CTO 1-10, 14-20; CLO 11-13)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Two stages: Build starts when #12897 has merged. Measure starts at the later of #12897 merged and 2026-11-21T23:14Z. Never bump the production SDK pin; never touch `apps/web-platform/package.json` or `package-lock.json`.

## Phase 0 — Gate

- [x] 0.1 `gh pr view 12897 --json state,mergedAt` reports merged; otherwise stop, keep the PR draft, emit a resume prompt.
- [x] 0.2 `git fetch origin && git rebase origin/main` (WIP commit first, never stash); confirm `apps/web-platform/test/helpers/netns-egress-harness.mts` exists (AC1).

## Phase 1 — Classifier (tests first)

- [x] 1.1 RED: `apps/web-platform/test/sandbox-network-cache-verdict.test.ts` with a fresh-object fixture factory; the cases listed in plan Phase 1 (verdicts incl. MIXED exit 0 and `incoherent-f-f2`, every precondition incl. `post-teardown-ran`, extra input keys, baseline, LEAK and `LEAK (baseline)`, precedence pairs, UNVERIFIED, F2 counts, parser ERROR, sentinel redaction, `--markdown`).
- [x] 1.2 GREEN: `apps/web-platform/scripts/lib/sandbox-network-cache-verdict.ts` exporting `MEASURED_BASELINE` (with pinned `integrity` from `npm view <pkg>@0.3.321 dist.integrity`) and `DEAD_FORWARDER`; precedence table as the combine order; `REMEASURE verdict= exit= reason= next=` line; `--out`; `--markdown`; verdict-to-action table in the header.
- [x] 1.3 Apply each Guard 1 mutation (rows 1-8) once; record the failing test name for the PR body (AC2).

## Phase 2 — Harness override

- [x] 2.1 RED: runtime suite imports `MEASURED_BASELINE`/`DEAD_FORWARDER`; step-0 asserts `sdkVersion === MEASURED_ON_SDK` and per-arm `initClaudeCodeVersion === step0.cliVersion`.
- [x] 2.2 GREEN: harness `NETNS_SDK_ENTRY` + `loadSdk()`; STEP0 `sdkEntry` (via `fileURLToPath(import.meta.resolve(...))`), `sdkVersion`, `cliPath`, `cliVersion`; per-arm `initClaudeCodeVersion` from the `system`/`init` message; `step0.ok` unchanged.
- [x] 2.3 Reword the `MEASURED_ON_SDK` failure message (both versions, the command, CACHES-only baseline move).
- [x] 2.4 Run the runtime suite under `unshare`; green on 0.3.321 (AC4).

## Phase 3 — Re-run script (tests first)

- [x] 3.1 RED: `apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.test.sh`:
  - argv-exact stubs on PATH (`npm`, `unshare`, `uname`, `df`, `timeout`, the glibc probe) with an empty refusal log;
  - a copied fixture tree with the real `tsx` and the real classifier;
  - no env seams;
  - the rows from plan Phase 3, including containment, integrity, boundary, low-disk, timeout and bad-version-arg.
- [x] 3.2 GREEN: `apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh` steps 1-11:
  - arch and setup preflight, userns check, trap armed first, whole-tree app hash;
  - version argument regex check, then version resolve;
  - the `time[exact]` floor;
  - two scratch prefixes with a free-space check;
  - hardened `env -i` npm installs with `--min-release-age=3` and `npm audit signatures`;
  - version asserts, then baseline `dist.integrity` against `MEASURED_BASELINE.integrity` (step 9b);
  - containment in each run's namespace: tmpfs over `$HOME` and `$XDG_RUNTIME_DIR`, the worktree and git common dir read-only, a write probe that fails closed (step 10a);
  - two harness runs under `timeout -k 10 600 unshare -rnm --fork --pid --mount-proc --kill-child`, both with `NETNS_SDK_ENTRY`;
  - classify, with path and identity redaction.
- [x] 3.3 Apply each Guard 2 mutation once; record the failing case for the PR body (AC3).
- [x] 3.4 `git add` the suite; run it and `bash scripts/lint-orphan-test-suites.sh`; `tsc --noEmit` (AC7).

## Phase 4 — Pointers

- [x] 4.1 `sdk-bump-sandbox-gate.sh`: one `echo`, after the loop that prints the `DETECTED bump` lines. Run its `.test.sh` with a row asserting the line prints exactly once.
- [x] 4.2 ADR-278 2026-11-18 addendum "Re-measure trigger": the command and the verdict-to-action table (AC5).

## Phase 5 — Measure (after 2026-11-21T23:14Z and #12897 merged)

- [x] 5.1 Run `bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh 0.3.328 --out <scratchpad>/verdict-0.3.328.json --markdown <scratchpad>/records` via a run_in_background launch or Monitor (never sleep-poll).
- [x] 5.2 Branch on `verdict=`: CACHES / RE-ASKS-AFTER-TEARDOWN / MIXED / INCONCLUSIVE (one re-run) / UNVERIFIED / REFUSED / LEAK / ERROR, per plan Phase 5.
- [x] 5.3 Write `## Addendum — <run date> (#12906): ...` in ADR-278 with the CLO verbatim wording (AC8-AC10).
- [x] 5.4 Check the drafts against the redaction list, then `gh issue comment 12906 --body-file <file>` (AC11). File the conditional issues (AC12).

## Phase 6 — Verification

- [ ] 6.1 Both vitest suites; both `.test.sh` suites; `tsc --noEmit`.
- [ ] 6.2 `git diff --quiet origin/main...HEAD -- apps/web-platform/package.json apps/web-platform/package-lock.json` (AC6); pin and `MEASURED_BASELINE.version` still 0.3.321 (AC13).
- [ ] 6.3 `python3 scripts/lint-guard-contract.py <plan>`.
