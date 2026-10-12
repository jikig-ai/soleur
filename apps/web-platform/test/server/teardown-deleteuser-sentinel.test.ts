/**
 * Recurrence sentinel — no raw `auth.admin.deleteUser` outside canonical
 * teardown helpers and an explicit, reviewed allowlist.
 *
 * Pure source grep (no dev Supabase) — runs in the default ci.yml
 * test-webplat shard, NOT behind an env gate. Third recurrence of this
 * defect class (#4791, #5582, #9994): a suite that calls
 * `service.auth.admin.deleteUser` directly on a user carrying dependent
 * rows deterministically 500s on dev (`workspace_members_user_id_fkey`
 * ON DELETE RESTRICT — every auth user gets a trigger-created solo
 * workspace + owner membership), and `withGoTrueRetry` masks it as a
 * transient retry storm. Suites that ignore the `{ data, error }` result
 * leak the user silently instead.
 *
 * Property: every in-scope file containing the literal call
 * `\.admin\.deleteUser\(` is either a canonical teardown chokepoint
 * (`tearDownTenantUser`, `tearDownSharedWorkspace`) or on the explicit
 * MANUAL_TEARDOWN_ALLOWLIST below — an entry is the review-visible act of
 * declaring "this suite runs deliberate manual FK-reverse teardown".
 *
 * Scope is deliberately `test/*.integration.test.ts` + `test/helpers/*.ts`
 * — the nightly-leg surface where the defect shipped. `test/server/**`
 * carries the same class silently (~16 sites) and is tracked by #10096;
 * including it now would bake a ~20-name allowlist into the guard.
 */

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";

const TEST_ROOT = join(__dirname, "..");

/** The two canonical teardown chokepoints — never allowlist entries. */
const CANONICAL_HELPERS = new Set([
  "test/helpers/tenant-isolation-teardown.ts",
  "test/helpers/workspace-members-fixtures.ts",
]);

/**
 * Suites with deliberate, verified manual FK-reverse teardown: each calls
 * `anonymise_workspace_members` (+ `anonymise_workspace_member_actions`)
 * then explicit `workspaces`/`organizations` deletes before `deleteUser` —
 * a different cleanup semantic from the helper (they also remove
 * solo-workspace/org cruft the helper leaves as NULL-owner rows), and
 * working today. Migration to the helper is allowed future cleanup, not
 * required by this guard.
 *
 * mu1.integration.test.ts is allowlisted provisionally: it uses a
 * different synthetic domain (@soleur-test.invalid) outside the helper's
 * prefix allowlist. Its raw deleteUser hits the same RESTRICT class once
 * its #9995 credential blocker clears — revisit with that issue's owner.
 */
const MANUAL_TEARDOWN_ALLOWLIST = new Set([
  "test/concurrency-acquire-slot-workspace-id.integration.test.ts",
  "test/conversation-archive-release-slot.integration.test.ts",
  "test/workspace-binding-restart-survival.integration.test.ts",
  "test/worktree-write-lease.integration.test.ts",
  "test/mu1.integration.test.ts", // #9995 revisit — different synthetic domain
]);

/** Literal call form only — prose mentions in comments cannot match. */
const CALL_RE = /\.admin\.deleteUser\(/;

function deleteUserCarriers(): string[] {
  const files = readdirSync(TEST_ROOT, { withFileTypes: true })
    .filter((e) => e.isFile() && e.name.endsWith(".integration.test.ts"))
    .map((e) => `test/${e.name}`);
  const helpers = readdirSync(join(TEST_ROOT, "helpers"), {
    withFileTypes: true,
  })
    .filter((e) => e.isFile() && e.name.endsWith(".ts"))
    .map((e) => `test/helpers/${e.name}`);
  return [...files, ...helpers]
    .filter((rel) => CALL_RE.test(readFileSync(join(TEST_ROOT, "..", rel), "utf8")))
    .sort();
}

describe("teardown deleteUser sentinel (recurrence guard, #9994)", () => {
  const carriers = deleteUserCarriers();

  test("anti-vacuity floor: the census finds at least one carrier", () => {
    // A call-expression drift (rename, spacing change) must be RED, never
    // green-over-zero-files. Today: 12 carriers on the scoped surface.
    expect(carriers.length).toBeGreaterThanOrEqual(1);
  });

  test("every admin.deleteUser( carrier is a canonical helper or allowlisted", () => {
    const offenders = carriers.filter(
      (rel) => !CANONICAL_HELPERS.has(rel) && !MANUAL_TEARDOWN_ALLOWLIST.has(rel),
    );
    expect(
      offenders,
      `file(s) calling raw admin.deleteUser outside the canonical teardown ` +
        `helpers and the manual-teardown allowlist — route teardown through ` +
        `test/helpers/tenant-isolation-teardown.ts (tearDownTenantUser), or ` +
        `add a reviewed allowlist entry:\n  ${offenders.join("\n  ")}`,
    ).toEqual([]);
  });

  test("allowlist entries are real carriers (no stale names)", () => {
    const stale = [...MANUAL_TEARDOWN_ALLOWLIST].filter(
      (rel) => !carriers.includes(rel),
    );
    expect(
      stale,
      `allowlist entries that no longer call admin.deleteUser — drop them ` +
        `so the list stays a precise audit of manual teardown:\n  ${stale.join("\n  ")}`,
    ).toEqual([]);
  });
});
