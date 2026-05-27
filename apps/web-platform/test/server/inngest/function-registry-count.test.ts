import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

const ROUTE_PATH = resolve(
  __dirname,
  "../../../app/api/inngest/route.ts",
);
const FUNCTIONS_DIR = resolve(
  __dirname,
  "../../../server/inngest/functions",
);
const CRON_MONITORS_TF = resolve(
  __dirname,
  "../../../infra/sentry/cron-monitors.tf",
);

const routeSrc = readFileSync(ROUTE_PATH, "utf8");
const tfSrc = readFileSync(CRON_MONITORS_TF, "utf8");

function extractRouteArrayEntries(): string[] {
  return [...routeSrc.matchAll(/^\s+(\w+),$/gm)].map((m) => m[1]);
}

function listCronFiles(): string[] {
  return readdirSync(FUNCTIONS_DIR)
    .filter((f) => f.startsWith("cron-") && f.endsWith(".ts") && !f.startsWith("_"))
    .map((f) => f.replace(/\.ts$/, ""));
}

function extractSentryMonitorSlugs(): Map<string, string> {
  const slugs = new Map<string, string>();
  for (const file of listCronFiles()) {
    const src = readFileSync(resolve(FUNCTIONS_DIR, `${file}.ts`), "utf8");
    const m = src.match(/SENTRY_MONITOR_SLUG\s*=\s*"([^"]+)"/);
    if (m) slugs.set(file, m[1]);
  }
  return slugs;
}

function extractTfMonitorNames(): Set<string> {
  return new Set([...tfSrc.matchAll(/name\s*=\s*"([^"]+)"/g)].map((m) => m[1]));
}

const KNOWN_UNMONITORED_SLUGS = new Set([
  "scheduled-campaign-calendar",
  "scheduled-cloud-task-heartbeat",
  "scheduled-content-generator",
  "scheduled-content-publisher",
  "scheduled-growth-audit",
  "scheduled-growth-execution",
  "scheduled-linkedin-token-check",
  "scheduled-membership-health",
  "scheduled-nag-4216-readiness",
  "scheduled-plausible-goals",
  "scheduled-rule-prune",
  "scheduled-ruleset-bypass-audit",
  "scheduled-seo-aeo-audit",
  "scheduled-weekly-analytics",
]);

describe("Inngest function registry — drift guards", () => {
  const routeEntries = extractRouteArrayEntries();
  const cronFiles = listCronFiles();
  const slugMap = extractSentryMonitorSlugs();
  const tfMonitors = extractTfMonitorNames();

  it("(a) route.ts functions array has expected count", () => {
    expect(routeEntries.length).toBe(40);
  });

  it("(b) every cron-*.ts file has a corresponding route.ts import", () => {
    const routeImports = [...routeSrc.matchAll(/from\s+"@\/server\/inngest\/functions\/([\w-]+)"/g)]
      .map((m) => m[1]);

    const missing = cronFiles.filter((f) => !routeImports.includes(f));
    expect(missing).toEqual([]);
  });

  it("(b2) every cron-*.ts file has its export in the functions array", () => {
    const routeSet = new Set(routeEntries.map((e) => e.toLowerCase()));

    const missing: string[] = [];
    for (const file of cronFiles) {
      const parts = file.split("-");
      const camel = parts[0] + parts.slice(1).map((p) => p[0].toUpperCase() + p.slice(1)).join("");
      if (!routeSet.has(camel.toLowerCase())) {
        missing.push(`${file} (expected identifier ~${camel})`);
      }
    }
    expect(missing).toEqual([]);
  });

  it("(c) every SENTRY_MONITOR_SLUG has a cron-monitors.tf resource (or is explicitly exempt)", () => {
    const unmonitored: string[] = [];
    for (const [file, slug] of slugMap) {
      if (!tfMonitors.has(slug) && !KNOWN_UNMONITORED_SLUGS.has(slug)) {
        unmonitored.push(`${file}: ${slug}`);
      }
    }
    expect(unmonitored).toEqual([]);
  });

  it("(c2) every cron-monitors.tf resource name maps to a registered cron function or GHA workflow", () => {
    const GHA_ONLY_MONITORS = new Set([
      "scheduled-terraform-drift",
      "scheduled-realtime-probe",
      "scheduled-gh-pages-cert-state",
    ]);

    const slugValues = new Set(slugMap.values());
    const phantom: string[] = [];
    for (const name of tfMonitors) {
      if (!slugValues.has(name) && !GHA_ONLY_MONITORS.has(name)) {
        phantom.push(name);
      }
    }
    expect(phantom).toEqual([]);
  });
});
