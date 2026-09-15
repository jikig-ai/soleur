import { describe, it, expect, vi, afterEach } from "vitest";
import {
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// Guard 1 (#7884): the paging contract between the Better Stack monitor on
// app.soleur.ai/health and the body that endpoint serves.
//
// Property: exactly one Terraform-declared betteruptime_monitor watches the
// health URL; its type is the committed EXPECTED_BRANCH; on the keyword branch
// its required keyword occurs in the served body exactly when the Supabase
// check succeeds; on either branch /health answers HTTP 200 in every database
// state. Rationale for the alarm itself: ADR-222 and the comment on
// betteruptime_monitor.app_health in apps/web-platform/infra/uptime-alerts.tf.
//
// The keyword is READ from the declaration, never copied here, so the two
// cannot drift apart silently. The monitor type is the one thing deliberately
// NOT read from the declaration: EXPECTED_BRANCH is set from the pre-merge
// vendor probe (plan Phase 0.2), so downgrading the alarm to `status` needs an
// edit to this constant that a reviewer sees.

vi.mock("@/lib/supabase/service", () => ({
  serverUrl: () => "https://test.supabase.co",
}));

// session-metrics pulls in ws-handler, which builds a service client at module
// load. Stubbed so only buildHealthResponse's Supabase check is exercised.
vi.mock("../../server/session-metrics", () => ({
  getActiveSessionCount: () => 0,
  getActiveWorkspaceCount: () => 0,
}));

type Branch = "keyword" | "status";

/** Set from the Phase 0.2 probe decision. Never derive it from the .tf. */
const EXPECTED_BRANCH: Branch = "keyword";

const APP_ROOT = path.join(__dirname, "..", "..");
const INFRA_DIR = path.join(APP_ROOT, "infra");
const INDEX_PATH = path.join(APP_ROOT, "server", "index.ts");
const HEALTH_PATH = path.join(APP_ROOT, "server", "health.ts");
const SESSION_METRICS_PATH = path.join(APP_ROOT, "server", "session-metrics");

const HEALTH_URL = "https://app.soleur.ai/health";

interface Violation {
  rule: string;
}

interface ContractInput {
  tfTexts: string[];
  indexText: string;
  connectedBody: string;
  failedBodies: string[];
  expectedBranch: Branch;
}

// ── HCL helpers (no HCL parser in the toolchain; source-text precedent:
// test/seo-config-rules.test.ts) ─────────────────────────────────────────────

/** Strip `#` and `//` line comments, quote- and escape-aware. */
function stripHclLineComment(line: string): string {
  let inStr = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inStr && c === "\\") {
      i++;
      continue;
    }
    if (c === '"') {
      inStr = !inStr;
      continue;
    }
    if (!inStr && c === "#") return line.slice(0, i);
    if (!inStr && c === "/" && line[i + 1] === "/") return line.slice(0, i);
  }
  return line;
}

function stripHclComments(text: string): string {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map(stripHclLineComment)
    .join("\n");
}

/** Brace-matched body (between the braces) of every block opened by `header`. */
function extractBlocks(stripped: string, header: RegExp): string[] {
  const out: string[] = [];
  const re = new RegExp(header.source, "g");
  let m: RegExpExecArray | null;
  while ((m = re.exec(stripped)) !== null) {
    const open = re.lastIndex - 1;
    let depth = 0;
    let inStr = false;
    let end = -1;
    for (let i = open; i < stripped.length; i++) {
      const c = stripped[i];
      if (inStr) {
        if (c === "\\") i++;
        else if (c === '"' || c === "\n") inStr = false;
        continue;
      }
      if (c === '"') inStr = true;
      else if (c === "{") depth++;
      else if (c === "}" && --depth === 0) {
        end = i;
        break;
      }
    }
    if (end === -1) throw new Error(`unbalanced block at offset ${open}`);
    out.push(stripped.slice(open + 1, end));
  }
  return out;
}

/** Top-level (depth-0) `key = value` attributes of a block body. */
function topLevelAttributes(body: string): Map<string, string> {
  const attrs = new Map<string, string>();
  let depth = 0;
  for (const line of body.split("\n")) {
    const m = depth === 0 ? line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/) : null;
    if (m) attrs.set(m[1], m[2]);
    const noStrings = line.replace(/"(?:[^"\\]|\\.)*"/g, '""');
    depth += (noStrings.match(/\{/g) ?? []).length;
    depth -= (noStrings.match(/\}/g) ?? []).length;
  }
  return attrs;
}

/** Decode a plain HCL string literal; `null` for anything that is not one. */
function hclStringLiteral(raw: string | undefined): string | null {
  if (raw === undefined) return null;
  const m = raw.match(/^"((?:[^"\\]|\\.)*)"$/);
  if (!m || /(^|[^$])\$\{|(^|[^%])%\{/.test(m[1])) return null;
  return m[1].replace(/\\(u[0-9A-Fa-f]{4}|.)/g, (_, e: string) => {
    if (e.length === 5) return String.fromCharCode(parseInt(e.slice(1), 16));
    return ({ n: "\n", t: "\t", r: "\r" } as Record<string, string>)[e] ?? e;
  });
}

/** Index of the `}` closing the `{` at `open` in RAW HCL (skips strings and line comments). */
function matchHclBrace(text: string, open: number): number {
  let depth = 0;
  let inStr = false;
  for (let i = open; i < text.length; i++) {
    const c = text[i];
    if (inStr) {
      if (c === "\\") i++;
      else if (c === '"' || c === "\n") inStr = false;
      continue;
    }
    if (c === "#" || (c === "/" && text[i + 1] === "/")) {
      while (i < text.length && text[i] !== "\n") i++;
    } else if (c === '"') inStr = true;
    else if (c === "{") depth++;
    else if (c === "}" && --depth === 0) return i;
  }
  return -1;
}

const MONITOR_HEADER = /resource\s+"betteruptime_monitor"\s+"[A-Za-z0-9_-]+"\s*\{/;

/** Every `*.tf` directly in `dir`, sorted by name. Throws on an empty dir. */
function loadInfraTf(dir: string): string[] {
  const files = readdirSync(dir)
    .filter((f) => f.endsWith(".tf"))
    .sort();
  if (files.length === 0) throw new Error(`no *.tf files in ${dir}`);
  return files.map((f) => readFileSync(path.join(dir, f), "utf8"));
}

// ── TS helpers for the /health branch of server/index.ts ─────────────────────

/** Remove `//` and block comments, leaving string and template contents intact. */
function stripTsComments(src: string): string {
  let out = "";
  let quote: string | null = null;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (quote) {
      out += c;
      if (c === "\\") out += src[++i] ?? "";
      else if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === "'" || c === "`") {
      quote = c;
      out += c;
    } else if (c === "/" && src[i + 1] === "/") {
      while (i < src.length && src[i] !== "\n") i++;
      out += "\n";
    } else if (c === "/" && src[i + 1] === "*") {
      const close = src.indexOf("*/", i + 2);
      i = close === -1 ? src.length : close + 1;
    } else {
      out += c;
    }
  }
  return out;
}

/** Index of the delimiter closing the one at `open` (string-aware). */
function matchDelimiter(src: string, open: number): number {
  const opener = src[open];
  const closer = opener === "{" ? "}" : ")";
  let depth = 0;
  let quote: string | null = null;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    if (quote) {
      if (c === "\\") i++;
      else if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === "'" || c === "`") quote = c;
    else if (c === opener) depth++;
    else if (c === closer && --depth === 0) return i;
  }
  return -1;
}

const HEALTH_ANCHOR = /pathname\s*===\s*"\/health"/g;

// ── The checker ───────────────────────────────────────────────────────────────

function checkHealthKeywordContract(input: ContractInput): Violation[] {
  const v: Violation[] = [];

  // (1) Census: every betteruptime_monitor on the health URL, across every file.
  const healthBlocks = input.tfTexts
    .flatMap((t) => extractBlocks(stripHclComments(t), MONITOR_HEADER))
    .map(topLevelAttributes)
    .filter((a) => hclStringLiteral(a.get("url")) === HEALTH_URL);

  if (healthBlocks.length !== 1) {
    v.push({ rule: "census-not-one" });
  } else {
    const attrs = healthBlocks[0];
    const type = hclStringLiteral(attrs.get("monitor_type"));
    if (input.expectedBranch === "keyword" && type !== "keyword") {
      v.push({ rule: "branch-downgraded" });
    } else if (input.expectedBranch === "status" && type !== "status") {
      v.push({ rule: "branch-unexpected" });
    } else if (input.expectedBranch === "keyword") {
      if (!attrs.has("required_keyword")) {
        v.push({ rule: "keyword-missing" });
      } else {
        const keyword = hclStringLiteral(attrs.get("required_keyword"));
        if (keyword === null || keyword === "") {
          v.push({ rule: "keyword-unresolvable" });
        } else {
          // Better Stack's keyword lookup is case-insensitive (vendor docs).
          const kw = keyword.toLowerCase();
          if (!input.connectedBody.toLowerCase().includes(kw)) {
            v.push({ rule: "keyword-absent-connected" });
          }
          if (input.failedBodies.some((b) => b.toLowerCase().includes(kw))) {
            v.push({ rule: "keyword-present-failed" });
          }
        }
      }
    }
  }

  // (3) The single /health branch of server/index.ts.
  const index = stripTsComments(input.indexText);
  const anchors = [...index.matchAll(HEALTH_ANCHOR)];
  if (anchors.length !== 1) {
    v.push({ rule: "health-branch-not-one" });
    return v;
  }
  const open = index.indexOf("{", anchors[0].index);
  const close = open === -1 ? -1 : matchDelimiter(index, open);
  if (close === -1) {
    v.push({ rule: "health-branch-not-one" });
    return v;
  }
  const branch = index.slice(open + 1, close);

  const statuses = [...branch.matchAll(/\bwriteHead\(\s*([^,)]*)/g)].map((m) => m[1].trim());
  if (statuses.length === 0 || statuses.some((s) => s !== "200")) {
    v.push({ rule: "status-not-always-200" });
  }

  const stringifyArgs: string[] = [];
  for (const m of branch.matchAll(/JSON\.stringify\s*\(/g)) {
    const p = m.index + m[0].length - 1;
    const end = matchDelimiter(branch, p);
    stringifyArgs.push(end === -1 ? "," : branch.slice(p + 1, end).trim());
  }
  if (
    stringifyArgs.length !== 1 ||
    !/^[A-Za-z_$][\w$]*$/.test(stringifyArgs[0])
  ) {
    v.push({ rule: "serializer-not-compact" });
  } else {
    const bound = new RegExp(
      `\\b(?:const|let)\\s+${stringifyArgs[0].replace(/\$/g, "\\$")}\\s*=\\s*await\\s+buildHealthResponse\\(\\s*\\)`,
    );
    if (!bound.test(branch)) v.push({ rule: "body-not-health-response" });
  }

  return v;
}

// ── Bodies, built through the real builder with fetch mocked ──────────────────

interface Bodies {
  connectedBody: string;
  failedBodies: string[];
}

type Builder = () => Promise<unknown>;

/** Serialize exactly as the /health branch does: `JSON.stringify(health)` (pinned above). */
async function buildBodies(builder: Builder): Promise<Bodies> {
  const fetchSpy = vi.spyOn(globalThis, "fetch");
  try {
    fetchSpy.mockResolvedValueOnce(new Response("[]", { status: 200 }));
    const connectedBody = JSON.stringify(await builder());
    fetchSpy.mockResolvedValueOnce(new Response("unavailable", { status: 503 }));
    const non2xx = JSON.stringify(await builder());
    fetchSpy.mockRejectedValueOnce(new Error("network unreachable"));
    const thrown = JSON.stringify(await builder());
    return { connectedBody, failedBodies: [non2xx, thrown] };
  } finally {
    fetchSpy.mockRestore();
  }
}

async function realBuilder(): Promise<Builder> {
  const { buildHealthResponse } = await import("../../server/health");
  return buildHealthResponse;
}

async function realInput(overrides: Partial<ContractInput> = {}): Promise<ContractInput> {
  return {
    tfTexts: loadInfraTf(INFRA_DIR),
    indexText: readFileSync(INDEX_PATH, "utf8"),
    ...(await buildBodies(await realBuilder())),
    expectedBranch: EXPECTED_BRANCH,
    ...overrides,
  };
}

// ── Mutation helpers (each asserts it actually changed something) ────────────

function replaceOnce(text: string, find: RegExp | string, repl: string): string {
  const re = typeof find === "string" ? new RegExp(find.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")) : find;
  const hits = text.match(new RegExp(re.source, "g"))?.length ?? 0;
  if (hits !== 1) throw new Error(`mutation anchor ${re} matched ${hits} times, expected 1`);
  return text.replace(re, repl);
}

const APP_HEALTH_HEADER = /resource\s+"betteruptime_monitor"\s+"app_health"\s*\{/;

/** The one real .tf text declaring app_health, and the block's header/brace offsets in it. */
function locateAppHealth(tfTexts: string[]): { owner: number; start: number; open: number; end: number } {
  const owners = tfTexts.flatMap((t, i) => (APP_HEALTH_HEADER.test(t) ? [i] : []));
  if (owners.length !== 1) {
    throw new Error(`betteruptime_monitor.app_health declared in ${owners.length} files, expected 1`);
  }
  const t = tfTexts[owners[0]];
  const start = t.search(APP_HEALTH_HEADER);
  const open = t.indexOf("{", start);
  const end = matchHclBrace(t, open);
  if (end === -1) throw new Error("app_health block is unbalanced");
  return { owner: owners[0], start, open, end };
}

/** Apply `edit` to the app_health block body inside whichever real .tf declares it. */
function mutateAppHealth(tfTexts: string[], edit: (block: string) => string): string[] {
  const { owner, open, end } = locateAppHealth(tfTexts);
  return tfTexts.map((t, i) => {
    if (i !== owner) return t;
    const body = t.slice(open + 1, end);
    const edited = edit(body);
    if (edited === body) throw new Error("app_health mutation changed nothing");
    return t.slice(0, open + 1) + edited + t.slice(end);
  });
}

function withTempTfDir(files: Record<string, string>, fn: (dir: string) => string[]): string[] {
  const dir = mkdtempSync(path.join(tmpdir(), "health-keyword-contract-"));
  try {
    for (const [name, text] of Object.entries(files)) writeFileSync(path.join(dir, name), text);
    return fn(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const KEYWORD_ATTR = /required_keyword\s*=\s*"(?:[^"\\]|\\.)*"/;
const TYPE_ATTR = /monitor_type\s*=\s*"keyword"/;

const SECOND_HEALTH_MONITOR = `
resource "betteruptime_monitor" "app_health_shadow" {
  monitor_type = "status"
  url          = "${HEALTH_URL}"
}
`;

// ── Guard 1 matrix ────────────────────────────────────────────────────────────

interface Row {
  id: string;
  mutation: string;
  expected: string[];
  run: () => Promise<Violation[]>;
}

const ROWS: Row[] = [
  {
    id: "1",
    mutation: "required_keyword gains a space after the colon",
    expected: ["keyword-absent-connected"],
    run: async () => {
      const base = await realInput();
      const tfTexts = mutateAppHealth(base.tfTexts, (b) =>
        replaceOnce(b, KEYWORD_ATTR, 'required_keyword = "\\"supabase\\": \\"connected\\""'),
      );
      return checkHealthKeywordContract({ ...base, tfTexts });
    },
  },
  {
    id: "2",
    mutation: 'injected connected body carries "supabase":"ok"',
    expected: ["keyword-absent-connected"],
    run: async () => {
      const base = await realInput();
      const connectedBody = replaceOnce(base.connectedBody, '"supabase":"connected"', '"supabase":"ok"');
      return checkHealthKeywordContract({ ...base, connectedBody });
    },
  },
  {
    id: "3",
    mutation: 'injected failed body contains "supabase":"connected"',
    expected: ["keyword-present-failed"],
    run: async () => {
      const base = await realInput();
      const failedBodies = [base.failedBodies[0], base.connectedBody];
      return checkHealthKeywordContract({ ...base, failedBodies });
    },
  },
  {
    id: "4",
    mutation: "/health branch pretty-prints: JSON.stringify(health, null, 2)",
    expected: ["serializer-not-compact"],
    run: async () => {
      const base = await realInput();
      const indexText = replaceOnce(base.indexText, "res.end(JSON.stringify(health));", "res.end(JSON.stringify(health, null, 2));");
      return checkHealthKeywordContract({ ...base, indexText });
    },
  },
  {
    id: "5",
    mutation: "/health branch gains a res.writeHead(503 inside an if",
    expected: ["status-not-always-200"],
    run: async () => {
      const base = await realInput();
      const indexText = replaceOnce(
        base.indexText,
        'res.writeHead(200, { "Content-Type": "application/json" });\n      res.end(JSON.stringify(health));',
        'if (health.supabase !== "connected") {\n        res.writeHead(503, { "Content-Type": "application/json" });\n      }\n      res.writeHead(200, { "Content-Type": "application/json" });\n      res.end(JSON.stringify(health));',
      );
      return checkHealthKeywordContract({ ...base, indexText });
    },
  },
  {
    id: "6",
    mutation: 'EXPECTED_BRANCH keyword, declaration says monitor_type = "status" with no required_keyword',
    expected: ["branch-downgraded"],
    run: async () => {
      const base = await realInput();
      const tfTexts = mutateAppHealth(base.tfTexts, (b) =>
        replaceOnce(replaceOnce(b, TYPE_ATTR, 'monitor_type = "status"'), KEYWORD_ATTR, ""),
      );
      return checkHealthKeywordContract({ ...base, tfTexts, expectedBranch: "keyword" });
    },
  },
  {
    id: "7",
    mutation: 'monitor_type = "keyword" with no required_keyword',
    expected: ["keyword-missing"],
    run: async () => {
      const base = await realInput();
      const tfTexts = mutateAppHealth(base.tfTexts, (b) => replaceOnce(b, KEYWORD_ATTR, ""));
      return checkHealthKeywordContract({ ...base, tfTexts, expectedBranch: "keyword" });
    },
  },
  {
    id: "8",
    mutation: "required_keyword = local.kw",
    expected: ["keyword-unresolvable"],
    run: async () => {
      const base = await realInput();
      const tfTexts = mutateAppHealth(base.tfTexts, (b) => replaceOnce(b, KEYWORD_ATTR, "required_keyword = local.kw"));
      return checkHealthKeywordContract({ ...base, tfTexts, expectedBranch: "keyword" });
    },
  },
  {
    id: "9",
    mutation: "a second health-URL monitor in a DIFFERENT .tf, loaded through loadInfraTf",
    expected: ["census-not-one"],
    run: async () => {
      const base = await realInput();
      const tfTexts = withTempTfDir(
        {
          "uptime-alerts.tf": readFileSync(path.join(INFRA_DIR, "uptime-alerts.tf"), "utf8"),
          "zz-shadow.tf": SECOND_HEALTH_MONITOR,
        },
        loadInfraTf,
      );
      return checkHealthKeywordContract({ ...base, tfTexts });
    },
  },
  {
    id: "10",
    mutation: "every real .tf copied with the app_health block deleted (zero health-URL blocks)",
    expected: ["census-not-one"],
    run: async () => {
      const base = await realInput();
      const names = readdirSync(INFRA_DIR).filter((f) => f.endsWith(".tf")).sort();
      const texts = names.map((f) => readFileSync(path.join(INFRA_DIR, f), "utf8"));
      const { owner, start, end } = locateAppHealth(texts);
      texts[owner] = texts[owner].slice(0, start) + texts[owner].slice(end + 1);
      const copies = Object.fromEntries(names.map((f, i) => [f, texts[i]]));
      const tfTexts = withTempTfDir(copies, loadInfraTf);
      expect(tfTexts).toHaveLength(names.length);
      return checkHealthKeywordContract({ ...base, tfTexts });
    },
  },
  {
    id: "11",
    mutation: 'index.ts with zero, then two, pathname === "/health" anchors',
    expected: ["health-branch-not-one"],
    run: async () => {
      const base = await realInput();
      const zero = replaceOnce(base.indexText, 'parsedUrl.pathname === "/health"', 'parsedUrl.pathname === "/healthz"');
      const two = replaceOnce(
        base.indexText,
        'if (parsedUrl.pathname === "/health") {',
        'if (parsedUrl.pathname === "/health") { res.end(); }\n    if (parsedUrl.pathname === "/health") {',
      );
      const zeroV = checkHealthKeywordContract({ ...base, indexText: zero });
      const twoV = checkHealthKeywordContract({ ...base, indexText: two });
      expect(twoV).toEqual(zeroV);
      return zeroV;
    },
  },
  // Harness rows: prove the real-file path and the extractors are load-bearing.
  {
    id: "H1",
    mutation: "stubbed buildHealthResponse returns the connected object on every arm",
    expected: ["keyword-present-failed"],
    run: async () => {
      const real = await realBuilder();
      const bodies = await buildBodies(real);
      const frozen = JSON.parse(bodies.connectedBody) as unknown;
      const stub: Builder = async () => frozen;
      return checkHealthKeywordContract({ ...(await realInput()), ...(await buildBodies(stub)) });
    },
  },
  {
    id: "H2",
    mutation: 'temp copy of server/health.ts with supabaseOk ? "ok" : "error", same builder path',
    expected: ["keyword-absent-connected"],
    run: async () => {
      const dir = mkdtempSync(path.join(tmpdir(), "health-keyword-h2-"));
      try {
        let src = readFileSync(HEALTH_PATH, "utf8");
        src = replaceOnce(src, 'supabaseOk ? "connected" : "error"', 'supabaseOk ? "ok" : "error"');
        src = replaceOnce(src, 'from "./session-metrics"', `from ${JSON.stringify(SESSION_METRICS_PATH)}`);
        const mutant = path.join(dir, "health.ts");
        writeFileSync(mutant, src);
        const mod = (await import(/* @vite-ignore */ mutant)) as { buildHealthResponse: Builder };
        return checkHealthKeywordContract({
          ...(await realInput()),
          ...(await buildBodies(mod.buildHealthResponse)),
        });
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    },
  },
  {
    id: "H3",
    mutation: 'must-PASS: attributes reordered plus a comment line containing monitor_type = "status"',
    expected: [],
    run: async () => {
      const base = await realInput();
      const tfTexts = mutateAppHealth(base.tfTexts, (b) =>
        `\n  # monitor_type = "status"\n  // monitor_type = "status"\n${b.split("\n").filter((l) => l.trim() !== "").reverse().join("\n")}\n`,
      );
      return checkHealthKeywordContract({ ...base, tfTexts });
    },
  },
  {
    id: "H4",
    mutation: "must-PASS: an unrelated monitor block with a different URL",
    expected: [],
    run: async () => {
      const base = await realInput();
      const unrelated = SECOND_HEALTH_MONITOR.replace(HEALTH_URL, "https://app.soleur.ai/healthz");
      return checkHealthKeywordContract({ ...base, tfTexts: [...base.tfTexts, unrelated] });
    },
  },
  {
    id: "H5",
    mutation: 'must-PASS: EXPECTED_BRANCH "status" with a status declaration',
    expected: [],
    run: async () => {
      const base = await realInput();
      const tfTexts = mutateAppHealth(base.tfTexts, (b) =>
        replaceOnce(replaceOnce(b, TYPE_ATTR, 'monitor_type = "status"'), KEYWORD_ATTR, ""),
      );
      return checkHealthKeywordContract({ ...base, tfTexts, expectedBranch: "status" });
    },
  },
];

describe("Guard 1 — health keyword monitor contract (#7884)", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("the committed files satisfy the contract on EXPECTED_BRANCH", async () => {
    const input = await realInput();
    // Non-vacuity: the three real bodies must actually differ on the checked field.
    expect(input.failedBodies).toHaveLength(2);
    expect(new Set([input.connectedBody, ...input.failedBodies]).size).toBeGreaterThan(1);
    expect(checkHealthKeywordContract(input)).toEqual([]);
  });

  it("the matrix carries exactly rows 1-11 and harness rows H1-H5", () => {
    expect(ROWS.map((r) => r.id)).toEqual([
      "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11",
      "H1", "H2", "H3", "H4", "H5",
    ]);
    expect(ROWS).toHaveLength(16);
  });

  it.each(ROWS.map((r) => [r.id, r.mutation, r] as const))(
    "row %s — %s",
    async (_id, _mutation, row) => {
      const violations = await row.run();
      expect(violations.map((x) => x.rule)).toEqual(row.expected);
    },
  );
});
