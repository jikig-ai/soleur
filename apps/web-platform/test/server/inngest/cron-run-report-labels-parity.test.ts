// #8076 — parity between the run-report leaf and the three things it stands in
// for. The population key is "calls `resolveOutputAwareOk`"; a heartbeat
// inventory is a liveness subset, not the filing population (the brainstorm
// keyed on it and was wrong by four). These rows are what makes the leaf a
// derivation rather than a hand-copied list.
import { describe, expect, it, vi } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
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

// A CALL SITE, not a comment mention: the line must start (after indentation)
// with an optional `const x = ` / `await ` and then the call. Comments naming
// the function ("… resolveOutputAwareOk cannot …") do not match.
const CALL_SITE = /^\s*(?:const\s+\w+\s*=\s*)?(?:await\s+)?resolveOutputAwareOk\(/m;

function verifyCallers(): Map<string, string> {
  const out = new Map<string, string>();
  for (const f of readdirSync(FUNCTIONS_DIR)) {
    if (!/^cron-.*\.ts$/.test(f) || f.endsWith(".test.ts")) continue;
    const src = readFileSync(join(FUNCTIONS_DIR, f), "utf-8");
    if (!CALL_SITE.test(src)) continue;
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
  });

  it("(ii) every row's fn is a cron with `gh issue create` in CRON_BASH_ALLOWLISTS", () => {
    for (const row of RUN_REPORT_CRONS) {
      const allow = CRON_BASH_ALLOWLISTS[row.fn];
      expect(allow, `${row.fn} has no CRON_BASH_ALLOWLISTS entry`).toBeDefined();
      expect(allow, `${row.fn} cannot file: no gh issue create prefix`).toContain("gh issue create");
    }
  });

  it("(iii) closeAfterDays equals 3 × the heartbeat's maxGapDays for every TASK_INVENTORY row it sweeps", () => {
    let checked = 0;
    for (const t of TASK_INVENTORY) {
      const row = RUN_REPORT_CRONS.find((r) => r.label === t.label);
      expect(row, `${t.label} is in TASK_INVENTORY but not in RUN_REPORT_CRONS`).toBeDefined();
      if (row?.closeAfterDays === null) continue; // legal-audit: never swept
      expect(row?.closeAfterDays).toBe(3 * t.maxGapDays);
      checked += 1;
    }
    expect(checked).toBeGreaterThanOrEqual(4);
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
