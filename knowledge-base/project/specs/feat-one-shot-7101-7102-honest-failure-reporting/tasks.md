---
title: "Tasks — fix(dev-infra): two steps that report success they did not achieve"
branch: feat-one-shot-7101-7102-honest-failure-reporting
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-31-fix-honest-failure-reporting-hook-timeout-and-orphan-reaper-plan.md
closes: [7101, 7102]
---

# Tasks

Derived from plan **v3** (post 4-agent review). Phase order is load-bearing: each guard
must be observed **RED** before its fix.

## Phase 0 — Preconditions

- [x] **0.1** Re-run the asymmetry sweep over
      `apps/web-platform/test/server/*.tenant-isolation.test.ts`; confirm the same **4**
      violations on current `HEAD` (`workspace-member-revocation`,
      `byok-delegation.atomicity`, `byok-delegations`, `conversation-visibility`).
- [x] **0.2** Confirm by **content anchor**, not line number
      (`cq-cite-content-anchor-not-line-number`):
  - [x] **0.2.1** `_rm_errno()` exists in `worktree-manager.sh` and maps
        `"Permission denied"` → `EACCES`.
  - [x] **0.2.2** The `LC_ALL=C rm … 2>&1 >/dev/null` capture idiom and its explanatory
        comment.
  - [x] **0.2.3** The trailing `[[ "$verbose" == "true" ]] && echo` at the tail of
        `cleanup_orphan_worktree_dirs` (this is defect 3).

## Phase 1 — RED for #7101 (guard before fix)

- [x] **1.1** Create `apps/web-platform/test/tenant-isolation-hook-budget-symmetry.test.ts`.
- [x] **1.2** Primary rule (needs no global value): *if `beforeAll` has an explicit
      override, `afterAll` MUST have an explicit override ≥ it.* All 4 of today's
      violations are caught by this alone — make it the load-bearing assertion.
- [x] **1.2b** For the residual case only (`beforeAll` absent, `afterAll` explicit), read
      the global by **importing** `vitest.config.ts` and reading `config.test.hookTimeout`
      — do NOT parse the file (a loose regex matches the comment containing the literal
      text `20_000ms hookTimeout`). NOTE: that module is **not** side-effect-free — it
      does a top-level `process.env.WEBPLAT_TEST_USE_THREADS` read (`:14-15`). Importing
      is safe (a read, and `unit` pins `isolate: true`), but if the transitive
      `vitest/config` import proves heavy or brittle, fall back to a hardcoded `20_000`
      **plus** a parity assertion — never silently hardcode.
- [x] **1.3** Pair `beforeAll`/`afterAll` to their closing `}, <n>);` **structurally**
      (matching indentation), never by grepping the literal — per-test timeouts share the
      `}, 60_000);` form.
- [x] **1.4** **Strip `_` before `Number()`.** `Number("60_000")` is `NaN`;
      `parseInt("60_000")` is `60`. Both silently break the guard.
- [x] **1.5** Assert `afterAll` budget ≥ `beforeAll` budget per `describe` scope.
- [x] **1.6** Anti-vacuity — coverage floor: matched files > 0, **every** matched file
      yields ≥ 1 hook pair, total pairs ≥ total files. No hardcoded census constant.
- [x] **1.7** Anti-vacuity — in-suite parser mutation case: feed a synthetic asymmetric
      fixture string, assert the parser reports a violation.
- [x] **1.8** Comment the guard: symmetry is a deliberate proxy (a lower bound), and the
      known false-positive is a heavy setup with a genuinely trivial teardown.
- [x] **1.9** **Run it. MUST fail with exactly 4 violations.** A run reporting 0 means the
      parser is broken, not that the code is clean. Do not proceed until RED is observed.

## Phase 2 — GREEN for #7101

- [x] **2.1** `workspace-member-revocation.tenant-isolation.test.ts` — `afterAll` closer
      `})` → `}, 60_000);`, with a comment recording: 11 sequential remote round-trips, 3
      of them `deleteUser` under `withGoTrueRetry` (5 attempts, ≈14.25s of sleep = **71%
      of a 20s budget**, leaving ~5.75s for 11 round-trips).
      **Do not write "exceeds 20s" — that claim is false.**
- [x] **2.2** `byok-delegation.atomicity.tenant-isolation.test.ts` — `afterAll` `30_000` → `60_000`.
- [x] **2.3** `byok-delegations.tenant-isolation.test.ts` — `afterAll` `30_000` → `60_000`.
- [x] **2.4** `conversation-visibility.tenant-isolation.test.ts` — `afterAll` `30_000` → `60_000`.
- [x] **2.5** Do **not** touch `apps/web-platform/vitest.config.ts`.
- [x] **2.6** Re-run the guard → green, with the coverage floor still asserting.

## Phase 3 — RED for #7102 (suite before fix)

- [x] **3.1** Create `plugins/soleur/skills/git-worktree/test/orphan-reaper-honest-count.test.sh`,
      copying the harness idiom from the sibling `stale-lock-sweep.test.sh`
      (`set -uo pipefail`, `REPO_ROOT` via `BASH_SOURCE`, `source "$WM"` then `set +e`,
      `PASS`/`FAIL` counters).
- [x] **3.2** Preflight: `[[ $EUID -eq 0 ]]` → `SKIP` (root ignores permission bits, so
      the unremovable fixture cannot be constructed).
- [x] **3.3** Preflight: non-GNU `rm` strerror → `SKIP`.
- [x] **3.4** Case 1 — one temp `WORKTREE_DIR` with {plain orphan, registered worktree,
      orphan-with-`.git`}; one invocation; assert `orphans_cleaned == 1` and the other two
      survive.
- [x] **3.5** Case 2 (**RED**) — unremovable orphan via `chmod 500` on an inner dir;
      assert `orphans_cleaned == 0`, sentinel on **stdout**, dir survives, the failure
      summary prints at `verbose=false`, **and no `Removed orphan directory: <name>` line
      is emitted for the surviving dir** (the third lying surface — verified live today
      to print falsely).
- [x] **3.5b** Harness cleanup: case 2 leaves a `chmod 500` directory, which defeats the
      `trap 'rm -rf "$TMP"' EXIT` cleanup. `chmod -R u+rwX "$TMP"` before the trap fires
      (or at the top of the trap) or the suite litters `/tmp` on every run.
- [x] **3.6** Case 3 — counter integrity: `orphans_cleaned` equals a `find`-verified
      removal delta.
- [x] **3.7** Case 4 (**RED — defect 3**) — assert `rc == 0` for all of:
      (cleaned≥1, verbose=false), (cleaned≥1, verbose=true), (failed, verbose=false).
      The harness has no `set -e`, so the return code MUST be asserted explicitly.
- [x] **3.8** Anti-vacuity parity: assert a **minimum PASS count** before exiting 0, so a
      preflight `SKIP` cannot masquerade as coverage.
- [x] **3.9** **Run it. Cases 2, 3, and 4 MUST fail** against current code.

## Phase 4 — GREEN for #7102

- [x] **4.1** In `cleanup_orphan_worktree_dirs`, replace the unchecked `rm -rf` with the
      status-checked `if rm_err=$(LC_ALL=C rm -rf -- "$dir" 2>&1 >/dev/null); then` form,
      copying the explanatory comment (redirection order + locale pin), not just the idiom.
- [x] **4.2** Increment with the assignment form `orphans_cleaned=$(( orphans_cleaned + 1 ))`
      — never `(( orphans_cleaned++ ))` (rc 1 at old value 0 → `set -e` abort).
- [x] **4.2b** Move the per-directory `Removed orphan directory: <name>` line **inside the
      success branch**. Verified live: it currently prints for a directory the `rm`
      failed to remove, so it is a **third** lying surface alongside the counter and the
      summary. All three must be corrected together.
- [x] **4.3** Collect failures into `orphans_failed=()`.
- [x] **4.4** Emit `SOLEUR_ORPHAN_UNREMOVABLE dir=… errno=… reason=rm-partial hint="…"`
      on **stdout**. Use `reason=rm-partial` (not `rm-failed`) — `rm -rf` deletes what it
      can before failing, so the survivor is a hollow shell.
- [x] **4.5** The hint MUST name `git-worktree SKILL.md §Sharp Edges`. It MUST NOT contain
      a `docker run` string — that form is a verified `guardrails:block-rm-rf-worktrees`
      bypass, and this stream is what agents grep.
- [x] **4.6** Print the failure summary **unconditionally**; keep the success summary
      verbose-gated.
- [x] **4.7** Add an explicit **`return 0`** as the function's final statement (defect 3).
- [x] **4.8** Re-run the suite → green (all 4 cases).

## Phase 5 — Docs and deferrals

- [x] **5.1** `plugins/soleur/skills/git-worktree/SKILL.md` — Sharp Edge covering
      root-owned Supabase bind-mount residue, the partial-deletion (hollow shell) state,
      and the manual remediation. Body prose only; do NOT touch `description:`.
- [x] **5.2** File tracking issue: **EACCES escalation done safely** (opt-in default,
      code-enforced surface predicate, positive object-class predicate, exec-form
      `docker run` with no `sh -c`, charset validation, mount-the-target-not-the-parent,
      digest pin, `timeout 5 docker info`, local-socket assertion, live-stack
      precondition, `docker-killed-mid-rm` state, the ADR + ADR-081 §Alternatives (ii)
      pointer).
- [x] **5.3** File tracking issue: **`guardrails:block-rm-rf-worktrees` does not match the
      containerized form** (verified: plain MATCH, docker-wrapped NO MATCH). Pre-existing;
      not widened by this PR.
- [x] **5.4** File tracking issue: **producer-side fix** — the local Supabase stack
      bind-mounts as root and has no teardown path.
- [x] **5.5** Confirm `decision-challenges.md` is committed so `ship` renders UC-1/UC-2
      into the PR body and files the `action-required` issue.

## Phase 6 — Exit gate

- [x] **6.1** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
      (**not** `npm run -w …` — the repo root declares no `workspaces` field).
- [x] **6.2** `cd apps/web-platform && ./node_modules/.bin/vitest run test/tenant-isolation-hook-budget-symmetry.test.ts`
- [x] **6.3** `bash plugins/soleur/skills/git-worktree/test/orphan-reaper-honest-count.test.sh`
- [ ] **6.4** `TEST_GROUP=scripts bash scripts/test-all.sh` — catches regressions in the 4
      sibling git-worktree suites.
- [ ] **6.5** Record the mutation proofs in the PR body: revert one `60_000` → guard
      fails with exactly 1 violation; restore the unconditional increment → 7 assertions
      fail including counter-integrity.
      **CORRECTED at /work — the third proof as written is FALSE.** "Remove the explicit
      `return 0` → case 4 fails" was measured and the mutation **SURVIVED** (20/20 green).
      The new unconditional failure-summary block now ends the function on a
      zero-returning construct, so `return 0` is defence-in-depth, not the mechanism.
      Case 4 is a **contract** test (rc=0 on every path), not a `return 0`-presence test.
      The mutation that DOES fire is re-introducing the real defect shape — appending a
      trailing `[[ "$verbose" == "true" ]] && echo` as the last statement — which fails
      all 3 rc paths. Record that one instead.
- [ ] **6.6** Confirm `tenant-integration-required` is green on the PR (the 4 edited files
      match the workflow's changed-path anchor, so the dev-Supabase suite runs — that
      check going green is the deliverable of #7101).
- [ ] **6.7** PR body uses `Closes #7101` and `Closes #7102`.
