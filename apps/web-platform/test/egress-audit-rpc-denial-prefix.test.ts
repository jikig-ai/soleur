import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { RPC_DENIAL_PREFIX } from "@/lib/egress-audit/summary";

// Cross-artifact contract (#9545 PR2, extended by #11238): the loader tells the RPC's own denial from the database
// engine's ("permission denied for function ...", same SQLSTATE 42501) by the message prefix. If a migration ever
// raises a 42501 whose message does not start with RPC_DENIAL_PREFIX, the loader would report a real member's
// denial as a paged fault. This binds the two sides for BOTH member read functions (migration 177 and the windowed
// migration 183): every 42501 they raise carries the prefix, and so do their 22023 messages.

const here = dirname(fileURLToPath(import.meta.url));
const migrations = join(here, "..", "supabase", "migrations");

type Raise = { message: string; errcode: string };

const load = (ordinal: number): { file: string | undefined; code: string; raises: Raise[] } => {
  const file = readdirSync(migrations).find((f) => new RegExp(`^${ordinal}_.*\\.sql$`).test(f) && !f.endsWith(".down.sql"));
  const sql = file ? readFileSync(join(migrations, file), "utf8") : "";
  // A `-- ...` line comment never raises anything; strip them so a comment cannot satisfy or break the anchor.
  const code = sql.replace(/^\s*--.*$/gm, "");
  const raises = [...code.matchAll(/RAISE\s+EXCEPTION\s+'((?:[^']|'')*)'\s+USING\s+ERRCODE\s*=\s*'([0-9A-Z]{5})'/g)].map((m) => ({
    message: m[1].replace(/''/g, "'"),
    errcode: m[2],
  }));
  return { file, code, raises };
};

// Per migration: the minimum number of RAISE statements, of 42501 denials, and of 22023 argument errors the file
// must be seen to contain (a floor, so a scan that silently matches nothing cannot pass).
const MIGRATIONS = [
  { ordinal: 177, minRaises: 3, min42501: 2, min22023: 1 },
  { ordinal: 183, minRaises: 4, min42501: 2, min22023: 2 },
] as const;

describe.each(MIGRATIONS)("migration $ordinal denial messages vs RPC_DENIAL_PREFIX", ({ ordinal, minRaises, min42501, min22023 }) => {
  const { file, code, raises } = load(ordinal);

  it("finds the migration and its RAISE EXCEPTION statements (non-vacuous floor)", () => {
    expect(file).toBeTruthy();
    expect(raises.length).toBeGreaterThanOrEqual(minRaises);
    expect(raises.filter((r) => r.errcode === "42501").length).toBeGreaterThanOrEqual(min42501);
    expect(raises.filter((r) => r.errcode === "22023").length).toBeGreaterThanOrEqual(min22023);
  });

  it("every RAISE EXCEPTION ... ERRCODE '42501' starts with RPC_DENIAL_PREFIX", () => {
    const denials = raises.filter((r) => r.errcode === "42501");
    expect(denials.length).toBeGreaterThanOrEqual(min42501);
    for (const d of denials) expect([d.message, d.message.startsWith(RPC_DENIAL_PREFIX)]).toEqual([d.message, true]);
  });

  it("every RAISE EXCEPTION ... ERRCODE '22023' also starts with RPC_DENIAL_PREFIX", () => {
    const invalid = raises.filter((r) => r.errcode === "22023");
    expect(invalid.length).toBeGreaterThanOrEqual(min22023);
    for (const d of invalid) expect([d.message, d.message.startsWith(RPC_DENIAL_PREFIX)]).toEqual([d.message, true]);
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
