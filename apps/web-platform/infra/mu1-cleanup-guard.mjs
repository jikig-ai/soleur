// MU1 post-crash cleanup guard + sweep (#2839).
//
// The dev Supabase project ref is stable infra state. If it ever changes,
// update DEV_PROJECT_REF here AND the SYNTH allowlist regex in
// test/mu1-integration.test.ts in the same commit — they are coupled.
const DEV_PROJECT_REF = "ifsccnjhymdmidffkzhl";
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
    await c.auth.admin.deleteUser(u.id);
  }
  console.log(`cleanup complete: ${synth.length} synthetic user(s) deleted`);
}
