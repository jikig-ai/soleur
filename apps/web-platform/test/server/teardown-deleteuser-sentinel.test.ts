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
 * pinned), or KNOWN_LEGACY_CARRIERS (the #10096 drain set — it can only
 * shrink; every entry names its tracked drain). A carrier appearing
 * ANYWHERE else — a new suite, a new subdirectory, an evading call form —
 * is RED. The census is recursive: `test/rls-fuzz/` and any future
 * `test/<subdir>/` cannot silently grow the defect.
 */

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, test } from "vitest";
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
 * Drain list for #10096 — `test/server/**` (and nested `scope_grants/`)
 * carries the same raw-deleteUser class silently (many in the worst
 * `.catch(() => {})` variant). Enumerating them here turns the deferral
 * into a ratchet: no NEW carrier can appear anywhere under `test/`
 * without tripping this guard, and each drained file must be removed
 * from this list in the same commit (stale-entry check below).
 */
const KNOWN_LEGACY_CARRIERS = new Set([
  "test/server/action-sends-worm.test.ts",
  "test/server/attachment-pipeline.tenant-isolation.test.ts",
  "test/server/cc-dispatcher.tenant-isolation.test.ts",
  "test/server/conversations-tools.tenant-isolation.test.ts",
  "test/server/current-repo-url.tenant-isolation.test.ts",
  "test/server/email-triage-worm.test.ts",
  "test/server/kb-document-resolver.tenant-isolation.test.ts",
  "test/server/kb-route-helpers.tenant-isolation.test.ts",
  "test/server/lookup-conversation-for-path.tenant-isolation.test.ts",
  "test/server/scope-grants/lifecycle.test.ts",
  "test/server/template-authorizations-worm.test.ts",
  "test/server/tenant-jwt-deny.tenant-isolation.test.ts",
  "test/server/workspace-backfill-trigger-parity.test.ts",
  "test/server/workspace-member-revocation.tenant-isolation.test.ts",
  "test/server/ws-handler.tenant-isolation.test.ts",
]);

/** Exact canonical-form call counts per enumerated file (see header note). */
const EXPECTED_CALL_COUNTS: Readonly<Record<string, number>> = {
  "test/helpers/tenant-isolation-teardown.ts": 1,
  "test/concurrency-acquire-slot-workspace-id.integration.test.ts": 1,
  "test/conversation-archive-release-slot.integration.test.ts": 1,
  "test/workspace-binding-restart-survival.integration.test.ts": 1,
  "test/worktree-write-lease.integration.test.ts": 1,
  "test/mu1.integration.test.ts": 1,
  "test/server/action-sends-worm.test.ts": 2,
  "test/server/attachment-pipeline.tenant-isolation.test.ts": 1,
  "test/server/cc-dispatcher.tenant-isolation.test.ts": 1,
  "test/server/conversations-tools.tenant-isolation.test.ts": 1,
  "test/server/current-repo-url.tenant-isolation.test.ts": 1,
  "test/server/email-triage-worm.test.ts": 2,
  "test/server/kb-document-resolver.tenant-isolation.test.ts": 1,
  "test/server/kb-route-helpers.tenant-isolation.test.ts": 1,
  "test/server/lookup-conversation-for-path.tenant-isolation.test.ts": 1,
  "test/server/scope-grants/lifecycle.test.ts": 1,
  "test/server/template-authorizations-worm.test.ts": 1,
  "test/server/tenant-jwt-deny.tenant-isolation.test.ts": 2,
  "test/server/workspace-backfill-trigger-parity.test.ts": 1,
  "test/server/workspace-member-revocation.tenant-isolation.test.ts": 1,
  "test/server/ws-handler.tenant-isolation.test.ts": 1,
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
  /\[\s*["'`]deleteUser["'`]\s*\]/,
  /\b(?:const|let|var)\s*\{[^}\n]*\bdeleteUser\b[^}\n]*\}\s*=\s*[^;\n]*\badmin\b/,
  /\bdeleteUser\s*\.\s*(?:call|apply|bind)\s*\(/,
];

/** Count of the canonical `\.admin\.deleteUser\(` form — per-file pin basis. */
const CANONICAL_CALL_RE = /\.admin\.deleteUser\s*\(/g;

/**
 * Strip comments conservatively: drop C-style block comments, whole-line `//`
 * comments, and trailing `//` to EOL — except when the `//` is preceded by
 * `:` (URL protocols inside string literals). A contrived evasion would
 * need a call form inside a `//`-in-string on the same line — documented
 * accepted residual.
 */
function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((line) => {
      if (/^\s*(\/\/|\*)/.test(line)) return "";
      const idx = line.indexOf("//");
      if (idx > 0 && line[idx - 1] !== ":") return line.slice(0, idx);
      return line;
    })
    .join("\n");
}

/** Recursively census every `.ts` file under `test/` for call shapes. */
function deleteUserCarriers(): { carriers: string[]; byRel: Map<string, string> } {
  const byRel = new Map<string, string>();
  const walk = (dir: string): void => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, e.name);
      if (e.isSymbolicLink()) {
        // Follow links — a symlinked suite must not escape the census.
        if (statSync(full).isFile() && e.name.endsWith(".ts")) {
          byRel.set(
            `test/${relative(TEST_ROOT, full)}`,
            stripComments(readFileSync(full, "utf8")),
          );
        }
        continue;
      }
      if (e.isDirectory()) {
        walk(full);
        continue;
      }
      if (e.isFile() && e.name.endsWith(".ts")) {
        byRel.set(
          `test/${relative(TEST_ROOT, full)}`,
          stripComments(readFileSync(full, "utf8")),
        );
      }
    }
  };
  walk(TEST_ROOT);
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
    // green-over-fewer-files. Today: 23 enumerated carriers across test/**.
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
        `entry to MANUAL_TEARDOWN_ALLOWLIST; test/server/** carriers are ` +
        `tracked for drain by #10096:\n  ${offenders.join("\n  ")}`,
    ).toEqual([]);
  });

  test("no stale entries: every enumerated file is still a carrier", () => {
    const stale = [...ENUMERATED].filter((rel) => !carriers.includes(rel));
    expect(
      stale,
      `enumerated files that no longer carry a deleteUser call — drop ` +
        `the entry so the sets stay a precise audit (legacy drains belong ` +
        `in #10096's commit):\n  ${stale.join("\n  ")}`,
    ).toEqual([]);
  });

  test("per-file call counts are pinned (an allowlisted file may not gain calls)", () => {
    const drift = [...ENUMERATED].flatMap((rel) => {
      const stripped = byRel.get(rel) ?? "";
      const count = (stripped.match(CANONICAL_CALL_RE) ?? []).length;
      return count === EXPECTED_CALL_COUNTS[rel] ? [] : [`${rel}: ${count}`];
    });
    expect(
      drift,
      `files whose canonical-form deleteUser call count changed — a ` +
        `new call inside an enumerated file is a review-required act ` +
        `(update EXPECTED_CALL_COUNTS in the same commit):\n  ${drift.join("\n  ")}`,
    ).toEqual([]);
  });

  test("every SYNTHETIC_PREFIXES entry is claimed by at least one in-scope file", () => {
    // Stale-prefix garbage collection: a renamed/deleted suite must not
    // leave its prefix allowlisted forever (boundary-widening drift).
    const allSources = [...byRel.values()].join("\n");
    const unclaimed = SYNTHETIC_PREFIXES.filter((p) => !allSources.includes(p));
    expect(
      unclaimed,
      `helper prefixes no test file claims — drop them from ` +
        `SYNTHETIC_PREFIXES (a stale prefix widens the teardown boundary):\n  ${unclaimed.join("\n  ")}`,
    ).toEqual([]);
  });
});
