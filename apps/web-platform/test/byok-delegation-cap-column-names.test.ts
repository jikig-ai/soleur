import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

// Regression guard (review P1): the byok_delegations cap columns are
// daily_usd_cap_cents / hourly_usd_cap_cents (migration 064:82,86). The UI
// resolvers query an UNTYPED service client, so selecting the bare
// `daily_cap_cents` / `hourly_cap_cents` names ships green (tsc can't see it,
// the chain mocks discard the select arg) but errors at runtime with PostgREST
// 42703 → the read silently returns []/error → the owner "Share a key" toggle
// renders OFF on every reload (the core of symptom 1). PostgREST aliases
// (`daily_cap_cents:daily_usd_cap_cents`) query the real column while keeping
// the short TS key. This source-level test pins that no `.select()` against
// byok_delegations re-introduces a bare (unaliased) cap-column name.
// See knowledge-base/project/learnings/2026-06-01-untyped-supabase-select-nonexistent-column-ships-green.md

const RESOLVER_FILES = [
  "../server/team-membership-resolver.ts",
  "../server/byok-delegation-ui-resolver.ts",
];

// Match the string argument of each `.select("...")` call.
const SELECT_CALL_RE = /\.select\(\s*"([^"]*)"/g;
// A bare cap-column name = `daily_cap_cents` / `hourly_cap_cents` NOT immediately
// followed by `:` (the alias form `daily_cap_cents:daily_usd_cap_cents` is safe).
const BARE_CAP_RE = /\b(daily|hourly)_cap_cents(?!:)/;

describe("byok_delegations cap column names are the real *_usd_cap_cents columns", () => {
  for (const rel of RESOLVER_FILES) {
    it(`${rel}: every cap-column select queries *_usd_cap_cents, never a bare daily_cap_cents`, () => {
      const src = readFileSync(fileURLToPath(new URL(rel, import.meta.url)), "utf8");
      const selects = [...src.matchAll(SELECT_CALL_RE)].map((m) => m[1]);
      const capSelects = selects.filter((s) => s.includes("cap_cents"));
      // The file must actually contain a cap-column select (guards against the
      // test silently passing if the resolver is refactored away).
      expect(capSelects.length).toBeGreaterThan(0);
      for (const s of capSelects) {
        expect(s, `bare cap column in select: "${s}"`).not.toMatch(BARE_CAP_RE);
        expect(s).toContain("daily_usd_cap_cents");
      }
    });
  }
});
