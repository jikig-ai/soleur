// MU1 post-crash cleanup guard + sweep (#2839).
//
// The dev Supabase project ref is stable infra state. If it ever changes,
// also update `DEV_URL` and the `subdomain bypass` / `prefix-match bypass`
// `run_case` fixtures in `infra/mu1-runbook-cleanup.test.sh` in the same
// commit (grep `mu1-runbook-cleanup.test.sh` for the run_case names).
// The `SYNTH_EMAIL_RE` regex in `test/mu1-integration.test.ts` is
// email-shaped (not project-ref shaped) and does NOT need to track this
// constant.
const DEV_PROJECT_REF = "mlwiodleouzwniehynfz";
const DEV_HOSTNAME = `${DEV_PROJECT_REF}.supabase.co`;

export function assertDevCleanupEnv(env = process.env) {
  if (env.DOPPLER_CONFIG !== "dev") {
    throw new Error(
      "Refusing to run cleanup: DOPPLER_CONFIG is not 'dev' (got: " +
        (env.DOPPLER_CONFIG || "<unset>") +
        ")",
    );
  }
  const url = env.NEXT_PUBLIC_SUPABASE_URL || "";
  let actualHostname = "";
  try {
    actualHostname = new URL(url).hostname;
  } catch {
    // Malformed / empty URL → fall through to the hostname branch with
    // actualHostname="" so the thrown message stays actionable.
  }
  // Exact-hostname equality, not prefix-split. A prefix split would accept
  // `<ref>.supabase.co.attacker.example` because split(".")[0] returns the
  // label regardless of trailing domain — which is a credential-exfiltration
  // vector if NEXT_PUBLIC_SUPABASE_URL is ever operator-attacker-influenced.
  if (actualHostname !== DEV_HOSTNAME) {
    throw new Error(
      "Refusing to run cleanup: Supabase hostname '" +
        actualHostname +
        "' != expected dev hostname '" +
        DEV_HOSTNAME +
        "' (url=" +
        url +
        ")",
    );
  }
}

// FK-reverse anonymise sequence — must run BEFORE raw auth.admin.deleteUser
// so the cascade doesn't hit a RESTRICT FK from one of the public.* PII
// tables (mig 053 workspace_members, 048 scope_grants, 051 action_sends,
// 053b template_authorizations, 044 tc_acceptances, 058 workspace_member_
// attestations, 062 workspace_member_removals, 063 workspace_member_
// actions). Pre-#4356, raw deleteUser worked because handle_new_user (mig
// 053) hadn't yet created the workspace_members row; post-053 the cascade
// is blocked without the anonymise step. organizations.owner_user_id +
// audit_byok_use.founder_id are handled by mig 065 SET NULL cascade.
//
// Mirrors test/helpers/tenant-isolation-teardown.ts; this script is the
// production-shaped equivalent for the MU1 integration test sweep.
const ANONYMISE_RPCS = [
  "anonymise_action_sends",
  "anonymise_template_authorizations",
  "anonymise_scope_grants",
  "anonymise_tc_acceptances",
  "anonymise_workspace_member_attestations",
  "anonymise_workspace_member_removals",
  "anonymise_workspace_members",
  "anonymise_workspace_member_actions",
];

export async function sweep() {
  const { createClient } = await import("@supabase/supabase-js");
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const c = createClient(url, key);
  const SYNTH =
    /^mu1-integration-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}@soleur-test\.invalid$/i;
  const { data } = await c.auth.admin.listUsers({ perPage: 200 });
  const synth = (data?.users ?? []).filter((u) => SYNTH.test(u.email || ""));
  for (const u of synth) {
    console.log("deleting", u.email);
    for (const rpc of ANONYMISE_RPCS) {
      const { error } = await c.rpc(rpc, { p_user_id: u.id });
      if (error) {
        // Best-effort; surface for visibility but don't abort the sweep —
        // a stuck cascade row from a half-broken prior run shouldn't block
        // every subsequent cleanup.
        console.warn(
          `mu1-cleanup-guard: ${rpc} for ${u.email} returned ` +
            `code=${error.code ?? "?"} message=${error.message}`,
        );
      }
    }
    const { error: delErr } = await c.auth.admin.deleteUser(u.id);
    if (delErr && !/not found/i.test(delErr.message)) {
      console.warn(
        `mu1-cleanup-guard: deleteUser(${u.email}) failed: ${delErr.message}`,
      );
    }
  }
  console.log(`cleanup complete: ${synth.length} synthetic user(s) deleted`);
}
