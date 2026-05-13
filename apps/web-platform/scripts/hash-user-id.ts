#!/usr/bin/env bun
/**
 * Compute `hashUserId(<uuid>)` from a Doppler-resident SENTRY_USERID_PEPPER
 * so support operators can locate pseudonymous pino log lines from a raw user
 * UUID. Reuses the canonical primitive at `../server/observability.ts:36`
 * (single source of truth — same HMAC-SHA256 + pepper the pino
 * `formatters.log()` rename hook and `reportSilentFallback` helpers call).
 *
 * Operator-local invocation (NOT inside the prod container — `tsx`/`bun`
 * runtime is in devDependencies; the operator already has Bun locally per
 * the existing TS-scripts pattern in this directory):
 *
 *   cd apps/web-platform
 *   doppler run -p soleur -c prd -- npm run --silent hash-user-id -- <uuid>
 *
 * Note: the invocation cd's into `apps/web-platform/` first (matching the
 * sibling `verify-stripe-prices.ts` pattern). The repo root's package.json
 * does not declare `workspaces:`, so `npm run -w apps/web-platform ...`
 * from the root FAILS with "No workspaces found" — do not use that form.
 * The explicit `--` separator between the npm-script name and the
 * positional argument is load-bearing — without it, npm parses `<uuid>` as
 * a candidate flag rather than argv to the bun script. `--silent` is bound
 * to `npm run` and suppresses the wrapper banner so the captured value is
 * pure 64-hex.
 *
 * Hardened operator pattern (see `recover-userid-from-pino-stdout.md`):
 *
 *   cd apps/web-platform
 *   HASH=$(doppler run -p soleur -c prd -- npm run --silent hash-user-id -- "$UUID")
 *   ssh root@<prod-ip> "docker logs soleur-web-platform 2>&1 \
 *     | grep -F 'userIdHash' | grep -F \"$HASH\""
 *
 * Exit codes:
 *   0  — hash printed to stdout (64 hex chars + newline)
 *   1  — usage error (missing argv) or pepper not set
 *
 * Sharp-edge sanity guard: asserts the output is exactly 64 hex chars before
 * printing. If a future change to `hashUserId` widens the return contract
 * (e.g., adds a prefix, switches to base64), the guard fires here at the
 * operator boundary rather than misleading a support investigation.
 *
 * Plan: knowledge-base/project/plans/2026-05-13-feat-ops-hash-user-id-cli-pa8-retention-pin-plan.md
 */

import { hashUserId } from "../server/observability";

function fail(message: string): never {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

const userId = process.argv[2];
if (!userId) {
  fail(
    "usage: bun scripts/hash-user-id.ts <uuid>\n" +
      "       (typical invocation, from apps/web-platform/: doppler run -p soleur -c prd -- npm run --silent hash-user-id -- <uuid>)",
  );
}

if (!process.env.SENTRY_USERID_PEPPER) {
  fail(
    "pepper not set: SENTRY_USERID_PEPPER env var required.\n" +
      "From apps/web-platform/, run `doppler run -p soleur -c prd -- npm run --silent hash-user-id -- <uuid>` — never `export SENTRY_USERID_PEPPER=...` outside doppler run.",
  );
}

const hash = hashUserId(userId);
if (!/^[0-9a-f]{64}$/.test(hash)) {
  fail(
    `hash-user-id: contract drift detected — hashUserId returned non-64-hex output (got length ${hash.length}). Investigate apps/web-platform/server/observability.ts before relying on this operator boundary.`,
  );
}

console.log(hash);
