// Api-role table/sequence grant registry (ADR-303 — the AUTHORITATIVE tier of
// the two-tier table-grant guard, mirroring ADR-112's split).
//
// Every `public`-schema relation (relkind r,v,m) and sequence (relkind S) that
// `publicApiRelations`/`publicApiSequences` enumerate on the migrated stack
// must appear in EXACTLY ONE classification here — the rls-grants gate asserts
// catalog⇔registry parity and fails on any unclassified member (self-tracking:
// a new public relation reds the suite until classified) and on any registry
// entry whose relation no longer exists (stale).
//
//  - EXPOSED: the relation holds api-role privileges; `grants` records the
//    EXACT intended per-role verb sets (table-level `privileges`, column-level
//    `columnPrivileges` for the deliberate 006/079 splits where table-level was
//    revoked). The gate asserts effective privileges EQUAL this set — both
//    directions: a missing grant reds (P2), an unregistered extra reds (P3).
//  - INTERNAL: the relation must hold ZERO api-role privileges — the live-
//    catalog counterpart of the migration lint's `soleur:no-data-api:`
//    sentinel. A reason is REQUIRED (the ADR-112 escape-hatch lesson: a
//    reason-free exemption is an allowlist entry with no rationale).
//  - RETIRED: the relation was DROPPED or RENAMED away — it is EXPECTED to be
//    absent from the live catalog, so it is exempt from the stale-entry check
//    that would otherwise red on it (the remediation path for removals: keep
//    the classification as the record of intentional removal rather than
//    deleting the registry row). A reason is REQUIRED, and a RETIRED entry
//    whose relation still EXISTS reds — the retirement record is then wrong.
//
// SEEDING. The EXPOSED set is derived BY PARSING migration
// 174_api_data_grants_snapshot.sql at load — the generated snapshot IS the
// audited effective prd posture, so the registry cannot drift from the DDL it
// is meant to verify (a hand-copied list of ~70 relations would rot before
// review). INTERNAL and OVERRIDES are hand-authored for relations 174 does not
// cover; the parity assertion catches any catalog member none of the three
// sources classifies.

import { readFileSync } from "node:fs";
import path from "node:path";

/** The three roles the 2026-10-30 Supabase flip affects (snapshot scope, ADR-303). */
export const API_ROLES = ["anon", "authenticated", "service_role"] as const;
export type ApiRole = (typeof API_ROLES)[number];

/**
 * Privileges Postgres tracks at table level on relkind r/v/m — used as the
 * probe universe by the gate (asserting held == registered over EVERY verb is
 * what makes the check bidirectional). MAINTAIN is PG16+; the fuzz stack pins
 * major_version 17.
 */
export const TABLE_VERBS = [
  "DELETE",
  "INSERT",
  "MAINTAIN",
  "REFERENCES",
  "SELECT",
  "TRIGGER",
  "TRUNCATE",
  "UPDATE",
] as const;

/** Privileges Postgres tracks on sequences (relkind S). USAGE is nextval; the flip drops it. */
export const SEQUENCE_VERBS = ["USAGE", "SELECT", "UPDATE"] as const;

/** The intended api-role privilege surface of one relation. */
export interface GrantSet {
  /** role -> table-level (or sequence-level) verbs held. Absent role = nothing held. */
  privileges: Map<ApiRole, Set<string>>;
  /**
   * role -> column name -> verbs held at COLUMN level (granted while the same
   * verb is NOT held at table level — the 006/079 deliberate splits, e.g.
   * workspaces.authenticated SELECT on 8 named columns). Empty when all access
   * is table-level.
   */
  columnPrivileges: Map<ApiRole, Map<string, Set<string>>>;
}

export type RegistryEntry =
  | { kind: "EXPOSED"; grants: GrantSet; provenance: string }
  | { kind: "INTERNAL"; reason: string }
  | { kind: "RETIRED"; reason: string };

const SNAPSHOT_PATH = path.resolve(
  __dirname,
  "../../supabase/migrations/174_api_data_grants_snapshot.sql",
);

// Derived from the API_ROLES tuple — a hand-retyped regex would silently drift
// from the authoritative list.
const _API_ROLE_RE = `(${API_ROLES.join("|")})`;
const _RELNAME_RE = '"?([a-z_][a-z0-9_]*)"?';
const _ON_PUBLIC_TABLE = `on\\s+table\\s+public\\s*\\.\\s*${_RELNAME_RE}\\s+to\\s+${_API_ROLE_RE}\\b`;

/**
 * Parse the generated snapshot's GRANT statements into per-relation
 * {@link GrantSet}s. Operates on the raw file: the generator emits GRANTs only
 * as top-level statements inside `DO $$ … to_regclass preconditions $$`
 * blocks, so no noise-stripping is needed here (a `GRANT` inside a comment or
 * string would be a generator bug, and a wrong parse still reds the gate's
 * equality check rather than passing silently).
 */
export function parseSnapshotGrants(sql: string): Map<string, GrantSet> {
  const out = new Map<string, GrantSet>();
  const ensure = (rel: string): GrantSet => {
    let g = out.get(rel);
    if (!g) {
      g = { privileges: new Map(), columnPrivileges: new Map() };
      out.set(rel, g);
    }
    return g;
  };
  const addVerbs = (rel: string, role: string, verbs: string) => {
    const g = ensure(rel);
    const set = g.privileges.get(role as ApiRole) ?? new Set<string>();
    for (const v of verbs.split(",")) {
      const t = v.trim().toUpperCase();
      if (t) set.add(t);
    }
    g.privileges.set(role as ApiRole, set);
  };

  // Table-level:  GRANT <verbs> ON TABLE public."<rel>" TO <role>;
  // The verb class excludes '(' so the column-list form cannot match here.
  const TABLE_GRANT = new RegExp(`\\bgrant\\s+([a-z_,\\s]+?)\\s+${_ON_PUBLIC_TABLE}`, "gi");
  for (const m of sql.matchAll(TABLE_GRANT)) addVerbs(m[2]!, m[3]!, m[1]!);

  // Column-level: GRANT <verb> ("<col>", …) ON TABLE public."<rel>" TO <role>;
  const COLUMN_GRANT = new RegExp(
    `\\bgrant\\s+([a-z_]+)\\s*\\(([^)]*)\\)\\s+${_ON_PUBLIC_TABLE}`,
    "gi",
  );
  for (const m of sql.matchAll(COLUMN_GRANT)) {
    const g = ensure(m[3]!);
    const role = m[4] as ApiRole;
    const verb = m[1]!.toUpperCase();
    let perRole = g.columnPrivileges.get(role);
    if (!perRole) {
      perRole = new Map();
      g.columnPrivileges.set(role, perRole);
    }
    for (const raw of m[2]!.split(",")) {
      const col = raw.trim().replace(/^"|"$/g, "");
      if (!col) continue;
      const verbs = perRole.get(col) ?? new Set<string>();
      verbs.add(verb);
      perRole.set(col, verbs);
    }
  }

  // Sequence-level: GRANT <verbs> ON SEQUENCE public."<rel>" TO <role>;
  const SEQ_GRANT = new RegExp(
    `\\bgrant\\s+([a-z_,\\s]+?)\\s+on\\s+sequence\\s+public\\s*\\.\\s*${_RELNAME_RE}\\s+to\\s+${_API_ROLE_RE}\\b`,
    "gi",
  );
  for (const m of sql.matchAll(SEQ_GRANT)) addVerbs(m[2]!, m[3]!, m[1]!);

  return out;
}

/** Author an EXPOSED registry entry (for OVERRIDES) with plain literals. */
export function exposed(
  privileges: Partial<Record<ApiRole, readonly string[]>>,
  opts: {
    columns?: Partial<Record<ApiRole, Record<string, readonly string[]>>>;
    provenance?: string;
  } = {},
): RegistryEntry {
  const grants: GrantSet = {
    privileges: new Map(
      Object.entries(privileges).map(([r, vs]) => [r as ApiRole, new Set(vs.map((v) => v.toUpperCase()))]),
    ),
    columnPrivileges: new Map(
      Object.entries(opts.columns ?? {}).map(([r, cols]) => [
        r as ApiRole,
        new Map(Object.entries(cols).map(([c, vs]) => [c, new Set(vs.map((v) => v.toUpperCase()))])),
      ]),
    ),
  };
  return {
    kind: "EXPOSED",
    grants,
    provenance: opts.provenance ?? "hand-authored OVERRIDES entry in table-grants.ts",
  };
}

/**
 * INTERNAL — public relations holding ZERO api-role privileges by design.
 * Empty today: every catalog member carries >=1 api-role grant (all 62
 * relations enumerated on prd 2026-10-26 are covered by the 174 snapshot,
 * `_schema_migrations` included). The classification arm exists for relations
 * that arrive WITH a `soleur:no-data-api:` sentinel — the lint requires the
 * sentinel to carry a reason; this map requires the same, keyed by relname.
 */
const INTERNAL: Record<string, string> = {};

/**
 * RETIRED — relations the corpus has DROPPED or RENAMED away. The entry is
 * the record of intentional removal: excluded from the stale-entry check (a
 * retired relation is SUPPOSED to be absent from the catalog) and from the
 * privilege assertions (there is nothing to probe). A reason is REQUIRED;
 * an entry whose relation still exists in the live catalog reds — either the
 * relation was never actually removed or the entry name is a typo.
 *
 * Unlike INTERNAL, a RETIRED name MAY collide with a parsed snapshot entry —
 * that is the normal case: dropping a snapshot-covered relation leaves its
 * 174 GRANTs in place (the `to_regclass` precondition makes them no-ops on
 * replay), and the RETIRED row REPLACES the parsed EXPOSED entry so the gate
 * stops expecting the relation in the catalog. This replacement is the
 * remediation path a future DROP/RENAME migration uses.
 */
const RETIRED: Record<string, string> = {};

/**
 * OVERRIDES — registry entries for relations whose intended grant set is NOT
 * in migration 174: relations created after the snapshot (the author declares
 * the api surface here, mirroring the migration's own GRANTs — the lint makes
 * omitting them a PR-time red), or a deliberate divergence from the audited
 * prd posture. OVERRIDES entries REPLACE parsed snapshot entries for the same
 * name; INTERNAL entries must NOT collide (a relation cannot be both).
 */
const OVERRIDES: Record<string, RegistryEntry> = {
  // Migration 180 (#4672): durable approval requests. Owner SELECT through RLS is the one api surface (the approvals
  // landing page reads the row as the signed-in Owner); every write is a SECURITY DEFINER approval RPC and
  // service_role holds NO table privilege at all (it reaches the table only through the RPCs). Created after the 174 snapshot.
  "approval_request": exposed({ authenticated: ["SELECT"] }, { provenance: "migration 180 (#4672): authenticated SELECT only (Owner-gated by RLS); no write grant for any api role; service_role has no table access (RPC-only)" }),
  // OVERRIDES for migration 178's default-era api-grant narrowing (#11193 —
  // the deferred pass ADR-303 §Consequences names). Each entry replaces the
  // 174 snapshot's parsed full-DML set with the censused intended posture;
  // per-relation consumer evidence lives in the 178 migration header.
  "_schema_migrations": { kind: "INTERNAL", reason: "migration 178 (#11193) revokes all three api roles: every _schema_migrations reader/writer is a psql $DATABASE_URL script as the postgres role (run-migrations.sh, dev-ledger-parity*, preflight-schema-vs-ledger) — no api-role client exists" },
  "api_keys": exposed({ authenticated: ["SELECT"], service_role: ["DELETE","INSERT","MAINTAIN","REFERENCES","SELECT","TRIGGER","TRUNCATE","UPDATE"] }, { provenance: "migration 178 (#11193): authenticated reads it via tenant/cookie clients (byok-lease, codex-credential-provider, agent-runner, /api/services); all writes are service-client" }),
  "audit_byok_use": exposed({ authenticated: ["SELECT"], service_role: ["DELETE","INSERT","MAINTAIN","REFERENCES","SELECT","TRIGGER","TRUNCATE","UPDATE"] }, { provenance: "migration 178 (#11193): authenticated reads it via cookie client (dashboard/audit, today-cost route); writes via SECURITY DEFINER RPCs need no base-table grant" }),
  "audit_github_token_use": exposed({ authenticated: ["SELECT"], service_role: ["DELETE","INSERT","MAINTAIN","REFERENCES","SELECT","TRIGGER","TRUNCATE","UPDATE"] }, { provenance: "migration 178 (#11193): authenticated reads it via cookie client (dashboard/audit/github); writes via record_github_token_use definer RPC" }),
  "dsar_export_jobs": exposed({ authenticated: ["SELECT"], service_role: ["DELETE","INSERT","MAINTAIN","REFERENCES","SELECT","TRIGGER","TRUNCATE","UPDATE"] }, { provenance: "migration 178 (#11193): authenticated SELECT is the GDPR data-portability surface (settings/privacy, /api/account/export/*); writes via service-client dsar-export/account-delete" }),
  "flag_flip_audit": exposed({ service_role: ["DELETE","INSERT","MAINTAIN","REFERENCES","SELECT","TRIGGER","TRUNCATE","UPDATE"] }, { provenance: "migration 178 (#11193): no anon/authenticated call site exists; writes via audit_flag_flip definer RPC; service_role-only per the 175 convention" }),
  "users": exposed(
    { authenticated: ["SELECT"], service_role: ["DELETE","INSERT","MAINTAIN","REFERENCES","SELECT","TRIGGER","TRUNCATE","UPDATE"] },
    {
      columns: { authenticated: { email: ["UPDATE"], nudges_dismissed: ["UPDATE"], onboarding_completed_at: ["UPDATE"], pwa_banner_dismissed_at: ["UPDATE"], runtime_explainer_dismissed_at: ["UPDATE"] } },
      provenance: "migration 178 (#11193) revokes the wart table-level UPDATE and re-asserts 006's intent: authenticated holds SELECT + the censused column UPDATE set (use-onboarding dismissals, team-names nudges, 006's email). kb_sync_history is deliberately absent — 017's RESTRICTIVE policy pins it and writes route through append_kb_sync_row (053 definer RPC)",
    },
  ),
  // OVERRIDES for migration 175's shape-(iv) revokes: 174's parsed snapshot still
  // expects anon/authenticated grants on these seven tables, but the corpus's
  // effective state post-175 is service_role-only — the TOM-4 documented posture.
  "denied_jti": exposed({ service_role: ["DELETE","INSERT","MAINTAIN","REFERENCES","SELECT","TRIGGER","TRUNCATE","UPDATE"] }, { provenance: "migration 175 revokes anon/authenticated on TOM-4 shape-(iv) tables (inert on prd, RLS already denies); aligns corpus with the documented service-role-only posture" }),
  "dsar_export_audit_pii": exposed({ service_role: ["DELETE","INSERT","MAINTAIN","REFERENCES","SELECT","TRIGGER","TRUNCATE","UPDATE"] }, { provenance: "migration 175 revokes anon/authenticated on TOM-4 shape-(iv) tables (inert on prd, RLS already denies); aligns corpus with the documented service-role-only posture" }),
  "mint_rate_window": exposed({ service_role: ["DELETE","INSERT","MAINTAIN","REFERENCES","SELECT","TRIGGER","TRUNCATE","UPDATE"] }, { provenance: "migration 175 revokes anon/authenticated on TOM-4 shape-(iv) tables (inert on prd, RLS already denies); aligns corpus with the documented service-role-only posture" }),
  "pending_checkout_sessions": exposed({ service_role: ["DELETE","INSERT","MAINTAIN","REFERENCES","SELECT","TRIGGER","TRUNCATE","UPDATE"] }, { provenance: "migration 175 revokes anon/authenticated on TOM-4 shape-(iv) tables (inert on prd, RLS already denies); aligns corpus with the documented service-role-only posture" }),
  "tc_acceptances": exposed({ service_role: ["DELETE","INSERT","MAINTAIN","REFERENCES","SELECT","TRIGGER","TRUNCATE","UPDATE"] }, { provenance: "migration 175 revokes anon/authenticated on TOM-4 shape-(iv) tables (inert on prd, RLS already denies); aligns corpus with the documented service-role-only posture" }),
  "tenant_deploy_audit": exposed({ service_role: ["DELETE","INSERT","MAINTAIN","REFERENCES","SELECT","TRIGGER","TRUNCATE","UPDATE"] }, { provenance: "migration 175 revokes anon/authenticated on TOM-4 shape-(iv) tables (inert on prd, RLS already denies); aligns corpus with the documented service-role-only posture" }),
  "workspace_member_actions": exposed({ service_role: ["MAINTAIN","REFERENCES","SELECT","TRIGGER","TRUNCATE"] }, { provenance: "migration 175 revokes anon/authenticated on TOM-4 shape-(iv) tables (inert on prd, RLS already denies); aligns corpus with the documented service-role-only posture" }),
};

const SNAPSHOT_GRANTS = parseSnapshotGrants(readFileSync(SNAPSHOT_PATH, "utf8"));

/**
 * How many relations the 174 snapshot parse produced — the NON-VACUITY floor
 * asserts on THIS count (not the registry's size, which INTERNAL/OVERRIDES/
 * RETIRED inflate or mutate) so a dead parser is loud independent of the
 * hand-authored maps.
 */
export const SNAPSHOT_PARSED_RELATION_COUNT = SNAPSHOT_GRANTS.size;

function buildRegistry(): ReadonlyMap<string, RegistryEntry> {
  const registry = new Map<string, RegistryEntry>();
  for (const [name, grants] of SNAPSHOT_GRANTS) {
    registry.set(name, {
      kind: "EXPOSED",
      grants,
      provenance: "parsed from supabase/migrations/174_api_data_grants_snapshot.sql",
    });
  }
  for (const [name, reason] of Object.entries(INTERNAL)) {
    if (registry.has(name)) {
      throw new Error(
        `table-grants.ts: '${name}' is classified INTERNAL but migration 174 grants it — resolve the conflict (remove the grant or drop the INTERNAL entry)`,
      );
    }
    if (!reason.trim()) {
      throw new Error(`table-grants.ts: INTERNAL entry '${name}' has no reason — reason is required`);
    }
    registry.set(name, { kind: "INTERNAL", reason });
  }
  for (const [name, reason] of Object.entries(RETIRED)) {
    if (!reason.trim()) {
      throw new Error(`table-grants.ts: RETIRED entry '${name}' has no reason — reason is required`);
    }
    // Replaces any parsed snapshot/INTERNAL entry for the same name — a
    // dropped snapshot relation keeps its (now-no-op) 174 GRANTs, so the
    // parsed EXPOSED row is stale the moment the DROP lands.
    registry.set(name, { kind: "RETIRED", reason });
  }
  for (const [name, entry] of Object.entries(OVERRIDES)) registry.set(name, entry);
  return registry;
}

/**
 * The single classification registry. Keys are bare relnames — pg_class names
 * are unique per schema across relkinds, so a table and a sequence can never
 * collide on the same key.
 */
export const TABLE_GRANT_REGISTRY: ReadonlyMap<string, RegistryEntry> = buildRegistry();

/** Non-vacuity floor: the snapshot covered 62 public relations on prd 2026-10-26.
 *  Asserted against {@link SNAPSHOT_PARSED_RELATION_COUNT} — the parsed-snapshot
 *  count only, never the registry total (hand-authored entries must not feed a
 *  floor that exists to prove the PARSER produced the prd set). */
export const SNAPSHOT_RELATION_FLOOR = 62;
