---
title: Adding credential parsing before a mocked SDK constructor breaks every test that stubs a bogus credential
date: 2026-05-29
category: test-failures
tags: [testing, vitest, crypto, mocking, blast-radius, github-app]
modules: [apps/web-platform/server/github]
related_prs: [4569]
related_issues: []
---

# Learning: credential parsing before a mocked SDK constructor breaks stub-key fixtures

## Problem

Fixing the `cron-oauth-probe` "A JSON web token could not be decoded" error
required canonicalizing the GitHub App private key with
`crypto.createPrivateKey(pem).export(...)` BEFORE constructing `new App()`
(`@octokit/app`). Many unit tests mock `@octokit/app` and set a *placeholder*
private key in `process.env.GITHUB_APP_PRIVATE_KEY` (e.g.
`"-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----"`).

Mocking the `App` constructor used to make the key value irrelevant — the bogus
string never got parsed. After the fix, the real `createPrivateKey()` runs
*before* the mock, so every such test threw `ERR_OSSL_UNSUPPORTED` at
normalization. This surfaced **twice**: first in `probe-octokit-retry.test.ts`
(work phase), then again in `app-client.test.ts` (review phase, after a P1 fix
extended normalization to a third call site). Same root cause, two separate
test files, discovered ~30 min apart.

## Solution

Replace bogus placeholder keys with a **synthesized** real keypair generated
per-run (honours `cq-test-fixtures-synthesized-only` — never a real or
real-shaped production key):

```ts
import { generateKeyPairSync } from "crypto";
process.env.GITHUB_APP_PRIVATE_KEY = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "spki", format: "pem" },
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
}).privateKey as string;
```

The mock still intercepts `App`; the key just has to survive the new real parse
that runs before the mock.

## Key Insight

When you introduce real parsing/validation of a credential (or any input) that
runs **before** a mocked constructor/boundary, the mock no longer shields tests
from malformed fixtures. **Before committing such a change, sweep every test
that stubs that input** — not just the test for the file you edited:

```bash
git grep -lE 'GITHUB_APP_PRIVATE_KEY' -- 'test/**'   # adapt the env/fixture name
```

For each hit, decide whether the test exercises the REAL factory (mock only the
downstream SDK) or mocks the factory wholesale (fixture irrelevant). Only the
former need a real synthesized fixture. Tests that `vi.mock("@/server/.../the-factory")`
never run the parser and need no change.

A second, orthogonal lesson from the same PR: the plan's blast-radius sweep
enumerated the cron callers of the shared factory but missed the founder-facing
`createGitHubAppClient` in `app-client.ts`, which reads the *same* env key via
the *same* vulnerable `@octokit/app` path. Two review agents independently
caught it. When fixing a **shared-input** bug, `git grep` every site that reads
the input or calls the vulnerable primitive (`git grep -nE 'new App\(' apps/web-platform/server`),
not just the file the Sentry error happened to point at. This is the
`hr-type-widening-cross-consumer-grep` spirit applied to a shared credential.

## Session Errors

1. **`git grep --include='*.ts'` flag-ordering error** ("option '--include=*.ts'
   must come before non-option arguments"). Recovery: use the pathspec form
   `git grep -nE 'pattern' -- '*.ts'`. Prevention: `git grep` takes pathspecs
   after `--`, not `--include` (that's plain `grep`).
2. **`replace_all` matched only 1 of 2 `privateKey: readEnv(...)` sites** — the
   two lines had different indentation (6 vs 4 spaces) so the exact-string match
   only hit one. Recovery: a second targeted Edit on the 4-space site.
   Prevention: after a `replace_all` on a short line, re-grep the file to
   confirm zero un-converted occurrences remain (already in work skill's
   "Incomplete replace_all" pitfall — this is a fresh confirmation).
3. **`probe-octokit-retry.test.ts` 9 failures** after adding normalization
   (bogus fake key now parsed). Recovery + Prevention: see Key Insight above.
4. **`app-client.test.ts` 9 failures** — same root cause as #3, recurred in the
   review phase after the P1 extraction widened normalization to a third site.
   Recovery + Prevention: the up-front fixture sweep in Key Insight would have
   caught both in one pass.
5. **`tsc` exit code masked by `| tail`** — `./node_modules/.bin/tsc --noEmit | tail`
   reports `tail`'s exit (0), hiding a real tsc failure. Recovery: re-ran as
   `tsc --noEmit > /tmp/tsc.log 2>&1; echo $?`. Prevention: already documented
   in work skill (pipefail not inherited); redirect-then-check for load-bearing
   exit codes.
6. **semgrep-sast subagent first scan "Invalid scanning root"** from a `cd` to
   the bare-repo path. Recovery: subagent retried with absolute worktree paths.
   Prevention: in a worktree, pass MCP/scanner roots as absolute worktree paths
   (already covered by `hr-mcp-tools-playwright-etc-resolve-paths`).
