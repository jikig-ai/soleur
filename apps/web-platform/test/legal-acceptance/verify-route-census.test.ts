/**
 * #12011 PR-D: census of every route and page under app/api/internal/legal-acceptance/.
 *
 * `/api/internal/legal-acceptance` is a PREFIX entry in PUBLIC_PATHS (dynamic [key] segment): the middleware lets every path
 * under it through without a session, so the bearer check in the handler is the only gate. A sibling route added under it
 * later would be public by construction. This census lists every `route.*` and `page.*` file under the directory
 * (recursively, any extension; an empty tree fails) and, for EVERY exported HTTP handler (GET, POST, PUT, PATCH, DELETE,
 * HEAD, OPTIONS), requires on the comment- and string-stripped source of that handler:
 *  1. `readNamedBearerSecret(` and then `bearerMatches(` are both called;
 *  2. before the `bearerMatches(` call there is no `await` and no call other than the allow-listed shape checks and
 *     configuration helpers (ALLOWED_PRE_BEARER_CALLS), so no database, registry, parameter or URL work precedes the check;
 *  3. the result gates a return: `if (... || !bearerMatches(...)) return ...` (or a block that returns), the bearer test
 *     being a top-level `||` operand that is not joined to anything by `&&`.
 * A handler that is exported in a form this census cannot analyse (a wrapper call, `export { GET }`, an expression-bodied
 * arrow) FAILS: fail closed, restructure the handler. A `page.*` file fails outright: a page cannot check a bearer and
 * would be public by the prefix. A small tokenizer removes comments, string literals and template text (a string holding
 * a comment opener must not hide code that follows it) and keeps template `${ }` expressions, which are code.
 */
import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { PUBLIC_PATHS } from "@/lib/routes";
import { stripSource } from "./strip-source";

const WEB = path.join(__dirname, "../..");
const ROOT_DIR = "app/api/internal/legal-acceptance";
const PREFIX = "/api/internal/legal-acceptance";

// ── tokenizer (shared with the op-contract test) ────────────────────────────────────────────────────────────────

/** Source with comments removed, string literals emptied (`""`), template text removed (`${ }` code kept) and regex literals reduced to `/r/`. */
export const stripCommentsAndStrings = (src: string): string => stripSource(src, { strings: "empty" });
const stripImports = (t: string): string => t.replace(/\bimport\s[^;]*;/g, "");
const codeOf = (t: string): string => stripImports(stripCommentsAndStrings(t));

// ── handler analysis ────────────────────────────────────────────────────────────────────────────────────────────

const HTTP = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"];
const HTTP_ALT = HTTP.join("|");

/**
 * Calls that may precede bearerMatches(): the secret read, the configuration shape checks and their (event-only) report,
 * and the early return that answers 503. Nothing here reads a database, the registry, the parameters or the URL.
 */
const ALLOWED_PRE_BEARER_CALLS = new Set([
  "readNamedBearerSecret",
  "TOKEN_RE.test",
  "isUuid",
  "badConfig.push",
  "reportBadConfig",
  "unavailable",
  "founderRaw.toLowerCase",
]);
const KEYWORDS = new Set(["if", "for", "while", "switch", "catch", "function", "return", "typeof", "void", "super"]);

function matchClose(s: string, open: number): number {
  const pairs: Record<string, string> = { "(": ")", "{": "}", "[": "]" };
  const stack: string[] = [];
  for (let i = open; i < s.length; i++) {
    const c = s[i];
    if (pairs[c]) stack.push(pairs[c]);
    else if (c === ")" || c === "}" || c === "]") {
      if (stack.pop() !== c) return -1;
      if (stack.length === 0) return i;
    }
  }
  return -1;
}

function splitTop(s: string, sep: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let cur = "";
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if ("([{".includes(c)) depth++;
    else if (")]}".includes(c)) depth--;
    if (depth === 0 && s.startsWith(sep, i)) {
      out.push(cur);
      cur = "";
      i += sep.length - 1;
    } else cur += c;
  }
  out.push(cur);
  return out;
}

interface Handler {
  name: string;
  body: string;
}

/** The exported handlers of a stripped source, plus the problems of any export this census cannot analyse. */
export function exportedHandlers(code: string): { handlers: Handler[]; problems: string[] } {
  const handlers: Handler[] = [];
  const problems: string[] = [];
  const bodyAfterParen = (parenOpen: number, arrow: boolean): string | null => {
    const close = matchClose(code, parenOpen);
    if (close < 0) return null;
    let angle = 0;
    for (let i = close + 1; i < code.length; i++) {
      const c = code[i];
      if (c === "<") angle++;
      else if (c === ">" && code[i - 1] === "=") {
        // `=>`: an arrow handler needs a block body right after it.
        if (!arrow || angle > 0) continue;
        const rest = code.slice(i + 1).trimStart();
        if (!rest.startsWith("{")) return null;
        const open = code.length - rest.length;
        const end = matchClose(code, open);
        return end < 0 ? null : code.slice(open + 1, end);
      } else if (c === ">") angle = Math.max(0, angle - 1);
      else if (c === "{" && angle === 0 && !arrow) {
        const end = matchClose(code, i);
        return end < 0 ? null : code.slice(i + 1, end);
      } else if (c === ";" && angle === 0) return null;
    }
    return null;
  };
  const found = new Set<string>();
  for (const m of code.matchAll(new RegExp(`\\bexport\\s+(?:async\\s+)?function\\s+(${HTTP_ALT})\\s*\\(`, "g"))) {
    const body = bodyAfterParen(m.index! + m[0].length - 1, false);
    if (body === null) problems.push(`${m[1]}: cannot find the handler body`);
    else {
      handlers.push({ name: m[1], body });
      found.add(m[1]);
    }
  }
  for (const m of code.matchAll(new RegExp(`\\bexport\\s+const\\s+(${HTTP_ALT})\\s*(?::[^=]+)?=\\s*(?:async\\s+)?(?:function\\s*)?\\(`, "g"))) {
    const body = bodyAfterParen(m.index! + m[0].length - 1, true);
    if (body === null) problems.push(`${m[1]}: arrow handler without a block body cannot be analysed`);
    else {
      handlers.push({ name: m[1], body });
      found.add(m[1]);
    }
  }
  for (const m of code.matchAll(new RegExp(`\\bexport\\s+(?:async\\s+)?(?:function|const|let|var)\\s+(${HTTP_ALT})\\b`, "g"))) {
    if (!found.has(m[1])) problems.push(`${m[1]}: exported in a form this census cannot analyse (a wrapper call?)`);
  }
  if (new RegExp(`\\bexport\\s*\\{[^}]*\\b(${HTTP_ALT})\\b`).test(code) || /\bexport\s*\*/.test(code)) {
    problems.push("a handler is re-exported (export { ... } / export *): cannot be analysed");
  }
  if (handlers.length === 0 && problems.length === 0) problems.push("no exported HTTP handler found");
  return { handlers, problems };
}

/** Problems with one handler body (empty when it checks the bearer first and the result gates a return). */
export function handlerProblems(body: string): string[] {
  const problems: string[] = [];
  const r = body.search(/\breadNamedBearerSecret\(/);
  const b = body.search(/\bbearerMatches\(/);
  if (r < 0) problems.push("does not call readNamedBearerSecret(");
  if (b < 0) {
    problems.push("does not call bearerMatches(");
    return problems;
  }
  if (r > b) problems.push("calls readNamedBearerSecret( after bearerMatches(");
  const prefix = body.slice(0, b);
  if (/\bawait\b/.test(prefix)) problems.push("await before bearerMatches(");
  for (const m of prefix.matchAll(/([A-Za-z_$][\w$]*(?:\s*\.\s*[A-Za-z_$][\w$]*)*)\s*\(/g)) {
    const name = m[1].replace(/\s+/g, "");
    if (KEYWORDS.has(name) || ALLOWED_PRE_BEARER_CALLS.has(name)) continue;
    problems.push(`call to ${name}( before bearerMatches(`);
  }
  // The result must gate a return.
  let gated = false;
  for (const m of body.matchAll(/\bif\s*\(/g)) {
    const open = m.index! + m[0].length - 1;
    const close = matchClose(body, open);
    if (!(open < b && b < close)) continue;
    const cond = body.slice(open + 1, close);
    const operand = splitTop(cond, "||").find((o) => o.trim().startsWith("!bearerMatches("));
    if (operand === undefined || splitTop(operand, "&&").length > 1) continue;
    const rest = body.slice(close + 1).trimStart();
    if (/^return\b/.test(rest)) gated = true;
    else if (rest.startsWith("{")) {
      const end = matchClose(rest, 0);
      if (end > 0 && /\breturn\b/.test(rest.slice(1, end))) gated = true;
    }
  }
  if (!gated) problems.push("the bearerMatches( result does not gate a return (expected `if (... || !bearerMatches(...)) return ...`)");
  return problems;
}

/** Problems of one file (route.* or page.*). */
export function censusProblems(file: string, src: string): string[] {
  if (/^page\.[A-Za-z0-9]+$/.test(path.basename(file))) {
    return ["a page under the public prefix cannot check a bearer: none may exist here"];
  }
  const { handlers, problems } = exportedHandlers(codeOf(src));
  for (const h of handlers) for (const p of handlerProblems(h.body)) problems.push(`${h.name}: ${p}`);
  return problems;
}

/** A tree with no route or page files fails: an empty census must not read as "all handlers are fine". */
export function treeProblems(files: Array<{ rel: string; src: string }>): string[] {
  if (files.length === 0) return ["no route.* or page.* file found under the directory"];
  return files.flatMap((f) => censusProblems(f.rel, f.src).map((p) => `${f.rel}: ${p}`));
}

function censusFiles(dir: string): string[] {
  const out: string[] = [];
  for (const n of readdirSync(path.join(WEB, dir)).sort()) {
    const rel = `${dir}/${n}`;
    if (statSync(path.join(WEB, rel)).isDirectory()) out.push(...censusFiles(rel));
    else if (/^(route|page)\.[A-Za-z0-9]+$/.test(n)) out.push(rel);
  }
  return out;
}

/** The URL path a route file serves, with every dynamic segment replaced by a probe value. */
const urlOf = (rel: string): string => "/" + path.dirname(rel).replace(/^app\//, "").replace(/\[[^\]]+\]/g, "probe");

describe("every route and page under app/api/internal/legal-acceptance checks the bearer first", () => {
  const files = censusFiles(ROOT_DIR);

  it("finds the verify route (an empty census fails)", () => {
    expect(files.length).toBeGreaterThan(0);
    expect(files).toContain(`${ROOT_DIR}/[key]/route.ts`);
  });
  it("every handler of every file passes the census (readNamedBearerSecret, then bearerMatches gating a return, before any await or other call)", () => {
    expect(treeProblems(files.map((rel) => ({ rel, src: readFileSync(path.join(WEB, rel), "utf8") })))).toEqual([]);
  });
  it("the verify route exports exactly the handlers this census analysed (GET)", () => {
    const { handlers, problems } = exportedHandlers(codeOf(readFileSync(path.join(WEB, `${ROOT_DIR}/[key]/route.ts`), "utf8")));
    expect(problems).toEqual([]);
    expect(handlers.map((h) => h.name)).toEqual(["GET"]);
  });
  it.each(files)("%s: is reachable without a session through the PUBLIC_PATHS prefix entry, as the middleware evaluates it", (rel) => {
    const isPublic = (p: string): boolean => PUBLIC_PATHS.some((e) => p === e || p.startsWith(e + "/"));
    expect(isPublic(urlOf(rel)), urlOf(rel)).toBe(true);
  });

  it("the predicate used here is the one in middleware.ts (anchored on its source)", () => {
    const mw = stripCommentsAndStrings(readFileSync(path.join(WEB, "middleware.ts"), "utf8"));
    // Strings are emptied by the tokenizer, so anchor on the structure around the `"/"` literal.
    expect(mw).toMatch(/PUBLIC_PATHS\.some\(\(p\) => pathname === p \|\| pathname\.startsWith\(p \+ ""\)\)/);
    expect(readFileSync(path.join(WEB, "middleware.ts"), "utf8")).toContain('PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"))');
  });
  it("PUBLIC_PATHS has exactly one entry for this tree, it is the prefix, and neither /api/internal nor a look-alike is public", () => {
    const isPublic = (p: string): boolean => PUBLIC_PATHS.some((e) => p === e || p.startsWith(e + "/"));
    expect(PUBLIC_PATHS.filter((p) => p.startsWith(PREFIX))).toEqual([PREFIX]);
    expect(PUBLIC_PATHS).not.toContain("/api/internal");
    expect(PUBLIC_PATHS).not.toContain("/api/internal/");
    expect(isPublic(`${PREFIX}-foo`)).toBe(false);
    expect(isPublic("/api/internal/legal-acceptanc")).toBe(false);
    expect(isPublic("/api/internal")).toBe(false);
    expect(isPublic("/api/legal-acceptance/fixture-terms/decide")).toBe(false);
  });
});

describe("the tokenizer", () => {
  it("removes comments, empties strings, drops template text but keeps ${ } code, and reduces regex literals", () => {
    const out = stripCommentsAndStrings('a(); // bearerMatches(\n/* bearerMatches( */ const s = "bearerMatches(" + \'x\'; const t = `bearerMatches( ${real()} `; const r = /^[a-z"]+$/.test(s);');
    expect(out).not.toMatch(/bearerMatches/);
    expect(out).toContain("real()");
    expect(out).toContain("a();");
    expect(out).toContain("/r/.test(s)");
  });
  it("a string that holds a comment opener does not swallow the code after it", () => {
    const out = stripCommentsAndStrings('const s = "/*"; db.from("x"); /* c */ done();');
    expect(out).toContain("db.from(");
    expect(out).toContain("done();");
  });
  it("a division is not a regex, and a quote inside a regex class does not open a string", () => {
    expect(stripCommentsAndStrings("const q = a / b; await x(); const c = d / e;")).toContain("await x();");
    expect(stripCommentsAndStrings("const r = /[\"']/; await x();")).toContain("await x();");
  });
});

describe("negative controls: the census fails on each way a handler can check late, wrongly or not at all", () => {
  const GOOD = `
    import { bearerMatches } from "@/lib/internal-auth";
    import { createServiceClient } from "@/lib/supabase/service";
    export async function GET(req: Request, ctx: { params: Promise<{ key: string }> }): Promise<Response> {
      const token = readNamedBearerSecret("LEGAL_ACCEPTANCE_VERIFY_TOKEN");
      if (token === null || !TOKEN_RE.test(token)) return unavailable();
      if (!token || !bearerMatches(req.headers.get("authorization"), token)) return new Response(null, { status: 401 });
      const { key } = await ctx.params;
      return Response.json({ key, u: new URL(req.url).search, s: createServiceClient() });
    }`;
  const BEARER = 'if (!token || !bearerMatches(req.headers.get("authorization"), token)) return new Response(null, { status: 401 });';
  const problems = (src: string, file = "route.ts"): string[] => censusProblems(file, src);

  it("the good shape has no problems", () => {
    expect(problems(GOOD)).toEqual([]);
  });
  it("a block-bodied consequent that returns also gates", () => {
    expect(problems(GOOD.replace(BEARER, 'if (!bearerMatches(req.headers.get("authorization"), token)) { log(); return new Response(null, { status: 401 }); }'))).toEqual([]);
  });
  it("an arrow handler with a block body is analysed too", () => {
    const arrow = GOOD.replace("export async function GET(req: Request, ctx: { params: Promise<{ key: string }> }): Promise<Response> {", "export const GET = async (req: Request, ctx: { params: Promise<{ key: string }> }): Promise<Response> => {");
    expect(arrow).not.toBe(GOOD);
    expect(problems(arrow)).toEqual([]);
    expect(problems(arrow.replace(BEARER, "")).join("|")).toContain("does not call bearerMatches(");
  });

  it.each([
    ["no bearer check", GOOD.replace(BEARER, ""), "does not call bearerMatches("],
    ["no named secret", GOOD.replace("readNamedBearerSecret(", "somethingElse("), "does not call readNamedBearerSecret("],
    ["bearerMatches( only inside a string literal", GOOD.replace(BEARER, 'const doc = "if (!bearerMatches(req, token)) return";'), "does not call bearerMatches("],
    ["bearerMatches( only inside a template literal's text", GOOD.replace(BEARER, "const doc = `if (!bearerMatches(req, token)) return`;"), "does not call bearerMatches("],
    ["a comment that names bearerMatches(", GOOD.replace(BEARER, "// if (!bearerMatches(req, token)) return\n"), "does not call bearerMatches("],
    ["a block comment that names bearerMatches(", GOOD.replace(BEARER, "/* if (!bearerMatches(req, token)) return */"), "does not call bearerMatches("],
    ["the result is ignored", GOOD.replace(BEARER, 'bearerMatches(req.headers.get("authorization"), token);'), "does not gate a return"],
    ["the result is stored and never used", GOOD.replace(BEARER, 'const ok = bearerMatches(req.headers.get("authorization"), token);'), "does not gate a return"],
    ["positive polarity (returns when the token IS right)", GOOD.replace(BEARER, 'if (bearerMatches(req.headers.get("authorization"), token)) return new Response(null, { status: 200 });'), "does not gate a return"],
    ["joined to another condition with &&", GOOD.replace(BEARER, 'if (token && !bearerMatches(req.headers.get("authorization"), token) && flag) return new Response(null, { status: 401 });'), "does not gate a return"],
    ["the gate does not return", GOOD.replace(BEARER, 'if (!bearerMatches(req.headers.get("authorization"), token)) log();'), "does not gate a return"],
    ["params read first", GOOD.replace("const token", "const { key: k0 } = await ctx.params;\n      const token"), "await before bearerMatches("],
    ["any await first", GOOD.replace("const token", "await Promise.resolve();\n      const token"), "await before bearerMatches("],
    ["URL parsed first", GOOD.replace("const token", "const u0 = new URL(req.url);\n      const token"), "call to URL( before bearerMatches("],
    ["service client first", GOOD.replace("const token", "const c0 = createServiceClient();\n      const token"), "call to createServiceClient( before bearerMatches("],
    ["registry read first", GOOD.replace("const token", "getLegalText('x');\n      const token"), "call to getLegalText( before bearerMatches("],
    ["a database read through a name outside any list", GOOD.replace("const token", "const rows = db.from('t').select();\n      const token"), "call to db.from( before bearerMatches("],
    ["a database read hidden after a string that holds a comment opener", GOOD.replace("const token", 'const s = "/*"; db.from("t"); /* end */\n      const token'), "call to db.from( before bearerMatches("],
    ["the secret is read after the check", GOOD.replace('const token = readNamedBearerSecret("LEGAL_ACCEPTANCE_VERIFY_TOKEN");', "const token = other();").replace("const { key } = await ctx.params;", 'const t2 = readNamedBearerSecret("X");\n      const { key } = await ctx.params;'), "after bearerMatches("],
  ])("%s", (_label, src, want) => {
    expect(src).not.toBe(GOOD);
    expect(problems(src).join("|")).toContain(want);
  });

  it("a second exported handler with no bearer check fails, and names the handler", () => {
    const two = `${GOOD}\nexport async function POST(req: Request) { return Response.json({ ok: true }); }`;
    const out = problems(two);
    expect(out.join("|")).toMatch(/POST: does not call (readNamedBearerSecret|bearerMatches)\(/);
    expect(out.join("|")).not.toMatch(/GET:/);
  });
  it.each(["PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"])("an unguarded %s handler fails", (method) => {
    expect(problems(`${GOOD}\nexport async function ${method}() { return Response.json({}); }`).join("|")).toContain(`${method}: does not call`);
  });
  it("handlers exported in a form the census cannot analyse fail closed", () => {
    expect(problems(GOOD + "\nexport const POST = withAuth(async () => Response.json({}));").join("|")).toContain("POST: exported in a form this census cannot analyse");
    expect(problems(GOOD.replace("export async function GET", "async function GET") + "\nexport { GET };").join("|")).toContain("re-exported");
    expect(problems("export * from './other';").join("|")).toContain("re-exported");
    expect(problems(GOOD + "\nexport const DELETE = () => Response.json({});").join("|")).toContain("DELETE: arrow handler without a block body");
  });
  it("a file with no exported handler fails", () => {
    expect(problems("export const dynamic = 'force-dynamic';").join("|")).toContain("no exported HTTP handler found");
  });
  it("a page.* file fails whatever it contains, and a bearer check does not rescue it", () => {
    expect(problems("export default function Page() { return null; }", "page.tsx").join("|")).toContain("a page under the public prefix");
    expect(problems(GOOD, "page.ts").join("|")).toContain("a page under the public prefix");
  });
  it("an empty tree fails (zero files found)", () => {
    expect(treeProblems([]).join("|")).toContain("no route.* or page.* file found");
  });
  it("a tree with one good and one bad file fails and names the bad one", () => {
    const out = treeProblems([
      { rel: "a/route.ts", src: GOOD },
      { rel: "b/route.js", src: GOOD.replace(BEARER, "") },
    ]);
    expect(out.join("|")).toContain("b/route.js: GET: does not call bearerMatches(");
    expect(out.join("|")).not.toContain("a/route.ts");
  });
});
