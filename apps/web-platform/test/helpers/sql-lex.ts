// A single-pass SQL lexer for the offline migration-shape tests (#11238). It exists because the previous approach
// (two regex passes: `/* */` then `--`) is blind to nesting: a `/*` inside a string literal, or a `-- /*` line
// comment, made the first pass swallow live SQL, so the parity, denial-prefix and reader-set checks all read a
// truncated file. One left-to-right pass knows, at every character, whether it is inside a literal or a comment.
//
// Covers: '...' literals ('' escape), "..." quoted identifiers ("" escape), `--` line comments, nested `/* */`
// block comments (Postgres nests them). Dollar-quoted bodies ($$ ... $$) are DELIBERATELY treated as code: the
// function body is the thing the tests read. Not covered: E'...' backslash escapes (none in the files under test).

export type SqlTok = { kind: "code" | "lit"; text: string };

export const lexSql = (s: string): SqlTok[] => {
  const out: SqlTok[] = [];
  let code = "";
  const flush = (): void => {
    if (code !== "") out.push({ kind: "code", text: code });
    code = "";
  };
  let i = 0;
  while (i < s.length) {
    const c = s[i];
    const n = s[i + 1];
    if (c === "-" && n === "-") {
      // line comment: dropped up to (not including) the newline
      while (i < s.length && s[i] !== "\n") i++;
    } else if (c === "/" && n === "*") {
      // block comment, nested; an unterminated one swallows the rest (Postgres rejects it too)
      let depth = 1;
      i += 2;
      while (i < s.length && depth > 0) {
        if (s[i] === "/" && s[i + 1] === "*") (depth++, (i += 2));
        else if (s[i] === "*" && s[i + 1] === "/") (depth--, (i += 2));
        else i++;
      }
      code += " "; // a comment is whitespace to the parser
    } else if (c === "'" || c === '"') {
      flush();
      let j = i + 1;
      for (;;) {
        if (j >= s.length) break;
        if (s[j] === c) {
          if (s[j + 1] === c) j += 2;
          else {
            j++;
            break;
          }
        } else j++;
      }
      out.push({ kind: "lit", text: s.slice(i, j) });
      i = j;
    } else {
      code += c;
      i++;
    }
  }
  flush();
  return out;
};

/** Comments removed, literals and quoted identifiers byte-for-byte. */
export const stripSqlComments = (s: string): string => lexSql(s).map((t) => t.text).join("");

/** Whitespace collapsed and spacing around ( ) , ; removed OUTSIDE literals only; literals are untouched. */
export const collapseSql = (s: string): string =>
  lexSql(s)
    .map((t) => (t.kind === "lit" ? t.text : t.text.replace(/\s+/g, " ").replace(/\s*([(),;])\s*/g, "$1")))
    .join("")
    .trim();

/** Split on a `;` that is code (not inside a literal or comment). Terminators are dropped; empties are dropped. */
export const splitSqlStatements = (s: string): string[] => {
  const out: string[] = [];
  let cur = "";
  for (const t of lexSql(s)) {
    if (t.kind === "lit") {
      cur += t.text;
      continue;
    }
    const parts = t.text.split(";");
    for (let k = 0; k < parts.length - 1; k++) {
      out.push(cur + parts[k]);
      cur = "";
    }
    cur += parts[parts.length - 1];
  }
  out.push(cur);
  return out.map((x) => x.replace(/\s+/g, " ").trim()).filter(Boolean);
};
