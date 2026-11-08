/**
 * #12429 (ADR-319 amendment 2026-11-08): who may call `legal_acceptance_hash_counts`.
 *
 * The RPC is granted to `service_role`, so ANY server module that holds the service key can call it, including a module outside
 * the bearer-gated `app/api/internal/legal-acceptance` tree. The database does not narrow that; this census does, as a
 * code-review and test boundary. It walks the tracked TypeScript/JavaScript sources of apps/web-platform (comments blanked by
 * the TypeScript parser; test, e2e, supabase and node_modules paths excluded) and asserts:
 *  - the RPC name appears as a quoted literal (or as a `/rpc/<name>` REST path) in exactly one non-test file: server/legal-acceptance/service.ts;
 *  - the wrapper `hashCounts` is referenced by exactly two files: service.ts (its definition) and the counts route.
 * LIMIT, stated: a name assembled at run time ("legal_acceptance_" + "hash_counts") or an RPC issued from outside apps/web-platform
 * is not seen; the review checklist for a new service-key caller covers those.
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
const EXCLUDED = /(?:^|\/)(?:test|tests|e2e|__tests__|supabase|node_modules|\.next)\/|\.(?:test|spec)\.[a-z]+$/;
/** The RPC name as a quoted literal, or as the REST path `/rpc/<name>`. */
const NAME_SITE = /(["'`])legal_acceptance_hash_counts\1|\/rpc\/legal_acceptance_hash_counts\b/;
const WRAPPER_SITE = /\bhashCounts\b/;

interface Src {
  rel: string;
  src: string;
}

/** The pure census: which files (relative to apps/web-platform) name the RPC, and which reference the wrapper. */
export function census(files: Src[]): { names: string[]; wrapper: string[] } {
  const names: string[] = [];
  const wrapper: string[] = [];
  for (const f of files) {
    if (!SOURCE_EXT.test(f.rel) || EXCLUDED.test(f.rel)) continue;
    const code = stripComments(f.src, f.rel);
    if (NAME_SITE.test(code)) names.push(f.rel);
    if (WRAPPER_SITE.test(code)) wrapper.push(f.rel);
  }
  return { names: names.sort(), wrapper: wrapper.sort() };
}

/** Every tracked file under apps/web-platform (git ls-files), read from disk. Throws when git cannot list (a blind walk must not pass). */
function trackedSources(): Src[] {
  const r = spawnSync("git", ["ls-files", "-z", "--", "."], { cwd: WEB, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (r.status !== 0) throw new Error(`git ls-files failed (status ${r.status}): ${r.stderr}`);
  const rels = r.stdout.split("\0").filter((x) => x.length > 0);
  if (rels.length < 100) throw new Error(`git ls-files listed only ${rels.length} files: the census would be blind`);
  return rels.filter((rel) => SOURCE_EXT.test(rel) && !EXCLUDED.test(rel)).map((rel) => ({ rel, src: readFileSync(path.join(WEB, rel), "utf8") }));
}

describe("legal_acceptance_hash_counts has exactly one caller", () => {
  const files = trackedSources();

  it("the walk reads real sources (service.ts, the counts route and a non-trivial number of other files)", () => {
    const rels = files.map((f) => f.rel);
    expect(rels).toContain(SERVICE);
    expect(rels).toContain(COUNTS_ROUTE);
    expect(files.length).toBeGreaterThan(200);
  });

  it("the RPC name is a literal in service.ts and in no other non-test source", () => {
    expect(census(files).names).toEqual([SERVICE]);
  });

  it("the wrapper hashCounts is referenced only by service.ts (definition) and the counts route", () => {
    expect(census(files).wrapper).toEqual([COUNTS_ROUTE, SERVICE].sort());
  });
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
  it("test, e2e and supabase paths and non-source extensions are out of scope", () => {
    const code = 'service.rpc("legal_acceptance_hash_counts")';
    for (const rel of ["test/x.ts", "apps/test/x.ts", "e2e/x.ts", "supabase/x.ts", "server/x.test.ts", "server/x.spec.ts", "server/notes.md", "node_modules/p/x.js"]) {
      expect(census([...base, { rel, src: code }]), rel).toEqual(census(base));
    }
  });
  it("an empty file set finds nothing (so the real walk asserting a non-empty answer cannot pass blind)", () => {
    expect(census([])).toEqual({ names: [], wrapper: [] });
  });
});
