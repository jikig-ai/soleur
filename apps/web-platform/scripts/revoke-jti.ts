#!/usr/bin/env bun
// scripts/revoke-jti.ts
// Operator CLI to revoke a runtime JWT by its jti claim. Writes a row to
// public.denied_jti via the SECURITY DEFINER `revoke_jti` RPC (migration
// 068). The RPC is service-role-only; this script consumes
// SUPABASE_SERVICE_ROLE_KEY via createServiceClient() (Doppler-bound at
// invocation time). The denied_jti row IS the audit artifact per Article
// 30 PA1 §(g)(10); the existing tenant.ts mirrorWithDebounce
// ("is_jti_denied.deny") fires when the deny-list HIT happens at runtime.
//
// Usage:
//   doppler run -p soleur -c dev -- bun run apps/web-platform/scripts/revoke-jti.ts \
//     --jti <uuid> --founder-id <uuid> --reason "<text>" [--yes]
//
//   doppler run -p soleur -c prd_runtime -- bun run apps/web-platform/scripts/revoke-jti.ts \
//     --jti <uuid> --founder-id <uuid> --reason "<text>" [--yes]
//
// Print the resolved Supabase URL BEFORE the write — operator dev/prd
// visibility per hr-dev-prd-distinct-supabase-projects.

import { createInterface } from "node:readline/promises";
import { createServiceClient } from "@/lib/supabase/service";
import { createChildLogger } from "@/server/logger";

const log = createChildLogger("revoke-jti");

interface ParsedArgs {
  jti: string;
  founderId: string;
  reason: string;
  yes: boolean;
}

function parseArgs(argv: string[]): ParsedArgs {
  const get = (flag: string): string | undefined => {
    const idx = argv.indexOf(flag);
    return idx >= 0 && idx + 1 < argv.length ? argv[idx + 1] : undefined;
  };
  const required = (flag: string): string => {
    const v = get(flag);
    if (!v) {
      process.stderr.write(`::error::missing required flag ${flag}\n`);
      process.exit(2);
    }
    return v;
  };
  return {
    jti: required("--jti"),
    founderId: required("--founder-id"),
    reason: required("--reason"),
    yes: argv.includes("--yes"),
  };
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function confirm(summary: string): Promise<boolean> {
  process.stderr.write(summary + "\n");
  const rl = createInterface({ input: process.stdin, output: process.stderr });
  try {
    const answer = (await rl.question("Confirm revoke? [y/N]: ")).trim().toLowerCase();
    return answer === "y" || answer === "yes";
  } finally {
    rl.close();
  }
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));

  // UUID-shape gate before any DB write — avoids 22P02 invalid_text_representation
  // emitting from the RPC body's UUID-cast and lets the operator see the
  // typo cleanly.
  if (!UUID_RE.test(args.jti)) {
    process.stderr.write(`::error::--jti must be UUID; got "${args.jti}"\n`);
    process.exit(2);
  }
  if (!UUID_RE.test(args.founderId)) {
    process.stderr.write(`::error::--founder-id must be UUID; got "${args.founderId}"\n`);
    process.exit(2);
  }

  const supabase = createServiceClient();
  const supabaseUrl = process.env.SUPABASE_URL ?? "<not set>";
  // dev/prd visibility per hr-dev-prd-distinct-supabase-projects.
  // Operator-protection signal → stdout (not stderr) so the agent runtime
  // sees it.
  process.stdout.write(`[revoke-jti] target Supabase: ${supabaseUrl}\n`);

  const summary = [
    "Revoking:",
    `  jti:        ${args.jti}`,
    `  founder:    ${args.founderId}`,
    `  reason:     ${args.reason}`,
    `  target:     ${supabaseUrl}`,
    "",
  ].join("\n");

  if (!args.yes) {
    const ok = await confirm(summary);
    if (!ok) {
      process.stderr.write("aborted\n");
      process.exit(1);
    }
  } else {
    process.stderr.write(summary);
  }

  log.info(
    { jti: args.jti, founderId: args.founderId, reason: args.reason },
    "revoke-jti: invoking revoke_jti",
  );

  const { error } = await supabase.rpc("revoke_jti", {
    p_jti: args.jti,
    p_founder_id: args.founderId,
    p_reason: args.reason,
  });
  if (error) {
    process.stderr.write(`::error::revoke_jti failed: ${error.code ?? ""} ${error.message}\n`);
    process.exit(1);
  }

  // Re-read for founder_id-mismatch sanity (per Observability §failure_modes).
  const { data: row, error: readErr } = await supabase
    .from("denied_jti")
    .select("jti, founder_id, denied_at, reason")
    .eq("jti", args.jti)
    .maybeSingle();
  if (readErr || !row || row.founder_id !== args.founderId) {
    process.stderr.write(`::error::re-read mismatch: ${JSON.stringify(row)} readErr=${readErr?.message ?? "none"}\n`);
    process.exit(1);
  }

  process.stdout.write(`revoke_success: jti=${args.jti} founder=${args.founderId}\n`);
}

main().catch((err) => {
  process.stderr.write(`::error::revoke-jti: ${err instanceof Error ? err.message : String(err)}\n`);
  process.exit(1);
});
