---
title: "test(web-platform): F21 real-git flake root cause, and real-git url-rewrite rows at both git-data entry points"
date: 2026-11-11
slug: test-f21-flake-root-cause-and-url-guard-entry-point-real-git
branch: feat-one-shot-9601-f21-flake-url-guard-real-git
issue: 9601
closes: none
type: test
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain # Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).
---

# test(web-platform): F21 real-git flake root cause, and real-git url-rewrite rows at both git-data entry points

## Overview

A test-hardening follow-up to the host-side git consumers hardening (merged as cc8cd89302, Ref #9601). It has three parts:

1. **F21 flake.** Find and fix the root cause of the intermittent failure of the row "F21: the local rescue branch is
   deleted after the confirmed push, the store ref remains, a second replicate pushes no rescue" in the real-git describe
   of `apps/web-platform/test/git-data-replication.test.ts`. The cause is measured below. The trigger is the production
   command (a no-op push carrying push options) meeting git's send-pack; it is **reproduced only on the fake transport's
   direct pipe**, and the exposure over the production ssh carrier is unmeasured (CTO R6). The fix is in the fake.
2. **Entry-point rows for the url/remote rewrite guard.** A new real-git test file, with no `child_process` mock, that
   drives the two production call sites of `assertNoUrlRewrite` (`replicateToGitData` and `fetchFromGitData`) against
   two local bare stores, A (the workspace's own) and B (another tenant's). `assertNoUrlRewrite` has **two** production
   call sites on `main`, not three: `server/git-data-replication.ts` (in `replicateToGitData`, before the push) and
   `server/git-data-client.ts` (in `fetchFromGitData`, before the fetch).
3. **Mutant re-runs.** Mutant N6 (the push-side guard removed) re-run serially after the fix, with the killing
   assertions named and F21 shown absent from the RED list; three mutants re-run against the existing workspace and
   context-queries real-git rows (no new rows unless one survives).

The PR is test-only. No production file changes. `Ref #9601` in the PR body only, no closing keyword, no issue filed.

## Research Insights

### Premise Validation

Checked on 2026-11-11: #9601 OPEN (epic; never closed or edited here). #12626 OPEN and #11556 OPEN (known main-red
mutation-battery timeout noise; not fixed here). #9826 and #11640 OPEN (operator holds; untouched). Draft PR #12655 is
this branch's own PR. `collision-precheck.sh 9601`: the only open change naming #9601 is #12655 (ours); six foreign
`test-all.sh` processes from another worktree were running, which raises host load (load average 7.7-10.3 during the
planning measurements) and is recorded as the measurement condition. Every cited file and symbol exists on this tree:
`replicateToGitData`, `fetchFromGitData`, `assertNoUrlRewrite` / `GitDataUrlRewriteError`
(`server/git-data-url-guard.ts`), `gitDataPushRefspecs`, `gitDataFetchRefspecs`, `gitDataRemoteUrl`, the F21 row, and the
three item-5 mutant anchors (verified by grep, below). Nothing stale.

### Baseline measurement (unmodified tree, planning phase)

Command (from `apps/web-platform`, isolated row, one vitest process per run):

```bash
for i in $(seq 1 N); do npx vitest run test/git-data-replication.test.ts -t "F21: the local rescue branch is deleted" > log-$i 2>&1; echo "run $i rc=$?"; done
```

| Sample | Failures | Rate |
|---|---|---|
| runs 1-30 | 2 (runs 3, 21) | 6.7% |
| runs 31-130 | 1 (run 106) | 1.0% |
| **total 130** | **3** | **2.3%** |

Host: git 2.56.0, vitest 4.1.12, load average 7.7-10.3. PR #12512's body recorded about 4 of 12 on its host.

**Failing assertion, identical in all three failures:** `test/git-data-replication.test.ts:1294:28`,
`await expect(second.out).resolves.toEqual({ status: "replicated" })` →
`AssertionError: promise rejected "Error: Command failed: git push { stderr: '' }" instead of resolving`, thrown from
`pushWithRetry` (`server/git-data-replication.ts:871`) via the test's `gitWithPrivateKeyAuth` fake. That is the **second**
replicate's main push. It is a no-op push: `main` is already in the store and the rescue branch was deleted. It fails
with **empty stderr**, and empty stderr does not match the transient regex, so it is not retried.

### Root cause (measured, then confirmed in git's source)

- **Shell reproduction** of the exact F21 git sequence (file:// bare store with `receive.advertisePushOptions true`, the
  production refspecs, two `--push-option`s): 1 of 200 sequences failed. The no-op push exited **141 (SIGPIPE)** with
  empty stderr.
- **Differential, 1000 no-op pushes per arm, same store:** with push options 2 failures; **without push options 0**;
  250 changing pushes with options 0. Only a push that has nothing to update **and** carries push options fails.
- **Mechanism (`git/send-pack.c`, master):** with no commands, `req_buf` holds a flush packet followed by the push-option
  packets. It is written with `write_or_die(out, req_buf.buf, req_buf.len)` and then a **separate** `packet_flush(out)`.
  `send_pack` has no early return when `cmds_sent == 0`. `receive-pack` reads the first flush, finds no commands, never
  reads the push options, and exits. If it exits before the client's trailing `packet_flush` write, the client gets EPIPE,
  which git turns into SIGPIPE: rc 141 and no message.
- **Why the fix goes in the fake (reproduced only on the fake's direct pipe; exposure over ssh unmeasured):** the fake transport at "the authenticated transport: the production push argv,
  run by real git against the local store" connects the client pipe **directly** to a local `receive-pack`. Production
  writes into a pipe owned by ssh, which keeps reading its stdin until the remote exit comes back. That narrows the window,
  but **the ssh path was not measured** (see R6 and "Not measured").
- **Candidate fix A, measured:** an ssh-like intermediary as the fake's receive-pack,
  `sh -c 'git-receive-pack "$0"; s=$?; exec >/dev/null; cat; exit $s'`, keeps the pipe's read end open, drains it, and
  closes its own stdout so the client sees EOF. 1500 no-op pushes with push options gave **0** failures. The F20
  rejection shape still behaves the same through the wrapper (shell, store holds `heads/fix/x`, local `fix`): plain
  rc=1 with the `rejected` line and `main` landed; drained rc=1 with the `rejected` line and `main` landed. With the
  wrapper ending in `exit 0` instead of `exit $s` the result is the same (rc=1, measured by the lead and by two review
  seats): git push takes a rejected ref from receive-pack's status report, so `exit $s` is realism, not load-bearing.
- **Consequence stated plainly:** with the wrapper in place, F21 can no longer detect this race even if production starts
  hitting it; the production signal is a `git_data_replication_push` report with empty stderr (see Observability).

Scratch scripts (uncommitted, planning only):
`/tmp/claude-1000/-data-git-repositories-jikig-ai-soleur/adb98dcc-50c3-43ae-81b6-2db5bb2b99d6/scratchpad/repro/{f21.sh,noop.sh,drain.sh,reject.sh,carriers.sh}`.
The work phase rewrites what it needs rather than depending on them.

### Carrier measurements (planning phase, shell, git 2.56.0)

The fake transport routes the git-data URL with `-c url.file://<root>/stores/.insteadOf=ssh://git@10.0.1.20/mnt/git-data/repositories/`.
A planted workspace-config carrier must beat that shorter prefix (git takes the longest matching `insteadOf`):

| Carrier planted in the workspace config | Push (production argv, no guard) | Fetch (production argv, no guard) |
|---|---|---|
| `url.file://<B>.insteadOf <full git-data URL>` | lands in B, A untouched | B's ref lands in `refs/remotes/git-data/*` |
| `[remote "<git-data URL>"] pushurl = file://<B>` | lands in B, A untouched | **nothing from B lands** (pushurl is not a fetch carrier): the fetch goes to the git-data URL, which the fake routes to **A**, so A's `refs/remotes/git-data/main` lands (re-measured by the DHH review seat, 2026-11-11: rc=0) |
| `[remote "<git-data URL>"] url = file://<B>` | not measured (fetch-side carrier) | B's ref lands |

`assertNoUrlRewrite` refuses every one of these shapes: any `url.*` key, and any `remote.<name>.*` key whose name is
URL-shaped (`/[/:@]/`).

### N6 definition (recovered)

N6 is not defined anywhere in the repository. It comes from the earlier session's uncommitted battery
(`serial.py` / `lead.out` in that session's scratchpad, 2026-11-10 12:27):
`mut("N6 no url guard on push (lead, T4)", "server/git-data-replication.ts", "    assertNoUrlRewrite(workspacePath);\n    const pushTarget", "    const pushTarget")`.
`lead.out` recorded `SURVIVED N6 no url guard on push pass= 217 anchors= 1` on the run set
T4 = `test/host-git-consumers-real-git.test.ts`, `test/host-git.test.ts`, `test/git-data-replication.test.ts`,
`test/git-auth.test.ts`. In the same output, the RED lists of other mutants (N2, N7) include the F21 row, so the flake
contaminated kill attribution in that battery. The PR body later reports 39/39 killed, including "no `url.*` guard on the
push". The work phase does not rely on that scratchpad (it may be gone); the anchor is restated here and verified present
(`server/git-data-replication.ts`, the line `    assertNoUrlRewrite(workspacePath);` directly before
`    const pushTarget = gitDataRemoteUrl(workspaceId);`).

### Item-5 mutant anchors (verified present on this tree)

- **WS1, shape check removed:** `server/workspace.ts`, `    assertWorkspaceGitShape(workspacePath); //` → `    //`.
- **WS3, pinned init:** `server/workspace.ts`, `...(pin ? { cwd: workspacePath } : {})` → `cwd: workspacePath`.
- **CQ1, ls-files without cwd:** `server/context-queries-hook.ts`,
  `{ cwd: repoRoot, allowProtocol: ALLOW_PROTOCOL_NONE }` → `{ allowProtocol: ALLOW_PROTOCOL_NONE }`.

Existing rows they should hit (predictions, verified in Phase 5, not claimed here): `test/workspace.test.ts` "a fresh
workspace ends up with a real .git directory that git resolves" and "re-provisioning a workspace whose .git is a gitfile
naming another repository leaves that repository untouched"; `test/context-queries-hook.test.ts` "a gitfile .git naming
another repository is refused: reported once as git-refused, ...".

### Relevant files

- `apps/web-platform/test/git-data-replication.test.ts`: the real-git describe "replicateToGitData — real git store (F20
  per-ref main push, F21 rescue-branch delete)"; its `gitPush.mockImplementation` is the fake transport. The file mocks
  `child_process` (pass-through to real git, but with the env **replaced** by `gitFixtureEnv(root)`).
- `apps/web-platform/server/git-data-replication.ts`: `replicateToGitData` (provision → `ensureGitDataRemote` →
  `assertNoUrlRewrite` → rescue listing → step-1 rescue push → delete → step-2 main push); the refusal catch reports
  `op: "git_data_replication_refused"` and rethrows.
- `apps/web-platform/server/git-data-client.ts`: `fetchFromGitData` (authorize → key → URL → pin → `assertNoUrlRewrite`
  → `gitWithPrivateKeyAuth(["fetch", "--update-shallow", URL, heads, negativeRescue, tags])`); it emits no report of its
  own on a refusal (the caller, ensure-workspace-repo, owns that).
- `apps/web-platform/server/git-data-url-guard.ts`: the guard (a preflight, not a structural control; its header says so).
- `apps/web-platform/test/host-git-consumers-real-git.test.ts`: existing `assertNoUrlRewrite` rows with raw-git controls
  (direct guard calls, not the entry points). Untouched.
- `apps/web-platform/test/repo-wide-suites.ts`: suites that import outside the app (`plugins/soleur/test/lib/git-fixture-env`)
  must be listed; `test/repo-wide-containment.test.ts` recomputes the list from disk.
- `plugins/soleur/test/fixture-env-adoption.test.sh`: every test file spawning a mutating git must take its env from the
  shared fixture-env helper.

### Institutional learnings applied

- `knowledge-base/project/learnings/test-failures/2026-09-30-stub-drain-fidelity-and-endpoint-keyed-sweeps.md` and
  `.../2026-10-05-a-reader-that-exits-early-flipped-three-suites-and-the-stub-had-to-read-too.md`: a peer that exits
  without reading its stdin races its writer into EPIPE; the fix is a peer that drains. Same shape as here.
- `knowledge-base/project/learnings/2026-07-28-a-ten-run-sample-said-unreachable-and-the-defect-was-live-at-two-percent.md`:
  state the power of a clean-run count. At p = 2.3%, P(20 clean | unfixed) ≈ 0.63; P(200 clean | unfixed) ≈ 0.01.
- `knowledge-base/project/learnings/test-failures/2026-11-03-a-mutation-row-that-depends-on-a-race-needs-a-forced-path-not-more-runs.md`:
  a race is not proven by run counts alone; here the mechanism is proven by the differential stress (with vs without the
  wrapper) and by git's source, not by the 200-run count alone.
- `knowledge-base/project/learnings/test-failures/2026-09-25-the-flake-was-sigpipe-at-4kib-and-my-fix-leaked-a-pipe-status-through-a-bare-return.md`:
  a load-amplified run (parallel copies) raises a SIGPIPE race's rate when a single stream is too quiet to measure.
- `knowledge-base/project/learnings/2026-08-19-my-battery-reverted-the-fix-it-was-testing.md` and
  `.../workflow-patterns/2026-05-29-git-checkout-revert-clobbers-uncommitted-sibling-edits-during-mutation-testing.md`:
  restore a mutated file from a pristine copy, never `git checkout --`; commit before a battery; end every battery with
  `git status --short`.
- `knowledge-base/project/learnings/2026-11-10-a-redirect-guard-was-widened-one-level-at-a-time-and-reviewed-into-the-class-in-two-rounds.md`:
  derive the pristine-file list from the mutant table; a control must be run against its own negative once; grep tests
  that anchor on a file's source text before editing it.
- `knowledge-base/project/learnings/2026-10-04-a-new-suite-is-invisible-to-repo-ratchets-until-tracked-and-my-fix-moved-the-event-behind-a-hang.md`:
  repo ratchets read `git ls-files`; run them after the new file is tracked (`git add`).

### Property List (Phase 0.6b)

1. P1: the F21 row's outcome depends only on the code under test, never on a transport race in the test's fake.
2. P2: a planted `url.<B>.insteadOf` or a remote named by the git-data URL makes `replicateToGitData` refuse before any
   git transport call, with B and A unchanged and exactly one `git_data_replication_refused` report.
3. P3: the same carriers make `fetchFromGitData` refuse before the fetch, with no ref and no object from B landing in the
   workspace.
4. P4: each refusal row is non-vacuous: its carrier is shown live by raw git in the same row (or, for pushurl on fetch,
   shown NOT to be a fetch carrier), and the fake transport is shown to work by a positive row.
5. P5: kill attribution for N6, GC1 and the item-5 mutants is free of the flake.

### Cut List (Phase 0.6b)

- A production change for the no-op-push race (retry class, dry-run pre-push) → P1 is a test property, and the
  production retry gate makes the worst case a loud false alarm, not loss → cut (CTO R6).
- Making the F21 second replicate non-no-op → P1 is bought by fix A without dropping the only real-git no-op coverage →
  cut (CTO R1).
- A committed amplifier row (looping no-op pushes) → P1's evidence comes from the uncommitted stress and the 200-run
  measurement → cut (CTO R2).
- New rows in `workspace.test.ts` / `context-queries-hook.test.ts` → existing real-git rows already cover the property;
  mutant re-runs decide → cut unless a mutant survives (scope item 5).
- Editing `host-git-consumers-real-git.test.ts` → its direct-guard rows and controls stay as they are → cut (CTO R5).

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief | Reality | Plan response |
|---|---|---|
| "Find the N6 definition in the mutation-battery config/learning" | Not in the repo; only in the earlier session's uncommitted scratch (`serial.py`, `lead.out`) | Restate the anchor in this plan (above) and in `measurements.md`; do not depend on the scratchpad |
| "Repeat with `[remote "<url>"] pushurl = <B>`" for fetchFromGitData | `pushurl` does not redirect a fetch (measured: nothing lands) | Fetch gets `remote.<URL>.url` as its control-backed remote-name row, plus a pushurl refusal row with an INVERTED control (CTO R3) |
| "exactly one report with op git_data_replication_refused" | True for `replicateToGitData`; `fetchFromGitData` emits no report | Fetch rows assert `reportSilentFallback` not called by `fetchFromGitData` (CTO R4) |
| "no transport call" | `replicateToGitData` dials the (mocked) provision ssh **before** the guard by design | "No transport call" means `gitWithPrivateKeyAuth` is never called; the provision mock may be called and the row says so |
| "Keep the existing raw-git control proving the carrier works" | Existing controls are in `host-git-consumers-real-git.test.ts` (direct guard calls) | Keep them untouched; every new control-backed row carries its own in-row raw-git control (CTO R5) |
| ">=20 runs with 0 failures" | Non-discriminating at p = 2.3% | Floor kept; add >=200 isolated runs, the K=1000 differential stress and >=20 whole-file runs (CTO R2) |

## Files to Edit

- `apps/web-platform/test/git-data-replication.test.ts`: in the real-git describe, the `gitPush.mockImplementation` fake
  transport calls the shared local-transport helper (below) instead of its inline `realExec`. Nothing else in the file
  changes: no assertion, no row, and the F21 row's second, no-op replicate stays exactly as it is.
- `apps/web-platform/test/repo-wide-suites.ts`: add `"test/git-data-url-guard-entry-points-real-git.test.ts"` in
  sorted position.

## Files to Create

- `apps/web-platform/test/helpers/git-data-local-transport.ts`: the fake git-data transport, defined once (CTO R1). It
  exports the drain wrapper constant `DRAINING_RECEIVE_PACK` and `runGitDataLocal(args, { cwd, storesRoot, env })`, which runs `git` with
  `-c url.file://<storesRoot>/.insteadOf=ssh://git@10.0.1.20/mnt/git-data/repositories/` before the production argv and,
  **only when `args[0] === "push"`**, splices `--receive-pack=<drain wrapper>` right after `push`. The env is injected by
  the caller (`gitFixtureEnv(root)`), as `test/helpers/host-git-carrier-fixture.ts` does. On failure it throws
  `Object.assign(new Error("Command failed: git push\n" + stderr), { stderr })` exactly as the inline fake does today, so
  F20's `/Command failed: git push/` and the production retry regex see the same shape. A comment states the measured
  cause (send-pack's trailing flush after a command-less request, SIGPIPE rc 141) and that the wrapper models an ssh-like
  intermediary but is not ssh.
- `apps/web-platform/test/git-data-url-guard-entry-points-real-git.test.ts`: the entry-point rows (Phase 4). No
  `child_process` mock. Mocks only `@/server/git-auth` (`gitWithPrivateKeyAuth` → `runGitDataLocal`, `sshWithPrivateKeyAuth`
  → resolved no-op), `@/lib/supabase/tenant` (membership rpc → `true`) and `reportSilentFallback` (partial mock of
  `@/server/observability`, keeping `hashUserId` / `warnSilentFallback` real). Fixture-side git uses `gitFixtureEnv(root)`.
- `knowledge-base/project/specs/archive/20261112-002843-feat-one-shot-9601-f21-flake-url-guard-real-git/measurements.md`: the baseline, the
  stress, the post-fix counts with load averages, and the mutant table with killing assertions.

## Implementation Phases

### Phase 0: Preflight

- 0.1 `git --version` ≥ 2.38 (record it; host is 2.56.0). The negative fetch refspec needs ≥ 2.29.
- 0.2 Tree clean (`git status --short` empty). Record `uptime` (load) before each measurement block.
- 0.3 `git grep -l "git-data-replication.test" -- ':!knowledge-base'` and confirm no suite anchors on the text this PR
  edits (planning found only prose references in `git-data-stale-clone-push.test.sh`, `account-delete.test.ts`,
  `git-config-atomic.test.ts`, `git-data-reporter-line-parity.test.ts`).

### Phase 1: Real-git falsifier first (mechanism, uncommitted)

- 1.1 Scratch stress (CTO R2b), in the scratchpad, not committed: build a store and a workspace exactly as the real-git
  describe does, push once so `main` is in the store, then run **K=1000 no-op pushes** of the production step-2 argv
  (`push --force <git-data URL> <heads refspec> <tags refspec> --push-option=lease-gen=1 --push-option=worktree-id=<WT>`)
  through the fake's `-c url...insteadOf` prefix, **without** the drain wrapper. Count non-zero exits and record each
  exit code. **Bar: a nonzero count, with exit code 141.** If K=1000 gives 0 (expected about 2 at the shell rate; P(0) ≈
  0.14), raise to K=5000 or run 10 parallel copies (the load-amplification learning) and record which was needed.
- 1.2 Re-run the baseline F21 isolated loop for ≥ 20 runs on the unmodified tree if the host load differs materially from
  the planning measurement, so the before/after pair is at a comparable load.

### Phase 2: The fix (CTO R1)

- 2.1 Create `test/helpers/git-data-local-transport.ts` as specified.
- 2.2 In `test/git-data-replication.test.ts`, replace the inline `realExec("git", ["-c", ..., ...args], ...)` in the
  real-git describe's `gitPush.mockImplementation` with `runGitDataLocal(args, { cwd: opts.cwd, storesRoot: path.join(root, "stores"), env: gitFixtureEnv(root) })`.
  The compare-and-delete row wraps `getMockImplementation()`; it keeps working because it wraps the same mock.
- 2.3 Stress again with the wrapper (CTO R2b): the same K as 1.1 (and the same parallelism, if it was needed). **Bar: 0.**
- 2.4 F20 still holds with the wrapper (CTO R1 precondition): the F20 row passes (main lands, the call rejects with
  `/Command failed: git push/`, exactly one `git_data_replication_push` report, no success marker). Run it ≥ 5 times.

### Phase 3: Post-fix measurement (CTO R2)

- 3.1 ≥ 200 isolated runs of the F21 row, same command as the baseline. **Bar: 0 failures.** Record the load average at
  start and end; if it is not comparable to 7.7-10.3, label the result "measured at load <x>" (CTO R2 dissent).
- 3.2 ≥ 20 runs of the whole `test/git-data-replication.test.ts` file. **Bar: 0 failures** (F20 and compare-and-delete run
  beside F21).
- 3.3 Record all counts, rc values and loads in `measurements.md`. State the power honestly: 200 clean runs at a 2.3% base
  rate leave about a 1% chance of an unfixed race passing; the mechanism proof is the 1.1 / 2.3 differential plus git's
  source, not the count alone (CPO condition 4).

### Phase 4: Entry-point rows (new file, CTO R3-R5)

Fixture per row (`beforeEach`): `root = mkdtemp`, store A = `<root>/stores/<WS>.git` (bare, `receive.advertisePushOptions
true`), store B = `<root>/other/b.git` (bare, same option), workspace = `<root>/ws` (non-bare, `-b main`, one commit). All
data is synthesized: ids like `ws-uuid-123` and a worktree id of `5`s, no real tenant URL or key (`cq-test-fixtures-synthesized-only`).
Env stubs: `GIT_DATA_STORE_ENABLED=true`, `GIT_TRANSPORT_SSH_PRIVATE_KEY` / `GIT_PROVISION_SSH_PRIVATE_KEY` set to dummy
strings, `GIT_DATA_SSH_HOST_KEY` = `makeEd25519Pin()`; `GIT_DATA_SSH_HOST` unset so the URL is the non-prod default
`ssh://git@10.0.1.20/mnt/git-data/repositories/<WS>.git`. A `state(bare)` helper returns `for-each-ref` output plus
`count-objects -v` (`count` + `in-pack`), so "unchanged" compares refs **and** objects.

**describe "replicateToGitData — url/remote rewrite carriers, real git (A = own store, B = another tenant)"**

- R-PUSH-0 positive / must-PASS non-canonical input: the workspace also carries ordinary `origin` and `upstream`
  remotes and `remote.pushDefault=upstream` (not rewrites). `replicateToGitData` resolves `{ status: "replicated" }`;
  `refs/soleur/worktrees/<WT>/heads/main` in A equals the workspace's `main`; B's state unchanged; no
  `git_data_replication_refused` report. Proves the push fake works and that the guard does not refuse ordinary state.
- R-PUSH-1 `url.file://<B>.insteadOf <git-data URL>`:
  1. control: `runGitDataLocal(<production step-2 argv>)` called directly (not through the mock) lands
     `refs/soleur/worktrees/<WT>/heads/main` in **B** and leaves A unchanged; the row FAILS with "control: the insteadOf
     carrier is not live" if it does not (an `expect(..., msg)`, never a skip);
  2. **make the leak observable again**: commit once more in the workspace (`commit --allow-empty -m after-control`), so
     a push that leaked past the guard would MOVE B's ref to the new sha. Without this step the control has already put
     the workspace's `main` into B, a leaked push is a no-op, and "B unchanged" is vacuous (advisor consult 2026-11-11).
     Then `mockClear()` the transport and report mocks, and capture `state(A)` and `state(B)`;
  3. `replicateToGitData(...)` rejects with an instance of `GitDataUrlRewriteError`;
  4. `gitWithPrivateKeyAuth` mock called 0 times; the provision mock called exactly once (the row really went through the
     production order: provision, `ensureGitDataRemote`, guard); `git config --get remote.git-data.url` in the workspace
     still equals the canonical URL (`ensureGitDataRemote` writes it literally; the carrier is beside it, not in it);
  5. `state(A)` and `state(B)` equal the captured values, and B's ref is NOT the workspace's new `main` sha;
     Phase 5 checks under N6 that THIS assertion goes RED on its own (not only steps 3-4), so the state check is not a
     passenger of the rejection check;
  6. `reportSilentFallback` called exactly once, with `op: "git_data_replication_refused"`; no `git_data_replication_push`;
     the serialized report does not contain B's path (a count, never a key or a value).
- R-PUSH-2 `[remote "<git-data URL>"] pushurl = file://<B>` (plant `remote.<URL>.url = <URL>` as well, the shape measured
  in `host-git-consumers-real-git.test.ts`): the same six steps, control message "control: the remote-name carrier is not live".

**describe "fetchFromGitData — url/remote rewrite carriers, real git"**

Seed: A holds `refs/soleur/worktrees/<WT>/heads/main` (the workspace's commit); B holds
`refs/soleur/worktrees/<WT>/heads/evil` pointing at a commit **created only in B** (so its object is absent from the
workspace and from A).

- R-FETCH-0 positive: no carrier. `fetchFromGitData` resolves; `refs/remotes/git-data/main` lands with A's sha; the
  transport mock was called once. Without this row a broken fetch fake would pass every refusal row (CTO R4 amendment 2).
- R-FETCH-1 `url.file://<B>.insteadOf <URL>`: control (raw production fetch argv through `runGitDataLocal`, no guard)
  lands `refs/remotes/git-data/evil`; then delete the remote-tracking refs, run `git gc --prune=now` in the workspace so
  B's object is gone again, and confirm `cat-file -e <B tip>` fails; capture `state(A)`, `state(B)`. Guarded call:
  rejects instance of `GitDataUrlRewriteError`; transport mock 0 calls; zero `refs/remotes/git-data/*`;
  `cat-file -e <B tip>` fails in the workspace; A and B states unchanged; `reportSilentFallback` not called by
  `fetchFromGitData` (comment: the caller, ensure-workspace-repo, owns the report).
- R-FETCH-2 `[remote "<URL>"] url = file://<B>`: the same, control-backed.
- R-FETCH-3 `[remote "<URL>"] pushurl = file://<B>`: **inverted control**: the raw fetch argv without the guard lands
  **zero** `refs/remotes/git-data/*` (pushurl does not redirect a fetch on git 2.56; if a future git starts honouring it,
  this control fails and the change is noticed). Then the guarded call rejects with `GitDataUrlRewriteError` (the guard
  refuses every URL-shaped remote name) with the same no-transport / no-ref / no-object / no-report assertions.

Then: register the file in `repo-wide-suites.ts`; `git add` it; run `test/repo-wide-containment.test.ts` and
`bash plugins/soleur/test/fixture-env-adoption.test.sh`; run the new file ≥ 5 times (all green).

**Sequencing inside Phase 4 (falsifier first):** write each row's control first and run it alone to see the carrier land
in B (or, for R-FETCH-3, not land), then add the guarded half. The guarded half passes on the unmodified code; its
falsifier is the mutant run in Phase 5 (N6 for the push rows, GC1 for the fetch rows).

### Phase 5: Mutant re-runs (CTO R7)

Uncommitted scratch harness. Commit Phases 2 and 4 first; the harness refuses to start on a dirty tree. For each mutant:
copy the target file to a pristine copy, apply the anchor replacement and assert it matched **exactly once**, run each
listed test file in its own vitest process **serially**, record per-run RED row names, restore from the pristine copy,
assert the file's hash equals the committed one. End with `git status --short` empty.

| Mutant | Target / edit | Run set (serial, 3 reps) | Kill bar |
|---|---|---|---|
| baseline | none | `git-data-replication.test.ts`, the new file | 3/3 green |
| N6 | `server/git-data-replication.ts`: drop `    assertNoUrlRewrite(workspacePath);` before `const pushTarget` | same | 3/3 RED; killers named: the `rejects.toThrow(/refused/)` rows of "replicateToGitData — the url/remote rewrite guard runs before ANY push" and R-PUSH-1, R-PUSH-2; **F21 and every guard-unrelated row absent from the RED list in all 3**, else no kill is claimed; R-FETCH-* stay green |
| N6 on old T4 | same edit | `host-git-consumers-real-git`, `host-git`, `git-data-replication`, `git-auth` tests, once | record the result and explain the difference from the earlier "SURVIVED pass=217" (for example, whether the mocked guard rows existed at 12:27 on 2026-11-10: check the PR #12512 branch commits) |
| GC1 | `server/git-data-client.ts`: drop `  assertNoUrlRewrite(workspacePath);\n` | the new file, `git-data-client.test.ts` | 3/3 RED: R-FETCH-1, R-FETCH-2, R-FETCH-3 (and the mocked client guard row); R-PUSH-* stay green |
| G-DISPATCH | `server/git-data-url-guard.ts`: `if (keys.length > 0) throw new GitDataUrlRewriteError(keys.length);` → `if (false) throw new GitDataUrlRewriteError(keys.length);` | the new file | 3/3 RED: every refusal row on both entry points |
| G-SECOND | `server/git-data-url-guard.ts`: `return name !== undefined && /[/:@]/.test(name);` → `return false;` (only `url.*` refused) | the new file | 3/3 RED: R-PUSH-2, R-FETCH-2, R-FETCH-3; R-PUSH-1 and R-FETCH-1 stay green |
| G-OVER | same file, the same line → `return name !== undefined;` (every remote name refused) | the new file | 3/3 RED: R-PUSH-0 (must-PASS input refused) |
| H-FAKE | `test/helpers/git-data-local-transport.ts`: drop the `-c url...insteadOf` prefix (the fake can no longer reach any store) | the new file, `git-data-replication.test.ts` | 3/3 RED: R-PUSH-0, R-FETCH-0 and every control ("carrier is not live") |
| WS1 | `server/workspace.ts`: `    assertWorkspaceGitShape(workspacePath); //` → `    //` | `workspace.test.ts`, `context-queries-hook.test.ts` | 3/3 RED, killers named |
| WS3 | `server/workspace.ts`: `...(pin ? { cwd: workspacePath } : {})` → `cwd: workspacePath` | same | 3/3 RED, killers named |
| CQ1 | `server/context-queries-hook.ts`: `{ cwd: repoRoot, allowProtocol: ALLOW_PROTOCOL_NONE }` → `{ allowProtocol: ALLOW_PROTOCOL_NONE }` | same | 3/3 RED, killers named |

- 5.1 If WS1, WS3 or CQ1 **survives** (any rep green), add one real-git row to the matching existing file that fails under
  that mutant, re-run the mutant 3 times, and record it. Otherwise add no row (scope item 5).
- 5.2 Any other survivor: stop, read it, and treat it as a gap to close in this PR (a row that discriminates), then re-kill.
- 5.3 Record every row of the table in `measurements.md`: mutant, anchor, run set, per-rep RED row names, verdict.
- 5.4 The PR claims only the mutants run here. It does **not** claim "39/39": the full battery is not re-run.

### Phase 6: Gates on touched files

- 6.1 `npx tsc --noEmit -p apps/web-platform` (or the repo's typecheck script) and the repo's ESLint on the three touched
  test files; the `no-unused-vars` baseline must not grow.
- 6.2 `test/repo-wide-containment.test.ts`, `plugins/soleur/test/fixture-env-adoption.test.sh`, and
  `bash scripts/lint-orphan-test-suites.sh`, all after `git add` of the new files.
- 6.4 Run every literal command this plan prescribes once (the `discoverability_test`, the AC3 diff-stat, the AC10 grep)
  and confirm each returns what the plan says.
- 6.3 Single targeted suites only: `git-data-replication.test.ts`, the new file, `git-data-client.test.ts`,
  `host-git-consumers-real-git.test.ts` (untouched, run once as a neighbour check). Never the full battery (#12626 is
  known main-red noise under #11556 and is not fixed here).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Measure FIRST: run the F21 row >=20 times in isolation on unmodified main, record failure rate + failing assertion." | Research Insights / Baseline measurement (130 runs, 3 failures, line 1294); Phase 1.2 | mapped |
| 2 | "Root-cause fix in test or code; retries/skip/longer timeouts/loosened assertions do NOT count." | Root cause section; Phase 2 (drain intermediary in the fake transport; no assertion changed) | mapped |
| 3 | "Then >=20 runs with 0 failures, recorded." | Phase 3.1-3.3 (>=200 isolated, >=20 whole-file) | mapped |
| 4 | "Re-run mutant N6 serially after the fix; record which assertion kills it and show it is not the flake." | N6 definition; Phase 5 N6 rows | mapped |
| 5 | "Real-git rows for replicateToGitData ... plant `url.<B>.insteadOf <git-data URL>` → rejects with GitDataUrlRewriteError, no transport call, A and B unchanged, exactly one report with op git_data_replication_refused. Repeat with `[remote \"<url>\"] pushurl = <B>`." | Phase 4 R-PUSH-1, R-PUSH-2 | mapped |
| 6 | "Keep the existing raw-git control proving the carrier works." | host-git-consumers-real-git.test.ts untouched; in-row controls in every new control-backed row | mapped |
| 7 | "Same rows for fetchFromGitData ... rejects before fetch, no refs/remotes/git-data/* from B lands. New test file that does NOT mock child_process." | Phase 4 R-FETCH-0..3; Files to Create | mapped |
| 8 | "(assertNoUrlRewrite has TWO production call sites on main, not three — say so.)" | Overview item 2; PR body | mapped |
| 9 | "add NO rows; instead re-run three mutants (shape check removed, pinned init removed, ls-files without cwd) against existing rows and record kills; add a row only if one survives." | Phase 5 WS1, WS3, CQ1; 5.1 | mapped |
| 10 | "Run single targeted suites only, never the full battery." | Phase 6.3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Shared fake-transport helper with drain wrapper | "Root-cause fix in test or code" | asked |
| >=200 isolated runs, K=1000 stress, >=20 whole-file runs | "Then >=20 runs with 0 failures, recorded." | inferred — justification: the >=20 floor is kept; the extra runs are Ruled by CTO agent (R2) because 20 runs cannot discriminate at p=2.3% |
| R-PUSH-0 / R-FETCH-0 positive rows | "no transport call" | inferred — justification: Ruled by CTO agent (R4 amendment 2); without them a broken fake passes every refusal row |
| R-FETCH-2 (`remote.<URL>.url`) and the inverted pushurl control | "Same rows for fetchFromGitData" | inferred — justification: pushurl is not a fetch carrier (measured); Ruled by CTO agent (R3) |
| Mutants GC1, G-DISPATCH, G-SECOND, G-OVER, H-FAKE | "record kills" | inferred — justification: the Guard Contract mutation matrix (own dispatch, second member, harness rows) for the new rows |
| `measurements.md` | "recorded" | asked |
| repo-wide-suites.ts registration | "New test file" | inferred — justification: required by `repo-wide-containment.test.ts` for a suite importing `plugins/soleur/test/lib` |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform/test`, `knowledge-base/project/specs`
- Planned files: 5 | Estimated changed lines: about 400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing at runtime (no production file changes). A broken landing is
  a false sense of security: refusal rows that pass without proving anything, so a later regression that lets an
  agent-authored `.git/config` aim the git-data push or fetch at another tenant's store would ship green.
- **If this leaks, the user's data is exposed via:** the property under test: one tenant's workspace objects pushed into
  another tenant's git-data repository, or another tenant's objects fetched into this workspace, through a planted
  `url.*.insteadOf` or a remote named by the git-data URL.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one cross-tenant write or read through this path is a breach for that user, so
  the rows that pin the refusal carry the threshold of the surface they guard, even though the diff is test-only.
- **Residuals these rows do not close (added at review):**
  - One guard check covers both pushes, so the check-to-use window spans the whole rescue push.
  - Carriers outside the workspace config (include-based, global or system) have no entry-point row.
  - The test stores do not carry the production store's pre-receive fence.
  - If the F21 race hit a no-op rescue push in production, main would not be pushed in that replication. Replication is
    session-end-coupled, so main's update waits for the next session end, and is lost if the workspace is lost first
    (reasoning, not a measurement).

`requires_cpo_signoff: true` is set. CPO reviewed at plan time (see Domain Review). `soleur:engineering:review:user-impact-reviewer`
runs at review time.

## Observability

No production surface changes, so no new runtime signal exists or is claimed. The discoverability probe below confirms
the test-carrier fix is present; it says nothing about production.

```yaml
liveness_signal:
  what: none at runtime (test-only change); the CI signal is the vitest result of the touched suites
  cadence: per CI run
  alert_target: CI failure on the PR
  configured_in: apps/web-platform/vitest.config.ts (repo-wide project via test/repo-wide-suites.ts)
error_reporting:
  destination: unchanged; the production refusal report stays op git_data_replication_refused via reportSilentFallback (server/git-data-replication.ts)
  fail_loud: a red vitest row naming the carrier, or "control - the ... carrier is not live"
failure_modes:
  - mode: the fake transport race returns (wrapper removed or bypassed)
    detection: F21 reflakes; the Phase 1/2 differential stress is the measured mechanism check; layer: CI test suite only
    alert_route: CI failure on the PR or on main
  - mode: an entry-point guard call removed
    detection: R-PUSH-* or R-FETCH-* rows RED (mutants N6 / GC1 in Phase 5); layer: CI test suite only
    alert_route: CI failure on the PR
  - mode: the production ssh-path no-op push hits the same race (unmeasured)
    detection: a git_data_replication_push Sentry report with empty stderr; not measured by this PR
    alert_route: existing Sentry routing; no new alert is created
logs:
  where: vitest output in CI logs
  retention: GitHub Actions log retention (unchanged)
discoverability_test:
  command: grep -l DRAINING_RECEIVE_PACK apps/web-platform/test/helpers/git-data-local-transport.ts
  expected_output: "apps/web-platform/test/helpers/git-data-local-transport.ts"
```

Live verification: `UNVERIFIED:production-git-data-transport` (test-only change; no traffic through the git-data ssh
transport can be generated from this PR, and no production read is claimed).

## Guard Contract

### Guard 1 — entry-point url/remote rewrite refusal rows

**Property.** At each production call site of `assertNoUrlRewrite`, a planted url/remote rewrite carrier makes the
entry point refuse before any `gitWithPrivateKeyAuth` call, and nothing moves between the workspace and another tenant's
store.

**Assembly.** The chokepoint is `assertNoUrlRewrite` (`server/git-data-url-guard.ts`); its production callers are
exactly two: `replicateToGitData` (`server/git-data-replication.ts`) and `fetchFromGitData` (`server/git-data-client.ts`).
The rows quantify over both callers and over the guard's two key classes (`url.*`, URL-shaped `remote.<name>.*`). The
caller set is enumerated by `git grep -n "assertNoUrlRewrite(" -- apps/web-platform/server` (two hits outside the guard
file, verified 2026-11-11); a third caller would not be covered by these rows, and the PR body says so rather than
claiming coverage of every caller.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | N6: drop the guard call in `replicateToGitData` | RED (R-PUSH-1, R-PUSH-2, mocked guard rows) |
| 2 | GC1: drop the guard call in `fetchFromGitData` | RED (R-FETCH-1, R-FETCH-2, R-FETCH-3) |
| 3 | G-DISPATCH: the guard's throw never fires (`if (false)`), its own dispatch | RED (every refusal row) |
| 4 | G-SECOND: the remote-name branch returns false after a compliant `url.*` branch (second member) | RED (R-PUSH-2, R-FETCH-2, R-FETCH-3) |
| 5 | G-OVER: every remote name refused | RED (R-PUSH-0, must-PASS) |

**Harness rows.** H-FAKE: the fake transport loses its `insteadOf` prefix → R-PUSH-0, R-FETCH-0 and every control RED
("carrier is not live"). Must-PASS non-canonical input: R-PUSH-0 (ordinary `origin` / `upstream` remotes and
`remote.pushDefault`, permitted by the guard's contract).

**Anchor.** No stored value is compared; the rows are behavioural. One diff can edit the guard and the rows together, so
the rows prove consistency within a commit, not integrity; review of the test diff is the outside check.

### Guard 2 — the F21 carrier fix

**Property.** No real-git push in these suites can fail from the fake transport's direct-pipe race; a push fails only
for a reason the code under test or the store produces.

**Assembly.** The chokepoint is `runGitDataLocal` in `test/helpers/git-data-local-transport.ts`; its members are every
real-git push fake: the real-git describe of `git-data-replication.test.ts` and the new file. A push fake that bypasses
the helper (an inline `realExec("git", ["push", ...])`) is outside the chokepoint; `git grep -n '"push"' apps/web-platform/test/git-data-replication.test.ts apps/web-platform/test/git-data-url-guard-entry-points-real-git.test.ts`
is run in Phase 6 and every hit is either a fixture-side seed push (not a transport fake) or goes through the helper.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | delete the `--receive-pack` splice | RED in the K-push stress (nonzero, rc 141); the suite itself only flakes, so the stress is the detector |
| 2 | the splice applies to `fetch` too | RED: R-FETCH-0 (an upload-pack request sent to a receive-pack wrapper fails) |
| 3 | a second push fake added inline in the new file without the helper | RED in the Phase 6 grep (an unclassified `"push"` transport hit) |
| 4 | the wrapper drops `exit $s` (always exits 0) | **not a kill — measured GREEN in planning (2026-11-11, scratch `reject-exit0.sh`): with `exit 0` the F20-shape push still exits rc=1 with the rejection on stderr and main landed, because git push decides a rejected ref from receive-pack's status report, not its exit code.** `exit $s` stays only so a receive-pack that dies before its status report is not masked; not counted in any kill tally |

**Harness rows.** The stress script is itself checked against its negative: without the wrapper it must report a nonzero
count (Phase 1.1), so a stress that cannot fail is caught. Must-PASS non-canonical input: F20's partial rejection (a
legitimate non-zero exit must still pass through the wrapper).

**Anchor.** None stored.

## Acceptance Criteria

- [x] AC1 Baseline recorded in `measurements.md`: ≥ 20 isolated F21 runs on the unmodified tree with the failure count,
      rate, load average and the failing assertion (`git-data-replication.test.ts:1294`, second replicate's main push,
      empty stderr). Planning recorded 3/130.
- [x] AC2 Mechanism recorded: the K-push stress without the wrapper gives a nonzero count with exit code 141; with the
      wrapper, 0 at the same K and parallelism.
- [x] AC3 The fix is a test-carrier change only: `git diff --stat origin/main -- apps/web-platform/server` is empty; no
      assertion in `git-data-replication.test.ts` is removed or loosened; the F21 row's second replicate is still a no-op
      push; no retry, skip or timeout change.
- [x] AC4 F20 passes with the wrapper (main lands, rejects `/Command failed: git push/`, one `git_data_replication_push`
      report, no success marker), ≥ 5 runs.
- [x] AC5 Post-fix: ≥ 200 isolated F21 runs with 0 failures and ≥ 20 whole-file runs with 0 failures, each with its load
      average; the power statement is in `measurements.md` and the PR body.
- [x] AC6 The new file exists, mocks no `child_process`, is listed in `repo-wide-suites.ts`, and has the rows R-PUSH-0..2
      and R-FETCH-0..3 with the assertions named in Phase 4; every control-backed row fails its own control message when
      the carrier does not land. (Rows renamed UG-PUSH-n / UG-FETCH-n at review; UG-PUSH-3 and UG-FAKE added.)
- [x] AC7 Mutant table complete (Phase 5), 3 serial reps per mutant, killing rows named per rep; N6 RED 3/3 with F21
      absent from every RED list; R-FETCH-* green under N6; GC1 RED 3/3 with R-PUSH-* green; WS1, WS3, CQ1 each RED 3/3,
      or a new row added and the mutant re-killed (5.1).
- [x] AC8 `test/repo-wide-containment.test.ts`, `plugins/soleur/test/fixture-env-adoption.test.sh`, typecheck and ESLint on
      the touched files green; `git status --short` empty after the battery.
- [x] AC9 PR body: `Ref #9601` only (no closing keyword); states the two production call sites; carries the "Not measured"
      paragraph of CTO R6 verbatim in substance; claims no structural guard, no production measurement, no ADR-309 flip
      item, no epic status, no "39/39"; claims the flake fixed only with the AC5 numbers; lists the unfiled follow-up.
- [x] AC10 No forbidden number or file name appears in any diff line, commit, PR body or comment (the egress-audit range
      rule and the two named exclusions in the operator's standing constraints): checked with a grep over
      `git log -p origin/main..HEAD` and the PR body before marking ready.

## Domain Review

**Domains relevant:** Engineering, Product (sign-off only)

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled R1-R7 (decision-challenges.md): fix A in the fake transport, the extended evidence bar,
the fetch-side carrier rows, the fetch assertions plus a positive row, rows in a new non-mocked file, no production change
with the ssh-path exposure written down, and the serial three-rep mutant protocol.

### Product

**Status:** reviewed
**Assessment:** CPO (advisory, plan time): SIGN WITH CONDITIONS. Conditions 2-6 are folded in: honest preflight wording
(no "prevents cross-tenant replication"), machine-enforced non-vacuity (in-row controls that fail the row, the positive
fetch row, named mutant kills as a merge gate), the evidence bar reported as measured numbers with its power, the wrapper
described as a model of ssh and not as ssh, synthesized fixtures only. Condition 1 (file a tracking issue for the
ssh-path exposure before ship) conflicts with the operator's standing constraint that no issue is filed unless the CTO
rules it and the operator says so; the operator's constraint governs, the follow-up goes under "Follow-ups not filed" in
the PR body with draft text, and the conflict is recorded in decision-challenges.md.

Product/UX Gate: no UI surface in Files to Edit or Create (mechanical override checked: test files and a helper only), so
it does not run. Legal: not relevant; no public, legal or marketing text. GDPR gate (trigger: the declared
`single-user incident` threshold): run, no findings. The path scan examined 5 planned files and matched 0 of them.
No schema, column, PII table, foreign key, vendor or special-category surface is touched, and the fixtures are
synthesized. The row is in decision-challenges.md. This is not legal review.

## Operator Holds

- Hold: Operator-reserved: flag, environment and prd enablement (including the approval-queue flag)
- Hold: Operator-reserved: ADR-309 flip items 8-12
- Hold: Operator-reserved: item 2 pepper check
- Hold: Operator-reserved: item 5 erasure record
- Hold: Operator-reserved: item 6 CLO attestation
- Hold: Operator-reserved: the unverified third item-3 check (Sentry cron-monitor read returned 403)
- Hold: Operator-reserved: #9826 human criteria and the classify flag creation
- Hold: Operator-reserved: #11640
- Hold: Operator-reserved: ADR-287 Article 30 amendment and legal wording
- Hold: Operator-reserved: liveness alerts plus live Bash tool_response capture
- Hold: Operator-reserved: AGENT_OUTER_WRAP (never read or flipped live by the agent)
- Hold: Operator-reserved: the isolated-GIT_DIR push path
- Hold: Operator-reserved: filing the ssh-path no-op-push follow-up issue (CTO R6 calls it warranted; it stays unfiled until the operator says so)

None of these blocks this PR (CTO: no delegable act).

## Open Code-Review Overlap

None. Queried 95 open `code-review` issues for `apps/web-platform/test/git-data-replication.test.ts`,
`apps/web-platform/test/repo-wide-suites.ts`, `server/git-data-replication.ts`, `server/git-data-client.ts`,
`server/git-data-url-guard.ts`: no body names any of them.

## Test Scenarios

- unit/integration (real git, `integration`): Given a workspace whose config plants `url.<B>.insteadOf <git-data URL>`,
  when `replicateToGitData` runs, then it rejects with `GitDataUrlRewriteError`, no git transport call is made, A and B
  are unchanged and one `git_data_replication_refused` report is filed.
- integration: Given `[remote "<URL>"] pushurl = <B>`, when `replicateToGitData` runs, then the same.
- integration: Given ordinary `origin` / `upstream` remotes and `remote.pushDefault`, when `replicateToGitData` runs, then
  it replicates into A and B is untouched.
- integration: Given `url.<B>.insteadOf` or `[remote "<URL>"] url = <B>`, when `fetchFromGitData` runs, then it rejects
  before the fetch, no `refs/remotes/git-data/*` exists and B's tip object is absent.
- integration: Given `[remote "<URL>"] pushurl = <B>`, when the raw fetch argv runs, then nothing lands (inverted control);
  when `fetchFromGitData` runs, then it still refuses.
- integration: Given no carrier, when `fetchFromGitData` runs, then A's `main` lands in `refs/remotes/git-data/main`.
- integration: Given the F21 fixture, when the second (no-op) replicate runs ≥ 200 times in isolation, then 0 failures.
- Verification commands (from `apps/web-platform`):
  - `npx vitest run test/git-data-url-guard-entry-points-real-git.test.ts`
  - `npx vitest run test/git-data-replication.test.ts`
  - `npx vitest run test/git-data-replication.test.ts -t "F21: the local rescue branch is deleted"` (looped per Phase 3)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. This one is filled.
- `insteadOf` precedence: the planted carrier must be the **full** git-data URL (or any prefix longer than the fake's
  `ssh://git@10.0.1.20/mnt/git-data/repositories/`), or the fake's own rewrite wins and the control shows "not live".
- The guard runs `git config --get-regexp` with the production env (pinned `GIT_DIR`/`GIT_WORK_TREE`). The new file must
  not mock `child_process`, or it re-introduces the env replacement CTO R5 ruled out.
- `--receive-pack` must be spliced only into `push`. A fetch through the receive-pack wrapper fails (Guard 2 row 2).
- `cat-file -e <B tip>` after a control: the control fetch brought B's objects into the workspace; delete the
  remote-tracking refs and `git gc --prune=now` (or rebuild the workspace) before the guarded call, and confirm the object
  is gone, or the "B's object absent" assertion is vacuously false.
- `replicateToGitData` writes `remote.git-data.url` into the workspace config (`ensureGitDataRemote`) before the guard; the
  name `git-data` is not URL-shaped, so it is not refused. Do not plant carriers under the name `git-data`.
- A file-selected run cannot see a repo-global pin: after the change, `git grep -l 'git-data-replication.test\|git-data-local-transport'`
  across `*.sh`, `*.py`, `*.yml` and `scripts/`, and run any hit by name.
- The new suite is invisible to `repo-wide-containment` and the fixture-env ratchet until it is tracked: `git add` before
  running them.
- Mutation harness: restore from a pristine copy, never `git checkout --`; commit first; refuse a dirty tree; derive the
  pristine list from the mutant table.
- Measurement load: the planning host ran other worktrees' `test-all.sh`; label every count with its load average.

## Handoff block for the final report (consumed by work/ship)

- PR body leads with what is measured (AC1, AC2, AC5, AC7 numbers) and the "Not measured" paragraph (CTO R6), and states:
  the guard is a preflight (the check-to-use window is not covered); the drain wrapper models an ssh-like intermediary and
  is not ssh; nothing was measured in production (no Sentry read, no TLS canary, the built image's git version against the
  2.38 floor is unmeasured).
- `Live verification: UNVERIFIED:production-git-data-transport`.
- Follow-ups not filed (no issue filed, no comment posted): measure a no-op push with push options over the ssh carrier,
  and, if it reproduces, decide whether to skip the main push when nothing changed (CTO R6; CPO condition 1 recorded).
- Operator never-done items: see `## Operator Holds`.

## Addendum — 2026-11-11 (review)

In the new file, the rows R-PUSH-n and R-FETCH-n are now UG-PUSH-n and UG-FETCH-n, because the old IDs shared
the R-PUSH-/R-FETCH- prefix with `git-data-remote-url-wrapper.test.ts`. The sections above keep the old names.

The review added these rows:

- UG-PUSH-1 and UG-PUSH-2 now run with and without a local rescue branch.
- UG-PUSH-3: `url.<B>.pushInsteadOf`.
- UG-FAKE: a pin on the push argv's receive-pack splice.

The review also added three mutants: N6-MOVE, M-A and H-SPLICE-DROP. Their results are in the measurements addendum.

**Acceptance check (QA, 2026-11-11).** AC1-AC10 were checked by running their named commands:
- `git diff --stat origin/main -- apps/web-platform/server` is empty.
- No `child_process` mock; the file is registered in `repo-wide-suites.ts`.
- No `expect` removed from `git-data-replication.test.ts`.
- The measurements and addendum are in `measurements.md`.
- On the final tree: F21 isolated 30/30 (load 2.9-3.9), and the two suites 84/84 x3. This adds to AC5 and does not
  replace it.
- `fixture-env-adoption` 27/27, containment, tsc and ESLint are green.
- The AC10 grep is clean.
