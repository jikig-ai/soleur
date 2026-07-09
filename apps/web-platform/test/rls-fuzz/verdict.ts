// Classify the outcome of a cross-tenant attack query into an isolation verdict.
//
// The load-bearing distinction (AC2): a *write* denied by RLS raises SQLSTATE
// 42501 ("new row violates row-level security policy"). A write that fails for
// ANY OTHER reason (NOT NULL 23502, FK 23503, CHECK 23514, undefined column
// 42703, …) did NOT exercise RLS — it is a TEST ERROR (the query shape is wrong
// for this table), NEVER a pass. Scoring a constraint failure as "denied" is the
// single most likely false-green in the write matrix.

/** SQLSTATE for a row-level-security policy violation. */
export const RLS_VIOLATION_SQLSTATE = "42501";

export type Verdict =
  | { kind: "denied" } // RLS blocked it — the desired outcome
  | { kind: "leaked" } // cross-tenant access SUCCEEDED — a real isolation break
  | { kind: "test-error"; sqlstate: string }; // wrong query shape / constraint — inconclusive, must fail the case

/** Classify a write (INSERT/UPDATE/DELETE) attempt from its caught error (null = the write succeeded). */
export function classifyWriteOutcome(err: { code?: string } | null | undefined): Verdict {
  if (err == null) return { kind: "leaked" }; // no error → the cross-tenant write went through
  if (err.code === RLS_VIOLATION_SQLSTATE) return { kind: "denied" };
  return { kind: "test-error", sqlstate: err.code ?? "unknown" };
}

/** Classify a SELECT attempt from the row count of the target tenant's seeded row (RLS denies by filtering, not error). */
export function classifySelectOutcome(rowCount: number): Verdict {
  return rowCount === 0 ? { kind: "denied" } : { kind: "leaked" };
}

/** A verdict is a PASS for an isolation assertion only when the access was denied. */
export function isPass(v: Verdict): boolean {
  return v.kind === "denied";
}
