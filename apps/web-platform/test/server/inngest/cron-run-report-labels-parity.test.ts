// #8076 — parity between the run-report leaf and the three things it stands in
// for. The population key is "calls `resolveOutputAwareOk`"; a heartbeat
// inventory is a liveness subset, not the filing population (the brainstorm
// keyed on it and was wrong by four). These rows are what makes the leaf a
// derivation rather than a hand-copied list.
import { describe, expect, it, vi } from "vitest";
import { mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// The substrate and the heartbeat both load `server/inngest/client.ts`, which
// throws without INNGEST_SIGNING_KEY unless the build phase is set (mirrors
// cron-compound-promote.test.ts). Hoisted so it runs before the imports below.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});
import {
  RUN_REPORT_CRONS,
  runReportLabelFor,
  sweepableRunReports,
} from "../../../server/inngest/functions/_cron-run-reports";
import { CRON_BASH_ALLOWLISTS } from "../../../server/inngest/functions/_cron-claude-eval-substrate";
import { TASK_INVENTORY } from "../../../server/inngest/functions/cron-cloud-task-heartbeat";

const FUNCTIONS_DIR = join(__dirname, "../../../server/inngest/functions");

// A CALL SITE, not a comment mention. The population key is "the file CALLS
// resolveOutputAwareOk", so the haystack is the source with comments and
// string literals blanked (a `// … resolveOutputAwareOk cannot …` mention and
// a prose string do not match) and the needle is the bare call form — any
// shape: `const x = await f(`, `return f(`, `x = f(`, `step.run(() => f(`. A
// line-anchored `[const x =][await ]f(` regex missed every one of the last
// three, so a new run-reporter written in one of them was silently outside
// the map (#8074 review). Comment-stripping is a char scan, not a regex, so a
// `*/` inside a string cannot terminate a comment early (#5203 class).
const CALL_SITE = /\bresolveOutputAwareOk\(/;

export function stripCommentsAndStrings(src: string): string {
  let out = "";
  let i = 0;
  while (i < src.length) {
    const c = src[i];
    const n = src[i + 1];
    if (c === "/" && n === "/") {
      while (i < src.length && src[i] !== "\n") i++;
      continue;
    }
    if (c === "/" && n === "*") {
      i += 2;
      while (i < src.length && !(src[i] === "*" && src[i + 1] === "/")) i++;
      i += 2;
      continue;
    }
    if (c === '"' || c === "'" || c === "`") {
      const q = c;
      i++;
      while (i < src.length && src[i] !== q) {
        if (src[i] === "\\") i++;
        i++;
      }
      i++;
      out += " ";
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

function verifyCallers(dir: string = FUNCTIONS_DIR): Map<string, string> {
  const out = new Map<string, string>();
  for (const f of readdirSync(dir)) {
    if (!/^cron-.*\.ts$/.test(f) || f.endsWith(".test.ts")) continue;
    const src = readFileSync(join(dir, f), "utf-8");
    if (!CALL_SITE.test(stripCommentsAndStrings(src))) continue;
    const slug = /const SENTRY_MONITOR_SLUG = "([^"]+)"/.exec(src)?.[1];
    expect(slug, `${f} calls resolveOutputAwareOk but has no SENTRY_MONITOR_SLUG`).toBeTruthy();
    out.set(`cron-${f.replace(/^cron-/, "").replace(/\.ts$/, "")}`, slug as string);
  }
  return out;
}

describe("run-report leaf parity (#8076)", () => {
  it("(i) every resolveOutputAwareOk call site has a row with its SENTRY_MONITOR_SLUG, and every row maps back (legal-audit is the one operator-decided exception)", () => {
    const callers = verifyCallers();
    // Non-vacuity: the population is nine today; a sweep that finds fewer than
    // five has lost the regex, not the crons.
    expect(callers.size).toBeGreaterThanOrEqual(5);
    for (const [fn, slug] of callers) {
      expect(runReportLabelFor(fn), `${fn} calls resolveOutputAwareOk but has no RUN_REPORT_CRONS row`).toBe(slug);
    }
    for (const row of RUN_REPORT_CRONS) {
      if (row.fn === "cron-legal-audit") continue; // D1: in the map, not a verify-caller
      expect(callers.get(row.fn), `${row.fn} has a row but no resolveOutputAwareOk call site`).toBe(row.label);
    }
    expect(RUN_REPORT_CRONS.map((r) => r.fn)).toContain("cron-legal-audit");
    // Non-vacuity on the extractor itself: today's population is exactly nine.
    expect(callers.size).toBe(9);
  });

  it("(i′) the call-site extractor sees every call SHAPE and no comment/string mention (fixture dir)", () => {
    const dir = mkdtempSync(join(tmpdir(), "rr-parity-"));
    const slug = (s: string) => `const SENTRY_MONITOR_SLUG = "${s}";\n`;
    writeFileSync(join(dir, "cron-a.ts"), `${slug("scheduled-a")}export async function h() { return resolveOutputAwareOk({}); }\n`);
    writeFileSync(join(dir, "cron-b.ts"), `${slug("scheduled-b")}let ok;\nasync function h() { ok = await resolveOutputAwareOk({}); }\n`);
    writeFileSync(join(dir, "cron-c.ts"), `${slug("scheduled-c")}const r = await step.run("verify-output", () => resolveOutputAwareOk({}));\n`);
    writeFileSync(join(dir, "cron-d.ts"), `${slug("scheduled-d")}const ok =\n  await resolveOutputAwareOk({});\n`);
    // Mentions only: a line comment, a block comment with a decoy `*/` in a
    // string before it, a prose string — none is a caller.
    writeFileSync(join(dir, "cron-e.ts"), [
      slug("scheduled-e"),
      "// legal-audit does not call resolveOutputAwareOk( on purpose",
      'const s = "*/ resolveOutputAwareOk( in prose";',
      "/* resolveOutputAwareOk( inside a block comment */",
      "",
    ].join("\n"));
    writeFileSync(join(dir, "cron-f.test.ts"), `${slug("scheduled-f")}resolveOutputAwareOk({});\n`);
    const callers = verifyCallers(dir);
    expect([...callers.keys()].sort()).toEqual(["cron-a", "cron-b", "cron-c", "cron-d"]);
    expect(callers.get("cron-a")).toBe("scheduled-a");
  });

  it("(ii) every row's fn is a cron with `gh issue create` in CRON_BASH_ALLOWLISTS", () => {
    for (const row of RUN_REPORT_CRONS) {
      const allow = CRON_BASH_ALLOWLISTS[row.fn];
      expect(allow, `${row.fn} has no CRON_BASH_ALLOWLISTS entry`).toBeDefined();
      expect(allow, `${row.fn} cannot file: no gh issue create prefix`).toContain("gh issue create");
    }
  });

  it("(ii′) no bash allow entry is spelled like a directive — the directive's ONLY producer is buildAllowlistLines", () => {
    // `parseAllowlist` runs its directive regexes on every line of the allow
    // file with no provenance check, so a `run-report-label <slug>` string in
    // any CRON_BASH_ALLOWLISTS array would grant exit 0 to that cron outside
    // RUN_REPORT_CRONS and outside parity (i). Pin the producer set here.
    const DIRECTIVE = /^(mcp-allow|navigate-origin|run-report-label)\b/;
    for (const [fn, allow] of Object.entries(CRON_BASH_ALLOWLISTS)) {
      for (const entry of allow) {
        expect(entry, `${fn}: bash allow entry spelled like a directive: ${entry}`).not.toMatch(DIRECTIVE);
      }
    }
  });

  it("(iii) closeAfterDays equals 3 × the heartbeat's maxGapDays for every TASK_INVENTORY row it sweeps", () => {
    let checked = 0;
    const skipped: string[] = [];
    for (const t of TASK_INVENTORY) {
      const row = RUN_REPORT_CRONS.find((r) => r.label === t.label);
      expect(row, `${t.label} is in TASK_INVENTORY but not in RUN_REPORT_CRONS`).toBeDefined();
      if (row?.closeAfterDays === null) { skipped.push(t.label); continue; }
      expect(row?.closeAfterDays, `${t.label}: closeAfterDays must be 3 × maxGapDays`).toBe(3 * t.maxGapDays);
      checked += 1;
    }
    // legal-audit is the ONE heartbeat row that is never swept (D1); a second
    // null here is a row that lost its window, named rather than counted.
    expect(skipped).toEqual(["scheduled-legal-audit"]);
    expect(checked).toBe(TASK_INVENTORY.length - 1);
  });

  it("the sweep set never includes campaign-calendar or legal-audit, and every other row is sweepable", () => {
    const labels = sweepableRunReports().map((r) => r.label);
    expect(labels).not.toContain("scheduled-campaign-calendar");
    expect(labels).not.toContain("scheduled-legal-audit");
    expect(labels.length).toBe(RUN_REPORT_CRONS.length - 2);
  });

  it("labels are unique and every fn is unique", () => {
    expect(new Set(RUN_REPORT_CRONS.map((r) => r.label)).size).toBe(RUN_REPORT_CRONS.length);
    expect(new Set(RUN_REPORT_CRONS.map((r) => r.fn)).size).toBe(RUN_REPORT_CRONS.length);
  });
});
