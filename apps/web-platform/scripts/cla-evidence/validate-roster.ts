// CLI: validate a Corporate CLA roster file, and enforce contribution-triggered
// entry against the Individual CLA signature ledger.
//
//   tsx validate-roster.ts <roster.json> [<ledger.json>]
//
// With no ledger argument the ledger is read from
// `origin/cla-signatures:signatures/cla.json`. Both the write path
// (ccla-add.sh, before it opens a PR) and an operator checking by hand call
// this, so there is ONE validation implementation rather than a shell
// reimplementation that drifts from the schema it claims to enforce.
//
// Exit codes:
//   0 — valid, and every account has signed the ICLA
//   3 — schema violation (SchemaVersionMismatchError; mirrors the evidence-record contract)
//   4 — contribution-triggered entry violation
//   64 — usage error
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { SchemaVersionMismatchError, validateRosterRecord } from "./schema";
import {
  ContributionTriggeredEntryError,
  assertContributionTriggeredEntry,
  type SignatureLedger,
} from "./roster-entry-gate";

function main(): void {
  const [rosterPath, ledgerPath] = process.argv.slice(2);
  if (!rosterPath) {
    process.stderr.write("usage: validate-roster.ts <roster.json> [<ledger.json>]\n");
    process.exit(64);
  }

  const roster = validateRosterRecord(JSON.parse(readFileSync(rosterPath, "utf8")));

  const ledgerRaw = ledgerPath
    ? readFileSync(ledgerPath, "utf8")
    : execFileSync("git", ["show", "origin/cla-signatures:signatures/cla.json"], { encoding: "utf8" });
  const ledger = JSON.parse(ledgerRaw) as SignatureLedger;

  const checked = assertContributionTriggeredEntry(roster, ledger);
  process.stdout.write(
    `roster OK: ${roster.organizations.length} organisation(s), ${checked} account(s) cross-checked against the ICLA ledger\n`,
  );
}

try {
  main();
} catch (e) {
  if (e instanceof SchemaVersionMismatchError) {
    process.stderr.write(`::error::${e.message}\n`);
    process.exit(e.exitCode);
  }
  if (e instanceof ContributionTriggeredEntryError) {
    process.stderr.write(`::error::${e.message}\n`);
    process.exit(e.exitCode);
  }
  process.stderr.write(`::error::${e instanceof Error ? e.message : String(e)}\n`);
  process.exit(1);
}
