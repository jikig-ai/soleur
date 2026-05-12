// DSAR export worker — phase 2 skeleton.
//
// feat-dsar-art15-export-endpoint (issue #3637, plan rev-2). This phase
// lands the cross-tenant invariant primitives that EVERY downstream
// piece of the worker depends on:
//
//   - `CrossTenantViolation`  — the error type raised on any drift
//     between an expected owner and a row's owner.
//   - `assertReadScope`       — defense-in-depth invariant invoked on
//     every result set the worker reads. Per plan rev-2 AC12 / AC15 /
//     FR9 + the silent-RLS learning
//     `2026-04-12-silent-rls-failures-in-team-names.md`. Paired with
//     the file-parse lint `dsar-worker-per-row-where.test.ts` (AC30)
//     which proves the per-row WHERE clause is present at every call
//     site — `assertReadScope` is the runtime invariant that fires if
//     a refactor ever bypasses the lint.
//
// Phase 5 will land the full worker logic (enqueueExport, runExport,
// startDsarExportReaper, allowlist enumerator, archive pipe, manifest
// writer, per-file SHA-256, `O_NOFOLLOW + fstat`, AbortController
// timeout) in this same module per plan rev-2 C2 (single-module
// consolidation).

import { mirrorCrossTenantViolation } from "./observability";

// ---------------------------------------------------------------------------
// CrossTenantViolation — the load-bearing error type.
// ---------------------------------------------------------------------------

export class CrossTenantViolation extends Error {
  readonly name = "CrossTenantViolation";
  readonly tableName: string;
  readonly expectedUserId: string;
  readonly offendingUserId: string | null;

  constructor(
    tableName: string,
    expectedUserId: string,
    offendingUserId: string | null,
  ) {
    super(
      `Cross-tenant violation in table "${tableName}": ` +
        `row owned by ${offendingUserId ?? "(no owner_id field)"} ` +
        `appeared in a read scoped to ${expectedUserId}`,
    );
    this.tableName = tableName;
    this.expectedUserId = expectedUserId;
    this.offendingUserId = offendingUserId;
  }
}

// ---------------------------------------------------------------------------
// assertReadScope — runtime invariant for every worker read.
//
// Empty input is intentionally ALLOWED (returns []). An empty array is
// ambiguous between "RLS denied every row" and "user has no rows in
// this table" — the worker disambiguates via a separate service-role
// re-check inside its allowlist enumerator. This helper is a pure
// invariant on the rows it was handed, not a silent-RLS detector.
//
// `ownerField` defaults to "owner_id"; some tables (e.g.,
// `conversations`) use "user_id". Caller passes the table-specific
// field name when the convention differs.
// ---------------------------------------------------------------------------

export interface AssertReadScopeOptions {
  ownerField?: string;
}

export function assertReadScope<T extends Record<string, unknown>>(
  rows: T[],
  expectedUserId: string,
  tableName: string,
  options: AssertReadScopeOptions = {},
): T[] {
  const ownerField = options.ownerField ?? "owner_id";
  for (const row of rows) {
    const owner = row[ownerField];
    if (typeof owner !== "string" || owner !== expectedUserId) {
      const offending = typeof owner === "string" ? owner : null;
      const err = new CrossTenantViolation(
        tableName,
        expectedUserId,
        offending,
      );
      // Mirror to Sentry P0 BEFORE re-raising so the alert lands even
      // if the caller swallows the throw. The Sentry helper hashes
      // both userIds with the PII salt before logging.
      mirrorCrossTenantViolation(offending, expectedUserId, tableName, err);
      throw err;
    }
  }
  return rows;
}
