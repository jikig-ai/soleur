// Per-(userId, conversationId) Bash command-prefix batched-approval
// cache (#2921). The cc-soleur-go modal-cliff: a /soleur:work session
// fires `git status`/`git diff`/`bun test`/`npx tsc` repeatedly, each
// behind its own user gate. The user clicks "Approve all <prefix>" once
// and subsequent commands matching the prefix auto-approve for the rest
// of the conversation (TTL-bounded).
//
// Threat model + safety:
//   - The blocklist (`BLOCKED_BASH_PATTERNS` in permission-callback.ts)
//     STILL applies to every Bash command. The cache check happens AFTER
//     the blocklist, so curl/wget/nc/sh -c/eval/base64 -d/sudo cannot be
//     batched.
//   - Composite-key isolation: cross-(userId,conversationId) leaks are
//     impossible — the cache is keyed `${userId}:${conversationId}`.
//   - TTL-bounded: 60-minute idle expiry. WS reconnect / explicit revoke
//     also clear the cache (caller invokes `cache.revoke()` from the
//     conversation cleanup path).
//
// Process-local: in-memory Map. Single Next.js worker per container at
// current scale (matches `withWorkspacePermissionLock` blast radius
// boundary).

export const BASH_APPROVAL_CACHE_TTL_MS = 60 * 60 * 1000; // 60 minutes

interface CacheEntry {
  prefix: string;
  expiresAt: number;
}

// Map keyed on `${userId}:${conversationId}`. Each key tracks ONE
// granted prefix at a time — granting a new prefix replaces the prior
// (rare in practice; the user grants once per session phase).
const _bashApprovalCache = new Map<string, CacheEntry>();

export interface BashApprovalCache {
  /** Returns true iff the command's derived prefix matches a non-expired grant. */
  allow(command: string): boolean;
  /** Grant `prefix` for the next 60 minutes. */
  grant(prefix: string): void;
  /** Clear all grants for this (user, conversation). */
  revoke(): void;
}

/**
 * Returns a stable per-(userId, conversationId) cache handle. Multiple
 * calls with the same args return DIFFERENT handles but share state via
 * `_bashApprovalCache`.
 */
export function getBashApprovalCache(
  userId: string,
  conversationId: string,
): BashApprovalCache {
  const key = `${userId}:${conversationId}`;
  return {
    allow(command: string) {
      const entry = _bashApprovalCache.get(key);
      if (!entry) return false;
      if (Date.now() >= entry.expiresAt) {
        // Lazy-expire on read.
        _bashApprovalCache.delete(key);
        return false;
      }
      const cmdPrefix = deriveBashCommandPrefix(command);
      // Word-boundary equality on derived prefix — `git status` grants
      // `git status -s` but NOT `git statuses`. The derive helper takes
      // care of multi-token prefixes (e.g. `git status`, `npm run lint`).
      return cmdPrefix === entry.prefix;
    },
    grant(prefix: string) {
      _bashApprovalCache.set(key, {
        prefix,
        expiresAt: Date.now() + BASH_APPROVAL_CACHE_TTL_MS,
      });
    },
    revoke() {
      _bashApprovalCache.delete(key);
    },
  };
}

/**
 * Derive a conservative command prefix for batched approval. Favors
 * narrow over wide:
 *   - `git <verb>` (2 tokens) — `git status`, `git diff`, `git push`
 *     (push stays narrow — read-only verbs and write verbs do NOT share
 *     a prefix)
 *   - `npm run <script>` (3 tokens), `npx <tool>` (2 tokens),
 *     `bun <verb>` (2 tokens), `bun run <script>` (3 tokens)
 *   - Otherwise: first token only.
 *
 * The blocklist (`BLOCKED_BASH_PATTERNS` in permission-callback.ts) is
 * applied BEFORE this helper runs — `curl`/`wget`/etc. never reach the
 * cache.
 */
export function deriveBashCommandPrefix(command: string): string {
  const trimmed = command.trim();
  if (trimmed.length === 0) return "";
  const tokens = trimmed.split(/\s+/);
  const head = tokens[0];

  if (head === "git" && tokens.length >= 2) {
    return `git ${tokens[1]}`;
  }
  if (head === "npm" && tokens[1] === "run" && tokens.length >= 3) {
    return `npm run ${tokens[2]}`;
  }
  if (head === "bun" && tokens[1] === "run" && tokens.length >= 3) {
    return `bun run ${tokens[2]}`;
  }
  if (head === "bun" && tokens.length >= 2) {
    return `bun ${tokens[1]}`;
  }
  if (head === "npx" && tokens.length >= 2) {
    return `npx ${tokens[1]}`;
  }

  return head;
}

/** Test-only: drain the global cache. Do NOT call from production code. */
export function _resetBashApprovalCacheForTests(): void {
  _bashApprovalCache.clear();
}
