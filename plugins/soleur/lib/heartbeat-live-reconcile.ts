// Pure, network-free reconcile logic for the twice-daily source-vs-live Better Stack reconcile
// (#6549 item 2; monitors arm + unmanaged-live class #7884). The CLI wrapper that fetches the live
// payload lives in `plugins/soleur/scripts/reconcile-live-heartbeats.ts`.
//
// Why this exists: `heartbeat-reprovision-parity.test.ts` proves a feeder exists in SOURCE, but
// `lifecycle { ignore_changes = [paused] }` (plus these resources being untargeted) makes the .tf
// `paused` value only a LOWER BOUND on live state. A heartbeat that is `paused` or absent in LIVE
// Better Stack is invisible to any source-only test — the exact state that hid the registry
// heartbeat for 9 days (#6537). This module compares the live payload against the executable
// MANIFEST and the declared `.tf` blocks. It only READS; it never unpauses anything.
//
// #7884 widened it: every live Better Stack uptime MONITOR and HEARTBEAT must be accounted for by
// exactly one resolved declaration (monitors by literal `url`, heartbeats by resolved `name`), and a
// declared monitor's live `monitor_type` / `required_keyword` / `paused` must equal its declaration.
// `for_each` / `count` are resolved EXACTLY from literal variable defaults (`resolveInfraVariables`);
// any shape that cannot be resolved exactly throws `UnresolvableDeclaration` (fail closed — a guess
// would either invent false `unmanaged-live` rows or silently absorb a hand-made object).

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

import type { ManifestEntry } from "./heartbeat-manifest";

/** A declaration the reconcile cannot resolve exactly. `resource` is `<type>.<name>`. */
export class UnresolvableDeclaration extends Error {
  readonly resource: string;
  readonly why: string;
  constructor(resource: string, why: string) {
    super(`unresolvable declaration ${resource}: ${why}`);
    this.name = "UnresolvableDeclaration";
    this.resource = resource;
    this.why = why;
  }
}

/** One concrete `betteruptime_heartbeat` instance resolved from the infra `.tf` source. */
export interface DiscoveredHeartbeat {
  /** The `.tf` resource label — `betteruptime_heartbeat.<resourceName>`; the MANIFEST join key. */
  resourceName: string;
  /** The resolved `name = "..."` attribute (`${each.key}` substituted) — how live Better Stack keys it. */
  liveName: string;
  /**
   * The source-declared `paused` value (defaults to false when the attribute is absent). Carried
   * for reporting/diagnostics only — `reconcileHeartbeats` keys its decision on live state +
   * `feeder.kind`, never on this (source `paused` is only a lower bound on live; that decoupling is
   * the whole reason a live reconcile exists).
   */
  sourcePaused: boolean;
  /**
   * Whether the block carries a `count = var.<X> ? 1 : 0` meta-argument. Diagnostic only since
   * #7884: a count resolved to 0 yields NO instance (not expected live), a count resolved to 1 yields
   * one instance that is expected live like any other.
   */
  countGated: boolean;
}

/** One concrete `betteruptime_monitor` instance resolved from the infra `.tf` source (#7884). */
export interface DiscoveredMonitor {
  resourceName: string;
  /** Literal `url` — the monitors-arm join key (a rename never reads as unmanaged). */
  url: string;
  monitorType: string;
  /** `""` when the attribute is absent. */
  requiredKeyword: string;
  /** `false` when the attribute is absent. */
  paused: boolean;
}

/** One heartbeat as reported by `GET /api/v2/heartbeats` (`data[].id` + `data[].attributes`). */
export interface LiveHeartbeat {
  /** Vendor id, numeric string (validated at fetch). */
  id: string;
  name: string;
  paused: boolean;
}

/** One monitor as reported by `GET /api/v2/monitors` (#7884). */
export interface LiveMonitor {
  /** Vendor id, numeric string (validated at fetch). */
  id: string;
  url: string;
  /** `pronounceable_name`; `""` when absent. Vendor text — reporting only, never a join key. */
  name: string;
  monitorType: string;
  /** `null` when the vendor returns null/absent; compared equal to `""`. */
  requiredKeyword: string | null;
  paused: boolean;
}

/**
 * `fed-but-paused` / `absent-live` are the heartbeat classes (a)/(b) below (`absent-live` is also
 * the monitors-arm class for a declared monitor with no live object on its URL). `logs-alert-paused`
 * / `logs-alert-absent` are the #8097 `logs_alert` arm (ADR-218 §5). `unmanaged-live` and
 * `monitor-config-drift` are the #7884 classes.
 * Every consumer that switches on this union is listed in the scheduled-terraform-drift.yml
 * issue-body decode list (cq-union-widening-grep-three-patterns).
 */
export type ViolationReason =
  | "fed-but-paused"
  | "absent-live"
  | "logs-alert-paused"
  | "logs-alert-absent"
  | "unmanaged-live"
  | "monitor-config-drift";

/** Heartbeat classes (a)/(b). `live` is the heartbeat live STATE. */
export interface HeartbeatViolation {
  kind: "heartbeat";
  resourceName: string;
  liveName: string;
  live: "paused" | "absent";
  reason: "fed-but-paused" | "absent-live";
}

/**
 * #8097 `logs_alert` arm. `live: "logs_alert"` is a SURFACE tag kept because the marker grammar
 * `live=…` is a wire contract consumed by scheduled-terraform-drift.yml's decode list and ADR-218.
 */
export interface LogsAlertViolation {
  kind: "logs_alert";
  resourceName: string;
  liveName: string;
  live: "logs_alert";
  reason: "logs-alert-paused" | "logs-alert-absent";
  /** Vendor `paused_reason`, rendered inside a quoted `detail="…"`; absent for `logs-alert-absent`. */
  detail?: string;
}

export type MonitorField = "monitor_type" | "required_keyword" | "paused";

/** #7884 monitors arm: a declared instance absent live, or a live field drifted from its declaration. */
export type MonitorViolation =
  | { kind: "monitor"; reason: "absent-live"; resourceName: string; url: string }
  | {
      kind: "monitor";
      reason: "monitor-config-drift";
      resourceName: string;
      id: string;
      field: MonitorField;
      declared: string;
      live: string;
    };

/** #7884: a live object no resolved declaration accounts for (or one of ≥2 sharing a join key). */
export type UnmanagedViolation =
  | { kind: "unmanaged"; surface: "monitors"; reason: "unmanaged-live"; id: string; url: string; name: string; dup: boolean }
  | { kind: "unmanaged"; surface: "heartbeats"; reason: "unmanaged-live"; id: string; name: string; dup: boolean };

export type Violation = HeartbeatViolation | LogsAlertViolation | MonitorViolation | UnmanagedViolation;

/** A `logtail_exploration_alert` block parsed from the infra `.tf` source (#8097). */
export interface DiscoveredLogsAlert {
  resourceName: string;
  /** The `name = "..."` attribute — how the Telemetry API keys the alert. */
  liveName: string;
}

/** One alert as reported by `GET telemetry.betterstack.com/api/v2/alerts` (`data[].attributes`). */
export interface LiveLogsAlert {
  name: string;
  paused: boolean;
  /** Vendor free text; `""` when absent/null (coalesced once, at parse). */
  pausedReason: string;
}

/**
 * Strip HCL line comments (`#` and `//`) so a `count =` / `paused =` token that appears only inside
 * an explanatory comment cannot be mistaken for real config. Mirrors the comment-stripped view the
 * parity test parses. A `#`/`//` inside a double-quoted string is preserved.
 */
export function stripComments(text: string): string {
  return text
    .split("\n")
    .map((line) => {
      let inString = false;
      for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (ch === '"' && line[i - 1] !== "\\") {
          inString = !inString;
          continue;
        }
        if (inString) continue;
        if (ch === "#") return line.slice(0, i);
        if (ch === "/" && line[i + 1] === "/") return line.slice(0, i);
      }
      return line;
    })
    .join("\n");
}

// ─── HCL scanning (string-, interpolation- and heredoc-aware) ───────────────────────────────────

/** Index just past the closing `"` of the string opened at `open` (which must be a `"`). -1 if unterminated. */
function skipString(text: string, open: number): number {
  let i = open + 1;
  while (i < text.length) {
    const ch = text[i];
    if (ch === "\\") {
      i += 2;
      continue;
    }
    if (ch === "\n") return -1; // HCL quoted strings are single-line
    if (ch === '"') return i + 1;
    if ((ch === "$" || ch === "%") && text[i + 1] === "{") {
      // `$${` / `%%{` are literal escapes, not template sequences.
      if (text[i - 1] === ch) {
        i += 2;
        continue;
      }
      const close = matchBalanced(text, i + 1);
      if (close === -1) return -1;
      i = close + 1;
      continue;
    }
    i++;
  }
  return -1;
}

/** Index just past a heredoc opened at `open` (`<<` or `<<-`), or -1 when it is not a heredoc. */
function skipHeredoc(text: string, open: number): number {
  const m = /^<<-?([A-Za-z_][A-Za-z0-9_]*)[ \t]*\n/.exec(text.slice(open, open + 256));
  if (!m) return -1;
  const tag = m[1];
  const closer = new RegExp(`\\n[ \\t]*${tag}[ \\t]*(?=\\n|$)`, "g");
  closer.lastIndex = open + m[0].length - 1;
  const c = closer.exec(text);
  return c ? c.index + c[0].length : -1;
}

const OPENERS: Record<string, string> = { "{": "}", "[": "]", "(": ")" };

/**
 * Index of the bracket closing the one opened at `open` (`{`, `[` or `(`), skipping quoted strings
 * (with `${…}` interpolation) and heredocs. -1 when unbalanced.
 */
function matchBalanced(text: string, open: number): number {
  const stack: string[] = [OPENERS[text[open]]];
  let i = open + 1;
  while (i < text.length) {
    const ch = text[i];
    if (ch === '"') {
      const end = skipString(text, i);
      if (end === -1) return -1;
      i = end;
      continue;
    }
    if (ch === "<" && text[i + 1] === "<") {
      const end = skipHeredoc(text, i);
      if (end !== -1) {
        i = end;
        continue;
      }
    }
    if (ch in OPENERS) stack.push(OPENERS[ch]);
    else if (ch === "}" || ch === "]" || ch === ")") {
      if (stack.pop() !== ch) return -1;
      if (stack.length === 0) return i;
    }
    i++;
  }
  return -1;
}

/**
 * End index (exclusive) of the expression starting at `start`: runs to the first newline outside
 * any bracket/string/heredoc (or `stopAtComma` at depth 0), clamped to `limit`.
 */
function expressionEnd(text: string, start: number, limit: number, stopAtComma = false): number {
  let i = start;
  while (i < limit) {
    const ch = text[i];
    if (ch === "\n") return i;
    if (stopAtComma && ch === ",") return i;
    if (ch === '"') {
      const end = skipString(text, i);
      if (end === -1) return limit;
      i = end;
      continue;
    }
    if (ch === "<" && text[i + 1] === "<") {
      const end = skipHeredoc(text, i);
      if (end !== -1) {
        i = end;
        continue;
      }
    }
    if (ch in OPENERS) {
      const close = matchBalanced(text, i);
      if (close === -1) return limit;
      i = close + 1;
      continue;
    }
    i++;
  }
  return limit;
}

/**
 * Top-level (depth-1) `key = expr` attributes of a `{…}` block body. Nested blocks
 * (`lifecycle {…}`, `validation {…}`, `request_headers {…}`) are skipped whole, so an attribute
 * inside them is never read as the block's own.
 */
function topLevelAttributes(body: string): Map<string, string> {
  const out = new Map<string, string>();
  const limit = body.length - 1; // exclude the closing brace
  const attr = /[ \t\r\n]*([A-Za-z_][A-Za-z0-9_-]*)[ \t]*=(?!=)[ \t]*/y;
  const block = /[ \t\r\n]*[A-Za-z_][A-Za-z0-9_-]*(?:[ \t]+"[^"\n]*")*[ \t]*\{/y;
  let i = 1;
  while (i < limit) {
    attr.lastIndex = i;
    const a = attr.exec(body);
    if (a) {
      const valueStart = attr.lastIndex;
      const end = expressionEnd(body, valueStart, limit);
      out.set(a[1], body.slice(valueStart, end).trim());
      i = end + 1;
      continue;
    }
    block.lastIndex = i;
    const b = block.exec(body);
    if (b) {
      const close = matchBalanced(body, block.lastIndex - 1);
      if (close === -1) throw new Error("Unbalanced nested block");
      i = close + 1;
      continue;
    }
    const nl = body.indexOf("\n", i);
    i = nl === -1 ? limit : nl + 1;
  }
  return out;
}

/**
 * Brace-matched extraction of every `<kind> "<label>" [ "<name>" ] {…}` block in comment-stripped
 * HCL. Throws on an unbalanced block so a malformed source can never silently drop a resource.
 */
function labeledBlocks(stripped: string, headerRe: RegExp, what: (m: RegExpExecArray) => string): { m: RegExpExecArray; body: string }[] {
  const out: { m: RegExpExecArray; body: string }[] = [];
  let m: RegExpExecArray | null;
  while ((m = headerRe.exec(stripped)) !== null) {
    const openBrace = headerRe.lastIndex - 1;
    const end = matchBalanced(stripped, openBrace);
    if (end === -1) {
      throw new Error(`Unbalanced braces for ${what(m)}`);
    }
    out.push({ m, body: stripped.slice(openBrace, end + 1) });
    headerRe.lastIndex = end + 1;
  }
  return out;
}

function resourceBlocks(stripped: string, type: string): { resourceName: string; body: string }[] {
  const header = new RegExp(`\\bresource\\s+"${type}"\\s+"([A-Za-z0-9_]+)"\\s*\\{`, "g");
  return labeledBlocks(stripped, header, (m) => `${type}.${m[1]}`).map(({ m, body }) => ({ resourceName: m[1], body }));
}

// ─── Literal values ─────────────────────────────────────────────────────────────────────────────

/**
 * Decode a quoted HCL string expression. `${each.key}` is substituted with `eachKey` when given;
 * any other template sequence (`${…}` / `%{…}`), or trailing text after the closing quote, makes
 * the value non-literal → `null`.
 */
function decodeString(raw: string, eachKey?: string): string | null {
  if (!raw.startsWith('"')) return null;
  let out = "";
  let i = 1;
  while (i < raw.length) {
    const ch = raw[i];
    if (ch === '"') {
      return i === raw.length - 1 ? out : null;
    }
    if (ch === "\\") {
      const n = raw[i + 1];
      const simple: Record<string, string> = { n: "\n", r: "\r", t: "\t", '"': '"', "\\": "\\" };
      if (n in simple) {
        out += simple[n];
        i += 2;
        continue;
      }
      if (n === "u" && /^[0-9A-Fa-f]{4}$/.test(raw.slice(i + 2, i + 6))) {
        out += String.fromCharCode(parseInt(raw.slice(i + 2, i + 6), 16));
        i += 6;
        continue;
      }
      return null;
    }
    if ((ch === "$" || ch === "%") && raw[i + 1] === ch && raw[i + 2] === "{") {
      out += `${ch}{`;
      i += 3;
      continue;
    }
    if (ch === "%" && raw[i + 1] === "{") return null;
    if (ch === "$" && raw[i + 1] === "{") {
      const close = raw.indexOf("}", i + 2);
      if (close === -1) return null;
      const inner = raw.slice(i + 2, close).trim();
      if (inner === "each.key" && eachKey !== undefined) {
        out += eachKey;
        i = close + 1;
        continue;
      }
      return null;
    }
    out += ch;
    i++;
  }
  return null;
}

const IDENT = "[A-Za-z_][A-Za-z0-9_-]*";

/** A literal variable default the resolver understands. */
export type InfraVariableDefault =
  | { kind: "map"; keys: string[] }
  | { kind: "bool"; value: boolean }
  | { kind: "other" };
export type InfraVariables = ReadonlyMap<string, InfraVariableDefault>;

/** Top-level keys of a literal `{ … }` map/object expression, or `null` when not a plain literal map. */
function literalMapKeys(raw: string): string[] | null {
  if (!raw.startsWith("{")) return null;
  const close = matchBalanced(raw, 0);
  if (close !== raw.length - 1) return null;
  const keys: string[] = [];
  const keyRe = new RegExp(`[\\s,]*(?:("(?:[^"\\\\\\n]|\\\\.)*")|(${IDENT}))[ \\t]*[=:](?!=)[ \\t]*`, "y");
  let i = 1;
  const limit = raw.length - 1;
  while (i < limit) {
    if (/^[\s,]*$/.test(raw.slice(i, limit))) break;
    keyRe.lastIndex = i;
    const k = keyRe.exec(raw);
    if (!k) return null;
    const key = k[1] !== undefined ? decodeString(k[1]) : k[2];
    if (key === null) return null;
    keys.push(key);
    const end = expressionEnd(raw, keyRe.lastIndex, limit, true);
    i = end + 1;
  }
  return keys;
}

/** Parse every `variable "<X>" { default = … }` in one comment-stripped `.tf` text. */
export function parseInfraVariables(tfText: string): Map<string, InfraVariableDefault> {
  const stripped = stripComments(tfText);
  const out = new Map<string, InfraVariableDefault>();
  const header = /\bvariable\s+"([A-Za-z0-9_-]+)"\s*\{/g;
  for (const { m, body } of labeledBlocks(stripped, header, (x) => `variable.${x[1]}`)) {
    const raw = topLevelAttributes(body).get("default");
    if (raw === undefined) continue;
    let value: InfraVariableDefault = { kind: "other" };
    if (raw === "true" || raw === "false") value = { kind: "bool", value: raw === "true" };
    else {
      const keys = literalMapKeys(raw);
      if (keys !== null) value = { kind: "map", keys };
    }
    out.set(m[1], value);
  }
  return out;
}

/** Every literal variable default declared across the `*.tf` files of an infra directory. */
export function resolveInfraVariables(infraDir: string): Map<string, InfraVariableDefault> {
  const out = new Map<string, InfraVariableDefault>();
  for (const file of readdirSync(infraDir).sort()) {
    if (!file.endsWith(".tf")) continue;
    const text = readFileSync(join(infraDir, file), "utf8");
    if (!text.includes("variable")) continue;
    for (const [k, v] of parseInfraVariables(text)) out.set(k, v);
  }
  return out;
}

/**
 * Resolve a block's `for_each` / `count` into its instance keys: `[undefined]` for a plain block,
 * one key per map entry for `for_each = var.<X>` (literal map default), `[undefined]` or `[]` for
 * `count = var.<X> ? 1 : 0` (literal bool default). Anything else throws.
 */
function resolveInstances(
  resource: string,
  attrs: Map<string, string>,
  vars: InfraVariables,
): { keys: (string | undefined)[]; countGated: boolean } {
  const forEach = attrs.get("for_each");
  const count = attrs.get("count");
  if (forEach !== undefined && count !== undefined) {
    throw new UnresolvableDeclaration(resource, "both for_each and count");
  }
  if (forEach !== undefined) {
    const m = new RegExp(`^var\\.(${IDENT})$`).exec(forEach);
    if (!m) throw new UnresolvableDeclaration(resource, `for_each is not exactly var.<name>: ${forEach}`);
    const v = vars.get(m[1]);
    if (!v || v.kind !== "map") {
      throw new UnresolvableDeclaration(resource, `for_each variable ${m[1]} has no literal map default`);
    }
    return { keys: [...v.keys], countGated: false };
  }
  if (count !== undefined) {
    const m = new RegExp(`^var\\.(${IDENT})\\s*\\?\\s*1\\s*:\\s*0$`).exec(count);
    if (!m) throw new UnresolvableDeclaration(resource, `count is not exactly var.<name> ? 1 : 0: ${count}`);
    const v = vars.get(m[1]);
    if (!v || v.kind !== "bool") {
      throw new UnresolvableDeclaration(resource, `count variable ${m[1]} has no literal bool default`);
    }
    return { keys: v.value ? [undefined] : [], countGated: true };
  }
  return { keys: [undefined], countGated: false };
}

// ─── Declarations ───────────────────────────────────────────────────────────────────────────────

/**
 * Every concrete `betteruptime_heartbeat` instance in one `.tf` text, with `for_each`/`count`
 * resolved against `vars`. Throws on an unbalanced block (never silently drop a heartbeat) and
 * `UnresolvableDeclaration` on a name/meta-argument shape it cannot resolve exactly.
 */
export function parseHeartbeatBlocks(tfText: string, vars: InfraVariables = new Map()): DiscoveredHeartbeat[] {
  const stripped = stripComments(tfText);
  const out: DiscoveredHeartbeat[] = [];
  for (const { resourceName, body } of resourceBlocks(stripped, "betteruptime_heartbeat")) {
    const resource = `betteruptime_heartbeat.${resourceName}`;
    const attrs = topLevelAttributes(body);
    const { keys, countGated } = resolveInstances(resource, attrs, vars);
    const rawName = attrs.get("name");
    if (rawName === undefined) throw new UnresolvableDeclaration(resource, "no name attribute");
    // Absent `paused` defaults to active (false) — the conservative reading; an omission cannot
    // silently exempt a live heartbeat. Mirrors heartbeat-reprovision-parity.test.ts.
    const sourcePaused = attrs.get("paused") === "true";
    for (const key of keys) {
      const liveName = decodeString(rawName, key);
      if (liveName === null || liveName === "") {
        throw new UnresolvableDeclaration(resource, `name is not a literal (or \${each.key} template): ${rawName}`);
      }
      out.push({ resourceName, liveName, sourcePaused, countGated });
    }
  }
  return out;
}

/**
 * Every concrete `betteruptime_monitor` instance in one `.tf` text (#7884). `url` and
 * `monitor_type` must be literal strings; `required_keyword` a literal string or absent; `paused`
 * a literal bool or absent. Duplicate URLs across files are checked by `assertUniqueMonitorUrls`.
 */
export function parseMonitorBlocks(tfText: string, vars: InfraVariables = new Map()): DiscoveredMonitor[] {
  const stripped = stripComments(tfText);
  const out: DiscoveredMonitor[] = [];
  for (const { resourceName, body } of resourceBlocks(stripped, "betteruptime_monitor")) {
    const resource = `betteruptime_monitor.${resourceName}`;
    const attrs = topLevelAttributes(body);
    const { keys } = resolveInstances(resource, attrs, vars);
    const rawUrl = attrs.get("url");
    const url = rawUrl === undefined ? null : decodeString(rawUrl);
    if (url === null || url === "") throw new UnresolvableDeclaration(resource, "url is not a literal string");
    const rawType = attrs.get("monitor_type");
    const monitorType = rawType === undefined ? null : decodeString(rawType);
    if (monitorType === null) throw new UnresolvableDeclaration(resource, "monitor_type is not a literal string");
    const rawKw = attrs.get("required_keyword");
    const requiredKeyword = rawKw === undefined ? "" : decodeString(rawKw);
    if (requiredKeyword === null) throw new UnresolvableDeclaration(resource, "required_keyword is not a literal string");
    const rawPaused = attrs.get("paused");
    if (rawPaused !== undefined && rawPaused !== "true" && rawPaused !== "false") {
      throw new UnresolvableDeclaration(resource, "paused is not a literal bool");
    }
    for (const _ of keys) {
      out.push({ resourceName, url, monitorType, requiredKeyword, paused: rawPaused === "true" });
    }
  }
  return out;
}

/** Two declared monitor instances on one URL are ambiguous (which one owns the live object?). */
export function assertUniqueMonitorUrls(declared: readonly DiscoveredMonitor[]): void {
  const seen = new Set<string>();
  for (const d of declared) {
    if (seen.has(d.url)) {
      throw new UnresolvableDeclaration(`betteruptime_monitor.${d.resourceName}`, `duplicate declared url ${d.url}`);
    }
    seen.add(d.url);
  }
}

/** Extract every `logtail_exploration_alert` block's live name (#8097 `logs_alert` arm). */
export function parseLogsAlertBlocks(tfText: string): DiscoveredLogsAlert[] {
  const stripped = stripComments(tfText);
  return resourceBlocks(stripped, "logtail_exploration_alert").map(({ resourceName, body }) => {
    const nameMatch = /\bname\s*=\s*"([^"]+)"/.exec(body);
    return { resourceName, liveName: nameMatch ? nameMatch[1] : "" };
  });
}

// ─── Reconcile ──────────────────────────────────────────────────────────────────────────────────

/**
 * Reconcile the declared Logs alerts against the live Telemetry payload (#8097 / ADR-218).
 *
 * - **logs-alert-absent** — a declared `logtail_exploration_alert` missing from the live payload
 *   (the main apply never created it, or it was deleted vendor-side).
 * - **logs-alert-paused** — present but `paused` live. Unlike heartbeats there is no fed/unfed
 *   distinction: every declared alert writes `paused = false` as intent, so a live pause is
 *   always a vendor-side rejection (`paused_reason` carried as `detail`) or a hand pause.
 *
 * Foreign live alerts (not declared in `.tf`) are ignored — the arm only READS.
 */
export function reconcileLogsAlerts(
  declared: readonly DiscoveredLogsAlert[],
  live: readonly LiveLogsAlert[],
): LogsAlertViolation[] {
  const byName = new Map<string, LiveLogsAlert>();
  for (const a of live) byName.set(a.name, a);
  const violations: LogsAlertViolation[] = [];
  for (const d of declared) {
    const l = byName.get(d.liveName);
    if (!l) {
      violations.push({ kind: "logs_alert", resourceName: d.resourceName, liveName: d.liveName, live: "logs_alert", reason: "logs-alert-absent" });
      continue;
    }
    if (l.paused) {
      violations.push({
        kind: "logs_alert",
        resourceName: d.resourceName,
        liveName: d.liveName,
        live: "logs_alert",
        reason: "logs-alert-paused",
        detail: l.pausedReason,
      });
    }
  }
  return violations;
}

type ManifestRow = Pick<ManifestEntry, "name" | "feeder" | "arming_pending">;

/**
 * Reconcile the live Better Stack payload against the MANIFEST + discovered `.tf` instances.
 *
 * - **(a) fed-but-paused** — a heartbeat instance whose MANIFEST feeder is a working feeder
 *   (`kind ∈ {cron,timer}`) that is `paused` in the live payload (the #6537 9-days-dark shape).
 *   A row carrying `arming_pending` is EXEMPT from (a): its paused state is a deliberately-deferred
 *   arming window owned by an issue (ADR-117's FED-but-inert legal state), not a forgotten monitor.
 * - **(b) absent-live** — a resolved instance present in `.tf`/MANIFEST but missing from the live
 *   payload (the `git_data_prd` shape, #6548). A `count` resolved to 0 yields no instance at all
 *   (the item-1 paid-tier carve-out, evaluated rather than assumed since #7884).
 *   `arming_pending` does NOT exempt (b) — a declared-but-not-applied monitor is still surfaced.
 *
 * Iterates CONCRETE names: a `for_each` resource is checked once per resolved key (#7884 — the
 * templated `${each.key}` name used to be compared verbatim and always read absent).
 * The two classes are mutually exclusive per instance (present-but-paused vs. absent).
 */
export function reconcileHeartbeats(
  manifest: readonly ManifestRow[],
  discovered: readonly DiscoveredHeartbeat[],
  live: readonly LiveHeartbeat[],
): HeartbeatViolation[] {
  const livePausedByName = new Map<string, boolean>();
  for (const hb of live) livePausedByName.set(hb.name, livePausedByName.get(hb.name) === true || hb.paused);

  const discByResource = new Map<string, DiscoveredHeartbeat[]>();
  for (const d of discovered) {
    const list = discByResource.get(d.resourceName) ?? [];
    list.push(d);
    discByResource.set(d.resourceName, list);
  }

  const violations: HeartbeatViolation[] = [];
  for (const row of manifest) {
    // A manifest row with no matching .tf instance is a source-consistency issue that the static
    // parity test owns (or a count resolved to 0); the live reconcile has no name to check, so skip.
    const instances = discByResource.get(row.name) ?? [];
    const fed = row.feeder.kind === "cron" || row.feeder.kind === "timer";
    for (const disc of instances) {
      const present = livePausedByName.has(disc.liveName);
      if (!present) {
        violations.push({ kind: "heartbeat", resourceName: disc.resourceName, liveName: disc.liveName, live: "absent", reason: "absent-live" });
        continue;
      }
      if (fed && !row.arming_pending && livePausedByName.get(disc.liveName) === true) {
        violations.push({ kind: "heartbeat", resourceName: disc.resourceName, liveName: disc.liveName, live: "paused", reason: "fed-but-paused" });
      }
    }
  }
  return violations;
}

/**
 * `unmanaged-live` per live heartbeat whose name is no declared instance's name, and for EVERY
 * live heartbeat of a name that ≥2 live heartbeats share (`dup`; none is picked as the managed one).
 */
export function findUnmanagedHeartbeats(
  declared: readonly DiscoveredHeartbeat[],
  live: readonly LiveHeartbeat[],
): UnmanagedViolation[] {
  const declaredNames = new Set(declared.map((d) => d.liveName));
  const countByName = new Map<string, number>();
  for (const hb of live) countByName.set(hb.name, (countByName.get(hb.name) ?? 0) + 1);
  const out: UnmanagedViolation[] = [];
  for (const hb of live) {
    const dup = (countByName.get(hb.name) ?? 0) >= 2;
    if (dup || !declaredNames.has(hb.name)) {
      out.push({ kind: "unmanaged", surface: "heartbeats", reason: "unmanaged-live", id: hb.id, name: hb.name, dup });
    }
  }
  return out;
}

/** Group live monitors by URL (shared by `reconcileMonitors` and `matchedMonitorIds`). */
function liveMonitorsByUrl(live: readonly LiveMonitor[]): Map<string, LiveMonitor[]> {
  const byUrl = new Map<string, LiveMonitor[]>();
  for (const m of live) {
    const list = byUrl.get(m.url) ?? [];
    list.push(m);
    byUrl.set(m.url, list);
  }
  return byUrl;
}

/**
 * Reconcile declared monitor instances against the live monitors (#7884).
 *
 * - **absent-live** — a declared instance with no live monitor on its URL.
 * - **monitor-config-drift** — exactly one live monitor on a declared URL whose `monitor_type`,
 *   `required_keyword` (`null` == `""`) or `paused` differs; one row per field.
 * - **unmanaged-live** — a live monitor whose URL matches no declared instance, or every live
 *   monitor on a URL that ≥2 live monitors share (`dup`; none is picked as managed).
 */
export function reconcileMonitors(
  declared: readonly DiscoveredMonitor[],
  live: readonly LiveMonitor[],
): (MonitorViolation | UnmanagedViolation)[] {
  const liveByUrl = liveMonitorsByUrl(live);
  const declaredUrls = new Set(declared.map((d) => d.url));

  const violations: (MonitorViolation | UnmanagedViolation)[] = [];
  for (const d of declared) {
    const onUrl = liveByUrl.get(d.url) ?? [];
    if (onUrl.length === 0) {
      violations.push({ kind: "monitor", reason: "absent-live", resourceName: d.resourceName, url: d.url });
      continue;
    }
    if (onUrl.length !== 1) continue; // every one of them is reported below as dup=url
    const l = onUrl[0];
    const drift = (field: MonitorField, declaredValue: string, liveValue: string) => {
      if (declaredValue !== liveValue) {
        violations.push({ kind: "monitor", reason: "monitor-config-drift", resourceName: d.resourceName, id: l.id, field, declared: declaredValue, live: liveValue });
      }
    };
    drift("monitor_type", d.monitorType, l.monitorType);
    drift("required_keyword", d.requiredKeyword, l.requiredKeyword ?? "");
    drift("paused", String(d.paused), String(l.paused));
  }
  for (const l of live) {
    const dup = (liveByUrl.get(l.url)?.length ?? 0) >= 2;
    if (dup || !declaredUrls.has(l.url)) {
      violations.push({ kind: "unmanaged", surface: "monitors", reason: "unmanaged-live", id: l.id, url: l.url, name: l.name, dup });
    }
  }
  return violations;
}

/** Live ids that exactly one declared instance owns (its URL has exactly one live monitor), ascending. */
export function matchedMonitorIds(declared: readonly DiscoveredMonitor[], live: readonly LiveMonitor[]): string[] {
  const liveByUrl = liveMonitorsByUrl(live);
  const ids: string[] = [];
  for (const d of declared) {
    const onUrl = liveByUrl.get(d.url) ?? [];
    if (onUrl.length === 1) ids.push(onUrl[0].id);
  }
  return ids.sort((a, b) => Number(a) - Number(b));
}
