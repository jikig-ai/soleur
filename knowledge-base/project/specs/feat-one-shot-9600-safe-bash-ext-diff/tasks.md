# Tasks: safe-bash git config-exec carriers (Ref #9600, epic #9601)

Plan: `knowledge-base/project/plans/2026-11-09-fix-safe-bash-git-config-exec-carriers-plan.md`

## Phase 1 - Falsifier first (RED)

- 1.1 Create `apps/web-platform/test/safe-bash-git-config-exec.test.ts`: hermetic temp repo, constructed git env (no `GIT_DIR`/`GIT_INDEX_FILE`), plant `diff.external`, textconv + `.gitattributes`, `core.fsmonitor`, `filter.zz.clean`, `gpg.program` + hand-built signed commit, dirty worktree, text-built bare dir `evil/`.
- 1.2 `ROWS` table with observed channel sets; Test A (observed equals table, title prints `git --version`), Test B (`isBashCommandSafe` equals `approved`), Test C (approved-and-executing equals exact `CARRIER_DEPENDENT_APPROVED`; no exec-requesting flag in any approved row).
- 1.2b Add fixture rows: a source repo that COMMITS an embedded bare repo, cloned; a bare repo whose own config sets `[safe] bareRepository = all`; one submodule row.
- 1.3 Include `--flag=value`, combined, abbreviation, `&&`-segment, `-O*`, `--output*` rows and non-canonical must-PASS rows.
- 1.4 Confirm RED against pre-fix `safe-bash.ts`; commit the RED test first.

## Phase 2 - Closed flag grammar

- 2.1 Replace the three `git log|diff|show` patterns in `apps/web-platform/server/safe-bash.ts` with one shared closed-grammar builder (non-overlapping token alternation).
- 2.2 Admission-rule comment (a flag needs a real-git table row); keep `FILE_WRITE_FLAG_DENYLIST`.
- 2.3 Extend `apps/web-platform/test/safe-bash.test.ts` (positives, negatives, env-prefix and global-option rejections, ReDoS pin).
- 2.4 Add `safe-bash-git-flag-fallthrough` budgeted telemetry in `apps/web-platform/server/permission-callback.ts` near-miss block.
- 2.5 Callback-level test: denied git form takes the ask path, not deny (`permission-callback-safe-bash.test.ts`).

## Phase 3 - Carrier guard

- 3.1 Create `apps/web-platform/server/git-carrier-guard.ts` (`GIT_CARRIER_WRITE_TOOLS`, `gitCarrierTouched`; lexical + realpath; case-insensitive `.git` component; fail closed).
- 3.2 Wire into `apps/web-platform/server/sandbox-hook.ts` and the `permission-callback.ts` file-tool branch; plain deny message; budgeted `git-carrier-write-denied` event.
- 3.3 Create `apps/web-platform/test/git-carrier-guard.test.ts` (nested, case, symlink, gitdir-pointer file, non-existent target, reads unaffected, `.github`/`.gitignore` not matched, RED measurement row for pre-fix allow, call-site grep test).

## Phase 4 - Env pin (primary control; do this first after Phase 1)

- 4.1 `apps/web-platform/server/agent-env.ts`: pin `safe.bareRepository=explicit` via `GIT_CONFIG_COUNT/KEY/VALUE` (append to ambient count) and move `GIT_CONFIG_NOSYSTEM`/`GIT_CONFIG_GLOBAL` out of the git-auth block; set after the allowlist loop.
- 4.2 Extend `apps/web-platform/test/agent-env.test.ts`; real-git refusal assertion for the text-built bare dir.
- 4.2b `apps/web-platform/Dockerfile`: build-time assertion that git is 2.38 or later; text test pinning the floor; record the built image's `git --version` for AC11.
- 4.3 Check identity seeding (`git-config-atomic.ts`) and `git-auth.ts`/`git-hardened-env.ts` interplay; consumer grep for builder bypass.

## Phase 5 - Docs and PR inputs

- 5.1 ADR-050 dated amendment line; run `plugins/soleur/test/c4-count-parity.test.sh`; read the three `.c4` files for a falsified description.
- 5.2 Run `bunx tsc --noEmit`, vitest for touched files, `python3 scripts/lint-guard-contract.py`.
- 5.3 PR body: `Ref #9600`, honest falsifier result, residual list, UX cost, Changelog, brand-survival bullet, `Follow-ups not filed` line (9b residual (a) text from the plan AC10). `Closes` only per plan AC11.
