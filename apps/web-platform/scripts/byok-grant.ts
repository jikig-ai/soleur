#!/usr/bin/env bun
// scripts/byok-grant.ts
// BYOK Delegations PR-A (#4232). Admin CLI to grant a byok_delegations
// row. Resolves emails to user IDs, derives the workspace, prints a
// confirmation summary, then calls the consolidated
// `grant_byok_delegation` RPC via the service-role client.
//
// SECURITY: this is a service-role tool. The interactive y/N prompt is
// a v3 hardening (SS F5 — typo at single-user threshold IS the
// incident); `--yes` bypasses it for CI / discoverability tests.
//
// Usage:
//   doppler run -p soleur -c dev -- bun run byok-grant -- \
//     --actor jean@jikigai.com \
//     --grantor jean@jikigai.com --to harry@jikigai.com \
//     --workspace auto --cap-cents 2000 --hourly-cap-cents 500 \
//     [--expires-in 30d] [--yes]
//
// On success: prints JSON `{ delegation_id: "<uuid>" }` to stdout and
// the full resolution chain to stderr (forensic surface).

import { createInterface } from "node:readline/promises";
import { createServiceClient } from "@/lib/supabase/service";
import { getDefaultWorkspaceForUser } from "@/server/workspace-resolver";
import { createChildLogger } from "@/server/logger";

const log = createChildLogger("byok-grant");

interface ParsedArgs {
  actor: string;
  grantor: string;
  to: string;
  workspace: string;
  capCents: number;
  hourlyCapCents: number;
  expiresIn?: string;
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
  const capCents = Number(required("--cap-cents"));
  const hourlyCapCents = Number(required("--hourly-cap-cents"));
  if (!Number.isInteger(capCents) || capCents < 1 || capCents > 1_000_000) {
    process.stderr.write(`::error::--cap-cents must be integer in [1, 1000000]; got ${capCents}\n`);
    process.exit(2);
  }
  if (!Number.isInteger(hourlyCapCents) || hourlyCapCents < 1 || hourlyCapCents > capCents) {
    process.stderr.write(`::error::--hourly-cap-cents must be integer in [1, ${capCents}]; got ${hourlyCapCents}\n`);
    process.exit(2);
  }
  return {
    actor: required("--actor"),
    grantor: required("--grantor"),
    to: required("--to"),
    workspace: required("--workspace"),
    capCents,
    hourlyCapCents,
    expiresIn: get("--expires-in"),
    yes: argv.includes("--yes"),
  };
}

function parseExpiresIn(raw: string | undefined): string | null {
  if (!raw) return null;
  const m = raw.match(/^(\d+)([dhm])$/);
  if (!m) {
    process.stderr.write(`::error::--expires-in must match /\\d+[dhm]/; got "${raw}"\n`);
    process.exit(2);
  }
  const n = Number(m[1]);
  const unitMs = m[2] === "d" ? 86_400_000 : m[2] === "h" ? 3_600_000 : 60_000;
  return new Date(Date.now() + n * unitMs).toISOString();
}

// Look up users via auth.admin.listUsers. Dogfood scale (<100 users)
// makes single-page enumeration fine; tracked as a follow-up if the
// allowlist ever grows past one page.
async function resolveEmailsToUserIds(
  supabase: ReturnType<typeof createServiceClient>,
  emails: string[],
): Promise<Record<string, string>> {
  const want = new Set(emails.map((e) => e.toLowerCase()));
  const found: Record<string, string> = {};
  let page = 1;
  while (page < 50) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw new Error(`auth.admin.listUsers page ${page} failed: ${error.message}`);
    if (!data.users.length) break;
    for (const u of data.users) {
      const e = u.email?.toLowerCase();
      if (e && want.has(e)) found[e] = u.id;
    }
    if (data.users.length < 200) break;
    page += 1;
  }
  const missing = [...want].filter((e) => !(e in found));
  if (missing.length) {
    throw new Error(`unknown emails: ${missing.join(", ")}`);
  }
  return found;
}

async function confirm(summary: string): Promise<boolean> {
  process.stderr.write(summary + "\n");
  const rl = createInterface({ input: process.stdin, output: process.stderr });
  try {
    const answer = (await rl.question("Confirm? [y/N]: ")).trim().toLowerCase();
    return answer === "y" || answer === "yes";
  } finally {
    rl.close();
  }
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const supabase = createServiceClient();

  const emails = await resolveEmailsToUserIds(supabase, [args.actor, args.grantor, args.to]);
  const actorId = emails[args.actor.toLowerCase()]!;
  const grantorId = emails[args.grantor.toLowerCase()]!;
  const granteeId = emails[args.to.toLowerCase()]!;

  let workspaceId: string;
  if (args.workspace === "auto") {
    workspaceId = await getDefaultWorkspaceForUser(grantorId, supabase);
  } else {
    workspaceId = args.workspace;
  }

  const expiresAt = parseExpiresIn(args.expiresIn);

  const dailyDollars = (args.capCents / 100).toFixed(2);
  const hourlyDollars = (args.hourlyCapCents / 100).toFixed(2);
  const summary = [
    "Granting:",
    `  grantor:    ${args.grantor} (${grantorId})`,
    `  grantee:    ${args.to} (${granteeId})`,
    `  workspace:  ${workspaceId}`,
    `  daily cap:  $${dailyDollars}/day`,
    `  hourly cap: $${hourlyDollars}/hr`,
    `  expires:    ${expiresAt ?? "never"}`,
    `  actor:      ${args.actor} (${actorId})`,
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
    { actorId, grantorId, granteeId, workspaceId, capCents: args.capCents, hourlyCapCents: args.hourlyCapCents, expiresAt },
    "byok-grant: invoking grant_byok_delegation",
  );

  const { data, error } = await supabase.rpc("grant_byok_delegation", {
    p_grantor_user_id: grantorId,
    p_grantee_user_id: granteeId,
    p_workspace_id: workspaceId,
    p_daily_usd_cap_cents: args.capCents,
    p_hourly_usd_cap_cents: args.hourlyCapCents,
    p_expires_at: expiresAt,
    p_actor_user_id: actorId,
  });

  if (error) {
    process.stderr.write(`::error::grant_byok_delegation failed: ${error.message}\n`);
    process.exit(1);
  }

  // RPC returns the new row's uuid as data.
  process.stdout.write(JSON.stringify({ delegation_id: data }) + "\n");
}

main().catch((err) => {
  process.stderr.write(`::error::byok-grant: ${err instanceof Error ? err.message : String(err)}\n`);
  process.exit(1);
});
