# Tasks: ADR-309 flip item 9b - push the approved commit from an isolated git directory

Plan: `knowledge-base/project/plans/2026-11-06-fix-adr309-9b-isolated-git-dir-push-plan.md`
Branch: `feat-one-shot-9601-adr309-9b-push-hardening` | Epic Ref #9601 | One PR | `Ref #9601` only, no issue filed.
Every test task is written and seen RED before its implementation task. Commit from the worktree cwd, one call per commit,
trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Phase 1 - Leaf modules (RED first)

- 1.1 Write `apps/web-platform/test/git-isolated-push-dir.test.ts`: refusals (symlinked `.git`, `gitdir:` file, missing `.git`, symlinked `objects`, symlinked `objects/pack` / `objects/info` / fan-out child, `alternates`, `http-alternates`, `:` in path), shallow validation (FIFO with explicit timeout, oversized, non-hex, valid copy), server-written files exact, `realpath(gitDir)` not under the workspace, `dispose()` idempotent, injected write failure leaves no directory, no raw fs error escapes (`setup_failed`).
- 1.2 Write `apps/web-platform/test/approval/workspace-head.test.ts`: detached, symbolic, loose, packed-only, loose-shadows-packed, peeled lines, `commondir` planted, `process.env.GIT_DIR` set, hostile config, unborn HEAD, CRLF / uppercase hex refused, worktree `.git` file, symlinked `HEAD` / `refs/heads`, traversal ref name, FIFO, reftable, symref chain, oversized, spawn-counter proves no child, content test on the module's imports.
- 1.3 Implement `apps/web-platform/server/approval/workspace-head.ts` (`readSmallRegularFile`, `readWorkspaceHeadSha`).
- 1.4 Implement `apps/web-platform/server/git-isolated-push-dir.ts` (`createIsolatedPushDir`, `IsolatedPushDirRefusal`): directory under `$HOME/.soleur-push` (0700, no `/tmp` fallback), env-path step 0, fan-out Dirent walk with entry cap, server-written config with `commitGraph`/`multiPackIndex`/`useBitmaps`/`gc.auto`/`pack.threads` switched off.
- 1.5 `apps/web-platform/server/git-hardened-env.ts`: branded `IsolatedPushDir`, `isSafeGitPath`, `buildIsolatedGitEnv` (child `HOME` = the isolated directory); delete `buildHardenedGitEnv`; rewrite the header comment (remove the false `commondir` claim and the "NOT covered here" paragraph).

## Phase 2 - Wire the push

- 2.1 Update `test/git-auth-hardened-env.test.ts` and `test/git-auth-hardened.test.ts` to the isolated option (RED): runtime shape validation before the mint, no caller `cwd`, exact env key set, legacy form unchanged.
- 2.2 `apps/web-platform/server/git-auth.ts` hardened branch (GREEN): runtime shape validation before the mint, askpass written inside the isolated directory; legacy branch untouched.
- 2.3 Write `test/push-branch-isolated-real-git.test.ts` FIRST and run it RED against a `legacy9aEnv(ws)` helper (mutation 1: the vector is effective under the 9a env) before any push-branch change (task 2.5 content moved here); then rewrite `test/push-branch-hardened.test.ts` (RED): flow, refusal mapping (tamper reasons -> `commit_unavailable`, `setup_failed` -> plain static error), no `git config` spawn against the workspace, no-`commitSha` and 64-hex refusals, dispose after success / push failure / mint failure / refusal, refusal-reporting unit test, previously-refused entries now ignored (table), legacy path unchanged.
- 2.4 `apps/web-platform/server/push-branch.ts` hardened flow (GREEN); delete `assertPlainGitDir` and its lists.
- 2.5 Contents of `test/push-branch-isolated-real-git.test.ts` (written under 2.3): file-transport control vs isolated (`insteadOf`, `pushInsteadOf`), `config --list --show-origin` with hostile `$HOME` / `$XDG_CONFIG_HOME` configs, TLS recording-server arms per vector (sslVerify, sslCAInfo, specific proxy, curloptResolve, extraHeader; evil server records `Authorization` in the control only), alternate-only objects loose and packed with remote `fsck`, `--depth 1` remote-ahead plus negative control, boundary-commit push, non-fast-forward rejection, alternates chain, concurrent pushes. Positive TLS control with a trusted CA via the test-only `SSL_CERT_FILE`; assertions on server-recorded requests and exit status, not stderr wording; deliberate `GIT_CONFIG_COUNT` injection observed by the control and dropped by the isolated child; FIFO / `chmod 000` / sentinel-marker falsifiers per file class with hard timeouts; corrupt `commit-graph` / midx / bitmap and crafted `.gitmodules` still push; fake `git-remote-https` on a writable `PATH` dir; explicit timeouts and `closeAllConnections()`. Strip `GIT_CONFIG_COUNT` / `KEY_n` / `VALUE_n` / `GIT_CONFIG_PARAMETERS` from `process.env` in `beforeEach`. `openssl` precondition test fails loudly, never skips.
- 2.6 Register the new suites that read outside `apps/web-platform` in `apps/web-platform/test/repo-wide-suites.ts`; run `test/repo-wide-containment.test.ts`.

## Phase 3 - The gate

- 3.1 Extend `test/approval/gate-deps.test.ts` default-reader describe (planted `commondir`, `gitdir:` file, inherited `GIT_DIR`, spawn counter) (RED).
- 3.2 `apps/web-platform/server/approval/gate.ts` (the wrapper also reports `op: head-read-failed` with the reader's closed `reason` and rethrows; differential test of the reader against real git): `gitHeadSha` becomes a wrapper over `readWorkspaceHeadSha` keeping the `COMMIT_SHA_RE` throw text; remove the `execFile` imports (GREEN).

## Phase 4 - Mutation battery

- 4.1 Record the baseline: `bash apps/web-platform/test/approval-guard1-mutation.test.sh --list` and `--check-anchors`.
- 4.2 Rewrite G1-X9, G1-HD1, G1-HD2, G1-HD12, G1-GD22, G1-GD23 (and the `equivalent=` text of G1-GD24); delete G1-HD6, G1-HD15; replace G1-HD8/HD9/HD10/HD16 with rows on `git-isolated-push-dir.ts`; add G1-ISO1..ISO7; ratchet the `FLOOR` entries and `MIN_MUTANTS` / `MIN_KILLED` to the new literal counts.
- 4.3 `--check-anchors` exits 0; targeted `--only 'G1-HD|G1-X8|G1-X9|G1-GD2[2-4]|G1-ISO'`. The full 25-minute battery is CI's job.

## Phase 5 - ADR, handover, decision record

- 5.1 ADR-309: rewrite item 9 (9a note, 9b bullet, closer record, drop the "tracking issue is filed by ship" sentence) in place; italic *Superseded in part, 2026-11-06* pointers at each falsified item 7 clause, the addendum summary paragraph and item 11; short dated addendum (design, E1-E5 table with reproduction commands, correction of item 7, residuals, "discharges nothing", test names, CI-is-the-gate record).
- 5.2 Identical item-9 replacement in the archived handover copy; assert parity by content anchor (`9. **` block up to the line starting `10. **Register`) with `cmp`.
- 5.3 The ADR addendum residual list records, without filing any issue: object-store swap after the check (cross-tenant bytes for a known sha), the leaked directory after SIGKILL, pre-card validation of push-ability, reftable default flipping the gate reader to fail-closed, and the unverified sandbox-write and path-guessability limbs.
- 5.4 `bash scripts/markdown-lint.sh --repo-sweep`; `python3 scripts/lint-guard-contract.py` on the plan.

## Phase 6 - Verification and ship

- 6.1 Targeted vitest: the files in the plan's Files lists plus `test/approval/decide-boundary.test.ts`, `test/approval/runner-census.test.ts`, `test/git-data-ssh-dial-sweep.test.ts`, `test/git-data-ssh-connect-bound.test.ts`, `test/git-data-key-sweep.test.ts`, `test/github-tools-push-grant.test.ts`, `test/cc-dispatcher-real-factory.test.ts`; `npx tsc --noEmit` in `apps/web-platform`. CI is the ship gate; the PR test plan records that the slow local `--affected` battery was not awaited.
- 6.2 Before every push both token greps print nothing (diff and log forms in the plan's acceptance criteria).
- 6.3 PR title `fix(approval): ...`, body `Ref #9601` (never `Closes`), states that nothing here discharges the flip and the sandbox-write limb stays UNVERIFIED.

## Implementation status (Phases 1-3, code and tests)

Done (see the commits on the branch): 1.1-1.5, 2.1-2.6, 3.1-3.2. Notes: the positive TLS control trusts the test CA through
`GIT_SSL_CAINFO` supplied via the test-only builder seam, because `SSL_CERT_FILE` was measured not to be honoured by git's libcurl
on git 2.56; `env_path_unsafe` is mapped to the plain `Push could not be prepared` error (the environment is the server's, not the
agent's); `hardened` http extraHeader / env-config vectors are URL-scoped because the unscoped key is reset by the later `-c`.
Phase 4 (mutation battery) and Phase 5 (ADR, handover) belong to other agents.
