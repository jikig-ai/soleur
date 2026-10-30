/**
 * Shared source-scanning helper for the approval sentinels (decide-boundary, runner-census): a comment stripper that keeps
 * string/template content intact (a URL with `//` inside a string is code, not a comment).
 */

/** Blank out comments, keeping string/template/regex-free-enough code intact. Newlines are preserved. */
export function stripComments(src: string): string {
  let out = "";
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    const d = src[i + 1];
    if (c === "/" && d === "/") {
      while (i < n && src[i] !== "\n") i++;
    } else if (c === "/" && d === "*") {
      i += 2;
      while (i < n && !(src[i] === "*" && src[i + 1] === "/")) {
        if (src[i] === "\n") out += "\n";
        i++;
      }
      i += 2;
    } else if (c === '"' || c === "'" || c === "`") {
      const quote = c;
      out += c;
      i++;
      while (i < n && src[i] !== quote) {
        if (src[i] === "\\") {
          out += src[i];
          i++;
        }
        if (i < n) out += src[i];
        i++;
      }
      if (i < n) out += quote;
      i++;
    } else {
      out += c;
      i++;
    }
  }
  return out;
}
