import { GITHUB_ACTIONS_BOT_DB_ID } from "./allowlist";
import { SCHEMA_VERSION } from "./schema";

/**
 * Replace `[bot]` with `-bot` so the principal can be used as a path segment in
 * R2 keys without bracket-encoding ambiguity (Kieran F8). The canonical
 * principal (e.g., `dependabot[bot]`) is preserved inside the JSON payload.
 */
export function sanitizePrincipal(principal: string): string {
  return principal.replace(/\[bot\]/g, "-bot");
}

/** Convert a Date to a quarter token like `2026-q2`. */
export function quarterFor(d: Date): string {
  const year = d.getUTCFullYear();
  const q = Math.floor(d.getUTCMonth() / 3) + 1;
  return `${year}-q${q}`;
}

/** Deterministic R2 key for an allowlist-bypass canonical record. */
export function bypassRecordKey(principal: string, quarter: string): string {
  return `allowlist/${sanitizePrincipal(principal)}/${quarter}.json`;
}

export interface BypassRecord {
  schema_version: typeof SCHEMA_VERSION;
  principal: string;
  principal_safe: string;
  db_id: number;
  quarter: string;
  first_seen_at: string;
  first_pr: number;
  allowlist_source: "cla.yml#with.allowlist";
}

/**
 * Build the per-quarter canonical bypass record. Defense-in-depth: throws if
 * caller passes DB-id 41898282 (github-actions[bot]). The sidecar should call
 * isAllowlistBypass() first; this throw is a guard against callers that skip
 * the upstream filter.
 */
export function buildBypassRecord(opts: {
  principal: string;
  dbId: number;
  now: Date;
  firstPr: number;
}): BypassRecord {
  if (opts.dbId === GITHUB_ACTIONS_BOT_DB_ID) {
    throw new Error(
      `refusing to build bypass record for github-actions[bot] (DB-id ${GITHUB_ACTIONS_BOT_DB_ID}); ` +
        `the upstream CLA action filters this actor before the allowlist check fires (learning #2)`,
    );
  }
  return {
    schema_version: SCHEMA_VERSION,
    principal: opts.principal,
    principal_safe: sanitizePrincipal(opts.principal),
    db_id: opts.dbId,
    quarter: quarterFor(opts.now),
    first_seen_at: opts.now.toISOString(),
    first_pr: opts.firstPr,
    allowlist_source: "cla.yml#with.allowlist",
  };
}
