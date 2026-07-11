---
title: "A DSN/secret-shaped literal belongs in the gitleaks-allowlisted *.test.ts files, NOT a shared non-test helper — and CI gitleaks scans the whole diff RANGE, so a working-tree fix needs a history rewrite"
date: 2026-07-11
category: best-practices
tags: [gitleaks, secret-scan, allowlist, test-fixtures, history-rewrite, diff-range, rls-fuzz]
issue: 6307
---

# gitleaks: keep DSN literals in allowlisted test files, and remember it scans the whole diff range

## Problem

Extracting a shared test helper (`test/rls-fuzz/harness-fixture.ts`) out of three
`*.integration.test.ts` files, I moved the local disposable-Postgres DSN default into
the helper:

```ts
const DEFAULT_DSN = "postgres://<user>:<pass>@127.0.0.1:54322/postgres"; // real literal in source
```

(The real literal is the Supabase-CLI local default `postgres://<user>:<pass>@…` with
`<user>`=`<pass>`=`postgres`; it is redacted here so THIS learning file — which lives under
`knowledge-base/**/learnings/`, NOT in the gitleaks allowlist — does not itself trip the
rule. That is the very trap this note is about.)

CI's `gitleaks scan` failed: rule `database-url-with-password`, entropy 3.75. The exact
same literal lives in the three original test files and passes — because `.gitleaks.toml`
allowlists it via a **path pattern scoped to test files only**:

```
apps/web-platform/test/.*\.test\.(ts|tsx)$
```

`harness-fixture.ts` is a helper, **not** a `*.test.ts` file, so it fell outside the
allowlist. Two compounding traps:

1. **The literal is a non-secret** (the Supabase-CLI's well-known local default, user and
   password both `postgres`, host `127.0.0.1`) but is secret-*shaped*, so it trips the
   rule regardless.
2. **CI gitleaks scans the whole PR diff RANGE** (`--log-opts="--no-merges BASE..HEAD"`),
   not just the working tree. So after I removed the literal in a *new* commit, the scan
   STILL failed — it saw the literal in the earlier commit that *added* the helper. A
   working-tree fix is necessary but not sufficient.

## Solution

**Placement:** don't put a DSN/secret-shaped literal in a shared non-test helper. Keep it
in the allowlisted `*.test.ts` files (each already defines
`const DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "<local default>"`) and have them pass
it in — the helper's `connect(dsn: string)` takes a **required** arg (every caller already
passed `connect(DSN)`, so the helper's own default was dead code). The helper then holds
no literal and needs no allowlist widening — better than editing `.gitleaks.toml`, which
the repo intentionally makes hard to widen (`lint-fixture-content` re-scans independently).

**History:** because gitleaks scans the range, purge the literal from history. No `rebase -i`
in this env — soft-reset to the branch base and recommit the (now-clean) tree:

```
BASE=$(git merge-base origin/main HEAD)
git reset --soft "$BASE"    # keeps working tree + index, drops the offending commit
git commit -F <clean message>
git push --force-with-lease
```

(Fine for a squash-merge PR — the intermediate commits are collapsed anyway.) Verify
locally against the repo config + the exact range before pushing:
`gitleaks git -c .gitleaks.toml --log-opts="--no-merges origin/main..HEAD"`.

## Key Insight

Two independent facts, both easy to miss: (1) a gitleaks **path allowlist scoped to
`*.test.ts` does not cover sibling helper modules** in the same directory — extracting
shared code out of a test file can move a previously-allowlisted literal out of scope;
(2) the PR scan is **range-based, not tree-based**, so removing a secret in a later commit
does not clear a finding introduced by an earlier commit — the literal must leave *history*.
Same class as the api-key-in-git-history cleanup, but for a non-secret that only needs to
not *look* like one to the scanner: the cheapest fix is to never introduce the literal
outside the allowlisted path in the first place.

## Session Errors

1. **DSN literal placed in the shared helper `harness-fixture.ts`** (outside the
   `*.test.ts` allowlist) → CI gitleaks fail. Recovery: removed the literal (callers pass
   DSN), soft-reset + recommit to purge it from history, force-push. Prevention: this
   learning — keep secret-shaped literals in allowlisted test files, not extracted helpers.
