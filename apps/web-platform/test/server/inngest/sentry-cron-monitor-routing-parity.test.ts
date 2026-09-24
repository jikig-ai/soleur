// 2026-09-24 — #8630 Guard 1: cron-monitor routing parity.
//
// Every `sentry_cron_monitor` declared anywhere in the Sentry root must be
// EITHER listed in `sentry_alert.cron_monitor_failure.monitor_ids` (as
// `sentry_cron_monitor.<label>.id`) OR listed in
// `local.cron_monitor_alert_unrouted` with a reason citing `#<issue>` — never
// both, never neither. Without this, a new monitor detects its missed check-in,
// opens a Sentry issue, and emails nobody (the #8630 class: 59 monitors, zero
// alert workflows).
//
// Why a separate file: `sentry-monitor-iac-parity.test.ts` reads only
// `cron-monitors.tf`; this guard must read every `infra/sentry/*.tf` (a monitor
// declared in a sibling file is still a monitor).
//
// Parsing is line-anchored after dropping comment lines, so the alert file's own
// header prose (which quotes `monitor_ids`, `cron_monitor_alert_unrouted` and
// `resource "sentry_alert"`) cannot match (`cq-assert-anchor-not-bare-token`).
// `checkRouting` is a pure function over file contents, so the mutation-matrix
// rows below pass fixture strings and never read the real tree; one row runs it
// over the real tree.
//
// Known limit: the guard compares .tf with .tf inside one commit. A single diff
// can move a live monitor into the unrouted map under any issue number; the
// guard cannot check that issue offline (see the plan's §Guard Contract).

import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const SENTRY_DIR = resolve(__dirname, "../../../infra/sentry");
const ALERT_FILE = "cron-monitor-alerts.tf";

const DERIVATION_CMD =
  "grep -hoE '^resource \"sentry_cron_monitor\" \"[a-z0-9_]+\"' apps/web-platform/infra/sentry/*.tf | awk -F'\"' '{print $4}' | LC_ALL=C sort";

interface RoutingFindings {
  /** Labels of every declared `sentry_cron_monitor`, sorted. */
  declared: string[];
  /** True when zero monitors were read (the guard's own dispatch is broken). */
  vacuous: boolean;
  /** True when no `monitor_ids = [` block was found in the alert file. */
  routesBlockMissing: boolean;
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

// Drop whole-line comments (`#` and `//`). Block comments are not used in
// this root; a `/*` line is dropped too so it cannot smuggle an anchor match.
function codeLines(src: string): string[] {
  return src
    .split("\n")
    .filter((l) => !/^\s*(#|\/\/|\/\*|\*)/.test(l));
}

function stripTrailingComment(line: string): string {
  // Only used on monitor_ids element lines, which carry no string literals
  // with `#` in the valid form. (A string-literal element is flagged as a
  // non-reference either way.)
  return line.replace(/\s*(#|\/\/).*$/, "");
}

function declaredMonitors(files: Record<string, string>): string[] {
  const labels: string[] = [];
  for (const name of Object.keys(files).sort()) {
    if (!name.endsWith(".tf")) continue;
    for (const line of codeLines(files[name])) {
      const m = line.match(/^resource "sentry_cron_monitor" "([a-z0-9_]+)"/);
      if (m) labels.push(m[1]);
    }
  }
  return labels.sort();
}

// Elements of the `monitor_ids = [ ... ]` list(s) in the alert file. Handles
// the `[` ... `]` on one line and the multi-line form (reads to the next `]`).
function routeElements(
  src: string | undefined,
): { found: boolean; elements: string[] } {
  if (src === undefined) return { found: false, elements: [] };
  const lines = codeLines(src);
  const elements: string[] = [];
  let found = false;
  for (let i = 0; i < lines.length; i++) {
    const open = lines[i].match(/^\s*monitor_ids\s*=\s*\[(.*)$/);
    if (!open) continue;
    found = true;
    const chunks: string[] = [];
    let rest = stripTrailingComment(open[1]);
    let j = i;
    while (!rest.includes("]")) {
      chunks.push(rest);
      j++;
      if (j >= lines.length) {
        rest = "]";
        break;
      }
      rest = stripTrailingComment(lines[j]);
    }
    chunks.push(rest.slice(0, rest.indexOf("]")));
    i = j;
    for (const el of chunks.join(",").split(",")) {
      const t = el.trim();
      if (t) elements.push(t);
    }
  }
  return { found, elements };
}

// Keys (and reasons) of `cron_monitor_alert_unrouted = { ... }`, read from
// every file (a local must be unique across the root, so there is one).
function unroutedEntries(files: Record<string, string>): Map<string, string> {
  const out = new Map<string, string>();
  const entryRe = /"?([a-z0-9_]+)"?\s*=\s*"((?:[^"\\]|\\.)*)"/g;
  for (const name of Object.keys(files).sort()) {
    if (!name.endsWith(".tf")) continue;
    const lines = codeLines(files[name]);
    for (let i = 0; i < lines.length; i++) {
      const open = lines[i].match(/^\s*cron_monitor_alert_unrouted\s*=\s*\{(.*)$/);
      if (!open) continue;
      const body: string[] = [];
      const sameLine = open[1];
      if (/\}\s*(#.*|\/\/.*)?$/.test(sameLine)) {
        body.push(sameLine.slice(0, sameLine.lastIndexOf("}")));
      } else {
        body.push(sameLine);
        let j = i + 1;
        while (j < lines.length && !/^\s*\}/.test(lines[j])) {
          body.push(lines[j]);
          j++;
        }
        i = j;
      }
      for (const chunk of body) {
        for (const m of chunk.matchAll(entryRe)) out.set(m[1], m[2]);
      }
    }
  }
  return out;
}

function checkRouting(files: Record<string, string>): RoutingFindings {
  const declared = declaredMonitors(files);
  const declaredSet = new Set(declared);
  const { found, elements } = routeElements(files[ALERT_FILE]);

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
  const unroutedKeys = [...unroutedMap.keys()];

  return {
    declared,
    vacuous: declared.length === 0,
    routesBlockMissing: !found,
    unrouted: declared.filter(
      (l) => !routedSet.has(l) && !unroutedMap.has(l),
    ),
    doubleListed: unroutedKeys.filter((l) => routedSet.has(l)).sort(),
    reasonWithoutIssue: unroutedKeys
      .filter((l) => !/#\d+/.test(unroutedMap.get(l) ?? ""))
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
    !f.routesBlockMissing &&
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
  if (f.routesBlockMissing) {
    out.push(
      `- no \`monitor_ids = [\` list found in infra/sentry/${ALERT_FILE} (sentry_alert.cron_monitor_failure).`,
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

function realTree(): Record<string, string> {
  const files: Record<string, string> = {};
  for (const f of readdirSync(SENTRY_DIR)) {
    if (f.endsWith(".tf")) files[f] = readFileSync(resolve(SENTRY_DIR, f), "utf-8");
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

function alertFile(elements: string[], unrouted: Record<string, string> = {}): string {
  const entries = Object.entries(unrouted).map(
    ([k, v]) => `    ${k} = "${v}"`,
  );
  return [
    `# Header prose quoting monitor_ids = [ and cron_monitor_alert_unrouted = { and`,
    `# resource "sentry_cron_monitor" "decoy_in_comment" must not match.`,
    `locals {`,
    entries.length
      ? [`  cron_monitor_alert_unrouted = {`, ...entries, `  }`].join("\n")
      : `  cron_monitor_alert_unrouted = {}`,
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

  it("row 2 (anti-vacuity): real tree declares >= 1 monitor, matching an independent count", () => {
    const tfFiles = readdirSync(SENTRY_DIR).filter((f) => f.endsWith(".tf"));
    expect(tfFiles.length).toBeGreaterThan(0);
    let independent = 0;
    for (const f of tfFiles) {
      const src = readFileSync(resolve(SENTRY_DIR, f), "utf-8");
      independent += [...src.matchAll(/^resource "sentry_cron_monitor" /gm)].length;
    }
    const f = checkRouting(realTree());
    expect(independent).toBeGreaterThanOrEqual(1);
    expect(f.declared.length).toBe(independent);
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
  });

  it("row 7: an unrouted reason with no #<n> is RED", () => {
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha") + monitorBlock("beta"),
      [ALERT_FILE]: alertFile([ref("alpha")], { beta: "route later" }),
    });
    expect(f.reasonWithoutIssue).toEqual(["beta"]);
    expect(f.unrouted).toEqual([]);
  });

  it("row 10: a monitor_ids element that is not a sentry_cron_monitor.<label>.id reference is RED", () => {
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha"),
      [ALERT_FILE]: alertFile([ref("alpha"), `"1213799"`]),
    });
    expect(f.nonReferenceElements).toEqual([`"1213799"`]);
  });

  it("row 11: an unrouted key naming no declared monitor is RED", () => {
    const f = checkRouting({
      "cron-monitors.tf": monitorBlock("alpha"),
      [ALERT_FILE]: alertFile([ref("alpha")], {
        deleted_monitor: "left behind (#77)",
      }),
    });
    expect(f.unroutedWithoutMonitor).toEqual(["deleted_monitor"]);
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
});
