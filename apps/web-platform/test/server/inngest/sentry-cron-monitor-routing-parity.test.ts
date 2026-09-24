// 2026-09-24 — #8630 Guard 1: cron-monitor routing parity.
//
// Every `sentry_cron_monitor` declared anywhere in the Sentry root must be
// EITHER listed in `sentry_alert.cron_monitor_failure.monitor_ids` (as
// `sentry_cron_monitor.<label>.id`) OR listed in
// `local.cron_monitor_alert_unrouted` with a reason citing `#<issue>` — never
// both, never neither. Without this, a new monitor detects its missed check-in,
// opens a Sentry issue, and emails nobody (the #8630 class: every cron monitor
// in the root, zero alert workflows).
//
// Why a separate file: `sentry-monitor-iac-parity.test.ts` reads only
// `cron-monitors.tf`; this guard must read every `infra/sentry/*.tf` (a monitor
// declared in a sibling file is still a monitor).
//
// Parsing: comments (`#`, `//`, `/* ... */`, string-aware) are stripped first,
// so header prose and commented-out elements or map entries cannot match
// (`cq-assert-anchor-not-bare-token`). Routes are read ONLY from the top-level
// `monitor_ids` attribute of `resource "sentry_alert" "cron_monitor_failure"`
// in cron-monitor-alerts.tf (header line to the first `^}` line — `terraform
// fmt` layout); a `monitor_ids` anywhere else (a local, another resource, a
// heredoc, a nested block) routes nothing, and a non-list expression is RED.
// `*.tf.json` and override files are RED outright: Terraform merges them and
// this parser does not model them.
//
// `checkRouting` is a pure function over {filename: contents}; the fixture rows
// never read the real tree. Three rows do: the real-tree parity row, the
// anti-vacuity row (cross-checks the parser against DERIVATION_CMD run by
// grep/awk), and the binding-gate address parity row.
//
// Known limit: the guard compares .tf with .tf inside one commit. A single diff
// can move a live monitor into the unrouted map under any issue number; the
// guard cannot check that issue offline (see the plan's §Guard Contract).

import { execSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const REPO_ROOT = resolve(__dirname, "../../../../..");
const SENTRY_DIR = resolve(__dirname, "../../../infra/sentry");
const GATE_SCRIPT = resolve(REPO_ROOT, "scripts/sentry-monitor-binding-gate.sh");
const ALERT_FILE = "cron-monitor-alerts.tf";
const ALERT_LABEL = "cron_monitor_failure";
const ALERT_HEADER_RE = new RegExp(`^resource "sentry_alert" "${ALERT_LABEL}"\\s*\\{\\s*$`);

const DERIVATION_CMD =
  "grep -hoE '^resource \"sentry_cron_monitor\" \"[a-z0-9_]+\"' apps/web-platform/infra/sentry/*.tf | awk -F'\"' '{print $4}' | LC_ALL=C sort";

interface RoutingFindings {
  /** Labels of every declared `sentry_cron_monitor`, sorted. */
  declared: string[];
  /** True when zero monitors were read (the guard's own dispatch is broken). */
  vacuous: boolean;
  /** `*.tf.json` / override files present: Terraform reads them, this parser does not. */
  unsupportedConfigFiles: string[];
  /** True when the alert resource, or its top-level `monitor_ids`, is absent from the alert file. */
  routesBlockMissing: boolean;
  /** The alert's `monitor_ids` value when it is not an inline `[ ... ]` list. */
  routesNotInlineList: string[];
  /** True when no `locals { cron_monitor_alert_unrouted = ... }` exists in any file. */
  unroutedMapMissing: boolean;
  /** Declared monitors in neither `monitor_ids` nor the unrouted map. */
  unrouted: string[];
  /** Labels present in both `monitor_ids` and the unrouted map. */
  doubleListed: string[];
  /** Unrouted-map keys whose reason cites no `#<n>` issue. */
  reasonWithoutIssue: string[];
  /** `monitor_ids` elements that are not `sentry_cron_monitor.<label>.id`. */
  nonReferenceElements: string[];
  /** Unrouted-map keys naming no declared monitor (stale entry). */
  unroutedWithoutMonitor: string[];
  /** `monitor_ids` references naming no declared monitor. */
  routedWithoutMonitor: string[];
  /** Labels listed more than once in `monitor_ids`. */
  duplicateRoutes: string[];
}

// Remove `#` / `//` line comments and `/* ... */` block comments (multi-line
// too), outside double-quoted strings, so `"... (#1234)"` survives. Newlines
// inside a block comment are kept so line structure is preserved. HCL quoted
// strings are single-line, so a newline ends string state (heredoc recovery).
function stripComments(src: string): string {
  let out = "";
  let inStr = false;
  let i = 0;
  while (i < src.length) {
    const c = src[i];
    if (inStr) {
      if (c === "\\") {
        out += src.slice(i, i + 2);
        i += 2;
        continue;
      }
      if (c === '"' || c === "\n") inStr = false;
      out += c;
      i++;
      continue;
    }
    if (c === '"') {
      inStr = true;
      out += c;
      i++;
    } else if (c === "#" || (c === "/" && src[i + 1] === "/")) {
      while (i < src.length && src[i] !== "\n") i++;
    } else if (c === "/" && src[i + 1] === "*") {
      const end = src.indexOf("*/", i + 2);
      const stop = end === -1 ? src.length : end + 2;
      out += src.slice(i, stop).replace(/[^\n]/g, "");
      i = stop;
    } else {
      out += c;
      i++;
    }
  }
  return out;
}

// Net `{[(` minus `}])` on a comment-stripped line, ignoring string contents.
function bracketDelta(line: string): number {
  let d = 0;
  let inStr = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inStr) {
      if (c === "\\") i++;
      else if (c === '"') inStr = false;
    } else if (c === '"') inStr = true;
    else if ("{[(".includes(c)) d++;
    else if ("}])".includes(c)) d--;
  }
  return d;
}

// Body lines of every top-level block whose header matches `header`, from the
// header line to the first following `^}` line (`terraform fmt` layout).
function blockBodies(lines: string[], header: RegExp): string[][] {
  const bodies: string[][] = [];
  for (let i = 0; i < lines.length; i++) {
    if (!header.test(lines[i])) continue;
    let j = i + 1;
    while (j < lines.length && !/^\}\s*$/.test(lines[j])) j++;
    bodies.push(lines.slice(i + 1, j));
    i = j;
  }
  return bodies;
}

// Value text of attribute `name` at depth 0 of `body` (first match), or null.
// When the value opens with `open`, returns the text between it and its
// matching close (string-aware, may span lines); otherwise `{ literal: false }`.
function attributeValue(
  body: string[],
  name: string,
  open: "[" | "{",
): { literal: true; inner: string } | { literal: false; expr: string } | null {
  const close = open === "[" ? "]" : "}";
  const attrRe = new RegExp(`^\\s*${name}\\s*=\\s*(.*)$`);
  let depth = 0;
  for (let i = 0; i < body.length; i++) {
    const m = depth === 0 ? body[i].match(attrRe) : null;
    if (m) {
      const rest = [m[1], ...body.slice(i + 1)].join("\n").trimStart();
      if (!rest.startsWith(open)) {
        return { literal: false, expr: m[1].trim() };
      }
      let d = 0;
      let inStr = false;
      for (let k = 0; k < rest.length; k++) {
        const c = rest[k];
        if (inStr) {
          if (c === "\\") k++;
          else if (c === '"' || c === "\n") inStr = false;
        } else if (c === '"') inStr = true;
        else if ("{[(".includes(c)) d++;
        else if ("}])".includes(c)) {
          d--;
          if (d === 0 && c === close) return { literal: true, inner: rest.slice(1, k) };
        }
      }
      return { literal: true, inner: rest.slice(1) };
    }
    depth += bracketDelta(body[i]);
  }
  return null;
}

// Split list text at depth-0 commas (string-aware); trimmed, non-empty.
function splitTopLevel(inner: string): string[] {
  const parts: string[] = [];
  let cur = "";
  let d = 0;
  let inStr = false;
  for (let k = 0; k < inner.length; k++) {
    const c = inner[k];
    if (inStr) {
      if (c === "\\") {
        cur += c + (inner[k + 1] ?? "");
        k++;
        continue;
      }
      if (c === '"' || c === "\n") inStr = false;
    } else if (c === '"') inStr = true;
    else if ("{[(".includes(c)) d++;
    else if ("}])".includes(c)) d--;
    else if (c === "," && d === 0) {
      parts.push(cur);
      cur = "";
      continue;
    }
    cur += c;
  }
  parts.push(cur);
  return parts.map((p) => p.trim().replace(/\s+/g, " ")).filter(Boolean);
}

function isTf(name: string): boolean {
  return name.endsWith(".tf");
}

// Config files Terraform loads that this parser does not model.
function unsupportedConfigFiles(names: string[]): string[] {
  return names
    .filter((n) => n.endsWith(".tf.json") || /(^|_)override\.tf(\.json)?$/.test(n))
    .sort();
}

function declaredMonitors(files: Record<string, string>): string[] {
  const labels: string[] = [];
  for (const name of Object.keys(files).filter(isTf)) {
    for (const m of stripComments(files[name]).matchAll(
      /^resource "sentry_cron_monitor" "([a-z0-9_]+)"/gm,
    )) {
      labels.push(m[1]);
    }
  }
  return labels.sort();
}

// The alert's own `monitor_ids`: only the top-level attribute of
// `resource "sentry_alert" "cron_monitor_failure"` in ALERT_FILE.
function routeList(src: string | undefined): {
  found: boolean;
  expressions: string[];
  elements: string[];
} {
  const none = { found: false, expressions: [], elements: [] };
  if (src === undefined) return none;
  const [body] = blockBodies(stripComments(src).split("\n"), ALERT_HEADER_RE);
  if (!body) return none;
  const v = attributeValue(body, "monitor_ids", "[");
  if (v === null) return none;
  if (!v.literal) return { found: true, expressions: [v.expr], elements: [] };
  return { found: true, expressions: [], elements: splitTopLevel(v.inner) };
}

// Keys (and string reasons) of `locals { cron_monitor_alert_unrouted = {...} }`
// across every .tf file (a local is unique across the root).
function unroutedEntries(files: Record<string, string>): {
  found: boolean;
  entries: Map<string, string>;
} {
  const entries = new Map<string, string>();
  let found = false;
  const entryRe = /^"?([a-z0-9_]+)"?\s*[=:]\s*"((?:[^"\\]|\\.)*)"$/;
  for (const name of Object.keys(files).filter(isTf).sort()) {
    const lines = stripComments(files[name]).split("\n");
    for (const body of blockBodies(lines, /^locals\s*\{\s*$/)) {
      const v = attributeValue(body, "cron_monitor_alert_unrouted", "{");
      if (v === null) continue;
      found = true;
      if (!v.literal) continue;
      // Entries are newline- or comma-separated.
      for (const line of v.inner.split("\n")) {
        for (const part of splitTopLevel(line)) {
          const m = part.match(entryRe);
          if (m) entries.set(m[1], m[2]);
        }
      }
    }
  }
  return { found, entries };
}

function checkRouting(files: Record<string, string>): RoutingFindings {
  const declared = declaredMonitors(files);
  const declaredSet = new Set(declared);
  const { found, expressions, elements } = routeList(files[ALERT_FILE]);

  const nonReferenceElements: string[] = [];
  const routed: string[] = [];
  for (const el of elements) {
    const m = el.match(/^sentry_cron_monitor\.([a-z0-9_]+)\.id$/);
    if (m) routed.push(m[1]);
    else nonReferenceElements.push(el);
  }
  const routedSet = new Set(routed);
  const duplicateRoutes = [
    ...new Set(routed.filter((l, i) => routed.indexOf(l) !== i)),
  ].sort();

  const unroutedMap = unroutedEntries(files);
  const unroutedKeys = [...unroutedMap.entries.keys()];

  return {
    declared,
    vacuous: declared.length === 0,
    unsupportedConfigFiles: unsupportedConfigFiles(Object.keys(files)),
    routesBlockMissing: !found,
    routesNotInlineList: expressions,
    unroutedMapMissing: !unroutedMap.found,
    unrouted: declared.filter(
      (l) => !routedSet.has(l) && !unroutedMap.entries.has(l),
    ),
    doubleListed: unroutedKeys.filter((l) => routedSet.has(l)).sort(),
    reasonWithoutIssue: unroutedKeys
      .filter((l) => !/#\d+/.test(unroutedMap.entries.get(l) ?? ""))
      .sort(),
    nonReferenceElements,
    unroutedWithoutMonitor: unroutedKeys
      .filter((l) => !declaredSet.has(l))
      .sort(),
    routedWithoutMonitor: [...routedSet]
      .filter((l) => !declaredSet.has(l))
      .sort(),
    duplicateRoutes,
  };
}

function isClean(f: RoutingFindings): boolean {
  return (
    !f.vacuous &&
    f.unsupportedConfigFiles.length === 0 &&
    !f.routesBlockMissing &&
    f.routesNotInlineList.length === 0 &&
    !f.unroutedMapMissing &&
    f.unrouted.length === 0 &&
    f.doubleListed.length === 0 &&
    f.reasonWithoutIssue.length === 0 &&
    f.nonReferenceElements.length === 0 &&
    f.unroutedWithoutMonitor.length === 0 &&
    f.routedWithoutMonitor.length === 0 &&
    f.duplicateRoutes.length === 0
  );
}

function formatFindings(f: RoutingFindings): string {
  const out: string[] = [];
  if (f.vacuous) {
    out.push(
      "- zero sentry_cron_monitor resources were read: the guard itself is broken (wrong dir or parser).",
    );
  }
  for (const n of f.unsupportedConfigFiles) {
    out.push(
      `- infra/sentry/${n}: *.tf.json / override files are not parsed by this guard (Terraform merges them, so a monitor or route there is invisible here) — write plain .tf instead.`,
    );
  }
  if (f.routesBlockMissing) {
    out.push(
      `- no top-level \`monitor_ids = [...]\` in \`resource "sentry_alert" "${ALERT_LABEL}"\` in infra/sentry/${ALERT_FILE} (the resource must live in that file; a monitor_ids anywhere else routes nothing).`,
    );
  }
  for (const e of f.routesNotInlineList) {
    out.push(
      `- sentry_alert.${ALERT_LABEL}.monitor_ids is \`${e}\`, not an inline list — write one \`sentry_cron_monitor.<label>.id\` element per monitor.`,
    );
  }
  if (f.unroutedMapMissing) {
    out.push(
      "- `locals { cron_monitor_alert_unrouted = {...} }` is missing — keep it, as `{}` when empty.",
    );
  }
  for (const l of f.unrouted) {
    out.push(
      `- ${l}: declared but routed nowhere. Add \`sentry_cron_monitor.${l}.id,\` to monitor_ids in ${ALERT_FILE}, ` +
        `or (a monitor created in THIS PR — two-PR rule) add \`${l} = "<reason> (#N)"\` to cron_monitor_alert_unrouted.`,
    );
  }
  for (const l of f.doubleListed) {
    out.push(
      `- ${l}: in BOTH monitor_ids and cron_monitor_alert_unrouted — remove it from one.`,
    );
  }
  for (const l of f.reasonWithoutIssue) {
    out.push(
      `- ${l}: cron_monitor_alert_unrouted reason cites no issue — write \`${l} = "<reason> (#N)"\`.`,
    );
  }
  for (const e of f.nonReferenceElements) {
    out.push(
      `- monitor_ids element \`${e}\` is not a sentry_cron_monitor.<label>.id reference.`,
    );
  }
  for (const l of f.unroutedWithoutMonitor) {
    out.push(
      `- ${l}: cron_monitor_alert_unrouted names no declared sentry_cron_monitor — delete the stale entry.`,
    );
  }
  for (const l of f.routedWithoutMonitor) {
    out.push(
      `- ${l}: monitor_ids references an undeclared sentry_cron_monitor.`,
    );
  }
  for (const l of f.duplicateRoutes) {
    out.push(`- ${l}: listed more than once in monitor_ids.`);
  }
  if (out.length === 0) return "";
  return [
    "cron-monitor routing parity (Guard 1, #8630) failed:",
    ...out,
    `Derive the declared label set with: ${DERIVATION_CMD}`,
  ].join("\n");
}

// Every .tf and .tf.json in the root (the latter only to be flagged).
function realTree(): Record<string, string> {
  const files: Record<string, string> = {};
  for (const f of readdirSync(SENTRY_DIR)) {
    if (/\.tf(\.json)?$/.test(f)) files[f] = readFileSync(resolve(SENTRY_DIR, f), "utf-8");
  }
  return files;
}

// ---- fixture helpers -------------------------------------------------------

function monitorBlock(label: string): string {
  return [
    `resource "sentry_cron_monitor" "${label}" {`,
    `  organization = var.sentry_org`,
    `  name         = "${label.replace(/_/g, "-")}"`,
    `}`,
    ``,
  ].join("\n");
}

function alertFile(
  elements: string[],
  unrouted: Record<string, string> | null = {},
): string {
  const entries = Object.entries(unrouted ?? {}).map(
    ([k, v]) => `    ${k} = "${v}"`,
  );
  const map =
    unrouted === null
      ? `  unrelated_local = {}`
      : entries.length
        ? [`  cron_monitor_alert_unrouted = {`, ...entries, `  }`].join("\n")
        : `  cron_monitor_alert_unrouted = {}`;
  return [
    `# Header prose quoting monitor_ids = [ and cron_monitor_alert_unrouted = { and`,
    `# resource "sentry_cron_monitor" "decoy_in_comment" must not match.`,
    `locals {`,
    map,
    `}`,
    ``,
    `resource "sentry_alert" "cron_monitor_failure" {`,
    `  organization = var.sentry_org`,
    `  monitor_ids = [`,
    ...elements.map((e) => `    ${e},`),
    `  ]`,
    `}`,
    ``,
  ].join("\n");
}

const ref = (l: string) => `sentry_cron_monitor.${l}.id`;

// ---- tests -----------------------------------------------------------------

describe("cron-monitor routing parity (Guard 1, #8630)", () => {
  it("real tree: every declared sentry_cron_monitor is routed or declared-unrouted", () => {
    const f = checkRouting(realTree());
    expect(isClean(f), formatFindings(f)).toBe(true);
  });

  it("row 2 (anti-vacuity): real tree declares >= 1 monitor, the same labels DERIVATION_CMD (grep/awk) derives", () => {
    // Independent of the parser: a different engine (grep -E + awk) over the raw
    // files, and it also proves the command the failure message prints works.
    const derived = execSync(DERIVATION_CMD, {
      cwd: REPO_ROOT,
      shell: "/bin/bash",
      encoding: "utf-8",
    })
      .split("\n")
      .filter(Boolean);
    const f = checkRouting(realTree());
    expect(derived.length).toBeGreaterThanOrEqual(1);
    expect(f.declared).toEqual(derived);
    expect(f.vacuous).toBe(false);
  });

  it("row 2 (anti-vacuity): zero .tf files or zero monitors is RED", () => {
    const none = checkRouting({});
    expect(none.vacuous).toBe(true);
    expect(isClean(none)).toBe(false);
    const noMonitors = checkRouting({ [ALERT_FILE]: alertFile([]) });
    expect(noMonitors.vacuous).toBe(true);
    expect(isClean(noMonitors)).toBe(false);
  });

  it("row 1: deleting one monitor_ids element is RED, naming that label", () => {
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha") + monitorBlock("beta") + monitorBlock("gamma"),
      [ALERT_FILE]: alertFile([ref("alpha"), ref("gamma")]),
    });
    expect(f.unrouted).toEqual(["beta"]);
    expect(formatFindings(f)).toContain("sentry_cron_monitor.beta.id");
    expect(formatFindings(f)).toContain('beta = "<reason> (#N)"');
    expect(formatFindings(f)).toContain("LC_ALL=C sort");
  });

  it("row 3: two new monitors, only the first routed, is RED naming the second", () => {
    const f = checkRouting({
      "cron-monitors.tf":
        monitorBlock("alpha") + monitorBlock("new_one") + monitorBlock("new_two"),
      [ALERT_FILE]: alertFile([ref("alpha"), ref("new_one")]),
    });
    expect(f.unrouted).toEqual(["new_two"]);
  });

  it("row 4: an unrouted monitor declared in a sibling file (uptime-monitors.tf) is RED", () => {
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha"),
      "uptime-monitors.tf": monitorBlock("sibling_cron"),
      [ALERT_FILE]: alertFile([ref("alpha")]),
    });
    expect(f.unrouted).toEqual(["sibling_cron"]);
    expect(f.declared).toEqual(["alpha", "sibling_cron"]);
  });

  it("row 6: a label in both monitor_ids and unrouted is RED", () => {
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha") + monitorBlock("beta"),
      [ALERT_FILE]: alertFile([ref("alpha"), ref("beta")], {
        beta: "created in this PR (#1234)",
      }),
    });
    expect(f.doubleListed).toEqual(["beta"]);
    expect(f.unrouted).toEqual([]);
    expect(isClean(f)).toBe(false);
  });

  it("row 7: an unrouted reason with no #<n> is RED", () => {
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha") + monitorBlock("beta"),
      [ALERT_FILE]: alertFile([ref("alpha")], { beta: "route later" }),
    });
    expect(f.reasonWithoutIssue).toEqual(["beta"]);
    expect(f.unrouted).toEqual([]);
    expect(isClean(f)).toBe(false);
  });

  it("row 10: a monitor_ids element that is not a sentry_cron_monitor.<label>.id reference is RED", () => {
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha"),
      [ALERT_FILE]: alertFile([ref("alpha"), `"1213799"`]),
    });
    expect(f.nonReferenceElements).toEqual([`"1213799"`]);
    expect(isClean(f)).toBe(false);
  });

  it("row 11: an unrouted key naming no declared monitor is RED", () => {
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha"),
      [ALERT_FILE]: alertFile([ref("alpha")], {
        deleted_monitor: "left behind (#77)",
      }),
    });
    expect(f.unroutedWithoutMonitor).toEqual(["deleted_monitor"]);
    expect(isClean(f)).toBe(false);
  });

  it("P1 (must PASS): reordered elements, odd whitespace, trailing comments", () => {
    const alert = [
      `locals {`,
      `  cron_monitor_alert_unrouted = {}`,
      `}`,
      `resource "sentry_alert" "cron_monitor_failure" {`,
      `  monitor_ids    =   [`,
      `      sentry_cron_monitor.gamma.id ,   # trailing comment`,
      `sentry_cron_monitor.alpha.id,// another`,
      `  # sentry_cron_monitor.not_a_real_one.id,`,
      `\tsentry_cron_monitor.beta.id`,
      `  ]`,
      `}`,
    ].join("\n");
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha") + monitorBlock("beta") + monitorBlock("gamma"),
      [ALERT_FILE]: alert,
    });
    expect(isClean(f), formatFindings(f)).toBe(true);
  });

  it("P1 (must PASS): single-line monitor_ids = [sentry_cron_monitor.x.id] form", () => {
    const alert = [
      `locals {`,
      `  cron_monitor_alert_unrouted = {}`,
      `}`,
      `resource "sentry_alert" "cron_monitor_failure" {`,
      `  monitor_ids = [sentry_cron_monitor.x.id]`,
      `  trigger_conditions = [`,
      `    { first_seen_event = {} },`,
      `  ]`,
      `}`,
    ].join("\n");
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("x"),
      [ALERT_FILE]: alert,
    });
    expect(isClean(f), formatFindings(f)).toBe(true);
  });

  it("P2 (must PASS): a monitor in unrouted with a valid (#1234) reason and absent from monitor_ids", () => {
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha") + monitorBlock("brand_new"),
      [ALERT_FILE]: alertFile([ref("alpha")], {
        brand_new: "created in this PR; route after first apply (#1234)",
      }),
    });
    expect(isClean(f), formatFindings(f)).toBe(true);
  });
  it("row 12 (decoy): a `locals { monitor_ids = [...] }` decoy cannot stand in for the alert's own list", () => {
    const alert = [
      `locals {`,
      `  cron_monitor_alert_unrouted = {}`,
      `  monitor_ids = [`,
      `    sentry_cron_monitor.alpha.id,`,
      `    sentry_cron_monitor.beta.id,`,
      `  ]`,
      `}`,
      `resource "sentry_alert" "cron_monitor_failure" {`,
      `  organization = var.sentry_org`,
      `  monitor_ids  = slice(local.monitor_ids, 0, 1)`,
      `}`,
    ].join("\n");
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha") + monitorBlock("beta"),
      [ALERT_FILE]: alert,
    });
    expect(f.routesNotInlineList).toEqual(["slice(local.monitor_ids, 0, 1)"]);
    expect(f.unrouted).toEqual(["alpha", "beta"]);
    expect(formatFindings(f)).toContain("slice(local.monitor_ids, 0, 1)");
    expect(isClean(f)).toBe(false);
    // Isolated: every monitor declared-unrouted, so the expression is the only finding.
    const only = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha"),
      [ALERT_FILE]: alert.replace(
        "cron_monitor_alert_unrouted = {}",
        'cron_monitor_alert_unrouted = { alpha = "pending (#1)" }',
      ),
    });
    expect(only.unrouted).toEqual([]);
    expect(only.routesNotInlineList).toEqual(["slice(local.monitor_ids, 0, 1)"]);
    expect(isClean(only)).toBe(false);
  });

  it("row 13 (decoy): another resource's monitor_ids, or a heredoc line, does not route a monitor", () => {
    const alert = [
      alertFile([ref("alpha")]),
      `resource "sentry_alert" "some_other_alert" {`,
      `  monitor_ids = [`,
      `    sentry_cron_monitor.beta.id,`,
      `  ]`,
      `}`,
      `resource "terraform_data" "doc" {`,
      `  input = <<-EOT`,
      `  monitor_ids = [sentry_cron_monitor.gamma.id]`,
      `  EOT`,
      `}`,
    ].join("\n");
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha") + monitorBlock("beta") + monitorBlock("gamma"),
      [ALERT_FILE]: alert,
    });
    expect(f.unrouted).toEqual(["beta", "gamma"]);
    expect(isClean(f)).toBe(false);
  });

  it("row 14: monitor_ids only inside a nested block of the alert is RED (not the alert's attribute)", () => {
    const alert = [
      `locals {`,
      `  cron_monitor_alert_unrouted = {}`,
      `}`,
      `resource "sentry_alert" "cron_monitor_failure" {`,
      `  action_filters = [`,
      `    {`,
      `      monitor_ids = [sentry_cron_monitor.alpha.id]`,
      `    },`,
      `  ]`,
      `}`,
    ].join("\n");
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha"),
      [ALERT_FILE]: alert,
    });
    expect(f.routesBlockMissing).toBe(true);
    expect(f.unrouted).toEqual(["alpha"]);
    expect(isClean(f)).toBe(false);
  });

  it("row 15: the alert resource moved out of cron-monitor-alerts.tf is RED", () => {
    const moved = alertFile([ref("alpha")]);
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha"),
      [ALERT_FILE]: [`locals {`, `  cron_monitor_alert_unrouted = {}`, `}`].join("\n"),
      "other-alerts.tf": moved.replace(/^locals \{[\s\S]*?^\}\n/m, ""),
    });
    expect(f.routesBlockMissing).toBe(true);
    expect(formatFindings(f)).toContain(`resource "sentry_alert" "cron_monitor_failure"`);
    expect(isClean(f)).toBe(false);
    // Isolated: every monitor declared-unrouted, so the missing block is the only finding.
    const only = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha"),
      [ALERT_FILE]: [`locals {`, `  cron_monitor_alert_unrouted = { alpha = "pending (#1)" }`, `}`].join("\n"),
    });
    expect(only.unrouted).toEqual([]);
    expect(only.routesBlockMissing).toBe(true);
    expect(isClean(only)).toBe(false);
  });

  it("row 16: a /* block comment */ inside monitor_ids routes nothing (single- and multi-line)", () => {
    const alert = [
      `locals {`,
      `  cron_monitor_alert_unrouted = {}`,
      `}`,
      `resource "sentry_alert" "cron_monitor_failure" {`,
      `  monitor_ids = [`,
      `    sentry_cron_monitor.alpha.id, /* sentry_cron_monitor.beta.id, */`,
      `    /*`,
      `    sentry_cron_monitor.gamma.id,`,
      `    */`,
      `  ]`,
      `}`,
    ].join("\n");
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha") + monitorBlock("beta") + monitorBlock("gamma"),
      [ALERT_FILE]: alert,
    });
    expect(f.unrouted).toEqual(["beta", "gamma"]);
    // Terraform ignores the comment entirely: no residue element may survive.
    expect(f.nonReferenceElements).toEqual([]);
    expect(isClean(f)).toBe(false);
  });

  it("row 17: *.tf.json and override files in the root are RED (config the parser does not model)", () => {
    expect(
      unsupportedConfigFiles([
        "cron-monitors.tf",
        "alert-reference.json",
        "vendor-default-workflows.json",
        "extra.tf.json",
        "override.tf",
        "alerts_override.tf",
        "x_override.tf.json",
      ]),
    ).toEqual(["alerts_override.tf", "extra.tf.json", "override.tf", "x_override.tf.json"]);
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha"),
      [ALERT_FILE]: alertFile([ref("alpha")]),
      "extra.tf.json": `{"resource":{"sentry_cron_monitor":{"json_only":{}}}}`,
    });
    expect(f.unsupportedConfigFiles).toEqual(["extra.tf.json"]);
    expect(formatFindings(f)).toContain("extra.tf.json");
    expect(isClean(f)).toBe(false);
  });

  it("row 18: a commented-out unrouted entry does not exempt its monitor", () => {
    const alert = [
      `locals {`,
      `  cron_monitor_alert_unrouted = {`,
      `    # beta = "pending (#12)"`,
      `    // gamma = "pending (#13)"`,
      `    /* delta = "pending (#14)" */`,
      `  }`,
      `}`,
      `resource "sentry_alert" "cron_monitor_failure" {`,
      `  monitor_ids = [sentry_cron_monitor.alpha.id]`,
      `}`,
    ].join("\n");
    const f = checkRouting({
      "cron-monitors.tf":
        monitorBlock("alpha") + monitorBlock("beta") + monitorBlock("gamma") + monitorBlock("delta"),
      [ALERT_FILE]: alert,
    });
    expect(f.unrouted).toEqual(["beta", "delta", "gamma"]);
    expect(isClean(f)).toBe(false);
  });

  it("row 19: every unrouted key's reason is checked, not only the first", () => {
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha") + monitorBlock("beta") + monitorBlock("gamma"),
      [ALERT_FILE]: alertFile([ref("alpha")], { beta: "ok (#1)", gamma: "later" }),
    });
    expect(f.reasonWithoutIssue).toEqual(["gamma"]);
    expect(f.unrouted).toEqual([]);
    expect(isClean(f)).toBe(false);
  });

  it("row 20: a duplicated route and a route to an undeclared monitor are both RED", () => {
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha"),
      [ALERT_FILE]: alertFile([ref("alpha"), ref("alpha"), ref("ghost")]),
    });
    expect(f.duplicateRoutes).toEqual(["alpha"]);
    expect(f.routedWithoutMonitor).toEqual(["ghost"]);
    expect(isClean(f)).toBe(false);
    // Isolated: each finding alone must still be RED.
    const dupOnly = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha"),
      [ALERT_FILE]: alertFile([ref("alpha"), ref("alpha")]),
    });
    expect(dupOnly.routedWithoutMonitor).toEqual([]);
    expect(isClean(dupOnly)).toBe(false);
    const ghostOnly = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha"),
      [ALERT_FILE]: alertFile([ref("alpha"), ref("ghost")]),
    });
    expect(ghostOnly.duplicateRoutes).toEqual([]);
    expect(isClean(ghostOnly)).toBe(false);
  });

  it("row 21: the cron_monitor_alert_unrouted local absent entirely is RED (`{}` stays valid)", () => {
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha"),
      [ALERT_FILE]: alertFile([ref("alpha")], null),
    });
    expect(f.unroutedMapMissing).toBe(true);
    expect(formatFindings(f)).toContain("cron_monitor_alert_unrouted");
    expect(isClean(f)).toBe(false);
    const empty = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha"),
      [ALERT_FILE]: alertFile([ref("alpha")], {}),
    });
    expect(empty.unroutedMapMissing).toBe(false);
    expect(isClean(empty), formatFindings(empty)).toBe(true);
  });

  it("row 22 (parity): the binding gate's cron-bound literal names the alert address declared in the .tf", () => {
    const labels = [
      ...stripComments(readFileSync(resolve(SENTRY_DIR, ALERT_FILE), "utf-8")).matchAll(
        /^resource "sentry_alert" "([a-z0-9_]+)"/gm,
      ),
    ].map((m) => m[1]);
    expect(labels).toEqual([ALERT_LABEL]);
    const address = `sentry_alert.${labels[0]}`;
    const gate = readFileSync(GATE_SCRIPT, "utf-8");
    const literal = gate
      .split("\n")
      .filter((l) => /^CRON_BOUND_ADDRESSES=/.test(l));
    expect(literal, "exactly one CRON_BOUND_ADDRESSES= assignment line").toHaveLength(1);
    expect(literal[0]).toContain(`"${address}"`);
  });
});
