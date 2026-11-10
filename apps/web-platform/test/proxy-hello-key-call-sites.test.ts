import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";

import { stripComments } from "./helpers/strip-comments";

// #8211 (ADR-323 Decision 9) — Guard 1 at the level of the SET of call sites: the accept-only slot is verify-only.
// The behaviour rows (session-proxy-hello.test.ts) pin the one sender they drive; this scan pins that it is the only
// one. (1) Exactly one production call of signProxyHello outside proxy-hello.ts, and its key argument is a const bound
// to exactly `loadProxyHelloKeys().current`. (2) `acceptAlso` and the slot's env name appear in production code only in
// the files that need them. A new signer, `acceptAlso ?? current`, or an env-gated slot at the call site turns it RED,
// including an edit that only takes effect under NODE_ENV=production (the behaviour rows run under NODE_ENV=test).
// Comments are blanked by the TypeScript parser first, so prose naming these identifiers never counts.

const ROOT = join(__dirname, "..");
const PROD_DIRS = ["server", "lib", "app"];

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name === "node_modules" || e.name.startsWith(".")) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p));
    else if (/\.tsx?$/.test(e.name) && !/\.d\.ts$/.test(e.name) && !/\.test\.tsx?$/.test(e.name)) out.push(p);
  }
  return out;
}

const ALL_FILES = PROD_DIRS.flatMap((d) => walk(join(ROOT, d)));
// Only a file whose raw text names a scanned token can name it once comments are blanked, so only those are parsed
// (parsing every file costs ~20 s). The four relay files are always kept for the vacuity floor.
const TOKENS = /signProxyHello|acceptAlso|PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO|loadProxyHelloKeys/;

/** Production sources naming a scanned token, comment-stripped, keyed by path relative to apps/web-platform. */
const SOURCES: ReadonlyMap<string, string> = new Map(
  ALL_FILES.map((p) => [p, readFileSync(p, "utf8")] as const)
    .filter(([, raw]) => TOKENS.test(raw))
    .map(([p, raw]) => [relative(ROOT, p), stripComments(raw, p)]),
);

const count = (src: string, re: RegExp) => (src.match(new RegExp(re.source, "g")) ?? []).length;
const filesMatching = (re: RegExp) =>
  [...SOURCES]
    .filter(([, src]) => count(src, re) > 0)
    .map(([f]) => f)
    .sort();

describe("Guard 1 call sites: the accept-only slot never signs (#8211)", () => {
  it("the scan sees the production tree (vacuity floor: the known files are present and non-empty)", () => {
    expect(ALL_FILES.length).toBeGreaterThan(100);
    for (const f of ["server/proxy-hello.ts", "server/proxy-tls.ts", "server/session-proxy.ts", "server/index.ts"]) {
      expect(SOURCES.get(f)?.length ?? 0, f).toBeGreaterThan(0);
    }
  });

  it("(1) exactly one production call of signProxyHello( outside proxy-hello.ts, in session-proxy.ts", () => {
    const calls = [...SOURCES]
      .filter(([f]) => f !== "server/proxy-hello.ts")
      .flatMap(([f, src]) => Array.from({ length: count(src, /\bsignProxyHello\s*\(/) }, () => f));
    expect(calls).toEqual(["server/session-proxy.ts"]);
  });

  it("(1) the signer is never aliased or passed around: outside proxy-hello.ts its only other mention is one plain named import", () => {
    const sp = SOURCES.get("server/session-proxy.ts") ?? "";
    expect(count(sp, /\bsignProxyHello\b/)).toBe(2); // the import specifier + the one call
    expect(sp).not.toMatch(/\bsignProxyHello\s+as\b/);
    expect(sp).toMatch(/^import \{[^}]*\bsignProxyHello\b[^}]*\} from "\.\/proxy-hello";$/m);
    const elsewhere = [...SOURCES].filter(([f, src]) => !["server/proxy-hello.ts", "server/session-proxy.ts"].includes(f) && /\bsignProxyHello\b/.test(src));
    expect(elsewhere.map(([f]) => f)).toEqual([]);
  });

  it("(1) the one call's key argument is a const bound to exactly loadProxyHelloKeys().current, bound once in its file", () => {
    const sp = SOURCES.get("server/session-proxy.ts") ?? "";
    const arg = /\bsignProxyHello\(\s*([A-Za-z_$][\w$]*)\s*,/.exec(sp);
    expect(arg, "the first argument is a bare identifier").not.toBeNull();
    const id = (arg as RegExpExecArray)[1];
    // Unique within the file: one binding of the identifier (const/let/var, a parameter or a destructure would add one).
    expect(count(sp, new RegExp(`\\b(?:const|let|var)\\s+${id}\\b`))).toBe(1);
    expect(count(sp, new RegExp(`\\b${id}\\s*=(?!=)`))).toBe(1);
    expect(count(sp, new RegExp(`[(,]\\s*${id}\\s*[),:=]`))).toBe(1); // only the signer call's own `(id,`
    // Anchored on the whole statement: `acceptAlso ?? current`, `(env && acceptAlso) || current`, a `!` or a cast fail.
    expect(sp).toMatch(new RegExp(`^\\s*const ${id} = loadProxyHelloKeys\\(\\)\\.current;\\s*$`, "m"));
  });

  it("(2) `acceptAlso` is referenced in production code only by the verifier, the loader and the fingerprint line", () => {
    expect(filesMatching(/\bacceptAlso\b/)).toEqual(["server/proxy-hello.ts", "server/proxy-tls.ts", "server/session-proxy.ts"]);
  });

  it("(2) in session-proxy.ts every `acceptAlso` sits on the one fingerprint line (2 references, 1 line)", () => {
    const sp = SOURCES.get("server/session-proxy.ts") ?? "";
    expect(count(sp, /\bacceptAlso\b/)).toBe(2);
    const lines = sp.split("\n").filter((l) => /\bacceptAlso\b/.test(l));
    expect(lines.map((l) => l.trim())).toEqual([
      'const acceptAlsoFp = helloKeys.acceptAlso === null ? "none" : helloKeyFingerprint(helloKeys.acceptAlso);',
    ]);
  });

  it("(2) in proxy-hello.ts the signer's body never names `acceptAlso` (only the type and the verifier do)", () => {
    const ph = SOURCES.get("server/proxy-hello.ts") ?? "";
    const start = ph.indexOf("export function signProxyHello(");
    expect(start).toBeGreaterThanOrEqual(0);
    const body = ph.slice(start, ph.indexOf("\n}\n", start));
    expect(body).toContain("JSON.stringify");
    expect(body).not.toMatch(/\bacceptAlso\b/);
  });

  it("(2) the slot's env name appears in production code only in the loader and the sensitive-key list", () => {
    expect(filesMatching(/\bPROXY_HELLO_HMAC_KEY_ACCEPT_ALSO\b/)).toEqual(["server/proxy-tls.ts", "server/sensitive-keys.ts"]);
  });
});
