// The incident-telemetry sandbox, as a runner-entry side effect (#7853).
//
// PROPERTY. A test-runner process redirects incident telemetry to a scratch root BEFORE running a
// single test, so no suite reached through that runner can append to the operator's real
// `.claude/.rule-incidents.jsonl`.
//
// This is the sibling of `./git-tripwire`, registered at the same five chokepoints, and it is
// deliberately the ONLY containment mechanism. Two alternatives were cut during review. A tripwire
// inside `incidents.sh` refusing to append when the process "looks like a test" would put
// test-awareness into production hook code, where a false positive darkens real operator telemetry.
// A per-call-site sweep has now been applied twice and missed a sibling both times -- partial
// isolation greps identically to full isolation, which is why those gaps survived a static check.
//
// It EXPORTS rather than failing, which is the opposite of the git tripwire's choice, and the
// asymmetry is deliberate: an inherited git-location environment is a broken ENTRY POINT that
// someone must fix, whereas an unset telemetry sink is the DEFAULT everywhere outside a test. There
// is no entry point to name, so there is nothing to fail loudly about -- only a default to set.
//
// What it does NOT do is redirect `CLAUDE_PROJECT_DIR`. An earlier revision of the bash sibling did,
// and the measured harm is recorded in that file's header: pointing it at an empty temp dir made
// `new-scheduled-cron-prefer-inngest.sh` unable to see a file on `origin/main`, flipping an allow
// case to deny. Redirect the telemetry sink, not the repo.

import { mkdtempSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/**
 * Point incident telemetry at a fresh scratch root, unless the caller already chose one.
 *
 * Idempotent and non-destructive: an INCIDENTS_REPO_ROOT already set by a suite, by
 * `test-incident-sandbox.sh`, or by an outer runner wins. Returns the root in force.
 *
 * @throws if a sandbox cannot be created. Refusal is the only safe direction — leaving the variable
 *   unset does not degrade to a lesser sandbox, it restores the operator's real ledger, and an
 *   EMPTY value is indistinguishable from unset to `_incidents_repo_root()` while still reading as
 *   "set" to any static check for the variable's name.
 */
export function ensureIncidentSandbox(): string {
  const existing = process.env.INCIDENTS_REPO_ROOT;
  if (existing !== undefined && existing !== "" && existing.startsWith("/")) {
    return existing;
  }

  let root: string;
  try {
    root = mkdtempSync(join(tmpdir(), "soleur-inc-"));
  } catch (cause) {
    throw new Error(
      "incident-sandbox: could not create a telemetry sandbox. Refusing to continue: an unset " +
        "INCIDENTS_REPO_ROOT points test telemetry at the operator's real " +
        `.claude/.rule-incidents.jsonl. Check free space on ${tmpdir()}.`,
      { cause },
    );
  }
  if (!root || !root.startsWith("/")) {
    throw new Error(`incident-sandbox: refusing a non-absolute sandbox path ${JSON.stringify(root)}`);
  }
  // Create the `.claude/` parent rather than relying on the emitter to do it, matching the bash
  // sibling so both spellings leave the same shape on disk.
  mkdirSync(join(root, ".claude"), { recursive: true });

  process.env.INCIDENTS_REPO_ROOT = root;
  // Exported a SECOND time under a name a suite may read to find the rows its own emitter wrote,
  // without knowing this module's internals. That is what keeps a suite asserting on emitted
  // telemetry a two-line change rather than a redesign.
  process.env.SOLEUR_TEST_INCIDENT_ROOT = root;
  return root;
}
