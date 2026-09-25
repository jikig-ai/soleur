// Guard for a request-supplied KB-relative path that is interpolated into a
// GitHub API URL (`/repos/{owner}/{repo}/contents/knowledge-base/<path>`).
//
// A containment check on the filesystem (`isPathInWorkspace(path.join(...))`)
// does not protect the URL: `path.join` treats `%2e%2e` and `\` as literal
// name characters, while `fetch`'s WHATWG URL parser resolves `%2e%2e` (any
// case) and `.%2e` as `..` and turns `\` into `/`. So `x/%2e%2e/%2e%2e/f.pdf`
// passes the filesystem check and reaches `/contents/f.pdf`, outside
// `knowledge-base/`. Percent-encoding each segment makes every segment a
// literal name to GitHub (`%2e%2e` is sent as `%252e%252e`, `?`/`#` as
// `%3F`/`%23`), so the only remaining traversal is a real `.`/`..` segment,
// which is refused here, along with empty segments and control characters.

/** C0 controls, DEL, and the U+2028/U+2029 line separators. A loop rather
 *  than a regex so the eslint `no-control-regex` ratchet does not grow. */
export function hasControlChar(s: string): boolean {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x20 || c === 0x7f || c === 0x2028 || c === 0x2029) return true;
  }
  return false;
}

/** A segment that is, or percent-decodes to, `.` or `..` (`%2e%2e`, `.%2E`).
 *  Encoding already makes the encoded forms literal names; refusing them too
 *  keeps a future caller that skips the encoding safe. */
const DOT_SEGMENT = /^(?:\.|%2e){1,2}$/i;

/** The segments of a KB-relative path, or null when it is not a plain
 *  relative path: empty, a leading/trailing/doubled `/`, a dot segment
 *  (literal or percent-encoded), a control character, or longer than
 *  `maxLength`. */
export function kbPathSegments(rel: string, maxLength = 1024): string[] | null {
  if (rel.length === 0 || rel.length > maxLength) return null;
  if (hasControlChar(rel)) return null;
  const segments = rel.split("/");
  if (segments.some((seg) => seg === "" || DOT_SEGMENT.test(seg))) return null;
  return segments;
}

/** `knowledge-base/<rel>` percent-encoded per segment for a GitHub API URL,
 *  or null when `rel` is unsafe (see `kbPathSegments`). Use the RAW
 *  `knowledge-base/<rel>` for JSON bodies (e.g. `git/trees` entries), never
 *  this encoded form. */
export function kbGithubUrlPath(rel: string, maxLength = 1024): string | null {
  const segments = kbPathSegments(rel, maxLength);
  if (!segments) return null;
  return `knowledge-base/${segments.map(encodeURIComponent).join("/")}`;
}
