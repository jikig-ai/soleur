import { describe, it, expect } from "vitest";
import path from "node:path";
import { classifyDefinerFns, loadForwardCorpus } from "./migration-lint/definer-grants";
import { CLASSIFIED_DEFINER_FN_NAMES } from "./rls-fuzz/rpc-cases";

// ===========================================================================
// SECURITY DEFINER grant-hygiene static pre-filter (#6328, ADR-112).
//
// TWO-TIER GUARD. The AUTHORITATIVE durable guard for DEFINER grant hygiene is the
// runtime `rls-authz-fuzz` AC8 gate (live `pg_proc.proacl` introspection, per-
// migration-PR; see test/rls-fuzz/{catalog.ts,rpc-cases.ts}). This suite is the
// SUBORDINATE, no-stack, fast STATIC pre-filter — advisory fast-feedback in the
// ordinary vitest run, NEVER coverage-bearing. A non-vacuity parity guard
// (test/rls-fuzz/rls-rpc.integration.test.ts) ties the set the detector below finds
// to AC8's live enumeration so the static tier cannot silently regress.
//
// WHY THIS EXISTS (#6306 blind spot). The previous lint was case-sensitive and
// `AS $$`-body-form-only, so it silently passed over the five lowercase
// `security definer` files (incl. the #6306 functions and `handle_new_user`) AND
// over `AS $$ … $$ … SECURITY DEFINER` body-forms — a green lint dead for whole
// authoring styles is false confidence. The detector (./migration-lint/
// definer-grants.ts) is case-insensitive and body-form-agnostic.
//
// THE INVARIANT. For every SECURITY DEFINER function across
// `apps/web-platform/supabase/migrations/*.sql` (forward files only), the LATEST
// definition of each (name, type-signature) identity must satisfy BOTH:
//   1. `SET search_path = public, pg_temp` in the declaration header (pg_temp
//      allowlisted for pre-existing legacy fns; `= public` always required).
//   2. one of: it RETURNS TRIGGER (no GRANT EXECUTE path); it is
//      authenticated-callable (in the AC8 registry — see AUTHENTICATED_CALLABLE);
//      it was DROP FUNCTION'd without recreate; OR the corpus REVOKEs it from ALL
//      of {public, anon, authenticated} (`public` ⊇ {anon, authenticated}).
//
// DELIBERATE SIMPLICITY BOUNDARY. This does NOT re-implement
// `has_function_privilege()` — AC8 computes net grant state exactly at runtime. The
// revoke-then-DROP+CREATE-without-re-revoke case is a documented residual the static
// union does not model; AC8 owns it via live `proacl`.
//
// Generalises the prior AC13/AC14 lint per
// `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md` +
// `cq-pg-security-definer-search-path-pin-pg-temp`.
// ===========================================================================

const MIGRATIONS_DIR = path.join(__dirname, "../supabase/migrations");

// AUTHENTICATED_CALLABLE — the DEFINER fns `authenticated` may legitimately EXECUTE.
// This is NOT a hand-maintained list; it IS the runtime AC8 classification registry
// (test/rls-fuzz/rpc-cases.ts → CLASSIFIED_DEFINER_FN_NAMES). By construction every
// entry cites its AC8 EXCLUDED/ATTACK/KNOWN_EXPOSURES classification (it is that
// classification), and the static tier can never bless a fn AC8 has not classified —
// the single-source-of-truth that keeps the subordinate static pre-filter from
// drifting from the authoritative runtime guard (ADR-112). A new authenticated-
// callable DEFINER fn added WITHOUT an AC8 classification therefore reds BOTH the AC8
// coverage gate (at runtime) and this static union (as an un-allowlisted grant
// surface). Name-collision-on-overload residual: see ADR-112 §Consequences.
const AUTHENTICATED_CALLABLE = CLASSIFIED_DEFINER_FN_NAMES;

// Grandfather allowlist for genuine pre-existing revoke-union gaps (keyed by name or
// `name(signature)`; each entry needs a rationale + tracking issue). EMPTY: migration
// 128 (#6318) + prior hygiene closed every residual-grant DEFINER fn, so the corpus
// is clean with no grandfathered revoke gaps.
const GRANDFATHER_REVOKE_GAPS = new Set<string>();

// Pre-existing DEFINER fns that pin `search_path = public` but NOT pg_temp. The
// defence-in-depth value of pg_temp is small when the body is pure SQL referencing
// only qualified public.<rel> identifiers, but the convention still applies. Keyed by
// FUNCTION NAME (not file) so a future differently-named DEFINER fn added to the same
// file is NOT silently exempted; tracked for follow-up cleanup, NOT touched here
// (out-of-feature-scope per `wg-when-an-audit-identifies-pre-existing`).
//   - sum_user_mtd_cost (027) — the original known entry.
//   - increment_conversation_cost (017, 4-arg v1) — surfaced by THIS PR's
//     case-insensitive + body-form-agnostic detector. The old regex required
//     SECURITY DEFINER *before* `AS $$`, but this fn is `AS $$ … $$ … SECURITY
//     DEFINER`, so it was silently unchecked. Superseded by the 6-arg v2 (mig 042,
//     which DOES pin pg_temp) but the v1 overload was never DROP FUNCTION'd.
const LEGACY_SEARCH_PATH_NO_PG_TEMP = new Set([
  "increment_conversation_cost",
  "sum_user_mtd_cost",
]);

const corpus = loadForwardCorpus(MIGRATIONS_DIR);

const verdicts = classifyDefinerFns(corpus, {
  authenticatedCallable: AUTHENTICATED_CALLABLE,
  grandfather: GRANDFATHER_REVOKE_GAPS,
});

describe("migration SECURITY DEFINER grant-hygiene static pre-filter (#6328, ADR-112)", () => {
  it("scans the forward-migration corpus and detects DEFINER fns (non-vacuity floor)", () => {
    // Guard against a detector regression that finds zero fns → vacuous green. The
    // corpus has 150+ forward migrations and 100+ DEFINER identities; a floor well
    // below the real count still catches "the detector broke and matches nothing".
    expect(corpus.length).toBeGreaterThan(100);
    expect(verdicts.length).toBeGreaterThan(80);
  });

  it("has NO residual-grant VIOLATION — every service-role-only DEFINER fn revokes {public, anon, authenticated}", () => {
    const violations = verdicts
      .filter((v) => v.classification === "violation")
      .map((v) => `${v.fn.name}(${v.fn.signature}) [${v.fn.file}] revoked={${v.revokedRoles.join(",")}}`);
    expect(violations, `residual-grant DEFINER fns (add an explicit REVOKE of {public, anon, authenticated}, or — if authenticated-callable — an AC8 classification in rls-fuzz/rpc-cases.ts):\n${violations.join("\n")}`).toEqual([]);
  });

  it("pins search_path (public always; pg_temp except pre-existing legacy) on every active DEFINER fn", () => {
    const missingPublic: string[] = [];
    const missingPgTemp: string[] = [];
    for (const v of verdicts) {
      if (v.classification === "dropped") continue; // superseded/removed overloads are not live
      // Extract the search_path value list (accept `=` or `TO`; `public` need not be
      // first — `pg_catalog, public, pg_temp` is valid). Robust to element ordering
      // and the `TO` spelling per review P3.
      const spMatch = /SET\s+search_path\s*(?:=|to)\s+([^\n;]+)/i.exec(v.fn.header);
      const spRhs = spMatch?.[1] ?? "";
      if (!spMatch || !/\bpublic\b/i.test(spRhs)) {
        missingPublic.push(`${v.fn.name} [${v.fn.file}]`);
        continue;
      }
      if (!LEGACY_SEARCH_PATH_NO_PG_TEMP.has(v.fn.name) && !/\bpg_temp\b/i.test(spRhs)) {
        missingPgTemp.push(`${v.fn.name} [${v.fn.file}]`);
      }
    }
    expect(missingPublic, `DEFINER fns missing 'search_path' pin including public:\n${missingPublic.join("\n")}`).toEqual([]);
    expect(missingPgTemp, `DEFINER fns missing 'pg_temp' pin (add the fn name to LEGACY_SEARCH_PATH_NO_PG_TEMP if pre-existing):\n${missingPgTemp.join("\n")}`).toEqual([]);
  });

  it("detects known lowercase / definer-after-body / drop-then-create fns over the REAL corpus (partial-regression guard)", () => {
    // The fast (no-DB) suite's only per-fn under-detection guard — the live-catalog
    // parity guard (staticallyUndetectedDefinerFns) runs ONLY in the RLS_FUZZ_LOCAL
    // rls-authz-fuzz job. Each name below exercises a distinct blind-spot class the
    // detector exists to close; a regression that drops one class reds here even
    // though the >80 floor would still pass (review P1 / test-design P1).
    const detected = new Set(verdicts.map((v) => v.fn.name));
    for (const name of [
      "handle_new_user", //             lowercase `create … security definer` + RETURNS TRIGGER (001/005/112)
      "increment_conversation_cost", // `AS $$ … $$ … SECURITY DEFINER` body-form (017 v1)
      "check_my_revocation", //         same-file DROP;CREATE of one identity (067)
      "find_stuck_active_conversations", // lowercase #6306 fn (037)
      "is_workspace_member", //         mixed-case file, authenticated-callable (053)
    ]) {
      expect(detected.has(name), `detector must find '${name}' over the real corpus`).toBe(true);
    }
    // Regression guard for the same-file DROP;CREATE ordering fix (#067): the live
    // (line-63) definition must win over the earlier (line-61) DROP → NOT `dropped`.
    const cmr = verdicts.filter((v) => v.fn.name === "check_my_revocation");
    expect(
      cmr.length > 0 && cmr.every((v) => v.classification !== "dropped"),
      "check_my_revocation must resolve to a live (non-dropped) identity",
    ).toBe(true);
    // Class-count floors — a detector that silently drops a whole class reds here.
    const byClass = (c: string) => verdicts.filter((v) => v.classification === c).length;
    expect(byClass("returns-trigger"), "returns-trigger count").toBeGreaterThanOrEqual(8);
    expect(byClass("pass-union"), "pass-union count").toBeGreaterThanOrEqual(20);
  });

  it("every classification is exactly one of the known kinds (zero silent skips)", () => {
    const known = new Set([
      "pass-union",
      "returns-trigger",
      "dropped",
      "authenticated-callable",
      "grandfather",
      "violation",
    ]);
    const unknown = verdicts.filter((v) => !known.has(v.classification));
    expect(unknown, `unclassified verdicts: ${unknown.map((v) => v.fn.name).join(", ")}`).toEqual([]);
  });

  it("AUTHENTICATED_CALLABLE is the AC8 registry and is non-trivial (≥8, cites AC8 by construction)", () => {
    // Plan AC8: grep confirms ≥8 entries, not zero. Each is an AC8 ATTACK/EXCLUDED/
    // KNOWN_EXPOSURES key, so it cites its AC8 classification by identity.
    expect(AUTHENTICATED_CALLABLE.size).toBeGreaterThanOrEqual(8);
    // Every fn we exempt as authenticated-callable is in the AC8 registry.
    const detectedAuthCallable = verdicts.filter((v) => v.classification === "authenticated-callable");
    for (const v of detectedAuthCallable) {
      expect(AUTHENTICATED_CALLABLE.has(v.fn.name), `${v.fn.name} exempted without an AC8 classification`).toBe(true);
    }
    expect(detectedAuthCallable.length).toBeGreaterThanOrEqual(8);
  });
});
