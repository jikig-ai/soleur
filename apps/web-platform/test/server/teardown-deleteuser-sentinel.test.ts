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
 * Property enforced: every `test/**` file whose comment-stripped source
 * matches a deleteUser call-shape is either CANONICAL (the parity-guarded
 * helper), MANUAL_TEARDOWN_ALLOWLIST (reviewed per-file, per-call-count
 * pinned), or KNOWN_LEGACY_CARRIERS (the standing drain mechanism —
 * emptied by #10096; a future reviewed deferral may re-add entries, which
 * can then only shrink). A carrier appearing ANYWHERE else — a new suite,
 * a new subdirectory, an evading call form —
 * is RED. The census is recursive over `.ts`/`.tsx`/`.mts`/`.cts` under
 * `test/` (symlinked files AND directories followed): `test/rls-fuzz/` and
 * any future `test/<subdir>/` cannot silently grow the defect.
 *
 * Documented residuals (accepted, reviewed): comments are stripped via the
 * shared TS-parser helper (helpers/strip-comments.ts) but STRING literals
 * are not — a test name like `it("auth.admin.deleteUser(id) ...")` or a
 * grep-shape constant counts as a carrier (fails loud, the safe direction;
 * avoid verbatim call shapes in strings — write `admin.deleteUser` without
 * the trailing `(`). Evasions needing more than a source grep — method
 * extraction to a bare identifier, `import`-aliased wrappers, computed
 * member names, `deleteUser (` with a space — are out of this guard's
 * threat model (accidental regression, not adversarial authorship).
 */

import { readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, test } from "vitest";
import { stripComments } from "../helpers/strip-comments";
import { SYNTHETIC_PREFIXES } from "../helpers/tenant-isolation-teardown";

const TEST_ROOT = join(__dirname, "..");

/** The single canonical teardown chokepoint — never an allowlist entry. */
const CANONICAL_HELPERS = new Set([
  "test/helpers/tenant-isolation-teardown.ts",
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

/**
 * Drain list — EMPTY since #10096 drained all 15 `test/server/**` (and
 * nested `scope-grants/`) carriers through `tearDownTenantUser`. Kept as
 * the standing mechanism for any future reviewed deferral: enumerating a
 * carrier here turns the deferral into a ratchet — no NEW carrier can
 * appear anywhere under `test/` without tripping this guard, and each
 * drained file must be removed from this list in the same commit
 * (stale-entry check below). Entries may only be added as an explicit,
 * issue-tracked deferral; the set can then only shrink.
 */
const KNOWN_LEGACY_CARRIERS = new Set<string>([]);

/**
 * Exact carrier-form call counts per enumerated file — the union of every
 * CALL_RES shape, so a non-canonical call added inside an allowlisted file
 * also trips the pin (canonical-form-only counting would miss it).
 */
const EXPECTED_CALL_COUNTS: Readonly<Record<string, number>> = {
  "test/helpers/tenant-isolation-teardown.ts": 1,
  "test/concurrency-acquire-slot-workspace-id.integration.test.ts": 1,
  "test/conversation-archive-release-slot.integration.test.ts": 1,
  "test/workspace-binding-restart-survival.integration.test.ts": 1,
  "test/worktree-write-lease.integration.test.ts": 1,
  "test/mu1.integration.test.ts": 1,
};

/**
 * Call shapes that count as carriers (applied to comment-stripped source —
 * a docblock quoting `admin.deleteUser(id)` is NOT a carrier; the stale-
 * entry check would otherwise be satisfied by a comment after the real
 * call is deleted):
 *   `.deleteUser(`        — member access incl `?.` (no spacing drift:
 *                          real call sites never write `f (x)` — prose
 *                          test names like `auth.admin.deleteUser (FK…`
 *                          must NOT match)
 *   `["deleteUser"]`      — bracket access
 *   `const { deleteUser } = …admin` — destructured alias from an admin
 *                          object (RHS must name `admin` so mock
 *                          destructures like `{ service, deleteUser } =
 *                          mockService()` do not false-positive)
 *   `deleteUser.call/apply/bind` — reflective invocation
 */
const CALL_RES = [
  /\.deleteUser\(/,
  /\.deleteUser\?\.\(/,
  /\[\s*["'`]deleteUser["'`]\s*\]/,
  // Destructured alias from an admin-ish source (admin, authAdmin,
  // adminSvc, getAdmin() — any RHS token containing admin/Admin) so mock
  // destructures like `{ service, deleteUser } = mockService()` don't
  // false-positive.
  /\b(?:const|let|var)\s*\{[^}]*\bdeleteUser\b[^}]*\}\s*=\s*[^;\n]*\w*[Aa]dmin\w*/,
  /\bdeleteUser\s*\.\s*(?:call|apply|bind)\s*\(/,
];

const SOURCE_EXT_RE = /\.[cm]?[jt]sx?$/;

/** Recursively census every source file under `test/` for call shapes. */
function deleteUserCarriers(): { carriers: string[]; byRel: Map<string, string> } {
  const byRel = new Map<string, string>();
  const visitedDirs = new Set<string>();
  const visit = (full: string): void => {
    let st: ReturnType<typeof statSync>;
    try {
      st = statSync(full); // follows symlinks
    } catch {
      return; // dangling link — nothing to census
    }
    if (st.isDirectory()) {
      const real = realpathSync(full); // cycle guard for symlinked dirs
      if (visitedDirs.has(real)) return;
      visitedDirs.add(real);
      for (const e of readdirSync(full, { withFileTypes: true })) {
        visit(join(full, e.name));
      }
      return;
    }
    if (st.isFile() && SOURCE_EXT_RE.test(full)) {
      byRel.set(
        `test/${relative(TEST_ROOT, full)}`,
        stripComments(readFileSync(full, "utf8"), full),
      );
    }
  };
  visit(TEST_ROOT);
  const carriers = [...byRel.entries()]
    .filter(([, stripped]) => CALL_RES.some((re) => re.test(stripped)))
    .map(([rel]) => rel)
    .sort();
  return { carriers, byRel };
}

describe("teardown deleteUser sentinel (recurrence guard, #9994)", () => {
  const { carriers, byRel } = deleteUserCarriers();
  const ENUMERATED = new Set([
    ...CANONICAL_HELPERS,
    ...MANUAL_TEARDOWN_ALLOWLIST,
    ...KNOWN_LEGACY_CARRIERS,
  ]);

  test("anti-vacuity floor: the census finds every enumerated carrier", () => {
    // A call-shape drift (rename, spacing change) must be RED, never
    // green-over-fewer-files. Green requires carriers == ENUMERATED
    // exactly (floor + offender + stale triad below).
    expect(carriers.length).toBeGreaterThanOrEqual(ENUMERATED.size);
  });

  test("every admin.deleteUser carrier is enumerated (no new carrier anywhere)", () => {
    const offenders = carriers.filter((rel) => !ENUMERATED.has(rel));
    expect(
      offenders,
      `file(s) calling raw admin.deleteUser outside the canonical ` +
        `teardown helper and the reviewed sets — route teardown through ` +
        `test/helpers/tenant-isolation-teardown.ts (tearDownTenantUser). ` +
        `If a manual-FK-reverse path is genuinely required, add a reviewed ` +
        `entry to MANUAL_TEARDOWN_ALLOWLIST; a legacy drain belongs in ` +
        `KNOWN_LEGACY_CARRIERS only as an issue-tracked deferral ` +
        `(the #10096 set is drained):\n  ${offenders.join("\n  ")}`,
    ).toEqual([]);
  });

  test("no stale entries: every enumerated file is still a carrier", () => {
    const stale = [...ENUMERATED].filter((rel) => !carriers.includes(rel));
    expect(
      stale,
      `enumerated files that no longer carry a deleteUser call — drop ` +
        `the entry so the sets stay a precise audit (drained entries ` +
        `leave the sets in the same commit as the migration):\n  ${stale.join("\n  ")}`,
    ).toEqual([]);
  });

  test("per-file call counts are pinned (an allowlisted file may not gain calls)", () => {
    const drift = [...ENUMERATED].flatMap((rel) => {
      const stripped = byRel.get(rel) ?? "";
      const count = CALL_RES.reduce(
        (n, re) =>
          n + (stripped.match(new RegExp(re.source, "g")) ?? []).length,
        0,
      );
      return count === EXPECTED_CALL_COUNTS[rel]
        ? []
        : [
            `${rel}: ${count} (expected ${EXPECTED_CALL_COUNTS[rel] ?? "no entry"})`,
          ];
    });
    expect(
      drift,
      `files whose deleteUser call-site count changed — a new call inside ` +
        `an enumerated file is a review-required act ` +
        `(update EXPECTED_CALL_COUNTS in the same commit):\n  ${drift.join("\n  ")}`,
    ).toEqual([]);
  });

  test("EXPECTED_CALL_COUNTS keys are exactly the enumerated set", () => {
    // Two-directional: a set entry without a count key AND a count key
    // orphaned by a drained/removed set entry are both RED.
    expect([...Object.keys(EXPECTED_CALL_COUNTS)].sort()).toEqual(
      [...ENUMERATED].sort(),
    );
  });

  test("every SYNTHETIC_PREFIXES entry is claimed by a real suite file", () => {
    // Stale-prefix garbage collection: a renamed/deleted suite must not
    // leave its prefix allowlisted forever (boundary-widening drift).
    // The claimant must be a file OTHER than the two prefix-defining
    // files — the helper's own declaration and its unit test's literal
    // copy would self-claim every prefix forever.
    const DEFINITION_FILES = new Set([
      "test/helpers/tenant-isolation-teardown.ts",
      "test/helpers/tenant-isolation-teardown.test.ts",
    ]);
    const claimantSources = [...byRel.entries()]
      .filter(([rel]) => !DEFINITION_FILES.has(rel))
      .map(([, src]) => src)
      .join("\n");
    const unclaimed = SYNTHETIC_PREFIXES.filter(
      (p) => !claimantSources.includes(p),
    );
    expect(
      unclaimed,
      `helper prefixes no suite file claims — drop them from ` +
        `SYNTHETIC_PREFIXES (a stale prefix widens the teardown boundary):\n  ${unclaimed.join("\n  ")}`,
    ).toEqual([]);
  });
});
