// Egress guard for GitHub API request URLs (CodeQL js/request-forgery,
// alert #234 / issue #8857).
//
// The wrappers in server/github-api.ts and the githubFetch chokepoint in
// server/github-app.ts attach a GitHub App credential (installation token or
// App JWT) to every request. The URL was assembled as
// `${GITHUB_API}${callerSuppliedPath}` with no check on what `path` is: a path
// without a leading `/` rebinds the URL authority (`@host`, `.suffix` joins),
// and dot-segments (literal or %-encoded — WHATWG resolves `%2e%2e` and `.%2e`
// as `..` before fetch sees them) escape the caller-intended endpoint prefix.
// Both shapes carry a live token to a place the caller did not mean.
//
// This leaf owns the check so neither consumer needs the other in its import
// graph (github-api.ts already imports github-app.ts for
// generateInstallationToken — the reverse would be a cycle, the same reason
// isRetryable lives in ./github-retry). Convention mirrors
// assertCodexEndpoint in server/codex-code-adapter.ts: `new URL` + `https:` +
// no userinfo + host assertion, never substring matching on the raw string.

import { hasControlChar, DOT_SEGMENT } from "./kb-github-path";
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";

const log = createChildLogger("github-egress");

const GITHUB_API_ORIGIN = "https://api.github.com";

// Bounds the whole request URL (scheme + authority + path + query). GitHub
// API URLs are far shorter; the cap bounds the segment work on
// attacker-influenced input before any parsing happens.
const MAX_URL_LENGTH = 4096;

function egressDenied(reason: string): Error {
  return Object.assign(new Error(`GitHub API egress denied: ${reason}`), {
    code: "github_api_egress_denied",
  });
}

function assertOrigin(url: URL): void {
  if (url.origin !== GITHUB_API_ORIGIN) {
    throw egressDenied(`origin ${url.origin} is not ${GITHUB_API_ORIGIN}`);
  }
  if (url.username || url.password) {
    throw egressDenied("URL carries userinfo");
  }
}

// Rejects dot-segments on the raw (pre-parse) path portion. The query is
// excluded — `?` terminates the path, so only bytes before it form segments.
function assertNoDotSegments(rawPathAndQuery: string): void {
  const pathname = rawPathAndQuery.split("?")[0];
  for (const segment of pathname.split("/")) {
    if (DOT_SEGMENT.test(segment)) {
      throw egressDenied("dot-segment in path");
    }
  }
}

/** Assert an already-absolute URL targets https://api.github.com and carries
 *  no userinfo or dot-segments, or throw. For callers (github-app.ts
 *  › githubFetch) that hold a whole URL rather than a path fragment. */
export function assertGithubApiAbsoluteUrl(rawUrl: string): string {
  if (rawUrl.length === 0 || rawUrl.length > MAX_URL_LENGTH) {
    throw egressDenied("URL empty or over-length");
  }
  // `\` folds to `/` and `#` truncates the URL under WHATWG; neither is
  // legitimate in a GitHub API request URL.
  if (rawUrl.includes("\\") || rawUrl.includes("#") || hasControlChar(rawUrl)) {
    throw egressDenied("URL contains unsafe bytes");
  }
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    throw egressDenied("URL does not parse");
  }
  assertOrigin(url);
  // Everything after scheme://authority is the raw path — dot-segments in it
  // would be normalized away by the parse above, so check the raw bytes.
  const pathPortion = rawUrl.replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^/?#]*/, "");
  assertNoDotSegments(pathPortion);
  return url.href;
}

/** Resolve a GitHub API path fragment to an absolute URL bound to
 *  https://api.github.com, or throw. The leading-`/` check is the one
 *  assertion that must run BEFORE the fragment is concatenated — after
 *  concatenation `api.github.compath` is already a mangled authority — so it
 *  lives here rather than in assertGithubApiAbsoluteUrl. */
export function githubApiUrl(path: string): string {
  if (!path.startsWith("/") || path.startsWith("//")) {
    throw egressDenied("path must begin with a single /");
  }
  return assertGithubApiAbsoluteUrl(GITHUB_API_ORIGIN + path);
}

// Refused inputs are the class that can carry line separators — strip
// control bytes and \u2028 / \u2029 before they land in pino/Sentry fields so
// a hostile URL can't split a log line (it poisons only its own refusal
// record either way; credentials never appear in a refused value).
function sanitizedTarget(raw: string): string {
  return raw.replace(/[\p{Cc}\u2028\u2029]/gu, "").slice(0, 512);
}

/** Mirror an egress refusal to pino + Sentry. Every assert call site routes
 *  through this (directly or via githubEgressUrl) so `op: "url-refused"` is
 *  the single liveness signal for the whole guard surface — a sudden cluster
 *  means a caller shape changed or the guard misclassifies a real path. */
export function reportEgressRefusal(
  err: unknown,
  feature: string,
  target: string,
): void {
  const refusal = err instanceof Error ? err : new Error(String(err));
  log.error(
    { err: refusal.message, target: sanitizedTarget(target) },
    "Refused non-GitHub-bound API URL",
  );
  reportSilentFallback(refusal, {
    feature,
    op: "url-refused",
    extra: { target: sanitizedTarget(target) },
    message: "GitHub API request URL refused by egress guard",
  });
}

/** assertGithubApiAbsoluteUrl plus the refusal mirror — the form call sites
 *  should use so a refusal is never silent. Returns the pinned URL. */
export function githubEgressUrl(rawUrl: string, feature: string): string {
  try {
    return assertGithubApiAbsoluteUrl(rawUrl);
  } catch (err) {
    reportEgressRefusal(err, feature, rawUrl);
    throw err;
  }
}
