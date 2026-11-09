/**
 * #12429 (ADR-319 amendment 2026-11-08): who may call `legal_acceptance_hash_counts`.
 *
 * The RPC is granted to `service_role`, so ANY server module that holds the service key can call it, including a module outside
 * the bearer-gated `app/api/internal/legal-acceptance` tree. The database does not narrow that; this census does, as a
 * code-review and test boundary. It walks the tracked TypeScript/JavaScript sources of apps/web-platform (comments blanked by
 * the TypeScript parser). Excluded: the app-root directories test/, e2e/ and supabase/ (migrations), any *.test.* or *.spec.*
 * file, and node_modules/.next at any depth. The exclusions are ROOT-anchored on purpose: lib/supabase/ holds the service-key
 * client and is in scope, as are lib/test, server/test and route directories named test, e2e or supabase below app/api. It asserts:
 *  - the RPC name appears as a quoted literal (or as a `/rpc/<name>` REST path) in exactly one non-test file: server/legal-acceptance/service.ts;
 *  - the wrapper `hashCounts` is referenced by exactly two files: service.ts (its definition) and the counts route.
 * LIMIT, stated: a name assembled at run time ("legal_acceptance_" + "hash_counts") or an RPC issued from outside apps/web-platform
 * is not seen; the review checklist for a new service-key caller covers those. A file that is not tracked by git is not walked.
 * The self-tests below run the same census over synthetic file sets, so an empty or blind walk cannot read as "all clear".
 */
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { stripComments } from "../helpers/strip-comments";

const WEB = path.join(__dirname, "../..");

const SERVICE = "server/legal-acceptance/service.ts";
const COUNTS_ROUTE = "app/api/internal/legal-acceptance/[key]/counts/route.ts";

const SOURCE_EXT = /\.(?:ts|tsx|mts|cts|js|jsx|mjs|cjs)$/;
/** Root-anchored (relative to apps/web-platform): only the real top-level test/e2e/supabase directories, never a nested segment of that name. */
const EXCLUDED = /^(?:test|e2e|supabase)\/|(?:^|\/)(?:node_modules|\.next)\/|\.(?:test|spec)\.[a-z]+$/;
/** The RPC name as a quoted literal, or as the REST path `/rpc/<name>`. */
const NAME_SITE = /(["'`])legal_acceptance_hash_counts\1|\/rpc\/legal_acceptance_hash_counts\b/;
const WRAPPER_SITE = /\bhashCounts\b/;

interface Src {
  rel: string;
  src: string;
}

/** The one scope decision: TypeScript/JavaScript sources outside the excluded paths. */
export function inScope(files: Src[]): Src[] {
  return files.filter((f) => SOURCE_EXT.test(f.rel) && !EXCLUDED.test(f.rel));
}

/** The pure census: which files (relative to apps/web-platform) name the RPC, and which reference the wrapper. */
export function census(files: Src[]): { names: string[]; wrapper: string[] } {
  const names: string[] = [];
  const wrapper: string[] = [];
  for (const f of inScope(files)) {
    const code = stripComments(f.src, f.rel);
    if (NAME_SITE.test(code)) names.push(f.rel);
    if (WRAPPER_SITE.test(code)) wrapper.push(f.rel);
  }
  return { names: names.sort(), wrapper: wrapper.sort() };
}

/** Every tracked file under apps/web-platform (git ls-files), UNFILTERED (the scope is decided once, in inScope; each file is read on first use). Throws when git cannot list (a blind walk must not pass). */
function trackedSources(): Src[] {
  const r = spawnSync("git", ["ls-files", "-z", "--", "."], { cwd: WEB, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (r.status !== 0) throw new Error(`git ls-files failed (status ${r.status}): ${r.stderr}`);
  const rels = r.stdout.split("\0").filter((x) => x.length > 0);
  if (rels.length < 100) throw new Error(`git ls-files listed only ${rels.length} files: the census would be blind`);
  // `src` is read on first use, so only the files the census keeps are opened (a tracked symlink or a binary is never read).
  return rels.map((rel) => ({
    rel,
    get src() {
      return readFileSync(path.join(WEB, rel), "utf8");
    },
  }));
}

describe("legal_acceptance_hash_counts has exactly one caller", () => {
  const files = trackedSources();
  // The parse of the whole tree is the slow part: run it once, in whichever test needs it first.
  let real: ReturnType<typeof census> | undefined;
  const realCensus = () => (real ??= census(files));

  it("the walk reads real sources (service.ts, the counts route and a non-trivial number of other files)", () => {
    const rels = inScope(files).map((f) => f.rel);
    expect(rels).toContain(SERVICE);
    expect(rels).toContain(COUNTS_ROUTE);
    expect(rels.length).toBeGreaterThan(200);
  });

  it("the walk's scope matches the real tree: lib/supabase (the service-key client) is in scope, the top-level test/ and e2e/ are not", () => {
    const rels = inScope(files).map((f) => f.rel);
    expect(rels).toContain("lib/supabase/service.ts");
    expect(files.map((f) => f.rel).some((r) => r.startsWith("test/") && SOURCE_EXT.test(r))).toBe(true);
    expect(rels.filter((r) => r.startsWith("test/") || r.startsWith("e2e/") || r.startsWith("supabase/"))).toEqual([]);
  });

  it("the RPC name is a literal in service.ts and in no other non-test source", () => {
    expect(realCensus().names).toEqual([SERVICE]);
  }, 60_000);

  it("the wrapper hashCounts is referenced only by service.ts (definition) and the counts route", () => {
    expect(realCensus().wrapper).toEqual([COUNTS_ROUTE, SERVICE].sort());
  }, 60_000);
});

describe("census self-tests (synthetic file sets)", () => {
  const base: Src[] = [
    { rel: SERVICE, src: 'export async function hashCounts() { const fn = "legal_acceptance_hash_counts"; return fn; }' },
    { rel: COUNTS_ROUTE, src: 'import { hashCounts } from "@/server/legal-acceptance/service"; export const x = hashCounts;' },
  ];
  it("control: the honest set yields exactly the two expected answers", () => {
    expect(census(base)).toEqual({ names: [SERVICE], wrapper: [COUNTS_ROUTE, SERVICE].sort() });
  });
  it.each([
    ["a second module calling the RPC with a double-quoted literal", 'service.rpc("legal_acceptance_hash_counts", { p_key: k })'],
    ["a single-quoted literal", "client.rpc('legal_acceptance_hash_counts', {})"],
    ["a template literal", "client.rpc(`legal_acceptance_hash_counts`, {})"],
    ["a REST path", "fetch(`${base}/rest/v1/rpc/legal_acceptance_hash_counts`, { method: 'POST' })"],
  ])("%s is found", (_label, code) => {
    expect(census([...base, { rel: "server/other/rogue.ts", src: code }]).names).toEqual(["server/other/rogue.ts", SERVICE].sort());
  });
  it("a second importer of hashCounts is found", () => {
    expect(census([...base, { rel: "app/api/other/route.ts", src: 'import { hashCounts } from "@/server/legal-acceptance/service";' }]).wrapper).toEqual(
      ["app/api/other/route.ts", COUNTS_ROUTE, SERVICE].sort(),
    );
  });
  it("a mention in a comment is not a call (comments are blanked by the parser, not a regex)", () => {
    const f: Src = { rel: "server/other/doc.ts", src: '// service.rpc("legal_acceptance_hash_counts")\n/* hashCounts(service, { key }) */\nexport const a = "https://example.test/x"; // legal_acceptance_hash_counts' };
    expect(census([...base, f])).toEqual(census(base));
  });
  it("the real top-level test, e2e and supabase directories, test/spec files and non-source extensions are out of scope", () => {
    const code = 'service.rpc("legal_acceptance_hash_counts")';
    for (const rel of ["test/x.ts", "test/legal-acceptance/y.ts", "e2e/x.ts", "supabase/x.ts", "server/x.test.ts", "server/x.spec.ts", "server/notes.md", "node_modules/p/x.js", "app/node_modules/p/x.js", ".next/x.js"]) {
      expect(census([...base, { rel, src: code }]), rel).toEqual(census(base));
    }
  });
  it.each([
    ["lib/supabase/x.ts"],
    ["lib/supabase/service-rogue.ts"],
    ["server/test/x.ts"],
    ["lib/test/x.ts"],
    ["apps/test/x.ts"],
    ["app/api/webhooks/supabase/route.ts"],
    ["app/api/test/route.ts"],
    ["app/api/e2e/seed/route.ts"],
    ["server/__tests__/x.ts"],
  ])("a caller at %s is FOUND (an exclusion segment below the app root hides nothing)", (rel) => {
    const found = census([...base, { rel, src: 'service.rpc("legal_acceptance_hash_counts")' }]);
    expect(found.names).toEqual([rel, SERVICE].sort());
  });
  it("an empty file set finds nothing (so the real walk asserting a non-empty answer cannot pass blind)", () => {
    expect(census([])).toEqual({ names: [], wrapper: [] });
  });
});
