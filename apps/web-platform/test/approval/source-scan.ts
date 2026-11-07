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

// ---------------------------------------------------------------------------------------------------------------------
// #9601: a role-classified census of the module edges and call sites of a named export. A small lexer (comments, strings,
// template literals with nested expressions, and regex literals are NOT code) feeds a statement-aware classifier, so an
// aliased import, `export { x } from`, `export *`, `import * as R` with `R.x(`, a dynamic `import()` and a `require()` are
// each reported under their own role instead of slipping past a substring match. Anything the classifier cannot place is
// `other`, which callers pin to zero (the red `unclassified` bucket).
//
// Named residual: a computed-name access (`R["render" + "ApprovalView"]`) is invisible to a lexical scan.
// ---------------------------------------------------------------------------------------------------------------------

export interface Token {
  t: "id" | "str" | "num" | "punct";
  v: string;
  pos: number;
}

const ID_START = /[A-Za-z_$]/;
const ID_PART = /[A-Za-z0-9_$]/;
const REGEX_PRECEDING_KEYWORDS = new Set(["return", "typeof", "case", "in", "of", "delete", "void", "throw", "new", "else", "do", "yield", "await"]);

export function tokenize(src: string): Token[] {
  const out: Token[] = [];
  const n = src.length;

  // Lex code from `i`. When `untilCloseBrace`, stop at the `}` that closes a template `${` (depth 0) and return its index.
  const lexCode = (start: number, untilCloseBrace: boolean): number => {
    let i = start;
    let depth = 0;
    while (i < n) {
      const c = src[i];
      const d = src[i + 1];
      if (c === " " || c === "\t" || c === "\n" || c === "\r") {
        i++;
      } else if (c === "/" && d === "/") {
        while (i < n && src[i] !== "\n") i++;
      } else if (c === "/" && d === "*") {
        i += 2;
        while (i < n && !(src[i] === "*" && src[i + 1] === "/")) i++;
        i += 2;
      } else if (c === '"' || c === "'") {
        const s = i;
        i++;
        while (i < n && src[i] !== c) {
          if (src[i] === "\\") i++;
          i++;
        }
        out.push({ t: "str", v: src.slice(s + 1, i), pos: s });
        i++;
      } else if (c === "`") {
        const s = i;
        i++;
        let text = "";
        while (i < n && src[i] !== "`") {
          if (src[i] === "\\") {
            text += src[i] + (src[i + 1] ?? "");
            i += 2;
          } else if (src[i] === "$" && src[i + 1] === "{") {
            i = lexCode(i + 2, true) + 1;
          } else {
            text += src[i];
            i++;
          }
        }
        out.push({ t: "str", v: text, pos: s });
        i++;
      } else if (c === "/" && regexAllowed(out)) {
        const s = i;
        i++;
        let inClass = false;
        while (i < n && (inClass || src[i] !== "/")) {
          if (src[i] === "\\") i++;
          else if (src[i] === "[") inClass = true;
          else if (src[i] === "]") inClass = false;
          i++;
        }
        i++;
        while (i < n && ID_PART.test(src[i])) i++;
        out.push({ t: "str", v: "<regex>", pos: s });
      } else if (ID_START.test(c)) {
        const s = i;
        while (i < n && ID_PART.test(src[i])) i++;
        out.push({ t: "id", v: src.slice(s, i), pos: s });
      } else if (/[0-9]/.test(c)) {
        const s = i;
        while (i < n && /[0-9A-Za-z_.]/.test(src[i])) i++;
        out.push({ t: "num", v: src.slice(s, i), pos: s });
      } else {
        if (untilCloseBrace) {
          if (c === "{") depth++;
          else if (c === "}") {
            if (depth === 0) return i;
            depth--;
          }
        }
        out.push({ t: "punct", v: c, pos: i });
        i++;
      }
    }
    return i;
  };

  lexCode(0, false);
  return out;
}

function regexAllowed(prev: Token[]): boolean {
  const last = prev[prev.length - 1];
  if (!last) return true;
  if (last.t === "num" || last.t === "str") return false;
  if (last.t === "id") return REGEX_PRECEDING_KEYWORDS.has(last.v);
  return !(last.v === ")" || last.v === "]" || last.v === "}");
}

export type CensusRole =
  | "import"
  | "type-import"
  | "reexport"
  | "namespace-import"
  | "namespace-member"
  | "dynamic-import"
  | "require"
  | "call"
  | "definition"
  | "other";

export interface CensusHit {
  /** `id`: the bare identifier; `edge`: a module edge whose specifier resolves to the target module path. */
  kind: "id" | "edge";
  role: CensusRole;
  /** For an edge: the resolved target path (no extension), relative to apps/web-platform. */
  resolved?: string;
  pos: number;
}

/** Resolve an import specifier from `fromFile` (a path relative to apps/web-platform) to a path without extension, or null for a package. */
export function resolveSpecifier(fromFile: string, spec: string): string | null {
  let p: string;
  if (spec.startsWith("@/")) p = spec.slice(2);
  else if (spec.startsWith("./") || spec.startsWith("../")) {
    const parts = fromFile.split("/").slice(0, -1);
    for (const seg of spec.split("/")) {
      if (seg === "." || seg === "") continue;
      if (seg === "..") parts.pop();
      else parts.push(seg);
    }
    p = parts.join("/");
  } else return null;
  return p.replace(/\.(tsx?|jsx?|mjs|cjs)$/, "");
}

/**
 * Census of one source file. `ident` is the exported name to follow (for example `renderApprovalView`), `targets` the module
 * paths (no extension, relative to apps/web-platform) whose edges to report.
 */
export function censusSource(src: string, file: string, ident: string, targets: readonly string[]): CensusHit[] {
  const toks = tokenize(src);
  const hits: CensusHit[] = [];
  const consumed = new Set<number>();
  const isP = (i: number, v: string) => toks[i]?.t === "punct" && toks[i].v === v;
  const isId = (i: number, v?: string) => toks[i]?.t === "id" && (v === undefined || toks[i].v === v);
  const edge = (spec: string, role: CensusRole, pos: number) => {
    const resolved = resolveSpecifier(file, spec);
    if (resolved !== null && targets.includes(resolved)) hits.push({ kind: "edge", role, resolved, pos });
  };

  for (let i = 0; i < toks.length; i++) {
    const tk = toks[i];
    if (tk.t !== "id") continue;

    if (tk.v === "import" && !isP(i - 1, ".")) {
      if (isP(i + 1, "(")) {
        if (toks[i + 2]?.t === "str") edge(toks[i + 2].v, "dynamic-import", tk.pos);
        continue;
      }
      // Static import statement: up to `from "x"`, a bare `import "x"`, or `;`.
      let j = i + 1;
      const typeOnlyWhole = isId(j, "type") && !isId(j + 1, "from");
      let ns = false;
      let allInlineType = true;
      let sawNamed = false;
      let inBraces = false;
      let braceItemStart = true;
      let hasIdent = false;
      let spec: string | null = null;
      for (; j < toks.length; j++) {
        if (isP(j, ";")) break;
        if (toks[j].t === "str") {
          spec = toks[j].v;
          break;
        }
        if (isP(j, "{")) {
          inBraces = true;
          braceItemStart = true;
          continue;
        }
        if (isP(j, "}")) {
          inBraces = false;
          continue;
        }
        if (isP(j, "*")) ns = true;
        if (isP(j, ",")) {
          braceItemStart = true;
          continue;
        }
        if (toks[j].t === "id" && toks[j].v !== "from") {
          if (inBraces) {
            if (braceItemStart) {
              sawNamed = true;
              if (!(toks[j].v === "type" && toks[j + 1]?.t === "id" && toks[j + 1].v !== "as")) allInlineType = false;
            }
            braceItemStart = false;
          }
          if (toks[j].v === ident) {
            hasIdent = true;
            consumed.add(j);
          }
        }
      }
      const typeOnly = typeOnlyWhole || (sawNamed && allInlineType);
      const role: CensusRole = typeOnly ? "type-import" : ns ? "namespace-import" : "import";
      if (hasIdent) hits.push({ kind: "id", role, pos: tk.pos });
      if (spec !== null) edge(spec, role, tk.pos);
      i = Math.max(i, j);
      continue;
    }

    if (tk.v === "export") {
      let j = i + 1;
      const typeOnly = isId(j, "type") && (isP(j + 1, "{") || isP(j + 1, "*"));
      if (typeOnly) j++;
      if (isP(j, "{") || isP(j, "*")) {
        let hasIdent = false;
        let spec: string | null = null;
        if (isP(j, "{")) {
          for (j++; j < toks.length && !isP(j, "}"); j++) {
            if (toks[j].t === "id" && toks[j].v === ident) {
              hasIdent = true;
              consumed.add(j);
            }
          }
          if (isId(j + 1, "from") && toks[j + 2]?.t === "str") spec = toks[j + 2].v;
        } else {
          // `export * from "x"` or `export * as ns from "x"`
          for (j++; j < toks.length && !isId(j, "from") && !isP(j, ";"); j++);
          if (isId(j, "from") && toks[j + 1]?.t === "str") spec = toks[j + 1].v;
        }
        const role: CensusRole = typeOnly ? "type-import" : "reexport";
        if (hasIdent) hits.push({ kind: "id", role, pos: tk.pos });
        if (spec !== null) edge(spec, role, tk.pos);
        i = Math.max(i, j);
      }
      continue;
    }

    if (tk.v === "require" && isP(i + 1, "(") && toks[i + 2]?.t === "str" && !isP(i - 1, ".")) {
      edge(toks[i + 2].v, "require", tk.pos);
      continue;
    }
  }

  for (let i = 0; i < toks.length; i++) {
    if (toks[i].t !== "id" || toks[i].v !== ident || consumed.has(i)) continue;
    const pos = toks[i].pos;
    if (isId(i - 1, "function")) hits.push({ kind: "id", role: "definition", pos });
    else if (isP(i - 1, ".")) hits.push({ kind: "id", role: "namespace-member", pos });
    else if (isP(i + 1, "(")) hits.push({ kind: "id", role: "call", pos });
    else hits.push({ kind: "id", role: "other", pos });
  }
  return hits.sort((a, b) => a.pos - b.pos);
}

/** The source with comments blanked and string/regex bodies kept out of the way: only `code` offsets, for structural ordering checks. */
export function codeOffsets(src: string, ident: string): number[] {
  return tokenize(src)
    .filter((t, i, all) => t.t === "id" && t.v === ident && all[i + 1]?.v === "(")
    .map((t) => t.pos);
}
