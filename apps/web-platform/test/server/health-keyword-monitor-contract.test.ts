import { describe, it, expect, vi, afterEach } from "vitest";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

import {
  UnresolvableDeclaration,
  listTfFiles,
  parseInfraVariables,
  parseMonitorBlocks,
  resolveInfraVariables,
  stripComments,
  type DiscoveredMonitor,
  type InfraVariableDefault,
} from "../../../../plugins/soleur/lib/heartbeat-live-reconcile";
import {
  buildHealthResponse,
  writeHealthResponse,
  type HealthResponseSink,
} from "../../server/health";

// Guard 1 (#7884): the paging contract between the Better Stack monitor on
// app.soleur.ai/health and the response that endpoint serves.
//
// Property: exactly one Terraform-declared betteruptime_monitor watches the
// health URL, unconditionally (no count/for_each), unpaused and with a
// notification channel on; its type is EXPECTED_MONITOR_TYPE; its required
// keyword occurs in the served body exactly when the Supabase check succeeds;
// /health answers HTTP 200 with Cache-Control: no-store in every database
// state, through writeHealthResponse, which server/index.ts's /health branch
// delegates to; and no `import {}` addresses the monitor any more, the
// adoption having completed in #8216 (ADR-222 H-F: a kept import aborts the
// apply if the monitor is deleted vendor-side). Rationale: ADR-222 and the
// comment on betteruptime_monitor.app_health
// in apps/web-platform/infra/uptime-alerts.tf.
//
// The keyword is READ from the declaration (through the reconcile's own
// parser), never copied here, so the two cannot drift apart silently. The
// monitor type is deliberately NOT read: downgrading the alarm to `status`
// needs an edit to EXPECTED_MONITOR_TYPE that a reviewer sees.

vi.mock("@/lib/supabase/service", () => ({
  serverUrl: () => "https://test.supabase.co",
}));

// session-metrics pulls in ws-handler, which builds a service client at module
// load. Stubbed so only buildHealthResponse's Supabase check is exercised.
vi.mock("../../server/session-metrics", () => ({
  getActiveSessionCount: () => 0,
  getActiveWorkspaceCount: () => 0,
}));

/** Set from the Phase 0.2 vendor probe. Never derive it from the .tf. */
const EXPECTED_MONITOR_TYPE = "keyword";

const APP_ROOT = path.join(__dirname, "..", "..");
const INFRA_DIR = path.join(APP_ROOT, "infra");
const INDEX_PATH = path.join(APP_ROOT, "server", "index.ts");

const HEALTH_URL = "https://app.soleur.ai/health";
const ADOPTION_TARGET = "betteruptime_monitor.app_health";
const ADOPTED_MONITOR_ID = '"4226366"';
/**
 * Rows 16 and 17 are a PAIR: 16 gates the block on a count that resolves to 1, 17 on one that
 * resolves to 0. Both expect `alarm-conditional`, so if either variable's default flipped — or the
 * variable were deleted, which resolves as unresolvable and ALSO yields `alarm-conditional` — the
 * row would keep passing while silently testing the other half, or nothing. `requireBoolDefault`
 * below makes that precondition fail loudly instead. Do not swap in a name without re-checking it.
 */
const TRUE_DEFAULT_VARIABLE = "adopt_seo_config_entrypoint";
const FALSE_DEFAULT_VARIABLE = "betterstack_paid_tier";

interface Violation {
  rule: string;
  detail?: string;
}

/** What one /health request wrote through writeHealthResponse. */
interface Served {
  status: number;
  headers: Record<string, string>;
  body: string;
}

interface ContractInput {
  tfTexts: string[];
  indexText: string;
  connected: Served;
  failed: Served[];
}

// ── Declarations, read through the reconcile's parser ─────────────────────────

/** Every literal variable default across the texts (resolveInfraVariables, in memory). */
function variablesOf(tfTexts: string[]): Map<string, InfraVariableDefault> {
  return new Map(tfTexts.flatMap((t) => [...parseInfraVariables(t)]));
}

/**
 * Every bool variable forced true. The parser drops a `count = var.x ? 1 : 0`
 * block whose default is false; forcing keeps every count-gated declaration
 * visible, so a gated health monitor is refused whichever way its gate resolves.
 */
function rawDeclarationView(vars: Map<string, InfraVariableDefault>): Map<string, InfraVariableDefault> {
  return new Map([...vars].map(([k, d]) => [k, d.kind === "bool" ? { kind: "bool", value: true } : d]));
}

/** UnresolvableDeclaration.why starts with the attribute it could not resolve. */
const UNRESOLVABLE_RULES: [RegExp, string][] = [
  [/^(for_each|count|both for_each and count)\b/, "alarm-conditional"],
  [/^required_keyword\b/, "keyword-unresolvable"],
  [/^paused\b/, "alarm-paused"],
  [/^(email|call|sms|push)\b/, "alarm-silenced"],
];

/** Every `import { … }` block's top-level `key = value` lines (import blocks hold no nested braces). */
function importBlocks(tfTexts: string[]): Map<string, string>[] {
  return tfTexts
    .flatMap((t) => [...stripComments(t).matchAll(/(?<![^\s{}])import\s*\{([^{}]*)\}/g)])
    .map((m) => new Map(m[1].split("\n").flatMap((l) => {
      const a = l.match(/^\s*([A-Za-z_][\w-]*)\s*=\s*(.+?)\s*$/);
      return a ? [[a[1], a[2]] as [string, string]] : [];
    })));
}

// ── The /health branch of server/index.ts ─────────────────────────────────────

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

/** Index of the `}` closing the `{` at `open` (string-aware). */
function matchBrace(src: string, open: number): number {
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
    else if (c === "{") depth++;
    else if (c === "}" && --depth === 0) return i;
  }
  return -1;
}

// ── The checker ───────────────────────────────────────────────────────────────

function checkMonitor(input: ContractInput, v: Violation[]): void {
  let monitors: DiscoveredMonitor[];
  try {
    const view = rawDeclarationView(variablesOf(input.tfTexts));
    monitors = input.tfTexts.flatMap((t) => parseMonitorBlocks(t, view));
  } catch (err) {
    if (!(err instanceof UnresolvableDeclaration)) throw err;
    const rule = UNRESOLVABLE_RULES.find(([re]) => re.test(err.why))?.[1] ?? "census-unresolvable";
    v.push({ rule, detail: err.message });
    return;
  }

  const health = monitors.filter((m) => m.url === HEALTH_URL);
  if (health.length !== 1) {
    v.push({ rule: "census-not-one", detail: health.map((m) => m.resource).join(", ") });
    return;
  }
  const [m] = health;
  if (m.hasCount || m.hasForEach) v.push({ rule: "alarm-conditional" });
  if (m.paused === true) v.push({ rule: "alarm-paused" });
  if (![m.email, m.call, m.sms, m.push].includes(true)) v.push({ rule: "alarm-silenced" });

  if (m.monitorType !== EXPECTED_MONITOR_TYPE) {
    v.push({ rule: "branch-downgraded", detail: m.monitorType });
  } else if (m.requiredKeyword === undefined) {
    v.push({ rule: "keyword-missing" });
  } else if (m.requiredKeyword === "") {
    v.push({ rule: "keyword-unresolvable" });
  } else {
    // Better Stack's keyword lookup is case-insensitive (vendor docs).
    const kw = m.requiredKeyword.toLowerCase();
    if (!input.connected.body.toLowerCase().includes(kw)) v.push({ rule: "keyword-absent-connected" });
    if (input.failed.some((s) => s.body.toLowerCase().includes(kw))) v.push({ rule: "keyword-present-failed" });
  }
}

function checkServed(input: ContractInput, v: Violation[]): void {
  const all = [input.connected, ...input.failed];
  if (all.some((s) => s.status !== 200)) v.push({ rule: "status-not-always-200" });
  const cacheControl = (s: Served) =>
    Object.entries(s.headers).find(([k]) => k.toLowerCase() === "cache-control")?.[1] ?? "";
  if (all.some((s) => !/\bno-store\b/.test(cacheControl(s)))) v.push({ rule: "health-cacheable" });
}

function checkDelegation(indexText: string, v: Violation[]): void {
  const index = stripTsComments(indexText);
  const anchors = [...index.matchAll(/pathname\s*===\s*"\/health"/g)];
  const open = anchors.length === 1 ? index.indexOf("{", anchors[0].index) : -1;
  const close = open === -1 ? -1 : matchBrace(index, open);
  if (close === -1) {
    v.push({ rule: "health-branch-not-one" });
    return;
  }
  const branch = index.slice(open + 1, close);
  if (
    !/\bwriteHealthResponse\(\s*res\s*,\s*await\s+buildHealthResponse\(\s*\)\s*\)/.test(branch) ||
    /\bstatusCode\s*=(?!=)|\bwriteHead\s*\(/.test(branch)
  ) {
    v.push({ rule: "health-branch-not-delegating" });
  }
}

/**
 * The adoption is DONE (#8216 imported 4226366; the read-back passed), so no `import {}` may
 * address the monitor any more. One kept is not inert: a vendor-side deletion makes Terraform
 * re-attempt the import against a missing object, which aborts the per-merge apply and the
 * untargeted drift plan (ADR-222, H-F). Re-adding one is the regression this pins.
 */
function checkNoAdoptionImport(tfTexts: string[], v: Violation[]): void {
  const imports = importBlocks(tfTexts).filter((a) => a.get("to") === ADOPTION_TARGET);
  if (imports.length > 0) v.push({ rule: "adoption-import-lingering" });
}

function checkHealthKeywordContract(input: ContractInput): Violation[] {
  const v: Violation[] = [];
  checkMonitor(input, v);
  checkServed(input, v);
  checkDelegation(input.indexText, v);
  checkNoAdoptionImport(input.tfTexts, v);
  return v;
}

// ── Inputs: real files, real builder, real writer ─────────────────────────────

/** Every `*.tf` in `dir` (the reconcile's listing). Throws on an empty dir. */
function loadInfraTf(dir: string): string[] {
  const files = listTfFiles(dir);
  if (files.length === 0) throw new Error(`no *.tf files in ${dir}`);
  return files.map((f) => readFileSync(path.join(dir, f), "utf8"));
}

/** /health in each database state: writeHealthResponse(fakeRes, await buildHealthResponse()). */
async function serveEveryState(): Promise<Pick<ContractInput, "connected" | "failed">> {
  const serve = async (): Promise<Served> => {
    const health = await buildHealthResponse();
    const served: Served = { status: -1, headers: {}, body: "" };
    const res: HealthResponseSink = {
      writeHead: (status, headers) => {
        served.status = status;
        served.headers = headers;
      },
      end: (body) => {
        served.body = body;
      },
    };
    writeHealthResponse(res, health);
    return served;
  };
  const fetchSpy = vi.spyOn(globalThis, "fetch");
  try {
    fetchSpy.mockResolvedValueOnce(new Response("[]", { status: 200 }));
    const connected = await serve();
    fetchSpy.mockResolvedValueOnce(new Response("unavailable", { status: 503 }));
    const non2xx = await serve();
    fetchSpy.mockRejectedValueOnce(new Error("network unreachable"));
    const thrown = await serve();
    return { connected, failed: [non2xx, thrown] };
  } finally {
    fetchSpy.mockRestore();
  }
}

async function realInput(): Promise<ContractInput> {
  return {
    tfTexts: loadInfraTf(INFRA_DIR),
    indexText: readFileSync(INDEX_PATH, "utf8"),
    ...(await serveEveryState()),
  };
}

// ── Mutation helpers (each throws unless it changed exactly what it names) ────

function replaceOnce(text: string, find: string, repl: string): string {
  const hits = text.split(find).length - 1;
  if (hits !== 1) throw new Error(`mutation anchor ${JSON.stringify(find)} matched ${hits} times, expected 1`);
  return text.replace(find, () => repl);
}

/** Apply `edit` to the one .tf text containing `needle`. */
function editFileWith(tfTexts: string[], needle: string, edit: (text: string) => string): string[] {
  const owners = tfTexts.flatMap((t, i) => (t.includes(needle) ? [i] : []));
  if (owners.length !== 1) throw new Error(`${JSON.stringify(needle)} found in ${owners.length} files, expected 1`);
  return tfTexts.map((t, i) => (i === owners[0] ? edit(t) : t));
}

const APP_HEALTH_HEADER = 'resource "betteruptime_monitor" "app_health" {';

/** Apply `edit` to the app_health block body (terraform fmt closes a top-level block with `}` at column 0). */
function editAppHealth(tfTexts: string[], edit: (body: string) => string): string[] {
  return editFileWith(tfTexts, APP_HEALTH_HEADER, (t) => {
    const open = t.indexOf(APP_HEALTH_HEADER) + APP_HEALTH_HEADER.length;
    const close = t.indexOf("\n}\n", open);
    if (close === -1) throw new Error("app_health block has no column-0 closing brace");
    return t.slice(0, open) + edit(t.slice(open, close + 1)) + t.slice(close + 1);
  });
}

const KEYWORD_LINE = 'required_keyword = "\\"supabase\\":\\"connected\\""';
const TYPE_LINE = 'monitor_type = "keyword"';

const SECOND_HEALTH_MONITOR = `
resource "betteruptime_monitor" "app_health_shadow" {
  monitor_type = "status"
  url          = "${HEALTH_URL}"
  email        = true
}
`;

// ── Guard 1 matrix ────────────────────────────────────────────────────────────

interface Row {
  id: string;
  mutation: string;
  expected: string[];
  run: () => Promise<Violation[]>;
}

/** A row that edits the real input in memory and checks it. */
function row(id: string, mutation: string, expected: string[], mutate: (base: ContractInput) => ContractInput): Row {
  return { id, mutation, expected, run: async () => checkHealthKeywordContract(mutate(await realInput())) };
}

const withTf = (edit: (tf: string[]) => string[]) => (b: ContractInput) => ({ ...b, tfTexts: edit(b.tfTexts) });

/**
 * Throw rather than let a count-gate row degenerate. A deleted variable resolves as unresolvable
 * and yields the same `alarm-conditional` the row expects, so without this the row would pass
 * while proving something else entirely.
 */
function requireBoolDefault(tf: string[], name: string, want: boolean): string[] {
  const d = variablesOf(tf).get(name);
  if (d?.kind !== "bool" || d.value !== want) {
    throw new Error(`count-gate row needs var.${name} declared bool default ${want}, got ${JSON.stringify(d)}`);
  }
  return tf;
}
const withIndex = (find: string, repl: string) => (b: ContractInput) => ({ ...b, indexText: replaceOnce(b.indexText, find, repl) });

const HEALTH_BRANCH_CALL = "writeHealthResponse(res, await buildHealthResponse());";

const ROWS: Row[] = [
  // Keyword ↔ served body.
  row("1", "required_keyword gains a space after the colon", ["keyword-absent-connected"],
    withTf((tf) => editAppHealth(tf, (b) => replaceOnce(b, KEYWORD_LINE, 'required_keyword = "\\"supabase\\": \\"connected\\""')))),
  row("2", 'connected response body carries "supabase":"ok"', ["keyword-absent-connected"],
    (b) => ({ ...b, connected: { ...b.connected, body: replaceOnce(b.connected.body, '"supabase":"connected"', '"supabase":"ok"') } })),
  row("3", "a failed-state response body carries the connected keyword", ["keyword-present-failed"],
    (b) => ({ ...b, failed: [b.failed[0], { ...b.failed[1], body: b.connected.body }] })),
  // Response shape, from writeHealthResponse.
  row("4", "a failed-state response is served as 503", ["status-not-always-200"],
    (b) => ({ ...b, failed: [{ ...b.failed[0], status: 503 }, b.failed[1]] })),
  row("5", "the connected response loses Cache-Control: no-store", ["health-cacheable"],
    (b) => ({ ...b, connected: { ...b.connected, headers: { "Content-Type": "application/json" } } })),
  // index.ts delegates.
  row("6", "the /health branch writes its own status before delegating", ["health-branch-not-delegating"],
    withIndex(HEALTH_BRANCH_CALL, `res.statusCode = 503;\n      res.writeHead(503);\n      ${HEALTH_BRANCH_CALL}`)),
  row("7", "the /health branch serializes itself instead of delegating", ["health-branch-not-delegating"],
    withIndex(HEALTH_BRANCH_CALL, "res.end(JSON.stringify(await buildHealthResponse(), null, 2));")),
  {
    id: "8",
    mutation: 'index.ts with zero, then two, pathname === "/health" anchors',
    expected: ["health-branch-not-one"],
    run: async () => {
      const base = await realInput();
      const zero = withIndex('pathname === "/health"', 'pathname === "/healthz"')(base);
      const two = withIndex('if (parsedUrl.pathname === "/health") {', 'if (parsedUrl.pathname === "/health") { res.end(); }\n    if (parsedUrl.pathname === "/health") {')(base);
      const zeroV = checkHealthKeywordContract(zero);
      expect(checkHealthKeywordContract(two)).toEqual(zeroV);
      return zeroV;
    },
  },
  // Type and keyword declaration.
  row("9", 'monitor_type = "status" with no required_keyword', ["branch-downgraded"],
    withTf((tf) => editAppHealth(tf, (b) => replaceOnce(replaceOnce(b, TYPE_LINE, 'monitor_type = "status"'), KEYWORD_LINE, "")))),
  row("10", 'monitor_type = "keyword" with no required_keyword', ["keyword-missing"],
    withTf((tf) => editAppHealth(tf, (b) => replaceOnce(b, KEYWORD_LINE, "")))),
  row("11", "required_keyword = local.kw", ["keyword-unresolvable"],
    withTf((tf) => editAppHealth(tf, (b) => replaceOnce(b, KEYWORD_LINE, "required_keyword = local.kw")))),
  // Census.
  {
    id: "12",
    mutation: "a second health-URL monitor in a DIFFERENT .tf of a real directory",
    expected: ["census-not-one"],
    run: async () => {
      const dir = mkdtempSync(path.join(tmpdir(), "health-keyword-contract-"));
      try {
        for (const f of ["uptime-alerts.tf", "variables.tf"]) {
          writeFileSync(path.join(dir, f), readFileSync(path.join(INFRA_DIR, f), "utf8"));
        }
        writeFileSync(path.join(dir, "zz-shadow.tf"), SECOND_HEALTH_MONITOR);
        return checkHealthKeywordContract({ ...(await realInput()), tfTexts: loadInfraTf(dir) });
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    },
  },
  row("13", "the app_health block deleted (zero health-URL monitors)", ["census-not-one"],
    withTf((tf) => editFileWith(tf, APP_HEALTH_HEADER, (t) => {
      const start = t.indexOf(APP_HEALTH_HEADER);
      return t.slice(0, start) + t.slice(t.indexOf("\n}\n", start) + 3);
    }))),
  // Alarm stays armed.
  row("14", "paused = true", ["alarm-paused"],
    withTf((tf) => editAppHealth(tf, (b) => replaceOnce(b, "paused     = false", "paused     = true")))),
  row("15", "email = false with call/sms/push already false", ["alarm-silenced"],
    withTf((tf) => editAppHealth(tf, (b) => replaceOnce(b, "email = true", "email = false")))),
  row("16", `count = var.${TRUE_DEFAULT_VARIABLE} ? 1 : 0 (resolves to 1)`, ["alarm-conditional"],
    withTf((tf) => editAppHealth(requireBoolDefault(tf, TRUE_DEFAULT_VARIABLE, true), (b) => `\n  count = var.${TRUE_DEFAULT_VARIABLE} ? 1 : 0${b}`))),
  row("17", `count gated on var.${FALSE_DEFAULT_VARIABLE} (false default — the parser alone would drop the block)`, ["alarm-conditional"],
    withTf((tf) => editAppHealth(requireBoolDefault(tf, FALSE_DEFAULT_VARIABLE, false), (b) => `\n  count = var.${FALSE_DEFAULT_VARIABLE} ? 1 : 0${b}`))),
  row("18", "for_each on the monitor", ["alarm-conditional"],
    withTf((tf) => editAppHealth(tf, (b) => `\n  for_each = toset(["a"])${b}`))),
  // The one-time adoption import stays gone (#7884).
  row("19", "an import block addressing app_health is re-added", ["adoption-import-lingering"],
    withTf((tf) => editFileWith(tf, APP_HEALTH_HEADER, (t) =>
      `import {\n  to = ${ADOPTION_TARGET}\n  id = ${ADOPTED_MONITOR_ID}\n}\n\n${t}`))),
  // Must-pass: the parser reads syntax, not text.
  row("H1", 'must-PASS: attributes reordered plus comment lines containing monitor_type = "status" and paused = true', [],
    withTf((tf) => editAppHealth(tf, (b) =>
      `\n  # monitor_type = "status"\n  // paused = true\n  /* count = 0 */\n${b.split("\n").filter((l) => l.trim() !== "").reverse().join("\n")}\n`))),
  row("H2", "must-PASS: an unrelated monitor block with a different URL", [],
    (b) => ({ ...b, tfTexts: [...b.tfTexts, SECOND_HEALTH_MONITOR.replace(HEALTH_URL, "https://app.soleur.ai/healthz")] })),
];

describe("Guard 1 — health keyword monitor contract (#7884)", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("the committed files satisfy the contract", async () => {
    const input = await realInput();
    // Non-vacuity: the real builder ran in each state, through the real writer.
    expect(JSON.parse(input.connected.body).supabase).toBe("connected");
    expect(input.failed.map((s) => JSON.parse(s.body).supabase)).toEqual(["error", "error"]);
    expect(input.connected.headers["Content-Type"]).toBe("application/json");
    // The in-memory variable merge the checker uses equals the reconcile's directory resolution.
    expect(variablesOf(input.tfTexts)).toEqual(resolveInfraVariables(INFRA_DIR));
    expect(checkHealthKeywordContract(input)).toEqual([]);
  });

  it("the matrix carries exactly rows 1-19 and must-pass rows H1-H2", () => {
    expect(ROWS.map((r) => r.id)).toEqual([
      ...Array.from({ length: 19 }, (_, i) => String(i + 1)),
      "H1", "H2",
    ]);
  });

  it.each(ROWS.map((r) => [r.id, r.mutation, r] as const))("row %s — %s", async (_id, _mutation, r) => {
    const violations = await r.run();
    expect(violations.map((x) => x.rule)).toEqual(r.expected);
  });
});
