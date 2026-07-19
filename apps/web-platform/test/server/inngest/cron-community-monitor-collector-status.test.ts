// #6695 — collector-status sidecar + fabrication detector.
//
// These cover the two gaps that made the 2026-07-19 digest possible:
//   AC13  a non-zero collector record must be readable by the handler at all
//         (every other channel the collectors have ends in the spawned agent's
//         context window, and resolveOutputAwareOk is a presence check that
//         returns GREEN for both the fabrication and honest-failure paths).
//   AC13b paging and persistence must stay separable: a collector failure has
//         to turn the monitor RED without discarding the digest that reports
//         it. `heartbeatOk` gates both, so the separation is load-bearing and
//         easy to "simplify" away.

import { afterEach, describe, expect, it } from "vitest";

// vi.hoisted runs BEFORE the ES-module imports below — sets NEXT_PHASE so the
// inngest client's startup-key check short-circuits. Without it this file errors
// at COLLECTION under CI (no INNGEST_SIGNING_KEY) while passing locally under
// Doppler. Mirrors cron-community-monitor.test.ts.
import { vi } from "vitest";
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  readCollectorStatus,
  classifyCollectorStatus,
} from "@/server/inngest/functions/cron-community-monitor";
import { STRUCTURAL_EXCLUSION_PREFIXES } from "@/server/inngest/functions/_cron-safe-commit";

const STATUS_DIR = ".soleur-collector-status";
const STATUS_FILE = "collector-status.jsonl";

const created: string[] = [];

async function makeCwd(lines?: string[]): Promise<string> {
  const cwd = await mkdtemp(join(tmpdir(), "collector-status-"));
  created.push(cwd);
  if (lines) {
    await mkdir(join(cwd, STATUS_DIR), { recursive: true });
    await writeFile(join(cwd, STATUS_DIR, STATUS_FILE), lines.join("\n") + "\n");
  }
  return cwd;
}

afterEach(async () => {
  await Promise.all(created.splice(0).map((d) => rm(d, { recursive: true, force: true })));
});

const okRecord = (command: string) =>
  JSON.stringify({ collector: "github", command, exit: 0, cause: "" });
const failRecord = (command: string, cause = "stargazers-non-array") =>
  JSON.stringify({ collector: "github", command, exit: 1, cause });

describe("readCollectorStatus", () => {
  it("reports absent when no sidecar was written", async () => {
    const report = await readCollectorStatus(await makeCwd());
    expect(report.present).toBe(false);
    expect(report.records).toEqual([]);
    expect(report.failed).toEqual([]);
  });

  it("distinguishes an absent sidecar from an all-green one", async () => {
    const report = await readCollectorStatus(
      await makeCwd([okRecord("activity"), okRecord("repo-stats")]),
    );
    // The distinction is the point: "no signal" and "all collectors succeeded"
    // must not collapse into the same value, or a collector that never ran
    // reads as a healthy run.
    expect(report.present).toBe(true);
    expect(report.failed).toEqual([]);
    expect(report.records).toHaveLength(2);
  });

  it("surfaces every non-zero record with its command and cause", async () => {
    const report = await readCollectorStatus(
      await makeCwd([
        okRecord("activity"),
        failRecord("repo-stats"),
        failRecord("contributors", "issues-fetch-failed"),
      ]),
    );
    expect(report.failed.map((r) => r.command)).toEqual([
      "repo-stats",
      "contributors",
    ]);
    expect(report.failed[0].cause).toBe("stargazers-non-array");
  });

  it("counts a malformed line as a failure rather than dropping it", async () => {
    const report = await readCollectorStatus(
      await makeCwd([okRecord("activity"), "{not json"]),
    );
    expect(report.present).toBe(true);
    expect(report.failed).toHaveLength(1);
    expect(report.failed[0].cause).toBe("malformed-record");
  });

  it("ignores blank lines", async () => {
    const report = await readCollectorStatus(
      await makeCwd([okRecord("activity"), "", okRecord("repo-stats")]),
    );
    expect(report.records).toHaveLength(2);
    expect(report.failed).toEqual([]);
  });
});

describe("sidecar contract — producer, consumer, and commit-guard agree", () => {
  // The contract spans a plugin shell script and this handler with no shared
  // constant: the dir name, the file name, and the env var are separate string
  // literals on both sides. Nothing else fails if they drift, and the drift
  // would manifest as SILENCE — the failure class this PR exists to remove.
  const COLLECTOR = readFileSync(
    new URL(
      "../../../../../plugins/soleur/skills/community/scripts/github-community.sh",
      import.meta.url,
    ),
    "utf8",
  );
  const HANDLER = readFileSync(
    new URL(
      "../../../server/inngest/functions/cron-community-monitor.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("resolves the collector script (path anchor, so the rest is not vacuous)", () => {
    expect(COLLECTOR).toContain("github-community.sh");
    expect(COLLECTOR.length).toBeGreaterThan(1000);
  });

  it("producer and consumer use the same env var and file name", () => {
    expect(COLLECTOR).toContain("SOLEUR_COLLECTOR_STATUS_DIR");
    expect(HANDLER).toContain("SOLEUR_COLLECTOR_STATUS_DIR");
    expect(COLLECTOR).toContain(STATUS_FILE);
    expect(HANDLER).toContain(STATUS_FILE);
  });

  it("the handler's dir constant matches the literal used everywhere else", () => {
    expect(HANDLER).toContain(`COLLECTOR_STATUS_DIRNAME = "${STATUS_DIR}"`);
  });

  it("safeCommitAndPr structurally excludes the sidecar, so it cannot page every run", () => {
    // Without this the sidecar is an untracked path on EVERY successful run, so
    // `safe-commit-paths-dropped` — the control that catches a bot writing
    // outside its allowlist — fires nightly and stops being read.
    expect(STRUCTURAL_EXCLUSION_PREFIXES).toContain(`${STATUS_DIR}/`);
  });

  it("the collector dispatches the command name the handler keys on", () => {
    expect(COLLECTOR).toContain("repo-stats)");
  });
});

describe("classifyCollectorStatus — the three arms are distinct outcomes", () => {
  // Inline in the handler these were reachable only through a full Inngest run,
  // so the warn arm could be deleted with the whole suite green. Each arm drives
  // a different operator action: page / report-only / report-absence.
  const rec = (over: Partial<Parameters<typeof classifyCollectorStatus>[0]["records"][number]>) => ({
    collector: "github",
    command: "activity",
    exit: 0,
    ...over,
  });

  it("pages on a non-zero record", () => {
    const failed = [rec({ exit: 1, cause: "issues-fetch-failed" })];
    const v = classifyCollectorStatus({ present: true, records: failed, failed });
    expect(v.failed).toHaveLength(1);
    expect(v.warned).toHaveLength(0);
    expect(v.missing).toBe(false);
  });

  it("reports a truncation warn WITHOUT treating it as a failure", () => {
    // Truncation is latent: this run's data is correct. Paging nightly on a
    // hypothetical is how a signal stops being read.
    const records = [rec({ warn: "truncated_at_per_page" })];
    const v = classifyCollectorStatus({ present: true, records, failed: [] });
    expect(v.warned).toHaveLength(1);
    expect(v.failed).toHaveLength(0);
    expect(v.missing).toBe(false);
  });

  it("distinguishes an absent sidecar from an all-green one", () => {
    const green = classifyCollectorStatus({
      present: true,
      records: [rec({})],
      failed: [],
    });
    const absent = classifyCollectorStatus({ present: false, records: [], failed: [] });
    expect(green.missing).toBe(false);
    expect(absent.missing).toBe(true);
    // Both have zero failures — only `missing` separates them.
    expect(green.failed).toEqual(absent.failed);
  });

  it("a failed record takes precedence over a warn on the same run", () => {
    const failed = [rec({ command: "repo-stats", exit: 1 })];
    const records = [...failed, rec({ warn: "truncated_at_per_page" })];
    const v = classifyCollectorStatus({ present: true, records, failed });
    expect(v.failed).toHaveLength(1);
    expect(v.warned).toHaveLength(1);
  });
});

describe("paging must not discard the digest (separation invariant)", () => {
  // `heartbeatOk` gates BOTH the Sentry page and safeCommitAndPr. Lowering it
  // at the collector gate would page AND throw away the honest digest, leaving
  // the operator strictly less to act on than before this PR. Applying it as
  // the last statement of the try was worse: a throw from safe-commit-pr jumps
  // to the catch, which deliberately keeps heartbeatOk true for a trailing-step
  // failure, so the page was lost on exactly the compound-failure run.
  const src = readFileSync(
    new URL(
      "../../../server/inngest/functions/cron-community-monitor.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("never lowers heartbeatOk inside the collector gate (digest must survive)", () => {
    const gate = src.slice(
      src.indexOf("verify-collector-status"),
      src.indexOf("Step 4.5: deterministic persistence"),
    );
    expect(gate.length).toBeGreaterThan(200); // slice anchors resolved
    expect(gate).toContain("collectorSignalRed = true");
    expect(gate).not.toContain("heartbeatOk = false");
  });

  it("applies the flag after BOTH persistence and the catch, so a trailing throw cannot drop the page", () => {
    const persist = src.indexOf("safeCommitAndPr({");
    // Anchor on the catch that CLOSES the handler body's inner try -- the first
    // one AFTER persistence. A bare indexOf("} catch (err) {") finds an earlier
    // catch in a different function, which makes the ordering assertion
    // trivially true and the guard vacuous (caught by mutation).
    const catchStart = src.indexOf("} catch (err) {", persist);
    const apply = src.indexOf("if (collectorSignalRed) heartbeatOk = false;");

    expect(persist).toBeGreaterThan(-1);
    expect(catchStart).toBeGreaterThan(persist);
    expect(apply).toBeGreaterThan(-1);

    // After persistence => the honest digest is committed before the page.
    expect(apply).toBeGreaterThan(persist);
    // After the catch closes => reached even when a trailing step throws. As
    // the try's last statement it was skipped on exactly that path, and the
    // catch keeps heartbeatOk true for a trailing-step failure.
    expect(apply).toBeGreaterThan(catchStart);
  });

  it("keeps the cohort-wide issue-verified persistence gate shape", () => {
    expect(src).toMatch(
      /if \(heartbeatOk && !spawnResult\.abortedByTimeout\) \{[\s\S]{0,800}?safeCommitAndPr\(\{/,
    );
  });
});
