import { describe, expect, it } from "vitest";
import { readFileSync, readdirSync, statSync } from "fs";
import { resolve, join, relative } from "path";

/**
 * Drift-guard: every site that calls a Supabase auth verb must mirror to
 * Sentry with `feature: "auth"` and a matching `op: "<verb>"` tag. The four
 * auth alert rules filter on these tags — silently dropping a tag breaks
 * paging without any runtime symptom.
 *
 * Ownership split since #7650 Phase 2 (2026-09-04): three of the four
 * (auth-signout-burst, auth-exchange-code-burst, auth-callback-no-code-burst)
 * are now Terraform-managed as `sentry_alert` in
 * apps/web-platform/infra/sentry/issue-alerts.tf, with their real tag filters
 * declared there. The fourth, auth-per-user-loop, is still defined by
 * apps/web-platform/scripts/configure-sentry-alerts.sh because the pinned
 * provider cannot express `event_unique_user_frequency_count` as a trigger
 * (upstream jianyuan/terraform-provider-sentry issue 950). Either way the tag
 * contract this guard enforces is unchanged.
 *
 * Pattern: apps/web-platform/lib/auth/csrf-coverage.test.ts (no glob dep,
 * fs.readdirSync + fs.statSync recursive walk).
 */

const AUTH_DIRS = ["app/(auth)", "components/auth"];

const AUTH_VERBS = [
  "exchangeCodeForSession",
  "signInWithOAuth",
  "signInWithOtp",
  "verifyOtp",
  "signOut",
];

const APP_ROOT = resolve(__dirname, "../../");

function walkSource(dir: string): string[] {
  const results: string[] = [];
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    return results;
  }
  for (const entry of entries) {
    const full = join(dir, entry);
    const stat = statSync(full);
    if (stat.isDirectory()) {
      results.push(...walkSource(full));
    } else if (
      /\.(ts|tsx)$/.test(entry) &&
      !/\.(test|spec|stories)\.tsx?$/.test(entry)
    ) {
      results.push(full);
    }
  }
  return results;
}

describe("auth Sentry tag coverage", () => {
  const allFiles = AUTH_DIRS.flatMap((d) => walkSource(resolve(APP_ROOT, d)));

  it("walk found at least one source file in every auth dir (sanity)", () => {
    expect(allFiles.length).toBeGreaterThan(0);
    for (const dir of AUTH_DIRS) {
      const dirRoot = resolve(APP_ROOT, dir);
      const filesInDir = allFiles.filter((f) => f.startsWith(dirRoot));
      expect(
        filesInDir.length,
        `No .ts/.tsx source files found in ${dir} — was the dir renamed?`,
      ).toBeGreaterThan(0);
    }
  });

  // Anchored regex avoids false-positives in comments and string literals
  // (e.g., errorMap["signInWithOtp"]). Matches `.signInWithOtp(` and
  // `.signInWithOtp ( ` (whitespace tolerated) but not `// .signInWithOtp(`.
  const verbCallRegex = (verb: string) =>
    new RegExp(`\\.${verb}\\s*\\(`);

  it("every file calling an auth verb mirrors to Sentry with feature:auth", () => {
    const offenders: string[] = [];
    for (const file of allFiles) {
      const src = readFileSync(file, "utf8");
      const verbsInFile = AUTH_VERBS.filter((v) => verbCallRegex(v).test(src));
      if (verbsInFile.length === 0) continue;
      if (!/feature:\s*["']auth["']/.test(src)) {
        const rel = relative(APP_ROOT, file);
        offenders.push(
          `${rel} calls ${verbsInFile.join(",")} without feature:"auth" Sentry mirror`,
        );
      }
    }
    expect(offenders, offenders.join("\n")).toEqual([]);
  });

  it("every auth verb is paired with a matching op tag in the same file", () => {
    const offenders: string[] = [];
    for (const file of allFiles) {
      const src = readFileSync(file, "utf8");
      for (const verb of AUTH_VERBS) {
        if (!verbCallRegex(verb).test(src)) continue;
        const opRegex = new RegExp(`op:\\s*["']${verb}["']`);
        if (!opRegex.test(src)) {
          const rel = relative(APP_ROOT, file);
          offenders.push(
            `${rel}: calls .${verb}() but missing op:"${verb}" in Sentry mirror`,
          );
        }
      }
    }
    expect(offenders, offenders.join("\n")).toEqual([]);
  });
});
