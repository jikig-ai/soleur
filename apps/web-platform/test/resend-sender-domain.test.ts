import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

/**
 * Resend only accepts mail from a domain that carries its verification records
 * (a DKIM TXT at `resend._domainkey.<domain>` and the bounce subdomain
 * `send.<domain>`). soleur.ai carries both; jikigai.com carries neither, so a
 * send whose `from:` sits on it is rejected by the vendor and — where the
 * response is discarded — fails silently.
 *
 * That is not hypothetical: two Inngest cron alert paths shipped with a
 * jikigai.com sender and no response check, so the alerts they exist to raise
 * had been going nowhere. This guard is scoped to the CLASS (every Resend send
 * site) rather than to those two files, so a new send site cannot reintroduce it.
 *
 * The forbidden domain is assembled at runtime: a source-scanning guard that
 * spelled it literally would match itself and any explanatory comment.
 */
const FORBIDDEN_SENDER_DOMAIN = ["jikigai", "com"].join(".");

function repoRoot(): string {
  return execFileSync("git", ["rev-parse", "--show-toplevel"], {
    encoding: "utf8",
  }).trim();
}

/** Every tracked file that POSTs to the Resend send endpoint. */
function resendSendSites(): string[] {
  const root = repoRoot();
  const out = execFileSync(
    "git",
    ["grep", "-l", "--", "api\\.resend\\.com/emails"],
    { cwd: root, encoding: "utf8" },
  );
  return out
    .split("\n")
    .filter(Boolean)
    // Planning artifacts and runbooks quote payloads as prose, not as code.
    .filter((p) => !p.startsWith("knowledge-base/"))
    // This guard names the domain it forbids.
    .filter((p) => !p.endsWith("resend-sender-domain.test.ts"));
}

/**
 * Extract `from:` / `--arg from` senders. Anchored on the assignment construct
 * so a comment mentioning a sender is not mistaken for one being used.
 */
function sendersIn(source: string): string[] {
  const found: string[] = [];
  const patterns = [
    /(?:^|[\s{,])from:\s*"([^"]+)"/gm, // TS/JS object literal
    /--arg\s+from\s+"([^"]+)"/gm, // jq payload construction in shell/YAML
  ];
  for (const re of patterns) {
    for (const m of source.matchAll(re)) found.push(m[1]);
  }
  return found;
}

describe("Resend sender domain", () => {
  const root = repoRoot();
  const sites = resendSendSites();

  it("finds the Resend send sites it is meant to guard", () => {
    // Cardinality floor: a zero-match enumeration would make every assertion
    // below vacuously true, which is the failure mode this guard exists to avoid.
    expect(sites.length).toBeGreaterThanOrEqual(5);
  });

  it("never sends from a domain without Resend verification records", () => {
    const offenders: string[] = [];
    for (const rel of sites) {
      const src = readFileSync(`${root}/${rel}`, "utf8");
      for (const sender of sendersIn(src)) {
        if (sender.includes(FORBIDDEN_SENDER_DOMAIN)) {
          offenders.push(`${rel}: from=${sender}`);
        }
      }
    }
    expect(offenders).toEqual([]);
  });

  it("checks the Resend response instead of discarding it", () => {
    // A send whose response is never inspected cannot report a vendor
    // rejection, which is how the jikigai.com sender stayed invisible.
    const mustCheck = [
      "apps/web-platform/server/inngest/functions/cron-oauth-probe.ts",
      "apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts",
    ];
    for (const rel of mustCheck) {
      const src = readFileSync(`${root}/${rel}`, "utf8");
      expect(src, `${rel} must capture the Resend response`).toMatch(
        /(?:const|let)\s+\w+\s*=\s*await\s+fetch\(\s*"https:\/\/api\.resend\.com\/emails"/,
      );
      expect(src, `${rel} must mirror a non-OK Resend response`).toMatch(
        /\.ok\b/,
      );
    }
  });
});
