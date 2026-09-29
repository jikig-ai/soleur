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

const GITHUB_API_ORIGIN = "https://api.github.com";

// GitHub API paths are far shorter than this; the cap bounds the segment work
// on attacker-influenced input before any parsing happens.
const MAX_PATH_LENGTH = 4096;

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
  if (rawUrl.length === 0 || rawUrl.length > MAX_PATH_LENGTH + GITHUB_API_ORIGIN.length) {
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
 *  https://api.github.com, or throw. A `path` lacking a leading `/` can rebind
 *  the request authority — the one check assertGithubApiAbsoluteUrl cannot
 *  perform, since by then the fragment is already concatenated. */
export function githubApiUrl(path: string): string {
  if (!path.startsWith("/") || path.startsWith("//")) {
    throw egressDenied("path must begin with a single /");
  }
  return assertGithubApiAbsoluteUrl(GITHUB_API_ORIGIN + path);
}
