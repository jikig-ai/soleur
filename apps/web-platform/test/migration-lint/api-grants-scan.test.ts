import { describe, it, expect } from "vitest";
import { stripSqlNoise } from "./definer-grants";
import {
  stripSqlNoise as scanStripSqlNoise,
  extractCreates,
  extractSentinels,
  checkSql,
} from "../../scripts/lib/lint-migration-api-grants.mjs";

// Unit tests for lint-migration-api-grants.mjs (ADR-303 — the static tier's
// detection engine). Two halves:
//
//  1. PARITY PIN — diffs the .mjs's stripSqlNoise against definer-grants.ts's
//     on the noise shapes that actually interact (comments inside dollar
//     bodies, dollar-quotes inside comments, nested block comments,
//     ''-escaped strings, $1 params). SCOPE, exactly: `stripSqlNoise` is the
//     ONLY function pinned to definer-grants.ts. `stripSqlNoisePreserveBodies`
//     is a NEW sibling profile (bodies kept verbatim so literal DO-block
//     GRANTs count) with no parity target; extractCreates/extractGrants/
//     extractSentinels/extractBlanketGrants are new logic covered only by the
//     CHECKER half below — none of them are diffed against definer-grants.ts.
//  2. CHECKER — the create/grant/sentinel/sequence logic, on synthesized
//     fixtures only (cq-test-fixtures-synthesized-only).

const NOISE_FIXTURES = [
  "-- line comment\ncreate table t (id int);\n",
  "/* block /* nested */ still comment */ create view v as select 1;",
  "do $$ begin execute 'create table x()'; end $$;",
  "do $tag$ begin -- not a comment inside $tag$ end $tag$; select 1;",
  "insert into t values ('it''s -- not comment');",
  "select $1, $$quoted$$, $p$tagged$p$;",
  "grant select on public.t to anon; -- soleur:not-a-sentinel",
];

describe("stripSqlNoise parity (ported copy must match definer-grants.ts exactly)", () => {
  it("identical output on every noise-interaction fixture", () => {
    for (const src of NOISE_FIXTURES) {
      expect(scanStripSqlNoise(src)).toBe(stripSqlNoise(src));
    }
  });
});

describe("extractCreates", () => {
  const names = (sql: string) => extractCreates(stripSqlNoise(sql)).map((c) => `${c.kind}:${c.name}`);

  it("detects table/view/matview/sequence, qualified and bare, case-insensitive", () => {
    expect(
      names(
        "CREATE TABLE public.a (id int); create view b as select 1; " +
          "CREATE MATERIALIZED VIEW public.c AS SELECT 1; create sequence public.d_seq;",
      ),
    ).toEqual(["table:a", "view:b", "matview:c", "sequence:d_seq"]);
  });

  it("skips non-public schemas, temp, and partition children", () => {
    expect(
      names(
        "create table auth.s (id int); create temp table tmp1 (id int); " +
          "create table public.child partition of public.parent; create table public.k (id int);",
      ),
    ).toEqual(["table:k"]);
  });
});

describe("checkSql", () => {
  it("reds an ungranted relation and passes a granted one", () => {
    expect(checkSql("create table public.x (id int);")).toHaveLength(1);
    expect(checkSql("create table public.x (id int); grant select on x to anon;")).toEqual([]);
  });

  it("column-list grant form satisfies (it IS api exposure — the 006/079 shape)", () => {
    expect(
      checkSql("create table public.x (id int, email text); grant select (id, email) on table public.x to authenticated;"),
    ).toEqual([]);
    expect(
      checkSql("create table public.x (id int, email text); grant select (id), update (email) on x to anon;"),
    ).toEqual([]);
  });

  it("blanket ON ALL TABLES/SEQUENCES IN SCHEMA public is rejected outright", () => {
    // Two violations: the blanket form itself is flagged AND it does not
    // satisfy the create — the relation still needs its own GRANT/sentinel.
    expect(
      checkSql("create table public.x (id int); grant select on all tables in schema public to authenticated;"),
    ).toHaveLength(2);
    expect(
      checkSql("grant usage on all sequences in schema public to anon, service_role;"),
    ).toHaveLength(1);
    // ...but the same form scoped to another schema or a non-api role is not ours to flag
    expect(checkSql("grant select on all tables in schema auth to postgres;")).toEqual([]);
  });

  it("requires USAGE (or ALL) on the derived sequence for identity columns", () => {
    const base = "create table public.t (id bigint generated always as identity primary key); grant select on t to anon;";
    expect(checkSql(base)).toHaveLength(1);
    expect(checkSql(base + " grant usage on sequence public.t_id_seq to service_role;")).toEqual([]);
    // SELECT-only sequence grant does NOT satisfy the arm
    expect(checkSql(base + " grant select on sequence public.t_id_seq to service_role;")).toHaveLength(1);
  });

  it("LIKE … INCLUDING ALL|IDENTITY copies need a sequence grant (names underivable)", () => {
    const base = "create table public.t (like public.src including all); grant select on t to anon;";
    expect(checkSql(base)).toHaveLength(1);
    expect(checkSql(base + " grant usage on sequence public.t_id_seq to service_role;")).toEqual([]);
    expect(
      checkSql("create table public.t (like public.src including identity); grant select on t to anon;"),
    ).toHaveLength(1);
    // plain LIKE (no INCLUDING ALL/IDENTITY) does not trigger the arm
    expect(checkSql("create table public.t (like public.src including defaults); grant select on t to anon;")).toEqual([]);
  });

  it("sentinel satisfies, reason-free sentinel reds", () => {
    expect(
      checkSql("create table public.a (id int); -- soleur:no-data-api: a — internal-only"),
    ).toEqual([]);
    expect(checkSql("create table public.a (id int); -- soleur:no-data-api: a")).toHaveLength(1);
    // schema-qualified sentinel name is the same relation
    expect(
      checkSql("create table public.a (id int); -- soleur:no-data-api: public.a — internal-only"),
    ).toEqual([]);
  });

  it("sentinel inside a /* */ comment or dollar-quoted body does NOT exempt", () => {
    expect(
      checkSql("create table public.a (id int); /* -- soleur:no-data-api: a — commented out */"),
    ).toHaveLength(1);
    expect(
      checkSql("create table public.a (id int); do $$ begin execute '-- soleur:no-data-api: a — x'; end $$;"),
    ).toHaveLength(1);
    expect(
      checkSql("create table public.a (id int); do $tag$ begin -- soleur:no-data-api: a — x end $tag$;"),
    ).toHaveLength(1);
    // but a -- comment inside a line that only looks noisy still counts
    expect(
      checkSql("create table public.a (id int); -- soleur:no-data-api: a — real\nselect '/*';"),
    ).toEqual([]);
  });

  it("grant to a non-api role does not satisfy", () => {
    expect(checkSql("create table public.x (id int); grant select on x to postgres;")).toHaveLength(1);
  });

  it("extractSentinels parses the em-dash reason", () => {
    const s = extractSentinels("-- soleur:no-data-api: audit_x — internal only\n");
    expect(s.get("audit_x")?.reason).toBe("internal only");
    const q = extractSentinels("-- soleur:no-data-api: public.audit_x — internal only\n");
    expect(q.get("audit_x")?.reason).toBe("internal only");
  });
});
