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

const LEDGER_REF = "origin/cla-signatures:signatures/cla.json";

const msg = (e: unknown) => (e instanceof Error ? e.message : String(e));

function fatal(message: string): never {
  process.stderr.write(`::error::${message}\n`);
  process.exit(1);
}

function read(path: string, what: string): string {
  try {
    return readFileSync(path, "utf8");
  } catch (e) {
    fatal(`could not read the ${what} at ${path}: ${msg(e)}`);
  }
}

function showLedgerRef(): string {
  try {
    return execFileSync("git", ["show", LEDGER_REF], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  } catch (e) {
    fatal(
      `could not read ${LEDGER_REF}: ${msg(e)}. That branch is maintained by the upstream CLA action ` +
        "and is absent from a shallow single-branch clone — fetch it with " +
        "`git fetch origin +refs/heads/cla-signatures:refs/remotes/origin/cla-signatures`, " +
        "or pass a ledger path explicitly.",
    );
  }
}

function main(): void {
  const [rosterPath, ledgerPath] = process.argv.slice(2);
  if (!rosterPath) {
    process.stderr.write("usage: validate-roster.ts <roster.json> [<ledger.json>]\n");
    process.exit(64);
  }

  // Five distinct causes used to arrive at the same generic catch arm below —
  // roster unreadable, roster unparseable, ledger unreachable, ledger
  // unreadable, ledger unparseable — all reported as exit 1 with whatever
  // message the underlying library happened to raise. The operator could not
  // tell "I typed the path wrong" from "the signature branch is not fetched".
  // Each one now says which artifact failed and what to do about it.
  let rosterPayload: unknown;
  try {
    rosterPayload = JSON.parse(read(rosterPath, "roster"));
  } catch (e) {
    fatal(`the roster at ${rosterPath} is not valid JSON: ${msg(e)}`);
  }
  const roster = validateRosterRecord(rosterPayload);

  const ledgerRaw = ledgerPath
    ? read(ledgerPath, "ICLA signature ledger")
    : showLedgerRef();
  let ledger: SignatureLedger;
  try {
    ledger = JSON.parse(ledgerRaw) as SignatureLedger;
  } catch (e) {
    fatal(
      `the ICLA signature ledger is not valid JSON (${ledgerPath ?? LEDGER_REF}): ${msg(e)}. ` +
        "The reference set is UNUSABLE — this is not a finding about any account.",
    );
  }

  const checked = assertContributionTriggeredEntry(roster, ledger);
  // stderr: this is a diagnostic, and callers pipe this CLI's stdout.
  process.stderr.write(
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
