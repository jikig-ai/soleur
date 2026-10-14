---
title: A source census that checks the argument's name (not its binding) and a closed file list both let guarded egress through
date: 2026-09-29
category: security-issues
tags: [guards, mutation-testing, review, ssrf, codeql, census, egress]
issue: 8857
pr: 9218
---

# Learning: a source census that checks the argument's name (not its binding) and a closed file list both let guarded egress through

## Problem

PR #9218 (issue #8857, CodeQL `js/request-forgery` alert #234) shipped an egress guard pinning
every credential-bearing GitHub API `fetch` to `https://api.github.com`, plus a source-reading
"egress census" test meant to keep future call sites inside the guard. The author's census passed
the full mutation battery — and the 12-seat review still found it narrower than the property it
named, in five compounding ways:

- **Name, not binding.** `/^url[,\s)]/` on the fetch head verified the first argument was *spelled*
  `url`, not that `url` had been asserted. Deleting `url = githubEgressUrl(url, …)` at the
  `githubFetch` chokepoint left the checked text identical — the suite stayed green while the SSRF
  class reopened (test-design P1; security-sentinel verified the deletion ships green).
- **`startsWith` prefix checks admit suffix evasion.** `fetch` on the literal + suffix (`` `https://api.github.com/app` + x ``)
  and `fetch(assertGithubApiAbsoluteUrl(url) + x)` both satisfy a prefix check while carrying
  unguarded output — and `/^url[,\s)]/` itself passed `url + x` because `\s` covered the space
  before `+`.
- **Closed-world file list.** The census enumerated only the two files its author remembered; two
  real installation-token sinks (`release-notes.ts`, `cron-weekly-release-digest.ts`) sat outside
  both guard and census, and any NEW credential-bearing file was structurally invisible.
- **`await`-scoped site regex.** `return fetch(`, `void fetch(`, `.then`-chained, and member-access
  `globalThis.fetch(` sites were all unenumerated.
- **Mint-ordering asymmetry.** Wrappers asserted before `generateInstallationToken`, but
  `postRepoCreate`'s plumbed `url` param minted first — the stated invariant "never mint a
  credential for a request the guard refuses" was only half true.

## Solution

- Provenance, not name: for `fetch(url…` sites the census requires
  `githubEgressUrl(url`/`assertGithubApiAbsoluteUrl(url` to appear textually BEFORE the site in the
  same file — deleting the assert is now a census RED.
- Terminator rules everywhere: the first argument must BE the guarded value — `,\` or `)` may
  follow it (whitespace-then-terminator only); `+ suffix` fails on `url`, guard-call, and named
  literal forms alike.
- Open-world membership sweep: any file under `server/`/`app/` containing `fetch(` AND a GitHub
  credential signal (origin literal, `GITHUB_API`, a mint symbol, a guard export) must be in
  `GUARDED_FILES` or a named bucket (user-OAuth, user-PAT, unauthenticated, mint-but-other-lane) —
  new members cannot slip through uncategorized.
- `/(?<!\w)fetch\s*\(` counts member-access and non-awaited sites; `//`/`/* */` comments are
  excluded, residual lexical limits (aliasing, shadowing) are documented as acknowledged gaps.
- One shared `reportEgressRefusal`/`githubEgressUrl` in `github-url.ts` gives every assert site
  the same pino+Sentry `url-refused` signal with a single `extra.target` key; `postRepoCreate`
  pre-asserts its plumbed `url` before the mint.
- Battery extended to 10 mutations on the census axes themselves (assert-deletion, suffix evasion,
  member-access, new-file, octokit non-literal) — every row RED.

## Key Insight

When the deliverable IS a guard, the census tripwire is part of the guarded surface: a census that
checks what the author *wrote* (identifier names, remembered file lists, `await`-prefixed sites)
pins exactly the shape that was written and nothing more. The durable version binds the identifier
to its guard call, terminates the accepted shapes, and enumerates membership in the open world —
then mutates the census's own recognizers, not just the SUT. The single most valuable seat on a
guard-shaped PR is the structural enumeration ("every path by which a credential can reach a sink"),
not another adversarial sample of the shapes you already remembered to check.
