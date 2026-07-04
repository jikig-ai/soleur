import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";

// Static gate (plan Observability failure_modes / ADR-066 trap): the inbox read
// routes MUST use the user-context Supabase client so workspace-Owner RLS stays
// load-bearing. `createServiceClient` there silently bypasses RLS and returns a
// co-Owner's / another workspace's items. Route unit tests call the handler
// directly and cannot catch this — a source grep is the merge gate.

const INBOX_API_DIR = path.join(__dirname, "../app/api/inbox");

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir)) {
    const full = path.join(dir, entry);
    if (statSync(full).isDirectory()) out.push(...walk(full));
    else if (/\.(ts|tsx)$/.test(entry)) out.push(full);
  }
  return out;
}

describe("inbox read routes never use the service client (RLS bypass gate)", () => {
  const files = walk(INBOX_API_DIR);

  it("finds route files to gate (non-vacuous)", () => {
    expect(files.length).toBeGreaterThan(0);
  });

  for (const file of files) {
    it(`app/api/inbox/${path.relative(INBOX_API_DIR, file)} has no createServiceClient`, () => {
      const src = readFileSync(file, "utf-8");
      // Strip comments so a cautionary comment naming the forbidden call does
      // not false-fail the gate.
      const code = src
        .split("\n")
        .filter((l) => !l.trim().startsWith("//") && !l.trim().startsWith("*"))
        .join("\n");
      expect(code).not.toMatch(/createServiceClient|getServiceClient/);
    });
  }
});
