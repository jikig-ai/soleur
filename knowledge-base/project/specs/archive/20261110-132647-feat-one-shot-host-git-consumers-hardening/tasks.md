# Tasks: harden the host-side git consumers (Ref #9601)

Plan: `knowledge-base/project/plans/2026-11-09-fix-host-side-git-consumers-hardening-plan.md`
Branch: `feat-one-shot-host-git-consumers-hardening` | Draft PR 12512 | One PR only.

## Phase 0: Preconditions

- 0.1 Re-run `bash plugins/soleur/scripts/collision-precheck.sh 9601`.
- 0.2 Confirm `git --version` >= 2.38 (the suite's `beforeAll` throws below it, never skips).
- 0.3 Grep that no in-scope consumer runs with a bare repository as cwd (needed for `safe.bareRepository=explicit`; cut the pin if one does).

## Phase 1: RED first (local commit before product changes; imports no new module)

- 1.1 Create `apps/web-platform/test/helpers/host-git-carrier-fixture.ts`: hermetic env, throwaway roots, sentinel in `process.env`, canary and env-dump helpers, cached raw-git twin per carrier type, git-floor assertion.
  - 1.1.1 Carrier planters table: `commondir`, `.git/config`, `config.worktree`, hooks, `.git/modules/sub/config`, tracked `.gitattributes` (filter and merge drivers), `.git/info/attributes`, repo `core.attributesFile`, signing program, committed bare cwd, `core.worktree` to a sibling dir, `core.bare=true` vs `GIT_WORK_TREE`, gitfile to a foreign gitdir, `uploadpack` on a local-path remote, `protocol.ext.allow=always` + `ext::` rewrite, `merge.verifySignatures`, submodule recursion.
  - 1.1.2 Label carriers already inert on today's code as "pre-existing control / regression pin".
- 1.2 Create `apps/web-platform/test/host-git-consumers-real-git.test.ts` with drivers for `syncPush` (and `syncPull`), the ensure-workspace-repo overlay, `ensureGitDataRemote` + `gitWithPrivateKeyAuth` push and fetch (fake `ssh` on PATH), legacy `gitWithInstallationAuth` (only `generateInstallationToken` mocked, local `node:http` 401 server), and the inflight-checkpoint entry; no `child_process` mock.
  - 1.2.1 Assertions A1-A3 (no canary, no sentinel in any env dump, operation succeeds with the seeded local identity).
  - 1.2.2 `RESIDUAL` pin rows generated from the planter table; measure `remote.origin.url`/`pushurl`, `http.proxy`, `http.sslVerify`, URL-scoped `credential.<url>.helper` and pin those that fire; key-auth rewritten-host row asserting the pinned ssh options (close the arm with an explicit URL if a row shows a non-origin handshake).
  - 1.2.3 Floor row derived from the planter and driver tables.
- 1.3 Run against current code; record RED (fsmonitor via `commondir` for session-sync and legacy pull; `gpg.program` on commit). Commit RED locally; push only with the GREEN commits.

## Phase 2: Shared leaf helper

- 2.1 Create `apps/web-platform/server/host-git.ts` (imports `node:os` and `_git-hardening` only): moved `buildScrubbedEnv`/`BaseEnv`/regex, moved `AGENT_GIT_GLOBAL_CONFIG`, `hostGitInvocation(args, { extraEnv?, globalConfig? }) -> { args, env }` with the extras `safe.bareRepository=explicit`, `commit.gpgsign=false`, `tag.gpgsign=false`, passthrough keys when set; `cwd` -> `GIT_WORK_TREE`; required `allowProtocol` on the network arms (`https` legacy, `ssh` key-auth) plus `-c protocol.ext.allow=never`; measured-or-dropped `-c` additions; empty/non-absolute PATH entries dropped; only `-c key=value` and env, no new global option.
- 2.2 `compound-promote-create-gates.ts` re-exports `buildScrubbedEnv`; `agent-env.ts` re-exports `AGENT_GIT_GLOBAL_CONFIG`.
- 2.3 Create `apps/web-platform/test/host-git.test.ts` (env contents, scrub, extras last, passthrough only when set, identity rows with real git incl. absent file, gpg flags, layering).

## Phase 3: Wire the consumers (separate commits; network arms revert alone)

- 3.1 Commit (b): `session-sync.ts` `runConnectedRepoGit` (type excludes `env`), `ensure-workspace-repo.ts` `realLocalGit`, `git-data-replication.ts` five execs, `inflight-checkpoint.ts` `runPlumbingGit`; Sentry mirror at the two auto-commit catches (`auto-commit-pull`, `auto-commit-push`).
- 3.2 Commit (c): `git-auth.ts` `gitWithPrivateKeyAuth` (helper args and env, no `GIT_CONFIG_*` of its own).
- 3.3 Commit (d): `git-auth.ts` legacy arm (hardening block before `HELPER_RESET`; `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_NOSYSTEM` stripped from the legacy env only; shared `authEnv` and the `hardened` arm unchanged).
- 3.4 Update sibling assertions that break (`git-auth.test.ts` `/dev/null` and argv rows, `git-data-replication.test.ts` positional argv reads, the `args[0]`-branching `execFileSync` mocks in `session-sync-path-allowlist.test.ts` and `session-sync-protected-fallback.test.ts`) in the commit that breaks them.
- 3.5 Scheme grep (including `test/` and e2e) before wiring `allowProtocol`; shape check for a gitfile `.git` via `git-worktree-validity.ts` if cheap, else pin the residual.

## Phase 4: ADR and wording

- 4.1 Amend the ADR-050 2026-11-09 amendment host-side git bullet (a few lines; census output goes in the PR body).
- 4.2 Draft the PR body: Ref lines, "does NOT claim" block, `Follow-ups not filed`, rollback sentence, census output, sibling-test edits.

## Phase 5: Gates

- 5.1 Sibling unit suites, `compound-promote-create-gates`, `agent-env`, `dockerfile-git-version-floor`, hardened tests unmodified.
- 5.2 `tests/scripts/test-no-tofu-ssh-mutation.sh`, `tests/scripts/test-no-tofu-ssh.sh`.
- 5.3 Source-pin test, session-sync sentry-mirror tests, auto-commit density check, `ci-pr-affected-replay.py audit` (exit 0, counts unchanged), `c4-count-parity.test.sh`, `lint-guard-contract.py`, markdownlint, `repo-wide-containment.test.ts`.
- 5.4 Forbidden-token sweep (pattern kept outside the repo) over the three-dot diff, PR body, commit messages.
- 5.5 Local-config snapshot before and after the suite.

## Phase 6: Ship-time

- 6.1 Dev-host `git ls-remote` under the helper env, recorded as "I checked", labelled not a prod measurement; on failure drop the legacy-arm commit and list it under `Follow-ups not filed`.
- 6.2 ADR-276 `ci-head-verdict.sh` runs from inside this worktree; one rerun of `40P01` failures only.
- 6.3 No sync of an armed or queued PR without explicit operator OK; no issue filed; no comment posted.
- 6.4 Carry-forward: 24-hour post-deploy Sentry read against the pre-deploy baseline.
