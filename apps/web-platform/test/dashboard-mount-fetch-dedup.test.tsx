import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// ADR-067 mount-fetch contract (issue #9178 / Guard 1): every mount-time
// `/api/*` GET on the dashboard shell routes through `useSWR` + a `swrKeys.*`
// tuple so SWR's per-key in-flight coalescing + `dedupingInterval` own dedup.
// A raw `fetch()` GET on the mount path is the defect class — it cannot join
// an SWR flight and produced the observed same-mount duplicate fan-out
// (active-repo x3-4, foundation-status x3, memberships/inbox/today x2).
//
// This is a CENSUS, not a hand list: the mount-surface set is enumerated
// structurally from the filesystem, every `fetch("/api/"` call site inside it
// is classified, and any site that is neither (a) an explicit non-GET mutation
// nor (b) inside a fetcher wired to `useSWR` in the same module is a
// violation. A new raw-GET mount consumer fails this suite naming the file.

const ROOT = dirname(dirname(fileURLToPath(import.meta.url))); // apps/web-platform

// The mount-surface set (plan Guard Contract "Assembly"): the three shell
// entry modules + every components/dashboard/** and hooks/** module reachable
// at mount, plus the key registry. Route-primary content pages under
// app/(dashboard)/dashboard/*/ are excluded — their GETs fire on that route
// only and are not part of the every-navigation mount burst.
const SCAN_FILES = [
  "app/(dashboard)/layout.tsx",
  "app/(dashboard)/dashboard-shell.tsx",
  "app/(dashboard)/dashboard/page.tsx",
  "lib/swr-config.ts",
];
const SCAN_DIRS = ["components/dashboard", "hooks"];

function walk(dir: string, acc: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) walk(p, acc);
    else if (/\.(tsx|ts)$/.test(p) && !/\.test\.tsx?$/.test(p)) acc.push(p);
  }
  return acc;
}

const FILES = [
  ...SCAN_FILES.map((f) => join(ROOT, f)),
  ...SCAN_DIRS.flatMap((d) => walk(join(ROOT, d))),
];

/** Strip line + block comments so a `fetch("/api/` mention in prose can never
 * satisfy or trip the census (cq-assert-anchor-not-bare-token). */
function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, (m) => " ".repeat(m.length))
    .replace(/\/\/[^\n]*/g, (m) => " ".repeat(m.length));
}

/** Return the end offset (exclusive) of the balanced-paren group that opens
 * at `openIdx` (src[openIdx] === "("), skipping strings/template literals. */
function callEnd(src: string, openIdx: number): number {
  let depth = 0;
  for (let i = openIdx; i < src.length; i++) {
    const c = src[i];
    if (c === '"' || c === "'" || c === "`") {
      const q = c;
      i++;
      while (i < src.length && src[i] !== q) {
        if (src[i] === "\\") i++;
        i++;
      }
      continue;
    }
    if (c === "(") depth++;
    else if (c === ")") {
      depth--;
      if (depth === 0) return i + 1;
    }
  }
  return src.length;
}

/** Same balanced scan for a `{` group opened at `openIdx`. */
function braceEnd(src: string, openIdx: number): number {
  let depth = 0;
  for (let i = openIdx; i < src.length; i++) {
    const c = src[i];
    if (c === '"' || c === "'" || c === "`") {
      const q = c;
      i++;
      while (i < src.length && src[i] !== q) {
        if (src[i] === "\\") i++;
        i++;
      }
      continue;
    }
    if (c === "{") depth++;
    else if (c === "}") {
      depth--;
      if (depth === 0) return i + 1;
    }
  }
  return src.length;
}

interface FetchSite {
  file: string;
  line: number;
  kind: "mutation" | "swr-fetcher" | "raw-get";
}

/** Classify every `fetch(` call site whose first argument is an `/api/` URL. */
export function censusMountFetches(src: string, file: string): FetchSite[] {
  const clean = stripComments(src);
  const sites: FetchSite[] = [];

  // Identifier declarations (const X = … / function X …) with their spans —
  // used to name the enclosing function of each fetch site. A `const`/`let`
  // span runs to its terminating `;` at depth 0; a `function` span is its
  // balanced-brace body.
  const decls: { name: string; start: number; end: number }[] = [];
  for (const m of clean.matchAll(
    /(const|let|function)\s+([A-Za-z_$][\w$]*)/g,
  )) {
    const [, kw, name] = m;
    let end = clean.length;
    if (kw === "function") {
      // The body `{` follows the param list's balanced `)` AND any `: Type`
      // return annotation. Scan with `<>` depth so `Promise<{…}>` braces are
      // skipped (an `=>` inside a type would fake-close `<>` — suppressed by
      // treating `=>` as a unit).
      const parenIdx = clean.indexOf("(", m.index + m[0].length);
      const afterParams =
        parenIdx >= 0 ? callEnd(clean, parenIdx) : m.index + m[0].length;
      let angle = 0;
      let braceIdx = -1;
      for (let i = afterParams; i < clean.length; i++) {
        const c = clean[i];
        if (c === "=" && clean[i + 1] === ">") {
          i++;
          continue;
        }
        if (c === "<") angle++;
        else if (c === ">") angle = Math.max(0, angle - 1);
        else if (c === "{" && angle === 0) {
          braceIdx = i;
          break;
        } else if (c === ";" && angle === 0) break;
      }
      if (braceIdx >= 0) end = braceEnd(clean, braceIdx);
    } else {
      let depth = 0;
      for (let i = m.index; i < clean.length; i++) {
        const c = clean[i];
        if (c === '"' || c === "'" || c === "`") {
          const q = c;
          i++;
          while (i < clean.length && clean[i] !== q) {
            if (clean[i] === "\\") i++;
            i++;
          }
          continue;
        }
        if (c === "(" || c === "{" || c === "[") depth++;
        else if (c === ")" || c === "}" || c === "]") depth--;
        else if (c === ";" && depth === 0) {
          end = i;
          break;
        }
      }
    }
    // Only function-valued declarations can be fetchers (a plain
    // `const r = await fetch(...)` inside a fetcher must not shadow the
    // enclosing function name).
    const isFunction =
      kw === "function" ||
      /=>|function\s*\(/.test(clean.slice(m.index, end));
    if (isFunction) decls.push({ name, start: m.index, end });
  }

  // useSWR(…) call spans (inline fetchers) + the identifiers passed as the
  // fetcher argument (named fetchers).
  const swrSpans: { start: number; end: number }[] = [];
  const fetcherNames = new Set<string>();
  for (const m of clean.matchAll(/useSWR(?:<[^>\n]*>)?\s*\(/g)) {
    const openIdx = m.index + m[0].length - 1;
    const end = callEnd(clean, openIdx);
    swrSpans.push({ start: m.index, end });
    // Second argument's leading identifier, if any.
    const args = clean.slice(openIdx + 1, end - 1);
    const comma = args.indexOf(",");
    if (comma >= 0) {
      const second = args.slice(comma + 1).trim();
      const nameM = /^([A-Za-z_$][\w$]*)\s*[,)]/.exec(second + ")");
      if (nameM) fetcherNames.add(nameM[1]);
    }
  }

  const FETCH_RE = /fetch\(\s*["'`]\/api\//g;
  for (const m of clean.matchAll(FETCH_RE)) {
    const pos = m.index;
    const line = clean.slice(0, pos).split("\n").length;
    const openIdx = clean.indexOf("(", pos);
    const end = callEnd(clean, openIdx);
    const callText = clean.slice(pos, end);

    // Explicit non-GET method → mutation, not in the property's scope.
    const methodM = /method:\s*["'`]([A-Za-z]+)["'`]/.exec(callText);
    if (methodM && methodM[1].toUpperCase() !== "GET") {
      sites.push({ file, line, kind: "mutation" });
      continue;
    }

    // Inside a `useSWR(` argument list → inline fetcher.
    if (swrSpans.some((s) => pos > s.start && pos < s.end)) {
      sites.push({ file, line, kind: "swr-fetcher" });
      continue;
    }

    // Inside the innermost declaration whose span contains the site → check
    // whether that identifier is wired to a useSWR in this module.
    const enclosing = decls
      .filter((d) => d.start < pos && pos < d.end)
      .sort((a, b) => b.start - a.start)[0];
    if (enclosing && fetcherNames.has(enclosing.name)) {
      sites.push({ file, line, kind: "swr-fetcher" });
      continue;
    }

    sites.push({ file, line, kind: "raw-get" });
  }
  return sites;
}

describe("dashboard mount-fetch dedup census (ADR-067 contract, #9178)", () => {
  const results = FILES.flatMap((f) =>
    censusMountFetches(readFileSync(f, "utf8"), f.slice(ROOT.length + 1)),
  );

  it("enumerates a non-empty mount surface (non-vacuity)", () => {
    expect(FILES.length).toBeGreaterThan(10);
    // The census must actually SEE fetch sites — a neutered pattern that
    // matches nothing would pass vacuously. These known swr-routed fetchers
    // must classify as compliant, proving the scan reaches real sites.
    const routed = results.filter((r) => r.kind === "swr-fetcher");
    expect(routed.length).toBeGreaterThanOrEqual(3);
    expect(
      routed.some((r) => r.file === "app/(dashboard)/dashboard/page.tsx"),
    ).toBe(true);
    expect(
      routed.some((r) => r.file === "hooks/use-kb-layout-state.tsx"),
    ).toBe(true);
  });

  it("no raw `fetch()` GET on the dashboard mount path", () => {
    const violations = results
      .filter((r) => r.kind === "raw-get")
      .map((r) => `${r.file}:${r.line}`);
    expect(violations).toEqual([]);
  });

  it("mutation matrix: explicit non-GET calls classify as mutations, not violations", () => {
    const mutations = results.filter((r) => r.kind === "mutation");
    expect(mutations.length).toBeGreaterThanOrEqual(2);
  });
});

describe("censusMountFetches — classifier self-test", () => {
  it("flags a raw mount GET", () => {
    const src = `export function X() { useEffect(() => { fetch("/api/x").then(r => r.json()); }, []); }`;
    const v = censusMountFetches(src, "probe.ts").filter(
      (s) => s.kind === "raw-get",
    );
    expect(v).toHaveLength(1);
  });

  it("passes an SWR-wired named fetcher", () => {
    const src = `const load = useCallback(async () => { const r = await fetch("/api/x"); return r.json(); }, []);\nuseSWR(key, load);`;
    expect(censusMountFetches(src, "p.ts")[0].kind).toBe("swr-fetcher");
  });

  it("passes an inline useSWR fetcher", () => {
    const src = `useSWR(key, async () => { const r = await fetch("/api/x"); return r.json(); });`;
    expect(censusMountFetches(src, "p.ts")[0].kind).toBe("swr-fetcher");
  });

  it("passes an explicit POST mutation", () => {
    const src = `function save() { return fetch("/api/x", { method: "POST" }); }`;
    expect(censusMountFetches(src, "p.ts")[0].kind).toBe("mutation");
  });

  it("ignores fetch mentions inside comments", () => {
    const src = `// fetch("/api/x") was here\n/* fetch("/api/y") */\nconst a = 1;`;
    expect(censusMountFetches(src, "p.ts")).toHaveLength(0);
  });
});
