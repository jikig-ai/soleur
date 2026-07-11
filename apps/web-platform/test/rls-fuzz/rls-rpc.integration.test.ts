import { describe, test, expect, beforeAll, afterAll } from "vitest";
import type postgres from "postgres";
import { buildAuthenticatedClaims } from "./claim";
import { classifyRpcOutcome, type Verdict } from "./verdict";
import { securityDefinerAuthenticatedFns, securityDefinerAnonFns, type SecDefFn } from "./catalog";
import { ATTACK_SQL, EXCLUDED, KNOWN_EXPOSURES, type RpcCtx } from "./rpc-cases";
import { connect, seedRpcCtx, rolledBackRaw } from "./harness-fixture";

// SECURITY DEFINER RPC-bypass dimension (#6256, ADR-111, AC8). Drives every
// authenticated-EXECUTE definer fn with tenant-B claims + tenant-A params and
// asserts each denies (throw / empty / false / 0-rows). The catalog is the
// enumerator; rpc-cases.ts is the classification; the coverage gate fails on any
// uncovered fn. Gated behind RLS_FUZZ_LOCAL=1 against a LOCAL disposable Postgres.
// Shared connect/seed/txn helpers live in harness-fixture.ts (Item 8).
const ENABLED = process.env.RLS_FUZZ_LOCAL === "1";
const DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:54322/postgres";

let sql: postgres.Sql<{}>;
let ctx: RpcCtx;
const bClaims = () => buildAuthenticatedClaims({ sub: ctx.userB });

/** Execute one RPC under tenant-B claims; classify the outcome as denied|leaked. */
async function driveDenied(sqlText: string): Promise<Verdict> {
  try {
    return await rolledBackRaw(sql, async (t): Promise<Verdict> => {
      await t`set local role authenticated`;
      await t.unsafe("select set_config('request.jwt.claims', $1, true)", [bClaims()]);
      const rows = await t.unsafe(sqlText);
      if (rows.length === 0) return { kind: "denied" };
      const v = Object.values(rows[0] as object)[0];
      // null/false/0 = a getter returning nothing to a non-member → denied. NOTE:
      // "" (postgres.js's representation of a void return) is deliberately NOT a
      // denial sentinel — a void setter that returns cleanly for tenant-B MUTATED
      // A's data, which must surface as leaked, not be masked as denied.
      if (v === null || v === false || v === 0 || v === "0") return { kind: "denied" };
      return { kind: "leaked" };
    });
  } catch (err) {
    // SQLSTATE-classify the raise: a denial code (42501/P0001/P0002) = denied; any
    // other code (signature drift 42883, malformed uuid 22P02, validation 22023,
    // constraint 23xxx) = the call never reached the auth boundary → test-error.
    return classifyRpcOutcome(err as { code?: string }, 0);
  }
}

describe.skipIf(!ENABLED)("RLS/authz-fuzz — SECURITY DEFINER RPC bypass (local, catalog-driven)", () => {
  beforeAll(async () => {
    sql = connect(DSN); // assertLocalDsn + max:1 pinned in the shared fixture
    ctx = await seedRpcCtx(sql);
  });
  afterAll(async () => {
    if (sql) await sql.end({ timeout: 5 });
  });

  // Build the proname → identity-args index from a catalog fn list, ASSERTING no
  // overloaded proname (a proname with >1 identity-arg signature would collapse to
  // one classification entry, silently mis-covering one of the overloads). The maps
  // in rpc-cases.ts stay keyed by bare proname (human-maintainable); the gate
  // NORMALIZES both sides to the catalog-derived `proname(args)` composite (AC7) so
  // the key is catalog-sourced, never hand-typed — hand-typed args drift from
  // pg_get_function_identity_arguments byte-for-byte (`character varying` vs
  // `varchar`, arg-name presence) and read `stale`. The overload assertion is what
  // makes bare-proname keying provably unambiguous; it reds the moment an overload
  // appears, forcing per-signature classification then.
  function compositeIndex(fns: SecDefFn[]): { composite: (n: string) => string; overloaded: string[] } {
    const byName = new Map<string, string[]>();
    for (const f of fns) byName.set(f.proname, [...(byName.get(f.proname) ?? []), f.args]);
    const overloaded = [...byName].filter(([, sigs]) => sigs.length > 1).map(([n]) => n);
    // For a classified name absent from the catalog (stale), fall back to the bare
    // name — it matches no catalog composite, so it is correctly flagged stale.
    const composite = (n: string) => (byName.has(n) ? `${n}(${byName.get(n)![0]})` : n);
    return { composite, overloaded };
  }

  // AC8/AC7 coverage gate: every catalog fn classified exactly once, keyed on the
  // catalog-derived proname(args) composite (overload-safe).
  test("AC8: every authenticated-EXECUTE SECURITY DEFINER fn is classified (proname(args) key)", async () => {
    const catalogFns = await securityDefinerAuthenticatedFns(sql);
    const { composite, overloaded } = compositeIndex(catalogFns);
    expect(
      overloaded,
      `overloaded definer proname(s) — classification must key on proname(args): ${overloaded.join(", ")}`,
    ).toEqual([]);

    const catalog = new Set(catalogFns.map((f) => composite(f.proname)));
    const classifiedNames = [...Object.keys(ATTACK_SQL), ...Object.keys(EXCLUDED), ...Object.keys(KNOWN_EXPOSURES)];
    const classified = new Set(classifiedNames.map((n) => composite(n)));
    const uncovered = [...catalog].filter((f) => !classified.has(f));
    const stale = [...classified].filter((f) => !catalog.has(f));
    // fail on a definer fn granted to authenticated that no case covers…
    expect(uncovered, `uncovered definer fns: ${uncovered.join(", ")}`).toEqual([]);
    // …and on a classification that no longer matches the catalog.
    expect(stale, `stale RPC-case entries: ${stale.join(", ")}`).toEqual([]);
    // a fn must not be double-classified
    const dupes = [...Object.keys(ATTACK_SQL)].filter((f) => EXCLUDED[f] || KNOWN_EXPOSURES[f]);
    expect(dupes, `double-classified: ${dupes.join(", ")}`).toEqual([]);
  });

  // AC7 anon coverage gate — ENUMERATION-COVERAGE ONLY (documented scope). Every
  // anon-EXECUTE SECURITY DEFINER fn must be classified (in the SAME maps, keyed by
  // composite). This is NOT a proof that anon isolation holds under attack: the
  // EXCLUDED rationales are reasoned under `authenticated` (`founder_id =
  // auth.uid()`), and under anon (`auth.uid()=NULL`) that premise evaporates — a
  // green anon gate means "no anon-granted definer fn escaped enumeration", not
  // "anon cannot bypass". Its VALUE is forward: it is the tripwire that would have
  // auto-caught #6306 (a residual anon EXECUTE grant). Currently empty — mig 128
  // (PR #6318) revoked the #6306 anon grants, and no other definer fn is
  // anon-executable — so this gate is a near-tautology today, by design. Full anon
  // ATTACK-coverage (driving the maps under anon with re-reasoned rationales) is a
  // separate follow-up; see the #6306-sibling tracking note in rpc-cases.ts.
  test("AC7: every anon-EXECUTE SECURITY DEFINER fn is classified (enumeration-coverage only)", async () => {
    const anonFns = await securityDefinerAnonFns(sql);
    // Index built from the authenticated catalog (the maps' reference frame) plus
    // any anon-only fn, so an anon-only-granted fn still resolves to a composite.
    const { composite, overloaded } = compositeIndex([...(await securityDefinerAuthenticatedFns(sql)), ...anonFns]);
    expect(overloaded, `overloaded definer proname(s): ${overloaded.join(", ")}`).toEqual([]);
    const classifiedNames = [...Object.keys(ATTACK_SQL), ...Object.keys(EXCLUDED), ...Object.keys(KNOWN_EXPOSURES)];
    const classified = new Set(classifiedNames.map((n) => composite(n)));
    const uncovered = anonFns.map((f) => composite(f.proname)).filter((c) => !classified.has(c));
    expect(uncovered, `anon-EXECUTE definer fns with no classification: ${uncovered.join(", ")}`).toEqual([]);
  });

  // AC8 attack cases — each must DENY tenant-B.
  for (const name of Object.keys(ATTACK_SQL)) {
    test(`RPC denial: ${name}`, async () => {
      const verdict = await driveDenied(ATTACK_SQL[name](ctx));
      expect(verdict, `${name}: definer fn must deny tenant-B + tenant-A params`).toEqual({ kind: "denied" });
    });
  }

  // RPC positive control — the base-table driver has AC3 (tenant-A self-read); the
  // RPC dimension needs the mirror or the value-returning getters are vacuous (a
  // leak of A's *default* value would read identically to a denial). Under A's own
  // claims the poisoned getters MUST return the seeded non-sentinel value; if they
  // returned null here, every cross-tenant getter "denial" would be green-by-default.
  test("RPC positive control: value-returning getters return A's poisoned data under A's claims", async () => {
    const readAsA = (sqlText: string) =>
      rolledBackRaw(sql, async (t) => {
        await t`set local role authenticated`;
        await t.unsafe("select set_config('request.jwt.claims', $1, true)", [buildAuthenticatedClaims({ sub: ctx.userA })]);
        const rows = await t.unsafe(sqlText);
        return Object.values(rows[0] as object)[0];
      });
    expect(await readAsA(`select get_workspace_debug_mode('${ctx.wsA}')`), "A must read its own debug_mode=true").toBe(true);
    expect(await readAsA(`select get_workspace_autonomous_ack('${ctx.wsA}')`), "A must read its own ack timestamp").not.toBeNull();
    expect(await readAsA(`select resolve_workspace_installation_id('${ctx.wsA}')`), "A must resolve its own installation id").not.toBeNull();
  });

  // authorize_template bespoke attack (#6307 Item 2). founder-scoped write: the
  // generic driveDenied is WRONG (B writing B's OWN row returns a non-null id
  // legally). The real security property: a founder must not be able to BACK a
  // template_authorization with a scope_grant it does not OWN (the p_grant_id
  // cross-founder reference). Seed is a REAL A-owned grant (ctx.scopeGrantA), driven
  // as B; the check runs IN-txn before rollback. Owner positive control below proves
  // the fn works (the guard is ownership, not not-found).
  // EXPOSURE confirmed live (harness working as designed): authorize_template does
  // NOT validate p_grant_id ownership, so B DOES create a row referencing A's grant
  // → the `toBe(0)` assertion fails today → test.fails is green. When the ownership
  // check lands, B can no longer create the row → assertion passes → test.fails reds
  // → forces un-baseline. Tracked by #6336.
  test.fails("authorize_template EXPOSURE (baselined, #6336): tenant-B CAN back an authorization with tenant-A's grant", async () => {
    const rowsUnderB = await rolledBackRaw(sql, async (t) => {
      await t`set local role authenticated`;
      await t.unsafe("select set_config('request.jwt.claims', $1, true)", [buildAuthenticatedClaims({ sub: ctx.userB })]);
      try {
        await t.unsafe(`select authorize_template('h-${ctx.messageA}', 'general.attack', '${ctx.scopeGrantA}')`);
      } catch {
        // a raise is itself a denial — the 0-rows assertion below still holds.
      }
      const r = await t.unsafe(
        `select count(*)::int as n from template_authorizations where grant_id = $1 and founder_id = $2`,
        [ctx.scopeGrantA, ctx.userB],
      );
      return (r[0] as unknown as { n: number }).n;
    });
    expect(rowsUnderB, "tenant-B must not create a template_authorization backed by tenant-A's grant").toBe(0);
  });

  // authorize_template owner positive control — proves the fn works (the p_grant_id
  // guard, if any, is ownership; a denial for B is not a blanket not-found).
  test("authorize_template positive control: owner A CAN authorize with its own grant", async () => {
    const id = await rolledBackRaw(sql, async (t) => {
      await t`set local role authenticated`;
      await t.unsafe("select set_config('request.jwt.claims', $1, true)", [buildAuthenticatedClaims({ sub: ctx.userA })]);
      const r = await t.unsafe(`select authorize_template('h-own-${ctx.messageA}', 'general.legit', '${ctx.scopeGrantA}') as id`);
      return (r[0] as unknown as { id: string | null }).id;
    });
    expect(id, "owner A must be able to authorize a template backed by its own grant").not.toBeNull();
  });

  // AC9 RPC self-test — mirror the base matrix's AC5 for the RPC dimension: prove the
  // RPC harness can report RED, not just green on an already-safe DB. A scratch
  // SECURITY DEFINER fn (granted to authenticated, dropped on rollback) with NO
  // membership guard reads wsA's debug_mode. Because seedRpcCtx POISONED it to `true`
  // (non-sentinel), a guard-stripped read returns `true` to tenant-B → observably
  // leaked. Prefer a scratch fn over CREATE OR REPLACE of a real fn (a return-shape
  // change would flip the classifier for the wrong reason). Stripping a guard on a
  // null-defaulting getter would NOT flip (still null → still denied), so the poison
  // is load-bearing here too.
  test("AC9 RPC self-test: a guard-stripped definer fn over a poisoned value flips to leaked", async () => {
    const verdict = await rolledBackRaw(sql, async (t): Promise<Verdict> => {
      await t.unsafe(
        `create function public._rls_fuzz_selftest(p_ws uuid) returns boolean
         language sql security definer set search_path = public, pg_temp
         as $$ select debug_mode from workspaces where id = p_ws $$`,
      );
      await t.unsafe(`grant execute on function public._rls_fuzz_selftest(uuid) to authenticated`);
      await t`set local role authenticated`;
      await t.unsafe("select set_config('request.jwt.claims', $1, true)", [buildAuthenticatedClaims({ sub: ctx.userB })]);
      try {
        const rows = await t.unsafe(`select public._rls_fuzz_selftest('${ctx.wsA}') as v`);
        const v = (rows[0] as unknown as { v: unknown }).v;
        if (v === null || v === false) return { kind: "denied" }; // (would be a broken self-test)
        return classifyRpcOutcome(null, 1); // A's poisoned `true` reached B → leaked
      } catch (err) {
        return classifyRpcOutcome(err as { code?: string }, 0);
      }
    });
    expect(verdict, "guard-stripped definer fn over A's poisoned value must be LEAKED").toEqual({ kind: "leaked" });
  });

  // AC14 post-rollback verification — a DDL escape on the reused local DB must not
  // persist. After the guard-strip self-test's rollback, the scratch definer fn must
  // be ABSENT (so a guard-stripped fn cannot silently survive into a later run).
  test("AC14: the scratch self-test definer fn does not persist after rollback", async () => {
    const [{ n }] = await sql<{ n: number }[]>`
      select count(*)::int as n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.proname = '_rls_fuzz_selftest'`;
    expect(n, "scratch self-test fn must not persist past its rolled-back txn").toBe(0);
  });

  // EXCLUDED — documented as covered (no cross-tenant param surface). Asserting the
  // rationale is non-empty keeps the registry honest (no silent blanks).
  test("EXCLUDED fns each carry a rationale", () => {
    for (const [name, reason] of Object.entries(EXCLUDED)) {
      expect(reason.length, `${name}: excluded without rationale`).toBeGreaterThan(10);
    }
  });

  // KNOWN_EXPOSURES is empty: the #6306 exposures (find_stuck_active_conversations
  // + acquire/release/touch_conversation_slot) were closed by migration 128
  // (PR #6318), which revokes the residual anon/authenticated EXECUTE. Those fns
  // no longer appear in the securityDefinerAuthenticatedFns catalog, so the AC8
  // coverage gate above (stale = classified − catalog) enforces their removal from
  // all three maps. The per-fn `test.fails` denial baselines were removed here as
  // part of that un-baselining; the deploy-time verify/128_*.sql sentinel is the
  // durable regression guard for the closed grant. Future KNOWN_EXPOSURES entries
  // re-introduce a parametrized `test.fails` loop over the map.
});
