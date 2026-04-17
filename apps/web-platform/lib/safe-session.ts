/**
 * Thin wrapper around `window.sessionStorage` that swallows
 * QuotaExceeded/SecurityError/DOMException (incognito quirks) and is SSR-safe.
 *
 * Contract:
 *   safeSession(key)            → read:  returns string | null
 *   safeSession(key, "value")   → write: returns the intended value
 *   safeSession(key, null)      → clear (removeItem): returns null
 *
 * On the server (no `window`), reads return `null` and writes are no-ops
 * but still return the intended value so callers can branch without nulls.
 *
 * Introduced to replace 8 scattered try/catch sessionStorage blocks across
 * `chat-input.tsx` and `kb/layout.tsx` (issue #2387 task 7H).
 */
export function safeSession(
  key: string,
  value?: string | null,
): string | null {
  if (typeof window === "undefined") {
    // SSR: reads are null; writes return the intended value without
    // touching storage so callers don't have to branch on SSR.
    if (value === undefined) return null;
    return value;
  }
  try {
    if (value === undefined) {
      return window.sessionStorage.getItem(key);
    }
    if (value === null) {
      window.sessionStorage.removeItem(key);
      return null;
    }
    window.sessionStorage.setItem(key, value);
    return value;
  } catch {
    // Storage quota exceeded, SecurityError in sandboxed iframe, private
    // browsing restrictions — callers must not receive a throw.
    if (value === undefined) return null;
    return value;
  }
}
