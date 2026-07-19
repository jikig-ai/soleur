// #6695 — collector-status sidecar + fabrication detector.
//
// These cover the two gaps that made the 2026-07-19 digest possible:
//   AC13  a non-zero collector record must be readable by the handler at all
//         (every other channel the collectors have ends in the spawned agent's
//         context window, and resolveOutputAwareOk is a presence check that
//         returns GREEN for both the fabrication and honest-failure paths).
//   AC14  a digest that states Repository Stats numbers the collector never
//         produced must fire; an honest "collection failed:" digest carrying
//         the SAME non-zero record must NOT. Both arms are required — a
//         detector that fires on the honest path trains the reader to ignore it.

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
  digestFabricatesRepoStats,
} from "@/server/inngest/functions/cron-community-monitor";

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

describe("paging must not discard the digest (ordering invariant)", () => {
  // heartbeatOk gates BOTH the Sentry page and safe-commit-pr. Lowering it
  // inside the collector gate would page AND throw away the digest that
  // honestly reports the failure -- leaving the operator strictly less to act
  // on than before this PR. The flag is therefore applied AFTER persistence.
  // This is the kind of indirection a later "simplification" removes, so the
  // ordering is asserted rather than left to a comment.
  const src = readFileSync(
    new URL(
      "../../../server/inngest/functions/cron-community-monitor.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("raises a flag in the collector gate rather than lowering heartbeatOk there", () => {
    const gate = src.slice(
      src.indexOf("verify-collector-status"),
      src.indexOf("Step 4.5: deterministic persistence"),
    );
    expect(gate.length).toBeGreaterThan(200); // slice anchors resolved
    expect(gate).toContain("collectorSignalRed = true");
    expect(gate).not.toContain("heartbeatOk = false");
  });

  it("applies the flag to heartbeatOk only AFTER the safeCommitAndPr block", () => {
    const persist = src.indexOf("safeCommitAndPr({");
    const apply = src.indexOf("if (collectorSignalRed) heartbeatOk = false;");
    expect(persist).toBeGreaterThan(-1);
    expect(apply).toBeGreaterThan(-1);
    expect(apply).toBeGreaterThan(persist);
  });

  it("keeps the cohort-wide issue-verified persistence gate shape", () => {
    // cron-safe-commit-parity asserts this literal across 9 crons; renaming the
    // variable here to express the new concept would have silently weakened it.
    expect(src).toMatch(
      /if \(heartbeatOk && !spawnResult\.abortedByTimeout\) \{[\s\S]{0,800}?safeCommitAndPr\(\{/,
    );
  });
});

describe("digestFabricatesRepoStats", () => {
  const failed = {
    present: true,
    records: [],
    failed: [{ collector: "github", command: "repo-stats", exit: 1 }],
  };
  const clean = { present: true, records: [], failed: [] };

  const withStats = [
    "## GitHub Activity",
    "",
    "**Repository Stats**",
    "",
    "| Metric | Value |",
    "|---|---|",
    "| Stars | 10 |",
    "| Forks | 1 |",
    "",
  ].join("\n");

  // The reason string CONTAINS DIGITS on purpose. A digit-free fixture would
  // pass this test for the wrong reason -- the bare "does it contain a number?"
  // check would return false on its own and the honest-failure exemption would
  // never be exercised. Real causes carry status codes ("HTTP 404", "exit 5"),
  // so the digit-free version is also the unrealistic one.
  const withHonestFailure = [
    "## GitHub Activity",
    "",
    "**Repository Stats**",
    "",
    "collection failed: stargazers returned HTTP 404 (non-array payload)",
    "",
  ].join("\n");

  it("fires when repo-stats failed but the digest still states numbers", () => {
    expect(digestFabricatesRepoStats(withStats, failed)).toBe(true);
  });

  it("does NOT fire when the digest honestly reports the failure", () => {
    // The arm that keeps the alert credible.
    expect(digestFabricatesRepoStats(withHonestFailure, failed)).toBe(false);
  });

  it("does NOT fire when repo-stats succeeded", () => {
    expect(digestFabricatesRepoStats(withStats, clean)).toBe(false);
  });

  it("does NOT fire when the digest omits the section entirely", () => {
    // Numbers ELSEWHERE in the digest must not count. Without a digit here the
    // detector would return false for lack of any number at all, and this test
    // would pass against a version that scanned the whole document.
    expect(
      digestFabricatesRepoStats(
        "## GitHub Activity\n\n12 issues opened, 3 PRs merged this period.\n",
        failed,
      ),
    ).toBe(false);
  });

  it("fires on the exact shape the 2026-07-19 digest shipped", () => {
    // The regression this whole PR exists for: a stale number carried forward
    // from a six-week-old digest and labelled "(stale)" rather than reported as
    // a failure. "(stale)" is not an honest-failure marker.
    const shipped = [
      "## GitHub Activity",
      "",
      "**Repository Stats**",
      "",
      "| Stars/Forks/Watchers | 10 / 1 / 10 (stale — last confirmed 2026-06-08) |",
      "",
    ].join("\n");
    expect(digestFabricatesRepoStats(shipped, failed)).toBe(true);
  });
});
