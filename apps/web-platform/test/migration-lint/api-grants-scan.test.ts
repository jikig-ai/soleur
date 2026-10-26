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
//  1. PARITY PIN — the .mjs's stripSqlNoise is a faithful PORT of
//     definer-grants.ts's (plain JS so ambient `node` can run it at the
//     tenant-integration lint position, before setup-node/npm ci). Two
//     drifting copies would silently change which SQL the lint sees; this
//     diffs their outputs on the noise shapes that actually interact
//     (comments inside dollar bodies, dollar-quotes inside comments, nested
//     block comments, ''-escaped strings, $1 params).
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
    expect(checkSql("create table public.x (id int);", "f.sql")).toHaveLength(1);
    expect(checkSql("create table public.x (id int); grant select on x to anon;", "f.sql")).toEqual([]);
  });

  it("requires USAGE (or ALL) on the derived sequence for identity columns", () => {
    const base = "create table public.t (id bigint generated always as identity primary key); grant select on t to anon;";
    expect(checkSql(base, "f.sql")).toHaveLength(1);
    expect(checkSql(base + " grant usage on sequence public.t_id_seq to service_role;", "f.sql")).toEqual([]);
    // SELECT-only sequence grant does NOT satisfy the arm
    expect(checkSql(base + " grant select on sequence public.t_id_seq to service_role;", "f.sql")).toHaveLength(1);
  });

  it("sentinel satisfies, reason-free sentinel reds", () => {
    expect(
      checkSql("create table public.a (id int); -- soleur:no-data-api: a — internal-only", "f.sql"),
    ).toEqual([]);
    expect(checkSql("create table public.a (id int); -- soleur:no-data-api: a", "f.sql")).toHaveLength(1);
  });

  it("grant to a non-api role does not satisfy", () => {
    expect(checkSql("create table public.x (id int); grant select on x to postgres;", "f.sql")).toHaveLength(1);
  });

  it("extractSentinels parses the em-dash reason", () => {
    const s = extractSentinels("-- soleur:no-data-api: audit_x — internal only\n");
    expect(s.get("audit_x")?.reason).toBe("internal only");
  });
});
