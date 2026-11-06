---
title: "fix(approval): ADR-309 flip item 9b - push the approved commit from an isolated git directory"
date: 2026-11-06
slug: adr309-9b-isolated-git-dir-push
branch: feat-one-shot-9601-adr309-9b-push-hardening
issue: 9601
type: fix
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix(approval): ADR-309 flip item 9b - push the approved commit from an isolated git directory

Epic Ref #9601. One PR. `Ref #9601` only: the PR closes nothing and files no issue (net issue flow 0). No Standing
Delegation exists, so every production act stays an operator hold and this plan contains none.

## Overview

The cc form of the approved `github_push_branch` push (shipped dark by the PR that closed flip item 9a) still runs `git` in
the dispatch process with `GIT_DIR` pinned to `<workspace>/.git`, a directory the agent can write. Everything git reads from
that directory is therefore agent-controlled, and the hardening shipped so far can only layer `-c` resets on top of it. The
CTO ruling (2026-11-06, recorded in `decision-challenges.md`) is to stop reading it: the server creates a fresh bare git
directory in a server-owned temp location, writes its config itself, exposes the workspace object store to it only through
`GIT_ALTERNATE_OBJECT_DIRECTORIES`, pushes `<sha>:refs/heads/<branch>` to the literal URL from there, and deletes the
directory in a `finally`. The approval gate's own read of the workspace HEAD (`gitHeadSha`, a plain `git rev-parse HEAD`
with the inherited environment) is replaced by a read that executes no git.

What this does NOT do, stated up front so no prose downstream overclaims it: it discharges no flip item. Items 1-8 and
10-12 remain. Whether the cc sandbox can write `<workspace>/.git` stays UNVERIFIED (flip evidence: the live probe, an
operator hold). Item 9 stays a precondition beyond the canary until this PR merges, and after it merges the ADR records this
PR as the closer of the 9b code limb only.

## Research Reconciliation - Spec vs. Codebase

No spec.md exists for this branch; the brief and ADR-309 are the spec. The brief and the ADR make claims the measurements
below contradict or complete. Each is carried into the plan:

| Claim (source) | Reality (measured 2026-11-06, git 2.56.0) | Plan response |
|---|---|---|
| "Pins for `GIT_DIR`, `GIT_COMMON_DIR` and `GIT_OBJECT_DIRECTORY` ... a `commondir` file cannot redirect" (ADR-309 addendum item 7; `git-hardened-env.ts` header) | FALSE for ref resolution. With all three pinned to `<ws>/.git`, a planted `.git/commondir` still made `git rev-parse HEAD` return the other repository's HEAD (`--git-common-dir` prints the pinned dir, the refs backend reads the file anyway). The shipped pre-flight refusing `commondir` is what actually covers it, non-atomically. | Correct item 7 in place (Fork D). The new control is "never run git against the workspace `.git`", not env pinning. Regression test plants `commondir`. |
| "Close it by pushing from an isolated trusted GIT_DIR with GIT_ALTERNATE_OBJECT_DIRECTORIES" (brief, ADR 9b) | Works for a commit whose objects live only in the alternate, loose or packed, whole ancestry arrives, remote `fsck` clean (E1). | Adopt. |
| (unstated) workspace clones are complete | Workspaces are `git clone --depth 1` (`server/ensure-workspace-repo.ts`). From a fresh GIT_DIR WITHOUT the shallow boundary the push FAILS (`remote unpack failed: eof before pack header`) whenever the remote branch advanced past the clone (E2). Copying `.git/shallow` into the isolated dir fixes it. | The isolated dir carries a validated copy of `shallow` (Fork B). Real-git test with a remote that is ahead. |
| (unstated) a missing commit fails the push locally | A push of a sha absent from the object store does not fail locally; the remote answers `unpacker error` (E1 negative control). | The local `cat-file -e <sha>^{commit}` check stays, run in the isolated environment. |
| "`remote.*.pushurl` is not a vector" (ADR 9b) | Still true; and moot now. | Keep the sentence, add that the isolated config has no remotes at all. |
| "git follows only the object directories we name" (implicit in option (ii)) | git follows `<alternate>/info/alternates` chains (E5): a planted `.git/objects/info/alternates` exposes another store's objects to the isolated push. A `:` in the alternate path breaks `GIT_ALTERNATE_OBJECT_DIRECTORIES`. | Narrowed pre-flight keeps the alternates refusal and validates the alternate path (Fork B). |
| Gate: "`gitHeadSha` ... inherited environment" is the exposure | Also: an inherited `GIT_DIR` in the server environment redirects the current read to another repository (E4a). | JS reader that never consults the environment or any git config (Fork A). |
| "The tracking issue for 9b is filed by `soleur:ship`" (ADR 9 cohort bullet) | Superseded by CTO ruling 2 (net issue flow 0). | Sentence replaced; PR is recorded as the closer. |

## Research Insights

### Premise Validation (Phase 0.6)

Checked: #9601 (epic, OPEN), #11636 and #11635 (OPEN; the registration PR that shipped 9a is merged as #12188). The draft
PR for this very branch (#12216) is the only open change naming #9601, not a collision; the three `test-all.sh` processes
the collision pre-check lists belong to other worktrees. Cited paths exist on `origin/main` (`push-branch.ts`,
`git-auth.ts`, `git-hardened-env.ts`, `approval/gate.ts`, both test files, ADR-309 and its archived handover copy). The
ADR corpus was grepped for the mechanism: ADR-309 9b names option (ii) as an allowed closure, so it is not a rejected
alternative. Open code-review issues touching any planned file: none.

### Property List and Cut List (Phase 0.6b)

Properties the change must buy:

1. P1: no config, hook, ref, index or `commondir` file in the agent-writable workspace is read by the git child that carries the installation token.
2. P2: the token-bearing child cannot be pointed at another host, proxy, resolver or CA by anything the agent wrote.
3. P3: the approved commit, with the ancestry the remote lacks, still reaches the remote (shallow clones included).
4. P4: the gate's displayed HEAD is read without executing git and without consulting the server environment or repo config.
5. P5: the temp directory never outlives the call, success or failure (except process death: SIGKILL/OOM skips `finally`; the leaked directory holds no secret).
6. P6: legacy runner argv and environment stay byte-identical.
7. P7: the ADR and its handover copy say exactly what the code does, and no more.

Mechanisms considered and cut:

| Mechanism | Buys | Cut because |
|---|---|---|
| Keep the 9a pre-flight in full (config, HEAD, hooks, refs, commondir, grafts, packed-refs) | P1 for the old design | Nothing reads those files in the new design; keeping them adds false refusals and a non-atomic "control" that closes nothing (Fork B). |
| `GIT_SHALLOW_FILE` env pointing at a copy | P3 | A file inside the server-written dir needs no extra environment variable; measured equivalent (E2 arm B vs C). |
| Hardened git + full pre-flight for the gate read | P4 | `GIT_COMMON_DIR` pin is ineffective (E4); would leave the only protection non-atomic (Fork A). |
| Live sandbox probe (option i) | P1 evidence | Needs a production action; rejected by ruling 1. Stays the flip evidence. |
| New Sentry op per refusal reason beyond one `isolated-dir-refused` op with a `reason` tag | diagnosability | One op with an enum tag discriminates all refusal causes in one event. |
| Per-tenant UID / mount boundary | removes the object-store residual | Separate item, not a 9b blocker (Fork B). |
| `GIT_COMMON_DIR`, `GIT_OBJECT_DIRECTORY`, `GIT_CEILING_DIRECTORIES` pins on the isolated child | nothing | A fresh bare dir has no `commondir`, defaults its object dir, and never runs discovery once `GIT_DIR` is set (review round). |
| `repositoryformatversion = 1` + `extensions.objectformat` | sha256 safety | The 40-hex rule already excludes sha256; version 0 is universally accepted (review round). |
| Startup sweep of leaked `soleur-push-*` directories | P5 after process death | A leaked directory holds no secret (the token is only in the child env); YAGNI. |
| `realpath` re-check before each spawn | narrower TOCTOU window | Microsecond window against a residual already accepted as non-atomic; theatre. |
| A second Sentry op vs a `reason` on `approval-grant-refused` | diagnosability | Kept the separate op: the alternative edits `grants.ts`, three anchored mutation rows and a pinned list. |
| `packed-refs` branch of the HEAD reader | P4 correctness | KEPT despite a simplicity cut suggestion: `git gc --auto` packs `refs/heads/*`, so removing it makes routine repo maintenance a permanent gate failure. |

### Measurements that the tests reproduce (scripts ran in the session scratchpad, real git 2.56.0)

- E1 isolated dir + alternate pushes an alternate-only commit; remote `fsck` clean; isolated `objects/` stays empty; a missing sha does not fail locally.
- E2 shallow workspace, remote ahead: no shallow file = FAIL; `<iso>/shallow` or `GIT_SHALLOW_FILE` = OK.
- E3 over real TLS (local `openssl` server, self-signed cert), CONTROL (9a form) vs ISOLATED, hostile `.git/config`: `http.<url>.sslVerify=false`, `http.<url>.sslCAInfo=<attacker CA>`, a more specific `http.<url>.proxy` (beats the `-c` reset of the broader key), `http.curloptResolve`, `url.*.insteadOf`, `url.*.pushInsteadOf` all take effect in the control and none in the isolated form; `git config --list --show-origin` in the isolated child lists only the server-written file and `command line`.
- E4 `commondir` redirect survives the three pins (above); inherited `GIT_DIR` redirects the old gate read; a `gitdir:` file fails closed under a pinned `GIT_DIR`.
- E5 alternates chain is followed; `:` in the path breaks the variable; a 64-hex id is rejected by a sha1 repository.

### Institutional learnings applied

- `2026-11-06-a-guard-on-the-registrar-result-...-hardening-prose-was-false-four-times`: every universal claim in the ADR and code comments carries the command that falsifies it (Claims ledger below); refusal tests use a target that CONTAINS the approved commit so only the check can refuse.
- `2026-10-13-an-identity-read-from-an-untrusted-repo-needs-a-layout-anchor-a-size-gate-...`: the JS HEAD reader gates every read by `fstat` size before reading, checks bytes read equal the size, and denies ref names by a deny-list.
- `2026-04-17-kb-share-mcp-parity-lstat-toctou-and-mock-cascade`: no pre-open `lstat` on a path that is then opened; use `O_NOFOLLOW` + `fstat` for files, and `readdir` with `withFileTypes` (Dirent types, no second path lookup) plus a `realpath` equality check for directories.
- `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526`: the env stays allowlist-only; the builder module keeps zero heavy imports.
- `2026-09-07-the-gate-that-fires-most-was-manufacturing-its-own-evidence`: count-indexed env is `GIT_CONFIG_KEY_0` / `GIT_CONFIG_VALUE_0` (underscore); a test that injects it asserts it was observed by the control.
- `2026-08-20-my-mutation-battery-sampled-the-axes-i-already-believed-in`: mutation rows cover every git spawn site and every file the isolated child could read, not only the ones the design believes in.
- `2026-05-16-adr-amendment-required-when-reversing-...`: the ADR text on `main` is amended in the same PR, and the mirrored handover copy is edited with it.
- Process learnings from the brief: a new suite reading outside `apps/web-platform` is listed in `test/repo-wide-suites.ts`; tests that spawn git use `gitFixtureEnv` and strip `GIT_CONFIG_COUNT`/`KEY_n`/`VALUE_n`/`GIT_CONFIG_PARAMETERS`; select Anthropic content blocks by type (nothing here touches them); the registration guards are re-asserted on the PUBLISHED set (this PR changes no registration, and a census test asserts the push tool's published set is unchanged).

External research: none needed. Git semantics were measured against the real binary, which is the authority for this change.
Registry overlap check (Phase 1.5/1.5b): internal server hardening of one module family; no community skill or agent
covers it, so no registry search was run.

## User-Brand Impact

- **If this lands broken, the user experiences:** an Owner-approved push that fails after the approval was spent (the card says approved, the tool result says `PUSH_FAILED_APPROVAL_SPENT`, nothing lands, a new conversation and a new approval are needed), or - worse - a refusal (`commit_unavailable`) on a perfectly normal shallow workspace because the isolated dir lacks the shallow boundary.
- **If this leaks, the user's workflow is exposed via:** a prompt-injected agent that wrote `url.<base>.insteadOf`, `http.<url>.proxy`/`sslVerify`/`sslCAInfo`/`curloptResolve` into its own `.git/config`, so the one-hour GitHub installation token (write access to the connected repository) is sent to an attacker-chosen host or read from a TLS-stripped connection on an Owner-approved push that looks benign on the card.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one user's repository write token reaching a third party through a push that user explicitly approved is the incident the approval gate exists to prevent, so `aggregate pattern` understates it; the feature is dark, which lowers likelihood, not the tier.

`requires_cpo_signoff: true` (CPO advisory obtained at plan time, recorded in `## Domain Review`). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Proposed Solution

### Design (all in `apps/web-platform/server/`)

**1. `git-isolated-push-dir.ts` (new leaf).** `createIsolatedPushDir(workspacePath): IsolatedPushDirHandle` where the handle
is `{ gitDir, alternateObjectDirectory, dispose() }` and satisfies the branded `IsolatedPushDir` type of the env leaf (below),
plus a typed `IsolatedPushDirRefusal extends Error` carrying a closed `readonly reason`:
`"git_dir_not_plain" | "object_store_redirect" | "alternate_path_unsafe" | "shallow_invalid" | "setup_failed"`.
Order is load-bearing: every workspace check resolves BEFORE the first write (the temp dir is created last). Steps 1-4 are
wrapped so no raw fs error escapes: ENOENT -> `git_dir_not_plain`, any other errno -> `setup_failed`, and no `cause`/message
carrying a path leaves the module.

1. Resolve `ws = realpathSync(workspacePath)` (absolute required). `objects = <ws>/.git/objects`; require `realpathSync(objects) === objects` (this rejects a symlinked `.git`, a symlinked `objects`, a `gitdir:` file (no `objects` under it) and any symlinked ancestor in one comparison, with no pre-open `lstat`).
2. `alternate_path_unsafe` when `objects` contains `:`, `"`, `\`, a newline or NUL (E5: `:` splits the variable). The pure predicate lives in the env leaf so the builder enforces the same rule.
3. ONE `readdirSync(..., { withFileTypes: true })` loop over `objects`, `objects/pack` and `objects/info`: any symlink Dirent refuses (`object_store_redirect`); an `alternates` or `http-alternates` entry under `objects/info` refuses (E5 chain). Stated exactly (no wider claim): the direct children of those three directories are checked; the loose-object files INSIDE the fan-out directories are not walked (residual, same class as the non-atomic residual below).
4. `shallow`: read `<ws>/.git/shallow` through the one shared helper `readSmallRegularFile(path, maxBytes)` (below); ENOENT = not shallow; a non-regular file (FIFO, device), a size above 64 KiB or a short read refuses (`shallow_invalid`); every non-empty line must match `/^[0-9a-f]{40}$/` else refuse.
5. Only now `mkdtempSync(join(tmpdir(), "soleur-push-"))` (mode 0700, unpredictable name). Assert `realpath(gitDir)` is not under `ws`. The claim that the sandbox cannot write it rests on `server/agent-runner-sandbox-config.ts` (`allowWrite` is `[workspacePath]` plus its own `claude-<uid>` directory), which is configuration, not a live probe, and the agent shares the server's uid, so mode 0700 is not the control: path placement is. Write, with `fs`, never git: `HEAD` (`ref: refs/heads/main`), `config` (`[core] repositoryformatversion = 0` and `bare = true`; measured working on 2.56, and the 40-hex rule already excludes sha256, so no `extensions.objectformat`), empty `objects/{pack,info}`, `refs/{heads,tags}`, and `shallow` (mode 0600, only when the source had lines). No `git init` spawn, no templates, no hooks directory.
6. Any throw after step 5 removes the directory and rethrows; `dispose()` is idempotent, swallows ENOENT, and a throwing `dispose()` never changes the push result. A SIGKILL/OOM of the server skips the `finally` and leaks the directory; it holds only `HEAD`, `config` and `shallow` (no token: the token lives only in the child environment), so the leak is accepted and no startup sweep is added (YAGNI). "Never outlives the call" is therefore claimed for every path except process death.

**Shared helper.** `readSmallRegularFile(path, maxBytes)` (exported from `server/approval/workspace-head.ts`, imported by the creator): open with `O_RDONLY | O_NONBLOCK | O_NOFOLLOW`, `fstat` must be a regular file, size <= `maxBytes`, read in a loop until exactly `size` bytes are read (bytes read must equal the stat size), return the string; it is the only place this pattern is written (shallow, HEAD, ref file, packed-refs). A FIFO/hang regression test carries an explicit vitest timeout so it fails instead of hanging.

**2. `git-hardened-env.ts` (stays a leaf: `node:path` + `_git-hardening` only; it must never import the creator, which uses `fs`).** Add the
structural, branded `IsolatedPushDir` type (`{ readonly gitDir: string; readonly alternateObjectDirectory: string; readonly [brand]: true }`
with a `unique symbol` brand that only the creator sets), the pure path-safety predicate `isSafeGitPath(p)` (absolute; no `:`, `"`, `\`,
newline, NUL), and `buildIsolatedGitEnv(dir, extra)`; remove `buildHardenedGitEnv` (its only two callers move; keeping it would
leave dead code carrying the false `GIT_COMMON_DIR` comment). Env = allowlist + `GIT_HARDENING_ENV` + `GIT_DIR` = `gitDir`,
`GIT_ALTERNATE_OBJECT_DIRECTORIES` = `alternateObjectDirectory`, `GIT_ALLOW_PROTOCOL=https`, then `extra`. Review cut the pins that
do nothing for a server-written bare directory (`GIT_COMMON_DIR`, `GIT_OBJECT_DIRECTORY`, `GIT_CEILING_DIRECTORIES`): a fresh
directory has no `commondir` file, its object directory defaults to `<gitDir>/objects`, and discovery never runs once `GIT_DIR` is set;
the mutation rows that anchored on them are deleted, not preserved (the battery must not dictate the code). The builder throws on
a path `isSafeGitPath` refuses. The header comment is rewritten: the "NOT covered here" paragraph goes, the false `commondir`
sentence goes, and the 9a `-c` resets are described for what they are (defence in depth on top of a config the child no longer reads).

**3. `git-auth.ts` (hardened branch only).** `GitExecOptions.hardened` becomes `IsolatedPushDir` (was `true`). A hardened call is
validated at RUNTIME before the token mint (a stray `true`, an `as any` value, a relative or unsafe path, or a missing brand
refuses: same ordering guarantee as the current cwd guard), takes no `cwd` of its own (a caller-supplied `cwd` with `hardened`
throws, never silently overridden), runs with `cwd: hardened.gitDir` placed AFTER the `...execOpts` spread, builds the env with
`buildIsolatedGitEnv(hardened, authEnv)`, and keeps `[...HELPER_RESET, ...HARDENED_GIT_ARGS, ...args]`. `git-auth.ts` imports only
the env leaf, never the creator. The non-hardened branch and its `{ ...process.env, ...authEnv }` are not touched (P6, pinned by
the existing legacy-form tests).

**4. `push-branch.ts`.** Hardened flow: validate force/branch/protected as today; require `commitSha` (a hardened push with no
sha is refused as `ApprovedCommitUnavailableError`, Fork C) and require exactly 40 lowercase hex (one check and one message; sha256 ids
are rejected there, and the gate reader below already refuses to show one, so no card can display a sha the push will refuse after the
approval is spent); `createIsolatedPushDir`: the four workspace-tamper reasons (`git_dir_not_plain`, `object_store_redirect`,
`alternate_path_unsafe`, `shallow_invalid`) become `ApprovedCommitUnavailableError` with the SAME static text as today and an unchanged
`name` (reported as `commit_unavailable`), while `setup_failed` is an infrastructure failure and throws a plain `Error("Push could not be
prepared")` (static text, no path, no `cause`) so it flows through the existing tool-error path and the `PUSH_FAILED_APPROVAL_SPENT` line
(the CPO condition: the text says plainly that the approval was spent and nothing landed); every refusal emits one
`reportSilentFallback(null, { feature: "cc-push", op: "isolated-dir-refused", extra: { reason } })`; `cat-file -e <sha>^{commit}` in the isolated
environment (`cwd` = isolated dir, 10 s timeout); NO `git config user.*` calls in hardened mode (Fork C); the single existing
`gitWithInstallationAuth(["push", repoUrl, `${commitSha ?? "HEAD"}:refs/heads/${branch}`], ...)` call site keeps its text and gains
`hardened: isolated` (and loses `cwd`) for the hardened form; `finally { isolated?.dispose() }`. `assertPlainGitDir`, the two entry lists
and their mirror-comment are deleted (their coverage moves to step 1 of the creator). The legacy path is unchanged. Known gap, recorded
not built: the gate consumes the approval before the handler runs, so a `setup_failed` (tmpdir not writable) spends an approval;
availability only, the CPO accepted it with the failure text condition above.

**5. `approval/gate.ts` + `approval/workspace-head.ts` (new leaf; imports only `node:fs`, `node:path`, `./canonical`, asserted by a content test).**
`readWorkspaceHeadSha(workspacePath)` reads data, spawns nothing, reads no environment variable and no git config (Fork A). What it
removes is the risk of git running in the server process under agent-controlled config and an inherited `GIT_DIR`; it does not
pretend HEAD cannot be falsified (the agent writes HEAD, refs and objects anyway: the control that matters is that the approved sha
equals the pushed sha plus the local `cat-file` check). A worktree-style `.git` file fails closed. Algorithm, all reads through
`readSmallRegularFile`: `HEAD` (<= 4 KiB). `ref: <name>`: validate `<name>` (starts `refs/`; no `.`, `..`, empty, NUL or backslash component; no
`.lock` suffix), read `<ws>/.git/<name>` (loose file; accept only an exactly 40-hex body, trailing newline trimmed, uppercase and CRLF
refused), then compare `realpath` of the file against the real `<ws>/.git` AFTER the read and fail closed on a mismatch (read-then-verify, no
check-then-open; this value is display-only, the push re-verifies by sha); if the loose file is absent read `packed-refs` (regular file,
<= 8 MiB, the first exact `<40-hex> <name>` line, skipping `#` and `^` lines; a loose ref always shadows a packed one). The packed-refs
branch stays because `git gc --auto` runs `pack-refs --all` and would otherwise turn an agent's routine repository maintenance into a
permanent gate failure. A loose file that is itself `ref: ...` (deeper than the one hop HEAD already took), a `.git/reftable` directory, an unborn
HEAD, a missing/unresolvable ref, or any non-regular file refuses by throwing. A detached HEAD (40-hex body) returns it. `gitHeadSha` in
`gate.ts` becomes a three-line wrapper (read, `COMMIT_SHA_RE` check with the existing message, which keeps mutation row G1-GD24 anchored),
and the `execFile` imports go.

### Attack Surface Enumeration (security fix)

| Vector the agent controls | 9a form (shipped) | This PR | Falsifier |
|---|---|---|---|
| `.git/config` `url.*.insteadOf` / `pushInsteadOf` | token diverted (E3) | not read | real-git test, push lands in the good remote, control lands in the evil one |
| `http.<url>.proxy` more specific than the `-c` reset | diverted | not read | TLS test: control "Failed to connect ... over proxy", isolated TLS error |
| `http.<url>.sslVerify=false`, `sslCAInfo` | TLS stripped | not read | TLS test: control passes the handshake, isolated "self-signed certificate" |
| `http.curloptResolve`, `http.extraHeader` | host redirected | not read | resolve test and server-observed header |
| `core.hooksPath`, hooks, `core.fsmonitor`, attributes | neutralised by `-c` | not read (and `-c` kept) | existing planted-hook tests, now also "workspace hooks dir is never consulted" |
| `commondir`, `config.worktree`, `info/grafts`, `refs/replace`, `index`, `HEAD`, `packed-refs` | refused by pre-flight, NOT neutralised by pins (E4) | not read at all | symlinked/planted copies of each: push still succeeds, nothing read |
| `objects/info/alternates` (chain) | refused | refused (E5) | alternates test with a victim commit present in the target store |
| symlinked `objects`, `objects/pack`, fan-out dir, pack file child | refused | refused (children of `objects`, `pack`, `info`) | symlink tests with a target that CONTAINS the approved commit |
| `shallow` as FIFO / oversized / non-hex | not read by pre-flight | refused | FIFO + size + hex tests |
| inherited server `GIT_DIR` / env secrets | allowlist for the push, NOT for the gate read | allowlist; gate spawns nothing | env-dump PATH-shim test; `process.env.GIT_DIR` canary |
| non-atomic swap after the pre-flight | possible, config/token impact | possible, object-bytes impact only (cross-tenant, known sha) | stated residual; no test can close it |

Residual, accepted by CTO ruling (Fork B): object-store read redirection after the check. Not closed: whether the cc sandbox can
write `<workspace>/.git` (UNVERIFIED, live probe, operator hold); whether workspace paths are unguessable (UNVERIFIED).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-309 (no new ordinal; status stays `adopting`):

1. **Flip checklist item 9, rewritten in place** (the checklist is a living list copied verbatim into the handover; the CTO ruling says rewrite the 9b bullet in place). The 9a bullet is ALSO rewritten in place with a one-line "superseded by the 9b closure" note: it lists the `GIT_COMMON_DIR` pin and the `.git` pre-flight (`commondir` etc.), which this PR deletes and which the measurement shows did not do what the bullet says. Replace the 9b bullet with what is now closed (token diversion, `http.<url>.*`, `curloptResolve`, `sslVerify`/`sslCAInfo`, the non-atomic `.git` pre-flight for config/HEAD/refs, the gate's HEAD read), what remains (non-atomic object-store redirection; the UNVERIFIED sandbox-write limb), record "closer of the 9b code limb: this PR (Ref #9601)", and state that item 9 stays a precondition beyond the canary until this PR merges and that the live probe remains the flip evidence. Delete the sentence "The tracking issue for 9b is filed by `soleur:ship` ..." (ruling 2: none filed). Keep `remote.*.pushurl` sentence.
2. **Addendum item 7 and item 11** (dated text already on `main`; the ADR's own rule is inline italic forward pointers, not rewrites): append an italic *Superseded in part, 2026-11-06* pointer, leaving the old wording visible (Fork D), at EACH falsified place: item 7 clause (2) (the pins and "a `commondir` cannot redirect" claim), clause (3) (the `assertPlainGitDir` entry lists and the `_cron-safe-commit` mirror, now deleted), the closing sentence "What it does not close is item 9b", the addendum's summary paragraph ("the wider `.git` pre-flight"), and the item 11 9b sentence.
3. **New dated section** `## Addendum - 2026-11-06 (epic Ref #9601): flip item 9b, push from an isolated git directory`, numbered like the earlier addenda but SHORT: the design in five sentences, the measurement table (E1-E5, each with the command that reproduces it), the correction of item 7, the residuals, the explicit "discharges nothing" sentence, the test file names, and the "CI is the gate; the slow local `--affected` battery was not awaited" record. The Claims ledger stays in this plan only (review cut the duplicate).
4. **Handover copy** `knowledge-base/project/specs/archive/20261029-164429-feat-hitl-approval-queue/flag-create-handover.md`: the item-9 block (9 with its 9a, 9b and cohort sub-bullets) is byte-identical to the ADR's today; apply the identical replacement (9a and 9b) and assert parity by CONTENT anchor, not line numbers: extract both blocks from the line starting `9. **` `.git` hook, config and environment exposure` up to (not including) the line starting `10. **Register and DPA preconditions` and `cmp` the two extracts.
5. The ADR makes the claim "the isolated form reads no workspace config"; per the negative-claim learning the amendment names the command that would falsify it (`git config --list --show-origin` in the exact child environment lists only the server-written file and `command line`) and the test that runs it.

No public document, legal text, marketing page or compliance-posture file is touched; no security-posture claim is added anywhere public (operator hold).

### C4 views

READ in full: `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`. Conclusion: **no C4 impact**, with the enumeration the gate requires:
(a) external human actor: the workspace Owner (`model.c4` actor at line 70, already multi-Owner) - unchanged; (b) external system: GitHub - the push edge `engine -> github "Git operations and CI"` (line 609) already exists and the target host/protocol do not change; (c) container/data store touched: `workspacesVolume` (line 349, per-user checkouts, read-only access through the object store, unchanged) and `approvalStore` (line 329, untouched); the temp directory is a process-local, per-call, deleted-in-finally directory, not a store; (d) actor-surface access relationship: no change. No element description is falsified (grep of `model.c4` for push/insteadOf/alternates/installation found only the entries above). `plugins/soleur/test/c4-count-parity.test.sh` was run at plan time: 13 passed, 0 failed.

### Sequencing

The decision is true when this PR merges; nothing is soak-gated. The ADR is authored in this PR, not deferred.

## Guard Contract

### Guard 1 - isolated push reads no workspace config

**Property.** The git child that carries the installation token reads no configuration, hook, ref, index or redirect file from the agent-writable workspace; the only workspace bytes it can read are object-store bytes through the alternate.

**Assembly.** Chokepoints: (1) the one creator `createIsolatedPushDir` (every file the isolated dir contains is written by it); (2) the one env builder `buildIsolatedGitEnv` (the only place `GIT_DIR`/`GIT_ALTERNATE_OBJECT_DIRECTORIES` are set for a hardened child); (3) the one hardened spawn site in `gitWithInstallationAuth`; (4) the second spawn site in `pushBranch` (`cat-file`), which must use the same env; (5) the gate's `readWorkspaceHeadSha`, which spawns nothing. More than one chokepoint exists on purpose: a guard scoped to the push spawn alone is the defect (the `cat-file` child and the gate read are the other two readers of the workspace).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `buildIsolatedGitEnv` sets `GIT_DIR` to `<ws>/.git` (the 9a regression) | RED: hostile-config real-git suite shows isolated == control for every vector |
| 2 | the creator copies the workspace `.git/config` into the isolated dir | RED: `config --list --show-origin` test lists a workspace-origin entry; sslVerify/proxy/insteadOf vectors take effect |
| 3 | the hardened `cat-file` runs with the legacy env/cwd (a SECOND spawn site, compliant first) | RED: every-git-child-uses-the-isolated-env assertion (spy over all `execFileSync`/`execFile` calls in a hardened push) |
| 4 | the fixtures stop writing the hostile config (guard's own dispatch: "0 vectors checked") | RED: the control-arm precondition test ("the hostile key is effective in the 9a-form control") fails |
| 5 | `GIT_CONFIG_GLOBAL` dropped from the child env | RED: hostile `$HOME/.gitconfig` + `$XDG_CONFIG_HOME/git/config` take effect |
| 6 | `dispose()` skipped on the failure path | RED: temp-dir-removed-after-throw test |
| 7 | shallow copy dropped | RED: remote-ahead shallow push test |
| 8 | alternates refusal dropped | RED: chain test (victim commit becomes visible) |
| 9 | `readWorkspaceHeadSha` falls back to `git rev-parse HEAD` | RED: commondir / inherited-`GIT_DIR` / spawn-counter tests |
| 10 | an extra `git config user.name` against the workspace added back in hardened mode | RED: no-git-config-against-workspace test |

Harness rows: (H1) delete the TLS-server start from the suite -> the TLS vectors must fail loudly (not skip, not pass vacuously); (H2) a must-PASS input that is not the canonical: a workspace whose `.git/config`, `HEAD`, `hooks`, `refs`, `commondir`-free `info/grafts` and `packed-refs` are all symlinks or hostile (previously refused, now ignored) still pushes; plus a normal shallow clone with a packed-only object store. (H3) `openssl` missing -> the suite fails with a named precondition test, never skips. (H4) the control arm's evil recording server sees NO `Authorization` header (mutant: server never answers 401) -> the control-effective precondition test fails.

**Anchor.** The guard compares no stored value. The independent anchor is the real `git` binary's behaviour in the control arm: each vector is shown effective under the shipped 9a environment before it is shown inert under the isolated one, so a fixture that cannot exercise git cannot pass.

## Observability

```yaml
liveness_signal:
  what: "cc-push outcome: pushBranch logs 'Branch pushed successfully' (pino) and the registrar emits the existing cc-push-registration outcome event; this PR adds the op-tagged refusal event cc-push / isolated-dir-refused"
  cadence: "per approved push (the tool is dark: no events until the flag is flipped, an operator hold)"
  alert_target: "Sentry issue feed (feature=cc-push)"
  configured_in: "apps/web-platform/server/push-branch.ts (reportSilentFallback call) and server/observability.ts"
error_reporting:
  destination: "Sentry via reportSilentFallback(null, { feature: 'cc-push', op: 'isolated-dir-refused', extra: { reason } }); the Error object is never passed (#8629 class), reason is a closed enum"
  fail_loud: "the tool result is the static commit_unavailable refusal (reported under the existing approval-grant-refused op) and a failed push after consume returns PUSH_FAILED_APPROVAL_SPENT"
failure_modes:
  - mode: "workspace .git tampered (alternates, symlinked object-store child, bad shallow)"
    detection: "isolated-dir-refused with reason=object_store_redirect | git_dir_not_plain | shallow_invalid; this is also the first in-product signal that the agent can write .git (it feeds the UNVERIFIED sandbox-write limb)"
    alert_route: "Sentry issue, feature=cc-push"
  - mode: "legitimate shallow workspace refused or fails to push (regression of the E2 fix)"
    detection: "reason=shallow_invalid or a push failure with 'unpack failed' in the relayed stderr; real-git remote-ahead test guards it pre-merge"
    alert_route: "Sentry issue + the PUSH_FAILED_APPROVAL_SPENT tool result"
  - mode: "temp directory creation fails (tmpdir not writable) or removal fails"
    detection: "reason=setup_failed event; dispose failure is log.warn with the error class only"
    alert_route: "Sentry issue, feature=cc-push"
logs:
  where: "pino child logger 'push-branch' (warn/error shipped; info is dropped by the shipper, so refusals use warn plus the Sentry op)"
  retention: "per the log shipper's retention; Sentry events per project retention"
discoverability_test:
  command: rg -c "isolated-dir-refused" apps/web-platform/server/push-branch.ts
  expected_output: "1"
```

(The op string appears exactly once in `push-branch.ts`; the count is the committed-code form of the signal, because the tool is dark and has no runtime events to read until the flag flip. The behavioural proof is a unit test in `push-branch-hardened.test.ts` that drives each refusal reason and asserts `reportSilentFallback` is called with `{ feature: "cc-push", op: "isolated-dir-refused", extra: { reason } }` and that the Error object is never passed. A separate op, not a `reason` on `approval-grant-refused`, was chosen on purpose: the latter would touch `grants.ts`, three anchored mutation rows and a pinned `toEqual` list for no gain.)

## Implementation Phases

TDD order (`cq-write-failing-tests-before`): each phase starts with its failing tests.

### Phase 1 - leaf modules and their tests (RED first)
1.1 Write `test/git-isolated-push-dir.test.ts` (creator refusals, shallow validation, config content, dispose) and `test/approval/workspace-head.test.ts` (reader) against stubs; confirm RED.
1.2 Implement `server/git-isolated-push-dir.ts`, `server/approval/workspace-head.ts`. GREEN.
1.3 `git-hardened-env.ts`: `IsolatedPushDir`, `buildIsolatedGitEnv`, delete `buildHardenedGitEnv`, rewrite header.

### Phase 2 - wire the push
2.1 Update `test/git-auth-hardened-env.test.ts` and `test/git-auth-hardened.test.ts` to the isolated option (RED), then `git-auth.ts` hardened branch (GREEN); legacy-form tests untouched and green.
2.2 Rewrite `test/push-branch-hardened.test.ts` (flow level) (RED), then `push-branch.ts` (GREEN).
2.3 Add `test/push-branch-isolated-real-git.test.ts`: the hostile-config vector suite (control vs isolated), shallow remote-ahead, alternate-only objects, alternates chain, temp-dir removal. Design (review round, mechanical): `pushBranch` hardcodes `https://github.com/...` and `GIT_ALLOW_PROTOCOL=https` blocks `file` in BOTH arms, so (a) the file-transport vectors (`insteadOf`, `pushInsteadOf`) drive the env builder / `gitWithInstallationAuth` directly against local bare remotes with a test-only `extra: { GIT_ALLOW_PROTOCOL: "https:file" }` (the `extra` argument is applied last, exactly like `git-auth-hardened.test.ts` does today); (b) the TLS vectors (`http.<url>.sslVerify`, `sslCAInfo`, a more specific `proxy`, `curloptResolve`, `extraHeader`) drive `gitWithInstallationAuth` against `https://127.0.0.1:<port>/x.git` with one `node:https` recording server per arm on port 0, a self-signed certificate generated by the `openssl` CLI in `beforeAll`, NO `SSL_CERT_FILE` trust, the server answering `401 WWW-Authenticate: Basic` so a git that reaches it sends its `Authorization` header: the control arm's evil server RECORDS the header (token reached the attacker host), the isolated arm's records nothing and the child fails on the TLS/resolve error. Per-vector coverage is kept on purpose (the brief says "per vector"); the review panel's suggestion to collapse the TLS arms to one is recorded as a taste row in `decision-challenges.md`. Register in `test/repo-wide-suites.ts` together with `test/git-isolated-push-dir.test.ts` and `test/approval/workspace-head.test.ts` if they import `../../../plugins/soleur/test/lib/git-fixture-env`; strip `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_<n>`, `GIT_CONFIG_VALUE_<n>` and `GIT_CONFIG_PARAMETERS` from `process.env` in `beforeEach` (restore after), as `git-auth-hardened.test.ts` does.

### Phase 3 - the gate
3.1 Extend `test/approval/gate-deps.test.ts` default-reader describe (commondir, `gitdir:` file, inherited `GIT_DIR`, spawn counter), RED then `gate.ts` wrapper GREEN.

### Phase 4 - mutation battery
4.1 `bash apps/web-platform/test/approval-guard1-mutation.test.sh --list` and `--check-anchors` before editing to record the baseline; after the code lands rewrite the rows the table below names, ratchet `FLOOR` entries and `MIN_MUTANTS`/`MIN_KILLED` to the new literal counts, rerun `--check-anchors`, and run a targeted `--only 'G1-HD|G1-X8|G1-X9|G1-GD2[2-4]|G1-ISO'`. The full 25-minute battery is CI's job.

| Row | Disposition |
|---|---|
| G1-X8 | anchor unchanged (call-site text kept) |
| G1-X9 | rewrite: `cat-file` block now uses `cwd: gitCwd`; keep the kill = "a sha that is not in the workspace repository" test |
| G1-HD1 | rewrite: `createIsolatedPushDir` call removed |
| G1-HD2 | rewrite: `? buildIsolatedGitEnv(hardened, authEnv)` -> `{ ...process.env, ...authEnv }` |
| G1-HD3, HD4, HD5, HD7, HD13, HD14 | unchanged (anchors and kills kept) |
| G1-HD8, HD9, HD10, HD16 | replace by rows on `git-isolated-push-dir.ts` (alternates refusal, symlinked object-store child, `realpath` equality, `.git` symlink) |
| G1-HD11 | anchor text kept if the `cat-file` call still ends `, timeout: HARDENED_SYNC_GIT_TIMEOUT_MS }`; re-verify with `--check-anchors` |
| G1-HD12 | rewrite: isolation guard before the token mint |
| G1-GD22, GD23 | rewrite against `workspace-head.ts` (reads the process cwd; untrimmed body) |
| G1-GD24 | anchor unchanged (the `COMMIT_SHA_RE` throw stays in `gate.ts`); its `equivalent=` justification text cites `git rev-parse HEAD` and is rewritten to cite the reader |
| G1-HD6, HD15 | deleted with the pins they anchored (`GIT_COMMON_DIR`, `GIT_OBJECT_DIRECTORY`); replaced by the exact-env-key-set assertion already in `git-auth-hardened-env.test.ts` |
| new G1-ISO1..ISO7 | matrix rows 2, 3, 6, 8, 9, 10 and the env `GIT_DIR` regression (row 1); the shallow-dropped mutant (row 7) is NOT given a battery row: the remote-ahead real-git test already reddens it and it is an availability failure |

### Phase 5 - ADR, handover, decision record
5.1 ADR-309 and handover edits as in `### ADR`; `cmp` the two item-9 blocks.
5.2 `bash scripts/markdown-lint.sh --repo-sweep` before committing markdown.

### Phase 6 - verification and ship
6.1 Targeted vitest only: the files named in `## Files to Edit` and `## Files to Create`, plus the suites that pin text or graph shape of the files this PR touches (research: `test/approval/decide-boundary.test.ts` (walks every file under `server/approval`, so the new `workspace-head.ts` joins its set; it may not reach `decide.ts`), `test/approval/runner-census.test.ts`, `test/git-data-ssh-dial-sweep.test.ts`, `test/git-data-ssh-connect-bound.test.ts` and `test/git-data-key-sweep.test.ts` (read `git-auth.ts` text; the hardened-branch edit must leave their two-ssh-sites and bound-options pins intact), `test/github-tools-push-grant.test.ts` (exact `toEqual` on the `pushBranch` argument, so the public `hardened?: true` option must not change shape), `test/cc-dispatcher-real-factory.test.ts`); `npx tsc --noEmit` in `apps/web-platform`. CI is the ship gate; the PR test plan records that the slow local `--affected` battery was not awaited.
6.2 Both leak-token greps (diff and log) print nothing before every push. Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR body `Ref #9601`, never `Closes`; title prefix `fix(approval):`.

## Files to Edit

- `apps/web-platform/server/push-branch.ts`
- `apps/web-platform/server/git-auth.ts` (hardened branch + option type only)
- `apps/web-platform/server/git-hardened-env.ts`
- `apps/web-platform/server/approval/gate.ts`
- `apps/web-platform/test/git-auth-hardened-env.test.ts`
- `apps/web-platform/test/git-auth-hardened.test.ts`
- `apps/web-platform/test/push-branch-hardened.test.ts`
- `apps/web-platform/test/approval/gate-deps.test.ts`
- `apps/web-platform/test/repo-wide-suites.ts`
- `apps/web-platform/test/approval-guard1-mutation.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md`
- `knowledge-base/project/specs/archive/20261029-164429-feat-hitl-approval-queue/flag-create-handover.md`

`server/github-tools.ts` is read-only context: it passes `hardened: true` to `pushBranch`, whose public option stays `hardened?: true`.

## Files to Create

- `apps/web-platform/server/git-isolated-push-dir.ts`
- `apps/web-platform/server/approval/workspace-head.ts`
- `apps/web-platform/test/git-isolated-push-dir.test.ts`
- `apps/web-platform/test/push-branch-isolated-real-git.test.ts`
- `apps/web-platform/test/approval/workspace-head.test.ts`
- `knowledge-base/project/specs/feat-one-shot-9601-adr309-9b-push-hardening/decision-challenges.md` (exists)
- `knowledge-base/project/specs/feat-one-shot-9601-adr309-9b-push-hardening/tasks.md`

Glob check: every path above was verified with `git ls-files` (edits) or confirmed absent (creates) at plan time.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200) searched for every planned file path and for `ADR-309`: no body names any of them.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Two CTO rulings of 2026-11-06 (the brief's three, and the four forks above, F1-F4 = Forks A-D in `decision-challenges.md`). Accepted with conditions that are folded into the design: realpath containment for the loose ref, reftable/symref-depth fail-closed, `objects/pack` and `objects/info` child checks, 64 KiB shallow cap, `objectformat=sha1`, no `git config` against the workspace, a regression test for `commondir`.

### Product/UX Gate

**Tier:** none (no user-facing surface; no new component, page or copy). **Decision:** n/a. **Pencil available:** N/A (no UI surface).

### CPO sign-off (single-user incident)

Ruled by CPO agent, 2026-11-06: sign-off YES to proceed to implementation - the change closes the 9b code limb only, protects the single-user token-diversion case, and touches no UI, copy, flag or production state. Conditions carried: (1) a normal `--depth 1` workspace must never be refused as `commit_unavailable` (the remote-ahead test and its negative control block merge); (2) the spent-approval failure text must say plainly that the approval was spent and nothing landed, never read as success, and the workspace checks that need no temp dir run first inside the handler (the approval itself is consumed earlier, by the gate; a setup failure after consume is a recorded known gap, availability only); (3) the behaviour change (a planted `.git/config` symlink no longer refuses) is stated in the ADR and tested. No public-claim guard is needed because nothing public is touched; every artifact keeps "cc sandbox can write `.git`" and "workspace-path unguessability" marked UNVERIFIED, no document calls the push "safe" or "hardened end-to-end", and ADR-309 item 9 is never recorded as discharged.

Legal/compliance: this PR edits no legal or public text and adds no security-posture claim (operator hold); the GDPR gate does not fire (no schema, migration, auth flow, API route or `.sql`; no new processing activity - the push already carries the same data to the same processor).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "push the approved commit from a server-created isolated trusted GIT_DIR (fresh temp bare repo with server-written config)" | Design 1, 4 | mapped |
| 2 | "with GIT_ALTERNATE_OBJECT_DIRECTORIES=<workspace>/.git/objects so the commit's objects are reachable, GIT_CONFIG_NOSYSTEM=1, GIT_CONFIG_GLOBAL=/dev/null" | Design 2 (`buildIsolatedGitEnv`) | mapped |
| 3 | "pushing <sha>:refs/heads/<branch> to the literal URL; never read the agent-writable .git/config; delete the temp dir in finally" | Design 4 | mapped |
| 4 | "Also harden gitHeadSha in apps/web-platform/server/approval/gate.ts ... or read HEAD without executing repo-config-driven git" | Design 5 | mapped |
| 5 | "git-auth.ts (hardened branch only; legacy runner argv/env byte-identical)" | Design 3 | mapped |
| 6 | "new tests beside test/git-auth-hardened-env.test.ts and test/push-branch-hardened.test.ts with synthesized hostile .git/config fixtures per vector" | Phase 2.3, Attack Surface table | mapped |
| 7 | "the ADR-309 9b bullet (rewrite in place ...; also the archived handover copy ...; record this PR as the closer)" | `### ADR` 1, 4 | mapped |
| 8 | "Add the CTO rulings as decision-challenges rows of class technical" | `decision-challenges.md` | mapped |
| 9 | "the plan must verify every vector claimed closed against the actual git behaviour with a hostile-config fixture, and verify that git honours GIT_ALTERNATE_OBJECT_DIRECTORIES + a fresh GIT_DIR for push of a commit whose objects live only in the alternate" | Research Insights E1-E5, Claims ledger, Phase 2.3 | mapped |
| 10 | "a new suite that reads outside apps/web-platform must be listed in test/repo-wide-suites.ts" | Phase 2.3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Shallow-boundary copy in the isolated dir | "verify that git honours GIT_ALTERNATE_OBJECT_DIRECTORIES + a fresh GIT_DIR for push" | asked (the verification found the shallow failure; fixing it is required for the ruled design to work on `--depth 1` workspaces) |
| Narrowed pre-flight (alternates chain, object-store children, path safety) | "closes by construction ... and the non-atomic .git pre-flight" | asked (the chain is what construction does not close, E5) |
| JS HEAD reader | "or read HEAD without executing repo-config-driven git" | asked (chosen over the git form because E4 shows the env pins fail) |
| Mutation-battery row rewrites and floors | "check hardening prose against what the code actually does" | inferred - justification: the battery is a CI-required suite whose rows are anchored on the text this PR rewrites; leaving them red blocks the merge |
| Sentry op `isolated-dir-refused` | "Likely files: ... push-branch.ts" | inferred - justification: `hr-observability-as-plan-quality-gate`; a refusal reason is the only in-product signal on the unmeasured sandbox-write limb |

### Split Assessment

- Subsystems touched: 3 - `apps/web-platform/server`, `apps/web-platform/test`, `knowledge-base`
- Planned files: 12 edits + 5 creates (17) | Estimated changed lines: ~700 (about 250 server, 350 tests, 100 docs/battery rows)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Functional (pre-merge)

- [ ] With `hardened: true` and a hostile `.git/config` per vector (insteadOf, pushInsteadOf, `http.<url>.proxy`/`sslVerify`/`sslCAInfo`/`extraHeader`, `curloptResolve`, `core.hooksPath`), the real-git suite shows the vector effective in the 9a-form control and inert in the isolated form (`push-branch-isolated-real-git.test.ts`).
- [ ] `git config --list --show-origin` run in the exact hardened child environment lists only `<iso>/config` and `command line` entries, with a hostile `$HOME/.gitconfig` and `$XDG_CONFIG_HOME/git/config` present.
- [ ] A commit whose objects live only in the workspace object store (loose, then after `git gc` packed-only) reaches a local bare remote with its full ancestry; remote `git fsck` exits 0; `<iso>/objects` holds no files afterwards.
- [ ] A `--depth 1` workspace with the remote branch ahead pushes successfully; the same scenario without the shallow copy fails (negative control inside the suite).
- [ ] Refused with the static `Workspace git directory is not a plain repository directory` text and NO git child spawned: symlinked `.git`, `.git` as a `gitdir:` file, missing `.git`, symlinked `objects`, symlinked `objects/pack`, symlinked fan-out dir, symlinked pack child, `objects/info/alternates`, `objects/info/http-alternates`, FIFO `shallow`, oversized `shallow`, non-hex `shallow` line, `:` in the workspace path; each symlink case targets a COMPLETE copy containing the approved commit.
- [ ] No longer refused (documented behaviour change, one table-driven test): symlinked or planted `.git/config`, `HEAD`, `hooks`, `index`, `refs`, `packed-refs`, `commondir`, `config.worktree`, `info/grafts`; the push succeeds and none of them is read.
- [ ] Hardened push with no `commitSha` or a 64-hex id is refused as `ApprovedCommitUnavailableError`; no `git config` child is spawned against the workspace in hardened mode; the legacy path still runs the three original git calls byte-identically.
- [ ] The isolated directory is removed after success AND after a push failure AND after a creator refusal (asserted by path non-existence).
- [ ] Every git child of a hardened push (counted via the `execFileSync`/`execFile` seams) has `GIT_DIR` = the isolated dir, `GIT_ALTERNATE_OBJECT_DIRECTORIES` = `<ws>/.git/objects`, an allowlist-only key set, and never `cwd` = the workspace.
- [ ] `readWorkspaceHeadSha` returns the workspace's own HEAD with a planted `commondir`, with `process.env.GIT_DIR` set to another repo, with a hostile config, for detached, symbolic, loose and packed-only refs; throws for a `.git` file, symlinked `HEAD`, symlinked `refs/heads`, a traversal ref name, a FIFO, reftable, a symref chain, a missing ref, and an oversized file; spawns no child (spawn-counter) in every case.
- [ ] `gate-deps.test.ts` default-reader tests stay green (workspace path binding, non-git workspace throws).
- [ ] Shallow and flow edge cases (SpecFlow round): the approved commit being the shallow boundary commit itself pushes; HEAD moved or reset after approval still pushes the bound sha (not HEAD); two concurrent pushes from one workspace get distinct directories, both disposed; injected `ENOSPC`/`EROFS` at each write step maps to `setup_failed` (plain static error, directory removed); a token-mint rejection after the directory exists removes it; a non-fast-forward to a divergent remote branch is rejected without `--force` and the relayed text contains no token and no temp path; a worktree-style `.git` file fails closed in both the gate reader and the creator; a throwing `dispose()` does not change the push result.
- [ ] `readWorkspaceHeadSha` also covers: unborn HEAD, CRLF and uppercase hex (refused), a packed-refs peeled (`^`) line, a loose ref shadowing a stale packed entry, `git gc --auto`-style packed-only `refs/heads/<branch>`, and a content test that the module imports only `node:fs`, `node:path` and `./canonical` (so `decide-boundary.test.ts` and the dependency-cruiser rules stay satisfied).
- [ ] `realpath(gitDir)` is never under the workspace (asserted), and the env key set of a hardened child is exactly allowlist + `GIT_HARDENING_ENV` keys + `GIT_DIR` + `GIT_ALTERNATE_OBJECT_DIRECTORIES` + `GIT_ALLOW_PROTOCOL` + the askpass wiring.
- [ ] The refusal-reporting unit test (each `reason` -> one `reportSilentFallback` with the closed enum, never the Error). The payload carries the enum only: no workspace path, no sha.
- [ ] With `GIT_DIR`, `GIT_COMMON_DIR`, `GIT_INDEX_FILE` and `GIT_WORK_TREE` set in `process.env`, the hardened child env contains none of them except `GIT_DIR` = the isolated directory (CTO G1 condition).
- [ ] Legacy-form tests (`git-auth-hardened-env`, `push-branch-hardened` legacy, `git-auth.test.ts`, `push-branch.test.ts`, `push-branch-pinned.test.ts`, `github-tools-push-grant.test.ts`, `cc-github-push.test.ts`) pass unchanged except for the hardened option's new shape.

### Mutation battery and registrations

- [ ] `bash apps/web-platform/test/approval-guard1-mutation.test.sh --check-anchors` exits 0; the targeted `--only` run over the rewritten rows reports every row killed or marked with its reason; floors equal the new literal counts.
- [ ] `test/repo-wide-containment.test.ts` is green (new suites that read outside the app are listed in `test/repo-wide-suites.ts`).
- [ ] `npx tsc --noEmit` clean in `apps/web-platform`; dependency-cruiser boundary and `decide-boundary.test.ts` green (the new leaves import no `./decide` and no client module).

### Documentation (pre-merge)

- [ ] ADR-309 item 9b rewritten in place and the PR recorded as closer; item 7 and item 11 carry the italic superseded pointers; the new dated addendum exists; the handover item-9 block is byte-identical to the ADR's (`cmp` exits 0).
- [ ] Every universal claim in the new ADR text and code comments names its falsifying command or test (Claims ledger).
- [ ] `bash scripts/markdown-lint.sh --repo-sweep` passes; `python3 scripts/lint-guard-contract.py` passes on this plan.
- [ ] `decision-challenges.md` has the three brief rulings plus Forks A-D, all class `technical` or `operator (...)`, in `Ruled by CTO agent, 2026-11-06:` shape.
- [ ] Before every push both token greps print nothing: `git diff origin/main...HEAD -U0 | grep '^+' | grep -E '\b112[0-9]{2}\b' | grep -v 11258` and `git log origin/main..HEAD --format=%B | grep -E '\b112[0-9]{2}\b' | grep -v 11258`.

### Post-merge (operator, not part of this PR)

None added by this PR. The flip evidence (live probe of whether the cc sandbox can write `<workspace>/.git`) and every flip item stay operator holds.

## Test Scenarios

1. Given a hostile `[url "..."] pushInsteadOf` in the workspace config, when the approved push runs hardened, then the remote that receives the ref is the literal URL's, not the rewrite target (control: the 9a form lands in the rewrite target).
2. Given a TLS server with a self-signed certificate and `http.<url>.sslVerify=false` in the workspace config, when pushing hardened, then git fails with the certificate error (control: passes the handshake).
3. Given `http.<more specific url>.proxy` set, then the isolated form never attempts the proxy.
4. Given `http.curloptResolve` mapping an unresolvable name to the local server, then isolated fails with `Could not resolve host`.
5. Given a `--depth 1` workspace and a remote that moved ahead, when pushing the approved commit, then it lands with the new commit on top of the remote history.
6. Given `.git/objects/info/alternates` pointing at a victim store holding commit V, when pushing hardened, then the push is refused and V is never packed.
7. Given a workspace path containing `:`, then the creator refuses `alternate_path_unsafe` and spawns nothing.
8. Given the gate reads HEAD while `.git/commondir` points at another repository and `process.env.GIT_DIR` is set, then the workspace's own HEAD is returned and no process is spawned.
9. Given `git config` against the workspace is attempted in hardened mode (mutant), then the no-config-write test fails.
10. Given a push failure after the isolated dir exists, then the directory is gone and the error text is the existing path-stripped `Git push failed: ...`.

## Claims ledger (every "closed" claim and the command that falsifies it)

| Claim | Falsifying check |
|---|---|
| The isolated child reads no workspace config | `git config --list --show-origin` in the exact child env: any `.git/config` of the workspace in the output falsifies it (test) |
| `url.*.insteadOf` / `pushInsteadOf` cannot divert the push | `git ls-remote --get-url <url>` and a file-transport push in control vs isolated (test) |
| `http.<url>.sslVerify`/`sslCAInfo`/`proxy`/`curloptResolve` cannot weaken the push | local TLS server arms (test); `git config --get-urlmatch http.sslVerify <url>` as a cheap cross-check |
| Pinning `GIT_COMMON_DIR` stops a `commondir` redirect | FALSE (E4); asserted false by the control arm of the gate test and recorded as superseded in the ADR |
| The gate read executes no git | spawn-counter over `child_process` in the reader tests |
| The temp dir never outlives the call (except process death, which leaks a directory with no secret in it) | path non-existence after success, push failure, token-mint failure, creator refusal, injected write failure |
| Legacy argv/env are byte-identical | the existing legacy-form tests, unchanged |
| The mutation rows still anchor | `--check-anchors` exit 0 |
| Nothing here discharges the flip | the ADR sentence; items 1-8 and 10-12 are listed unchanged in the addendum |

## Risks and Sharp Edges

- **Shallow regression is the highest functional risk.** The ruled design silently fails on `--depth 1` workspaces unless `shallow` is carried (E2). The remote-ahead test is mandatory and has a negative control.
- **Repository format:** the server-written config is `repositoryformatversion = 0`, no extensions (review cut the version-1 variant: the 40-hex rule already excludes sha256, and version 0 is the one every git accepts). Measured working on 2.56 (E1-E3 used it); the real-git suite runs on the CI image's git.
- **Temp dir location:** `os.tmpdir()` must be writable in the container; the askpass helper already falls back to `/tmp`, so it is. A failure surfaces as `setup_failed` after the approval was consumed (availability only).
- **CodeQL `js/file-system-race`:** the creator avoids check-then-open on the same path (Dirent types, `realpath` equality, `O_NOFOLLOW` + `fstat`). Do not "simplify" this back to `lstat` + `readFile`.
- **Mutation battery is CI-required and anchored on source text:** rewrite rows in the same commit as the code they anchor, never after.
- **Dropping the old refusals changes observable behaviour** (a planted `.git/config` symlink no longer refuses). That is intended and tested; the ADR says so.
- **Do not claim more than measured:** whether the cc sandbox can write `.git`, and workspace-path unguessability, stay UNVERIFIED in every artifact this PR touches.
- A plan whose `## User-Brand Impact` section is empty, contains only filler text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `single-user incident`.

## Non-Goals

No flag creation or flip; no production write; no migration; no live probe; no legal, marketing or public-doc wording; no
change to the legacy runner push; no change to `dsar-export-allowlist.ts`; no issue filed; the epic body is not edited; the
per-tenant UID/mount boundary is a separate item, not tracked by this slice.
