# Fix: `POST /api/repo/setup` fails with "could not read Username" on reconnect

**Type:** bug (production P1 — user-blocking)
**Branch:** `feat-one-shot-fix-repo-setup-git-clone-creds`
**Worktree:** `.worktrees/feat-one-shot-fix-repo-setup-git-clone-creds`
**Sentry:** `6aac752a7dbd4587857fb617abb1e6ac` — `soleur-web-platform`, prod, 2026-04-23 12:06 CEST
**Status:** deepened

## Enhancement Summary

**Deepened on:** 2026-04-23
**Sections enhanced:** Overview, Root Cause Analysis, Alternative Approaches, Phase 1 GREEN (helper design), Risks, Research Insights.
**Research sources:** git-scm.com/docs/gitcredentials, GitHub REST API docs (installation tokens, /repos/), GitHub community discussions #173881 + #150402 + #48186, CoolAJ86 "Ultimate Guide to Git Credentials", Snyk advisory on `execFileSync` patterns, Docker-side credential-helper issue corpus.

### Key Improvements (over the initial plan)

1. **Token delivery via env var, not script-body interpolation.** Closes a latent shell-injection class regardless of whether the installation-token regex ever drifts. The askpass script reads `$GIT_INSTALLATION_TOKEN` from its own environment via `printf '%s' "$GIT_INSTALLATION_TOKEN"`; the token never lives in a script file on disk.
2. **Explicit credential.helper reset, not implicit.** Git docs confirm `credential.helper` is tried FIRST; `GIT_ASKPASS` is fallback. So the new invocation passes `-c credential.helper=` (empty) + `-c credential.helper=""` (belt-and-suspenders) plus `GIT_CONFIG_NOSYSTEM=1` to ensure GIT_ASKPASS is the credential path actually used.
3. **Replaced brittle-regex token validator with length-range + charset permissive match.** GitHub does NOT document the exact format of `ghs_` tokens. Hard-coded length assumptions would reject future valid tokens.
4. **Added Phase 0 `exec` probe**, not just `mount` inspection. `mount | grep noexec` misses user-namespace bind mounts where the flag doesn't show up — the definitive test is writing a throwaway `+x` shell script and running it.
5. **Username-slot convention preserved (`x-access-token`) for log auditability**, but documented the GitHub community finding that it is not semantically required.
6. **Added a defense-in-depth probe: set `GIT_CURL_VERBOSE=1` on FIRST clone attempt in a recovery retry path.** If primary attempt fails with an auth-like stderr, the retry captures curl-level diagnostics into the logs (not into `repo_error`) to narrow future debugging.

### New Considerations Discovered

- **`x-access-token` is not magic**: GitHub's backend ignores the username when a valid token is in the password slot. Useful for testing: if we ever need to verify our helper is being consulted, we can temporarily use a sentinel username (`soleur-probe`) and grep for it in request logs.
- **Installation tokens have no documented format**: the plan's original `^ghs_[A-Za-z0-9]{36}$` regex would reject future valid tokens if GitHub lengthens the suffix. Switched to `^ghs_[A-Za-z0-9_-]{30,128}$` with log-warn on mismatch rather than throw.
- **Docker/compose has a well-documented class of silent credential-helper failures** — our `!`-prefix pattern is a known fragile idiom outside of developer laptops with host-mounted credential stores.
- **No-op usernames test for GitHub App clone** — per community discussion, any non-empty username works; we can assert in tests without depending on "x-access-token" being meaningful.

---

## Overview

Reconnecting to a previously-connected project (or connecting any repo) fails at the git-clone step with:

```
Git clone failed: fatal: could not read Username for 'https://github.com': No such device or address
```

The stack trace originates in `provisionWorkspaceWithRepo` (`apps/web-platform/server/workspace.ts:136`), which writes a temporary credential helper to `/tmp/git-cred-<uuid>` and invokes:

```ts
execFileSync("git", [
  "-c", `credential.helper=!${helperPath}`,
  "clone", "--depth", "1", repoUrl, workspacePath,
], { stdio: "pipe", timeout: 120_000 });
```

Git is falling back to prompting for a username, which means the credential helper is **not being consulted** (or it ran but returned empty output). In a non-TTY child_process context, the prompt fails immediately with `could not read Username … No such device or address`.

The raw git stderr is then surfaced verbatim in the UI via `FailedState` (`apps/web-platform/components/connect-repo/failed-state.tsx:34`) — unactionable for users.

**Goal:** Fix the root cause (credential helper not being consulted and/or silent auth failure) and replace the raw git stderr with an actionable, user-safe error message.

---

## Research Reconciliation — Spec vs. Codebase

| Hypothesis from issue body | Codebase reality | Plan response |
|---|---|---|
| (a) "credential helper script path or shebang not executable" | Helper is written with `mode: 0o700` and `#!/bin/sh`. Invocation uses `credential.helper=!<path>` — the `!` prefix tells git to run the string under `sh -c`, so the file is executed by the shell, not the kernel's `execve`. If `/tmp` were `noexec`, `sh -c '/tmp/git-cred-abc get'` would still fail (shell tries to exec). **Possible** in some container runtimes. | Phase 1 switches away from file-on-disk helper to `GIT_ASKPASS` env var pointing to a file (avoids `!`-prefix shell indirection) OR an inline `-c credential.helper=` command that does not require file execution. |
| (b) "missing/expired GitHub token for reconnecting user" | `generateInstallationToken` has a 5-minute safety margin cache and always re-requests on expiry. A 401 at token-fetch would throw `"Token generation failed: …"` — **different error path** than the observed one. Not the cause here. | Out of scope for fix; already handled. But Phase 3 adds preflight validation: hit `GET /repos/{owner}/{repo}` with the installation token before clone, so a deauthorized installation surfaces as "Repository access revoked — please reinstall the Soleur GitHub App" rather than a raw git stderr. |
| (c) "credential helper not being consulted" | **Most likely.** `credential.helper=!<path>` relies on: (i) `/tmp` being exec-mountable, (ii) `sh` on `PATH`, (iii) the file existing at helper invocation time. In the `node:22-slim` runner with user `soleur`, `/tmp` is typically world-writable but could be `noexec` depending on host mount flags. Also: `GIT_TERMINAL_PROMPT` is **not** set to `0`, so any helper failure silently falls through to terminal prompt, producing the exact observed error. | Phase 1 switches to the **stdin credential-approve** pattern (Git's canonical non-shell, non-file, non-TTY approach) and sets `GIT_TERMINAL_PROMPT=0` as defense-in-depth so any future auth failure yields a deterministic "Authentication failed" error instead of the current silent-prompt-fallback behavior. |

### Additional reality checks

- The same `credential.helper=!${helperPath}` pattern is used in **five** places: `workspace.ts`, `push-branch.ts`, `kb-route-helpers.ts`, `session-sync.ts` (two sites). All share the same failure mode. **Fix must be applied across all sites** (see `Files to Edit`), or extract a shared helper (preferred).
- `GIT_TERMINAL_PROMPT` is grep-absent across `apps/web-platform/`. No call site defensively disables terminal prompts.
- The `FailedState` UI component exists and has an "Error details" card — we have an existing surface to render the actionable message into. No new component needed.

---

## Root Cause Analysis

### Why "could not read Username" happens despite a credential helper

1. Git parses `credential.helper=!/tmp/git-cred-abc`. The `!` prefix means "execute as shell command".
2. Git runs `sh -c '/tmp/git-cred-abc get'`.
3. For the helper to succeed, **three** conditions must all hold:
   - `sh` is on `PATH` (yes — busybox/dash/bash all present in `node:22-slim`).
   - `/tmp/git-cred-abc` is executable AND the filesystem allows exec.
   - The file still exists at the moment git forks (we delete it in `finally` — if the clone's internal retry happens to race with cleanup, that'd be a bug, but cleanup runs after the clone returns, so not the cause here).
4. **Silent failure mode**: if `sh -c` fails (exec denied, file missing, shell syntax error), git logs **nothing at --stderr level** and falls back to its credential prompt chain. With no TTY attached (`stdio: "pipe"`), prompting immediately errors with `could not read Username for 'https://github.com': No such device or address`.
5. No `GIT_TERMINAL_PROMPT=0` is set — so the prompt fallback happens implicitly.

### Why it manifests on *reconnect* specifically (per Sentry context)

Two plausible explanations, both investigated in Phase 0:

- **Install-time state drift**: the container image was re-deployed after the initial successful clone, and `/tmp` mount flags changed (host-level `/var/lib/docker/tmp` `noexec` defaults, or a systemd-tmpfiles override). Fresh users would hit this too — but reconnect is more common in prod than first-time connect right now, biasing the Sentry volume.
- **GitHub App installation revoked/reinstalled**: the user uninstalled + reinstalled the Soleur GitHub App, their stored `github_installation_id` is stale. BUT — stale installation IDs throw `401 Bad credentials` at `generateInstallationToken`, which wraps as `"Token generation failed: …"` — **not** the error we see. So this is NOT the proximate cause but **is a latent bug** we'll fix in Phase 3 preflight.

### Fix strategy (layered)

- **Phase 1 (root cause)**: replace the `credential.helper=!<path>` pattern with a non-shell, non-file-exec approach. Two viable options, plan adopts (A) for simplicity:

  - **(A) Chosen**: `GIT_ASKPASS=<path-to-script>` env var + explicit `-c credential.helper=` reset (empty) + `GIT_CONFIG_NOSYSTEM=1`. The script reads the token from `$GIT_INSTALLATION_TOKEN` in its own env — **the token is NEVER interpolated into the script body or into argv.** Script body is a fixed 6-line shell snippet, byte-identical across invocations (can even be written once at container startup if we want; Phase 1 keeps it per-clone for cleanup simplicity). This still requires file exec on `/home/soleur` — but homedirs are never `noexec` by convention and our Dockerfile creates `/home/soleur` via `useradd -m`.

    **Why the empty credential.helper reset is load-bearing**: per git-scm.com/docs/gitcredentials, if `credential.helper` is configured (system config, user config, or passed via `-c`), git tries those helpers FIRST and only falls back to `GIT_ASKPASS` if they all return empty/error. `/etc/gitconfig` or `/home/soleur/.gitconfig` could inherit a helper (e.g., from a future base-image change) and silently win over our `GIT_ASKPASS`. Passing `-c credential.helper=` (empty value) clears the list in the current invocation. `GIT_CONFIG_NOSYSTEM=1` additionally ignores `/etc/gitconfig` to prevent future surprise.

  - **(B) Rejected**: Inline token in URL (`https://x-access-token:${token}@github.com/owner/repo`). Simplest, but puts the token in the process argv — visible via `/proc/<pid>/cmdline` to any process in the same PID namespace, and logged by many error paths (node unhandled-rejection handlers, Sentry breadcrumbs that serialize `argv`). Security regression. **Do not do this.**
  - **(C) Rejected**: `git credential approve` via stdin before clone. Cleanest in theory but requires two-step invocation, a persistent credential cache with a write-to-disk step, and a separate `credential erase` on cleanup. More state than (A).

- **Phase 1 (defense-in-depth)**: Set `GIT_TERMINAL_PROMPT=0` on every `execFileSync` that invokes git with a credential helper. This ensures any future auth failure yields `fatal: could not read Username … terminal prompts disabled` (deterministic) rather than falling through with `No such device or address`.

- **Phase 2 (deduplication)**: Extract the credential-bearing git invocation into a single helper `gitWithInstallationAuth(installationId, args, opts)` in `server/git-auth.ts`. Replace all 5 call sites.

- **Phase 3 (preflight & UX)**: Before the clone, hit `GET /repos/{owner}/{repo}` with the installation token. If 404/403, surface a specific error ("Repository access revoked. Please reinstall the Soleur GitHub App.") with a reinstall CTA. If 200, proceed to clone — any subsequent git failure is then an infrastructure/network issue, not an auth issue, and can be messaged as such.

- **Phase 4 (UX)**: Map the internal error into a user-safe, actionable message. Add an `errorCode` field to `repo_error` (e.g., `REPO_ACCESS_REVOKED`, `CLONE_NETWORK_ERROR`, `CLONE_TIMEOUT`, `CLONE_UNKNOWN`). The `FailedState` component renders human-readable copy per code, keeping "Error details" (raw) collapsible for support use.

---

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **(A) GIT_ASKPASS + script in $HOME** | Portable, avoids `!`-shell indirection, keeps token off argv | Still needs exec perm on homedir (OK) | **Chosen** |
| (B) Inline token in URL | 1-line change | Token in `/proc/<pid>/cmdline` — security regression | Rejected |
| (C) `git credential approve` via stdin | Canonical git approach | Two-step flow, harder to clean up | Rejected |
| (D) Switch to libgit2 (nodegit/isomorphic-git) | No shell, no `/tmp`, full programmatic control | New dep, larger refactor, slower for large repos than native git | Deferred — file issue if (A) proves unreliable |
| (E) Mount `/tmp` as `exec` in Dockerfile/compose | Minimal code change | Requires infra change + doesn't fix the root design smell (shell-invoked helper) | Rejected as a fix; Phase 0 still verifies the mount as part of investigation |

---

## Files to Edit

- `apps/web-platform/server/workspace.ts` — switch `provisionWorkspaceWithRepo` to `GIT_ASKPASS` pattern; set `GIT_TERMINAL_PROMPT=0`; preflight repo-access check.
- `apps/web-platform/server/push-branch.ts` — adopt `gitWithInstallationAuth` helper.
- `apps/web-platform/server/kb-route-helpers.ts` — adopt helper.
- `apps/web-platform/server/session-sync.ts` — two sites (`syncPull`, `syncPush`) adopt helper.
- `apps/web-platform/app/api/kb/upload/route.ts` — adopt helper (shares same pattern).
- `apps/web-platform/server/github-app.ts` — add `checkRepoAccess(installationId, owner, repo)` function for preflight (Phase 3).
- `apps/web-platform/app/api/repo/setup/route.ts` — catch wrapped errors, stamp `errorCode` into `repo_error` JSON (keep `repo_error` column as TEXT; store JSON string).
- `apps/web-platform/app/api/repo/status/route.ts` — return `{ errorMessage, errorCode }` in status payload.
- `apps/web-platform/components/connect-repo/failed-state.tsx` — render code-specific copy; keep raw message in collapsible.
- `apps/web-platform/components/connect-repo/reconnect-cta.tsx` (if exists) — CTA for `REPO_ACCESS_REVOKED`.

## Files to Create

- `apps/web-platform/server/git-auth.ts` — `writeAskpassScript(token)`, `gitWithInstallationAuth(installationId, cwd, args, opts)` — new single entry-point for authenticated git invocations.
- `apps/web-platform/test/git-auth.test.ts` — unit tests for the helper (askpass content, env vars set, cleanup on error).
- `apps/web-platform/test/workspace-auth-preflight.test.ts` — tests for Phase 3 preflight against a mocked 200/404/403 installation repo check.
- `apps/web-platform/test/connect-repo-failed-state.test.tsx` — RTL tests for the new code-mapped UX.

## Files to Read (no edit expected)

- `apps/web-platform/Dockerfile` — confirm `/home/soleur` exists and is writeable (it is — `useradd -m`).
- `apps/web-platform/infra/main.tf` — confirm no bind-mount changes to `/tmp` are pending.

---

## Open Code-Review Overlap

Query of open `code-review` issues against planned file list: 26 open issues, grep against `workspace.ts`, `push-branch.ts`, `kb-route-helpers.ts`, `session-sync.ts`, `github-app.ts`, `app/api/repo/setup/route.ts`, `app/api/repo/status/route.ts`, `failed-state.tsx`:

- **#2244** — "refactor(kb): migrate upload route to syncWorkspace (finish PR #2235 scope)": touches `app/api/kb/upload/route.ts` which this plan also edits. **Disposition: Acknowledge.** This plan's edit is minimal (one-line substitution for the helper call). #2244's refactor is structurally orthogonal (route-to-service migration). Leave #2244 open; we'll re-check its scope when it lands.
- **#2246** — "refactor(kb): low-severity polish from PR #2235": generic polish, no specific file pin to our touchpoints. **Disposition: Acknowledge.**
- **#2778** — "migrate conversations scoping to first-class projects table": doesn't touch our files. False positive match. **Disposition: Acknowledge.**

None folded in — all three are orthogonal scopes.

---

## Hypotheses — Phase 0 investigation (before writing fix)

| # | Hypothesis | Test | Expected signal |
|---|---|---|---|
| H1 | `/tmp` in prod container is mounted `noexec` | `docker exec soleur-web mount \| grep /tmp`; alternately `touch /tmp/x.sh && chmod +x /tmp/x.sh && /tmp/x.sh` (should print "exec denied" if noexec) | If confirmed, the `!`-prefix helper cannot be exec'd. Fix Phase 1 resolves. |
| H2 | `sh` not on PATH for the git subprocess | `docker exec soleur-web env \| grep PATH`; `docker exec soleur-web which sh` | If absent, `sh -c` fails. Unlikely — `node:22-slim` has `/bin/sh` (dash). |
| H3 | `GIT_ASKPASS` / `GIT_TERMINAL_PROMPT` inherited from parent with wrong values | `docker exec soleur-web env \| grep -E '^GIT_'` | Should be absent. Our fix sets both explicitly. |
| H4 | Installation token returns empty / invalid | Sentry breadcrumbs: is there a `"Failed to generate installation token"` log immediately before? | If yes, wrong error-wrap; if no, helper is the issue. |
| H5 | User's `github_installation_id` points to a revoked installation | Check the specific user in Sentry (user.id) in Supabase: does the installation still exist via `GET /app/installations/{id}`? | If revoked → Phase 3 fix eliminates this failure class. |

Phase 0 is **observability only** — no code changes. Findings go into the PR description.

### L3→L7 diagnostic order

This issue is **not** an SSH/network-connectivity symptom (hr-ssh-diagnosis-verify-firewall does not apply). Nevertheless, confirm in Phase 0:

- `curl -I https://github.com/` from inside the prod container → expect 200 (rules out egress firewall blocking api.github.com or github.com).
- No hcloud firewall check required (github.com is egress, not ingress).

---

## Implementation Phases

### Phase 0 — Observability and hypothesis validation

**Goal:** Confirm which of H1–H5 is the proximate cause before writing code. This narrows the fix and validates the Phase 1 approach works.

- [ ] Pull Sentry event `6aac752a7dbd4587857fb617abb1e6ac` via Sentry API (`SENTRY_API_TOKEN` from Doppler `prd`) to extract: breadcrumbs (10 before the error), user.id, `repoUrl`, `installationId`, full stack trace. Paste into PR description.
- [ ] Query Supabase for that `user.id`: is `github_installation_id` still valid? Use `GET /app/installations/{id}` with an App JWT (reuse `createAppJwt()` logic in a one-off script). Record: installation exists? suspended? account login matches stored `github_login`?
- [ ] `docker exec` into the prod container (SSH read-only per `cq-for-production-debugging-use`; **this is a read-only diagnosis step, NOT a fix**). Capture:
  - `mount | grep -E '(/tmp|/home)'` — does `/tmp` or `/home/soleur` have `noexec`?
  - **Definitive exec probe** (mount flags can be misleading under user namespaces):

    ```sh
    echo '#!/bin/sh
    echo ok' > /tmp/exec-probe.sh && chmod +x /tmp/exec-probe.sh && /tmp/exec-probe.sh
    rm -f /tmp/exec-probe.sh
    ```

    Expect `ok`. If "Permission denied", H1 is confirmed.
    Repeat with `/home/soleur/exec-probe.sh`.
  - `env | grep -E '^(GIT_|HOME|PATH)='` — inherited GIT_* vars? HOME set correctly?
  - `which sh && ls -la /bin/sh` — `sh` resolves to dash or bash; file is executable.
  - `ls -la /tmp/git-cred-*` — any leaked helpers from past failed clones (indicates failure points BEFORE the cleanup step in the finally block, e.g., process SIGKILL between write and unlink).
  - `git --version` — our patterns (especially `-c credential.helper=` reset) require git ≥ 2.23. Expected `node:22-slim` ships git 2.39+.
- [ ] **Sentry query for recurrence rate**: run Sentry API `issues/?query=message:"could not read Username"` over last 7 days. Bucket by `user.id` and `repoUrl`. If it's a single user repeatedly failing, H5 (their installation is revoked) is most likely. If it's many users across many repos, H1 (`/tmp` noexec) or H3 (inherited env var) is more likely.
- [ ] Write findings into this plan's "Phase 0 findings" section below, under Acceptance Criteria. **Do not start Phase 1 until findings resolve to a primary cause.** If findings contradict the plan (e.g., H5 dominates and no exec issue exists), scope-down: Phase 1 code change still lands (defense-in-depth), but Phase 3 preflight becomes the load-bearing fix.

### Phase 1 — Core fix: switch to GIT_ASKPASS + GIT_TERMINAL_PROMPT=0

**RED:**

- [ ] `apps/web-platform/test/git-auth.test.ts` — write failing tests asserting:
  - `gitWithInstallationAuth` writes an askpass script to `$HOME/.soleur-git-askpass-<uuid>` (NOT `/tmp`).
  - Script is chmod 0o700.
  - `execFileSync` is called with env `{ GIT_ASKPASS: <path>, GIT_TERMINAL_PROMPT: "0", GIT_TERMINAL_PROGRESS: "0", ...process.env }`.
  - Script echoes `x-access-token` when invoked with `argv[1]` matching `/^Username/`, echoes the token when matching `/^Password/`.
  - Cleanup: askpass file is unlinked in `finally`, even on git-clone failure.
  - Token does NOT appear in any `execFileSync` args array.
- [ ] `apps/web-platform/test/workspace-error-handling.test.ts` — extend: assert that a simulated auth failure yields a wrapped error matching `/Authentication failed|Repository access/`, NOT a raw `could not read Username` leak.

**GREEN:**

- [ ] Create `apps/web-platform/server/git-auth.ts`:

  ```ts
  // Exports:
  //   writeAskpassScript(homeDir?: string): string           → absolute script path (NO token in args)
  //   gitWithInstallationAuth(
  //     args: string[],
  //     installationId: number,
  //     opts?: { cwd?: string; timeout?: number }
  //   ): Buffer
  //   cleanupAskpassScript(path: string): void               (best-effort unlink, swallow ENOENT)
  ```

  - **Askpass script body** (fixed, no interpolation — token-safe by construction):

    ```sh
    #!/bin/sh
    case "$1" in
      Username*) printf '%s' "${GIT_USERNAME:-x-access-token}" ;;
      Password*) printf '%s' "${GIT_INSTALLATION_TOKEN}" ;;
    esac
    ```

    The token is passed via the child process's env, not in the script file. Script file contents are **byte-identical** across users and invocations — eliminates shell-injection class regardless of token format.
  - **Token format validator**: `^ghs_[A-Za-z0-9_-]{30,128}$` (permissive charset + generous length range). On mismatch: `log.warn("Installation token does not match expected format", { lengthBucket })` but DO NOT throw — GitHub has historically extended token formats without notice. Throwing would convert a GitHub format change into a full outage for our users.
  - **Directory selection**: `const askpassDir = process.env.HOME && isWriteable(process.env.HOME) ? process.env.HOME : "/tmp"`. The `isWriteable` check uses `access(path, W_OK | X_OK)` synchronously. In the prod image `HOME=/home/soleur` is set by `useradd -m` (confirmed — grep of Dockerfile line 74). Fall-through to `/tmp` only preserves local-dev ergonomics.
  - **File naming**: `askpass-${randomUUID()}.sh` (suffix `.sh` so the file is auditable on disk). Mode `0o700`.
  - **`execFileSync` env**:

    ```ts
    env: {
      ...process.env,
      GIT_ASKPASS: scriptPath,
      GIT_INSTALLATION_TOKEN: token,              // read by the askpass script
      GIT_USERNAME: "x-access-token",             // convention; GitHub ignores it
      GIT_TERMINAL_PROMPT: "0",
      GIT_TERMINAL_PROGRESS: "0",
      GIT_CONFIG_NOSYSTEM: "1",                   // ignore /etc/gitconfig helper chains
      // Intentionally do NOT set HOME=/dev/null (would break git's own tempdir resolution)
    }
    ```

  - **`execFileSync` args prefix** (prepended to every invocation):

    ```ts
    const HELPER_RESET: readonly string[] = [
      "-c", "credential.helper=",     // clear inherited helpers
      "-c", 'credential.helper=""',   // belt-and-suspenders: empty-quote form some git versions require
    ];
    ```

    Rationale: per `gitcredentials(7)`, `credential.helper` is tried before `GIT_ASKPASS`. Resetting inherited helpers ensures our askpass wins.
  - **Token-in-argv audit**: assert in test that `token` never appears in `execFileSync`'s args array. Use `expect(args.join(" ")).not.toContain(token)`.
  - **Logging on helper failure**: wrap `execFileSync` in try/catch; on error, before rethrowing, log `{ stderr: stderr.slice(0, 2000), helperExists: existsSync(scriptPath), helperPerms: statSync(scriptPath).mode.toString(8) }` so we can tell post-hoc whether the helper was missing/unexecutable.
- [ ] Refactor `provisionWorkspaceWithRepo` in `workspace.ts` to call `gitWithInstallationAuth(["clone", "--depth", "1", repoUrl, workspacePath], installationId, { timeout: 120_000 })`. Remove `writeFileSync(helperPath, ...)` and `randomCredentialPath` from this call site.
- [ ] Preserve the error-wrapping (`Git clone failed: <stderr>`) but also parse stderr for known auth strings and throw `new GitCloneError(code, rawStderr)` with `code ∈ {AUTH_FAILED, REPO_NOT_FOUND, NETWORK, TIMEOUT, UNKNOWN}`. Stderr patterns to match:
  - `/terminal prompts disabled|could not read Username|could not read Password|Authentication failed|HTTP 401|HTTP 403/i` → `AUTH_FAILED`
  - `/repository .* not found|HTTP 404/i` → `REPO_NOT_FOUND`
  - `/Could not resolve host|Connection timed out|Network is unreachable|curl.*Connection refused/i` → `NETWORK`
  - `/timeout exceeded|signal SIGTERM/i` combined with our 120s timeout → `TIMEOUT`
  - otherwise → `UNKNOWN` (preserve raw stderr for support)
- [ ] **Diagnostic retry (one-shot)**: if first clone attempt fails with `AUTH_FAILED` **and** Phase 3 preflight returned `"ok"`, retry **once** with `GIT_TRACE=1 GIT_CURL_VERBOSE=1` and the same args. Capture stderr into `log.error` (structured) — **never** into `repo_error` surfaced to the user (leaks internal paths, token prefix headers). This single retry is bounded and only fires when we know the token works (preflight succeeded) — so failure means a helper-consultation bug, not auth, and the verbose trace narrows which of H1/H2/H3 is live in prod. Delete this retry once production is healthy (file follow-up issue).

**REFACTOR:**

- [ ] Replace `randomCredentialPath` usages in `github-app.ts` with a re-export of `writeAskpassScript` path util (or mark `randomCredentialPath` deprecated with inline comment and a follow-up issue to delete).

**Verify:**

- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/git-auth.test.ts test/workspace-error-handling.test.ts` — all green.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/workspace.test.ts test/workspace-symlink-hardening.test.ts test/workspace-cleanup.test.ts` — no regressions.

### Phase 2 — Propagate helper to all 5 call sites

**RED:**

- [ ] Extend `apps/web-platform/test/push-branch.test.ts`, `kb-upload.test.ts`, `kb-delete.test.ts`, `kb-rename.test.ts`, `kb-route-helpers.test.ts`: replace `expect.stringContaining("credential.helper=!")` assertions with assertions against `gitWithInstallationAuth` being called with the expected args. These tests **will go RED** under the current implementation — that is by design.

**GREEN:**

- [ ] `server/push-branch.ts` — swap the `execFileSync("git", ["-c",`credential.helper=!${helperPath}`, "push", …])` block for `gitWithInstallationAuth(["push", …], installationId, { cwd: workspacePath })`.
- [ ] `server/kb-route-helpers.ts` — same substitution for the `pull --ff-only` invocation.
- [ ] `server/session-sync.ts` — both sites (`syncPull` and `syncPush`).
- [ ] `app/api/kb/upload/route.ts` — the `pull --ff-only` invocation at line 211.

**Verify:**

- [ ] Full vitest sweep: `cd apps/web-platform && ./node_modules/.bin/vitest run`.
- [ ] `rg 'credential.helper=!' apps/web-platform/` — expect zero matches (any leftover call site is a bug).

### Phase 3 — Preflight repo-access check + distinct error codes

**RED:**

- [ ] `apps/web-platform/test/workspace-auth-preflight.test.ts` — RED tests:
  - Mock `GET /repos/{owner}/{repo}` → 200: clone proceeds.
  - Mock → 404: throws with `errorCode = "REPO_NOT_FOUND"`, message "Repository not found or no longer accessible. Reinstall the Soleur GitHub App or reconnect a different repository."
  - Mock → 403: throws with `errorCode = "REPO_ACCESS_REVOKED"`, message "The Soleur GitHub App no longer has access to this repository. Reinstall the app, then try again."
  - Mock → 500: proceeds (network flake at GitHub shouldn't block clone attempt — let git itself retry).

**GREEN:**

- [ ] Add `checkRepoAccess(installationId, owner, repo): Promise<"ok" | "not_found" | "access_revoked" | "degraded">` to `server/github-app.ts`.
- [ ] In `provisionWorkspaceWithRepo`, after `generateInstallationToken` and before the clone, call `checkRepoAccess`. Parse `owner/repo` from `repoUrl` (regex already exists in `status/route.ts` — extract to `lib/repo-url.ts`). On `"not_found"` or `"access_revoked"` throw a typed error.
- [ ] Map typed errors to `errorCode` in the catch block in `app/api/repo/setup/route.ts`. Persist as a JSON string in `repo_error` (existing column stays TEXT; UI parses): `{"code":"REPO_ACCESS_REVOKED","message":"...","timestamp":"2026-04-23T12:06:00Z"}`.

**Verify:**

- [ ] Preflight tests green.
- [ ] Existing route tests (`setup` route) updated to assert new error-code persistence shape.

### Phase 4 — UX: actionable error messages in FailedState

**RED:**

- [ ] `apps/web-platform/test/connect-repo-failed-state.test.tsx` — assert:
  - Given `{ errorCode: "REPO_ACCESS_REVOKED" }`, the card shows "Soleur no longer has access" and a "Reinstall the Soleur GitHub App" CTA linking to `/api/repo/install`.
  - Given `{ errorCode: "REPO_NOT_FOUND" }`, shows "Repository not found" + "Choose a different repository" CTA.
  - Given `{ errorCode: "CLONE_TIMEOUT" }`, shows "Clone timed out" + retry.
  - Given `{ errorCode: "AUTH_FAILED" }` (Phase 1's wrapped code), shows "Authentication failed" + reinstall CTA.
  - Given `errorCode: undefined` (legacy error rows), shows the existing generic "Project Setup Failed" copy.
  - In all cases: a `<details>` element exposes the raw `errorMessage` for support — collapsed by default.

**GREEN:**

- [ ] `components/connect-repo/failed-state.tsx`:
  - Add `errorCode?: string` prop.
  - Extract a `ERROR_COPY: Record<ErrorCode, { headline; body; cta }>` map.
  - Render code-mapped copy when `errorCode` is in the map; fallback to current copy when not.
  - Wrap raw message in `<details><summary>Error details (for support)</summary>…</details>`.
- [ ] `app/api/repo/status/route.ts` — parse `repo_error` as JSON-first, fallback to string; return `{ errorCode, errorMessage }`.
- [ ] Parent page (`app/connect-repo/page.tsx` or equivalent) — pipe `errorCode` through to `FailedState`.

**Verify:**

- [ ] RTL tests green.
- [ ] Manual smoke in local dev: trigger each error code path (stub `provisionWorkspaceWithRepo` with each error type) and screenshot the UI.

### Phase 5 — End-to-end verification in prod-like environment

- [ ] Deploy PR preview (or run against prod with a test-user whose installation is intentionally revoked).
- [ ] Reconnect test-user → assert `REPO_ACCESS_REVOKED` UX lands.
- [ ] Revoke installation → reconnect → assert no "could not read Username" leak in Sentry for the next hour.
- [ ] Check `/tmp/git-cred-*` and `$HOME/.soleur-git-askpass-*` for leaked helpers after 10 sequential reconnects.

---

## Test Scenarios

**Unit (RED-before-GREEN per `cq-write-failing-tests-before`):**

1. `git-auth.test.ts::writeAskpassScript writes to HOME not /tmp when HOME set`
2. `git-auth.test.ts::askpass script echoes correct username/password based on argv[1]`
3. `git-auth.test.ts::rejects malformed token (not matching ^ghs_…)`
4. `git-auth.test.ts::unlinks script on clone failure`
5. `git-auth.test.ts::sets GIT_TERMINAL_PROMPT=0 and GIT_TERMINAL_PROGRESS=0`
6. `git-auth.test.ts::token never appears in execFileSync args`
7. `workspace-auth-preflight.test.ts::404 maps to REPO_NOT_FOUND`
8. `workspace-auth-preflight.test.ts::403 maps to REPO_ACCESS_REVOKED`
9. `workspace-auth-preflight.test.ts::500 proceeds to clone (graceful degradation)`
10. `workspace-error-handling.test.ts::clone failure with "could not read Username" stderr maps to AUTH_FAILED code`
11. `connect-repo-failed-state.test.tsx::renders code-mapped headline for each code`
12. `connect-repo-failed-state.test.tsx::raw errorMessage is in a collapsed <details>`

**Integration:**

13. Full `/api/repo/setup` → `/api/repo/status` round-trip with mocked installation returning 403 — user sees `REPO_ACCESS_REVOKED`, not raw git stderr.
14. Fresh user, happy-path clone via mocked git succeeds and `repo_error` is null.

**Manual smoke (Phase 5):**

15. Reconnect an existing project with a revoked installation → UI shows Reinstall CTA.
16. Network partition to `github.com` at clone time → UI shows "Clone network error, retry."
17. 10 sequential reconnects → no leaked askpass files in `$HOME`.

---

## Acceptance Criteria

### Pre-merge (PR)

- [ ] All 12 unit tests + 2 integration tests green.
- [ ] `rg 'credential.helper=!' apps/web-platform/` returns 0 matches (all 5 sites migrated to `gitWithInstallationAuth`).
- [ ] No token strings in any `execFileSync` args across the tree (`rg 'ghs_' apps/web-platform/server/ | grep -v test` returns 0).
- [ ] `FailedState` component renders code-mapped copy for all 4 defined error codes + legacy fallback.
- [ ] Phase 0 findings documented in PR description (which of H1–H5 was the proximate cause).
- [ ] No regression in existing `workspace.test.ts`, `push-branch.test.ts`, `kb-upload.test.ts`, `kb-rename.test.ts`, `kb-delete.test.ts`, `kb-route-helpers.test.ts`, `session-sync.test.ts`.

### Post-merge (operator)

- [ ] Watch Sentry for the 6-hour window after deploy: Sentry ID `6aac752a7dbd4587857fb617abb1e6ac` signature should not recur.
- [ ] Sample 5 recent production reconnect events in Sentry breadcrumbs: confirm none show raw `could not read Username`.
- [ ] If Phase 0 confirmed H1 (`/tmp` is `noexec`), file a separate issue to audit other `/tmp`-executing code paths (`apps/web-platform/scripts/` or any helper generation elsewhere).

### Out of scope (file issues)

- Move away from shelling out to `git` entirely (e.g., isomorphic-git) — tracked in a new issue if askpass proves brittle.
- Unify all 5 "auth + git" call sites into a single service module beyond the helper (current plan extracts the helper; service-level dedup is a larger refactor).

---

## Domain Review

**Domains relevant:** Product (UX-impacting error messages), Engineering (infra/security).

### Engineering (CTO)

**Status:** reviewed inline during planning
**Assessment:** Primary security concern is token exposure. The chosen (A) GIT_ASKPASS approach keeps the token in a 0o700 file in the user's homedir, not in `/tmp`, not in argv, not in env directly (env passes the script path, not the token). Defense-in-depth via `GIT_TERMINAL_PROMPT=0` prevents silent fallthrough. No new network dependencies. Refactor reduces attack surface (removes `!`-shell indirection).

### Product/UX Gate

**Tier:** advisory — modifies an existing user-facing page/component; no new flows or pages.
**Decision:** auto-accepted (pipeline — plan is running in one-shot context per skill inputs).
**Agents invoked:** none (advisory auto-accept).
**Skipped specialists:** ux-design-lead (advisory + no new component surface), copywriter (no brand-voice gate recommended).
**Pencil available:** N/A.

**Findings:** UX changes are limited to: (1) replacing raw git stderr with code-mapped copy in `FailedState`, (2) collapsing raw stderr into a `<details>` element for support use, (3) adding a "Reinstall the Soleur GitHub App" CTA for the revoked-installation code path. The error-card pattern already exists in `FailedState` — we're refining content, not adding new interactive surfaces. If plan-review flags the copy as needing brand-voice review, we'll invoke copywriter at that time.

---

## Research Insights

- **Git credential.helper semantics** (per `man git-credential`): a helper value starting with `!` is run under `sh -c`. The command is appended with `get`/`store`/`erase`. Silent failure (non-zero exit, missing file, shell error) falls through to the next helper or the credential prompt. With no TTY, the prompt emits `fatal: could not read Username for '<host>': No such device or address`. **Citation:** `git help credential-helpers` section "Custom Helpers".
- **`GIT_ASKPASS` semantics**: when set, git invokes the program as `$GIT_ASKPASS 'Username for <url>: '` (exec, not shell). The script's stdout is the response. No `/bin/sh` indirection. **Citation:** `man git` section "Environment Variables".
- **`GIT_TERMINAL_PROMPT=0`**: disables any interactive prompt; forces immediate failure with `fatal: could not read Username for '<url>': terminal prompts disabled`. This is the deterministic failure mode we want instead of the current `No such device or address` fallback. **Citation:** git 2.3+ release notes.
- **Container `/tmp` exec semantics**: some container runtimes (or host systemd-tmpfiles overrides) mount `/tmp` with `noexec`. Node:22-slim default does NOT set noexec, but host bind-mounts can override. Audit via `mount` inside container. **Phase 0** verifies this for soleur prod.
- **Installation token format**: `ghs_<40-char-base62>` — validated regex: `^ghs_[A-Za-z0-9]{36}$` (actually 36 chars after the `ghs_` prefix — confirm at implementation time from a real token via `generateInstallationToken` for a dev installation; hard-coded expectation may drift with GitHub's token format).

<!-- verified: 2026-04-23 source: git-scm.com/docs/git-credential & GitHub App docs -->

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `$HOME` is not writeable in some path (e.g., older Dockerfile stages) | Low | Medium | Fallback to `/tmp`; Phase 0 confirms `/home/soleur` is writeable; add test. |
| GitHub installation token format changes (length/prefix) | Very low | Very high (outage for all users if throw-on-mismatch) | Regex is a safety net — permissive charset `^ghs_[A-Za-z0-9_-]{30,128}$`; mismatch emits `log.warn` with a length bucket (for alerting) and proceeds. Never throw. **Additionally**: the askpass script reads the token from env, so shell-metacharacter risk is moot even if the token format extends. |
| Askpass script file still leaks if process is SIGKILLed between write and unlink | Very low | Low (token TTL is 1h, file mode 0o700, unpredictable path) | Accept; periodic sweep job can clean `$HOME/.soleur-git-askpass-*` older than 1h (file a follow-up issue). |
| `GIT_TERMINAL_PROMPT=0` breaks an unknown code path that relied on interactive prompts | Very low | Low | No interactive prompts can exist in a Node subprocess anyway; env var is a no-op for non-auth git operations. |
| `checkRepoAccess` preflight adds latency to happy-path clone | Low | Low | Single GET to GitHub API (~100ms); parallelize with token-gen in Phase 3. |

---

## ERD / Diagrams

Not applicable — no schema changes. `repo_error` column is reused (TEXT, now storing JSON string).

---

## Rollback

If the fix introduces clone regressions:

1. Revert the PR (`git revert <sha>`).
2. No data migration required — `repo_error` remains TEXT; legacy reads fall back to string-parsing.
3. `git-auth.ts` removal leaves the 5 call sites referencing a missing module — rollback must revert those call-site changes too. Ensure PR is squashed so single-revert works.

---

## Phase 0 Findings (fill during investigation)

| Hypothesis | Tested? | Outcome |
|---|---|---|
| H1 `/tmp` noexec | ☐ | |
| H2 `sh` missing | ☐ | |
| H3 inherited `GIT_*` env vars | ☐ | |
| H4 token empty | ☐ | |
| H5 installation revoked | ☐ | |

**Primary cause identified:** *(pending Phase 0)*

---

## Open Questions

1. Should the preflight repo-access check be rate-limited? (One GitHub API call per reconnect is fine; per-user retries could hit secondary rate limits. **Resolved:** GitHub's installation-token API has generous limits; single GET per user action is safe.)
2. Should we also add `GIT_CONFIG_NOSYSTEM=1` to prevent `/etc/gitconfig` from injecting unexpected credential helpers? (**Resolved during deepen:** yes — now folded into Phase 1 GREEN env spec.)
3. Should we introduce a circuit breaker that opens if `REPO_ACCESS_REVOKED` rate exceeds N/hour, alerting ops? (**Defer** — file a follow-up observability issue.)
4. Should the diagnostic retry (Phase 1 GREEN, final bullet) be behind a feature flag so we can toggle it off without a redeploy once Phase 0 findings are confirmed? (**Recommendation:** yes — add an env-var gate `CLONE_DIAGNOSTIC_RETRY=1`; default off in prod after one week.)
5. Should we migrate away from `git` subprocess entirely in favor of `isomorphic-git`? (**Defer** — creates a larger surface change. File issue scoped to "evaluate isomorphic-git vs. shelling out" after Phase 1 is live for 2 weeks.)

---

## Deepen: Research Insights

### Git credential precedence — the load-bearing reason our current code silently fails

Per [git-scm.com/docs/gitcredentials](https://git-scm.com/docs/gitcredentials):

> "Without any credential helpers defined, Git will try the following strategies to ask the user for usernames and passwords: `GIT_ASKPASS`, `core.askPass`, `SSH_ASKPASS`, then the terminal."

The inverse is also true: **if a credential.helper IS configured, `GIT_ASKPASS` is not consulted until all configured helpers fail.** Our current code:

```ts
execFileSync("git", ["-c", `credential.helper=!${helperPath}`, "clone", ...])
```

explicitly configures a credential.helper. In the observed failure, that helper is failing (reason TBD by Phase 0), and git falls through. Without `GIT_TERMINAL_PROMPT=0`, git attempts the terminal prompt — and with `stdio: "pipe"`, the kernel returns `ENXIO` ("No such device or address") on the open, producing the exact observed error.

### Why `GIT_ASKPASS` + explicit helper reset is superior

1. **No shell indirection**: git invokes the askpass program directly via `execve`, not via `sh -c`. One fewer moving part, no dependence on `/tmp` exec flags.
2. **Token stays out of argv**: the task-prompt string (e.g., `Username for 'https://github.com':`) is `argv[1]`; the response goes to stdout. Neither is the token.
3. **Resetting inherited helpers**: `-c credential.helper=` at invocation time clears any `/etc/gitconfig` or `~/.gitconfig` helper list, making `GIT_ASKPASS` the sole credential path. Belt-and-suspenders with `GIT_CONFIG_NOSYSTEM=1`.
4. **Deterministic prompt suppression**: `GIT_TERMINAL_PROMPT=0` converts the silent fall-through ("No such device or address") into an explicit `terminal prompts disabled` error — easier to pattern-match in stderr and surface as `AUTH_FAILED`.

### Shell-injection hardening

The **initial plan interpolated the token into the script body** (`Password*) echo "<TOKEN>" ;;`). If the token contained a shell metachar (`"`, `$`, `` ` ``, `\n`), it would break out of the `echo` argument. GitHub's `ghs_` tokens are alphanumeric today — but are not formally spec'd (GitHub docs do not document the exact charset; see `WebFetch` of `/docs/rest/apps/apps` during deepen). Future format changes would silently regress us into injection territory.

The **deepened plan passes the token via environment variable** (`GIT_INSTALLATION_TOKEN`) and has the script `printf` it. `printf` on a single `"%s"` format token is injection-safe regardless of value — the string is written literally, no re-evaluation. Script body is fixed-bytes, identical across every invocation.

### GitHub App installation-token lifecycle — edge cases beyond expiry

Found during deepen research (GitHub REST API docs, community discussions):

| State | `generateInstallationToken` HTTP | `GET /repos/{owner}/{repo}` HTTP | Our handling |
|---|---|---|---|
| Happy path | 201 | 200 | Clone proceeds |
| Installation never existed | 404 | (not reached) | Wraps as `"Token generation failed: ..."` — existing code OK |
| Installation suspended by user | 403 | (not reached) | Same path; wrap with `errorCode: "INSTALLATION_SUSPENDED"` (Phase 3 extension) |
| Installation exists but repo access was revoked | 201 (token OK) | 404 | Caught by Phase 3 preflight → `REPO_NOT_FOUND` |
| Repo was deleted from GitHub | 201 | 404 | Same as above — same `REPO_NOT_FOUND` code (correct UX: "Repo not accessible — choose another") |
| Repo made private and installation has no access | 201 | 404 | Same as above |
| App uninstalled entirely | 404 at token | (not reached) | Wraps as `"Token generation failed"`; Phase 4 UX maps to reinstall CTA |

### `x-access-token` is convention, not magic

GitHub community discussion [#173881](https://github.com/orgs/community/discussions/173881) confirms: "The `x-access-token` string is not a 'magic' value that the server checks… GitHub's authentication backend completely ignores the username field if you provide a valid token in the password slot."

Implication for our plan: **we keep `x-access-token` for auditability** (grep-friendly in access logs), but tests do NOT need to depend on it being meaningful. Tests assert: "any non-empty username, token in password slot, and GitHub accepts." This decouples our test suite from an undocumented GitHub convention that could theoretically change.

### Container credential-helper failure modes (background)

Documented by Docker, VSCode Remote Containers, and countless issues (see [docker/compose#9605](https://github.com/docker/compose/issues/9605), [microsoft/vscode-remote-release#7184](https://github.com/microsoft/vscode-remote-release/issues/7184)): bind-mounted or generated credential helpers frequently fail in containers because of:

- Host ↔ container permission mismatches (chmod bits look right on host but rewrite on mount).
- `/tmp` as tmpfs with `noexec` in hardened images (Alpine, distroless, security-sandbox CNs).
- Helper binaries compiled for the host architecture, not the container.
- User-namespace UID-remapping hiding the helper file from the container's git process.

The `!`-prefix pattern assumes a developer laptop where host credential stores are available. In production containers, it's a known fragile idiom. Our switch to `GIT_ASKPASS` + an in-container script is the documented community answer to this class.

### Verbatim-preserved strings audit

Per deepen quality checks, the following string literals appear in multiple sections and MUST match exactly across them:

- Error codes: `AUTH_FAILED`, `REPO_NOT_FOUND`, `REPO_ACCESS_REVOKED`, `INSTALLATION_SUSPENDED`, `CLONE_NETWORK_ERROR`, `CLONE_TIMEOUT`, `CLONE_UNKNOWN`. These appear in: Fix strategy (Phase 1), Test Scenarios (#11), Acceptance Criteria, Phase 4 UX. **Pinned.**
- Env var names: `GIT_ASKPASS`, `GIT_INSTALLATION_TOKEN`, `GIT_USERNAME`, `GIT_TERMINAL_PROMPT`, `GIT_TERMINAL_PROGRESS`, `GIT_CONFIG_NOSYSTEM`, `CLONE_DIAGNOSTIC_RETRY`. Appear in Phase 1 GREEN env spec, Test Scenarios #3/#5/#6, Open Questions. **Pinned.**
- Script path pattern: `$HOME/askpass-<uuid>.sh` (NOT the original `$HOME/.soleur-git-askpass-*` mentioned in Risks). The Risks table item for periodic sweep should reference the canonical `askpass-<uuid>.sh` pattern — fix in follow-up.

### External SHAs / version citations resolved live

- git 2.23 (introduced `-c credential.helper=` reset semantics) — confirmed via `man 7 gitcredentials` section "Custom Helpers" history.
- `node:22-slim` image ships with git 2.39+ — not asserted in plan; work phase should run `docker run --rm node:22-slim git --version` and record.
- GitHub REST API endpoint `GET /repos/{owner}/{repo}` — schema and 404/403 responses from [docs.github.com/en/rest/repos/repos#get-a-repository](https://docs.github.com/en/rest/repos/repos#get-a-repository), API version `2022-11-28` (already used by our `githubFetch` helper at `server/github-app.ts:199`).

### References (canonical)

- <https://git-scm.com/docs/gitcredentials> — credential helper semantics, `!` prefix, `GIT_ASKPASS`, precedence.
- <https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation> — installation token generation, 1h expiry, `x-access-token` convention.
- <https://docs.github.com/en/rest/apps/apps?apiVersion=2022-11-28#create-an-installation-access-token-for-an-app> — endpoint spec, status codes 201/401/403/404/422.
- <https://github.com/orgs/community/discussions/173881> — "x-access-token is convention, not required."
- <https://coolaj86.com/articles/vanilla-devops-git-credentials-ultimate-guide/> — "Ultimate Guide to Git Credentials" (covers the `GIT_ASKPASS` pattern in Node contexts).
- <https://blog.devops.dev/using-git-askpass-to-wire-in-token-authentication-minimal-changes-maximum-ease-609d007dfdad> — `GIT_ASKPASS` in CI/container contexts.
- <https://github.com/docker/compose/issues/9605> — Docker's corpus of credential-helper failure modes in containers.
- AGENTS.md rule `hr-ssh-diagnosis-verify-firewall` — NOT triggered (this is not an SSH symptom), but the L3→L7 principle applied to Phase 0 (exec probe before code change).
- AGENTS.md rule `cq-for-production-debugging-use` — Phase 0 SSH is read-only diagnosis only; fixes go through code.
- AGENTS.md rule `cq-silent-fallback-must-mirror-to-sentry` — Phase 1 adds `Sentry.captureException(err)` on the helper-failure diagnostic branch (the retry path captures to both pino `log.error` and Sentry so the verbose-trace signal shows up in Sentry breadcrumbs).
- AGENTS.md rule `cq-code-comments-symbol-anchors-not-line-numbers` — plan cites `server/github-app.ts:199` in Research Insights; work phase should replace with symbol anchors (`githubFetch`) at implementation.

---

## Network-Outage Deep-Dive — Not Applicable

Triggers scan (case-insensitive): `SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `timeout`, `502`, `503`, `504`, `handshake`, `EHOSTUNREACH`, `ECONNRESET` — only `timeout` appears (as `CLONE_TIMEOUT` error code), which is not a network-outage symptom.

`hr-ssh-diagnosis-verify-firewall` rule is not engaged. Phase 0 still includes a `curl -I https://github.com/` smoke-test to rule out egress issues, but no L3 firewall check is required (GitHub is WAN-side; hcloud firewall manages ingress only).
