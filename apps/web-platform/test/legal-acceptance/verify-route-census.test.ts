/**
 * #12011 PR-D: census of every handler under app/api/internal/legal-acceptance/.
 *
 * `/api/internal/legal-acceptance` is a PREFIX entry in PUBLIC_PATHS (dynamic [key] segment): the middleware lets every path
 * under it through without a session, so the bearer check in the handler is the only gate. A sibling route added under it
 * later would be public by construction. This test lists every route.ts under the directory (recursively) and requires that
 * each one reads the named secret, calls bearerMatches, and does so BEFORE any lookup, registry read, parameter read or
 * URL parse. The source is comment-stripped and import lines are removed so neither can satisfy or break an anchor.
 */
import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { PUBLIC_PATHS } from "@/lib/routes";

const WEB = path.join(__dirname, "../..");
const ROOT_DIR = "app/api/internal/legal-acceptance";
const PREFIX = "/api/internal/legal-acceptance";

const stripJsComments = (t: string): string => t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|\s)\/\/.*$/gm, "$1");
const stripImports = (t: string): string => t.replace(/\bimport\s[^;]*;/g, "");
const code = (t: string): string => stripImports(stripJsComments(t));

function routeFiles(dir: string): string[] {
  const out: string[] = [];
  for (const n of readdirSync(path.join(WEB, dir)).sort()) {
    const rel = `${dir}/${n}`;
    if (statSync(path.join(WEB, rel)).isDirectory()) out.push(...routeFiles(rel));
    else if (n === "route.ts") out.push(rel);
  }
  return out;
}

const LOOKUPS = /createServiceClient|getLegalText|verifyAcceptance|ackState|await ctx\.params|req\.url/;

/** Problems with one handler source (empty when it checks the bearer first). */
export function bearerFirstProblems(src: string): string[] {
  const c = code(src);
  const problems: string[] = [];
  if (!/readNamedBearerSecret\(/.test(c)) problems.push("does not call readNamedBearerSecret(");
  const bearer = c.search(/\bbearerMatches\(/);
  if (bearer < 0) {
    problems.push("does not call bearerMatches(");
    return problems;
  }
  const first = c.search(LOOKUPS);
  if (first >= 0 && first < bearer) problems.push(`${LOOKUPS.exec(c)![0]} comes before bearerMatches(`);
  return problems;
}

/** The URL path a route file serves, with every dynamic segment replaced by a probe value. */
const urlOf = (rel: string): string => "/" + path.dirname(rel).replace(/^app\//, "").replace(/\[[^\]]+\]/g, "probe");

describe("every handler under app/api/internal/legal-acceptance checks the bearer first", () => {
  const files = routeFiles(ROOT_DIR);

  it("finds the verify route (an empty census fails)", () => {
    expect(files).toContain(`${ROOT_DIR}/[key]/route.ts`);
  });
  it.each(files)("%s: reads the named secret and calls bearerMatches before any lookup, registry read, param read or URL parse", (rel) => {
    expect(bearerFirstProblems(readFileSync(path.join(WEB, rel), "utf8"))).toEqual([]);
  });
  it.each(files)("%s: is reachable without a session through the PUBLIC_PATHS prefix entry, as the middleware evaluates it", (rel) => {
    const isPublic = (p: string): boolean => PUBLIC_PATHS.some((e) => p === e || p.startsWith(e + "/"));
    expect(isPublic(urlOf(rel)), urlOf(rel)).toBe(true);
  });

  it("the predicate used here is the one in middleware.ts (anchored on its source)", () => {
    const mw = stripJsComments(readFileSync(path.join(WEB, "middleware.ts"), "utf8"));
    expect(mw).toContain('PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"))');
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

describe("negative controls: the census detects each way a handler can check late or not at all", () => {
  const GOOD = `
    import { bearerMatches } from "@/lib/internal-auth";
    import { createServiceClient } from "@/lib/supabase/service";
    export async function GET(req: Request, ctx: { params: Promise<{ key: string }> }) {
      const token = readNamedBearerSecret("LEGAL_ACCEPTANCE_VERIFY_TOKEN");
      if (!token || !bearerMatches(req.headers.get("authorization"), token)) return new Response(null, { status: 401 });
      const { key } = await ctx.params;
      return Response.json({ key, u: new URL(req.url).search, s: createServiceClient() });
    }`;
  it("the good shape has no problems", () => {
    expect(bearerFirstProblems(GOOD)).toEqual([]);
  });
  it.each([
    ["no bearer check", GOOD.replace("!bearerMatches(req.headers.get(\"authorization\"), token)", "false").replace("bearerMatches(req.headers.get(\"authorization\"), token)", "true"), "does not call bearerMatches("],
    ["no named secret", GOOD.replace("readNamedBearerSecret(", "somethingElse("), "does not call readNamedBearerSecret("],
    ["params read first", GOOD.replace("const token", "const { key: k0 } = await ctx.params;\n      const token"), "comes before bearerMatches("],
    ["URL parsed first", GOOD.replace("const token", "const u0 = new URL(req.url);\n      const token"), "comes before bearerMatches("],
    ["service client first", GOOD.replace("const token", "const c0 = createServiceClient();\n      const token"), "comes before bearerMatches("],
    ["registry read first", GOOD.replace("const token", "getLegalText('x');\n      const token"), "comes before bearerMatches("],
  ])("%s", (_label, src, want) => {
    expect(src).not.toBe(GOOD);
    expect(bearerFirstProblems(src).join("|")).toContain(want);
  });
  it("a comment that names bearerMatches( does not satisfy the anchor", () => {
    const commented = GOOD.replace("if (!token || !bearerMatches(req.headers.get(\"authorization\"), token))", "// bearerMatches(\n      if (!token)");
    expect(bearerFirstProblems(commented)).toContain("does not call bearerMatches(");
  });
});
