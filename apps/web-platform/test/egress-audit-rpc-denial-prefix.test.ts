import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { RPC_DENIAL_PREFIX } from "@/lib/egress-audit/summary";

// Cross-artifact contract (#9545 PR2): the loader tells the RPC's own denial from the database engine's
// ("permission denied for function ...", same SQLSTATE 42501) by the message prefix. If the migration ever
// raises a 42501 whose message does not start with RPC_DENIAL_PREFIX, the loader would report a real member's
// denial as a paged fault. This binds the two sides: every 42501 the migration raises carries the prefix.

const here = dirname(fileURLToPath(import.meta.url));
const migrations = join(here, "..", "supabase", "migrations");
const file = readdirSync(migrations).find((f) => /^177_.*\.sql$/.test(f) && !f.endsWith(".down.sql"));
const sql = file ? readFileSync(join(migrations, file), "utf8") : "";
// A `-- ...` line comment never raises anything; strip them so a comment cannot satisfy or break the anchor.
const code = sql.replace(/^\s*--.*$/gm, "");

const raises = [...code.matchAll(/RAISE\s+EXCEPTION\s+'((?:[^']|'')*)'\s+USING\s+ERRCODE\s*=\s*'([0-9A-Z]{5})'/g)].map((m) => ({
  message: m[1].replace(/''/g, "'"),
  errcode: m[2],
}));

describe("migration 177 denial messages vs RPC_DENIAL_PREFIX", () => {
  it("finds the migration and its RAISE EXCEPTION statements (non-vacuous)", () => {
    expect(file).toBeTruthy();
    expect(raises.length).toBeGreaterThanOrEqual(2);
    expect(raises.some((r) => r.errcode === "42501")).toBe(true);
  });

  it("every RAISE EXCEPTION ... ERRCODE '42501' starts with RPC_DENIAL_PREFIX", () => {
    const denials = raises.filter((r) => r.errcode === "42501");
    expect(denials.length).toBeGreaterThanOrEqual(2);
    for (const d of denials) expect([d.message, d.message.startsWith(RPC_DENIAL_PREFIX)]).toEqual([d.message, true]);
  });

  it("no statement raises the denial by its condition NAME (insufficient_privilege), which the SQLSTATE scan would miss", () => {
    expect(code).not.toMatch(/ERRCODE\s*=\s*'?insufficient_privilege'?/i);
    expect(code).not.toMatch(/\bRAISE\s+insufficient_privilege\b/i);
    expect(code).not.toMatch(/\binsufficient_privilege\b/i);
  });

  it("no statement in the file raises 42501 by a spelling the scan above does not see", () => {
    // Every mention of the SQLSTATE in executable code must be one of the parsed RAISE statements.
    expect((code.match(/'42501'/g) ?? []).length).toBe(raises.filter((r) => r.errcode === "42501").length);
  });
});
