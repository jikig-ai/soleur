// #6143 Part 2 — cohort-wide digest-title date pin (determinism guard).
//
// Every cron in the "always-create digest" cohort files an issue titled
// `[Scheduled] <task> - <date>`. The code-level same-date dedup key is
// `runStartedAt.slice(0,10)` (host UTC, captured in the handler), but the title
// date was previously derived by the spawned eval from its OWN container clock.
// Across a UTC-midnight boundary the two could diverge, so isRealScheduledDigest's
// exact-title match could MISS (duplicate) or OVER-suppress. The fix pins the
// issue-TITLE date to the same value as the dedup key: each cohort prompt carries
// a `{{RUN_DATE}}` sentinel and each spawn site wraps the prompt in
// `injectRunDate(PROMPT, runStartedAt)`, which substitutes runStartedAt.slice(0,10).
//
// This guard is DISCOVERY-BASED (readdirSync + `digestIssueExistsForDate` filter),
// NOT a hardcoded 9-path array — so a future digest cron that lands without the
// pin fails here immediately, instead of silently escaping the convention
// (precedent: sentry-monitor-iac-parity.test.ts's self-discovering parity guard).
//
// cq-test-fixtures-synthesized-only: the discovery guard reads the real SUT via
// readFileSync and asserts SENTINEL PRESENCE in the const + `injectRunDate(` at
// the spawn edge (not a resolved date), so build-time substitution never breaks it.

import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";

import {
  RUN_DATE_SENTINEL,
  injectRunDate,
} from "@/server/inngest/functions/_cron-shared";

const FUNCTIONS_DIR = resolve(__dirname, "../../../server/inngest/functions");

// The cohort = every `cron-*.ts` handler that runs the code-level same-date
// dedup (`digestIssueExistsForDate`). `_cron-shared.ts` defines the helper but
// is excluded by the `cron-` (no underscore) prefix.
function cohortFiles(): string[] {
  return readdirSync(FUNCTIONS_DIR).filter(
    (f) =>
      f.startsWith("cron-") &&
      f.endsWith(".ts") &&
      !f.endsWith(".test.ts") &&
      readFileSync(join(FUNCTIONS_DIR, f), "utf-8").includes(
        "digestIssueExistsForDate",
      ),
  );
}

describe("#6143 — cohort digest-title date pin (discovery-based drift guard)", () => {
  const cohort = cohortFiles();

  it("discovers a non-empty digest cohort (sanity: 9 today, derived not hardcoded)", () => {
    expect(cohort.length).toBeGreaterThan(0);
    // Documented count as of 2026-07-07 — a soft cross-check, NOT the gate. If
    // this trips, a digest cron was added/removed: update the number AND confirm
    // the new cron carries the pin (the per-file assertions below enforce that).
    expect(cohort.length).toBe(9);
  });

  it.each(cohortFiles())(
    "%s pins its issue-title date via {{RUN_DATE}} + injectRunDate( at the spawn edge",
    (file) => {
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      expect(src).toContain(RUN_DATE_SENTINEL);
      expect(src).toContain("injectRunDate(");
    },
  );
});

describe("injectRunDate — substitution contract", () => {
  it("replaces EVERY sentinel occurrence with runStartedAt.slice(0,10)", () => {
    const out = injectRunDate(
      "a {{RUN_DATE}} b {{RUN_DATE}}",
      "2026-07-07T23:59:00Z",
    );
    expect(out).toBe("a 2026-07-07 b 2026-07-07");
    expect(out).not.toContain(RUN_DATE_SENTINEL);
  });

  it("uses the DATE portion of runStartedAt (host UTC), not the full ISO string", () => {
    expect(injectRunDate("t={{RUN_DATE}}", "2026-01-02T00:00:00Z")).toBe(
      "t=2026-01-02",
    );
  });

  it("THROWS when the sentinel is absent (a forgotten wiring is loud, not a literal-{{RUN_DATE}} title)", () => {
    expect(() =>
      injectRunDate("no sentinel here", "2026-07-07T12:00:00Z"),
    ).toThrow(/RUN_DATE/);
  });
});

describe("#6143 AC8 — campaign-calendar canary (` (heartbeat)` suffix is OUTSIDE the sentinel)", () => {
  it("cron-campaign-calendar.ts pins the date but keeps ` (heartbeat)` outside the sentinel, so the injected title equals ${prefix} ${date}${suffix}", () => {
    const src = readFileSync(
      join(FUNCTIONS_DIR, "cron-campaign-calendar.ts"),
      "utf-8",
    );
    // The suffix must sit OUTSIDE the sentinel — otherwise the injected title
    // would not equal isRealScheduledDigest's `${titlePrefix} ${date}${titleSuffix}`
    // (titleSuffix " (heartbeat)") and the exact-title dedup match would break.
    const pinnedTitle = "[Scheduled] Campaign Calendar - {{RUN_DATE}} (heartbeat)";
    expect(src).toContain(pinnedTitle);
    expect(injectRunDate(pinnedTitle, "2026-07-07T23:59:00Z")).toBe(
      "[Scheduled] Campaign Calendar - 2026-07-07 (heartbeat)",
    );
  });
});
