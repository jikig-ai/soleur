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
//     --jti <uuid> --founder-id <uuid> --reason "<text>" [--revoke-session] [--yes]
//
//   doppler run -p soleur -c prd_runtime -- bun run apps/web-platform/scripts/revoke-jti.ts \
//     --jti <uuid> --founder-id <uuid> --reason "<text>" [--revoke-session] [--yes]
//
// Print the resolved Supabase URL BEFORE the write — operator dev/prd
// visibility per hr-dev-prd-distinct-supabase-projects.
//
// SCOPE: Default behavior revokes a specific JTI (one JWT instance), NOT
// the underlying Supabase auth session. A founder whose magiclink session
// is still valid can re-mint a fresh JWT with a new jti and resume
// access. Pass `--revoke-session` to ALSO kill the underlying Supabase
// session in the same operator action — combining the JTI deny-list
// write with `service.auth.admin.signOut(userId, { scope: 'global' })`.
//
// The session-revoke is invoked AFTER the revoke_jti RPC + re-read
// sanity check succeed; a failure of the auth.admin.signOut surfaces
// as a separate `::error::` line and exit code 1 — the JTI is already
// on the deny-list (the audit artifact has landed) so the operator
// can retry the session-revoke step idempotently without re-running
// revoke_jti.

import { createInterface } from "node:readline/promises";
import { createServiceClient } from "@/lib/supabase/service";
import { createChildLogger } from "@/server/logger";

const log = createChildLogger("revoke-jti");

interface ParsedArgs {
  jti: string;
  founderId: string;
  reason: string;
  yes: boolean;
  // #4440 follow-up to #4418 — pair the JTI deny-list write with a
  // Supabase auth.admin.signOut(scope:'global') so the founder cannot
  // re-mint a fresh JWT from a still-valid magiclink session. Default
  // false preserves the original JTI-only semantic; opt-in flag keeps
  // the lower-blast-radius default for the common "rotate one stolen
  // JWT" operator workflow.
  revokeSession: boolean;
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
    revokeSession: argv.includes("--revoke-session"),
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

  // UUID-shape gate before any DB write — RPC body's UUID-cast would
  // otherwise emit 22P02 invalid_text_representation.
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
  // dev/prd visibility per hr-dev-prd-distinct-supabase-projects — stdout
  // (not stderr) so the agent runtime captures it.
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

  // #4440 follow-up to #4418 — optional Supabase session termination.
  // The denied_jti.founder_id column IS the auth.users.id (FK
  // documented in migration 037), so args.founderId can be passed
  // directly to auth.admin.signOut.
  //
  // scope: 'global' kills every refresh token bound to the user across
  // every device — the strongest invalidation Supabase exposes. A
  // partial 'local' or 'others' is intentionally NOT offered here: the
  // operator who invoked --revoke-session has already decided the
  // session is compromised, and a half-revoked session is the worst
  // outcome (founder thinks they're logged out but a stale browser tab
  // keeps minting).
  //
  // Idempotency: the JTI deny-list row above is the audit artifact and
  // it has already landed by this point. A signOut failure here is
  // operator-retryable without re-running revoke_jti.
  if (args.revokeSession) {
    log.info(
      { founderId: args.founderId },
      "revoke-jti: invoking GoTrue admin user-logout (scope=global)",
    );
    // The supabase-js admin.signOut(jwt) API takes a JWT, not a user id.
    // For user-id-keyed session termination we call the GoTrue admin
    // REST endpoint directly: POST /auth/v1/admin/users/{user_id}/logout
    // with the service-role bearer. `scope=global` invalidates every
    // refresh token bound to the user across every device.
    const supabaseUrl = process.env.SUPABASE_URL;
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!supabaseUrl || !serviceRoleKey) {
      process.stderr.write(
        "::error::SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY unset; cannot call admin signOut\n",
      );
      process.exit(1);
    }
    const logoutUrl = `${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(args.founderId)}/logout`;
    const res = await fetch(logoutUrl, {
      method: "POST",
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ scope: "global" }),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "<unreadable>");
      process.stderr.write(
        `::error::admin signOut failed: ${res.status} ${res.statusText} body=${body}\n`,
      );
      process.exit(1);
    }
    process.stdout.write(
      `session_revoke_success: founder=${args.founderId} scope=global\n`,
    );
  }
}

main().catch((err) => {
  process.stderr.write(`::error::revoke-jti: ${err instanceof Error ? err.message : String(err)}\n`);
  process.exit(1);
});
