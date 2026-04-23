# Learning: GIT_ASKPASS over shell-invoked credential helpers for headless git auth

## Problem

Production P1 (Sentry `6aac752a7dbd4587857fb617abb1e6ac`, 2026-04-23 12:06 CEST). Reconnecting a past project in `app.soleur.ai` failed at the git-clone step with:

```text
Git clone failed: Cloning into '<path>'
<path>: Permission denied
fatal: could not read Username for 'https://github.com': No such device or address
```

The `/api/repo/setup` route handler ran `execFileSync("git", ["-c", `credential.helper=!${helperPath}`, "clone", ...])` where `helperPath` pointed to `/tmp/git-cred-<uuid>` (a `#!/bin/sh` script mode 0o700 that echoed the installation token). The `!`-prefix pattern runs the script under `sh -c`, which in this container silently failed — likely from tmpfs `noexec` flags, shell-indirection quirks, or any other exec-path problem the shell doesn't surface as a first-class error. When the helper returned empty, git fell through to the terminal prompt chain; `stdio: "pipe"` means no TTY; `open(/dev/tty)` returned `ENXIO`, which git emits as the observed stderr.

The pattern was introduced in PR #1257 (2026-03-28) and propagated by copy-paste to five call sites over four weeks (`apps/web-platform/server/workspace.ts`, `push-branch.ts`, `kb-route-helpers.ts`, `session-sync.ts` ×2, `app/api/kb/upload/route.ts`). No prior commits mention "could not read Username" — first-time architectural fix, not a regression.

## Solution

PR #2842 introduces `apps/web-platform/server/git-auth.ts` as the single entry point for authenticated git subprocesses:

- `writeAskpassScript()` writes a fixed-body 6-line shell script to `$HOME/askpass-<uuid>.sh` mode 0o700. The body reads `${GIT_INSTALLATION_TOKEN}` via `printf '%s'` — the token is delivered through the child's env, never interpolated into the script file or argv.
- `gitWithInstallationAuth(args, installationId, opts)` fetches the token via the cached `generateInstallationToken`, sets the env block, prepends `-c credential.helper=` (resets inherited helpers so GIT_ASKPASS wins per `gitcredentials(7)`), and invokes `execFile + promisify(execFile)` — non-blocking, critical for Next.js route handlers.
- `GIT_TERMINAL_PROMPT=0` + `GIT_CONFIG_NOSYSTEM=1` + `GIT_CONFIG_GLOBAL=/dev/null` form defense-in-depth: any auth failure produces deterministic `terminal prompts disabled` stderr instead of silent fall-through, and no system/user gitconfig can inject a rogue `credential.helper`.
- `GitOperationError` with a closed `GitErrorCode` union (`AUTH_FAILED`, `REPO_NOT_FOUND`, `REPO_ACCESS_REVOKED`, `CLONE_NETWORK_ERROR`, `CLONE_TIMEOUT`, `CLONE_UNKNOWN`) classifies stderr into codes the UI routes to actionable copy.
- `checkRepoAccess(installationId, owner, repo)` preflight via `GET /repos/{owner}/{repo}` distinguishes revoked installs (403) and deleted repos (404) from generic clone failures. Runs in `Promise.all` with `removeWorkspaceDir` so it doesn't add latency to the happy path.
- `/api/repo/setup` persists a JSON payload `{code, message, timestamp}` to `users.repo_error` (TEXT column, legacy string rows still parse via fallback). `/api/repo/status` allowlist-validates `errorCode` against `GIT_ERROR_CODES` — unknown codes coerce to `undefined` so the UI renders generic copy rather than a blank headline.
- `FailedState` renders code-mapped headline + body + steps + CTA (Reinstall / Choose different / Try Again) with raw stderr collapsed in `<details>` for support use. Legacy rows fall through to the generic copy unchanged.

Migration: 5 production call sites + 6 test files, typed `GitErrorCode` exported to the client, `randomCredentialPath` kept as `@deprecated` stub for test-mock compatibility (cleanup filed as #2848).

## Key Insight

**`git -c credential.helper=!<path>` is a fragile idiom outside developer laptops.** It depends on: (a) `/tmp` being exec-mountable, (b) `sh` on PATH, (c) the helper file existing at fork time, (d) no inherited `credential.helper` in system/user config, and (e) `stdio: "pipe"` not routing the child to `/dev/tty`. Any one of these fails silently — git logs nothing at stderr level, falls through to the prompt chain, and emits `could not read Username … No such device or address` when there's no TTY. Developer laptops hide all five of these; production containers don't.

The robust replacement is `GIT_ASKPASS` pointing to a fixed-body script in `$HOME` with `GIT_TERMINAL_PROMPT=0` + `GIT_CONFIG_NOSYSTEM=1` + `GIT_CONFIG_GLOBAL=/dev/null` + an explicit `-c credential.helper=` reset. `GIT_ASKPASS` invokes the program via `execve`, not `sh -c`, removing the shell-indirection dependency. Prompt-disabled mode converts silent ENXIO fall-through into a deterministic pattern-matchable stderr.

Token delivery must go through a child-process env var (`GIT_INSTALLATION_TOKEN`) read by a fixed script body. Interpolating the token into the script file is a shell-injection class the day GitHub extends the token format to include metachars. Interpolating into argv is a process-listing leak (`/proc/<pid>/cmdline` is world-readable).

**Multi-agent review caught what one-shot implementation missed.** After tests passed and tsc was clean, 10 parallel review agents surfaced 8 P2s that would have shipped otherwise: dead `INSTALLATION_SUSPENDED` branch, redundant `HELPER_RESET` entry, `execFileSync`-in-async-wrapper blocking the event loop (regression for two route handlers previously non-blocking via `execFileAsync`), missing `GIT_CONFIG_GLOBAL`, untyped client-server error-code coupling, unconditional sanitization gap in the setup route's catch handler, preflight serialized with workspace cleanup, and missing errorCode allowlist on the read path. All 8 fixed inline in one commit before ship.

## Prevention

- **Ban `credential.helper=!<path>` in any server or Node-subprocess context.** New AGENTS.md rule (proposed via Route-to-Definition below) makes the pattern grep-detectable and anchors future reviews. The replacement is always `server/git-auth.ts#gitWithInstallationAuth` — do not roll a second helper.
- **When migrating `execFileSync` to `execFile + promisify(execFile)` in a module that other tests mock,** update every `vi.doMock("child_process", ...)` in the test tree to use the partial-mock pattern (`{ ...actual, ...overrides }` via `vi.importActual`). Wholesale mocks that omit `execFile` break at module-load time when the SUT's top-level `promisify(execFile)` evaluates — symptom: `[vitest] No "execFile" export is defined on the "child_process" mock`. Same class as `cq-preflight-fetch-sweep-test-mocks` but for node builtins.
- **`vi.spyOn(mod, "foo")` cannot intercept same-module calls in ESM.** Module namespaces get mutated; in-module references are captured at definition time via live bindings and bypass the spy. Use `vi.doMock` with `importOriginal` + spread to replace at the module boundary, or refactor to parameter-inject the dependency. Trying to spy on `generateInstallationToken` inside a test for `checkRepoAccess` (both in `server/github-app.ts`) consumed ~15 minutes before we abandoned the approach for integration-style tests.
- **JSON-in-TEXT column reads must allowlist-validate.** `parseErrorPayload` in `/api/repo/status/route.ts` uses `isGitErrorCode(parsed.code)` so a typo in the writer (or a stale row from a reverted PR that wrote an unrecognized code) coerces cleanly to `undefined` — UI falls back to generic copy. Without the allowlist, `ERROR_COPY[typo_code]` returns `undefined` and the UI renders a blank headline.
- **Shell-exec credential idioms are a class.** If a second reviewer ever says "let's just write a shell helper that echoes the token," the answer is "no, use `gitWithInstallationAuth`." The helper exists precisely so this class cannot proliferate by copy-paste again.

## Session Errors

1. **ESM live-binding defeated `vi.spyOn` for same-module refs.** — Recovery: abandoned the HTTP-status unit-test approach for `checkRepoAccess` and kept only integration-style tests that mock `../server/github-app` wholesale. **Prevention:** rule proposal in Route-to-Definition below: "Never rely on `vi.spyOn(mod, fn)` to intercept calls from `fn`'s own module — ESM captures local references at definition time. Use `vi.doMock` at the module boundary or refactor to dependency injection."

2. **`execFileSync` → `execFile + promisify` conversion broke `workspace-cleanup.test.ts`.** — Pre-existing wholesale `vi.doMock("child_process", () => ({ execFileSync: ... }))` calls returned `undefined` for `execFile`, crashing git-auth.ts's top-level `promisify(execFile)` at module load. Recovery: migrated to partial mocks via `importActual` + spread. **Prevention:** rule proposal: "When migrating a module between `execFileSync` and `execFile+promisify`, audit every test that mocks `child_process` wholesale — add `importActual` + spread so the mock survives the SUT growing new imports."

3. **Bash tool CWD did not persist across calls.** — Recovery: always `cd <abs-path> && <cmd>` in a single Bash invocation after catching one "No such file or directory". **Prevention:** already covered by `cq-for-local-verification-of-apps-doppler`; no new rule needed.

4. **Dangling `}` from deleted `finally` block.** — Recovery: TypeScript caught the syntax mismatch post-edit; one additional Edit fixed it. **Prevention:** when deleting a `try { … } finally { cleanup() }` block because the callee now owns cleanup, re-read the surrounding braces rather than pattern-matching on `finally` alone.

5. **FailedState RTL test failed at module load on `next/font/google`.** — Recovery: added `vi.mock("next/font/google", ...)` per the pattern already used in `ready-state.test.tsx` / `connect-repo-page.test.tsx`. **Prevention:** rule proposal already exists implicitly — any `happy-dom` RTL test for a component that transitively imports `next/font` needs the mock. Consider a shared setup helper if this recurs.

6. **Code-quality review false-positive on tokenCache.** — The agent claimed `generateInstallationToken` has no in-memory cache; the cache exists at `github-app.ts:428`. Recovery: correctly identified the false positive, did not act on the agent's proposed refactor. **Prevention:** reinforces existing guidance — verify agent claims against the actual file before implementing agent-prescribed fixes.

7. **`replace_all` Edit replaced only one occurrence due to surrounding context.** — Recovery: used `Write` to rewrite the whole test file cleanly. **Prevention:** when the `old_string` contains context that is unique to one test (variable names, comment strings), use targeted Edit per test or rewrite the file. `replace_all` is for truly identical sub-strings.

## Tags

category: integration-issues
module: web-platform-repo-setup
prs:
  - "2842"
sentry_ids:
  - "6aac752a7dbd4587857fb617abb1e6ac"
scope_outs:
  - "2846"
  - "2847"
  - "2848"
