import { hashUserId } from "@/server/observability";

/**
 * Pseudonymisation primitives for `userId` emissions.
 *
 * Single source of truth for renaming `userId` → `userIdHash` across pino
 * (`logger.ts:formatters.log`) and the observability helper (`observability.ts:hashExtraUserId`).
 * Architectural contract documented in
 * `knowledge-base/engineering/architecture/decisions/ADR-028-rename-at-boundary-userid-pseudonymisation.md`.
 *
 * Boundary invariants (do NOT widen without an explicit decision):
 * - Top-level only. Nested `{extra: {userId: "x"}}` shapes are NOT rewritten.
 *   This matches the 11 known direct call sites (verified at plan time);
 *   widening to nested requires a test fixture flip and ADR update.
 * - Null/undefined values resolve to the `"pepper_unset_null"` sentinel —
 *   mirrors `observability.ts:hashExtraUserId` (L48-55) so the empty-string
 *   collision class doesn't occur.
 * - Missing pepper resolves to the `"pepper_unset"` sentinel via the
 *   `hashUserId` primitive — fail-closed, boot-warning surfaced.
 */

/**
 * Hash a single `userId` value (or yield a sentinel for null/undefined).
 * Used as the value-level primitive by the recursive walker and by any
 * other site that needs to compute `userIdHash` without re-introducing
 * its own crypto import.
 */
export function hashUserIdValue(rawValue: unknown): string {
  if (rawValue == null) return "pepper_unset_null";
  return hashUserId(String(rawValue));
}

/**
 * Rename a top-level `userId` (or `user_id`) key on `obj` to `userIdHash`,
 * computing the hash via `hashUserIdValue`. Returns the original `obj`
 * unchanged when no `userId`/`user_id` key is present. Defensive: if both
 * `userIdHash` AND `userId` are present, keep `userIdHash` and drop `userId`
 * (prevents double-hash from re-application across re-entry).
 *
 * **Top-level only.** This walker does NOT recurse into nested objects.
 * If a future caller needs `extra.userId` rewriting, widen with intent +
 * test + ADR update — silent recursion is forbidden.
 */
export function renameUserIdToHash(
  obj: Record<string, unknown>,
): Record<string, unknown> {
  const hasUserId = "userId" in obj;
  const hasUserIdSnake = "user_id" in obj;
  const hasUserIdHash = "userIdHash" in obj;

  // Defensive: both userId and userIdHash present → keep userIdHash, drop userId.
  if (hasUserIdHash && (hasUserId || hasUserIdSnake)) {
    const { userId: _drop1, user_id: _drop2, ...rest } = obj as {
      userId?: unknown;
      user_id?: unknown;
    } & Record<string, unknown>;
    return rest;
  }

  if (!hasUserId && !hasUserIdSnake) return obj;

  const sourceKey = hasUserId ? "userId" : "user_id";
  const { [sourceKey]: rawValue, ...rest } = obj as {
    [k: string]: unknown;
  };
  return { ...rest, userIdHash: hashUserIdValue(rawValue) };
}
