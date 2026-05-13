// Sentry scrub helpers for `beforeSend` and `beforeBreadcrumb`.
//
// Sentry events nest sensitive data under request.headers, contexts, extra,
// tags, and breadcrumb.data. The recursive walk below replaces values whose
// key matches a case-insensitive sensitive set imported from
// `./sensitive-keys` (single source of truth shared with the pino redact
// paths in `./logger`).
//
// Cycle and shared-DAG correctness: a `Map<object, scrubbed>` memoizes the
// scrubbed copy on first visit and returns it on every subsequent visit.
// The prior WeakSet implementation returned the original (un-scrubbed)
// value on revisit, leaking credentials nested under shared sub-objects
// (e.g., a single `error.cause` chain referenced from multiple breadcrumbs).
// See PR #3240 review.
//
// userId rename special-case (#3710 PR-B deliverable 3): top-level and nested
// `userId` / `user_id` keys (case-insensitive) are renamed to `userIdHash`
// via the shared `hashUserIdValue` primitive. This is the structural
// backstop for direct `Sentry.captureException({extra: {userId}})` sites
// that bypass the centralised helpers (e.g., `server/ws-handler.ts`,
// `server/index.ts:120` startup capture). ADR-029 (rename-at-boundary).
// The rename wins over `SENSITIVE_LOWER.has()` so a future addition of
// `userId` to `SENSITIVE_KEY_NAMES` does not bury the pseudonymous
// identifier under `[Redacted]`.

import { SENSITIVE_LOWER, SENSITIVE_KEY_NAMES } from "./sensitive-keys";
import { hashUserIdValue } from "./userid-pseudonymize";

// Canonical inventory of helper-migration sites bound to `Sentry.setUser` via
// `Sentry.withIsolationScope`. Single source of truth for the Article 30
// register PA8 §(c)(i) symmetric-coverage claim. Update this list whenever a
// new authenticated emit site adopts the helper+isolation wrap; the legal
// disclosure references this file path (not a PR number that ages out).
//
// HOC binding (4 routes inherit setUser via `server/with-user-rate-limit.ts`):
//   - app/api/conversations/route.ts          (per `withUserRateLimit`)
//   - app/api/kb/search/route.ts              (per `withUserRateLimit`)
//   - app/api/kb/tree/route.ts                (per `withUserRateLimit`)
//   - app/api/chat/thread-info/route.ts       (per `withUserRateLimit`)
//
// Inline helper-migration sites (each wraps reportSilentFallback in
// Sentry.withIsolationScope + setUser({id: hashUserIdValue(userId)})):
//   - app/(auth)/callback/route.ts            (auth-callback / user-upsert)
//   - app/(auth)/callback/route.ts            (auth-callback / workspace-provisioning)
//   - app/api/accept-terms/route.ts           (accept-terms / record — DB error)
//   - app/api/accept-terms/route.ts           (accept-terms / record — user row missing)
//   - app/api/auth/github-resolve/callback/route.ts (github-resolve / store-username)
//   - app/api/repo/setup/route.ts             (repo-setup / clone)
//   - app/api/services/route.ts               (services / store)
//   - app/api/services/route.ts               (services / list)
//   - app/api/services/route.ts               (services / delete)
//   - app/api/webhooks/stripe/route.ts        (stripe-webhook / checkout.session.completed)
//   - app/api/workspace/route.ts              (workspace / provisioning)
//
// Sites outside this inventory (e.g., server/ws-handler.ts, server/index.ts:120,
// app/api/attachments/presign/route.ts, app/api/keys/route.ts,
// app/api/checkout/route.ts, app/api/billing/portal/route.ts,
// app/api/repo/create/route.ts, app/api/repo/setup/route.ts:126/175/194)
// are covered by the rename special-case below as the structural backstop —
// they emit raw `userId` in extras which is rewritten to `userIdHash` at the
// scrub boundary.

const REDACTED = "[Redacted]";

// Re-export under the legacy name so existing test surface keeps stable.
// `SENSITIVE_KEY_NAMES` is the canonical export from `./sensitive-keys`.
export const SENTRY_SENSITIVE_KEYS = SENSITIVE_KEY_NAMES;

function scrubRecursive(
  value: unknown,
  memo: Map<object, unknown>,
): unknown {
  if (value === null || typeof value !== "object") return value;
  const obj = value as object;

  const cached = memo.get(obj);
  if (cached !== undefined) return cached;

  if (Array.isArray(value)) {
    const out: unknown[] = [];
    memo.set(obj, out);
    for (const v of value) out.push(scrubRecursive(v, memo));
    return out;
  }

  const out: Record<string, unknown> = {};
  memo.set(obj, out);

  // Pre-scan for the rename special-case so defensive precedence wins:
  // when both `userId` (or `user_id`) and `userIdHash` are present, the
  // caller-supplied `userIdHash` is preserved verbatim and the raw key is
  // dropped — prevents re-hashing an already-pseudonymous value across
  // re-entries (mirrors `renameUserIdToHash` defensive branch).
  // `userIdHash` is the ADR-029 §I8 reserved emit-key.
  let hasUserIdHashPreset = false;
  for (const k of Object.keys(value as Record<string, unknown>)) {
    if (k === "userIdHash") {
      hasUserIdHashPreset = true;
      break;
    }
  }

  let renamedHashWritten = false;
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    const keyLower = k.toLowerCase();

    // userId / user_id rename special-case — wins over SENSITIVE_LOWER.has().
    if (keyLower === "userid" || keyLower === "user_id") {
      if (hasUserIdHashPreset) {
        // Defensive precedence — keep preset, drop raw.
        continue;
      }
      if (!renamedHashWritten) {
        out["userIdHash"] = hashUserIdValue(v);
        renamedHashWritten = true;
      }
      continue;
    }

    if (SENSITIVE_LOWER.has(keyLower)) {
      out[k] = REDACTED;
    } else {
      out[k] = scrubRecursive(v, memo);
    }
  }
  return out;
}

export function scrubSentryEvent<T>(event: T): T {
  return scrubRecursive(event, new Map()) as T;
}

export function scrubSentryBreadcrumb<T>(breadcrumb: T): T {
  return scrubRecursive(breadcrumb, new Map()) as T;
}
