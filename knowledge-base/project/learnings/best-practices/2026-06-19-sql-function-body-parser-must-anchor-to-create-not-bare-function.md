---
title: "A migration-function-body parser keyed on `FUNCTION public.<name>` silently resolves the wrong function (inert drift guard)"
date: 2026-06-19
category: best-practices
module: test-guards
tags: [drift-guard, sql-parsing, regex, vacuous-test, tenant-isolation]
issue: 5582
pr: 5583
---

## Problem

A new always-on drift guard (`test/server/teardown-anonymise-parity.test.ts`, #5582) derives each anonymise RPC's FK `ON DELETE` class by reading the RPC's function body from its defining migration and extracting the `UPDATE/DELETE FROM <table>` targets. The body extractor matched the function with:

```js
const sigRe = new RegExp(`function\\s+public\\.${rpc}\\b`, "gi");
```

This matches **every** `… FUNCTION public.<rpc>` token in the migration, not just the `CREATE` — including the `REVOKE ALL ON FUNCTION …` and `GRANT EXECUTE ON FUNCTION …` lines that follow every SECURITY DEFINER RPC. The loop kept the **last** match (`lastBody = …`), and the REVOKE/GRANT matches sit *after* the `CREATE`, so from their offset the next `AS $$…$$` block found is the **next function's** body.

Concretely: `anonymise_workspace_activity` (mig 076) is followed by `set_conversation_visibility` in the same file. The guard resolved `anonymise_workspace_activity` to `conversations` (which `set_conversation_visibility` UPDATEs) instead of `workspace_activity`. Because `conversations.user_id` is `ON DELETE CASCADE` (not RESTRICT), the FATALITY assertion — "every `set-null`-labeled RPC is genuinely non-RESTRICT" — **passed for the wrong reason**. The guard was *inert* for the exact RPC it was meant to validate.

The bug was invisible: all 4 guard tests were green, and a mutation test on a *different* RPC (mislabel `anonymise_email_triage_items`) correctly went red, so the guard *looked* non-vacuous.

## Solution

1. **Anchor the signature regex to the definition only:**

```js
const sigRe = new RegExp(
  `create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.${rpc}\\b`,
  "gi",
);
```

   `REVOKE`/`GRANT`/`COMMENT ON FUNCTION` no longer match, so the only hit is the real `CREATE`, and the `$$` body pairing resolves the correct function.

2. **Convert silent-skip into fail-loud.** The FATALITY test previously *skipped* any RPC whose FK class couldn't be resolved (`classes.size === 0`) — which is exactly the inert state. Changed to a hard failure for any `set-null`-labeled RPC that resolves to zero FK tables, so the guard can never silently go inert again:

```js
if (classes.size === 0) { unresolvable.push(entry.rpc); continue; }
expect(unresolvable, "FATALITY verification is inert for these — fix resolver or label").toEqual([]);
```

3. Same class of over-broad match in the production-set extractor: `/"(anonymise_[a-z_]+)"/g` matched RPC names inside error/log-message strings. Anchored to the call shape `/\.rpc\(\s*"(anonymise_[a-z_]+)"/g`.

## Key Insight

When a test/guard parses SQL out of migration files, **a bare `FUNCTION public.<name>` match is not specific to the definition** — `REVOKE`/`GRANT`/`COMMENT ON FUNCTION` carry the same token, and "last match wins" over a slice-to-EOF window silently bridges into the *next* function's dollar-quoted body. The failure mode is the worst kind: the guard stays green by resolving an unrelated table that happens to satisfy the assertion. Two defenses, both cheap:

- **Anchor to `CREATE [OR REPLACE] FUNCTION`**, never bare `FUNCTION`.
- **Fail loud on "couldn't resolve"** instead of skipping — an unverifiable guard assertion must be a red test, not a no-op. A guard that can silently degrade to "verified nothing" is indistinguishable from a passing guard until the regression it was built to catch ships.

Generalizes beyond SQL: any source-parsing guard that maps name→body must anchor on the *definition* keyword and treat an empty resolution as failure, not as "nothing to check."

## How it was caught

Multi-agent review: `data-integrity-guardian` and `code-quality-analyst` independently identified the misresolution; `test-design-reviewer` replicated `buildFkClassMap` but not the `findFunctionBody` REVOKE/GRANT bug and reported it "sound" — the contradiction was resolved empirically by reading mig 076 and confirming the REVOKE/GRANT lines at 124/126 precede `set_conversation_visibility` at 134. Cross-reconciliation (2 orthogonal agents concurring vs 1 dissent, verified by reading source) was the deciding step.

## Session Errors

1. **`gh issue create` denied for missing `--milestone`** (filing follow-up #5585). Recovery: added `--milestone "Post-MVP / Later"`. Prevention: already hook-enforced (`guardrails:require-milestone`); default operational issues to `Post-MVP / Later`. No new enforcement needed.
2. **Self-introduced inert drift-guard** (the subject of this learning). Recovery: anchor to `CREATE FUNCTION` + fail-loud on unresolvable. Prevention: this learning; the fail-loud assertion is the durable guard.
3. **First drift-guard iteration grepped the whole migration file** for `UPDATE` targets (picked up `ON`/`OR`/unrelated tables) → resolved `audit_github_token_use` to mixed classes. Recovery: scoped extraction to the function body. Same root cause as #2; fixed together.
4. **`sleep 45` Bash blocked** (harness requires Monitor/background for waits). One-off; used background task + log grep instead.
