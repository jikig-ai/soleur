import { describe, it, expect } from "vitest";
import {
  stripSqlNoise,
  normalizeSignature,
  extractDefinerFns,
  parseRevokes,
  parseGrants,
  parseDrops,
  classifyDefinerFns,
  type CorpusFile,
} from "./definer-grants";

// Unit fixtures for the DB-free SECURITY DEFINER grant-hygiene detector (#6328,
// ADR-112). Every fixture is SYNTHESIZED inline (`cq-test-fixtures-synthesized-only`)
// — no real migration text — so a corpus reshuffle can never make these vacuous.
//
// The detector is the SUBORDINATE static pre-filter; the authoritative durable
// guard is the runtime rls-authz-fuzz AC8 gate. These tests pin the pre-filter's
// blind-spot classes: case-insensitive detection, body-form-agnosticism, the
// revoke-union of {public, anon, authenticated}, RETURNS TRIGGER exclusion,
// type-precise overload discrimination, DROP-without-recreate exclusion, and
// comment/dollar-body noise stripping.

/** Build a one-file corpus and return the verdict for the named fn. */
function verdict(
  files: CorpusFile[],
  name: string,
  opts: { authenticatedCallable?: Set<string>; grandfather?: Set<string> } = {},
) {
  const results = classifyDefinerFns(files, {
    authenticatedCallable: opts.authenticatedCallable ?? new Set(),
    grandfather: opts.grandfather ?? new Set(),
  });
  return results.filter((r) => r.fn.name === name);
}

describe("stripSqlNoise", () => {
  it("strips -- line comments", () => {
    expect(stripSqlNoise("select 1; -- grant execute to authenticated\nselect 2;")).not.toMatch(
      /grant/i,
    );
  });

  it("strips /* */ block comments (incl. embedded grant prose)", () => {
    const src = "/* revoke all from public */ create function public.f() returns int;";
    expect(stripSqlNoise(src)).not.toMatch(/revoke/i);
    expect(stripSqlNoise(src)).toMatch(/create function/i);
  });

  it("strips dollar-quoted bodies so embedded EXECUTE 'GRANT ...' is not a top-level grant", () => {
    const src =
      "create function public.f() returns void language plpgsql as $$ begin execute 'grant execute on function public.x() to authenticated'; end $$;";
    const out = stripSqlNoise(src);
    // the AS marker survives (header termination) but the body text is gone
    expect(out).toMatch(/\bas\b/i);
    expect(out).not.toMatch(/grant/i);
  });

  it("strips $tag$-delimited bodies", () => {
    const src = "create function public.f() as $body$ select 'grant'; $body$;";
    expect(stripSqlNoise(src)).not.toMatch(/select/i);
  });

  it("leaves positional $1 params alone", () => {
    expect(stripSqlNoise("where id = $1 and x = $2")).toContain("$1");
  });
});

describe("normalizeSignature", () => {
  it("reduces CREATE-side params to a type vector (names + DEFAULT stripped)", () => {
    expect(normalizeSignature("p_workspace_id uuid, p_status text default null")).toBe(
      "uuid, text",
    );
  });
  it("matches REVOKE-side type-only params", () => {
    expect(normalizeSignature("uuid, uuid, integer")).toBe("uuid, uuid, integer");
  });
  it("canonicalises int -> integer so CREATE `int` matches REVOKE `integer`", () => {
    expect(normalizeSignature("p_limit int default 50")).toBe(
      normalizeSignature("integer"),
    );
  });
  it("keeps array + parametric types intact under balanced-paren split", () => {
    expect(normalizeSignature("p_lens text[], p_amount numeric(10,2)")).toBe(
      "text[], numeric(10,2)",
    );
  });
  it("returns empty string for a no-arg fn", () => {
    expect(normalizeSignature("")).toBe("");
  });
});

describe("extractDefinerFns", () => {
  it("detects LOWERCASE `create ... security definer` (the #6306 blind spot)", () => {
    const sql =
      "create or replace function public.finder(p_threshold_seconds integer)\nreturns setof uuid\nlanguage sql\nsecurity definer\nset search_path = public, pg_temp\nas $$ select id from t $$;";
    const fns = extractDefinerFns("037_x.sql", sql);
    expect(fns).toHaveLength(1);
    expect(fns[0].name).toBe("finder");
    expect(fns[0].signature).toBe("integer");
    expect(fns[0].returnsTrigger).toBe(false);
  });

  it("does NOT detect a SECURITY INVOKER fn", () => {
    const sql =
      "create function public.g() returns int language sql security invoker as $$ select 1 $$;";
    expect(extractDefinerFns("x.sql", sql)).toHaveLength(0);
  });

  it("captures the returnsTrigger flag", () => {
    const sql =
      "CREATE OR REPLACE FUNCTION public.t_fn() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$ begin return new; end $$;";
    const fns = extractDefinerFns("x.sql", sql);
    expect(fns[0].returnsTrigger).toBe(true);
  });

  it("detects `begin atomic` (SQL-standard) body form", () => {
    const sql =
      "create function public.h(p_a uuid) returns boolean security definer set search_path = public, pg_temp begin atomic select true; end;";
    const fns = extractDefinerFns("x.sql", sql);
    expect(fns).toHaveLength(1);
    expect(fns[0].name).toBe("h");
  });

  it("balanced-paren signature capture survives numeric(10,2) defaults", () => {
    const sql =
      "create function public.p(p_amt numeric(10,2) default 0) returns void security definer set search_path=public,pg_temp as $$ $$;";
    expect(extractDefinerFns("x.sql", sql)[0].signature).toBe("numeric(10,2)");
  });
});

describe("parseRevokes / parseGrants / parseDrops", () => {
  it("unions REVOKE role lists across statement forms", () => {
    const sql =
      "revoke execute on function public.f(uuid) from anon, authenticated;\nrevoke all on function public.f(uuid) from public;";
    const r = parseRevokes(sql).filter((s) => s.name === "f");
    const roles = new Set(r.flatMap((s) => [...s.roles]));
    expect(roles).toEqual(new Set(["anon", "authenticated", "public"]));
  });

  it("parses GRANT EXECUTE ... TO authenticated", () => {
    const g = parseGrants("grant execute on function public.f(uuid) to authenticated;");
    expect(g[0].roles.has("authenticated")).toBe(true);
  });

  it("parses DROP FUNCTION with type-precise signature", () => {
    const d = parseDrops("drop function if exists public.f(uuid, uuid, integer);");
    expect(d[0]).toMatchObject({ name: "f", signature: "uuid, uuid, integer" });
  });
});

describe("classifyDefinerFns — the corpus revoke-union", () => {
  it("VIOLATION: lowercase definer fn, no revoke anywhere", () => {
    const files: CorpusFile[] = [
      {
        file: "900_x.sql",
        sql: "create function public.svc(p_ws uuid) returns void security definer set search_path=public,pg_temp as $$ $$;",
      },
    ];
    expect(verdict(files, "svc")[0].classification).toBe("violation");
  });

  it("PASS: created in A, revoked from all three roles in a later file B (cross-file union)", () => {
    const files: CorpusFile[] = [
      {
        file: "900_a.sql",
        sql: "create function public.svc(p_ws uuid) returns void security definer set search_path=public,pg_temp as $$ $$;",
      },
      {
        file: "901_b.sql",
        sql: "revoke all on function public.svc(uuid) from public, anon, authenticated;",
      },
    ];
    expect(verdict(files, "svc")[0].classification).toBe("pass-union");
  });

  it("VIOLATION: revoke from anon + authenticated but NOT public (public ⊇ {anon,authenticated})", () => {
    const files: CorpusFile[] = [
      {
        file: "900_a.sql",
        sql: "create function public.svc(p_ws uuid) returns void security definer set search_path=public,pg_temp as $$ $$; revoke all on function public.svc(uuid) from anon, authenticated;",
      },
    ];
    expect(verdict(files, "svc")[0].classification).toBe("violation");
  });

  it("PASS (returns-trigger): a trigger definer fn needs no grant revoke (no EXECUTE path)", () => {
    const files: CorpusFile[] = [
      {
        file: "900_a.sql",
        sql: "create function public.t_fn() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$ begin return new; end $$;",
      },
    ];
    expect(verdict(files, "t_fn")[0].classification).toBe("returns-trigger");
  });

  it("type-precise: two overloads, only one revoked → the un-revoked one VIOLATES", () => {
    const files: CorpusFile[] = [
      {
        file: "900_a.sql",
        sql: "create function public.ov(a uuid, b uuid, c integer) returns void security definer set search_path=public,pg_temp as $$ $$;\ncreate function public.ov(a uuid, b uuid, c integer, d uuid) returns void security definer set search_path=public,pg_temp as $$ $$;\nrevoke all on function public.ov(uuid, uuid, integer, uuid) from public, anon, authenticated;",
      },
    ];
    const v = verdict(files, "ov");
    const threeArg = v.find((r) => r.fn.signature === "uuid, uuid, integer");
    const fourArg = v.find((r) => r.fn.signature === "uuid, uuid, integer, uuid");
    expect(threeArg?.classification).toBe("violation");
    expect(fourArg?.classification).toBe("pass-union");
  });

  it("excludes DROP-without-recreate (3-arg created then dropped, never recreated)", () => {
    const files: CorpusFile[] = [
      {
        file: "900_a.sql",
        sql: "create function public.ov(a uuid, b uuid, c integer) returns void security definer set search_path=public,pg_temp as $$ $$;",
      },
      {
        file: "901_b.sql",
        sql: "drop function if exists public.ov(uuid, uuid, integer);\ncreate function public.ov(a uuid, b uuid, c integer, d uuid) returns void security definer set search_path=public,pg_temp as $$ $$;\nrevoke all on function public.ov(uuid, uuid, integer, uuid) from public, anon, authenticated;",
      },
    ];
    const v = verdict(files, "ov");
    const threeArg = v.find((r) => r.fn.signature === "uuid, uuid, integer");
    expect(threeArg?.classification).toBe("dropped");
  });

  it("ignores a .down.sql re-grant (corpus must exclude down files upstream)", () => {
    // The corpus builder excludes *.down.sql; this asserts that a re-grant present
    // ONLY in a down file does not satisfy the union for a forward fn.
    const files: CorpusFile[] = [
      {
        file: "900_a.sql",
        sql: "create function public.svc(p_ws uuid) returns void security definer set search_path=public,pg_temp as $$ $$;",
      },
    ];
    // caller is responsible for excluding down files; here the forward-only corpus
    // has no revoke → violation (a down-file revoke would never be passed in).
    expect(verdict(files, "svc")[0].classification).toBe("violation");
  });

  it("ignores a grant embedded in a block comment / dollar body", () => {
    const files: CorpusFile[] = [
      {
        file: "900_a.sql",
        sql: "/* revoke all on function public.svc(uuid) from public, anon, authenticated; */ create function public.svc(p_ws uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$ begin execute 'revoke all on function public.svc(uuid) from public, anon, authenticated'; end $$;",
      },
    ];
    // the only revoke text lives in a comment + a dollar body → not counted → violation
    expect(verdict(files, "svc")[0].classification).toBe("violation");
  });

  it("authenticated-callable allowlist: PASS when listed, VIOLATION when a bare grant-to-authenticated fn is absent", () => {
    const files: CorpusFile[] = [
      {
        file: "900_a.sql",
        sql: "create function public.set_current_workspace_id(p_ws uuid) returns void security definer set search_path=public,pg_temp as $$ $$;\ngrant execute on function public.set_current_workspace_id(uuid) to authenticated;",
      },
    ];
    expect(
      verdict(files, "set_current_workspace_id", {
        authenticatedCallable: new Set(["set_current_workspace_id"]),
      })[0].classification,
    ).toBe("authenticated-callable");
    expect(verdict(files, "set_current_workspace_id")[0].classification).toBe("violation");
  });

  it("grandfather allowlist classifies a listed pre-existing gap", () => {
    const files: CorpusFile[] = [
      {
        file: "900_a.sql",
        sql: "create function public.legacy(p_ws uuid) returns void security definer set search_path=public,pg_temp as $$ $$;",
      },
    ];
    expect(
      verdict(files, "legacy", { grandfather: new Set(["legacy"]) })[0].classification,
    ).toBe("grandfather");
  });
});
