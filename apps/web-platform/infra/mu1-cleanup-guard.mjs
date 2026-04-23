// MU1 post-crash cleanup guard + sweep (#2839).
//
// The dev Supabase project ref is stable infra state. If it ever changes,
// update DEV_PROJECT_REF here AND the SYNTH allowlist regex in
// test/mu1-integration.test.ts in the same commit — they are coupled.
const DEV_PROJECT_REF = "ifsccnjhymdmidffkzhl";

export function assertDevCleanupEnv(env = process.env) {
  if (env.DOPPLER_CONFIG !== "dev") {
    throw new Error(
      "Refusing to run cleanup: DOPPLER_CONFIG is not 'dev' (got: " +
        (env.DOPPLER_CONFIG || "<unset>") +
        ")",
    );
  }
  const url = env.NEXT_PUBLIC_SUPABASE_URL || "";
  let actualRef = "";
  try {
    actualRef = new URL(url).hostname.split(".")[0];
  } catch {
    // Malformed / empty URL → fall through to the project-ref branch with
    // actualRef="" so the thrown message stays actionable.
  }
  if (actualRef !== DEV_PROJECT_REF) {
    throw new Error(
      "Refusing to run cleanup: Supabase project ref '" +
        actualRef +
        "' != expected dev ref '" +
        DEV_PROJECT_REF +
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
