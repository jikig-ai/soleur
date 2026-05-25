# Helper-migration: drop `err` from `extra` when the helper already accepts it positionally

**Date:** 2026-05-25
**PR:** #4393 (closes #4390)
**Branch:** `feat-one-shot-4390-account-delete-sentry`

## Problem

Migrating 21 `log.error`/`log.warn` emit sites in `apps/web-platform/server/account-delete.ts` (GDPR Art. 17 cascade) to the canonical `reportSilentFallback` / `warnSilentFallback` helpers. Pre-PR shape:

```ts
log.error({ userId, err: anonAsErr }, "anonymise_action_sends failed — ...")
```

The naive migration preserves the `{userId, err}` structure inside `extra:` and ALSO passes the error positionally:

```ts
reportSilentFallback(anonAsErr, {
  feature: "account-delete",
  op: "anonymise-action-sends",
  extra: { userId, err: anonAsErr },  // <-- redundant: helper already has the error
  message: "anonymise_action_sends failed — ...",
})
```

The helper signature (`apps/web-platform/server/observability.ts:138`) is `(err: unknown, options: { feature, op?, extra?, message? }): void`. The first positional arg becomes `Sentry.captureException`'s first arg AND lands in pino's `{err, feature, op, ...extra}` payload at observability.ts:154. Spreading `extra` AFTER explicit `err` means `extra.err` (if present) silently overrides the explicit `err`. Same data either way in the if-error arm — but asymmetric with the catch arm where `extra: { userId }` correctly carries only the non-err context.

Multi-agent review caught the redundancy: `extra` should carry the same shape across both arms.

## Solution

In if-error arms, drop `err: anonXxxErr` from `extra`. Final shape (uniform across all 11 if-error arms + 10 catch arms = 21 emits):

```ts
// if-error arm
reportSilentFallback(anonAsErr, {
  feature: "account-delete",
  op: "anonymise-action-sends",
  extra: { userId },
  message: "anonymise_action_sends failed — aborting deletion to avoid FK-block",
});

// catch arm
reportSilentFallback(err, {
  feature: "account-delete",
  op: "anonymise-action-sends",
  extra: { userId },
  message: "anonymise_action_sends threw — aborting deletion to avoid FK-block",
});
```

The error reaches Sentry via `captureException(err, ...)`'s first arg and pino via the helper's structured emit; no second copy in `extra` is needed.

## Key Insight

**When migrating from pino's `log.error({a, b, err}, msg)` shape to a helper with `(err, {extra})`, `extra` carries only the non-err context. The helper owns error transport — duplicating into `extra` is at best gratuitous, at worst silently overrides the positional `err` if the spread order changes.**

This is a generalization of the 2026-05-13 helper-migration learning (`message:` carry-forward). That learning covered the message string; this one covers the `extra:` payload shape.

Look for this pattern whenever you grep for `extra: { userId, err:` after a helper migration — every match is a candidate dedup.

## Tags

category: best-practices
module: observability

## Session Errors

- **AC2 grep counted 22 instead of 21.** Plan's `grep -cE "reportSilentFallback|warnSilentFallback"` matched the import line at L6, so the expected 21 didn't match. Recovery: tightened to `grep -cE "^\s*(report|warn)SilentFallback\("` (call-site-anchored). **Prevention:** when an AC counts a helper, anchor the grep to the call-site indentation, not the bare name — the import line is a structural false-positive class for any helper-migration AC.

- **TS2339 `Property 'message' does not exist on type 'never'`.** Initial migration wrapped errors as `anonAsErr instanceof Error ? anonAsErr : new Error(String(anonAsErr.message ?? anonAsErr))`. PostgrestError extends Error → the else branch narrows to `never` → `.message` is unreachable. Recovery: pass raw error to the helper (signature is `err: unknown`). **Prevention:** when migrating to a helper accepting `unknown`, never wrap with `instanceof Error` ternary — the helper's internal `if (err instanceof Error)` branch handles both cases.

- **Bash `&&` chain broke at first `grep -c` returning 0.** `grep -c` exits 1 when there are no matches even though it prints `0`. The chain `grep -c A && grep -c B && ...` stopped after the first 0-match. Recovery: used `|| true` per command and separated with newlines. **Prevention:** when chaining AC greps that may legitimately match 0, suffix each with `|| true`.

- **`next lint --file <path>` hit interactive prompt.** Web-platform has `scripts.lint = "next lint"` but no `.eslintrc*` / `eslint.config.*` exists; `next lint` prompted for ESLint config setup. Recovery: skipped lint (the plan's AC10 was aspirational; typecheck is the actual gate). **Prevention:** plan-time should verify the lint command actually runs against the touched files before listing it as an AC. Run the lint script once on a known-clean file; if it prompts, the AC is bogus.

- **`extra: { userId, err: ... }` redundancy not caught at plan time.** The plan + spec specified the `extra` shape verbatim, and /work implemented it verbatim. Multi-agent review at PR time surfaced the redundancy. **Prevention:** plan-time should review helper-migration `extra:` payloads against the helper's first-positional-arg contract — if the error reaches the helper twice (positionally + in extra), drop the second copy.
