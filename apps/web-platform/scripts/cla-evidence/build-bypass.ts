// Builds the per-quarter allowlist-bypass canonical record JSON payload
// from workflow env vars. Invoked by .github/workflows/cla-evidence.yml on
// pull_request_target events.
//
// Emits empty stdout (length 0) when the actor is NOT an allowlist bypass —
// the workflow then skips the upload step. Otherwise emits the JSON payload.
//
// Reads `.github/workflows/cla.yml` at HEAD to keep the allowlist source-
// of-truth in sync with the upstream filter at workflow run-time.

import { readFileSync } from "node:fs";
import { isAllowlistBypass, parseAllowlistLine } from "./allowlist";
import { buildBypassRecord } from "./allowlist-bypass";

const env = (k: string): string => {
  const v = process.env[k];
  if (!v) {
    process.stderr.write(`::error::env ${k} missing\n`);
    process.exit(1);
  }
  return v;
};

function readAllowlist(): string[] {
  // The read and the exit stay HERE; the expression itself lives in
  // allowlist.ts as the pure `parseAllowlistLine()`, so a guard can drive it
  // against the real tracked workflow (Guard 1 / #7597). The chokepoint stays
  // singular — there is exactly one implementation, and this is its only caller.
  //
  // BASE-REF INVARIANT: cla-evidence.yml checks out `base.sha` and never the PR
  // head, so this cwd-relative read resolves against the BASE tree. That is
  // what stops a contributor authorizing themselves by editing the allowlist in
  // the same pull request the allowlist governs. Do not make this path absolute
  // to the PR head, and do not move the checkout `ref:`.
  const yml = readFileSync(".github/workflows/cla.yml", "utf8");
  const parsed = parseAllowlistLine(yml);
  if (!parsed) {
    process.stderr.write("::error::could not parse `allowlist:` line in cla.yml\n");
    process.exit(1);
  }
  return parsed;
}

function main(): void {
  const login = env("ACTOR_LOGIN");
  const dbId = Number(env("ACTOR_ID"));
  const prNumber = Number(env("PR_NUMBER"));
  const allowlist = readAllowlist();

  if (!isAllowlistBypass(login, dbId, allowlist)) {
    // Empty stdout signals the workflow to skip.
    return;
  }

  const record = buildBypassRecord({
    principal: login,
    dbId,
    now: new Date(),
    firstPr: prNumber,
  });
  process.stdout.write(JSON.stringify(record));
}

try {
  main();
} catch (e) {
  process.stderr.write(`::error::${e instanceof Error ? e.message : String(e)}\n`);
  process.exit(1);
}
