/**
 * A small JavaScript/TypeScript tokenizer for the source-scanning tests (#12011 PR-D). It removes comments correctly (a string
 * that holds a comment opener must not swallow the code after it, and a comment that holds a quote must not open a string),
 * and either EMPTIES string literals, template text and regex literals (`strings: "empty"`, for tests that must not be
 * satisfied by a literal) or keeps them verbatim (`strings: "keep"`, for tests that read literal values). Template `${ }`
 * expressions are code and are always kept.
 */

const REGEX_PRECEDERS = new Set(["", "(", ",", "=", ":", "[", "!", "&", "|", "?", "{", "}", ";", "+", "-", "*", "%", "<", ">", "~", "^"]);

export function stripSource(src: string, o: { strings: "empty" | "keep" }): string {
  const keep = o.strings === "keep";
  function scan(start: number, inTemplateExpr: boolean): { out: string; end: number } {
    let out = "";
    let depth = 0;
    let i = start;
    const lastSignificant = (): string => out.trimEnd().slice(-1);
    const endsWithWord = (w: string): boolean => new RegExp(`(?:^|[^\\w$])${w}$`).test(out.trimEnd());
    while (i < src.length) {
      const c = src[i];
      const next = src[i + 1];
      if (c === "/" && next === "/") {
        while (i < src.length && src[i] !== "\n") i++;
      } else if (c === "/" && next === "*") {
        const end = src.indexOf("*/", i + 2);
        i = end < 0 ? src.length : end + 2;
        out += " ";
      } else if (c === '"' || c === "'") {
        const from = i;
        i++;
        while (i < src.length && src[i] !== c && src[i] !== "\n") i += src[i] === "\\" ? 2 : 1;
        i++;
        out += keep ? src.slice(from, i) : c + c;
      } else if (c === "`") {
        out += "`";
        i++;
        while (i < src.length && src[i] !== "`") {
          if (src[i] === "\\") {
            if (keep) out += src.slice(i, i + 2);
            i += 2;
          } else if (src[i] === "$" && src[i + 1] === "{") {
            out += "${";
            const r = scan(i + 2, true);
            out += r.out + "}";
            i = r.end;
          } else {
            if (keep) out += src[i];
            i++;
          }
        }
        i++;
        out += "`";
      } else if (c === "/" && (REGEX_PRECEDERS.has(lastSignificant()) || endsWithWord("return") || endsWithWord("typeof"))) {
        let j = i + 1;
        let inClass = false;
        let ok = false;
        while (j < src.length && src[j] !== "\n") {
          if (src[j] === "\\") j += 2;
          else if (src[j] === "[") (inClass = true), j++;
          else if (src[j] === "]") (inClass = false), j++;
          else if (src[j] === "/" && !inClass) {
            ok = true;
            break;
          } else j++;
        }
        if (ok) {
          j++;
          while (/[a-z]/i.test(src[j] ?? "")) j++;
          out += keep ? src.slice(i, j) : "/r/";
          i = j;
        } else {
          out += c;
          i++;
        }
      } else {
        if (inTemplateExpr) {
          if (c === "{") depth++;
          else if (c === "}") {
            if (depth === 0) return { out, end: i + 1 };
            depth--;
          }
        }
        out += c;
        i++;
      }
    }
    return { out, end: i };
  }
  return scan(0, false).out;
}
