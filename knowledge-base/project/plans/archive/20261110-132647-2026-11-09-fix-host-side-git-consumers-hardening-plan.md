---
title: "fix: harden the host-side git consumers that run outside the sandbox"
date: 2026-11-09
slug: fix-host-side-git-consumers-hardening
branch: feat-one-shot-host-git-consumers-hardening
issue: 9601
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: harden the host-side git consumers that run outside the sandbox

## Enhancement Summary

**Deepened on:** 2026-11-09
**Agents and passes used:** security-sentinel, a verify-the-negative code-claims pass, the CTO (round 3, R8a-R8f), plus the lead's own real-git spikes (git 2.56.0) and the mechanical halts 4.6-4.13 (all green).

1. Two new carriers with cross-tenant consequence were found and measured: `core.worktree` pointing at a foreign tenant directory (closed by env `GIT_WORK_TREE=<cwd>`, not by `-c`) and local-exec transports on the network arms (`remote.<n>.uploadpack` on a local-path remote, `ext::`; closed by `GIT_ALLOW_PROTOCOL` and `-c protocol.ext.allow=never`). The earlier cut of the protocol allowlist is reversed.
2. The residual set is wider and the key-auth wording is sharper: an executing helper can read the 0600 transport key file. `--attr-source` was measured and rejected (partial, new global option on an unmeasured image git).
3. Sibling-test breakage is larger than argv slicing (mocks branching on `args[0]`, positional index reads); the plan names the files.

### New considerations discovered

- Only `-c key=value` and environment may be added to the helper: the built image's git version is unmeasured and an unknown global option exits 129 on git 2.38/2.39.
- Unmeasured helper additions ship only if their Phase 1 row fires under the shared args (CTO R8c).

Ref #9601 (agent security hardening epic, stays open; this plan never closes or edits it). Follow-on to the
git-read hardening that merged 2026-11-09 (PR 12485, `Ref #9600`; ADR-050 amendment of the same date).
Draft PR 12512 already exists on this branch; the work ships as exactly that one PR.

## Overview

Host-side git in tenant workspaces runs OUTSIDE the agent sandbox, with the server's process environment, in a
workspace whose `.git` an agent session can author. The 2026-11-09 amendment recorded this as a residual and
hardened only `inflight-checkpoint`'s plumbing git. This plan closes the part that `-c` arguments and an
environment scrub can close, for the consumers named in the binding CTO ruling plus the ones the rulings pull in,
and records, with tests that assert today's behaviour, the part that stays open.

Shape of the change:

1. A real-git RED test battery first. It plants agent-authorable `.git` carriers and drives the REAL code paths of
   each consumer (`syncPush`, the `ensure-workspace-repo` overlay's `realLocalGit`, `ensureGitDataRemote` and the
   key-auth push, `gitWithInstallationAuth`'s legacy arm, `inflight-checkpoint`), with a sentinel secret in the
   test's `process.env`. The RED battery imports no new module, so it fails on carrier evidence, not on an import.
2. One shared leaf helper `apps/web-platform/server/host-git.ts` returning `{ args, env }`: `GIT_HARDENING_ARGS`
   plus the helper-only extras (`safe.bareRepository=explicit`, signing off), and an env of `buildScrubbedEnv` plus
   `GIT_HARDENING_ENV`, with each consumer's own auth variables merged AFTER the scrub.
3. Residual pins: where a carrier stays executable after the `-c` arguments, a test asserts current behaviour and the
   ADR says so. No closure claim is made without a structural control; the only structural control is the
   isolated-`GIT_DIR` path, which is operator-held and untouched.

## Research Insights

### Premise Validation (Phase 0.6)

Checked on this branch (HEAD = main + the init commit):

- Epic #9601 is open (title "feat: agent security hardening epic (three-layer review)"). Draft PR 12512 is open and
  draft on this branch. Collision pre-check for #9601: no other open change names it, no foreign gate process.
- The git-read hardening is PR 12485 (merged 2026-11-09, `fix(safe-bash): shut git config-exec carriers behind
  auto-approved reads (Ref #9600)`); its ADR text is the 2026-11-09 amendment in ADR-050.
- Every cited site holds, by content anchor: `runConnectedRepoGit` (`execFileSync("git", argv, opts)`),
  `realLocalGit`, `ensureGitDataRemote` (remote add/set-url), the `for-each-ref` and `update-ref -d` execs in the
  replication function, the legacy arm of `gitWithInstallationAuth` (`{ ...process.env, ...authEnv }`),
  `runPlumbingGit` in `inflight-checkpoint.ts`.
- ONE premise is wrong, recorded in the reconciliation table: `runPlumbingGit` carries `GIT_HARDENING_ARGS` and
  `GIT_HARDENING_ENV` but spreads `...process.env`; it does NOT use `buildScrubbedEnv`. The model for "scrubbed env +
  hardening env" is `runGit` in `compound-promote-create-gates.ts`.
- ADR corpus check for the mechanism (shared args + scrubbed env): ADR-050's 2026-11-09 amendment lists exactly this
  as a recorded residual, and the same-day CTO ruling deferred it for per-call-site tests. Nothing in the corpus
  rejects it. The isolated-`GIT_DIR` design (ADR-309 flip item 9b, `git-hardened-env.ts` header) is the structural
  alternative and is operator-held.

### Property List and Cut List (Phase 0.6b)

Properties (observable outcomes):

- P1. On each consumer's real code path, a planted carrier that the helper's `-c` arguments can close (fsmonitor from
  the three measured config sources, hooks, `config.worktree`, a repo or global attributes file, commit signing)
  executes nothing.
- P2. No server-only environment variable present in the server's `process.env` reaches any helper that a planted
  carrier does cause to run, on any consumer.
- P3. The consumer's legitimate operation still succeeds, including the commit identity.
- P4. What is not closed is pinned: a test asserts today's behaviour for `filter.*`, `merge.*.driver`, repo-config
  remote rewriting and a consumer's own auth variable, so a later change in either direction fails a test.
- P5. A git older than 2.38 fails the new suite loudly instead of skipping.
- P6. The PR and the ADR state what the control does not claim.

Mechanisms the ask names, and what already covers them (authority grepped: `server/inngest/functions/_git-hardening.ts`,
`server/compound-promote-create-gates.ts`, `server/inflight-checkpoint.ts`, `server/git-auth.ts`):

| Mechanism in the ask | Property | Already on main? |
|---|---|---|
| Shared helper returning `GIT_HARDENING_ARGS` + scrubbed env | P1, P2 | Constants exist (`_git-hardening.ts`); `buildScrubbedEnv` exists; `runGit` composes them for ONE async, closed-evidence caller. No sync or per-call-env variant. Helper is new. |
| Real-git RED test with planted carriers | P1-P3 | `test/helpers/git-config-exec-fixture.ts` plants the agent-read channels for the safe-bash falsifier (reusable ideas: `baseGitEnv`, `IDENT`, `script`); `test/ensure-workspace-repo-ancestry-real-git.test.ts` runs the real `realLocalGit`. No suite drives the host-side consumers against carriers. Tests are new. |
| Residual pin test | P4 | None. New. |

Cut List (mechanisms considered and removed before or during review):

- Reuse `runGit` (`compound-promote-create-gates.ts`) as the shared helper -> P1/P2 -> cut: async-only, closed evidence
  without stdout on failure, mirrors every failure to Sentry under the create-gate feature, takes no per-call env. Its
  env recipe is reused; the function is not.
- Carrier-presence preflight refusal -> P1 -> cut (CTO F4): agent-writable carriers make a presence check TOCTOU
  rather than a control, and it would refuse legitimate worktree-style workspaces.
- Repo-wide sentinel sweep failing on any raw `execFile("git"` in `server/` -> cut as a separate mechanism; its
  one useful part survives inside Guard 1 as a single tree-wide census row (see Guard Contract), not as a new gate.
- `allowProtocol` / `GIT_ALLOW_PROTOCOL` on the network arms -> cut by CTO R2, then REINSTATED by CTO R8b (deepen-plan,
  2026-11-09) on new evidence: repo config can switch `ext::` on, and a local-path remote with `remote.<n>.uploadpack`
  executes a planted program on fetch (measured), while `GIT_ALLOW_PROTOCOL` blocks it. It stays a required parameter
  for the network arms only; an https allowlist still does not stop an https rewrite to an attacker host (residual).
- `--attr-source=<empty tree>` as a `filter.*` control -> cut (CTO R8d): measured partial. It stops worktree
  `.gitattributes` filters but not `.git/info/attributes` (including via `commondir`), and it is a new global OPTION,
  which hard-fails (exit 129) on git 2.38/2.39 while the Dockerfile floor is 2.38 and the built image's git version is
  unmeasured.
- Env-pair delivery (`GIT_CONFIG_COUNT`/`KEY_n`/`VALUE_n`) of the `-c` set instead of argv -> cut: it would stop the
  hardening block shifting `args[0]` in sibling mocks, but the brief binds the helper to return `GIT_HARDENING_ARGS`;
  the sibling mocks are edited instead.
- Deepen-plan additions dropped by CTO R8c as redundant or not an independent control: `GIT_ASKPASS=/bin/false` /
  `core.askPass` and `GIT_SSH_COMMAND=/bin/false` defaults (the protocol allowlist blocks the paths they target),
  always-set `GIT_SSL_CAINFO` (subsumed by the pinned remote-rewrite residual), `core.excludesFile`, the four
  `gpg.*.program` keys (nothing invokes gpg once signing and signature verification are off), and a `PATH` pin (the
  helper filters empty and non-absolute `PATH` entries instead).
- Option-bag test hooks (`base`, a runtime throw on a caller-supplied `opts.env`, an exported argv-prefix constant, a
  shimmed-`git --version` row, a space/unicode-path row, a non-`main` branch row, a `filter.other.clean` row) -> cut
  per code-simplicity and DHH review: they test the tests, not a property. The `opts.env` rule becomes a narrowed
  parameter type.

### Measured facts (git 2.56.0, scratch repos, this session)

Spike scripts live in the session scratchpad only and are not committed. Arm A = today's invocation (no arguments,
`process.env`-derived env, a sentinel exported). Arm B = `--no-replace-objects -c core.hooksPath=/dev/null -c
core.fsmonitor=false -c core.attributesFile=/dev/null` plus a scrubbed env with `GIT_HARDENING_ENV`.

| Carrier | A (today) | B (shared args + scrubbed env) |
|---|---|---|
| `commondir` -> copied dir whose config sets `core.fsmonitor` | fsmonitor runs on status/add/commit/reset/diff | closed |
| `.git/config` direct `core.fsmonitor` | runs | closed |
| `config.worktree` (`extensions.worktreeConfig`) `core.fsmonitor` | runs | closed |
| `.git/hooks/pre-commit` | runs | closed (`core.hooksPath=/dev/null`) |
| `core.attributesFile` (global config or repo config) naming a filtered path | filter runs | closed (`GIT_CONFIG_GLOBAL=/dev/null` plus the `-c` override) |
| `commit.gpgsign=true` + planted `gpg.program` | program runs on commit | STILL RUNS (commit exits 128); closed by adding `-c commit.gpgsign=false` (re-measured: no run, commit succeeds) |
| `filter.zz.clean` via `commondir` + its `info/attributes` | runs (status/add/commit/reset) | STILL RUNS (status, add of the filtered path, commit, reset --hard, diff) |
| `filter.zz.clean` via `.git/config` + tracked `.gitattributes` | runs | STILL RUNS |
| `merge.mg.driver` via tracked `.gitattributes` on `pull --no-rebase` | not run in A (pull stopped earlier) | STILL RUNS |
| `diff.tc.textconv` via attribute | not a consumer verb | does not run on status/add/commit; runs only on `git diff` (not a consumer verb) |
| `url.<x>.insteadOf` in the `commondir` config | a tokened pull follows the rewrite | STILL FOLLOWS (pull went to the planted URL) |
| a helper that does run: server sentinel in env | visible | NOT visible |
| a helper that does run: the consumer's own auth variable | visible | visible (`GIT_INSTALLATION_TOKEN` seen by a filter helper in a hardened+scrubbed reset) |
| `remote -v`, `rev-list`, `for-each-ref`, `branch`, `merge-base`, `rev-parse` | no helper ran | no helper ran |
| `git commit` with `GIT_CONFIG_GLOBAL=/dev/null`, HOME a temp dir, no local identity | not run | rc=128 "Author identity unknown" (repo research pass) |
| bare repository as cwd with `-c safe.bareRepository=explicit` | works | `fatal: cannot use bare repository` (refused) |
| `HTTPS_PROXY`/`SSL_CERT_*` in the prod container env | grep of `apps/web-platform/Dockerfile`, `infra/cloud-init.yml`, `infra/ci-deploy.sh` finds none set | the passthrough list is a no-op in prod today |
| `core.worktree=<other directory>` in `.git/config` (deepen-plan, measured) | status/add/commit/reset operate on the OTHER directory (a foreign tenant dir would be staged, pushed, or overwritten by `reset --hard`) | STILL REDIRECTS under `-c core.worktree=<cwd>`; CLOSED by env `GIT_WORK_TREE=<cwd>` (status clean) |
| `remote.<n>.uploadpack` on a LOCAL-path remote (deepen-plan, measured) | planted program runs on fetch | STILL RUNS; CLOSED by env `GIT_ALLOW_PROTOCOL=https` (file transport refused); `GIT_ALLOW_PROTOCOL=file` set by a test restores the fixture |
| `protocol.ext.allow=always` + `url.<x>.insteadOf=ext::...` (security-sentinel pass, confirmed there; the lead's own probe was inconclusive) | shell runs on fetch | STILL RUNS under the shared args; blocked by `-c protocol.ext.allow=never` (sentinel run) |
| `--attr-source=<empty tree>` (git >= 2.40) (deepen-plan, measured) | not applicable | stops worktree `.gitattributes` filters; does NOT stop `.git/info/attributes` filters; named-filter `-c filter.zz.clean=` neutraliser works but cannot cover unknown names |

Consequences carried into the design: `-c` arguments close fsmonitor, hooks, `config.worktree`, attribute-file
sources and (with one added flag) commit signing; they do not close `filter.*`, `merge.*.driver` or URL rewriting.
Two further carriers need ENV, not `-c`: `GIT_WORK_TREE=<cwd>` (foreign worktree) and `GIT_ALLOW_PROTOCOL`
(local-exec transports on the network arms; the review round made it required on every call). The env scrub hides server
variables from a helper that reads only its own environment (not from a same-uid helper reading `/proc`), and a
consumer's own auth variable still reaches it. Open items are pinned as residuals (CTO F4, R7). Not yet measured
(Phase 1 measures them and pins the ones that fire, or drops the matching helper addition): `remote.origin.url`/`pushurl`,
`http.proxy`, `http.sslVerify`, URL-scoped `credential.<url>.helper`, `merge.verifySignatures` on `pull`,
`submodule.recurse` with `submodule.<n>.update=!cmd` on `pull`, `core.bare=true` against `GIT_WORK_TREE`, and a gitfile
`.git` pointing at a foreign gitdir.

### Deepen-plan findings (2026-11-09)

- Security-sentinel pass: the first measured table was not a complete carrier list. New rows above (`core.worktree`,
  local-exec transports) are the two with cross-tenant consequence; the CTO ruled both closable by env in this PR
  (R8a, R8b). The pass also asserts, from git docs, that `GIT_CONFIG_GLOBAL` stops the XDG config read, and that
  `core.pager`/`core.editor`/`sequence.editor`/`commit.template` need a TTY or editor flow that `execFile` does not
  provide (rated `needs-TTY`/`harmless`, not measured here).
- Verify-the-negative pass against code: `syncPush` and `ensureGitDataRemote` are exported and drivable as planned
  (`resolveInstallationId` is a dynamic import, intercepted by `vi.mock`; `ensureGitDataRemote` needs
  `GIT_DATA_STORE_ENABLED=true` and, in production mode, `GIT_DATA_SSH_HOST`); `checkpointInflightWork` is the
  exported entry for `runPlumbingGit` (also `restoreInflightCheckpoint`, `checkpointInflightWorkForConversation`);
  no in-scope consumer runs with a bare repository as cwd (the bare git-data store is remote-only and the isolated path
  sets `GIT_DIR`); `getAskpassDir()` reads the server's own `process.env.HOME`, not the child env; no test asserts
  `process.env` passthrough into a child git. Sibling-test breakage is larger than argv slicing: `test/session-sync-path-allowlist.test.ts`
  and `test/server/session-sync-protected-fallback.test.ts` mock `execFileSync` and branch on `args[0]` being the
  subcommand, and `test/git-data-replication.test.ts` reads `args[2]`/`[4]` positionally (content anchors: the
  `for-each-ref` and `update-ref` branches and the `remote` index read); these mocks must find the subcommand past the
  hardening block. `reportSilentFallback` call-count assertions in the session-sync tests all filter by `op` first, so
  new ops `auto-commit-pull`/`auto-commit-push` break none (reusing an existing op would).
- Partial mocks of `@/server/agent-env` that omit `...actual` exist in about a dozen unrelated suites but none of the
  in-scope server modules imports `agent-env` today; importing the new leaf directly avoids the exposure.
- The built image's `git --version` is unmeasured (`node:22-slim`, digest-pinned, Debian; Dockerfile floor 2.38). The
  helper therefore uses only `-c key=value` pairs and environment (never a new global option): unknown config keys
  never fail an old git, an unknown option exits 129.

### Institutional learnings applied

- `2026-11-09-a-guard-rewrite-closed-the-reported-bypass-and-opened-two-narrower-ones.md` (PR 12485): a flag or `-c`
  denylist cannot close config carriers; use a real-filesystem oracle. Applied: real git, not argv assertions.
- `2026-11-05-a-review-seat-simulating-an-inherited-git-dir-wrote-into-the-live-repo-and-the-shared-config.md`: a fixture
  that does not scrub `GIT_DIR`/`GIT_INDEX_FILE` writes into the live repo. Applied: hermetic env, throwaway roots,
  a before/after snapshot of the worktree's local config.
- `2026-11-06-a-guard-on-the-registrar-result-is-not-a-guard-on-the-published-set-and-the-hardening-prose-was-false-four-times.md`:
  name the residual and falsify every "closed" sentence. Applied: PR and ADR wording is generated from the measured table.
- `2026-10-13-an-identity-read-from-an-untrusted-repo-needs-a-layout-anchor-a-size-gate-and-fixtures-that-can-discriminate.md`:
  a recording stub alone makes "never ran git" vacuous; the witness must arm real git.
- `2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md`: each row needs a control proving the refused
  action would otherwise succeed. Applied: the raw-git twin control.
- `2026-04-23-git-askpass-over-shell-helper-for-headless-auth.md`: sibling tests that mock `child_process` without
  `execFile` break module load. Applied: new tests do not mock `child_process`; hardening args go BEFORE `HELPER_RESET`.
- Ratchet learnings (`2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree.md`): accept rows are
  keyed by anchor; re-run after every sync.

### Census of host-side git callers (grepped, not enumerated from memory)

Command (multi-line aware; the work phase re-runs it tree-wide under `apps/web-platform/server`, `app` and `lib`
and the Guard 1 census row encodes the classification):
`git grep -n -E -A2 '(execFile|execFileSync|spawn|spawnSync)\(' -- apps/web-platform/server | grep -n '"git"'`
plus `git grep -n 'gitWithInstallationAuth\|gitWithPrivateKeyAuth'`.

In scope (CTO F2, R3): `runConnectedRepoGit` (`session-sync.ts`); `realLocalGit` (`ensure-workspace-repo.ts`); the five
local execs in `git-data-replication.ts` and the push through `gitWithPrivateKeyAuth` (which also carries the
`git-data-client.ts` fetch and clone); `gitWithInstallationAuth`'s legacy arm, which carries every legacy caller
(`workspace.ts` clone, `workspace-sync.ts`, `ensure-workspace-repo.ts` clone, `session-sync.ts` pull and push and
protected-fallback, `push-branch.ts` legacy branch); `runPlumbingGit` (`inflight-checkpoint.ts`, migrated onto the helper).

Census-only residuals, not fixed here: `workspace.ts` fresh `git init`, `git-config-atomic.ts`,
`worktree-config-seed.ts`, `push-branch.ts` (`cat-file` and `git config` writes into the workspace), `context-queries-hook.ts`,
`git-worktree-validity.ts` (own minimal env), `event-ship-merge.ts` (explicit small env), `_cron-safe-commit.ts`,
`cron-follow-through-monitor.ts`, `cron-github-cidr-refresh.ts`, and the other cron helpers
(`cron-compound-promote`, `cron-content-vendor-drift`, `cron-weekly-analytics`, `cron-content-publisher`,
`cron-rule-prune`, `cron-strategy-review`, `_cron-claude-eval-substrate`), which mostly clone fresh into ephemeral
directories. `sshWithPrivateKeyAuth` spawns `ssh`, not git, and reads no workspace config. The isolated-`GIT_DIR` paths
(`push-branch.ts` isolated `checkCommitPresent`, `git-hardened-env.ts`) are operator-held and untouched.

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief | Reality | Plan response |
|---|---|---|
| "reuse the inflight-checkpoint pattern" with an env "built from buildScrubbedEnv" | `runPlumbingGit` spreads `process.env`; `buildScrubbedEnv` is used by `runGit` in the gates module | Helper composes the `runGit` recipe; `inflight-checkpoint` is migrated onto it (CTO F2 ii). |
| "git-data-replication (~:632/904/920)" | Those are the local sites. The push goes through `gitWithPrivateKeyAuth`, which spreads `process.env` and has the transport key reachable in the server env | Included under the git-data-replication consumer (CTO F2 i). |
| "legacy `gitWithInstallationAuth` (~git-auth.ts:315-329)" | `authEnv` already sets `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, `GIT_TERMINAL_PROMPT=0`; gaps are `...process.env`, no hardening arguments, no `GIT_NO_REPLACE_OBJECTS`. `authEnv` is SHARED with the `hardened` arm | Legacy arm gains the helper; `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_NOSYSTEM` are stripped from the legacy env only (CTO R5); the shared `authEnv` object and the `hardened` ternary arm are not changed. |
| "the commit still succeeds" | `GIT_HARDENING_ENV` nulls `GIT_CONFIG_GLOBAL` and `buildScrubbedEnv` moves HOME to a temp dir: both removed the image's `~/.gitconfig` identity, so a workspace with no local identity fails rc=128 | CTO F1: helper points `GIT_CONFIG_GLOBAL` at the image-owned identity file; local identity still wins. Tested at helper level with real git and a temp identity file; at consumer level the seeded-local-identity commit is asserted. |
| "probe-coverage EXCLUDED rows; affected-index accept rows" for the touched files | Searched: no EXCLUDED or probe-coverage ledger names the four modules; `scripts/ci-pr-affected-audit.accept.tsv` has no row for them, but has anchor-keyed rows for `apps/web-platform/server/agent-env.ts` (also edited here), re-checked in Phase 5. A TS suite under `apps/web-platform/test/` is covered by `WEBPLAT_APP_PATHS` and is not an affected-index pair. `git-auth.ts` IS in `AFFECTED_TESTS_SCRIPTS_NO_TOFU_SSH_MUTATION_PATHS` (`scripts/lib/test-affected-paths.sh`), so that battery re-arms. `.github/CODEOWNERS` names `git-auth.ts` and `git-data-replication.ts` | Phase 5 runs the no-tofu-ssh battery and the replay audit; any new accept row uses a typed kind with file:line evidence. CODEOWNERS review is a merge-time fact (Open items). The advisory affected-index ratchet itself is NOT fixed here. |
| "Expect fsmonitor via commondir RED on current main" | Confirmed by measurement (arm A) | Phase 1 records the RED run. |
| (not in the brief) commit signing | `commit.gpgsign` + `gpg.program` in a planted config runs on the session-sync commit under the shared args | Helper-only `-c commit.gpgsign=false -c tag.gpgsign=false` (CTO R6; `_git-hardening.ts` untouched). |

## Files to Edit

- `apps/web-platform/server/session-sync.ts`: `runConnectedRepoGit` applies the helper after the existing argv guards, and its parameter type becomes `Omit<ExecFileSyncOptions, "env">` so a caller cannot pass `env`; the two auto-commit `catch` blocks keep their `log.warn` and also call the existing `reportSilentFallback` (feature `session-sync`, ops `auto-commit-pull` / `auto-commit-push`; CTO R4). No new Sentry alert.
- `apps/web-platform/server/ensure-workspace-repo.ts`: `realLocalGit` applies the helper (the `localGitFn` seam receives pre-hardening args, so seam-level tests are unaffected).
- `apps/web-platform/server/git-data-replication.ts`: the three `ensureGitDataRemote` execs, the `for-each-ref` exec and the `update-ref -d` exec go through the helper.
- `apps/web-platform/server/git-auth.ts`: legacy arm of `gitWithInstallationAuth` (args and env; `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_NOSYSTEM` removed from the legacy env only) and `gitWithPrivateKeyAuth` (args and env; its own `GIT_CONFIG_GLOBAL=/dev/null` removed). The `hardened` ternary arm, `HARDENED_GIT_ARGS`, `buildIsolatedGitEnv(hardened, authEnv)` and `writeAskpassScriptTo(hardened.gitDir)` keep their resulting behaviour (proved by the unmodified hardened tests).
- `apps/web-platform/server/inflight-checkpoint.ts`: `runPlumbingGit` migrates onto the helper; its `GIT_AUTHOR_*`/`GIT_COMMITTER_*` and caller `extraEnv` (including the temp `GIT_INDEX_FILE`) become helper extras.
- `apps/web-platform/server/compound-promote-create-gates.ts`: `buildScrubbedEnv`, `BaseEnv` and the forbidden-extra regex move to the new leaf; this file re-exports `buildScrubbedEnv`.
- `apps/web-platform/server/agent-env.ts`: imports `AGENT_GIT_GLOBAL_CONFIG` from the leaf and re-exports it (`test/dockerfile-git-version-floor.test.ts` imports it from here); one definition. The leaf must not import `agent-env.ts` (it imports providers and plugin-path); a partial `vi.mock` of `@/server/agent-env` elsewhere must still resolve the constant (checked by running the suites).
- `knowledge-base/engineering/architecture/decisions/ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md`: amend the "Host-side git in tenant workspaces" residual bullet of the 2026-11-09 amendment (a few lines: now covered, still open, corrected premise, and a pointer to the PR body for the census output so the ADR does not carry a stale list). No new ADR.
- Sibling tests, found by running the suites and listed in the PR body: `test/git-auth.test.ts` (the assertions that `GIT_CONFIG_GLOBAL` is `/dev/null` on the legacy and key-auth arms now expect the helper-owned identity file; the `pull`/`clone` argv assertions expect the hardening block before `HELPER_RESET`), `test/git-data-replication.test.ts` (positional argv reads such as the remote-add index and exact-argv assertions slice off the hardening block), and any `session-sync*`, `ensure-workspace-repo*`, `inflight-checkpoint*` row asserting exact argv or `process.env` passthrough.

## Files to Create

- `apps/web-platform/server/host-git.ts`: the leaf helper (imports `node:os` and `./inngest/functions/_git-hardening` only; `tmpdir()` evaluated at call time).
- `apps/web-platform/test/helpers/host-git-carrier-fixture.ts`: carrier planters, canary and env-dump helpers, raw-git twin runner, git-floor assertion (borrows ideas from `test/helpers/git-config-exec-fixture.ts`; does not edit it).
- `apps/web-platform/test/host-git-consumers-real-git.test.ts`: the RED-first battery and residual pins. It imports only the consumers and the fixture.
- `apps/web-platform/test/host-git.test.ts`: helper rows, created with the helper (not RED-first): env contents and scrub, extras last, passthrough only when set, identity rows with real git (temp identity file, absent file), gpg flags, layering row (source of `host-git.ts` imports only `node:os` and `_git-hardening`).
- `knowledge-base/project/specs/feat-one-shot-host-git-consumers-hardening/tasks.md` and `decision-challenges.md`.

Not edited: `git-hardened-env.ts`, `push-branch.ts`, `_git-hardening.ts`, `test/git-auth-hardened*.test.ts`, `test/push-branch-hardened.test.ts`, `test/push-branch-isolated-real-git.test.ts`.

## Implementation Phases

### Phase 0: preconditions (no product code)

1. `git --version` is 2.56.0 on this host (floor 2.38). The new suite asserts the floor in a `beforeAll` that THROWS (never `it.skip`/early return): `git version X is older than 2.38; the host-git hardening battery cannot run`.
2. Re-run `bash plugins/soleur/scripts/collision-precheck.sh 9601`.
3. `git grep -n 'bare' -- apps/web-platform/server | grep -i 'git'` and read the cwd of every in-scope exec: confirm no consumer runs with a bare repository as cwd (needed for `safe.bareRepository=explicit`; if any does, the pin is cut, CTO R1).

### Phase 1: RED first (local commit before any product change)

Write `host-git-carrier-fixture.ts` and `host-git-consumers-real-git.test.ts` against the CURRENT code.

Fixture contract (hermetic):

- env built from scratch, no inherited `GIT_DIR`/`GIT_INDEX_FILE` (the vitest `globalSetup` tripwire exits rc=97 otherwise; a server-set `GIT_DIR` row sets it only inside the child-spawn scope, after the tripwire); throwaway root per test; synthesized fixtures (`cq-test-fixtures-synthesized-only`); ephemeral ports and bounded timeouts for the local `node:http` and `ssh` rows.
- `process.env.SERVER_ONLY_SENTINEL = "SENTINEL-<random>"` set in `beforeEach`, restored in `afterEach`. Helper scripts append a tag line to a canary file OUTSIDE the workspace and write `env` to a per-helper dump file, so the test reads the exact environment a helper saw.
- Workspace: real `git init`, baseline commit, `knowledge-base/` content, a local `user.name`/`user.email` (as `provisionWorkspaceWithRepo` seeds), a bare "upstream" for pull and push rows.
- Carrier planters (a table, so rows are generated from it): `commondir` (a copied `.git` inside the workspace, e.g. `.cache-x/`, whose config carries fsmonitor, `filter.zz.clean`, `gpg.program` with `commit.gpgsign`, `diff.external`, `core.sshCommand`, `credential.helper`, `url.<x>.insteadOf`, plus `info/attributes`; `.git/commondir` pointing at it); `.git/config`; `config.worktree`; `.git/hooks/*`; `.git/modules/sub/config` with a gitlink `sub`; tracked `.gitattributes` with `filter` and `merge` drivers; `.git/info/attributes`; a repo `core.attributesFile`; a committed bare repository as cwd; `core.worktree` pointing at a sibling directory; `core.bare=true` against `GIT_WORK_TREE`; a gitfile `.git` pointing at a foreign gitdir; `remote.<n>.uploadpack` on a local-path remote; `protocol.ext.allow=always` plus an `ext::` `insteadOf`; `merge.verifySignatures` on `pull`; `submodule.recurse` with `submodule.<n>.update=!cmd` on `pull`.
- Twin control, defined: each carrier type runs ONCE, in `beforeAll`, under raw `git <verb>` (no hardening, fresh copy of the fixture, so it cannot mutate the state the hardened rows use) and the result is cached. A carrier that cannot fire on this git fails every row that uses it as "carrier not live". Carriers that are already inert on today's code (`core.sshCommand` against the key-auth arm because `GIT_SSH_COMMAND` wins; `credential.helper` against the legacy arm because `HELPER_RESET` wins; `diff.external`/`textconv` on consumer verbs) are labelled "pre-existing control / regression pin", have no raw twin expectation, and are excluded from the RED expectation.

Drivers (the real code paths; no new seams, CTO F5):

- session-sync: exported `syncPush` with `@/lib/supabase/tenant` (auth probe) mocked and `@/server/resolve-installation-id` returning null, so the function performs the real `remote -v`, `status`, `add`, `commit`, `rev-list` and returns before any network; `getAllowlistedChanges` is also called directly; `syncPull`'s auto-commit and legacy `pull` ride the same fixture.
- ensure-workspace-repo: the exported overlay entry that reaches `realLocalGit` (the precedent `ensure-workspace-repo-ancestry-real-git.test.ts` drives `ensureWorkspaceRepoCloned` with the real overlay; reuse its mock set).
- git-data-replication: `ensureGitDataRemote` (real, exported); `gitWithPrivateKeyAuth` with a local `file://` bare remote for `push` (hooks), plus a fake `ssh` first on `PATH` (the precedent test does this) for the `core.sshCommand` row and for the rewritten-host row (a planted `insteadOf` toward another host: the recorded ssh argv must still carry `HostKeyAlias=git-data`, `StrictHostKeyChecking=yes` and the pinned `UserKnownHostsFile`, which is the control that keeps the transport key from authenticating to a rewritten host; this pins the control, it does not measure a real handshake); a `fetch` row for the `git-data-client.ts` verb.
- legacy arm: `gitWithInstallationAuth(["pull", ...], 1, { cwd })` with ONLY `@/server/github-app` `generateInstallationToken` mocked; a local `node:http` server returning 401 for the `credential.helper` row.
- inflight-checkpoint: the exported checkpoint entry that reaches `runPlumbingGit` (with the temp `GIT_INDEX_FILE` and author identity surviving the scrub).

Assertions per row, on observed effects:

- A1 no closable-carrier canary file written (fsmonitor, hook, `config.worktree`, `.git/modules/*/config`, `commit.gpgsign` program, attribute-file filter, `uploadpack` on a local-path remote, `ext::` rewrite); and with `core.worktree` pointing at a sibling directory, that directory's files are neither staged, committed, pushed nor overwritten by `reset --hard` (a content check on the sibling);
- A2 the sentinel is absent from every env dump of every helper that did run (the weight of this assertion sits on the residual-pin rows, because closable carriers never run and leave no dump);
- A3 the operation's own success (commit lands with the seeded local identity; reset moves HEAD; remote is configured; push reaches the bare remote; checkpoint ref is written);
- A4 a committed bare repository as cwd is refused when the pin is present (helper-level row).

Residual-pin rows (named `RESIDUAL`, one per attribute source or config key, generated from the planter table): filter-clean helper runs through each attribute source; `merge.*.driver` runs on legacy `pull`; server sentinel absent from each dump; the consumer's own auth variable present in the legacy arm dump (the installation token of that user's repository) and, for the key-auth arm, the `GIT_SSH_COMMAND` carrying the transport key file path is present in a helper's dump (a cross-tenant credential reference, stated as such); `insteadOf` followed; plus the keys Phase 1 measures for the first time (`remote.origin.url`/`pushurl`, `http.proxy`, `http.sslVerify`, URL-scoped `credential.<url>.helper`), each pinned if it fires. If a measured row shows the key-auth arm authenticating to a non-origin host, it is NOT pinned: the key-auth arm is closed inside this PR with an explicit URL (CTO R7 exception). A comment on each pin states "measured open item, not a control".

Expected RED on current code (and recorded): fsmonitor via `commondir` (A1) for session-sync and legacy pull; hooks and fsmonitor for the others; `gpg.program` on commit; the sentinel present in the residual-pin dumps. The RED run (SHA plus per-row counts, no env values) goes in the PR body; the RED commit is local and is pushed together with the GREEN commits so the draft's CI does not carry a red head.

### Phase 2: the leaf helper

`apps/web-platform/server/host-git.ts` exports:

- `buildScrubbedEnv` (moved verbatim with its regex and `BaseEnv`), `AGENT_GIT_GLOBAL_CONFIG` (moved; `agent-env.ts` re-exports).
- `hostGitInvocation(args, opts) -> { args: string[]; env: NodeJS.ProcessEnv }`, `opts = { cwd?, extraEnv?, allowProtocol?, globalConfig? }` (`globalConfig` exists only for the helper-level identity rows and defaults to `AGENT_GIT_GLOBAL_CONFIG`; it is a parameter, not a consumer-visible seam). `cwd` is the workspace root for every working-tree command (omitted for `clone`/`init`); `allowProtocol` is REQUIRED for the two network arms (`gitWithInstallationAuth` legacy passes `https`, `gitWithPrivateKeyAuth` passes `ssh`) and omitted for the local-only consumers; tests widen it through the same parameter (for example `file:https`), never through a separate seam, and a census assertion requires production call sites to pass only those two constants (CTO R8b).
  - `args = [...GIT_HARDENING_ARGS, "-c", "safe.bareRepository=explicit", "-c", "protocol.ext.allow=never", "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false", ...<each of the following only if its Phase 1 row shows it fires under the shared args: "-c", "merge.verifySignatures=false", "-c", "log.showSignature=false", "-c", "submodule.recurse=false", "-c", "fetch.recurseSubmodules=false">, ...args]`. Only `-c key=value` pairs and environment are used, never a new global option (the built image's git is unmeasured and an unknown option exits 129; CTO R8c, R8d). A caller that prepends `HELPER_RESET` passes it inside `args`, after the block.
  - `env = { ...buildScrubbedEnv({}, process.env) with empty and non-absolute PATH entries dropped, ...GIT_HARDENING_ENV, GIT_CONFIG_GLOBAL: globalConfig, GIT_CONFIG_NOSYSTEM: "1", GIT_TERMINAL_PROMPT: "0", GIT_WORK_TREE: cwd (when given), GIT_ALLOW_PROTOCOL: allowProtocol (when given), <passthrough keys when set>, ...extraEnv }`. Whether `core.bare=true` defeats `GIT_WORK_TREE` and whether a gitfile `.git` to a foreign gitdir escapes it is measured in Phase 1: if `isStrandingFilePointer` / the worktree-shape classifier in `git-worktree-validity.ts` can flag an escaping or unclassifiable pointer cheaply, the helper refuses that workspace and mirrors the refusal to Sentry; otherwise it is pinned as a named residual (CTO R8a).
  - Passthrough keys, only when set in the server env: `SSL_CERT_FILE`, `SSL_CERT_DIR`, `GIT_SSL_CAINFO`, `HTTPS_PROXY`, `https_proxy`, `NO_PROXY`, `no_proxy` (CTO R3; the server env is not agent-writable; prod sets none today). The list is defined in the leaf, not imported from `git-hardened-env.ts`.
  - `extraEnv` is merged AFTER the scrub (the scrub refuses `GIT_*`/`TOKEN`/`SECRET` extras by design; the call-site's own `GIT_ASKPASS`, `GIT_INSTALLATION_TOKEN`, `GIT_SSH_COMMAND`, author identity and temp index live here, code-authored, never agent-authored).
  - Server `GIT_*` variables (`GIT_DIR`, `GIT_EXEC_PATH`, `GIT_OPTIONAL_LOCKS`) are dropped by the scrub.

Rows in `test/host-git.test.ts`: args and env contents; identity file wins over `GIT_HARDENING_ENV`'s `/dev/null`; a real-git commit in a workspace with NO local identity succeeds through a temp identity file passed as `globalConfig`; an ABSENT identity file makes the same commit fail with "Author identity unknown" (pins the dev/CI behaviour; prod relies on the Dockerfile build-time `git var GIT_AUTHOR_IDENT` check); `extraEnv` wins last; no `process.env` key outside the allowlist appears; passthrough keys only when set; layering (the leaf's source imports only `node:os` and `_git-hardening`).

### Phase 3: wire the consumers (separate commits so the network arms revert alone)

Commit order after the RED commit: (a) helper + moves; (b) local-only consumers (`runConnectedRepoGit`, `realLocalGit`, the five replication execs, `inflight-checkpoint`) plus the Sentry mirror; (c) `gitWithPrivateKeyAuth`; (d) `gitWithInstallationAuth` legacy arm; (e) sibling test updates ride with the commit that breaks them; (f) ADR amendment.

- `runConnectedRepoGit`: after the verb allowlist and forbidden-flag guards, `execFileSync("git", h.args, { ...opts, env: h.env })`; the type excludes `env`.
- `realLocalGit`: `execFileAsync("git", h.args, { cwd, env: h.env, timeout, killSignal, maxBuffer })`.
- `gitWithPrivateKeyAuth`: `fullArgs = h.args` with `HELPER_RESET` inside; `extraEnv: { GIT_SSH_COMMAND, GIT_TERMINAL_PROMPT, GIT_TERMINAL_PROGRESS }`; no `GIT_CONFIG_*` of its own.
- Legacy arm of `gitWithInstallationAuth`: hardening block first, then `HELPER_RESET`, then `args`; `extraEnv` is `authEnv` minus `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_NOSYSTEM`. In the `hardened` arm nothing changes (its argv order, which puts `HELPER_RESET` first, stays).
- Existing exact-argv sibling assertions are updated to slice off the hardening block (computed from the helper's own output in the test, not a copied literal list). The mocks that branch on `args[0]` being the subcommand (`test/session-sync-path-allowlist.test.ts`, `test/server/session-sync-protected-fallback.test.ts`) are changed to find the subcommand past the block, and the positional index reads in `test/git-data-replication.test.ts` shift by the block length.
- Scheme grep (before wiring `allowProtocol`): every remote URL scheme the legacy and key-auth callers can see, including `test/` and e2e fixtures (`git grep -n 'https://\|ssh://\|file://' -- apps/web-platform/server apps/web-platform/test apps/web-platform/e2e`); results go in the PR body. A scheme outside `https`/`ssh` on a network arm becomes a documented parameter value, not a silent break.
- `GIT_WORK_TREE` is set from the workspace path each consumer already holds (`workspacePath`/`cwd`); `clone` and `init` pass no `cwd`.

### Phase 4: residual wording and ADR

Amend ADR-050 (2026-11-09 amendment, host-side git bullet): now covered / still open (measured table) / corrected `inflight-checkpoint` premise / the structural closure is the isolated-`GIT_DIR` path (operator-held). Wording is generated from the measured table, not from memory. Draft the PR body: Ref lines, the "does NOT claim" block, `Follow-ups not filed`, the rollback sentence, the census output. No public/marketing/legal text changes; `knowledge-base/legal/public-security-claim-ledger.md` is not touched.

### Phase 5: ratchets and gates (run, then record outputs)

1. The affected unit-suite families (`session-sync*`, `git-auth*`, `git-data-replication*`, `ensure-workspace-repo*`, `inflight-checkpoint*`), plus `compound-promote-create-gates`, `agent-env`, `dockerfile-git-version-floor`, and the hardened tests UNMODIFIED.
2. `bash tests/scripts/test-no-tofu-ssh-mutation.sh` and `tests/scripts/test-no-tofu-ssh.sh` (`git-auth.ts` is in that battery's edge list).
3. `test/sentry-kb-sync-protected-fallback-alert-op-contract.test.ts` (reads `session-sync.ts` literals), `session-sync-sentry-mirror` tests (the new mirror calls must not break call-count assertions), and `.github/scripts/check-auto-commit-density.sh` (the `AUTO_COMMIT_MSG_*` strings are unchanged).
4. `python3 scripts/ci-pr-affected-replay.py audit` (its own flags; pass = exit 0 and summary counts unchanged against the merge-base). Re-check the anchor-keyed accept rows that name `agent-env.ts`. A new accept row needs one typed `ACCEPT_KINDS` kind and file:line evidence; a row on a file the suite really reads is wrong. The advisory affected-index ratchet itself is not repaired here.
5. `python3 scripts/lint-guard-contract.py <this plan>` and `markdownlint-cli2` on the plan.
6. `test/repo-wide-containment.test.ts` (new tests read only under `apps/web-platform`).
7. Forbidden-token sweep over `git diff origin/main...HEAD`, the PR body and every commit message, using the brief's forbidden-number list kept in a file outside the repo (the pattern itself must not appear in any committed file). Expected output: empty.
8. A before/after snapshot of this worktree's local git config (`git config --local --list`) around the suite: identical.

### Phase 6: ship-time requirements (carried to `soleur:work` / `soleur:ship`)

- Pre-merge, credential-less, read-only check (CTO F3, R3): `git ls-remote https://github.com/octocat/Hello-World` under the real helper's env (scrubbed, HOME a temp dir, passthrough keys when set), run on the named dev host with the git version recorded, pasted as an "I checked" line that says it measures nothing about the prod container and does not exercise the token path. If it fails, the legacy-arm commit is dropped from this PR and recorded under `Follow-ups not filed` (no second PR).
- Rollback sentence for the PR body: "revert the network-arm commit(s) and redeploy through the normal pipeline; the local-only consumers are unaffected."
- ADR-276 draft-run `test` rows via `ci-head-verdict.sh` are read from INSIDE a git worktree (this one).
- tenant-integration `40P01` deadlocks/timeouts: one rerun of the failed jobs, not a fix.
- Never sync an armed or queued PR without explicit operator OK; if a ratchet needs a refresh after main moves, ask the operator or disarm first.
- Follow-ups are NOT filed as issues (brief): they go in the PR body under `Follow-ups not filed` with draft issue text. No comment is posted on any existing issue.
- Post-merge read (carry-forward, owned by whoever runs `soleur:postmerge` after deploy): Sentry counts for feature `session-sync` ops `syncPull`, `syncPush`, `auto-commit-pull`, `auto-commit-push`, the git-data replication `push failed` query, and clone-failure reports (`AUTH_FAILED`, `CLONE_NETWORK_ERROR`), compared against the pre-deploy 24 hours; a sustained rise means revert the network-arm commit(s). The delayed 24-hour read cannot be done inside one session and cannot be turned into a tracker (no issue may be filed), so it is listed as carry-forward.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "write a real-git (git >= 2.38; fail loudly if older) RED test FIRST" | Phase 0 step 1, Phase 1 | mapped |
| 2 | "planting agent-authorable `.git` carriers (`commondir` redirect to a directory whose config sets `core.fsmonitor`, `diff.external`, `filter.*.clean`, `core.sshCommand`, `credential.helper`; `.git/info/attributes`; tracked `.gitattributes`; `.git/modules/*/config`, `config.worktree`)" | Phase 1 carrier planters | mapped |
| 3 | "running the real code paths of session-sync `runConnectedRepoGit` ... ensure-workspace-repo `realLocalGit` ... git-data-replication ... and legacy `gitWithInstallationAuth` (... stubbed token seam)" | Phase 1 drivers | mapped |
| 4 | "Assert: no canary file is written, no server-only env var ... reaches a planted helper that dumps its environment, and the commit still succeeds." | Phase 1 A1-A3 | mapped |
| 5 | "Expect fsmonitor via commondir RED on current main." | Phase 1 expected-RED record | mapped |
| 6 | "one shared helper returning GIT_HARDENING_ARGS plus an env built from buildScrubbedEnv plus GIT_HARDENING_ENV ... used by all four consumers, each keeping its own auth vars" | Phase 2, Phase 3 | mapped |
| 7 | "Do NOT touch the isolated-GIT_DIR push path" | Files to Edit (not edited list), AC8 | mapped |
| 8 | "pin it as a measured residual with a test asserting current behaviour; do not claim closure without a structural control" | Phase 1 residual-pin rows, Phase 4 | mapped |
| 9 | "State plainly in the PR what the control does NOT claim" | PR-body block, Phase 4 | mapped |
| 10 | "`Ref #9601` and `Ref` to the earlier git-read hardening work ... never a closing keyword; brand-survival threshold stays `single-user incident`; file no issue and post no comments" | AC9, User-Brand Impact | mapped |
| 11 | "check ratchets that reference the touched files ... ADR-276 draft-run `test` rows ... 40P01 ... Never sync an armed or queued PR" | Phase 5, Phase 6 | mapped |
| 12 | "The final report must carry: residuals (a), operator never-done items (b), open items (c) ..." | Handoff block at the end of this plan | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `host-git.ts` leaf with `{args, env}` | "one shared helper returning GIT_HARDENING_ARGS plus an env built from buildScrubbedEnv plus GIT_HARDENING_ENV" | asked |
| Moving `buildScrubbedEnv` into the leaf, re-export from the gates module | "an env built from buildScrubbedEnv" | inferred - justification: CTO F6 (importing the gates module into `git-auth.ts` drags observability and cron modules into every git consumer); re-export keeps existing imports green |
| `gitWithPrivateKeyAuth` on the helper | "git-data-replication (~:632/904/920)" | inferred - justification: CTO F2(i); the replication push is the same consumer and spreads `process.env` |
| `inflight-checkpoint` migration | "reuse the inflight-checkpoint pattern" | inferred - justification: CTO F2(ii); the brief's premise that it already scrubs is wrong |
| `AGENT_GIT_GLOBAL_CONFIG` as `GIT_CONFIG_GLOBAL`, its move, stripping `GIT_CONFIG_*` from the legacy/key envs | "and the commit still succeeds" | inferred - justification: CTO F1, R5; `GIT_CONFIG_GLOBAL=/dev/null` removes the fallback identity (measured rc=128) |
| `safe.bareRepository=explicit` | "harden the host-side git consumers" | inferred - justification: CTO R1; kept only with the Phase 0 grep and a measured bare-cwd row, cut if any consumer runs in a bare directory (code-simplicity dissent recorded) |
| `commit.gpgsign=false` / `tag.gpgsign=false` | "no canary file is written" | inferred - justification: CTO R6; measured: a planted `gpg.program` runs on the session-sync commit under the shared args |
| `SSL_CERT_*`, `GIT_SSL_CAINFO`, proxy passthrough when set | "and the commit still succeeds" (the network arms must keep working) | inferred - justification: CTO F3, R3; a no-op in prod today (no such env set), keeps TLS behaviour unchanged if it is ever set |
| Sentry mirror at the two auto-commit catches | "the commit still succeeds" | inferred - justification: CTO R4 and `cq-silent-fallback-must-mirror-to-sentry`; the headline failure this change can expose (identity) was a bare `log.warn` |
| ADR-050 bullet amendment | "State plainly in the PR what the control does NOT claim" | inferred - justification: the recorded residual lives in ADR-050; leaving it stale contradicts the plan-as-deliverable rule (CTO F7) |
| `GIT_WORK_TREE=<cwd>`, `GIT_ALLOW_PROTOCOL` on the network arms, `-c protocol.ext.allow=never`, measured-or-dropped `-c` additions (`merge.verifySignatures`, `log.showSignature`, `submodule.recurse`, `fetch.recurseSubmodules`), PATH-entry filtering | "harden the host-side git consumers" | inferred - justification: CTO R8a-R8c; each closes a carrier measured or sentinel-confirmed at deepen-plan time (`core.worktree` redirect to a foreign tenant dir, local-exec transports on the network arms); the unmeasured ones ship only if their Phase 1 row fires |
| Carrier-presence preflight | - | descoped - justification: CTO F4 |

### Split Assessment

- Subsystems touched: 3 - `apps/web-platform/server`, `apps/web-platform/test`, `knowledge-base`
- Planned files: 14 edited or created named entries plus the sibling-test edits found by the suites (about 18 in total) | Estimated changed lines: ~750
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (the brief mandates exactly one PR). Pipeline-written artifacts that appear in the diff and are expected: `knowledge-base/INDEX.md` (index refresh) and `knowledge-base/project/specs/feat-one-shot-host-git-consumers-hardening/session-state.md`.

## Acceptance Criteria

Pre-merge (PR):

- [ ] AC1. `host-git-consumers-real-git.test.ts` was run RED against the unmodified consumers first and is GREEN at the end. The RED run (SHA and per-row counts) in the PR body shows fsmonitor via `commondir` executing for session-sync and legacy `pull`, and `gpg.program` on commit; the RED battery imports no module that does not exist at that commit.
- [ ] AC2. Every carrier type has a cached raw-git twin; a carrier that cannot fire fails its rows as "carrier not live"; carriers inert on today's code are labelled "pre-existing control / regression pin".
- [ ] AC3. For each of the FIVE consumers (session-sync, ensure-workspace-repo, git-data-replication including the key-auth push, the legacy installation-auth arm, inflight-checkpoint): no fsmonitor, hook, `config.worktree`, `.git/modules/*/config`, attribute-file filter, signing program, `core.sshCommand`, `credential.helper` or `diff.external` canary is written; no server-only sentinel appears in any env dump; the operation succeeds.
- [ ] AC4. Helper-level rows: a workspace with NO local identity commits through a temp identity file; the default `globalConfig` is `AGENT_GIT_GLOBAL_CONFIG` (one definition); an absent file fails with "Author identity unknown" (pinned); a consumer-level commit lands with the seeded local identity.
- [ ] AC3a. With `core.worktree` pointing at a sibling directory, the sibling's content is untouched by every consumer (staging, commit, push, `reset --hard`); with `uploadpack` on a local-path remote and an `ext::` rewrite, no canary is written on the two network arms; a gitfile `.git` to a foreign gitdir is either refused by the shape check (with a Sentry mirror) or pinned as a named residual.
- [ ] AC3b. Every helper addition outside the CTO's R6 and R8a-R8b rulings (`merge.verifySignatures`, `log.showSignature`, `submodule.recurse`, `fetch.recurseSubmodules`) ships only with a Phase 1 row showing it fires under the shared args; otherwise it is dropped from the PR. The helper uses only `-c key=value` pairs and environment, never a new global option.
- [ ] AC5. `RESIDUAL` rows exist for `filter.*` (each attribute source), `merge.*.driver` on `pull`, repo-config remote rewriting (every measured key), the legacy arm's installation token and the key-auth arm's transport-key reference; comments say "measured open item, not a control". The key-auth rewritten-host row shows the host-key pin options in the recorded ssh argv.
- [ ] AC6. Git older than 2.38 makes the suite THROW (`beforeAll`), no `skip`.
- [ ] AC7. `buildScrubbedEnv` and `AGENT_GIT_GLOBAL_CONFIG` each have one definition (the leaf); `compound-promote-create-gates.test.ts` and `dockerfile-git-version-floor.test.ts` pass unmodified; `host-git.ts` imports only `node:os` and `_git-hardening`.
- [ ] AC8. The isolated-`GIT_DIR` path is untouched: `git diff --stat origin/main...HEAD -- apps/web-platform/server/git-hardened-env.ts apps/web-platform/server/push-branch.ts apps/web-platform/server/inngest/functions/_git-hardening.ts` is empty, none of the hardened tests is modified, and they all pass.
- [ ] AC9. PR body: `Ref #9601`, `Ref` PR 12485 (git-read hardening, 2026-11-09) in prose, no closing keyword in the PR body, commit messages or plan; #9601 is not edited or commented; no issue filed; no comment posted; the "does NOT claim" block verbatim; `Follow-ups not filed`; rollback sentence; census output; sibling-test edits listed.
- [ ] AC10. Phase 5 gates all recorded (suites, no-tofu-ssh battery, source-pin and density checks, replay audit, guard-contract lint, markdownlint, containment test, forbidden-token sweep empty, local-config snapshot identical). Any accept row has one typed kind and file:line evidence.
- [ ] AC11. The two auto-commit catches call `reportSilentFallback` with feature `session-sync` and ops `auto-commit-pull` / `auto-commit-push`; no Sentry alert is created.
- [ ] AC12. The network-arm changes are separate commits; Phase 3 order is followed; ADR-050 bullet amended; the public-claim ledger is untouched; the dev-host `ls-remote` line is in the PR, labelled as not a prod measurement.

Post-merge (operator-free, agent-run, carry-forward): the Sentry read in Phase 6 against the pre-deploy baseline. No operator action is required by this plan.

### PR-body "does NOT claim" block (verbatim)

> This change does not isolate host-side git from the workspace `.git`: host-side git still reads the repository's
> config. It adds `-c` arguments, a few environment pins (`GIT_WORK_TREE`, `GIT_ALLOW_PROTOCOL` on the two network
> arms) and a scrubbed environment, which close fsmonitor, hooks, `config.worktree`, attribute-file sources, commit
> signing, a `core.worktree` redirect, the measured local-exec transport carriers (`uploadpack` on a local-path remote,
> `ext::`). The scrubbed environment hides server variables only from a helper that reads its own environment (a same-uid helper can read the server's `/proc` environ). It does NOT close `filter.*` drivers (through
> `.git/info/attributes`, a `commondir` redirect or a tracked `.gitattributes`), `merge.*.driver`, repo-config remote,
> proxy and TLS settings (including `url.<x>.insteadOf` toward an https or ssh host), or any other repo-config execution path that
> was not measured. A consumer's own auth variable still reaches any helper that runs: the installation token in the
> legacy arm, and in the key-auth arm a helper that runs can READ the 0600 transport key file during the push (the
> pinned host key protects the handshake, not the file). Those are pinned by tests as measured open items. It says
> nothing about in-sandbox git, Bash-created `.git` members, `bash_autonomous` or batch-grant grammar binding,
> pre-poisoned workspaces, or a production TLS or egress measurement (not measured). The isolated-`GIT_DIR` push path
> and its tracking issue are not closed or touched. Ref #9601.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Spawned twice. Round 1: seven forks (F1-F7) and five added forks ruled. Round 2 after plan review: R1-R7 ruled (keep `safe.bareRepository` with a grep and a measured row; cut `allowProtocol`; one PR with the network arms as separate revertable commits and a proxy/SSL passthrough when set; mirror the auto-commit failures to Sentry; strip `GIT_CONFIG_*` from the legacy and key envs; add signing-off flags if measured; pin the wider remote/proxy/TLS residual set). Operator-needed actions: none. Rulings are rows in `decision-challenges.md`.

Legal: not relevant. No public, marketing or legal text changes; any legal wording or public security claim sign-off stays operator-owned and is not drafted here. Product/UX: no UI surface in Files to Edit/Create (mechanical override checked), so the Product/UX Gate does not run. CPO: reviewed at plan time (advisory, no `AskUserQuestion`): SIGN WITH CONDITIONS; the four conditions are folded in (key-auth residual scoped separately and stated cross-tenant; auto-commit failure mirrored to Sentry; `safe.directory`/bare-repo behaviour covered by the Phase 0 grep and the bare-cwd row; rollback path decided: revert the network-arm commits). GDPR gate (trigger: declared `single-user incident` threshold): run, no findings. The only regulated-path regex hit is `git-auth.ts` through the broad `*auth*` pattern, an accepted false positive; no schema, column, PII table, foreign key, vendor or special-category surface is touched, and the change narrows which process variables a child git sees (an Art. 32 benefit).

## User-Brand Impact

- **If this lands broken, the user experiences:** the end-of-session auto-commit or pull silently stops (identity loss, or a scrubbed environment that breaks the HTTPS clone or pull), so a user's knowledge-base edits never reach their GitHub repository, or a new session cannot open the workspace; the visible symptom is "Sync pull failed - continuing with local state" and unpushed work. After this change the two auto-commit failures also reach Sentry.
- **If this leaks, the user's data / workflow is exposed via:** a prompt-injected agent session in one workspace plants a `.git` carrier (a `commondir` redirect to a directory it authored); the server's next host-side git run, outside the sandbox, executes the carrier's helper with the server's environment, which holds the database service-role key, the BYOK encryption key and the git-data transport key. That reaches other tenants, not only the author. After this change the server-only variables are absent from the OWN environment of a helper that runs, but a same-uid helper can still read the server's `/proc/<pid>/environ` (measured in review), so any carrier that executes is a full same-uid compromise, including other tenants' workspace directories (the sandbox protects only the agent's own tree). A `filter.*` or `merge.*.driver` helper still runs and still sees the consumer's own auth variable: the installation token of that same user's repository in the legacy arm, and, in the key-auth push, the `GIT_SSH_COMMAND` that names the cross-tenant git-data transport key file, which a same-uid helper that runs can read during the push. Repo-config remote rewriting toward an https host can still redirect a tokened fetch or pull (the askpass script answers for any host and is shared with the operator-held isolated arm). The review round added: a `.git` that is a gitfile, a symlink or carries `commondir` is refused before git runs (a preflight; measured for session-sync and `ensureGitDataRemote`), `GIT_ALLOW_PROTOCOL` is required on every call (`none` for local-only consumers), and the git-data push goes to the explicit server-derived URL behind a `url.*` preflight guard. Those are pinned residuals, not controls. The env pins (`GIT_WORK_TREE`, `GIT_ALLOW_PROTOCOL` on the network arms) close the measured foreign-worktree and local-exec transport carriers; any other repo-config execution path that was not measured remains open.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** ratified by the CTO 2026-11-09 for the preceding git-read change and carried forward unchanged: execution needs only one prompt-injected session in one workspace, and the server-environment reach is cross-tenant, so `aggregate pattern` would understate it.

`requires_cpo_signoff: true` is set in the frontmatter. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what: Existing Sentry fallbacks and pino logs of the consumers; a regression of this change appears as these events rising, there is no new heartbeat (the helper is a pure function with no process of its own)
  cadence: per session start (clone/overlay) and per session end (auto-commit, push, replication)
  alert_target: existing Sentry issue alerts for feature session-sync and the git-data replication failure queries in Better Stack
  configured_in: apps/web-platform/infra/sentry/issue-alerts.tf (session-sync protected-fallback alert); apps/web-platform/server/session-sync.ts reportSilentFallback calls; apps/web-platform/infra/vector.toml app_container_warn_filter (ships pino warn and above)
error_reporting:
  destination: Sentry web-platform via reportSilentFallback (server/observability), ops syncPull, syncPush, and the new auto-commit-pull and auto-commit-push; reportRepoCloneFailed for clone failures
  fail_loud: syncPull and syncPush mirror to Sentry; the two auto-commit catches now mirror too; the git-data push failure logs "git-data replication push failed" and reports; a clone failure reports a classified GitErrorCode (AUTH_FAILED, CLONE_NETWORK_ERROR, CLONE_UNKNOWN)
failure_modes:
  - mode: scrubbed environment breaks the HTTPS clone or pull (CA bundle lookup, missing PATH tool)
    detection: classifyGitError codes AUTH_FAILED / CLONE_NETWORK_ERROR / CLONE_UNKNOWN in reportRepoCloneFailed and the syncPull silent-fallback event; layer 2 (Sentry mirror)
    alert_route: existing Sentry alerts for feature session-sync and clone-failure reports; post-merge read against the pre-deploy baseline
  - mode: a hardening argument is rejected by the runtime git (unknown option) so every consumer exits 129
    detection: same Sentry events plus the Dockerfile build-time floor (git >= 2.38); layer 2
    alert_route: existing Sentry alerts
  - mode: commit fails with "Author identity unknown" because the image identity file is missing or unreadable in a workspace with no local identity
    detection: the new auto-commit-pull / auto-commit-push Sentry events (layer 2) and the pino warn lines "Auto-commit before push failed" / "Auto-commit before pull failed" shipped to Better Stack by the warn filter (layer 3); the Dockerfile build-time git var GIT_AUTHOR_IDENT check covers the file existing
    alert_route: no new alert (creating one mutates Sentry configuration; out of scope); the post-merge read counts the new ops
  - mode: a planted carrier executes despite the control (a residual)
    detection: not detectable in production by this change; the residual rows are the only signal and they run in CI; layer: CI test suite only
    alert_route: CI failure on the PR; no runtime alert is claimed
logs:
  where: pino stdout of the web-platform container shipped to Better Stack Logs; Sentry events for the mirrored paths
  retention: Better Stack Logs and Sentry plan defaults (unchanged by this change)
discoverability_test:
  command: grep -c "Auto-commit before push failed" apps/web-platform/server/session-sync.ts
  expected_output: 1
```

## Guard Contract

### Guard 1 - host-git carrier battery

**Property.** On the real code path of every host-side consumer (session-sync, ensure-workspace-repo, git-data-replication including the key-auth push, the legacy installation-auth arm, inflight-checkpoint), no carrier that the helper's `-c` arguments can close executes, no server-only environment variable reaches a helper that does run, and the operation still succeeds.

**Assembly.** The chokepoint is `hostGitInvocation` in `server/host-git.ts`; the members that flow through it are every git exec site in the five consumer files. More than one chokepoint exists on purpose: the isolated-`GIT_DIR` path is a second, operator-held one and is not guarded here. Members are not trusted as a list: one tree-wide census row scans `apps/web-platform/server` with multi-line-aware matching for `execFile`, `execFileSync`, `spawn` and `spawnSync` calls naming `"git"` and for `gitWith*Auth` calls, classifies each hit as in-scope (must be reached through the helper), census-only (listed in the test with the reason), or isolated-path, and fails on any UNCLASSIFIED hit, so a sixth site in any file reddens it. The census proves consistency with the source in the same commit, not integrity, and its comment says so.

**Mutation matrix.**

| # | Mutation (must drive the guard RED) | Which row reddens |
|---|---|---|
| 1 | delete `core.fsmonitor=false` from the arguments the helper applies | fsmonitor rows (every consumer) |
| 2 | one consumer (git-data key-auth push) reverts to `{ ...process.env }` | sentinel-in-dump row for that consumer only |
| 3 | add a second `execFileSync("git"` in `git-data-replication.ts` that bypasses the helper | census row (unclassified hit) |
| 4 | helper stops applying `extraEnv` after the scrub | operation-succeeds rows (askpass, identity, temp index missing) |
| 5 | helper puts `GIT_CONFIG_GLOBAL=/dev/null` last, or a network arm re-adds its own `/dev/null` after the helper | no-local-identity commit row and the legacy/key identity rows |
| 6 | move the hardening block after `HELPER_RESET` / after the subcommand | argv-order row on the recorded spawn argv |
| 7 | drop `commit.gpgsign=false` from the helper | gpg-program row |
| 7a | stop setting `GIT_WORK_TREE=<cwd>` in the helper | `core.worktree` foreign-directory row (sibling content staged or overwritten) |
| 7b | stop passing `allowProtocol` from the key-auth arm (or widen it to `file`) | `uploadpack` local-remote row and the census assertion on production call-site constants |
| 7c | drop `-c protocol.ext.allow=never` | `ext::` rewrite row |
| 8 | the battery's own dispatch: every driver returns early so zero canary-checked runs happen | floor row: `canaryCheckedRuns === carrierTypes.length * drivers.length` computed from the planter and driver tables, not a literal |
| 9 | remove carrier B's per-carrier canary assertion (keep carrier A's) | the row-count/assertion-presence row for B, because each carrier asserts its own canary |

**Harness rows.** (a) Edit to the suite: replace a planted helper with a no-op script; the cached twin control must go RED ("carrier not live"). (b) Must-PASS input that is not the canonical fixture: a clean repo with no carriers (every assertion holds, operation succeeds).

**Anchor.** No stored value is compared to the thing it protects; the guard is behavioural, and nothing outside the commit must move for a weakening to pass. The census row's class table lives in the test file, so one diff can edit both the table and the source; that row therefore proves consistency only, and is paired with the behavioural rows above for integrity.

### Guard 2 - residual pins

**Property.** The set of carriers that still execute after the control equals the measured set (`filter.*` per attribute source, `merge.*.driver` on pull, repo-config remote rewriting for every measured key, the consumer's own auth variable), so a change that closes one, or widens the set, fails a test.

**Assembly.** One pin row per entry of the planter table flagged residual (generated from the table, so adding a planter adds a row), each run on the consumer verbs that can reach it (session-sync add/commit/status, ensure-workspace-repo reset --hard, legacy pull, key-auth push/fetch).

**Mutation matrix.**

| # | Mutation | Which row reddens |
|---|---|---|
| 1 | a future change adds a per-driver `-c filter.zz.clean=` neutraliser | the pin for that driver (helper no longer runs); the pin must then be updated deliberately |
| 2 | scrub drops `GIT_INSTALLATION_TOKEN` for the legacy arm | the own-auth-variable pin |
| 3 | helper starts forwarding one more server variable | the sentinel-absent assertion inside the pin rows |
| 4 | the planter table is emptied | floor row `pinRows === residualPlanters.length * verbs` (derived, not a literal) |

**Harness rows.** Edit to the suite: flip one pin's expected canary to absent and that row reds. Must-PASS non-canonical input: none beyond Guard 1's clean-repo row.

**Anchor.** None stored; behavioural pins, stated rather than assumed.

## Architecture Decision (ADR/C4)

No new architectural decision. This extends coverage of an invariant ADR-050 already records ("tenant workspace content, the worktree and its `.git`, is untrusted input") from the agent's own git to the host-side consumers the 2026-11-09 amendment listed as a residual.

### ADR

Amend ADR-050, 2026-11-09 amendment, "Host-side git in tenant workspaces" residual bullet (CTO F7). No new ADR; the decision itself (carrier closure is structural, `-c` arguments are not) is unchanged and the isolated-`GIT_DIR` design remains the named structural closure.

### C4 views

No C4 impact. Checked: `views.c4` and `spec.c4` read in full, `model.c4` read for the git surfaces. External human actors (the agent-session user and the connected-repo owner) are modelled; external systems (`github`, `gitDataStore`) and the stores touched (`workspacesVolume`) are modelled with their existing edges; the change adds no actor, system, store or relationship. The `workspacesVolume` description (session-sync autocommits only `knowledge-base/**`) and the `gitDataStore` description stay true. Backed by a green `plugins/soleur/test/c4-count-parity.test.sh` run in Phase 5 (it guards the derived counts that `model.c4` embeds).

### Sequencing

Single slice; nothing waits on a later one.

## Open Code-Review Overlap

None. Queried open `code-review` issues for `session-sync.ts`, `ensure-workspace-repo.ts`, `git-data-replication.ts`, `git-auth.ts`, `inflight-checkpoint.ts`, `compound-promote-create-gates.ts` and `agent-env.ts`: no body names any of them.

## Test Scenarios

1. Each carrier x consumer cell in Phase 1 (A1-A3), plus the bare-cwd row.
2. Twin control: the raw-git run of each carrier type fires the canary (cached once).
3. No-local-identity commit through the identity file; seeded local identity wins; absent identity file fails (pinned).
4. A server-set `GIT_DIR`, `GIT_EXEC_PATH` and the sentinel never appear in a child's environment.
5. `runConnectedRepoGit` still rejects `reset`, `--force`, `--no-verify` (existing rows); a caller cannot pass `env` (compile-time).
6. Git floor: the `beforeAll` throws below 2.38.
7. Residual pins (Guard 2).
8. Hermeticity: the worktree's local config snapshot is identical before and after.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, a stub, or omits the threshold would fail `deepen-plan` Phase 4.6. This one carries all three lines.
- Siblings mock `node:child_process` with factories lacking `execFile`; the new suite must not import a module graph under such a mock, and `inflight-checkpoint` keeps its lazy `import("node:child_process")`.
- `buildScrubbedEnv` refuses `GIT_*`/`TOKEN`/`SECRET` extras by design: auth variables are merged AFTER the scrub through `extraEnv`. Passing them as `buildScrubbedEnv` extras throws.
- The shared `authEnv` object in `git-auth.ts` feeds both the legacy arm and `buildIsolatedGitEnv`; strip `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_NOSYSTEM` from the legacy env only, never from the shared object, or the hardened arm changes.
- `HOME` is a shared temp directory under the scrub; the askpass script is written in-process from the real `HOME` (`getAskpassDir`), and ssh reads `~/.ssh` from the passwd entry, so neither depends on the child's `HOME`.
- `core.hooksPath=/dev/null` also stops legitimate repo hooks (for example a repo's own pre-commit tooling) on the auto-commit; this is intended and stated.
- `git-auth.ts` is CODEOWNERS-protected and sits in the no-tofu-ssh mutation battery edge list; touching it re-arms that battery.
- Do not add a closing keyword anywhere. Do not name the quarantined issue numbers anywhere, including this plan, `tasks.md` and `decision-challenges.md`.
- The dev-host `ls-remote` check is not the prod TLS canary and does not exercise the token path; the PR must not word it as either.

## Handoff block for the final report (consumed by work/ship)

- (a) Residuals: `filter.*` through every attribute source (`--attr-source` measured as a partial control and not adopted: git floor, `info/attributes` still fires); `merge.*.driver` on pull; repo-config remote, proxy and TLS settings including `url.<x>.insteadOf` toward https/ssh hosts; the consumer's own auth variable reaching a helper that runs (legacy: installation token; key-auth: the helper can read the 0600 cross-tenant transport key file during the push; the transport-key temp-file location is left as is, CTO R8e); a gitfile `.git` to a foreign gitdir unless the Phase 1 shape check closes it; any repo-config execution path not measured; host-side git not isolated from the workspace `.git`; census-only callers (`workspace.ts`, `git-config-atomic.ts`, `worktree-config-seed.ts`, `push-branch.ts` legacy branch, `context-queries-hook.ts`, `git-worktree-validity.ts`, `event-ship-merge.ts`, cron helpers); in-sandbox git, Bash-created `.git` members, `bash_autonomous`/batch-grant grammar binding and pre-poisoned workspaces untouched.
- (b) Operator never-done items: creating or flipping any flag or environment; prd writes needing approval, prd migrations or psql; legal wording sign-off; public security claims ahead of a measured control; reading or flipping `AGENT_OUTER_WRAP` live; the isolated-`GIT_DIR` push path and its tracking issue; creating a Sentry alert.
- (c) Open items: CODEOWNERS review for `git-auth.ts` and `git-data-replication.ts`; PR-body `Follow-ups not filed` (isolated-`GIT_DIR` extension to the legacy arm; `sshWithPrivateKeyAuth` and `git-config-atomic.ts` census items; repo-config remote rewriting closure; a Sentry alert on the new auto-commit ops) with draft text; Infra Validation (cloud-init pin drift) and the advisory affected-index ratchet deliberately not fixed.
- The CTO's operator-needed actions: none (both rounds).
- Carry-forward: the 24-hour post-deploy Sentry read against the pre-deploy baseline (Phase 6), owned by the session that runs `soleur:postmerge`.
- Not measured: the prod TLS/egress canary (HTTPS clone and pull under the scrubbed env inside the prod container); the token path of any network arm; the key-auth arm's real handshake against a rewritten host (only the pinned ssh options are asserted); the in-sandbox delivery of the agent env pin (unchanged); the image identity file under the host-side path beyond the Dockerfile build-time check; `remote.origin.url`/`pushurl`, `http.proxy`, `http.sslVerify` and URL-scoped `credential.<url>.helper` until Phase 1 measures them.

## Review-round addendum (2026-11-09, appended; earlier sections above are the plan as written)

The 13-seat review panel changed the shipped design in the ways below; each is a "Ruled by CTO agent, 2026-11-09" row in
`decision-challenges.md` (review round). The plan text above that conflicts with these points is superseded by them.

- `allowProtocol` is required on every call (`none` for local-only consumers): a promisor or `file` remote reached from a
  local verb ran `remote.<n>.uploadpack` (measured). This amends R8b.
- `-c core.alternateRefsCommand=` joins the helper-only arguments (measured to run on fetch with `objects/info/alternates`).
- A call with a workspace `cwd` refuses a `.git` that is a gitfile, a symlink or carries `commondir`, and pins `GIT_DIR` and
  `GIT_COMMON_DIR` to the workspace. This flips the earlier "shape check is a follow-up" ruling. A preflight, not a structural control.
- The git-data push targets the explicit server-derived URL, and a `url.*` preflight guard (`git-data-url-guard.ts`) is shared
  with the fetch.
- `extraEnv` accepts only an allowlist of the call-sites' own names; TLS/proxy passthrough is https-arm only; `cwd` must be
  absolute and is refused with `clone`/`init`.
- `workspace.ts` provisioning and the `context-queries-hook` `ls-files` are routed through the helper (planted fsmonitor ran on both).
- The Sentry auto-commit mirrors carry a classified failure (stage, exit status, closed bucket), not the raw error.
- Wording: the scrub is NOT a secrecy control against a same-uid helper that reads `/proc/<pid>/environ` (measured); any
  executing carrier is a full same-uid compromise including other tenants' workspace directories.
- Fix-round additions (same day): the shape refusal also covers symlinked first-level `.git` entries and `refs/*` / `objects/*`
  children, `objects/info/alternates`, `http-alternates` and `info/grafts`; the git-data guard also refuses any `remote.<name>.*`
  key whose name is not `origin` or `git-data`; the worktree-config heal (`worktree-config-seed.ts`) is routed through the helper
  (it WROTE through a redirect, measured); refusals are mirrored to Sentry at the session-sync gates, in provisioning and in the
  context-queries hook; `workspace.ts` and `worktree-config-seed.ts` are no longer census-only.
