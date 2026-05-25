#!/usr/bin/env bun
// scripts/byok-revoke.ts
// BYOK Delegations PR-A (#4232). Admin CLI to revoke a byok_delegations
// row. Resolves the actor email, verifies the delegation exists,
// prints a confirmation summary, then calls the consolidated
// `revoke_byok_delegation` RPC. CLI is constrained to `admin_revoke`
// reason; `member_departed` + `art_17_anonymise` are reserved for the
// trigger and Art. 17 cascade paths.
//
// Usage:
//   doppler run -p soleur -c dev -- bun run byok-revoke -- \
//     --actor jean@jikigai.com --id <uuid> \
//     [--reason admin_revoke] [--yes]

import { createInterface } from "node:readline/promises";
import { createServiceClient } from "@/lib/supabase/service";
import { createChildLogger } from "@/server/logger";

const log = createChildLogger("byok-revoke");

interface ParsedArgs {
  actor: string;
  id: string;
  reason: "grantor_revoke" | "grantee_decline" | "admin_revoke";
  yes: boolean;
}

const ALLOWED_REASONS = new Set([
  "grantor_revoke",
  "grantee_decline",
  "admin_revoke",
]);

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
  const reason = (get("--reason") ?? "admin_revoke") as ParsedArgs["reason"];
  if (!ALLOWED_REASONS.has(reason)) {
    process.stderr.write(
      `::error::--reason must be one of ${[...ALLOWED_REASONS].join(", ")}; got "${reason}"\n`,
    );
    process.exit(2);
  }
  return {
    actor: required("--actor"),
    id: required("--id"),
    reason,
    yes: argv.includes("--yes"),
  };
}

async function resolveEmailToUserId(
  supabase: ReturnType<typeof createServiceClient>,
  email: string,
): Promise<string> {
  const want = email.toLowerCase();
  let page = 1;
  while (page < 50) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw new Error(`auth.admin.listUsers page ${page} failed: ${error.message}`);
    if (!data.users.length) break;
    for (const u of data.users) {
      if (u.email?.toLowerCase() === want) return u.id;
    }
    if (data.users.length < 200) break;
    page += 1;
  }
  throw new Error(`unknown actor email: ${email}`);
}

interface DelegationRow {
  id: string;
  grantor_user_id: string | null;
  grantee_user_id: string | null;
  workspace_id: string | null;
  revoked_at: string | null;
  expires_at: string | null;
}

async function loadDelegation(
  supabase: ReturnType<typeof createServiceClient>,
  id: string,
): Promise<DelegationRow> {
  const { data, error } = await supabase
    .from("byok_delegations")
    .select("id, grantor_user_id, grantee_user_id, workspace_id, revoked_at, expires_at")
    .eq("id", id)
    .maybeSingle<DelegationRow>();
  if (error) throw new Error(`load delegation failed: ${error.message}`);
  if (!data) throw new Error(`delegation ${id} not found`);
  return data;
}

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
  const supabase = createServiceClient();

  const actorId = await resolveEmailToUserId(supabase, args.actor);
  const row = await loadDelegation(supabase, args.id);

  if (row.revoked_at !== null) {
    process.stderr.write(`::error::delegation ${args.id} already revoked at ${row.revoked_at}\n`);
    process.exit(1);
  }

  const summary = [
    "Revoking:",
    `  delegation: ${row.id}`,
    `  grantor:    ${row.grantor_user_id ?? "<anonymised>"}`,
    `  grantee:    ${row.grantee_user_id ?? "<anonymised>"}`,
    `  workspace:  ${row.workspace_id ?? "<anonymised>"}`,
    `  expires:    ${row.expires_at ?? "never"}`,
    `  actor:      ${args.actor} (${actorId})`,
    `  reason:     ${args.reason}`,
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
    { actorId, delegationId: args.id, reason: args.reason },
    "byok-revoke: invoking revoke_byok_delegation",
  );

  const { error } = await supabase.rpc("revoke_byok_delegation", {
    p_delegation_id: args.id,
    p_actor_user_id: actorId,
    p_reason: args.reason,
  });

  if (error) {
    process.stderr.write(`::error::revoke_byok_delegation failed: ${error.message}\n`);
    process.exit(1);
  }

  process.stdout.write(`revoke_success: ${args.id}\n`);
}

main().catch((err) => {
  process.stderr.write(`::error::byok-revoke: ${err instanceof Error ? err.message : String(err)}\n`);
  process.exit(1);
});
